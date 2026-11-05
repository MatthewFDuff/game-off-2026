extends Node
## Gamepad autoload (`Pad`, docs/controls.md section 4.2): knows whether the player is using a pad
## and translates pad presses into the keys the keyboard-driven menus expect, so every handle_key
## gets the pad for free. active is true once the last input was a pad button or a stick past its
## deadzone, and false again on a key, a mouse button or real mouse movement; connected follows
## the plugged-in pads; device_changed fires when either changes. It watches the root window's
## window_input signal, which sees every event before any node can handle it, even while paused.

## active or connected changed.
signal device_changed

## The pad buttons and the keys they stand for in the menus.
const BUTTON_KEYS := {
	JOY_BUTTON_A: KEY_ENTER,
	JOY_BUTTON_B: KEY_ESCAPE,
	JOY_BUTTON_START: KEY_ESCAPE,
	JOY_BUTTON_Y: KEY_SHIFT,
	JOY_BUTTON_X: KEY_BACKSPACE,
	JOY_BUTTON_DPAD_UP: KEY_UP,
	JOY_BUTTON_DPAD_DOWN: KEY_DOWN,
	JOY_BUTTON_DPAD_LEFT: KEY_LEFT,
	JOY_BUTTON_DPAD_RIGHT: KEY_RIGHT,
}
## The left stick presses an arrow when it crosses PRESS and lets go of it under RELEASE, so a held
## stick is one press.
const STICK_PRESS := 0.5
const STICK_RELEASE := 0.3
## A stick or trigger past this counts as using the pad (resting sticks drift a little).
const ACTIVE_DEADZONE := 0.3
## Mouse motion shorter than this (pixels) is a bumped desk, not the player switching back.
const MOUSE_SLOP := 2.0
## The prompts' key tokens and what they read on a pad.
const TOKENS := {"[E]": "[X]", "[SHIFT]": "[Y]"}

## The last input came from a pad. Tests may set it directly.
var active := false:
	set(value):
		if value != active:
			active = value
			device_changed.emit()
## A pad is plugged in.
var connected := false

## The left stick's arrows currently held down: {Key: bool}.
var _stick := {KEY_UP: false, KEY_DOWN: false, KEY_LEFT: false, KEY_RIGHT: false}
## The last event translated and its key, so every handler asking about the same event gets the
## same answer (a stick edge is only an edge once).
var _last_event: InputEvent
var _last_key: InputEventKey


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputSetup.ensure_actions() # The pad actions and ui_cancel's Start, before any menu asks.
	connected = not Input.get_connected_joypads().is_empty()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	get_tree().root.window_input.connect(_watch)


## True for an event from a pad (a button or a stick / trigger axis).
static func is_pad(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


## A pressed pad button or a left-stick edge as the key the menus expect, with keycode and
## physical_keycode both set (so is_action_pressed("ui_cancel") matches too), or null for anything
## else: A Enter, B and Start Escape, Y Shift, X Backspace, the D-pad and the left stick arrows.
func to_key(event: InputEvent) -> InputEventKey:
	if event == null or not is_pad(event):
		return null
	if event != _last_event:
		_last_event = event
		_last_key = _translate(event)
	return _last_key


## s with the prompts' key tokens for the device in use: "[E] Open" reads "[X] Open" on a pad,
## "[SHIFT]" reads "[Y]".
func text(s: String) -> String:
	if not active:
		return s
	for token: String in TOKENS:
		s = s.replace(token, TOKENS[token])
	return s


## The pad name of action's first pad binding ("X", "RT", "Start"), "" when it has none.
func glyph(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for event in InputMap.action_get_events(action):
		if is_pad(event):
			return InputSetup.pad_name(event)
	return ""


func _translate(event: InputEvent) -> InputEventKey:
	if event is InputEventJoypadButton:
		if not event.pressed or not BUTTON_KEYS.has(event.button_index):
			return null
		return _key(BUTTON_KEYS[event.button_index])
	var motion := event as InputEventJoypadMotion
	var pressed: Key = KEY_NONE
	if motion.axis == JOY_AXIS_LEFT_X:
		pressed = _edge(KEY_RIGHT, motion.axis_value, pressed)
		pressed = _edge(KEY_LEFT, -motion.axis_value, pressed)
	elif motion.axis == JOY_AXIS_LEFT_Y:
		pressed = _edge(KEY_DOWN, motion.axis_value, pressed)
		pressed = _edge(KEY_UP, -motion.axis_value, pressed)
	return _key(pressed) if pressed != KEY_NONE else null


## Updates one stick direction from its deflection; returns it when it just crossed STICK_PRESS,
## otherwise pressed unchanged.
func _edge(direction: Key, value: float, pressed: Key) -> Key:
	if not _stick[direction] and value >= STICK_PRESS:
		_stick[direction] = true
		return direction
	if _stick[direction] and value < STICK_RELEASE:
		_stick[direction] = false
	return pressed


static func _key(keycode: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.physical_keycode = keycode
	key.pressed = true
	key.echo = false
	return key


func _watch(event: InputEvent) -> void:
	# Every pad event is translated as it arrives, so the stick's edges stay right even while no
	# menu is asking (walking with the stick held, then pausing, isn't a press).
	to_key(event)
	if event is InputEventJoypadButton:
		if event.pressed:
			active = true
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > ACTIVE_DEADZONE:
			active = true
	elif event is InputEventKey or event is InputEventMouseButton:
		active = false
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > MOUSE_SLOP:
		active = false


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	var now := not Input.get_connected_joypads().is_empty()
	if now != connected:
		connected = now
		device_changed.emit()
