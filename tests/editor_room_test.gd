extends SceneTree
## Rooms and openings as level objects (structure edits, VoxelWorld.apply_structure), headless:
##   godot --headless --path . --script res://tests/editor_room_test.gd
## A room carved in rock, resized (painted wall detail survives where the wall stays, an old wall
## becomes air where it moved away), re-lined, an opening cut and removed, a door prop cutting and
## carrying its own opening, undo / redo, and deleting a room filling it back with rock. Works on a
## scratch copy of the lab level (a rock level).
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://editor_room_test_levels/"
const LEVEL := "lab_room_test"
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
	var world = lab.world
	var edits = lab.edits
	await _frames(5)

	# A 2.5 x 3 x 2 m room in solid rock high above the lab (inside x 100-125, y 200-230, z 100-120).
	var from := Vector3i(100, 200, 100)
	var inside_to := Vector3i(125, 230, 120)
	_check("solid rock there to start", _count_air(world, from - Vector3i(5, 5, 5), inside_to + Vector3i(15, 15, 5)) == 0)
	var room = LevelSchema.new_room(from, inside_to, M.TILE_LIGHT, M.WALL_PAINT, M.CONCRETE, 3, 1000)
	edits.put_object(room)
	await _frames(2)
	var room_id := _find(lab, "room", from)
	_check("room object added", room_id != "")
	room = lab.level.objects.get(room_id, {})
	_check("inside carved", _count_air(world, from, inside_to) == 25 * 30 * 20)
	_check("floor lined", world.get_voxel(Vector3i(110, 199, 110)) == M.TILE_LIGHT and world.get_voxel(Vector3i(110, 197, 110)) == M.TILE_LIGHT)
	_check("lining is 3 thick", world.get_voxel(Vector3i(110, 196, 110)) != M.TILE_LIGHT)
	_check("walls lined", world.get_voxel(Vector3i(99, 210, 110)) == M.WALL_PAINT and world.get_voxel(Vector3i(125, 210, 110)) == M.WALL_PAINT)
	_check("ceiling lined", world.get_voxel(Vector3i(110, 230, 110)) == M.CONCRETE)

	# Paint detail on the west wall (stays) and the east wall (will move away).
	edits.voxel_op({type = "box", from = Vector3i(99, 210, 105), to = Vector3i(100, 212, 107), material = M.METAL})
	edits.voxel_op({type = "box", from = Vector3i(125, 210, 105), to = Vector3i(126, 212, 107), material = M.METAL})
	await _frames(2)

	# Resize: the east wall moves out 10 voxels and the room gets 1 m taller.
	var bigger: Dictionary = room.duplicate()
	bigger.to = inside_to + Vector3i(10, 10, 0)
	edits.put_object(bigger, room_id)
	await _frames(2)
	_check("resized object", lab.level.objects[room_id].to == bigger.to)
	_check("grown inside carved", _count_air(world, from, bigger.to) == 35 * 40 * 20)
	_check("old east wall is air, paint and all", world.get_voxel(Vector3i(125, 210, 105)) == M.AIR and world.get_voxel(Vector3i(126, 210, 110)) == M.AIR)
	_check("new east wall lined", world.get_voxel(Vector3i(135, 210, 110)) == M.WALL_PAINT)
	_check("west wall detail survives", world.get_voxel(Vector3i(99, 210, 105)) == M.METAL)
	_check("old ceiling height is air now", world.get_voxel(Vector3i(110, 232, 110)) == M.AIR)

	# Re-line the walls: unpainted wall changes, the detail stays.
	var relined: Dictionary = lab.level.objects[room_id].duplicate()
	relined.wall = M.PLANK
	edits.put_object(relined, room_id)
	await _frames(2)
	_check("re-lined walls", world.get_voxel(Vector3i(99, 210, 115)) == M.PLANK, str([world.get_voxel(Vector3i(99, 210, 115)), world.get_voxel(Vector3i(98, 210, 115)), world.get_voxel(Vector3i(99, 210, 111))]))
	_check("...not the detail", world.get_voxel(Vector3i(99, 210, 105)) == M.METAL)
	_check("...not the floor", world.get_voxel(Vector3i(110, 199, 110)) == M.TILE_LIGHT)

	# An opening through the south wall (z 120-123), and taking it away again.
	edits.put_object(LevelSchema.new_opening(Vector3i(110, 200, 120), Vector3i(120, 222, 123), room_id))
	await _frames(2)
	var opening_id := _find(lab, "opening", Vector3i(110, 200, 120))
	_check("opening cut", opening_id != "" and _count_air(world, Vector3i(110, 200, 120), Vector3i(120, 222, 123)) == 10 * 22 * 3)
	edits.remove_object(opening_id)
	await _frames(2)
	_check("opening removed: wall back", world.get_voxel(Vector3i(115, 210, 121)) == M.PLANK and _count_air(world, Vector3i(110, 200, 120), Vector3i(120, 222, 123)) == 0)

	# A door prop in the north wall cuts its own opening and carries it when it moves.
	var door = LevelSchema.new_prop("crate_8", Vector3i(105, 200, 97), 0)
	door.door = true
	edits.put_object(door)
	await _frames(2)
	var door_id := _find(lab, "prop", Vector3i(105, 200, 97))
	var link := _linked(lab, door_id)
	_check("door got a linked opening", link != "" and lab.level.objects[link].room == room_id)
	var box := LevelSchema.prop_box(lab.level.objects[door_id])
	_check("door's opening is cut", _count_air(world, Vector3i(box.position), Vector3i(box.end)) == int(box.size.x * box.size.y * box.size.z))
	var moved: Dictionary = lab.level.objects[door_id].duplicate()
	moved.origin = Vector3i(115, 200, 97)
	edits.put_object(moved, door_id)
	await _frames(2)
	_check("opening moved with the door", _linked(lab, door_id) == link and lab.level.objects[link].from == Vector3i(115, 200, 97))
	_check("old door hole walled up", world.get_voxel(Vector3i(Vector3i(box.position) + Vector3i(1, 1, 1))) != M.AIR)
	edits.remove_object(door_id)
	await _frames(2)
	_check("deleting the door removes its opening", _linked(lab, door_id) == "" and not lab.level.objects.has(link))

	# Undo the door removal: the door and its opening come back together.
	edits.undo()
	await _frames(2)
	_check("undo brings the door and its opening back", lab.level.objects.has(door_id) and _linked(lab, door_id) == link)
	edits.redo()
	await _frames(2)
	_check("redo removes them again", not lab.level.objects.has(door_id) and not lab.level.objects.has(link))

	# Delete the room: inside and lining go back to rock.
	edits.remove_object(room_id)
	await _frames(2)
	_check("deleted room fills back with rock", world.get_voxel(Vector3i(110, 210, 110)) == M.ROCK and world.get_voxel(Vector3i(99, 210, 115)) == M.ROCK)
	edits.undo()
	await _frames(2)
	_check("undo restores the room and its voxels", lab.level.objects.has(room_id) and world.get_voxel(Vector3i(110, 210, 110)) == M.AIR
			and world.get_voxel(Vector3i(99, 210, 105)) == M.METAL)

	# A room overlapping the atrium (hand-carved voxels, no room object) leaves the atrium open.
	var atrium_air: int = _count_air(world, Vector3i(206, 41, 222), Vector3i(215, 60, 240))
	edits.put_object(LevelSchema.new_room(Vector3i(190, 40, 225), Vector3i(208, 60, 240), M.TILE_LIGHT, M.WALL_PAINT, M.CONCRETE, 3, 1001))
	await _frames(2)
	_check("joining room doesn't wall up the atrium", _count_air(world, Vector3i(206, 41, 222), Vector3i(215, 60, 240)) >= atrium_air)

	# Saved and loaded back as objects.
	lab.request_save()
	await _frames(4)
	var loaded = LevelData.load_level(LEVEL)
	var saved: Dictionary = loaded.objects.get(room_id, {})
	_check("room saves with Vector3i corners", saved.get("from") == from and saved.get("to") == bigger.to and saved.get("wall") is int, str(saved))
	_finish()


func _find(lab, kind: String, from: Vector3i) -> String:
	for object: Dictionary in lab.level.objects.values():
		if object.kind == kind and (object.get("from", object.get("origin")) == from):
			return object.id
	return ""


func _linked(lab, door_id: String) -> String:
	for object: Dictionary in lab.level.objects.values():
		if object.kind == "opening" and object.door == door_id:
			return object.id
	return ""


func _count_air(world, from: Vector3i, to: Vector3i) -> int:
	var count := 0
	for b in world.get_box(from, to):
		if b == 0:
			count += 1
	return count


func _finish() -> void:
	print("editor room test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
