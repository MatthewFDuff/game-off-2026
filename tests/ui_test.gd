extends SceneTree
## Checks the play HUD's layout and layering on the committed laboratory:
##   godot --headless --path . --script res://tests/ui_test.gd
## The interact prompt fills the viewport and centers its label under the crosshair, a long note's
## reader panel stays inside the viewport, the intercom subtitle moves off the reader while it's
## open, delayed lines (say_after) fire and cancel, the training nudge is dropped by the outbreak,
## a door refusal plays the generic line (or the door's hint), the ending's fade covers the viewport
## with the HUD hidden under it, a mode change resets the intercom and the ending, and F doesn't fly
## without --dev. Run windowed with `-- --shots=<dir>` to also save screenshots of the prompt at the
## training terminal, the reader with the subtitle above it, and the ending statement.
##
## Game types are left untyped (see editor_test.gd).

const LONG_NOTE := "ui_test_note"

var _failures := 0
var _lab
var _me
var _shots := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
	_run.call_deferred()


func _run() -> void:
	root.get_node("Net").start_solo("laboratory", "play")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	_lab = current_scene
	_me = _lab.local_player()
	var play = _lab.play
	_lab.director.scale_per_player = 0.0
	if _shots != "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		DirAccess.make_dir_recursive_absolute(_shots)
	await _frames(20)
	var story = _find(_lab, "Story")
	var prompt = _find(_lab, "InteractPrompt")
	var hud = _find(_lab, "LabHud")
	if story == null or prompt == null or hud == null:
		_check("the HUD, story and prompt exist", false)
		quit(1)
		return
	var intercom = story.intercom
	var viewport: Vector2 = prompt.get_viewport_rect().size

	# The prompt layer fills the viewport (not 0 x 0 in the corner).
	_check("the interact prompt fills the viewport", prompt.get_global_rect().is_equal_approx(Rect2(Vector2.ZERO, viewport)), "%s vs %s" % [prompt.get_global_rect(), viewport])
	_check("the intercom fills the viewport", intercom.get_global_rect().is_equal_approx(Rect2(Vector2.ZERO, viewport)), str(intercom.get_global_rect()))

	# The prompt at the training terminal: centered horizontally, just under the crosshair.
	var aimed: bool = await _aim_at("term_training")
	var label = prompt._prompt
	var rect: Rect2 = label.get_global_rect()
	_check("the training terminal shows a prompt", aimed and label.visible and label.text != "", label.text)
	_check("the prompt is centered horizontally", absf(rect.get_center().x - viewport.x * 0.5) <= 2.0, "%s in %s" % [rect, viewport])
	_check("the prompt sits just under the crosshair", rect.position.y > viewport.y * 0.5 and rect.position.y < viewport.y * 0.5 + 80.0, str(rect))
	_check("the prompt is inside the viewport", Rect2(Vector2.ZERO, viewport).encloses(rect), str(rect))
	await _shot("prompt_training_terminal")

	# A long note: the reader stays inside the viewport and scrolls.
	_lab.level.objects[LONG_NOTE] = {kind = "prop", name = "corkboard_small", use = "note", text = "Memo. ".repeat(334)}
	intercom.reset()
	play.open_reading(LONG_NOTE)
	await _frames(3)
	var reader: Rect2 = prompt.reader_rect()
	_check("the reader opens", reader.size != Vector2.ZERO)
	_check("a 2000-character note's reader is inside the viewport", Rect2(Vector2.ZERO, viewport).encloses(reader), "%s in %s" % [reader, viewport])

	# The subtitle moves off the reader while it's open, and back to the bottom after.
	intercom.say("t_0_outbreak")
	await _frames(3)
	var subtitle: Rect2 = intercom._panel.get_global_rect()
	_check("the subtitle shows over the reader", intercom._panel.visible and intercom.overlay_open())
	_check("the subtitle doesn't cover the reader", not subtitle.intersects(reader), "%s vs %s" % [subtitle, reader])
	_check("the subtitle sits above it", subtitle.end.y <= reader.position.y, "%s vs %s" % [subtitle, reader])
	await _shot("reader_with_subtitle")
	play.close_reading()
	await _frames(3)
	subtitle = intercom._panel.get_global_rect()
	_check("the subtitle returns to the bottom", subtitle.get_center().y > viewport.y * 0.5, str(subtitle))
	_lab.level.objects.erase(LONG_NOTE)

	# The controls sheet moves it too.
	var controls = _find(_lab, "ControlsOverlay")
	controls.visible = true
	await _frames(2)
	_check("the subtitle moves off the controls sheet", intercom._panel.get_global_rect().end.y < viewport.y * 0.5)
	controls.visible = false

	# Tour lines: a newer one drops a queued one.
	intercom.reset()
	intercom._queue.assign(["say_yard"])
	intercom._enqueue("say_lobby")
	_check("a newer tour line drops a queued one", intercom._queue == ["say_lobby"], str(intercom._queue))
	intercom._enqueue("gate_open")
	intercom._enqueue("say_break_room")
	_check("non-tour lines stay queued", intercom._queue == ["gate_open", "say_break_room"], str(intercom._queue))

	# Free text and delayed lines.
	intercom.reset()
	intercom.say_text("Please hold.")
	_check("say_text queues free text", intercom._queue.size() == 1 and intercom.text_of(intercom._queue[0]) == "Please hold.", str(intercom._queue))
	intercom.reset()
	intercom.say_after("gate_open", 0.05)
	_check("say_after waits", not _said(intercom, "gate_open"))
	await _wait_seconds(0.3)
	_check("say_after plays after its delay", _said(intercom, "gate_open"), str(intercom._queue))
	intercom.reset()
	intercom.say_after("gate_locked", 0.05)
	intercom.cancel_after("gate_locked")
	await _wait_seconds(0.3)
	_check("a cancelled say_after doesn't play", not _said(intercom, "gate_locked"), str(intercom._queue))
	intercom.reset()
	intercom.say_after("gate_locked", 0.05, func() -> bool: return true)
	await _wait_seconds(0.3)
	_check("say_after skips when its condition says so", not _said(intercom, "gate_locked"))
	intercom.reset()
	intercom.say("say_training")
	_check("the training line schedules the nudge", intercom.is_pending(intercom.NUDGE_LINE))
	play.triggered.emit(intercom.NUDGE_CANCEL, _lab.multiplayer.get_unique_id())
	_check("the outbreak cancels the nudge", not intercom.is_pending(intercom.NUDGE_LINE))

	# Door refusals: the door's own hint the first time if Lines has one, else the generic line.
	intercom.reset()
	play.door_refused.emit("d_ui_test_none", _lab.multiplayer.get_unique_id())
	_check("a door with no hint says clearance required", "gate_locked" in intercom._queue, str(intercom._queue))
	for key: String in Lines.INTERCOM:
		if key.begins_with(intercom.HINT_PREFIX):
			intercom.reset()
			play.door_refused.emit(key.trim_prefix(intercom.HINT_PREFIX), _lab.multiplayer.get_unique_id())
			_check("a door's hint plays instead of the generic line (%s)" % key, key in intercom._queue and "gate_locked" not in intercom._queue, str(intercom._queue))
			break

	# Fly mode is a dev key.
	_check("F has no key without --dev", InputMap.action_get_events("toggle_fly").is_empty())
	var press := InputEventKey.new()
	press.physical_keycode = KEY_F
	press.keycode = KEY_F
	press.pressed = true
	root.push_input(press)
	await _frames(2)
	_check("F doesn't fly without --dev", not _me.flying)
	var look: Array = InputSetup.describe_play_controls().filter(func(row: Dictionary) -> bool: return row.label == "Look")
	_check("Look lists the mouse", not look.is_empty() and look[0].keys == "Mouse / arrows", str(look))

	# The ending: the fade covers the viewport and the HUD hides under it.
	intercom.reset()
	_lab.notify("Checkpoint")
	play.triggered.emit("ending", _lab.multiplayer.get_unique_id())
	await _frames(3)
	var ending = story.ending
	_check("the ending shows", ending.shown and ending.visible)
	_check("the ending fills the viewport", ending.get_global_rect().is_equal_approx(Rect2(Vector2.ZERO, viewport)), str(ending.get_global_rect()))
	_check("the fade covers the viewport", ending._black.get_global_rect().is_equal_approx(Rect2(Vector2.ZERO, viewport)), str(ending._black.get_global_rect()))
	var combat = _find(_lab, "CombatHud")
	_check("the combat HUD hides", not combat.visible)
	_check("the toast hides", not hud._toast.visible)
	_check("the crosshair hides", not hud._crosshair.visible)
	_check("the prompt hides", not prompt.is_visible_in_tree())
	_check("the pause panel hides", not hud._pause.visible)
	if _shots != "":
		await _wait_until(func() -> bool: return ending._button.visible, 15.0)
		await _shot("ending_statement")

	# A mode change (the editor's F5) resets the intercom and the ending.
	intercom.say("say_yard")
	_lab.mode_changed.emit(_lab.mode)
	await _frames(2)
	_check("a mode change resets the intercom", intercom.said.is_empty() and intercom._queue.is_empty())
	_check("a mode change resets the ending", not ending.shown and not ending.visible)
	await _frames(2)
	_check("the combat HUD comes back", combat.visible)

	print("ui_test: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _said(intercom, id: String) -> bool:
	return intercom.showing == id or id in intercom._queue


## Stands in front of a prop (tries each side) and looks at its middle; true once it shows a prompt.
func _aim_at(id: String) -> bool:
	var box: AABB = _lab.play.box_of(id)
	var center := box.get_center()
	for front: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.BACK, Vector3.FORWARD]:
		var face := center + front * absf(front.dot(box.size)) * 0.5
		var feet := Vector3(face.x, box.position.y, face.z) + front * 1.4
		_me.teleport(feet)
		_me.velocity = Vector3.ZERO
		await _frames(4)
		var eye: Vector3 = _me.camera.global_position
		var to := center - eye
		_me.rotation.y = atan2(-to.x, -to.z)
		_me.head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
		await _frames(3)
		if _lab.play.interactables.prompt_for(_me.camera).text != "":
			return true
	return false


func _shot(shot_name: String) -> void:
	if _shots == "":
		return
	await _frames(4)
	await RenderingServer.frame_post_draw
	var path := _shots.path_join(shot_name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


func _find(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.get_class() == type_name or (child.get_script() and child.get_script().get_global_name() == type_name):
			return child
		var found := _find(child, type_name)
		if found:
			return found
	return null


func _check(what: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   ", what)
	else:
		_failures += 1
		print("  FAIL ", what, "  ", detail)


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await physics_frame
	return true


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _frames(count: int) -> void:
	for i in count:
		await process_frame
