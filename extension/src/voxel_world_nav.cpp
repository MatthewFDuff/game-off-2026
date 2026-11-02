// Floor detection and flow fields for enemy navigation. See the nav members in voxel_world.h.
//
// A "span" is a walkable floor in a column: a height where the voxel layer below is at least half
// solid and there is enough headroom above. Spans whose headroom is blocked only by soft voxels
// (planks, dirt) are "breach" spans: walkable, but only by digging through, so they cost extra.
// The flow field is a Dijkstra search outward from the span under the target, giving every
// reachable span its cost to walk there. Agents step to whichever neighbor span is cheapest.

#include "voxel_world.h"

#include <godot_cpp/classes/time.hpp>

#include <algorithm>
#include <climits>
#include <cmath>
#include <functional>
#include <queue>

using namespace godot;
using namespace voxel;

namespace {

// A column layer counts as floor when at least this many of its 16 voxels are solid...
constexpr int SUPPORT_MIN = 8;
// ...and as open air when at most this many are (a little rubble doesn't block anything).
constexpr int CLEAR_MAX = 3;
constexpr uint32_t UNREACHED = UINT32_MAX;
constexpr int STRAIGHT_COST = 10;
constexpr int DIAGONAL_COST = 14;

const int DIRECTIONS[8][2] = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } };

} // namespace

void VoxelWorld::nav_allocate() {
	nav_columns_x = size_in_chunks.x * CHUNK_SIZE / NAV_COLUMN;
	nav_columns_z = size_in_chunks.z * CHUNK_SIZE / NAV_COLUMN;
	nav_height = size_in_chunks.y * CHUNK_SIZE;
	const size_t columns = size_t(nav_columns_x) * nav_columns_z;
	nav_solid.assign(columns * nav_height, 0);
	nav_hard.assign(columns * nav_height, 0);
	nav_column_dirty.assign(columns, 1);
	nav_span_height.assign(columns * NAV_MAX_SPANS, 0);
	nav_span_breach.assign(columns * NAV_MAX_SPANS, 0);
	nav_span_count.assign(columns, 0);
	nav_flow.assign(columns * NAV_MAX_SPANS, UNREACHED);
	nav_flow_target = -1;
}

void VoxelWorld::nav_rebuild_chunk(int slot) {
	const Chunk &c = chunks[slot];
	const int cx = slot % size_in_chunks.x;
	const int cz = (slot / size_in_chunks.x) % size_in_chunks.z;
	const int cy = slot / (size_in_chunks.x * size_in_chunks.z);
	constexpr int COLUMNS_PER_CHUNK = CHUNK_SIZE / NAV_COLUMN;

	for (int lz = 0; lz < COLUMNS_PER_CHUNK; lz++) {
		for (int lx = 0; lx < COLUMNS_PER_CHUNK; lx++) {
			const int column = (cz * COLUMNS_PER_CHUNK + lz) * nav_columns_x + (cx * COLUMNS_PER_CHUNK + lx);
			for (int ly = 0; ly < CHUNK_SIZE; ly++) {
				int solid = 0;
				int hard = 0;
				if (c.data.empty()) {
					solid = c.uniform_value != 0 ? NAV_COLUMN_AREA : 0;
					hard = nav_is_hard(c.uniform_value) ? NAV_COLUMN_AREA : 0;
				} else {
					for (int j = 0; j < NAV_COLUMN; j++) {
						for (int i = 0; i < NAV_COLUMN; i++) {
							const uint8_t m = c.data[chunk_index(lx * NAV_COLUMN + i, ly, lz * NAV_COLUMN + j)];
							solid += m != 0 ? 1 : 0;
							hard += nav_is_hard(m) ? 1 : 0;
						}
					}
				}
				const int i = column * nav_height + cy * CHUNK_SIZE + ly;
				nav_solid[i] = uint8_t(solid);
				nav_hard[i] = uint8_t(hard);
			}
			nav_column_dirty[column] = 1;
		}
	}
}

void VoxelWorld::nav_rebuild_spans(int column) {
	const uint8_t *solid = &nav_solid[size_t(column) * nav_height];
	const uint8_t *hard = &nav_hard[size_t(column) * nav_height];
	int16_t *heights = &nav_span_height[size_t(column) * NAV_MAX_SPANS];
	uint8_t *breach = &nav_span_breach[size_t(column) * NAV_MAX_SPANS];
	int count = 0;

	for (int y = 1; y < nav_height; y++) {
		if (solid[y - 1] < SUPPORT_MIN) {
			continue;
		}
		bool blocked = false;
		bool soft = false;
		for (int k = 0; k < nav_clearance && !blocked; k++) {
			const int yy = y + k;
			if (yy >= nav_height) {
				blocked = out_of_bounds_solid;
				break;
			}
			blocked = hard[yy] > CLEAR_MAX;
			soft = soft || solid[yy] > CLEAR_MAX;
		}
		if (blocked) {
			continue;
		}
		// Floors a step apart are the same floor (rubble, sandbags). Keep one, preferring open ones.
		if (count > 0 && y - heights[count - 1] <= nav_step) {
			if (breach[count - 1] && !soft) {
				heights[count - 1] = int16_t(y);
				breach[count - 1] = 0;
			}
			continue;
		}
		if (count == NAV_MAX_SPANS) {
			break;
		}
		heights[count] = int16_t(y);
		breach[count] = soft ? 1 : 0;
		count++;
	}
	nav_span_count[column] = uint8_t(count);
}

int VoxelWorld::nav_find_span(int column, int y) const {
	int best = -1;
	for (int k = 0; k < nav_span_count[column]; k++) {
		const int h = nav_span_height[size_t(column) * NAV_MAX_SPANS + k];
		if (h <= y + nav_step) {
			best = k; // Spans are sorted bottom-up, so the last match is the highest below the feet.
		}
	}
	return best;
}

bool VoxelWorld::nav_has_span_near(int column, int height, int tolerance) const {
	for (int k = 0; k < nav_span_count[column]; k++) {
		if (std::abs(nav_span_height[size_t(column) * NAV_MAX_SPANS + k] - height) <= tolerance) {
			return true;
		}
	}
	return false;
}

uint32_t VoxelWorld::nav_move_cost(int cu, int ku, int cv, int kv, int dx, int dz) const {
	const int hu = nav_span_height[size_t(cu) * NAV_MAX_SPANS + ku];
	const int hv = nav_span_height[size_t(cv) * NAV_MAX_SPANS + kv];
	if (hv - hu > nav_step || hu - hv > nav_max_drop) {
		return 0;
	}
	uint32_t cost = STRAIGHT_COST;
	if (dx != 0 && dz != 0) {
		// No cutting corners: both columns beside the diagonal must be walkable at this height.
		const int ca = cu + dx;
		const int cb = cu + dz * nav_columns_x;
		const bool a_open = nav_has_span_near(ca, hu, nav_step) || nav_has_span_near(ca, hv, nav_step);
		const bool b_open = nav_has_span_near(cb, hu, nav_step) || nav_has_span_near(cb, hv, nav_step);
		if (!a_open || !b_open) {
			return 0;
		}
		cost = DIAGONAL_COST;
	}
	if (nav_span_breach[size_t(cv) * NAV_MAX_SPANS + kv]) {
		cost += uint32_t(nav_breach_cost);
	}
	return cost;
}

Vector3 VoxelWorld::nav_span_world(int column, int k) const {
	const Vector3 origin = is_inside_tree() ? get_global_position() : get_position();
	const int cx = column % nav_columns_x;
	const int cz = column / nav_columns_x;
	const float half = NAV_COLUMN * 0.5f;
	return origin + Vector3(cx * NAV_COLUMN + half, nav_span_height[size_t(column) * NAV_MAX_SPANS + k], cz * NAV_COLUMN + half) * voxel_size;
}

void VoxelWorld::update_flow_field(const Vector3 &target, float max_distance) {
	const uint64_t start = Time::get_singleton()->get_ticks_usec();

	if (nav_hardness_stale) {
		for (int slot = 0; slot < int(chunks.size()); slot++) {
			nav_rebuild_chunk(slot);
		}
		nav_hardness_stale = false;
	}
	const int columns = nav_columns_x * nav_columns_z;
	for (int column = 0; column < columns; column++) {
		if (nav_column_dirty[column]) {
			nav_rebuild_spans(column);
			nav_column_dirty[column] = 0;
		}
	}

	std::fill(nav_flow.begin(), nav_flow.end(), UNREACHED);
	nav_flow_target = -1;
	last_flow_reached = 0;

	// Start from the floor under the target, looking a couple of columns out if it is mid-air.
	const Vector3 p = to_voxel_space(target);
	const int tx = int(std::floor(p.x / NAV_COLUMN));
	const int tz = int(std::floor(p.z / NAV_COLUMN));
	const int ty = int(std::floor(p.y + 0.05f));
	for (int radius = 0; radius <= 2 && nav_flow_target < 0; radius++) {
		for (int dz = -radius; dz <= radius && nav_flow_target < 0; dz++) {
			for (int dx = -radius; dx <= radius && nav_flow_target < 0; dx++) {
				const int cx = tx + dx, cz = tz + dz;
				if (cx < 0 || cz < 0 || cx >= nav_columns_x || cz >= nav_columns_z) {
					continue;
				}
				const int k = nav_find_span(cz * nav_columns_x + cx, ty);
				if (k >= 0) {
					nav_flow_target = (cz * nav_columns_x + cx) * NAV_MAX_SPANS + k;
				}
			}
		}
	}

	if (nav_flow_target >= 0) {
		const uint32_t max_cost = uint32_t(max_distance / (NAV_COLUMN * voxel_size) * STRAIGHT_COST);
		using Entry = std::pair<uint32_t, int>;
		std::priority_queue<Entry, std::vector<Entry>, std::greater<Entry>> open;
		nav_flow[nav_flow_target] = 0;
		open.push({ 0, nav_flow_target });

		while (!open.empty()) {
			const auto [cost, node] = open.top();
			open.pop();
			if (cost > nav_flow[node]) {
				continue;
			}
			last_flow_reached++;
			const int cv = node / NAV_MAX_SPANS;
			const int kv = node % NAV_MAX_SPANS;
			const int vx = cv % nav_columns_x;
			const int vz = cv / nav_columns_x;
			for (const auto &d : DIRECTIONS) {
				const int ux = vx + d[0], uz = vz + d[1];
				if (ux < 0 || uz < 0 || ux >= nav_columns_x || uz >= nav_columns_z) {
					continue;
				}
				const int cu = uz * nav_columns_x + ux;
				for (int ku = 0; ku < nav_span_count[cu]; ku++) {
					// Agents walk from u toward v, the opposite of the direction we search in.
					const uint32_t step = nav_move_cost(cu, ku, cv, kv, -d[0], -d[1]);
					if (step == 0) {
						continue;
					}
					const uint32_t total = cost + step;
					const int u = cu * NAV_MAX_SPANS + ku;
					if (total <= max_cost && total < nav_flow[u]) {
						nav_flow[u] = total;
						open.push({ total, u });
					}
				}
			}
		}
	}

	last_flow_usec = double(Time::get_singleton()->get_ticks_usec() - start);
}

Dictionary VoxelWorld::get_flow(const Vector3 &feet) const {
	Dictionary result;
	result["valid"] = false;
	if (nav_flow_target < 0) {
		return result;
	}
	const Vector3 p = to_voxel_space(feet);
	const int x = int(std::floor(p.x / NAV_COLUMN));
	const int z = int(std::floor(p.z / NAV_COLUMN));
	if (x < 0 || z < 0 || x >= nav_columns_x || z >= nav_columns_z) {
		return result;
	}
	const int column = z * nav_columns_x + x;
	const int k = nav_find_span(column, int(std::floor(p.y + 0.05f)));
	if (k < 0) {
		return result;
	}
	const int node = column * NAV_MAX_SPANS + k;
	if (nav_flow[node] == UNREACHED) {
		return result;
	}

	result["distance"] = float(nav_flow[node]) / STRAIGHT_COST * NAV_COLUMN * voxel_size;
	if (node == nav_flow_target) {
		result["valid"] = true;
		result["at_target"] = true;
		result["breach"] = false;
		result["next"] = nav_span_world(column, k);
		return result;
	}

	uint32_t best_total = UNREACHED;
	int best_column = -1;
	int best_k = -1;
	for (const auto &d : DIRECTIONS) {
		const int nx = x + d[0], nz = z + d[1];
		if (nx < 0 || nz < 0 || nx >= nav_columns_x || nz >= nav_columns_z) {
			continue;
		}
		const int cv = nz * nav_columns_x + nx;
		for (int kv = 0; kv < nav_span_count[cv]; kv++) {
			const uint32_t flow = nav_flow[cv * NAV_MAX_SPANS + kv];
			if (flow == UNREACHED) {
				continue;
			}
			const uint32_t step = nav_move_cost(column, k, cv, kv, d[0], d[1]);
			if (step != 0 && step + flow < best_total) {
				best_total = step + flow;
				best_column = cv;
				best_k = kv;
			}
		}
	}
	if (best_column < 0) {
		return result;
	}
	result["valid"] = true;
	result["at_target"] = false;
	result["breach"] = nav_span_breach[size_t(best_column) * NAV_MAX_SPANS + best_k] != 0;
	result["next"] = nav_span_world(best_column, best_k);
	return result;
}
