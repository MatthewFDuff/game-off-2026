extends SceneTree
## Screenshots of the cubicle (needs a window, not --headless), at 1152 x 648:
##   godot --path . --script res://tests/cubicle_shots.gd -- <output_dir>
## The spawn view, the hallway from the opening (across and down it), the reader, the clock-out
## prompt, the console's SPLASH, SIGN IN, MAIN, SETTINGS, HOST (a session opened and closed again),
## MAINTENANCE, JOIN, a shift on file (SINGLEPLAYER with CONTINUE lit, HOST with CONTINUE SHIFT,
## DISCARD, a stale layout), SINGLEPLAYER with none, the LOG with three lines, the email, the dying vignette, and a statement rolling and
## rolled. The name on file is put back at the end.

var _out := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1152, 648)
	var settings = root.get_node("GameSettings")
	var net = root.get_node("Net")
	var kept_name = settings.get_value("name")
	var kept_orientation = settings.get_value("orientation")
	settings.set_value("orientation", "play")
	settings.set_value("name", "")

	var cubicle = load("res://scenes/cubicle.tscn").instantiate()
	cubicle.pause_scale = 0.0
	cubicle.auto_start = false
	root.add_child(cubicle)
	await _frames(30)
	await _shot("cubicle_spawn")
	var player = cubicle.player
	var spawn: Vector3 = player.global_position
	var spawn_yaw: float = player.rotation.y
	var spawn_pitch: float = player.head.rotation.x
	var box: AABB = cubicle._leave_box
	player.teleport(Vector3(box.get_center().x, box.position.y, box.position.z - 0.05))
	player.rotation.y = PI
	player.head.rotation.x = -0.1
	await _frames(10)
	await _shot("cubicle_hallway_across")
	player.rotation.y = PI * 0.5
	await _frames(10)
	await _shot("cubicle_hallway_west")
	player.rotation.y = -PI * 0.5
	await _frames(10)
	await _shot("cubicle_hallway_east")
	player.teleport(spawn)
	player.rotation.y = spawn_yaw
	player.head.rotation.x = spawn_pitch
	await _frames(5)
	cubicle.interact("sticky")
	await _shot("cubicle_reader")
	cubicle.close_reader()
	cubicle.interact("sleeping_bag")
	await _shot("cubicle_clock_out")
	cubicle.close_clock_out()

	cubicle.use_monitor()
	await _frames(10)
	await _shot("console_splash")
	cubicle.press_shift()
	cubicle.type_text("Matthew")
	await _shot("console_sign_in")
	cubicle.press_enter()
	await _shot("console_main")
	cubicle.open_page(cubicle.Page.SETTINGS)
	await _shot("console_settings")
	cubicle.open_page(cubicle.Page.HOST)
	await _frames(5)
	await _shot("console_host")
	net.close_session()
	cubicle.open_page(cubicle.Page.MAINTENANCE)
	await _shot("console_maintenance")
	cubicle.open_page(cubicle.Page.JOIN)
	await _shot("console_join")

	# A shift on file (a scratch save): SINGLEPLAYER with CONTINUE lit, HOST with CONTINUE SHIFT, and
	# NEW GAME's DISCARD.
	ShiftSave.dir_override = "user://cubicle_shots_shift/"
	ShiftSave.write({level = "laboratory", checkpoint = "vat_compute", vat_room = "Compute stair lobby", elapsed = 3725.0,
		total_damage = 31100, deaths = 2, party = ["Matthew"], saved_at = int(Time.get_unix_time_from_system())}, PackedByteArray([0, 0, 0, 0]))
	cubicle.open_page(cubicle.Page.SINGLEPLAYER)
	await _shot("console_singleplayer_continue")
	cubicle.open_page(cubicle.Page.HOST)
	await _frames(5)
	await _shot("console_host_continue")
	net.close_session()
	cubicle.open_page(cubicle.Page.SINGLEPLAYER)
	cubicle.move_cursor(1)
	cubicle.press_enter()
	await _shot("console_discard")
	cubicle.back()
	ShiftSave.write({level = "laboratory", level_hash = "stale", checkpoint = "vat_compute", elapsed = 60.0}, PackedByteArray([0, 0, 0, 0]))
	cubicle.open_page(cubicle.Page.SINGLEPLAYER)
	await _shot("console_singleplayer_stale")
	ShiftSave.clear() # The scratch folder stays, so a real save on file does not light CONTINUE below.
	cubicle.open_page(cubicle.Page.SINGLEPLAYER)
	await _shot("console_singleplayer")

	cubicle.open_page(cubicle.Page.SINGLEPLAYER)
	cubicle.press_enter()
	await _frames(5)
	for i in 3:
		cubicle._pause_left = 0.0
		cubicle.press_shift()
	cubicle._pause_left = 0.0
	await _frames(5)
	cubicle._prompt.text = "[SHIFT]"
	cubicle._prompt.visible = true
	await _shot("console_log")
	cubicle._pause_left = 0.0
	cubicle.press_shift()
	cubicle.open_email()
	await _shot("console_email")
	cubicle.decline()
	cubicle._enter(cubicle.State.DYING)
	cubicle.pause_scale = 1.0
	cubicle._state_time = 16.0
	await _frames(3)
	await _shot("console_dying")
	cubicle.free()

	net.pending_statement = ["Shift wages|+$180", "Property damage:|", "   specimen case|-$25000", "   spore tank|-$6000", "   coffee machine|-$1100", "Replacements grown: 2 x $5000|-$10000", "Doors forced|-$0", "TOTAL OWED TO FUNG AI|-$41920"]
	net.pending_total = -41920
	var kept_shifts = settings.get_value("shifts_worked")
	var kept_balance = settings.get_value("balance_owed")
	var second = load("res://scenes/cubicle.tscn").instantiate()
	second.auto_start = false
	root.add_child(second)
	await _frames(30)
	await _shot("cubicle_statement_waiting")
	second.use_monitor()
	await create_timer(2.6).timeout
	await _shot("console_statement_rolling")
	await create_timer(5.0).timeout
	await _shot("console_statement_done")
	second.free()
	settings.set_value("shifts_worked", kept_shifts)
	settings.set_value("balance_owed", kept_balance)
	settings.set_value("name", kept_name)
	settings.set_value("orientation", kept_orientation)
	ShiftSave.dir_override = ""
	quit(0)


func _shot(name: String) -> void:
	await _frames(3)
	var path := _out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
