extends SceneTree
## Headless checks for the generator finale (phase 6):
##   godot --headless --path . --script res://tests/finale_test.gd
## One room with a generator and two spawners (one off). Using the generator starts a short
## finale: spawners turn on and their alive cap doubles, the countdown runs, and at zero
## finale_survived and the "finale_survived" trigger fire, spawner settings are restored and the
## enemies live on. A second finale where the only player dies ends in finale_failed: enemies
## cleared, power back to backup, the generator usable again.
##
## Game types are left unnamed (see editor_test.gd).

const SCRATCH := "user://finale_test_levels/"
const LEVEL := "finale_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIZE := Vector3i(6, 2, 4)
const FLOOR := 8
const ROOM := [Vector3i(8, FLOOR, 8), Vector3i(184, 40, 120)]
const NORTH := 0

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
	var play = lab.play
	var director = lab.director
	var enemies = lab.enemies
	me.max_health = 100000.0
	me.health = 100000.0
	await _frames(10)
	_check("playing on backup power", play.power == "backup" and director.running and not director.finale_active)
	var fired := []
	play.triggered.connect(func(id: String, _peer: int) -> void: fired.append(id))
	var events := []
	director.finale_event.connect(func(kind: String) -> void: events.append(kind))
	var survived := [false]
	director.finale_survived.connect(func() -> void: survived[0] = true)

	# Finale 1: the generator starts it (finale_seconds = 4).
	play._use("gen", 1)
	await _frames(3)
	_check("generator starts the finale", director.state == "finale" and director.finale_active and play.power == "restored")
	_check("started event", events == ["started"], str(events))
	_check("every spawner active", director.spawners.a.active and director.spawners.b.active)
	var most := [0]
	await _wait_until(func() -> bool:
		most[0] = maxi(most[0], director.spawners.a.alive.size())
		return false, 1.5)
	_check("alive cap doubles (2 -> 4)", most[0] == 4, str(most[0]))
	var left1: float = director.finale_left
	_check("countdown runs", left1 < 3.5 and left1 > 0.0, str(left1))
	await _wait_until(func() -> bool: return survived[0], 6.0)
	_check("finale_survived fires", survived[0] and "finale_survived" in fired and events.back() == "survived", str(events))
	_check("finale over", not director.finale_active and director.state == "calm" and director.finale_left == 0.0)
	_check("spawners restored", not director.spawners.b.active and director.spawners.a.active
			and director.spawners.a.alive_mult == 1.0 and director.spawners.a.rate_mult == 1.0)
	var alive: int = enemies.alive_count()
	await _frames(5)
	_check("enemies live on", alive > 0 and enemies.alive_count() >= alive - 1, str(alive))
	_check("power stays restored, generator spent", play.power == "restored" and play.state_of("gen").used)

	# Finale 2: the only player dies.
	play.set_power("backup")
	play.reset_prop("gen")
	fired.clear()
	events.clear()
	var failed := [false]
	director.finale_failed.connect(func() -> void: failed[0] = true)
	director.finale(30.0)
	await _frames(3)
	_check("second finale running", director.finale_active and play.power == "restored")
	me.take_damage(1000000.0, me.global_position)
	await _wait_until(func() -> bool: return failed[0], 3.0)
	_check("wipe fails the finale", failed[0] and "finale_failed" in fired and events.back() == "failed", str(events))
	_check("enemies cleared", enemies.enemies.is_empty() and director.state == "calm" and not director.finale_active)
	_check("power back to backup", play.power == "backup")
	_check("generator usable again", not play.state_of("gen").used)
	_check("spawners restored after fail", not director.spawners.b.active and director.spawners.a.alive.is_empty())

	print("finale test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## One room, a spawn, a generator (4 s finale), spawner "a" (on) and "b" (off), both fast with max 2.
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

	var gen := LevelSchema.new_prop("generator", Vector3i(100, FLOOR, 108), NORTH)
	gen.id = "gen"
	gen.finale_seconds = 4.0
	var spawn := LevelSchema.new_marker("spawn", Vector3(96.0, FLOOR, 64.0), 0.0)
	spawn.id = "spawn_1"
	level.objects["gen"] = gen
	level.objects["spawn_1"] = spawn
	for entry in [["a", true, Vector3(30.0, FLOOR, 30.0)], ["b", false, Vector3(150.0, FLOOR, 30.0)]]:
		var spawner := LevelSchema.new_marker("horde", entry[2])
		spawner.id = entry[0]
		spawner.rate = 600.0
		spawner.max_alive = 2
		spawner.active = entry[1]
		level.objects[spawner.id] = spawner
	level.settings.start_power = "backup"
	_check("level saves", level.save() == OK)


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
