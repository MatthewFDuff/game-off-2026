extends SceneTree
## Build mode's Floor and Ceiling tools (EditorTool, BuildTools), headless, with real mouse events:
##   godot --headless --path . --script res://tests/build_floor_test.gd
## Dragging paints a floor; corners snap to wall ends and walls; Shift+drag erases; a click inside
## four walls fills the room (under the walls too), inside a 45° diamond as well, and an open loop
## refuses; the Ceiling tool covers a dragged area and Auto covers every closed room with a floor;
## undo; a floor on storey 2 after Page Up; the filled shapes survive saving and loading.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://build_floor_test_levels/"
const LEVEL := "build_floor_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")

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

	_check("a build level's rail has Floor and Ceiling, not Room", _tool.tools().has(8) and _tool.tools().has(10) and not _tool.tools().has(1))
	await _key(KEY_2)
	_check("2 picks Floor (second on the rail)", _tool.tool == 8, str(_tool.tool))
	_tool.room_floor = M.TILE_LIGHT
	_tool.room_ceiling = M.CONCRETE

	# Drag a floor rectangle.
	await _drag(Vector2(20, 20), Vector2(60, 50))
	_check("dragging paints a floor", world.get_voxel(Vector3i(40, 1, 35)) == M.TILE_LIGHT and world.get_voxel(Vector3i(59, 2, 49)) == M.TILE_LIGHT)
	_check("...over the dragged area only", world.get_voxel(Vector3i(19, 1, 35)) == M.AIR and world.get_voxel(Vector3i(60, 1, 35)) == M.AIR
			and world.get_voxel(Vector3i(40, 3, 35)) == M.AIR)

	# Shift+drag erases.
	await _drag(Vector2(30, 30), Vector2(40, 40), true)
	_check("Shift+drag erases", world.get_voxel(Vector3i(35, 1, 35)) == M.AIR and world.get_voxel(Vector3i(25, 1, 25)) == M.TILE_LIGHT)

	# A square room of walls: corners and walls snap, a click inside fills it.
	var square := [Vector3i(200, 0, 20), Vector3i(240, 0, 20), Vector3i(240, 0, 60), Vector3i(200, 0, 60)]
	for i in 4:
		_lab.edits.put_object(LevelBuild.new_wall(0, square[i], square[(i + 1) % 4], M.WALL_PAINT, 2))
	await _aim(Vector2(201.6, 21.3))
	_check("the aim snaps to a wall corner", _tool.build.snapped == Vector2i(200, 20) and _tool.build.snapped_to == "corner", "%s %s" % [_tool.build.snapped, _tool.build.snapped_to])
	await _aim(Vector2(221.0, 21.2))
	_check("...and onto a wall", _tool.build.snapped == Vector2i(220, 20) and _tool.build.snapped_to == "on wall", "%s %s" % [_tool.build.snapped, _tool.build.snapped_to])
	await _click(Vector2(220.5, 40.5))
	_check("a click inside four walls fills the room", world.get_voxel(Vector3i(220, 1, 40)) == M.TILE_LIGHT and world.get_voxel(Vector3i(202, 1, 22)) == M.TILE_LIGHT)
	_check("...under the walls too", world.get_voxel(Vector3i(220, 1, 20)) == M.TILE_LIGHT and world.get_voxel(Vector3i(220, 1, 19)) == M.TILE_LIGHT)
	_check("...and not outside them", world.get_voxel(Vector3i(220, 1, 17)) == M.AIR and world.get_voxel(Vector3i(220, 1, 70)) == M.AIR)

	# A 45° diamond fills too.
	var diamond := [Vector3i(50, 0, 170), Vector3i(80, 0, 200), Vector3i(50, 0, 230), Vector3i(20, 0, 200)]
	for i in 4:
		_lab.edits.put_object(LevelBuild.new_wall(0, diamond[i], diamond[(i + 1) % 4], M.WALL_PAINT, 2))
	await _click(Vector2(50.5, 200.5))
	_check("a click inside a 45° diamond fills it", world.get_voxel(Vector3i(50, 1, 200)) == M.TILE_LIGHT and world.get_voxel(Vector3i(50, 1, 176)) == M.TILE_LIGHT)
	_check("...and stops at its walls", world.get_voxel(Vector3i(75, 1, 175)) == M.AIR and world.get_voxel(Vector3i(50, 1, 166)) == M.AIR)

	# Three walls don't close a room.
	var open := [Vector3i(150, 0, 20), Vector3i(190, 0, 20), Vector3i(190, 0, 60), Vector3i(150, 0, 60)]
	for i in 3:
		_lab.edits.put_object(LevelBuild.new_wall(0, open[i], open[i + 1], M.WALL_PAINT, 2))
	var shapes: int = objects.floor_0.shapes.size()
	await _click(Vector2(170.5, 40.5))
	_check("an open loop doesn't fill", world.get_voxel(Vector3i(170, 1, 40)) == M.AIR and objects.floor_0.shapes.size() == shapes)

	# Ceilings: drag one, then Auto over every closed room with a floor.
	await _key(KEY_4)
	_check("4 picks Ceiling", _tool.tool == 10, str(_tool.tool))
	await _frames(2)
	_check("...and the cut opens over the ceiling", _camera.cut_layer == 36, str(_camera.cut_layer))
	await _drag(Vector2(100, 20), Vector2(130, 40))
	_check("dragging a ceiling covers the area at the walls' top", world.get_voxel(Vector3i(115, 33, 30)) == M.CONCRETE and world.get_voxel(Vector3i(115, 32, 30)) == M.AIR)
	_tool.auto_ceiling()
	_check("Auto covers the closed rooms", world.get_voxel(Vector3i(220, 33, 40)) == M.CONCRETE and world.get_voxel(Vector3i(50, 34, 200)) == M.CONCRETE)
	_check("...not the open one", world.get_voxel(Vector3i(170, 33, 40)) == M.AIR)
	_lab.edits.undo()
	_check("undo takes Auto's ceiling off", world.get_voxel(Vector3i(220, 33, 40)) == M.AIR and world.get_voxel(Vector3i(115, 33, 30)) == M.CONCRETE)

	# A floor on storey 2.
	await _key(KEY_2)
	await _key(KEY_PAGEUP)
	_check("Page Up goes to storey 2", _tool.storey == 1)
	await _drag(Vector2(20, 20), Vector2(60, 50))
	_check("its floor is painted on storey 2", world.get_voxel(Vector3i(40, 34, 35)) == M.TILE_LIGHT and world.get_voxel(Vector3i(40, 36, 35)) == M.AIR)
	await _key(KEY_PAGEDOWN)

	# Filled shapes (runs) survive saving and loading.
	_lab.request_save()
	var saved = LevelData.load_level(LEVEL)
	var runs_kept: bool = saved != null and saved.objects.floor_0.shapes == objects.floor_0.shapes and objects.floor_0.shapes.any(func(s: Array) -> bool: return s[2] < 0)
	_check("filled shapes save and load", runs_kept)
	_check("...and the voxels match", saved != null and saved.voxels == world.get_data())
	_finish()


## The screen point over a voxel (x, z) on the tool's plane.
func _screen(at: Vector2) -> Vector2:
	var y: int = _tool.build.plane_y if _tool.build.plane_y > 0 else 3
	var world_point: Vector3 = _lab.view.to_world(Vector3(at.x, y, at.y))
	return _camera.camera.unproject_position(world_point)


## Looks straight down at a spot (voxels x, z) on the plane.
func _look_at(at: Vector2) -> void:
	var y: int = _tool.build.plane_y if _tool.build.plane_y > 0 else 3
	_camera.pivot = _lab.view.to_world(Vector3(at.x, y, at.y))
	_camera.yaw = 0.0
	_camera.pitch = 89.0
	_camera.distance = 12.0
	_camera.snap_to_target()
	await _frames(2)


func _aim(at: Vector2) -> void:
	await _look_at(at)
	await _move_mouse(_screen(at))
	await _frames(2)


func _drag(from: Vector2, to: Vector2, shift := false) -> void:
	await _look_at((from + to) * 0.5)
	await _move_mouse(_screen(from))
	await _button(_screen(from), true, shift)
	await _move_mouse(_screen(to))
	await _button(_screen(to), false, shift)


func _click(at: Vector2, shift := false) -> void:
	await _look_at(at)
	await _move_mouse(_screen(at))
	await _button(_screen(at), true, shift)
	await _button(_screen(at), false, shift)


func _button(at: Vector2, pressed: bool, shift: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.global_position = at
	event.pressed = pressed
	event.shift_pressed = shift
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
	print("build floor test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
