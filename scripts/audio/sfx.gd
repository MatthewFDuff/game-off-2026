class_name Sfx
extends Node
## Every sound in the game, synthesized once at startup into AudioStreamWAVs (no audio assets), and
## played through small pools of reused players. Registered as the `SfxBank` autoload; gameplay code
## calls the static API (`Sfx.play`, `Sfx.play_at`, `Sfx.set_ambience`), which quietly does nothing
## when the autoload isn't there.

const RATE := 22050
## Low-frequency material (ambience, servo grind, power hum) is rendered at half rate to save startup time.
const LOW_RATE := 11025
const SILENT_DB := -40.0
const POSITIONAL_VOICES := 12
const FLAT_VOICES := 6
const NOISE_SIZE := 16384
const TABLE_SIZE := 2048
## Samples per envelope step.
const BLOCK := 16

enum Shape { SINE, TRIANGLE, SAW, SQUARE }

static var _instance: Sfx

var _streams := {}
var _noise := PackedFloat32Array()
## One-cycle wavetables, indexed by Shape.
var _tables: Array[PackedFloat32Array] = []
var _rng := RandomNumberGenerator.new()
var _positional: Array[AudioStreamPlayer3D] = []
var _positional_started: Array[int] = []
var _flat: Array[AudioStreamPlayer] = []
var _flat_started: Array[int] = []
var _ambience: Array[AudioStreamPlayer] = []
var _ambience_index := 0
var _ambience_name := ""
var _ambience_tween: Tween
## Headless runs (tests) synthesize and route everything but start no playback: there's nothing to
## hear, and playbacks still finishing when a test quits are reported as leaks.
var _muted := DisplayServer.get_name() == "headless"


#region Static API

## Plays a non-positional sound (UI, the player's own gun and body).
static func play(sound: String, volume_db := 0.0, pitch_jitter := 0.08, pitch := 1.0) -> void:
	if is_instance_valid(_instance):
		_instance._play(sound, volume_db, pitch_jitter, pitch)


## Plays a sound in the world at position.
static func play_at(sound: String, position: Vector3, volume_db := 0.0, pitch_jitter := 0.08, pitch := 1.0) -> void:
	if is_instance_valid(_instance):
		_instance._play_at(sound, position, volume_db, pitch_jitter, pitch)


## Crossfades the looped background to sound (or just retargets its volume if it's already playing).
## fade <= 0 sets the volume at once, unless a crossfade is still running.
static func set_ambience(sound: String, volume_db := -18.0, fade := 1.5) -> void:
	if is_instance_valid(_instance):
		_instance._set_ambience(sound, volume_db, fade)


static func stop_ambience(fade := 1.0) -> void:
	if is_instance_valid(_instance):
		_instance._set_ambience("", SILENT_DB, fade)


static func has_sound(sound: String) -> bool:
	return is_instance_valid(_instance) and _instance._streams.has(sound)

#endregion


func _enter_tree() -> void:
	_instance = self


func _exit_tree() -> void:
	if _instance == self:
		_instance = null
	# Players still holding a playback at shutdown leak it.
	for player in get_children():
		if player is AudioStreamPlayer or player is AudioStreamPlayer3D:
			player.stop()
			player.stream = null
	_streams.clear()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_count() == 0:
		push_warning("Sfx: no audio bus, staying silent.")
		return
	var start := Time.get_ticks_usec()
	var samples := _synthesize_all()
	print("Sfx: synthesized %d sounds (%d samples) in %.1f ms" % [_streams.size(), samples, (Time.get_ticks_usec() - start) / 1000.0])
	for i in POSITIONAL_VOICES:
		var player := AudioStreamPlayer3D.new()
		player.unit_size = 4.0
		player.max_distance = 45.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(player)
		_positional.append(player)
		_positional_started.append(0)
	for i in FLAT_VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_flat.append(player)
		_flat_started.append(0)
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.volume_db = SILENT_DB
		add_child(player)
		_ambience.append(player)


func _play(sound: String, volume_db: float, pitch_jitter: float, pitch: float) -> void:
	var stream: AudioStream = _streams.get(sound)
	if stream == null or _flat.is_empty():
		return
	var index := _pick(_flat, _flat_started)
	var player := _flat[index]
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = maxf(0.05, pitch * (1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)))
	if not _muted:
		player.play()


func _play_at(sound: String, position: Vector3, volume_db: float, pitch_jitter: float, pitch: float) -> void:
	var stream: AudioStream = _streams.get(sound)
	if stream == null or _positional.is_empty():
		return
	var index := _pick(_positional, _positional_started)
	var player := _positional[index]
	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db
	player.pitch_scale = maxf(0.05, pitch * (1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)))
	if not _muted:
		player.play()


## A free player if there is one, otherwise the one that started longest ago.
func _pick(pool: Array, started: Array[int]) -> int:
	var oldest := 0
	for i in pool.size():
		if not pool[i].playing:
			oldest = i
			break
		if started[i] < started[oldest]:
			oldest = i
	started[oldest] = Time.get_ticks_msec()
	return oldest


func _set_ambience(sound: String, volume_db: float, fade: float) -> void:
	if _ambience.is_empty():
		return
	var running := _ambience_tween != null and _ambience_tween.is_running()
	var current := _ambience[_ambience_index]
	if sound == _ambience_name:
		if sound.is_empty():
			return
		if fade <= 0.0:
			if not running:
				current.volume_db = volume_db
			return
		if running:
			_ambience_tween.kill()
			_ambience[1 - _ambience_index].stop()
		_ambience_tween = create_tween()
		_ambience_tween.tween_property(current, "volume_db", volume_db, fade)
		return

	var stream: AudioStreamWAV = _streams.get(sound)
	if not sound.is_empty() and stream == null:
		return
	if running:
		_ambience_tween.kill()
	_ambience_name = sound
	_ambience_index = 1 - _ambience_index
	var next := _ambience[_ambience_index]
	next.stop()
	_ambience_tween = null
	if stream:
		next.stream = stream
		next.volume_db = SILENT_DB
		if not _muted:
			next.play(_rng.randf() * stream.get_length())
		_ambience_tween = create_tween().set_parallel()
		_ambience_tween.tween_property(next, "volume_db", volume_db, maxf(fade, 0.01))
	if current.playing:
		if _ambience_tween == null:
			_ambience_tween = create_tween().set_parallel()
		_ambience_tween.tween_property(current, "volume_db", SILENT_DB, maxf(fade, 0.01))
		_ambience_tween.chain().tween_callback(current.stop)


#region Synthesis

func _synthesize_all() -> int:
	_rng.seed = 2026
	_noise.resize(NOISE_SIZE)
	for i in NOISE_SIZE:
		_noise[i] = _rng.randf() * 2.0 - 1.0
	_rng.randomize()
	for shape in Shape.size():
		var table := PackedFloat32Array()
		table.resize(TABLE_SIZE)
		for i in TABLE_SIZE:
			var phase := float(i) / TABLE_SIZE
			match shape:
				Shape.SINE:
					table[i] = sin(TAU * phase)
				Shape.TRIANGLE:
					table[i] = 4.0 * absf(phase - 0.5) - 1.0
				Shape.SAW:
					table[i] = 2.0 * phase - 1.0
				_:
					table[i] = 1.0 if phase < 0.5 else -1.0
		_tables.append(table)
	var total := 0
	for sound in [
		"rifle", "blast", "chip", "shroom_hit", "shroom_pop", "harvest_chime", "hurt", "plant", "uproot",
		"shroom_chitter", "bite", "dig", "hatch_servo", "power_down", "alarm", "power_up", "ui_blip",
		"build_place", "build_denied", "amb_day", "amb_night",
		"sting_night", "sting_finale", "sting_quota", "sting_gameover", "sting_dawn",
		"shotgun", "flame", "ricochet", "homing", "poison_shot", "ammo_shift", "pickup",
		"melee_swing", "melee_hit", "flask_throw", "flask_break",
		"drawer_open", "terminal_beep", "station_use", "glass_break",
		"fuse", "shroom_scream", "spit", "giant_slam",
		"spawn_pop", "burst", "spore_puff", "tentacle_grab",
	]:
		var stream: AudioStreamWAV = call("_make_" + sound)
		if stream:
			_streams[sound] = stream
			total += stream.data.size() / 2
	return total


## Sharp crack: bright noise burst over a darker body and a fast low thump.
func _make_rifle() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.22)
	_add_noise(buf, RATE, 0.0, 0.22, 0.6, 0.03, 7000.0)
	_add_noise(buf, RATE, 0.0, 0.22, 0.4, 0.07, 900.0)
	_add_tone(buf, RATE, 0.0, 0.12, 170.0, 55.0, 0.5, 0.045)
	return _to_wav(buf, RATE)


## Shotgun: a wide, heavier crack than the rifle with a long low boom under it.
func _make_shotgun() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.5)
	_add_noise(buf, RATE, 0.0, 0.5, 0.65, 0.05, 6000.0)
	_add_noise(buf, RATE, 0.0, 0.5, 0.55, 0.14, 700.0)
	_add_tone(buf, RATE, 0.0, 0.3, 120.0, 38.0, 0.6, 0.09)
	return _to_wav(buf, RATE)


## Flamethrower tick (replayed about 10 times a second while firing): a soft roaring whoosh with a
## fast flutter and a couple of crackles.
func _make_flame() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.16)
	_add_noise(buf, RATE, 0.0, 0.16, 0.45, 0.0, 1400.0, 120.0, 0.02, 0.05, 32.0, 0.5)
	for t in [0.03, 0.09]:
		_add_noise(buf, RATE, t + _rng.randf() * 0.02, 0.03, 0.3, 0.008, 0.0, 2500.0)
	return _to_wav(buf, RATE)


## Ricochet: a metallic ping that whines down in pitch, over a short scrape.
func _make_ricochet() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.35)
	_add_noise(buf, RATE, 0.0, 0.08, 0.5, 0.02, 0.0, 2500.0)
	_add_tone(buf, RATE, 0.0, 0.35, 2600.0, 1100.0, 0.35, 0.12, Shape.TRIANGLE)
	_add_tone(buf, RATE, 0.0, 0.2, 3900.0, 1700.0, 0.12, 0.06)
	return _to_wav(buf, RATE)


## Homing launch: a rising square-wave chirp with a breathy puff of exhaust.
func _make_homing() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.3)
	_add_tone(buf, RATE, 0.0, 0.22, 420.0, 1150.0, 0.22, 0.12, Shape.SQUARE)
	_add_tone(buf, RATE, 0.05, 0.2, 840.0, 2100.0, 0.12, 0.08)
	_add_noise(buf, RATE, 0.0, 0.3, 0.4, 0.1, 2200.0, 300.0)
	return _to_wav(buf, RATE)


## Poison shot: a wet bloop sliding down, a burble of bubbles and a hiss.
func _make_poison_shot() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.4)
	_add_tone(buf, RATE, 0.0, 0.18, 320.0, 110.0, 0.5, 0.07)
	for i in 4:
		var f := 500.0 + _rng.randf() * 400.0
		_add_tone(buf, RATE, 0.06 + i * 0.05, 0.05, f, f * 1.6, 0.18, 0.02)
	_add_noise(buf, RATE, 0.0, 0.4, 0.25, 0.15, 5000.0, 1500.0, 0.02)
	return _to_wav(buf, RATE)


## Ammo shift: two quick mechanical clicks and a short whirr rising between them.
func _make_ammo_shift() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.22)
	_add_noise(buf, RATE, 0.0, 0.03, 0.7, 0.006, 0.0, 3000.0)
	_add_tone(buf, RATE, 0.02, 0.12, 300.0, 700.0, 0.18, 0.0, Shape.SAW, 0.01, 0.03)
	_add_noise(buf, RATE, 0.14, 0.04, 0.8, 0.008, 0.0, 2500.0)
	_add_tone(buf, RATE, 0.14, 0.05, 1500.0, 1200.0, 0.15, 0.015, Shape.TRIANGLE)
	return _to_wav(buf, RATE)


## Melee swing: a fast whoosh of band-passed air that rises and falls.
func _make_melee_swing() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.28)
	_add_noise(buf, RATE, 0.0, 0.28, 0.5, 0.0, 2200.0, 500.0, 0.09, 0.15)
	_add_noise(buf, RATE, 0.05, 0.15, 0.25, 0.05, 4500.0, 1800.0, 0.03, 0.08)
	return _to_wav(buf, RATE)


## Melee hit: a heavy chop, a meaty thud under a short wet crack.
func _make_melee_hit() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.3)
	_add_tone(buf, RATE, 0.0, 0.18, 180.0, 60.0, 0.7, 0.06)
	_add_noise(buf, RATE, 0.0, 0.12, 0.6, 0.025, 3500.0)
	_add_noise(buf, RATE, 0.01, 0.25, 0.4, 0.08, 900.0)
	return _to_wav(buf, RATE)


## Flask throw: a short soft whoosh with a slosh of liquid.
func _make_flask_throw() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.3)
	_add_noise(buf, RATE, 0.0, 0.25, 0.35, 0.0, 1500.0, 300.0, 0.05, 0.12)
	for i in 3:
		var f := 300.0 + _rng.randf() * 250.0
		_add_tone(buf, RATE, 0.04 + i * 0.06, 0.06, f, f * 1.5, 0.12, 0.025)
	return _to_wav(buf, RATE)


## Flask break: bright glass tinkles over a crunchy shatter and a splash.
func _make_flask_break() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.6)
	_add_noise(buf, RATE, 0.0, 0.3, 0.7, 0.04, 0.0, 3000.0)
	_add_noise(buf, RATE, 0.0, 0.5, 0.35, 0.12, 1200.0, 200.0)
	for i in 6:
		var f := 2500.0 + _rng.randf() * 3000.0
		_add_tone(buf, RATE, 0.02 + _rng.randf() * 0.3, 0.12, f, f * 0.97, 0.12, 0.04, Shape.TRIANGLE)
	return _to_wav(buf, RATE)


## Pickup: two bright rising blips.
func _make_pickup() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.3)
	_add_tone(buf, RATE, 0.0, 0.12, 880.0, 880.0, 0.3, 0.06, Shape.TRIANGLE)
	_add_tone(buf, RATE, 0.08, 0.22, 1320.0, 1320.0, 0.3, 0.09, Shape.TRIANGLE)
	return _to_wav(buf, RATE)


## Explosion: long low-passed noise roar, a deep rumble, and a sub thump sweeping down.
func _make_blast() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.9)
	_add_noise(buf, RATE, 0.0, 0.9, 0.55, 0.18, 1800.0)
	_add_noise(buf, RATE, 0.0, 0.9, 0.5, 0.35, 260.0)
	_add_tone(buf, RATE, 0.0, 0.6, 95.0, 28.0, 0.55, 0.25)
	return _to_wav(buf, RATE)


## Voxel debris: a tick of high-passed noise with a tiny pitched ting.
func _make_chip() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.1)
	_add_noise(buf, RATE, 0.0, 0.1, 0.85, 0.018, 0.0, 2200.0)
	_add_tone(buf, RATE, 0.0, 0.06, 1900.0, 1300.0, 0.2, 0.015, Shape.TRIANGLE)
	return _to_wav(buf, RATE)


## Wet squish: a sine sliding down through the body, a muffled slap, and a second smaller squelch.
func _make_shroom_hit() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.25)
	_add_tone(buf, RATE, 0.0, 0.2, 340.0, 110.0, 0.55, 0.07)
	_add_noise(buf, RATE, 0.0, 0.2, 0.5, 0.05, 1300.0)
	_add_tone(buf, RATE, 0.035, 0.15, 560.0, 220.0, 0.25, 0.04)
	return _to_wav(buf, RATE)


## Death pop: a rising bloop, then a bright burst and a soft splatter tail.
func _make_shroom_pop() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.45)
	_add_tone(buf, RATE, 0.0, 0.1, 170.0, 720.0, 0.55, 0.06)
	_add_noise(buf, RATE, 0.05, 0.15, 0.6, 0.035, 3000.0)
	_add_noise(buf, RATE, 0.06, 0.39, 0.3, 0.12, 700.0, 0.0, 0.01)
	return _to_wav(buf, RATE)


## Money: two bell sines a fifth apart (C6 then G6) with a quiet octave shimmer.
func _make_harvest_chime() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.7)
	_add_tone(buf, RATE, 0.0, 0.7, 1046.5, 1046.5, 0.32, 0.22)
	_add_tone(buf, RATE, 0.08, 0.62, 1568.0, 1568.0, 0.3, 0.25)
	_add_tone(buf, RATE, 0.08, 0.4, 2093.0, 2093.0, 0.08, 0.12)
	return _to_wav(buf, RATE)


## Player hit: a body thud, a short scuff, and a low triangle grunt that sags in pitch.
func _make_hurt() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.3)
	_add_tone(buf, RATE, 0.0, 0.2, 150.0, 65.0, 0.62, 0.07)
	_add_noise(buf, RATE, 0.0, 0.15, 0.5, 0.04, 700.0)
	_add_tone(buf, RATE, 0.01, 0.28, 210.0, 135.0, 0.3, 0.09, Shape.TRIANGLE, 0.015)
	return _to_wav(buf, RATE)


## Planting: a soft low thump with a slow-attack puff of substrate.
func _make_plant() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.35)
	_add_tone(buf, RATE, 0.0, 0.15, 115.0, 55.0, 0.65, 0.05)
	_add_noise(buf, RATE, 0.02, 0.33, 0.28, 0.1, 1800.0, 0.0, 0.04)
	return _to_wav(buf, RATE)


## Spore matures: a ragged run of crunchy clicks over a tearing noise swell and a low heave.
func _make_uproot() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.6)
	for i in 7:
		_add_noise(buf, RATE, 0.02 + i * 0.055 + _rng.randf() * 0.03, 0.06, 0.5, 0.015, 4500.0, 600.0)
	_add_noise(buf, RATE, 0.0, 0.6, 0.4, 0.22, 900.0, 0.0, 0.08)
	_add_tone(buf, RATE, 0.0, 0.5, 90.0, 48.0, 0.45, 0.18, Shape.SINE, 0.05)
	return _to_wav(buf, RATE)


## Shroom vocal: a burst of five quick triangle chirps that wander in pitch.
func _make_shroom_chitter() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.4)
	for i in 5:
		var f := 850.0 + _rng.randf() * 450.0
		_add_tone(buf, RATE, i * 0.06, 0.07, f, f * 1.35, 0.55, 0.022, Shape.TRIANGLE)
	_add_noise(buf, RATE, 0.0, 0.32, 0.1, 0.1, 3000.0, 1200.0)
	return _to_wav(buf, RATE)


## Shroom bite: a hard high-passed snap with a short low knock.
func _make_bite() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.18)
	_add_noise(buf, RATE, 0.0, 0.1, 0.8, 0.014, 0.0, 1500.0)
	_add_tone(buf, RATE, 0.0, 0.12, 210.0, 80.0, 0.5, 0.035)
	return _to_wav(buf, RATE)


## Exploding shroom's fuse (0.8 s): a fizzing hiss under ticking beeps that speed up and rise.
func _make_fuse() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.8)
	_add_noise(buf, RATE, 0.0, 0.8, 0.3, 0.0, 0.0, 3500.0, 0.02, 0.05, 23.0, 0.5)
	var t := 0.0
	var gap := 0.17
	var f := 900.0
	while t < 0.75:
		_add_tone(buf, RATE, t, 0.04, f, f, 0.3, 0.015, Shape.SQUARE)
		t += gap
		gap *= 0.78
		f *= 1.08
	return _to_wav(buf, RATE)


## Alarm shroom's scream (1.5 s): a wailing saw that climbs, wavering, over breathy noise.
func _make_shroom_scream() -> AudioStreamWAV:
	var buf := _buffer(RATE, 1.5)
	_add_tone(buf, RATE, 0.0, 1.5, 420.0, 1250.0, 0.35, 0.0, Shape.SAW, 0.2, 0.15, 7.0, 0.35)
	_add_tone(buf, RATE, 0.0, 1.5, 633.0, 1880.0, 0.18, 0.0, Shape.TRIANGLE, 0.25, 0.15, 7.0, 0.35)
	_add_noise(buf, RATE, 0.0, 1.5, 0.22, 0.0, 4000.0, 900.0, 0.3, 0.2)
	return _to_wav(buf, RATE)


## Ranged shroom's spit: a wet hork, a bloop sliding up and a short spray.
func _make_spit() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.3)
	_add_noise(buf, RATE, 0.0, 0.12, 0.5, 0.04, 2500.0, 300.0)
	_add_tone(buf, RATE, 0.02, 0.14, 160.0, 420.0, 0.45, 0.05)
	_add_noise(buf, RATE, 0.08, 0.2, 0.25, 0.06, 6000.0, 2000.0)
	return _to_wav(buf, RATE)


## Giant's swing: a deep whoosh into a heavy ground thud.
func _make_giant_slam() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.7)
	_add_noise(buf, RATE, 0.0, 0.3, 0.4, 0.0, 900.0, 120.0, 0.12, 0.08)
	_add_tone(buf, RATE, 0.22, 0.45, 95.0, 34.0, 0.85, 0.16)
	_add_noise(buf, RATE, 0.22, 0.4, 0.5, 0.1, 700.0)
	return _to_wav(buf, RATE)


## Breaching: a gritty scrape of low-passed noise, three crunches, and a dull knock.
func _make_dig() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.35)
	_add_noise(buf, RATE, 0.0, 0.35, 0.5, 0.1, 1200.0)
	for t in [0.04, 0.12, 0.21]:
		_add_noise(buf, RATE, t, 0.08, 0.4, 0.018, 3500.0, 400.0)
	_add_tone(buf, RATE, 0.0, 0.15, 85.0, 50.0, 0.4, 0.07)
	return _to_wav(buf, RATE)


## Hatch servo: two low saws slowly winding up with a stuttering grind, motor noise, and a clunk.
func _make_hatch_servo() -> AudioStreamWAV:
	var buf := _buffer(LOW_RATE, 2.1)
	_add_tone(buf, LOW_RATE, 0.0, 1.85, 48.0, 66.0, 0.3, 0.0, Shape.SAW, 0.15, 0.25, 11.0, 0.5)
	_add_tone(buf, LOW_RATE, 0.0, 1.85, 97.0, 133.0, 0.12, 0.0, Shape.SAW, 0.2, 0.25, 7.0, 0.6)
	_add_noise(buf, LOW_RATE, 0.0, 1.85, 0.25, 0.0, 900.0, 0.0, 0.2, 0.25, 9.0, 0.7)
	_add_tone(buf, LOW_RATE, 1.8, 0.3, 95.0, 40.0, 0.6, 0.08)
	_add_noise(buf, LOW_RATE, 1.8, 0.2, 0.5, 0.035, 2500.0)
	return _to_wav(buf, LOW_RATE)


## Drawer / cabinet opening: a low wooden scrape and a latch click.
func _make_drawer_open() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.45)
	_add_noise(buf, RATE, 0.0, 0.32, 0.45, 0.0, 900.0, 120.0, 0.02, 0.06, 23.0, 0.5)
	_add_tone(buf, RATE, 0.0, 0.3, 140.0, 110.0, 0.12, 0.0, Shape.SAW, 0.02, 0.06, 23.0, 0.5)
	_add_noise(buf, RATE, 0.33, 0.05, 0.7, 0.01, 0.0, 2500.0)
	_add_tone(buf, RATE, 0.33, 0.06, 1700.0, 1400.0, 0.18, 0.015, Shape.TRIANGLE)
	return _to_wav(buf, RATE)


## Terminal: a short two-note square beep.
func _make_terminal_beep() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.22)
	_add_tone(buf, RATE, 0.0, 0.08, 1046.5, 1046.5, 0.16, 0.0, Shape.SQUARE, 0.003, 0.01)
	_add_tone(buf, RATE, 0.1, 0.1, 1568.0, 1568.0, 0.16, 0.0, Shape.SQUARE, 0.003, 0.02)
	return _to_wav(buf, RATE)


## Station: a hiss of air and a rising confirmation chime.
func _make_station_use() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.6)
	_add_noise(buf, RATE, 0.0, 0.35, 0.35, 0.12, 0.0, 1800.0)
	_add_tone(buf, RATE, 0.05, 0.25, 660.0, 660.0, 0.2, 0.1, Shape.TRIANGLE)
	_add_tone(buf, RATE, 0.18, 0.4, 990.0, 990.0, 0.2, 0.14, Shape.TRIANGLE)
	return _to_wav(buf, RATE)


## Mommy shroom births one: a wet low squelch rising into a soft pop.
func _make_spawn_pop() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.5)
	_add_tone(buf, RATE, 0.0, 0.3, 80.0, 160.0, 0.5, 0.12)
	_add_noise(buf, RATE, 0.0, 0.3, 0.35, 0.1, 600.0, 0.0, 0.05)
	_add_tone(buf, RATE, 0.25, 0.12, 260.0, 620.0, 0.4, 0.04)
	_add_noise(buf, RATE, 0.28, 0.2, 0.25, 0.05, 2200.0)
	return _to_wav(buf, RATE)


## Ceiling sac bursts: a heavy wet splat, a gush of low noise and a drippy tail.
func _make_burst() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.8)
	_add_tone(buf, RATE, 0.0, 0.25, 220.0, 60.0, 0.6, 0.08)
	_add_noise(buf, RATE, 0.0, 0.5, 0.7, 0.15, 1400.0)
	_add_noise(buf, RATE, 0.05, 0.75, 0.3, 0.3, 500.0, 0.0, 0.05)
	for i in 4:
		_add_tone(buf, RATE, 0.3 + i * 0.11, 0.06, 900.0 - i * 90.0, 400.0, 0.12, 0.02)
	return _to_wav(buf, RATE)


## Spore shroom puffs: a breathy hiss swelling and fading with a soft low cough under it.
func _make_spore_puff() -> AudioStreamWAV:
	var buf := _buffer(RATE, 1.1)
	_add_noise(buf, RATE, 0.0, 1.1, 0.5, 0.0, 3500.0, 300.0, 0.25, 0.6)
	_add_tone(buf, RATE, 0.0, 0.2, 120.0, 70.0, 0.45, 0.06)
	return _to_wav(buf, RATE)


## Tentacle grabs: a fleshy whip crack, then a slow wet creak as it tightens.
func _make_tentacle_grab() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.7)
	_add_noise(buf, RATE, 0.0, 0.08, 0.7, 0.02, 5000.0, 800.0)
	_add_tone(buf, RATE, 0.0, 0.15, 500.0, 140.0, 0.4, 0.05)
	_add_tone(buf, RATE, 0.1, 0.6, 70.0, 95.0, 0.3, 0.0, Shape.SAW, 0.1, 0.2, 9.0, 0.5)
	_add_noise(buf, RATE, 0.1, 0.55, 0.2, 0.0, 700.0, 0.0, 0.1, 0.2)
	return _to_wav(buf, RATE)


## Glass breaking: a bright crack and a shower of high, ringing shards.
func _make_glass_break() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.8)
	_add_noise(buf, RATE, 0.0, 0.15, 0.9, 0.04, 0.0, 3000.0)
	for i in 7:
		var t := 0.03 + i * 0.07 + _rng.randf() * 0.04
		var f := _rng.randf_range(2500.0, 5200.0)
		_add_tone(buf, RATE, t, 0.25, f, f * 0.97, 0.12, 0.05, Shape.TRIANGLE)
		_add_noise(buf, RATE, t, 0.04, 0.3, 0.01, 0.0, 4000.0)
	return _to_wav(buf, RATE)


## Power cut: a heavy breaker thunk, then the mains hum (saw and sine) sagging in pitch and fading.
func _make_power_down() -> AudioStreamWAV:
	var buf := _buffer(LOW_RATE, 1.6)
	_add_tone(buf, LOW_RATE, 0.0, 0.4, 120.0, 35.0, 0.7, 0.11)
	_add_noise(buf, LOW_RATE, 0.0, 0.2, 0.45, 0.035, 1600.0)
	_add_tone(buf, LOW_RATE, 0.0, 1.6, 120.0, 38.0, 0.18, 0.45, Shape.SAW, 0.01, 0.2)
	_add_tone(buf, LOW_RATE, 0.0, 1.6, 60.0, 20.0, 0.3, 0.5, Shape.SINE, 0.01, 0.2)
	return _to_wav(buf, LOW_RATE)


## Emergency lights: two square-ish beeps, the second a fourth lower.
func _make_alarm() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.75)
	_add_tone(buf, RATE, 0.0, 0.28, 784.0, 784.0, 0.24, 0.0, Shape.SQUARE, 0.005, 0.03)
	_add_tone(buf, RATE, 0.0, 0.28, 784.0, 784.0, 0.24, 0.0, Shape.TRIANGLE, 0.005, 0.03)
	_add_tone(buf, RATE, 0.38, 0.32, 587.0, 587.0, 0.24, 0.0, Shape.SQUARE, 0.005, 0.05)
	_add_tone(buf, RATE, 0.38, 0.32, 587.0, 587.0, 0.24, 0.0, Shape.TRIANGLE, 0.005, 0.05)
	return _to_wav(buf, RATE)


## Dawn: the hum spins back up (rising saw and sine) and settles with a soft chime.
func _make_power_up() -> AudioStreamWAV:
	var buf := _buffer(LOW_RATE, 1.5)
	_add_tone(buf, LOW_RATE, 0.0, 1.3, 35.0, 120.0, 0.16, 0.0, Shape.SAW, 0.9, 0.35)
	_add_tone(buf, LOW_RATE, 0.0, 1.3, 30.0, 60.0, 0.3, 0.0, Shape.SINE, 0.9, 0.35)
	_add_tone(buf, LOW_RATE, 0.95, 0.55, 880.0, 880.0, 0.18, 0.18)
	_add_tone(buf, LOW_RATE, 1.05, 0.45, 1318.5, 1318.5, 0.14, 0.15)
	return _to_wav(buf, LOW_RATE)


## UI blip: a short sine chirping upward.
func _make_ui_blip() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.09)
	_add_tone(buf, RATE, 0.0, 0.09, 1150.0, 1550.0, 0.55, 0.025)
	return _to_wav(buf, RATE)


## Build placed: a woody knock (falling sine), a noise clack, and a faint click on top.
func _make_build_place() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.22)
	_add_tone(buf, RATE, 0.0, 0.18, 190.0, 95.0, 0.55, 0.05)
	_add_noise(buf, RATE, 0.0, 0.12, 0.4, 0.025, 2600.0)
	_add_tone(buf, RATE, 0.0, 0.05, 950.0, 950.0, 0.1, 0.02, Shape.TRIANGLE)
	return _to_wav(buf, RATE)


## Denied: two low square buzzes, the second lower.
func _make_build_denied() -> AudioStreamWAV:
	var buf := _buffer(RATE, 0.28)
	_add_tone(buf, RATE, 0.0, 0.11, 220.0, 220.0, 0.26, 0.0, Shape.SQUARE, 0.004, 0.02)
	_add_tone(buf, RATE, 0.13, 0.15, 165.0, 165.0, 0.26, 0.0, Shape.SQUARE, 0.004, 0.03)
	return _to_wav(buf, RATE)


## Day ambience (2 s loop): 60 Hz mains hum with harmonics, plus ventilation (low-passed noise)
## breathing at 0.5 Hz and a faint hiss. Every periodic part fits the loop a whole number of times.
func _make_amb_day() -> AudioStreamWAV:
	var buf := _buffer(LOW_RATE, 2.05)
	_add_tone(buf, LOW_RATE, 0.0, 2.05, 60.0, 60.0, 0.12, 0.0, Shape.SINE, 0.0, 0.0)
	_add_tone(buf, LOW_RATE, 0.0, 2.05, 120.0, 120.0, 0.07, 0.0, Shape.SINE, 0.0, 0.0)
	_add_tone(buf, LOW_RATE, 0.0, 2.05, 180.0, 180.0, 0.025, 0.0, Shape.SINE, 0.0, 0.0)
	_add_noise(buf, LOW_RATE, 0.0, 2.05, 0.45, 0.0, 450.0, 0.0, 0.0, 0.0, 0.5, 0.35)
	_add_noise(buf, LOW_RATE, 0.0, 2.05, 0.05, 0.0, 0.0, 2500.0, 0.0, 0.0)
	_seam(buf, LOW_RATE)
	return _to_wav(buf, LOW_RATE, true)


## Night ambience (2 s loop): two detuned low sines beating at 1.5 Hz, an octave above, and a deep
## rumble of heavily low-passed noise swelling once per loop.
func _make_amb_night() -> AudioStreamWAV:
	var buf := _buffer(LOW_RATE, 2.05)
	_add_tone(buf, LOW_RATE, 0.0, 2.05, 41.0, 41.0, 0.22, 0.0, Shape.SINE, 0.0, 0.0)
	_add_tone(buf, LOW_RATE, 0.0, 2.05, 42.5, 42.5, 0.22, 0.0, Shape.SINE, 0.0, 0.0)
	_add_tone(buf, LOW_RATE, 0.0, 2.05, 82.0, 82.0, 0.06, 0.0, Shape.TRIANGLE, 0.0, 0.0, 0.5, 0.6)
	_add_noise(buf, LOW_RATE, 0.0, 2.05, 0.6, 0.0, 140.0, 0.0, 0.0, 0.0, 0.5, 0.5)
	_seam(buf, LOW_RATE)
	return _to_wav(buf, LOW_RATE, true)


## Night falls (2.4 s): a low A minor chord (A2 C3 E3 triangles plus a saw on the root) swelling in over 0.6 s, a
## detuned pair of high sines shimmering above it, and a soft low thud as it lands.
func _make_sting_night() -> AudioStreamWAV:
	var buf := _buffer(LOW_RATE, 2.4)
	for f in [110.0, 130.8, 164.8]:
		_add_tone(buf, LOW_RATE, 0.0, 2.4, f, f, 0.13, 1.4, Shape.TRIANGLE, 0.6, 0.8)
	_add_tone(buf, LOW_RATE, 0.0, 2.4, 110.4, 110.4, 0.07, 1.4, Shape.SAW, 0.6, 0.8)
	_add_tone(buf, LOW_RATE, 0.5, 1.9, 1318.5, 1318.5, 0.05, 0.7, Shape.SINE, 0.5, 0.6, 5.0, 0.4)
	_add_tone(buf, LOW_RATE, 0.5, 1.9, 1327.0, 1327.0, 0.05, 0.7, Shape.SINE, 0.5, 0.6, 5.0, 0.4)
	_add_tone(buf, LOW_RATE, 0.65, 0.5, 80.0, 38.0, 0.45, 0.14)
	return _to_wav(buf, LOW_RATE)


## Finale (2.0 s): two harsh low saw stabs a tritone apart (A2, Eb3) with a deep thud under each, and a
## rising triangle sweep over the second half.
func _make_sting_finale() -> AudioStreamWAV:
	var buf := _buffer(LOW_RATE, 2.0)
	for i in 2:
		_add_tone(buf, LOW_RATE, i * 0.5, 0.7, 110.0, 108.0, 0.14, 0.4, Shape.SAW, 0.02, 0.2)
		_add_tone(buf, LOW_RATE, i * 0.5, 0.7, 155.6, 153.0, 0.1, 0.4, Shape.SAW, 0.02, 0.2)
		_add_tone(buf, LOW_RATE, i * 0.5, 0.4, 70.0, 36.0, 0.4, 0.15)
	_add_tone(buf, LOW_RATE, 1.0, 1.0, 330.0, 660.0, 0.08, 0.6, Shape.TRIANGLE, 0.2, 0.4)
	return _to_wav(buf, LOW_RATE)


## Quota met (1.8 s): a rising C5 E5 G5 arpeggio of bell sines, each with a quiet octave partial, and
## a C6 octave ringing out over the top.
func _make_sting_quota() -> AudioStreamWAV:
	var buf := _buffer(LOW_RATE, 1.8)
	var notes := [523.25, 659.25, 784.0]
	for i in notes.size():
		var f: float = notes[i]
		_add_tone(buf, LOW_RATE, i * 0.11, 0.9, f, f, 0.3, 0.3)
		_add_tone(buf, LOW_RATE, i * 0.11, 0.5, f * 2.0, f * 2.0, 0.07, 0.15)
	_add_tone(buf, LOW_RATE, 0.33, 1.45, 1046.5, 1046.5, 0.22, 0.5, Shape.SINE, 0.004, 0.2)
	_add_tone(buf, LOW_RATE, 0.33, 1.45, 1568.0, 1568.0, 0.07, 0.45, Shape.SINE, 0.004, 0.2)
	return _to_wav(buf, LOW_RATE)


## Game over (2.5 s): a descending A minor line (E4, C4, A3) of slow-attack saws doubled with sines,
## ending on a long low A1 drone that fades out.
func _make_sting_gameover() -> AudioStreamWAV:
	var buf := _buffer(LOW_RATE, 2.5)
	var notes := [329.6, 261.6, 220.0]
	for i in notes.size():
		var f: float = notes[i]
		_add_tone(buf, LOW_RATE, i * 0.4, 0.6, f, f * 0.99, 0.09, 0.35, Shape.SAW, 0.12, 0.2)
		_add_tone(buf, LOW_RATE, i * 0.4, 0.6, f, f * 0.99, 0.22, 0.35, Shape.SINE, 0.12, 0.2)
	_add_tone(buf, LOW_RATE, 1.1, 1.4, 55.0, 52.0, 0.3, 0.7, Shape.SINE, 0.15, 0.4)
	_add_tone(buf, LOW_RATE, 1.1, 1.4, 110.0, 104.0, 0.1, 0.6, Shape.TRIANGLE, 0.15, 0.4)
	return _to_wav(buf, LOW_RATE)


## Dawn (2.2 s): a warm C major chord (sines on C4 E4 G4, triangles on a C3 root and C4) blooming over 1 s,
## with a gentle high G6 chime landing on top.
func _make_sting_dawn() -> AudioStreamWAV:
	var buf := _buffer(LOW_RATE, 2.2)
	for f in [261.6, 329.6, 392.0]:
		_add_tone(buf, LOW_RATE, 0.0, 2.2, f, f, 0.14, 1.0, Shape.SINE, 1.0, 0.6)
	_add_tone(buf, LOW_RATE, 0.0, 2.2, 130.8, 130.8, 0.12, 1.0, Shape.TRIANGLE, 1.0, 0.6)
	_add_tone(buf, LOW_RATE, 0.0, 2.2, 261.6, 261.6, 0.08, 1.0, Shape.TRIANGLE, 1.0, 0.6)
	_add_tone(buf, LOW_RATE, 0.9, 1.2, 1568.0, 1568.0, 0.12, 0.35)
	_add_tone(buf, LOW_RATE, 0.9, 0.7, 2093.0, 2093.0, 0.04, 0.2)
	return _to_wav(buf, LOW_RATE)


func _buffer(rate: int, seconds: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(rate * seconds))
	return buf


## Adds a tone from t0 lasting dur, gliding exponentially from f0 to f1 Hz. decay is the amplitude's
## e-folding time in seconds (0 = sustained). Linear attack and release ramps keep the edges clickless,
## and am_rate/am_depth add amplitude wobble. Reads one-cycle wavetables; the envelope runs per block.
func _add_tone(buf: PackedFloat32Array, rate: int, t0: float, dur: float, f0: float, f1: float, amp: float,
		decay: float, shape := Shape.SINE, attack := 0.003, release := 0.01, am_rate := 0.0, am_depth := 0.0) -> void:
	var start := int(t0 * rate)
	var n := mini(int(dur * rate), buf.size() - start)
	if n <= 0:
		return
	var table: PackedFloat32Array = _tables[shape]
	var mask := TABLE_SIZE - 1
	var phase := 0.0
	var step := f0 * TABLE_SIZE / rate
	var glide := pow(f1 / f0, 1.0 / n)
	var envelope := _Envelope.new(rate, n, amp, decay, attack, release, am_rate, am_depth)
	var i := 0
	while i < n:
		var g := envelope.at(i, _tables[Shape.SINE])
		var end := mini(i + BLOCK, n)
		for j in range(start + i, start + end):
			buf[j] += table[int(phase) & mask] * g
			phase += step
			step *= glide
		i = end


## Adds noise from t0 lasting dur, through an optional one-pole low-pass (lp_hz) and high-pass
## (hp_hz). Envelope parameters match _add_tone.
func _add_noise(buf: PackedFloat32Array, rate: int, t0: float, dur: float, amp: float, decay: float,
		lp_hz := 0.0, hp_hz := 0.0, attack := 0.001, release := 0.01, am_rate := 0.0, am_depth := 0.0) -> void:
	var start := int(t0 * rate)
	var n := mini(int(dur * rate), buf.size() - start)
	if n <= 0:
		return
	var lp_k := 1.0 - exp(-TAU * lp_hz / rate) if lp_hz > 0.0 else 1.0
	var hp_k := 1.0 - exp(-TAU * hp_hz / rate) if hp_hz > 0.0 else 0.0
	# Low-passing loses level; make some of it back so cutoffs can be tuned without retuning amp.
	var envelope := _Envelope.new(rate, n, amp * (1.0 + 2.5 * (1.0 - sqrt(lp_k))), decay, attack, release, am_rate, am_depth)
	var noise := _noise
	var offset := _rng.randi() % NOISE_SIZE
	var mask := NOISE_SIZE - 1
	var low := 0.0
	var slow := 0.0
	var i := 0
	while i < n:
		var g := envelope.at(i, _tables[Shape.SINE])
		var end := mini(i + BLOCK, n)
		if hp_k > 0.0:
			for j in range(i, end):
				low += lp_k * (noise[(offset + j) & mask] - low)
				slow += hp_k * (low - slow)
				buf[start + j] += (low - slow) * g
		else:
			for j in range(i, end):
				low += lp_k * (noise[(offset + j) & mask] - low)
				buf[start + j] += low * g
		i = end


## Amplitude envelope evaluated once per block: attack ramp, exponential decay, release ramp, wobble.
class _Envelope:
	var amp: float
	var decay_per_sample: float
	var attack_n: int
	var release_at: int
	var release_n: int
	var n: int
	var am_step: float
	var am_depth: float

	func _init(rate: int, length: int, gain: float, decay: float, attack: float, release: float, am_rate: float, depth: float) -> void:
		n = length
		amp = gain
		decay_per_sample = 1.0 / (decay * rate) if decay > 0.0 else 0.0
		attack_n = maxi(1, int(attack * rate))
		release_n = maxi(1, int(release * rate))
		release_at = n - release_n
		am_step = am_rate * TABLE_SIZE / rate
		am_depth = depth

	func at(i: int, sine: PackedFloat32Array) -> float:
		var g := amp
		if decay_per_sample > 0.0:
			g *= exp(-i * decay_per_sample)
		if i < attack_n:
			g *= float(i) / attack_n
		elif i > release_at:
			g *= float(n - i) / release_n
		if am_depth > 0.0:
			g *= 1.0 - am_depth * (0.5 + 0.5 * sine[int(i * am_step) & (TABLE_SIZE - 1)])
		return g


## Smooths a loop's wrap point by crossfading its last 50 ms into its first and dropping it. Buffers
## are rendered 50 ms long so periodic parts still fit the remaining loop whole.
func _seam(buf: PackedFloat32Array, rate: int) -> void:
	var n := int(0.05 * rate)
	var size := buf.size()
	for i in n:
		var t := float(i) / n
		buf[i] = buf[i] * t + buf[size - n + i] * (1.0 - t)
	buf.resize(size - n)


func _to_wav(buf: PackedFloat32Array, rate: int, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = buf.size()
	return wav

#endregion
