extends SceneTree
## Headless run through one full shift: plant, night, shrooms hunt, harvest, dawn. Then checks a
## shroom digs through a plank wall to reach the player.
##   godot --headless --path . --script res://tests/shift_loop_test.gd

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: Node3D = load("res://scenes/test_world.tscn").instantiate()
	root.add_child(scene)
	var world: VoxelWorld = scene.get_node("VoxelWorld")
	var player: Player = scene.get_node("Player")
	var director: ShiftDirector = scene.get_node("ShiftDirector")
	var shrooms: ShroomManager = scene.get_node("Shrooms")
	var state: GameState = scene.get_node("GameState")
	await _frames(10)

	_check("starts in the day shift", director.phase == ShiftDirector.Phase.DAY, str(director.phase))
	_check("first quota is 3", state.quota == 3, str(state.quota))
	var money_at_start := state.money

	# Short timings so the test runs quickly.
	director.hatch_duration = 0.2
	director.dark_duration = 0.2
	director.first_growth_delay = 0.0
	director.growth_spread = 0.3

	director._try_start_night()
	await _frames(3)
	_check("night needs the quota planted first", director.phase == ShiftDirector.Phase.DAY, str(director.phase))

	player.teleport(Vector3(32.0, 2.2, 38.0))
	for x in [26.0, 27.0, 28.0]:
		var spore := shrooms.plant(Vector3(x, 2.2, 26.0))
		spore.growth_time = 0.3
		state.planted += 1
	director._try_start_night()
	await _wait_for(func() -> bool: return director.phase == ShiftDirector.Phase.NIGHT, 5.0)
	_check("night begins", director.phase == ShiftDirector.Phase.NIGHT, str(director.phase))
	_check("hatch is closed", world.get_voxel(world.world_to_voxel(Vector3(32.0, 7.25, 32.0))) == VoxelMaterials.HATCH)

	await _wait_for(func() -> bool: return shrooms.shrooms.size() == 3, 5.0)
	_check("spores grow into shrooms", shrooms.shrooms.size() == 3 and shrooms.spores.is_empty(), "%d shrooms, %d spores" % [shrooms.shrooms.size(), shrooms.spores.size()])

	var before := _nearest_distance(shrooms, player)
	await _seconds(2.0)
	var after := _nearest_distance(shrooms, player)
	_check("shrooms close in on the player", after < before - 2.0, "%.1f -> %.1f" % [before, after])

	await _wait_for(func() -> bool: return player.health < player.max_health, 8.0)
	_check("shrooms attack the player", player.health < player.max_health, str(player.health))

	for shroom in shrooms.shrooms.duplicate():
		shroom.take_damage(1000.0)
	await _frames(2)
	_check("harvest counts", state.harvested == 3, str(state.harvested))
	await _wait_for(func() -> bool: return director.phase == ShiftDirector.Phase.DAY, 5.0)
	_check("dawn returns to day shift 2", director.phase == ShiftDirector.Phase.DAY and state.shift == 2, "%s shift %d" % [director.phase, state.shift])
	_check("harvest and bonus paid", state.money == money_at_start + 3 * shrooms.harvest_reward + director.survival_bonus, "%d -> %d" % [money_at_start, state.money])
	_check("hatch reopens", world.get_voxel(world.world_to_voxel(Vector3(32.0, 7.25, 32.0))) == VoxelMaterials.AIR)
	_check("quota grows", state.quota == 5, str(state.quota))

	# Breaching: wall the player into a plank box and drop a shroom outside it.
	player.health = player.max_health
	player.teleport(Vector3(36.0, 2.2, 40.0))
	world.fill_box(Vector3i(340, 22, 380), Vector3i(380, 50, 420), VoxelMaterials.PLANK)
	world.fill_box(Vector3i(342, 22, 382), Vector3i(378, 50, 418), VoxelMaterials.AIR)
	var planks_before := _count(world, Vector3i(340, 22, 380), Vector3i(380, 50, 420), VoxelMaterials.PLANK)
	var spore := shrooms.plant(Vector3(36.0, 2.2, 34.0))
	spore.growth_time = 0.1
	spore.start_growing(0.0)
	await _wait_for(func() -> bool: return player.health < player.max_health, 20.0)
	var planks_after := _count(world, Vector3i(340, 22, 380), Vector3i(380, 50, 420), VoxelMaterials.PLANK)
	_check("shroom breaches a plank wall", planks_after < planks_before and player.health < player.max_health, "planks %d -> %d, hp %.0f" % [planks_before, planks_after, player.health])

	print("shift loop test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _nearest_distance(shrooms: ShroomManager, player: Player) -> float:
	var best := INF
	for shroom in shrooms.shrooms:
		best = minf(best, shroom.global_position.distance_to(player.global_position))
	return best


func _count(world: VoxelWorld, from: Vector3i, to: Vector3i, material: int) -> int:
	var total := 0
	for y in range(from.y, to.y):
		for z in range(from.z, to.z):
			for x in range(from.x, to.x):
				if world.get_voxel(Vector3i(x, y, z)) == material:
					total += 1
	return total


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _wait_for(condition: Callable, timeout: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await physics_frame


func _check(label: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", label, "" if ok else detail])
	if not ok:
		_failures += 1
