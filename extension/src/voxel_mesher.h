#pragma once

#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <vector>

namespace voxel {

constexpr int CHUNK_SIZE = 32;
constexpr int CHUNK_SHIFT = 5;
constexpr int CHUNK_MASK = CHUNK_SIZE - 1;
constexpr int CHUNK_VOLUME = CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE;

// Chunk plus a one-voxel apron on every side, so faces and AO are correct across chunk borders.
constexpr int PADDED_SIZE = CHUNK_SIZE + 2;
constexpr int PADDED_VOLUME = PADDED_SIZE * PADDED_SIZE * PADDED_SIZE;

inline int chunk_index(int x, int y, int z) {
	return x + (z << CHUNK_SHIFT) + (y << (CHUNK_SHIFT * 2));
}

// Coordinates are chunk-local and may be -1..CHUNK_SIZE.
inline int padded_index(int x, int y, int z) {
	return (x + 1) + (z + 1) * PADDED_SIZE + (y + 1) * PADDED_SIZE * PADDED_SIZE;
}

struct MeshBuffers {
	std::vector<godot::Vector3> vertices;
	std::vector<godot::Vector3> normals;
	// r = ambient occlusion (0 dark .. 1 open), g = material id / 255.
	std::vector<godot::Color> colors;
	std::vector<int32_t> indices;

	void clear() {
		vertices.clear();
		normals.clear();
		colors.clear();
		indices.clear();
	}
};

// Greedy mesher with per-vertex ambient occlusion. Faces only merge when they share a material and
// all four corners have the same AO, so the merged quad looks identical to the unmerged faces.
// Material 0 is air; every other id is opaque. Vertices are in chunk-local units scaled by voxel_size.
void mesh_padded_chunk(const uint8_t *padded, float voxel_size, MeshBuffers &out);

} // namespace voxel
