extends SceneTree
## Headless checks for the shroom shooter, ammo, projectiles and pickups (phase 2):
##   godot --headless --path . --script res://tests/weapon_test.gd
## Builds a scratch level (one concrete box room with two item spots), plays it solo, and fires
## every ammo type at a frozen enemy, checking the damage lands (projectiles are stepped until they
## hit). Then: ricochet bounces off a wall into an enemy and pierces two in a row, explosive carves
## the wall through WorldSync, homing curves into an enemy off to the side that a straight shot
## misses, Shift (cycle_ammo) skips types with no ammo, pickups give ammo / flasks / keycards and
## the medkit heals, enemies drop ammo, and the item spots' pickups appear at play start and are
## cleared on the way back to edit.
##
## Phase 3: melee hits an enemy in front and not one behind and chips a glass voxel (not concrete),
## a thrown flask uses one and shatters into its cloud, and Q (cycle_flask) skips empty types.
##
## Game types are left unnamed (see editor_test.gd): naming them would compile those scripts before
## the autoloads they use are registered.

const SCRATCH := "user://weapon_test_levels/"
const LEVEL := "weapon_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIZE := Vector3i(6, 2, 6)
const FLOOR := 8
## The room, in voxels [from, to).
const ROOM := [Vector3i(8, FLOOR, 8), Vector3i(152, 48, 152)]
const PLAYER_SPOT := Vector3(80.0, FLOOR, 130.0)
const ITEM_SPOTS := {spot_a = [Vector3(20.0, FLOOR, 20.0), "ammo_homing"], spot_b = [Vector3(140.0, FLOOR, 20.0), "flask_fire"]}

var _failures := 0
var lab
var me
var weapon
var enemies
var items
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
	weapon = me.weapon
	enemies = lab.enemies
	items = lab.items
	await _frames(10)
	_check("player has the weapon and an inventory", weapon != null and me.inventory != null and weapon.current == "basic")
	_check("view model built from the .vox, with glow voxels", weapon._model != null and weapon._model.get_node_or_null("Glow") != null)
	_check("item spots spawn pickups at play start", _items() == ["ammo_homing", "flask_fire"], str(_items()))
	items.drop_chance = 0.0
	enemies.enemy_damaged.connect(func(enemy, amount: float, _zone: String) -> void:
		_damage[enemy.id] = _damage.get(enemy.id, 0.0) + amount)

	await _each_ammo_type()
	await _ricochet()
	await _explosive_carves()
	await _homing()
	await _cycling()
	await _pickups()
	await _melee()
	await _flasks()

	lab.request_mode("edit")
	await _frames(3)
	_check("back to edit clears the pickups", _all_queued(), str(items.pickups.keys()))
	_check("back to edit clears the clouds", enemies.clouds.is_empty())

	print("weapon test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Every ammo type at an enemy straight ahead.
func _each_ammo_type() -> void:
	# Offsets from the player; the explosive one off to the side, so its crater doesn't get in the
	# way of the later tests.
	var spots := {basic = Vector3(0, 0, -6), shotgun = Vector3(0, 0, -3.5), flame = Vector3(0, 0, -2.5),
			explosive = Vector3(4, 0, -6), ricochet = Vector3(0, 0, -6), homing = Vector3(0, 0, -6), poison = Vector3(0, 0, -5)}
	for ammo_name: String in spots:
		await _no_projectiles()
		var enemy = _target(spots[ammo_name])
		_arm(ammo_name)
		var before: int = me.inventory.count(ammo_name)
		var aim: Vector3 = enemy.get_center() - me.camera.global_position
		var landed := false
		if ammo_name == "flame":
			landed = await _wait_until(func() -> bool:
				weapon.fire(aim)
				return _damage.get(enemy.id, 0.0) >= 12.0, 3.0)
		else:
			_check("%s fires" % ammo_name, weapon.fire(aim))
			landed = await _wait_until(func() -> bool: return _damage.get(enemy.id, 0.0) > 0.0, 3.0)
			await _no_projectiles()
		_check("%s damages the enemy" % ammo_name, landed, "damage %s" % _damage.get(enemy.id, 0.0))
		if ammo_name == "basic":
			_check("basic is infinite", before == -1 and me.inventory.count("basic") == -1)
		else:
			_check("%s uses ammo" % ammo_name, me.inventory.count(ammo_name) < before, "%d -> %d" % [before, me.inventory.count(ammo_name)])
		if ammo_name == "shotgun":
			_check("shotgun pellets add up", _damage.get(enemy.id, 0.0) >= 14.0, str(_damage.get(enemy.id, 0.0)))
		if ammo_name == "flame" and is_instance_valid(enemy):
			_check("flame sets it burning", enemy.statuses.has("burning"), str(enemy.statuses))
		if ammo_name == "poison" and is_instance_valid(enemy):
			_check("poison leaves a poison cloud that poisons it", enemy.statuses.has("poisoned") and _clouds("poison") == 1,
					"%s, %d clouds" % [enemy.statuses, enemies.clouds.size()])
		_clear_enemies()
		await _frames(2)


## Ricochet: a shot at the wall at the mirror image of an enemy bounces into it; a straight shot
## pierces two enemies in a row, damaging each once.
func _ricochet() -> void:
	await _no_projectiles()
	var feet: Vector3 = me.global_position
	var wall_x: float = lab.view.to_world(Vector3(ROOM[0])).x
	var enemy = _target(Vector3(wall_x + 3.2 - feet.x, 0.0, -6.0))
	var center: Vector3 = enemy.get_center()
	var mirror := Vector3(2.0 * wall_x - center.x, center.y, center.z)
	_arm("ricochet")
	var shots := []
	var watch := func(shot) -> void: shots.append(shot)
	weapon.projectile_spawned.connect(watch)
	weapon.fire(mirror - me.camera.global_position)
	var hit_after_bounce := [false]
	var landed := await _wait_until(func() -> bool:
		if _damage.get(enemy.id, 0.0) > 0.0 and not shots.is_empty():
			hit_after_bounce[0] = not is_instance_valid(shots[0]) or shots[0].bounces >= 1
			return true
		return false, 3.0)
	_check("ricochet bounces off the wall into the enemy", landed and hit_after_bounce[0], "damage %s" % _damage.get(enemy.id, 0.0))
	_clear_enemies()
	await _frames(2)

	await _no_projectiles()
	var near = _target(Vector3(0.0, 0.0, -4.5))
	var far = _target(Vector3(0.0, 0.0, -6.0))
	weapon._cooldown = 0.0
	weapon.fire(far.global_position + Vector3.UP * 0.5 - me.camera.global_position)
	var both := await _wait_until(func() -> bool: return _damage.get(near.id, 0.0) > 0.0 and _damage.get(far.id, 0.0) > 0.0, 3.0)
	await _wait_seconds(0.5)
	_check("ricochet pierces enemies, damaging each once", both and _damage.get(near.id) == 18.0 and _damage.get(far.id) == 18.0,
			"near %s far %s" % [_damage.get(near.id), _damage.get(far.id)])
	weapon.projectile_spawned.disconnect(watch)
	_clear_enemies()
	await _frames(2)


## Explosive at the far wall: a crater through WorldSync.
func _explosive_carves() -> void:
	_arm("explosive")
	var eye: Vector3 = me.camera.global_position
	var aim := Vector3(0.0, -0.05, -1.0).normalized()
	var wall: Dictionary = lab.world.raycast(eye, aim, 40.0)
	var carves := []
	var on_carve := func(at: Vector3, _normal: Vector3, removed: Dictionary) -> void: carves.append([at, removed])
	lab.world_sync.carved.connect(on_carve)
	weapon.fire(aim)
	var carved := await _wait_until(func() -> bool: return not carves.is_empty(), 3.0)
	lab.world_sync.carved.disconnect(on_carve)
	_check("explosive carves the wall through WorldSync", carved and wall.hit and lab.world.get_voxel(wall.voxel) == M.AIR,
			"%d carves, wall voxel %s" % [carves.size(), lab.world.get_voxel(wall.voxel) if wall.hit else -1])
	if carved:
		var total := 0
		for count: int in carves[0][1].values():
			total += count
		_check("a blast-sized crater", total > 500, "%d voxels" % total)


## Homing: an enemy 15 degrees off to the side that a straight shot would miss.
func _homing() -> void:
	await _no_projectiles()
	var enemy = _target(Vector3(2.4, 0.0, -9.0))
	_arm("homing")
	var aim := Vector3(0.0, -0.12, -1.0).normalized()
	var straight: Dictionary = load("res://scripts/combat/combat.gd").ray_hit(lab.world, me.camera.global_position, aim, 40.0)
	_check("a straight shot misses the homing target", straight.enemy != enemy)
	var shots := []
	var watch := func(shot) -> void: shots.append(shot)
	weapon.projectile_spawned.connect(watch)
	weapon.fire(aim)
	var start_heading: Vector3 = shots[0].velocity.normalized() if not shots.is_empty() else Vector3.ZERO
	var turned := [0.0]
	var landed := await _wait_until(func() -> bool:
		if not shots.is_empty() and is_instance_valid(shots[0]):
			turned[0] = rad_to_deg(start_heading.angle_to(shots[0].velocity))
		return _damage.get(enemy.id, 0.0) > 0.0, 3.0)
	weapon.projectile_spawned.disconnect(watch)
	_check("homing curves into the off-axis enemy", landed and turned[0] > 5.0, "turned %.1f deg, damage %s" % [turned[0], _damage.get(enemy.id, 0.0)])
	_clear_enemies()
	await _frames(2)


## Shift cycles only through types with ammo; number keys pick by slot.
func _cycling() -> void:
	me.inventory.clear()
	me.inventory.add("ammo_shotgun")
	me.inventory.add("ammo_explosive")
	weapon.select("basic")
	var seen: Array[String] = []
	for i in 3:
		await _press("cycle_ammo")
		seen.append(weapon.current)
	_check("Shift skips types with no ammo", seen == ["shotgun", "explosive", "basic"], str(seen))
	await _press("ammo_3")
	_check("a slot with no ammo does nothing", weapon.current == "basic", weapon.current)
	await _press("ammo_2")
	_check("number keys pick by slot", weapon.current == "shotgun", weapon.current)
	_check("next type for the HUD", weapon.next_ammo() == "explosive", weapon.next_ammo())
	me.inventory.ammo["shotgun"] = 1
	weapon._cooldown = 0.0
	weapon.fire(Vector3.FORWARD)
	_check("running out goes back to basic", weapon.current == "basic" and me.inventory.count("shotgun") == 0, weapon.current)


## Pickups: walking into them gives the item; the medkit heals; enemies drop ammo.
func _pickups() -> void:
	me.inventory.clear()
	var here: Vector3 = me.global_position + Vector3(0.0, 0.35, -0.3)
	for item in ["ammo_shotgun", "flask_poison", "keycard_red"]:
		items.spawn(item, here)
	var taken := await _wait_until(func() -> bool: return _items().filter(func(i: String) -> bool: return i in ["ammo_shotgun", "flask_poison", "keycard_red"]).is_empty(), 2.0)
	_check("walking into pickups takes them", taken, str(_items()))
	_check("ammo pickup adds ammo", me.inventory.count("shotgun") == 12, str(me.inventory.ammo))
	_check("flask and keycard pickups go in the inventory", me.inventory.flasks.get("poison", 0) == 1 and me.inventory.has_keycard("red"),
			"%s %s" % [me.inventory.flasks, me.inventory.keycards])
	_check("far pickups stay", _items() == ["ammo_homing", "flask_fire"], str(_items()))
	me.health = 40.0
	me._since_damage = 0.0
	items.spawn("medkit", here)
	await _wait_until(func() -> bool: return not "medkit" in _items(), 2.0)
	_check("medkit heals 50", absf(me.health - 90.0) < 0.5, str(me.health))

	items.drop_chance = 1.0
	var enemy = _target(Vector3(4.0, 0.0, -8.0))
	enemy.health = 10.0
	var count: int = items.pickups.size()
	var before := _items()
	enemies.request_hit(enemy.id, 1000.0, enemy.get_center(), "rifle")
	# The new pickup, whatever type it rolled (homing ammo is already lying around from earlier).
	var dropped := _items()
	for item in before:
		dropped.erase(item)
	_check("dead enemies drop ammo", items.pickups.size() == count + 1 and dropped.size() == 1 and dropped[0].begins_with("ammo_"), str(_items()))
	items.drop_chance = 0.0


## Melee: the box in front hits, behind doesn't; the swing chips glass but not concrete.
func _melee() -> void:
	_clear_enemies()
	await _frames(2)
	var front = _target(Vector3(0.0, 0.0, -1.1))
	var behind = _target(Vector3(0.0, 0.0, 1.1))
	weapon._melee_cooldown = 0.0
	var swings := []
	var on_melee := func(hits: int) -> void: swings.append(hits)
	weapon.meleed.connect(on_melee)
	await _press("melee")
	_check("MMB swings", weapon._swing > 0.0 or not swings.is_empty())
	var landed := await _wait_until(func() -> bool: return not swings.is_empty(), 1.0)
	_check("melee hits the enemy in front", landed and _damage.get(front.id, 0.0) == 35.0, "damage %s" % _damage.get(front.id, 0.0))
	_check("melee misses the enemy behind", _damage.get(behind.id, 0.0) == 0.0, "damage %s" % _damage.get(behind.id, 0.0))
	_check("melee has a cooldown", not weapon.melee())
	_clear_enemies()
	await _frames(2)

	# A pane of glass across the view at arm's length, and a concrete one further along.
	var eye: Vector3 = me.camera.global_position
	var aim: Vector3 = -me.camera.global_basis.z
	var glass: Vector3i = lab.world.world_to_voxel(eye + aim * 1.0)
	lab.world.fill_box(glass - Vector3i(4, 4, 0), glass + Vector3i(5, 5, 1), M.GLASS, false)
	await _wait_seconds(0.7)
	_check("glass placed", lab.world.get_voxel(glass) == M.GLASS)
	weapon.melee()
	await _wait_until(func() -> bool: return lab.world.get_voxel(glass) != M.GLASS, 1.0)
	_check("melee breaks glass", lab.world.get_voxel(glass) == M.AIR, str(lab.world.get_voxel(glass)))
	lab.world.fill_box(glass - Vector3i(4, 4, 0), glass + Vector3i(5, 5, 1), M.CONCRETE, false)
	await _wait_seconds(0.7)
	weapon.melee()
	await _wait_seconds(0.3)
	_check("melee doesn't break concrete", lab.world.get_voxel(glass) == M.CONCRETE, str(lab.world.get_voxel(glass)))
	lab.world.fill_box(glass - Vector3i(4, 4, 0), glass + Vector3i(5, 5, 1), M.AIR, false)
	weapon.meleed.disconnect(on_melee)


## Flasks: Q cycles the carried types, RMB throws one, which breaks into its cloud.
func _flasks() -> void:
	me.inventory.clear()
	await _frames(2)
	_check("no flasks, none selected", weapon.flask == "", weapon.flask)
	_check("nothing to throw", not weapon.throw_flask())
	me.inventory.add("flask_fire")
	me.inventory.add("flask_freeze", 2)
	await _frames(1)
	_check("a picked-up flask is selected", weapon.flask == "fire", weapon.flask)
	var seen: Array[String] = []
	for i in 3:
		await _press("cycle_flask")
		seen.append(weapon.flask)
	_check("Q skips flask types there are none of", seen == ["freeze", "fire", "freeze"], str(seen))

	await _press("cycle_flask") # Back to fire.
	var shots := []
	var watch := func(shot) -> void: shots.append(shot)
	weapon.projectile_spawned.connect(watch)
	weapon._flask_cooldown = 0.0
	# At the floor a few meters ahead (the flask arcs, so aim low).
	var feet: Vector3 = me.global_position
	var aim: Vector3 = (feet + Vector3(0.0, 0.0, -5.0)) - me.camera.global_position
	_check("RMB throws the selected flask", weapon.throw_flask(aim))
	weapon.projectile_spawned.disconnect(watch)
	_check("throw cooldown", not weapon.throw_flask(aim))
	_check("throwing uses one flask", me.inventory.flask_count("fire") == 0, str(me.inventory.flasks))
	_check("the flask flies as a projectile with its model", shots.size() == 1 and shots[0].ammo.name == "flask_fire" and shots[0]._model != null, str(shots))
	var cloud := await _wait_until(func() -> bool: return _clouds("fire") == 1, 4.0)
	_check("the flask shatters into a fire cloud", cloud, "%d clouds" % enemies.clouds.size())
	_check("out of fire flasks, freeze is selected", weapon.flask == "freeze", weapon.flask)


## Clouds of a type that are still up.
func _clouds(type: String) -> int:
	var n := 0
	for cloud in enemies.clouds.values():
		if cloud.type == type and not cloud.is_queued_for_deletion():
			n += 1
	return n


# --- Helpers -------------------------------------------------------------------------------------

## A frozen enemy at offset (meters) from the player's feet, on the floor.
func _target(offset: Vector3):
	var enemy = enemies.spawn("basic", me.global_position + offset, 0.0)
	enemy.speed = 0.0
	enemy.attack_range = 0.0
	enemy.damage = 0.0
	enemy.knockback_scale = 0.0
	enemy.max_health = 10000.0
	enemy.health = 10000.0
	return enemy


## Removes every enemy and cloud (so a lingering cloud doesn't add to the next test's damage).
func _clear_enemies() -> void:
	for id: int in enemies.enemies.keys():
		enemies.despawn(id)
	for cloud in enemies.clouds.values():
		cloud.queue_free()
	enemies.clouds.clear()


## Loads an ammo type with plenty of ammo and no cooldown.
func _arm(ammo_name: String) -> void:
	if ammo_name != "basic":
		me.inventory.add("ammo_" + ammo_name, 50)
	weapon.select(ammo_name)
	weapon._cooldown = 0.0


## Waits for every projectile in flight to land, so none hits the next test's enemy.
func _no_projectiles() -> void:
	await _wait_until(func() -> bool: return weapon._projectiles.is_empty(), 6.0)


func _press(action: String) -> void:
	Input.action_press(action)
	await process_frame
	await process_frame
	Input.action_release(action)
	await process_frame


func _items() -> Array[String]:
	var out: Array[String] = []
	for pickup in items.pickups.values():
		out.append(pickup.item)
	out.sort()
	return out


func _all_queued() -> bool:
	for child in items.get_children():
		if not child.is_queued_for_deletion():
			return false
	return items.pickups.is_empty()


## One concrete room, the player spawn near one end facing the far wall (-Z), two item spots far
## from it.
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
	for id: String in ITEM_SPOTS:
		var spot := LevelSchema.new_marker("item", ITEM_SPOTS[id][0])
		spot.id = id
		spot.item = ITEM_SPOTS[id][1]
		level.objects[id] = spot
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
