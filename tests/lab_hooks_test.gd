extends SceneTree
## Headless checks for the laboratory's level hooks:
##   godot --headless --path . --script res://tests/lab_hooks_test.gd
## Two concrete rooms joined by a gap at one end. Checks trigger `actions` (power, lock / unlock,
## open, on), a "finale_survived" marker's actions running when the finale ends, a boss spawner's
## `on_dead` trigger, the checkpoint vat (reached by walking, used on respawn), hordes ranking
## spawners by walking distance rather than straight-line, and player-count scaling of spawners.
##
## Game types are left unnamed (see editor_test.gd).

const SCRATCH := "user://lab_hooks_test_levels/"
const LEVEL := "lab_hooks_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIZE := Vector3i(6, 2, 4)
const FLOOR := 8
## Room 1 and room 2, with a 5-voxel concrete wall between them open only at z 100..120.
const ROOM1 := [Vector3i(8, FLOOR, 8), Vector3i(100, 40, 120)]
const ROOM2 := [Vector3i(105, FLOOR, 8), Vector3i(184, 40, 120)]
const GAP := [Vector3i(100, FLOOR, 100), Vector3i(105, 40, 120)]
const NORTH := 0

var _failures := 0
var _lab


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LevelData.save_dir_override = SCRATCH
	_make_level()
	root.get_node("Net").start_solo(LEVEL, "play")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	_lab = current_scene
	var me = _lab.local_player()
	var play = _lab.play
	var director = _lab.director
	var enemies = _lab.enemies
	me.max_health = 100000.0
	me.health = 100000.0
	await _frames(10)
	_check("playing on facility power", _lab.mode == "play" and play.active and play.power == "facility" and director.running)
	var fired := []
	play.triggered.connect(func(id: String, _peer: int) -> void: fired.append(id))

	# Player-count scaling: one player on data tuned for two.
	_check("player factor for one player", is_equal_approx(director.player_factor(), 0.8), str(director.player_factor()))
	_check("boss cap stays 1, a cap of 4 becomes 3", director.alive_cap(director.spawners.boss) == 1
			and director.alive_cap(director.spawners.a) == 3)

	# Walking distance: spawner a is 2.5 m away through the wall but 20 m by path; b is 4 m away in
	# the open. Straight-line would pick a first; the path ranking picks b.
	me.teleport(_at(Vector3(90, FLOOR, 20)))
	await _frames(3)
	var order: Array = director._spawners_by_distance()
	var straight_a: float = enemies.nearest_player_distance(_at(Vector3(115, FLOOR, 20)))
	var straight_b: float = enemies.nearest_player_distance(_at(Vector3(50, FLOOR, 20)))
	_check("straight-line would favor the spawner through the wall", straight_a < straight_b, "%.1f / %.1f" % [straight_a, straight_b])
	_check("hordes rank by walking distance", order.size() == 3 and order[0] == "b" and order.back() == "a", str(order))
	var flow: Dictionary = _lab.world.get_flow(_at(Vector3(115, FLOOR, 20)) + Vector3.UP * 0.05)
	_check("path through the gap is long", flow.get("valid", false) and flow.distance > 12.0, str(flow))

	# Trigger actions: power to backup and a door locked.
	me.teleport(_at(Vector3(40, FLOOR, 60)))
	var hit := await _wait_until(func() -> bool: return "t_act" in fired, 2.0)
	await _frames(2)
	_check("trigger fires", hit, str(fired))
	_check("power=backup", play.power == "backup", play.power)
	_check("lock=d1", play.is_door_locked("d1"))
	_check("off=boss", not director.spawners.boss.active)

	# Unlock, open and turn a spawner on.
	me.teleport(_at(Vector3(70, FLOOR, 60)))
	hit = await _wait_until(func() -> bool: return "t_un" in fired, 2.0)
	await _frames(2)
	_check("unlock=d1", hit and not play.is_door_locked("d1"))
	_check("on=a", director.spawners.a.active)
	var opened := await _wait_until(func() -> bool: return play.is_door_open("d1"), 3.0)
	_check("open=d1", opened)
	director.set_spawner_active("a", false)

	# on_dead: the boss spawner (max_alive 1) births one enemy; killing it fires its trigger, which
	# opens d2. Only once.
	director.set_spawner_active("boss", true)
	var born := await _wait_until(func() -> bool: return director.spawners.boss.alive.size() == 1, 3.0)
	_check("boss spawns", born)
	var boss_id: int = director.spawners.boss.alive[0] if born else -1
	_check("on_dead waits for the death", "boss_dead" not in fired)
	director.set_spawner_active("boss", false)
	enemies.kill(boss_id)
	var dead := await _wait_until(func() -> bool: return "boss_dead" in fired, 3.0)
	_check("on_dead fires", dead, str(fired))
	var d2 := await _wait_until(func() -> bool: return play.is_door_open("d2"), 3.0)
	_check("its trigger's actions run (open=d2)", d2)
	_check("on_dead fires once", fired.count("boss_dead") == 1)

	# A finale_survived marker runs its actions when the finale ends (power back to backup, d1 shut).
	director.finale(0.5)
	await _frames(2)
	_check("finale restores power", play.power == "restored")
	var survived := await _wait_until(func() -> bool: return "finale_survived" in fired, 4.0)
	await _frames(2)
	_check("finale_survived marker's actions run", survived and play.power == "backup", play.power)
	var closed := await _wait_until(func() -> bool: return not play.is_door_open("d1"), 3.0)
	_check("close=d1 from the finale marker", closed)
	for id: int in enemies.enemies.keys():
		enemies.despawn(id)

	# Checkpoint: walking to a vat makes it the respawn point.
	_check("no checkpoint yet", play.checkpoint == "")
	me.teleport(_at(Vector3(20, FLOOR, 100)))
	var cp1 := await _wait_until(func() -> bool: return play.checkpoint == "vat1", 2.0)
	_check("first vat reached", cp1, play.checkpoint)
	me.teleport(_at(Vector3(80, FLOOR, 100)))
	var cp2 := await _wait_until(func() -> bool: return play.checkpoint == "vat2", 2.0)
	_check("second vat becomes the checkpoint", cp2, play.checkpoint)
	me.teleport(_at(Vector3(90, FLOOR, 20)))
	me.take_damage(1000000.0, me.global_position)
	await _frames(2)
	_check("dead", me.is_dead)
	var revived := await _wait_until(func() -> bool: return not me.is_dead, 6.0)
	var vat2 := _at(Vector3(80, FLOOR, 100))
	_check("respawned at the checkpoint vat", revived and me.global_position.distance_to(vat2) < 1.0,
			"%s vs %s" % [me.global_position, vat2])

	print("lab_hooks_test: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _at(voxel: Vector3) -> Vector3:
	return _lab.view.to_world(voxel)


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
	for box in [ROOM1, ROOM2, GAP]:
		world.fill_box(box[0], box[1], M.AIR, false)
	level.voxels = world.get_data()
	world.free()

	var add := func(id: String, object: Dictionary) -> void:
		object.id = id
		level.objects[id] = object
	var spawn := LevelSchema.new_marker("spawn", Vector3(50.0, FLOOR, 90.0), 0.0)
	add.call("spawn_1", spawn)
	for entry in [["d1", Vector3i(20, FLOOR, 112)], ["d2", Vector3i(60, FLOOR, 112)]]:
		var door := LevelSchema.new_prop("crate_8", entry[1], NORTH)
		door.door = true
		door.door_offset = Vector3i(10, 0, 0)
		door.use = "none"
		add.call(entry[0], door)
	for entry in [["a", Vector3(115.0, FLOOR, 20.0), 4], ["b", Vector3(50.0, FLOOR, 20.0), 4], ["boss", Vector3(170.0, FLOOR, 110.0), 1]]:
		var spawner := LevelSchema.new_marker("horde", entry[1])
		spawner.rate = 600.0
		spawner.max_alive = entry[2]
		spawner.active = false
		add.call(entry[0], spawner)
	level.objects.boss.on_dead = "boss_dead"
	var act := LevelSchema.new_marker("trigger", Vector3(40.0, FLOOR, 60.0))
	act.actions = "power=backup, lock=d1, off=boss"
	add.call("t_act", act)
	var un := LevelSchema.new_marker("trigger", Vector3(70.0, FLOOR, 60.0))
	un.actions = "unlock=d1,open=d1,on=a"
	add.call("t_un", un)
	var survived := LevelSchema.new_marker("trigger", Vector3(170.0, FLOOR, 20.0))
	survived.actions = "power=backup,close=d1"
	add.call("finale_survived", survived)
	var boss_dead := LevelSchema.new_marker("trigger", Vector3(170.0, FLOOR, 40.0))
	boss_dead.actions = "open=d2"
	add.call("boss_dead", boss_dead)
	add.call("vat1", LevelSchema.new_marker("clone_vat", Vector3(20.0, FLOOR, 100.0), 90.0))
	add.call("vat2", LevelSchema.new_marker("clone_vat", Vector3(80.0, FLOOR, 100.0), 180.0))
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
