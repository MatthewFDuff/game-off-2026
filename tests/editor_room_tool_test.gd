extends SceneTree
## The level editor's room tools driven like a player would (builder and walk view), headless:
##   godot --headless --path . --script res://tests/editor_room_tool_test.gd
## Select a room by clicking its floor, drag a wall handle, pick a handle up and nudge it with the
## wheel, cut a doorway with the Opening tool, move the room with M (its opening and a prop inside
## come along), delete it (it fills back in), and adopt the atrium with Room from space. Works on a
## scratch copy of the lab level.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://editor_room_tool_test_levels/"
const LEVEL := "lab_room_tool_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
## A room in solid rock high above the lab, and the atrium (floor at voxel y 40).
const FROM := Vector3i(100, 200, 100)
const TO := Vector3i(140, 230, 130)
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

	lab.edits.put_object(LevelSchema.new_room(FROM, TO, M.TILE_LIGHT, M.WALL_PAINT, M.CONCRETE, 3, 1000))
	lab.edits.put_object(LevelSchema.new_prop("crate_8", FROM + Vector3i(5, 0, 5), 0))
	await _frames(2)
	var room_id := ""
	var crate_id := ""
	for object: Dictionary in lab.level.objects.values():
		if object.kind == "room" and object.from == FROM:
			room_id = object.id
		elif object.kind == "prop" and object.origin == FROM + Vector3i(5, 0, 5):
			crate_id = object.id

	# Look down into the room and click its floor with the Select tool.
	var floor_center: Vector3 = lab.view.to_world(Vector3(120, 200, 115))
	_look_down(camera, floor_center)
	await _frames(3)
	tool.set_tool(0)
	var center: Vector2 = root.get_visible_rect().get_center()
	await _move_mouse(center)
	await _click(center, MOUSE_BUTTON_LEFT)
	_check("clicking the floor selects the room", tool.selected == room_id, tool.selected)
	_check("handles are on it", tool.handles.room.get("id") == room_id)

	# Drag the east wall's handle 1 m east.
	var handles = tool.handles
	var east: Vector3 = handles.handle_position(FROM, TO, Vector3i(1, 0, 0))
	var east_screen: Vector2 = camera.camera.unproject_position(east)
	await _move_mouse(east_screen)
	_check("hovering the east handle", handles.hover == Vector3i(1, 0, 0), str(handles.hover))
	await _press(east_screen, MOUSE_BUTTON_LEFT, true)
	await _move_mouse(camera.camera.unproject_position(east + Vector3(0.5, 0.0, 0.0)))
	await _move_mouse(camera.camera.unproject_position(east + Vector3(1.0, 0.0, 0.0)))
	_check("dragging shows the new size", handles.resized.get("to", Vector3i.ZERO).x == TO.x + 10, str(handles.resized.get("to")))
	await _press(camera.camera.unproject_position(east + Vector3(1.0, 0.0, 0.0)), MOUSE_BUTTON_LEFT, false)
	var room: Dictionary = lab.level.objects[room_id]
	_check("drag resizes the room", room.to == TO + Vector3i(10, 0, 0), str(room.to))
	_check("the new east part is carved", world.get_voxel(Vector3i(145, 210, 115)) == M.AIR and world.get_voxel(Vector3i(150, 210, 115)) == M.WALL_PAINT)

	# Click the north handle to pick it up, nudge it out two grid steps, click to drop.
	await _frames(2)
	var north: Vector3 = handles.handle_position(room.from, room.to, Vector3i(0, 0, -1))
	var north_screen: Vector2 = camera.camera.unproject_position(north)
	await _move_mouse(north_screen)
	await _click(north_screen, MOUSE_BUTTON_LEFT)
	_check("a click picks the handle up", handles.picked and handles.active == Vector3i(0, 0, -1))
	var zoom: float = camera.distance
	await _wheel(north_screen, MOUSE_BUTTON_WHEEL_UP)
	await _wheel(north_screen, MOUSE_BUTTON_WHEEL_UP)
	_check("the wheel nudges it, not the zoom", handles.resized.from.z == FROM.z - 10 and is_equal_approx(camera.distance, zoom), str(handles.resized.from))
	await _click(north_screen, MOUSE_BUTTON_LEFT)
	room = lab.level.objects[room_id]
	_check("the next click drops it", not handles.is_busy() and room.from.z == FROM.z - 10, str(room.from))

	# Walk view, facing the north wall from inside: the Opening tool cuts a doorway.
	await _key(KEY_V)
	await _frames(2)
	me.teleport(lab.view.to_world(Vector3(120, 200, 110)))
	me.rotation.y = 0.0
	me.head.rotation.x = 0.0
	me.flying = true
	tool.set_tool(5) # Opening
	await _frames(3)
	_check("aiming at the north wall", tool.has_cursor and tool.cursor_normal == Vector3i(0, 0, 1), "%s %s" % [tool.solid_cell, tool.cursor_normal])
	await _click(center, MOUSE_BUTTON_LEFT)
	var opening_id := ""
	for object: Dictionary in lab.level.objects.values():
		if object.kind == "opening" and object.room == room_id:
			opening_id = object.id
	_check("a doorway in the room's wall", opening_id != "")
	if opening_id == "":
		return _finish()
	var opening: Dictionary = lab.level.objects[opening_id]
	_check("doorway starts at the floor, 2.2 m tall", opening.from.y == 200 and opening.to.y == 222 and opening.to.x - opening.from.x == 12, "%s %s" % [opening.from, opening.to])
	_check("doorway is cut through", world.get_voxel(Vector3i((opening.from.x + opening.to.x) / 2, 205, opening.to.z - 1)) == M.AIR
			and world.get_voxel(Vector3i((opening.from.x + opening.to.x) / 2, 205, opening.from.z)) == M.AIR)

	# Back to the builder view: move the room with M to a spot over cut rock.
	await _key(KEY_V)
	await _frames(2)
	_look_down(camera, floor_center)
	await _frames(3)
	tool.set_tool(0)
	tool.select(room_id)
	await _move_mouse(center)
	await _key(KEY_M)
	var spot: Vector2 = camera.camera.unproject_position(floor_center + Vector3(-1.0, 0.0, 0.0))
	await _move_mouse(spot)
	await _click(spot, MOUSE_BUTTON_LEFT)
	var moved: Dictionary = lab.level.objects[room_id]
	var shift: Vector3i = moved.from - room.from
	_check("M moves the room", shift != Vector3i.ZERO and shift.y == 0 and moved.to - moved.from == room.to - room.from, str(shift))
	_check("its doorway came along", lab.level.objects[opening_id].from == opening.from + shift)
	_check("so did the crate inside", lab.level.objects[crate_id].origin == FROM + Vector3i(5, 0, 5) + shift)
	# A cell the move left: inside the old room, outside the new one and its walls.
	var left := Vector3i(room.to.x - 1 if shift.x < 0 else room.from.x, 210, (room.from.z + room.to.z) / 2)
	_check("the old spot filled back in", not LevelSchema.room_outer(moved).has_point(Vector3(left)) and world.get_voxel(left) == M.ROCK, "%s is %d" % [left, world.get_voxel(left)])

	# Delete: the room and its doorway go, the rock comes back.
	tool.select(room_id)
	await _key(KEY_DELETE)
	_check("Delete removes the room and its doorway", not lab.level.objects.has(room_id) and not lab.level.objects.has(opening_id))
	var middle: Vector3i = (moved.from + moved.to) / 2
	_check("it fills back with rock", world.get_voxel(middle) == M.ROCK, str(world.get_voxel(middle)))

	# Room from space: Alt+click in the atrium adopts it, voxels untouched.
	camera.look_from(ATRIUM, 0.0)
	camera.pitch = 89.0
	camera.distance = 6.0
	camera.snap_to_target()
	await _frames(3)
	tool.set_tool(1) # Room
	await _move_mouse(center)
	var before: PackedByteArray = world.get_box(Vector3i(200, 30, 210), Vector3i(250, 60, 260))
	await _click(center, MOUSE_BUTTON_LEFT, true)
	var adopted := {}
	for object: Dictionary in lab.level.objects.values():
		if object.kind == "room" and LevelSchema.box_of(object).has_point(Vector3(230.5, 41.5, 230.5)):
			adopted = object
	_check("Alt+click adopts the atrium as a room", not adopted.is_empty() and adopted.from.y == 40, str(adopted))
	_check("...without changing its voxels", world.get_box(Vector3i(200, 30, 210), Vector3i(250, 60, 260)) == before)
	_finish()


func _look_down(camera, at: Vector3) -> void:
	camera.look_from(at, 0.0)
	camera.pitch = 89.0
	camera.distance = 12.0
	camera.snap_to_target()


func _finish() -> void:
	print("editor room tool test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _move_mouse(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event, true)
	await _frames(2)


func _press(at: Vector2, button: MouseButton, pressed: bool, alt := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = at
	event.global_position = at
	event.pressed = pressed
	event.alt_pressed = alt
	root.push_input(event, true)
	await _frames(2)


func _click(at: Vector2, button: MouseButton, alt := false) -> void:
	await _press(at, button, true, alt)
	await _press(at, button, false, alt)


func _wheel(at: Vector2, button: MouseButton) -> void:
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


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
