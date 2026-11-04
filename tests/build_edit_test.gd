extends SceneTree
## Editing build mode walls (EditorTool, WallHandles), headless, with real mouse and key events:
##   godot --headless --path . --script res://tests/build_edit_test.gd
## Clicking a wall selects it; dragging its end handle moves the end, refused when a joined wall
## would bend; sliding a wall by its middle handle takes the joined wall's end along (corner still
## closed); the length field; undo; the Opening tool cuts a doorway in a straight wall and in a 45°
## one; a door prop goes in a straight wall (cutting its way through) but not in a 45° one; sliding
## a wall carries its door and opening; deleting a wall takes its openings and door (and undo brings
## them back); Merge joins two walls in line, Split cuts one in two, their openings following.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://build_edit_test_levels/"
const LEVEL := "build_edit_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
## Storey 0's floor top, and the top of its walls.
const FLOOR_Y := 3
const TOP_Y := 33
const DOOR := "door_single"

var _failures := 0
var _lab
var _tool
var _camera
var _objects: Dictionary


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	LevelData.save_dir_override = SCRATCH
	var holder := Node.new()
	root.add_child(holder)
	var level = LevelData.create(LEVEL, Vector3i(12, 6, 8), "empty", holder)
	level.save()
	holder.free()
	root.get_node("Net").start_solo(LEVEL, "edit")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	_lab = current_scene
	var world = _lab.world
	var edits = _lab.edits
	_objects = _lab.level.objects
	_tool = _lab.local_player().get_node("EditorTool")
	_camera = _tool.camera
	await _frames(10)
	root.notification(Node.NOTIFICATION_VP_MOUSE_ENTER) # Headless never says the mouse is in the window.

	# Two walls joined at (160, 100), and a 45° one.
	edits.put_objects([["", LevelBuild.new_wall(0, Vector3i(100, 0, 100), Vector3i(160, 0, 100), M.CONCRETE)],
			["", LevelBuild.new_wall(0, Vector3i(160, 0, 100), Vector3i(160, 0, 160), M.CONCRETE)],
			["", LevelBuild.new_wall(0, Vector3i(200, 0, 100), Vector3i(240, 0, 140), M.CONCRETE)]])
	var w1 := _wall_from(Vector2i(100, 100))
	var w2 := _wall_from(Vector2i(160, 100))
	var w3 := _wall_from(Vector2i(200, 100))
	_check("three walls", not w1.is_empty() and not w2.is_empty() and not w3.is_empty())
	await _key(KEY_1)
	_check("1 picks Select", _tool.tool == 0)

	# Clicking a wall selects it.
	await _look(Vector2(130, 100), 0.0, 89.0)
	await _click(_screen(Vector3(130, TOP_Y, 100)))
	_check("clicking a wall selects it", _tool.selected == w1.id, _tool.selected)
	_check("...with handles on its ends and middle", _tool.wall_handles.wall.get("id", "") == w1.id)

	# Its free end, dragged out along it.
	await _look(Vector2(100, 100), 0.0, 89.0)
	await _drag(_screen(Vector3(100, TOP_Y, 100)), _screen(Vector3(80, FLOOR_Y, 100.5)))
	w1 = _objects[w1.id]
	_check("dragging an end handle moves the end", w1.a == Vector3i(80, 0, 100), str(w1.a))
	_check("...and the wall in voxels", world.get_voxel(Vector3i(85, 10, 99)) == M.CONCRETE)

	# Its joined end, dragged along it: the joined wall would bend, so it's refused.
	await _look(Vector2(160, 100), 0.0, 89.0)
	await _drag(_screen(Vector3(160, TOP_Y, 100)), _screen(Vector3(180, FLOOR_Y, 100.5)))
	w1 = _objects[w1.id]
	_check("an end that would bend a joined wall is refused", w1.b == Vector3i(160, 0, 100) and _objects[w2.id].a == Vector3i(160, 0, 100), str(w1.b))

	# Slide the joined wall sideways by its middle: the first wall's end follows.
	await _look(Vector2(160, 130), 0.0, 89.0)
	await _click(_screen(Vector3(160, TOP_Y, 130)))
	_check("selecting the other wall", _tool.selected == w2.id, _tool.selected)
	await _drag(_screen(Vector3(160, TOP_Y, 130)), _screen(Vector3(180.4, FLOOR_Y, 130)))
	w1 = _objects[w1.id]
	w2 = _objects[w2.id]
	_check("sliding a wall by its middle moves it", w2.a == Vector3i(180, 0, 100) and w2.b == Vector3i(180, 0, 160), "%s %s" % [w2.a, w2.b])
	_check("...and the joined wall's end follows", w1.b == Vector3i(180, 0, 100), str(w1.b))
	_check("...the corner stays closed in voxels", world.get_voxel(Vector3i(180, 10, 99)) == M.CONCRETE and world.get_voxel(Vector3i(179, 10, 100)) == M.CONCRETE
			and world.get_voxel(Vector3i(160, 10, 130)) == M.AIR)

	# The length field, and undo.
	_tool.set_wall_length(4.0)
	_check("the length field moves the far end", _objects[w2.id].b == Vector3i(180, 0, 140), str(_objects[w2.id].b))
	edits.undo()
	_check("...and undoes", _objects[w2.id].b == Vector3i(180, 0, 160))

	# The Opening tool: a doorway in the straight wall, aimed at its south face.
	await _key(KEY_8)
	_check("8 picks Opening", _tool.tool == _tool.tools()[7] and _tool.tool == 5, str(_tool.tool))
	await _look(Vector2(130, 115), 0.0, 25.0, 8.0)
	await _click(_screen(Vector3(130.5, 12, 101.0)))
	var doorway := _opening_in(w1.id)
	_check("the Opening tool cuts a doorway in a wall", not doorway.is_empty() and doorway.sill == 0, str(doorway))
	if not doorway.is_empty():
		var x: int = 80 + int(doorway.along) + 2
		_check("...through it, from the floor", world.get_voxel(Vector3i(x, FLOOR_Y, 99)) == M.AIR and world.get_voxel(Vector3i(x, FLOOR_Y + 20, 100)) == M.AIR
				and world.get_voxel(Vector3i(x, FLOOR_Y + 23, 100)) == M.CONCRETE and world.get_voxel(Vector3i(80 + int(doorway.along) - 1, 10, 100)) == M.CONCRETE)

	# ...and in the 45° wall, aimed at its face from the side it faces.
	await _look(Vector2(220, 120), 135.0, 20.0, 8.0)
	await _click(_screen(Vector3(220.8, 12, 119.2)))
	var slanted := _opening_in(w3.id)
	_check("...and in a 45° wall", not slanted.is_empty(), str(_tool.object_under))
	if not slanted.is_empty():
		var middle := Vector2(200, 100) + Vector2(1, 1).normalized() * (int(slanted.along) + 6.0)
		var cut := true
		for dx in [-1, 0, 1]:
			cut = cut and world.get_voxel(Vector3i(floori(middle.x) + dx, 10, floori(middle.y))) == M.AIR
		_check("...cut right through", cut and world.get_voxel(Vector3i(238, 10, 138)) == M.CONCRETE)

	# A door prop: into the straight wall, not into the 45° one.
	await _key(KEY_9)
	_tool.prop_name = DOOR
	await _look(Vector2(110, 115), 0.0, 25.0, 8.0)
	await _move_mouse(_screen(Vector3(110.5, 8, 101.0)))
	await _frames(2)
	_check("a door fits in a straight wall", _tool.prop_spot(DOOR, _tool.facing, "").valid, str(_tool.prop_spot(DOOR, _tool.facing, "")))
	await _click(_screen(Vector3(110.5, 8, 101.0)))
	var door := _find_prop(DOOR)
	_check("...and goes in", not door.is_empty())
	if not door.is_empty():
		var box := LevelSchema.prop_box(door)
		var c := Vector3i(box.get_center())
		_check("...cutting its way through", world.get_voxel(Vector3i(c.x, FLOOR_Y + 2, 99)) == M.AIR and world.get_voxel(Vector3i(c.x, FLOOR_Y + 2, 100)) == M.AIR)
		_check("...with its doorway linked", _objects.values().any(func(o: Dictionary) -> bool: return o.kind == "opening" and o.door == door.id))
	await _look(Vector2(206, 106), 135.0, 20.0, 8.0)
	await _move_mouse(_screen(Vector3(206.4, 8, 105.0)))
	await _frames(2)
	var spot: Dictionary = _tool.prop_spot(DOOR, _tool.facing, "")
	_check("a door doesn't go in a 45° wall", not spot.valid and spot.reason == "doors go in straight walls", str(spot))

	# Sliding the wall carries its door and its opening.
	await _key(KEY_1)
	await _look(Vector2(130, 100), 0.0, 89.0)
	await _click(_screen(Vector3(140, TOP_Y, 100)))
	_check("selecting the wall with the door", _tool.selected == w1.id, _tool.selected)
	await _drag(_screen(Vector3(130, TOP_Y, 100)), _screen(Vector3(130, FLOOR_Y, 110.4)))
	w1 = _objects[w1.id]
	_check("the wall slid", w1.a == Vector3i(80, 0, 110) and w1.b == Vector3i(180, 0, 110), "%s %s" % [w1.a, w1.b])
	_check("...the joined wall followed", _objects[w2.id].a == Vector3i(180, 0, 110))
	if not door.is_empty():
		var moved: Dictionary = _objects.get(door.id, {})
		_check("...the door went with it", moved.get("origin", Vector3i.ZERO) == door.origin + Vector3i(0, 0, 10), str(moved.get("origin")))
		var c := Vector3i(LevelSchema.prop_box(moved).get_center())
		_check("...cutting its way through there", world.get_voxel(Vector3i(c.x, FLOOR_Y + 2, 109)) == M.AIR and world.get_voxel(Vector3i(c.x, FLOOR_Y + 2, 110)) == M.AIR)
	if not doorway.is_empty():
		var x: int = 80 + int(doorway.along) + 2
		_check("...and the doorway", world.get_voxel(Vector3i(x, 10, 109)) == M.AIR and world.get_voxel(Vector3i(x, 10, 99)) == M.AIR
				and world.get_voxel(Vector3i(x - 8, 10, 99)) == M.AIR)

	# Delete takes its openings and its door; undo brings them all back.
	_tool.delete_selected()
	_check("deleting a wall", not _objects.has(w1.id) and _opening_in(w1.id).is_empty() and _find_prop(DOOR).is_empty()
			and world.get_voxel(Vector3i(100, 10, 109)) == M.AIR)
	edits.undo()
	_check("...undo brings it back with its opening and door", _objects.has(w1.id) and not _opening_in(w1.id).is_empty() and not _find_prop(DOOR).is_empty()
			and world.get_voxel(Vector3i(100, 10, 109)) == M.CONCRETE)

	# Merge two walls in line (the second with an opening), then split the result.
	edits.put_objects([["", LevelBuild.new_wall(0, Vector3i(300, 0, 200), Vector3i(330, 0, 200), M.CONCRETE)],
			["", LevelBuild.new_wall(0, Vector3i(330, 0, 200), Vector3i(360, 0, 200), M.CONCRETE)],
			["", LevelSchema.new_wall_opening("$1", 5, 10, 0, 20)]])
	var w4 := _wall_from(Vector2i(300, 200))
	var w5 := _wall_from(Vector2i(330, 200))
	_tool.select(w4.id)
	_tool.merge_selected()
	w4 = _objects[w4.id]
	var merged_opening := _opening_in(w4.id)
	_check("Merge joins walls in line", w4.b == Vector3i(360, 0, 200) and not _objects.has(w5.id), str(w4.b))
	_check("...its openings move over, where they were", merged_opening.get("along", -1) == 35, str(merged_opening))
	_check("...the voxels are the same", world.get_voxel(Vector3i(337, 10, 200)) == M.AIR and world.get_voxel(Vector3i(330, 10, 200)) == M.CONCRETE)
	_tool.split_selected()
	var second := _wall_from(Vector2i(330, 200))
	_check("Split cuts it in two at its middle", _objects[w4.id].b == Vector3i(330, 0, 200) and second.get("b") == Vector3i(360, 0, 200), str(second))
	_check("...the opening goes with its half", not second.is_empty() and _opening_in(second.id).get("along", -1) == 5)
	_check("...and the voxels are the same", world.get_voxel(Vector3i(337, 10, 200)) == M.AIR and world.get_voxel(Vector3i(330, 10, 200)) == M.CONCRETE)
	_finish()


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


func _find_prop(prop_name: String) -> Dictionary:
	for object: Dictionary in _objects.values():
		if object.kind == "prop" and object.name == prop_name:
			return object
	return {}


## The screen point over a voxel-space point.
func _screen(at: Vector3) -> Vector2:
	return _camera.camera.unproject_position(_lab.view.to_world(at))


## Looks at a spot (voxels x, z) on storey 0's floor.
func _look(at: Vector2, yaw: float, pitch: float, distance := 12.0) -> void:
	_camera.pivot = _lab.view.to_world(Vector3(at.x, FLOOR_Y, at.y))
	_camera.yaw = yaw
	_camera.pitch = pitch
	_camera.distance = distance
	_camera.snap_to_target()
	await _frames(2)


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
	print("build edit test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
