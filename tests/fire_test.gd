extends SceneTree
## Headless checks for spreading fire (Fire):
##   godot --headless --path . --script res://tests/fire_test.gd
## Builds a scratch level (one big concrete room), plays it solo, and checks: a lit wooden wall
## catches from one corner and spreads (more up than down), the concrete under it never burns, it
## burns out to air and char; a wooden post burning through drops the concrete slab it held; an
## enemy standing in fire burns, and a burning enemy lights the wooden floor it walks on; water
## puts out fire next to it and a freeze cloud puts out fire around it; a green sample next to fire
## boils into a poison cloud, which goes up in a fireball; a big wooden floor burning stays under
## MAX_BURNING and the host's frame time stays reasonable; leaving play forgets every fire.
##
## Game types are left unnamed (see editor_test.gd): naming them would compile those scripts before
## the autoloads they use are registered.

const SCRATCH := "user://fire_test_levels/"
const LEVEL := "fire_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIZE := Vector3i(8, 2, 8)
const FLOOR := 8
## The room, in voxels [from, to).
const ROOM := [Vector3i(8, FLOOR, 8), Vector3i(248, 60, 248)]
const PLAYER_SPOT := Vector3(128.0, FLOOR, 240.0)

var _failures := 0
var lab
var me
var enemies
var fire


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
	fire = lab.fire
	lab.items.drop_chance = 0.0
	lab.director.set_process(false)
	lab.director.set_physics_process(false)
	await _frames(10)
	_check("the lab has a fire", fire != null and fire == load("res://scripts/world/fire.gd").find())

	await _wall()
	await _collapse()
	await _heat()
	await _douse()
	await _boil()
	await _big_fire()
	await _leave_play()

	print("fire test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## A wooden wall lit at one bottom corner.
func _wall() -> void:
	var from := Vector3i(40, FLOOR, 40)
	var to := from + Vector3i(30, 20, 2)
	lab.world.fill_box(from, to, M.WOOD, false)
	var total := 30 * 20 * 2
	var corner: Vector3 = lab.world.voxel_to_world(from)
	fire.ignite(corner, 0.15, 5)
	await _wait_until(func() -> bool: return not fire.burning.is_empty(), 1.0)
	_check("lighting the corner sets a few voxels burning", fire.burning.size() > 0 and fire.burning.size() <= 5, str(fire.burning.size()))
	_check("they're embers in the world", _count(from, to, [M.EMBER, M.EMBER_DEEP]) == fire.burning.size())
	await _wait_seconds(4.0)
	var reach := Vector3i.ZERO
	for p: Vector3i in fire.burning.values():
		reach = reach.max(p - from)
	_check("the fire spreads across the wall", fire.burning.size() > 20, str(fire.burning.size()))
	_check("up faster than along", reach.y >= 4 and reach.y >= reach.x * 0.6, str(reach))
	_check("the concrete floor doesn't burn", _count(from - Vector3i(0, 1, 0), Vector3i(to.x, from.y, to.z), [M.CONCRETE]) == 30 * 2)
	var gone := await _wait_until(func() -> bool: return _count(from, to, [M.WOOD]) == 0 and fire.burning.is_empty(), 60.0)
	var chars := _count(from, to, [M.CHAR])
	_check("the wall burns out", gone, "%d wood, %d burning" % [_count(from, to, [M.WOOD]), fire.burning.size()])
	_check("leaving char and air", chars > 0 and chars < total * 0.6, str(chars))
	_check("nothing's still burning", fire.cells.is_empty() and fire._fuel.is_empty())
	lab.world.fill_box(from, to, M.AIR, false)


## A concrete slab on one wooden post: the post burns through and the slab falls.
func _collapse() -> void:
	var post := Vector3i(100, FLOOR, 40)
	lab.world.fill_box(post, post + Vector3i(2, 16, 2), M.WOOD, false)
	var slab := post + Vector3i(-4, 16, -4)
	lab.world.fill_box(slab, slab + Vector3i(10, 2, 10), M.CONCRETE, false)
	var fragments := []
	lab.world.fragments_detached.connect(func(list: Array) -> void: fragments.append_array(list))
	fire.ignite(lab.world.voxel_to_world(post + Vector3i(0, 4, 0)), 0.3, 40, false)
	var fell := await _wait_until(func() -> bool: return _count(slab, slab + Vector3i(10, 2, 10), [M.CONCRETE]) == 0, 30.0)
	_check("burning through the post drops the slab", fell, "%d concrete left" % _count(slab, slab + Vector3i(10, 2, 10), [M.CONCRETE]))
	var concrete := 0
	for fragment: Dictionary in fragments:
		concrete += fragment.materials.get(M.CONCRETE, 0)
	_check("as a falling piece", concrete == 200, str(concrete))
	await _wait_until(func() -> bool: return fire.burning.is_empty(), 20.0)
	lab.world.fill_box(post + Vector3i(-4, 0, -4), post + Vector3i(6, 20, 6), M.AIR, false)


## Enemies in fire burn; a burning enemy lights the wooden floor it stands on.
func _heat() -> void:
	var patch := Vector3i(40, FLOOR - 1, 100)
	lab.world.fill_box(patch, patch + Vector3i(20, 1, 20), M.WOOD, false)
	var enemy = _target(lab.world.voxel_to_world(patch + Vector3i(10, 1, 10)) - Vector3(0, 0.05, 0))
	await _frames(5)
	fire.ignite(lab.world.voxel_to_world(patch + Vector3i(10, 0, 10)), 0.25, 20)
	var burned := await _wait_until(func() -> bool: return enemy.has_status("burning"), 3.0)
	_check("an enemy standing in fire burns", burned)
	enemies.despawn(enemy.id)
	await _wait_until(func() -> bool: return fire.burning.is_empty(), 40.0)
	# A fresh floor, nothing alight, and a burning enemy on it.
	lab.world.fill_box(patch, patch + Vector3i(20, 1, 20), M.WOOD, false)
	var torch = _target(lab.world.voxel_to_world(patch + Vector3i(10, 1, 10)) - Vector3(0, 0.05, 0))
	await _frames(5)
	enemies.request_status(torch.id, "burning", 6.0)
	var lit := await _wait_until(func() -> bool: return not fire.burning.is_empty(), 4.0)
	_check("a burning enemy sets the floor alight", lit)
	enemies.despawn(torch.id)
	await _wait_until(func() -> bool: return fire.burning.is_empty(), 40.0)
	lab.world.fill_box(patch, patch + Vector3i(20, 1, 20), M.CONCRETE, false)


## Water next to burning wood puts it out; a freeze cloud puts out everything around it.
func _douse() -> void:
	var strip := Vector3i(140, FLOOR, 100)
	lab.world.fill_box(strip, strip + Vector3i(10, 1, 1), M.WOOD, false)
	lab.world.fill_box(strip + Vector3i(0, 0, 1), strip + Vector3i(10, 1, 2), M.WATER, false)
	fire.ignite(lab.world.voxel_to_world(strip + Vector3i(5, 0, 0)), 0.15, 3)
	await _wait_seconds(0.8)
	_check("water next to fire puts it out", fire.burning.is_empty() and _count(strip, strip + Vector3i(10, 1, 1), [M.CHAR]) > 0,
			"%d burning" % fire.burning.size())
	lab.world.fill_box(strip, strip + Vector3i(10, 1, 2), M.AIR, false)

	var block := Vector3i(140, FLOOR, 140)
	lab.world.fill_box(block, block + Vector3i(10, 10, 10), M.WOOD, false)
	fire.ignite(lab.world.voxel_to_world(block + Vector3i(5, 5, 5)), 1.0, 400, false)
	await _wait_seconds(0.5)
	var before: int = fire.burning.size()
	enemies.request_cloud("freeze", lab.world.voxel_to_world(block + Vector3i(5, 5, 5)), 2.0)
	await _wait_seconds(0.5)
	_check("a freeze cloud puts out the fire around it", before > 100 and fire.burning.is_empty(), "%d -> %d" % [before, fire.burning.size()])
	_check("leaving char", _count(block, block + Vector3i(10, 10, 10), [M.CHAR]) >= before)
	_clear_clouds()
	lab.world.fill_box(block, block + Vector3i(10, 10, 10), M.AIR, false)


## A green sample beside burning wood boils into poison, and the poison catches.
func _boil() -> void:
	var bench := Vector3i(180, FLOOR, 40)
	lab.world.fill_box(bench, bench + Vector3i(6, 4, 2), M.WOOD, false)
	lab.world.fill_box(bench + Vector3i(0, 4, 0), bench + Vector3i(6, 6, 2), M.LIQUID_GREEN, false)
	var spawned := []
	var on_cloud := func(cloud) -> void: spawned.append(cloud.type)
	enemies.cloud_spawned.connect(on_cloud)
	fire.ignite(lab.world.voxel_to_world(bench + Vector3i(3, 3, 0)), 0.3, 40, false)
	var boiled := await _wait_until(func() -> bool: return "poison" in spawned, 10.0)
	_check("a sample next to fire boils into its cloud", boiled, str(spawned))
	var boom := await _wait_until(func() -> bool:
		for cloud in enemies.clouds.values():
			if cloud.type == "poison":
				return false
		return spawned.count("fire") > 0, 4.0)
	_check("and the poison goes up in a fireball", boom, str(spawned))
	enemies.cloud_spawned.disconnect(on_cloud)
	await _wait_until(func() -> bool: return fire.burning.is_empty() and enemies.clouds.is_empty(), 40.0)
	_clear_clouds()
	lab.world.fill_box(bench, bench + Vector3i(6, 6, 2), M.AIR, false)


## A big wooden floor: stays under the cap and the frames stay quick.
func _big_fire() -> void:
	var from := Vector3i(20, FLOOR - 1, 20)
	var to := Vector3i(236, FLOOR, 200)
	lab.world.fill_box(from, to, M.WOOD, false)
	lab.world.fill_box(from + Vector3i(0, 1, 0), Vector3i(236, FLOOR + 3, 200), M.CLOTH, false) # A carpet that goes up fast.
	await _frames(10)
	for x in range(40, 220, 30):
		for z in range(40, 190, 30):
			fire.ignite(lab.world.voxel_to_world(Vector3i(x, FLOOR + 1, z)), 0.3, 40)
	var most := 0
	var slowest := 0
	var total := 0
	var frames := 0
	var deadline := Time.get_ticks_msec() + 8000
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		var now := Time.get_ticks_usec()
		if frames > 0:
			slowest = maxi(slowest, now - last)
			total += now - last
		last = now
		frames += 1
		most = maxi(most, fire.burning.size())
	var average := total / maxi(frames - 1, 1)
	print("  big fire: %d burning at most, %d frames, average %.1f ms, slowest %.1f ms" % [most, frames, average / 1000.0, slowest / 1000.0])
	_check("a big fire stays under the cap", most > 1000 and most <= fire.MAX_BURNING, str(most))
	_check("and the host keeps up (50+ physics frames a second)", frames >= 400, "%d frames in 8 s" % frames)


## Leaving play forgets every fire.
func _leave_play() -> void:
	_check("still burning before leaving", not fire.burning.is_empty())
	lab.request_mode("edit")
	await _wait_until(func() -> bool: return lab.mode == "edit", 5.0)
	await _frames(5)
	_check("leaving play forgets every fire", fire.burning.is_empty() and fire.cells.is_empty() and fire._fuel.is_empty())


# --- Helpers -------------------------------------------------------------------------------------

func _count(from: Vector3i, to: Vector3i, ids: Array) -> int:
	var n := 0
	for y in range(from.y, to.y):
		for z in range(from.z, to.z):
			for x in range(from.x, to.x):
				if lab.world.get_voxel(Vector3i(x, y, z)) in ids:
					n += 1
	return n


func _target(feet: Vector3):
	var enemy = enemies.spawn("basic", feet, 0.0)
	enemy.speed = 0.0
	enemy.attack_range = 0.0
	enemy.damage = 0.0
	enemy.knockback_scale = 0.0
	enemy.max_health = 10000.0
	enemy.health = 10000.0
	return enemy


func _clear_clouds() -> void:
	for cloud in enemies.clouds.values():
		cloud.queue_free()
	enemies.clouds.clear()


## One big concrete room, the player spawn at one end.
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
