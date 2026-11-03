extends SceneTree
## Three-click volumes (VolumeSteps, the Room / Box / Replace tools), headless:
##   godot --headless --path . --script res://tests/editor_volume_test.gd
## The sizing rules on their own (signed sizes, the floor plane, wheel, typing, Tab, back), then in
## the builder view: wheel and typing during the steps, Backspace / RMB stepping back, the readout
## and edge labels, and a room dug down from the cutaway beside the atrium that lines up with its
## floor and ceiling. Works on a scratch copy of the lab level.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://editor_volume_test_levels/"
const LEVEL := "lab_volume_test"
## The atrium: floor top at voxel y 40.
const ATRIUM := Vector3(23.0, 4.0, 23.0)

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LevelData.save_dir_override = SCRATCH
	var to := SCRATCH.path_join(LEVEL)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to))
	for file in ["level.json", "voxels.bin"]:
		FileAccess.open(to.path_join(file), FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes("res://levels/lab".path_join(file)))
	root.get_node("Net").start_solo(LEVEL, "edit")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	var lab = current_scene
	var me = lab.local_player()
	var tool = me.get_node("EditorTool")
	var camera = tool.camera
	var world = lab.world
	await _frames(5)
	_rules(world)

	root.notification(Node.NOTIFICATION_VP_MOUSE_ENTER) # Headless never says the mouse is in the window.
	camera.look_from(ATRIUM, 0.0)
	camera.pitch = 89.0
	camera.distance = 30.0
	camera.snap_to_target()
	await _frames(3)
	var cut: int = camera.cut_layer
	_check("auto cut at the atrium ceiling", camera.is_cutting() and cut > 41, str(cut))

	# Box: wheel and typing while sizing, Tab, stepping back.
	tool.set_tool(2) # Box
	var center: Vector2 = root.get_visible_rect().get_center()
	await _move_mouse(center)
	await _click(center, MOUSE_BUTTON_LEFT)
	var volume = tool.volume
	_check("first click starts the floor step", volume.step == 1)
	var zoom: float = camera.distance
	await _wheel(center, MOUSE_BUTTON_WHEEL_UP, false)
	_check("wheel grows the width a grid step", volume.extent.x == 10 and volume.is_locked(Vector3.AXIS_X), str(volume.extent))
	_check("...and doesn't zoom", is_equal_approx(camera.distance, zoom))
	var length: int = volume.extent.z
	await _wheel(center, MOUSE_BUTTON_WHEEL_UP, true)
	_check("Shift+wheel grows the length", volume.extent.z == length + 5, "%d -> %d" % [length, volume.extent.z])
	length = volume.extent.z
	await _move_mouse(center + Vector2(80, 60))
	_check("the mouse leaves wheeled sizes alone", volume.extent.x == 10 and volume.extent.z == length, str(volume.extent))
	await _key(KEY_TAB)
	_check("Tab moves to the length", volume.axis == Vector3.AXIS_Z)
	await _key(KEY_2)
	await _key(KEY_PERIOD)
	await _key(KEY_5)
	_check("typing meters sets it (2.5 m = 25 voxels)", volume.extent.z == 25 and tool.tool == 2, str(volume.extent))
	_check("readout shows the typing", "2.5_" in tool.volume_readout(), tool.volume_readout())
	await _key(KEY_ENTER)
	_check("Enter keeps it", volume.typed == "" and volume.extent.z == 25 and volume.step == 1)
	await _key(KEY_ENTER)
	_check("Enter again goes on to the height", volume.step == 2 and volume.extent.y == 10, str(volume.extent))
	_check("height label shown", tool._size_labels[1].visible and tool._size_labels[1].text == "1.0 m", tool._size_labels[1].text)
	await _key(KEY_BACKSPACE)
	_check("Backspace steps back to the floor", volume.step == 1 and volume.extent.z == 25)
	await _click(center, MOUSE_BUTTON_RIGHT)
	_check("right click steps back again (cancels)", not volume.is_active())

	# Room dug down from the cutaway beside the atrium: its floor and ceiling line up.
	tool.set_tool(1) # Room
	var a := Vector3i(170, cut - 1, 230)
	var b := Vector3i(184, cut - 1, 244)
	_check("rock beside the atrium", world.get_voxel(a) != 0 and world.get_voxel(Vector3i(177, 45, 237)) != 0)
	var a_screen := _screen(camera, lab, a)
	var b_screen := _screen(camera, lab, b)
	await _move_mouse(a_screen)
	_check("cursor on the cap", tool.has_cursor and tool.cursor_on_cap and tool.solid_cell.y == cut - 1, "%s cap %s" % [tool.solid_cell, tool.cursor_on_cap])
	await _click(a_screen, MOUSE_BUTTON_LEFT)
	await _move_mouse(b_screen)
	await _click(b_screen, MOUSE_BUTTON_LEFT)
	_check("dug room: height reaches the atrium floor", volume.extent.y == -(cut - 40), str(volume.extent))
	var box: Array = volume.box()
	_check("dug room box", box[0] == Vector3i(170, 40, 230) and box[1] == Vector3i(185, cut, 245), str(box))
	await _click(b_screen, MOUSE_BUTTON_LEFT)
	_check("third click builds it", not volume.is_active())
	_check("inside is carved", world.get_voxel(Vector3i(177, 45, 237)) == 0 and world.get_voxel(Vector3i(177, cut - 1, 237)) == 0)
	_check("floor lined at the atrium's floor height", world.get_voxel(Vector3i(177, 39, 237)) == tool.room_floor)
	_check("ceiling lined at the atrium's ceiling height", world.get_voxel(Vector3i(177, cut, 237)) == tool.room_ceiling)
	_check("the room tool remembers the height", tool._last_height[1] == cut - 40)
	_finish()


## VolumeSteps on its own.
func _rules(world) -> void:
	var v := VolumeSteps.new()
	v.world = world
	var origin: Vector3 = world.global_position
	var size: float = world.voxel_size
	v.begin(Vector3i(100, 40, 100), origin.y + 40 * size, 5, 1)
	_check("begins on the floor step, one cell", v.step == 1 and v.size() == Vector3i(5, 1, 5))
	# Aim straight down at voxel (112, 40, 93): the start cell and 2 more along +x, and 2 back along
	# -z (cells 95 and 90).
	var eye := origin + Vector3(112.5, 60.0, 93.5) * size
	v.aim(eye, Vector3.DOWN)
	_check("floor follows the plane", v.extent == Vector3i(15, 1, -15), str(v.extent))
	_check("negative side keeps the start cell", v.box() == [Vector3i(100, 40, 90), Vector3i(115, 41, 105)], str(v.box()))
	v.nudge(Vector3.AXIS_X, -1)
	_check("nudge shrinks and locks", v.extent.x == 10 and v.is_locked(Vector3.AXIS_X))
	v.aim(eye + Vector3(1.0, 0.0, 0.0), Vector3.DOWN)
	_check("locked size ignores the mouse", v.extent.x == 10)
	v.nudge(Vector3.AXIS_X, -5)
	_check("never below one voxel", v.extent.x == 1)
	v.cycle_axis()
	for c in "3v":
		v.type_char(c)
	_check("typed voxels", v.extent.z == -3 and v.axis == Vector3.AXIS_Z, str(v.extent))
	v.type_char("v")
	v.type_char("1")
	_check("nothing after the v", v.typed == "3v")
	v.advance(30)
	_check("height step at the given height", v.step == 2 and v.extent.y == 30 and v.typed == "" and v.axis == Vector3.AXIS_Y)
	# A horizontal look: the vertical line through the floor's center sets the height relative to
	# where the aim was when the step began.
	var side := origin + Vector3(105.0, 50.0, 140.0) * size
	v.aim(side, Vector3.FORWARD)
	_check("first height aim keeps the given height", v.extent.y == 30, str(v.extent))
	v.aim(side + Vector3.UP * 1.0, Vector3.FORWARD)
	_check("aiming 1 m higher adds 10", v.extent.y == 40, str(v.extent))
	v.aim(side + Vector3.DOWN * 3.2, Vector3.FORWARD)
	_check("aiming below the start flips it down", v.extent.y == -5, str(v.extent))
	_check("back to the floor", v.back() and v.step == 1)
	_check("back again ends it", not v.back() and not v.is_active())


func _finish() -> void:
	print("editor volume test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


## Screen position of a voxel's top center.
func _screen(camera, lab, voxel: Vector3i) -> Vector2:
	return camera.camera.unproject_position(lab.view.to_world(Vector3(voxel) + Vector3(0.5, 1.0, 0.5)))


func _move_mouse(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event, true)
	await _frames(2)


func _click(at: Vector2, button: MouseButton) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.position = at
		event.global_position = at
		event.pressed = pressed
		root.push_input(event, true)
		await _frames(2)


func _wheel(at: Vector2, button: MouseButton, shift: bool) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.position = at
		event.global_position = at
		event.pressed = pressed
		event.shift_pressed = shift
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
