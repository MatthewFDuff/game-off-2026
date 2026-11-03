class_name PaperNumber
extends LineEdit
## A number field: drag left / right on it to scrub the value, or click it to type one. Enter or
## clicking away commits, Esc puts the old value back. `committed` fires once per change (when a
## scrub ends or a typed value is accepted), so a drag sends one edit, not one per step.

signal committed(value: float)

## Pixels of drag per step.
const SCRUB_PIXELS := 6.0
const DRAG_THRESHOLD := 4.0

var min_value := 0.0
var max_value := 100.0
var step := 1.0
var value := 0.0

var _press_x := NAN
var _press_value := 0.0
var _scrubbing := false


static func make(initial: float, low: float, high: float, step_size := 1.0) -> PaperNumber:
	var field := PaperNumber.new()
	field.min_value = low
	field.max_value = high
	field.step = step_size
	field.value = clampf(initial, low, high)
	return field


func _ready() -> void:
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	focus_mode = Control.FOCUS_CLICK
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	if custom_minimum_size.x == 0.0:
		custom_minimum_size.x = 56
	select_all_on_focus = true
	text = _format(value)
	text_submitted.connect(func(_text: String) -> void: release_focus())
	focus_exited.connect(_accept_text)
	set_meta("revert", func() -> void: text = _format(value))


func set_value_quietly(new_value: float) -> void:
	value = clampf(new_value, min_value, max_value)
	if not has_focus():
		text = _format(value)


func _gui_input(event: InputEvent) -> void:
	if has_focus():
		return # Typing: the LineEdit handles it.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_x = event.position.x
			_press_value = value
			_scrubbing = false
		elif not is_nan(_press_x):
			_press_x = NAN
			if _scrubbing:
				committed.emit(value)
			else:
				grab_focus()
		accept_event()
	elif event is InputEventMouseMotion and not is_nan(_press_x):
		var dx: float = event.position.x - _press_x
		if absf(dx) > DRAG_THRESHOLD:
			_scrubbing = true
		if _scrubbing:
			value = clampf(snappedf(_press_value + roundf(dx / SCRUB_PIXELS) * step, step), min_value, max_value)
			text = _format(value)
		accept_event()


func _accept_text() -> void:
	var typed := text.strip_edges()
	if typed.is_valid_float():
		var new_value := clampf(snappedf(typed.to_float(), step), min_value, max_value)
		if new_value != value:
			value = new_value
			committed.emit(value)
	text = _format(value)


func _format(number: float) -> String:
	return str(int(number)) if step >= 1.0 else String.num(number, 2)
