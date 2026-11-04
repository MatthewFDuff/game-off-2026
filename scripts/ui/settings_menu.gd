class_name SettingsMenu
extends Control
## The settings rows, shared by the cubicle's console (at 1x, on the 240 x 160 screen) and the
## lab's pause panel (at 2x): Orientation, Fullscreen, Mouse sensitivity, Field of view and the
## three volumes, in the pixel font at 8 * scale px, labels left and values right as "<  value  >",
## the chosen row marked with the amber caret. It is keyboard-driven through handle_key (the
## console feeds it the screen's keys; the pause panel its own): up / down choose a row, left /
## right change it, Enter flips a two-state row, Esc emits closed. Every change goes straight to
## GameSettings.set_value, which saves and applies it. Hard pixels only: no panel of its own, so
## it takes the background of whatever holds it.

signal closed

const Settings := preload("res://scripts/game_settings.gd")
const CARET_COLOR := Color(0.95, 0.68, 0.16)
## {key, label, kind}: "choice" rows step through values, "range" rows through GameSettings' range.
const ROWS: Array[Dictionary] = [
	{key = "orientation", label = "Orientation", kind = "choice", values = ["play", "skip"], names = ["Attend", "Skip"]},
	{key = "fullscreen", label = "Fullscreen", kind = "choice", values = [false, true], names = ["Off", "On"]},
	{key = "mouse_sensitivity", label = "Mouse sensitivity", kind = "range", range = Settings.SENSITIVITY_RANGE},
	{key = "fov", label = "Field of view", kind = "range", range = Settings.FOV_RANGE},
	{key = "volume_master", label = "Master", kind = "range", range = Settings.VOLUME_RANGE},
	{key = "volume_effects", label = "Effects", kind = "range", range = Settings.VOLUME_RANGE},
	{key = "volume_music", label = "Music", kind = "range", range = Settings.VOLUME_RANGE},
]
## The widest values the rows show, so the arrows line up down the column.
const WIDE_VALUES := ["Attend", "0.00x", "110"]

## Font pixels per screen pixel: 1 on the console, 2 on the pause panel.
var pixel_scale := 1
## The rows' text color (the console's green by default).
var color := Color(0.75, 0.95, 0.8)
var selected := 0
var _column := VBoxContainer.new()
var _carets: Array[Label] = []
var _names: Array[Label] = []
var _values: Array[Label] = []
var _lefts: Array[Label] = []
var _rights: Array[Label] = []


## A settings menu at scale (1 on the console, 2 on the pause panel), in color.
static func create(scale: int, text_color := Color(0.75, 0.95, 0.8)) -> SettingsMenu:
	var menu := SettingsMenu.new()
	menu.pixel_scale = maxi(scale, 1)
	menu.color = text_color
	menu._build()
	return menu


func _get_minimum_size() -> Vector2:
	return _column.get_combined_minimum_size()


func _ready() -> void:
	name = "SettingsMenu"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _carets.is_empty():
		_build()
	_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var settings := _settings()
	if settings and not settings.changed.is_connected(_on_changed):
		settings.changed.connect(_on_changed)
	_refresh()


## Handles a key for the menu; true when it was the menu's (the caller marks it handled).
func handle_key(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed:
		return false
	var key: Key = (event as InputEventKey).keycode
	match key:
		KEY_ESCAPE:
			if event.is_echo():
				return true
			closed.emit()
		KEY_UP, KEY_W:
			selected = posmod(selected - 1, ROWS.size())
			_blip()
		KEY_DOWN, KEY_S:
			selected = posmod(selected + 1, ROWS.size())
			_blip()
		KEY_LEFT, KEY_A:
			_step(-1)
		KEY_RIGHT, KEY_D:
			_step(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if event.is_echo():
				return true
			if ROWS[selected].kind == "choice" and ROWS[selected].values.size() == 2:
				_step(1, true)
		_:
			return false
	_refresh()
	return true


## The value the row shows ("Attend", "On", "1.25x", "80", "7").
static func value_text(row: Dictionary, value: Variant) -> String:
	if row.kind == "choice":
		var index: int = row.values.find(value)
		return str(row.names[index]) if index >= 0 else str(value)
	if row.key == "mouse_sensitivity":
		return "%.2fx" % float(value)
	return str(int(value))


func _build() -> void:
	if not _carets.is_empty():
		return
	var font_size := PixelFont.SIZE * pixel_scale
	_column.add_theme_constant_override("separation", 2 * pixel_scale)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	var title := _label("SETTINGS", color, font_size)
	_column.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size.y = 2 * pixel_scale
	_column.add_child(gap)
	var value_width := 0.0
	for text: String in WIDE_VALUES:
		value_width = maxf(value_width, PixelFont.font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	for row: Dictionary in ROWS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 3 * pixel_scale)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var caret := _label(">", CARET_COLOR, font_size)
		caret.custom_minimum_size.x = font_size
		line.add_child(caret)
		var label := _label(str(row.label), color, font_size)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		var spacer := Control.new()
		spacer.custom_minimum_size.x = 4 * pixel_scale
		line.add_child(spacer)
		var left := _label("<", color, font_size)
		line.add_child(left)
		var value := _label("", color, font_size)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.custom_minimum_size.x = value_width + 2 * pixel_scale
		line.add_child(value)
		var right := _label(">", color, font_size)
		line.add_child(right)
		_column.add_child(line)
		_carets.append(caret)
		_names.append(label)
		_lefts.append(left)
		_values.append(value)
		_rights.append(right)
	_refresh()


func _label(text: String, text_color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.label_settings = PixelFont.settings(font_size, text_color, 0, 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return label


## Moves the chosen row's value by direction steps (wrapping for a two-state row when wrap).
func _step(direction: int, wrap := false) -> void:
	var settings := _settings()
	if settings == null:
		return
	var row: Dictionary = ROWS[selected]
	var current: Variant = settings.get_value(row.key)
	var next: Variant = current
	if row.kind == "choice":
		var index: int = maxi(row.values.find(current), 0) + direction
		index = posmod(index, row.values.size()) if wrap else clampi(index, 0, row.values.size() - 1)
		next = row.values[index]
	else:
		var range_: Array = row.range
		next = clampf(float(current) + direction * float(range_[2]), float(range_[0]), float(range_[1]))
	if next == current:
		return
	settings.set_value(row.key, next)
	_blip()


func _blip() -> void:
	Sfx.play("ui_blip", -10.0, 0.0)


func _on_changed(_key: String) -> void:
	_refresh()


func _refresh() -> void:
	var settings := _settings()
	for i in _carets.size():
		var row: Dictionary = ROWS[i]
		var chosen := i == selected
		_carets[i].modulate.a = 1.0 if chosen else 0.0
		var dim := Color(1, 1, 1, 1.0 if chosen else 0.7)
		_names[i].modulate = dim
		_values[i].modulate = dim
		if settings == null:
			_values[i].text = "-"
			continue
		var value: Variant = settings.get_value(row.key)
		_values[i].text = value_text(row, value)
		var at_min: bool
		var at_max: bool
		if row.kind == "choice":
			var index: int = row.values.find(value)
			at_min = index <= 0
			at_max = index >= row.values.size() - 1
		else:
			var range_: Array = row.range
			at_min = float(value) <= float(range_[0])
			at_max = float(value) >= float(range_[1])
		# The arrows show only on the chosen row, and only toward a value there is.
		_lefts[i].modulate.a = 1.0 if chosen and not at_min else (0.25 if chosen else 0.0)
		_rights[i].modulate.a = 1.0 if chosen and not at_max else (0.25 if chosen else 0.0)


## The GameSettings autoload (looked up by path, so the menu also builds where it isn't loaded).
func _settings() -> Node:
	return get_node_or_null("/root/GameSettings") if is_inside_tree() else Engine.get_main_loop().root.get_node_or_null("GameSettings")
