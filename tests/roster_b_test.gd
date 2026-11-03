extends SceneTree
## Headless checks for the second half of the enemy roster (phase 4B):
##   godot --headless --path . --script res://tests/roster_b_test.gd
## Builds a scratch level (one big concrete room, ceiling 4 m up), plays it solo, and checks: the
## mommy shroom births basic shrooms up to its cap of 6, a dead one frees a slot, and the brood
## pops with her; a spore cloud blinds the player inside (the fog overlay comes up) and not one
## outside, and expires (the fog clears); a spore shroom vents spores when the player is near and
## when it dies; a ceiling poison cloud hangs under the ceiling, drops a poison cloud on the floor
## when the player walks under it or when it's shot, and falls and bursts when its ceiling voxel is
## carved; a tentacle grabs the player in reach, pulls them in against their input and squeezes,
## lets go after 40 damage, ignores the held player's own melee, lets go on a partner's melee, and
## on death.
##
## Game types are left unnamed (see editor_test.gd): naming them would compile those scripts before
## the autoloads they use are registered.

const SCRATCH := "user://roster_b_test_levels/"
const LEVEL := "roster_b_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIZE := Vector3i(8, 2, 8)
const FLOOR := 8
const CEILING := 48
## The room, in voxels [from, to).
const ROOM := [Vector3i(8, FLOOR, 8), Vector3i(248, CEILING, 248)]
const PLAYER_SPOT := Vector3(128.0, FLOOR, 200.0)

var _failures := 0
var lab
var me
var enemies
var _home := Vector3.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LevelData.save_dir_override = SCRATCH
	_make_level()
	root.get_node("Net").start_solo(LEVEL, "play")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	lab = current_scene
	me = lab.local_player()
	enemies = lab.enemies
	lab.items.drop_chance = 0.0
	await _frames(10)
	_home = me.global_position

	await _mommy()
	await _spores()
	await _ceiling_cloud()
	await _tentacle()

	print("roster b test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Mommy: births up to 6, a dead child frees a slot, the brood pops with her.
func _mommy() -> void:
	# Keep the brood still and harmless so the counts are all that's tested.
	var tame := func(enemy) -> void:
		if enemy.kind == "basic":
			enemy.speed = 0.0
			enemy.damage = 0.0
			enemy.attack_range = 0.0
	enemies.enemy_spawned.connect(tame)
	var mommy = enemies.spawn("mommy", _home + Vector3(0.0, 0.0, -12.0), 0.0)
	_check("mommy spawns", mommy != null and mommy.kind == "mommy" and mommy.health == 200.0, "%s %s %s" % [mommy.kind, mommy.health, mommy.max_health] if mommy else "null")
	mommy.spawn_interval = 0.2
	mommy._spawn_timer = 0.2
	var start: Vector3 = mommy.global_position
	var full := await _wait_until(func() -> bool: return mommy.brood.size() == 6, 4.0)
	_check("mommy births basic shrooms up to 6", full and enemies.alive_count("basic") == 6,
			"%d brood, %d basic" % [mommy.brood.size(), enemies.alive_count("basic")])
	await _wait_seconds(0.8)
	_check("and no more than 6", mommy.brood.size() == 6 and enemies.alive_count("basic") == 6, str(enemies.alive_count("basic")))
	_check("mommy stays put", Vector2(mommy.global_position.x - start.x, mommy.global_position.z - start.z).length() < 0.05)
	var near := true
	for child_id: int in mommy.brood:
		near = near and enemies.get_enemy(child_id).global_position.distance_to(mommy.global_position) < 3.0
	_check("births land beside her", near)
	var first: int = mommy.brood[0]
	enemies.kill(first)
	var refilled := await _wait_until(func() -> bool: return mommy.brood.size() == 6 and not mommy.brood.has(first), 2.0)
	_check("a dead child frees a slot that refills", refilled, str(mommy.brood))
	var brood: Array = mommy.brood.duplicate()
	var mommy_id: int = mommy.id
	enemies.request_hit(mommy.id, 500.0, mommy.get_center(), "rifle")
	await _frames(2)
	var any_left := false
	for child_id: int in brood:
		any_left = any_left or enemies.enemies.has(child_id)
	_check("killing mommy pops her whole brood", not enemies.enemies.has(mommy_id) and not any_left and enemies.alive_count("basic") == 0,
			"%d basic left" % enemies.alive_count("basic"))
	enemies.enemy_spawned.disconnect(tame)
	_clear()
	await _frames(2)


## Spore clouds blind inside, not outside, and expire; spore shrooms vent near players and on death.
func _spores() -> void:
	var cloud_script = load("res://scripts/weapons/cloud.gd")
	cloud_script.spawn("spore", _home + Vector3(0.0, 1.0, -12.0), 4.0, 3.0)
	await _wait_seconds(0.6)
	_check("a spore cloud 12 m off doesn't blind the player", not me.statuses.has("blinded") and me.blind_amount == 0.0, str(me.statuses))
	_clear()
	var cloud = cloud_script.spawn("spore", _home + Vector3(0.0, 1.0, -1.0), 4.0, 1.0)
	_check("spore clouds are a dense cloud type", cloud != null and cloud.type == "spore" and cloud.get_node("Particles").amount > 100)
	var health: float = me.health
	await _wait_seconds(0.6)
	_check("a spore cloud blinds the player inside", me.statuses.has("blinded"), str(me.statuses))
	_check("the fog overlay comes up on the player's screen", me.blind_amount > 0.5 and me._blind_overlay != null and me._blind_overlay.visible,
			"%.2f" % me.blind_amount)
	_check("blinded does no damage", me.health >= health)
	var ref: WeakRef = weakref(cloud)
	cloud = null
	var gone := await _wait_until(func() -> bool: return enemies.clouds.is_empty() and ref.get_ref() == null, 2.0)
	_check("the spore cloud expires", gone)
	var cleared := await _wait_until(func() -> bool: return not me.statuses.has("blinded") and me.blind_amount == 0.0, 5.0)
	_check("blindness wears off and the fog clears", cleared and not me._blind_overlay.visible, "%s %.2f" % [me.statuses, me.blind_amount])

	var puff = enemies.spawn("spore", _home + Vector3(0.0, 0.0, -3.0), 0.0)
	puff.damage = 0.0
	_check("spore shroom: 25 health, slow", puff.max_health == 25.0 and puff.speed == 1.5, "%s %s" % [puff.max_health, puff.speed])
	var vented := await _wait_until(func() -> bool: return _clouds_of("spore") > 0, 1.0)
	_check("a spore shroom vents spores when the player comes within 4 m", vented)
	await _wait_seconds(0.8)
	_check("which blind the player", me.statuses.has("blinded"))
	_clear()
	await _frames(2)
	var far = enemies.spawn("spore", _home + Vector3(6.0, 0.0, -14.0), 0.0)
	far.speed = 0.0
	await _frames(3)
	_check("not when the player is far", _clouds_of("spore") == 0)
	var at: Vector3 = far.get_center()
	enemies.request_hit(far.id, 100.0, at, "rifle")
	await _frames(2)
	var on_death := false
	for c in enemies.clouds.values():
		on_death = on_death or (c.type == "spore" and c.global_position.distance_to(at) < 0.5)
	_check("a spore shroom vents spores when it dies", on_death)
	_clear()
	me.revive()
	await _frames(2)


## Ceiling poison clouds: hang, drop when walked under or shot, fall when the ceiling goes.
func _ceiling_cloud() -> void:
	var ceiling_y: float = lab.view.to_world(Vector3(0, CEILING, 0)).y
	var floor_y: float = lab.view.to_world(Vector3(0, FLOOR, 0)).y
	var spot := _home + Vector3(0.0, 0.0, -8.0)
	var sac = enemies.spawn("ceiling_cloud", spot, 0.0)
	var sac_id: int = sac.id
	await _physics(3)
	_check("the ceiling cloud hangs under the ceiling", sac.attached and absf(sac.global_position.y + sac.bounds.size.y - ceiling_y) < 0.05,
			"top %.2f, ceiling %.2f" % [sac.global_position.y + sac.bounds.size.y, ceiling_y])
	await _wait_seconds(0.5)
	_check("and stays there (no gravity)", sac.alive and absf(sac.global_position.y + sac.bounds.size.y - ceiling_y) < 0.05)
	_check("it doesn't drop with the player 8 m off", sac.alive and enemies.clouds.is_empty())
	me.teleport(Vector3(spot.x + 1.0, me.global_position.y, spot.z))
	var dropped := await _wait_until(func() -> bool: return not enemies.enemies.has(sac_id), 1.0)
	var cloud = enemies.clouds.values()[0] if enemies.clouds.size() == 1 else null
	_check("walking under it drops it", dropped)
	_check("a 3 m poison cloud forms on the floor below", cloud != null and cloud.type == "poison" and absf(cloud.radius - 3.0) < 0.01
			and Vector2(cloud.global_position.x - spot.x, cloud.global_position.z - spot.z).length() < 0.3
			and cloud.global_position.y < floor_y + 1.5, str(cloud.global_position if cloud else null))
	_clear()
	me.teleport(_home)
	me.revive()
	await _frames(2)

	var shot = enemies.spawn("ceiling_cloud", _home + Vector3(-4.0, 0.0, -14.0), 0.0)
	var shot_id: int = shot.id
	await _physics(3)
	enemies.request_hit(shot.id, 1.0, shot.get_center(), "rifle")
	var burst := await _wait_until(func() -> bool: return not enemies.enemies.has(shot_id), 0.5)
	_check("shooting it (even a scratch) drops it, far from the player", burst and _clouds_of("poison") == 1)
	_clear()
	await _frames(2)

	var hanging = enemies.spawn("ceiling_cloud", _home + Vector3(5.0, 0.0, -10.0), 0.0)
	var hanging_id: int = hanging.id
	await _physics(3)
	var anchor: Vector3i = hanging.anchor_voxel
	_check("it knows the ceiling voxel it hangs from", lab.world.get_voxel(anchor) == M.CONCRETE and anchor.y == CEILING, str(anchor))
	var center: Vector3 = lab.view.to_world(Vector3(anchor) + Vector3(0.5, 0.5, 0.5))
	lab.world_sync.carve_sphere(center, 0.6, 255, Vector3.DOWN)
	await _physics(2)
	_check("carving its ceiling voxel lets it fall", lab.world.get_voxel(anchor) == M.AIR and (not is_instance_valid(hanging) or hanging.falling or not hanging.alive))
	var landed := await _wait_until(func() -> bool: return not enemies.enemies.has(hanging_id), 3.0)
	_check("and it bursts where it lands", landed and _clouds_of("poison") == 1)
	_clear()
	await _frames(2)


## Tentacle: grab, pull, squeeze, let go on 40 damage, on a partner's melee, and on death.
func _tentacle() -> void:
	me.teleport(_home)
	me.revive()
	await _frames(2)
	var spot := _home + Vector3(0.0, 0.0, -3.0)
	var tentacle = enemies.spawn("tentacle", spot, 0.0)
	_check("tentacle: 120 health, rooted", tentacle.max_health == 120.0 and tentacle.speed == 0.0, "%s %s" % [tentacle.max_health, tentacle.speed])
	var grabbed := await _wait_until(func() -> bool: return me.held_by == str(tentacle.id), 1.0)
	_check("it grabs the player within 3.5 m", grabbed and tentacle.held == me, me.held_by)
	Input.action_press("move_back") # Trying to get away does nothing.
	var start := _flat_distance(spot)
	await _wait_seconds(0.5)
	var mid := _flat_distance(spot)
	_check("the held player is pulled in at about 2 m/s, against their input", mid < start - 0.6 and mid > start - 1.4,
			"%.2f -> %.2f" % [start, mid])
	var close := await _wait_until(func() -> bool: return _flat_distance(spot) <= 1.0, 2.0)
	_check("and held within 1 m", close, "%.2f" % _flat_distance(spot))
	var health: float = me.health
	await _wait_seconds(1.05)
	_check("where it squeezes 8 damage/s", absf(health - me.health - 8.0) < 4.1, "%.1f" % (health - me.health))
	Input.action_release("move_back")
	enemies.request_hit(tentacle.id, 10.0, tentacle.get_center(), "melee")
	await _frames(2)
	_check("the held player's own melee doesn't free them", me.held_by == str(tentacle.id))
	enemies.request_hit(tentacle.id, 31.0, tentacle.get_center(), "rifle")
	await _frames(2)
	_check("40 damage since the grab frees them", me.held_by == "" and is_instance_valid(tentacle) and tentacle.held == null, me.held_by)
	var regrabbed := await _wait_until(func() -> bool: return me.held_by == str(tentacle.id), 3.0)
	_check("it grabs again after a moment", regrabbed)
	# A partner's melee: the hit comes from another peer.
	enemies._hit_peer = 2
	enemies.damage(tentacle.id, 10.0, tentacle.get_center(), "melee")
	enemies._hit_peer = 0
	await _frames(2)
	_check("a partner's melee frees them", me.held_by == "" and tentacle.held == null)
	regrabbed = await _wait_until(func() -> bool: return me.held_by == str(tentacle.id), 3.0)
	enemies.request_hit(tentacle.id, 500.0, tentacle.get_center(), "rifle")
	await _frames(2)
	_check("killing it frees them", regrabbed and me.held_by == "" and not is_instance_valid(tentacle))
	var before: Vector3 = me.global_position
	Input.action_press("move_back")
	await _wait_seconds(0.3)
	Input.action_release("move_back")
	_check("and they can walk again", me.global_position.distance_to(before) > 0.5)
	_clear()


# --- Helpers -------------------------------------------------------------------------------------

func _flat_distance(to: Vector3) -> float:
	return Vector2(me.global_position.x - to.x, me.global_position.z - to.z).length()


func _clouds_of(type: String) -> int:
	var n := 0
	for cloud in enemies.clouds.values():
		if cloud.type == type:
			n += 1
	return n


func _clear() -> void:
	for id: int in enemies.enemies.keys():
		enemies.despawn(id)
	for cloud in enemies.clouds.values():
		cloud.queue_free()
	enemies.clouds.clear()


## One big concrete room 4 m tall, the player spawn near one end facing the far wall (-Z).
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
	level.voxels = world.get_data()
	world.free()
	var spawn := LevelSchema.new_marker("spawn", PLAYER_SPOT, 0.0)
	spawn.id = "spawn_1"
	level.objects[spawn.id] = spawn
	_check("level saves", level.save() == OK)


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await physics_frame
	return true


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _physics(count: int) -> void:
	for i in count:
		await physics_frame


func _check(label: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", label, "" if ok or detail == "" else detail])
	if not ok:
		_failures += 1
