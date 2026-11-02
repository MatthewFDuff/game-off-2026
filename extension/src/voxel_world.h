#pragma once

#include "voxel_mesher.h"

#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <vector>

namespace godot {

// A bounded voxel volume split into 32^3 chunks. Material 0 is air, every other id is solid.
// The world's origin is this node's global position; rotation and scale are not supported.
class VoxelWorld : public Node3D {
	GDCLASS(VoxelWorld, Node3D)

public:
	// Returned for voxels outside the world when out_of_bounds_solid is on. Never carved.
	static constexpr int BOUNDARY_MATERIAL = 255;

private:
	struct Chunk {
		// Empty means every voxel is uniform_value. Most underground chunks stay solid rock forever.
		std::vector<uint8_t> data;
		uint8_t uniform_value = 0;
		bool dirty = false;
		MeshInstance3D *mesh_instance = nullptr;
		int triangle_count = 0;
	};

	Vector3i size_in_chunks = Vector3i(20, 5, 20);
	float voxel_size = 0.1f;
	bool out_of_bounds_solid = true;
	Ref<Material> material;
	PackedByteArray material_hardness;
	float remesh_budget_ms = 4.0f;
	int immediate_remesh_limit = 24;
	bool detach_floating = true;
	int max_fragment_voxels = 6000;

	std::vector<Chunk> chunks;
	std::vector<int> dirty_queue;
	voxel::MeshBuffers mesh_buffers;
	std::vector<uint8_t> padded;

	// Stats for the debug overlay.
	double last_mesh_usec = 0.0;
	double max_mesh_usec = 0.0;
	// Breakdown of the last build: padded copy, greedy mesher, ArrayMesh upload.
	double last_pad_usec = 0.0;
	double last_greedy_usec = 0.0;
	double last_upload_usec = 0.0;
	int meshes_built_total = 0;

	void allocate();
	void free_meshes();

	inline bool in_bounds(int x, int y, int z) const {
		return x >= 0 && y >= 0 && z >= 0 && x < size_in_chunks.x * voxel::CHUNK_SIZE &&
				y < size_in_chunks.y * voxel::CHUNK_SIZE && z < size_in_chunks.z * voxel::CHUNK_SIZE;
	}
	inline int chunk_slot(int cx, int cy, int cz) const {
		return cx + cz * size_in_chunks.x + cy * size_in_chunks.x * size_in_chunks.z;
	}
	inline uint8_t read(int x, int y, int z) const {
		if (!in_bounds(x, y, z)) {
			return out_of_bounds_solid ? BOUNDARY_MATERIAL : 0;
		}
		const Chunk &c = chunks[chunk_slot(x >> voxel::CHUNK_SHIFT, y >> voxel::CHUNK_SHIFT, z >> voxel::CHUNK_SHIFT)];
		if (c.data.empty()) {
			return c.uniform_value;
		}
		return c.data[voxel::chunk_index(x & voxel::CHUNK_MASK, y & voxel::CHUNK_MASK, z & voxel::CHUNK_MASK)];
	}
	// Caller must check bounds and mark chunks dirty.
	void write(int x, int y, int z, uint8_t value);
	void try_compress(Chunk &c);

	int hardness_of(uint8_t material_id) const;

	// Marks every chunk whose mesh can see the voxel range [from, to] (inclusive) dirty, then
	// remeshes them right away if there are few enough, nearest the camera first.
	void finish_edit(const Vector3i &from, const Vector3i &to);
	void mark_dirty(int slot);
	bool chunk_needs_mesh(int slot) const;
	void build_chunk_mesh(int slot);
	Vector3 camera_position_in_voxels() const;
	void sort_by_camera_distance(std::vector<int> &slots) const;

	// Flood-fills from solid voxels next to the removed ones. Any connected piece that reaches no
	// unbreakable voxel within max_fragment_voxels is floating: it is removed, the edit bounds grow
	// to cover it, and it is reported through fragments_detached.
	void detach_fragments(const std::vector<Vector3i> &removed, Vector3i &edit_from, Vector3i &edit_to);

	Vector3 to_voxel_space(const Vector3 &world_position) const;
	bool box_hits_solid(int axis, int layer, int b0, int b1, int c0, int c1) const;
	bool sweep_axis(double mn[3], double mx[3], int axis, double &delta) const;

protected:
	static void _bind_methods();

public:
	VoxelWorld();
	~VoxelWorld();

	void _ready() override;
	void _process(double delta) override;

	void set_size_in_chunks(const Vector3i &value);
	Vector3i get_size_in_chunks() const { return size_in_chunks; }
	void set_voxel_size(float value);
	float get_voxel_size() const { return voxel_size; }
	void set_out_of_bounds_solid(bool value) { out_of_bounds_solid = value; }
	bool get_out_of_bounds_solid() const { return out_of_bounds_solid; }
	void set_material(const Ref<Material> &value);
	Ref<Material> get_material() const { return material; }
	void set_material_hardness(const PackedByteArray &value) { material_hardness = value; }
	PackedByteArray get_material_hardness() const { return material_hardness; }
	void set_remesh_budget_ms(float value) { remesh_budget_ms = value; }
	float get_remesh_budget_ms() const { return remesh_budget_ms; }
	void set_immediate_remesh_limit(int value) { immediate_remesh_limit = value; }
	int get_immediate_remesh_limit() const { return immediate_remesh_limit; }
	void set_detach_floating(bool value) { detach_floating = value; }
	bool get_detach_floating() const { return detach_floating; }
	void set_max_fragment_voxels(int value) { max_fragment_voxels = MAX(1, value); }
	int get_max_fragment_voxels() const { return max_fragment_voxels; }

	Vector3i get_size_in_voxels() const { return size_in_chunks * voxel::CHUNK_SIZE; }
	Vector3i world_to_voxel(const Vector3 &world_position) const;
	Vector3 voxel_to_world(const Vector3i &voxel) const;

	int get_voxel(const Vector3i &voxel) const;
	void set_voxel(const Vector3i &voxel, int material_id);

	void fill_all(int material_id);
	// Voxel-space box, from inclusive, to exclusive.
	int fill_box(const Vector3i &from, const Vector3i &to, int material_id, bool only_air);
	int fill_sphere(const Vector3 &center, float radius, int material_id, bool only_air);
	// Removes voxels whose hardness <= max_hardness. Returns {material_id: voxels_removed}.
	Dictionary carve_sphere(const Vector3 &center, float radius, int max_hardness);

	// Model voxels are indexed x + y * size.x + z * size.x * size.y; 0 entries are skipped.
	// stamp writes the model at origin (voxel space) and returns how many voxels changed.
	int stamp(const Vector3i &origin, const Vector3i &size, const PackedByteArray &voxels, bool only_air);
	// Returns {free: model voxels over air, supported: model voxels touching or overlapping existing
	// solid voxels}, so callers can reject pieces that would float or place nothing.
	Dictionary check_stamp(const Vector3i &origin, const Vector3i &size, const PackedByteArray &voxels) const;

	// Voxel DDA. Returns {hit, position, normal, voxel, material, distance}; hit is false on a miss.
	Dictionary raycast(const Vector3 &origin, const Vector3 &direction, float max_distance) const;

	// Moves an axis-aligned box standing on `feet` (bottom center) through the voxels, sliding along
	// walls and stepping up ledges up to step_height when allow_step is set.
	// Returns {position, on_floor, hit_ceiling, hit_wall, step_up}.
	Dictionary move_box(const Vector3 &feet, const Vector3 &box_size, const Vector3 &motion, float step_height, bool allow_step) const;
	bool box_overlaps_solid(const AABB &box) const;

	void remesh_all_now();
	Dictionary get_stats() const;
};

} // namespace godot
