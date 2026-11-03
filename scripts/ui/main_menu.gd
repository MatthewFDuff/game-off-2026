extends Control
## Title menu: pick a level, then play solo, host a co-op game, open the co-op level editor, or join
## someone by address. New levels are created here too. Remembers the name, address and level
## between runs. Web builds are single-player, so the editor and co-op run solo there.

const SETTINGS_PATH := "user://settings.cfg"
const SIZES := [
	{label = "Small (25 x 19 x 25 m)", chunks = Vector3i(8, 6, 8)},
	{label = "Medium (38 x 25 x 38 m)", chunks = Vector3i(12, 8, 12)},
	{label = "Large (51 x 32 x 51 m)", chunks = Vector3i(16, 10, 16)},
]

var _name := LineEdit.new()
var _address := LineEdit.new()
var _level := OptionButton.new()
var _status := Label.new()
var _buttons: Array[Button] = []
var _new_panel := VBoxContainer.new()
var _new_name := LineEdit.new()
var _new_size := OptionButton.new()
var _new_fill := OptionButton.new()


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
	column.custom_minimum_size = Vector2(380, 0)
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

	var level_row := HBoxContainer.new()
	_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_row.add_child(_level)
	var new_button := Button.new()
	new_button.text = "New level..."
	new_button.pressed.connect(func() -> void: _new_panel.visible = not _new_panel.visible)
	level_row.add_child(new_button)
	column.add_child(_labeled("Level", level_row))
	_fill_levels(settings.get_value("player", "level", Net.DEFAULT_LEVEL))
	_build_new_panel(column)

	_add_button(column, "Play solo", _on_solo)
	if Net.can_network():
		_add_button(column, "Host co-op game (port %d)" % Net.DEFAULT_PORT, _on_host)
	_add_button(column, "Edit level" + (" (co-op: friends can join)" if Net.can_network() else ""), _on_edit)
	if Net.can_network():
		_address.placeholder_text = "host address, e.g. 203.0.113.5"
		_address.text = settings.get_value("player", "address", "127.0.0.1")
		column.add_child(_labeled("Join", _address))
		_add_button(column, "Join (game or editor)", _on_join)
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


func _build_new_panel(column: Control) -> void:
	_new_panel.visible = false
	_new_name.placeholder_text = "level name, e.g. cubicle"
	_new_panel.add_child(_labeled("Name", _new_name))
	for size in SIZES:
		_new_size.add_item(size.label)
	_new_size.select(0)
	_new_panel.add_child(_labeled("Size", _new_size))
	_new_fill.add_item("Solid rock (carve rooms out)")
	_new_fill.add_item("Empty air (build up)")
	_new_panel.add_child(_labeled("Start", _new_fill))
	var create := Button.new()
	create.text = "Create level"
	create.pressed.connect(_on_create)
	_new_panel.add_child(create)
	column.add_child(_new_panel)


func _fill_levels(select: String) -> void:
	_level.clear()
	for level_name in LevelData.list():
		_level.add_item(level_name)
		if level_name == select:
			_level.select(_level.item_count - 1)


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


func _level_name() -> String:
	return _level.get_item_text(_level.selected) if _level.selected >= 0 else ""


func _remember() -> void:
	Net.player_name = _name.text.strip_edges() if _name.text.strip_edges() != "" else "Expendable"
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("player", "name", _name.text.strip_edges())
	settings.set_value("player", "address", _address.text.strip_edges())
	settings.set_value("player", "level", _level_name())
	settings.save(SETTINGS_PATH)


func _on_solo() -> void:
	if _level_name() == "":
		_status.text = "Create a level first."
		return
	_remember()
	Net.start_solo(_level_name(), "play")


func _on_host() -> void:
	_host_mode("play")


func _on_edit() -> void:
	if not Net.can_network():
		_remember()
		Net.start_solo(_level_name(), "edit")
		return
	_host_mode("edit")


func _host_mode(mode: String) -> void:
	if _level_name() == "":
		_status.text = "Create a level first."
		return
	_remember()
	var error := Net.host(Net.DEFAULT_PORT, _level_name(), mode)
	if error != OK:
		_status.text = "Couldn't host on port %d (%s). Is another copy already hosting?" % [Net.DEFAULT_PORT, error_string(error)]


func _on_create() -> void:
	var level_name := _new_name.text.strip_edges().to_snake_case().validate_filename()
	if level_name == "":
		_status.text = "Name the new level."
		return
	if level_name in LevelData.list():
		_status.text = "There's already a level called %s." % level_name
		return
	var level := LevelData.create(level_name, SIZES[_new_size.selected].chunks, "rock" if _new_fill.selected == 0 else "empty", self)
	var error := level.save()
	if error != OK:
		_status.text = "Couldn't save the level: %s" % error_string(error)
		return
	_fill_levels(level_name)
	_new_panel.visible = false
	_status.text = "Created %s. Press Edit level to start building." % level_name


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
