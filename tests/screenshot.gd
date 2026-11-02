extends SceneTree
## Renders the test world from a few viewpoints and saves PNGs. Needs a window (not --headless):
##   godot --path . --script res://tests/screenshot.gd -- <output_dir>

const VIEWS := [
	{name = "hall", pos = Vector3(24, 2.2, 42), yaw = -135.0, pitch = -8.0},
	{name = "tunnel", pos = Vector3(42, 2.2, 32), yaw = -90.0, pitch = -5.0},
	{name = "crater", pos = Vector3(36, 2.2, 28), yaw = -90.0, pitch = -10.0},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else OS.get_user_data_dir()
	root.size = Vector2i(1280, 720)

	var scene: Node3D = load("res://scenes/test_world.tscn").instantiate()
	root.add_child(scene)
	var world: VoxelWorld = scene.get_node("VoxelWorld")
	var player: Player = scene.get_node("Player")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.set_physics_process(false)
	await process_frame

	# A few blasts so destroyed terrain shows up in the shots.
	for z in [24.0, 27.0, 31.0]:
		world.carve_sphere(Vector3(44.0, 3.5, z), 1.3, 6)
	world.carve_sphere(Vector3(32.0, 2.2, 24.0), 1.5, 6)

	for view in VIEWS:
		player.global_position = view.pos
		player.rotation_degrees.y = view.yaw
		player.get_node("Head").rotation_degrees.x = view.pitch
		for i in 20:
			await process_frame
		var path: String = out_dir.path_join("%s.png" % view.name)
		root.get_texture().get_image().save_png(path)

		var start := Time.get_ticks_usec()
		for i in 120:
			await process_frame
		var frame_ms := (Time.get_ticks_usec() - start) / 120000.0
		print("saved %s  (avg frame %.2f ms)" % [path, frame_ms])
	quit()
