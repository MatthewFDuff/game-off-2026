extends SceneTree
## Plays a night at 1080p with the rifle and blasts going, and reports frame-time spikes per phase.
## Needs a window:
##   godot --path . --script res://tests/perf_play.gd

var _phase := "boot"
var _frames := {}
var _last := 0


func _initialize() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _last > 0:
		var ms := (now - _last) / 1000.0
		var bucket: Array = _frames.get_or_add(_phase, [])
		bucket.append(ms)
		if ms > 15.0:
			print("  spike %.1fms in %s at frame %d" % [ms, _phase, bucket.size()])
	_last = now
	return false


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.size = Vector2i(1920, 1080)
	var scene: Node3D = load("res://scenes/facility.tscn").instantiate()
	root.add_child(scene)
	var player: Player = scene.get_node("Player")
	var director: ShiftDirector = scene.get_node("ShiftDirector")
	var shrooms: ShroomManager = scene.get_node("Shrooms")
	var state: GameState = scene.get_node("GameState")
	var head: Node3D = player.get_node("Head")
	await process_frame
	await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_phase = "day walk"
	player.teleport(Vector3(25.6, 4.0, 29.0))
	Input.action_press("move_forward")
	for i in 120:
		player.rotate_y(0.02)
		await process_frame
	Input.action_release("move_forward")

	_phase = "day rifle"
	head.rotation_degrees.x = -10.0
	Input.action_press("fire")
	for i in 180:
		player.rotate_y(0.01)
		await process_frame
	Input.action_release("fire")

	_phase = "day blasts"
	for i in 6:
		player.rotate_y(0.5)
		Input.action_press("alt_fire")
		await process_frame
		Input.action_release("alt_fire")
		for j in 25:
			await process_frame

	director.hatch_duration = 0.3
	director.dark_duration = 0.3
	director.first_growth_delay = 0.0
	director.growth_spread = 1.0
	for bed: AABB in scene.info.spore_beds:
		for i in 3:
			var spore := shrooms.plant(bed.position + Vector3(0.5 + i * 1.2, 0.0, 0.5))
			spore.growth_time = 1.0
			state.planted += 1
	player.teleport(Vector3(25.6, 4.0, 27.0))
	director._try_start_night()
	_phase = "night start"
	await create_timer(3.0).timeout
	_phase = "night hunt (%d)" % shrooms.shrooms.size()
	await create_timer(8.0).timeout
	_phase = "night fight"
	player.max_health = 100000.0
	player.health = 100000.0
	Input.action_press("fire")
	await create_timer(6.0).timeout
	Input.action_release("fire")
	_phase = "done"

	for phase: String in _frames:
		if phase == "done" or phase == "boot":
			continue
		var times: Array = _frames[phase]
		times.sort()
		var slow := times.filter(func(t: float) -> bool: return t > 16.7).size()
		print("%-18s %4d frames  median %5.2fms  p99 %6.2fms  worst %6.2fms  >16.7ms: %d" % [
			phase, times.size(), times[times.size() / 2], times[int(times.size() * 0.99)], times[-1], slow])
	print("shrooms alive at end: %d" % shrooms.shrooms.size())
	quit()
