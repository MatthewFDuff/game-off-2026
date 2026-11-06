extends SceneTree
## Moving prop parts (PropMotion), headless:
##   godot --headless --path . --script res://tests/prop_motion_test.gd
## A security camera under a ceiling in a scratch copy of the lab level: in edit mode it's one still
## mesh (arm and head) and nothing moves; in play only the arm is stamped (and counted as the asset),
## the head is a mesh that pans and whose LED blinks; shooting the arm away drops the head and it's
## gone; back in edit nothing animates.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://prop_motion_test_levels/"
const LEVEL := "lab_motion_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const FROM := Vector3i(100, 200, 100)
const TO := Vector3i(140, 230, 130)
const CAMERA_AT := Vector3i(118, 225, 112)

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
	var motion = lab.view.motion
	await _frames(5)

	# The model: the stamped camera is the arm only, in the camera's old frame.
	var arm: Dictionary = Props.oriented("security_camera", Props.NORTH)
	var head: Dictionary = Props.oriented("security_camera_head", Props.NORTH)
	_check("the arm keeps the camera's frame (4 x 5 x 8)", arm.size == Vector3i(4, 5, 8), str(arm.get("size")))
	_check("the arm is only a few steel voxels, the head a model of its own", _solid(arm) == 18 and _solid(head) > 50, "%d / %d" % [_solid(arm), _solid(head)])
	var whole: Dictionary = load("res://scripts/world/prop_motion.gd").display_model("security_camera", Props.EAST)
	_check("editor views draw arm and head together", _solid(whole) == _solid(arm) + _solid(head) and whole.size == Vector3i(8, 5, 4), str(whole.get("size")))

	lab.edits.put_objects([["", LevelSchema.new_room(FROM, TO, M.TILE_LIGHT, M.WALL_PAINT, M.CONCRETE, 3, 1000)]])
	var camera_prop := LevelSchema.new_prop("security_camera", CAMERA_AT, Props.NORTH)
	lab.edits.put_objects([["", camera_prop]])
	await _frames(3)
	var id := ""
	for object: Dictionary in lab.level.objects.values():
		if object.kind == "prop" and object.name == "security_camera" and object.origin == CAMERA_AT:
			id = object.id
	_check("camera placed", id != "")
	_check("edit: nothing animates", motion.parts().is_empty() and not motion.active)
	var edit_node = lab.view._nodes.get(id)
	_check("edit: the camera is one still mesh with its head", edit_node is MeshInstance3D and edit_node.mesh != null
			and edit_node.mesh.get_aabb().size.y > 0.45, str(edit_node.mesh.get_aabb() if edit_node else null))

	# Play: the arm is stamped, the head hangs under it and moves.
	lab.request_mode("play")
	await _frames(5)
	var me = lab.local_player()
	me.teleport(lab.view.to_world(Vector3(120, 200, 118)))
	await _frames(3)
	_check("play: arm stamped", world.get_voxel(CAMERA_AT + Vector3i(1, 3, 3)) == M.STEEL)
	_check("play: head not stamped", world.get_voxel(CAMERA_AT + Vector3i(1, 1, 2)) == M.AIR)
	var asset: Dictionary = lab.play._assets.get(id, {})
	_check("play: the asset counts the arm", asset.get("total", 0) == _solid(arm), str(asset.get("total")))
	_check("play: one moving part", motion.parts().size() == 1, str(motion.parts().size()))
	if motion.parts().size() != 1:
		_finish()
		return
	var part: Dictionary = motion.parts()[0]
	var pivot = part.pivot
	_check("play: the head is shown and hanging", pivot.visible and part.state == "hanging", part.state)
	var yaws: Array[float] = []
	var lit := {}
	for i in 30:
		await create_timer(0.1).timeout
		yaws.append(pivot.rotation.y)
		lit[part.led.visible] = true
	var low: float = yaws.min()
	var high: float = yaws.max()
	_check("play: the head pans", high - low > deg_to_rad(10.0), "%.2f to %.2f" % [low, high])
	_check("play: the pan stays within 40 degrees", absf(low) <= deg_to_rad(40.5) and absf(high) <= deg_to_rad(40.5))
	_check("play: the LED blinks", lit.has(true) and lit.has(false), str(lit.keys()))

	# Shoot the arm away: the head drops and is gone.
	var damage_before: int = lab.play.total_damage
	lab.world_sync.carve_sphere(lab.view.to_world(Vector3(CAMERA_AT) + Vector3(2.0, 3.5, 4.0)), 0.35, 10, Vector3.DOWN)
	await _frames(3)
	_check("shot: the arm is gone", world.get_voxel(CAMERA_AT + Vector3i(1, 3, 3)) == M.AIR and world.get_voxel(CAMERA_AT + Vector3i(2, 3, 3)) == M.AIR)
	_check("shot: the payroll bills the camera", lab.play.total_damage > damage_before, str(lab.play.total_damage))
	await create_timer(0.3).timeout
	_check("shot: the head falls, dark", part.state in ["falling", "gone"] and not part.led.visible, part.state)
	var start_y: float = lab.view.to_world(Vector3(CAMERA_AT) + Vector3(0, 3, 0)).y
	_check("shot: ... down from the arm", part.state == "gone" or pivot.global_position.y < start_y - 0.05)
	await create_timer(1.6).timeout
	_check("shot: the head is gone", part.state == "gone" and not is_instance_valid(pivot), part.state)

	# Back to edit: nothing animates, the camera is whole again.
	lab.request_mode("edit")
	await _frames(3)
	_check("edit again: nothing animates", motion.parts().is_empty() and not motion.active)
	_check("edit again: no moving nodes left", motion.get_child_count() == 0, str(motion.get_child_count()))
	_finish()


func _solid(model: Dictionary) -> int:
	var count := 0
	for material in model.get("voxels", PackedByteArray()):
		if material != 0:
			count += 1
	return count


func _finish() -> void:
	print("prop motion test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
