extends SceneTree
## Screenshots of the level editor (needs a window, not --headless):
##   godot --path . --script res://tests/editor_screenshots.gd -- <output_dir>
## Works on a scratch copy of the lab. Paints a strip of each pattern material on the atrium's west
## wall, then shoots the box tool, the room tool, the prop browser, markers, the inspector and a
## play-test view.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://editor_shots_levels/"
const LEVEL := "lab_shots"
const M := preload("res://scripts/voxel/voxel_materials.gd")

var _out := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	root.size = Vector2i(1600, 900)
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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _frames(10)

	# Pattern strips on the atrium's west wall (x 203-206), 2 m wide, floor to 3 m.
	var patterned: Array[int] = M.patterned()
	for i in patterned.size():
		var z := 222 + i * 22
		lab.edits.voxel_op({type = "box", from = Vector3i(203, 40, z), to = Vector3i(206, 70, z + 20), material = patterned[i]})
	lab.edits.voxel_op({type = "box", from = Vector3i(210, 39, 222), to = Vector3i(240, 40, 330 - 18), material = M.LARGE_TILE})

	# Box tool with a corner down, looking at the pattern wall.
	_look(me, Vector3(24.5, 5.0, 27.0), Vector3(20.4, 5.0, 27.0))
	tool.set_tool(2)
	tool.material = M.BLOCK_WALL
	await _frames(4)
	tool._corner = Vector3i(206, 40, 240)
	await _shot("editor_box_patterns")
	tool.cancel()

	_look(me, Vector3(27.0, 6.0, 33.0), Vector3(20.4, 4.0, 26.0))
	tool.set_tool(1)
	await _frames(4)
	tool._corner = tool.solid_cell + Vector3i(0, 0, -20)
	await _shot("editor_room")
	tool.cancel()

	# Prop browser: give the thumbnails time to render.
	_look(me, Vector3(40.0, 5.5, 25.0), Vector3(44.0, 4.0, 25.0))
	tool.set_tool(5)
	tool.prop_name = "fume_hood"
	await _frames(90)
	lab.get_node("EditorHud")._refresh()
	await _frames(4)
	await _shot("editor_props")

	# Markers and the inspector on a light.
	_look(me, Vector3(25.6, 6.5, 33.0), Vector3(25.6, 6.0, 25.0))
	tool.set_tool(0)
	var light_id := ""
	for id in lab.level.objects:
		var object = lab.level.objects[id]
		if object.kind == "marker" and object.type == "light":
			light_id = id
			break
	tool.select(light_id)
	await _frames(6)
	await _shot("editor_select_light")

	lab.request_mode("play")
	_look(me, Vector3(24.0, 4.0 + 1.6, 27.0), Vector3(20.4, 5.0, 27.0))
	me.flying = true # Hold the view still for the shot.
	await _frames(20)
	await _shot("play_patterns")
	quit()


## Puts the player's eyes at eye and aims at target.
func _look(player, eye: Vector3, target: Vector3) -> void:
	player.teleport(eye - Vector3.UP * (player.standing_height - player.eye_offset))
	var direction := (target - eye).normalized()
	player.rotation.y = atan2(-direction.x, -direction.z)
	player.head.rotation.x = asin(direction.y)


func _shot(name: String) -> void:
	await _frames(3)
	var path := _out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
