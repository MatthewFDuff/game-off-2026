extends SceneTree
## The cubicle on a gamepad (docs/controls.md, sections 2.1 to 2.3 and 4.1 to 4.3), headless:
##   godot --headless --path . --script res://tests/pad_console_test.gd
## Builds the cubicle into a scratch folder like cubicle_test and drives it with pad events
## (Input.parse_input_event, as a pad would send them) and the play-focus flag in place of mouse
## capture: A in the room gives play focus, X on the computer zooms onto SPLASH, Y signs in, arcade
## entry spells a name (up / down turn and wrap, the stick too, right adds, left and X erase) and A
## submits it to MAIN; the D-pad moves the caret, A opens SINGLEPLAYER, B backs out, the settings
## menu takes the pad, B from MAIN zooms out; the footers and prompts read the pad's buttons while
## it is in use and the keys' when not; APPLY FOR JOB by pad runs the log (Y advances, A opens
## the email, X declines, A at the go-back prompt returns to it, B does nothing there, A accepts);
## B at the go-back prompt finishes declined; Y steps off NEW LEVEL's name field; Start in the
## room opens the clock-out prompt and B stays; X and B close a note. The settings it touches are
## put back at the end.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://pad_console_test_levels/"
const SAVE_SCRATCH := "user://pad_console_test_shift/"
const Builder := preload("res://scripts/tools/build_cubicle.gd")
const SCENE := "res://scenes/cubicle.tscn"
const KEPT := ["name", "orientation"]

var _failures := 0
var _pad


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_pad = root.get_node("Pad")
	InputSetup.ensure_actions()
	var settings = root.get_node("GameSettings")
	var kept := {}
	for key in KEPT:
		kept[key] = settings.get_value(key)
	settings.set_value("name", "")
	settings.set_value("orientation", "play")
	LevelData.save_dir_override = SCRATCH
	ShiftSave.dir_override = SAVE_SCRATCH
	ShiftSave.clear()
	var built: Dictionary = Builder.build(root)
	_check("the cubicle builds", built.error == OK, error_string(built.error))
	built.world.free()

	# The room without play focus, the way a window sees it.
	InputSetup.headless_plays = false
	InputSetup.release_play()
	_pad.active = true
	var cubicle = _new_cubicle()
	await _frames(20)
	var player = cubicle.player
	_check("no play focus at the start", not InputSetup.is_playing())
	_check("the hint offers A", cubicle._click_hint.visible and cubicle._click_hint.text == cubicle.CLICK_HINT_PAD, cubicle._click_hint.text)
	await _press(JOY_BUTTON_A)
	_check("A in the room gives play focus on the pad", InputSetup.is_playing() and InputSetup.playing_on_pad)
	await _frames(1)
	_check("...and the hint goes", not cubicle._click_hint.visible)
	await _wait_until(func() -> bool: return player.on_floor and cubicle.aimed() == "monitor", 3.0)
	_check("the use prompt names X", cubicle._use_prompt.text == "[X] Use computer", cubicle._use_prompt.text)

	# The console: SPLASH, SIGN IN with arcade entry, MAIN.
	await _press(JOY_BUTTON_X)
	var screen := await _wait_until(func() -> bool: return cubicle.state == cubicle.State.SCREEN, 2.0)
	_check("X on the computer zooms onto SPLASH", screen and cubicle.page == cubicle.Page.SPLASH)
	_check("...and takes play focus away", not InputSetup.is_playing())
	_check("the splash footer reads the pad", cubicle._footer.text == "Y: sign in    B: step away", cubicle._footer.text)
	_check("the splash says Press Y", _texts(cubicle).has(cubicle.SIGN_IN_PROMPT_PAD), str(_texts(cubicle)))
	await _press(JOY_BUTTON_Y)
	_check("Y shows SIGN IN", cubicle.page == cubicle.Page.SIGN_IN and cubicle._name_field == "")
	_check("the field footer reads the pad", cubicle._footer.text == "turn: up/down    A: select    B: back", cubicle._footer.text)
	await _press(JOY_BUTTON_DPAD_UP)
	_check("up on an empty field starts at A", cubicle._name_field == "A", cubicle._name_field)
	await _press(JOY_BUTTON_DPAD_UP)
	_check("up turns A to B", cubicle._name_field == "B", cubicle._name_field)
	await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_DPAD_DOWN)
	_check("down from A is a space", cubicle._name_field == " ", "'%s'" % cubicle._name_field)
	await _press(JOY_BUTTON_DPAD_DOWN)
	_check("down from the space wraps to 9 (a name takes no . - :)", cubicle._name_field == "9", cubicle._name_field)
	await _press(JOY_BUTTON_DPAD_UP)
	await _stick(JOY_AXIS_LEFT_Y, -0.9)
	_check("up wraps back, the stick turns too", cubicle._name_field == "A", cubicle._name_field)
	await _press(JOY_BUTTON_DPAD_RIGHT)
	_check("right adds an A", cubicle._name_field == "AA", cubicle._name_field)
	await _press(JOY_BUTTON_DPAD_UP)
	_check("up turns the last character", cubicle._name_field == "AB", cubicle._name_field)
	var block = cubicle._cursor_block
	_check("the caret block sits on it", block != null and block.get_child_count() == 1 and block.get_child(0).text == "B")
	await _press(JOY_BUTTON_DPAD_LEFT)
	_check("left erases", cubicle._name_field == "A", cubicle._name_field)
	await _press(JOY_BUTTON_DPAD_RIGHT)
	await _press(JOY_BUTTON_DPAD_RIGHT)
	await _press(JOY_BUTTON_X)
	_check("X erases too", cubicle._name_field == "AA", cubicle._name_field)
	await _press(JOY_BUTTON_DPAD_UP)
	await _press(JOY_BUTTON_A)
	_check("A submits the name: MAIN", cubicle.page == cubicle.Page.MAIN and settings.get_value("name") == "AB", str(settings.get_value("name")))

	# MAIN by pad.
	_check("the MAIN footer reads the pad", cubicle._footer.text == "A: select    B: step away", cubicle._footer.text)
	await _press(JOY_BUTTON_DPAD_DOWN)
	_check("D-pad down moves the caret", cubicle.cursor == 1, str(cubicle.cursor))
	await _press(JOY_BUTTON_DPAD_UP)
	_check("D-pad up moves it back", cubicle.cursor == 0, str(cubicle.cursor))
	await _press(JOY_BUTTON_A)
	_check("A opens SINGLEPLAYER, the caret on APPLY FOR JOB", cubicle.page == cubicle.Page.SINGLEPLAYER and cubicle._current_item().text == cubicle.NEW_GAME)
	_check("its footer reads the pad", cubicle._footer.text == "A: select    B: back", cubicle._footer.text)
	await _press(JOY_BUTTON_B)
	_check("B backs to MAIN", cubicle.page == cubicle.Page.MAIN)
	await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_DPAD_DOWN)
	await _press(JOY_BUTTON_A)
	_check("A on SETTINGS opens the settings menu", cubicle.page == cubicle.Page.SETTINGS and cubicle._settings_menu != null)
	_check("its footer reads the pad", cubicle._footer.text == "arrows: change    B: back", cubicle._footer.text)
	var row: int = cubicle._settings_menu.selected
	await _press(JOY_BUTTON_DPAD_DOWN)
	_check("D-pad down moves the settings row", cubicle._settings_menu.selected == row + 1, str(cubicle._settings_menu.selected))
	await _press(JOY_BUTTON_B)
	_check("B closes the settings: MAIN", cubicle.page == cubicle.Page.MAIN)

	# The keys' wording comes back with the keyboard.
	_pad.active = false
	_check("keys: the MAIN footer", cubicle._footer.text == "arrows    SHIFT: select    Esc: step away", cubicle._footer.text)
	_check("keys: the clock-out keys", cubicle._clock_keys.text == cubicle.CLOCK_OUT_KEYS, cubicle._clock_keys.text)
	_check("keys: the email notice and buttons", cubicle._notification.text == cubicle.EMAIL_NOTICE and cubicle._email_buttons[0].text == "ACCEPT (A)" and cubicle._email_buttons[1].text == "DECLINE (D)")
	cubicle.open_page(cubicle.Page.SPLASH)
	_check("keys: the splash", _texts(cubicle).has(cubicle.SIGN_IN_PROMPT) and cubicle._footer.text == "SHIFT: sign in    Esc: step away", cubicle._footer.text)
	cubicle.open_page(cubicle.Page.MAIN)
	_pad.active = true
	_check("pad again: the clock-out keys", cubicle._clock_keys.text == cubicle.CLOCK_OUT_PAD_KEYS, cubicle._clock_keys.text)

	await _press(JOY_BUTTON_B)
	var out := await _wait_until(func() -> bool: return cubicle.state == cubicle.State.ROOM, 2.0)
	_check("B from MAIN zooms out to the room", out and player.camera.current)
	_check("...with play focus on the pad again", InputSetup.playing_on_pad)

	# Clock out, notes.
	await _press(JOY_BUTTON_START)
	_check("Start in the room opens the clock-out prompt", cubicle.state == cubicle.State.CLOCK_OUT and cubicle._clock_panel.visible)
	_check("...and releases play", not InputSetup.is_playing())
	await _press(JOY_BUTTON_B)
	_check("B stays", cubicle.state == cubicle.State.ROOM and not cubicle._clock_panel.visible and InputSetup.playing_on_pad)
	cubicle.interact("sticky")
	_check("the sticky note reads", cubicle.state == cubicle.State.READING and cubicle._reader.visible)
	_check("its hint names X and B", cubicle._reader_hint.text == "X or B to close", cubicle._reader_hint.text)
	await _press(JOY_BUTTON_X)
	_check("X closes it", cubicle.state == cubicle.State.ROOM and not cubicle._reader.visible)
	cubicle.interact("sticky")
	await _press(JOY_BUTTON_B)
	_check("B closes it too", cubicle.state == cubicle.State.ROOM and not cubicle._reader.visible)
	cubicle.interact("plant")
	_check("the plant talks", cubicle.subtitle_text() == cubicle.PLANT_LINE)

	# APPLY FOR JOB by pad: the log and the email.
	await _wait_until(func() -> bool: return player.on_floor and cubicle.aimed() == "monitor", 3.0)
	await _press(JOY_BUTTON_X)
	await _wait_until(func() -> bool: return cubicle.state == cubicle.State.SCREEN, 2.0)
	_check("back at the computer: MAIN", cubicle.page == cubicle.Page.MAIN)
	var result := []
	cubicle.finished.connect(func(accepted: bool) -> void: result.append(accepted))
	await _press(JOY_BUTTON_A)
	await _press(JOY_BUTTON_A)
	_check("A, A: APPLY FOR JOB begins orientation", cubicle.page == cubicle.Page.LOG and cubicle.state == cubicle.State.LOG)
	var prompt := await _wait_until(func() -> bool: return cubicle._pause_left <= 0.0, 2.0)
	await _frames(1)
	_check("the log asks for Y", prompt and cubicle._prompt.text == "[Y]", cubicle._prompt.text)
	await _press(JOY_BUTTON_Y)
	_check("Y advances the log", cubicle.shown == 1)
	for i in 3:
		await _wait_until(func() -> bool: return cubicle._pause_left <= 0.0, 2.0)
		await _press(JOY_BUTTON_Y)
	_check("four lines in, the email arrives", cubicle.shown == 4 and cubicle.email_sent and cubicle._notification.visible)
	_check("the notice names A", cubicle._notification.text == cubicle.EMAIL_NOTICE_PAD, cubicle._notification.text)
	await _press(JOY_BUTTON_A)
	_check("A opens the email", cubicle.email_open and cubicle._email.visible)
	_check("its buttons name A and X", cubicle._email_buttons[0].text == "ACCEPT [A]" and cubicle._email_buttons[1].text == "DECLINE [X]")
	await _press(JOY_BUTTON_X)
	_check("X declines", cubicle.declined and not cubicle.email_open and cubicle.state == cubicle.State.LOG)
	for i in 4:
		await _wait_until(func() -> bool: return cubicle._pause_left <= 0.0, 2.0)
		await _press(JOY_BUTTON_Y)
	_check("Y on to the dying", cubicle.state == cubicle.State.DYING, str(cubicle.state))
	var asked := await _wait_until(func() -> bool: return cubicle.state == cubicle.State.GO_BACK, 6.0)
	_check("would you like to go back?", asked and cubicle._buttons.visible)
	var names := []
	for button in cubicle._buttons.get_children():
		names.append(button.text)
	_check("its buttons name A and B", names == ["Yes [A]", "No [B]"], str(names))
	await _press(JOY_BUTTON_A)
	_check("A goes back to the email", cubicle.state == cubicle.State.LOG and cubicle.email_open and not cubicle.declined)
	await _press(JOY_BUTTON_B)
	_check("B with the email open does nothing", cubicle.state == cubicle.State.LOG and cubicle.email_open)
	await _press(JOY_BUTTON_A)
	_check("A accepts", cubicle.state == cubicle.State.ACCEPTED)
	var done := await _wait_until(func() -> bool: return not result.is_empty(), 3.0)
	_check("and finishes accepted", done and result == [true], str(result))
	cubicle.free()

	# B at the go-back prompt: declined, MAIN.
	var second = _new_cubicle()
	await _frames(2)
	second.use_monitor()
	await _wait_until(func() -> bool: return second.state == second.State.SCREEN, 2.0)
	second.press_shift()
	second.press_enter()
	second.open_page(second.Page.SINGLEPLAYER)
	second.press_enter()
	var refused := []
	second.finished.connect(func(accepted: bool) -> void: refused.append(accepted))
	second._enter(second.State.GO_BACK)
	await _press(JOY_BUTTON_B)
	_check("B at the go-back prompt finishes declined, back on MAIN", refused == [false] and second.page == second.Page.MAIN and second.state == second.State.SCREEN)

	# A field with lines under it: Y steps off the field, the D-pad works the lines, up goes back.
	second.open_page(second.Page.NEW_LEVEL)
	await _press(JOY_BUTTON_Y)
	_check("NEW LEVEL: Y steps off the field onto SIZE", second.cursor == 1, str(second.cursor))
	var size: int = second._new_size
	await _press(JOY_BUTTON_DPAD_RIGHT)
	_check("right steps the size", second._new_size == size + 1, str(second._new_size))
	await _press(JOY_BUTTON_DPAD_UP)
	await _press(JOY_BUTTON_DPAD_UP)
	_check("up returns to the field and turns it", second.cursor == 0 and second._new_name == "A", "%d '%s'" % [second.cursor, second._new_name])
	second.free()

	ShiftSave.clear()
	ShiftSave.dir_override = ""
	for key in KEPT:
		settings.set_value(key, kept[key])
	InputSetup.headless_plays = true
	InputSetup.playing_on_pad = false
	_pad.active = false
	print("pad_console_test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _new_cubicle():
	var cubicle = load(SCENE).instantiate()
	cubicle.pause_scale = 0.02
	cubicle.auto_start = false
	root.add_child(cubicle)
	return cubicle


## The console's text lines on the current page.
func _texts(cubicle) -> Array:
	return cubicle._items().filter(func(line: Dictionary) -> bool: return line.kind == "text").map(func(line: Dictionary) -> String: return str(line.text))


## A pad button pressed and let go. Input.parse_input_event's events arrive on the next idle frame.
func _press(button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	var release := InputEventJoypadButton.new()
	release.button_index = button
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(2)


## The left stick pushed to value on axis and let go.
func _stick(axis: int, value: float) -> void:
	for v in [value, 0.0]:
		var event := InputEventJoypadMotion.new()
		event.axis = axis
		event.axis_value = v
		Input.parse_input_event(event)
		await _frames(2)


func _wait_until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return condition.call()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failures += 1
		print("  FAIL %s%s" % [name, "" if detail == "" else ": " + detail])
