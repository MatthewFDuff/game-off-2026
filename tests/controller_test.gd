extends SceneTree
## The character controller (Player._walk) with scripted input, headless:
##   godot --headless --path . --script res://tests/controller_test.gd
## Walking tops out at walk speed and stops cleanly; jump height, and a short hop when jump is let
## go early; coyote jumps just off a ledge (and none after it); buffered jumps fire on landing;
## ten chained hops keep their speed; strafing while turning gains speed in the air, up to the
## cap; crouching in the air pulls the feet up. Builds a scratch level: one big concrete room with a
## 1 m platform.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://controller_test_levels/"
const LEVEL := "controller_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIZE := Vector3i(16, 4, 16)
## The room (air), floor top at y 20; a platform 1 m high on its west side.
const ROOM := [Vector3i(8, 20, 8), Vector3i(504, 100, 504)]
const PLATFORM := [Vector3i(8, 20, 8), Vector3i(120, 30, 504)]
const START := Vector3(30.0, 2.0, 25.0)

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LevelData.save_dir_override = SCRATCH
	_make_level()
	root.get_node("Net").start_solo(LEVEL, "play")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	var lab = current_scene
	var me = lab.local_player()
	await _frames(10)
	me.teleport(START)
	me.rotation.y = 0.0 # Facing -Z.
	await _settle(me)

	# Walking: top speed is walk speed, and letting go stops quickly.
	Input.action_press("move_forward")
	await _seconds(1.0)
	var walk: float = _flat(me.velocity)
	_check("walking reaches walk speed and no more", walk > me.walk_speed * 0.97 and walk <= me.walk_speed + 0.01, "%.2f" % walk)
	Input.action_release("move_forward")
	await _seconds(0.5)
	_check("letting go stops", _flat(me.velocity) < 0.05, "%.2f" % _flat(me.velocity))

	# Jump height: held to the top, and let go right away.
	var floor_y: float = me.global_position.y
	var peak := [floor_y]
	var track := func() -> void: peak[0] = maxf(peak[0], me.global_position.y)
	physics_frame.connect(track)
	Input.action_press("jump")
	await _seconds(0.8)
	Input.action_release("jump")
	await _settle(me)
	var full: float = peak[0] - floor_y
	var expected: float = me.jump_velocity * me.jump_velocity / (2.0 * me.gravity)
	_check("a held jump reaches full height", absf(full - expected) < 0.1, "%.2f vs %.2f" % [full, expected])
	peak[0] = floor_y
	Input.action_press("jump")
	await _frames(3)
	Input.action_release("jump")
	await _settle(me)
	var short: float = peak[0] - floor_y
	_check("letting go early makes a short hop", short < full * 0.6 and short > 0.05, "%.2f vs %.2f" % [short, full])
	physics_frame.disconnect(track)

	# Coyote time: walk off the platform's east edge and jump just after.
	await _edge_test(me, true)
	await _edge_test(me, false)

	# Jump buffer: pressed just before landing, it fires on landing.
	me.teleport(START)
	await _settle(me)
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	await _wait_falling_near_floor(me, floor_y, 0.25)
	Input.action_press("jump")
	await _frames(1)
	Input.action_release("jump")
	await _wait(func() -> bool: return me.on_floor or me.velocity.y > 2.0, 1.0)
	await _frames(3)
	_check("a jump pressed before landing fires on landing", me.velocity.y > 2.0 or me.global_position.y > floor_y + 0.1, "vy %.2f" % me.velocity.y)
	await _settle(me)

	# Bunny hops: ten chained hops (buffered just before each landing) keep their speed.
	me.teleport(Vector3(30.0, 2.0, 49.0))
	me.rotation.y = 0.0
	await _settle(me)
	Input.action_press("move_forward")
	await _seconds(1.0)
	var start_speed: float = _flat(me.velocity)
	for hop in 10:
		Input.action_press("jump")
		await _frames(2)
		Input.action_release("jump")
		await _frames(4)
		await _wait_falling_near_floor(me, floor_y, 0.2)
	await _frames(1)
	var hop_speed: float = _flat(me.velocity)
	_check("ten chained hops keep their speed", hop_speed >= start_speed * 0.95, "%.2f -> %.2f" % [start_speed, hop_speed])
	Input.action_release("move_forward")
	await _settle(me)

	# Strafing while turning in the air gains speed, up to the cap.
	me.teleport(Vector3(30.0, 2.0, 49.0))
	me.rotation.y = 0.0
	await _settle(me)
	Input.action_press("move_forward")
	await _seconds(0.8)
	Input.action_release("move_forward")
	Input.action_press("move_left")
	var gained := 0.0
	for hop in 12:
		Input.action_press("jump")
		await _frames(1)
		Input.action_release("jump")
		var air_frames := 0
		while air_frames < 120 and (air_frames < 3 or not me.on_floor):
			me.rotation.y += 0.035 # Turning left while holding left: the classic strafe.
			await physics_frame
			air_frames += 1
		gained = maxf(gained, _flat(me.velocity))
	Input.action_release("move_left")
	_check("strafe-turning in the air gains speed", gained > me.walk_speed * 1.1, "%.2f" % gained)
	_check("...but not past the cap", gained <= me.max_air_speed + 0.05, "%.2f" % gained)
	await _settle(me)

	# Crouch-jump: crouching in the air raises the feet.
	me.teleport(START)
	await _settle(me)
	Input.action_press("jump")
	await _frames(8)
	var before: float = me.global_position.y
	Input.action_press("crouch")
	await _frames(1)
	_check("crouching mid-air pulls the feet up", me.global_position.y > before + 0.4, "%.2f -> %.2f" % [before, me.global_position.y])
	Input.action_release("crouch")
	Input.action_release("jump")
	await _settle(me)
	_check("standing again on the floor", not me.crouching and me.on_floor)
	_finish()


## Walks east off the platform (top at 1 m) and jumps late_by after leaving it: within coyote time
## it jumps, past it nothing.
func _edge_test(me, within: bool) -> void:
	me.teleport(Vector3(11.0, 3.0, 25.0))
	me.rotation.y = -PI * 0.5 # Facing +X.
	await _settle(me)
	Input.action_press("move_forward")
	await _wait(func() -> bool: return not me.on_floor, 3.0)
	await _seconds(0.04 if within else 0.25)
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	var rising: bool = me.velocity.y > 1.0
	Input.action_release("move_forward")
	if within:
		_check("coyote time: a jump just off the ledge still goes", rising, "vy %.2f" % me.velocity.y)
	else:
		_check("...but not long after", not rising, "vy %.2f" % me.velocity.y)
	await _settle(me)


func _wait_falling_near_floor(me, floor_y: float, height: float) -> void:
	await _wait(func() -> bool: return me.velocity.y < 0.0 and me.global_position.y < floor_y + height and not me.on_floor, 2.0)


func _settle(me) -> void:
	await _wait(func() -> bool: return me.on_floor, 3.0)
	await _seconds(0.3)


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _make_level() -> void:
	var level := LevelData.new()
	level.name = LEVEL
	level.settings = LevelData.default_settings(SIZE, "rock")
	var world := VoxelWorld.new()
	world.size_in_chunks = SIZE
	world.immediate_remesh_limit = 0
	world.detach_floating = false
	root.add_child(world)
	world.fill_all(M.CONCRETE)
	world.fill_box(ROOM[0], ROOM[1], M.AIR, false)
	world.fill_box(PLATFORM[0], PLATFORM[1], M.CONCRETE, false)
	level.voxels = world.get_data()
	world.free()
	var spawn := LevelSchema.new_marker("spawn", START / 0.1, 0.0)
	spawn.id = "spawn_1"
	level.objects[spawn.id] = spawn
	_check("level saves", level.save() == OK)


func _finish() -> void:
	print("controller test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _wait(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await physics_frame
	return true


func _seconds(seconds: float) -> void:
	var frames := int(seconds * Engine.physics_ticks_per_second)
	for i in frames:
		await physics_frame


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
