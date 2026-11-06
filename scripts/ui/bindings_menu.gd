class_name BindingsMenu
extends Control
## The bindings menu (docs/controls.md, section 5), opened from the settings menu's Controls row on
## the cubicle's console (at 1x, on the 240 x 160 screen) and the lab's pause panel (at 2x). Built
## like SettingsMenu: the pixel font at 8 * scale px, the amber caret on the chosen row, no panel of
## its own. One row per rebindable action (InputSetup.REBINDABLE): its label, its key or mouse
## binding and its pad binding; the last row is Reset to defaults. Only a window of the rows shows
## at once, scrolled to keep the chosen one in view.
##
## handle_key takes the holder's keys and pad presses (as keys, through Pad.to_key): up / down
## choose a row, Enter (A) on an action row listens, on Reset clears the rebinds, Esc or Backspace
## (B) emits closed. While listening the row reads "press a key or button..." and the menu wants
## the raw events, which handle_key passes to listen when given them; a holder that translates pad
## presses itself (the console) calls listen first while listening is set. The next key, mouse
## button, pad button or trigger pulled past TRIGGER_PRESS becomes the binding of the device it
## came from; the sticks and the wheel are ignored, Esc and Start cancel. A binding another
## rebindable action has on the same device swaps with it. Writes go through
## GameSettings.set_value("bindings"), only the overrides kept.

signal closed

const CARET_COLOR := Color(0.95, 0.68, 0.16)
## The rows' labels, by action.
const LABELS := {
	move_forward = "Forward",
	move_back = "Back",
	move_left = "Left",
	move_right = "Right",
	jump = "Jump",
	crouch = "Crouch",
	fire = "Shoot",
	alt_fire = "Throw flask",
	melee = "Melee",
	cycle_flask = "Cycle flask",
	cycle_ammo = "Next ammo",
	ammo_1 = "Ammo 1",
	ammo_2 = "Ammo 2",
	ammo_3 = "Ammo 3",
	ammo_4 = "Ammo 4",
	interact = "Interact",
	toggle_flashlight = "Flashlight",
	show_controls = "Controls",
}
const RESET_LABEL := "Reset to defaults"
## What the listening row reads.
const LISTEN_TEXT := "press a key or button..."
## A trigger pulled this far binds.
const TRIGGER_PRESS := 0.5
## The two binding columns' width in font pixels (the widest pad name, "D-pad Right", fits; longer
## key names are clipped). Together they hold LISTEN_TEXT.
const COLUMN_WIDTH := 62
## Rows shown at once by scale: the console's small screen, the pause panel.
const SHOWN_AT_1X := 9
const SHOWN_AT_2X := 10

## A bindings menu is listening somewhere: the controls sheet leaves F1 / Back alone meanwhile.
static var capturing := false
## The last event a listening menu took, so a later handler of the same event can skip it.
static var last_taken: InputEvent

## Font pixels per screen pixel: 1 on the console, 2 on the pause panel.
var pixel_scale := 1
## The rows' text color (the console's green by default).
var color := Color(0.75, 0.95, 0.8)
## The actions, in REBINDABLE's order; the row after the last is Reset.
var actions: Array[String] = []
var selected := 0
## The action whose binding the next press becomes, "" when not listening.
var listening := ""
## How many rows show at once (the rest scroll).
var rows_shown := SHOWN_AT_1X
## The first row shown.
var top := 0
var _column := VBoxContainer.new()
var _position: Label
var _key_head: Label
var _pad_head: Label
var _lines: Array[HBoxContainer] = []
var _carets: Array[Label] = []
var _names: Array[Label] = []
var _keys: Array[Label] = []
var _pads: Array[Label] = []
var _listens: Array[Label] = []


## A bindings menu at scale (1 on the console, 2 on the pause panel), in color, showing rows_shown
## rows at once (0: the scale's default).
static func create(scale: int, text_color := Color(0.75, 0.95, 0.8), shown := 0) -> BindingsMenu:
	var menu := BindingsMenu.new()
	menu.pixel_scale = maxi(scale, 1)
	menu.color = text_color
	menu.rows_shown = shown if shown > 0 else (SHOWN_AT_1X if menu.pixel_scale == 1 else SHOWN_AT_2X)
	menu._build()
	return menu


func _get_minimum_size() -> Vector2:
	return _column.get_combined_minimum_size()


func _ready() -> void:
	name = "BindingsMenu"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _carets.is_empty():
		_build()
	_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var settings := _settings()
	if settings and not settings.changed.is_connected(_on_changed):
		settings.changed.connect(_on_changed)
	var pad := _pad()
	if pad and not pad.device_changed.is_connected(_refresh):
		pad.device_changed.connect(_refresh)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			cancel())
	_refresh()


func _exit_tree() -> void:
	cancel()


## The number of rows: one per action, then Reset.
func row_count() -> int:
	return actions.size() + 1


## True on the Reset row.
func on_reset() -> bool:
	return selected >= actions.size()


## Handles a key (or a pad press, as its key) for the menu; true when it was the menu's (the caller
## marks it handled). While listening it is listen's.
func handle_key(event: InputEvent) -> bool:
	if listening != "":
		return listen(event)
	if Pad.is_pad(event):
		event = Pad.to_key(event)
	if not (event is InputEventKey) or not event.pressed:
		return false
	match (event as InputEventKey).keycode:
		KEY_ESCAPE, KEY_BACKSPACE:
			if not event.is_echo():
				closed.emit()
		KEY_UP, KEY_W:
			selected = posmod(selected - 1, row_count())
			_blip()
		KEY_DOWN, KEY_S:
			selected = posmod(selected + 1, row_count())
			_blip()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if event.is_echo():
				return true
			if on_reset():
				reset()
			else:
				start_listening()
		_:
			return false
	_refresh()
	return true


## Listens on the chosen action row: the next bindable press becomes its binding.
func start_listening() -> void:
	if on_reset():
		return
	listening = actions[selected]
	capturing = true
	_blip()
	_refresh()


## Stops listening without a change.
func cancel() -> void:
	if listening == "":
		return
	listening = ""
	capturing = false
	if is_inside_tree():
		_refresh()


## A raw event while listening; true when the menu took it (everything but mouse motion, so nothing
## behind the menu acts on a press meant as a binding). A pressed key, mouse button or pad button,
## or a trigger past TRIGGER_PRESS, binds on its device; Esc and Start cancel; releases, echoes,
## the sticks, the wheel and a pad press on a keyboard-only row are swallowed and listening goes on.
func listen(event: InputEvent) -> bool:
	if listening == "" or event == null or event is InputEventMouseMotion:
		return false
	last_taken = event
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return true
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			cancel()
			return true
	elif event is InputEventJoypadButton:
		if not event.pressed:
			return true
		if event.button_index == JOY_BUTTON_START:
			cancel()
			return true
	elif event is InputEventMouseButton:
		if not event.pressed:
			return true
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) < TRIGGER_PRESS:
			return true
	else:
		return true
	if not InputSetup.bindable(event):
		return true
	var device := InputSetup.device_of(event)
	if not device in InputSetup.REBINDABLE.get(listening, []):
		return true
	var action := listening
	listening = ""
	capturing = false
	bind(action, device, InputSetup.serialize(event))
	return true


## Binds spec (serialized, InputSetup.serialize) to action on device and saves it; a rebindable
## action that already has spec on that device takes action's old binding there instead.
func bind(action: String, device: String, spec: String) -> void:
	var settings := _settings()
	if settings == null or spec == "":
		return
	var bindings: Dictionary = (settings.get_value("bindings") as Dictionary).duplicate(true)
	var current := InputSetup.current_bindings(action, device)
	var old: String = current[0] if not current.is_empty() else InputSetup.default_binding(action, device)
	for other: String in InputSetup.REBINDABLE:
		if other != action and device in InputSetup.REBINDABLE[other] and spec in InputSetup.current_bindings(other, device):
			_put(bindings, other, device, old)
	_put(bindings, action, device, spec)
	settings.set_value("bindings", bindings)
	Sfx.play("ui_click", -8.0, 0.0)


## Every binding back to its default.
func reset() -> void:
	cancel()
	var settings := _settings()
	if settings:
		settings.set_value("bindings", {})
	Sfx.play("ui_click", -8.0, 0.0)


## Stores spec as action's override on device, or drops the override when spec is the default.
static func _put(bindings: Dictionary, action: String, device: String, spec: String) -> void:
	var entry: Dictionary = bindings.get(action, {})
	if spec == InputSetup.default_binding(action, device):
		entry.erase(device)
	else:
		entry[device] = spec
	if entry.is_empty():
		bindings.erase(action)
	else:
		bindings[action] = entry


func _build() -> void:
	if not _carets.is_empty():
		return
	actions.assign(InputSetup.REBINDABLE.keys())
	var font_size := PixelFont.SIZE * pixel_scale
	_column.add_theme_constant_override("separation", 2 * pixel_scale)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	var title_line := HBoxContainer.new()
	title_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := _label("CONTROLS", color, font_size)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_line.add_child(title)
	_position = _label("", color, font_size)
	_position.modulate.a = 0.5
	title_line.add_child(_position)
	_column.add_child(title_line)
	var label_width := 0.0
	for text: String in LABELS.values():
		label_width = maxf(label_width, PixelFont.font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var heads := _line(font_size, label_width, "", "Keys", "Pad")
	_key_head = heads[3]
	_pad_head = heads[4]
	(heads[0] as HBoxContainer).modulate.a = 0.6
	_column.add_child(heads[0])
	for i in row_count():
		var text: String = LABELS.get(actions[i], actions[i]) if i < actions.size() else RESET_LABEL
		var parts := _line(font_size, label_width, text, "", "")
		_column.add_child(parts[0])
		_lines.append(parts[0])
		_carets.append(parts[1])
		_names.append(parts[2])
		_keys.append(parts[3])
		_pads.append(parts[4])
		_listens.append(parts[5])
	_refresh()


## One row: [line, caret, label, key, pad, listen]. The listen label stands in for the two binding
## columns while the row listens.
func _line(font_size: int, label_width: float, text: String, key_text: String, pad_text: String) -> Array:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 3 * pixel_scale)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caret := _label(">", CARET_COLOR, font_size)
	caret.custom_minimum_size.x = font_size
	caret.modulate.a = 0.0
	line.add_child(caret)
	var label := _label(text, color, font_size)
	label.custom_minimum_size.x = label_width
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	var key := _label(key_text, color, font_size)
	var pad := _label(pad_text, color, font_size)
	var listen := _label(LISTEN_TEXT, CARET_COLOR, font_size)
	for column: Label in [key, pad]:
		column.custom_minimum_size.x = COLUMN_WIDTH * pixel_scale
		column.clip_text = true
		line.add_child(column)
	listen.custom_minimum_size.x = (2 * COLUMN_WIDTH + 3) * pixel_scale
	listen.clip_text = true
	listen.visible = false
	line.add_child(listen)
	return [line, caret, label, key, pad, listen]


func _label(text: String, text_color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.label_settings = PixelFont.settings(font_size, text_color, 0, 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return label


func _blip() -> void:
	Sfx.play("ui_blip", -10.0, 0.0)


func _on_changed(key: String) -> void:
	if key == "bindings":
		_refresh()


func _refresh() -> void:
	if _carets.is_empty():
		return
	selected = clampi(selected, 0, row_count() - 1)
	# The window follows the caret.
	var shown := mini(rows_shown, row_count())
	top = clampi(top, selected - shown + 1, selected)
	top = clampi(top, 0, row_count() - shown)
	_position.text = "%d/%d" % [selected + 1, row_count()]
	var pad := _pad()
	var on_pad: bool = pad != null and pad.active
	_key_head.modulate.a = 0.6 if on_pad else 1.0
	_pad_head.modulate.a = 1.0 if on_pad else 0.6
	for i in _carets.size():
		var chosen := i == selected
		_lines[i].visible = i >= top and i < top + shown
		_carets[i].modulate.a = 1.0 if chosen else 0.0
		var dim := Color(1, 1, 1, 1.0 if chosen else 0.7)
		_names[i].modulate = dim
		var is_listening := chosen and listening != ""
		_listens[i].visible = is_listening
		# Reset to defaults has no columns: its label runs on over them.
		_keys[i].visible = not is_listening and i < actions.size()
		_pads[i].visible = _keys[i].visible
		if i >= actions.size():
			continue
		var action := actions[i]
		_keys[i].text = InputSetup.binding_name(action, "kb")
		_keys[i].modulate = dim
		var rebindable_pad: bool = "pad" in InputSetup.REBINDABLE[action]
		_pads[i].text = InputSetup.binding_name(action, "pad")
		# A keyboard-only row shows its fixed pad binding (the left stick) faintly.
		_pads[i].modulate = dim if rebindable_pad else Color(1, 1, 1, 0.35)
	if is_inside_tree():
		update_minimum_size()


## The GameSettings autoload (looked up by path, so the menu also builds where it isn't loaded).
func _settings() -> Node:
	return get_node_or_null("/root/GameSettings") if is_inside_tree() else Engine.get_main_loop().root.get_node_or_null("GameSettings")


func _pad() -> Node:
	return get_node_or_null("/root/Pad") if is_inside_tree() else Engine.get_main_loop().root.get_node_or_null("Pad")
