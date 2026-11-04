extends SceneTree
## Headless checks for the cubicle, the game's menu (scripts/story/cubicle.gd, docs/cubicle-menu.md):
##   godot --headless --path . --script res://tests/cubicle_test.gd
## Builds the cubicle into a scratch folder and plays it with the pauses shrunk: the player spawns
## standing in air beside the chair, unarmed and offline, aimed at the monitor; walking into the
## opening freezes them, says the first line and sets them back inside, and the second attempt says
## the second line; the notes read and the plant talks; E on the computer zooms onto the screen and
## shows SPLASH; SHIFT with no name shows SIGN IN; typing a name and Enter reaches MAIN; NEW GAME
## starts orientation on the LOG page, where the old intro's checks run (SHIFT while thinking, the
## email after line 4, Decline to death and the go-back prompt, Yes back to the email, Accept
## finishes); F9 finishes at once; No goes back to MAIN; Esc from SPLASH zooms out; the duck opens
## MAINTENANCE; the sleeping bag and Esc show the clock-out prompt; a pending statement rolls,
## clears and updates the nameplate. The settings it touches are put back at the end.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://cubicle_test_levels/"
const Builder := preload("res://scripts/tools/build_cubicle.gd")
const SCENE := "res://scenes/cubicle.tscn"
const KEPT := ["name", "orientation", "shifts_worked", "balance_owed"]

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings = root.get_node("GameSettings")
	var net = root.get_node("Net")
	var kept := {}
	for key in KEPT:
		kept[key] = settings.get_value(key)
	settings.set_value("name", "")
	settings.set_value("orientation", "play")

	LevelData.save_dir_override = SCRATCH
	var built: Dictionary = Builder.build(root)
	var objects: Dictionary = built.level.objects
	var ids_ok := true
	for id in ["monitor", "chair", "duck", "plant", "sleeping_bag", "nameplate", "poster", "sticky", "t_leave"]:
		ids_ok = ids_ok and objects.has(id)
	_check("the cubicle builds with its props and markers", built.error == OK and ids_ok, error_string(built.error))
	_check("every prop model exists", Props.missing.is_empty(), str(Props.missing))
	var desk_box: AABB = LevelSchema.prop_box(objects.monitor)
	var duck_box: AABB = LevelSchema.prop_box(objects.duck)
	_check("the duck stands on the desk top", is_equal_approx(duck_box.position.y, desk_box.position.y + 8.0) and desk_box.grow(0.01).encloses(AABB(duck_box.position, Vector3(duck_box.size.x, 0.0, duck_box.size.z))), str(duck_box))
	built.world.free()

	var cubicle = _new_cubicle()
	await _frames(3)
	var player = cubicle.player
	var vs: float = cubicle._world.voxel_size
	_check("starts in the room with a Player", cubicle.state == cubicle.State.ROOM and player != null and cubicle.page == cubicle.Page.SPLASH)
	_check("the player is unarmed and offline", not player.has_weapon and player.net_peers.is_empty())
	var feet: Vector3 = player.global_position
	var cell := Vector3i((feet / vs).floor())
	_check("spawns standing in air, on the floor", cubicle._world.get_voxel(cell) == 0 and cubicle._world.get_voxel(cell + Vector3i(0, 1, 0)) == 0 and cubicle._world.get_voxel(cell - Vector3i(0, 1, 0)) != 0, str(cell))
	var chair_box: AABB = LevelSchema.prop_box(cubicle.level.objects.chair)
	var chair := Vector3(chair_box.get_center().x, chair_box.position.y, chair_box.get_center().z) * vs
	_check("beside the chair", Vector2(feet.x - chair.x, feet.z - chair.z).length() < 1.2, str(feet.distance_to(chair)))
	await _frames(20)
	_check("and still standing a moment later", absf(player.global_position.y - feet.y) < 0.05 and player.on_floor, str(player.global_position))
	_check("facing the monitor", cubicle.aimed() == "monitor", cubicle.aimed())
	_check("the prompt names it", cubicle._use_prompt.visible and cubicle._use_prompt.text == "[E] Use computer", cubicle._use_prompt.text)

	# Leaving: walk south into the opening.
	var box: AABB = cubicle._leave_box
	player.teleport(Vector3(box.get_center().x, box.position.y, box.position.z - 0.5))
	player.rotation.y = PI
	Input.action_press("move_forward")
	var frozen := await _wait_until(func() -> bool: return cubicle.state == cubicle.State.FROZEN, 3.0)
	Input.action_release("move_forward")
	_check("walking into the opening freezes the player", frozen and player.process_mode == Node.PROCESS_MODE_DISABLED and cubicle.exits == 1)
	_check("and says the first line", cubicle.subtitle_text().contains(cubicle.LEAVE_LINES[0]), cubicle.subtitle_text())
	var back := await _wait_until(func() -> bool: return cubicle.state == cubicle.State.ROOM, 2.0)
	_check("then sets them back inside", back and player.global_position.z < box.position.z - 0.3 and player.process_mode != Node.PROCESS_MODE_DISABLED, str(player.global_position))
	player.teleport(box.get_center() - Vector3(0, box.size.y * 0.5 - 0.01, 0))
	frozen = await _wait_until(func() -> bool: return cubicle.state == cubicle.State.FROZEN, 2.0)
	_check("the second attempt says the second line", frozen and cubicle.exits == 2 and cubicle.subtitle_text().contains(cubicle.LEAVE_LINES[1]), cubicle.subtitle_text())
	await _wait_until(func() -> bool: return cubicle.state == cubicle.State.ROOM, 2.0)

	# The notes and the plant.
	cubicle.interact("sticky")
	_check("the sticky note reads", cubicle.state == cubicle.State.READING and cubicle._reader.visible and cubicle._reader_text.text.contains("PRESS SHIFT"))
	cubicle.close_reader()
	cubicle.interact("plant")
	_check("the plant is plastic", cubicle.state == cubicle.State.ROOM and cubicle.subtitle_text() == cubicle.PLANT_LINE)
	_check("the nameplate has no name yet", str(cubicle.level.objects.nameplate.text).begins_with("EMPLOYEE"))

	# The computer: SPLASH, SIGN IN, MAIN.
	cubicle.interact("monitor")
	var screen := await _wait_until(func() -> bool: return cubicle.state == cubicle.State.SCREEN, 2.0)
	_check("E on the computer zooms onto the screen and shows SPLASH", screen and cubicle.page == cubicle.Page.SPLASH and cubicle._zoom_camera.current)
	var eye: Vector3 = cubicle._zoom_camera.global_position
	_check("the camera sits in front of the screen", eye.distance_to(cubicle._screen_center) < cubicle.SCREEN_DISTANCE + 0.05, str(eye.distance_to(cubicle._screen_center)))
	_check("the player is frozen at the screen", player.process_mode == Node.PROCESS_MODE_DISABLED)
	cubicle.press_shift()
	_check("SHIFT with no name shows SIGN IN", cubicle.page == cubicle.Page.SIGN_IN)
	for c in "Zack 9!":
		cubicle.handle_key(_key(KEY_NONE, c.unicode_at(0)))
	cubicle.handle_key(_key(KEY_BACKSPACE))
	cubicle.handle_key(_key(KEY_9, "9".unicode_at(0)))
	_check("typing fills the field (no punctuation)", cubicle._name_field == "Zack 9", cubicle._name_field)
	cubicle.handle_key(_key(KEY_ENTER))
	_check("Enter signs in and reaches MAIN", cubicle.page == cubicle.Page.MAIN and settings.get_value("name") == "Zack 9" and net.player_name == "Zack 9", str(settings.get_value("name")))
	_check("the nameplate carries the name", str(cubicle.level.objects.nameplate.text).begins_with("Zack 9\nLLM Operator"))
	cubicle.handle_key(_key(KEY_DOWN))
	cubicle.handle_key(_key(KEY_DOWN))
	cubicle.handle_key(_key(KEY_SHIFT))
	_check("SETTINGS shows the settings menu", cubicle.page == cubicle.Page.SETTINGS and cubicle._settings_menu != null and cubicle._settings_menu.is_inside_tree())
	cubicle.handle_key(_key(KEY_ESCAPE))
	_check("Esc from SETTINGS goes back to MAIN", cubicle.page == cubicle.Page.MAIN)
	cubicle.handle_key(_key(KEY_SHIFT))
	_check("SINGLEPLAYER", cubicle.page == cubicle.Page.SINGLEPLAYER)
	cubicle.handle_key(_key(KEY_DOWN))
	cubicle.handle_key(_key(KEY_ENTER))
	_check("CONTINUE is dimmed: no clone on file", cubicle.page == cubicle.Page.SINGLEPLAYER and cubicle.status == cubicle.NO_CLONE)
	cubicle.handle_key(_key(KEY_UP))
	var result := []
	cubicle.finished.connect(func(accepted: bool) -> void: result.append(accepted))
	cubicle.handle_key(_key(KEY_ENTER))
	_check("NEW GAME begins orientation on the LOG page", cubicle.page == cubicle.Page.LOG and cubicle.state == cubicle.State.LOG and cubicle._header.text == cubicle.SESSION_STARTED)

	# The thought log, as the intro had it.
	cubicle._pause_left = 10.0 # Still thinking, whatever the frame timing.
	cubicle.press_shift()
	_check("SHIFT while thinking shows nothing", cubicle.shown == 0 and cubicle._prompt.text == "not yet")
	cubicle._pause_left = 0.0
	cubicle.press_shift()
	_check("SHIFT after the pause shows a line", cubicle.shown == 1 and cubicle._log.get_child_count() == 1)
	_check("the next line is thinking again", cubicle._pause_left > 0.0)
	for i in 3:
		await _wait_until(func() -> bool: return cubicle._pause_left <= 0.0, 2.0)
		cubicle.press_shift()
	_check("four lines in", cubicle.shown == 4)
	_check("the email arrives after line 4, on the monitor", cubicle.email_sent and cubicle._notification.visible)
	cubicle.open_email()
	_check("the email opens", cubicle.email_open and cubicle._email.visible)
	cubicle.decline()
	_check("declined: back to the log", cubicle.declined and not cubicle.email_open and cubicle.state == cubicle.State.LOG)
	for i in 4:
		await _wait_until(func() -> bool: return cubicle._pause_left <= 0.0, 2.0)
		cubicle.press_shift()
	_check("the last line starts the dying", cubicle.state == cubicle.State.DYING, str(cubicle.state))
	var dead := await _wait_until(func() -> bool: return cubicle.state == cubicle.State.DEAD, 4.0)
	_check("the vignette closes and you die", dead and cubicle._black.visible)
	var trash := await _wait_until(func() -> bool: return cubicle.state == cubicle.State.TRASH, 3.0)
	_check("the trash-bag scene", trash and cubicle._overlay_text.visible and cubicle._overlay_text.text == cubicle.TRASH_TEXT)
	var prompt := await _wait_until(func() -> bool: return cubicle.state == cubicle.State.GO_BACK, 3.0)
	_check("would you like to go back?", prompt and cubicle._buttons.visible)
	_check("nothing finished yet", result.is_empty())
	cubicle.go_back()
	_check("Yes returns to the open email", cubicle.state == cubicle.State.LOG and cubicle.email_open and cubicle._email.visible and not cubicle.declined)
	cubicle.accept()
	_check("Accept shows the transfer note", cubicle.state == cubicle.State.ACCEPTED and cubicle._overlay_text.text == cubicle.ACCEPT_TEXT)
	var done := await _wait_until(func() -> bool: return not result.is_empty(), 3.0)
	_check("and finishes accepted", done and result == [true], str(result))
	cubicle.free()

	# Signed in: SHIFT on the splash goes straight to MAIN; F9 accepts at once.
	var second = _new_cubicle()
	await _frames(2)
	second.use_monitor()
	await _wait_until(func() -> bool: return second.state == second.State.SCREEN, 2.0)
	second.press_shift()
	_check("signed in: SHIFT on the splash reaches MAIN", second.page == second.Page.MAIN)
	second.open_page(second.Page.SINGLEPLAYER)
	second.press_enter()
	var dev := []
	second.finished.connect(func(accepted: bool) -> void: dev.append(accepted))
	_check("the F9 hint shows when the log starts", await _wait_until(func() -> bool: return second._hint.visible, 1.0))
	second.handle_key(_key(KEY_F9))
	_check("F9 finishes accepted at once", dev == [true])
	second.free()

	# Declining and refusing to go back: MAIN, declined.
	var third = _new_cubicle()
	await _frames(2)
	third.use_monitor()
	await _wait_until(func() -> bool: return third.state == third.State.SCREEN, 2.0)
	third.press_shift()
	third.open_page(third.Page.SINGLEPLAYER)
	third.press_enter()
	var refused := []
	third.finished.connect(func(accepted: bool) -> void: refused.append(accepted))
	third._enter(third.State.GO_BACK)
	third.handle_key(_key(KEY_N))
	_check("No finishes declined, back on MAIN", refused == [false] and third.page == third.Page.MAIN and third.state == third.State.SCREEN and third.status == third.DECLINED_TEXT)
	third.open_page(third.Page.SPLASH)
	third.handle_key(_key(KEY_ESCAPE))
	var out := await _wait_until(func() -> bool: return third.state == third.State.ROOM, 2.0)
	_check("Esc from SPLASH zooms out", out and third.player.camera.current and third.player.process_mode != Node.PROCESS_MODE_DISABLED)

	# The duck, the sleeping bag, Esc in the room.
	third.interact("duck")
	var duck := await _wait_until(func() -> bool: return third.state == third.State.SCREEN, 2.0)
	_check("the duck opens MAINTENANCE", duck and third.page == third.Page.MAINTENANCE and "cubicle" in third._levels)
	third.handle_key(_key(KEY_ESCAPE))
	await _wait_until(func() -> bool: return third.state == third.State.ROOM, 2.0)
	third.interact("sleeping_bag")
	_check("the sleeping bag shows the clock-out prompt", third.state == third.State.CLOCK_OUT and third._clock_panel.visible)
	third._unhandled_input(_key(KEY_N))
	_check("N stays in the room", third.state == third.State.ROOM and not third._clock_panel.visible)
	third._unhandled_input(_key(KEY_ESCAPE))
	_check("Esc in the room shows it too", third.state == third.State.CLOCK_OUT)
	third.close_clock_out()
	third.use_monitor()
	await _wait_until(func() -> bool: return third.state == third.State.SCREEN, 2.0)
	_check("the computer after the duck shows the home page again", third.page == third.Page.MAIN)
	third.free()

	# A shift's statement waiting on the screen.
	settings.set_value("shifts_worked", 2)
	settings.set_value("balance_owed", 100)
	net.pending_statement = ["Shift wages|+$180", "Property damage|$0", "TOTAL OWED TO FUNG AI|-$4820"]
	net.pending_total = -4820
	var fourth = _new_cubicle()
	await _frames(2)
	_check("a pending statement waits on the screen", fourth.page == fourth.Page.STATEMENT and fourth._statement == "waiting")
	fourth.use_monitor()
	var rolled := await _wait_until(func() -> bool: return fourth._statement == "done", 4.0)
	_check("using the computer rolls it", rolled and fourth._statement_rows.size() == 3)
	_check("and clears it", net.pending_statement.is_empty() and net.pending_total == 0)
	_check("the nameplate's numbers move", settings.get_value("shifts_worked") == 3 and settings.get_value("balance_owed") == 4920 and str(fourth.level.objects.nameplate.text).contains("$4920"), str(fourth.level.objects.nameplate.text))
	fourth.press_shift()
	_check("then SHIFT signs in", fourth.page == fourth.Page.MAIN)
	fourth.free()

	for key in KEPT:
		settings.set_value(key, kept[key])
	print("cubicle_test: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _new_cubicle():
	var cubicle = load(SCENE).instantiate()
	cubicle.pause_scale = 0.02
	cubicle.auto_start = false
	root.add_child(cubicle)
	return cubicle


func _key(keycode: Key, unicode := 0) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.unicode = unicode
	event.pressed = true
	return event


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
