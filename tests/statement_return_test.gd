extends SceneTree
## Headless check of the way home after a shift (play-test report, 2026-11-04: "froze after
## winning, back to cubicle, says click or press A to look around but nothing happens"):
##   godot --headless --path . --script res://tests/statement_return_test.gd
## A solo story shift on the committed laboratory fires the `ending` trigger; the Ending fades and
## leaves, landing in the cubicle with the statement waiting. There, seen the way a window sees it
## (InputSetup.headless_plays off), the player must be able to get play focus back: a click, or on
## a pad a button's release, gives it (Player / Cubicle._room_input), and the player is live
## (process_mode) in the ROOM state. Then E on the computer rolls the statement.
##
## Game types are left untyped (see editor_test.gd).

const SAVE_SCRATCH := "user://statement_return_test_shift/"
const CUBICLE_SCENE := "res://scenes/cubicle.tscn"

var _failures := 0
var _lab


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	ShiftSave.dir_override = SAVE_SCRATCH
	ShiftSave.clear()
	var net = root.get_node("Net")
	var pad = root.get_node("Pad")
	net.pending_statement = []
	net.pending_total = 0
	net.start_solo("laboratory", "play", {shift = true})
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	_lab = current_scene
	await _frames(10)
	var story = _lab.story
	_check("the lab has its story", story != null and story.ending != null)
	if story == null:
		_finish()
		return

	# The ending, seen the way a window sees it: the Ending releases play focus, which in solo play
	# puts the pause panel up and pauses the tree (LabHud); the way home must survive that.
	InputSetup.headless_plays = false
	_lab.play.triggered.emit("ending", _lab.multiplayer.get_unique_id())
	await _frames(2)
	_check("the ending shows", story.ending.shown)
	var home := await _wait_until(func() -> bool: return current_scene != null and current_scene.scene_file_path == CUBICLE_SCENE, story.ending.FADE_SECONDS + 8.0)
	_check("the ending leaves for the cubicle", home, str(current_scene))
	if not home:
		_finish()
		return
	var cubicle = current_scene
	await _frames(5)
	_check("the statement waits on the screen", cubicle.page == cubicle.Page.STATEMENT and cubicle._statement == "waiting", "%s / %s" % [cubicle.page, cubicle._statement])
	_check("the cubicle is in the ROOM state", cubicle.state == cubicle.State.ROOM, str(cubicle.state))
	_check("the player exists and is in the tree", cubicle.player != null and cubicle.player.is_inside_tree())
	_check("the player is live", cubicle.player != null and cubicle.player.process_mode != Node.PROCESS_MODE_DISABLED, str(cubicle.player.process_mode if cubicle.player else -1))
	_check("the player can process", cubicle.player != null and cubicle.player.can_process())
	_check("the tree isn't paused", not paused)

	# Nobody has play focus until a click (or a pad press). Headless can't capture the mouse, so
	# the pad flag stands in: with the pad active, resume_play sets playing_on_pad. Pad's watcher
	# (the root window's window_input) would read the click as a switch back to the keyboard, so
	# it is unhooked around the click.
	InputSetup.release_play()
	cubicle._ever_played = false
	pad.active = true
	root.window_input.disconnect(pad._watch)
	await _frames(2)
	_check("the look-around hint shows", cubicle._click_hint.visible)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = get_root().get_visible_rect().size * 0.5
	Input.parse_input_event(click)
	await _frames(3)
	_check("a click gives play focus back", InputSetup.playing_on_pad and InputSetup.is_playing())
	_check("the hint goes", not cubicle._click_hint.visible)
	root.window_input.connect(pad._watch)

	# A pad: A's release.
	InputSetup.release_play()
	await _frames(2)
	_check("released again", not InputSetup.is_playing())
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(1)
	var release := InputEventJoypadButton.new()
	release.button_index = JOY_BUTTON_A
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(3)
	_check("a pad button's release gives play focus back", InputSetup.playing_on_pad and InputSetup.is_playing())

	# The player can move: a frame of walking forward moves them.
	var before: Vector3 = cubicle.player.global_position
	Input.action_press("move_back")
	await _frames(20)
	Input.action_release("move_back")
	await _frames(2)
	_check("the player walks", cubicle.player.global_position.distance_to(before) > 0.05, str(cubicle.player.global_position - before))

	# E on the computer rolls the statement.
	cubicle.use_monitor()
	var rolled := await _wait_until(func() -> bool: return cubicle._statement == "done", 20.0)
	_check("using the computer rolls the statement", rolled, cubicle._statement)
	pad.active = false
	InputSetup.headless_plays = true
	ShiftSave.clear()
	_finish()


func _finish() -> void:
	print("statement_return_test: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


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
