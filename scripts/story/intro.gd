class_name Intro
extends Control
## The cubicle (docs/story.md, act 1): an LLM OPERATOR CONSOLE whose thought log advances one line
## each time the player presses SHIFT once the line's "thinking" pause is over. After line 4 an
## email offers the Site 3 job. Accept: a transfer note, a fade, `finished(true)`. Decline: the log
## goes on to its last line and loops it while a vignette closes in and a heartbeat rises, then
## death, the trash-bag scene and "Would you like to go back and accept?" (Yes: back to the email;
## No: `finished(false)`). Esc offers to skip (which counts as accepting). Solo and local: nothing
## here touches the network; the menu plays it before starting a session.
##
## Rewrite the text in the consts at the top. `pause_scale` shortens the pauses (tests).

signal finished(accepted: bool)

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
## The email arrives after this many lines.
const EMAIL_AFTER := 4
const EMAIL_FROM := "Fung AI People Operations"
const EMAIL_SUBJECT := "Opportunity: Laboratory Technician (Expendable Grade), Site 3"
const EMAIL_BODY := "Congratulations! Your performance as LLM Operator (pressing: 100%) has been noticed. Fung AI is pleased to offer you a transfer to Site 3, where you will continue experiments on our substrate program. Lab coat provided. Science permitted."
const EMAIL_FINE_PRINT := "Fine print. By accepting you assign to Fung AI all rights to your DNA, likeness, thoughts (recorded or inferred), and any clones derived therefrom; damage to Fung AI property is recovered from wages; clones are property; Fung AI is not liable for anything, ever; the coffee machine is property. This offer expires when you do."
const ACCEPT_TEXT := "Transfer accepted. Report to Site 3 tonight.\n\nA car has been sent."
const TRASH_TEXT := "Later.\n\nA robot drags a heavy trash bag out of the cubicle row.\nBehind it, a screen blinks: PRESS SHIFT."
const GO_BACK_TEXT := "Would you like to go back and accept?"
const STICKY_NOTE := "PRESS SHIFT WHEN IT STOPS.\nDO NOT READ IT.\n- mgmt"

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

enum State { LOG, EMAIL, DYING, DEAD, TRASH, GO_BACK, ACCEPTED, SKIP }

## Multiplies every pause (tests set it near zero).
var pause_scale := 1.0
var state := State.LOG
## Lines shown so far.
var shown := 0
## Whether the email has been offered and whether it is open.
var email_sent := false
var email_open := false
## Whether the player declined (the log then runs to its end).
var declined := false

var _pause_left := 0.0
var _state_time := 0.0
var _beat_left := 0.0
var _blink := 0.0
var _rng := RandomNumberGenerator.new()

var _console := VBoxContainer.new()
var _log := VBoxContainer.new()
var _prompt := Label.new()
var _notification: PanelContainer
var _email: PanelContainer
var _email_scroll := ScrollContainer.new()
var _vignette := ColorRect.new()
var _black := ColorRect.new()
var _overlay_text := Label.new()
var _buttons := HBoxContainer.new()
var _skip_panel: PanelContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rng.randomize()
	_build()
	_start_pause()


# --- Driving it --------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_blink += delta
	_state_time += delta
	match state:
		State.LOG:
			if _pause_left > 0.0:
				_pause_left -= delta
				if _pause_left <= 0.0:
					_prompt.text = "[SHIFT]"
			_prompt.visible = _pause_left <= 0.0 and fmod(_blink, 1.0) < 0.6
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
			_black.modulate.a = clampf(_state_time / (ACCEPT_SECONDS * pause_scale), 0.0, 1.0)
			if _state_time >= ACCEPT_SECONDS * pause_scale:
				_finish(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SHIFT:
				press_shift()
			KEY_ESCAPE:
				if state == State.SKIP:
					_leave_skip()
				elif state in [State.LOG, State.EMAIL, State.DYING]:
					_enter(State.SKIP)
			KEY_ENTER, KEY_KP_ENTER:
				if state == State.SKIP:
					_finish(true)
				elif state == State.LOG and email_sent and not email_open:
					open_email()
			KEY_E:
				if state == State.LOG and email_sent and not email_open:
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
		get_viewport().set_input_as_handled()


## SHIFT: the next log line, if the current one has finished thinking.
func press_shift() -> void:
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


func _enter(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	match new_state:
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
			_console.visible = false
			_black.visible = true
			_black.modulate.a = 0.0
			_overlay_text.text = ACCEPT_TEXT
			_overlay_text.visible = true
			_overlay_text.modulate = Color.WHITE
			Sfx.play("harvest_chime", -8.0, 0.0)
		State.SKIP:
			_skip_panel.visible = true
			set_process(false)


func _leave_skip() -> void:
	_skip_panel.visible = false
	state = State.LOG if not declined or shown < LOG_LINES.size() else State.DYING
	set_process(true)


func _finish(accepted: bool) -> void:
	set_process(false)
	finished.emit(accepted)


func _start_pause() -> void:
	_pause_left = _rng.randf_range(PAUSE_MIN, PAUSE_MAX) * pause_scale
	_prompt.text = "thinking..."
	_prompt.visible = false


func _send_email() -> void:
	email_sent = true
	_notification.visible = true
	Sfx.play("ui_blip", -4.0, 0.0)


# --- Building the screen -----------------------------------------------------------------------------

func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.05, 0.05, 0.06)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	# The cubicle: a wall color band, the poster and the sticky note around the monitor.
	var wall := ColorRect.new()
	wall.color = Color(0.22, 0.2, 0.17)
	wall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wall.offset_bottom = -140.0
	add_child(wall)
	var poster := _panel(Color(0.85, 0.72, 0.35), Color(0.3, 0.25, 0.1))
	poster.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	poster.position = Vector2(40, 40)
	var poster_text := Label.new()
	poster_text.text = "HANG\nIN\nTHERE"
	poster_text.label_settings = _label(22, Color(0.2, 0.15, 0.05), 0)
	poster_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	poster.add_child(poster_text)
	add_child(poster)
	var sticky := _panel(Color(0.95, 0.9, 0.45), Color(0.6, 0.55, 0.2))
	sticky.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	sticky.position = Vector2(-280, 60)
	sticky.rotation = 0.06
	var sticky_text := Label.new()
	sticky_text.text = STICKY_NOTE
	sticky_text.label_settings = _label(14, Color(0.2, 0.15, 0.05), 0)
	sticky.add_child(sticky_text)
	add_child(sticky)

	# The monitor.
	var monitor := _panel(Color(0.02, 0.05, 0.03), Color(0.25, 0.3, 0.28))
	monitor.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	monitor.grow_horizontal = Control.GROW_DIRECTION_BOTH
	monitor.grow_vertical = Control.GROW_DIRECTION_BOTH
	monitor.custom_minimum_size = Vector2(760, 420)
	add_child(monitor)
	_console.add_theme_constant_override("separation", 8)
	monitor.add_child(_console)
	var header := Label.new()
	header.text = "LLM OPERATOR CONSOLE  |  Fung AI  |  operator: you  |  shift: night"
	header.label_settings = _label(15, Color(0.45, 0.9, 0.6), 0)
	_console.add_child(header)
	var rule := ColorRect.new()
	rule.color = Color(0.25, 0.5, 0.35)
	rule.custom_minimum_size = Vector2(0, 2)
	_console.add_child(rule)
	_log.add_theme_constant_override("separation", 6)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_console.add_child(_log)
	_prompt.label_settings = _label(20, Color(0.85, 1.0, 0.9), 0)
	_prompt.text = "thinking..."
	_console.add_child(_prompt)

	# The email notification (top right) and the email itself (centered, scrolling).
	_notification = _panel(Color(0.1, 0.12, 0.2, 0.97), Color(0.4, 0.55, 0.9))
	_notification.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_notification.position = Vector2(-330, 16)
	var note_row := VBoxContainer.new()
	var note := Label.new()
	note.text = "1 new email: Fung AI People Operations"
	note.label_settings = _label(15, Color.WHITE, 0)
	note_row.add_child(note)
	var open_button := Button.new()
	open_button.text = "Open (E)"
	open_button.pressed.connect(open_email)
	note_row.add_child(open_button)
	_notification.add_child(note_row)
	_notification.visible = false
	add_child(_notification)

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
		head.label_settings = _label(15, Color(0.15, 0.15, 0.2), 0)
		email_column.add_child(head)
	_email_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_email_scroll.custom_minimum_size = Vector2(580, 220)
	var body := Label.new()
	body.text = EMAIL_BODY + "\n\n" + EMAIL_FINE_PRINT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(560, 0)
	body.label_settings = _label(15, Color(0.1, 0.1, 0.12), 0)
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
	add_child(_email)

	# The vignette, the black, the overlay text and buttons, the skip prompt.
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5)) * 1.45;
	float edge = mix(1.2, 0.05, strength);
	float a = smoothstep(edge - 0.35, edge + 0.25, d);
	COLOR = vec4(0.05, 0.0, 0.0, clamp(a + strength * 0.25 * a, 0.0, 1.0));
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("strength", 0.0)
	_vignette.material = material
	add_child(_vignette)
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.visible = false
	add_child(_black)
	var overlay := VBoxContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
	overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay.add_theme_constant_override("separation", 20)
	_overlay_text.label_settings = _label(22, Color.WHITE, 0)
	_overlay_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_text.custom_minimum_size = Vector2(640, 0)
	_overlay_text.visible = false
	overlay.add_child(_overlay_text)
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 16)
	_buttons.visible = false
	overlay.add_child(_buttons)
	add_child(overlay)

	_skip_panel = _panel(Color(0.08, 0.08, 0.1, 0.96), Color(0.6, 0.6, 0.6))
	_skip_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_skip_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_skip_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var skip_column := VBoxContainer.new()
	skip_column.add_theme_constant_override("separation", 12)
	var skip_text := Label.new()
	skip_text.text = "Skip the intro? (You accept the job.)"
	skip_text.label_settings = _label(18, Color.WHITE, 0)
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
	add_child(_skip_panel)


static func _label(size: int, color := Color.WHITE, _outline := 0) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	return settings


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


func _show_line(index: int) -> void:
	var line := Label.new()
	line.text = "> " + LOG_LINES[index]
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.label_settings = _label(16, Color(0.75, 0.95, 0.8), 0)
	_log.add_child(line)
	while _log.get_child_count() > 7:
		_log.get_child(0).free()
	Sfx.play("terminal_beep", -12.0, 0.05)


func _rebuild_log() -> void:
	for child in _log.get_children():
		child.free()
	for i in shown:
		_show_line(i)


func _set_buttons(entries: Array) -> void:
	for child in _buttons.get_children():
		child.free()
	for entry: Array in entries:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		_buttons.add_child(button)
	_buttons.visible = true
