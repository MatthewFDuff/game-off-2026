extends SceneTree
## Headless checks for status effects and clouds (phase 3):
##   godot --headless --path . --script res://tests/status_test.gd
## Builds a scratch level (one big concrete room), plays it solo, and checks: burning ticks damage
## and spreads to an enemy standing next to it (for less time), but not to one further off; frozen
## stops an enemy chasing the player, then lets it walk at half speed, and makes hits on it count
## 1.5x; two raging enemies fight each other while the player stands by; a poison cloud poisons
## and damages an enemy inside and not one outside, poisons the player standing in it (cleared on
## revive), and expires; a fire cloud burns away shroom voxels around it but not the concrete
## floor; tints follow the statuses.
##
## Game types are left unnamed (see editor_test.gd): naming them would compile those scripts before
## the autoloads they use are registered.

const SCRATCH := "user://status_test_levels/"
const LEVEL := "status_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIZE := Vector3i(8, 2, 8)
const FLOOR := 8
## The room, in voxels [from, to).
const ROOM := [Vector3i(8, FLOOR, 8), Vector3i(248, 48, 248)]
const PLAYER_SPOT := Vector3(128.0, FLOOR, 220.0)

var _failures := 0
var lab
var me
var enemies
## enemy id -> total damage taken
var _damage := {}


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

	await _burning()
	await _frozen()
	await _raging()
	await _poison_cloud()
	await _fire_cloud()

	print("status test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Burning: damage over time, and it jumps to a touching neighbour (shorter) but not further.
func _burning() -> void:
	var a = _target(Vector3(-2.0, 0.0, -8.0))
	var b = _target(Vector3(-1.1, 0.0, -8.0))
	var far = _target(Vector3(3.0, 0.0, -8.0))
	enemies.request_status(a.id, "burning", 4.0)
	_check("burning shows on the enemy", a.shown_statuses == PackedStringArray(["burning"]) and a._mesh.material_overlay == a.tint_material(),
			str(a.shown_statuses))
	_check("burning tints orange and lights embers", a.tint_material().albedo_color.r > 0.9 and a._embers != null and a._embers.emitting)
	await _wait_seconds(1.1)
	_check("burning ticks damage (6/s)", absf(_damage.get(a.id, 0.0) - 6.0) < 3.1, str(_damage.get(a.id, 0.0)))
	_check("burning spreads to the enemy next to it", b.statuses.has("burning"), str(b.statuses))
	_check("for less time", b.statuses.has("burning") and b.statuses.burning < a.statuses.burning,
			"%s vs %s" % [b.statuses.get("burning"), a.statuses.get("burning")])
	_check("but not to one further off", not far.statuses.has("burning") and _damage.get(far.id, 0.0) == 0.0)
	var ended := await _wait_until(func() -> bool: return not a.statuses.has("burning") and not b.statuses.has("burning"), 6.0)
	await _frames(2)
	_check("burning runs out, and the tint goes", ended and a.shown_statuses.is_empty() and a._mesh.material_overlay == null)
	_clear()
	await _frames(2)


## Frozen: an enemy chasing the player stops dead, then walks at half speed; hits count 1.5x.
func _frozen() -> void:
	var enemy = enemies.spawn("basic", me.global_position + Vector3(0.0, 0.0, -14.0), 0.0)
	enemy.attack_range = 0.0
	var walking := await _speed_of(enemy, 1.0)
	_check("an enemy walks at its speed", walking > enemy.speed * 0.7, "%.2f m/s" % walking)
	enemies.request_status(enemy.id, "frozen", 5.0)
	_check("frozen tints blue", enemy.tint_material() != null and enemy.tint_material().albedo_color.b > 0.9)
	await _wait_seconds(0.3) # Momentum settles.
	var stopped := await _speed_of(enemy, 1.2)
	_check("frozen stops it for the first 2 s", stopped < 0.15, "%.2f m/s" % stopped)
	var before: float = enemy.health
	enemies.request_hit(enemy.id, 10.0, enemy.get_center(), "status")
	_check("frozen takes 1.5x damage", absf(before - enemy.health - 15.0) < 0.01, str(before - enemy.health))
	await _wait_seconds(0.8)
	var slowed := await _speed_of(enemy, 1.0)
	_check("then half speed", enemy.status_speed() == 0.5 and slowed > enemy.speed * 0.3 and slowed < enemy.speed * 0.65,
			"%.2f m/s (speed %.1f)" % [slowed, enemy.speed])
	_clear()
	await _frames(2)


## Raging: two enemies near each other ignore the player and bite each other, faster.
func _raging() -> void:
	var a = enemies.spawn("basic", me.global_position + Vector3(-1.5, 0.0, -12.0), 0.0)
	var b = enemies.spawn("basic", me.global_position + Vector3(1.5, 0.0, -12.0), 0.0)
	for enemy in [a, b]:
		enemy.max_health = 1000.0
		enemy.health = 1000.0
		enemies.request_status(enemy.id, "raging", 6.0)
	_check("raging is 1.5x speed and tints red", a.status_speed() == 1.5 and a.tint_material().albedo_color.r > 0.9 and a.tint_material().albedo_color.g < 0.3)
	var hurt := [0]
	var on_hurt := func(_amount: float, _from: Vector3) -> void: hurt[0] += 1
	me.damaged.connect(on_hurt)
	var fought := await _wait_until(func() -> bool: return _damage.get(a.id, 0.0) > 0.0 and _damage.get(b.id, 0.0) > 0.0, 5.0)
	me.damaged.disconnect(on_hurt)
	_check("raging enemies fight each other", fought, "%s / %s" % [_damage.get(a.id, 0.0), _damage.get(b.id, 0.0)])
	_check("and leave the player alone", hurt[0] == 0 and a.global_position.distance_to(me.global_position) > 5.0)
	_clear()
	await _frames(2)


## A poison cloud: inside is poisoned and hurt, outside isn't; the player in it is poisoned (the
## HUD vignette shows it); it expires.
func _poison_cloud() -> void:
	var center: Vector3 = me.global_position + Vector3(0.0, 0.5, -8.0)
	var inside = _target(Vector3(0.5, 0.0, -8.0))
	var outside = _target(Vector3(5.0, 0.0, -8.0))
	var cloud = load("res://scripts/weapons/cloud.gd").spawn("poison", center, 2.0, 1.5)
	_check("Cloud.spawn makes a host cloud", cloud != null and cloud.authoritative and enemies.clouds.size() == 1)
	_check("drawn with a ground stain and particles", cloud != null and cloud.get_node_or_null("Stain") != null and cloud.get_node_or_null("Particles") != null)
	await _wait_seconds(1.1)
	_check("poison cloud poisons the enemy inside", inside.statuses.has("poisoned") and _damage.get(inside.id, 0.0) > 0.0,
			"%s %s" % [inside.statuses, _damage.get(inside.id, 0.0)])
	_check("and not the one outside", not outside.statuses.has("poisoned") and _damage.get(outside.id, 0.0) == 0.0)
	var ref: WeakRef = weakref(cloud)
	cloud = null
	var gone := await _wait_until(func() -> bool: return enemies.clouds.is_empty() and ref.get_ref() == null, 2.0)
	_check("the cloud expires", gone, str(enemies.clouds))

	# The player in a cloud: poisoned, health ticks down, the HUD shows a vignette.
	await _wait_seconds(0.2)
	me.health = me.max_health
	load("res://scripts/weapons/cloud.gd").spawn("poison", me.global_position + Vector3.UP * 0.8, 2.0, 1.0)
	await _wait_seconds(1.2)
	_check("the player in the cloud is poisoned", me.statuses.has("poisoned") and me.health < me.max_health, "%s %.1f" % [me.statuses, me.health])
	var hud = _find_hud(lab)
	_check("the HUD shows the poison vignette", hud != null and hud._vignette.visible and hud._vignette.modulate.g > 0.8)
	me.revive()
	_check("revive clears player statuses", me.statuses.is_empty())
	_clear()
	await _frames(2)


## A fire cloud burns away a clump of shroom voxels, but not the concrete floor under it.
func _fire_cloud() -> void:
	var spot: Vector3 = me.global_position + Vector3(0.0, 0.0, -10.0)
	var base: Vector3i = lab.world.world_to_voxel(spot)
	var from := base + Vector3i(-6, 0, -6)
	var to := base + Vector3i(6, 10, 6)
	lab.world.fill_box(from, to, M.SHROOM_STEM, false)
	lab.world.fill_box(from + Vector3i(0, 6, 0), to, M.SHROOM_CAP, false)
	_check("shroom voxels placed", _shrooms(from, to) == 12 * 12 * 10, str(_shrooms(from, to)))
	var cloud = load("res://scripts/weapons/cloud.gd").spawn("fire", spot + Vector3.UP * 0.2, 2.0, 5.0)
	await _wait_seconds(1.0)
	var partway: int = _shrooms(from, to)
	_check("the fire burns shrooms over time, not all at once", partway > 0 and partway < 12 * 12 * 10, str(partway))
	var burned := await _wait_until(func() -> bool: return _shrooms(from, to) == 0, 5.0)
	_check("the fire cloud burns away the shroom voxels", burned, "%d left" % _shrooms(from, to))
	_check("but not the concrete floor", lab.world.get_voxel(base + Vector3i(0, -1, 0)) == M.CONCRETE)
	_check("fire clouds are fire", cloud != null and cloud.type == "fire")
	_clear()


# --- Helpers -------------------------------------------------------------------------------------

## Horizontal speed (m/s) of an enemy over seconds.
func _speed_of(enemy, seconds: float) -> float:
	var start: Vector3 = enemy.global_position
	await _wait_seconds(seconds)
	var moved: Vector3 = enemy.global_position - start
	return Vector2(moved.x, moved.z).length() / seconds


func _shrooms(from: Vector3i, to: Vector3i) -> int:
	var n := 0
	for y in range(from.y, to.y):
		for z in range(from.z, to.z):
			for x in range(from.x, to.x):
				var id: int = lab.world.get_voxel(Vector3i(x, y, z))
				if id >= M.SHROOM_CAP and id <= M.SHROOM_EYE:
					n += 1
	return n


func _find_hud(node: Node):
	for child in node.get_children():
		if child.get_script() == load("res://scripts/ui/combat_hud.gd"):
			return child
		var found = _find_hud(child)
		if found:
			return found
	return null


## A frozen-in-place enemy (no moving or attacking) at offset (meters) from the player's feet.
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


## One big concrete room, the player spawn near one end facing the far wall (-Z).
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


func _check(label: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", label, "" if ok or detail == "" else detail])
	if not ok:
		_failures += 1
