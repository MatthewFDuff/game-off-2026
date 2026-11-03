extends SceneTree
## Floor plans of the laboratory level, shot from the editor's builder view with a manual cutaway
## just under each floor's ceiling (needs a window, not --headless):
##   godot --path . --script res://tests/laboratory_shots.gd -- <output_dir>
## Works on a scratch copy of res://levels/laboratory. One top-down shot per floor
## (floor_g, floor_0, floor_m1, floor_m2, floor_m3, floor_dig), then a few angled views.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://laboratory_shots_levels/"
const LEVEL := "laboratory_shots"
const Layout := preload("res://scripts/tools/lab_layout.gd")
## Floor name -> the cut layer (voxels): just under that floor's ceiling, so walls and props show.
const FLOORS := {floor_g = 290, floor_0 = 250, floor_m1 = 210, floor_m2 = 170, floor_m3 = 130, floor_dig = 30}

var _out := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	root.size = Vector2i(1400, 1400)
	LevelData.save_dir_override = SCRATCH
	var to := SCRATCH.path_join(LEVEL)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to))
	for file in ["level.json", "voxels.bin"]:
		FileAccess.open(to.path_join(file), FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes("res://levels/laboratory".path_join(file)))
	root.get_node("Net").start_solo(LEVEL, "edit")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	var lab = current_scene
	var me = lab.local_player()
	var tool = me.get_node("EditorTool")
	await _frames(20)
	var camera = tool.camera
	var size: Vector3 = Vector3(lab.world.get_size_in_voxels()) * lab.world.voxel_size
	var center: Vector3 = lab.world.global_position + Vector3(size.x * 0.5, 0.0, size.z * 0.5)

	camera.set_cut_mode(2)
	for name in FLOORS:
		var y: int = FLOORS[name]
		camera.cut_layer = y + 32
		camera.pivot = Vector3(center.x, lab.world.global_position.y + y * lab.world.voxel_size, center.z)
		camera.yaw = 0.0
		camera.pitch = 89.0
		camera.distance = 62.0
		camera.snap_to_target()
		await _frames(30)
		await _shot(name)

	# Angled views: the yard and gatehouse, the server hall, the mother cavern and the generator hall.
	var views := {
		yard = [Vector3(39.0, 29.0, 6.0), 290, 55.0, 24.0, 20.0],
		server_hall = [Vector3(30.0, 17.0, 11.0), 170, 60.0, 30.0, 25.0],
		cavern = [Vector3(7.0, 3.0, 30.0), 30, 100.0, 45.0, 45.0],
		generator_hall = [Vector3(27.0, 3.0, 33.0), 30, 70.0, 30.0, 25.0],
	}
	for name in views:
		var v: Array = views[name]
		camera.cut_layer = int(v[1]) + 40
		camera.pivot = v[0]
		camera.yaw = float(v[2])
		camera.pitch = float(v[3])
		camera.distance = float(v[4])
		camera.snap_to_target()
		await _frames(30)
		await _shot("view_" + name)
	quit(0)


func _shot(name: String) -> void:
	await _frames(3)
	var path := _out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
