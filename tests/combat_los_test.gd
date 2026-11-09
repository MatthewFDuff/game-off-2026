extends SceneTree
## Headless checks for combat fairness (line of sight, fair spawns, emergence):
##   godot --headless --path . --script res://tests/combat_los_test.gd
## Builds a two-storey concrete level (a ground room, an 0.8 m slab, a room above), plays it solo
## and checks: Combat.can_see is blocked by the slab and a wall but not by glass; a spore cloud on
## the floor above doesn't blind the player below, one in the same room does; enemy sounds through
## the slab are muffled; a giant's swing doesn't reach through a wall but does without it; a basic
## shroom doesn't bite through a thin wall; a spawner the player is looking at (or within 6 m of)
## defers and keeps its budget, one behind the player spawns, and the deferred one spawns once the
## player turns away; a giant spawner in a 1 m corridor defers (one that also lists basic spawns a
## basic) while one in the open room spawns a giant with its body clear; a spawned enemy emerges out of the floor (unhittable, no attack) before its
## first bite, and a ceiling one drops in from above. Spawner scope: a spawner on the floor below
## (10 m in a straight line, no path) doesn't trickle while the player is upstairs and does once
## they're on its floor, and turning it off sinks its enemy (no death). Player attacks: an
## explosive blast and a melee swing don't reach an enemy through a wall, and do without it.
##
## Game types are left unnamed (see editor_test.gd).

const SCRATCH := "user://combat_los_test_levels/"
const LEVEL := "combat_los_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIZE := Vector3i(8, 3, 8)
const FLOOR := 8
## Ground room, the slab over it, and the upper room, in voxels [from, to).
const GROUND := [Vector3i(8, FLOOR, 8), Vector3i(248, 40, 248)]
const SLAB_TOP := 48
const UPPER := [Vector3i(8, SLAB_TOP, 8), Vector3i(248, 88, 248)]
const PLAYER_SPOT := Vector3(128.0, FLOOR, 160.0)
## Spawners (voxels): 12 m in front of the player, 8 m behind, and 4 m behind (too close).
const FRONT_SPOT := Vector3(128.0, FLOOR, 40.0)
const BACK_SPOT := Vector3(128.0, FLOOR, 240.0)
const CLOSE_SPOT := Vector3(100.0, FLOOR, 200.0)
## A spawner on the ground floor about 10 m behind the player, and the spot above the player's.
const BELOW_SPOT := Vector3(60.0, FLOOR, 230.0)
const UPSTAIRS_SPOT := Vector3(128.0, SLAB_TOP, 160.0)
## Spawn room (voxels): a 1 m wide corridor (x 195..205, walls either side, from z 190 to the back
## wall) about 8 m behind-right of the player, and an open spot 8 m behind-left.
const CORRIDOR_SPOT := Vector3(200.0, FLOOR, 225.0)
const OPEN_SPOT := Vector3(60.0, FLOOR, 200.0)

var _failures := 0
var lab
var me
var enemies
var director
var combat


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
	director = lab.director
	director.scale_per_player = 0.0
	lab.items.drop_chance = 0.0
	combat = load("res://scripts/combat/combat.gd")
	await _frames(10)

	await _sight()
	await _spore_clouds()
	await _giant_wall()
	await _bite_wall()
	await _fair_spawns()
	await _room_to_move()
	await _emergence()
	await _wake_by_path()
	await _blast_wall()
	await _melee_wall()

	print("combat los test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Combat.can_see: the slab and a wall block, glass doesn't, a start buried in the floor is fine.
func _sight() -> void:
	var world = lab.world
	var chest: Vector3 = combat.chest(me)
	var above: Vector3 = me.global_position + Vector3(0.0, 5.0, 0.0)
	_check("the slab blocks sight to the floor above", not combat.can_see(world, above, chest))
	_check("open air doesn't", combat.can_see(world, me.global_position + Vector3(2.0, 1.5, -3.0), chest))
	var floor_point: Vector3 = me.global_position + Vector3(0.0, -0.05, -2.0)
	_check("a point buried in the floor still sees the room", combat.can_see(world, floor_point, chest))
	var wall := _wall(-2.0, M.CONCRETE)
	_check("a wall blocks it", not combat.can_see(world, me.global_position + Vector3(0.0, 1.0, -3.0), chest))
	_fill(wall, M.GLASS)
	_check("glass doesn't", combat.can_see(world, me.global_position + Vector3(0.0, 1.0, -3.0), chest))
	_fill(wall, M.AIR)
	_check("sounds through the slab are muffled", combat.muffle_db(world, above) < -10.0, str(combat.muffle_db(world, above)))
	_check("sounds in the room aren't", combat.muffle_db(world, me.global_position + Vector3(1.0, 1.0, -4.0)) == 0.0)


## A spore cloud on the floor above (its sphere reaching down through the slab) doesn't blind the
## player below; one in the same room does.
func _spore_clouds() -> void:
	me.statuses.clear()
	var cloud_script = load("res://scripts/weapons/cloud.gd")
	var upstairs: Vector3 = Vector3(me.global_position.x, SLAB_TOP * 0.1 + 1.0, me.global_position.z)
	_check("the cloud's sphere would reach the player", upstairs.y - (me.global_position.y + me.get_body_size().y) < 4.0)
	cloud_script.spawn("spore", upstairs, 4.0, 1.5)
	await _wait_seconds(1.0)
	_check("a spore cloud one floor up doesn't blind the player below", not me.statuses.has("blinded"), str(me.statuses))
	await _wait_seconds(0.8)
	cloud_script.spawn("spore", me.global_position + Vector3(0.0, 1.0, -1.5), 4.0, 1.0)
	await _wait_seconds(0.6)
	_check("one in the same room does", me.statuses.has("blinded"), str(me.statuses))
	me.statuses.clear()
	_clear()
	await _wait_seconds(1.2)


## The giant's swing: blocked by a wall between, lands without it.
func _giant_wall() -> void:
	_reset_player()
	var giant = enemies.spawn("giant", me.global_position + Vector3(0.0, 0.0, -2.1), PI)
	giant.speed = 0.0
	giant._attack_timer = 1000.0 # No swings of its own; the test swings it.
	var wall := _wall(-1.05, M.CONCRETE)
	await _frames(3)
	var hurt := [0.0]
	var on_hurt := func(amount: float, _from: Vector3) -> void: hurt[0] += amount
	me.damaged.connect(on_hurt)
	_check("the giant is within swing reach", Vector2(giant.global_position.x - me.global_position.x,
			giant.global_position.z - me.global_position.z).length() < giant.swing_reach)
	_check("it can't see the player through the wall", not giant.sees(me))
	giant._attack(me, true)
	await _frames(2)
	_check("the giant's swing doesn't reach through a wall", hurt[0] == 0.0, str(hurt[0]))
	_fill(wall, M.AIR)
	giant._attack(me, true)
	await _frames(2)
	_check("without the wall it lands", hurt[0] >= 30.0, str(hurt[0]))
	me.damaged.disconnect(on_hurt)
	_clear()
	await _frames(2)


## A basic shroom pressed against a thin wall, the player just the other side, doesn't bite.
func _bite_wall() -> void:
	_reset_player()
	var wall := _wall(-0.45, M.CONCRETE)
	var shroom = enemies.spawn("basic", me.global_position + Vector3(0.0, 0.0, -0.95), 0.0)
	shroom.speed = 0.0
	var hurt := [0]
	var on_hurt := func(_amount: float, _from: Vector3) -> void: hurt[0] += 1
	me.damaged.connect(on_hurt)
	await _wait_seconds(2.0)
	_check("a shroom within reach behind a thin wall can't bite", hurt[0] == 0 and _flat(shroom) < shroom.attack_range,
			"%d bites at %.2f m" % [hurt[0], _flat(shroom)])
	_fill(wall, M.AIR)
	var bitten := await _wait_until(func() -> bool: return hurt[0] > 0, 3.0)
	_check("with the wall gone it bites", bitten)
	me.damaged.disconnect(on_hurt)
	_clear()
	await _frames(2)


## Spawners: the one the player looks at defers (budget kept), as does one too close; the one
## behind spawns; turning around lets the front one spawn.
func _fair_spawns() -> void:
	_reset_player()
	var deferred_before: int = director.deferred_spawns
	director.set_spawner_active("front", true)
	director.set_spawner_active("close", true)
	await _wait_seconds(1.0)
	_check("a spawn the player is looking at is deferred", director.spawners.front.alive.is_empty()
			and director.deferred_spawns > deferred_before, "%d alive, %d deferred" % [director.spawners.front.alive.size(), director.deferred_spawns])
	_check("and keeps its budget", director.spawners.front.budget >= 1.0, str(director.spawners.front.budget))
	_check("a spawn within 6 m (behind) is deferred too", director.spawners.close.alive.is_empty())
	director.set_spawner_active("close", false)
	director.set_spawner_active("back", true)
	var behind := await _wait_until(func() -> bool: return not director.spawners.back.alive.is_empty(), 2.0)
	_check("a spawn behind the player succeeds", behind)
	if behind:
		var spawned = enemies.get_enemy(director.spawners.back.alive[0])
		var spot: Vector3 = lab.view.to_world(BACK_SPOT)
		_check("at a fair spot", spawned != null and spawned.global_position.distance_to(me.global_position) > 6.0
				and Vector2(spawned.global_position.x - spot.x, spawned.global_position.z - spot.z).length() < 2.2)
		_check("emerging out of the floor", spawned != null and spawned.emerge_from == 1)
	director.set_spawner_active("back", false)
	me.rotation.y = PI
	var turned := await _wait_until(func() -> bool: return not director.spawners.front.alive.is_empty(), 2.0)
	_check("once the player looks away, the deferred spawn goes through", turned)
	director.set_spawner_active("front", false)
	me.rotation.y = 0.0
	_clear()
	await _frames(2)


## Room to move: a giant-only spawner in a 1 m corridor never wedges a giant in (it defers), one
## that also lists basic falls back to a basic, and in the open room a giant spawns clear of solids.
func _room_to_move() -> void:
	_reset_player()
	_clear()
	var walls := [[Vector3i(180, FLOOR, 190), Vector3i(195, GROUND[1].y, GROUND[1].z)],
			[Vector3i(205, FLOOR, 190), Vector3i(220, GROUND[1].y, GROUND[1].z)]]
	for wall in walls:
		_fill(wall, M.CONCRETE)
	await _frames(2)
	var deferred_before: int = director.deferred_spawns
	var tight = director._spawn_from("corridor_giant")
	_check("a giant spawner in a 1 m corridor spawns nothing", tight == null and director.spawners.corridor_giant.alive.is_empty()
			and director.deferred_spawns > deferred_before, str(tight))
	var fallbacks := 0
	for i in 6:
		var mixed = director._spawn_from("corridor_mixed")
		if mixed != null and mixed.kind == "basic":
			fallbacks += 1
		elif mixed != null:
			_check("a mixed spawner in the corridor never makes a giant", false, mixed.kind)
	_check("one that also lists basic falls back to a basic", fallbacks == 6, "%d of 6" % fallbacks)
	_clear()
	await _frames(2)
	var giant = director._spawn_from("open_giant")
	_check("in the open room it spawns a giant", giant != null and giant.kind == "giant")
	if giant != null:
		var feet: Vector3 = giant._emerge_goal if giant.emerging > 0.0 else giant.global_position
		var body: Vector3 = giant.body_size
		var box := AABB(feet + Vector3(-body.x * 0.5, 0.02, -body.z * 0.5), body)
		_check("its body box is clear of solids", not lab.world.box_overlaps_solid(box), str(feet))
		var roomy := AABB(box.position - Vector3(0.45, 0.0, 0.45), box.size + Vector3(0.9, 0.0, 0.9))
		_check("with room to step out", not lab.world.box_overlaps_solid(roomy))
	_clear()
	for wall in walls:
		_fill(wall, M.AIR)
	await _frames(2)


## A spawned enemy emerges: under the floor, unhittable and harmless for EMERGE_TIME, then bites.
func _emergence() -> void:
	_reset_player()
	var feet: Vector3 = me.global_position + Vector3(0.0, 0.0, -0.9)
	var start := Time.get_ticks_msec()
	var shroom = enemies.spawn("basic", feet, 0.0, 1)
	var first_bite := [-1.0]
	var on_hurt := func(_amount: float, _from: Vector3) -> void:
		if first_bite[0] < 0.0:
			first_bite[0] = (Time.get_ticks_msec() - start) / 1000.0
	me.damaged.connect(on_hurt)
	await _frames(2)
	_check("it starts below the floor", shroom.emerging > 0.0 and shroom.global_position.y < feet.y - 0.3, str(shroom.global_position.y - feet.y))
	_check("and can't be hit", not combat.enemies().has(shroom))
	var health: float = shroom.health
	enemies.request_hit(shroom.id, 10.0, shroom.get_center(), "rifle")
	_check("hits do nothing", shroom.health == health)
	await _wait_seconds(0.4)
	_check("it rises", shroom.global_position.y > feet.y - 0.3 and shroom.global_position.y < feet.y - 0.01, str(shroom.global_position.y - feet.y))
	var bitten := await _wait_until(func() -> bool: return first_bite[0] >= 0.0, 4.0)
	_check("emergence delays the first attack", bitten and first_bite[0] >= shroom.EMERGE_TIME, str(first_bite[0]))
	_check("it ends on its feet, hittable", absf(shroom.global_position.y - feet.y) < 0.05 and combat.enemies().has(shroom))
	me.damaged.disconnect(on_hurt)
	_clear()
	await _frames(2)

	# A ceiling spawn drops in from above.
	var under: Vector3 = me.global_position + Vector3(8.0, 2.5, -4.0)
	var sac = enemies.spawn("ceiling_cloud", under, 0.0, -1)
	await _frames(3)
	var early: float = sac.global_position.y
	await _wait_seconds(1.0)
	_check("a ceiling spawn drops in out of the ceiling", sac.attached and early > sac.global_position.y + 0.1,
			"%.2f -> %.2f" % [early, sac.global_position.y])
	_clear()
	await _frames(2)


## Wake range by walking: a spawner on the floor below, well within wake_range in a straight line
## but with no path up, stays quiet; on its floor it trickles; off sinks its enemy without a death.
func _wake_by_path() -> void:
	_reset_player()
	me.teleport(lab.view.to_world(UPSTAIRS_SPOT))
	await _wait_seconds(0.5)
	var spot: Vector3 = lab.view.to_world(BELOW_SPOT)
	var straight: float = enemies.nearest_player_distance(spot)
	_check("the spawner below is within wake range in a straight line", straight < director.wake_range, "%.1f m" % straight)
	_check("but the flow field doesn't reach it", enemies.flow_reached > 0 and director.walk_distance(director.spawners.below.object) > director.wake_range,
			"%d reached, %.1f m" % [enemies.flow_reached, director.walk_distance(director.spawners.below.object)])
	director.set_spawner_active("below", true)
	await _wait_seconds(1.5)
	_check("a spawner a floor below by the slab doesn't trickle", director.spawners.below.alive.is_empty(), str(director.spawners.below.alive))
	_reset_player()
	var woke := await _wait_until(func() -> bool: return not director.spawners.below.alive.is_empty(), 3.0)
	_check("on its floor it does", woke)
	if not woke:
		director.set_spawner_active("below", false)
		return
	var shroom = enemies.get_enemy(director.spawners.below.alive[0])
	var deaths := [0]
	var on_died := func(_enemy) -> void: deaths[0] += 1
	enemies.enemy_died.connect(on_died)
	director.set_spawner_active("below", false)
	_check("off= takes its enemy out of play at once", not enemies.enemies.has(shroom.id) and not combat.enemies().has(shroom)
			and director.spawners.below.alive.is_empty())
	var top: float = shroom.global_position.y
	await _wait_seconds(0.25)
	_check("it sinks into the floor", is_instance_valid(shroom) and shroom.global_position.y < top - 0.2)
	await _wait_seconds(0.5)
	_check("and is gone, without a death", not is_instance_valid(shroom) and deaths[0] == 0, str(deaths[0]))
	enemies.enemy_died.disconnect(on_died)
	_clear()
	await _frames(2)


## An explosive blast on a wall's near face doesn't hurt an enemy behind it; without the wall it
## does. (Weapon.splash, the blast's damage; its carve is separate.)
func _blast_wall() -> void:
	_reset_player()
	var shroom = enemies.spawn("basic", me.global_position + Vector3(0.0, 0.0, -3.0), 0.0)
	shroom.speed = 0.0
	var wall := _wall(-2.2, M.CONCRETE)
	await _frames(3)
	var type = load("res://scripts/weapons/ammo_type.gd").by_name("explosive")
	var at: Vector3 = me.global_position + Vector3(0.0, 0.6, -2.1)
	var health: float = shroom.health
	_check("the enemy is within the blast's splash", combat.sphere_hit(at, type.splash_radius).has(shroom))
	me.weapon.splash(type, at, Vector3.BACK)
	await _frames(2)
	_check("an explosive blast doesn't damage an enemy behind a wall", shroom.health == health, "%.1f -> %.1f" % [health, shroom.health])
	_fill(wall, M.AIR)
	me.weapon.splash(type, at, Vector3.BACK)
	await _frames(2)
	_check("without the wall it does", not is_instance_valid(shroom) or shroom.health < health)
	_clear()
	await _frames(2)


## A melee swing at an enemy just the other side of a thin wall doesn't land; without it, it does.
func _melee_wall() -> void:
	_reset_player()
	var shroom = enemies.spawn("basic", me.global_position + Vector3(0.0, 0.0, -1.3), 0.0)
	shroom.speed = 0.0
	shroom._attack_timer = 1000.0
	var wall := _wall(-0.7, M.CONCRETE)
	await _frames(3)
	var health: float = shroom.health
	_check("the enemy is in the swing's box", combat.box_hit(me.weapon.melee_box()).has(shroom))
	var swings := []
	var on_melee := func(hits: int) -> void: swings.append(hits)
	me.weapon.meleed.connect(on_melee)
	me.weapon._melee_strike()
	await _frames(2)
	_check("melee doesn't hit through a wall", shroom.health == health and swings == [0], "%s, %.1f" % [swings, shroom.health])
	_fill(wall, M.AIR)
	me.weapon._melee_strike()
	await _frames(2)
	_check("without the wall it does", swings.size() == 2 and swings[1] == 1 and (not is_instance_valid(shroom) or shroom.health < health), str(swings))
	me.weapon.meleed.disconnect(on_melee)
	_clear()
	await _frames(2)


# --- Helpers -------------------------------------------------------------------------------------

## A 0.2 m wall across the ground room at z_offset meters from the player, floor to slab. Returns
## its [from, to) voxel box.
func _wall(z_offset: float, material: int) -> Array:
	var z: int = lab.world.world_to_voxel(me.global_position + Vector3(0.0, 0.0, z_offset)).z
	var box := [Vector3i(GROUND[0].x, FLOOR, z - 1), Vector3i(GROUND[1].x, GROUND[1].y, z + 1)]
	_fill(box, material)
	return box


func _fill(box: Array, material: int) -> void:
	lab.world.fill_box(box[0], box[1], material, false)


func _flat(enemy) -> float:
	var offset: Vector3 = enemy.global_position - me.global_position
	return Vector2(offset.x, offset.z).length()


func _reset_player() -> void:
	me.teleport(lab.view.to_world(PLAYER_SPOT))
	me.velocity = Vector3.ZERO
	me.rotation.y = 0.0
	me.health = me.max_health
	me.statuses.clear()


func _clear() -> void:
	for id: int in enemies.enemies.keys():
		enemies.despawn(id)
	for cloud in enemies.clouds.values():
		cloud.queue_free()
	enemies.clouds.clear()


## Two concrete storeys, the player spawn on the ground floor facing -Z, and four inactive
## spawners (front, back, close, below).
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
	world.fill_box(GROUND[0], GROUND[1], M.AIR, false)
	world.fill_box(UPPER[0], UPPER[1], M.AIR, false)
	level.voxels = world.get_data()
	world.free()
	var spawn := LevelSchema.new_marker("spawn", PLAYER_SPOT, 0.0)
	spawn.id = "spawn_1"
	level.objects[spawn.id] = spawn
	for entry in [["front", FRONT_SPOT], ["back", BACK_SPOT], ["close", CLOSE_SPOT], ["below", BELOW_SPOT],
			["corridor_giant", CORRIDOR_SPOT, "giant"], ["corridor_mixed", CORRIDOR_SPOT, "giant,basic"],
			["open_giant", OPEN_SPOT, "giant"]]:
		var spawner := LevelSchema.new_marker("horde", entry[1])
		spawner.id = entry[0]
		spawner.kinds = entry[2] if entry.size() > 2 else "basic"
		spawner.rate = 600.0
		spawner.max_alive = 1
		spawner.radius = 0.5
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
