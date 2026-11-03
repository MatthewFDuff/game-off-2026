extends SceneTree
## Drives the level editor through real input events (keys and clicks), headless:
##   godot --headless --path . --script res://tests/editor_tool_test.gd
## Box fill + undo, a brush stroke that undoes in one step, placing / selecting / rotating /
## deleting a prop, a marker, the grid snap key, and F5 to play and back. Works on a scratch copy of
## the lab level.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://editor_tool_test_levels/"
const LEVEL := "lab_tool_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")

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
	await _frames(5)
	_check("editing", lab.mode == "edit" and me.editing and me.flying)

	# Look straight down at the atrium floor (y 40) from 2 m up.
	_look_down(me, Vector3(23.0, 6.0, 23.0))
	await _frames(3)
	_check("cursor on the floor", tool.has_cursor and tool.solid_cell.y == 39 and tool.cell.y == 40, "%s / %s" % [tool.solid_cell, tool.cell])

	# Box tool, grid 1: two clicks fill a column of the current material.
	await _key(KEY_1)
	await _key(KEY_G)
	await _key(KEY_G)
	_check("G cycles the grid to 1", tool.snap() == 1, str(tool.snap()))
	tool.material = M.BLOCK_WALL
	var floor_cell: Vector3i = tool.cell
	await _click(MOUSE_BUTTON_LEFT)
	_look_down(me, Vector3(23.35, 6.0, 23.35))
	await _frames(2)
	await _click(MOUSE_BUTTON_LEFT)
	var far_cell: Vector3i = tool.cell
	var filled := _count(lab.world, floor_cell.min(far_cell), floor_cell.max(far_cell) + Vector3i.ONE, M.BLOCK_WALL)
	_check("two clicks fill the box", filled == (far_cell - floor_cell + Vector3i.ONE).x * (far_cell - floor_cell + Vector3i.ONE).z and filled > 1, "%d voxels" % filled)
	await _key(KEY_Z, true)
	_check("Ctrl+Z undoes it", _count(lab.world, floor_cell.min(far_cell), floor_cell.max(far_cell) + Vector3i.ONE, M.BLOCK_WALL) == 0)
	await _key(KEY_Y, true)
	_check("Ctrl+Y redoes it", _count(lab.world, floor_cell.min(far_cell), floor_cell.max(far_cell) + Vector3i.ONE, M.BLOCK_WALL) == filled)
	await _key(KEY_Z, true)

	# Brush: hold LMB for a few dabs while moving; one undo removes the whole stroke.
	await _key(KEY_3)
	tool.material = M.HAZARD_STRIPES
	_look_down(me, Vector3(24.0, 6.0, 24.0))
	await _frames(2)
	await _press(MOUSE_BUTTON_LEFT, true)
	for i in 6:
		_look_down(me, Vector3(24.0 + i * 0.15, 6.0, 24.0))
		await create_timer(0.08).timeout
	await _press(MOUSE_BUTTON_LEFT, false)
	await _frames(2)
	var painted := _count(lab.world, Vector3i(230, 35, 230), Vector3i(255, 50, 250), M.HAZARD_STRIPES)
	_check("brush stroke paints", painted > 20, "%d voxels" % painted)
	await _key(KEY_Z, true)
	_check("one undo removes the whole stroke", _count(lab.world, Vector3i(230, 35, 230), Vector3i(255, 50, 250), M.HAZARD_STRIPES) == 0)

	# Prop: place one, select it, rotate it, delete it.
	await _key(KEY_5)
	tool.prop_name = "crate_8"
	var before: int = lab.level.objects.size()
	var old_ids: Array = lab.level.objects.keys()
	_look_down(me, Vector3(26.0, 6.0, 26.0))
	await _frames(2)
	await _click(MOUSE_BUTTON_LEFT)
	var new_ids: Array = lab.level.objects.keys().filter(func(id: String) -> bool: return id not in old_ids)
	_check("LMB places a prop", lab.level.objects.size() == before + 1 and new_ids.size() == 1 and lab.level.objects[new_ids[0]].name == "crate_8")
	if new_ids.is_empty():
		return _finish()
	var crate_id: String = new_ids[0]
	await _key(KEY_7)
	_look_down(me, Vector3(26.0, 6.0, 26.0))
	await _frames(2)
	await _click(MOUSE_BUTTON_LEFT)
	_check("LMB selects it", tool.selected == crate_id, tool.selected)
	# The inspector shows the phase 5 prop fields, with a multi-line box for the text.
	await _frames(2)
	var hud = lab.get_node("EditorHud")
	var labels: Array = hud._content.find_children("*", "Label", true, false).map(func(l) -> String: return l.text)
	_check("inspector shows the use fields", "Use (E)" in labels and "Contents (pickups, comma-separated)" in labels
			and "Door keycard (red, blue, ...; empty = none)" in labels, str(labels))
	_check("inspector has a text box for notes", not hud._content.find_children("*", "TextEdit", true, false).is_empty())
	_check("new props start with use fields", lab.level.objects[crate_id].get("use") == "none" and lab.level.objects[crate_id].get("charges") == 3)
	await _key(KEY_R)
	_check("R rotates it", lab.level.objects[crate_id].facing == 1)
	await _key(KEY_X)
	_check("X deletes it", not lab.level.objects.has(crate_id) and tool.selected == "")
	await _key(KEY_Z, true)
	_check("undo brings it back", lab.level.objects.has(crate_id))

	# Marker.
	await _key(KEY_6)
	tool.marker_type = "horde"
	before = lab.level.objects.size()
	await _click(MOUSE_BUTTON_LEFT)
	var hordes: Array = lab.level.objects.values().filter(func(o: Dictionary) -> bool: return o.kind == "marker" and o.type == "horde")
	_check("LMB places a marker", lab.level.objects.size() == before + 1 and hordes.size() == 1)

	# Play-test and back.
	await _key(KEY_F5)
	_check("F5 play-tests", lab.mode == "play" and not me.editing)
	await _key(KEY_F5)
	_check("F5 again edits", lab.mode == "edit" and me.editing)
	_finish()


func _finish() -> void:
	print("editor tool test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _look_down(player, eye: Vector3) -> void:
	player.teleport(eye - Vector3.UP * (player.standing_height - player.eye_offset))
	player.rotation.y = 0.0
	player.head.rotation.x = -PI * 0.49


func _key(keycode: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		event.ctrl_pressed = ctrl
		Input.parse_input_event(event)
		await _frames(2)


func _click(button: MouseButton) -> void:
	await _press(button, true)
	await _press(button, false)


func _press(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	await _frames(2)


func _count(world, from: Vector3i, to: Vector3i, material: int) -> int:
	var n := 0
	for y in range(from.y, to.y):
		for z in range(from.z, to.z):
			for x in range(from.x, to.x):
				n += int(world.get_voxel(Vector3i(x, y, z)) == material)
	return n


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
