class_name ShiftDirector
extends Node
## Runs the shift loop. Day: plant spores in the grow beds, fortify. To start the night the player
## climbs the ladder and seals the hatch by hand; the power dies, emergency lights come on, and the
## spores grow into shrooms that must be harvested before the timer runs out.

signal phase_changed(phase: Phase)
signal message_posted(text: String, seconds: float)

enum Phase { DAY, CLOSING, DARK, NIGHT, DAWN, GAME_OVER }

@export var state: GameState
@export var shrooms: ShroomManager
@export var hatch: Hatch
@export var player: Player
@export var build_tool: BuildTool
@export var world: VoxelWorld
@export var environment: WorldEnvironment

@export_group("Hatch control")
## Where the player has to be to work the hatch (set by the level generator).
@export var hatch_control_position := Vector3.ZERO
@export var hatch_reach := 1.8
## World height of the underside of the hatch; the player must be entirely below it to close it.
@export var hatch_height := 9.0

@export_group("Timing")
@export var night_duration := 150.0
@export var dark_duration := 2.5
@export var hatch_duration := 2.0
@export var first_growth_delay := 3.0
@export var growth_spread := 12.0

@export_group("Quota")
@export var base_quota := 3
@export var quota_per_shift := 2
@export var survival_bonus := 25

var phase := Phase.DAY
var night_time_left := 0.0

var _work_lights := {}
var _day_ambient := 0.35
var _day_glow := 0.9


func _ready() -> void:
	InputSetup.ensure_actions()
	player.died.connect(_on_player_died)
	if environment:
		_day_ambient = environment.environment.ambient_light_energy
		_day_glow = environment.environment.glow_intensity
	_start_day.call_deferred()


func _process(delta: float) -> void:
	match phase:
		Phase.DAY:
			if Input.is_action_just_pressed("interact") and is_at_hatch_control():
				_try_start_night()
		Phase.NIGHT:
			night_time_left -= delta
			if shrooms.remaining() == 0 or night_time_left <= 0.0:
				_end_night()
		Phase.GAME_OVER:
			if Input.is_action_just_pressed("restart"):
				get_tree().reload_current_scene()


func is_at_hatch_control() -> bool:
	return hatch_control_position != Vector3.ZERO and player.global_position.distance_to(hatch_control_position) <= hatch_reach


## Text for the HUD's interaction prompt, or "" when there's nothing to do here.
func get_prompt() -> String:
	if phase != Phase.DAY or not is_at_hatch_control():
		return ""
	if state.planted < state.quota:
		return "Plant %d more spore(s) before sealing the hatch" % (state.quota - state.planted)
	if player.global_position.y + player.get_body_size().y > hatch_height - 0.05:
		return "Climb below the hatch to close it"
	return "[E] Seal the hatch and begin the night shift"


## Seals the hatch and starts the night, if the day's work is done.
func _try_start_night() -> void:
	if state.planted < state.quota:
		message_posted.emit("Plant %d more spore(s) in the grow beds first." % (state.quota - state.planted), 3.0)
		return
	if player.global_position.y + player.get_body_size().y > hatch_height - 0.05:
		return
	build_tool.allowed = false
	_set_phase(Phase.CLOSING)
	await hatch.close(hatch_duration)

	_set_phase(Phase.DARK)
	_capture_work_lights()
	var tween := create_tween().set_parallel()
	for light in _work_lights:
		tween.tween_property(light, "light_energy", 0.0, 0.2)
	tween.tween_method(_set_power, 1.0, 0.0, 0.2)
	if environment:
		tween.tween_property(environment.environment, "ambient_light_energy", 0.015, 0.2)
	message_posted.emit("The power cuts out.", 2.0)
	await get_tree().create_timer(dark_duration).timeout

	_set_phase(Phase.NIGHT)
	night_time_left = night_duration
	var glow := create_tween().set_parallel()
	glow.tween_method(shrooms.set_glow, 0.0, 1.0, 2.0)
	for light in get_tree().get_nodes_in_group("emergency_light"):
		glow.tween_property(light, "light_energy", light.get_meta("on_energy", 0.7), 2.0)
	if environment:
		glow.tween_property(environment.environment, "ambient_light_energy", 0.05, 2.0)
		glow.tween_property(environment.environment, "glow_intensity", 1.6, 2.0)
	shrooms.begin_growth(first_growth_delay, growth_spread)
	message_posted.emit("Night shift. Something is growing in the beds. Harvest %d." % state.quota, 5.0)


func _end_night() -> void:
	if state.harvested < state.quota:
		_game_over("Quota missed: %d of %d harvested." % [state.harvested, state.quota])
		return
	_set_phase(Phase.DAWN)
	shrooms.clear_all()
	state.earn(survival_bonus)
	message_posted.emit("Shift survived. +$%d bonus. Power restored." % survival_bonus, 4.0)
	state.shift += 1

	shrooms.set_glow(0.0)
	var tween := create_tween().set_parallel()
	for light in _work_lights:
		tween.tween_property(light, "light_energy", _work_lights[light], 1.0)
	for light in get_tree().get_nodes_in_group("emergency_light"):
		tween.tween_property(light, "light_energy", 0.0, 1.0)
	tween.tween_method(_set_power, 0.0, 1.0, 1.0)
	if environment:
		tween.tween_property(environment.environment, "ambient_light_energy", _day_ambient, 1.0)
		tween.tween_property(environment.environment, "glow_intensity", _day_glow, 1.0)
	await hatch.open(hatch_duration)
	_start_day()


func _start_day() -> void:
	state.quota = base_quota + (state.shift - 1) * quota_per_shift
	state.planted = 0
	state.harvested = 0
	state.changed.emit()
	build_tool.allowed = true
	_set_power(1.0)
	_set_phase(Phase.DAY)
	message_posted.emit("Day shift %d. Plant %d spores in the grow beds [E], fortify [Q], then climb up and seal the hatch." % [state.shift, state.quota], 8.0)


## Remembers each work light's daytime brightness the first time the power goes out.
func _capture_work_lights() -> void:
	if not _work_lights.is_empty():
		return
	for light in get_tree().get_nodes_in_group("work_light"):
		_work_lights[light] = light.light_energy


func _set_power(amount: float) -> void:
	if world and world.material is ShaderMaterial:
		(world.material as ShaderMaterial).set_shader_parameter("facility_power", amount)


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
	return ["Day shift", "Sealing hatch", "Power out", "Night shift", "Dawn", "Game over"][phase]
