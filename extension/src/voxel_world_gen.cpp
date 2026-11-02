// World generation helpers: layered strata, material-selective replacement, and meshing small
// standalone voxel models (props, creatures) with the chunk mesher.

#include "voxel_world.h"

#include <cmath>
#include <cstring>

using namespace godot;
using namespace voxel;

namespace {

inline uint32_t hash2(int x, int z, uint32_t seed) {
	uint32_t h = seed * 0x9E3779B1u ^ uint32_t(x) * 0x85EBCA6Bu ^ uint32_t(z) * 0xC2B2AE35u;
	h ^= h >> 15;
	h *= 0x2C1B3C6Du;
	h ^= h >> 12;
	h *= 0x297A2D39u;
	h ^= h >> 15;
	return h;
}

// Smooth 2D value noise in [0, 1].
float value_noise(float x, float z, uint32_t seed) {
	const int xi = int(std::floor(x));
	const int zi = int(std::floor(z));
	const float fx = x - xi;
	const float fz = z - zi;
	const float u = fx * fx * (3.0f - 2.0f * fx);
	const float v = fz * fz * (3.0f - 2.0f * fz);
	constexpr float SCALE = 1.0f / 4294967295.0f;
	const float a = hash2(xi, zi, seed) * SCALE;
	const float b = hash2(xi + 1, zi, seed) * SCALE;
	const float c = hash2(xi, zi + 1, seed) * SCALE;
	const float d = hash2(xi + 1, zi + 1, seed) * SCALE;
	return (a + (b - a) * u) + ((c + (d - c) * u) - (a + (b - a) * u)) * v;
}

// Two octaves, roughly in [-1, 1].
float fbm(float x, float z, uint32_t seed) {
	return (value_noise(x, z, seed) * 0.65f + value_noise(x * 2.03f, z * 2.03f, seed + 77u) * 0.35f) * 2.0f - 1.0f;
}

} // namespace

void VoxelWorld::build_host_table(const PackedByteArray &hosts, bool table[256]) const {
	const bool any_solid = hosts.is_empty();
	for (int m = 0; m < 256; m++) {
		table[m] = any_solid && m != 0 && m != BOUNDARY_MATERIAL;
	}
	for (int64_t i = 0; i < hosts.size(); i++) {
		table[hosts[i]] = true;
	}
}

int VoxelWorld::replace_in_box(const Vector3i &from, const Vector3i &to, int material_id, const PackedByteArray &hosts) {
	const uint8_t value = uint8_t(CLAMP(material_id, 0, 254));
	bool replaceable[256];
	build_host_table(hosts, replaceable);
	const Vector3i size = get_size_in_voxels();
	const Vector3i lo = from.max(Vector3i());
	const Vector3i hi = to.min(size);
	int changed = 0;
	for (int y = lo.y; y < hi.y; y++) {
		for (int z = lo.z; z < hi.z; z++) {
			for (int x = lo.x; x < hi.x; x++) {
				const uint8_t current = read(x, y, z);
				if (current != value && replaceable[current]) {
					write(x, y, z, value);
					changed++;
				}
			}
		}
	}
	if (changed > 0) {
		finish_edit(lo, hi - Vector3i(1, 1, 1));
	}
	return changed;
}

int VoxelWorld::replace_in_sphere(const Vector3 &center, float radius, int material_id, const PackedByteArray &hosts) {
	const uint8_t value = uint8_t(CLAMP(material_id, 0, 254));
	bool replaceable[256];
	build_host_table(hosts, replaceable);
	const Vector3 c = to_voxel_space(center);
	const double r = double(radius) / voxel_size;
	const double r2 = r * r;
	const Vector3i lo = Vector3i(int(std::floor(c.x - r)), int(std::floor(c.y - r)), int(std::floor(c.z - r)));
	const Vector3i hi = Vector3i(int(std::floor(c.x + r)), int(std::floor(c.y + r)), int(std::floor(c.z + r)));
	int changed = 0;
	for (int y = lo.y; y <= hi.y; y++) {
		for (int z = lo.z; z <= hi.z; z++) {
			for (int x = lo.x; x <= hi.x; x++) {
				const double dx = x + 0.5 - c.x, dy = y + 0.5 - c.y, dz = z + 0.5 - c.z;
				if (dx * dx + dy * dy + dz * dz > r2 || !in_bounds(x, y, z)) {
					continue;
				}
				const uint8_t current = read(x, y, z);
				if (current != value && replaceable[current]) {
					write(x, y, z, value);
					changed++;
				}
			}
		}
	}
	if (changed > 0) {
		finish_edit(lo, hi);
	}
	return changed;
}

void VoxelWorld::fill_layers(const Vector3i &from, const Vector3i &to, const PackedByteArray &materials, const PackedFloat32Array &tops, float undulation, float wavelength, int seed) {
	ERR_FAIL_COND_MSG(materials.size() != tops.size() || materials.is_empty(), "fill_layers: materials and tops must be the same non-zero length.");
	const Vector3i size = get_size_in_voxels();
	const Vector3i lo = from.max(Vector3i());
	const Vector3i hi = to.min(size);
	if (lo.x >= hi.x || lo.y >= hi.y || lo.z >= hi.z) {
		return;
	}
	const int layer_count = int(materials.size());
	const float frequency = 1.0f / MAX(1.0f, wavelength);
	std::vector<float> boundaries(layer_count);

	for (int cz = lo.z >> CHUNK_SHIFT; cz <= (hi.z - 1) >> CHUNK_SHIFT; cz++) {
		for (int cx = lo.x >> CHUNK_SHIFT; cx <= (hi.x - 1) >> CHUNK_SHIFT; cx++) {
			for (int cy = lo.y >> CHUNK_SHIFT; cy <= (hi.y - 1) >> CHUNK_SHIFT; cy++) {
				const int slot = chunk_slot(cx, cy, cz);
				Chunk &c = chunks[slot];
				if (c.data.empty()) {
					c.data.assign(CHUNK_VOLUME, c.uniform_value);
				}
				const int x0 = MAX(lo.x, cx * CHUNK_SIZE), x1 = MIN(hi.x, (cx + 1) * CHUNK_SIZE);
				const int y0 = MAX(lo.y, cy * CHUNK_SIZE), y1 = MIN(hi.y, (cy + 1) * CHUNK_SIZE);
				const int z0 = MAX(lo.z, cz * CHUNK_SIZE), z1 = MIN(hi.z, (cz + 1) * CHUNK_SIZE);
				for (int z = z0; z < z1; z++) {
					for (int x = x0; x < x1; x++) {
						for (int k = 0; k < layer_count; k++) {
							boundaries[k] = tops[k] + undulation * fbm(x * frequency, z * frequency, uint32_t(seed) + uint32_t(k) * 1013u);
						}
						for (int y = y0; y < y1; y++) {
							for (int k = 0; k < layer_count; k++) {
								if (y < boundaries[k]) {
									c.data[chunk_index(x & CHUNK_MASK, y & CHUNK_MASK, z & CHUNK_MASK)] = materials[k];
									break;
								}
							}
						}
					}
				}
				nav_rebuild_chunk(slot);
			}
		}
	}
	finish_edit(lo, hi - Vector3i(1, 1, 1));
}

Ref<ArrayMesh> VoxelWorld::build_model_mesh(const Vector3i &size, const PackedByteArray &voxels) {
	ERR_FAIL_COND_V_MSG(size.x < 1 || size.y < 1 || size.z < 1 || size.x > CHUNK_SIZE || size.y > CHUNK_SIZE || size.z > CHUNK_SIZE,
			Ref<ArrayMesh>(), "build_model_mesh: each side must be between 1 and 32.");
	ERR_FAIL_COND_V_MSG(int64_t(size.x) * size.y * size.z != voxels.size(), Ref<ArrayMesh>(), "build_model_mesh: voxels.size() must equal size.x * size.y * size.z.");

	std::vector<uint8_t> model(PADDED_VOLUME, 0);
	for (int z = 0; z < size.z; z++) {
		for (int y = 0; y < size.y; y++) {
			for (int x = 0; x < size.x; x++) {
				model[padded_index(x, y, z)] = voxels[x + y * size.x + z * size.x * size.y];
			}
		}
	}
	MeshBuffers buffers;
	mesh_padded_chunk(model.data(), voxel_size, buffers);
	return arrays_to_mesh(buffers);
}
