extends SceneTree
## Headless checks for the lab-side story (docs/story.md) on the committed laboratory:
##   godot --headless --path . --script res://tests/story_test.gd
## The intercom subtitles a tour trigger once (and not twice), the training terminal runs its
## experiment on SHIFT (steps print, the last one reveals line by line, then the outbreak fires),
## the player starts unarmed with the ammo readout hidden and the gun item arms them, keycard doors
## make the intercom speak, and the `ending` trigger leaves a statement for the cubicle (its total
## wages minus damage minus clones) and fades to black instead of rolling a panel over the lab.
##
## Game types are left untyped (see editor_test.gd).

var _failures := 0
var _lab
var _me


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Net").start_solo("laboratory", "play")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	_lab = current_scene
	_me = _lab.local_player()
	var play = _lab.play
	_lab.director.scale_per_player = 0.0
	await _frames(20)
	var story = _find(_lab, "Story")
	_check("the HUD has the story node", story != null)
	if story == null:
		quit(1)
		return
	var intercom = story.intercom

	# Unarmed start: no gun, no readout, fire and melee refuse.
	_check("starts unarmed", not _me.has_weapon)
	_check("fire refuses without the gun", not _me.weapon.fire())
	_check("melee refuses without the gun", not _me.weapon.melee())
	var hud = _find(_lab, "CombatHud")
	await _frames(2)
	_check("ammo readout hidden while unarmed", hud != null and not hud._ammo_box.visible)

	# The tour: walking into the yard's trigger plays its line once.
	var fired := []
	play.triggered.connect(func(id: String, _peer: int) -> void: fired.append(id))
	_teleport_to("yard", 0.5, 0.5)
	var said := await _wait_until(func() -> bool: return intercom.showing == "say_yard", 3.0)
	_check("the yard trigger shows its intercom line", said, intercom.showing)
	_check("the subtitle shows the line's text", intercom._label.text.contains("Site 3"), intercom._label.text)
	_check("the subtitle fits the viewport", intercom._panel.size.x <= intercom.get_viewport_rect().size.x)
	intercom.say("say_yard")
	_check("a line plays once", intercom._queue.is_empty())
	intercom.say("gate_locked")
	intercom.say("gate_locked")
	_check("repeatable lines are rate limited", intercom._queue.size() == 1, str(intercom._queue))
	intercom._queue.clear()

	# The experiment: SHIFT runs steps, the last reveals line by line, then the outbreak.
	_teleport_to("training", 0.82, 0.8) # Within reach of the terminal, or the reader closes itself.
	await _frames(3)
	play._use("term_training", _lab.multiplayer.get_unique_id())
	await _frames(2)
	_check("the terminal opens its reader", play.reading == "term_training")
	_check("opening it doesn't use it up", not play.state_of("term_training").used and "t_0_outbreak" not in fired)
	_check("the reader shows the first prompt", play.reading_text("term_training").contains("Step 1") and play.reading_text("term_training").contains("[SHIFT]"))
	var steps: int = Lines.EXPERIMENT.size()
	for i in steps - 1:
		play.request_step("term_training")
		await _frames(2)
	_check("steps advance", int(play.state_of("term_training").get("step", 0)) == steps - 1, str(play.state_of("term_training")))
	_check("results print", play.reading_text("term_training").count("no change detected") == steps - 1, play.reading_text("term_training"))
	_check("still not fired", "t_0_outbreak" not in fired and play.power == "facility")
	play.request_step("term_training")
	await _frames(2)
	_check("the last step starts revealing", int(play.state_of("term_training").get("reveal", 0)) == 1)
	play.request_step("term_training")
	await _frames(2)
	_check("SHIFT during the reveal does nothing", int(play.state_of("term_training").get("step", 0)) == steps and int(play.state_of("term_training").get("reveal", 0)) == 1)
	var outbreak := await _wait_until(func() -> bool: return "t_0_outbreak" in fired, 8.0)
	_check("the last result fires the outbreak", outbreak, str(fired))
	_check("the terminal is used up", play.state_of("term_training").used)
	_check("the reader ends with the crash", play.reading_text("term_training").contains("please go and look"))
	_check("the outbreak line is queued", await _wait_until(func() -> bool: return intercom.showing == "t_0_outbreak" or "t_0_outbreak" in intercom._queue, 2.0))
	play.close_reading()

	# Arming: the item arms the player and the readout returns.
	_me.inventory.add("spore_shooter")
	await _frames(2)
	_check("the gun item arms the player", _me.has_weapon)
	_check("ammo readout back", hud._ammo_box.visible)
	_check("fire works armed", _me.weapon.fire())

	# Gates: a refusal and an opening speak.
	intercom._last.clear()
	intercom._queue.clear()
	play._use("d_0_lift", _lab.multiplayer.get_unique_id())
	await _frames(2)
	# A door with a hint line plays the hint on its first refusal; otherwise the generic line.
	var said_gate := false
	for id in ["gate_locked", "hint_d_0_lift"]:
		if id in intercom._queue or intercom.showing == id:
			said_gate = true
	_check("a locked gate says clearance required (or its hint)", said_gate, str(intercom._queue))
	play.add_keycard("blue")
	play._use("d_0_lift", _lab.multiplayer.get_unique_id())
	await _frames(2)
	_check("an opened gate says thank you", "gate_open" in intercom._queue or intercom.showing == "gate_open", str(intercom._queue))

	# The ending: a statement from the night's accounts, left for the cubicle, then a fade to black.
	var net = root.get_node("Net")
	net.pending_statement = []
	story.ending.leave_after_fade = false
	play.damage_by_name["desk"] = 600
	play.damage_by_name["glass_case"] = 150
	story.deaths = 2
	play.triggered.emit("ending", _lab.multiplayer.get_unique_id())
	await _frames(2)
	_check("the ending shows", story.ending.shown and story.ending.visible)
	var expected: int = int(Lines.ENDING.wages) - 750 - 2 * int(Lines.ENDING.clone_cost)
	_check("the total is wages minus damage minus clones", story.ending.total == expected, "%d vs %d" % [story.ending.total, expected])
	_check("the statement is pending for the cubicle", net.pending_statement == story.ending._lines and not net.pending_statement.is_empty(), str(net.pending_statement))
	_check("the pending total is the total", net.pending_total == expected, "%d vs %d" % [net.pending_total, expected])
	_check("the statement lists the assets", net.pending_statement.any(func(l: String) -> bool: return l.contains("desk") and l.contains("600")), str(net.pending_statement))
	_check("the lines are left|right", net.pending_statement.all(func(l: String) -> bool: return l.split("|").size() == 2), str(net.pending_statement))
	_check("the total line is owed", str(net.pending_statement.back()).begins_with("TOTAL OWED"), str(net.pending_statement.back()))
	_check("no panel rolls over the lab", story.ending.get_child_count() == 1)
	_check("the fade starts clear", story.ending._black.color.a < 0.5, str(story.ending._black.color))
	var faded := await _wait_until(func() -> bool: return story.ending._black.color.a >= 1.0, story.ending.FADE_SECONDS + 3.0)
	_check("the screen fades to black", faded, str(story.ending._black.color))
	_check("the fade covers the viewport", story.ending._black.get_global_rect().size == story.ending.get_viewport_rect().size, str(story.ending._black.get_global_rect()))
	_check("still in the lab with leaving off", current_scene == _lab)
	net.pending_statement = []
	net.pending_total = 0

	print("story_test: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _teleport_to(room_id: String, fx: float, fz: float) -> void:
	var room: Dictionary = _lab.level.objects[room_id]
	var extent: Vector3i = room.to - room.from
	var voxel := Vector3(room.from) + Vector3(fx * extent.x, 0.0, fz * extent.z)
	_me.teleport(_lab.view.to_world(voxel))


func _find(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.get_class() == type_name or (child.get_script() and child.get_script().get_global_name() == type_name):
			return child
		var found := _find(child, type_name)
		if found:
			return found
	return null


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
