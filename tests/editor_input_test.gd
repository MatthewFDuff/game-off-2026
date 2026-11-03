extends SceneTree
## The level editor's input rules (EditorInput), headless, with real input events:
##   godot --headless --path . --script res://tests/editor_input_test.gd
## Covers the play-test bugs: the wheel over a panel changing fly speed, Tab moving focus between
## controls, Space pressing a focused button, and keys moving the player while typing or while a
## modal is up. Works on a scratch copy of the lab level.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://editor_input_test_levels/"
const LEVEL := "lab_input_test"

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LevelData.save_dir_override = SCRATCH
	var to := SCRATCH.path_join(LEVEL)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to))
	for file in ["level.json", "voxels.bin"]:
		FileAccess.open(to.path_join(file), FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes("res://levels/lab".path_join(file)))
	root.get_node("Net").start_solo(LEVEL, "edit")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	var lab = current_scene
	var me = lab.local_player()
	var tool = me.get_node("EditorTool")
	var hud = lab.get_node("EditorHud")
	await _frames(5)
	tool.set_tool(5) # Prop: the catalog drawer is up.
	await _frames(3)

	# Buttons never take keyboard focus.
	var focusable: Array[String] = []
	for node in _descendants(hud._root):
		if node is BaseButton and node.focus_mode != Control.FOCUS_NONE:
			focusable.append(str(node.get_path()))
	_check("no editor button takes keyboard focus", focusable.is_empty(), ", ".join(focusable))

	# The wheel over a panel scrolls the panel, not the camera; over the world it zooms (builder
	# view) or sets the fly speed (walk view).
	root.notification(Node.NOTIFICATION_VP_MOUSE_ENTER) # Headless never says the mouse is in the window.
	var camera = tool.camera
	_check("starts in the builder view", tool.builder and camera.active and camera.camera.current)
	var zoom: float = camera.distance
	var over_drawer: Vector2 = hud._drawer.get_global_rect().get_center()
	await _move_mouse(over_drawer)
	_check("pointer over the catalog counts as over UI", EditorInput.pointer_over_ui())
	_check("no cursor while over the catalog", not tool.has_cursor)
	await _wheel(over_drawer)
	_check("wheel over the catalog leaves the zoom alone", is_equal_approx(camera.distance, zoom), "%.2f -> %.2f" % [zoom, camera.distance])
	var over_world: Vector2 = root.get_visible_rect().get_center()
	await _move_mouse(over_world)
	await _wheel(over_world)
	_check("wheel over the world zooms", camera.distance < zoom)

	tool.set_view(false)
	me.flying = true
	await _frames(2)
	var speed: float = me.fly_speed
	await _move_mouse(over_drawer)
	await _wheel(over_drawer)
	_check("walk view: wheel over the catalog leaves fly speed alone", is_equal_approx(me.fly_speed, speed), "%.2f -> %.2f" % [speed, me.fly_speed])
	await _move_mouse(over_world)
	await _wheel(over_world)
	_check("walk view: wheel over the world changes fly speed", not is_equal_approx(me.fly_speed, speed))
	tool.set_view(true)
	await _frames(2)

	# Typing in the search box: movement keys don't move the player or the camera, Tab stays put,
	# Esc lets go.
	hud._search.grab_focus()
	await _frames(1)
	var start: Vector3 = me.global_position
	var pivot: Vector3 = camera.pivot
	await _hold(KEY_W, 10)
	await _hold(KEY_SPACE, 10)
	_check("typing doesn't move the player", me.global_position.distance_to(start) < 0.01, str(me.global_position - start))
	_check("typing doesn't pan the camera", camera.pivot.distance_to(pivot) < 0.01, str(camera.pivot - pivot))
	await _key(KEY_TAB)
	_check("Tab doesn't move focus", root.gui_get_focus_owner() == hud._search)
	var tool_before: int = tool.tool
	await _key(KEY_1)
	_check("number keys type instead of switching tools", tool.tool == tool_before)
	await _key(KEY_ESCAPE)
	_check("Esc lets go of the text field", root.gui_get_focus_owner() == null)
	_check("...and keeps the tool", tool.tool == tool_before)

	# A modal holds every key.
	await _key(KEY_F1)
	_check("F1 opens help", hud._help.visible and EditorInput.modal_open())
	start = me.global_position
	await _hold(KEY_W, 10)
	_check("keys don't move the player behind a modal", me.global_position.distance_to(start) < 0.01)
	await _key(KEY_2)
	_check("tool keys don't reach the editor behind a modal", tool.tool == tool_before)
	await _key(KEY_ESCAPE)
	_check("Esc closes help", not hud._help.visible and not EditorInput.modal_open())

	# Esc backs out one step at a time.
	tool.set_tool(2) # Box
	await _frames(1)
	tool._corner = Vector3i(200, 40, 200)
	await _key(KEY_ESCAPE)
	_check("Esc drops a pending corner first", not tool.has_step())

	# Play-testing closes modals so they can't hold the keys during play.
	await _key(KEY_F1)
	lab.request_mode("play")
	await _frames(3)
	_check("play-test lets go of modals", not EditorInput.modal_open())
	lab.request_mode("edit")
	await _frames(3)
	_finish()


func _finish() -> void:
	print("editor input test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out


func _move_mouse(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event, true)
	await _frames(2)


func _wheel(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_UP
		event.position = at
		event.global_position = at
		event.pressed = pressed
		root.push_input(event, true)
		await _frames(2)


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)


func _hold(keycode: Key, frames: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(frames)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(2)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
