extends SceneTree
## Rebinding (docs/controls.md, section 5), headless:
##   godot --headless --path . --script res://tests/bindings_test.gd
## The four serialized kinds round-trip; apply_bindings replaces only the given device's events and
## gives dropped actions their defaults back; the bindings setting drops junk; a BindingsMenu driven
## by keys and raw events: Enter then F rebinds interact's key, a pad button its pad binding, a
## trigger past 0.5 binds and a light pull doesn't, a stick push and the wheel are ignored, a pad
## press on a keyboard-only row is ignored, Esc and Start cancel, a binding another action has
## swaps, Reset clears; the controls sheet, Pad.text and binding_name follow. The bindings setting
## is put back at the end.
##
## Game types are left untyped (see editor_test.gd).

const MENU := "res://scripts/ui/bindings_menu.gd"

var _failures := 0
var _pad
var _settings


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_pad = root.get_node("Pad")
	_settings = root.get_node("GameSettings")
	var kept = _settings.get_value("bindings")
	_settings.set_value("bindings", {})
	_pad.active = false
	_check_serialize()
	_check_apply()
	_check_setting()
	await _check_menu()
	_settings.set_value("bindings", kept)
	_pad.active = false
	print("bindings_test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_serialize() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_X
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 0.8
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_Y
	stick.axis_value = -1.0
	_check("a key serializes", InputSetup.serialize(key) == "key:%d" % KEY_F, InputSetup.serialize(key))
	_check("a mouse button serializes", InputSetup.serialize(mouse) == "mouse:%d" % MOUSE_BUTTON_RIGHT)
	_check("a pad button serializes", InputSetup.serialize(button) == "joy:%d" % JOY_BUTTON_X)
	_check("a trigger serializes", InputSetup.serialize(trigger) == "axis:%d:+1" % JOY_AXIS_TRIGGER_RIGHT, InputSetup.serialize(trigger))
	_check("a stick direction serializes", InputSetup.serialize(stick) == "axis:%d:-1" % JOY_AXIS_LEFT_Y)
	for event in [key, mouse, button, trigger, stick]:
		var spec := InputSetup.serialize(event)
		var back := InputSetup.deserialize(spec)
		_check("%s round-trips" % spec, back != null and back.get_class() == event.get_class() and InputSetup.serialize(back) == spec)
	var key_back = InputSetup.deserialize("key:%d" % KEY_F)
	_check("a key comes back by its physical keycode", key_back.physical_keycode == KEY_F)
	for junk in ["", "key", "key:", "key:x", "key:0", "mouse:99", "joy:-1", "axis:2", "axis:2:0", "axis:99:+1", "pad:1", "key:70:1"]:
		_check("'%s' doesn't deserialize" % junk, InputSetup.deserialize(junk) == null)
	_check("default of interact on keys is E", InputSetup.default_binding("interact", "kb") == "key:%d" % KEY_E)
	_check("default of fire on keys is LMB", InputSetup.default_binding("fire", "kb") == "mouse:%d" % MOUSE_BUTTON_LEFT)
	_check("default of fire on the pad is RT", InputSetup.default_binding("fire", "pad") == "axis:%d:+1" % JOY_AXIS_TRIGGER_RIGHT)
	_check("move keys are keyboard only", InputSetup.REBINDABLE.move_forward == ["kb"])
	_check("look isn't rebindable", not InputSetup.REBINDABLE.has("look_left") and not InputSetup.REBINDABLE.has("ui_cancel"))


func _check_apply() -> void:
	var look_before := InputSetup.current_bindings("look_left", "kb")
	InputSetup.apply_bindings({interact = {kb = "key:%d" % KEY_F}})
	_check("an override replaces the keys", InputSetup.current_bindings("interact", "kb") == ["key:%d" % KEY_F], str(InputSetup.current_bindings("interact", "kb")))
	_check("...and leaves the pad", InputSetup.current_bindings("interact", "pad") == ["joy:%d" % JOY_BUTTON_X])
	_check("binding_name names it", InputSetup.binding_name("interact", "kb") == "F" and InputSetup.binding_name("interact", "pad") == "X")
	_check("other actions are untouched", InputSetup.current_bindings("jump", "kb") == ["key:%d" % KEY_SPACE])
	InputSetup.apply_bindings({crouch = {kb = "key:%d" % KEY_Z, pad = "axis:%d:+1" % JOY_AXIS_TRIGGER_LEFT}})
	_check("interact, dropped, has E back", InputSetup.current_bindings("interact", "kb") == ["key:%d" % KEY_E])
	_check("crouch's two keys give way to one", InputSetup.current_bindings("crouch", "kb") == ["key:%d" % KEY_Z])
	_check("crouch on a trigger takes the trigger deadzone", is_equal_approx(InputMap.action_get_deadzone("crouch"), InputSetup.TRIGGER_DEADZONE))
	InputSetup.apply_bindings({})
	_check("reset: crouch has Ctrl and C", InputSetup.current_bindings("crouch", "kb") == ["key:%d" % KEY_CTRL, "key:%d" % KEY_C], str(InputSetup.current_bindings("crouch", "kb")))
	_check("reset: crouch is B with the button deadzone", InputSetup.current_bindings("crouch", "pad") == ["joy:%d" % JOY_BUTTON_B] and is_equal_approx(InputMap.action_get_deadzone("crouch"), InputSetup.BUTTON_DEADZONE))
	_check("the look keys never change", InputSetup.current_bindings("look_left", "kb") == look_before)
	_check("binding_name of the left stick", InputSetup.binding_name("move_forward", "pad") == "Left stick")
	_check("binding_name of fire", InputSetup.binding_name("fire", "kb") == "LMB" and InputSetup.binding_name("fire", "pad") == "RT")


func _check_setting() -> void:
	_settings.set_value("bindings", {
		interact = {kb = "key:%d" % KEY_F, pad = "bogus", mouse = "mouse:1"},
		nonsense = {kb = "key:%d" % KEY_F},
		jump = "key:70",
		fire = {kb = "mouse:%d" % MOUSE_BUTTON_WHEEL_UP},
		melee = {pad = "joy:%d" % JOY_BUTTON_START, kb = "joy:1"},
		crouch = {kb = "key:%d" % KEY_CTRL},
		alt_fire = {pad = "axis:%d:+1" % JOY_AXIS_LEFT_X},
		move_left = {pad = "joy:0"},
		ammo_1 = {pad = "axis:%d:1" % JOY_AXIS_TRIGGER_LEFT},
	})
	var value: Dictionary = _settings.get_value("bindings")
	var want := {interact = {kb = "key:%d" % KEY_F}, ammo_1 = {pad = "axis:%d:+1" % JOY_AXIS_TRIGGER_LEFT}}
	_check("the setting keeps only real rebinds", value == want, str(value))
	_check("...and applies them", InputSetup.binding_name("interact", "kb") == "F" and InputSetup.binding_name("ammo_1", "pad") == "LT")
	_settings.set_value("bindings", "junk")
	_check("junk is no rebinds", _settings.get_value("bindings") == {} and InputSetup.binding_name("interact", "kb") == "E")


func _check_menu() -> void:
	var menu = load(MENU).create(1)
	root.add_child(menu)
	await process_frame
	var closed := [false]
	menu.closed.connect(func() -> void: closed[0] = true)
	_check("a row per action and Reset", menu.row_count() == InputSetup.REBINDABLE.size() + 1)
	_check("the window shows a few rows", _shown(menu) == menu.rows_shown, str(_shown(menu)))

	# Enter then F: interact's key.
	menu.selected = menu.actions.find("interact")
	_check("Enter is the menu's", menu.handle_key(_key(KEY_ENTER)))
	_check("...and listens", menu.listening == "interact" and load(MENU).capturing)
	_check("the row reads the listening text", menu._listens[menu.selected].visible and not menu._keys[menu.selected].visible)
	_check("the window keeps the row in view", menu._lines[menu.selected].visible)
	menu.handle_key(_key(KEY_ENTER, false))
	_check("a release doesn't bind", menu.listening == "interact")
	_check("F is the menu's", menu.handle_key(_key(KEY_F)))
	_check("F binds interact's key", menu.listening == "" and not load(MENU).capturing and InputSetup.binding_name("interact", "kb") == "F")
	_check("...stored as the only override", _settings.get_value("bindings") == {interact = {kb = "key:%d" % KEY_F}}, str(_settings.get_value("bindings")))
	_check("...and shown", menu._keys[menu.selected].text == "F" and menu._keys[menu.selected].visible)
	_check("the controls sheet follows", _row("Interact").begins_with("F"), _row("Interact"))
	_check("Pad.text names F on keys", _pad.text("[E] Open") == "[F] Open", _pad.text("[E] Open"))

	# A pad button: interact's pad binding; LB was cycle_flask's, which takes X.
	menu.handle_key(_key(KEY_ENTER))
	menu.handle_key(_button(JOY_BUTTON_LEFT_SHOULDER))
	_check("LB binds interact's pad", InputSetup.binding_name("interact", "pad") == "LB" and InputSetup.binding_name("interact", "kb") == "F")
	_check("...and cycle_flask swaps to X", InputSetup.binding_name("cycle_flask", "pad") == "X", InputSetup.binding_name("cycle_flask", "pad"))
	_pad.active = true
	_check("Pad.text names LB on a pad", _pad.text("[E] Open") == "[LB] Open", _pad.text("[E] Open"))
	_check("[SHIFT] still reads Y", _pad.text("[SHIFT]") == "[Y]")
	_pad.active = false

	# A trigger past 0.5 binds; a light pull doesn't.
	menu.selected = menu.actions.find("jump")
	menu.handle_key(_key(KEY_ENTER))
	_check("a light pull is taken", menu.handle_key(_motion(JOY_AXIS_TRIGGER_RIGHT, 0.3)))
	_check("...but doesn't bind", menu.listening == "jump")
	menu.handle_key(_motion(JOY_AXIS_TRIGGER_RIGHT, 0.8))
	_check("RT past 0.5 binds jump", menu.listening == "" and InputSetup.binding_name("jump", "pad") == "RT")
	_check("...with the trigger deadzone", is_equal_approx(InputMap.action_get_deadzone("jump"), InputSetup.TRIGGER_DEADZONE))
	_check("...and fire swaps to A", InputSetup.binding_name("fire", "pad") == "A", InputSetup.binding_name("fire", "pad"))
	menu.handle_key(_motion(JOY_AXIS_TRIGGER_RIGHT, 0.0))

	# The stick and the wheel are ignored; Esc and Start cancel; B binds.
	menu.selected = menu.actions.find("melee")
	menu.handle_key(_key(KEY_ENTER))
	menu.handle_key(_motion(JOY_AXIS_LEFT_X, 0.9))
	menu.handle_key(_motion(JOY_AXIS_RIGHT_Y, -1.0))
	_check("a stick push is ignored", menu.listening == "melee" and InputSetup.binding_name("melee", "pad") == "RB")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	menu.handle_key(wheel)
	_check("the wheel is ignored", menu.listening == "melee" and InputSetup.binding_name("melee", "kb") == "MMB")
	var motion := InputEventMouseMotion.new()
	_check("mouse motion isn't the menu's", not menu.handle_key(motion))
	menu.handle_key(_key(KEY_ESCAPE))
	_check("Esc cancels", menu.listening == "" and not closed[0] and InputSetup.binding_name("melee", "kb") == "MMB")
	menu.handle_key(_key(KEY_ENTER))
	menu.handle_key(_button(JOY_BUTTON_START))
	_check("Start cancels", menu.listening == "" and InputSetup.binding_name("melee", "pad") == "RB")
	menu.handle_key(_key(KEY_ENTER))
	menu.handle_key(_button(JOY_BUTTON_B))
	_check("B binds (it isn't back while listening)", not closed[0] and InputSetup.binding_name("melee", "pad") == "B")
	_check("...and crouch swaps to RB", InputSetup.binding_name("crouch", "pad") == "RB")
	menu.handle_key(_key(KEY_ENTER))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	menu.handle_key(click)
	_check("RMB binds melee's key", InputSetup.binding_name("melee", "kb") == "RMB")
	_check("...and throw swaps to MMB", InputSetup.binding_name("alt_fire", "kb") == "MMB")

	# A keyboard-only row ignores the pad.
	menu.selected = menu.actions.find("move_forward")
	menu.handle_key(_key(KEY_ENTER))
	menu.handle_key(_button(JOY_BUTTON_A))
	_check("a pad press on a move row is ignored", menu.listening == "move_forward" and not _settings.get_value("bindings").has("move_forward"))
	menu.handle_key(_key(KEY_ESCAPE))

	# F on jump: interact had it, and takes Space.
	menu.selected = menu.actions.find("jump")
	_check("the window scrolled back up", menu._lines[menu.selected].visible and not menu._lines[menu.row_count() - 1].visible)
	menu.handle_key(_key(KEY_ENTER))
	menu.handle_key(_key(KEY_F))
	_check("F on jump", InputSetup.binding_name("jump", "kb") == "F")
	_check("...swaps interact to Space", InputSetup.binding_name("interact", "kb") == "Space", InputSetup.binding_name("interact", "kb"))
	_check("...and Pad.text follows", _pad.text("[E] Open") == "[SPACE] Open", _pad.text("[E] Open"))
	# Binding a key back to its default drops the override.
	menu.handle_key(_key(KEY_ENTER))
	menu.handle_key(_key(KEY_SPACE))
	_check("Space back on jump", InputSetup.binding_name("jump", "kb") == "Space" and InputSetup.binding_name("interact", "kb") == "F")
	_check("...drops jump's key override", not _settings.get_value("bindings").get("jump", {}).has("kb"), str(_settings.get_value("bindings")))

	# Reset, at the end of the list.
	menu.selected = 0
	menu.handle_key(_key(KEY_UP))
	_check("up from the top wraps to Reset", menu.on_reset() and menu._lines[menu.selected].visible and not menu._lines[0].visible)
	menu.handle_key(_key(KEY_ENTER))
	_check("Reset clears the rebinds", _settings.get_value("bindings") == {} and InputSetup.binding_name("interact", "kb") == "E" and InputSetup.binding_name("crouch", "pad") == "B")
	_check("...and the rows show the defaults", menu._keys[menu.actions.find("interact")].text == "E")
	_check("Pad.text is [E] again", _pad.text("[E] Open") == "[E] Open" and _pad.text("[SHIFT]") == "[SHIFT]")
	menu.handle_key(_key(KEY_ESCAPE))
	_check("Esc closes the menu", closed[0])
	menu.queue_free()
	await process_frame


func _shown(menu) -> int:
	return menu._lines.filter(func(line: Control) -> bool: return line.visible).size()


## The controls sheet's keys for label.
func _row(label: String) -> String:
	for row in InputSetup.describe_play_controls():
		if row.label == label:
			return row.keys
	return ""


func _key(keycode: Key, pressed := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	return event


func _button(index: int, pressed := true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = pressed
	return event


func _motion(axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
