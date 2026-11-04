#include "voxel_world.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <unordered_set>

using namespace godot;
using namespace voxel;

namespace {

// Keeps boxes that rest exactly on a voxel face from counting as overlapping it.
constexpr double SWEEP_EPSILON = 1e-4;

inline int floor_to_int(double v) {
	return int(std::floor(v));
}

template <typename T>
PackedVector3Array to_packed_vector3(const std::vector<T> &src) {
	PackedVector3Array dst;
	dst.resize(int64_t(src.size()));
	std::memcpy(dst.ptrw(), src.data(), src.size() * sizeof(Vector3));
	return dst;
}

} // namespace

VoxelWorld::VoxelWorld() {
	padded.resize(PADDED_VOLUME);
	allocate();
}

VoxelWorld::~VoxelWorld() {
}

void VoxelWorld::allocate() {
	free_meshes();
	chunks.clear();
	chunks.resize(size_t(size_in_chunks.x) * size_in_chunks.y * size_in_chunks.z);
	dirty_queue.clear();
	nav_allocate();
}

void VoxelWorld::free_meshes() {
	for (Chunk &c : chunks) {
		if (c.mesh_instance != nullptr) {
			c.mesh_instance->queue_free();
			c.mesh_instance = nullptr;
		}
		c.triangle_count = 0;
	}
}

void VoxelWorld::_ready() {
	set_process(!Engine::get_singleton()->is_editor_hint());
}

void VoxelWorld::_process(double delta) {
	if (dirty_queue.empty()) {
		return;
	}
	dirty_queue.erase(std::remove_if(dirty_queue.begin(), dirty_queue.end(), [this](int slot) { return !chunks[slot].dirty; }), dirty_queue.end());
	sort_by_camera_distance(dirty_queue);

	// Always build at least one chunk so a huge backlog still drains.
	Time *time = Time::get_singleton();
	const uint64_t start = time->get_ticks_usec();
	const uint64_t budget = uint64_t(remesh_budget_ms * 1000.0f);
	size_t built = 0;
	while (built < dirty_queue.size()) {
		build_chunk_mesh(dirty_queue[built]);
		built++;
		if (time->get_ticks_usec() - start >= budget) {
			break;
		}
	}
	dirty_queue.erase(dirty_queue.begin(), dirty_queue.begin() + int64_t(built));
}

// --- Properties -------------------------------------------------------------------------------

void VoxelWorld::set_size_in_chunks(const Vector3i &value) {
	size_in_chunks = Vector3i(MAX(1, value.x), MAX(1, value.y), MAX(1, value.z));
	allocate();
}

void VoxelWorld::set_voxel_size(float value) {
	voxel_size = MAX(0.001f, value);
	for (int slot = 0; slot < int(chunks.size()); slot++) {
		mark_dirty(slot);
	}
}

void VoxelWorld::set_material(const Ref<Material> &value) {
	material = value;
	for (Chunk &c : chunks) {
		if (c.mesh_instance != nullptr) {
			c.mesh_instance->set_material_override(material);
		}
	}
}

int VoxelWorld::hardness_of(uint8_t material_id) const {
	if (material_id == BOUNDARY_MATERIAL) {
		return 255;
	}
	if (material_id < material_hardness.size()) {
		return material_hardness[material_id];
	}
	return 1;
}

// --- Coordinates ------------------------------------------------------------------------------

Vector3 VoxelWorld::to_voxel_space(const Vector3 &world_position) const {
	const Vector3 origin = is_inside_tree() ? get_global_position() : get_position();
	return (world_position - origin) / voxel_size;
}

Vector3i VoxelWorld::world_to_voxel(const Vector3 &world_position) const {
	const Vector3 p = to_voxel_space(world_position);
	return Vector3i(floor_to_int(p.x), floor_to_int(p.y), floor_to_int(p.z));
}

Vector3 VoxelWorld::voxel_to_world(const Vector3i &voxel) const {
	const Vector3 origin = is_inside_tree() ? get_global_position() : get_position();
	return origin + (Vector3(voxel) + Vector3(0.5f, 0.5f, 0.5f)) * voxel_size;
}

// --- Storage ----------------------------------------------------------------------------------

void VoxelWorld::write(int x, int y, int z, uint8_t value) {
	Chunk &c = chunks[chunk_slot(x >> CHUNK_SHIFT, y >> CHUNK_SHIFT, z >> CHUNK_SHIFT)];
	const int index = chunk_index(x & CHUNK_MASK, y & CHUNK_MASK, z & CHUNK_MASK);
	uint8_t old_value;
	if (c.data.empty()) {
		old_value = c.uniform_value;
		if (old_value == value) {
			return;
		}
		c.data.assign(CHUNK_VOLUME, c.uniform_value);
	} else {
		old_value = c.data[index];
		if (old_value == value) {
			return;
		}
	}
	c.data[index] = value;
	nav_on_write(x, y, z, old_value, value);
}

void VoxelWorld::try_compress(Chunk &c) {
	if (c.data.empty()) {
		return;
	}
	const uint8_t first = c.data[0];
	for (int i = 1; i < CHUNK_VOLUME; i++) {
		if (c.data[i] != first) {
			return;
		}
	}
	c.uniform_value = first;
	std::vector<uint8_t>().swap(c.data);
}

int VoxelWorld::get_voxel(const Vector3i &voxel) const {
	return read(voxel.x, voxel.y, voxel.z);
}

void VoxelWorld::set_voxel(const Vector3i &voxel, int material_id) {
	if (!in_bounds(voxel.x, voxel.y, voxel.z)) {
		return;
	}
	const uint8_t value = uint8_t(CLAMP(material_id, 0, 254));
	if (read(voxel.x, voxel.y, voxel.z) == value) {
		return;
	}
	write(voxel.x, voxel.y, voxel.z, value);
	finish_edit(voxel, voxel);
}

void VoxelWorld::fill_all(int material_id) {
	const uint8_t value = uint8_t(CLAMP(material_id, 0, 254));
	for (int slot = 0; slot < int(chunks.size()); slot++) {
		std::vector<uint8_t>().swap(chunks[slot].data);
		chunks[slot].uniform_value = value;
		mark_dirty(slot);
		nav_rebuild_chunk(slot);
	}
	nav_hardness_stale = false; // Every chunk was just rebuilt with the current hardness.
	emit_signal("voxels_changed", Vector3i(), get_size_in_voxels() - Vector3i(1, 1, 1));
}

PackedByteArray VoxelWorld::get_data() const {
	size_t total = 16;
	for (const Chunk &c : chunks) {
		total += c.data.empty() ? 2 : 1 + CHUNK_VOLUME;
	}
	PackedByteArray out;
	out.resize(int64_t(total));
	uint8_t *w = out.ptrw();
	std::memcpy(w, "VXW1", 4);
	const int32_t dims[3] = { size_in_chunks.x, size_in_chunks.y, size_in_chunks.z };
	std::memcpy(w + 4, dims, sizeof(dims));
	size_t at = 16;
	for (const Chunk &c : chunks) {
		if (c.data.empty()) {
			w[at++] = 0;
			w[at++] = c.uniform_value;
		} else {
			w[at++] = 1;
			std::memcpy(w + at, c.data.data(), CHUNK_VOLUME);
			at += CHUNK_VOLUME;
		}
	}
	return out;
}

bool VoxelWorld::set_data(const PackedByteArray &data) {
	const int64_t size = data.size();
	const uint8_t *r = data.ptr();
	if (size < 16 || std::memcmp(r, "VXW1", 4) != 0) {
		return false;
	}
	int32_t dims[3];
	std::memcpy(dims, r + 4, sizeof(dims));
	if (dims[0] < 1 || dims[1] < 1 || dims[2] < 1) {
		return false;
	}
	// Validate the whole payload before touching the world.
	const int64_t count = int64_t(dims[0]) * dims[1] * dims[2];
	int64_t at = 16;
	for (int64_t i = 0; i < count; i++) {
		if (at >= size) {
			return false;
		}
		at += r[at] == 0 ? 2 : 1 + CHUNK_VOLUME;
	}
	if (at != size) {
		return false;
	}

	const Vector3i dims_v(dims[0], dims[1], dims[2]);
	if (dims_v != size_in_chunks) {
		size_in_chunks = dims_v;
		allocate();
	}
	at = 16;
	for (int slot = 0; slot < int(chunks.size()); slot++) {
		Chunk &c = chunks[slot];
		if (r[at] == 0) {
			std::vector<uint8_t>().swap(c.data);
			c.uniform_value = r[at + 1];
			at += 2;
		} else {
			c.data.assign(r + at + 1, r + at + 1 + CHUNK_VOLUME);
			at += 1 + CHUNK_VOLUME;
			try_compress(c);
		}
		mark_dirty(slot);
		nav_rebuild_chunk(slot);
	}
	nav_hardness_stale = false;
	nav_flow_target = -1;
	emit_signal("voxels_changed", Vector3i(), get_size_in_voxels() - Vector3i(1, 1, 1));
	return true;
}

int VoxelWorld::fill_box(const Vector3i &from, const Vector3i &to, int material_id, bool only_air) {
	const uint8_t value = uint8_t(CLAMP(material_id, 0, 254));
	const Vector3i size = get_size_in_voxels();
	const Vector3i lo = Vector3i(MAX(from.x, 0), MAX(from.y, 0), MAX(from.z, 0));
	const Vector3i hi = Vector3i(MIN(to.x, size.x), MIN(to.y, size.y), MIN(to.z, size.z));
	if (lo.x >= hi.x || lo.y >= hi.y || lo.z >= hi.z) {
		return 0;
	}

	int changed = 0;
	for (int cy = lo.y >> CHUNK_SHIFT; cy <= (hi.y - 1) >> CHUNK_SHIFT; cy++) {
		for (int cz = lo.z >> CHUNK_SHIFT; cz <= (hi.z - 1) >> CHUNK_SHIFT; cz++) {
			for (int cx = lo.x >> CHUNK_SHIFT; cx <= (hi.x - 1) >> CHUNK_SHIFT; cx++) {
				Chunk &c = chunks[chunk_slot(cx, cy, cz)];
				const Vector3i c_lo = Vector3i(cx, cy, cz) * CHUNK_SIZE;
				const Vector3i c_hi = c_lo + Vector3i(CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE);
				const bool covers_chunk = lo.x <= c_lo.x && lo.y <= c_lo.y && lo.z <= c_lo.z &&
						hi.x >= c_hi.x && hi.y >= c_hi.y && hi.z >= c_hi.z;

				if (covers_chunk && !only_air) {
					if (!c.data.empty() || c.uniform_value != value) {
						std::vector<uint8_t>().swap(c.data);
						c.uniform_value = value;
						changed += CHUNK_VOLUME;
						nav_rebuild_chunk(chunk_slot(cx, cy, cz));
					}
					continue;
				}
				if (covers_chunk && c.data.empty() && c.uniform_value != 0) {
					continue; // only_air on a solid chunk: nothing to do.
				}

				const int x0 = MAX(lo.x, c_lo.x), x1 = MIN(hi.x, c_hi.x);
				const int y0 = MAX(lo.y, c_lo.y), y1 = MIN(hi.y, c_hi.y);
				const int z0 = MAX(lo.z, c_lo.z), z1 = MIN(hi.z, c_hi.z);
				for (int y = y0; y < y1; y++) {
					for (int z = z0; z < z1; z++) {
						for (int x = x0; x < x1; x++) {
							const uint8_t current = read(x, y, z);
							if (current == value || (only_air && current != 0)) {
								continue;
							}
							write(x, y, z, value);
							changed++;
						}
					}
				}
			}
		}
	}

	if (changed > 0) {
		finish_edit(lo, hi - Vector3i(1, 1, 1));
	}
	return changed;
}

int VoxelWorld::fill_sphere(const Vector3 &center, float radius, int material_id, bool only_air) {
	const uint8_t value = uint8_t(CLAMP(material_id, 0, 254));
	const Vector3 c = to_voxel_space(center);
	const double r = double(radius) / voxel_size;
	const double r2 = r * r;
	const Vector3i lo = Vector3i(floor_to_int(c.x - r), floor_to_int(c.y - r), floor_to_int(c.z - r));
	const Vector3i hi = Vector3i(floor_to_int(c.x + r), floor_to_int(c.y + r), floor_to_int(c.z + r));

	int changed = 0;
	for (int y = lo.y; y <= hi.y; y++) {
		for (int z = lo.z; z <= hi.z; z++) {
			for (int x = lo.x; x <= hi.x; x++) {
				const double dx = x + 0.5 - c.x, dy = y + 0.5 - c.y, dz = z + 0.5 - c.z;
				if (dx * dx + dy * dy + dz * dz > r2 || !in_bounds(x, y, z)) {
					continue;
				}
				const uint8_t current = read(x, y, z);
				if (current == value || (only_air && current != 0)) {
					continue;
				}
				write(x, y, z, value);
				changed++;
			}
		}
	}
	if (changed > 0) {
		finish_edit(lo, hi);
	}
	return changed;
}

Dictionary VoxelWorld::carve_sphere(const Vector3 &center, float radius, int max_hardness) {
	const Vector3 c = to_voxel_space(center);
	const double r = double(radius) / voxel_size;
	const double r2 = r * r;
	const Vector3i lo = Vector3i(floor_to_int(c.x - r), floor_to_int(c.y - r), floor_to_int(c.z - r));
	const Vector3i hi = Vector3i(floor_to_int(c.x + r), floor_to_int(c.y + r), floor_to_int(c.z + r));

	int removed[256] = {};
	std::vector<Vector3i> removed_voxels;
	for (int y = lo.y; y <= hi.y; y++) {
		for (int z = lo.z; z <= hi.z; z++) {
			for (int x = lo.x; x <= hi.x; x++) {
				const double dx = x + 0.5 - c.x, dy = y + 0.5 - c.y, dz = z + 0.5 - c.z;
				if (dx * dx + dy * dy + dz * dz > r2 || !in_bounds(x, y, z)) {
					continue;
				}
				const uint8_t current = read(x, y, z);
				if (current == 0 || current == BOUNDARY_MATERIAL || hardness_of(current) > max_hardness) {
					continue;
				}
				write(x, y, z, 0);
				removed[current]++;
				removed_voxels.push_back(Vector3i(x, y, z));
			}
		}
	}

	return finish_carve(removed, removed_voxels, lo, hi);
}

Dictionary VoxelWorld::carve_box(const AABB &box, int max_hardness) {
	const Vector3 a = to_voxel_space(box.position);
	const Vector3 b = to_voxel_space(box.position + box.size);
	// Voxels whose centers are inside the box.
	const Vector3i lo = Vector3i(int(std::ceil(a.x - 0.5f)), int(std::ceil(a.y - 0.5f)), int(std::ceil(a.z - 0.5f)));
	const Vector3i hi = Vector3i(floor_to_int(b.x - 0.5f), floor_to_int(b.y - 0.5f), floor_to_int(b.z - 0.5f));

	int removed[256] = {};
	std::vector<Vector3i> removed_voxels;
	for (int y = lo.y; y <= hi.y; y++) {
		for (int z = lo.z; z <= hi.z; z++) {
			for (int x = lo.x; x <= hi.x; x++) {
				if (!in_bounds(x, y, z)) {
					continue;
				}
				const uint8_t current = read(x, y, z);
				if (current == 0 || current == BOUNDARY_MATERIAL || hardness_of(current) > max_hardness) {
					continue;
				}
				write(x, y, z, 0);
				removed[current]++;
				removed_voxels.push_back(Vector3i(x, y, z));
			}
		}
	}
	return finish_carve(removed, removed_voxels, lo, hi);
}

Dictionary VoxelWorld::finish_carve(const int removed[256], const std::vector<Vector3i> &removed_voxels, const Vector3i &from, const Vector3i &to) {
	Dictionary result;
	if (removed_voxels.empty()) {
		return result;
	}
	for (int m = 1; m < 256; m++) {
		if (removed[m] > 0) {
			result[m] = removed[m];
		}
	}
	Vector3i edit_from = from;
	Vector3i edit_to = to;
	if (detach_floating) {
		detach_fragments(removed_voxels, edit_from, edit_to);
	}
	finish_edit(edit_from, edit_to);
	return result;
}

Dictionary VoxelWorld::set_voxels(const PackedInt32Array &points, const PackedByteArray &materials) {
	Dictionary result;
	ERR_FAIL_COND_V_MSG(points.size() != materials.size() * 3, result, "set_voxels: points must hold x, y, z for each material.");
	int removed[256] = {};
	std::vector<Vector3i> removed_voxels;
	std::vector<Vector3i> changed;
	for (int64_t i = 0; i < materials.size(); i++) {
		const Vector3i p(points[i * 3], points[i * 3 + 1], points[i * 3 + 2]);
		if (!in_bounds(p.x, p.y, p.z)) {
			continue;
		}
		const uint8_t value = uint8_t(CLAMP(int(materials[i]), 0, 254));
		const uint8_t current = read(p.x, p.y, p.z);
		if (current == value || current == BOUNDARY_MATERIAL) {
			continue;
		}
		write(p.x, p.y, p.z, value);
		changed.push_back(p);
		if (value == 0) {
			removed[current]++;
			removed_voxels.push_back(p);
		}
	}
	if (changed.empty()) {
		return result;
	}
	for (int m = 1; m < 256; m++) {
		if (removed[m] > 0) {
			result[m] = removed[m];
		}
	}

	Vector3i lo = changed[0];
	Vector3i hi = changed[0];
	for (const Vector3i &p : changed) {
		lo = lo.min(p);
		hi = hi.max(p);
	}
	// Loose pieces: detach_fragments grows a box around whatever it removes.
	const Vector3i none_lo(INT32_MAX, INT32_MAX, INT32_MAX);
	const Vector3i none_hi(INT32_MIN, INT32_MIN, INT32_MIN);
	Vector3i fragment_lo = none_lo;
	Vector3i fragment_hi = none_hi;
	if (detach_floating && !removed_voxels.empty()) {
		detach_fragments(removed_voxels, fragment_lo, fragment_hi);
	}

	// The chunks each point's mesh faces can reach (one voxel out), not the whole bounding box: a
	// fire's points are scattered across the level.
	std::unordered_set<int> seen;
	std::vector<int> touched;
	auto touch_range = [&](const Vector3i &from, const Vector3i &to) {
		const int cx0 = CLAMP((from.x - 1) >> CHUNK_SHIFT, 0, size_in_chunks.x - 1);
		const int cy0 = CLAMP((from.y - 1) >> CHUNK_SHIFT, 0, size_in_chunks.y - 1);
		const int cz0 = CLAMP((from.z - 1) >> CHUNK_SHIFT, 0, size_in_chunks.z - 1);
		const int cx1 = CLAMP((to.x + 1) >> CHUNK_SHIFT, 0, size_in_chunks.x - 1);
		const int cy1 = CLAMP((to.y + 1) >> CHUNK_SHIFT, 0, size_in_chunks.y - 1);
		const int cz1 = CLAMP((to.z + 1) >> CHUNK_SHIFT, 0, size_in_chunks.z - 1);
		for (int cy = cy0; cy <= cy1; cy++) {
			for (int cz = cz0; cz <= cz1; cz++) {
				for (int cx = cx0; cx <= cx1; cx++) {
					const int slot = chunk_slot(cx, cy, cz);
					if (seen.insert(slot).second) {
						touched.push_back(slot);
					}
				}
			}
		}
	};
	for (const Vector3i &p : changed) {
		touch_range(p, p);
	}
	if (fragment_lo.x <= fragment_hi.x) {
		touch_range(fragment_lo, fragment_hi);
		lo = lo.min(fragment_lo);
		hi = hi.max(fragment_hi);
	}
	for (int slot : touched) {
		try_compress(chunks[slot]);
		mark_dirty(slot);
	}
	if (int(touched.size()) <= immediate_remesh_limit) {
		sort_by_camera_distance(touched);
		for (int slot : touched) {
			build_chunk_mesh(slot);
		}
	}
	emit_signal("voxels_changed", lo, hi);
	return result;
}

PackedInt32Array VoxelWorld::find_in_sphere(const Vector3 &center, float radius, const PackedByteArray &hosts, bool exposed_only, int max_count) const {
	PackedInt32Array out;
	bool wanted[256];
	build_host_table(hosts, wanted);
	const Vector3 c = to_voxel_space(center);
	const double r = double(radius) / voxel_size;
	const double r2 = r * r;
	const Vector3i lo = Vector3i(floor_to_int(c.x - r), floor_to_int(c.y - r), floor_to_int(c.z - r));
	const Vector3i hi = Vector3i(floor_to_int(c.x + r), floor_to_int(c.y + r), floor_to_int(c.z + r));
	struct Found {
		double distance2;
		Vector3i p;
	};
	std::vector<Found> found;
	for (int y = lo.y; y <= hi.y; y++) {
		for (int z = lo.z; z <= hi.z; z++) {
			for (int x = lo.x; x <= hi.x; x++) {
				const double dx = x + 0.5 - c.x, dy = y + 0.5 - c.y, dz = z + 0.5 - c.z;
				const double d2 = dx * dx + dy * dy + dz * dz;
				if (d2 > r2 || !in_bounds(x, y, z)) {
					continue;
				}
				const uint8_t current = read(x, y, z);
				if (current == 0 || current == BOUNDARY_MATERIAL || !wanted[current]) {
					continue;
				}
				if (exposed_only && read(x + 1, y, z) != 0 && read(x - 1, y, z) != 0 && read(x, y + 1, z) != 0 &&
						read(x, y - 1, z) != 0 && read(x, y, z + 1) != 0 && read(x, y, z - 1) != 0) {
					continue;
				}
				found.push_back({ d2, Vector3i(x, y, z) });
			}
		}
	}
	// Stable, so equal distances keep scan order and every peer gets the same list.
	std::stable_sort(found.begin(), found.end(), [](const Found &a, const Found &b) { return a.distance2 < b.distance2; });
	const int count = MIN(int(found.size()), MAX(0, max_count));
	out.resize(int64_t(count) * 3);
	for (int i = 0; i < count; i++) {
		out[i * 3] = found[i].p.x;
		out[i * 3 + 1] = found[i].p.y;
		out[i * 3 + 2] = found[i].p.z;
	}
	return out;
}

void VoxelWorld::detach_fragments(const std::vector<Vector3i> &removed, Vector3i &edit_from, Vector3i &edit_to) {
	static const Vector3i NEIGHBORS[6] = { Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1) };
	auto key = [](const Vector3i &p) { return int64_t(p.x) | (int64_t(p.y) << 21) | (int64_t(p.z) << 42); };

	// Anything that reaches this far from the edit is treated as attached. Together with a
	// depth-first fill, proving that a rock wall is attached takes tens of steps, not thousands.
	constexpr int ESCAPE_MARGIN = 48;
	Vector3i escape_lo = removed[0];
	Vector3i escape_hi = removed[0];
	for (const Vector3i &p : removed) {
		escape_lo = escape_lo.min(p);
		escape_hi = escape_hi.max(p);
	}
	escape_lo -= Vector3i(ESCAPE_MARGIN, ESCAPE_MARGIN, ESCAPE_MARGIN);
	escape_hi += Vector3i(ESCAPE_MARGIN, ESCAPE_MARGIN, ESCAPE_MARGIN);
	auto escaped = [&](const Vector3i &p) {
		return p.x < escape_lo.x || p.y < escape_lo.y || p.z < escape_lo.z || p.x > escape_hi.x || p.y > escape_hi.y || p.z > escape_hi.z;
	};

	// Pieces already proven to be attached, shared across seeds so each is only filled once.
	std::unordered_set<int64_t> grounded;
	std::unordered_set<int64_t> visited;
	std::vector<Vector3i> piece;
	std::vector<Vector3i> stack;
	Array fragments;

	for (const Vector3i &hole : removed) {
		for (const Vector3i &offset : NEIGHBORS) {
			const Vector3i seed = hole + offset;
			const uint8_t seed_material = read(seed.x, seed.y, seed.z);
			if (seed_material == 0 || hardness_of(seed_material) >= 255 || grounded.count(key(seed)) > 0) {
				continue;
			}

			visited.clear();
			piece.clear();
			stack.clear();
			visited.insert(key(seed));
			piece.push_back(seed);
			stack.push_back(seed);
			bool anchored = false;
			while (!stack.empty() && !anchored) {
				const Vector3i current = stack.back();
				stack.pop_back();
				for (const Vector3i &step : NEIGHBORS) {
					const Vector3i p = current + step;
					const uint8_t m = read(p.x, p.y, p.z);
					if (m == 0) {
						continue;
					}
					const int64_t k = key(p);
					if (hardness_of(m) >= 255 || escaped(p) || grounded.count(k) > 0) {
						anchored = true;
						break;
					}
					if (visited.insert(k).second) {
						piece.push_back(p);
						stack.push_back(p);
						// Too big to be a loose piece. Treat it as part of the facility's structure.
						if (int(piece.size()) > max_fragment_voxels) {
							anchored = true;
							break;
						}
					}
				}
			}

			if (anchored) {
				grounded.insert(visited.begin(), visited.end());
				continue;
			}

			int counts[256] = {};
			Vector3i lo = piece[0];
			Vector3i hi = piece[0];
			for (const Vector3i &p : piece) {
				counts[read(p.x, p.y, p.z)]++;
				write(p.x, p.y, p.z, 0);
				lo = lo.min(p);
				hi = hi.max(p);
			}
			edit_from = edit_from.min(lo);
			edit_to = edit_to.max(hi);

			Dictionary materials;
			for (int m = 1; m < 256; m++) {
				if (counts[m] > 0) {
					materials[m] = counts[m];
				}
			}
			const Vector3 world_lo = voxel_to_world(lo) - Vector3(0.5f, 0.5f, 0.5f) * voxel_size;
			Dictionary fragment;
			fragment["aabb"] = AABB(world_lo, Vector3(hi - lo + Vector3i(1, 1, 1)) * voxel_size);
			fragment["voxel_count"] = int(piece.size());
			fragment["materials"] = materials;
			fragments.push_back(fragment);
		}
	}

	if (!fragments.is_empty()) {
		emit_signal("fragments_detached", fragments);
	}
}

int VoxelWorld::stamp(const Vector3i &origin, const Vector3i &size, const PackedByteArray &voxels, bool only_air) {
	ERR_FAIL_COND_V_MSG(int64_t(size.x) * size.y * size.z != voxels.size(), 0, "stamp: voxels.size() must equal size.x * size.y * size.z.");
	int changed = 0;
	Vector3i lo = origin + size;
	Vector3i hi = origin;
	for (int z = 0; z < size.z; z++) {
		for (int y = 0; y < size.y; y++) {
			for (int x = 0; x < size.x; x++) {
				const uint8_t value = voxels[x + y * size.x + z * size.x * size.y];
				const Vector3i p = origin + Vector3i(x, y, z);
				if (value == 0 || value == BOUNDARY_MATERIAL || !in_bounds(p.x, p.y, p.z)) {
					continue;
				}
				const uint8_t current = read(p.x, p.y, p.z);
				if (current == value || (only_air && current != 0)) {
					continue;
				}
				write(p.x, p.y, p.z, value);
				lo = lo.min(p);
				hi = hi.max(p);
				changed++;
			}
		}
	}
	if (changed > 0) {
		finish_edit(lo, hi);
	}
	return changed;
}

PackedByteArray VoxelWorld::get_box(const Vector3i &from, const Vector3i &to) const {
	PackedByteArray out;
	const Vector3i size = to - from;
	ERR_FAIL_COND_V_MSG(size.x <= 0 || size.y <= 0 || size.z <= 0, out, "get_box: to must be greater than from on every axis.");
	out.resize(int64_t(size.x) * size.y * size.z);
	uint8_t *w = out.ptrw();
	int64_t i = 0;
	for (int z = 0; z < size.z; z++) {
		for (int y = 0; y < size.y; y++) {
			for (int x = 0; x < size.x; x++) {
				const Vector3i p = from + Vector3i(x, y, z);
				// Outside the world reads as air so a restore never writes the boundary.
				w[i++] = in_bounds(p.x, p.y, p.z) ? read(p.x, p.y, p.z) : 0;
			}
		}
	}
	return out;
}

int VoxelWorld::set_box(const Vector3i &from, const Vector3i &to, const PackedByteArray &voxels) {
	const Vector3i size = to - from;
	ERR_FAIL_COND_V_MSG(size.x <= 0 || size.y <= 0 || size.z <= 0, 0, "set_box: to must be greater than from on every axis.");
	ERR_FAIL_COND_V_MSG(int64_t(size.x) * size.y * size.z != voxels.size(), 0, "set_box: voxels.size() must match the box.");
	const uint8_t *r = voxels.ptr();
	int changed = 0;
	Vector3i lo = to;
	Vector3i hi = from;
	int64_t i = 0;
	for (int z = 0; z < size.z; z++) {
		for (int y = 0; y < size.y; y++) {
			for (int x = 0; x < size.x; x++, i++) {
				const Vector3i p = from + Vector3i(x, y, z);
				const uint8_t value = r[i];
				if (!in_bounds(p.x, p.y, p.z) || value == BOUNDARY_MATERIAL || read(p.x, p.y, p.z) == value) {
					continue;
				}
				write(p.x, p.y, p.z, value);
				lo = lo.min(p);
				hi = hi.max(p);
				changed++;
			}
		}
	}
	if (changed > 0) {
		finish_edit(lo, hi);
	}
	return changed;
}

namespace {

enum StructureRole { ROLE_OUTSIDE, ROLE_LINING, ROLE_INTERIOR, ROLE_OPENING };

struct StructureCell {
	int role = ROLE_OUTSIDE;
	uint8_t material = 0;
};

constexpr int ROOM_STRIDE = 10;
constexpr int OPENING_STRIDE = 6;

inline bool inside(const int32_t *box, int x, int y, int z, int grow) {
	return x >= box[0] - grow && y >= box[1] - grow && z >= box[2] - grow && x < box[3] + grow && y < box[4] + grow && z < box[5] + grow;
}

// Build mode shapes (LevelBuild.pack): records of [type, payload length, payload...].
enum BuildType { BUILD_WALL = 1, BUILD_SLAB = 2, BUILD_WALL_OPENING = 3 };

// One parsed record, with its box for a quick reject.
struct BuildShape {
	int type = 0;
	const int32_t *data = nullptr; // The payload.
	int min[3] = {};
	int max[3] = {}; // Exclusive.
};

// A wall's frame: a cell center -> (along, across) in voxels, from a toward b. across < 0 is the
// left of a -> b seen from above (+y up, so with x east and z south: the side a left turn faces).
struct WallFrame {
	double ax, az, ux, uz, length;
	WallFrame(const int32_t *w) {
		ax = w[0];
		az = w[1];
		const double dx = w[2] - w[0], dz = w[3] - w[1];
		length = Math::sqrt(dx * dx + dz * dz);
		ux = length > 0.0 ? dx / length : 1.0;
		uz = length > 0.0 ? dz / length : 0.0;
	}
	void at(int x, int z, double &along, double &across) const {
		const double cx = x + 0.5 - ax, cz = z + 0.5 - az;
		along = cx * ux + cz * uz;
		across = cx * uz - cz * ux;
	}
};

// A slab shape's ints after [add, material, count]: a polygon of `count` (x, z) points, or for a
// negative count, -count runs (z, x0, x1), sorted by z, each covering columns x0 <= x < x1 of row z.
inline int slab_shape_ints(int count) {
	return count >= 0 ? count * 2 : -count * 3;
}

// Whether the runs (sorted by z) cover column (x, z).
bool runs_have(const int32_t *runs, int count, int x, int z) {
	int lo = 0, hi = count;
	while (lo < hi) { // The first run with run z >= z.
		const int mid = (lo + hi) / 2;
		if (runs[mid * 3] < z) {
			lo = mid + 1;
		} else {
			hi = mid;
		}
	}
	for (int i = lo; i < count && runs[i * 3] == z; i++) {
		if (x >= runs[i * 3 + 1] && x < runs[i * 3 + 2]) {
			return true;
		}
	}
	return false;
}

// Even-odd test of the point (x, z) against a polygon of `count` (x, z) points.
bool polygon_has(const int32_t *points, int count, double x, double z) {
	bool in = false;
	for (int i = 0, j = count - 1; i < count; j = i++) {
		const double xi = points[i * 2], zi = points[i * 2 + 1], xj = points[j * 2], zj = points[j * 2 + 1];
		if ((zi > z) != (zj > z) && x < (xj - xi) * (z - zi) / (zj - zi) + xi) {
			in = !in;
		}
	}
	return in;
}

std::vector<BuildShape> parse_build(const PackedInt32Array &build) {
	std::vector<BuildShape> shapes;
	const int32_t *b = build.ptr();
	const int64_t n = build.size();
	for (int64_t i = 0; i + 2 <= n;) {
		BuildShape shape;
		shape.type = b[i];
		const int length = b[i + 1];
		if (length < 0 || i + 2 + length > n) {
			break;
		}
		shape.data = b + i + 2;
		const int32_t *d = shape.data;
		if ((shape.type == BUILD_WALL || shape.type == BUILD_WALL_OPENING) && length >= 9) {
			// ax az bx bz y0 y1 thickness ...: the segment grown by the thickness (and a voxel).
			const int grow = d[6] / 2 + 2;
			shape.min[0] = MIN(d[0], d[2]) - grow;
			shape.max[0] = MAX(d[0], d[2]) + grow;
			shape.min[2] = MIN(d[1], d[3]) - grow;
			shape.max[2] = MAX(d[1], d[3]) + grow;
			shape.min[1] = d[4];
			shape.max[1] = d[5];
			shapes.push_back(shape);
		} else if (shape.type == BUILD_SLAB && length >= 3) {
			// y0 y1 count, then per shape: add, material, count, then its points or runs.
			shape.min[1] = d[0];
			shape.max[1] = d[1];
			shape.min[0] = shape.min[2] = INT32_MAX;
			shape.max[0] = shape.max[2] = INT32_MIN;
			int at = 3;
			bool whole = true;
			for (int k = 0; k < d[2]; k++) {
				if (at + 3 > length || at + 3 + slab_shape_ints(d[at + 2]) > length) {
					whole = false;
					break;
				}
				const int count = d[at + 2];
				const int32_t *v = d + at + 3;
				if (count >= 0) {
					for (int p = 0; p < count; p++) {
						shape.min[0] = MIN(shape.min[0], v[p * 2]);
						shape.max[0] = MAX(shape.max[0], v[p * 2]);
						shape.min[2] = MIN(shape.min[2], v[p * 2 + 1]);
						shape.max[2] = MAX(shape.max[2], v[p * 2 + 1]);
					}
				} else {
					for (int r = 0; r < -count; r++) {
						shape.min[0] = MIN(shape.min[0], v[r * 3 + 1]);
						shape.max[0] = MAX(shape.max[0], v[r * 3 + 2]);
						shape.min[2] = MIN(shape.min[2], v[r * 3]);
						shape.max[2] = MAX(shape.max[2], v[r * 3] + 1);
					}
				}
				at += 3 + slab_shape_ints(count);
			}
			if (whole && shape.min[0] < shape.max[0]) {
				shapes.push_back(shape);
			}
		}
		i += 2 + length;
	}
	return shapes;
}

inline bool shape_may_hold(const BuildShape &shape, int x, int y, int z) {
	return x >= shape.min[0] && x < shape.max[0] && y >= shape.min[1] && y < shape.max[1] && z >= shape.min[2] && z < shape.max[2];
}

// Wall: ax az bx bz y0 y1 thickness material inner (-1: none). Its cells are across [-t/2, t/2),
// along the segment and t/2 past each end (so corners close). inner paints the left half of a wall
// at least 2 thick. Returns the material, or -1 outside it.
int wall_material(const int32_t *w, int x, int y, int z) {
	if (y < w[4] || y >= w[5]) {
		return -1;
	}
	const WallFrame frame(w);
	double along, across;
	frame.at(x, z, along, across);
	const double half = w[6] * 0.5;
	if (across < -half || across >= half || along < -half || along >= frame.length + half) {
		return -1;
	}
	return (w[8] > 0 && w[6] >= 2 && across < 0.0) ? w[8] : w[7];
}

// Wall opening: ax az bx bz y0 y1 thickness along0 along1. The wall's cells (a voxel wider on each
// side, so it always cuts through) with along in [along0, along1).
bool wall_opening_has(const int32_t *o, int x, int y, int z) {
	if (y < o[4] || y >= o[5]) {
		return false;
	}
	const WallFrame frame(o);
	double along, across;
	frame.at(x, z, along, across);
	const double half = o[6] * 0.5 + 1.0;
	return across >= -half && across < half && along >= o[7] && along < o[8];
}

// Slab: the last of its shapes holding the cell's column decides (add: its material, erase: none).
int slab_material(const int32_t *d, int x, int y, int z) {
	if (y < d[0] || y >= d[1]) {
		return -1;
	}
	int material = -1;
	int at = 3;
	for (int k = 0; k < d[2]; k++) {
		const int count = d[at + 2];
		const bool holds = count >= 0 ? (count >= 3 && polygon_has(d + at + 3, count, x + 0.5, z + 0.5)) : runs_have(d + at + 3, -count, x, z);
		if (holds) {
			material = d[at] ? d[at + 1] : -1;
		}
		at += 3 + slab_shape_ints(count);
	}
	return material;
}

// The shapes (in order) whose box holds row z, or layer y of those: so each cell only tests the few
// that can hold it.
void shapes_in_row(const std::vector<BuildShape> &all, int z, std::vector<const BuildShape *> &out) {
	out.clear();
	for (const BuildShape &shape : all) {
		if (z >= shape.min[2] && z < shape.max[2]) {
			out.push_back(&shape);
		}
	}
}

void shapes_in_layer(const std::vector<const BuildShape *> &row, int y, std::vector<const BuildShape *> &out) {
	out.clear();
	for (const BuildShape *shape : row) {
		if (y >= shape->min[1] && y < shape->max[1]) {
			out.push_back(shape);
		}
	}
}

StructureCell structure_at(const PackedInt32Array &rooms, const PackedInt32Array &openings, const std::vector<const BuildShape *> &build, int base, int x, int y, int z) {
	StructureCell cell;
	cell.material = uint8_t(base);
	const int32_t *o = openings.ptr();
	for (int64_t i = 0; i + OPENING_STRIDE <= openings.size(); i += OPENING_STRIDE) {
		if (inside(o + i, x, y, z, 0)) {
			cell.role = ROLE_OPENING;
			cell.material = 0;
			return cell;
		}
	}
	// In rock levels (base solid) build pieces stand in carved rooms: they fill a room's inside and
	// recolor its lining, but never touch the rock around it, and a wall opening only cuts inside a
	// room (so it can't dig into the rock behind a wall).
	const bool in_rock = base != 0;
	int built = -1;
	bool wall_cut = false;
	for (const BuildShape *shape_ptr : build) {
		const BuildShape &shape = *shape_ptr;
		if (!shape_may_hold(shape, x, y, z)) {
			continue;
		}
		if (shape.type == BUILD_WALL_OPENING) {
			if (wall_opening_has(shape.data, x, y, z)) {
				if (!in_rock) {
					cell.role = ROLE_OPENING;
					cell.material = 0;
					return cell;
				}
				wall_cut = true;
			}
			continue;
		}
		const int material = shape.type == BUILD_WALL ? wall_material(shape.data, x, y, z) : slab_material(shape.data, x, y, z);
		if (material > 0) {
			built = material; // Later shapes win.
		}
	}
	const int32_t *r = rooms.ptr();
	int lining = -1;
	bool interior = false;
	for (int64_t i = 0; i + ROOM_STRIDE <= rooms.size(); i += ROOM_STRIDE) {
		if (inside(r + i, x, y, z, 0)) {
			interior = true;
			break;
		}
		if (inside(r + i, x, y, z, r[i + 9])) {
			lining = int(i);
		}
	}
	if (interior) {
		if (wall_cut) {
			cell.role = ROLE_OPENING;
			cell.material = 0;
		} else if (built > 0 && in_rock) {
			cell.role = ROLE_LINING;
			cell.material = uint8_t(built);
		} else {
			cell.role = ROLE_INTERIOR;
			cell.material = 0;
		}
		return cell;
	}
	if (built > 0 && (!in_rock || lining >= 0)) {
		// Built floors, walls and ceilings are like linings: they only replace untouched voxels.
		cell.role = ROLE_LINING;
		cell.material = uint8_t(built);
	} else if (lining >= 0) {
		const int32_t *room = r + lining;
		cell.role = ROLE_LINING;
		cell.material = uint8_t(y < room[1] ? room[6] : (y >= room[4] ? room[8] : room[7]));
	}
	return cell;
}

} // namespace

int VoxelWorld::apply_structure(const Vector3i &from, const Vector3i &to, const PackedInt32Array &before_rooms, const PackedInt32Array &after_rooms,
		const PackedInt32Array &before_openings, const PackedInt32Array &after_openings, int base, const PackedByteArray &base_set,
		const PackedInt32Array &before_build, const PackedInt32Array &after_build) {
	const std::vector<BuildShape> build_before = parse_build(before_build);
	const std::vector<BuildShape> build_after = parse_build(after_build);
	ERR_FAIL_COND_V_MSG(before_rooms.size() % ROOM_STRIDE != 0 || after_rooms.size() % ROOM_STRIDE != 0, 0, "apply_structure: rooms are 10 ints each.");
	ERR_FAIL_COND_V_MSG(before_openings.size() % OPENING_STRIDE != 0 || after_openings.size() % OPENING_STRIDE != 0, 0, "apply_structure: openings are 6 ints each.");
	bool is_base[256] = {};
	for (int64_t i = 0; i < base_set.size(); i++) {
		is_base[base_set[i]] = true;
	}
	const Vector3i lo_box = from.max(Vector3i());
	const Vector3i hi_box = to.min(get_size_in_voxels());
	int changed = 0;
	Vector3i lo = hi_box;
	Vector3i hi = lo_box;
	std::vector<const BuildShape *> row_before, row_after, layer_before, layer_after;
	for (int z = lo_box.z; z < hi_box.z; z++) {
		shapes_in_row(build_before, z, row_before);
		shapes_in_row(build_after, z, row_after);
		for (int y = lo_box.y; y < hi_box.y; y++) {
			shapes_in_layer(row_before, y, layer_before);
			shapes_in_layer(row_after, y, layer_after);
			for (int x = lo_box.x; x < hi_box.x; x++) {
				const StructureCell was = structure_at(before_rooms, before_openings, layer_before, base, x, y, z);
				const StructureCell now = structure_at(after_rooms, after_openings, layer_after, base, x, y, z);
				if (was.role == now.role && was.material == now.material) {
					continue;
				}
				const uint8_t current = read(x, y, z);
				if (current == BOUNDARY_MATERIAL) {
					continue;
				}
				// A room's inside and an opening are always air; a cell no room claims any more goes
				// back to base. Linings only replace what's still untouched.
				const bool forced = (now.role == ROLE_OPENING && was.role != ROLE_OPENING) ||
						(now.role == ROLE_INTERIOR && was.role != ROLE_INTERIOR && was.role != ROLE_OPENING) ||
						(now.role == ROLE_OUTSIDE && was.role != ROLE_OUTSIDE);
				const bool untouched = was.role == ROLE_OUTSIDE ? is_base[current] : current == was.material;
				if ((!forced && !untouched) || current == now.material) {
					continue;
				}
				write(x, y, z, now.material);
				const Vector3i p(x, y, z);
				lo = lo.min(p);
				hi = hi.max(p);
				changed++;
			}
		}
	}
	if (changed > 0) {
		finish_edit(lo, hi);
	}
	return changed;
}

int VoxelWorld::count_matching(const Vector3i &origin, const Vector3i &size, const PackedByteArray &voxels) const {
	ERR_FAIL_COND_V_MSG(int64_t(size.x) * size.y * size.z != voxels.size(), 0, "count_matching: voxels.size() must equal size.x * size.y * size.z.");
	const uint8_t *r = voxels.ptr();
	int count = 0;
	int64_t i = 0;
	for (int z = 0; z < size.z; z++) {
		for (int y = 0; y < size.y; y++) {
			for (int x = 0; x < size.x; x++, i++) {
				const Vector3i p = origin + Vector3i(x, y, z);
				if (r[i] != 0 && in_bounds(p.x, p.y, p.z) && read(p.x, p.y, p.z) == r[i]) {
					count++;
				}
			}
		}
	}
	return count;
}

int VoxelWorld::erase_stamp(const Vector3i &origin, const Vector3i &size, const PackedByteArray &voxels) {
	ERR_FAIL_COND_V_MSG(int64_t(size.x) * size.y * size.z != voxels.size(), 0, "erase_stamp: voxels.size() must equal size.x * size.y * size.z.");
	int changed = 0;
	Vector3i lo = origin + size;
	Vector3i hi = origin;
	for (int z = 0; z < size.z; z++) {
		for (int y = 0; y < size.y; y++) {
			for (int x = 0; x < size.x; x++) {
				const uint8_t value = voxels[x + y * size.x + z * size.x * size.y];
				const Vector3i p = origin + Vector3i(x, y, z);
				if (value == 0 || !in_bounds(p.x, p.y, p.z) || read(p.x, p.y, p.z) != value) {
					continue;
				}
				write(p.x, p.y, p.z, 0);
				lo = lo.min(p);
				hi = hi.max(p);
				changed++;
			}
		}
	}
	if (changed > 0) {
		finish_edit(lo, hi);
	}
	return changed;
}

Dictionary VoxelWorld::check_stamp(const Vector3i &origin, const Vector3i &size, const PackedByteArray &voxels) const {
	Dictionary result;
	result["free"] = 0;
	result["supported"] = 0;
	ERR_FAIL_COND_V_MSG(int64_t(size.x) * size.y * size.z != voxels.size(), result, "check_stamp: voxels.size() must equal size.x * size.y * size.z.");

	static const Vector3i NEIGHBORS[6] = { Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1) };
	auto in_model = [&](const Vector3i &local) {
		return local.x >= 0 && local.y >= 0 && local.z >= 0 && local.x < size.x && local.y < size.y && local.z < size.z &&
				voxels[local.x + local.y * size.x + local.z * size.x * size.y] != 0;
	};

	int free = 0;
	int supported = 0;
	for (int z = 0; z < size.z; z++) {
		for (int y = 0; y < size.y; y++) {
			for (int x = 0; x < size.x; x++) {
				const Vector3i local(x, y, z);
				if (!in_model(local)) {
					continue;
				}
				const Vector3i p = origin + local;
				if (read(p.x, p.y, p.z) != 0) {
					supported++;
					continue;
				}
				free++;
				for (const Vector3i &step : NEIGHBORS) {
					const Vector3i n = p + step;
					if (!in_model(local + step) && read(n.x, n.y, n.z) != 0) {
						supported++;
						break;
					}
				}
			}
		}
	}
	result["free"] = free;
	result["supported"] = supported;
	return result;
}

// --- Meshing ----------------------------------------------------------------------------------

void VoxelWorld::mark_dirty(int slot) {
	Chunk &c = chunks[slot];
	if (!c.dirty) {
		c.dirty = true;
		dirty_queue.push_back(slot);
	}
}

void VoxelWorld::finish_edit(const Vector3i &from, const Vector3i &to) {
	// Faces and AO of voxels one step away depend on the edited voxels, so grow the range by one.
	const int cx0 = CLAMP((from.x - 1) >> CHUNK_SHIFT, 0, size_in_chunks.x - 1);
	const int cy0 = CLAMP((from.y - 1) >> CHUNK_SHIFT, 0, size_in_chunks.y - 1);
	const int cz0 = CLAMP((from.z - 1) >> CHUNK_SHIFT, 0, size_in_chunks.z - 1);
	const int cx1 = CLAMP((to.x + 1) >> CHUNK_SHIFT, 0, size_in_chunks.x - 1);
	const int cy1 = CLAMP((to.y + 1) >> CHUNK_SHIFT, 0, size_in_chunks.y - 1);
	const int cz1 = CLAMP((to.z + 1) >> CHUNK_SHIFT, 0, size_in_chunks.z - 1);

	std::vector<int> touched;
	for (int cy = cy0; cy <= cy1; cy++) {
		for (int cz = cz0; cz <= cz1; cz++) {
			for (int cx = cx0; cx <= cx1; cx++) {
				const int slot = chunk_slot(cx, cy, cz);
				try_compress(chunks[slot]);
				mark_dirty(slot);
				touched.push_back(slot);
			}
		}
	}

	if (int(touched.size()) <= immediate_remesh_limit) {
		sort_by_camera_distance(touched);
		for (int slot : touched) {
			build_chunk_mesh(slot);
		}
	}
	emit_signal("voxels_changed", from, to);
}

bool VoxelWorld::chunk_fully_solid(int slot) const {
	const Chunk &c = chunks[slot];
	if (c.data.empty()) {
		return c.uniform_value != 0;
	}
	return std::memchr(c.data.data(), 0, c.data.size()) == nullptr;
}

Ref<ArrayMesh> VoxelWorld::arrays_to_mesh(const MeshBuffers &buffers) const {
	PackedColorArray colors;
	colors.resize(int64_t(buffers.colors.size()));
	std::memcpy(colors.ptrw(), buffers.colors.data(), buffers.colors.size() * sizeof(Color));
	PackedInt32Array indices;
	indices.resize(int64_t(buffers.indices.size()));
	std::memcpy(indices.ptrw(), buffers.indices.data(), buffers.indices.size() * sizeof(int32_t));

	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = to_packed_vector3(buffers.vertices);
	arrays[Mesh::ARRAY_NORMAL] = to_packed_vector3(buffers.normals);
	arrays[Mesh::ARRAY_COLOR] = colors;
	arrays[Mesh::ARRAY_INDEX] = indices;

	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	if (!buffers.indices.empty()) {
		mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	}
	return mesh;
}

bool VoxelWorld::chunk_needs_mesh(int slot) const {
	const Chunk &c = chunks[slot];
	if (c.data.empty() && c.uniform_value == 0) {
		return false;
	}
	if (!chunk_fully_solid(slot)) {
		return true;
	}
	// A fully solid chunk only has faces where it touches a chunk that has air in it.
	const int cx = slot % size_in_chunks.x;
	const int cz = (slot / size_in_chunks.x) % size_in_chunks.z;
	const int cy = slot / (size_in_chunks.x * size_in_chunks.z);
	static const int OFFSETS[6][3] = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } };
	for (const auto &o : OFFSETS) {
		const int nx = cx + o[0], ny = cy + o[1], nz = cz + o[2];
		if (nx < 0 || ny < 0 || nz < 0 || nx >= size_in_chunks.x || ny >= size_in_chunks.y || nz >= size_in_chunks.z) {
			if (!out_of_bounds_solid) {
				return true;
			}
			continue;
		}
		if (!chunk_fully_solid(chunk_slot(nx, ny, nz))) {
			return true;
		}
	}
	return false;
}

void VoxelWorld::build_chunk_mesh(int slot) {
	Chunk &c = chunks[slot];
	if (!c.dirty) {
		return;
	}
	c.dirty = false;

	Time *time = Time::get_singleton();
	const uint64_t start = time->get_ticks_usec();
	uint64_t padded_at = start;
	uint64_t greedy_at = start;

	mesh_buffers.clear();
	if (chunk_needs_mesh(slot)) {
		const int cx = slot % size_in_chunks.x;
		const int cz = (slot / size_in_chunks.x) % size_in_chunks.z;
		const int cy = slot / (size_in_chunks.x * size_in_chunks.z);
		const int ox = cx * CHUNK_SIZE, oy = cy * CHUNK_SIZE, oz = cz * CHUNK_SIZE;
		for (int y = -1; y <= CHUNK_SIZE; y++) {
			for (int z = -1; z <= CHUNK_SIZE; z++) {
				for (int x = -1; x <= CHUNK_SIZE; x++) {
					padded[padded_index(x, y, z)] = read(ox + x, oy + y, oz + z);
				}
			}
		}
		padded_at = time->get_ticks_usec();
		mesh_padded_chunk(padded.data(), voxel_size, mesh_buffers);
		greedy_at = time->get_ticks_usec();
	}

	if (mesh_buffers.indices.empty()) {
		if (c.mesh_instance != nullptr) {
			c.mesh_instance->queue_free();
			c.mesh_instance = nullptr;
		}
		c.triangle_count = 0;
	} else {
		Ref<ArrayMesh> mesh = arrays_to_mesh(mesh_buffers);

		if (c.mesh_instance == nullptr) {
			const int cx = slot % size_in_chunks.x;
			const int cz = (slot / size_in_chunks.x) % size_in_chunks.z;
			const int cy = slot / (size_in_chunks.x * size_in_chunks.z);
			c.mesh_instance = memnew(MeshInstance3D);
			c.mesh_instance->set_position(Vector3(cx, cy, cz) * (CHUNK_SIZE * voxel_size));
			add_child(c.mesh_instance, false, INTERNAL_MODE_BACK);
		}
		c.mesh_instance->set_mesh(mesh);
		c.mesh_instance->set_material_override(material);
		c.triangle_count = int(mesh_buffers.indices.size() / 3);
	}

	const uint64_t end = time->get_ticks_usec();
	const double elapsed = double(end - start);
	if (greedy_at != start) {
		last_pad_usec = double(padded_at - start);
		last_greedy_usec = double(greedy_at - padded_at);
		last_upload_usec = double(end - greedy_at);
	}
	last_mesh_usec = elapsed;
	max_mesh_usec = MAX(max_mesh_usec, elapsed);
	meshes_built_total++;
}

Vector3 VoxelWorld::camera_position_in_voxels() const {
	if (!is_inside_tree()) {
		return Vector3();
	}
	Viewport *viewport = get_viewport();
	Camera3D *camera = viewport != nullptr ? viewport->get_camera_3d() : nullptr;
	if (camera == nullptr) {
		return Vector3();
	}
	return to_voxel_space(camera->get_global_position());
}

void VoxelWorld::sort_by_camera_distance(std::vector<int> &slots) const {
	const Vector3 cam = camera_position_in_voxels();
	const int sx = size_in_chunks.x, sz = size_in_chunks.z;
	auto distance = [&](int slot) {
		const float half = CHUNK_SIZE * 0.5f;
		const Vector3 center(float(slot % sx) * CHUNK_SIZE + half, float(slot / (sx * sz)) * CHUNK_SIZE + half, float((slot / sx) % sz) * CHUNK_SIZE + half);
		return center.distance_squared_to(cam);
	};
	std::sort(slots.begin(), slots.end(), [&](int a, int b) { return distance(a) < distance(b); });
}

void VoxelWorld::remesh_all_now() {
	for (int slot : dirty_queue) {
		build_chunk_mesh(slot);
	}
	dirty_queue.clear();
}

Dictionary VoxelWorld::get_stats() const {
	int meshed = 0;
	int triangles = 0;
	int expanded = 0;
	int dirty = 0;
	for (const Chunk &c : chunks) {
		meshed += c.mesh_instance != nullptr ? 1 : 0;
		triangles += c.triangle_count;
		expanded += c.data.empty() ? 0 : 1;
		dirty += c.dirty ? 1 : 0;
	}
	Dictionary stats;
	stats["chunks"] = int(chunks.size());
	stats["chunks_meshed"] = meshed;
	stats["chunks_expanded"] = expanded;
	stats["chunks_dirty"] = dirty;
	stats["triangles"] = triangles;
	stats["last_mesh_ms"] = last_mesh_usec / 1000.0;
	stats["max_mesh_ms"] = max_mesh_usec / 1000.0;
	stats["last_pad_ms"] = last_pad_usec / 1000.0;
	stats["last_greedy_ms"] = last_greedy_usec / 1000.0;
	stats["last_upload_ms"] = last_upload_usec / 1000.0;
	stats["last_flow_ms"] = last_flow_usec / 1000.0;
	stats["flow_reached"] = last_flow_reached;
	stats["meshes_built"] = meshes_built_total;
	return stats;
}

// --- Queries ----------------------------------------------------------------------------------

Dictionary VoxelWorld::raycast(const Vector3 &origin, const Vector3 &direction, float max_distance) const {
	Dictionary result;
	result["hit"] = false;
	if (direction.is_zero_approx()) {
		return result;
	}
	const Vector3 dir = direction.normalized();
	const Vector3 o = to_voxel_space(origin);
	const double max_t = double(max_distance) / voxel_size;

	int pos[3] = { floor_to_int(o.x), floor_to_int(o.y), floor_to_int(o.z) };
	int step[3];
	double t_max[3];
	double t_delta[3];
	for (int a = 0; a < 3; a++) {
		if (dir[a] > 0.0f) {
			step[a] = 1;
			t_delta[a] = 1.0 / dir[a];
			t_max[a] = (pos[a] + 1 - double(o[a])) * t_delta[a];
		} else if (dir[a] < 0.0f) {
			step[a] = -1;
			t_delta[a] = -1.0 / dir[a];
			t_max[a] = (double(o[a]) - pos[a]) * t_delta[a];
		} else {
			step[a] = 0;
			t_delta[a] = INFINITY;
			t_max[a] = INFINITY;
		}
	}

	double t = 0.0;
	Vector3 normal;
	while (true) {
		const uint8_t m = read(pos[0], pos[1], pos[2]);
		if (m != 0) {
			result["hit"] = true;
			result["position"] = origin + dir * float(t * voxel_size);
			result["normal"] = normal;
			result["voxel"] = Vector3i(pos[0], pos[1], pos[2]);
			result["material"] = int(m);
			result["distance"] = float(t * voxel_size);
			return result;
		}
		const int a = (t_max[0] < t_max[1]) ? (t_max[0] < t_max[2] ? 0 : 2) : (t_max[1] < t_max[2] ? 1 : 2);
		if (t_max[a] > max_t) {
			return result;
		}
		t = t_max[a];
		t_max[a] += t_delta[a];
		pos[a] += step[a];
		normal = Vector3();
		normal[a] = float(-step[a]);
	}
}

bool VoxelWorld::box_hits_solid(int axis, int layer, int b0, int b1, int c0, int c1) const {
	const int b = (axis + 1) % 3;
	for (int i = b0; i <= b1; i++) {
		for (int j = c0; j <= c1; j++) {
			int p[3];
			p[axis] = layer;
			p[b] = i;
			p[(axis + 2) % 3] = j;
			if (read(p[0], p[1], p[2]) != 0) {
				return true;
			}
		}
	}
	return false;
}

// Moves the box along one axis, stopping flush against the first solid voxel layer in the way.
// Every layer crossed is checked, so fast movement cannot tunnel through thin walls.
bool VoxelWorld::sweep_axis(double mn[3], double mx[3], int axis, double &delta) const {
	if (delta == 0.0) {
		return false;
	}
	const int b = (axis + 1) % 3;
	const int c = (axis + 2) % 3;
	const int b0 = floor_to_int(mn[b] + SWEEP_EPSILON), b1 = floor_to_int(mx[b] - SWEEP_EPSILON);
	const int c0 = floor_to_int(mn[c] + SWEEP_EPSILON), c1 = floor_to_int(mx[c] - SWEEP_EPSILON);

	bool hit = false;
	if (delta > 0.0) {
		const int first = int(std::ceil(mx[axis] - SWEEP_EPSILON));
		const int last = floor_to_int(mx[axis] + delta - SWEEP_EPSILON);
		for (int layer = first; layer <= last; layer++) {
			if (box_hits_solid(axis, layer, b0, b1, c0, c1)) {
				delta = MAX(0.0, double(layer) - mx[axis]);
				hit = true;
				break;
			}
		}
	} else {
		const int first = floor_to_int(mn[axis] + SWEEP_EPSILON) - 1;
		const int last = int(std::ceil(mn[axis] + delta + SWEEP_EPSILON)) - 1;
		for (int layer = first; layer >= last; layer--) {
			if (box_hits_solid(axis, layer, b0, b1, c0, c1)) {
				delta = MIN(0.0, double(layer + 1) - mn[axis]);
				hit = true;
				break;
			}
		}
	}
	mn[axis] += delta;
	mx[axis] += delta;
	return hit;
}

Dictionary VoxelWorld::move_box(const Vector3 &feet, const Vector3 &box_size, const Vector3 &motion, float step_height, bool allow_step) const {
	const Vector3 base = to_voxel_space(feet);
	const Vector3 half = box_size / voxel_size * 0.5f;
	const Vector3 m = motion / voxel_size;

	double mn[3] = { base.x - half.x, base.y, base.z - half.z };
	double mx[3] = { base.x + half.x, base.y + box_size.y / voxel_size, base.z + half.z };

	double dy = m.y;
	const bool hit_y = sweep_axis(mn, mx, 1, dy);
	bool on_floor = hit_y && m.y <= 0.0f;
	const bool hit_ceiling = hit_y && m.y > 0.0f;

	double flat_mn[3] = { mn[0], mn[1], mn[2] };
	double flat_mx[3] = { mx[0], mx[1], mx[2] };
	double dx = m.x, dz = m.z;
	bool hit_wall = sweep_axis(flat_mn, flat_mx, 0, dx);
	hit_wall = sweep_axis(flat_mn, flat_mx, 2, dz) || hit_wall;

	double step_up = 0.0;
	if (hit_wall && allow_step && step_height > 0.0f) {
		// Retry the horizontal move from higher up, then drop back onto whatever is there.
		double step_mn[3] = { mn[0], mn[1], mn[2] };
		double step_mx[3] = { mx[0], mx[1], mx[2] };
		double up = step_height / voxel_size;
		sweep_axis(step_mn, step_mx, 1, up);
		double sx = m.x, sz = m.z;
		bool step_wall = sweep_axis(step_mn, step_mx, 0, sx);
		step_wall = sweep_axis(step_mn, step_mx, 2, sz) || step_wall;
		double down = -up;
		const bool landed = sweep_axis(step_mn, step_mx, 1, down);

		const double flat_progress = std::abs(dx) + std::abs(dz);
		const double step_progress = std::abs(sx) + std::abs(sz);
		if (landed && step_progress > flat_progress + 1e-3) {
			step_up = step_mn[1] - mn[1];
			for (int a = 0; a < 3; a++) {
				flat_mn[a] = step_mn[a];
				flat_mx[a] = step_mx[a];
			}
			hit_wall = step_wall;
			on_floor = true;
		}
	}

	const Vector3 origin = is_inside_tree() ? get_global_position() : get_position();
	Dictionary result;
	result["position"] = origin + Vector3((flat_mn[0] + flat_mx[0]) * 0.5, flat_mn[1], (flat_mn[2] + flat_mx[2]) * 0.5) * voxel_size;
	result["on_floor"] = on_floor;
	result["hit_ceiling"] = hit_ceiling;
	result["hit_wall"] = hit_wall;
	result["step_up"] = float(step_up * voxel_size);
	return result;
}

bool VoxelWorld::box_overlaps_solid(const AABB &box) const {
	const Vector3 lo = to_voxel_space(box.position);
	const Vector3 hi = to_voxel_space(box.position + box.size);
	for (int y = floor_to_int(lo.y + SWEEP_EPSILON); y <= floor_to_int(hi.y - SWEEP_EPSILON); y++) {
		for (int z = floor_to_int(lo.z + SWEEP_EPSILON); z <= floor_to_int(hi.z - SWEEP_EPSILON); z++) {
			for (int x = floor_to_int(lo.x + SWEEP_EPSILON); x <= floor_to_int(hi.x - SWEEP_EPSILON); x++) {
				if (read(x, y, z) != 0) {
					return true;
				}
			}
		}
	}
	return false;
}

// --- Bindings ---------------------------------------------------------------------------------

void VoxelWorld::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_size_in_chunks", "value"), &VoxelWorld::set_size_in_chunks);
	ClassDB::bind_method(D_METHOD("get_size_in_chunks"), &VoxelWorld::get_size_in_chunks);
	ClassDB::bind_method(D_METHOD("set_voxel_size", "value"), &VoxelWorld::set_voxel_size);
	ClassDB::bind_method(D_METHOD("get_voxel_size"), &VoxelWorld::get_voxel_size);
	ClassDB::bind_method(D_METHOD("set_out_of_bounds_solid", "value"), &VoxelWorld::set_out_of_bounds_solid);
	ClassDB::bind_method(D_METHOD("get_out_of_bounds_solid"), &VoxelWorld::get_out_of_bounds_solid);
	ClassDB::bind_method(D_METHOD("set_material", "value"), &VoxelWorld::set_material);
	ClassDB::bind_method(D_METHOD("get_material"), &VoxelWorld::get_material);
	ClassDB::bind_method(D_METHOD("set_material_hardness", "value"), &VoxelWorld::set_material_hardness);
	ClassDB::bind_method(D_METHOD("get_material_hardness"), &VoxelWorld::get_material_hardness);
	ClassDB::bind_method(D_METHOD("set_remesh_budget_ms", "value"), &VoxelWorld::set_remesh_budget_ms);
	ClassDB::bind_method(D_METHOD("get_remesh_budget_ms"), &VoxelWorld::get_remesh_budget_ms);
	ClassDB::bind_method(D_METHOD("set_immediate_remesh_limit", "value"), &VoxelWorld::set_immediate_remesh_limit);
	ClassDB::bind_method(D_METHOD("get_immediate_remesh_limit"), &VoxelWorld::get_immediate_remesh_limit);

	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3I, "size_in_chunks"), "set_size_in_chunks", "get_size_in_chunks");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "voxel_size", PROPERTY_HINT_RANGE, "0.01,1.0,0.01,suffix:m"), "set_voxel_size", "get_voxel_size");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "out_of_bounds_solid"), "set_out_of_bounds_solid", "get_out_of_bounds_solid");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "material", PROPERTY_HINT_RESOURCE_TYPE, "Material"), "set_material", "get_material");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_BYTE_ARRAY, "material_hardness"), "set_material_hardness", "get_material_hardness");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "remesh_budget_ms", PROPERTY_HINT_RANGE, "0.5,16,0.5,suffix:ms"), "set_remesh_budget_ms", "get_remesh_budget_ms");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "immediate_remesh_limit", PROPERTY_HINT_RANGE, "0,64,1"), "set_immediate_remesh_limit", "get_immediate_remesh_limit");

	ClassDB::bind_method(D_METHOD("set_detach_floating", "value"), &VoxelWorld::set_detach_floating);
	ClassDB::bind_method(D_METHOD("get_detach_floating"), &VoxelWorld::get_detach_floating);
	ClassDB::bind_method(D_METHOD("set_max_fragment_voxels", "value"), &VoxelWorld::set_max_fragment_voxels);
	ClassDB::bind_method(D_METHOD("get_max_fragment_voxels"), &VoxelWorld::get_max_fragment_voxels);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "detach_floating"), "set_detach_floating", "get_detach_floating");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_fragment_voxels", PROPERTY_HINT_RANGE, "1,100000,1"), "set_max_fragment_voxels", "get_max_fragment_voxels");

	ClassDB::bind_method(D_METHOD("get_size_in_voxels"), &VoxelWorld::get_size_in_voxels);
	ClassDB::bind_method(D_METHOD("world_to_voxel", "world_position"), &VoxelWorld::world_to_voxel);
	ClassDB::bind_method(D_METHOD("voxel_to_world", "voxel"), &VoxelWorld::voxel_to_world);
	ClassDB::bind_method(D_METHOD("get_voxel", "voxel"), &VoxelWorld::get_voxel);
	ClassDB::bind_method(D_METHOD("set_voxel", "voxel", "material_id"), &VoxelWorld::set_voxel);
	ClassDB::bind_method(D_METHOD("fill_all", "material_id"), &VoxelWorld::fill_all);
	ClassDB::bind_method(D_METHOD("get_data"), &VoxelWorld::get_data);
	ClassDB::bind_method(D_METHOD("set_data", "data"), &VoxelWorld::set_data);
	ClassDB::bind_method(D_METHOD("fill_box", "from", "to", "material_id", "only_air"), &VoxelWorld::fill_box, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("fill_sphere", "center", "radius", "material_id", "only_air"), &VoxelWorld::fill_sphere, DEFVAL(true));
	ClassDB::bind_method(D_METHOD("carve_sphere", "center", "radius", "max_hardness"), &VoxelWorld::carve_sphere, DEFVAL(254));
	ClassDB::bind_method(D_METHOD("carve_box", "box", "max_hardness"), &VoxelWorld::carve_box, DEFVAL(254));
	ClassDB::bind_method(D_METHOD("replace_in_box", "from", "to", "material_id", "hosts"), &VoxelWorld::replace_in_box, DEFVAL(PackedByteArray()));
	ClassDB::bind_method(D_METHOD("replace_in_sphere", "center", "radius", "material_id", "hosts"), &VoxelWorld::replace_in_sphere, DEFVAL(PackedByteArray()));
	ClassDB::bind_method(D_METHOD("set_voxels", "points", "materials"), &VoxelWorld::set_voxels);
	ClassDB::bind_method(D_METHOD("find_in_sphere", "center", "radius", "hosts", "exposed_only", "max_count"), &VoxelWorld::find_in_sphere);
	ClassDB::bind_method(D_METHOD("fill_layers", "from", "to", "materials", "tops", "undulation", "wavelength", "seed"), &VoxelWorld::fill_layers);
	ClassDB::bind_method(D_METHOD("build_model_mesh", "size", "voxels"), &VoxelWorld::build_model_mesh);
	ClassDB::bind_method(D_METHOD("stamp", "origin", "size", "voxels", "only_air"), &VoxelWorld::stamp, DEFVAL(true));
	ClassDB::bind_method(D_METHOD("check_stamp", "origin", "size", "voxels"), &VoxelWorld::check_stamp);
	ClassDB::bind_method(D_METHOD("erase_stamp", "origin", "size", "voxels"), &VoxelWorld::erase_stamp);
	ClassDB::bind_method(D_METHOD("get_box", "from", "to"), &VoxelWorld::get_box);
	ClassDB::bind_method(D_METHOD("set_box", "from", "to", "voxels"), &VoxelWorld::set_box);
	ClassDB::bind_method(D_METHOD("apply_structure", "from", "to", "before_rooms", "after_rooms", "before_openings", "after_openings", "base", "base_set", "before_build", "after_build"),
			&VoxelWorld::apply_structure, DEFVAL(PackedInt32Array()), DEFVAL(PackedInt32Array()));
	ClassDB::bind_method(D_METHOD("count_matching", "origin", "size", "voxels"), &VoxelWorld::count_matching);
	ClassDB::bind_method(D_METHOD("raycast", "origin", "direction", "max_distance"), &VoxelWorld::raycast, DEFVAL(100.0f));
	ClassDB::bind_method(D_METHOD("move_box", "feet", "box_size", "motion", "step_height", "allow_step"), &VoxelWorld::move_box, DEFVAL(0.0f), DEFVAL(false));
	ClassDB::bind_method(D_METHOD("box_overlaps_solid", "box"), &VoxelWorld::box_overlaps_solid);
	ClassDB::bind_method(D_METHOD("set_nav_breach_hardness", "value"), &VoxelWorld::set_nav_breach_hardness);
	ClassDB::bind_method(D_METHOD("get_nav_breach_hardness"), &VoxelWorld::get_nav_breach_hardness);
	ClassDB::bind_method(D_METHOD("set_nav_breach_cost", "value"), &VoxelWorld::set_nav_breach_cost);
	ClassDB::bind_method(D_METHOD("get_nav_breach_cost"), &VoxelWorld::get_nav_breach_cost);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "nav_breach_hardness", PROPERTY_HINT_RANGE, "0,254,1"), "set_nav_breach_hardness", "get_nav_breach_hardness");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "nav_breach_cost", PROPERTY_HINT_RANGE, "0,1000,1"), "set_nav_breach_cost", "get_nav_breach_cost");
	ClassDB::bind_method(D_METHOD("update_flow_field", "targets", "max_distance"), &VoxelWorld::update_flow_field, DEFVAL(60.0f));
	ClassDB::bind_method(D_METHOD("get_flow", "feet"), &VoxelWorld::get_flow);

	ClassDB::bind_method(D_METHOD("remesh_all_now"), &VoxelWorld::remesh_all_now);
	ClassDB::bind_method(D_METHOD("get_stats"), &VoxelWorld::get_stats);

	ADD_SIGNAL(MethodInfo("voxels_changed", PropertyInfo(Variant::VECTOR3I, "from"), PropertyInfo(Variant::VECTOR3I, "to")));
	// Each fragment is {aabb: AABB (world space), voxel_count: int, materials: {material_id: count}}.
	ADD_SIGNAL(MethodInfo("fragments_detached", PropertyInfo(Variant::ARRAY, "fragments")));

	BIND_CONSTANT(BOUNDARY_MATERIAL);
}
