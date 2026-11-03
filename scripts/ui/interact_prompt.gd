class_name InteractPrompt
extends Control
## Play-mode interact feedback for the local player: the prompt under the crosshair for the door or
## prop in view ("[E] Open", "Locked: needs red keycard"), and the reader panel for notes and
## terminals (LevelPlay.reading), which closes on E (Lab), Esc (the mouse is released), or walking
## away. Added by LabHud.

## Meters past reach the player can wander before an open note closes.
const READ_SLACK := 1.0

var lab: Lab

var _prompt := Label.new()
var _panel := PanelContainer.new()
var _title := Label.new()
var _text := Label.new()


static func create(level: Lab) -> InteractPrompt:
	var prompt := InteractPrompt.new()
	prompt.lab = level
	return prompt


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_prompt.label_settings = LabHud._settings(17, Color(1.0, 0.95, 0.8))
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position.y += 34.0
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt)

	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(520, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.05, 0.94)
	style.border_color = Color(0.3, 0.8, 0.6, 0.8)
	style.set_border_width_all(2)
	style.set_content_margin_all(18)
	style.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)
	_title.label_settings = LabHud._settings(20, Color(0.55, 1.0, 0.8), 0)
	column.add_child(_title)
	_text.label_settings = LabHud._settings(16, Color(0.85, 0.95, 0.9), 0)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(484, 0)
	column.add_child(_text)
	var hint := Label.new()
	hint.text = "E or Esc to close"
	hint.label_settings = LabHud._settings(13, Color(1, 1, 1, 0.5), 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(hint)
	_panel.visible = false
	add_child(_panel)
	lab.play.reading_changed.connect(_on_reading_changed)


func _process(_delta: float) -> void:
	var play := lab.play
	var me := lab.local_player()
	var playing := lab.mode == "play" and me != null and not me.is_dead and InputSetup.is_playing()
	if play.reading != "":
		var box := play.box_of(play.reading)
		var far := me == null or (box.size != Vector3.ZERO and _distance_to_box(me.camera.global_position, box) > LevelPlay.DOOR_REACH + READ_SLACK)
		if not playing or far:
			play.close_reading()
	_prompt.visible = playing and play.reading == ""
	if _prompt.visible:
		_prompt.text = play.interactables.prompt_for(me.camera).text


func _on_reading_changed(id: String) -> void:
	_panel.visible = id != ""
	if id == "":
		return
	var object: Dictionary = lab.level.objects.get(id, {})
	_title.text = "TERMINAL" if object.get("use") == "terminal" else "Note"
	var text := str(object.get("text", "")).strip_edges()
	_text.text = text if text != "" else "(blank)"


static func _distance_to_box(point: Vector3, box: AABB) -> float:
	return point.distance_to(point.clamp(box.position, box.end))
