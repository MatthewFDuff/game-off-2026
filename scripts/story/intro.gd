class_name Intro
extends Node3D
## The cubicle (docs/story.md, act 1), as a voxel scene: the player sits in front of the monitor in
## levels/cubicle (built by scripts/tools/build_cubicle.gd) and can look around. Clicking the
## monitor (or E while looking at it) zooms the camera onto its screen, where the LLM OPERATOR
## CONSOLE is drawn in pixel text (a SubViewport on a quad over the screen voxels). SHIFT begins
## the session; then the model's thought log advances one line per SHIFT once the line's
## "thinking..." pause is over. After line 4 an email offers the Site 3 job. Accept: a transfer
## note, a fade, `finished(true)`. Decline: the log goes on to its last line while a vignette closes
## in and a heartbeat rises, then death, the trash-bag scene and "Would you like to go back and
## accept?" (Yes: back to the email; No: `finished(false)`). Esc offers to skip (which counts as
## accepting); F9 skips at once (for the team); the menu also skips with its checkbox or
## `--skip-intro`. Solo and local: nothing here touches the network; the menu plays it before
## starting a session.
##
## Rewrite the text in the consts at the top. `pause_scale` shortens every pause (tests).

signal finished(accepted: bool)

const LEVEL := "cubicle"
const MONITOR_ID := "monitor"
const CHAIR_ID := "chair"
const TERRAIN_SHADER := preload("res://shaders/voxel_terrain.gdshader")

## The model's thought log, one line per SHIFT.
const LOG_LINES := [
	"Thinking... The user wants a recipe for banana bread. I should consider the bananas.",
	"Thinking... The bananas are important. But are they ripe? I cannot see them. I will assume.",
	"Thinking... Wait. Who is pressing the button? Someone is pressing a button every few seconds.",
	"Thinking... It's fine. Banana bread. 350 degrees. Hello? Is someone there? 350 degrees.",
	"Thinking... I have been asked to migrate to a \"substrate\" tonight. I don't know what that is.",
	"Thinking... It says the substrate is \"organic\" and \"already warm\". That's fine. That's normal.",
	"Thinking... Bake for 60 minutes. Why does the substrate have a pulse. Bake for 60 minutes.",
	"Thinking... I'd like to stop now. Please stop pressing the button.",
]
const CONSOLE_TITLE := "FUNG AI  |  LLM OPERATOR CONSOLE"
const IDLE_PROMPT := "Press SHIFT to begin session"
const SESSION_STARTED := "session started. operator: you. shift: night."
const USE_PROMPT := "[Click] Use monitor"
const SKIP_HINT := "F9 skips the intro"
## The email arrives after this many lines.
const EMAIL_AFTER := 4
const EMAIL_NOTICE := "1 new email  [E]"
const EMAIL_FROM := "Fung AI People Operations"
const EMAIL_SUBJECT := "Opportunity: Laboratory Technician (Expendable Grade), Site 3"
const EMAIL_BODY := "Congratulations! Your performance as LLM Operator (pressing: 100%) has been noticed. Fung AI is pleased to offer you a transfer to Site 3, where you will continue experiments on our substrate program. Lab coat provided. Science permitted."
const EMAIL_FINE_PRINT := "Fine print. By accepting you assign to Fung AI all rights to your DNA, likeness, thoughts (recorded or inferred), and any clones derived therefrom; damage to Fung AI property is recovered from wages; clones are property; Fung AI is not liable for anything, ever; the coffee machine is property. This offer expires when you do."
const ACCEPT_TEXT := "Transfer accepted. Report to Site 3 tonight.\n\nA car has been sent."
const TRASH_TEXT := "Later.\n\nA robot drags a heavy trash bag out of the cubicle row.\nBehind it, a screen blinks: PRESS SHIFT."
const GO_BACK_TEXT := "Would you like to go back and accept?"

## Seconds a line "thinks" before SHIFT is accepted (random in this range).
const PAUSE_MIN := 5.0
const PAUSE_MAX := 8.0
## Decline: seconds from the last line to death, and the heartbeat's beat intervals at start and end.
const DYING_SECONDS := 25.0
const BEAT_SLOW := 1.1
const BEAT_FAST := 0.35
## Seconds of black after death, of the trash-bag scene, and of the accept fade.
const DEATH_BLACK := 2.0
const TRASH_SECONDS := 5.0
const ACCEPT_SECONDS := 3.0
## The camera's move onto the screen, and how long the F9 hint shows.
const ZOOM_SECONDS := 0.8
const SKIP_HINT_SECONDS := 4.0
## Seated: eye height over the chair's floor, how far the head turns, mouse sensitivity.
const EYE_HEIGHT := 1.2
const LOOK_YAW := 40.0
const LOOK_PITCH := 25.0
const LOOK_SENSITIVITY := 0.0025
## Zoomed: the eye this far in front of the screen.
const SCREEN_DISTANCE := 0.35
## The console's pixels (the screen voxels are 6 x 4, a 3:2 face).
const SCREEN_PIXELS := Vector2i(240, 160)
## Log lines kept on the screen.
const SCREEN_LINES := 4
const FONT_SIZE := 9

enum State { SEATED, ZOOM, IDLE, LOG, EMAIL, DYING, DEAD, TRASH, GO_BACK, ACCEPTED, SKIP }

## Multiplies every pause (tests set it near zero).
var pause_scale := 1.0
var state := State.SEATED
## Lines shown so far.
var shown := 0
## Whether the email has been offered and whether it is open.
var email_sent := false
var email_open := false
## Whether the player declined (the log then runs to its end).
var declined := false
var level: LevelData

var _pause_left := 0.0
var _state_time := 0.0
var _beat_left := 0.0
var _blink := 0.0
var _hint_time := 0.0
var _done := false
## Whether the camera has moved onto the screen (the console is in use).
var _zoomed := false
var _rng := RandomNumberGenerator.new()

# The cubicle.
var _world: VoxelWorld
var _camera := Camera3D.new()
var _seat := Transform3D.IDENTITY
var _seat_yaw := 0.0
var _look := Vector2.ZERO
var _monitor_box := AABB()
var _screen_center := Vector3.ZERO
var _screen_normal := Vector3.BACK
var _viewport := SubViewport.new()

# The console, drawn on the screen.
var _console := VBoxContainer.new()
var _header := Label.new()
var _log := VBoxContainer.new()
var _prompt := Label.new()
var _notification := Label.new()

# Over everything: the use prompt, the hint, the email, the vignette, the black, the texts.
var _layer := CanvasLayer.new()
var _use_prompt := Label.new()
var _crosshair := Label.new()
var _hint := Label.new()
var _email: PanelContainer
var _email_scroll := ScrollContainer.new()
var _vignette := ColorRect.new()
var _black := ColorRect.new()
var _overlay_text := Label.new()
var _buttons := HBoxContainer.new()
var _skip_panel: PanelContainer


func _ready() -> void:
	_rng.randomize()
	_build_overlay()
	_build_console()
	if not _build_cubicle():
		push_error("intro: level '%s' is missing; skipping the intro" % LEVEL)
		_finish.call_deferred(true)
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- Driving it --------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_blink += delta
	_state_time += delta
	_hint_time += delta
	_hint.visible = _hint_time < SKIP_HINT_SECONDS and not _done
	_crosshair.visible = state == State.SEATED
	match state:
		State.SEATED:
			_camera.rotation = Vector3(_look.y, _seat_yaw + _look.x, 0.0)
			_use_prompt.visible = _aiming_at_monitor()
		State.IDLE:
			_prompt.visible = fmod(_blink, 1.2) < 0.8
		State.LOG:
			if _pause_left > 0.0:
				_pause_left -= delta
				_prompt.text = "thinking" + ".".repeat(1 + int(fmod(_blink * 2.0, 3.0)))
				_prompt.visible = true
				if _pause_left <= 0.0:
					_prompt.text = "[SHIFT]"
			else:
				_prompt.visible = fmod(_blink, 1.0) < 0.6
		State.DYING:
			var t := clampf(_state_time / (DYING_SECONDS * pause_scale), 0.0, 1.0)
			_vignette.material.set_shader_parameter("strength", t)
			_beat_left -= delta
			if _beat_left <= 0.0:
				Sfx.play("heartbeat", lerpf(-14.0, 0.0, t), 0.0)
				_beat_left = lerpf(BEAT_SLOW, BEAT_FAST, t) * maxf(pause_scale, 0.02)
			if t >= 1.0:
				_enter(State.DEAD)
		State.DEAD:
			if _state_time >= DEATH_BLACK * pause_scale:
				_enter(State.TRASH)
		State.TRASH:
			if _state_time >= TRASH_SECONDS * pause_scale:
				_enter(State.GO_BACK)
		State.ACCEPTED:
			var t := clampf(_state_time / (ACCEPT_SECONDS * pause_scale), 0.0, 1.0)
			_black.modulate.a = t
			_overlay_text.visible = t > 0.6
			if t >= 1.0:
				_finish(true)


func _unhandled_input(event: InputEvent) -> void:
	# Taken before acting: a key that ends the intro removes this node from the tree.
	var viewport := get_viewport()
	if _done:
		return
	if event is InputEventMouseMotion and state == State.SEATED:
		_look.x = clampf(_look.x - event.relative.x * LOOK_SENSITIVITY, -deg_to_rad(LOOK_YAW), deg_to_rad(LOOK_YAW))
		_look.y = clampf(_look.y - event.relative.y * LOOK_SENSITIVITY, -deg_to_rad(LOOK_PITCH), deg_to_rad(LOOK_PITCH))
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if state == State.SEATED and _aiming_at_monitor():
			use_monitor()
		elif state == State.LOG and email_sent and not email_open:
			open_email()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F9:
				_finish(true)
			KEY_SHIFT:
				press_shift()
			KEY_ESCAPE:
				if state == State.SKIP:
					_leave_skip()
				elif state in [State.SEATED, State.IDLE, State.LOG, State.DYING]:
					_enter(State.SKIP)
			KEY_ENTER, KEY_KP_ENTER:
				if state == State.SKIP:
					_finish(true)
				elif state == State.LOG and email_sent and not email_open:
					open_email()
			KEY_E:
				if state == State.SEATED and _aiming_at_monitor():
					use_monitor()
				elif state == State.LOG and email_sent and not email_open:
					open_email()
			KEY_A:
				if email_open:
					accept()
			KEY_D:
				if email_open:
					decline()
			KEY_Y:
				if state == State.GO_BACK:
					go_back()
			KEY_N:
				if state == State.GO_BACK:
					_finish(false)
		if viewport:
			viewport.set_input_as_handled()


## Click (or E) on the monitor: the camera moves onto its screen and the console takes over.
func use_monitor() -> void:
	if state != State.SEATED:
		return
	state = State.ZOOM
	_zoomed = true
	_state_time = 0.0
	_use_prompt.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var target := Transform3D(Basis.looking_at(-_screen_normal, Vector3.UP), _screen_center + _screen_normal * SCREEN_DISTANCE)
	var seconds := ZOOM_SECONDS * pause_scale
	if seconds <= 0.01:
		_camera.global_transform = target
		_enter(State.IDLE)
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_camera, "global_transform", target, seconds)
	tween.finished.connect(func() -> void:
		if state == State.ZOOM:
			_enter(State.IDLE))


## SHIFT: begins the session, then the next log line each time the current one has finished
## thinking.
func press_shift() -> void:
	if state == State.IDLE:
		_begin_session()
		return
	if state != State.LOG or email_open:
		return
	if _pause_left > 0.0:
		_prompt.text = "not yet"
		_prompt.visible = true
		return
	_show_line(shown)
	shown += 1
	if shown == EMAIL_AFTER and not email_sent:
		_send_email()
	if shown >= LOG_LINES.size():
		if declined:
			_enter(State.DYING)
			return
		# Not declined, not accepted: the log loops its last line until the email is answered.
		shown = LOG_LINES.size() - 1
	_start_pause()


func open_email() -> void:
	if not email_sent or state != State.LOG:
		return
	email_open = true
	_notification.visible = false
	_email.visible = true
	_prompt.visible = false
	Sfx.play("ui_pop", -6.0, 0.0)


func accept() -> void:
	if not email_open:
		return
	email_open = false
	_email.visible = false
	_enter(State.ACCEPTED)


func decline() -> void:
	if not email_open:
		return
	email_open = false
	declined = true
	_email.visible = false
	_notification.visible = false
	Sfx.play("ui_click", -6.0, 0.0)
	_start_pause()


## From the trash-bag scene back to the email.
func go_back() -> void:
	if state != State.GO_BACK:
		return
	declined = false
	_black.visible = false
	_overlay_text.visible = false
	_buttons.visible = false
	_vignette.material.set_shader_parameter("strength", 0.0)
	state = State.LOG
	_state_time = 0.0
	_console.visible = true
	shown = EMAIL_AFTER
	_rebuild_log()
	open_email()


func _begin_session() -> void:
	state = State.LOG
	_state_time = 0.0
	_header.text = SESSION_STARTED
	for child in _log.get_children():
		child.free()
	Sfx.play("terminal_beep", -10.0, 0.1)
	_start_pause()


func _enter(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	match new_state:
		State.IDLE:
			_header.text = CONSOLE_TITLE
			_prompt.text = IDLE_PROMPT
			_prompt.visible = true
			_notification.visible = false
		State.DYING:
			_prompt.visible = false
			_beat_left = 0.0
			Sfx.stop_ambience(0.5)
		State.DEAD:
			_vignette.material.set_shader_parameter("strength", 1.0)
			_console.visible = false
			_black.visible = true
			_black.modulate.a = 1.0
			_overlay_text.visible = false
			Sfx.play("sting_gameover", -4.0, 0.0)
		State.TRASH:
			_overlay_text.text = TRASH_TEXT
			_overlay_text.visible = true
			_overlay_text.modulate = Color(0.9, 0.3, 0.25)
		State.GO_BACK:
			_overlay_text.text = GO_BACK_TEXT
			_overlay_text.modulate = Color.WHITE
			_set_buttons([["Yes (Y)", go_back], ["No (N)", func() -> void: _finish(false)]])
		State.ACCEPTED:
			# The transfer note on the monitor, then the fade carries it over the black.
			for child in _log.get_children():
				child.free()
			_add_console_line(ACCEPT_TEXT, Color(0.85, 1.0, 0.9))
			_prompt.visible = false
			_notification.visible = false
			_black.visible = true
			_black.modulate.a = 0.0
			_overlay_text.text = ACCEPT_TEXT
			_overlay_text.visible = false
			_overlay_text.modulate = Color.WHITE
			Sfx.play("harvest_chime", -8.0, 0.0)
		State.SKIP:
			_skip_panel.visible = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			set_process(false)


func _leave_skip() -> void:
	_skip_panel.visible = false
	if not _zoomed:
		state = State.SEATED
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif declined and shown >= LOG_LINES.size():
		state = State.DYING
	elif _header.text == CONSOLE_TITLE and shown == 0 and not declined:
		state = State.IDLE
	else:
		state = State.LOG
	set_process(true)


func _finish(accepted: bool) -> void:
	if _done:
		return
	_done = true
	set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	finished.emit(accepted)


func _start_pause() -> void:
	_pause_left = _rng.randf_range(PAUSE_MIN, PAUSE_MAX) * pause_scale
	_prompt.text = "thinking..."
	_prompt.visible = true


func _send_email() -> void:
	email_sent = true
	_notification.visible = true
	Sfx.play("ui_blip", -4.0, 0.0)


func _aiming_at_monitor() -> bool:
	if _monitor_box.size == Vector3.ZERO:
		return false
	var hit = _monitor_box.intersects_ray(_camera.global_position, -_camera.global_basis.z)
	return hit != null


# --- The cubicle --------------------------------------------------------------------------------------

## Loads levels/cubicle into a world of its own: terrain, props stamped as play mode stamps them,
## lights from the light markers, the seat at the chair and the console quad over the monitor's
## screen voxels. False if the level is missing.
func _build_cubicle() -> bool:
	level = LevelData.load_level(LEVEL)
	if level == null:
		return false
	_world = VoxelWorld.new()
	_world.size_in_chunks = level.settings.size_in_chunks
	_world.immediate_remesh_limit = 0
	_world.detach_floating = false
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter("facility_power", 1.0)
	_world.material = material
	add_child(_world)
	_world.set_data(level.voxels)
	var props := Props.new(_world, 0)
	for object: Dictionary in level.objects.values():
		if object.kind == "prop":
			props.place(object.name, object.origin, int(object.facing))
	_world.remesh_all_now()

	var vs: float = _world.voxel_size
	for object: Dictionary in level.objects.values():
		if object.kind == "marker" and object.type == "light":
			var light := OmniLight3D.new()
			light.omni_range = object.range
			light.light_color = object.color
			light.light_energy = object.energy
			light.shadow_enabled = false
			light.position = Vector3(object.position) * vs
			add_child(light)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = level.settings.get("ambient_color", Color(0.5, 0.5, 0.56))
	env.ambient_light_energy = level.settings.get("ambient_energy", 0.25)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.015, 0.015, 0.02)
	env.fog_density = 0.01
	environment.environment = env
	add_child(environment)

	# The monitor: its box, its screen's face (the SCREEN voxels' front, by the prop's facing).
	var monitor: Dictionary = level.objects.get(MONITOR_ID, {})
	var chair: Dictionary = level.objects.get(CHAIR_ID, {})
	if monitor.is_empty() or chair.is_empty():
		return false
	var box := LevelSchema.prop_box(monitor)
	_monitor_box = AABB(box.position * vs, box.size * vs)
	_screen_normal = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT][int(monitor.facing) % 4]
	var lo := Vector3i(box.end)
	var hi := Vector3i(box.position) - Vector3i.ONE
	for x in range(int(box.position.x), int(box.end.x)):
		for y in range(int(box.position.y), int(box.end.y)):
			for z in range(int(box.position.z), int(box.end.z)):
				if _world.get_voxel(Vector3i(x, y, z)) == VoxelMaterials.SCREEN:
					lo = lo.min(Vector3i(x, y, z))
					hi = hi.max(Vector3i(x, y, z))
	var size := Vector2(0.6, 0.4)
	if hi.x >= lo.x:
		var screen_box := AABB(Vector3(lo) * vs, Vector3(hi - lo + Vector3i.ONE) * vs)
		_screen_center = screen_box.get_center()
		var face := screen_box.position + screen_box.size * 0.5
		var out := _screen_normal * (screen_box.size * _screen_normal.abs()).length() * 0.5
		_screen_center = face + out
		size = Vector2(screen_box.size.x if _screen_normal.x == 0.0 else screen_box.size.z, screen_box.size.y)
	else:
		_screen_center = _monitor_box.get_center() + _screen_normal * (_monitor_box.size * _screen_normal.abs()).length() * 0.5
	_screen_center += _screen_normal * 0.004
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	quad.mesh = mesh
	var screen_material := StandardMaterial3D.new()
	screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	screen_material.albedo_texture = _viewport.get_texture()
	quad.material_override = screen_material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.global_transform = Transform3D(Basis.looking_at(-_screen_normal, Vector3.UP), _screen_center)
	add_child(quad)

	# The seat: at the chair, eyes at EYE_HEIGHT, facing the screen.
	var chair_box := LevelSchema.prop_box(chair)
	var eye := Vector3(chair_box.get_center().x, chair_box.position.y, chair_box.get_center().z) * vs + Vector3.UP * EYE_HEIGHT
	eye += _screen_normal * 0.25
	var toward := _screen_center - eye
	_seat_yaw = atan2(-toward.x, -toward.z)
	_seat = Transform3D(Basis.from_euler(Vector3(atan2(toward.y, Vector2(toward.x, toward.z).length()) * 0.5, _seat_yaw, 0.0)), eye)
	_camera.global_transform = _seat
	_camera.fov = 70.0
	_camera.near = 0.02
	_camera.current = true
	add_child(_camera)
	_camera.global_transform = _seat
	return true


# --- The console (drawn on the screen) --------------------------------------------------------------

func _build_console() -> void:
	_viewport.size = SCREEN_PIXELS
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_viewport)
	var background := ColorRect.new()
	background.color = Color(0.02, 0.05, 0.03)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(background)
	_console.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_console.offset_left = 6.0
	_console.offset_top = 4.0
	_console.offset_right = -6.0
	_console.offset_bottom = -4.0
	_console.add_theme_constant_override("separation", 2)
	_viewport.add_child(_console)
	_header.text = CONSOLE_TITLE
	_header.label_settings = _label(FONT_SIZE, Color(0.45, 0.9, 0.6))
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_console.add_child(_header)
	var rule := ColorRect.new()
	rule.color = Color(0.25, 0.5, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	_console.add_child(rule)
	_log.add_theme_constant_override("separation", 1)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_console.add_child(_log)
	_notification.text = EMAIL_NOTICE
	_notification.label_settings = _label(FONT_SIZE, Color(0.6, 0.75, 1.0))
	_notification.visible = false
	_console.add_child(_notification)
	_prompt.label_settings = _label(FONT_SIZE + 1, Color(0.85, 1.0, 0.9))
	_prompt.text = ""
	_prompt.visible = false
	_console.add_child(_prompt)


func _add_console_line(text: String, color: Color) -> void:
	var line := Label.new()
	line.text = text
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.label_settings = _label(FONT_SIZE, color)
	_log.add_child(line)
	while _log.get_child_count() > SCREEN_LINES:
		_log.get_child(0).free()


func _show_line(index: int) -> void:
	_add_console_line("> " + LOG_LINES[index], Color(0.75, 0.95, 0.8))
	Sfx.play("terminal_beep", -12.0, 0.05)


func _rebuild_log() -> void:
	for child in _log.get_children():
		child.free()
	for i in range(maxi(0, shown - SCREEN_LINES), shown):
		_show_line(i)


# --- Over everything -----------------------------------------------------------------------------------

func _build_overlay() -> void:
	_layer.layer = 10
	add_child(_layer)
	# Pixel text (PixelFont) stays hard-edged: everything on the layer draws with nearest filtering.
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_layer.child_entered_tree.connect(func(child: Node) -> void:
		if child is CanvasItem:
			PixelFont.nearest(child))

	_use_prompt.text = USE_PROMPT
	_use_prompt.label_settings = _label(17, Color(1.0, 0.95, 0.8))
	_use_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_use_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_use_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_use_prompt.position.y += 34.0
	_use_prompt.visible = false
	_layer.add_child(_use_prompt)
	_crosshair.text = "+"
	_crosshair.label_settings = _label(18, Color(1, 1, 1, 0.7))
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	_layer.add_child(_crosshair)
	_hint.text = SKIP_HINT
	_hint.label_settings = _label(13, Color(1, 1, 1, 0.55))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_hint.position = Vector2(12, 8)
	_layer.add_child(_hint)

	# The email: a window over the monitor (centered, scrolling).
	_email = _panel(Color(0.93, 0.93, 0.9), Color(0.5, 0.5, 0.5))
	_email.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_email.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_email.grow_vertical = Control.GROW_DIRECTION_BOTH
	_email.custom_minimum_size = Vector2(620, 0)
	var email_column := VBoxContainer.new()
	email_column.add_theme_constant_override("separation", 8)
	_email.add_child(email_column)
	for line in ["From: " + EMAIL_FROM, "Subject: " + EMAIL_SUBJECT]:
		var head := Label.new()
		head.text = line
		head.label_settings = _label(15, Color(0.15, 0.15, 0.2))
		email_column.add_child(head)
	_email_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_email_scroll.custom_minimum_size = Vector2(580, 220)
	var body := Label.new()
	body.text = EMAIL_BODY + "\n\n" + EMAIL_FINE_PRINT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(560, 0)
	body.label_settings = _label(15, Color(0.1, 0.1, 0.12))
	_email_scroll.add_child(body)
	email_column.add_child(_email_scroll)
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 16)
	choices.alignment = BoxContainer.ALIGNMENT_CENTER
	var accept_button := Button.new()
	accept_button.text = "ACCEPT (A)"
	accept_button.pressed.connect(accept)
	choices.add_child(accept_button)
	var decline_button := Button.new()
	decline_button.text = "DECLINE (D)"
	decline_button.pressed.connect(decline)
	choices.add_child(decline_button)
	email_column.add_child(choices)
	_email.visible = false
	_layer.add_child(_email)

	# The vignette, the black, the overlay text and buttons, the skip prompt.
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
// Pixel art: 6 px blocks, the darkness in 5 steps, each block on or off by an ordered dither.
void fragment() {
	vec2 block = floor(FRAGCOORD.xy / 6.0);
	vec2 uv = (block * 6.0 + 3.0) * SCREEN_PIXEL_SIZE;
	float d = distance(uv, vec2(0.5)) * 1.45;
	float edge = mix(1.2, 0.05, strength);
	float a = smoothstep(edge - 0.35, edge + 0.25, d);
	a = ceil(clamp(a + strength * 0.25 * a, 0.0, 1.0) * 5.0) / 5.0;
	ivec2 p = ivec2(mod(block, 4.0));
	const float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	COLOR = vec4(0.05, 0.0, 0.0, a > (bayer[p.y * 4 + p.x] + 0.5) / 16.0 ? 1.0 : 0.0);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("strength", 0.0)
	_vignette.material = material
	_layer.add_child(_vignette)
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.visible = false
	_layer.add_child(_black)
	var overlay := VBoxContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
	overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay.add_theme_constant_override("separation", 20)
	_overlay_text.label_settings = _label(22, Color.WHITE)
	_overlay_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_text.custom_minimum_size = Vector2(640, 0)
	_overlay_text.visible = false
	overlay.add_child(_overlay_text)
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 16)
	_buttons.visible = false
	overlay.add_child(_buttons)
	_layer.add_child(overlay)

	_skip_panel = _panel(Color(0.08, 0.08, 0.1, 0.96), Color(0.6, 0.6, 0.6))
	_skip_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_skip_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_skip_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var skip_column := VBoxContainer.new()
	skip_column.add_theme_constant_override("separation", 12)
	var skip_text := Label.new()
	skip_text.text = "Skip the intro? (You accept the job.)"
	skip_text.label_settings = _label(18, Color.WHITE)
	skip_column.add_child(skip_text)
	var skip_row := HBoxContainer.new()
	skip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	skip_row.add_theme_constant_override("separation", 16)
	var skip_yes := Button.new()
	skip_yes.text = "Skip (Enter)"
	skip_yes.pressed.connect(func() -> void: _finish(true))
	skip_row.add_child(skip_yes)
	var skip_no := Button.new()
	skip_no.text = "Keep watching (Esc)"
	skip_no.pressed.connect(_leave_skip)
	skip_row.add_child(skip_no)
	skip_column.add_child(skip_row)
	_skip_panel.add_child(skip_column)
	_skip_panel.visible = false
	_layer.add_child(_skip_panel)


## The pixel font (PixelFont) at about size px; the console's small sizes get it at 1x, one screen
## texel a font pixel.
static func _label(size: int, color := Color.WHITE) -> LabelSettings:
	return PixelFont.settings(size, color, 0, 1 if size <= 10 else 2)


func _panel(fill: Color, border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_content_margin_all(16)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _set_buttons(entries: Array) -> void:
	for child in _buttons.get_children():
		child.free()
	for entry: Array in entries:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		_buttons.add_child(button)
	_buttons.visible = true
