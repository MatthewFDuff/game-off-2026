class_name SettingsMenu
extends Control
## The settings rows, shared by the cubicle's console (at 1x, on the 240 x 160 screen) and the
## lab's pause panel (at 2x): Orientation, Fullscreen, Mouse and Stick sensitivity, Field of view
## and the three volumes, in the pixel font at 8 * scale px, labels left and values right as "<  value  >",
## the chosen row marked with the amber caret. It is keyboard-driven through handle_key (the
## console feeds it the screen's keys; the pause panel its own): up / down choose a row, left /
## right change it, Enter flips a two-state row (or, on the console's Name row, emits rename),
## Esc or Backspace emits closed; the last row, Controls, emits controls on Enter (the holder opens
## its BindingsMenu, docs/controls.md section 5). A pad works too: handle_key reads its presses as
## keys (Pad.to_key: the D-pad and left stick are the arrows, A Enter, B Esc). With mouse_enabled
## (the pause panel; the console's screen gets no mouse) the mouse works it too: hovering a row
## chooses it, a click on `<` or `>` steps the value, on the value flips a two-state row or steps
## it up, on Controls (or Name) opens it, and a Back line under the rows emits closed. Every change
## goes straight to GameSettings.set_value, which saves and applies it. Hard pixels only: no panel
## of its own, so it takes the background of whatever holds it.

signal closed
## Enter on the Name row (the console's menu only): the holder opens its name field.
signal rename
## Enter on the Controls row: the holder opens the bindings menu.
signal controls

const Settings := preload("res://scripts/game_settings.gd")
const CARET_COLOR := Color(0.95, 0.68, 0.16)
## {key, label, kind}: "choice" rows step through values, "range" rows through GameSettings' range.
const ROWS: Array[Dictionary] = [
	{key = "orientation", label = "Orientation", kind = "choice", values = ["play", "skip"], names = ["Attend", "Skip"]},
	{key = "fullscreen", label = "Fullscreen", kind = "choice", values = [false, true], names = ["Off", "On"]},
	{key = "mouse_sensitivity", label = "Mouse sensitivity", kind = "range", range = Settings.SENSITIVITY_RANGE},
	{key = "stick_sensitivity", label = "Stick sensitivity", kind = "range", range = Settings.SENSITIVITY_RANGE},
	{key = "rumble", label = "Rumble", kind = "choice", values = [false, true], names = ["Off", "On"]},
	{key = "fov", label = "Field of view", kind = "range", range = Settings.FOV_RANGE},
	{key = "volume_master", label = "Master", kind = "range", range = Settings.VOLUME_RANGE},
	{key = "volume_effects", label = "Effects", kind = "range", range = Settings.VOLUME_RANGE},
	{key = "volume_music", label = "Music", kind = "range", range = Settings.VOLUME_RANGE},
]
## The Name row (kind "name"): shows the name on file, Enter emits rename. Only the console has it
## (the pause panel can't type a name).
const NAME_ROW: Dictionary = {key = "name", label = "Name", kind = "name"}
## The Controls row (kind "page"), last on both menus: Enter emits controls.
const CONTROLS_ROW: Dictionary = {key = "controls", label = "Controls", kind = "page"}
## The widest values the rows show, so the arrows line up down the column.
const WIDE_VALUES := ["Attend", "0.00x", "110"]
## What the mouse's Back line reads.
const BACK_LABEL := "< Back"

## Font pixels per screen pixel: 1 on the console, 2 on the pause panel.
var pixel_scale := 1
## The rows' text color (the console's green by default).
var color := Color(0.75, 0.95, 0.8)
## The rows this menu shows: ROWS, NAME_ROW when created with_name, then CONTROLS_ROW.
var rows: Array[Dictionary] = []
var selected := 0
## Mouse support: hover, clicks and the Back line (the pause panel sets it; the console doesn't).
var mouse_enabled := false:
	set(value):
		mouse_enabled = value
		mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
		if _back_line:
			_back_line.visible = value
		_back_hover = false
		if is_inside_tree():
			update_minimum_size()
			_refresh()
var _column := VBoxContainer.new()
var _lines: Array[HBoxContainer] = []
var _back_line: HBoxContainer
var _back_caret: Label
var _back_label: Label
## The mouse is over the Back line.
var _back_hover := false
var _carets: Array[Label] = []
var _names: Array[Label] = []
var _values: Array[Label] = []
var _lefts: Array[Label] = []
var _rights: Array[Label] = []


## A settings menu at scale (1 on the console, 2 on the pause panel), in color; with_name adds the
## Name row (the console).
static func create(scale: int, text_color := Color(0.75, 0.95, 0.8), with_name := false) -> SettingsMenu:
	var menu := SettingsMenu.new()
	menu.pixel_scale = maxi(scale, 1)
	menu.color = text_color
	menu.rows.assign(ROWS)
	if with_name:
		menu.rows.append(NAME_ROW)
	menu.rows.append(CONTROLS_ROW)
	menu._build()
	return menu


func _get_minimum_size() -> Vector2:
	return _column.get_combined_minimum_size()


func _ready() -> void:
	name = "SettingsMenu"
	mouse_filter = Control.MOUSE_FILTER_STOP if mouse_enabled else Control.MOUSE_FILTER_IGNORE
	if _carets.is_empty():
		_build()
	_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var settings := _settings()
	if settings and not settings.changed.is_connected(_on_changed):
		settings.changed.connect(_on_changed)
	_refresh()


## Handles a key (or a pad press, as its key) for the menu; true when it was the menu's (the caller
## marks it handled).
func handle_key(event: InputEvent) -> bool:
	if Pad.is_pad(event):
		event = Pad.to_key(event)
	if not (event is InputEventKey) or not event.pressed:
		return false
	var key: Key = (event as InputEventKey).keycode
	match key:
		KEY_ESCAPE, KEY_BACKSPACE:
			if event.is_echo():
				return true
			closed.emit()
		KEY_UP, KEY_W:
			selected = posmod(selected - 1, rows.size())
			_blip()
		KEY_DOWN, KEY_S:
			selected = posmod(selected + 1, rows.size())
			_blip()
		KEY_LEFT, KEY_A:
			_step(-1)
		KEY_RIGHT, KEY_D:
			_step(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if event.is_echo():
				return true
			if rows[selected].kind == "name":
				rename.emit()
			elif rows[selected].kind == "page":
				controls.emit()
			elif rows[selected].kind == "choice" and rows[selected].values.size() == 2:
				_step(1, true)
		_:
			return false
	_refresh()
	return true


## The value the row shows ("Attend", "On", "1.25x", "80", "7", the name).
static func value_text(row: Dictionary, value: Variant) -> String:
	if row.kind == "name":
		return str(value) if str(value).strip_edges() != "" else "(none)"
	if row.kind == "page":
		return ""
	if row.kind == "choice":
		var index: int = row.values.find(value)
		return str(row.names[index]) if index >= 0 else str(value)
	if row.key in ["mouse_sensitivity", "stick_sensitivity"]:
		return "%.2fx" % float(value)
	return str(int(value))


func _build() -> void:
	if not _carets.is_empty():
		return
	if rows.is_empty():
		rows.assign(ROWS)
		rows.append(CONTROLS_ROW)
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
	for row: Dictionary in rows:
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
		_lines.append(line)
		_carets.append(caret)
		_names.append(label)
		_lefts.append(left)
		_values.append(value)
		_rights.append(right)
	_back_line = HBoxContainer.new()
	_back_line.add_theme_constant_override("separation", 3 * pixel_scale)
	_back_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_caret = _label(">", CARET_COLOR, font_size)
	_back_caret.custom_minimum_size.x = font_size
	_back_line.add_child(_back_caret)
	_back_label = _label(BACK_LABEL, color, font_size)
	_back_line.add_child(_back_label)
	_back_line.visible = mouse_enabled
	var back_gap := Control.new()
	back_gap.custom_minimum_size.y = 2 * pixel_scale
	back_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back_gap.visible = mouse_enabled
	_back_line.visibility_changed.connect(func() -> void: back_gap.visible = _back_line.visible)
	_column.add_child(back_gap)
	_column.add_child(_back_line)
	_refresh()


## The mouse (mouse_enabled): motion chooses the row under it, a left click acts on the part of the
## row under it (_click); every mouse button is taken, so a click on the menu never reaches the
## game behind it (the Player resumes play on a stray click).
func _gui_input(event: InputEvent) -> void:
	if not mouse_enabled:
		return
	if event is InputEventMouseMotion:
		_hover(event.position)
	elif event is InputEventMouseButton:
		accept_event()
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_click(event.position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _back_hover:
		_back_hover = false
		_refresh()


## The row under point (menu coordinates), rows.size() for the Back line, -1 for none.
func row_at(point: Vector2) -> int:
	var gap := pixel_scale # Half the rows' separation: no dead line between rows.
	for i in _lines.size():
		if local_rect(_lines[i]).grow_individual(0, gap, 0, gap).has_point(point):
			return i
	if _back_line.visible and local_rect(_back_line).grow_individual(0, gap, 0, gap).has_point(point):
		return rows.size()
	return -1


## A child control's rect in this menu's coordinates.
func local_rect(control: Control) -> Rect2:
	return Rect2(control.get_global_rect().position - get_global_rect().position, control.size)


func _hover(point: Vector2) -> void:
	var row := row_at(point)
	var back := row == rows.size()
	var changed := back != _back_hover
	_back_hover = back
	if row >= 0 and row < rows.size() and row != selected:
		selected = row
		_blip()
		changed = true
	if changed:
		_refresh()


## A left click: `<` steps down, `>` up, the value flips a two-state row (steps others up), the
## Controls and Name rows open their page, the Back line emits closed; anywhere else on a row just
## chooses it.
func _click(point: Vector2) -> void:
	var row := row_at(point)
	if row < 0:
		return
	if row == rows.size():
		closed.emit()
		return
	selected = row
	var kind: String = rows[row].kind
	var reach := 3 * pixel_scale # The arrows' hit boxes take in the gap beside them.
	if kind == "page":
		controls.emit()
	elif kind == "name":
		rename.emit()
	elif local_rect(_lefts[row]).grow_individual(reach, 0, 0, 0).has_point(point):
		_step(-1)
	elif local_rect(_rights[row]).grow_individual(0, 0, reach, 0).has_point(point):
		_step(1)
	elif local_rect(_values[row]).has_point(point):
		_step(1, kind == "choice" and rows[row].values.size() == 2)
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
	var row: Dictionary = rows[selected]
	if row.kind in ["name", "page"]:
		return
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
	if _back_line:
		_back_caret.modulate.a = 1.0 if _back_hover else 0.0
		_back_label.modulate = Color(1, 1, 1, 1.0 if _back_hover else 0.7)
	for i in _carets.size():
		var row: Dictionary = rows[i]
		var chosen := i == selected
		# One caret: the Back line's while the mouse is on it.
		_carets[i].modulate.a = 1.0 if chosen and not _back_hover else 0.0
		var dim := Color(1, 1, 1, 1.0 if chosen else 0.7)
		_names[i].modulate = dim
		_values[i].modulate = dim
		if settings == null:
			_values[i].text = "-"
			continue
		if row.kind == "page":
			# No value: the arrow on the chosen row says Enter goes on to another page.
			_values[i].text = ""
			_lefts[i].modulate.a = 0.0
			_rights[i].modulate.a = 1.0 if chosen else 0.0
			continue
		var value: Variant = settings.get_value(row.key)
		_values[i].text = value_text(row, value)
		if row.kind == "name":
			# No arrows: Enter opens the name field.
			_lefts[i].modulate.a = 0.0
			_rights[i].modulate.a = 0.0
			continue
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
