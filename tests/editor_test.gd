extends SceneTree
## One side of the two-process level editor test; run both with `tools/net_test.sh editor_test`.
##
## Works on a scratch copy of the lab level. The client edits (a box, an undone box, a new light, a
## moved fridge, a spore tank turned into a door) and the host checks it sees all of it, then edits
## and undoes too. Then play-testing: props are stamped, the door slides, shooting a fume hood costs
## money. Back in edit mode the world must be exactly what it was before play. Finally the host
## saves and reloads. Both sides print HASH lines (world and objects) at each stage, which must match.
##
## Game types are left untyped: naming them would compile those scripts before the autoloads they
## use are registered.

const PORT := 24698
const SCRATCH := "user://editor_test_levels/"
const LEVEL := "lab_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")

## Atrium spots that are open air in the lab.
const BOX_A := [Vector3i(220, 60, 220), Vector3i(224, 64, 224)]
const BOX_B := [Vector3i(230, 60, 230), Vector3i(234, 64, 234)]
const BOX_C := [Vector3i(240, 60, 240), Vector3i(244, 64, 244)]
const DOOR_OFFSET := Vector3i(-8, 0, 0)
## A room the client builds and resizes in solid rock high above the lab (inside), plus its doorway.
const ROOM := [Vector3i(100, 200, 100), Vector3i(130, 230, 120)]
const ROOM_GROWN := Vector3i(140, 230, 120)
## Where the client's builder camera looks (presence).
const CLIENT_PIVOT := Vector3(30.0, 4.0, 30.0)

var _failures := 0
var _port := PORT


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var role := "host"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		elif arg.begins_with("--port="):
			_port = int(arg.trim_prefix("--port="))
	LevelData.save_dir_override = SCRATCH
	var net: Node = root.get_node("Net")
	if role == "host":
		await _host(net)
	else:
		await _client(net)
	print("%s: %s" % [role.to_upper(), "PASS" if _failures == 0 else "FAIL (%d)" % _failures])
	quit(1 if _failures > 0 else 0)


func _host(net: Node) -> void:
	_copy_level()
	net.player_name = "Host"
	_check("host starts editing", net.host(_port, LEVEL, "edit") == OK)
	var lab = await _wait_for_lab()
	if lab == null:
		return
	_check("starts in edit mode", lab.mode == "edit" and lab.local_player().editing)
	print("READY")

	if not await _wait_until(func() -> bool: return lab.level.objects.has("client_done"), 120.0):
		_check("client finished its edits", false)
		return
	await _wait_seconds(0.5)
	_check("client's box arrived", _all(lab.world, BOX_A, M.METAL))
	_check("client's undone box is gone", _all(lab.world, BOX_B, M.AIR))
	_check("client's light arrived", lab.level.objects.has("client_light") and lab.level.objects.client_light.type == "light")
	var fridge := _find(lab, "fridge")
	_check("client moved the fridge", fridge.origin == Vector3i(113, 40, 226), str(fridge.get("origin")))
	var tank := _find(lab, "spore_tank", true)
	_check("client made a door", not tank.is_empty() and tank.door_offset == DOOR_OFFSET)
	var room := _find_room(lab)
	_check("client's room arrived, resized", not room.is_empty() and room.to == ROOM_GROWN, str(room))
	_check("client's room is carved here", _all(lab.world, [ROOM[0], ROOM_GROWN], M.AIR) and lab.world.get_voxel(ROOM_GROWN + Vector3i(1, -5, -5)) == M.WALL_PAINT)
	_check("client's doorway is cut", _all(lab.world, [Vector3i(110, 200, 97), Vector3i(122, 222, 100)], M.AIR))

	# Presence: the client is in the builder view, looking at CLIENT_PIVOT, holding the fridge.
	var client: Player = null
	for player: Player in lab.players.values():
		if not player.is_local:
			client = player
	var presence = client.get_node("Presence") if client else null
	await _wait_until(func() -> bool: return presence != null and presence.state.get("pivot", Vector3.ZERO).distance_to(CLIENT_PIVOT) < 0.01, 10.0)
	_check("host sees the client's builder view and camera", presence != null and presence.state.get("builder", false)
			and presence.state.get("pivot", Vector3.ZERO).distance_to(CLIENT_PIVOT) < 0.01, str(presence.state if presence else {}))
	_check("...as a camera, not a body", presence != null and presence._gizmo.visible and (client._body == null or not client._body.visible))
	_check("client holds the fridge", lab.edits.locks.get(fridge.id, 0) == client.get_multiplayer_authority())
	var shoved := fridge.duplicate()
	shoved.origin += Vector3i(5, 0, 0)
	lab.edits.put_object(shoved, fridge.id)
	_check("host can't move what the client holds", lab.level.objects[fridge.id].origin == fridge.origin)

	# Host edits and undoes its own.
	var before: PackedByteArray = lab.world.get_box(BOX_C[0], BOX_C[1])
	lab.edits.voxel_op({type = "box", from = BOX_C[0], to = BOX_C[1], material = M.GLASS})
	_check("host box applied", _all(lab.world, BOX_C, M.GLASS))
	lab.edits.undo()
	_check("host undo restores", lab.world.get_box(BOX_C[0], BOX_C[1]) == before)
	lab.edits.put_object(LevelSchema.new_marker("trigger", Vector3(250, 41, 250)).merged({id = "host_done"}))
	_check("client lets go of the fridge", await _wait_until(func() -> bool: return lab.edits.locks.is_empty(), 10.0))
	await _wait_seconds(1.0)
	var edit_world := _hash(lab.world.get_data())
	_print_hashes(lab, "edit")

	# Play-test.
	var damage := [0]
	lab.play.asset_damaged.connect(func(_id: String, dollars: int, _total: int) -> void: damage[0] += dollars)
	lab.request_mode("play")
	_check("play mode", lab.mode == "play" and not lab.local_player().editing)
	_check("fridge stamped where it was moved", _count(lab.world, Vector3i(113, 40, 226), Vector3i(120, 59, 234), M.PLASTIC) > 100)
	var tank_voxels := _count(lab.world, tank.origin, tank.origin + Vector3i(4, 10, 4), M.GLASS)
	lab.play.set_door(tank.id, true)
	await _wait_seconds(2.0)
	_check("door slid open", _count(lab.world, tank.origin, tank.origin + Vector3i(4, 10, 4), M.GLASS) == 0
			and _count(lab.world, tank.origin + DOOR_OFFSET, tank.origin + DOOR_OFFSET + Vector3i(4, 10, 4), M.GLASS) == tank_voxels, "%d glass" % tank_voxels)
	lab.world_sync.carve_sphere(Vector3(45.2, 5.0, 22.6), 1.0, 254)
	await _wait_seconds(1.0)
	_check("shooting the fume hood costs money", damage[0] > 0, "$%d" % damage[0])
	_print_hashes(lab, "play")
	await _wait_seconds(2.0)

	lab.request_mode("edit")
	_check("edit restores the pre-play world", _hash(lab.world.get_data()) == edit_world)
	await _wait_seconds(1.0)
	_print_hashes(lab, "edit again")

	lab.request_save()
	var saved = LevelData.load_level(LEVEL)
	_check("saved level reloads", saved != null)
	if saved:
		_check("saved voxels match", saved.voxels == lab.world.get_data())
		_check("saved objects match", saved.objects.size() == lab.level.objects.size(), "%d vs %d" % [saved.objects.size(), lab.level.objects.size()])
		var mismatched: Array = lab.level.objects.keys().filter(func(id: String) -> bool:
			return JSON.stringify(LevelData._encode(saved.objects.get(id, {})), "", true) != JSON.stringify(LevelData._encode(lab.level.objects[id]), "", true))
		_check("saved objects identical", mismatched.is_empty(), str(mismatched.slice(0, 3)) + (" " + str(saved.objects.get(mismatched[0])) + " vs " + str(lab.level.objects[mismatched[0]]) if not mismatched.is_empty() else ""))
	await _wait_seconds(6.0) # Stay up until the client is done.


func _client(net: Node) -> void:
	net.player_name = "Zack"
	_check("client connects", net.join("127.0.0.1", _port) == OK)
	var lab = await _wait_for_lab()
	if lab == null:
		return
	if not await _wait_until(func() -> bool: return lab.local_player() != null and lab.level != null and lab.view.mode == "edit", 60.0):
		_check("entered the editor", false)
		return
	_check("joins in edit mode", lab.mode == "edit" and lab.local_player().editing)
	_check("got the level's objects", lab.level.objects.size() > 100, str(lab.level.objects.size()))
	await _wait_until(func() -> bool: return lab.local_player().net_peers == [1], 20.0)

	lab.edits.voxel_op({type = "box", from = BOX_A[0], to = BOX_A[1], material = M.METAL})
	lab.edits.voxel_op({type = "box", from = BOX_B[0], to = BOX_B[1], material = M.STEEL})
	lab.edits.undo()
	lab.edits.put_object(LevelSchema.new_marker("light", Vector3(250, 80, 250)).merged({id = "client_light"}))
	var fridge := _find(lab, "fridge").duplicate()
	fridge.origin = Vector3i(113, 40, 226)
	lab.edits.put_object(fridge, fridge.id)
	var tank := _find(lab, "spore_tank").duplicate()
	tank.door = true
	tank.door_offset = DOOR_OFFSET
	tank.door_speed = 4.0
	lab.edits.put_object(tank, tank.id)
	# A room as an object: build it with a doorway, then grow it east in one edit.
	lab.edits.put_objects([["", LevelSchema.new_room(ROOM[0], ROOM[1], M.TILE_LIGHT, M.WALL_PAINT, M.CONCRETE, 3, 1000)],
			["", LevelSchema.new_opening(Vector3i(110, 200, 97), Vector3i(122, 222, 100), "$0")]])
	if not await _wait_until(func() -> bool: return not _find_room(lab).is_empty(), 20.0):
		_check("room came back from the host", false)
		return
	var grown := _find_room(lab).duplicate()
	grown.to = ROOM_GROWN
	lab.edits.put_object(grown, grown.id)
	# Presence and a soft lock for the host to see: look at CLIENT_PIVOT, hold the fridge.
	var camera = lab.local_player().get_node("EditorTool").camera
	camera.look_from(CLIENT_PIVOT, 0.0)
	lab.edits.lock(fridge.id)
	await _wait_seconds(0.5)
	lab.edits.put_object(LevelSchema.new_marker("trigger", Vector3(260, 41, 260)).merged({id = "client_done"}))

	if not await _wait_until(func() -> bool: return lab.level.objects.has("host_done"), 60.0):
		_check("host finished its edits", false)
		return
	lab.edits.unlock(fridge.id)
	await _wait_seconds(1.0)
	_print_hashes(lab, "edit")
	if not await _wait_until(func() -> bool: return lab.mode == "play", 30.0):
		_check("switched to play", false)
		return
	_check("play mode reached the client", not lab.local_player().editing)
	await _wait_seconds(3.0) # Door, shot, snapshot.
	_print_hashes(lab, "play")
	if not await _wait_until(func() -> bool: return lab.mode == "edit", 30.0):
		_check("switched back to edit", false)
		return
	await _wait_seconds(2.0)
	_print_hashes(lab, "edit again")


func _copy_level() -> void:
	var to := SCRATCH.path_join(LEVEL)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to))
	for file in ["level.json", "voxels.bin"]:
		FileAccess.open(to.path_join(file), FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes("res://levels/lab".path_join(file)))


## The first prop with this name (only door ones if door is set).
func _find_room(lab) -> Dictionary:
	for object: Dictionary in lab.level.objects.values():
		if object.kind == "room" and object.from == ROOM[0]:
			return object
	return {}


func _find(lab, prop_name: String, door := false) -> Dictionary:
	var ids: Array = lab.level.objects.keys()
	ids.sort()
	for id in ids:
		var object: Dictionary = lab.level.objects[id]
		if object.kind == "prop" and object.name == prop_name and (not door or object.door):
			return object
	return {}


func _print_hashes(lab, stage: String) -> void:
	print("HASH %s world %s" % [stage, _hash(lab.world.get_data())])
	var ids: Array = lab.level.objects.keys()
	ids.sort()
	var text := ""
	for id in ids:
		text += JSON.stringify(LevelData._encode(lab.level.objects[id]), "", true)
	print("HASH %s objects %s" % [stage, _hash(text.to_utf8_buffer())])


func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode().left(16)


func _all(world, box: Array, material: int) -> bool:
	var size: Vector3i = box[1] - box[0]
	return _count(world, box[0], box[1], material) == size.x * size.y * size.z


func _count(world, from: Vector3i, to: Vector3i, material: int) -> int:
	var n := 0
	for y in range(from.y, to.y):
		for z in range(from.z, to.z):
			for x in range(from.x, to.x):
				n += int(world.get_voxel(Vector3i(x, y, z)) == material)
	return n


func _wait_for_lab():
	if not await _wait_until(func() -> bool: return current_scene != null and current_scene.name == "Lab", 60.0):
		_check("level loaded", false, str(current_scene))
		return null
	return current_scene


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await process_frame
	return true


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
