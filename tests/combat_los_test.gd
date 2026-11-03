extends SceneTree
## Headless checks for combat fairness (line of sight, fair spawns, emergence):
##   godot --headless --path . --script res://tests/combat_los_test.gd
## Builds a two-storey concrete level (a ground room, an 0.8 m slab, a room above), plays it solo
## and checks: Combat.can_see is blocked by the slab and a wall but not by glass; a spore cloud on
## the floor above doesn't blind the player below, one in the same room does; enemy sounds through
## the slab are muffled; a giant's swing doesn't reach through a wall but does without it; a basic
## shroom doesn't bite through a thin wall; a spawner the player is looking at (or within 6 m of)
## defers and keeps its budget, one behind the player spawns, and the deferred one spawns once the
## player turns away; a spawned enemy emerges out of the floor (unhittable, no attack) before its
## first bite, and a ceiling one drops in from above.
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
	await _emergence()

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


## Two concrete storeys, the player spawn on the ground floor facing -Z, and three inactive
## spawners (front, back, close).
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
	for entry in [["front", FRONT_SPOT], ["back", BACK_SPOT], ["close", CLOSE_SPOT]]:
		var spawner := LevelSchema.new_marker("horde", entry[1])
		spawner.id = entry[0]
		spawner.kinds = "basic"
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
