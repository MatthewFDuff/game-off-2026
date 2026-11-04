#pragma once

#include "voxel_mesher.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <cstdint>
#include <vector>

namespace voxel {

// Dictionary keys and shader parameter names, made once (StringName construction hashes the
// string). Created on first use, freed when the extension unloads (free_keys from register_types).
struct Keys {
	godot::StringName hit = "hit";
	godot::StringName position = "position";
	godot::StringName normal = "normal";
	godot::StringName voxel = "voxel";
	godot::StringName material = "material";
	godot::StringName distance = "distance";
	godot::StringName on_floor = "on_floor";
	godot::StringName hit_ceiling = "hit_ceiling";
	godot::StringName hit_wall = "hit_wall";
	godot::StringName step_up = "step_up";
	godot::StringName valid = "valid";
	godot::StringName at_target = "at_target";
	godot::StringName breach = "breach";
	godot::StringName next = "next";
	godot::StringName voxels_changed = "voxels_changed";
	godot::StringName cut_height = "cut_height";
	godot::StringName walls_down_dir = "walls_down_dir";
	godot::StringName walls_down_height = "walls_down_height";
};
const Keys &keys();
void free_keys();

} // namespace voxel

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
		// Dirty from an edit since the last flush (in pending_edits).
		bool pending = false;
		// Written since load (set_data / fill_all) or clear_changed_chunks().
		bool changed = false;
		MeshInstance3D *mesh_instance = nullptr;
		// Reused across rebuilds: only its surface is replaced.
		Ref<ArrayMesh> mesh;
		int triangle_count = 0;
	};

	Vector3i size_in_chunks = Vector3i(20, 5, 20);
	float voxel_size = 0.1f;
	bool out_of_bounds_solid = true;
	Ref<Material> material;
	PackedByteArray material_hardness;
	float remesh_budget_ms = 4.0f;
	// Of the chunks edits dirtied since the last flush, how many (nearest the camera first) are
	// rebuilt in the flush before the frame is drawn; the rest go through the budgeted queue.
	int immediate_remesh_limit = 3;
	// 0: swap the terrain material between the play and editor shaders by its cutaway uniforms;
	// 1: always the play shader; 2: always the editor shader. See update_terrain_shader.
	int terrain_shader_mode = 0;
	bool terrain_shaders_loaded = false;
	Ref<Shader> play_shader;
	Ref<Shader> editor_shader;
	bool frame_hook_connected = false;
	bool detach_floating = true;
	int max_fragment_voxels = 6000;

	// --- Navigation (voxel_world_nav.cpp) ---
	// The world is split into NAV_COLUMN x NAV_COLUMN voxel columns. For every column and voxel
	// height we keep how many of its voxels are solid, and how many of those enemies can't dig
	// through. Writes update the counts incrementally, so finding floors never rescans voxels.
	static constexpr int NAV_COLUMN = 4;
	static constexpr int NAV_COLUMN_AREA = NAV_COLUMN * NAV_COLUMN;
	static constexpr int NAV_MAX_SPANS = 6;
	int nav_breach_hardness = 2;
	int nav_breach_cost = 60;
	int nav_clearance = 12; // Voxels of headroom an enemy needs.
	int nav_step = 5; // Highest ledge an enemy can step up, in voxels.
	int nav_max_drop = 40; // Deepest drop an enemy will walk off, in voxels.

	int nav_columns_x = 0;
	int nav_columns_z = 0;
	int nav_height = 0;
	std::vector<uint8_t> nav_solid; // [column * nav_height + y]
	std::vector<uint8_t> nav_hard; // Solid voxels harder than nav_breach_hardness.
	std::vector<uint8_t> nav_column_dirty;
	bool nav_hardness_stale = false;
	// Walkable floors per column: the voxel height an enemy's feet rest at, and whether reaching it
	// means digging through soft voxels (a barricade) above it.
	std::vector<int16_t> nav_span_height; // [column * NAV_MAX_SPANS + k]
	std::vector<uint8_t> nav_span_breach;
	std::vector<uint8_t> nav_span_count;
	std::vector<uint32_t> nav_flow; // Path cost to the nearest flow target per span, UINT32_MAX if unreached.
	int nav_flow_target = -1; // A span under one of the targets, or -1 when the field is empty.
	double last_flow_usec = 0.0;
	int last_flow_reached = 0;
	// update_flow_field skips the search when the target nodes and range are the same as last time
	// and no nav column changed. Anything else that changes costs sets nav_flow_stale.
	bool nav_flow_stale = true;
	std::vector<int> last_flow_nodes;
	float last_flow_max_distance = -1.0f;
	int flow_rebuilds = 0;
	int flow_skips = 0;

	std::vector<Chunk> chunks;
	std::vector<int> dirty_queue;
	// Chunks dirtied by edits since the last flush, for flush_pending.
	std::vector<int> pending_edits;
	// Per chunk: touch_epoch when last added to a touched list (dedupe without a set).
	std::vector<uint32_t> touch_mark;
	uint32_t touch_epoch = 0;
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

	// Marks every chunk whose mesh can see the voxel range [from, to] (inclusive) dirty and pending
	// (built in the next flush, see flush_pending), then emits voxels_changed(from, to).
	void finish_edit(const Vector3i &from, const Vector3i &to);
	// Starts a touched list: adds the chunks whose meshes can see [from, to] (one voxel out) once.
	void begin_touch();
	void touch_range(const Vector3i &from, const Vector3i &to, std::vector<int> &touched);
	// Compresses, marks dirty and pending every touched chunk.
	void commit_touched(const std::vector<int> &touched);
	// voxels_changed once per chunk holding any of points, with the bounds of the points in it.
	void emit_per_chunk(const std::vector<Vector3i> &points);
	void mark_dirty(int slot);
	void mark_pending(int slot);
	// Builds up to max_chunks of the pending chunks (nearest the camera first; < 0: all). The rest
	// stay in dirty_queue for _process. Returns how many were built.
	int flush_pending(int max_chunks);
	void on_frame_pre_draw();
	void update_terrain_shader();
	bool chunk_needs_mesh(int slot) const;
	// True when every voxel in the chunk is solid (uniform solid, or expanded with no air).
	bool chunk_fully_solid(int slot) const;
	Ref<ArrayMesh> arrays_to_mesh(const voxel::MeshBuffers &buffers) const;
	// Replaces mesh's surfaces with the buffers (none when they are empty).
	void fill_mesh(const Ref<ArrayMesh> &mesh, const voxel::MeshBuffers &buffers) const;
	void build_host_table(const PackedByteArray &hosts, bool table[256]) const;
	// The chunk plus its one-voxel apron into padded, a row at a time.
	void copy_padded(int slot);
	void build_chunk_mesh(int slot);
	Vector3 camera_position_in_voxels() const;
	void sort_by_camera_distance(std::vector<int> &slots) const;

	// Flood-fills from solid voxels next to the removed ones. Any connected piece that reaches no
	// unbreakable voxel within max_fragment_voxels is floating: it is removed, the edit bounds grow
	// to cover it, and it is reported through fragments_detached.
	// detached, when given, gets every voxel removed this way.
	void detach_fragments(const std::vector<Vector3i> &removed, Vector3i &edit_from, Vector3i &edit_to, std::vector<Vector3i> *detached = nullptr);
	// Shared tail of the carve functions: detach loose pieces, remesh, and report counts.
	Dictionary finish_carve(const int removed[256], const std::vector<Vector3i> &removed_voxels, const Vector3i &from, const Vector3i &to);

	void nav_allocate();
	inline void nav_on_write(int x, int y, int z, uint8_t old_value, uint8_t new_value) {
		const int column = (z / NAV_COLUMN) * nav_columns_x + (x / NAV_COLUMN);
		const int i = column * nav_height + y;
		nav_solid[i] += int(new_value != 0) - int(old_value != 0);
		nav_hard[i] += int(nav_is_hard(new_value)) - int(nav_is_hard(old_value));
		nav_column_dirty[column] = 1;
	}
	inline bool nav_is_hard(uint8_t m) const { return m != 0 && hardness_of(m) > nav_breach_hardness; }
	void nav_rebuild_chunk(int slot);
	void nav_rebuild_spans(int column);
	// The span an agent with feet at voxel height y in this column stands on (or will land on).
	int nav_find_span(int column, int y) const;
	bool nav_has_span_near(int column, int height, int tolerance) const;
	// Movement cost from span (cu, ku) to the adjacent span (cv, kv), or 0 if the move isn't possible.
	uint32_t nav_move_cost(int cu, int ku, int cv, int kv, int dx, int dz) const;
	Vector3 nav_span_world(int column, int k) const;
	// The span node under a world position (looking a couple of columns out if it is mid-air), or -1.
	int nav_target_node(const Vector3 &target) const;

	Vector3 to_voxel_space(const Vector3 &world_position) const;
	bool box_hits_solid(int axis, int layer, int b0, int b1, int c0, int c1) const;
	bool sweep_axis(double mn[3], double mx[3], int axis, double &delta) const;

protected:
	static void _bind_methods();

public:
	VoxelWorld();
	~VoxelWorld();

	void _ready() override;
	void _enter_tree() override;
	void _exit_tree() override;
	void _process(double delta) override;

	void set_size_in_chunks(const Vector3i &value);
	Vector3i get_size_in_chunks() const { return size_in_chunks; }
	void set_voxel_size(float value);
	float get_voxel_size() const { return voxel_size; }
	void set_out_of_bounds_solid(bool value) { out_of_bounds_solid = value; }
	bool get_out_of_bounds_solid() const { return out_of_bounds_solid; }
	void set_material(const Ref<Material> &value);
	Ref<Material> get_material() const { return material; }
	void set_material_hardness(const PackedByteArray &value) {
		if (value == material_hardness) {
			return;
		}
		material_hardness = value;
		nav_hardness_stale = true;
	}
	void set_terrain_shader_mode(int value) { terrain_shader_mode = CLAMP(value, 0, 2); }
	int get_terrain_shader_mode() const { return terrain_shader_mode; }
	void set_play_shader(const Ref<Shader> &value) {
		play_shader = value;
		terrain_shaders_loaded = false;
	}
	Ref<Shader> get_play_shader() const { return play_shader; }
	void set_editor_shader(const Ref<Shader> &value) {
		editor_shader = value;
		terrain_shaders_loaded = false;
	}
	Ref<Shader> get_editor_shader() const { return editor_shader; }
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
	// The whole volume as bytes: "VXW1", size_in_chunks (3 x int32), then per chunk a 0 byte and its
	// uniform material, or a 1 byte and CHUNK_VOLUME materials. set_data resizes the world to match
	// and returns false (leaving the world alone) if the bytes aren't valid.
	PackedByteArray get_data() const;
	bool set_data(const PackedByteArray &data);
	// Chunk slots (cx + cz * size.x + cy * size.x * size.z) written since the last set_data /
	// fill_all / resize, or since clear_changed_chunks(), ascending. For delta saves and snapshots.
	PackedInt32Array get_changed_chunks() const;
	void clear_changed_chunks();
	// CHUNK_VOLUME (32768) raw bytes per slot, concatenated in the order given (uniform chunks
	// expanded; indexed x + z * 32 + y * 1024). Empty on a bad slot.
	PackedByteArray get_chunks_data(const PackedInt32Array &slots) const;
	// Writes get_chunks_data's bytes back to those slots: compresses uniform chunks, rebuilds their
	// nav, marks them (and the neighbours whose faces they touch) for remeshing, marks them changed,
	// and emits voxels_changed once per chunk. Returns false (writing nothing) on bad input.
	bool set_chunks_data(const PackedInt32Array &slots, const PackedByteArray &data);
	// Voxel-space box, from inclusive, to exclusive.
	int fill_box(const Vector3i &from, const Vector3i &to, int material_id, bool only_air);
	int fill_sphere(const Vector3 &center, float radius, int material_id, bool only_air);
	// Removes voxels whose hardness <= max_hardness. Returns {material_id: voxels_removed}.
	Dictionary carve_sphere(const Vector3 &center, float radius, int max_hardness);
	// carve_sphere at every center in turn (a shotgun's pellets) as one edit: one loose-piece pass
	// over everything removed, voxels_changed once per touched chunk, one remesh per chunk.
	// Returns one {material_id: voxels_removed} per center, in order (empty where it hit nothing;
	// a voxel two spheres share counts for the first).
	Array carve_spheres(const PackedVector3Array &centers, float radius, int max_hardness);
	// Same as carve_sphere, for every voxel whose center lies inside the world-space box.
	Dictionary carve_box(const AABB &box, int max_hardness);

	// Swaps voxels for material, but only where the current material is in hosts (any solid voxel
	// when hosts is empty). Returns how many changed. Box is voxel space, from inclusive, to exclusive.
	int replace_in_box(const Vector3i &from, const Vector3i &to, int material_id, const PackedByteArray &hosts);
	int replace_in_sphere(const Vector3 &center, float radius, int material_id, const PackedByteArray &hosts);

	// Many single voxels in one edit (fire): points holds x, y, z per voxel and materials one id
	// each. Voxels turned to air drop any loose pieces, like a carve. Only the chunks around the
	// points are remeshed, however far apart they are, and voxels_changed is emitted once per chunk
	// written (see the signal). Returns {material_id: voxels_removed}.
	Dictionary set_voxels(const PackedInt32Array &points, const PackedByteArray &materials);
	// Voxels inside the sphere whose material is in hosts, as x, y, z per voxel, nearest the center
	// first, at most max_count. exposed_only keeps those with air on at least one face.
	PackedInt32Array find_in_sphere(const Vector3 &center, float radius, const PackedByteArray &hosts, bool exposed_only, int max_count) const;

	// Fills the voxel box with horizontal layers. materials[k] fills up to height tops[k] (voxel y,
	// bottom layer first); voxels above the last top are left alone. Each boundary undulates by up
	// to `undulation` voxels following smooth noise with the given wavelength (in voxels).
	void fill_layers(const Vector3i &from, const Vector3i &to, const PackedByteArray &materials, const PackedFloat32Array &tops, float undulation, float wavelength, int seed);

	// Meshes a standalone voxel model (each side at most 256) with the same format as the world's
	// chunks, so it can use the world's material. Vertices start at the model's corner.
	Ref<ArrayMesh> build_model_mesh(const Vector3i &size, const PackedByteArray &voxels);

	// Model voxels are indexed x + y * size.x + z * size.x * size.y; 0 entries are skipped.
	// stamp writes the model at origin (voxel space) and returns how many voxels changed.
	int stamp(const Vector3i &origin, const Vector3i &size, const PackedByteArray &voxels, bool only_air);
	// Undoes a stamp: turns to air every voxel where the model has a voxel and the world still has
	// that same material, so damage and anything built over it since are left alone.
	int erase_stamp(const Vector3i &origin, const Vector3i &size, const PackedByteArray &voxels);
	// Every voxel in the box (from inclusive, to exclusive), indexed like stamp models; outside the
	// world reads as air. set_box writes them all back (air included), for undo and restores.
	PackedByteArray get_box(const Vector3i &from, const Vector3i &to) const;
	int set_box(const Vector3i &from, const Vector3i &to, const PackedByteArray &voxels);
	// Level editor rooms (see WorldSync's "structure" op). Rooms are 10 ints each, oldest first:
	// interior from (x, y, z), interior to (x, y, z, exclusive), floor, wall, ceiling, thickness;
	// openings 6 ints each (from, to). Each cell of [from, to) gets a role before and after: in an
	// opening -> air; in a room's interior -> air; in a room's lining -> that room's floor / wall /
	// ceiling (the newest room wins); else outside -> `base`. A cell whose role or material changes is
	// rewritten when it still holds what it was (outside: any material in `base_set`), and always when
	// it becomes an opening or a room's inside (a new room, or a wall that moved away) or leaves every
	// room. So hand detail on walls that stay walls survives a resize or a new lining, and a new
	// room's lining doesn't wall up spaces carved by hand. Returns how many voxels changed.
	// before_build / after_build are build mode's walls, slabs and wall openings (LevelBuild.pack):
	// wall openings are openings; walls and slabs are linings (the later one wins, and over rooms').
	int apply_structure(const Vector3i &from, const Vector3i &to, const PackedInt32Array &before_rooms, const PackedInt32Array &after_rooms,
			const PackedInt32Array &before_openings, const PackedInt32Array &after_openings, int base, const PackedByteArray &base_set,
			const PackedInt32Array &before_build, const PackedInt32Array &after_build);
	// How many of the model's solid voxels the world still has, unchanged, at origin.
	int count_matching(const Vector3i &origin, const Vector3i &size, const PackedByteArray &voxels) const;
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

	void set_nav_breach_hardness(int value) {
		nav_breach_hardness = value;
		nav_hardness_stale = true;
	}
	int get_nav_breach_hardness() const { return nav_breach_hardness; }
	void set_nav_breach_cost(int value) {
		if (MAX(0, value) != nav_breach_cost) {
			nav_flow_stale = true;
		}
		nav_breach_cost = MAX(0, value);
	}
	// Spans the last flow field reached (the same as get_stats().flow_reached).
	int get_flow_reached() const { return last_flow_reached; }
	int get_nav_breach_cost() const { return nav_breach_cost; }

	// Rebuilds the path costs from every walkable floor within max_distance (meters of walking) to
	// the floor under the nearest target. targets is one Vector3, or an Array / PackedVector3Array
	// of them (multi-source Dijkstra: one field leads every agent to whichever target is closest).
	// Cheap enough to call a few times a second. When the targets stand on the same floor cells as
	// last call, max_distance is the same and no voxel under any nav column changed, the field is
	// kept as it is and the search is skipped.
	void update_flow_field(const Variant &targets, float max_distance);
	// Next step for an agent standing at feet. Returns {valid, next: Vector3 (world feet position of
	// the next floor cell), distance: float (meters to target), breach: bool (next cell is through a
	// barricade), at_target: bool (standing on a target's floor)}. valid is false when the agent isn't on a floor reached by the field.
	Dictionary get_flow(const Vector3 &feet) const;

	// Builds every dirty chunk now (load, snapshots).
	void remesh_all_now();
	// Builds the chunks edits dirtied since the last flush now, nearest the camera first; at most
	// max_chunks of them when >= 0. Edits otherwise only mark chunks, and the world builds them
	// once per frame (before drawing, immediate_remesh_limit of them, the rest over frames).
	int flush_edits(int max_chunks);
	Dictionary get_stats() const;
};

} // namespace godot
