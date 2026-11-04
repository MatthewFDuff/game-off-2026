extends SceneTree
## Build mode in a rock level (EditorTool, WallTool, BuildTools, WallHandles), headless, with real
## mouse and key events, on a scratch copy of the laboratory:
##   godot --headless --path . --script res://tests/build_rock_test.gd
## In the Server hall (a carved room, floor top y 170, ceiling bottom y 205): the rail has Room and
## the build tools; the Wall tool draws a wall standing on the floor it's pressed on, floor to
## ceiling, solid in the carved air with the rock around untouched, and undoes; a wall run into the
## rock beside the room only fills the room and recolors its lining; the Floor tool draws a mezzanine
## on a plane held up with Ctrl+wheel; the Ceiling tool draws a dropped ceiling the same way, and
## follows the ceiling over the floor otherwise; a click inside walls on the floor fills it; a
## wall's middle handle slides it; the Opening tool cuts a doorway in it; and it all saves and loads.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://build_rock_test_levels/"
const LEVEL := "build_rock_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
## The Server hall: its inside, and its floor top and ceiling bottom.
const HALL_FROM := Vector3i(140, 170, 75)
const HALL_TO := Vector3i(395, 205, 200)
const FLOOR_Y := 170
const CEILING_Y := 205
## EditorTool.Tool values (Select 0, Room 1, ... Marker 7 on the rail first).
const FLOOR := 8
const WALL := 9
const CEILING := 10

var _failures := 0
var _lab
var _tool
var _camera
var _world
var _objects: Dictionary


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	LevelData.save_dir_override = SCRATCH
	var to := SCRATCH.path_join(LEVEL)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to))
	for file in ["level.json", "voxels.bin"]:
		FileAccess.open(to.path_join(file), FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes("res://levels/laboratory".path_join(file)))
	root.get_node("Net").start_solo(LEVEL, "edit")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	_lab = current_scene
	_world = _lab.world
	var edits = _lab.edits
	_objects = _lab.level.objects
	_tool = _lab.local_player().get_node("EditorTool")
	_camera = _tool.camera
	await _frames(10)
	root.notification(Node.NOTIFICATION_VP_MOUSE_ENTER) # Headless never says the mouse is in the window.
	_check("a rock level", _tool.is_rock_level() and not _tool.is_build_level())
	_check("the hall is carved", _world.get_voxel(Vector3i(370, FLOOR_Y - 1, 160)) != 0 and _world.get_voxel(Vector3i(370, FLOOR_Y, 160)) == M.AIR
			and _world.get_voxel(Vector3i(370, CEILING_Y - 1, 160)) == M.AIR and _world.get_voxel(Vector3i(370, CEILING_Y, 160)) != 0)

	# The rail: the rock tools keep their keys, the build tools come after them.
	var rail: Array = _tool.tools()
	_check("the rail keeps Room and adds Floor, Wall, Ceiling", rail.slice(0, 8) == [0, 1, 2, 3, 4, 5, 6, 7]
			and rail.slice(8) == [FLOOR, WALL, CEILING], str(rail))
	await _key(KEY_0)
	_check("0 picks Wall", _tool.tool == WALL, str(_tool.tool))
	await _key(KEY_MINUS)
	_check("- picks Ceiling", _tool.tool == CEILING, str(_tool.tool))
	await _key(KEY_0)

	# A wall drawn across the hall, floor to ceiling.
	_tool.room_wall = M.STEEL
	await _look(Vector2(370, 160), 0.0, 89.0)
	var before: PackedByteArray = _world.get_box(HALL_FROM - Vector3i.ONE * 8, HALL_TO + Vector3i.ONE * 8)
	await _drag(_screen(Vector3(360, FLOOR_Y, 160)), _screen(Vector3(390, FLOOR_Y, 160.4)))
	var w1 := _wall_from(Vector2i(360, 160))
	_check("the Wall tool draws a wall in a rock level", not w1.is_empty() and w1.get("b") == Vector3i(390, 0, 160), str(w1))
	_check("...with no storey, standing on the floor pressed on", int(w1.get("storey", 0)) == -1 and int(w1.get("base", 0)) == FLOOR_Y, str(w1))
	_check("...up to the ceiling", int(w1.get("height", 0)) == CEILING_Y - FLOOR_Y, str(w1.get("height")))
	_check("...solid in the carved air", _world.get_voxel(Vector3i(375, FLOOR_Y, 160)) == M.STEEL and _world.get_voxel(Vector3i(375, CEILING_Y - 1, 159)) == M.STEEL
			and _world.get_voxel(Vector3i(375, FLOOR_Y + 10, 158)) == M.AIR and _world.get_voxel(Vector3i(375, FLOOR_Y + 10, 161)) == M.AIR)
	var after: PackedByteArray = _world.get_box(HALL_FROM - Vector3i.ONE * 8, HALL_TO + Vector3i.ONE * 8)
	_check("...and nothing else changed", _changes_outside(before, after, HALL_FROM, HALL_TO) == 0 and _holes(before, after) == 0)
	edits.undo()
	_check("...undo takes it out", not _objects.has(str(w1.get("id", ""))) and _world.get_voxel(Vector3i(375, FLOOR_Y + 10, 160)) == M.AIR
			and _world.get_box(HALL_FROM - Vector3i.ONE * 8, HALL_TO + Vector3i.ONE * 8) == before)
	edits.redo()
	_check("...redo brings it back", _objects.has(str(w1.get("id", ""))) and _world.get_voxel(Vector3i(375, FLOOR_Y + 10, 160)) == M.STEEL)

	# A wall run out of the hall into the rock beside it: the rock stays rock, the lining is recolored.
	var rock_before: int = _world.get_voxel(Vector3i(128, FLOOR_Y + 10, 160))
	edits.put_object(LevelBuild.new_wall(-1, Vector3i(150, 0, 160), Vector3i(125, 0, 160), M.STEEL, 2, 20, 0, FLOOR_Y))
	_check("a wall into the rock fills the hall", _world.get_voxel(Vector3i(145, FLOOR_Y + 5, 160)) == M.STEEL)
	_check("...recolors its lining", _world.get_voxel(Vector3i(137, FLOOR_Y + 5, 160)) == M.STEEL)
	_check("...and leaves the rock alone", rock_before != M.AIR and rock_before != M.STEEL and _world.get_voxel(Vector3i(128, FLOOR_Y + 10, 160)) == rock_before,
			"%d -> %d" % [rock_before, _world.get_voxel(Vector3i(128, FLOOR_Y + 10, 160))])
	edits.undo()
	_check("...and undoes", _world.get_voxel(Vector3i(145, FLOOR_Y + 5, 160)) == M.AIR and _world.get_voxel(Vector3i(137, FLOOR_Y + 5, 160)) != M.STEEL)

	# A mezzanine: the Floor tool's plane held 1 m up with Ctrl+wheel, then an area dragged.
	await _key(KEY_9)
	_check("9 picks Floor", _tool.tool == FLOOR)
	_tool.room_floor = M.WOOD
	await _look(Vector2(370, 130), 0.0, 89.0)
	await _move_mouse(_screen(Vector3(365, FLOOR_Y, 130)))
	_check("the Floor tool aims at the floor", _tool.build.has_aim and _tool.build.plane_y == FLOOR_Y and _tool.build.storey == -1, str(_tool.build.plane_y))
	await _wheel(true, true)
	await _wheel(true, true)
	var mezzanine: int = FLOOR_Y + 2 * _tool.snap()
	_check("...Ctrl+wheel holds its plane higher", _tool.build.held == mezzanine and _tool.build.plane_y == mezzanine, "%d %d" % [_tool.build.held, _tool.build.plane_y])
	_check("...and says how high", _tool.rock_plane_text().begins_with("1.0 m up"), _tool.rock_plane_text())
	await _drag(_screen(Vector3(360, mezzanine, 120)), _screen(Vector3(380, mezzanine, 140)))
	var mezz: Dictionary = _objects.get(LevelBuild.slab_id("floor", -1, mezzanine), {})
	_check("a mezzanine floor at the held plane", int(mezz.get("y", -1)) == mezzanine and int(mezz.get("storey", 0)) == -1 and mezz.get("shapes", []).size() == 1, str(mezz))
	_check("...solid there, in the air", _world.get_voxel(Vector3i(370, mezzanine - 1, 130)) == M.WOOD and _world.get_voxel(Vector3i(370, mezzanine - 3, 130)) == M.WOOD
			and _world.get_voxel(Vector3i(370, mezzanine, 130)) == M.AIR and _world.get_voxel(Vector3i(370, mezzanine - 4, 130)) == M.AIR
			and _world.get_voxel(Vector3i(381, mezzanine - 1, 130)) == M.AIR)
	await _key(KEY_ESCAPE)
	await _move_mouse(_screen(Vector3(365, FLOOR_Y, 150)))
	_check("Esc lets the plane follow the floor again", _tool.build.held == -1 and _tool.build.plane_y == FLOOR_Y, str(_tool.build.plane_y))

	# A dropped ceiling: the Ceiling tool follows the ceiling over the floor, Ctrl+wheel lowers it.
	await _key(KEY_MINUS)
	_tool.room_ceiling = M.GLASS
	await _look(Vector2(370, 180), 0.0, 89.0)
	await _move_mouse(_screen(Vector3(365, FLOOR_Y, 180)))
	_check("the Ceiling tool aims under the ceiling", _tool.build.has_aim and _tool.build.plane_y == CEILING_Y and _tool.build.base == FLOOR_Y, "%d %d" % [_tool.build.plane_y, _tool.build.base])
	await _wheel(false, true)
	var dropped: int = CEILING_Y - _tool.snap()
	_check("...Ctrl+wheel lowers it", _tool.build.plane_y == dropped, str(_tool.build.plane_y))
	await _drag(_screen(Vector3(360, dropped, 175)), _screen(Vector3(380, dropped, 185)))
	var ceiling: Dictionary = _objects.get(LevelBuild.slab_id("ceiling", -1, dropped), {})
	_check("a ceiling at that plane", int(ceiling.get("y", -1)) == dropped and ceiling.get("shapes", []).size() == 1, str(ceiling))
	_check("...solid under the real one", _world.get_voxel(Vector3i(370, dropped, 180)) == M.GLASS and _world.get_voxel(Vector3i(370, dropped + 2, 180)) == M.GLASS
			and _world.get_voxel(Vector3i(370, dropped - 1, 180)) == M.AIR and _world.get_voxel(Vector3i(370, CEILING_Y, 180)) != M.GLASS)
	await _key(KEY_ESCAPE)

	# A room of walls on the floor (by hand), then a click inside it with the Floor tool fills it.
	edits.put_objects([["", LevelBuild.new_wall(-1, Vector3i(250, 0, 140), Vector3i(280, 0, 140), M.CONCRETE, 2, 20, 0, FLOOR_Y)],
			["", LevelBuild.new_wall(-1, Vector3i(280, 0, 140), Vector3i(280, 0, 170), M.CONCRETE, 2, 20, 0, FLOOR_Y)],
			["", LevelBuild.new_wall(-1, Vector3i(280, 0, 170), Vector3i(250, 0, 170), M.CONCRETE, 2, 20, 0, FLOOR_Y)],
			["", LevelBuild.new_wall(-1, Vector3i(250, 0, 170), Vector3i(250, 0, 140), M.CONCRETE, 2, 20, 0, FLOOR_Y)]])
	await _key(KEY_9)
	_tool.room_floor = M.TILE_LIGHT
	await _look(Vector2(265, 155), 0.0, 89.0)
	await _click(_screen(Vector3(265.5, FLOOR_Y, 155.5)))
	var floor: Dictionary = _objects.get(LevelBuild.slab_id("floor", -1, FLOOR_Y), {})
	_check("a click inside walls on the floor fills it", floor.get("shapes", []).size() == 1 and int(floor.shapes[0][2]) < 0, str(floor))
	_check("...repainting the floor inside", _world.get_voxel(Vector3i(265, FLOOR_Y - 1, 155)) == M.TILE_LIGHT and _world.get_voxel(Vector3i(265, FLOOR_Y - 1, 175)) != M.TILE_LIGHT
			and _world.get_voxel(Vector3i(265, FLOOR_Y, 155)) == M.AIR)

	# The first wall's middle handle slides it 1 m across.
	await _key(KEY_1)
	await _look(Vector2(375, 160), 0.0, 89.0)
	await _click(_screen(Vector3(372, CEILING_Y, 160)))
	_check("clicking a rock level wall selects it", _tool.selected == w1.id, _tool.selected)
	await _drag(_screen(Vector3(375, CEILING_Y, 160)), _screen(Vector3(375, FLOOR_Y, 170.4)))
	w1 = _objects.get(w1.id, {})
	_check("its middle handle slides it", w1.get("a") == Vector3i(360, 0, 170) and w1.get("b") == Vector3i(390, 0, 170), "%s %s" % [w1.get("a"), w1.get("b")])
	_check("...keeping its floor", int(w1.get("base", 0)) == FLOOR_Y and int(w1.get("height", 0)) == CEILING_Y - FLOOR_Y)
	_check("...the voxels move", _world.get_voxel(Vector3i(375, FLOOR_Y + 10, 160)) == M.AIR and _world.get_voxel(Vector3i(375, FLOOR_Y + 10, 170)) == M.STEEL)

	# The Opening tool: a doorway in it, from its floor.
	await _key(KEY_6)
	_tool.opening_type = "doorway"
	await _look(Vector2(375, 185), 0.0, 20.0, 1.2)
	await _click(_screen(Vector3(375.5, 185, 171.0)))
	var doorway := _opening_in(w1.id)
	_check("the Opening tool cuts a doorway in a rock level wall", not doorway.is_empty() and int(doorway.get("sill", -1)) == 0, "%s under %s" % [doorway, _tool.solid_cell])
	if not doorway.is_empty():
		var x: int = 360 + int(doorway.along) + 2
		_check("...through it, from its floor", _world.get_voxel(Vector3i(x, FLOOR_Y, 169)) == M.AIR and _world.get_voxel(Vector3i(x, FLOOR_Y + 20, 170)) == M.AIR
				and _world.get_voxel(Vector3i(x, FLOOR_Y + 23, 170)) == M.STEEL and _world.get_voxel(Vector3i(x, FLOOR_Y - 1, 170)) != M.AIR)

	# Save and load: the pieces come back as they were.
	var packed: PackedInt32Array = LevelBuild.pack(_objects, AABB(Vector3(HALL_FROM), Vector3(HALL_TO - HALL_FROM)))
	_lab.request_save()
	var saved = LevelData.load_level(LEVEL)
	var loaded: Dictionary = saved.objects if saved else {}
	var loaded_wall: Dictionary = loaded.get(w1.id, {})
	_check("it saves and loads", not loaded_wall.is_empty() and loaded_wall.base is int and int(loaded_wall.base) == FLOOR_Y and int(loaded_wall.storey) == -1
			and loaded.has(LevelBuild.slab_id("floor", -1, mezzanine)) and loaded[LevelBuild.slab_id("floor", -1, mezzanine)].y is int, str(loaded_wall))
	_check("...building the same", saved != null and LevelBuild.pack(loaded, AABB(Vector3(HALL_FROM), Vector3(HALL_TO - HALL_FROM))) == packed)
	_check("...with no storeys object", not loaded.has(LevelBuild.STOREYS_ID))
	_finish()


## Voxels in the box (HALL_FROM - 8 to HALL_TO + 8) that changed outside the hall's inside.
func _changes_outside(before: PackedByteArray, after: PackedByteArray, inside_from: Vector3i, inside_to: Vector3i) -> int:
	var from := HALL_FROM - Vector3i.ONE * 8
	var size := HALL_TO - HALL_FROM + Vector3i.ONE * 16
	var count := 0
	for i in before.size():
		if before[i] == after[i]:
			continue
		var p := from + Vector3i(i % size.x, (i / size.x) % size.y, i / (size.x * size.y))
		if p.x < inside_from.x or p.y < inside_from.y or p.z < inside_from.z or p.x >= inside_to.x or p.y >= inside_to.y or p.z >= inside_to.z:
			count += 1
	return count


## Solid voxels that turned to air.
func _holes(before: PackedByteArray, after: PackedByteArray) -> int:
	var count := 0
	for i in before.size():
		if before[i] != 0 and after[i] == 0:
			count += 1
	return count


func _wall_from(a: Vector2i) -> Dictionary:
	for object: Dictionary in _objects.values():
		if object.kind == "wall" and object.a == Vector3i(a.x, 0, a.y):
			return object
	return {}


func _opening_in(wall_id: String) -> Dictionary:
	for object: Dictionary in _objects.values():
		if object.kind == "opening" and object.get("wall", "") == wall_id:
			return object
	return {}


## The screen point over a voxel-space point.
func _screen(at: Vector3) -> Vector2:
	return _camera.camera.unproject_position(_lab.view.to_world(at))


## Looks at a spot (voxels x, z) on the hall's floor.
func _look(at: Vector2, yaw: float, pitch: float, distance := 12.0) -> void:
	_camera.pivot = _lab.view.to_world(Vector3(at.x, FLOOR_Y, at.y))
	_camera.yaw = yaw
	_camera.pitch = pitch
	_camera.distance = distance
	_camera.snap_to_target()
	await _frames(3)


func _drag(from: Vector2, to: Vector2) -> void:
	await _move_mouse(from)
	await _button(MOUSE_BUTTON_LEFT, from, true)
	await _move_mouse(from.lerp(to, 0.5))
	await _move_mouse(to)
	await _frames(2)
	await _button(MOUSE_BUTTON_LEFT, to, false)
	await _frames(2)


func _click(at: Vector2) -> void:
	await _move_mouse(at)
	await _button(MOUSE_BUTTON_LEFT, at, true)
	await _button(MOUSE_BUTTON_LEFT, at, false)
	await _frames(2)


func _wheel(up: bool, ctrl: bool) -> void:
	var at: Vector2 = _tool.camera.mouse_position()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		event.position = at
		event.global_position = at
		event.pressed = pressed
		event.ctrl_pressed = ctrl
		root.push_input(event, true)
		await _frames(1)
	await _frames(2)


func _button(index: MouseButton, at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.position = at
	event.global_position = at
	event.pressed = pressed
	root.push_input(event, true)
	await _frames(2)


func _move_mouse(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event, true)
	await _frames(2)


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)


func _finish() -> void:
	print("build rock test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
