class_name Music
extends Node
## The game's music: the two 8-bit loops in docs/music.md, played by the `MusicBox` autoload. Every
## TICK it decides from the current scene what should play, so nothing else has to cue it: the
## cubicle and a lab in play get the noir loop; the action loop takes over while a living enemy
## (done emerging) within DANGER_RANGE of the local player is in their sight or on their floor
## (_threat: one a storey up behind a slab doesn't count until it shows through a hole), or the
## generator finale is running (HordeDirector.finale_event, which every peer gets), and the noir
## comes back CALM_SECONDS after the last threat. Edit mode, the waiting room and every other scene are silent. Each change
## crossfades (FADE_IN / FADE_OUT); the noir resumes where it left off, the action loop starts from
## its top, and a loop that is already playing carries on across a scene change (cubicle to lab).
## The ending holds silence (hold) until the next scene; a replay releases it. GameSettings sets the
## music volume (set_volume_db) on top of each loop's own level (LEVELS). Keeps playing while the
## tree is paused. Static API, so callers don't care whether the autoload exists.

const TRACKS := {
	noir = "res://assets/audio/music/noir_loop.ogg",
	action = "res://assets/audio/music/action_loop.ogg",
}
## Each loop's level (dB) before the Music setting; the action loop renders about 3.5 LU hotter.
const LEVELS := {noir = -6.0, action = -9.0}
const SILENT_DB := -60.0
const FADE_IN := 1.5
const FADE_OUT := 2.5
const TICK := 0.25
## Meters (straight line) within which a living enemy can mean combat.
const DANGER_RANGE := 16.0
## Within DANGER_RANGE, an enemy counts when it stands less than this many meters above or below the
## local player (their floor, stairs included: a storey is 3.3 m floor to floor) or, farther up or
## down, when the player's camera has a line of sight to its body (a hole, a window, a mezzanine).
const SAME_FLOOR := 2.0
## Seconds without a threat before the action loop gives way to the noir.
const CALM_SECONDS := 8.0

static var _instance: Music
static var _volume_db := 0.0

## The loop playing (or fading in) now: "noir", "action" or "".
var current := ""
## Set by hold(): silence until the scene changes or release().
var held := false
var _players := {}
var _positions := {}
var _tweens := {}
var _muted := false
var _calm_left := 0.0
var _finale := false
var _scene: Node
var _tick := 0.0
## Combat (scripts/combat/combat.gd), loaded on first use: naming it here would compile the enemies
## and the lab along with this autoload, and a test that names Music compiles it before the
## autoloads those scripts name exist.
var _combat: Script


# --- Static API -----------------------------------------------------------------------------------

## The Music setting (GameSettings.volume_db), on top of the loop's own level.
static func set_volume_db(db: float) -> void:
	_volume_db = db
	if is_instance_valid(_instance):
		_instance._remix()


## Fade out and stay silent until the scene changes or release() (the ending).
static func hold(fade := FADE_OUT) -> void:
	if is_instance_valid(_instance):
		_instance.held = true
		_instance._switch("", fade)


static func release() -> void:
	if is_instance_valid(_instance):
		_instance.held = false


## The loop playing now ("noir", "action" or "").
static func playing() -> String:
	return _instance.current if is_instance_valid(_instance) else ""


# --- The autoload ---------------------------------------------------------------------------------

func _ready() -> void:
	_instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_count() == 0:
		push_warning("Music: no audio bus, staying silent.")
		_muted = true
	for track: String in TRACKS:
		var player := AudioStreamPlayer.new()
		player.name = track
		player.stream = load(TRACKS[track])
		player.volume_db = SILENT_DB
		add_child(player)
		_players[track] = player


func _process(delta: float) -> void:
	_calm_left = maxf(_calm_left - delta, 0.0)
	_tick += delta
	if _tick < TICK:
		return
	_tick = 0.0
	_watch_scene()
	var want := _wanted()
	if want != current:
		_switch(want, FADE_OUT)


## A new current scene: the hold ends, the finale flag clears, and a lab's director reports the
## finale to every peer.
func _watch_scene() -> void:
	var scene := get_tree().current_scene
	if scene == _scene:
		return
	_scene = scene
	held = false
	_finale = false
	_calm_left = 0.0
	var director: Object = scene.get("director") if scene else null
	if director and director.has_signal("finale_event"):
		director.finale_event.connect(_on_finale)


func _on_finale(kind: String) -> void:
	_finale = kind == "started"


func _wanted() -> String:
	if held or _scene == null:
		return ""
	var script: Script = _scene.get_script()
	var kind: String = script.get_global_name() if script else ""
	if kind == "Cubicle":
		return "noir"
	if kind != "Lab" or _scene.get("mode") != "play":
		return ""
	if _finale or _threat():
		_calm_left = CALM_SECONDS
		return "action"
	return "action" if current == "action" and _calm_left > 0.0 else "noir"


## A living enemy (done emerging) within DANGER_RANGE of the local player, on their floor
## (SAME_FLOOR) or in sight of their camera (Combat.can_see_box through the voxel world, so glass
## and holes count, slabs and walls don't). The eye is the camera, or the chest without one.
func _threat() -> bool:
	var me: Node3D = _scene.call("local_player") if _scene.has_method("local_player") else null
	var manager: Object = _scene.get("enemies")
	if me == null or manager == null:
		return false
	if _combat == null:
		_combat = load("res://scripts/combat/combat.gd")
	var world: VoxelWorld = _scene.get("world")
	var camera: Node3D = me.get("camera")
	var eye: Vector3 = camera.global_position if camera and camera.is_inside_tree() else _combat.chest(me)
	var enemies: Dictionary = manager.get("enemies")
	for enemy: Node3D in enemies.values():
		if not enemy.get("alive") or enemy.get("emerging") > 0.0:
			continue
		var offset := enemy.global_position - me.global_position
		if offset.length() > DANGER_RANGE:
			continue
		if absf(offset.y) < SAME_FLOOR or _combat.can_see_box(world, eye, enemy.call("world_bounds")):
			return true
	return false


## Crossfade from the current loop to track ("" for silence). The noir keeps its place; the
## action loop starts from the top.
func _switch(track: String, fade_out: float) -> void:
	var previous := current
	current = track
	if previous != "":
		var old: AudioStreamPlayer = _players[previous]
		_positions[previous] = old.get_playback_position()
		_fade(previous, SILENT_DB, fade_out, true)
	if track == "":
		return
	var player: AudioStreamPlayer = _players[track]
	if not _muted and not player.playing:
		player.play(_positions.get(track, 0.0) if track == "noir" else 0.0)
	_fade(track, _target_db(track), FADE_IN, false)


func _fade(track: String, to_db: float, seconds: float, stop_after: bool) -> void:
	var player: AudioStreamPlayer = _players[track]
	var tween: Tween = _tweens.get(track)
	if tween and tween.is_running():
		tween.kill()
	if seconds <= 0.0:
		player.volume_db = to_db
		if stop_after:
			player.stop()
		return
	tween = create_tween()
	tween.tween_property(player, "volume_db", to_db, seconds)
	if stop_after:
		tween.tween_callback(player.stop)
	_tweens[track] = tween


func _target_db(track: String) -> float:
	return maxf(LEVELS[track] + _volume_db, SILENT_DB)


## The Music setting changed: the playing loop takes its new level at once.
func _remix() -> void:
	if current == "":
		return
	var tween: Tween = _tweens.get(current)
	if tween and tween.is_running():
		tween.kill()
	_players[current].volume_db = _target_db(current)
