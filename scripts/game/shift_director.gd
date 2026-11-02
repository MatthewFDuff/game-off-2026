class_name ShiftDirector
extends Node
## Runs the shift loop. Day: plant spores in the grow beds, fortify. To start the night the player
## climbs the ladder and seals the hatch by hand; the power dies, emergency lights come on, and the
## spores grow into shrooms that must be harvested before the timer runs out.

signal phase_changed(phase: Phase)
signal message_posted(text: String, seconds: float)
## The dawn summary was closed ([E] or its timer ran out); the next day shift starts right after.
signal dawn_dismissed

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
## The atrium floor in front of the ladder up to the hatch control (set by the level generator).
@export var ladder_foot_position := Vector3.ZERO
## How close to the ladder's foot the player has to be for the climb prompt.
@export var ladder_prompt_radius := 3.0

@export_group("Objective marker")
## Centre of the grow-hall beds, where the day's planting happens (set by the level generator).
@export var beds_center := Vector3.ZERO
## At night, point at the nearest shroom when it's further away than this.
@export var straggler_distance := 12.0

@export_group("Emergency lights")
## The emergency lights come on one after another, nearest first, over this long.
@export var emergency_stagger := 2.5
## How many of the first lights beep as they come on.
@export var emergency_beeps := 3

@export_group("Timing")
@export var night_duration := 150.0
@export var dark_duration := 2.5
@export var hatch_duration := 2.0
@export var first_growth_delay := 3.0
@export var growth_spread := 12.0
## How long the dawn summary stays up before the next day starts on its own. [E] skips it.
@export var dawn_hold := 8.0

@export_group("Quota")
@export var base_quota := 3
@export var quota_per_shift := 2
@export var survival_bonus := 25

var phase := Phase.DAY
var night_time_left := 0.0
## What ended the run, for the game-over summary.
var game_over_cause := ""
## Seconds until the dawn summary closes by itself.
var dawn_time_left := 0.0

var _work_lights := {}
var _day_ambient := 0.35
var _day_glow := 0.9
## Flicker-on tweens for the emergency lights, killed if the night ends mid-sequence.
var _emergency_tweens: Array[Tween] = []
var _dawn_dismissed := false


func _ready() -> void:
	InputSetup.ensure_actions()
	player.died.connect(_on_player_died)
	shrooms.harvested.connect(func(_shroom: Shroom) -> void: state.record_harvest())
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
		Phase.DAWN:
			if not _dawn_dismissed:
				dawn_time_left -= delta
				# [E] skips it, but not in the first moment, so a tap meant for the last shroom doesn't.
				var can_skip := dawn_hold - dawn_time_left > 0.5
				if dawn_time_left <= 0.0 or (can_skip and Input.is_action_just_pressed("interact")):
					dawn_time_left = 0.0
					_dawn_dismissed = true
					dawn_dismissed.emit()
		Phase.GAME_OVER:
			if Input.is_action_just_pressed("restart"):
				get_tree().reload_current_scene()


func is_at_hatch_control() -> bool:
	return hatch_control_position != Vector3.ZERO and player.global_position.distance_to(hatch_control_position) <= hatch_reach


## Text for the HUD's interaction prompt, or "" when there's nothing to do here.
func get_prompt() -> String:
	if phase != Phase.DAY:
		return ""
	if not is_at_hatch_control():
		if state.planted >= state.quota and is_near_ladder_foot():
			return "Climb the ladder [W] to the hatch control"
		return ""
	if state.planted < state.quota:
		return "Plant %d more spore(s) before sealing the hatch" % (state.quota - state.planted)
	if not _below_hatch():
		return "Climb down a little, then [E] to seal the hatch"
	return "[E] Seal the hatch and begin the night shift"


## Whether the player is standing near the bottom of the hatch ladder (not climbing it yet).
func is_near_ladder_foot() -> bool:
	if ladder_foot_position == Vector3.ZERO or player.on_ladder:
		return false
	return player.global_position.distance_to(ladder_foot_position) <= ladder_prompt_radius


## Where the HUD's objective marker should point: {position: Vector3, label: String, dim: bool},
## or {} for no marker. Day: the grow hall until the quota is planted, then the ladder and hatch.
## Night: only the nearest shroom, when the quota is met or it's far off.
func get_objective_target() -> Dictionary:
	match phase:
		Phase.DAY:
			if state.planted < state.quota:
				if beds_center == Vector3.ZERO:
					return {}
				return {position = beds_center, label = "Grow hall", dim = false}
			if is_near_ladder_foot():
				return {position = ladder_foot_position, label = "Ladder", dim = false}
			if hatch_control_position == Vector3.ZERO:
				return {}
			return {position = hatch_control_position, label = "Hatch", dim = false}
		Phase.NIGHT:
			var nearest: Node3D = null
			var best := INF
			var candidates: Array[Node3D] = []
			candidates.append_array(shrooms.shrooms)
			if state.harvested >= state.quota:
				candidates.append_array(shrooms.spores)
			for node in candidates:
				var distance := node.global_position.distance_to(player.global_position)
				if distance < best:
					best = distance
					nearest = node
			if not nearest:
				return {}
			if state.harvested < state.quota and best <= straggler_distance:
				return {}
			var label := "Shroom" if nearest is Shroom else "Spore"
			return {position = nearest.global_position + Vector3.UP * 0.6, label = label, dim = true}
	return {}


## The standing goal for the HUD's objective line, shown under the phase title.
func get_objective() -> String:
	match phase:
		Phase.DAY:
			if state.planted < state.quota:
				return "Plant %d more spore%s in the grow hall [E]" % [state.quota - state.planted, _plural(state.quota - state.planted)]
			return "Climb the ladder in the atrium and seal the hatch [E]  ·  extra spores pay +$%d each" % shrooms.harvest_reward
		Phase.CLOSING:
			return "Sealing the hatch…"
		Phase.DARK:
			return "Get ready"
		Phase.NIGHT:
			var left := state.quota - state.harvested
			if left > 0:
				return "Harvest %d more shroom%s" % [left, _plural(left)]
			return "Quota met. Survive until dawn, or harvest the rest for +$%d each" % shrooms.harvest_reward
		Phase.DAWN:
			return "Power restored. Get ready for the next shift"
		Phase.GAME_OVER:
			return "Press [R] to restart"
	return ""


static func _plural(count: int) -> String:
	return "" if count == 1 else "s"


## Whether the player's head is under the hatch line, so closing it won't trap them in the shaft.
func _below_hatch() -> bool:
	return player.global_position.y + player.get_body_size().y <= hatch_height - 0.05


## Seals the hatch and starts the night, if the day's work is done.
func _try_start_night() -> void:
	if state.planted < state.quota:
		message_posted.emit("Plant %d more spore(s) in the grow beds first." % (state.quota - state.planted), 3.0)
		return
	if not _below_hatch():
		message_posted.emit("Climb down a little so the hatch clears your head.", 2.5)
		return
	build_tool.allowed = false
	_set_phase(Phase.CLOSING)
	message_posted.emit("Sealing the hatch…", hatch_duration + 0.5)
	_shake_while_sealing()
	await hatch.close(hatch_duration)

	_set_phase(Phase.DARK)
	_capture_work_lights()
	var tween := create_tween().set_parallel()
	for light in _work_lights:
		tween.tween_property(light, "light_energy", 0.0, 0.2)
	tween.tween_method(_set_power, 1.0, 0.0, 0.2)
	if environment:
		tween.tween_property(environment.environment, "ambient_light_energy", 0.015, 0.2)
	Sfx.play("power_down", -4.0, 0.0)
	message_posted.emit("The power cuts out.", 2.0)
	await get_tree().create_timer(dark_duration).timeout

	_set_phase(Phase.NIGHT)
	night_time_left = night_duration
	var glow := create_tween().set_parallel()
	glow.tween_method(shrooms.set_glow, 0.0, 1.0, 2.0)
	_light_emergency_lights()
	if environment:
		glow.tween_property(environment.environment, "ambient_light_energy", 0.05, 2.0)
		glow.tween_property(environment.environment, "glow_intensity", 1.6, 2.0)
	shrooms.begin_growth(first_growth_delay, growth_spread)
	message_posted.emit("Night shift. Something is growing in the beds. Harvest %d." % state.quota, 5.0)


func _end_night() -> void:
	if state.harvested < state.quota:
		_game_over("Quota missed: %d of %d harvested." % [state.harvested, state.quota])
		return
	shrooms.clear_all()
	state.earn(survival_bonus)
	state.shift += 1
	dawn_time_left = dawn_hold
	_dawn_dismissed = false
	_set_phase(Phase.DAWN)
	message_posted.emit("Power restored.", 2.5)

	shrooms.set_glow(0.0)
	Sfx.play("power_up", -5.0, 0.0)
	_kill_emergency_tweens()
	var tween := create_tween().set_parallel()
	for light in _work_lights:
		tween.tween_property(light, "light_energy", _work_lights[light], 1.0)
	for light in get_tree().get_nodes_in_group("emergency_light"):
		tween.tween_property(light, "light_energy", 0.0, 1.0)
	tween.tween_method(_set_power, 0.0, 1.0, 1.0)
	if environment:
		tween.tween_property(environment.environment, "ambient_light_energy", _day_ambient, 1.0)
		tween.tween_property(environment.environment, "glow_intensity", _day_glow, 1.0)
	# The summary stays up until dismissed; the hatch keeps opening behind it either way.
	await hatch.open(hatch_duration)
	if not _dawn_dismissed:
		await dawn_dismissed
	# A frame's grace, so the [E] that closed the summary doesn't also plant or seal something.
	await get_tree().process_frame
	if phase == Phase.DAWN:
		_start_day()


func _start_day() -> void:
	state.quota = quota_for(state.shift)
	state.planted = 0
	state.harvested = 0
	state.reset_shift_tallies()
	state.changed.emit()
	build_tool.allowed = true
	_set_power(1.0)
	_set_phase(Phase.DAY)
	message_posted.emit("Day shift %d. Fortify with [Q] while you work." % state.shift, 4.0)


## Switches the emergency lights on one by one, nearest the player first, each blinking a few
## times before it settles. Only the first few beep, so it reads as an alarm and not a wall of noise.
func _light_emergency_lights() -> void:
	_kill_emergency_tweens()
	var lights: Array[Light3D] = []
	for node in get_tree().get_nodes_in_group("emergency_light"):
		if node is Light3D:
			lights.append(node)
	var from := player.global_position
	lights.sort_custom(func(a: Light3D, b: Light3D) -> bool:
		return a.global_position.distance_squared_to(from) < b.global_position.distance_squared_to(from))
	var flicker := 0.3
	var step := (emergency_stagger - flicker) / maxf(1.0, lights.size() - 1.0)
	for i in lights.size():
		var light := lights[i]
		var on_energy: float = light.get_meta("on_energy", 0.7)
		var tween := create_tween()
		tween.tween_interval(step * i + randf() * step * 0.3)
		if i < emergency_beeps:
			tween.tween_callback(Sfx.play_at.bind("alarm", light.global_position, -10.0))
		# Two or three quick blinks, then settle.
		for blink in 2 + randi() % 2:
			tween.tween_property(light, "light_energy", on_energy * randf_range(0.6, 1.0), 0.02)
			tween.tween_interval(randf_range(0.03, 0.05))
			tween.tween_property(light, "light_energy", 0.0, 0.02)
			tween.tween_interval(randf_range(0.02, 0.04))
		tween.tween_property(light, "light_energy", on_energy, 0.08)
		_emergency_tweens.append(tween)


func _kill_emergency_tweens() -> void:
	for tween in _emergency_tweens:
		if tween.is_valid():
			tween.kill()
	_emergency_tweens.clear()


## The harvest (and minimum planting) quota for the given shift number.
func quota_for(shift: int) -> int:
	return base_quota + (shift - 1) * quota_per_shift


## Rattles the camera a few times while the hatch plate grinds shut.
func _shake_while_sealing() -> void:
	var steps := 4
	for i in steps:
		if phase != Phase.CLOSING:
			return
		player.add_shake(0.15)
		await get_tree().create_timer(hatch_duration / steps).timeout


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
	game_over_cause = reason
	_set_phase(Phase.GAME_OVER)


func _set_phase(value: Phase) -> void:
	phase = value
	phase_changed.emit(phase)


func get_phase_name() -> String:
	return ["Day shift", "Sealing hatch", "Power out", "Night shift", "Dawn", "Game over"][phase]
