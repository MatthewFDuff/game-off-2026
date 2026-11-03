extends SceneTree
## Headless checks for the first half of the enemy roster (phase 4):
##   godot --headless --path . --script res://tests/roster_a_test.gd
## Builds a scratch level (one big, tall concrete room with an inactive horde spawner), plays it
## solo, and checks: every kind spawns with its .vox body; the fast shroom closes on the player
## faster than a basic one; the exploding shroom lights its fuse next to the player, then carves
## the floor and hurts the player and a nearby enemy, and killed early it goes off smaller; the
## giant's antennae take 5x damage and break off after 60 (zone gone, mesh rebuilt, stagger), and
## its swing hurts and shoves the player and gouges the floor; the ranged shooter backs off when
## too close, walks in when too far, and spits globs that hurt and poison the player; the alarm
## shroom doesn't scream through a wall, screams once it can see the player, is choked off by a
## hit during the wind-up, and otherwise starts a horde (enemies spawn, a notice shows).
##
## Game types are left unnamed (see editor_test.gd): naming them would compile those scripts before
## the autoloads they use are registered.

const SCRATCH := "user://roster_a_test_levels/"
const LEVEL := "roster_a_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIZE := Vector3i(8, 3, 8)
const FLOOR := 8
## The room, in voxels [from, to).
const ROOM := [Vector3i(8, FLOOR, 8), Vector3i(248, 72, 248)]
const PLAYER_SPOT := Vector3(128.0, FLOOR, 220.0)
const SPAWNER_SPOT := Vector3(40.0, FLOOR, 40.0)

var _failures := 0
var lab
var me
var enemies
## enemy id -> total damage taken
var _damage := {}
## Damage amounts the player took, in order.
var _hurt: Array[float] = []
## [center, voxel count] of every carve.
var _carves: Array = []


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
	enemies.enemy_damaged.connect(func(enemy, amount: float, _zone: String) -> void:
		_damage[enemy.id] = _damage.get(enemy.id, 0.0) + amount)
	me.damaged.connect(func(amount: float, _from: Vector3) -> void: _hurt.append(amount))
	lab.world_sync.carved.connect(func(center: Vector3, _normal: Vector3, removed: Dictionary) -> void:
		var n := 0
		for count: int in removed.values():
			n += count
		_carves.append([center, n]))

	await _kinds()
	await _fast()
	await _exploding()
	await _giant()
	await _ranged()
	await _alarm()

	print("roster A test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Every kind spawns as its own class, with a body from its .vox.
func _kinds() -> void:
	var expected := {fast = 15.0, exploding = 20.0, alarm = 40.0, giant = 300.0, ranged = 25.0}
	var x := -6.0
	for kind: String in expected:
		_check("%s is registered" % kind, enemies.KINDS.has(kind))
		var enemy = enemies.spawn(kind, me.global_position + Vector3(x, 0.0, -12.0), 0.0)
		x += 3.0
		_check("%s spawns with %d health and its model" % [kind, expected[kind]],
				enemy != null and enemy.kind == kind and enemy.max_health == expected[kind] and enemy._mesh != null and enemy._mesh.mesh != null,
				str(enemy))
		_check("%s placeholders exist" % kind, FileAccess.file_exists("res://assets/vox/enemies/%s_0.vox" % kind))
	var giant = _first("giant")
	_check("the giant is about 26 x 40 x 26 voxels", giant and giant.bounds.size.is_equal_approx(Vector3(2.6, 4.0, 2.6)), str(giant.bounds if giant else null))
	_clear()
	await _frames(2)


## Fast: closes faster than a basic shroom over 3 s.
func _fast() -> void:
	_reset_player()
	var basic = enemies.spawn("basic", me.global_position + Vector3(-3.0, 0.0, -20.0), 0.0)
	var fast = enemies.spawn("fast", me.global_position + Vector3(3.0, 0.0, -20.0), 0.0)
	_check("fast is twice the basic speed", fast.speed == basic.speed * 2.0 and fast.damage == 8.0)
	var basic_start: float = basic.global_position.distance_to(me.global_position)
	var fast_start: float = fast.global_position.distance_to(me.global_position)
	await _wait_seconds(3.0)
	var basic_closed: float = basic_start - basic.global_position.distance_to(me.global_position)
	var fast_closed: float = fast_start - fast.global_position.distance_to(me.global_position)
	_check("fast closes faster than basic over 3 s", fast_closed > basic_closed * 1.5, "fast %.1f m, basic %.1f m" % [fast_closed, basic_closed])
	_clear()
	await _frames(2)


## Exploding: fuse next to the player, then a carve that hurts the player and an enemy nearby; killed
## early, a smaller blast.
func _exploding() -> void:
	_reset_player()
	var dummy = _target(Vector3(1.6, 0.0, -0.6))
	var boomer = enemies.spawn("exploding", me.global_position + Vector3(0.0, 0.0, -8.0), 0.0)
	var lit := [false, false]
	var last: Array = [boomer.global_position]
	var ref: WeakRef = weakref(boomer)
	var gone := await _wait_until(func() -> bool:
		var boomer_now = ref.get_ref()
		if boomer_now and boomer_now.alive:
			last[0] = boomer_now.global_position
			if boomer_now.fuse >= 0.0:
				lit[0] = true
				if boomer_now._mesh.material_overlay == boomer_now._fuse_material and boomer_now._fuse_material != null:
					lit[1] = true
			return false
		return true, 8.0)
	_check("lights its fuse next to the player", lit[0] and last[0].distance_to(me.global_position) < 2.3, "%s, %.2f m" % [lit[0], last[0].distance_to(me.global_position)])
	_check("and flashes", lit[1])
	_check("then blows up", gone)
	var blast: Array = _carves.back() if not _carves.is_empty() else []
	_check("the blast carves the floor", not blast.is_empty() and blast[1] > 100 and (blast[0] as Vector3).distance_to(last[0]) < 1.5,
			str(blast))
	var under: Vector3i = lab.world.world_to_voxel(last[0] + Vector3.DOWN * 0.15)
	_check("a hole where it stood", lab.world.get_voxel(under) == M.AIR)
	_check("the player takes 40", 40.0 in _hurt, str(_hurt))
	_check("the enemy next to it takes 40", absf(_damage.get(dummy.id, 0.0) - 40.0) < 0.01, str(_damage.get(dummy.id, 0.0)))
	_clear()
	await _frames(2)

	# Killed before it goes off: a smaller blast, 15 damage, the player out of reach.
	_reset_player()
	var spot: Vector3 = me.global_position + Vector3(0.0, 0.0, -10.0)
	var early = enemies.spawn("exploding", spot, 0.0)
	early.speed = 0.0
	var near = _target(Vector3(1.0, 0.0, -10.0))
	await _frames(3)
	var carves_before := _carves.size()
	_hurt.clear()
	enemies.request_hit(early.id, 100.0, early.get_center(), "rifle")
	_check("killed early, it dies", not enemies.enemies.has(early.id) and early.exploded)
	_check("and still goes off, smaller", _carves.size() > carves_before and _carves.back()[1] < blast[1] if not blast.is_empty() else false,
			str(_carves.back() if _carves.size() > carves_before else "no carve"))
	_check("the enemy next to it takes 15", absf(_damage.get(near.id, 0.0) - 15.0) < 0.01, str(_damage.get(near.id, 0.0)))
	_check("the player 10 m off takes nothing", _hurt.is_empty(), str(_hurt))
	_clear()
	await _frames(2)


## Giant: 5x on the antennae, which break off after 60; the swing hurts, shoves and gouges.
func _giant() -> void:
	_reset_player()
	var giant = enemies.spawn("giant", me.global_position + Vector3(0.0, 0.0, -7.0), 0.0)
	giant.speed = 0.0
	await _frames(3)
	_check("the giant has a crit zone on its antennae", giant.hit_zones.has("crit") and giant.hit_zones.crit.crit == 5.0
			and (giant.hit_zones.crit.box as AABB).position.y > 2.3, str(giant.hit_zones))
	var zone: AABB = giant.global_transform * (giant.hit_zones.crit.box as AABB)
	# A shot at an antenna strand, from where the player stands.
	var model: Dictionary = load("res://scripts/enemies/enemy_models.gd").model("giant", giant.variant)
	var strand := _solid_point(giant, model, zone)
	var eye: Vector3 = me.global_position + Vector3.UP * 1.6
	var ray: Dictionary = load("res://scripts/combat/combat.gd").ray_hit(lab.world, eye, strand - eye, 30.0)
	_check("a ray at an antenna hits the crit zone", ray.enemy == giant and ray.zone == "crit" and ray.crit == 5.0, str(ray))
	var hits := []
	var on_hit := func(enemy, amount: float, hit_zone: String) -> void:
		if enemy == giant:
			hits.append([amount, hit_zone])
	enemies.enemy_damaged.connect(on_hit)
	var body_mesh: Mesh = giant._mesh.mesh
	enemies.request_hit(giant.id, 10.0, ray.position, "rifle")
	_check("the antennae take 5x", hits.size() == 1 and hits[0][0] == 50.0 and hits[0][1] == "crit", str(hits))
	_check("and hold at 50 damage", giant.hit_zones.has("crit") and not giant.antennae_broken)
	enemies.request_hit(giant.id, 10.0, ray.position, "rifle")
	_check("past 60 the antennae break off", giant.antennae_broken and not giant.hit_zones.has("crit"))
	_check("the mesh is rebuilt without them", giant._mesh.mesh != body_mesh and giant._mesh.mesh != null)
	_check("it staggers", giant.stagger > 1.0)
	_check("the crit took 100 of its 300", giant.health == 200.0, str(giant.health))
	enemies.request_hit(giant.id, 10.0, ray.position, "rifle")
	_check("the same spot is just body now", hits.size() == 3 and hits[2][1] == "body" and hits[2][0] == 10.0, str(hits))
	enemies.enemy_damaged.disconnect(on_hit)

	# The swing: it walks up (after the stagger), hits for 30, shoves the player well back and digs
	# (soft ground only: it's a low-power gouge, so the floor between them is dirt).
	var feet: Vector3i = lab.world.world_to_voxel(me.global_position + Vector3.UP * 0.05)
	lab.world.fill_box(feet + Vector3i(-20, -3, -80), feet + Vector3i(20, 0, 10), M.DIRT, false)
	giant.speed = 1.2
	giant.health = 10000.0
	_hurt.clear()
	var carves_before := _carves.size()
	var start: Vector3 = me.global_position
	var swung := await _wait_until(func() -> bool: return 30.0 in _hurt, 12.0)
	_check("the giant's swing hits for 30", swung, str(_hurt))
	await _wait_seconds(0.6)
	var shoved := Vector2(me.global_position.x - start.x, me.global_position.z - start.z).length()
	_check("and shoves the player back hard", shoved > 1.5, "%.2f m" % shoved)
	_check("and gouges the ground in front of it", _carves.size() > carves_before, "%d carves" % (_carves.size() - carves_before))
	_clear()
	await _frames(2)


## Ranged: backs off when close, walks in when far, spits globs that poison the player.
func _ranged() -> void:
	_reset_player()
	var close = enemies.spawn("ranged", me.global_position + Vector3(-2.0, 0.0, -4.0), 0.0)
	var far = enemies.spawn("ranged", me.global_position + Vector3(2.0, 0.0, -19.0), 0.0)
	var close_start: float = _flat_distance(close)
	var far_start: float = _flat_distance(far)
	var spat := [false]
	var blob := [false]
	var poisoned := await _wait_until(func() -> bool:
		for enemy in [close, far]:
			if is_instance_valid(enemy) and not enemy.spits.is_empty():
				spat[0] = true
				var shot = enemy.spits.values()[0]
				if is_instance_valid(shot) and shot.get_node_or_null("Blob") != null:
					blob[0] = true
		return me.statuses.has("poisoned"), 8.0)
	_check("it spits globs", spat[0] and blob[0])
	_check("a glob hits for 12", 12.0 in _hurt, str(_hurt))
	_check("and poisons the player", poisoned, str(me.statuses))
	await _wait_seconds(3.0)
	_check("the close one backs off", _flat_distance(close) > close_start + 2.5, "%.1f -> %.1f m" % [close_start, _flat_distance(close)])
	_check("the far one walks in to 8-12 m", _flat_distance(far) < 12.5 and _flat_distance(far) > 7.0,
			"%.1f -> %.1f m" % [far_start, _flat_distance(far)])
	_clear()
	await _frames(2)


## Alarm: no scream through a wall; with a view it winds up; a hit chokes it; otherwise a horde.
func _alarm() -> void:
	_reset_player()
	var notices: Array[String] = []
	lab.notice.connect(func(text: String) -> void: notices.append(text))
	var wall_z := int(PLAYER_SPOT.z) - 60
	var wall := [Vector3i(ROOM[0].x, FLOOR, wall_z), Vector3i(ROOM[1].x, ROOM[1].y, wall_z + 4)]
	lab.world.fill_box(wall[0], wall[1], M.CONCRETE, false)
	var alarm = enemies.spawn("alarm", me.global_position + Vector3(0.0, 0.0, -15.0), 0.0)
	alarm.horde_count = 3
	var screamed := await _wait_until(func() -> bool: return alarm.scream >= 0.0, 2.5)
	_check("the alarm shroom can't see through a wall", not screamed and not alarm.sees_player())
	lab.world.fill_box(wall[0], wall[1], M.AIR, false)
	screamed = await _wait_until(func() -> bool: return alarm.scream >= 0.0, 2.0)
	_check("with a clear view it winds up a scream", screamed and alarm.sees_player())
	await _frames(5)
	_check("pulsing red", alarm._mesh.material_overlay == alarm._pulse_material and alarm._pulse_material != null)
	enemies.request_hit(alarm.id, 5.0, alarm.get_center(), "rifle")
	_check("a hit during the wind-up chokes it", alarm.scream < 0.0 and alarm.cooldown > 0.0)
	await _wait_seconds(1.8)
	_check("so no horde", lab.director.state == "calm" and enemies.alive_count() == 1, "%s, %d alive" % [lab.director.state, enemies.alive_count()])

	var states: Array[String] = []
	lab.director.state_changed.connect(func(state: String) -> void: states.append(state))
	var horde := await _wait_until(func() -> bool: return "horde" in states, 8.0)
	_check("left alone, it screams a horde in", horde, str(states))
	_check("with a notice", notices.any(func(text: String) -> bool: return "horde" in text.to_lower()), str(notices))
	var spawned := await _wait_until(func() -> bool: return enemies.alive_count() >= 4, 3.0)
	_check("the horde spawns", spawned, "%d alive" % enemies.alive_count())
	_check("then it rests", alarm.cooldown > 20.0 and alarm.scream < 0.0)
	_clear()


# --- Helpers -------------------------------------------------------------------------------------

## The world-space center of a solid model voxel inside zone (a world box), facing the player.
func _solid_point(enemy, model: Dictionary, zone: AABB) -> Vector3:
	var size: Vector3i = model.size
	var voxel_size: float = lab.world.voxel_size
	var best := zone.get_center()
	var best_distance := INF
	for z in size.z:
		for y in size.y:
			for x in size.x:
				if model.voxels[x + y * size.x + z * size.x * size.y] == 0:
					continue
				var local: Vector3 = enemy.bounds.position + (Vector3(x, y, z) + Vector3.ONE * 0.5) * voxel_size
				var point: Vector3 = enemy.global_transform * local
				if not zone.has_point(point):
					continue
				var distance := point.distance_to(me.global_position)
				if distance < best_distance:
					best_distance = distance
					best = point
	return best


func _flat_distance(enemy) -> float:
	var to: Vector3 = enemy.global_position - me.global_position
	return Vector2(to.x, to.z).length()


func _first(kind: String):
	for enemy in enemies.enemies.values():
		if enemy.kind == kind:
			return enemy
	return null


func _reset_player() -> void:
	me.revive()
	me.teleport(lab.view.to_world(PLAYER_SPOT))
	_hurt.clear()


## A still, harmless, sturdy enemy at offset (meters) from the player's feet.
func _target(offset: Vector3):
	var enemy = enemies.spawn("basic", me.global_position + offset, 0.0)
	enemy.speed = 0.0
	enemy.attack_range = 0.0
	enemy.damage = 0.0
	enemy.knockback_scale = 0.0
	enemy.max_health = 10000.0
	enemy.health = 10000.0
	return enemy


func _clear() -> void:
	for id: int in enemies.enemies.keys():
		enemies.despawn(id)
	for cloud in enemies.clouds.values():
		cloud.queue_free()
	enemies.clouds.clear()


## One big tall concrete room, the player spawn near one end facing the far wall (-Z), and an
## inactive horde spawner for the alarm shroom's horde.
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
	var spawner := LevelSchema.new_marker("horde", SPAWNER_SPOT)
	spawner.id = "horde_test"
	spawner.kinds = "basic"
	spawner.rate = 0.0
	spawner.active = false
	level.objects[spawner.id] = spawner
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


func _check(label: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", label, "" if ok or detail == "" else detail])
	if not ok:
		_failures += 1
