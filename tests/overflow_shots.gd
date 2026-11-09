extends SceneTree
## Screenshots of the play HUD's centered panels at several window sizes, with each panel's rect
## checked against the viewport (needs a window, not --headless):
##   godot --path . --script res://tests/overflow_shots.gd -- <output_dir>
## The longest laboratory terminal in the reader, the F1 sheet with a pad shown, the pause panel's
## Settings and Controls pages, then the cubicle's reader (a long note), clock-out prompt and email,
## at 1152 x 648, 1280 x 720, 960 x 540 and 1600 x 600.
##
## Game types are left untyped (see editor_test.gd).

const SIZES := [Vector2i(1152, 648), Vector2i(1280, 720), Vector2i(960, 540), Vector2i(1600, 600)]

var _out := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(_out)
	var pad = root.get_node("Pad")
	root.get_node("Net").start_solo("laboratory", "play")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	var lab = current_scene
	lab.director.scale_per_player = 0.0
	await _frames(20)
	var prompt = _find(lab, "InteractPrompt")
	var hud = _find(lab, "LabHud")
	var controls = _find(lab, "ControlsOverlay")
	var intercom = _find(lab, "Story").intercom
	var longest := ""
	for id: String in lab.level.objects:
		if longest == "" or str(lab.level.objects[id].get("text", "")).length() > str(lab.level.objects[longest].get("text", "")).length():
			longest = id
	# The intercom's first line, at the bottom.
	await _frames(5)
	if intercom._panel.visible:
		_report("intercom first line", intercom._panel)
	await _shot("intercom_first")
	for size: Vector2i in SIZES:
		root.size = size
		var tag := "%dx%d" % [size.x, size.y]
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		await _frames(5)
		lab.play.open_reading(longest)
		await _frames(4)
		_report("reader " + tag, prompt._panel)
		if intercom._panel.visible:
			_report("intercom over the reader " + tag, intercom._panel)
		await _shot("reader_" + tag)
		lab.play.close_reading()
		pad.connected = true
		controls._rebuild()
		controls.visible = true
		await _frames(4)
		_report("controls sheet (pad) " + tag, controls.get_child(0))
		if intercom._panel.visible:
			_report("intercom over the sheet " + tag, intercom._panel)
		await _shot("controls_pad_" + tag)
		controls.visible = false
		pad.connected = false
		controls._rebuild()
		InputSetup.release_play()
		await _frames(4)
		_report("pause buttons " + tag, hud._pause)
		await _shot("pause_buttons_" + tag)
		hud._show_settings()
		await _frames(4)
		_report("pause settings " + tag, hud._pause)
		await _shot("pause_settings_" + tag)
		hud._show_controls_page()
		await _frames(4)
		_report("pause controls " + tag, hud._pause)
		await _shot("pause_controls_" + tag)
		hud._show_buttons()
		InputSetup.resume_play()
		await _frames(4)

	root.get_node("Net").leave()
	await _frames(10)
	var cubicle = load("res://scenes/cubicle.tscn").instantiate()
	cubicle.pause_scale = 0.0
	cubicle.auto_start = false
	root.add_child(cubicle)
	await _frames(30)
	cubicle._say("The night shift starts at the desk. Sign in on the console and read your email before you clock in.", true)
	await _frames(3)
	_report("cubicle subtitle", cubicle._subtitle_panel)
	await _shot("cubicle_subtitle")
	cubicle.level.objects["sticky"]["text"] = str(cubicle.level.objects["sticky"]["text"]) + " " + "Remember the quarterly numbers. ".repeat(40)
	for size: Vector2i in SIZES:
		root.size = size
		var tag := "%dx%d" % [size.x, size.y]
		await _frames(5)
		cubicle.interact("sticky")
		await _frames(3)
		_report("cubicle reader " + tag, cubicle._reader)
		await _shot("cubicle_reader_" + tag)
		cubicle.close_reader()
		cubicle.interact("sleeping_bag")
		await _frames(3)
		_report("cubicle clock-out " + tag, cubicle._clock_panel)
		await _shot("cubicle_clock_" + tag)
		cubicle.close_clock_out()
		cubicle._email.visible = true
		await _frames(3)
		_report("cubicle email " + tag, cubicle._email)
		await _shot("cubicle_email_" + tag)
		cubicle._email.visible = false
	quit(0)


func _report(what: String, panel: Control) -> void:
	var view: Rect2 = panel.get_viewport().get_visible_rect()
	var rect := panel.get_global_rect()
	print("%s %s: %s in %s" % ["ok  " if view.encloses(rect) else "OVER", what, rect, view.size])


func _shot(shot_name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var path := _out.path_join(shot_name + ".png")
	root.get_texture().get_image().save_png(path)


func _find(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.get_class() == type_name or (child.get_script() and child.get_script().get_global_name() == type_name):
			return child
		var found := _find(child, type_name)
		if found:
			return found
	return null


func _frames(count: int) -> void:
	for i in count:
		await process_frame
