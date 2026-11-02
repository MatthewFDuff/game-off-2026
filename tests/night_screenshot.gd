extends SceneTree
## Renders day.png, night_growing.png and night_hunt.png of a short shift. Needs a window:
##   godot --path . --script res://tests/night_screenshot.gd -- <output_dir>
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1280, 720)
	var scene: Node3D = load("res://scenes/test_world.tscn").instantiate()
	root.add_child(scene)
	var player: Player = scene.get_node("Player")
	var director: ShiftDirector = scene.get_node("ShiftDirector")
	var shrooms: ShroomManager = scene.get_node("Shrooms")
	var state: GameState = scene.get_node("GameState")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in 10:
		await process_frame
	player.teleport(Vector3(32, 2.2, 40))
	player.rotation_degrees.y = 0.0
	player.get_node("Head").rotation_degrees.x = -5.0
	await create_timer(0.5).timeout
	root.get_texture().get_image().save_png(out.path_join("day.png"))
	director.hatch_duration = 0.3
	director.dark_duration = 0.3
	director.first_growth_delay = 0.5
	director.growth_spread = 1.5
	for p in [Vector3(29, 2.2, 30), Vector3(31, 2.2, 29), Vector3(33.5, 2.2, 30.5), Vector3(35, 2.2, 28), Vector3(30, 2.2, 26)]:
		shrooms.plant(p).growth_time = 2.0
		state.planted += 1
	director._try_start_night()
	await create_timer(3.0).timeout
	root.get_texture().get_image().save_png(out.path_join("night_growing.png"))
	await create_timer(3.5).timeout
	root.get_texture().get_image().save_png(out.path_join("night_hunt.png"))
	print("shroom count ", shrooms.shrooms.size(), " phase ", director.get_phase_name())
	quit()
