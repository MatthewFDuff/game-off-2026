class_name ShiftDirector
extends Node
## Runs the shift loop. Day: plant spores, build. Night: the hatch closes, the lights die, the
## spores glow and grow into shrooms that must be harvested before the timer runs out.

signal phase_changed(phase: Phase)
signal message_posted(text: String, seconds: float)

enum Phase { DAY, CLOSING, DARK, NIGHT, DAWN, GAME_OVER }

@export var state: GameState
@export var shrooms: ShroomManager
@export var hatch: Hatch
@export var player: Player
@export var build_tool: BuildTool
@export var environment: WorldEnvironment
## Every Light3D under this node is a work light: on in the day, off at night.
@export var work_lights: Node3D

@export_group("Timing")
@export var night_duration := 150.0
@export var dark_duration := 2.0
@export var hatch_duration := 1.5
@export var first_growth_delay := 3.0
@export var growth_spread := 12.0

@export_group("Quota")
@export var base_quota := 3
@export var quota_per_shift := 2
@export var survival_bonus := 25

var phase := Phase.DAY
var night_time_left := 0.0

var _light_energy := {}
var _day_ambient := 0.35
var _day_glow := 0.9


func _ready() -> void:
	InputSetup.ensure_actions()
	player.died.connect(_on_player_died)
	if work_lights:
		for light in work_lights.find_children("*", "Light3D"):
			_light_energy[light] = light.light_energy
	if environment:
		_day_ambient = environment.environment.ambient_light_energy
		_day_glow = environment.environment.glow_intensity
	_start_day.call_deferred()


func _process(delta: float) -> void:
	match phase:
		Phase.DAY:
			if Input.is_action_just_pressed("start_night"):
				_try_start_night()
		Phase.NIGHT:
			night_time_left -= delta
			var all_harvested := shrooms.remaining() == 0
			if all_harvested or night_time_left <= 0.0:
				_end_night()
		Phase.GAME_OVER:
			if Input.is_action_just_pressed("restart"):
				get_tree().reload_current_scene()


func _start_day() -> void:
	state.quota = base_quota + (state.shift - 1) * quota_per_shift
	state.planted = 0
	state.harvested = 0
	state.changed.emit()
	build_tool.allowed = true
	_set_phase(Phase.DAY)
	message_posted.emit("Day shift %d. Plant at least %d spores [E], fortify [Q], then start the night [Enter]." % [state.shift, state.quota], 8.0)


func _try_start_night() -> void:
	if state.planted < state.quota:
		message_posted.emit("Plant %d more spore(s) before the night shift." % (state.quota - state.planted), 3.0)
		return
	build_tool.allowed = false
	_set_phase(Phase.CLOSING)
	message_posted.emit("Hatch closing...", 2.0)
	await hatch.close(hatch_duration)

	_set_phase(Phase.DARK)
	var tween := create_tween().set_parallel()
	for light in _light_energy:
		tween.tween_property(light, "light_energy", 0.0, 0.25)
	if environment:
		tween.tween_property(environment.environment, "ambient_light_energy", 0.02, 0.25)
	await get_tree().create_timer(dark_duration).timeout

	_set_phase(Phase.NIGHT)
	night_time_left = night_duration
	var glow := create_tween().set_parallel()
	glow.tween_method(shrooms.set_glow, 0.0, 1.0, 1.5)
	if environment:
		glow.tween_property(environment.environment, "ambient_light_energy", 0.08, 1.5)
		glow.tween_property(environment.environment, "glow_intensity", 1.6, 1.5)
	shrooms.begin_growth(first_growth_delay, growth_spread)
	message_posted.emit("Night shift. Harvest %d before the timer runs out." % state.quota, 4.0)


func _end_night() -> void:
	if state.harvested < state.quota:
		_game_over("Quota missed: %d of %d harvested." % [state.harvested, state.quota])
		return
	_set_phase(Phase.DAWN)
	shrooms.clear_all()
	state.earn(survival_bonus)
	message_posted.emit("Shift survived. +$%d bonus." % survival_bonus, 4.0)
	state.shift += 1

	shrooms.set_glow(0.0)
	var tween := create_tween().set_parallel()
	for light in _light_energy:
		tween.tween_property(light, "light_energy", _light_energy[light], 1.0)
	if environment:
		tween.tween_property(environment.environment, "ambient_light_energy", _day_ambient, 1.0)
		tween.tween_property(environment.environment, "glow_intensity", _day_glow, 1.0)
	await hatch.open(hatch_duration)
	_start_day()


func _on_player_died() -> void:
	_game_over("You were overrun on shift %d." % state.shift)


func _game_over(reason: String) -> void:
	if phase == Phase.GAME_OVER:
		return
	build_tool.allowed = false
	_set_phase(Phase.GAME_OVER)
	message_posted.emit("%s  Press [R] to restart." % reason, 9999.0)


func _set_phase(value: Phase) -> void:
	phase = value
	phase_changed.emit(phase)


func get_phase_name() -> String:
	return ["Day shift", "Hatch closing", "Lights out", "Night shift", "Dawn", "Game over"][phase]
