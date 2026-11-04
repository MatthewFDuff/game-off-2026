extends SceneTree
## One side of the two-process build mode test; run both with `tools/net_test.sh build_net_test`.
##
## The host makes an empty level and edits it; the client joins and builds with the editor's own
## tools (WallTool, BuildTools, WallHandles, LevelEdits): a rectangle of walls with its floor and
## ceiling, a second room closed by a 45° wall, a floor filled inside it and an Auto ceiling, a
## window, a door, a free wall whose end is dragged, a taller storey, and a floor painted then
## undone. The host checks the objects and voxels it sees, and the client's selection in its
## presence. Both print HASH lines (world and objects), which must match.
##
## Game types are left untyped (see editor_test.gd).

const PORT := 24712
const SCRATCH := "user://build_net_test_levels/"
const LEVEL := "build_net_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const DOOR := "door_single"
## The starter floor's top (storey 1's floor).
const FLOOR_Y := 3

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
	var holder := Node.new()
	root.add_child(holder)
	var level = LevelData.create(LEVEL, Vector3i(8, 4, 8), "empty", holder)
	_check("host makes an empty level", level.save() == OK)
	holder.free()
	net.player_name = "Host"
	_check("host starts editing", net.host(_port, LEVEL, "edit") == OK)
	var lab = await _wait_for_lab()
	if lab == null:
		return
	print("READY")
	if not await _wait_until(func() -> bool: return lab.level.objects.has("client_done"), 120.0):
		_check("client finished building", false)
		return
	await _wait_seconds(0.5)
	var objects: Dictionary = lab.level.objects
	var world = lab.world
	var walls: Array = objects.values().filter(func(o: Dictionary) -> bool: return o.kind == "wall")
	_check("client's walls arrived", walls.size() == 9, str(walls.size()))
	_check("...one of them at 45°", walls.any(func(w: Dictionary) -> bool: return absi(w.b.x - w.a.x) == absi(w.b.z - w.a.z) and w.a != w.b))
	_check("the rectangle's walls stand", world.get_voxel(Vector3i(120, FLOOR_Y + 5, 90)) == M.WALL_PAINT and world.get_voxel(Vector3i(90, FLOOR_Y + 5, 110)) == M.WALL_PAINT)
	_check("...with its floor and ceiling", world.get_voxel(Vector3i(120, FLOOR_Y - 1, 110)) == M.TILE_LIGHT and world.get_voxel(Vector3i(120, FLOOR_Y + 40, 110)) == M.CONCRETE,
			"%d %d" % [world.get_voxel(Vector3i(120, FLOOR_Y - 1, 110)), world.get_voxel(Vector3i(120, FLOOR_Y + 40, 110))])
	_check("the second room's floor is filled", world.get_voxel(Vector3i(165, FLOOR_Y - 1, 100)) == M.METAL)
	_check("...and the Auto ceiling covers it", world.get_voxel(Vector3i(165, FLOOR_Y + 40, 100)) == M.CONCRETE)
	_check("...but not outside it", world.get_voxel(Vector3i(165, FLOOR_Y + 40, 140)) == M.AIR)
	var openings: Array = objects.values().filter(func(o: Dictionary) -> bool: return o.kind == "opening")
	var windows: Array = openings.filter(func(o: Dictionary) -> bool: return o.type == "window")
	var window_cut := false
	if windows.size() == 1 and objects.has(windows[0].wall):
		var in_wall: Dictionary = objects[windows[0].wall]
		var middle: Vector2 = Vector2(in_wall.a.x, in_wall.a.z) + LevelBuild.wall_unit(in_wall) * (int(windows[0].along) + 5)
		window_cut = world.get_voxel(Vector3i(floori(middle.x), FLOOR_Y + 15, 90)) == M.AIR and world.get_voxel(Vector3i(floori(middle.x), FLOOR_Y + 25, 90)) == M.WALL_PAINT
	_check("the window is cut", window_cut, str(windows))
	var doors: Array = objects.values().filter(func(o: Dictionary) -> bool: return o.kind == "prop" and o.name == DOOR)
	_check("the door is in its wall", doors.size() == 1 and openings.any(func(o: Dictionary) -> bool: return o.door == doors[0].id))
	_check("the dragged wall end arrived", walls.any(func(w: Dictionary) -> bool: return w.a == Vector3i(100, 0, 160) and w.b == Vector3i(150, 0, 160))
			and world.get_voxel(Vector3i(145, FLOOR_Y + 5, 160)) == M.WALL_PAINT)
	_check("the storey is taller", int(objects.storeys.heights[0]) == 40 and world.get_voxel(Vector3i(120, FLOOR_Y + 38, 90)) == M.WALL_PAINT)
	_check("the undone floor is gone", world.get_voxel(Vector3i(205, FLOOR_Y - 1, 205)) == M.AIR and objects.has("floor_0"))
	# Presence: the client has a wall selected; the host outlines it square to the wall.
	var client = null
	for player in lab.players.values():
		if not player.is_local:
			client = player
	var presence = client.get_node("Presence") if client else null
	await _wait_until(func() -> bool: return presence != null and objects.has(str(presence.state.get("selected", ""))), 10.0)
	_check("host sees the client's selected wall", presence != null and objects.get(str(presence.state.get("selected", "")), {}).get("kind") == "wall",
			str(presence.state if presence else {}))
	# The outline is drawn on the presence's next frame after the state arrives.
	await _wait_until(func() -> bool: return presence != null and presence._selection.visible, 5.0)
	_check("...outlined", presence != null and presence._selection.visible)
	lab.edits.put_object(LevelSchema.new_marker("trigger", Vector3(240, 10, 240)).merged({id = "host_done"}))
	await _wait_seconds(1.0)
	_print_hashes(lab, "build")
	await _wait_seconds(4.0) # Stay up until the client is done.


func _client(net: Node) -> void:
	net.player_name = "Zack"
	_check("client connects", net.join("127.0.0.1", _port) == OK)
	var lab = await _wait_for_lab()
	if lab == null:
		return
	var ready := func() -> bool: return lab.local_player() != null and lab.level != null and lab.view.mode == "edit" and lab.level.objects.has("storeys")
	if not await _wait_until(ready, 60.0):
		_check("entered the editor", false)
		return
	await _wait_until(func() -> bool: return lab.local_player().net_peers == [1], 20.0)
	var tool = lab.local_player().get_node("EditorTool")
	var objects: Dictionary = lab.level.objects
	var edits = lab.edits
	_check("client's tools know it's a build level", tool.is_build_level())

	# The Wall tool, Ctrl+drag: four walls with their floor and ceiling.
	var wall = tool.wall
	wall.storey = 0
	wall.plane_y = FLOOR_Y
	wall.storey_height = 30
	wall.has_aim = true
	wall.snapped = Vector2i(90, 90)
	wall.begin(false, true, 30)
	wall.snapped = Vector2i(150, 130)
	wall.update_end(5)
	wall.finish(objects, M.WALL_PAINT, 2, 0, true, M.TILE_LIGHT, M.CONCRETE)
	_check("the rectangle came back", await _wait_until(func() -> bool: return _walls(objects).size() == 4 and objects.has("ceiling_0"), 20.0))

	# A second room east of it, closed by a 45° wall; its floor filled and an Auto ceiling.
	for segment in [[Vector2i(150, 90), Vector2i(180, 90)], [Vector2i(180, 90), Vector2i(180, 120)],
			[Vector2i(180, 120), Vector2i(170, 130)], [Vector2i(170, 130), Vector2i(150, 130)]]:
		edits.put_object(wall.make_wall(segment[0], segment[1], M.WALL_PAINT, 2, 0))
	_check("the second room came back", await _wait_until(func() -> bool: return _walls(objects).size() == 8, 20.0))
	var build = tool.build
	build.storey = 0
	build.kind = "floor"
	_check("filling the second room's floor", build.fill(objects, Vector2i(165, 100), M.METAL) == "Floor filled")
	await _wait_until(func() -> bool: return lab.world.get_voxel(Vector3i(165, FLOOR_Y - 1, 100)) == M.METAL, 20.0)
	build.kind = "ceiling"
	var said: String = build.auto_ceiling(objects, M.CONCRETE)
	_check("Auto ceiling", said.begins_with("Ceiling over"), said)
	await _wait_until(func() -> bool: return lab.world.get_voxel(Vector3i(165, FLOOR_Y + 30, 100)) == M.CONCRETE, 20.0)

	# A window in the rectangle's north wall, and a door in its south wall.
	var north := _wall_along(objects, 90, 90, 150)
	edits.put_object(LevelSchema.new_wall_opening(north.id, 10, 10, 10, 10, "window"))
	tool.has_cursor = true
	tool.cell = Vector3i(120, FLOOR_Y + 1, 131)
	tool.solid_cell = Vector3i(120, FLOOR_Y + 1, 130)
	tool.cursor_normal = Vector3i(0, 0, 1)
	var spot: Dictionary = tool.prop_spot(DOOR, 0, "")
	_check("a door fits in the south wall", spot.get("valid", false), str(spot))
	if spot.get("valid", false):
		edits.put_object(tool._placed(LevelSchema.new_prop(DOOR, spot.origin, spot.facing), spot))
	await _wait_until(func() -> bool: return objects.values().any(func(o: Dictionary) -> bool: return o.kind == "prop" and o.name == DOOR), 20.0)

	# A free wall, its end dragged out (WallHandles, as the handle does).
	edits.put_object(wall.make_wall(Vector2i(100, 160), Vector2i(140, 160), M.WALL_PAINT, 2, 0))
	await _wait_until(func() -> bool: return _walls(objects).size() == 9, 20.0)
	var free := _wall_along(objects, 160, 100, 140)
	var done: Dictionary = tool.wall_handles.reshape(objects, free, Vector2i(100, 160), Vector2i(150, 160), Vector2i.ZERO, true)
	_check("the dragged end is valid", done.valid, done.reason)
	edits.put_objects(done.puts)
	await _wait_until(func() -> bool: return not _wall_along(objects, 160, 100, 150).is_empty(), 20.0)

	# A taller storey, then a floor painted and undone.
	tool.set_storey_height(40)
	await _wait_until(func() -> bool: return int(objects.storeys.heights[0]) == 40, 20.0)
	edits.add_slab_shape("floor", 0, LevelBuild.rect_shape(Vector3i(200, 0, 200), Vector3i(210, 0, 210), M.GLASS))
	await _wait_until(func() -> bool: return lab.world.get_voxel(Vector3i(205, FLOOR_Y - 1, 205)) == M.GLASS, 20.0)
	edits.undo()
	await _wait_until(func() -> bool: return lab.world.get_voxel(Vector3i(205, FLOOR_Y - 1, 205)) == M.AIR, 20.0)

	# Select the north wall (the host sees it in presence), and say we're done.
	tool.set_tool(0)
	tool.select(north.id)
	await _wait_seconds(0.5)
	edits.put_object(LevelSchema.new_marker("trigger", Vector3(230, 10, 230)).merged({id = "client_done"}))
	if not await _wait_until(func() -> bool: return objects.has("host_done"), 60.0):
		_check("host finished checking", false)
		return
	await _wait_seconds(1.0)
	_print_hashes(lab, "build")


func _walls(objects: Dictionary) -> Array:
	return objects.values().filter(func(o: Dictionary) -> bool: return o.kind == "wall")


## The straight wall along x at z from x0 to x1 (either way round), or {}.
func _wall_along(objects: Dictionary, z: int, x0: int, x1: int) -> Dictionary:
	for w: Dictionary in _walls(objects):
		if w.a.z == z and w.b.z == z and mini(w.a.x, w.b.x) == x0 and maxi(w.a.x, w.b.x) == x1:
			return w
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
