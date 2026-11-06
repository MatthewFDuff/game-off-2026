class_name InputSetup
## Registers the game's input actions at startup so they don't need to be maintained in
## project.godot by hand. Actions already defined in the project settings are left alone. Play
## actions get their gamepad bindings from PAD (docs/controls.md); the menus' pad actions come from
## PAD_MENU, and ui_cancel trades Godot's joypad B (crouch in play) for Start.

const KEYS := {
	move_forward = [KEY_W],
	move_back = [KEY_S],
	move_left = [KEY_A],
	move_right = [KEY_D],
	jump = [KEY_SPACE],
	cycle_ammo = [KEY_SHIFT],
	ammo_1 = [KEY_1],
	ammo_2 = [KEY_2],
	ammo_3 = [KEY_3],
	ammo_4 = [KEY_4],
	cycle_flask = [KEY_Q],
	show_controls = [KEY_F1],
	crouch = [KEY_CTRL, KEY_C],
	interact = [KEY_E],
	toggle_fly = [KEY_F],
	toggle_flashlight = [KEY_T],
	look_left = [KEY_LEFT],
	look_right = [KEY_RIGHT],
	look_up = [KEY_UP],
	look_down = [KEY_DOWN],
}

## Level editor shortcuts, as "Mod+Key" text (key names as OS.find_keycode_from_string reads them).
## Matched exactly, so Ctrl+D isn't also D. The help overlay and tooltips print these.
const EDITOR_KEYS := {
	editor_tool_select = ["1"],
	editor_tool_room = ["2"],
	editor_tool_box = ["3"],
	editor_tool_brush = ["4"],
	editor_tool_replace = ["5"],
	editor_tool_opening = ["6"],
	editor_tool_prop = ["7"],
	editor_tool_marker = ["8"],
	# The 9th, 10th and 11th place on the tool rail (build levels have more tools).
	editor_tool_slot_9 = ["9"],
	editor_tool_slot_10 = ["0"],
	editor_tool_slot_11 = ["Minus"],
	editor_rotate = ["R"],
	editor_grid = ["G"],
	editor_free_cursor = ["N"],
	editor_view = ["V"],
	# Builder view camera (the walk view uses the same keys to move and fly).
	editor_orbit_left = ["Q"],
	editor_orbit_right = ["E"],
	editor_frame = ["F", "Kp Period"],
	editor_frame_all = ["Home"],
	# Numpad views, as in Blender: 1 / 3 / 7 front, right, top (Ctrl: the other side), 9 turn
	# around, 4 / 6 / 8 / 2 turn and tilt, 5 orthographic, + / - zoom.
	editor_view_front = ["Kp 1"],
	editor_view_back = ["Ctrl+Kp 1"],
	editor_view_right = ["Kp 3"],
	editor_view_left = ["Ctrl+Kp 3"],
	editor_view_top = ["Kp 7", "Ctrl+Kp 7"],
	editor_view_around = ["Kp 9"],
	editor_view_ortho = ["Kp 5"],
	editor_turn_left = ["Kp 4"],
	editor_turn_right = ["Kp 6"],
	editor_tilt_up = ["Kp 8"],
	editor_tilt_down = ["Kp 2"],
	editor_zoom_in = ["Kp Add"],
	editor_zoom_out = ["Kp Subtract"],
	editor_cut_up = ["PageUp"],
	editor_cut_down = ["PageDown"],
	editor_cut_mode = ["C"],
	editor_walls_down = ["H"],
	editor_edit_hidden = ["L"],
	editor_fly = ["F"],
	editor_brush_smaller = ["BracketLeft"],
	editor_brush_bigger = ["BracketRight"],
	editor_move = ["M"],
	editor_duplicate = ["Ctrl+D"],
	editor_delete = ["Delete", "X"],
	editor_undo = ["Ctrl+Z"],
	editor_redo = ["Ctrl+Y", "Ctrl+Shift+Z"],
	editor_save = ["Ctrl+S"],
	editor_playtest = ["F5"],
	editor_help = ["F1"],
	editor_catalog = ["B"],
	editor_back = ["Escape"],
}

const MOUSE_BUTTONS := {
	fire = [MOUSE_BUTTON_LEFT],
	alt_fire = [MOUSE_BUTTON_RIGHT],
	melee = [MOUSE_BUTTON_MIDDLE],
}

## Gamepad bindings of the play actions, by position (Xbox names): a JOY_BUTTON_* is a button, an
## [axis, value] pair a stick or trigger direction. Nothing on R3; the dev keys have none.
const PAD := {
	move_forward = [[JOY_AXIS_LEFT_Y, -1.0]],
	move_back = [[JOY_AXIS_LEFT_Y, 1.0]],
	move_left = [[JOY_AXIS_LEFT_X, -1.0]],
	move_right = [[JOY_AXIS_LEFT_X, 1.0]],
	look_left = [[JOY_AXIS_RIGHT_X, -1.0]],
	look_right = [[JOY_AXIS_RIGHT_X, 1.0]],
	look_up = [[JOY_AXIS_RIGHT_Y, -1.0]],
	look_down = [[JOY_AXIS_RIGHT_Y, 1.0]],
	jump = [JOY_BUTTON_A],
	crouch = [JOY_BUTTON_B],
	fire = [[JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	alt_fire = [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
	melee = [JOY_BUTTON_RIGHT_SHOULDER],
	cycle_flask = [JOY_BUTTON_LEFT_SHOULDER],
	cycle_ammo = [JOY_BUTTON_Y],
	ammo_1 = [JOY_BUTTON_DPAD_UP],
	ammo_2 = [JOY_BUTTON_DPAD_RIGHT],
	ammo_3 = [JOY_BUTTON_DPAD_DOWN],
	ammo_4 = [JOY_BUTTON_DPAD_LEFT],
	interact = [JOY_BUTTON_X],
	toggle_flashlight = [JOY_BUTTON_LEFT_STICK],
	show_controls = [JOY_BUTTON_BACK],
}
## Pad-only actions for the menus' checks and for tests (the menus themselves read keys, through
## Pad.to_key): the face buttons, Start, and the D-pad with the left stick.
const PAD_MENU := {
	pad_accept = [JOY_BUTTON_A],
	pad_back = [JOY_BUTTON_B],
	pad_alt = [JOY_BUTTON_X],
	pad_shift = [JOY_BUTTON_Y],
	pad_start = [JOY_BUTTON_START],
	pad_up = [JOY_BUTTON_DPAD_UP, [JOY_AXIS_LEFT_Y, -1.0]],
	pad_down = [JOY_BUTTON_DPAD_DOWN, [JOY_AXIS_LEFT_Y, 1.0]],
	pad_left = [JOY_BUTTON_DPAD_LEFT, [JOY_AXIS_LEFT_X, -1.0]],
	pad_right = [JOY_BUTTON_DPAD_RIGHT, [JOY_AXIS_LEFT_X, 1.0]],
}
## Deadzones of the actions bound to a stick (the look's squared response starts past it) and to a
## trigger; the menus' stick directions need a firmer push. Buttons keep InputMap's default.
const STICK_DEADZONE := 0.25
const TRIGGER_DEADZONE := 0.3
const MENU_STICK_DEADZONE := 0.5
const BUTTON_DEADZONE := 0.2
const BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_DPAD_UP: "D-pad Up", JOY_BUTTON_DPAD_RIGHT: "D-pad Right",
	JOY_BUTTON_DPAD_DOWN: "D-pad Down", JOY_BUTTON_DPAD_LEFT: "D-pad Left",
}
const AXIS_NAMES := {
	JOY_AXIS_LEFT_X: "Left stick", JOY_AXIS_LEFT_Y: "Left stick",
	JOY_AXIS_RIGHT_X: "Right stick", JOY_AXIS_RIGHT_Y: "Right stick",
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
}

## Play-mode rows of the F1 controls overlay, in display order: [label, actions...].
const PLAY_CONTROLS := [
	["Move", "move_forward", "move_left", "move_back", "move_right"],
	["Look", "look_left", "look_right", "look_up", "look_down"],
	["Shoot", "fire"],
	["Melee", "melee"],
	["Throw flask", "alt_fire"],
	["Cycle flask", "cycle_flask"],
	["Change ammo (SHIFT)", "cycle_ammo", "ammo_1", "ammo_2", "ammo_3", "ammo_4"],
	["Interact", "interact"],
	["Jump", "jump"],
	["Crouch", "crouch"],
	["Flashlight", "toggle_flashlight"],
	["Controls", "show_controls"],
	["Pause", "ui_cancel"],
]
## Rows whose keys read better as words than as the bound keys' names.
const CONTROL_TEXT := {Look = "Mouse / arrows"}
## The same rows' words when the sheet lists the pad too.
const PAD_CONTROL_TEXT := {Look = "Mouse / arrows / right stick"}
## The actions the player can rebind (docs/controls.md, section 5), in the bindings menu's order,
## and the devices each takes: "kb" (a key or mouse button) and "pad" (a pad button or trigger).
## The move keys are keyboard only (the left stick stays); look, pause and the menus' keys are fixed.
const REBINDABLE := {
	move_forward = ["kb"],
	move_back = ["kb"],
	move_left = ["kb"],
	move_right = ["kb"],
	jump = ["kb", "pad"],
	crouch = ["kb", "pad"],
	fire = ["kb", "pad"],
	alt_fire = ["kb", "pad"],
	melee = ["kb", "pad"],
	cycle_flask = ["kb", "pad"],
	cycle_ammo = ["kb", "pad"],
	ammo_1 = ["kb", "pad"],
	ammo_2 = ["kb", "pad"],
	ammo_3 = ["kb", "pad"],
	ammo_4 = ["kb", "pad"],
	interact = ["kb", "pad"],
	toggle_flashlight = ["kb", "pad"],
	show_controls = ["kb", "pad"],
}
## Actions bound only when the game is launched with the dev flag (DEV_FLAG); otherwise they exist
## with no keys, so checking them is harmless and never true.
const DEV_ACTIONS := ["toggle_fly"]
## The launch flag for developer keys (F flies): `godot -- --dev`.
const DEV_FLAG := "--dev"

## The game is being played on a pad: play input is live without the mouse captured (the web
## build can't capture it on a pad press). Set by resume_play, cleared by release_play.
static var playing_on_pad := false
## Headless runs count as playing (no display to capture the mouse on). Tests of the paused state
## set this false to see the game the way a window does.
static var headless_plays := true


## True when the game was launched with the dev flag after `--` (OS.get_cmdline_user_args).
static func is_dev() -> bool:
	return DEV_FLAG in OS.get_cmdline_user_args()


## True when gameplay input should be live: the mouse is captured, the game is being played on a
## pad (playing_on_pad), or there is no display to capture it on (headless test runs).
static func is_playing() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or playing_on_pad \
			or (headless_plays and DisplayServer.get_name() == "headless")


## Gives the game play focus: captures the mouse (not headless) and, when the pad is the device in
## use, sets playing_on_pad, so the game is live even where the capture doesn't take.
static func resume_play() -> void:
	var pad := _pad()
	playing_on_pad = pad == null or pad.active
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Takes play focus away (pause, a menu, the window losing focus): clears playing_on_pad and shows
## the mouse.
static func release_play() -> void:
	playing_on_pad = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## True when the controls sheet lists the pad too: a pad is plugged in or was used last.
static func shows_pad() -> bool:
	var pad := _pad()
	return pad != null and (pad.connected or pad.active)


## The Pad autoload, or null where it isn't loaded.
static func _pad() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Pad") if tree else null


## The play controls for the F1 overlay as [{label, keys}], generated from the input map so it
## never goes stale. With a pad plugged in or in use (shows_pad), each row adds the pad's names
## after the keys ("LMB / RT").
static func describe_play_controls() -> Array[Dictionary]:
	ensure_actions()
	var with_pad := shows_pad()
	var texts: Dictionary = PAD_CONTROL_TEXT if with_pad else CONTROL_TEXT
	var rows: Array[Dictionary] = []
	for row: Array in PLAY_CONTROLS:
		if texts.has(row[0]):
			rows.append({label = row[0], keys = texts[row[0]]})
			continue
		var keys: Array[String] = []
		var pads: Array[String] = []
		for i in range(1, row.size()):
			var action: String = row[i]
			if not InputMap.has_action(action):
				continue
			var names: Array[String] = []
			for event in InputMap.action_get_events(action):
				var pad := pad_name(event)
				if pad == "":
					names.append(_event_name(event))
				elif with_pad and not pad in pads:
					pads.append(pad)
			if not names.is_empty():
				keys.append(names[0])
		# Several D-pad directions on one row read as the D-pad.
		var dpad := pads.filter(func(n: String) -> bool: return n.begins_with("D-pad"))
		if dpad.size() > 1:
			pads.assign(pads.filter(func(n: String) -> bool: return not n.begins_with("D-pad")))
			pads.append("D-pad")
		keys.append_array(pads)
		rows.append({label = row[0], keys = " / ".join(keys)})
	return rows


## A pad event's name by position, Xbox style ("A", "LB", "RT", "D-pad Up", "Left stick"), or ""
## for anything that isn't a pad binding.
static func pad_name(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		return BUTTON_NAMES.get(event.button_index, "")
	if event is InputEventJoypadMotion:
		return AXIS_NAMES.get(event.axis, "")
	return ""


static func _event_name(event: InputEvent) -> String:
	if pad_name(event) != "":
		return pad_name(event)
	if event is InputEventKey:
		var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return OS.get_keycode_string(code)
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
	return event.as_text()


static func ensure_actions() -> void:
	for action in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, _deadzone(action))
		if action in DEV_ACTIONS and not is_dev():
			continue
		for keycode in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
		_add_pad_events(action, PAD)
	for action in EDITOR_KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for spec: String in EDITOR_KEYS[action]:
			InputMap.action_add_event(action, _key_event(spec))
	for action in MOUSE_BUTTONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, _deadzone(action))
		for button in MOUSE_BUTTONS[action]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)
		_add_pad_events(action, PAD)
	for action in PAD_MENU:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, MENU_STICK_DEADZONE)
		_add_pad_events(action, PAD_MENU)
	_pad_ui_actions()


## The deadzone of a play action: its stick's or trigger's, BUTTON_DEADZONE for the rest.
static func _deadzone(action: String) -> float:
	for spec: Variant in PAD.get(action, []):
		if spec is Array:
			return TRIGGER_DEADZONE if spec[0] in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] else STICK_DEADZONE
	return BUTTON_DEADZONE


static func _add_pad_events(action: String, table: Dictionary) -> void:
	for spec: Variant in table.get(action, []):
		if spec is Array:
			var motion := InputEventJoypadMotion.new()
			motion.axis = spec[0]
			motion.axis_value = spec[1]
			InputMap.action_add_event(action, motion)
		else:
			var button := InputEventJoypadButton.new()
			button.button_index = spec
			InputMap.action_add_event(action, button)


## ui_cancel without a joypad B (B crouches in play; menus read it through Pad) and with Start;
## ui_accept with A (Godot 4.6 gives it no pad button), which presses the pause panel's buttons.
## Safe to run again.
static func _pad_ui_actions() -> void:
	var has_start := false
	for event in InputMap.action_get_events("ui_cancel"):
		if event is InputEventJoypadButton:
			if event.button_index == JOY_BUTTON_START:
				has_start = true
			else:
				InputMap.action_erase_event("ui_cancel", event)
	if not has_start:
		var start := InputEventJoypadButton.new()
		start.button_index = JOY_BUTTON_START
		InputMap.action_add_event("ui_cancel", start)
	var has_a := InputMap.action_get_events("ui_accept").any(func(event: InputEvent) -> bool:
		return event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A)
	if not has_a:
		var accept := InputEventJoypadButton.new()
		accept.button_index = JOY_BUTTON_A
		InputMap.action_add_event("ui_accept", accept)


## The device an event belongs to for bindings: "kb" for a key or mouse button, "pad" for a pad
## button or axis, "" for anything else.
static func device_of(event: InputEvent) -> String:
	if event is InputEventKey or event is InputEventMouseButton:
		return "kb"
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return "pad"
	return ""


## A binding as text, the way the bindings setting stores it: "key:<physical keycode>",
## "mouse:<button>", "joy:<button>" or "axis:<axis>:<+1|-1>"; "" for anything else.
static func serialize(event: InputEvent) -> String:
	if event is InputEventKey:
		var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return "key:%d" % code if code != KEY_NONE else ""
	if event is InputEventMouseButton:
		return "mouse:%d" % event.button_index
	if event is InputEventJoypadButton:
		return "joy:%d" % event.button_index
	if event is InputEventJoypadMotion:
		return "axis:%d:%s" % [event.axis, "+1" if event.axis_value >= 0.0 else "-1"]
	return ""


## The event a serialized binding stands for (serialize's inverse), or null when spec isn't one.
static func deserialize(spec: String) -> InputEvent:
	var parts := spec.split(":")
	if parts.size() < 2 or not parts[1].is_valid_int():
		return null
	var number := parts[1].to_int()
	match parts[0]:
		"key":
			if parts.size() != 2 or number <= 0:
				return null
			var key := InputEventKey.new()
			key.physical_keycode = number as Key
			return key
		"mouse":
			if parts.size() != 2 or number < MOUSE_BUTTON_LEFT or number > MOUSE_BUTTON_XBUTTON2:
				return null
			var mouse := InputEventMouseButton.new()
			mouse.button_index = number as MouseButton
			return mouse
		"joy":
			if parts.size() != 2 or number < 0 or number >= JOY_BUTTON_SDL_MAX:
				return null
			var button := InputEventJoypadButton.new()
			button.button_index = number as JoyButton
			return button
		"axis":
			if parts.size() != 3 or number < 0 or number >= JOY_AXIS_SDL_MAX or not parts[2] in ["+1", "-1", "1"]:
				return null
			var motion := InputEventJoypadMotion.new()
			motion.axis = number as JoyAxis
			motion.axis_value = -1.0 if parts[2] == "-1" else 1.0
			return motion
	return null


## True for an event that can be a binding: a key, a mouse button other than the wheel, a pad
## button or a trigger pulled forward. Esc and Start cancel the bindings menu's listening, so they
## never bind; the sticks are refused (they move and look).
static func bindable(event: InputEvent) -> bool:
	if event is InputEventKey:
		var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return code != KEY_NONE and code != KEY_ESCAPE
	if event is InputEventMouseButton:
		return not event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
	if event is InputEventJoypadButton:
		return event.button_index != JOY_BUTTON_START
	if event is InputEventJoypadMotion:
		return event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] and event.axis_value > 0.0
	return false


## The default binding of action on device ("kb" or "pad"), serialized: its first key or mouse
## button, or its first pad binding; "" when it has none there.
static func default_binding(action: String, device: String) -> String:
	var specs := _default_specs(action, device)
	return specs[0] if not specs.is_empty() else ""


## Every default binding of action on device, serialized (crouch has two keys).
static func _default_specs(action: String, device: String) -> Array[String]:
	var specs: Array[String] = []
	if device == "kb":
		for button in MOUSE_BUTTONS.get(action, []):
			specs.append("mouse:%d" % button)
		for keycode in KEYS.get(action, []):
			specs.append("key:%d" % keycode)
	elif device == "pad":
		for spec: Variant in PAD.get(action, []):
			if spec is Array:
				specs.append("axis:%d:%s" % [spec[0], "+1" if spec[1] >= 0.0 else "-1"])
			else:
				specs.append("joy:%d" % spec)
	return specs


## The bindings in effect on action for device, serialized, in the input map's order.
static func current_bindings(action: String, device: String) -> Array[String]:
	var specs: Array[String] = []
	if InputMap.has_action(action):
		for event in InputMap.action_get_events(action):
			if device_of(event) == device:
				specs.append(serialize(event))
	return specs


## Applies the player's bindings (the bindings setting: action -> {kb?, pad?}, serialized): each
## override replaces that device's events on the action, and every rebindable action or device
## without one gets its defaults back, so apply_bindings({}) is Reset. Creates the actions first
## (ensure_actions), so it works however early it runs. Actions outside REBINDABLE are untouched.
static func apply_bindings(overrides: Dictionary) -> void:
	ensure_actions()
	for action: String in REBINDABLE:
		if not InputMap.has_action(action):
			continue
		var entry: Variant = overrides.get(action, {})
		for device: String in REBINDABLE[action]:
			var desired := _default_specs(action, device)
			if entry is Dictionary and entry.has(device):
				var spec := str(entry[device])
				var event := deserialize(spec)
				if event != null and device_of(event) == device:
					desired = [spec]
			if current_bindings(action, device) == desired:
				continue
			for event in InputMap.action_get_events(action):
				if device_of(event) == device:
					InputMap.action_erase_event(action, event)
			for spec in desired:
				InputMap.action_add_event(action, deserialize(spec))
		# A trigger presses at its own deadzone, whatever the action had before.
		var on_trigger := current_bindings(action, "pad").any(func(spec: String) -> bool:
			return spec.begins_with("axis:%d:" % JOY_AXIS_TRIGGER_LEFT) or spec.begins_with("axis:%d:" % JOY_AXIS_TRIGGER_RIGHT))
		InputMap.action_set_deadzone(action, TRIGGER_DEADZONE if on_trigger else _deadzone(action))


## The name of action's binding on device ("kb" or "pad") for people: "E", "LMB", "Shift", "X",
## "RT", "Left stick"; "" when it has none there.
static func binding_name(action: String, device: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for event in InputMap.action_get_events(action):
		if device_of(event) == device:
			return _event_name(event)
	return ""


static func _key_event(spec: String) -> InputEventKey:
	var event := InputEventKey.new()
	var parts := spec.split("+")
	event.physical_keycode = OS.find_keycode_from_string(parts[-1])
	event.ctrl_pressed = "Ctrl" in parts
	event.shift_pressed = "Shift" in parts
	event.alt_pressed = "Alt" in parts
	return event


## An editor action's keys for people: "Ctrl+Y / Ctrl+Shift+Z", "[".
static func describe(action: String) -> String:
	var names: Array[String] = []
	for spec: String in EDITOR_KEYS.get(action, []):
		names.append(spec.replace("BracketLeft", "[").replace("BracketRight", "]").replace("Escape", "Esc")
				.replace("PageUp", "PgUp").replace("PageDown", "PgDn").replace("Kp Period", "Num .").replace("Kp Add", "Num +")
				.replace("Kp Subtract", "Num -").replace("Kp ", "Num ").replace("Minus", "-"))
	return " / ".join(names)


## A pressed editor shortcut (exact modifiers, no echo).
static func pressed(event: InputEvent, action: String) -> bool:
	return event.is_action_pressed(action, false, true)
