class_name WorldSync
extends Node
## Keeps every peer's voxel world identical. Gameplay asks this node for edits instead of calling
## VoxelWorld directly: the host applies each edit, then replays it on every peer in the level in
## the same order, and the edits are deterministic, so the worlds never drift. Peers that join get
## a compressed snapshot first.

## Every peer, after a carve lands in its world, for debris and sound.
signal carved(center: Vector3, normal: Vector3, removed: Dictionary)
## A joining peer's world now matches the host's.
signal snapshot_applied

## Snapshot bytes per RPC. Reliable RPCs of ~48 KB were silently never delivered over ENet in
## testing, while 4 KB parts arrive fine, so keep these small.
const PART_SIZE := 4000
## Requests from peers are clamped to this so a bad packet can't carve out the whole level.
const MAX_CARVE_RADIUS := 3.0

@export var world: VoxelWorld

## Host: peers that have a snapshot and receive edits.
var _synced: Array[int] = []
var _incoming := PackedByteArray()
var _incoming_raw_size := 0
var _incoming_parts := 0
var _received_parts := 0


func _ready() -> void:
	multiplayer.peer_disconnected.connect(func(peer_id: int) -> void: _synced.erase(peer_id))


## Carves a sphere everywhere. normal is the surface the hit came from, for debris.
func carve_sphere(center: Vector3, radius: float, max_hardness: int, normal := Vector3.UP) -> void:
	if multiplayer.is_server():
		_apply_carve(center, radius, max_hardness, normal)
		for peer_id in _synced:
			_apply_carve.rpc_id(peer_id, center, radius, max_hardness, normal)
	else:
		_request_carve.rpc_id(1, center, radius, max_hardness, normal)


## Host: sends the current world to a peer and starts replaying edits to it.
func send_snapshot(peer_id: int) -> void:
	var raw: PackedByteArray = world.get_data()
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var parts := ceili(packed.size() / float(PART_SIZE))
	_snapshot_begin.rpc_id(peer_id, raw.size(), parts)
	for i in parts:
		_snapshot_part.rpc_id(peer_id, packed.slice(i * PART_SIZE, (i + 1) * PART_SIZE))
	# Edits from here on are sent after the snapshot on the same ordered channel.
	if peer_id not in _synced:
		_synced.append(peer_id)
	print("sent world snapshot to %d: %d KB in %d parts" % [peer_id, packed.size() / 1024, parts])


@rpc("any_peer", "reliable")
func _request_carve(center: Vector3, radius: float, max_hardness: int, normal: Vector3) -> void:
	if multiplayer.is_server():
		carve_sphere(center, minf(radius, MAX_CARVE_RADIUS), max_hardness, normal)


@rpc("authority", "reliable")
func _apply_carve(center: Vector3, radius: float, max_hardness: int, normal: Vector3) -> void:
	var removed: Dictionary = world.carve_sphere(center, radius, max_hardness)
	if not removed.is_empty():
		carved.emit(center, normal, removed)


@rpc("authority", "reliable")
func _snapshot_begin(raw_size: int, parts: int) -> void:
	_incoming = PackedByteArray()
	_incoming_raw_size = raw_size
	_incoming_parts = parts
	_received_parts = 0
	if parts == 0:
		_finish_snapshot()


@rpc("authority", "reliable")
func _snapshot_part(bytes: PackedByteArray) -> void:
	_incoming.append_array(bytes)
	_received_parts += 1
	if _received_parts == _incoming_parts:
		_finish_snapshot()


func _finish_snapshot() -> void:
	var raw := _incoming.decompress(_incoming_raw_size, FileAccess.COMPRESSION_ZSTD)
	_incoming = PackedByteArray()
	if not world.set_data(raw):
		push_error("world snapshot was invalid")
		Net.leave("Couldn't load the host's world.")
		return
	world.remesh_all_now()
	snapshot_applied.emit()
