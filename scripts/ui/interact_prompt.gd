class_name InteractPrompt
extends Control
## Play-mode interact feedback for the local player: the prompt under the crosshair for the door or
## prop in view ("[E] Open", "Locked: needs red keycard"), and the reader panel for notes and
## terminals (LevelPlay.reading), which closes on E (Lab), Esc (the mouse is released), or walking
## away. Added by LabHud.

## Meters past reach the player can wander before an open note closes.
const READ_SLACK := 1.0
## The reader's text area never takes more than this share of the viewport's height; longer texts
## scroll (wheel, arrows, Page Up / Down).
const READ_HEIGHT_SHARE := 0.6
const READ_WIDTH := 520.0
const SCROLL_STEP := 40.0

var lab: Lab

var _prompt := Label.new()
var _panel := PanelContainer.new()
var _title := Label.new()
var _text := Label.new()
var _scroll := ScrollContainer.new()
var _reading := ""


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
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.custom_minimum_size = Vector2(READ_WIDTH - 36.0, 0)
	_scroll.add_child(_text)
	column.add_child(_scroll)
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
	if _panel.visible:
		_fit_reader()


## Keeps the reader on screen: its width fits the viewport and the text area is capped at a share of
## the viewport's height, scrolling past that.
func _fit_reader() -> void:
	var viewport := get_viewport_rect().size
	var width := minf(READ_WIDTH, viewport.x - 40.0)
	_panel.custom_minimum_size.x = width
	_scroll.custom_minimum_size.x = width - 36.0
	var cap := maxf(80.0, viewport.y * READ_HEIGHT_SHARE - 90.0)
	_scroll.custom_minimum_size.y = minf(_text.get_combined_minimum_size().y, cap)
	# Centered whatever size it ends up: its rect is its minimum size around the viewport's middle.
	var size := _panel.get_combined_minimum_size()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = (viewport - size) * 0.5
	_panel.size = size


func _unhandled_input(event: InputEvent) -> void:
	if not _panel.visible:
		return
	var step := 0.0
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step = SCROLL_STEP
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			step = -SCROLL_STEP
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_DOWN: step = SCROLL_STEP
			KEY_UP: step = -SCROLL_STEP
			KEY_PAGEDOWN: step = _scroll.size.y
			KEY_PAGEUP: step = -_scroll.size.y
	if step != 0.0:
		_scroll.scroll_vertical += int(step)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cycle_ammo") and lab.play.reading != "" and str(lab.level.objects.get(lab.play.reading, {}).get("steps", "")) != "":
		# SHIFT runs the next step of an experiment terminal (the host decides).
		lab.play.request_step(lab.play.reading)
		get_viewport().set_input_as_handled()


func _on_reading_changed(id: String) -> void:
	_panel.visible = id != ""
	if id == "":
		return
	var object: Dictionary = lab.level.objects.get(id, {})
	_title.text = "TERMINAL" if object.get("use") == "terminal" else "Note"
	var text := lab.play.reading_text(id).strip_edges()
	_text.text = text if text != "" else "(blank)"
	var same := id == _reading
	_reading = id
	_fit_reader()
	# A fresh note starts at the top; an experiment that just printed a line shows its end.
	_scroll.scroll_vertical = 100000 if same else 0


static func _distance_to_box(point: Vector3, box: AABB) -> float:
	return point.distance_to(point.clamp(box.position, box.end))
