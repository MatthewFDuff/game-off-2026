extends SceneTree
## Screenshots of the cubicle intro (needs a window, not --headless):
##   godot --path . --script res://tests/intro_shots.gd -- <output_dir>
## The seated view with the use prompt, the zoomed monitor with the idle console, the monitor with
## three log lines and the SHIFT prompt, the email, and the dying vignette.

var _out := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	root.size = Vector2i(1280, 800)
	var intro = load("res://scenes/intro.tscn").instantiate()
	intro.pause_scale = 0.0
	root.add_child(intro)
	await _frames(20)
	await _shot("intro_seated")
	intro.use_monitor()
	await _frames(10)
	await _shot("intro_monitor_idle")
	intro.press_shift()
	await _frames(5)
	for i in 3:
		intro._pause_left = 0.0
		intro.press_shift()
	intro._pause_left = 0.0
	await _frames(5)
	intro._prompt.text = "[SHIFT]"
	intro._prompt.visible = true
	await _shot("intro_monitor_log")
	intro._pause_left = 0.0
	intro.press_shift()
	intro.open_email()
	await _shot("intro_email")
	intro.decline()
	intro._enter(intro.State.DYING)
	intro.pause_scale = 1.0
	intro._state_time = 16.0
	await _frames(3)
	await _shot("intro_dying")
	quit(0)


func _shot(name: String) -> void:
	await _frames(3)
	var path := _out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
