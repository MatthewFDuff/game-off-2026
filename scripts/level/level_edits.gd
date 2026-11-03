class_name LevelEdits
extends Node
## Co-op level editing. Everyone calls the same API; requests go to the host, which applies them
## (voxels through WorldSync, objects through _object_set), replays them to every peer, and keeps
## each person's own undo / redo history. Undo is per person but, like any edit, shared.

## On every peer, after an object was added, changed, renamed or removed. remove_id is the id that
## went away ("" if none); object is the new state ({} if removed).
signal object_set(remove_id: String, object: Dictionary)

const MAX_HISTORY := 100
## Voxel edits bigger than this aren't recorded for undo (two copies of the box would be kept).
const MAX_UNDO_VOXELS := 8_000_000

@export var lab: Lab

## Host only. peer id -> Array of groups; a group is an Array of records:
##   {type = "voxels", from, to, before, after}   {type = "object", before, after}
var _history := {}
var _redo := {}
## peer id -> the group being collected between begin_group and end_group.
var _open := {}


# --- API (any peer) ------------------------------------------------------------------------------

## An operation for WorldSync._apply_op (box, room, sphere, replace).
func voxel_op(op: Dictionary) -> void:
	_call("_do_voxel_op", [op])


## Adds or updates an object. An empty id gets a fresh one; old_id renames (or "" for a new object).
func put_object(object: Dictionary, old_id := "") -> void:
	_call("_do_put", [old_id, object])


func remove_object(id: String) -> void:
	_call("_do_put", [id, {}])


## Everything between begin_group and end_group undoes as one step (a brush stroke).
func begin_group() -> void:
	_call("_do_begin", [])


func end_group() -> void:
	_call("_do_end", [])


func undo() -> void:
	_call("_do_undo", [])


func redo() -> void:
	_call("_do_redo", [])


func _call(method: String, args: Array) -> void:
	if multiplayer.is_server():
		callv(method, [1] + args)
	else:
		_request.rpc_id(1, method, args)


@rpc("any_peer", "reliable")
func _request(method: String, args: Array) -> void:
	if multiplayer.is_server() and method in ["_do_voxel_op", "_do_put", "_do_begin", "_do_end", "_do_undo", "_do_redo"]:
		callv(method, [multiplayer.get_remote_sender_id()] + args)


# --- Host ----------------------------------------------------------------------------------------

func _do_voxel_op(peer: int, op: Dictionary) -> void:
	if lab.mode != "edit" or not op.get("type", "") in ["box", "room", "sphere", "replace"]:
		return
	var bounds := WorldSync.op_bounds(op)
	var size: Vector3i = lab.world.get_size_in_voxels()
	var from: Vector3i = bounds[0].clamp(Vector3i.ZERO, size)
	var to: Vector3i = bounds[1].clamp(Vector3i.ZERO, size)
	var extent := to - from
	if extent.x <= 0 or extent.y <= 0 or extent.z <= 0:
		return
	var undoable := extent.x * extent.y * extent.z <= MAX_UNDO_VOXELS
	var before: PackedByteArray = lab.world.get_box(from, to) if undoable else PackedByteArray()
	lab.world_sync.apply_op(op)
	if undoable:
		_record(peer, {type = "voxels", from = from, to = to, before = before, after = lab.world.get_box(from, to)})
	else:
		lab.notify_peer(peer, "That edit was too big to undo")


func _do_put(peer: int, old_id: String, object: Dictionary) -> void:
	if lab.mode != "edit":
		return
	var level: LevelData = lab.level
	var before: Dictionary = level.objects.get(old_id, {})
	if old_id != "" and before.is_empty():
		return # Someone else already removed or renamed it.
	var after := object.duplicate(true)
	if not after.is_empty():
		var id: String = after.get("id", "")
		if id == "" or (id != old_id and level.objects.has(id)):
			after.id = level.new_id(after.get("type", after.kind))
	_transition(before, after)
	_record(peer, {type = "object", before = before, after = after})


func _do_begin(peer: int) -> void:
	_open[peer] = []


func _do_end(peer: int) -> void:
	var group: Array = _open.get(peer, [])
	_open.erase(peer)
	if not group.is_empty():
		_push(peer, group)


func _do_undo(peer: int) -> void:
	_do_end(peer)
	var history: Array = _history.get(peer, [])
	if history.is_empty():
		lab.notify_peer(peer, "Nothing to undo")
		return
	var group: Array = history.pop_back()
	for i in range(group.size() - 1, -1, -1):
		_revert(group[i], true)
	_redo.get_or_add(peer, []).append(group)


func _do_redo(peer: int) -> void:
	var redo: Array = _redo.get(peer, [])
	if redo.is_empty():
		lab.notify_peer(peer, "Nothing to redo")
		return
	var group: Array = redo.pop_back()
	for record in group:
		_revert(record, false)
	_history.get_or_add(peer, []).append(group)


func _revert(record: Dictionary, undo: bool) -> void:
	if record.type == "voxels":
		lab.world_sync.set_box(record.from, record.to, record.before if undo else record.after)
	elif undo:
		_transition(record.after, record.before)
	else:
		_transition(record.before, record.after)


func _record(peer: int, record: Dictionary) -> void:
	_redo.erase(peer)
	if _open.has(peer):
		_open[peer].append(record)
	else:
		_push(peer, [record])


func _push(peer: int, group: Array) -> void:
	var history: Array = _history.get_or_add(peer, [])
	history.append(group)
	if history.size() > MAX_HISTORY:
		history.pop_front()


## Host: object state from -> to, on every peer.
func _transition(from: Dictionary, to: Dictionary) -> void:
	var remove_id: String = from.get("id", "")
	_object_set(remove_id, to)
	# Same peers, same ordered channel as voxel edits: a joiner gets the level first, then these.
	for peer_id in lab.world_sync.synced_peers():
		_object_set.rpc_id(peer_id, remove_id, to)


@rpc("authority", "reliable")
func _object_set(remove_id: String, object: Dictionary) -> void:
	var level: LevelData = lab.level
	if remove_id != "":
		level.objects.erase(remove_id)
	if not object.is_empty():
		level.objects[object.id] = object
	object_set.emit(remove_id, object)
