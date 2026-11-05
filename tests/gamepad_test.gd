extends SceneTree
## Gamepad support (docs/controls.md, section 4), headless:
##   godot --headless --path . --script res://tests/gamepad_test.gd
## Every play action has a pad binding and ui_cancel traded B for Start; Pad.to_key on each button
## and on the left stick's edges (one press per push); Pad.active follows the device; Pad.text and
## the controls sheet's pad names; the settings menu by pad; a pushed left stick walks the player
## and a pushed right stick turns them, with the play-focus flag set and the mouse not captured;
## the pause panel opens with Resume focused, A presses it, Start resumes, and the Player and the
## panel never both act on one Start. Builds a scratch level: one concrete room.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://gamepad_test_levels/"
const LEVEL := "gamepad_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIZE := Vector3i(16, 4, 16)
const ROOM := [Vector3i(8, 20, 8), Vector3i(504, 100, 504)]
const START := Vector3(25.0, 2.0, 25.0)

var _failures := 0
var _pad


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_pad = root.get_node("Pad")
	InputSetup.ensure_actions()
	_check_bindings()
	_check_to_key()
	await _check_active()
	_check_text()
	_check_controls_sheet()
	_check_settings_menu()

	LevelData.save_dir_override = SCRATCH
	_make_level()
	root.get_node("Net").start_solo(LEVEL, "play")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	var lab = current_scene
	var me = lab.local_player()
	await _frames(10)
	me.teleport(START)
	me.rotation.y = 0.0
	await _wait(func() -> bool: return me.on_floor, 3.0)
	await _check_stick_play(me)
	await _check_pause_panel(lab, me)
	await _check_overlay(lab)
	_finish()


func _check_bindings() -> void:
	for action: String in InputSetup.PAD:
		var pads: Array = InputMap.action_get_events(action).filter(func(e: InputEvent) -> bool: return _pad.is_pad(e))
		_check("%s has a pad binding" % action, not pads.is_empty())
	_check("toggle_fly has no pad binding", InputMap.action_get_events("toggle_fly").all(func(e: InputEvent) -> bool: return not _pad.is_pad(e)))
	for action: String in InputSetup.PAD_MENU:
		_check("%s exists" % action, InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty())
	var cancel_buttons: Array = []
	for event in InputMap.action_get_events("ui_cancel"):
		if event is InputEventJoypadButton:
			cancel_buttons.append(event.button_index)
	_check("ui_cancel has Start and not B", cancel_buttons == [JOY_BUTTON_START], str(cancel_buttons))
	_check("ui_accept has A", InputMap.action_get_events("ui_accept").any(func(e: InputEvent) -> bool: return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_A))
	_check("the look actions use the stick deadzone", is_equal_approx(InputMap.action_get_deadzone("look_left"), InputSetup.STICK_DEADZONE))
	_check("fire uses the trigger deadzone", is_equal_approx(InputMap.action_get_deadzone("fire"), InputSetup.TRIGGER_DEADZONE))
	_check("the pad glyph of interact is X", _pad.glyph("interact") == "X", _pad.glyph("interact"))
	_check("the pad glyph of fire is RT", _pad.glyph("fire") == "RT", _pad.glyph("fire"))
	_check("toggle_fly has no glyph", _pad.glyph("toggle_fly") == "")


func _check_to_key() -> void:
	for button: int in _pad.BUTTON_KEYS:
		var key = _pad.to_key(_button(button, true))
		var want: Key = _pad.BUTTON_KEYS[button]
		_check("pad button %d is key %s" % [button, OS.get_keycode_string(want)], key != null and key.keycode == want and key.physical_keycode == want and key.pressed and not key.echo)
		_check("...and its release is nothing", _pad.to_key(_button(button, false)) == null)
	var b = _pad.to_key(_button(JOY_BUTTON_B, true))
	_check("B reads as ui_cancel", b != null and b.is_action_pressed("ui_cancel"))
	_check("LB is no key", _pad.to_key(_button(JOY_BUTTON_LEFT_SHOULDER, true)) == null)
	_check("a key event is no pad key", _pad.to_key(InputEventKey.new()) == null)
	_check("a key event isn't a pad event", not _pad.is_pad(InputEventKey.new()))

	# The left stick: one press per push.
	var push = _motion(JOY_AXIS_LEFT_X, 0.6)
	var key = _pad.to_key(push)
	_check("the stick pushed right is Right", key != null and key.keycode == KEY_RIGHT)
	_check("the same event asked again is the same key", _pad.to_key(push) == key)
	_check("held further it is no new press", _pad.to_key(_motion(JOY_AXIS_LEFT_X, 0.9)) == null)
	_check("between release and press it stays held", _pad.to_key(_motion(JOY_AXIS_LEFT_X, 0.4)) == null)
	_check("let go it is nothing", _pad.to_key(_motion(JOY_AXIS_LEFT_X, 0.1)) == null)
	key = _pad.to_key(_motion(JOY_AXIS_LEFT_X, 0.7))
	_check("pushed again it is Right again", key != null and key.keycode == KEY_RIGHT)
	key = _pad.to_key(_motion(JOY_AXIS_LEFT_X, -0.8))
	_check("swung left it is Left", key != null and key.keycode == KEY_LEFT)
	_pad.to_key(_motion(JOY_AXIS_LEFT_X, 0.0))
	key = _pad.to_key(_motion(JOY_AXIS_LEFT_Y, -0.9))
	_check("pushed up it is Up", key != null and key.keycode == KEY_UP)
	_pad.to_key(_motion(JOY_AXIS_LEFT_Y, 0.0))
	key = _pad.to_key(_motion(JOY_AXIS_LEFT_Y, 0.9))
	_check("pushed down it is Down", key != null and key.keycode == KEY_DOWN)
	_pad.to_key(_motion(JOY_AXIS_LEFT_Y, 0.0))
	_check("the right stick is no key", _pad.to_key(_motion(JOY_AXIS_RIGHT_Y, 1.0)) == null)


func _check_active() -> void:
	_pad.active = false
	Input.parse_input_event(_button(JOY_BUTTON_X, true))
	Input.parse_input_event(_button(JOY_BUTTON_X, false))
	await _idle(2)
	_check("a pad press makes the pad active", _pad.active)
	var key := InputEventKey.new()
	key.keycode = KEY_K
	key.physical_keycode = KEY_K
	key.pressed = true
	Input.parse_input_event(key)
	await _idle(2)
	_check("a key makes it inactive", not _pad.active)
	Input.parse_input_event(_motion(JOY_AXIS_RIGHT_X, 0.1))
	await _idle(2)
	_check("a resting stick's drift doesn't", not _pad.active)
	Input.parse_input_event(_motion(JOY_AXIS_RIGHT_X, 0.8))
	Input.parse_input_event(_motion(JOY_AXIS_RIGHT_X, 0.0))
	await _idle(2)
	_check("a pushed stick does", _pad.active)
	var nudge := InputEventMouseMotion.new()
	nudge.relative = Vector2(1, 0)
	Input.parse_input_event(nudge)
	await _idle(2)
	_check("a nudged mouse doesn't make it inactive", _pad.active)
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(30, 5)
	Input.parse_input_event(move)
	await _idle(2)
	_check("a moved mouse does", not _pad.active)


func _check_text() -> void:
	_pad.active = false
	_check("keys: [E] Open stays", _pad.text("[E] Open") == "[E] Open")
	_pad.active = true
	_check("pad: [E] Open reads [X] Open", _pad.text("[E] Open") == "[X] Open", _pad.text("[E] Open"))
	_check("pad: [SHIFT] reads [Y]", _pad.text("Press [SHIFT] to run") == "Press [Y] to run")
	_pad.active = false


func _check_controls_sheet() -> void:
	_pad.active = true
	var rows := {}
	for row in InputSetup.describe_play_controls():
		rows[row.label] = row.keys
	_check("pad: Shoot is LMB / RT", rows.get("Shoot") == "LMB / RT", str(rows.get("Shoot")))
	_check("pad: Melee is MMB / RB", rows.get("Melee") == "MMB / RB", str(rows.get("Melee")))
	_check("pad: Interact is E / X", rows.get("Interact") == "E / X", str(rows.get("Interact")))
	_check("pad: Move ends in Left stick", str(rows.get("Move")).ends_with(" / Left stick"), str(rows.get("Move")))
	_check("pad: Look names the right stick", rows.get("Look") == "Mouse / arrows / right stick", str(rows.get("Look")))
	_check("pad: ammo lists Y and the D-pad", "Y" in str(rows.get("Change ammo (SHIFT)")).split(" / ") and "D-pad" in str(rows.get("Change ammo (SHIFT)")), str(rows.get("Change ammo (SHIFT)")))
	_check("pad: Pause is Start too", str(rows.get("Pause")).ends_with(" / Start"), str(rows.get("Pause")))
	_check("pad: Controls is Back too", rows.get("Controls") == "F1 / Back", str(rows.get("Controls")))
	_pad.active = false
	if not _pad.connected:
		rows.clear()
		for row in InputSetup.describe_play_controls():
			rows[row.label] = row.keys
		_check("keys only without a pad", rows.get("Melee") == "MMB" and rows.get("Look") == "Mouse / arrows", "%s, %s" % [rows.get("Melee"), rows.get("Look")])


func _check_settings_menu() -> void:
	var settings = root.get_node("GameSettings")
	var value = settings.get_value("stick_sensitivity")
	_check("stick_sensitivity is a setting in range", value is float and value >= settings.SENSITIVITY_RANGE[0] and value <= settings.SENSITIVITY_RANGE[1], str(value))
	var menu_script = load("res://scripts/ui/settings_menu.gd")
	var keys: Array = menu_script.ROWS.map(func(row: Dictionary) -> String: return row.key)
	_check("Stick sensitivity follows Mouse sensitivity", keys.find("stick_sensitivity") == keys.find("mouse_sensitivity") + 1, str(keys))
	_check("it reads 1.00x", menu_script.value_text(menu_script.ROWS[keys.find("stick_sensitivity")], 1.0) == "1.00x")
	var menu = menu_script.create(1)
	root.add_child(menu)
	var closed := [false]
	menu.closed.connect(func() -> void: closed[0] = true)
	menu.selected = 0
	_check("D-pad down is the menu's", menu.handle_key(_button(JOY_BUTTON_DPAD_DOWN, true)))
	_check("...and chooses the next row", menu.selected == 1, str(menu.selected))
	menu.handle_key(_motion(JOY_AXIS_LEFT_Y, -0.9))
	_check("the stick up chooses the row above", menu.selected == 0, str(menu.selected))
	menu.handle_key(_motion(JOY_AXIS_LEFT_Y, 0.0))
	_check("LB isn't the menu's", not menu.handle_key(_button(JOY_BUTTON_LEFT_SHOULDER, true)))
	menu.handle_key(_button(JOY_BUTTON_B, true))
	_check("B closes it", closed[0])
	menu.queue_free()


## The play-focus flag stands in for mouse capture: the sticks walk and turn the player.
func _check_stick_play(me) -> void:
	InputSetup.headless_plays = false
	InputSetup.release_play()
	await _frames(5)
	_check("released, the game isn't playing", not InputSetup.is_playing())
	_pad.active = true
	InputSetup.resume_play()
	await _frames(5)
	_check("resumed on a pad: playing_on_pad", InputSetup.playing_on_pad and InputSetup.is_playing())
	_check("...with the mouse not captured", Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
	var strength := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	Input.parse_input_event(_motion(JOY_AXIS_LEFT_Y, -1.0))
	await _frames(2)
	strength = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_check("a pushed left stick is the move vector (parse_input_event)", strength.y < -0.95, str(strength))
	var from: Vector3 = me.global_position
	await _seconds(0.8)
	var moved := Vector2(me.global_position.x - from.x, me.global_position.z - from.z)
	_check("the left stick walks the player forward", moved.y < -1.0 and absf(moved.x) < 0.3, str(moved))
	Input.parse_input_event(_motion(JOY_AXIS_LEFT_Y, 0.0))
	await _seconds(0.5)
	_check("let go, the player stops", Vector2(me.velocity.x, me.velocity.z).length() < 0.1, str(me.velocity))

	var yaw: float = me.rotation.y
	Input.parse_input_event(_motion(JOY_AXIS_RIGHT_X, 1.0))
	await _seconds(0.5)
	Input.parse_input_event(_motion(JOY_AXIS_RIGHT_X, 0.0))
	await _frames(2)
	var turned: float = yaw - me.rotation.y
	_check("the right stick turns the player right", turned > 0.6 and turned < me.pad_look_speed * 0.5 * 1.5, "%.2f rad" % turned)
	yaw = me.rotation.y
	Input.parse_input_event(_motion(JOY_AXIS_RIGHT_X, 0.5))
	await _seconds(0.5)
	Input.parse_input_event(_motion(JOY_AXIS_RIGHT_X, 0.0))
	await _frames(2)
	var fine: float = yaw - me.rotation.y
	_check("half a push turns far less than half as fast (squared)", fine > 0.0 and fine < turned * 0.3, "%.2f vs %.2f" % [fine, turned])

	InputSetup.release_play()
	await _frames(3)
	var still: Vector3 = me.global_position
	Input.parse_input_event(_motion(JOY_AXIS_LEFT_Y, -1.0))
	await _seconds(0.3)
	Input.parse_input_event(_motion(JOY_AXIS_LEFT_Y, 0.0))
	_check("released, the stick doesn't walk", me.global_position.distance_to(still) < 0.05)


func _check_pause_panel(lab, me) -> void:
	var hud = _find(lab, "LabHud")
	if hud == null:
		_check("the LabHud exists", false)
		return
	_pad.active = true
	InputSetup.release_play()
	await _frames(4)
	var resume = hud._buttons.get_child(0)
	_check("released, the pause panel shows", hud._pause.visible and hud._buttons.visible)
	_check("Resume has the focus", resume.text == "Resume" and resume.has_focus(), str(hud.get_viewport().gui_get_focus_owner()))
	_check("the hint says Start", hud._pause_hint.text.begins_with("Press Start to resume."), hud._pause_hint.text)
	_check("solo, the tree pauses", paused)

	Input.parse_input_event(_button(JOY_BUTTON_START, true))
	Input.parse_input_event(_button(JOY_BUTTON_START, false))
	await _frames(4)
	_check("Start resumes", InputSetup.is_playing() and InputSetup.playing_on_pad and not hud._pause.visible)

	Input.parse_input_event(_button(JOY_BUTTON_START, true))
	Input.parse_input_event(_button(JOY_BUTTON_START, false))
	await _frames(4)
	_check("Start while playing pauses (and stays paused)", not InputSetup.is_playing() and hud._pause.visible)

	# A on the focused Resume.
	Input.parse_input_event(_button(JOY_BUTTON_A, true))
	Input.parse_input_event(_button(JOY_BUTTON_A, false))
	await _frames(4)
	_check("A on Resume resumes", InputSetup.is_playing() and not hud._pause.visible)

	# One Start, both handlers, either order: the panel first (paused), then the Player.
	InputSetup.release_play()
	await _frames(4)
	var start := _button(JOY_BUTTON_START, true)
	_fresh_event()
	hud._input(start)
	me._input(start)
	_check("panel then player: resumed, not released again", InputSetup.is_playing())
	await _frames(4)
	# The Player first (playing), then the panel.
	_fresh_event()
	start = _button(JOY_BUTTON_START, true)
	me._input(start)
	hud._input(start)
	_check("player then panel: paused, not resumed again", not InputSetup.is_playing())
	await _frames(4)
	_check("...and the panel shows", hud._pause.visible)

	# Settings by pad: down to Settings, A opens it, B comes back with Resume focused.
	Input.parse_input_event(_button(JOY_BUTTON_DPAD_DOWN, true))
	Input.parse_input_event(_button(JOY_BUTTON_DPAD_DOWN, false))
	await _frames(2)
	var settings_button = hud._buttons.get_child(1)
	_check("D-pad down moves the focus to Settings", settings_button.has_focus(), str(hud.get_viewport().gui_get_focus_owner()))
	Input.parse_input_event(_button(JOY_BUTTON_A, true))
	Input.parse_input_event(_button(JOY_BUTTON_A, false))
	await _frames(3)
	_check("A opens Settings", hud._settings_menu.visible and not hud._buttons.visible)
	var row: int = hud._settings_menu.selected
	Input.parse_input_event(_button(JOY_BUTTON_DPAD_DOWN, true))
	Input.parse_input_event(_button(JOY_BUTTON_DPAD_DOWN, false))
	await _frames(2)
	_check("D-pad down moves the settings row", hud._settings_menu.selected == row + 1, str(hud._settings_menu.selected))
	Input.parse_input_event(_button(JOY_BUTTON_B, true))
	Input.parse_input_event(_button(JOY_BUTTON_B, false))
	await _frames(3)
	_check("B goes back to the buttons", hud._buttons.visible and not hud._settings_menu.visible and resume.has_focus())
	_check("...still paused", hud._pause.visible and not InputSetup.is_playing())

	_pad.active = false
	await _frames(2)
	_check("on keys the hint says Click", hud._pause_hint.text.begins_with("Click to resume."), hud._pause_hint.text)
	InputSetup.resume_play()
	_check("resumed on keys: no pad flag", not InputSetup.playing_on_pad)
	await _frames(2)


func _check_overlay(lab) -> void:
	var overlay = _find(lab, "ControlsOverlay")
	if overlay == null:
		_check("the controls overlay exists", false)
		return
	_pad.active = false
	if not _pad.connected:
		_check("keys: the sheet's title is F1", overlay._title.text == "Controls (F1)", overlay._title.text)
	Input.parse_input_event(_button(JOY_BUTTON_BACK, true))
	Input.parse_input_event(_button(JOY_BUTTON_BACK, false))
	await _frames(3)
	_check("Back opens the controls sheet", overlay.visible)
	_check("pad: the sheet's title names Back", overlay._title.text == "Controls (F1 / Back)", overlay._title.text)
	var shown := []
	for child in overlay._grid.get_children():
		shown.append(child.text)
	_check("pad: the sheet lists RT", "LMB / RT" in shown, str(shown))
	Input.parse_input_event(_button(JOY_BUTTON_B, true))
	Input.parse_input_event(_button(JOY_BUTTON_B, false))
	await _frames(3)
	_check("B closes it", not overlay.visible)


## Starts a new input event on the root viewport, so its handled flag is fresh for the next calls.
func _fresh_event() -> void:
	root.push_input(_motion(JOY_AXIS_TRIGGER_LEFT, 0.0))


func _button(index: int, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = pressed
	return event


func _motion(axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func _make_level() -> void:
	var level := LevelData.new()
	level.name = LEVEL
	level.settings = LevelData.default_settings(SIZE, "rock")
	var world := VoxelWorld.new()
	world.size_in_chunks = SIZE
	world.immediate_remesh_limit = 0
	world.detach_floating = false
	root.add_child(world)
	world.fill_all(M.CONCRETE)
	world.fill_box(ROOM[0], ROOM[1], M.AIR, false)
	level.voxels = world.get_data()
	world.free()
	var spawn := LevelSchema.new_marker("spawn", START / 0.1, 0.0)
	spawn.id = "spawn_1"
	level.objects[spawn.id] = spawn
	_check("level saves", level.save() == OK)


func _find(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.get_class() == type_name or (child.get_script() and child.get_script().get_global_name() == type_name):
			return child
		var found := _find(child, type_name)
		if found:
			return found
	return null


func _finish() -> void:
	InputSetup.headless_plays = true
	InputSetup.playing_on_pad = false
	print("gamepad_test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _wait(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await physics_frame
	return true


func _seconds(seconds: float) -> void:
	var frames := int(seconds * Engine.physics_ticks_per_second)
	for i in frames:
		await physics_frame


## Input.parse_input_event's events arrive on the next idle frame (several physics frames can
## run first at startup).
func _idle(count: int) -> void:
	for i in count:
		await process_frame


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
