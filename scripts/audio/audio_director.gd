class_name AudioDirector
extends Node
## Wires gameplay signals to sounds and runs the ambience for each phase of the shift, so gameplay
## scripts only make the few direct Sfx calls that have no signal to hang off.

@export var director: ShiftDirector
@export var weapons: SandboxTools
@export var player: Player
@export var shrooms: ShroomManager
@export var build_tool: BuildTool

@export_group("Levels")
@export var shot_db := -6.0
@export var blast_db := -3.0
@export var day_ambience_db := -18.0
@export var night_ambience_db := -20.0
## The night drone climbs to this over the last stretch of the timer.
@export var night_peak_db := -11.0
@export var night_build_up := 30.0

## Set once the quota sting has played this night; cleared when the next day starts.
var _quota_sung := false


func _ready() -> void:
	if weapons:
		weapons.fired.connect(_on_fired)
		weapons.shroom_hit.connect(_on_shroom_hit)
	if player:
		player.damaged.connect(_on_player_damaged)
		player.died.connect(_on_player_died)
	if shrooms:
		shrooms.harvested.connect(_on_harvested)
		shrooms.spore_matured.connect(_on_spore_matured)
	if build_tool:
		build_tool.piece_placed.connect(_on_piece_placed)
		build_tool.toggle_refused.connect(func() -> void: Sfx.play("build_denied", -8.0, 0.0))
	if director:
		if director.state:
			director.state.changed.connect(_on_state_changed)
		director.phase_changed.connect(_on_phase_changed)
		director.message_posted.connect(func(_text: String, _seconds: float) -> void: Sfx.play("ui_blip", -14.0, 0.03))


func _process(_delta: float) -> void:
	if director == null or director.phase != ShiftDirector.Phase.NIGHT:
		return
	var left := director.night_time_left
	if left < night_build_up:
		var t := clampf(1.0 - left / night_build_up, 0.0, 1.0)
		Sfx.set_ambience("amb_night", lerpf(night_ambience_db, night_peak_db, t), 0.0)


func _on_fired(kind: String) -> void:
	if kind == "blast":
		Sfx.play("blast", blast_db, 0.06)
	else:
		Sfx.play("rifle", shot_db, 0.1)


## Kills are voiced by the harvest pop instead, at the shroom.
func _on_shroom_hit(killed: bool) -> void:
	if not killed:
		Sfx.play("shroom_hit", -5.0, 0.12)


func _on_player_damaged(_amount: float, _from: Vector3) -> void:
	Sfx.play("hurt", -3.0, 0.1)


func _on_player_died() -> void:
	Sfx.play("hurt", 0.0, 0.0, 0.7)
	Sfx.play("power_down", -6.0, 0.0, 0.8)


func _on_harvested(shroom: Shroom) -> void:
	Sfx.play_at("shroom_pop", shroom.get_center(), -2.0, 0.12)
	Sfx.play("harvest_chime", -9.0, 0.02)


func _on_spore_matured(shroom: Shroom) -> void:
	Sfx.play_at("uproot", shroom.get_center(), -3.0, 0.12)


func _on_piece_placed(_piece: Dictionary, _voxels: int) -> void:
	Sfx.play("build_place", -6.0, 0.1)


func _on_phase_changed(phase: ShiftDirector.Phase) -> void:
	match phase:
		ShiftDirector.Phase.DAY:
			_quota_sung = false
			Sfx.set_ambience("amb_day", day_ambience_db, 2.0)
		ShiftDirector.Phase.DAWN:
			Sfx.set_ambience("amb_day", day_ambience_db, 2.0)
			Sfx.play("sting_dawn", -8.0, 0.0)
		ShiftDirector.Phase.DARK:
			Sfx.stop_ambience(0.25) # power_down carries the hum out.
		ShiftDirector.Phase.NIGHT:
			Sfx.set_ambience("amb_night", night_ambience_db, 3.0)
			Sfx.play("sting_night", -8.0, 0.0)
		ShiftDirector.Phase.GAME_OVER:
			Sfx.stop_ambience(2.5)
			Sfx.play("sting_gameover", -6.0, 0.0)


## Sounds the quota sting the first time the night's harvest reaches the quota.
func _on_state_changed() -> void:
	if _quota_sung or director == null or director.phase != ShiftDirector.Phase.NIGHT:
		return
	var state := director.state
	if state != null and state.quota > 0 and state.harvested >= state.quota:
		_quota_sung = true
		Sfx.play("sting_quota", -6.0, 0.0)
