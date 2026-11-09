extends SceneTree
## Headless checks for enemies, combat and the horde director (phase 1):
##   godot --headless --path . --script res://tests/enemy_test.gd
## Builds a scratch level of two concrete rooms joined by a doorway, plays it solo, and checks that
## a basic shroom walks from one room to the player in the other through the doorway, bites them,
## is found by combat.ray_hit, takes a crit through a hit zone, and dies into debris on
## request_hit. Chunks: a hit blasts voxels out of the body (its own mesh), repeated hits at one
## spot kill it before its health would, and the death burst is what's left; a giant's carved body
## loses its antennae on top of the chunks, and crits still count. Then a trigger turns on a spawner that trickles up to its max_alive, a horde
## bursts past it, the finale stub reports survival, and going back to edit clears every enemy.
##
## Game types (Lab, Enemy, Combat) are left unnamed (see editor_test.gd): naming them would
## compile those scripts before the autoloads they use are registered.

const SCRATCH := "user://enemy_test_levels/"
const LEVEL := "enemy_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIZE := Vector3i(6, 2, 4)
const FLOOR := 8
## Voxel boxes [from, to) of the two rooms and the doorway in the wall between them.
const ROOM_A := [Vector3i(8, FLOOR, 8), Vector3i(88, 40, 120)]
const ROOM_B := [Vector3i(98, FLOOR, 8), Vector3i(184, 40, 120)]
const DOOR := [Vector3i(85, FLOOR, 58), Vector3i(101, 30, 70)]
const PLAYER_SPOT := Vector3(150.0, FLOOR, 100.0)
const ENEMY_SPOT := Vector3(40.0, FLOOR, 100.0)
const SPAWNER_SPOT := Vector3(40.0, FLOOR, 30.0)
const TRIGGER_SPOT := Vector3(170.0, FLOOR, 30.0)

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
	var enemies = lab.enemies
	var combat = load("res://scripts/combat/combat.gd") # Not by name: see the note at the top.
	await _frames(10)
	lab.director.scale_per_player = 0.0 # Raw spawner numbers (the data here isn't tuned for two players).
	_check("playing", lab.mode == "play" and enemies.simulating and lab.director.running)
	_check("spawner read with its fields", lab.director.spawners.has("horde_test") and not lab.director.spawners.horde_test.active)

	# Path: from room A to the player in room B, the only way being the doorway.
	var enemy = enemies.spawn("basic", lab.view.to_world(ENEMY_SPOT))
	_check("spawns a basic shroom", enemy != null and enemy.kind == "basic" and enemy.max_health == 30.0 and enemy.speed == 2.5)
	_check("body built from the .vox", enemy._mesh != null and enemy._mesh.mesh != null and enemy.bounds.size.y > 1.0, str(enemy.bounds))
	var bitten := [0]
	me.damaged.connect(func(_amount: float, _from: Vector3) -> void: bitten[0] += 1)
	var door_box := AABB(lab.view.to_world(Vector3(DOOR[0])), Vector3(DOOR[1] - DOOR[0]) * lab.world.voxel_size)
	var through_door := [false]
	var reached := await _wait_until(func() -> bool:
		if door_box.grow(0.1).has_point(enemy.global_position + Vector3.UP * 0.1):
			through_door[0] = true
		return enemy.global_position.distance_to(me.global_position) < 1.3, 30.0)
	_check("walks to the player", reached, "enemy %s, player %s" % [enemy.global_position, me.global_position])
	_check("goes through the doorway", through_door[0])
	var health_before: float = me.health
	await _wait_until(func() -> bool: return bitten[0] >= 2, 5.0)
	_check("bites the player", bitten[0] >= 2 and me.health < health_before, "%d bites, health %.1f" % [bitten[0], me.health])

	# Hits: the ray finds the enemy before the wall behind it; a hit zone multiplies damage.
	var eye: Vector3 = me.global_position + Vector3.UP * 1.0
	var ray: Dictionary = combat.ray_hit(lab.world, eye, enemy.get_center() - eye, 20.0)
	_check("ray_hit finds the enemy", ray.hit and ray.enemy == enemy and ray.zone == "body", str(ray))
	_check("sphere_hit finds it", enemy in combat.sphere_hit(enemy.get_center(), 0.5))
	_check("box_hit finds it", enemy in combat.box_hit(AABB(enemy.global_position - Vector3(0.2, 0, 0.2), Vector3(0.4, 0.4, 0.4))))
	enemy.hit_zones["test_crit"] = {box = AABB(Vector3(-0.3, 0.0, -0.3), Vector3(0.6, 0.4, 0.6)), crit = 2.0}
	var damaged := []
	enemies.enemy_damaged.connect(func(e, amount: float, zone: String) -> void: damaged.append([e, amount, zone]))
	var local_hits := [0]
	enemies.local_hit.connect(func(_e, _p: Vector3) -> void: local_hits[0] += 1)
	enemies.request_hit(enemy.id, 5.0, enemy.global_position + Vector3.UP * 0.2, "rifle")
	_check("crit zone doubles damage", damaged.size() == 1 and damaged[0][1] == 10.0 and damaged[0][2] == "test_crit" and enemy.health == 20.0, str(damaged))
	_check("hit flashes", enemy._mesh.material_overlay != null)
	_check("local hit reported for the hit marker", local_hits[0] == 1)

	var died := []
	enemies.enemy_died.connect(func(e) -> void: died.append(e))
	var debris_before: int = lab.debris.get_child_count()
	enemies.request_hit(enemy.id, 50.0, enemy.get_center(), "rifle")
	_check("dies", died.size() == 1 and not enemies.enemies.has(enemy.id))
	_check("bursts into debris", lab.debris.get_child_count() > debris_before, "%d -> %d" % [debris_before, lab.debris.get_child_count()])
	await _frames(2)
	_check("freed", not is_instance_valid(enemy))
	await _chunks(lab, enemies)

	# Spawner: off until the trigger fires, then trickles up to max_alive and no further.
	await _frames(30)
	_check("inactive spawner spawns nothing", enemies.alive_count() == 0, str(enemies.alive_count()))
	me.teleport(lab.view.to_world(TRIGGER_SPOT))
	var activated := await _wait_until(func() -> bool: return lab.director.spawners.horde_test.active, 3.0)
	_check("trigger activates the spawner", activated)
	var most := [0]
	await _wait_until(func() -> bool:
		most[0] = maxi(most[0], enemies.alive_count())
		return false, 2.5)
	_check("trickles up to max_alive", enemies.alive_count() == 3 and most[0] == 3, "alive %d, most %d" % [enemies.alive_count(), most[0]])

	lab.director.start_horde(4)
	_check("horde state", lab.director.state == "horde")
	await _wait_until(func() -> bool: return enemies.alive_count() >= 7, 3.0)
	_check("horde bursts past max_alive", enemies.alive_count() == 7, str(enemies.alive_count()))

	var survived := [false]
	lab.director.finale_survived.connect(func() -> void: survived[0] = true)
	lab.director.finale(0.5)
	await _wait_until(func() -> bool: return survived[0], 3.0)
	_check("finale stub ends in finale_survived", survived[0] and lab.director.state == "calm")

	lab.request_mode("edit")
	await _frames(3)
	_check("back to edit clears every enemy", enemies.enemies.is_empty() and root.get_tree().get_nodes_in_group("enemies").is_empty() and not enemies.simulating)

	print("enemy test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Chunks (Enemy.chip): hits carve the body, enough of them kill, the death burst is the remains,
## and the giant's antennae compose with carving. Everything stands in room A, away from the player.
func _chunks(lab, enemies) -> void:
	var spot: Vector3 = lab.view.to_world(ENEMY_SPOT)
	var shroom = enemies.spawn("basic", spot, 0.0)
	shroom.speed = 0.0
	shroom.damage = 0.0
	await _frames(1)
	var shared = shroom._mesh.mesh
	var full: int = shroom.voxel_count()
	var front: Vector3 = shroom.global_transform * (shroom.bounds.get_center() + Vector3(0.0, 0.0, -shroom.bounds.size.z * 0.5))
	enemies.request_hit(shroom.id, 6.0, front, "rifle")
	_check("a hit carves voxels out", shroom.is_carved() and shroom.voxel_count() < full, "%d of %d" % [shroom.voxel_count(), full])
	await _frames(1)
	_check("into its own mesh, not the shared one", shroom._mesh.mesh != null and shroom._mesh.mesh != shared and shroom._mesh.mesh == shroom._own_mesh)
	_check("the hit flash still shows on it", shroom._mesh.material_overlay != null)
	_check("one chunk logged for late joiners", shroom.carve_points.size() == 1 and shroom.carve_radii.size() == 1)
	var radius: float = shroom.carve_radius(6.0)
	_check("chunk radius scales with damage", shroom.carve_radius(20.0) > radius and radius >= shroom.CARVE_MIN_RADIUS, str(radius))

	# Repeated hits at one spot: it falls apart before its (padded) health runs out.
	shroom.health = 100000.0
	var death_share: float = shroom.CARVE_DEATH_SHARE
	var at_death := []
	var on_died := func(e) -> void:
		if e == shroom:
			var sum := 0
			for count: int in e._debris_counts().values():
				sum += count
			at_death.append([sum, e.voxel_count(), e.health, e.remaining_share()])
	enemies.enemy_died.connect(on_died)
	var debris_before: int = lab.debris.get_child_count()
	var hits := 0
	while is_instance_valid(shroom) and shroom.alive and hits < 300:
		enemies.request_hit(shroom.id, 6.0, front, "rifle")
		hits += 1
		if hits % 5 == 0:
			await _frames(1)
	enemies.enemy_died.disconnect(on_died)
	_check("repeated hits at one spot kill it before its health would", at_death.size() == 1 and at_death[0][2] > 0.0, "%d hits, %s" % [hits, str(at_death)])
	if at_death.size() == 1:
		_check("once under the death share", at_death[0][3] < death_share and at_death[0][3] > 0.0, str(at_death[0][3]))
		_check("the death burst is what was left of it", at_death[0][0] == at_death[0][1] and at_death[0][1] < full, "%s of %d" % [str(at_death[0]), full])
	_check("and bursts", lab.debris.get_child_count() > debris_before)
	await _frames(2)

	# The giant: carved, then its antennae break on top of the chunks, and crits still count.
	var giant = enemies.spawn("giant", spot, 0.0)
	giant.speed = 0.0
	giant.damage = 0.0
	await _frames(1)
	var model: Dictionary = load("res://scripts/enemies/enemy_models.gd").model("giant", giant.variant)
	var rebuild_ms := INF
	for i in 5:
		var started := Time.get_ticks_usec()
		lab.world.build_model_mesh(model.size, model.voxels)
		rebuild_ms = minf(rebuild_ms, (Time.get_ticks_usec() - started) / 1000.0)
	print("    giant model %s (%d voxels): mesh rebuild %.2f ms (best of 5)" % [model.size, giant.voxel_count(), rebuild_ms])
	_check("a giant's mesh rebuild is quick", rebuild_ms < 20.0, "%.2f ms" % rebuild_ms)
	var giant_full: int = giant.voxel_count()
	var side: Vector3 = giant.global_transform * (giant.bounds.get_center() + Vector3(giant.bounds.size.x * 0.5, -0.3, 0.0))
	enemies.request_hit(giant.id, 30.0, side, "rifle")
	var carved: int = giant.voxel_count()
	_check("a giant takes a chunk", giant.is_carved() and carved < giant_full, "%d of %d" % [carved, giant_full])
	var crit_damage := []
	var on_damaged := func(e, amount: float, zone: String) -> void:
		if e == giant:
			crit_damage.append([amount, zone])
	enemies.enemy_damaged.connect(on_damaged)
	var crit_point: Vector3 = giant.global_transform * (giant.hit_zones.crit.box as AABB).get_center()
	enemies.request_hit(giant.id, 20.0, crit_point, "rifle")
	enemies.enemy_damaged.disconnect(on_damaged)
	_check("antenna crits still multiply", crit_damage.size() == 1 and crit_damage[0][1] == "crit" and crit_damage[0][0] == 100.0, str(crit_damage))
	_check("and break the antennae", giant.antennae_broken and not giant.hit_zones.has("crit"))
	var antennae: int = giant_full - giant._count_voxels(giant.without_antennae(model))
	await _frames(1)
	_check("the carved body loses the antennae too", giant.voxel_count() <= carved - antennae and giant._mesh.mesh == giant._own_mesh,
			"%d -> %d (antennae %d)" % [carved, giant.voxel_count(), antennae])
	var timings := []
	for amount in [30.0, 4.0]:
		var started_carve := Time.get_ticks_usec()
		giant.chip(side, amount)
		var chip_ms := (Time.get_ticks_usec() - started_carve) / 1000.0
		started_carve = Time.get_ticks_usec()
		giant._rebuild_own_mesh()
		timings.append("chip(%d) %.2f ms + own mesh %.2f ms" % [amount, chip_ms, (Time.get_ticks_usec() - started_carve) / 1000.0])
	print("    giant: %s" % ", ".join(timings))
	enemies.despawn(giant.id)
	await _frames(2)


## Two concrete rooms side by side with a doorway between, a spawn in room B, an inactive spawner in
## room A and a trigger in room B that turns it on.
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
	for room in [ROOM_A, ROOM_B]:
		world.fill_box(room[0], room[1], M.AIR, false)
	world.fill_box(DOOR[0], DOOR[1], M.AIR, false)
	level.voxels = world.get_data()
	world.free()

	var spawn := LevelSchema.new_marker("spawn", PLAYER_SPOT, 0.0)
	spawn.id = "spawn_1"
	var spawner := LevelSchema.new_marker("horde", SPAWNER_SPOT)
	spawner.id = "horde_test"
	spawner.rate = 600.0
	spawner.max_alive = 3
	spawner.active = false
	var trigger := LevelSchema.new_marker("trigger", TRIGGER_SPOT)
	trigger.id = "trigger_test"
	trigger.activates = "horde_test"
	for object in [spawn, spawner, trigger]:
		level.objects[object.id] = object
	# An old-style spawner without the phase 1 fields must load with defaults.
	level.objects["horde_old"] = {kind = "marker", type = "horde", position = Vector3(40.0, FLOOR, 60.0), yaw = 0.0, id = "horde_old"}
	_check("level saves", level.save() == OK)
	var loaded := LevelData.load_level(LEVEL)
	var old: Dictionary = loaded.objects.get("horde_old", {}) if loaded else {}
	_check("old spawner gets default fields", old.get("kinds") == "basic" and old.get("max_alive") == 4 and old.get("active") == true, str(old))
	_check("int fields load as ints", loaded and loaded.objects.horde_test.max_alive is int)
	# The old spawner is active by default; turn it off in the saved file so it doesn't interfere.
	loaded.objects.horde_old.active = false
	loaded.save()


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await physics_frame
	return true


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(label: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", label, "" if ok else detail])
	if not ok:
		_failures += 1
