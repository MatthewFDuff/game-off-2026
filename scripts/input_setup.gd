class_name InputSetup
## Registers the game's input actions at startup so they don't need to be maintained in
## project.godot by hand. Actions already defined in the project settings are left alone.

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
	editor_tool_prop = ["7"],
	editor_tool_marker = ["8"],
	editor_rotate = ["R"],
	editor_grid = ["G"],
	editor_free_cursor = ["V"],
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


## True when gameplay input should be live: the mouse is captured, or there is no display to
## capture it on (headless test runs).
static func is_playing() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"


## The play controls for the F1 overlay as [{label, keys}], generated from the input map so it
## never goes stale.
static func describe_play_controls() -> Array[Dictionary]:
	ensure_actions()
	var rows: Array[Dictionary] = []
	for row: Array in PLAY_CONTROLS:
		var keys: Array[String] = []
		for i in range(1, row.size()):
			var action: String = row[i]
			if not InputMap.has_action(action):
				continue
			var names: Array[String] = []
			for event in InputMap.action_get_events(action):
				names.append(_event_name(event))
			if not names.is_empty():
				keys.append(names[0])
		rows.append({label = row[0], keys = " / ".join(keys)})
	return rows


static func _event_name(event: InputEvent) -> String:
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
		InputMap.add_action(action)
		for keycode in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
	for action in EDITOR_KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for spec: String in EDITOR_KEYS[action]:
			InputMap.action_add_event(action, _key_event(spec))
	for action in MOUSE_BUTTONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for button in MOUSE_BUTTONS[action]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)


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
		names.append(spec.replace("BracketLeft", "[").replace("BracketRight", "]").replace("Escape", "Esc"))
	return " / ".join(names)


## A pressed editor shortcut (exact modifiers, no echo).
static func pressed(event: InputEvent, action: String) -> bool:
	return event.is_action_pressed(action, false, true)
