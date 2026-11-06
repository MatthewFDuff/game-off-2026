extends SceneTree
## The music (docs/music.md), headless:
##   godot --headless --path . --script res://tests/music_test.gd
## The two OGGs load as looping AudioStreamOggVorbis at the lengths they were rendered to. Then,
## in a scratch level (two concrete rooms, one above the other) played solo, the MusicBox autoload
## plays the noir loop, switches to the action loop once a shroom stands within DANGER_RANGE of the
## player, keeps it for CALM_SECONDS after the shroom is gone and goes back to the noir where it
## left off; a finale "started" forces the action loop and "survived" releases it; a shroom in range
## but a floor up leaves the noir until a hole in the slab puts it in sight; hold() fades to silence
## and the Music setting moves the playing loop's level; edit mode is silent.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://music_test_levels/"
const LEVEL := "music_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIZE := Vector3i(6, 2, 4)
const FLOOR := 8
const ROOM := [Vector3i(8, FLOOR, 8), Vector3i(180, 40, 120)]
## The room above, over a slab of concrete.
const UP_FLOOR := 44
const ROOM_UP := [Vector3i(8, UP_FLOOR, 8), Vector3i(180, 76, 120)]
const PLAYER_SPOT := Vector3(150.0, FLOOR, 100.0)
## Just outside, then well inside, Music.DANGER_RANGE of the player (voxels are 0.1 m).
const FAR_SPOT := Vector3(150.0, FLOOR, 100.0 - 24.0 * 10.0 + 10.0)
const NEAR_SPOT := Vector3(150.0, FLOOR, 100.0 - 60.0)
## In the room above, 4 m along and 3.6 m up from the player: in range, out of sight.
const ABOVE_SPOT := Vector3(110.0, UP_FLOOR, 100.0)
## A hole in the slab on the line from the player's eye to that shroom (not under its feet; wide
## across, as the spawn stands the player a little off the marker).
const HOLE := [Vector3i(115, 40, 85), Vector3i(140, UP_FLOOR, 130)]
const LOOPS := {
	"res://assets/audio/music/noir_loop.ogg": 106.667,
	"res://assets/audio/music/action_loop.ogg": 55.814,
}

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for path in LOOPS:
		_check_loop(path, LOOPS[path])

	LevelData.save_dir_override = SCRATCH
	_make_level()
	var music = root.get_node("MusicBox")
	_check("silent before any scene", Music.playing() == "")
	root.get_node("Net").start_solo(LEVEL, "play")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	var lab = current_scene
	var me = lab.local_player()
	var enemies = lab.enemies
	lab.director.scale_per_player = 0.0
	_check("noir in play", await _wait_until(func() -> bool: return Music.playing() == "noir", 2.0), Music.playing())
	var noir = music.get_node("noir")
	var action = music.get_node("action")
	_check("noir fading in", noir.playing and noir.volume_db > Music.SILENT_DB)

	# A shroom out of range leaves the noir; one within DANGER_RANGE brings the action loop.
	var far = enemies.spawn("basic", lab.view.to_world(FAR_SPOT))
	_check("shroom spawned out of range", far != null and far.global_position.distance_to(me.global_position) > Music.DANGER_RANGE)
	await _seconds(0.6)
	_check("still noir with a shroom out of range", Music.playing() == "noir", Music.playing())
	enemies.despawn(far.id)
	var noir_left_at: float = noir.get_playback_position()
	var near = enemies.spawn("basic", lab.view.to_world(NEAR_SPOT))
	_check("shroom spawned in range", near != null and near.global_position.distance_to(me.global_position) < Music.DANGER_RANGE)
	_check("action loop on a nearby shroom", await _wait_until(func() -> bool: return Music.playing() == "action", 2.0), Music.playing())
	_check("action plays from its top", action.playing and action.get_playback_position() < 1.0)
	await _seconds(Music.FADE_OUT + 0.3)
	_check("noir faded out and stopped", not noir.playing, str(noir.volume_db))
	_check("action at its level", absf(action.volume_db - Music.LEVELS.action) < 0.5, str(action.volume_db))

	# Volume setting: the playing loop takes it at once.
	Music.set_volume_db(-12.0)
	_check("music setting applied to the playing loop", absf(action.volume_db - (Music.LEVELS.action - 12.0)) < 0.01, str(action.volume_db))
	Music.set_volume_db(0.0)

	# The threat gone: action for CALM_SECONDS more, then the noir again, resumed where it left off.
	enemies.despawn(near.id)
	await _seconds(Music.CALM_SECONDS * 0.5)
	_check("action lingers after the threat", Music.playing() == "action", Music.playing())
	_check("noir comes back", await _wait_until(func() -> bool: return Music.playing() == "noir", Music.CALM_SECONDS), Music.playing())
	_check("noir resumed where it left off", noir.playing and noir.get_playback_position() >= noir_left_at - 0.1 and noir.get_playback_position() < noir_left_at + 1.0, "%.2f s, left at %.2f s" % [noir.get_playback_position(), noir_left_at])

	# The finale forces the action loop on every peer; the end of it lets the noir back.
	lab.director.finale_event.emit("started")
	_check("finale starts the action loop", await _wait_until(func() -> bool: return Music.playing() == "action", 2.0), Music.playing())
	lab.director.finale_event.emit("survived")
	_check("noir after the finale", await _wait_until(func() -> bool: return Music.playing() == "noir", Music.CALM_SECONDS + 2.0), Music.playing())

	# A shroom in range but a floor up, behind the slab, is no threat; a hole that shows it is.
	var above = enemies.spawn("basic", lab.view.to_world(ABOVE_SPOT))
	above.set_physics_process(false) # Stays put instead of walking toward the player (and the hole).
	var above_offset: Vector3 = above.global_position - me.global_position
	_check("shroom spawned in range a floor up", above_offset.length() < Music.DANGER_RANGE and above_offset.y > Music.SAME_FLOOR, str(above_offset))
	await _seconds(0.6)
	_check("still noir with a shroom a floor up", Music.playing() == "noir", Music.playing())
	lab.world.fill_box(HOLE[0], HOLE[1], M.AIR, false)
	_check("action loop once the shroom shows through a hole", await _wait_until(func() -> bool: return Music.playing() == "action", 2.0), Music.playing())
	enemies.despawn(above.id)

	# The ending holds silence until released or the scene changes.
	Music.hold(0.0)
	await _seconds(Music.FADE_OUT + 0.3) # The action loop was still fading out.
	_check("hold silences", Music.playing() == "" and not noir.playing and not action.playing, "%s noir %s action %s" % [Music.playing(), noir.playing, action.playing])
	Music.release()
	_check("release brings the music back", await _wait_until(func() -> bool: return Music.playing() == "noir", 2.0), Music.playing())

	# Edit mode is silent.
	lab.request_mode("edit")
	_check("edit mode is silent", await _wait_until(func() -> bool: return Music.playing() == "", 2.0), Music.playing())

	print("music_test: %s" % ("OK" if _failures == 0 else "%d failure(s)" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_loop(path: String, seconds: float) -> void:
	var stream := load(path)
	if stream == null or not (stream is AudioStreamOggVorbis):
		_check("%s loads as AudioStreamOggVorbis" % path, false)
		return
	_check("%s loops" % path.get_file(), stream.loop)
	var length: float = stream.get_length()
	_check("%s is %.3f s" % [path.get_file(), seconds], absf(length - seconds) <= 0.05, "%.3f s" % length)


## Two concrete rooms, one above the other, with a spawn in the lower one.
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
	world.fill_box(ROOM_UP[0], ROOM_UP[1], M.AIR, false)
	level.voxels = world.get_data()
	world.free()
	var spawn := LevelSchema.new_marker("spawn", PLAYER_SPOT, 0.0)
	spawn.id = "spawn_1"
	level.objects[spawn.id] = spawn
	_check("level saves", level.save() == OK)


func _seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await process_frame
	return true


func _check(label: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", label, "" if ok else detail])
	if not ok:
		_failures += 1
