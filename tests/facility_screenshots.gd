extends SceneTree
## Renders the facility from several viewpoints, then a night in the grow hall. Needs a window:
##   godot --path . --script res://tests/facility_screenshots.gd -- <output_dir>

const VIEWS := [
	{name = "atrium", pos = Vector3(25.6, 4.0, 29.0), yaw = 0.0, pitch = 8.0},
	{name = "shaft", pos = Vector3(25.6, 4.0, 22.0), yaw = 0.0, pitch = 80.0},
	{name = "lab", pos = Vector3(36.5, 4.0, 25.6), yaw = -90.0, pitch = -8.0},
	{name = "break_room", pos = Vector3(15.0, 4.0, 25.6), yaw = 90.0, pitch = -8.0},
	{name = "storage", pos = Vector3(25.6, 4.0, 36.5), yaw = 180.0, pitch = -5.0},
	{name = "grow_hall", pos = Vector3(25.6, 4.0, 44.5), yaw = 180.0, pitch = -15.0},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else OS.get_user_data_dir()
	root.size = Vector2i(1280, 720)
	var scene: Node3D = load("res://scenes/facility.tscn").instantiate()
	root.add_child(scene)
	var world: VoxelWorld = scene.get_node("VoxelWorld")
	var player: Player = scene.get_node("Player")
	var director: ShiftDirector = scene.get_node("ShiftDirector")
	var shrooms: ShroomManager = scene.get_node("Shrooms")
	var state: GameState = scene.get_node("GameState")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.set_physics_process(false)
	await process_frame

	for view in VIEWS:
		await _shoot(player, view, out)

	# Blast a hole in the break room wall to show the ground behind the lining.
	world.carve_sphere(Vector3(7.4, 5.5, 25.6), 1.6, 6)
	await _shoot(player, {name = "strata", pos = Vector3(11.0, 4.0, 25.6), yaw = 90.0, pitch = 0.0}, out)

	# Night in the grow hall.
	director.hatch_duration = 0.2
	director.dark_duration = 0.2
	director.first_growth_delay = 0.2
	director.growth_spread = 2.0
	for bed: AABB in scene.info.spore_beds.slice(0, 4):
		for i in 2:
			var spore := shrooms.plant(bed.position + Vector3(0.6 + i * 1.5, 0.0, 0.5))
			spore.growth_time = 3.0
			state.planted += 1
	player.teleport(Vector3(25.6, 4.0, 22.0))
	director._try_start_night()
	await create_timer(1.0).timeout
	await _shoot(player, {name = "night_atrium", pos = Vector3(25.6, 4.0, 29.0), yaw = 0.0, pitch = 5.0}, out)
	var bed_view := {name = "night_growing", pos = Vector3(17.5, 4.0, 47.8), yaw = 0.0, pitch = -28.0}
	await create_timer(1.6).timeout
	await _shoot(player, bed_view, out)
	await create_timer(3.0).timeout
	for shroom in shrooms.shrooms:
		shroom.set_physics_process(false) # Hold still for the picture.
	bed_view.name = "night_grown"
	await _shoot(player, bed_view, out)
	quit()


func _shoot(player: Player, view: Dictionary, out: String) -> void:
	player.teleport(view.pos)
	player.rotation_degrees.y = view.yaw
	player.get_node("Head").rotation_degrees.x = view.pitch
	for i in 12:
		await process_frame
	var path := out.path_join("%s.png" % view.name)
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
