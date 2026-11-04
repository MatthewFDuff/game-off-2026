extends SceneTree
## Headless checks for glass that shatters as a pane (Glass):
##   godot --headless --path . --script res://tests/glass_test.gd
## Builds a scratch level (one big concrete room) with a 20 x 20 ordinary pane, two 20 x 20
## tempered panes, a spore tank and an 80 x 80 skylight, plays it solo and checks: one basic shot
## clears the whole ordinary pane in one WorldSync batch (after the shot's own carve), leaves a
## one-voxel scatter of shards under it, and bills the pane; a tempered pane cracks on the first
## shot (the whole pane turns GLASS_CRACKED), survives the second (aimed at its lowest corner, so
## the pane's key moves) and shatters on the third; a blast shatters a tempered pane at once; the
## spore tank's glass vents a spore cloud and drains it, billed as the tank; walking on shards
## crunches; the flood fill stops at PANE_MAX, and how long it took is printed.
##
## Game types are left unnamed (see editor_test.gd).

const SCRATCH := "user://glass_test_levels/"
const LEVEL := "glass_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIZE := Vector3i(8, 2, 8)
const FLOOR := 8
const ROOM := [Vector3i(8, FLOOR, 8), Vector3i(248, 60, 248)]
## Panes, [from, to) in voxels: 20 wide, 20 tall, 1 thick, standing on the floor.
const PANE := [Vector3i(40, FLOOR, 60), Vector3i(60, FLOOR + 20, 61)]
const TEMPERED := [Vector3i(90, FLOOR, 60), Vector3i(110, FLOOR + 20, 61)]
const BLASTED := [Vector3i(140, FLOOR, 60), Vector3i(160, FLOOR + 20, 61)]
const TANK := Vector3i(190, FLOOR, 58)
## A horizontal sheet off the west wall, bigger than PANE_MAX.
const SKYLIGHT := [Vector3i(8, 40, 120), Vector3i(88, 41, 200)]
const PLAYER_SPOT := Vector3(128.0, FLOOR, 140.0)

var _failures := 0
var lab
var me
var weapon
var glass


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
	glass = load("res://scripts/world/glass.gd").find()
	lab.items.drop_chance = 0.0
	lab.director.set_process(false)
	lab.director.set_physics_process(false)
	await _frames(10)
	_check("the lab has a Glass node", glass != null and lab.glass == glass)

	await _ordinary()
	await _tempered()
	await _blast()
	await _spore_tank()
	await _crunch()
	await _big_sheet()

	print("glass test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## One basic shot at the middle of the ordinary pane.
func _ordinary() -> void:
	var events := []
	var on_carve := func(_at: Vector3, _n: Vector3, removed: Dictionary) -> void: events.append(["carve", removed.get(M.GLASS, 0)])
	var on_set := func(_p: PackedInt32Array, materials: PackedByteArray, removed: Dictionary) -> void:
		events.append(["set", materials.size(), removed.get(M.GLASS, 0)])
	lab.world_sync.carved.connect(on_carve)
	lab.world_sync.voxels_set.connect(on_set)
	var before: int = lab.play.damage_by_name.get("glass_pane", 0)
	await _shoot(PANE, Vector2i(10, 10))
	lab.world_sync.carved.disconnect(on_carve)
	lab.world_sync.voxels_set.disconnect(on_set)
	_check("one basic shot clears the whole ordinary pane", _count(PANE[0], PANE[1], [M.GLASS]) == 0,
			"%d glass left" % _count(PANE[0], PANE[1], [M.GLASS]))
	var batch := events.filter(func(e: Array) -> bool: return e[0] == "set")
	var sent := 0
	for e: Array in batch:
		sent += e[1]
	_check("the shot's carve comes first, then the pane (and its shards) in WorldSync batches", events.size() >= 2 and events[0][0] == "carve"
			and events[0][1] > 0 and sent >= glass.last_shatter.voxels and glass.last_shatter.voxels + events[0][1] == 400, str(events))
	print("  flood fill of the 20 x 20 pane: %.2f ms (%d voxels)" % [glass.last_fill_msec, glass.last_shatter.voxels])
	_check("the flood fill is quick", glass.last_fill_msec < 10.0, "%.2f ms" % glass.last_fill_msec)
	var area := [PANE[0] - Vector3i(4, 0, 4), Vector3i(PANE[1].x + 4, FLOOR + 1, PANE[1].z + 4)]
	var shards := _count(area[0], area[1], [M.GLASS_SHARDS])
	var columns := (20 + 6) * (1 + 6)
	_check("shards scatter on the floor under it (about 30%)", shards >= columns * 0.15 and shards <= columns * 0.45, "%d of %d" % [shards, columns])
	_check("shards are one voxel thick", _count(area[0] + Vector3i(0, 1, 0), area[1] + Vector3i(0, 1, 0), [M.GLASS_SHARDS]) == 0)
	var billed: int = lab.play.damage_by_name.get("glass_pane", 0) - before
	_check("the payroll is charged for the pane", billed == 400, "$%d" % billed)


## Three shots at a tempered pane: crack, hold, shatter.
func _tempered() -> void:
	var total := 400
	await _shoot(TEMPERED, Vector2i(6, 12))
	var cracked := _count(TEMPERED[0], TEMPERED[1], [M.GLASS_CRACKED])
	var left := _count(TEMPERED[0], TEMPERED[1], [M.GLASS_TEMPERED])
	_check("a tempered pane survives the first shot, cracked all over", left == 0 and cracked > total - 30 and cracked < total,
			"%d cracked, %d tempered" % [cracked, left])
	# The second at the lowest corner: the voxel the pane was keyed by goes with it.
	await _shoot(TEMPERED, Vector2i(0, 0))
	var second := _count(TEMPERED[0], TEMPERED[1], [M.GLASS_CRACKED])
	_check("it survives the second (its lowest voxel shot away)", second > total - 60 and second < cracked
			and lab.world.get_voxel(TEMPERED[0]) == M.AIR, "%d cracked" % second)
	await _shoot(TEMPERED, Vector2i(14, 8))
	_check("the third shatters it", _count(TEMPERED[0], TEMPERED[1], [M.GLASS_CRACKED, M.GLASS_TEMPERED]) == 0,
			"%d left" % _count(TEMPERED[0], TEMPERED[1], [M.GLASS_CRACKED, M.GLASS_TEMPERED]))
	var area := [TEMPERED[0] - Vector3i(4, 0, 4), Vector3i(TEMPERED[1].x + 4, FLOOR + 1, TEMPERED[1].z + 4)]
	_check("and leaves shards", _count(area[0], area[1], [M.GLASS_SHARDS]) > 20)
	_check("no hits are left counted", glass._tempered.is_empty(), str(glass._tempered))


## A blast (explosive-sized carve) at a tempered pane: gone at once.
func _blast() -> void:
	var at: Vector3 = lab.world.voxel_to_world(Vector3i(150, FLOOR + 10, 61))
	lab.world_sync.carve_sphere(at, 1.2, 6, Vector3.BACK)
	await _frames(3)
	_check("a blast shatters a tempered pane in one go", _count(BLASTED[0], BLASTED[1], [M.GLASS_TEMPERED, M.GLASS_CRACKED]) == 0,
			"%d left" % _count(BLASTED[0], BLASTED[1], [M.GLASS_TEMPERED, M.GLASS_CRACKED]))


## The spore tank's glass: a spore cloud, the tank drained, billed as the tank (not a loose pane).
func _spore_tank() -> void:
	var tank_from := TANK
	var tank_to := TANK + Vector3i(4, 10, 4)
	var green := _count(tank_from, tank_to, [M.LIQUID_GREEN])
	var pane_bill: int = lab.play.damage_by_name.get("glass_pane", 0)
	await _shoot([TANK, TANK + Vector3i(4, 10, 4)], Vector2i(2, 8), 4)
	await _frames(3)
	var spore := false
	for cloud in lab.enemies.clouds.values():
		if cloud.type == "spore" and cloud.global_position.distance_to(lab.world.voxel_to_world(TANK + Vector3i(2, 5, 2))) < 1.0:
			spore = true
	_check("the spore tank's glass vents a spore cloud", spore, str(lab.enemies.clouds.size()))
	_check("and drains the tank", green > 0 and _count(tank_from, tank_to, [M.LIQUID_GREEN]) == 0, "%d of %d green left" % [_count(tank_from, tank_to, [M.LIQUID_GREEN]), green])
	_check("its glass is all gone", _count(tank_from, tank_to, [M.GLASS]) == 0)
	_check("billed as the tank, not as a loose pane", lab.play.damage_by_name.get("spore_tank", 0) > 0
			and lab.play.damage_by_name.get("glass_pane", 0) == pane_bill, str(lab.play.damage_by_name))


## Footsteps on shards crunch; on bare floor they don't.
func _crunch() -> void:
	var sounds := []
	me.footstep_played.connect(func(sound: String) -> void: sounds.append(sound))
	var shard := _first(PANE[0] - Vector3i(4, 0, 4), Vector3i(PANE[1].x + 4, FLOOR + 1, PANE[1].z + 4), M.GLASS_SHARDS)
	_check("there's a shard to stand on", shard.x >= 0)
	me.teleport(lab.world.voxel_to_world(shard) + Vector3(0, 0.05, 0))
	await _frames(2)
	me._footstep(1.0)
	_check("walking on shards crunches", sounds == ["glass_crunch"], str(sounds))
	me.teleport(PLAYER_SPOT * lab.world.voxel_size + lab.world.global_position)
	await _frames(2)
	me._footstep(1.0)
	_check("bare floor doesn't", sounds.size() == 1, str(sounds))


## A sheet bigger than PANE_MAX: one hit clears PANE_MAX of it; the fill time is printed.
func _big_sheet() -> void:
	var at: Vector3 = lab.world.voxel_to_world(Vector3i(48, 40, 160))
	var before := _count(SKYLIGHT[0], SKYLIGHT[1], [M.GLASS])
	lab.world_sync.carve_sphere(at, 0.14, 4, Vector3.DOWN)
	await _frames(3)
	var max_pane: int = load("res://scripts/world/glass.gd").PANE_MAX
	print("  flood fill at the cap: %.2f ms (%d voxels)" % [glass.last_fill_msec, glass.last_shatter.voxels])
	_check("a sheet over the cap loses PANE_MAX voxels to one hit", glass.last_shatter.voxels == max_pane and before == 6400,
			"%d of %d" % [glass.last_shatter.voxels, before])


## Fires one basic shot from in front of (+z) a pane at its voxel (along x, up y) on the front face.
func _shoot(pane: Array, spot: Vector2i, depth := 1) -> void:
	var target := Vector3(pane[0].x + spot.x + 0.5, pane[0].y + spot.y + 0.5, pane[0].z + depth)
	var aim_at: Vector3 = lab.world.global_position + target * lab.world.voxel_size
	var feet: Vector3 = lab.world.global_position + Vector3(target.x, FLOOR, target.z + 30) * lab.world.voxel_size
	me.teleport(feet)
	me.velocity = Vector3.ZERO
	await _frames(3)
	weapon.select("basic")
	weapon._cooldown = 0.0
	weapon.fire(aim_at - me.camera.global_position)
	await _frames(4)


## One big concrete room with the panes, the tank and the skylight painted in.
func _make_level() -> void:
	var level := LevelData.new()
	level.name = LEVEL
	level.settings = LevelData.default_settings(SIZE, "rock")
	var world := VoxelWorld.new()
	world.size_in_chunks = SIZE
	world.immediate_remesh_limit = 0
	root.add_child(world)
	world.fill_all(M.CONCRETE)
	world.fill_box(ROOM[0], ROOM[1], M.AIR, false)
	world.fill_box(PANE[0], PANE[1], M.GLASS, false)
	world.fill_box(TEMPERED[0], TEMPERED[1], M.GLASS_TEMPERED, false)
	world.fill_box(BLASTED[0], BLASTED[1], M.GLASS_TEMPERED, false)
	world.fill_box(SKYLIGHT[0], SKYLIGHT[1], M.GLASS, false)
	level.voxels = world.get_data()
	world.free()
	var tank := LevelSchema.new_prop("spore_tank", TANK, 0)
	tank.id = "tank"
	level.objects[tank.id] = tank
	var spawn := LevelSchema.new_marker("spawn", PLAYER_SPOT, 0.0)
	spawn.id = "spawn_1"
	level.objects[spawn.id] = spawn
	_check("level saves", level.save() == OK)


func _count(from: Vector3i, to: Vector3i, ids: Array) -> int:
	var n := 0
	for y in range(from.y, to.y):
		for z in range(from.z, to.z):
			for x in range(from.x, to.x):
				if lab.world.get_voxel(Vector3i(x, y, z)) in ids:
					n += 1
	return n


func _first(from: Vector3i, to: Vector3i, material: int) -> Vector3i:
	for y in range(from.y, to.y):
		for z in range(from.z, to.z):
			for x in range(from.x, to.x):
				if lab.world.get_voxel(Vector3i(x, y, z)) == material:
					return Vector3i(x, y, z)
	return Vector3i(-1, -1, -1)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(label: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", label, "" if ok or detail == "" else detail])
	if not ok:
		_failures += 1
