extends SceneTree
## Props that sit on things (PropPlacement) and door props, headless:
##   godot --headless --path . --script res://tests/editor_prop_test.gd
## Floor props on floors and against walls, wall props on walls, push-out from walls and other
## props, ceiling props (flush under a ceiling, refused on floors and walls; "any" props on all three),
## floating and wrong-face placements refused, a crate on a desk, floor markers, the Prop
## tool's red ghost, the level check, the warning after a resize, and a door between two rooms:
## its doorway through the wall, its hidden pocket, and sliding open and shut in play. Works on a
## scratch copy of the lab level, in rock high above it.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://editor_prop_test_levels/"
const LEVEL := "lab_prop_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
## Room A (inside) and room B just north of it, sharing a 6-voxel wall (z 94 to 100).
const A_FROM := Vector3i(100, 200, 100)
const A_TO := Vector3i(140, 230, 130)
const B_FROM := Vector3i(100, 200, 70)
const B_TO := Vector3i(140, 230, 94)

var _failures := 0
var _notices: Array[String] = []


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
	var world = lab.world
	lab.notice.connect(func(text: String) -> void: _notices.append(text))
	await _frames(5)
	lab.edits.put_objects([["", LevelSchema.new_room(A_FROM, A_TO, M.TILE_LIGHT, M.WALL_PAINT, M.CONCRETE, 3, 1000)],
			["", LevelSchema.new_room(B_FROM, B_TO, M.TILE_LIGHT, M.WALL_PAINT, M.CONCRETE, 3, 1001)]])
	await _frames(2)
	var objects: Dictionary = lab.level.objects
	var up := Vector3i.UP
	var east := Vector3i(1, 0, 0)

	# Floor props.
	var spot = PropPlacement.place(world, objects, "crate_8", 0, Vector3i(120, 200, 115), Vector3i(120, 199, 115), up, 5)
	_check("crate on the floor rests on it", spot.valid and spot.origin.y == 200, str(spot))
	spot = PropPlacement.place(world, objects, "crate_8", 0, Vector3i(100, 215, 115), Vector3i(99, 215, 115), east, 5)
	_check("crate aimed at a wall: on the floor, back to the wall, facing out", spot.valid and spot.origin.y == 200 and spot.origin.x == 100 and spot.facing == 1, str(spot))
	spot = PropPlacement.place(world, objects, "crate_8", 0, Vector3i(100, 200, 115), Vector3i(100, 199, 115), up, 5)
	_check("crate overlapping the wall is pushed out of it", spot.valid and spot.origin.x == 100 and spot.origin.y == 200, str(spot))
	spot = PropPlacement.place(world, objects, "crate_8", 0, Vector3i(120, 215, 115), Vector3i(120, 214, 115), up, 5)
	_check("crate in mid-air is refused", not spot.valid and spot.reason.contains("sit on"), str(spot))

	# Wall props.
	spot = PropPlacement.place(world, objects, "whiteboard", 0, Vector3i(100, 215, 115), Vector3i(99, 215, 115), east, 5)
	_check("whiteboard on a wall: flush, facing out", spot.valid and spot.origin.x == 100 and spot.facing == 1 and spot.origin.y > 200, str(spot))
	spot = PropPlacement.place(world, objects, "whiteboard", 0, Vector3i(120, 200, 115), Vector3i(120, 199, 115), up, 5)
	_check("whiteboard on a floor is refused", not spot.valid and spot.reason.contains("wall"), str(spot))
	spot = PropPlacement.place(world, objects, "whiteboard", 1, Vector3i(100, 215, 115), Vector3i(99, 215, 115), east, 5)
	_check("R turns a wall prop from facing out", spot.facing == 2)

	# Ceiling props hang from a downward face with their top flush; "any" props go on all three.
	var down := Vector3i.DOWN
	var troffer_h := int(LevelSchema.prop_box({kind = "prop", name = "fixture_troffer", origin = Vector3i.ZERO, facing = 0}).size.y)
	spot = PropPlacement.place(world, objects, "fixture_troffer", 0, Vector3i(120, A_TO.y - 1, 115), Vector3i(120, A_TO.y, 115), down, 5)
	_check("troffer under the ceiling: top flush with it", spot.valid and spot.mount == "ceiling" and spot.origin.y + troffer_h == A_TO.y, str(spot))
	spot = PropPlacement.place(world, objects, "fixture_troffer", 0, Vector3i(120, 200, 115), Vector3i(120, 199, 115), up, 5)
	_check("troffer on a floor is refused", not spot.valid and spot.reason.contains("ceiling"), str(spot))
	spot = PropPlacement.place(world, objects, "fixture_troffer", 0, Vector3i(100, 215, 115), Vector3i(99, 215, 115), east, 5)
	_check("troffer on a wall is refused", not spot.valid and spot.reason.contains("ceiling"), str(spot))
	spot = PropPlacement.place(world, objects, "duct_straight", 1, Vector3i(120, A_TO.y - 1, 115), Vector3i(120, A_TO.y, 115), down, 5)
	_check("R turns a ceiling prop", spot.valid and spot.facing == 1, str(spot))
	spot = PropPlacement.place(world, objects, "fixture_troffer", 0, Vector3i(120, A_TO.y - 1, 115), Vector3i(120, A_TO.y, 115), up, 5)
	_check("ceiling prop with nothing above is refused", not spot.valid, str(spot))
	for aim: Array in [["wall", Vector3i(100, 215, 115), Vector3i(99, 215, 115), east], ["ceiling", Vector3i(120, A_TO.y - 1, 115), Vector3i(120, A_TO.y, 115), down],
			["floor", Vector3i(120, 200, 115), Vector3i(120, 199, 115), up]]:
		spot = PropPlacement.place(world, objects, "fixture_bulkhead", 0, aim[1], aim[2], aim[3], 5)
		_check("bulkhead (any) on a %s" % aim[0], spot.valid and spot.mount == aim[0], str(spot))
	# Moving an "any" prop that faces south on a ceiling onto the west wall: it faces out of the
	# wall (east), not one turn off; back on the ceiling it keeps its facing; R still turns it.
	var hung = LevelSchema.new_prop("fixture_bulkhead", Vector3i(118, A_TO.y - 3, 113), 2)
	tool._grab = hung
	tool._grab_id = ""
	tool._grab_rotation = tool._start_rotation(hung)
	for aim: Array in [["wall", Vector3i(100, 215, 115), Vector3i(99, 215, 115), east, 1], ["ceiling", Vector3i(120, A_TO.y - 1, 115), Vector3i(120, A_TO.y, 115), down, 2]]:
		tool.cell = aim[1]
		tool.solid_cell = aim[2]
		tool.cursor_normal = aim[3]
		var moved: Dictionary = hung.duplicate()
		tool._place_grab(moved)
		_check("moved bulkhead onto the %s faces %d" % [aim[0], aim[4]], tool._spot.valid and moved.facing == aim[4], "%s %s" % [moved.facing, tool._spot])
	tool._grab_rotation += 1
	tool.cell = Vector3i(100, 215, 115)
	tool.solid_cell = Vector3i(99, 215, 115)
	tool.cursor_normal = east
	var turned: Dictionary = hung.duplicate()
	tool._place_grab(turned)
	_check("...and R turns it from facing out of the wall", turned.facing == 2, str(turned.facing))
	tool._grab = {}

	# A crate on a desk: other props count as something to sit on, and as something to avoid.
	var desk = LevelSchema.new_prop("desk", Vector3i(110, 200, 110), 0)
	lab.edits.put_object(desk)
	await _frames(2)
	var desk_box := LevelSchema.prop_box(desk)
	var top := Vector3i(int(desk_box.get_center().x), int(desk_box.end.y), int(desk_box.get_center().z))
	spot = PropPlacement.place(world, objects, "crate_5", 0, top, top + Vector3i.DOWN, up, 1)
	_check("crate on the desk sits on it", spot.valid and spot.origin.y == int(desk_box.end.y), str(spot))
	spot = PropPlacement.place(world, objects, "crate_5", 0, Vector3i(top.x, 200, top.z), Vector3i(top.x, 199, top.z), up, 1)
	_check("crate under the desk is pushed out of it", spot.valid and not LevelSchema.prop_box({kind = "prop", name = "crate_5", origin = spot.origin, facing = 0}).intersects(desk_box), str(spot))

	# Floor markers drop to the floor; the Prop tool's ghost goes red with no spot and won't place.
	tool.cell = Vector3i(100, 215, 115)
	_check("spawns stand on the floor", is_equal_approx(tool._marker_position("spawn").y, 200.0))
	_check("lights stay where they're put", is_equal_approx(tool._marker_position("light").y, 215.0))
	tool.set_view(false)
	me.teleport(lab.view.to_world(Vector3(120, 210, 115)))
	me.rotation.y = 0.0
	me.head.rotation.x = -PI * 0.49
	me.flying = true
	tool.set_tool(6) # Prop
	tool.prop_name = "whiteboard"
	await _frames(3)
	_check("whiteboard aimed at the floor: red ghost", tool.has_cursor and not tool._spot.valid and tool._ghost.material_override == tool._invalid_material)
	var count: int = lab.level.objects.size()
	await _click()
	_check("...and clicking places nothing", lab.level.objects.size() == count)
	tool.prop_name = "crate_8"
	await _frames(2)
	_check("crate aimed at the floor: real ghost", tool._spot.valid and tool._ghost.material_override == world.material)
	await _click()
	_check("...and clicking places it", lab.level.objects.size() == count + 1)
	tool.prop_name = "fixture_troffer"
	await _frames(2)
	_check("troffer aimed at the floor: red ghost", tool.has_cursor and not tool._spot.valid and tool._ghost.material_override == tool._invalid_material)
	me.head.rotation.x = PI * 0.49
	await _frames(3)
	_check("troffer aimed at the ceiling: real ghost, flush under it", tool._spot.valid and tool._spot.origin.y + troffer_h == A_TO.y
			and tool._ghost.material_override == world.material, str(tool._spot))
	await _click()
	_check("...and clicking hangs it", lab.level.objects.size() == count + 2)
	me.head.rotation.x = -PI * 0.49
	await _frames(2)

	# The level check finds a floating crate and one inside a wall.
	lab.edits.put_object(LevelSchema.new_prop("crate_6", Vector3i(130, 215, 120), 0).merged({id = "float_crate"}))
	lab.edits.put_object(LevelSchema.new_prop("crate_6", Vector3i(96, 200, 120), 0).merged({id = "buried_crate"}))
	# ...and a floating ceiling prop, but not one hung properly or an "any" prop on a wall.
	lab.edits.put_object(LevelSchema.new_prop("smoke_detector", Vector3i(125, 222, 104), 0).merged({id = "float_detector"}))
	lab.edits.put_object(LevelSchema.new_prop("fixture_troffer", Vector3i(102, A_TO.y - troffer_h, 122), 0).merged({id = "hung_troffer"}))
	lab.edits.put_object(LevelSchema.new_prop("fixture_bulkhead", Vector3i(100, 215, 104), 1).merged({id = "wall_bulkhead"}))
	await _frames(2)
	var found := PropPlacement.problems(world, lab.level.objects)
	var ids: Array = found.map(func(f: Dictionary) -> String: return f.id)
	_check("level check finds the floating crate", "float_crate" in ids)
	_check("...and the buried one", "buried_crate" in ids)
	_check("...and the floating ceiling prop", "float_detector" in ids)
	_check("...and nothing standing or hanging properly", not desk.get("id", "x") in ids and ids.size() == 3, str(found))
	for id in ["float_crate", "buried_crate", "float_detector", "hung_troffer", "wall_bulkhead"]:
		lab.edits.remove_object(id)
	await _frames(2)

	# Shrinking room A past the desk leaves it inside the new wall: a warning.
	var room_a := ""
	for object: Dictionary in lab.level.objects.values():
		if object.kind == "room" and object.from == A_FROM:
			room_a = object.id
	var smaller: Dictionary = lab.level.objects[room_a].duplicate()
	smaller.from = A_FROM + Vector3i(15, 0, 0)
	_notices.clear()
	tool._commit_resize(smaller)
	await create_timer(0.6).timeout
	_check("a resize that buries a prop warns", _notices.any(func(t: String) -> bool: return t.contains("floating or inside")), str(_notices))
	tool._commit_resize(lab.level.objects[room_a].merged({from = A_FROM}, true))
	await _frames(2)

	# A door in the wall between A and B: the doorway goes through, the pocket stays hidden.
	spot = PropPlacement.place(world, lab.level.objects, "door_single", 0, Vector3i(110, 210, 100), Vector3i(110, 210, 99), Vector3i(0, 0, 1), 1)
	_check("door: in the wall's middle, on the floor", spot.valid and spot.origin.y == 200 and spot.door_ahead + spot.door_behind == 5 and spot.door_offset == Vector3i(12, 0, 0), str(spot))
	var door = tool._placed(LevelSchema.new_prop("door_single", spot.origin, spot.facing), spot)
	_check("door props start as doors", door.door == true)
	lab.edits.put_object(door.merged({id = "test_door"}))
	await _frames(2)
	var linked := {}
	for object: Dictionary in lab.level.objects.values():
		if object.kind == "opening" and object.door == "test_door":
			linked[object.type] = object
	_check("door cut a doorway and a pocket", linked.has("doorway") and linked.has("slot"), str(linked.keys()))
	var panel_z: int = spot.origin.z
	_check("walk through: air from room to room", world.get_voxel(Vector3i(110, 205, 94)) == M.AIR and world.get_voxel(Vector3i(110, 205, 99)) == M.AIR)
	var pocket := Vector3i(spot.origin.x + 12 + 5, 205, panel_z)
	_check("pocket is cut inside the wall", world.get_voxel(pocket) == M.AIR)
	_check("...hidden from both rooms", world.get_voxel(Vector3i(pocket.x, 205, 99)) != M.AIR and world.get_voxel(Vector3i(pocket.x, 205, 94)) != M.AIR)

	# Play: the door slides into its pocket and back, the wall stays whole.
	lab.request_mode("play")
	await _frames(5)
	var closed: Vector3i = spot.origin + Vector3i(5, 5, 0)
	_check("closed door is solid", world.get_voxel(closed) != M.AIR)
	lab.play.set_door("test_door", true)
	await create_timer(1.0).timeout
	_check("open: the doorway is clear", world.get_voxel(closed) == M.AIR)
	_check("open: the door is in its pocket", world.get_voxel(pocket) != M.AIR)
	lab.play.set_door("test_door", false)
	await create_timer(1.0).timeout
	_check("shut again, the pocket is empty and the wall beside it whole", world.get_voxel(closed) != M.AIR and world.get_voxel(pocket) == M.AIR
			and world.get_voxel(Vector3i(pocket.x, 205, 99)) != M.AIR)
	lab.request_mode("edit")
	await _frames(3)
	_finish()


func _finish() -> void:
	print("editor prop test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _click() -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
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
