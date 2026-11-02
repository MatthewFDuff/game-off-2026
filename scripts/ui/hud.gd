extends CanvasLayer
## Crosshair, capture prompt, shift status, money and quota, health, director messages, and a red
## flash when the player is hurt. Everything except the crosshair and prompt is built in code.

@export var director: ShiftDirector
@export var state: GameState
@export var player: Player
@export var plant_tool: PlantTool

@onready var crosshair: Label = $Crosshair
@onready var capture_hint: Label = $CaptureHint

var _phase := Label.new()
var _status := Label.new()
var _health := Label.new()
var _message := Label.new()
var _prompt := Label.new()
var _hurt := ColorRect.new()
var _message_time := 0.0


func _ready() -> void:
	var settings := LabelSettings.new()
	settings.font_size = 22
	settings.outline_size = 5
	settings.outline_color = Color.BLACK
	for label in [_phase, _status, _health, _message, _prompt]:
		label.label_settings = settings
		add_child(label)

	_phase.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_health.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	_health.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 90)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.position.y += 48.0
	_prompt.modulate = Color(1.0, 0.95, 0.7)

	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.color = Color(0.8, 0.0, 0.0, 0.0)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hurt)
	move_child(_hurt, 0)

	if director:
		director.message_posted.connect(_show_message)
	if player:
		player.damaged.connect(func(_amount: float) -> void: _hurt.color.a = 0.35)


func _show_message(text: String, seconds: float) -> void:
	_message.text = text
	_message_time = seconds


func _process(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	crosshair.visible = captured
	capture_hint.visible = not captured

	_message_time -= delta
	_message.visible = _message_time > 0.0
	_hurt.color.a = move_toward(_hurt.color.a, 0.0, delta * 0.8)

	if director:
		var text := director.get_phase_name()
		if director.phase == ShiftDirector.Phase.NIGHT:
			var t := maxi(0, ceili(director.night_time_left))
			text += "  %d:%02d" % [t / 60, t % 60]
		_phase.text = text
	if state:
		var progress := "Planted %d / %d" % [state.planted, state.quota]
		if director and director.phase >= ShiftDirector.Phase.CLOSING and director.phase <= ShiftDirector.Phase.DAWN:
			progress = "Harvested %d / %d" % [state.harvested, state.quota]
		_status.text = "$%d\n%s" % [state.money, progress]
	var prompt := director.get_prompt() if director else ""
	if prompt.is_empty() and plant_tool:
		prompt = plant_tool.get_prompt()
	_prompt.text = prompt
	_prompt.visible = captured and not prompt.is_empty()
	if player:
		_health.text = "HP %d" % ceili(player.health)
		_health.modulate = Color.WHITE if player.health > 35.0 else Color(1, 0.4, 0.4)
