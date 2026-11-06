extends SceneTree
## Headless checks for footsteps and door sounds:
##   godot --headless --path . --script res://tests/sound_test.gd
## Builds a scratch level (one concrete room whose floor is striped tile, plank, diamond plate and
## dirt, plus a single door and a blast door standing in the open), plays it solo and checks: walking
## each stripe plays its surface's step (step_hard, step_wood, step_metal, step_soft) through
## footstep_played and Sfx at the player's feet, quietly; crouched steps are quieter; a fall lands
## with a thump; set_door plays door_slide at the door and door_clunk when it settles, the blast
## door the heavy slide; a locked door refused buzzes for the player who tried. Sounds are seen
## through the SfxBank autoload's `played` signal (headless runs start no playback).
##
## Game types are left unnamed (see editor_test.gd).

const SCRATCH := "user://sound_test_levels/"
const LEVEL := "sound_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIZE := Vector3i(6, 2, 6)
const FLOOR := 8
const ROOM := [Vector3i(8, FLOOR, 8), Vector3i(184, 50, 184)]
## Floor stripes (x from, x to, material), running the room's length along z.
const STRIPES := [[8, 48, M.TILE_LIGHT, "step_hard"], [48, 88, M.PLANK, "step_wood"],
		[88, 128, M.DIAMOND_PLATE, "step_metal"], [128, 184, M.DIRT, "step_soft"]]
const PLAYER_SPOT := Vector3(28.0, FLOOR, 170.0)

var _failures := 0
var lab
var me
## [sound, volume_db, position] for every sound started since the last _clear().
var _played := []
var _steps := []


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
	lab.items.drop_chance = 0.0
	lab.director.set_process(false)
	lab.director.set_physics_process(false)
	var bank = root.get_node_or_null("SfxBank")
	_check("the SfxBank autoload is there with a played signal", bank != null and bank.has_signal("played"))
	if bank == null:
		quit(1)
		return
	bank.played.connect(func(sound: String, db: float, at: Vector3) -> void: _played.append([sound, db, at]))
	me.footstep_played.connect(func(sound: String) -> void: _steps.append(sound))
	for sound in ["step_hard", "step_metal", "step_soft", "step_wood", "land", "door_slide", "door_slide_heavy", "door_clunk", "door_buzz"]:
		_check("Sfx builds %s" % sound, bank.has_sound(sound) and bank._get_stream(sound) != null)
	_check("footsteps are under 0.15 s", ["step_hard", "step_metal", "step_soft", "step_wood"].all(
			func(s: String) -> bool: return bank._get_stream(s).get_length() < 0.15))
	await _frames(10)

	await _walking()
	await _crouching()
	await _landing()
	await _doors()

	print("sound test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Walks forward a second along each stripe: every step is that surface's sound, at the feet.
func _walking() -> void:
	for stripe in STRIPES:
		var x: float = (stripe[0] + stripe[1]) * 0.5
		await _walk(Vector3(x, FLOOR, PLAYER_SPOT.z), 1.0)
		var sounds := _sounds_named(stripe[3])
		_check("walking on %s plays %s" % [M.get_material_name(stripe[2]), stripe[3]],
				_steps.size() >= 3 and _steps.all(func(s: String) -> bool: return s == stripe[3]), str(_steps))
		_check("  through Sfx, near the feet and quiet", sounds.size() == _steps.size()
				and sounds.all(func(p: Array) -> bool: return p[1] <= -12.0 and (p[2] as Vector3).distance_to(me.global_position) < 6.0),
				str(sounds))


func _crouching() -> void:
	await _walk(Vector3(28.0, FLOOR, PLAYER_SPOT.z), 1.0)
	var standing := _sounds_named("step_hard")
	Input.action_press("crouch")
	await _frames(3)
	await _walk(Vector3(28.0, FLOOR, PLAYER_SPOT.z), 1.5)
	var was_crouching: bool = me.crouching
	Input.action_release("crouch")
	var crouched := _sounds_named("step_hard")
	_check("crouched steps still sound", was_crouching and crouched.size() >= 2, str(_steps))
	_check("crouched steps are quieter", not standing.is_empty() and not crouched.is_empty()
			and crouched.all(func(p: Array) -> bool: return p[1] < standing[0][1] - 3.0), "%s vs %s" % [crouched, standing])
	await _frames(10)


## A two-meter drop lands with a thump at the feet.
func _landing() -> void:
	me.teleport(lab.view.to_world(PLAYER_SPOT) + Vector3.UP * 2.0)
	me.velocity = Vector3.ZERO
	await _frames(2)
	_clear()
	var landed := await _wait_until(func() -> bool: return me.on_floor, 3.0)
	await _frames(2)
	_check("a fall lands", landed)
	_check("with a thump", _sounds_named("land").size() == 1, str(_played))


## Door sounds come from the door (every peer's _door_motion and _door_settled play them).
func _doors() -> void:
	var play = lab.play
	for pair in [["door_a", "door_slide"], ["blast", "door_slide_heavy"]]:
		var id: String = pair[0]
		var center: Vector3 = play.door_box(id).get_center()
		_clear()
		play.set_door(id, true)
		await _frames(2)
		var slides := _sounds_named(pair[1])
		_check("%s starts to slide with %s" % [id, pair[1]], slides.size() == 1, str(_played))
		_check("  at the door", slides.size() == 1 and (slides[0][2] as Vector3).distance_to(center) < 0.5, str(slides))
		_check("  and no clunk yet", _sounds_named("door_clunk").is_empty(), str(_played))
		var opened := await _wait_until(func() -> bool: return play.is_door_open(id), 4.0)
		var clunks := _sounds_named("door_clunk")
		_check("%s settles open with a clunk" % id, opened and clunks.size() == 1, str(_played))
		_check("  at where it stopped", clunks.size() == 1
				and (clunks[0][2] as Vector3).distance_to(play.door_box(id).get_center()) < 0.5, str(clunks))
	# Locked: the player who tried hears a buzz (flat, theirs alone); nothing slides.
	play.set_door_locked("door_b", true)
	_clear()
	play.request_use("door_b")
	await _frames(3)
	_check("a locked door refuses with a buzz", _sounds_named("door_buzz").size() == 1
			and (_sounds_named("door_buzz")[0][2] as Vector3) == Vector3.INF, str(_played))
	_check("  and doesn't move", not play.is_door_open("door_b") and _sounds_named("door_slide").is_empty())


## Teleports the player to feet (voxels) and walks forward (-z) for seconds; clears the records first.
func _walk(feet: Vector3, seconds: float) -> void:
	me.teleport(lab.view.to_world(feet))
	me.velocity = Vector3.ZERO
	me.rotation.y = 0.0
	await _frames(3)
	_clear()
	me._stride = 0.0
	Input.action_press("move_forward")
	await create_timer(seconds).timeout
	Input.action_release("move_forward")
	await _frames(15)


func _clear() -> void:
	_played.clear()
	_steps.clear()


func _sounds_named(sound: String) -> Array:
	return _played.filter(func(p: Array) -> bool: return p[0] == sound)


## One concrete room with a striped floor, a single door and a blast door.
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
	for stripe in STRIPES:
		world.fill_box(Vector3i(stripe[0], FLOOR - 2, ROOM[0].z), Vector3i(stripe[1], FLOOR, ROOM[1].z), stripe[2], false)
	level.voxels = world.get_data()
	world.free()
	var add := func(id: String, prop_name: String, origin: Vector3i, fields := {}) -> void:
		var prop := LevelSchema.new_prop(prop_name, origin, 0)
		prop.id = id
		prop.merge(fields, true)
		level.objects[id] = prop
	add.call("door_a", "door_single", Vector3i(20, FLOOR, 30), {door_offset = Vector3i(14, 0, 0)})
	add.call("door_b", "door_single", Vector3i(60, FLOOR, 30), {door_offset = Vector3i(14, 0, 0)})
	add.call("blast", "door_blast", Vector3i(110, FLOOR, 30), {door_offset = Vector3i(0, 26, 0)})
	_check("the doors are doors", level.objects.door_a.door and level.objects.blast.door)
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


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(label: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", label, "" if ok or detail == "" else detail])
	if not ok:
		_failures += 1
