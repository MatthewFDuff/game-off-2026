extends SceneTree
## Build mode storeys in the editor (EditorTool, EditorCamera), headless, with real key events:
##   godot --headless --path . --script res://tests/build_storey_test.gd
## In an empty level Page Up / Down change storeys (adding one past the top, dropping an empty top
## one on the way down, keeping one with a wall), the cutaway opens the active storey, the cursor
## lands on its floor plane, and a storey's wall height moves its walls and the storeys above
## (undoable).
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://build_storey_test_levels/"
const LEVEL := "build_storey_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")

var _failures := 0


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
	var lab = current_scene
	var world = lab.world
	var objects: Dictionary = lab.level.objects
	var tool = lab.local_player().get_node("EditorTool")
	var camera = tool.camera
	await _frames(10)

	_check("an empty level is a build level", tool.is_build_level() and tool.storey == 0)
	_check("the cut opens storey 1 (its ceiling cut away)", camera.cut_layer == 33 and camera.is_cutting(), str(camera.cut_layer))
	_check("...in the shader", absf(world.material.get_shader_parameter("cut_height") - (world.global_position.y + 3.3)) < 0.01)

	await _key(KEY_PAGEUP)
	await _frames(3)
	_check("Page Up adds storey 2 and goes there", tool.storey == 1 and objects.storeys.heights == [30, 30], str(objects.storeys.heights))
	_check("...the cut follows", camera.cut_layer == 66, str(camera.cut_layer))
	_check("...and the camera looks at its floor", absf(camera.pivot.y - (world.global_position.y + 3.6)) < 0.01, str(camera.pivot.y))

	# The cursor lands on storey 2's floor plane (nothing is built there).
	camera.pivot = Vector3(12.8, camera.pivot.y, 12.8)
	camera.pitch = 89.0
	camera.distance = 10.0
	camera.snap_to_target()
	await _move_mouse(Vector2(640, 360))
	await _frames(3)
	_check("the cursor is on the storey's floor plane", tool.has_cursor and tool.cell.y == 36 and tool.solid_cell.y == 35 and tool.cursor_normal == Vector3i.UP,
			"%s %s" % [tool.cell, tool.has_cursor])

	await _key(KEY_PAGEDOWN)
	await _frames(3)
	_check("Page Down goes back and drops the empty storey", tool.storey == 0 and objects.storeys.heights == [30], str(objects.storeys.heights))
	await _key(KEY_PAGEDOWN)
	_check("...and stops at the ground floor", tool.storey == 0)

	# A storey with a wall on it stays.
	await _key(KEY_PAGEUP)
	lab.edits.put_object(LevelBuild.new_wall(1, Vector3i(100, 0, 100), Vector3i(140, 0, 100), M.CONCRETE))
	await _key(KEY_PAGEDOWN)
	_check("a storey with a wall stays", tool.storey == 0 and objects.storeys.heights.size() == 2)
	_check("...and its wall stands on storey 2's floor", world.get_voxel(Vector3i(120, 36, 99)) == M.CONCRETE and world.get_voxel(Vector3i(120, 35, 99)) == M.AIR)

	# A taller ground floor: storey 2 and its wall move up; undo.
	lab.edits.put_object(LevelBuild.new_wall(0, Vector3i(100, 0, 140), Vector3i(140, 0, 140), M.WALL_PAINT))
	tool.set_storey_height(40)
	_check("the storey's height changes", objects.storeys.heights == [40, 30], str(objects.storeys.heights))
	_check("...its walls grow", world.get_voxel(Vector3i(120, 42, 139)) == M.WALL_PAINT and world.get_voxel(Vector3i(120, 43, 139)) == M.AIR)
	_check("...and the storey above moves up", world.get_voxel(Vector3i(120, 36, 99)) == M.AIR and world.get_voxel(Vector3i(120, 46, 99)) == M.CONCRETE)
	await _frames(2)
	_check("...and so does the cut", camera.cut_layer == 43, str(camera.cut_layer))
	lab.edits.undo()
	await _frames(2)
	_check("undo puts it back", objects.storeys.heights == [30, 30] and world.get_voxel(Vector3i(120, 36, 99)) == M.CONCRETE
			and world.get_voxel(Vector3i(120, 40, 139)) == M.AIR)

	# The storey bar in the HUD.
	var hud = lab.find_children("*", "EditorHud", true, false)
	if not hud.is_empty():
		await _frames(2)
		_check("the HUD shows the storey bar", hud[0]._storey_row.visible and hud[0]._storey_label.text == "1 / 2", hud[0]._storey_label.text)
	_finish()


func _finish() -> void:
	print("build storey test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


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


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
