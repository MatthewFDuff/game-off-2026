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
	for action in MOUSE_BUTTONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for button in MOUSE_BUTTONS[action]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)
