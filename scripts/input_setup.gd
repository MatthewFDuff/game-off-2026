class_name InputSetup
## Registers the game's input actions at startup so they don't need to be maintained in
## project.godot by hand. Actions already defined in the project settings are left alone.

const KEYS := {
	move_forward = [KEY_W],
	move_back = [KEY_S],
	move_left = [KEY_A],
	move_right = [KEY_D],
	jump = [KEY_SPACE],
	sprint = [KEY_SHIFT],
	crouch = [KEY_CTRL, KEY_C],
	toggle_build = [KEY_Q],
	rotate_piece = [KEY_R],
	toggle_fly = [KEY_F],
	toggle_debug = [KEY_F3],
	toggle_flashlight = [KEY_T],
	look_left = [KEY_LEFT],
	look_right = [KEY_RIGHT],
	look_up = [KEY_UP],
	look_down = [KEY_DOWN],
	slot_1 = [KEY_1],
	slot_2 = [KEY_2],
	slot_3 = [KEY_3],
	slot_4 = [KEY_4],
}

const MOUSE_BUTTONS := {
	fire = [MOUSE_BUTTON_LEFT],
	alt_fire = [MOUSE_BUTTON_RIGHT],
}


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
