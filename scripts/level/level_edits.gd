class_name LevelEdits
extends Node
## Co-op level editing. Everyone calls the same API; requests go to the host, which applies them
## (voxels through WorldSync, objects through _object_set), replays them to every peer, and keeps
## each person's own undo / redo history. Undo is per person but, like any edit, shared.
##
## Rooms, openings and door props change through structure edits: the objects change and the voxels
## follow (WorldSync's "structure" op, built by LevelStructure), as one undo step. A door prop keeps
## an opening the size of its box linked to it (opening.door), made, moved and removed with it.

## On every peer, after an object was added, changed, renamed or removed. remove_id is the id that
## went away ("" if none); object is the new state ({} if removed).
signal object_set(remove_id: String, object: Dictionary)
## The soft locks changed (on every peer).
signal locks_changed

const MAX_HISTORY := 100
## Voxel edits bigger than this aren't recorded for undo (two copies of the box would be kept).
const MAX_UNDO_VOXELS := 8_000_000
## The most voxel bytes everyone's undo and redo history keep together (each voxel edit keeps its
## box before and after); past it the oldest steps go. Less on the web, where memory is tight.
const MAX_UNDO_BYTES := 256 * 1024 * 1024
const MAX_UNDO_BYTES_WEB := 64 * 1024 * 1024

@export var lab: Lab

## Host only. peer id -> Array of groups; a group is an Array of records:
##   {type = "voxels", from, to, before, after}   {type = "object", before, after}
var _history := {}
var _redo := {}
## peer id -> the group being collected between begin_group and end_group.
var _open := {}
## Host only. The voxel bytes held in _history and _redo, and the groups holding any, oldest first
## ({peer, group, bytes}; an entry whose group already went is skipped).
var _undo_bytes := 0
var _byte_groups: Array = []
## The cap on _undo_bytes (MAX_UNDO_BYTES, or MAX_UNDO_BYTES_WEB on the web).
var max_undo_bytes := MAX_UNDO_BYTES_WEB if OS.has_feature("web") else MAX_UNDO_BYTES
## Soft locks: object id -> the peer moving or resizing it (the host's table, on every peer). Others
## can't grab it and the host refuses their edits to it until it's let go; a peer's locks go when
## it disconnects.
var locks := {}
## Goes up on every object change, before object_set is emitted (on every peer), so a cache over
## the level's objects can tell it's behind even from inside another object_set handler.
var objects_version := 0


func _ready() -> void:
	multiplayer.peer_disconnected.connect(func(peer: int) -> void:
		if multiplayer.is_server():
			for id: String in locks.keys():
				if locks[id] == peer:
					locks.erase(id)
			_send_locks())


# --- API (any peer) ------------------------------------------------------------------------------

## An operation for WorldSync._apply_op (box, room, sphere, replace).
func voxel_op(op: Dictionary) -> void:
	_call("_do_voxel_op", [op])


## Adds or updates an object. An empty id gets a fresh one; old_id renames (or "" for a new object).
func put_object(object: Dictionary, old_id := "") -> void:
	_call("_do_put", [old_id, object])


func remove_object(id: String) -> void:
	_call("_do_put", [id, {}])


## Several objects changed together as one edit (a room resized with the openings and props that
## move with it). puts: [old_id, object] pairs as for put_object ({} removes). A string field "$n"
## in a later object stands for the id the n-th put ended up with (an opening of a new room).
func put_objects(puts: Array) -> void:
	_call("_do_puts", [puts])


## Build mode: paints (or erases) a shape (LevelBuild.shape) onto a storey's floor or ceiling
## (kind), on top of what's there; storey -1 (rock levels): onto the one at plane (voxel y). The
## host adds it to the slab as it is then, so two people painting at once both land.
func add_slab_shape(kind: String, storey: int, shape: Array, plane := 0) -> void:
	_call("_do_slab", [kind, storey, shape, plane])


## Everything between begin_group and end_group undoes as one step (a brush stroke).
func begin_group() -> void:
	_call("_do_begin", [])


func end_group() -> void:
	_call("_do_end", [])


## Holds an object while moving or resizing it (one at a time; a new lock lets go of the old).
func lock(id: String) -> void:
	_call("_do_lock", [id, true])


func unlock(id: String) -> void:
	_call("_do_lock", [id, false])


## The peer holding id's lock if it's someone else, else 0.
func locked_by_other(id: String) -> int:
	var holder: int = locks.get(id, 0)
	return holder if holder != multiplayer.get_unique_id() else 0


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
	if multiplayer.is_server() and method in ["_do_voxel_op", "_do_put", "_do_puts", "_do_slab", "_do_lock", "_do_begin", "_do_end", "_do_undo", "_do_redo"]:
		callv(method, [multiplayer.get_remote_sender_id()] + args)


# --- Host ----------------------------------------------------------------------------------------

func _do_voxel_op(peer: int, op: Dictionary) -> void:
	if lab.mode != "edit" or not op.get("type", "") in ["box", "room", "sphere", "replace"]:
		return
	var bounds := WorldSync.op_bounds_below(op)
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
	if _refuse_locked(peer, [old_id]):
		return
	var old: Dictionary = level.objects.get(old_id, {})
	if LevelSchema.is_structure(object) or LevelSchema.is_door(object) or LevelSchema.is_structure(old) or LevelSchema.is_door(old):
		_do_puts(peer, [[old_id, object]])
		return
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


func _do_slab(peer: int, kind: String, storey: int, shape: Array, plane := 0) -> void:
	if lab.mode != "edit" or not kind in ["floor", "ceiling"] or shape.size() < 3 + 3 * 2:
		return
	# Storey -1: a plane (rock levels build there, with no storeys object).
	var rock := storey < 0
	if rock and (plane < 0 or plane > lab.world.get_size_in_voxels().y):
		return
	var objects: Dictionary = lab.level.objects
	var id := LevelBuild.slab_id(kind, storey, plane)
	var puts: Array = []
	if not rock and not objects.has(LevelBuild.STOREYS_ID):
		puts.append(["", LevelBuild.storeys(objects)])
	var slab: Dictionary = objects[id].duplicate(true) if objects.has(id) else LevelBuild.new_slab(kind, storey, plane)
	slab.shapes.append(shape.map(func(v: Variant) -> int: return int(v)))
	puts.append([id if objects.has(id) else "", slab])
	_do_puts(peer, puts)


func _do_puts(peer: int, puts: Array) -> void:
	if lab.mode != "edit" or _refuse_locked(peer, puts.map(func(put: Array) -> String: return put[0])):
		return
	var level: LevelData = lab.level
	var after := level.objects.duplicate()
	var changes: Array[Dictionary] = [] # {before, after}
	var ids: Array[String] = []
	for put: Array in puts:
		var old_id: String = put[0]
		var object: Dictionary = put[1].duplicate(true)
		var before: Dictionary = after.get(old_id, {})
		if old_id != "" and before.is_empty():
			ids.append("")
			continue # Someone else already removed or renamed it.
		for key: String in object:
			var value = object[key]
			if value is String and value.begins_with("$") and value.substr(1).is_valid_int() and int(value.substr(1)) < ids.size():
				object[key] = ids[int(value.substr(1))]
		if not object.is_empty():
			var id: String = object.get("id", "")
			if id == "" or (id != old_id and after.has(id)):
				object.id = level.new_id(object.get("type", object.kind))
		after.erase(old_id)
		if not object.is_empty():
			after[object.id] = object
		changes.append({before = before, after = object})
		ids.append(object.get("id", ""))
	for change in changes.duplicate():
		if LevelSchema.is_door(change.before) or LevelSchema.is_door(change.after):
			changes.append_array(_door_openings(change.before, change.after, after))
	if changes.is_empty():
		return

	var touched: Array = []
	for change in changes:
		touched.append(change.before)
		touched.append(change.after)
	var op := LevelStructure.op(level.objects, after, touched, level.settings, lab.world.get_size_in_voxels())
	var group: Array = []
	if not op.is_empty():
		var size: Vector3i = op.to - op.from
		var undoable: bool = size.x * size.y * size.z <= MAX_UNDO_VOXELS
		var voxels_before: PackedByteArray = lab.world.get_box(op.from, op.to) if undoable else PackedByteArray()
		lab.world_sync.apply_op(op)
		if undoable:
			group.append({type = "voxels", from = op.from, to = op.to, before = voxels_before, after = lab.world.get_box(op.from, op.to)})
		else:
			lab.notify_peer(peer, "That edit was too big to undo")
	for change in changes:
		_transition(change.before, change.after)
		group.append({type = "object", before = change.before, after = change.after})
	_clear_redo(peer)
	if _open.has(peer):
		_open[peer].append_array(group)
	else:
		_push(peer, group)


## A door prop changed (door_before -> door_after, either may be {} or not a door): its linked
## openings follow it, in the room whose wall it's in: the doorway (its box, through the wall in
## front of and behind it: door_ahead / door_behind voxels along its facing) and, if it slides, the
## pocket it slides into (its box moved by door_offset), which stays hidden inside a thick enough
## wall. Updates `objects` and returns the {before, after} changes.
func _door_openings(door_before: Dictionary, door_after: Dictionary, objects: Dictionary) -> Array[Dictionary]:
	var linked := {}
	for id in [door_before.get("id", ""), door_after.get("id", "")]:
		if id == "":
			continue
		for object: Dictionary in objects.values():
			if object.kind == "opening" and object.door == id and not linked.has(object.type):
				linked[object.type] = object
	var wanted := {}
	if LevelSchema.is_door(door_after):
		var box := LevelSchema.prop_box(door_after)
		var from := Vector3i(box.position)
		var to := Vector3i(box.end)
		var front: Vector3i = PropPlacement.FACING_NORMALS[int(door_after.facing) % 4]
		var ahead: int = door_after.get("door_ahead", 0)
		var behind: int = door_after.get("door_behind", 0)
		var through_from := from
		var through_to := to
		for a in 3:
			if front[a] > 0:
				through_to[a] += ahead
				through_from[a] -= behind
			elif front[a] < 0:
				through_from[a] -= ahead
				through_to[a] += behind
		wanted["doorway"] = [through_from, through_to]
		var offset: Vector3i = door_after.get("door_offset", Vector3i.ZERO)
		if offset != Vector3i.ZERO and (ahead > 0 or behind > 0):
			wanted["slot"] = [from + offset, to + offset]
	var changes: Array[Dictionary] = []
	for type: String in ["doorway", "slot"]:
		var before: Dictionary = linked.get(type, {})
		var after := {}
		if wanted.has(type):
			var box: Array = wanted[type]
			after = before.duplicate() if not before.is_empty() else LevelSchema.new_opening(box[0], box[1], "", type)
			after.from = box[0]
			after.to = box[1]
			after.door = door_after.id
			after.room = LevelStructure.room_at(objects, LevelSchema.prop_box(door_after))
			if not after.has("id"):
				after.id = lab.level.new_id(type)
		if after == before:
			continue
		if not before.is_empty():
			objects.erase(before.id)
		if not after.is_empty():
			objects[after.id] = after
		changes.append({before = before, after = after})
	return changes


func _do_lock(peer: int, id: String, on: bool) -> void:
	if on:
		if locks.has(id) and locks[id] != peer:
			lab.notify_peer(peer, "%s is moving that" % Net.players.get(locks[id], {}).get("name", "Someone"))
			return
		for held: String in locks.keys():
			if locks[held] == peer:
				locks.erase(held)
		locks[id] = peer
	elif locks.get(id, 0) == peer:
		locks.erase(id)
	else:
		return
	_send_locks()


## Host: true (and tells the peer) if any of these ids is held by someone else.
func _refuse_locked(peer: int, ids: Array) -> bool:
	for id in ids:
		var holder: int = locks.get(id, 0)
		if holder != 0 and holder != peer:
			lab.notify_peer(peer, "%s is moving that" % Net.players.get(holder, {}).get("name", "Someone"))
			return true
	return false


func _send_locks() -> void:
	_locks_set(locks)
	for peer_id in lab.world_sync.synced_peers():
		_locks_set.rpc_id(peer_id, locks)


@rpc("authority", "reliable")
func _locks_set(table: Dictionary) -> void:
	locks = table.duplicate()
	locks_changed.emit()


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
	_clear_redo(peer)
	if _open.has(peer):
		_open[peer].append(record)
	else:
		_push(peer, [record])


func _push(peer: int, group: Array) -> void:
	var history: Array = _history.get_or_add(peer, [])
	history.append(group)
	if history.size() > MAX_HISTORY:
		_undo_bytes -= _bytes_of(history.pop_front())
	var bytes := _bytes_of(group)
	if bytes > 0:
		_undo_bytes += bytes
		_byte_groups.append({peer = peer, group = group, bytes = bytes})
		_trim_undo(group)


## The voxel bytes an undo group keeps.
static func _bytes_of(group: Array) -> int:
	var bytes := 0
	for record: Dictionary in group:
		if record.type == "voxels":
			bytes += record.before.size() + record.after.size()
	return bytes


## Drops a peer's redo steps (a new edit makes them moot).
func _clear_redo(peer: int) -> void:
	for group: Array in _redo.get(peer, []):
		_undo_bytes -= _bytes_of(group)
	_redo.erase(peer)


## Over the byte cap: drops the oldest undo (or redo) steps holding voxels, anyone's, until it fits,
## never the one just pushed (keep).
func _trim_undo(keep: Array) -> void:
	while _undo_bytes > max_undo_bytes and not _byte_groups.is_empty():
		var entry: Dictionary = _byte_groups[0]
		if is_same(entry.group, keep):
			break
		_byte_groups.pop_front()
		for stacks: Dictionary in [_history, _redo]:
			var stack: Array = stacks.get(entry.peer, [])
			var at := -1
			for i in stack.size():
				if is_same(stack[i], entry.group):
					at = i
					break
			if at >= 0:
				stack.remove_at(at)
				_undo_bytes -= entry.bytes
				break
	# Entries for groups that went another way (history full, redo cleared) pile up: prune them.
	if _byte_groups.size() > 4 * (MAX_HISTORY + 1):
		_byte_groups = _byte_groups.filter(func(entry: Dictionary) -> bool:
			return _holds(entry.peer, entry.group))


func _holds(peer: int, group: Array) -> bool:
	for stacks: Dictionary in [_history, _redo]:
		for held: Array in stacks.get(peer, []):
			if is_same(held, group):
				return true
	return false


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
	objects_version += 1
	if remove_id != "":
		level.objects.erase(remove_id)
	if not object.is_empty():
		level.objects[object.id] = object
	object_set.emit(remove_id, object)
