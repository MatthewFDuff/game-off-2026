extends SceneTree
## Build mode's Wall tool (EditorTool, WallTool), headless, with real mouse and key events:
##   godot --headless --path . --script res://tests/build_wall_test.gd
## Dragging builds a wall along X, at 45°, and snaps a near-45° drag to 45° and a near-X one to X;
## a wall drawn from another's end joins it (closed corner) and one ending on a wall's middle makes
## a T; the wheel sets the height and typing the length while dragging; Ctrl+drag builds four walls
## with a floor and a ceiling, undone in one step; Shift+drag erases the middle of a wall, leaving
## two pieces and moving an opening onto the second; the Floor tool fills walls the tool drew.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://build_wall_test_levels/"
const LEVEL := "build_wall_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
## Storey 0's floor top (the starter slab's).
const FLOOR_Y := 3

var _failures := 0
var _lab
var _tool
var _camera


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	LevelData.save_dir_override = SCRATCH
	var holder := Node.new()
	root.add_child(holder)
	var level = LevelData.create(LEVEL, Vector3i(8, 6, 8), "empty", holder)
	level.save()
	holder.free()
	root.get_node("Net").start_solo(LEVEL, "edit")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	_lab = current_scene
	var world = _lab.world
	var objects: Dictionary = _lab.level.objects
	_tool = _lab.local_player().get_node("EditorTool")
	_camera = _tool.camera
	await _frames(10)
	root.notification(Node.NOTIFICATION_VP_MOUSE_ENTER) # Headless never says the mouse is in the window.

	_check("the build rail has Wall third", _tool.tools()[2] == 9, str(_tool.tools()))
	await _key(KEY_3)
	_check("3 picks Wall", _tool.tool == 9, str(_tool.tool))
	_tool.room_wall = M.WALL_PAINT
	_tool.room_floor = M.TILE_LIGHT
	_tool.room_ceiling = M.CONCRETE

	# Along X.
	await _drag(Vector2(20, 20), Vector2(60, 20.6))
	var first := _wall_from(objects, Vector2i(20, 20))
	_check("dragging along X builds a wall", first.get("b") == Vector3i(60, 0, 20), str(first))
	_check("...in voxels, from the floor up a storey", world.get_voxel(Vector3i(40, FLOOR_Y, 19)) == M.WALL_PAINT and world.get_voxel(Vector3i(40, FLOOR_Y + 29, 20)) == M.WALL_PAINT
			and world.get_voxel(Vector3i(40, FLOOR_Y + 30, 20)) == M.AIR and world.get_voxel(Vector3i(40, 10, 21)) == M.AIR)

	# From its end, along Z: a closed corner.
	await _drag(Vector2(61.2, 20.8), Vector2(60, 60))
	var corner := _wall_from(objects, Vector2i(60, 20))
	_check("a drag from a wall's end starts on it", corner.get("b") == Vector3i(60, 0, 60), str(corner))
	_check("...and the corner is closed", world.get_voxel(Vector3i(60, 10, 19)) == M.WALL_PAINT and world.get_voxel(Vector3i(59, 10, 19)) == M.WALL_PAINT
			and world.get_voxel(Vector3i(60, 10, 21)) == M.WALL_PAINT)

	# Onto the first wall's middle: a T.
	await _drag(Vector2(40, 55), Vector2(40.4, 20.7))
	var tee := _wall_from(objects, Vector2i(40, 55))
	_check("a drag ending on a wall's middle stops on it (a T)", tee.get("b") == Vector3i(40, 0, 20), str(tee))

	# 45°, and near-45° snapping to it.
	await _drag(Vector2(20, 100), Vector2(50, 131))
	var diagonal := _wall_from(objects, Vector2i(20, 100))
	_check("a near-45° drag builds a 45° wall", diagonal.get("b") == Vector3i(50, 0, 130), str(diagonal))
	_check("...in voxels", world.get_voxel(Vector3i(35, 10, 115)) == M.WALL_PAINT and world.get_voxel(Vector3i(36, 10, 115)) == M.WALL_PAINT
			and world.get_voxel(Vector3i(38, 10, 115)) == M.AIR)
	await _drag(Vector2(100, 20), Vector2(140, 24))
	_check("a near-X drag snaps to X", _wall_from(objects, Vector2i(100, 20)).get("b") == Vector3i(140, 0, 20), str(_wall_from(objects, Vector2i(100, 20))))

	# The wheel sets the height while dragging.
	await _drag(Vector2(100, 60), Vector2(140, 60), {wheel = 2})
	var tall := _wall_from(objects, Vector2i(100, 60))
	_check("the wheel makes it taller", tall.get("height") == 40, str(tall))
	_check("...in voxels", world.get_voxel(Vector3i(120, FLOOR_Y + 39, 60)) == M.WALL_PAINT and world.get_voxel(Vector3i(120, FLOOR_Y + 40, 60)) == M.AIR)
	_check("a wall at the storey's height follows it", first.get("height") == -1)

	# Typing the length.
	await _drag(Vector2(100, 100), Vector2(130, 100), {type = [KEY_2, KEY_PERIOD, KEY_5]})
	_check("typing 2.5 makes it 2.5 m long", _wall_from(objects, Vector2i(100, 100)).get("b") == Vector3i(125, 0, 100), str(_wall_from(objects, Vector2i(100, 100))))

	# Ctrl+drag: four walls, a floor and a ceiling, one undo step.
	var walls_before := _count(objects, "wall")
	await _drag(Vector2(200, 200), Vector2(240, 240), {ctrl = true})
	_check("Ctrl+drag builds four walls", _count(objects, "wall") == walls_before + 4, "%d -> %d" % [walls_before, _count(objects, "wall")])
	_check("...with a floor and a ceiling", world.get_voxel(Vector3i(220, 1, 220)) == M.TILE_LIGHT and world.get_voxel(Vector3i(220, FLOOR_Y + 30, 220)) == M.CONCRETE)
	_check("...and walls all round", world.get_voxel(Vector3i(220, 10, 200)) == M.WALL_PAINT and world.get_voxel(Vector3i(240, 10, 220)) == M.WALL_PAINT
			and world.get_voxel(Vector3i(220, 10, 239)) == M.WALL_PAINT and world.get_voxel(Vector3i(200, 10, 220)) == M.WALL_PAINT)
	_lab.edits.undo()
	_check("one undo takes it all away", _count(objects, "wall") == walls_before and world.get_voxel(Vector3i(220, 1, 220)) == M.AIR
			and world.get_voxel(Vector3i(220, FLOOR_Y + 30, 220)) == M.AIR and world.get_voxel(Vector3i(220, 10, 200)) == M.AIR)

	# Shift+drag erases the middle of a wall; an opening past it moves to the second piece.
	_lab.edits.put_object(LevelBuild.new_wall(0, Vector3i(20, 0, 200), Vector3i(100, 0, 200), M.WALL_PAINT, 2))
	var long := _wall_from(objects, Vector2i(20, 200))
	_lab.edits.put_object(LevelSchema.new_wall_opening(long.id, 60, 10, 0, 20))
	await _drag(Vector2(40, 200), Vector2(60, 200), {shift = true})
	var left := _wall_from(objects, Vector2i(20, 200))
	var right := _wall_from(objects, Vector2i(60, 200))
	_check("Shift+drag splits the wall", left.get("b") == Vector3i(40, 0, 200) and right.get("b") == Vector3i(100, 0, 200), "%s %s" % [left, right])
	_check("...the middle is gone", world.get_voxel(Vector3i(50, 10, 199)) == M.AIR and world.get_voxel(Vector3i(30, 10, 199)) == M.WALL_PAINT)
	var moved := {}
	for object: Dictionary in objects.values():
		if object.kind == "opening" and str(object.get("wall", "")) != "":
			moved = object
	_check("...and the opening moved onto the second piece", not right.is_empty() and moved.get("wall") == right.get("id") and moved.get("along") == 20, str(moved))
	_check("...where it was", world.get_voxel(Vector3i(85, 10, 199)) == M.AIR and world.get_voxel(Vector3i(75, 10, 199)) == M.WALL_PAINT)

	# The Floor tool fills walls the Wall tool drew.
	_tool.wall_slabs = false
	await _drag(Vector2(200, 20), Vector2(240, 60), {ctrl = true})
	_check("Ctrl+drag without floor and ceiling: just walls", world.get_voxel(Vector3i(220, 1, 40)) == M.AIR)
	await _key(KEY_2)
	await _click(Vector2(220.5, 40.5))
	_check("the Floor tool fills the room they close in", world.get_voxel(Vector3i(220, 1, 40)) == M.TILE_LIGHT and world.get_voxel(Vector3i(220, 1, 15)) == M.AIR)
	_finish()


## The wall starting at a point (voxel x, z), {} if none.
func _wall_from(objects: Dictionary, a: Vector2i) -> Dictionary:
	for object: Dictionary in objects.values():
		if object.kind == "wall" and object.a == Vector3i(a.x, 0, a.y):
			return object
	return {}


func _count(objects: Dictionary, kind: String) -> int:
	return objects.values().filter(func(o: Dictionary) -> bool: return o.kind == kind).size()


## The screen point over a voxel (x, z) on storey 0's floor.
func _screen(at: Vector2) -> Vector2:
	return _camera.camera.unproject_position(_lab.view.to_world(Vector3(at.x, FLOOR_Y, at.y)))


## Looks straight down at a spot (voxels x, z) on the floor.
func _look_at(at: Vector2) -> void:
	_camera.pivot = _lab.view.to_world(Vector3(at.x, FLOOR_Y, at.y))
	_camera.yaw = 0.0
	_camera.pitch = 89.0
	_camera.distance = 12.0
	_camera.snap_to_target()
	await _frames(2)


## Presses at from, moves to to and releases; with: shift / ctrl held, wheel ups while held, keys
## typed while held.
func _drag(from: Vector2, to: Vector2, with := {}) -> void:
	var shift: bool = with.get("shift", false)
	var ctrl: bool = with.get("ctrl", false)
	await _look_at((from + to) * 0.5)
	await _move_mouse(_screen(from))
	await _button(MOUSE_BUTTON_LEFT, _screen(from), true, shift, ctrl)
	await _move_mouse(_screen(to))
	for i in int(with.get("wheel", 0)):
		await _button(MOUSE_BUTTON_WHEEL_UP, _screen(to), true, false, false)
		await _button(MOUSE_BUTTON_WHEEL_UP, _screen(to), false, false, false)
	for keycode: Key in with.get("type", []):
		await _key(keycode)
	await _frames(2)
	await _button(MOUSE_BUTTON_LEFT, _screen(to), false, shift, ctrl)


func _click(at: Vector2) -> void:
	await _look_at(at)
	await _move_mouse(_screen(at))
	await _button(MOUSE_BUTTON_LEFT, _screen(at), true, false, false)
	await _button(MOUSE_BUTTON_LEFT, _screen(at), false, false, false)


func _button(index: MouseButton, at: Vector2, pressed: bool, shift: bool, ctrl: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.position = at
	event.global_position = at
	event.pressed = pressed
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
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
	print("build wall test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
