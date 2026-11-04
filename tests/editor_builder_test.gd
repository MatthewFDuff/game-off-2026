extends SceneTree
## The level editor's builder view (EditorCamera), headless, with real input events:
##   godot --headless --path . --script res://tests/editor_builder_test.gd
## Covers aiming through the mouse, clicks, right drag orbit vs right click, WASD pan, Q / E, the
## auto and manual cutaway (shader, cap, aim ray), dropping into the walk view and back, and
## play-testing in between. Works on a scratch copy of the lab level.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://editor_builder_test_levels/"
const LEVEL := "lab_builder_test"
## The atrium: floor top at voxel y 40, open well above it.
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
	root.notification(Node.NOTIFICATION_VP_MOUSE_ENTER) # Headless never says the mouse is in the window.
	var center: Vector2 = root.get_visible_rect().get_center()
	await _move_mouse(center)

	_check("starts in the builder view", tool.builder and camera.active and camera.camera.current and me.builder_view)

	# Look down at the atrium floor: auto cut at its ceiling, the cursor on the floor under the mouse.
	camera.look_from(ATRIUM, 0.0)
	camera.pitch = 89.0
	camera.distance = 6.0
	camera.snap_to_target()
	await _frames(3)
	var ceiling: int = camera.cut_layer
	_check("auto cut above the atrium floor", camera.is_cutting() and ceiling > 41, "layer %d" % ceiling)
	_check("auto cut is a ceiling", world.get_voxel(Vector3i(230, ceiling, 230)) != 0 and world.get_voxel(Vector3i(230, ceiling - 1, 230)) == 0)
	var shader_cut: float = world.material.get_shader_parameter("cut_height")
	_check("terrain shader cuts there", is_equal_approx(shader_cut, camera.cut_y() - 0.001), "%.3f vs %.3f" % [shader_cut, camera.cut_y()])
	_check("cursor on the floor under the mouse", tool.has_cursor and tool.solid_cell.y == 39 and Vector2(tool.solid_cell.x, tool.solid_cell.z).distance_to(Vector2(230, 230)) < 3,
			"%s" % tool.solid_cell)

	# Three clicks with the Box tool fill a grid box on the floor.
	tool.set_tool(2) # Box
	tool.material = VoxelMaterials.METAL
	await _frames(2)
	var target: Vector3i = tool._start_cell(false)
	await _click(center, MOUSE_BUTTON_LEFT)
	await _click(center, MOUSE_BUTTON_LEFT)
	await _click(center, MOUSE_BUTTON_LEFT)
	_check("box placed by mouse clicks", world.get_voxel(target) == VoxelMaterials.METAL, "%s is %d" % [target, world.get_voxel(target)])
	lab.edits.undo()
	await _frames(2)

	# A right drag orbits and isn't a click; a right click without a drag is the tool's RMB.
	var yaw: float = camera.yaw
	await _press(center, MOUSE_BUTTON_RIGHT, true)
	await _move_mouse(center + Vector2(60, 0))
	await _move_mouse(center + Vector2(120, 0))
	await _press(center + Vector2(120, 0), MOUSE_BUTTON_RIGHT, false)
	_check("right drag orbits", not is_equal_approx(camera.yaw, yaw), "%.1f -> %.1f" % [yaw, camera.yaw])
	_check("...and doesn't click", not tool.has_step())
	await _move_mouse(center)
	await _click(center, MOUSE_BUTTON_RIGHT)
	_check("right click starts a carve corner", tool.has_step() and tool._volume_carve)
	await _key(KEY_ESCAPE)
	_check("Esc drops it", not tool.has_step())

	# Keys: Q turns 45 degrees, WASD pans, the player stays put.
	yaw = camera.yaw
	await _key(KEY_Q)
	_check("Q turns 45 degrees", is_equal_approx(camera.yaw, snappedf(yaw, 45.0) + 45.0), "%.1f -> %.1f" % [yaw, camera.yaw])
	var pivot: Vector3 = camera.pivot
	var feet: Vector3 = me.global_position
	await _hold(KEY_W, 10)
	_check("W pans the camera", camera.pivot.distance_to(pivot) > 0.2)
	_check("...and doesn't move the player", me.global_position.distance_to(feet) < 0.01)
	camera.look_from(ATRIUM, 0.0)
	camera.pitch = 89.0
	camera.distance = 6.0
	camera.snap_to_target()
	await _frames(2)

	# Manual cut below the floor: the aim lands on the cap (rock cross section), never above it.
	await _key(KEY_PAGEDOWN)
	_check("Page Down switches to a manual cut", camera.cut_mode == 2 and camera.cut_layer == ceiling - tool.snap())
	camera.cut_layer = 20
	await _frames(3)
	_check("aim hits the cap under a low cut", tool.has_cursor and tool.solid_cell.y == 19, "%s" % tool.solid_cell)
	_check("the cap is drawn", camera._cap.visible and camera._cap_layer == 19)
	await _key(KEY_C)
	_check("C cycles to Off", camera.cut_mode == 0 and not camera.is_cutting())
	await _frames(2)
	_check("no cut: the shader shows everything", world.material.get_shader_parameter("cut_height") > 1e8 and not camera._cap.visible)
	await _key(KEY_C)
	await _frames(2)
	_check("C cycles to Auto: the atrium ceiling again", camera.cut_mode == 1 and camera.cut_layer == ceiling)

	# Walls-down: from a low angle the near wall is in the way; with H it's hidden and the cursor
	# goes through to the floor.
	camera.look_from(ATRIUM, 0.0)
	camera.pitch = 25.0
	camera.distance = 14.0
	camera.snap_to_target()
	await _move_mouse(center)
	await _frames(3)
	var blocked: Vector3i = tool.solid_cell
	await _key(KEY_H)
	await _frames(3)
	_check("H turns walls-down on", camera.walls_down and world.material.get_shader_parameter("walls_down_dir") != Vector2.ZERO)
	_check("the near wall was in the way", blocked.y > 41, str(blocked))
	_check("...and walls-down looks past it to the floor", tool.has_cursor and tool.solid_cell.y == 39, str(tool.solid_cell))
	await _key(KEY_H)
	await _frames(2)
	_check("H again: walls up", not camera.walls_down and world.material.get_shader_parameter("walls_down_dir") == Vector2.ZERO)

	# Numpad views: 7 top, 3 from the right, 9 turns around, 5 orthographic and back.
	await _key(KEY_KP_7)
	_check("Num 7: top view", camera.pitch == camera.PITCH_MAX, str(camera.pitch))
	await _key(KEY_KP_3)
	_check("Num 3: from the right", is_equal_approx(wrapf(camera.yaw, -180.0, 180.0), 90.0) and camera.pitch == camera.PITCH_MIN, "%s %s" % [camera.yaw, camera.pitch])
	await _key(KEY_KP_9)
	_check("Num 9: turned around", is_equal_approx(wrapf(camera.yaw, -180.0, 180.0), -90.0), str(camera.yaw))
	await _key(KEY_KP_5)
	await _frames(2)
	_check("Num 5: orthographic", camera.orthographic and camera.camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	await _key(KEY_KP_5)
	await _frames(2)
	_check("...and back to perspective", not camera.orthographic and camera.camera.projection == Camera3D.PROJECTION_PERSPECTIVE)

	# From outside the world the aim comes in through its edge (outside reads as solid); past the
	# world's bottom, the cursor lands on the ground there.
	var extent: Vector3 = Vector3(world.get_size_in_voxels()) * world.voxel_size
	var above: Vector3 = world.global_position + Vector3(extent.x * 0.5, extent.y + 10.0, extent.z * 0.5)
	var hit: Dictionary = camera.raycast(above, Vector3.DOWN)
	_check("a ray from above the world comes in through the top", hit.hit and hit.distance > 10.0, str(hit))
	var ground: Dictionary = tool._ground_hit(above, Vector3.DOWN)
	_check("the world's bottom is ground for the cursor", ground.hit and ground.voxel.y == -1 and ground.normal == Vector3.UP, str(ground))
	_check("...but not off the world's footprint", not tool._ground_hit(above + Vector3(extent.x, 0.0, 0.0), Vector3.DOWN).hit)
	# The rock at the world's edge isn't drawn from outside, so a ray from beside the world goes
	# through it rather than stopping on the edge in mid-air.
	var beside: Vector3 = world.global_position + Vector3(extent.x + 5.0, ATRIUM.y + 1.0, ATRIUM.z)
	hit = camera.raycast(beside, Vector3.LEFT)
	_check("a ray from beside the world doesn't stop on its undrawn edge", not hit.hit or hit.voxel.x < world.get_size_in_voxels().x - 1, str(hit))

	# Shift+middle drag pans in the screen's plane: up / down raises the view looking ahead, moves it
	# forward looking down.
	camera.look_from(ATRIUM, 0.0)
	camera.pitch = camera.PITCH_MIN
	camera._drag_pans = true
	camera._drag(Vector2(0.0, 60.0))
	_check("Shift+drag looking ahead raises the view", camera.pivot.y - ATRIUM.y > 0.5 * absf(camera.pivot.z - ATRIUM.z), str(camera.pivot))
	camera.look_from(ATRIUM, 0.0)
	camera.pitch = camera.PITCH_MAX
	camera._drag(Vector2(0.0, 60.0))
	_check("...and looking down moves it forward", ATRIUM.z - camera.pivot.z > 0.1 and absf(camera.pivot.y - ATRIUM.y) < 0.05, str(camera.pivot))
	camera._drag_pans = false

	# Box, Brush and Replace leave what's above the cut alone, unless that's unlocked.
	camera.look_from(ATRIUM, 0.0)
	camera.snap_to_target()
	camera.set_cut_mode(2)
	camera.cut_layer = 45
	await _frames(2)
	lab.edits.voxel_op(tool._seen({type = "box", from = Vector3i(228, 40, 228), to = Vector3i(232, 50, 232), material = VoxelMaterials.METAL}))
	await _frames(2)
	_check("a box under the cut fills there", world.get_voxel(Vector3i(230, 44, 230)) == VoxelMaterials.METAL)
	_check("...but not above the cut", world.get_voxel(Vector3i(230, 46, 230)) == 0)
	lab.edits.undo()
	lab.edits.voxel_op(tool._seen({type = "sphere", center = Vector3(230.5, 45.5, 230.5), radius = 3.0, material = VoxelMaterials.METAL}))
	await _frames(2)
	_check("a brush dab paints under the cut", world.get_voxel(Vector3i(230, 44, 230)) == VoxelMaterials.METAL)
	_check("...and not above it", world.get_voxel(Vector3i(230, 46, 230)) == 0)
	lab.edits.undo()
	await _frames(2)
	_check("...and undoes", world.get_voxel(Vector3i(230, 44, 230)) == 0)
	await _key(KEY_L)
	lab.edits.voxel_op(tool._seen({type = "box", from = Vector3i(228, 40, 228), to = Vector3i(232, 50, 232), material = VoxelMaterials.METAL}))
	await _frames(2)
	_check("L unlocks it", tool.edit_hidden and world.get_voxel(Vector3i(230, 46, 230)) == VoxelMaterials.METAL)
	lab.edits.undo()
	await _key(KEY_L)
	camera.set_cut_mode(1)
	camera.look_from(ATRIUM, 0.0)
	camera.pitch = 89.0
	camera.distance = 6.0
	camera.snap_to_target()
	await _frames(3)

	# V drops into the walk view where the mouse points, and back.
	await _key(KEY_V)
	await _frames(2)
	_check("V switches to the walk view", not tool.builder and not camera.active and me.camera.current and not me.builder_view)
	_check("landed on the floor under the mouse", absf(me.global_position.y - 4.0) < 0.05 and Vector2(me.global_position.x, me.global_position.z).distance_to(Vector2(23, 23)) < 0.5,
			str(me.global_position))
	_check("walking, not flying", not me.flying)
	_check("shader cut is off in the walk view", world.material.get_shader_parameter("cut_height") > 1e8)
	me.teleport(ATRIUM + Vector3(1.0, 0.0, 0.0))
	await _key(KEY_V)
	await _frames(2)
	_check("V comes back to the builder view", tool.builder and camera.active and camera.camera.current)
	_check("...looking at where you were", camera.pivot.distance_to(ATRIUM + Vector3(1.0, 0.0, 0.0)) < 0.01)

	# Play-testing uses the player's own camera; editing again brings the builder view back.
	lab.request_mode("play")
	await _frames(4)
	_check("play-test: player camera, no cut", me.camera.current and not camera.active and world.material.get_shader_parameter("cut_height") > 1e8)
	lab.request_mode("edit")
	await _frames(4)
	_check("editing again: builder view", camera.active and camera.camera.current and me.builder_view)
	_finish()


func _finish() -> void:
	print("editor builder test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _move_mouse(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	var from := root.get_mouse_position()
	event.position = at
	event.global_position = at
	event.relative = at - from
	root.push_input(event, true)
	await _frames(2)


func _press(at: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = at
	event.global_position = at
	event.pressed = pressed
	root.push_input(event, true)
	await _frames(2)


func _click(at: Vector2, button: MouseButton) -> void:
	await _press(at, button, true)
	await _press(at, button, false)


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)


func _hold(keycode: Key, frames: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(frames)
	event = event.duplicate()
	event.pressed = false
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
