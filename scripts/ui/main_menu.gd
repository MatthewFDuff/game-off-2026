extends Control
## Title menu: play solo, host a co-op session, or join one by address. Remembers the name and
## address between runs. Web builds are single-player, so only Solo is offered there.

const SETTINGS_PATH := "user://settings.cfg"

var _name := LineEdit.new()
var _address := LineEdit.new()
var _status := Label.new()
var _buttons: Array[Button] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)

	var background := ColorRect.new()
	background.color = Color(0.04, 0.045, 0.05)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(360, 0)
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)

	var title := Label.new()
	title.text = "EXPENDABLE"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "working title · prototype"
	subtitle.modulate = Color(1, 1, 1, 0.5)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

	_name.placeholder_text = "Your name"
	_name.text = settings.get_value("player", "name", "")
	_name.max_length = 20
	column.add_child(_labeled("Name", _name))

	_add_button(column, "Play solo", _on_solo)
	if Net.can_network():
		_add_button(column, "Host co-op (port %d)" % Net.DEFAULT_PORT, _on_host)
		_address.placeholder_text = "host address, e.g. 203.0.113.5"
		_address.text = settings.get_value("player", "address", "127.0.0.1")
		column.add_child(_labeled("Join", _address))
		_add_button(column, "Join co-op", _on_join)
		_address.text_submitted.connect(func(_t: String) -> void: _on_join())
	else:
		var note := Label.new()
		note.text = "Co-op needs the desktop build."
		note.modulate = Color(1, 1, 1, 0.5)
		column.add_child(note)

	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_status.text = Net.end_reason
	Net.end_reason = ""
	Net.session_ended.connect(_on_session_ended)


func _labeled(text: String, field: Control) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(60, 0)
	row.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return row


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	_buttons.append(button)


func _remember() -> void:
	Net.player_name = _name.text.strip_edges() if _name.text.strip_edges() != "" else "Expendable"
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("player", "name", _name.text.strip_edges())
	settings.set_value("player", "address", _address.text.strip_edges())
	settings.save(SETTINGS_PATH)


func _on_solo() -> void:
	_remember()
	Net.start_solo()


func _on_host() -> void:
	_remember()
	var error := Net.host()
	if error != OK:
		_status.text = "Couldn't host on port %d (%s). Is another copy already hosting?" % [Net.DEFAULT_PORT, error_string(error)]


func _on_join() -> void:
	_remember()
	var target := _address.text.strip_edges()
	var port := Net.DEFAULT_PORT
	if ":" in target:
		port = int(target.get_slice(":", 1))
		target = target.get_slice(":", 0)
	if target == "":
		_status.text = "Enter the host's address."
		return
	var error := Net.join(target, port)
	if error != OK:
		_status.text = "Couldn't connect (%s)." % error_string(error)
		return
	_status.text = "Connecting to %s:%d..." % [target, port]
	for button in _buttons:
		button.disabled = true


func _on_session_ended(reason: String) -> void:
	_status.text = reason
	for button in _buttons:
		button.disabled = false
