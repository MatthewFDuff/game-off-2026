extends SceneTree
## Measures frame cost in the facility from several viewpoints, with lighting features toggled to
## see what each one costs, then a night with hunting shrooms. Needs a window (real GPU):
##   godot --path . --script res://tests/perf_probe.gd

const VIEWS := [
	{name = "atrium", pos = Vector3(25.6, 4.0, 29.0), yaw = 0.0, pitch = 8.0},
	{name = "lab", pos = Vector3(36.5, 4.0, 25.6), yaw = -90.0, pitch = -8.0},
	{name = "grow_hall", pos = Vector3(25.6, 4.0, 44.5), yaw = 180.0, pitch = -15.0},
	{name = "corridor", pos = Vector3(25.6, 4.0, 31.0), yaw = 180.0, pitch = 0.0},
]
const FRAMES := 90

var _rid: RID


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = Vector2i(1280, 720)
	_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_rid, true)
	var scene: Node3D = load("res://scenes/facility.tscn").instantiate()
	root.add_child(scene)
	var player: Player = scene.get_node("Player")
	var director: ShiftDirector = scene.get_node("ShiftDirector")
	var shrooms: ShroomManager = scene.get_node("Shrooms")
	var state: GameState = scene.get_node("GameState")
	var world: VoxelWorld = scene.get_node("VoxelWorld")
	var env: Environment = scene.get_node("WorldEnvironment").environment
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.set_physics_process(false)
	await process_frame

	var lights: Array[Light3D] = []
	for node in scene.find_children("*", "Light3D", true, false):
		lights.append(node)
	var shadowed := lights.filter(func(l: Light3D) -> bool: return l.shadow_enabled)
	print("GPU: %s | lights %d (%d shadowed) | chunks with mesh: %s" % [RenderingServer.get_video_adapter_name(), lights.size(), shadowed.size(), world.get_stats()])

	print("%-10s %-14s %8s %8s %7s %8s %9s" % ["view", "config", "frame", "gpu", "draws", "objects", "prims"])
	for view in VIEWS:
		_place(player, view)
		await _measure(view.name, "baseline")
		for l in shadowed:
			l.shadow_enabled = false
		await _measure(view.name, "no shadows")
		for l in lights:
			l.visible = l is SpotLight3D
		await _measure(view.name, "flashlight only")
		var fog := env.fog_enabled
		env.fog_enabled = false
		await _measure(view.name, "+ no fog")
		env.fog_enabled = fog
		for l in lights:
			l.visible = true
		for l in shadowed:
			l.shadow_enabled = true

	# Night: shrooms hunting the player.
	director.hatch_duration = 0.1
	director.dark_duration = 0.1
	director.first_growth_delay = 0.0
	director.growth_spread = 0.5
	for bed: AABB in scene.info.spore_beds:
		for i in 2:
			var spore := shrooms.plant(bed.position + Vector3(0.6 + i * 1.5, 0.0, 0.5))
			spore.growth_time = 0.5
			state.planted += 1
	player.teleport(Vector3(25.6, 4.0, 22.0))
	director._try_start_night()
	await create_timer(3.0).timeout
	_place(player, VIEWS[0])
	player.set_physics_process(true)
	await _measure("night", "%d shrooms" % shrooms.shrooms.size())
	await create_timer(4.0).timeout
	await _measure("night", "%d shrooms" % shrooms.shrooms.size())
	quit()


func _place(player: Player, view: Dictionary) -> void:
	player.teleport(view.pos)
	player.rotation_degrees.y = view.yaw
	player.get_node("Head").rotation_degrees.x = view.pitch


func _measure(view: String, config: String) -> void:
	for i in 10:
		await process_frame
	var cpu := 0.0
	var gpu := 0.0
	var physics := 0.0
	var start := Time.get_ticks_usec()
	for i in FRAMES:
		await process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(_rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(_rid)
		physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var frame := (Time.get_ticks_usec() - start) / 1000.0 / FRAMES
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("%-10s %-14s %6.2fms %6.2fms %7d %8d %9d  (render cpu %.2fms, physics %.2fms)" % [view, config, frame, gpu / FRAMES, draws, objects, prims, cpu / FRAMES, physics / FRAMES])
