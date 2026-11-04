class_name WorldSync
extends Node
## Keeps every peer's voxel world identical. Gameplay and the editor ask this node for edits instead
## of calling VoxelWorld directly: the host applies each edit, then replays it on every peer in the
## level in the same order, and the edits are deterministic, so the worlds never drift.
##
## Also carries big payloads (world snapshots, level files) to peers in small pieces: reliable RPCs
## of ~48 KB were silently never delivered over ENet in testing, while 4 KB pieces arrive fine.

## Every peer, after a carve lands in its world, for debris and sound.
signal carved(center: Vector3, normal: Vector3, removed: Dictionary)
## Every peer, after a set_voxels batch lands in its world (Fire keeps its burning set with it).
signal voxels_set(points: PackedInt32Array, materials: PackedByteArray, removed: Dictionary)
## This peer's world was replaced by a snapshot from the host.
signal snapshot_applied
## A blob sent with send_blob arrived whole (tags other than "world", which is applied directly).
signal blob_received(tag: String, bytes: PackedByteArray)

## Bytes per RPC for blobs and sliced edits.
const PART_SIZE := 4000
## Requests from peers are clamped to this so a bad packet can't carve out the whole level.
const MAX_CARVE_RADIUS := 3.0
## ...and to this hardness: the strongest weapon's blast_power (explosive), so a peer can't dig bedrock.
const MAX_CARVE_POWER := 6
## Voxels per set_voxels RPC (13 bytes each, so a part stays near PART_SIZE).
const SET_PART := 300

@export var world: VoxelWorld

## Every peer: the radius (meters) of the carve a `carved` signal is about, for listeners that care
## how big the hit was (Glass: a blast shatters tempered glass at once).
var last_carve_radius := 0.0
## Host: peers that have the world and receive edits.
var _synced: Array[int] = []
## Blobs being received: tag -> {raw_size, parts, received, bytes}
var _incoming := {}


func _ready() -> void:
	multiplayer.peer_disconnected.connect(func(peer_id: int) -> void: _synced.erase(peer_id))


## Host: peers that have the world and get every edit.
func synced_peers() -> Array[int]:
	return _synced


# --- Gameplay edits ------------------------------------------------------------------------------

## Carves a sphere everywhere. normal is the surface the hit came from, for debris.
func carve_sphere(center: Vector3, radius: float, max_hardness: int, normal := Vector3.UP) -> void:
	if multiplayer.is_server():
		_apply_carve(center, radius, max_hardness, normal)
		for peer_id in _synced:
			_apply_carve.rpc_id(peer_id, center, radius, max_hardness, normal)
	else:
		_request_carve.rpc_id(1, center, radius, max_hardness, normal)


## Only from a peer that has the world (so the carve lands on both sides), within the caps.
@rpc("any_peer", "reliable")
func _request_carve(center: Vector3, radius: float, max_hardness: int, normal: Vector3) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() not in _synced:
		return
	if not center.is_finite() or not is_finite(radius) or not normal.is_finite():
		return
	carve_sphere(center, minf(radius, MAX_CARVE_RADIUS), mini(max_hardness, MAX_CARVE_POWER), normal)


@rpc("authority", "reliable")
func _apply_carve(center: Vector3, radius: float, max_hardness: int, normal: Vector3) -> void:
	var removed: Dictionary = world.carve_sphere(center, radius, max_hardness)
	if not removed.is_empty():
		last_carve_radius = radius
		carved.emit(center, normal, removed)


# --- Host edits ----------------------------------------------------------------------------------

## Host: stamps a model (see VoxelWorld.stamp) everywhere, or with erase, takes one away (see
## VoxelWorld.erase_stamp).
func stamp_model(origin: Vector3i, size: Vector3i, voxels: PackedByteArray, erase := false) -> void:
	_sliced(origin, size, voxels, 1 if erase else 0)


## Host: writes a whole box everywhere, air included (undo, restores).
func set_box(from: Vector3i, to: Vector3i, voxels: PackedByteArray) -> void:
	_sliced(from, to - from, voxels, 2)


## Host: turns every voxel of the sources materials inside a sphere (world space, meters) into
## material, everywhere (fire clouds burning shroom voxels away to air).
func replace_sphere(center: Vector3, radius: float, material: int, sources: PackedByteArray) -> void:
	if not multiplayer.is_server():
		push_error("only the host replaces voxels")
		return
	_apply_replace_sphere(center, radius, material, sources)
	for peer_id in _synced:
		_apply_replace_sphere.rpc_id(peer_id, center, radius, material, sources)


@rpc("authority", "reliable")
func _apply_replace_sphere(center: Vector3, radius: float, material: int, sources: PackedByteArray) -> void:
	world.replace_in_sphere(center, minf(radius, MAX_CARVE_RADIUS), material, sources)


## Host: sets many single voxels everywhere (points: x, y, z per voxel; one material each), in
## parts of SET_PART voxels. Voxels set to air drop loose pieces like a carve (fire).
func set_voxels(points: PackedInt32Array, materials: PackedByteArray) -> void:
	if not multiplayer.is_server():
		push_error("only the host sets voxels")
		return
	for start in range(0, materials.size(), SET_PART):
		var part_points := points.slice(start * 3, (start + SET_PART) * 3)
		var part_materials := materials.slice(start, start + SET_PART)
		_apply_set_voxels(part_points, part_materials)
		for peer_id in _synced:
			_apply_set_voxels.rpc_id(peer_id, part_points, part_materials)


@rpc("authority", "reliable")
func _apply_set_voxels(points: PackedInt32Array, materials: PackedByteArray) -> void:
	if points.size() != materials.size() * 3:
		return
	var removed: Dictionary = world.set_voxels(points, materials)
	voxels_set.emit(points, materials, removed)


## Host: applies an editor operation (see _apply_op) everywhere.
func apply_op(op: Dictionary) -> void:
	if not multiplayer.is_server():
		push_error("only the host applies edits")
		return
	_apply_op(op)
	for peer_id in _synced:
		_apply_op.rpc_id(peer_id, op)


## The voxel box an operation can change, for undo, as [from, to).
static func op_bounds(op: Dictionary) -> Array[Vector3i]:
	match op.type:
		"room":
			var t := Vector3i.ONE * int(op.thickness)
			return [op.from - t, op.to + t]
		"sphere":
			var r := Vector3.ONE * (float(op.radius) + 1.0)
			var center: Vector3 = op.center
			return [Vector3i((center - r).floor()), Vector3i((center + r).ceil())]
		_:
			return [op.from, op.to]


## op_bounds, kept under the op's "below" layer when it has one.
static func op_bounds_below(op: Dictionary) -> Array[Vector3i]:
	var bounds := op_bounds(op)
	if op.has("below"):
		bounds[1].y = mini(bounds[1].y, int(op.below))
	return bounds


## Editor operations, all deterministic so every peer ends up the same:
##   box      {from, to, material}                 fill the box (material 0 carves)
##   room     {from, to, floor, wall, ceiling, thickness, solid_only}
##            carve the inside, line the shell. solid_only recolors only solid voxels, so openings
##            into neighbouring rooms stay open (rock levels); otherwise the shell is built (empty levels)
##   sphere   {center: Vector3, radius, material}  voxel units
##   replace  {from, to, material, source}         swap source for material inside the box
##   box, sphere and replace may also have below: layers from it up are left as they were (the
##   editor's cutaway hides them)
##   structure {from, to, before_rooms, after_rooms, before_openings, after_openings, base, base_set,
##            before_build, after_build}
##            a room / opening change over [from, to): VoxelWorld.apply_structure (LevelEdits
##            builds it from the level's room and opening objects)
@rpc("authority", "reliable")
func _apply_op(op: Dictionary) -> void:
	run_op(world, op)


## Applies an operation straight to a world (no syncing): level setup, and _apply_op on each peer.
static func run_op(world: VoxelWorld, op: Dictionary) -> void:
	if op.has("below"):
		_run_below(world, op)
		return
	match op.type:
		"box":
			world.fill_box(op.from, op.to, op.material, false)
		"room":
			var t := Vector3i.ONE * int(op.thickness)
			var outer_from: Vector3i = op.from - t
			var outer_to: Vector3i = op.to + t
			var floor_to := Vector3i(outer_to.x, op.from.y, outer_to.z)
			var ceiling_from := Vector3i(outer_from.x, op.to.y, outer_from.z)
			if op.solid_only:
				var any := PackedByteArray()
				world.replace_in_box(outer_from, outer_to, op.wall, any)
				world.replace_in_box(outer_from, floor_to, op.floor, any)
				world.replace_in_box(ceiling_from, outer_to, op.ceiling, any)
			else:
				world.fill_box(outer_from, outer_to, op.wall, false)
				world.fill_box(outer_from, floor_to, op.floor, false)
				world.fill_box(ceiling_from, outer_to, op.ceiling, false)
			world.fill_box(op.from, op.to, VoxelMaterials.AIR, false)
		"sphere":
			world.fill_sphere(world.global_position + op.center * world.voxel_size, float(op.radius) * world.voxel_size, op.material, false)
		"replace":
			world.replace_in_box(op.from, op.to, op.material, PackedByteArray([op.source]))
		"structure":
			world.apply_structure(op.from, op.to, op.before_rooms, op.after_rooms, op.before_openings, op.after_openings, op.base, op.base_set,
					op.get("before_build", PackedInt32Array()), op.get("after_build", PackedInt32Array()))


## run_op with the layers from op.below up kept as they were.
static func _run_below(world: VoxelWorld, op: Dictionary) -> void:
	var bounds := op_bounds(op)
	var size: Vector3i = world.get_size_in_voxels()
	var keep_from := Vector3i(bounds[0].x, maxi(bounds[0].y, int(op.below)), bounds[0].z).clamp(Vector3i.ZERO, size)
	var keep_to: Vector3i = bounds[1].clamp(Vector3i.ZERO, size)
	var plain := op.duplicate()
	plain.erase("below")
	if op.type in ["box", "replace"]:
		plain.to = Vector3i(op.to.x, mini(op.to.y, int(op.below)), op.to.z)
		if plain.to.y > plain.from.y:
			run_op(world, plain)
		return
	if keep_from.y >= keep_to.y or keep_from.x >= keep_to.x or keep_from.z >= keep_to.z:
		run_op(world, plain)
		return
	var kept := world.get_box(keep_from, keep_to)
	run_op(world, plain)
	world.set_box(keep_from, keep_to, kept)


## Applies a box of voxels here in one go, and sends it to the others in slices so no RPC gets near
## the size ENet drops. mode: 0 stamp, 1 erase stamp, 2 set box.
func _sliced(origin: Vector3i, size: Vector3i, voxels: PackedByteArray, mode: int) -> void:
	if not multiplayer.is_server():
		push_error("only the host writes models and boxes")
		return
	_apply_box(origin, size, voxels, mode)
	if _synced.is_empty():
		return
	var rows := clampi(PART_SIZE / size.x, 1, size.y)
	var depth := clampi(PART_SIZE / (size.x * rows), 1, size.z)
	# In more than one part, the parts only mark chunks for remeshing (it catches up over the next
	# frames): remeshing the same chunks for every thin slice of a big undo took seconds.
	var whole := rows >= size.y and depth >= size.z
	for y0 in range(0, size.y, rows):
		for z0 in range(0, size.z, depth):
			var part_size := Vector3i(size.x, mini(rows, size.y - y0), mini(depth, size.z - z0))
			# Whole rows at a time (a part is full rows of the box, in the same order).
			var part := PackedByteArray()
			for z in part_size.z:
				for y in part_size.y:
					var from := (y0 + y) * size.x + (z0 + z) * size.x * size.y
					part.append_array(voxels.slice(from, from + size.x))
			var any := mode == 2 or part.count(0) != part.size()
			if not any:
				continue
			var part_origin := origin + Vector3i(0, y0, z0)
			for peer_id in _synced:
				_apply_slice.rpc_id(peer_id, part_origin, part_size, part, mode, whole)


@rpc("authority", "reliable")
func _apply_slice(origin: Vector3i, size: Vector3i, voxels: PackedByteArray, mode: int, whole: bool) -> void:
	if whole:
		_apply_box(origin, size, voxels, mode)
		return
	var limit := world.immediate_remesh_limit
	world.immediate_remesh_limit = 0
	_apply_box(origin, size, voxels, mode)
	world.immediate_remesh_limit = limit


func _apply_box(origin: Vector3i, size: Vector3i, voxels: PackedByteArray, mode: int) -> void:
	match mode:
		0:
			world.stamp(origin, size, voxels, false)
		1:
			world.erase_stamp(origin, size, voxels)
		2:
			world.set_box(origin, origin + size, voxels)


# --- Snapshots and blobs -------------------------------------------------------------------------

## Host: sends the current world to a peer and starts replaying edits to it.
func send_snapshot(peer_id: int) -> void:
	send_blob(peer_id, "world", world.get_data())
	# Edits from here on are sent after the snapshot on the same ordered channel.
	if peer_id not in _synced:
		_synced.append(peer_id)


## Host: sends the current world to every peer that has one (after a wholesale change).
func resend_snapshots() -> void:
	if _synced.is_empty():
		return
	var data: PackedByteArray = world.get_data()
	for peer_id in _synced:
		send_blob(peer_id, "world", data)


## Host: sends bytes of any size to a peer, compressed and in parts; it arrives as blob_received
## (or, tagged "world", replaces the peer's world).
func send_blob(peer_id: int, tag: String, bytes: PackedByteArray) -> void:
	var packed := bytes.compress(FileAccess.COMPRESSION_ZSTD)
	var parts := ceili(packed.size() / float(PART_SIZE))
	_blob_begin.rpc_id(peer_id, tag, bytes.size(), parts)
	for i in parts:
		_blob_part.rpc_id(peer_id, tag, packed.slice(i * PART_SIZE, (i + 1) * PART_SIZE))


@rpc("authority", "reliable")
func _blob_begin(tag: String, raw_size: int, parts: int) -> void:
	_incoming[tag] = {raw_size = raw_size, parts = parts, received = 0, bytes = PackedByteArray()}
	if parts == 0:
		_finish_blob(tag)


@rpc("authority", "reliable")
func _blob_part(tag: String, bytes: PackedByteArray) -> void:
	var blob: Dictionary = _incoming.get(tag, {})
	if blob.is_empty():
		return
	blob.bytes.append_array(bytes)
	blob.received += 1
	if blob.received == blob.parts:
		_finish_blob(tag)


func _finish_blob(tag: String) -> void:
	var blob: Dictionary = _incoming[tag]
	_incoming.erase(tag)
	var bytes: PackedByteArray = blob.bytes
	var raw := bytes.decompress(blob.raw_size, FileAccess.COMPRESSION_ZSTD) if blob.raw_size > 0 else PackedByteArray()
	if tag != "world":
		blob_received.emit(tag, raw)
		return
	if not world.set_data(raw):
		push_error("world snapshot was invalid")
		get_node("/root/Net").leave("Couldn't load the host's world.")
		return
	world.remesh_all_now()
	snapshot_applied.emit()
