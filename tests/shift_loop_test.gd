extends SceneTree
## Headless run through one full shift in the facility: plant in the grow beds, climb the ladder,
## seal the hatch, shrooms grow and hunt, harvest, dawn. Then checks a shroom digs through a plank
## wall to reach the player.
##   godot --headless --path . --script res://tests/shift_loop_test.gd

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: Node3D = load("res://scenes/facility.tscn").instantiate()
	root.add_child(scene)
	var world: VoxelWorld = scene.get_node("VoxelWorld")
	var player: Player = scene.get_node("Player")
	var director: ShiftDirector = scene.get_node("ShiftDirector")
	var shrooms: ShroomManager = scene.get_node("Shrooms")
	var state: GameState = scene.get_node("GameState")
	var plant_tool: PlantTool = scene.get_node("PlantTool")
	var camera: Camera3D = player.get_node("Head/Camera3D")
	await _frames(10)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_check("starts in the day shift", director.phase == ShiftDirector.Phase.DAY, str(director.phase))
	_check("first quota is 3", state.quota == 3, str(state.quota))
	var money_at_start := state.money
	director.hatch_duration = 0.2
	director.dark_duration = 0.2
	director.first_growth_delay = 0.0
	director.growth_spread = 0.3

	# Planting only works on grow-bed substrate.
	player.teleport(Vector3(25.6, 4.0, 27.0))
	await _frames(3)
	_check("can't plant on the atrium floor", plant_tool.get_prompt().is_empty())
	var beds: Array = scene.info.spore_beds
	for i in 3:
		var bed: AABB = beds[i]
		player.teleport(bed.get_center() + Vector3(0, 0.0, 1.6) - Vector3(0, bed.position.y - 4.0, 0))
		player.rotation.y = 0.0
		camera.get_parent().rotation_degrees.x = -45.0
		await _frames(3)
		Input.action_press("interact")
		await _frames(1)
		Input.action_release("interact")
		await _frames(2)
	_check("planted in three beds", state.planted == 3 and shrooms.spores.size() == 3, "%d planted" % state.planted)
	for spore in shrooms.spores:
		spore.growth_time = 0.3
	camera.get_parent().rotation_degrees.x = 0.0

	# Climb the ladder to the hatch control.
	player.teleport(Vector3(25.6, 4.0, 21.2))
	player.rotation.y = 0.0
	await _frames(3)
	var start_y := player.global_position.y
	Input.action_press("move_forward")
	await _wait_for(func() -> bool: return player.global_position.y > 6.4, 4.0)
	Input.action_release("move_forward")
	await _frames(5)
	_check("climbs the ladder", player.global_position.y > start_y + 2.0 and player.on_ladder, "y %.2f -> %.2f" % [start_y, player.global_position.y])
	_check("reaches the hatch control", director.is_at_hatch_control(), str(player.global_position))
	var held_y := player.global_position.y
	await _frames(30)
	_check("hangs on the ladder without input", absf(player.global_position.y - held_y) < 0.05, "%.2f -> %.2f" % [held_y, player.global_position.y])

	Input.action_press("interact")
	await _frames(1)
	Input.action_release("interact")
	await _wait_for(func() -> bool: return director.phase == ShiftDirector.Phase.NIGHT, 5.0)
	_check("sealing the hatch starts the night", director.phase == ShiftDirector.Phase.NIGHT, str(director.phase))
	_check("hatch is sealed", world.get_voxel(Vector3i(256, 91, 220)) == VoxelMaterials.HATCH)
	var power: float = (world.material as ShaderMaterial).get_shader_parameter("facility_power")
	_check("power is cut", power < 0.01, str(power))

	# Climb down and wait in the atrium.
	player.teleport(Vector3(25.6, 4.0, 27.0))
	await _wait_for(func() -> bool: return shrooms.shrooms.size() == 3, 5.0)
	_check("spores grow into shrooms", shrooms.shrooms.size() == 3 and shrooms.spores.is_empty(), "%d shrooms, %d spores" % [shrooms.shrooms.size(), shrooms.spores.size()])

	var before := _nearest_distance(shrooms, player)
	await _seconds(3.0)
	var after := _nearest_distance(shrooms, player)
	_check("shrooms close in from the grow hall", after < before - 3.0, "%.1f -> %.1f" % [before, after])

	await _wait_for(func() -> bool: return player.health < player.max_health, 25.0)
	_check("shrooms reach and attack the player", player.health < player.max_health, str(player.health))

	for shroom in shrooms.shrooms.duplicate():
		shroom.take_damage(1000.0)
	await _frames(2)
	_check("harvest counts", state.harvested == 3, str(state.harvested))
	await _wait_for(func() -> bool: return director.phase == ShiftDirector.Phase.DAY, 5.0)
	_check("dawn returns to day shift 2", director.phase == ShiftDirector.Phase.DAY and state.shift == 2, "%s shift %d" % [director.phase, state.shift])
	_check("harvest and bonus paid", state.money == money_at_start + 3 * shrooms.harvest_reward + director.survival_bonus, "%d -> %d" % [money_at_start, state.money])
	_check("hatch reopens", world.get_voxel(Vector3i(256, 91, 220)) == VoxelMaterials.AIR)
	_check("ladder survives the hatch", world.get_voxel(Vector3i(251, 91, 206)) == VoxelMaterials.LADDER)

	# Breaching: wall the player into a plank box in the atrium and grow a shroom outside it.
	player.health = player.max_health
	player.teleport(Vector3(29.0, 4.0, 27.0))
	world.fill_box(Vector3i(276, 40, 256), Vector3i(304, 70, 284), VoxelMaterials.PLANK)
	world.fill_box(Vector3i(278, 40, 258), Vector3i(302, 70, 282), VoxelMaterials.AIR)
	var planks_before := _count(world, Vector3i(276, 40, 256), Vector3i(304, 70, 284), VoxelMaterials.PLANK)
	var spore := shrooms.plant(Vector3(29.0, 4.0, 23.5))
	spore.growth_time = 0.1
	spore.start_growing(0.0)
	await _wait_for(func() -> bool: return player.health < player.max_health, 20.0)
	var planks_after := _count(world, Vector3i(276, 40, 256), Vector3i(304, 70, 284), VoxelMaterials.PLANK)
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
