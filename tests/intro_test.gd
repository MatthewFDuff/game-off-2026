extends SceneTree
## Headless checks for the cubicle intro (scripts/story/intro.gd):
##   godot --headless --path . --script res://tests/intro_test.gd
## With the pauses shrunk: SHIFT does nothing while a line is thinking and shows the next line once
## it stops; the email arrives after the fourth line; Decline runs the log out, dies, shows the
## trash-bag scene and the go-back prompt; Yes returns to the email; Accept ends with finished(true);
## the skip prompt ends with finished(true) too.
##
## Game types are left untyped (see editor_test.gd).

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var intro = load("res://scenes/intro.tscn").instantiate()
	intro.pause_scale = 0.02
	root.add_child(intro)
	var result := []
	intro.finished.connect(func(accepted: bool) -> void: result.append(accepted))
	await _frames(2)

	_check("starts on the log with nothing shown", intro.state == intro.State.LOG and intro.shown == 0)
	intro._pause_left = 10.0 # Still thinking, whatever the frame timing.
	intro.press_shift()
	_check("SHIFT while thinking shows nothing", intro.shown == 0 and intro._prompt.text == "not yet")
	intro._pause_left = 0.0
	intro.press_shift()
	_check("SHIFT after the pause shows a line", intro.shown == 1)
	_check("the next line is thinking again", intro._pause_left > 0.0)
	for i in 3:
		await _wait_until(func() -> bool: return intro._pause_left <= 0.0, 2.0)
		intro.press_shift()
	_check("four lines in", intro.shown == 4)
	_check("the email arrives after line 4", intro.email_sent and intro._notification.visible)
	intro.open_email()
	_check("the email opens", intro.email_open and intro._email.visible)

	# Decline: the log runs out, death, the trash bag, the prompt.
	intro.decline()
	_check("declined: back to the log", intro.declined and not intro.email_open and intro.state == intro.State.LOG)
	for i in 4:
		await _wait_until(func() -> bool: return intro._pause_left <= 0.0, 2.0)
		intro.press_shift()
	_check("the last line starts the dying", intro.state == intro.State.DYING, str(intro.state))
	var dead := await _wait_until(func() -> bool: return intro.state == intro.State.DEAD, 4.0)
	_check("the vignette closes and you die", dead and intro._black.visible)
	var trash := await _wait_until(func() -> bool: return intro.state == intro.State.TRASH, 3.0)
	_check("the trash-bag scene", trash and intro._overlay_text.visible and intro._overlay_text.text == intro.TRASH_TEXT)
	var prompt := await _wait_until(func() -> bool: return intro.state == intro.State.GO_BACK, 3.0)
	_check("would you like to go back?", prompt and intro._buttons.visible)
	_check("nothing finished yet", result.is_empty())

	# Yes: back to the email, open.
	intro.go_back()
	_check("Yes returns to the open email", intro.state == intro.State.LOG and intro.email_open and intro._email.visible and not intro.declined)
	intro.accept()
	_check("Accept shows the transfer note", intro.state == intro.State.ACCEPTED and intro._overlay_text.text == intro.ACCEPT_TEXT)
	var done := await _wait_until(func() -> bool: return not result.is_empty(), 3.0)
	_check("and finishes accepted", done and result == [true], str(result))
	intro.free()

	# A fresh intro: Esc, then Enter skips (accepting).
	var second = load("res://scenes/intro.tscn").instantiate()
	second.pause_scale = 0.02
	root.add_child(second)
	var skipped := []
	second.finished.connect(func(accepted: bool) -> void: skipped.append(accepted))
	await _frames(2)
	second._enter(second.State.SKIP)
	_check("Esc shows the skip prompt", second._skip_panel.visible)
	second._leave_skip()
	_check("Esc again keeps watching", not second._skip_panel.visible and second.state == second.State.LOG)
	second._enter(second.State.SKIP)
	second._finish(true)
	_check("skipping finishes accepted", skipped == [true])
	second.free()

	# A declined intro that refuses to go back finishes declined.
	var third = load("res://scenes/intro.tscn").instantiate()
	third.pause_scale = 0.02
	root.add_child(third)
	var declined := []
	third.finished.connect(func(accepted: bool) -> void: declined.append(accepted))
	await _frames(2)
	third._enter(third.State.GO_BACK)
	third._finish(false)
	_check("No finishes declined", declined == [false])
	third.free()

	print("intro_test: %d failure(s)" % _failures)
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
