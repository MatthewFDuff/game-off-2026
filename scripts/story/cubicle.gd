class_name Cubicle
extends Node3D
## The game opens here: the LLM operator's cubicle (levels/cubicle, built by
## scripts/tools/build_cubicle.gd), and the computer on its desk is the only menu
## (docs/cubicle-menu.md). The player walks around as the ordinary first-person Player (unarmed, no
## HUD, no networking). E or a click on what they aim at: the computer (the camera zooms onto its
## screen), the rubber duck (a squeak, then the computer on its Site maintenance page), the sleeping
## bag (the clock-out prompt; Esc in the room shows it too), the notes (the reader panel) and the
## plant. Straying too far into the hallway (HALL_DEPTH past the opening) freezes the player with
## an error buzz, a flashing red light and an intercom line (escalating, counted in `exits`) and
## sets them back inside. Back in the room from a panel or the screen, the mouse is captured again.
##
## The console is drawn in pixel text on the monitor's screen voxels (a SubViewport on a quad) and
## is keyboard-driven: arrows move, Enter / SHIFT select, Esc (or Backspace outside a field) backs
## out one page (from the top page the camera zooms back out). Its pages (Page) are the sign-in
## (nobody is signed in at launch; the name on file is offered), the main menu, singleplayer,
## multiplayer (host / join a shift), settings (the shared SettingsMenu), the payroll statement
## left by the last shift (Net.pending_statement), Site maintenance (the old menu's testing and
## editing: levels, new level, play solo, host co-op, the co-op editor) and the LOG: orientation,
## the model's thought log from the old cubicle intro, unchanged in behavior (SHIFT advances a line
## once its "thinking..." pause is over, the email after line 4, Accept: the transfer note and a
## fade, Decline: the log runs out into a vignette, death, the trash bag and "Would you like to go
## back and accept?"). Accepting starts the shift by how the session was begun (`_start`); the
## orientation setting (or `--skip-intro`) skips the log for the transfer note. F9 accepts at once.
##
## Rewrite the text in the consts at the top. `pause_scale` shortens every pause (tests), and
## `auto_start` false keeps an accepted orientation from starting a session (tests).

## Orientation ended (accepted: the job was taken).
signal finished(accepted: bool)

const LEVEL := "cubicle"
const MONITOR_ID := "monitor"
const CHAIR_ID := "chair"
const NAMEPLATE_ID := "nameplate"
const LEAVE_ID := "t_leave"
const TERRAIN_SHADER := preload("res://shaders/voxel_terrain.gdshader")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
## The story's levels: a new game starts in the lab, a co-op shift in the waiting room.
const STORY_LEVEL := "laboratory"
const WAITING_LEVEL := "waiting_room"
const SIZES := [
	{label = "Small", chunks = Vector3i(8, 6, 8)},
	{label = "Medium", chunks = Vector3i(12, 8, 12)},
	{label = "Large", chunks = Vector3i(16, 10, 16)},
]
const FILLS := [{label = "Rock", fill = "rock"}, {label = "Empty", fill = "empty"}]

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
const GAME_NAME := "FUNG AI"
const SIGN_IN_PROMPT := "Press SHIFT to sign in"
const SESSION_STARTED := "session started. operator: you. shift: night."
const SKIP_HINT := "F9 skips orientation"
const CLICK_HINT := "Click to look around"
## The email arrives after this many lines.
const EMAIL_AFTER := 4
const EMAIL_NOTICE := "1 new email  [E]"
const EMAIL_FROM := "Fung AI People Operations"
const EMAIL_SUBJECT := "Opportunity: Laboratory Technician (Expendable Grade), Site 3"
const EMAIL_BODY := "Congratulations! Your performance as LLM Operator (pressing: 100%) has been noticed. Fung AI is pleased to offer you a transfer to Site 3, where you will continue experiments on our substrate program. Lab coat provided. Science permitted."
const EMAIL_FINE_PRINT := "Fine print. By accepting you assign to Fung AI all rights to your DNA, likeness, thoughts (recorded or inferred), and any clones derived therefrom; damage to Fung AI property is recovered from wages; clones are property; Fung AI is not liable for anything, ever; the coffee machine is property. This offer expires when you do."
const ACCEPT_TEXT := "Transfer accepted. Report to Site 3 tonight.\n\nA car has been sent."
const WAITING_TEXT := "Waiting for the host to begin the shift..."
const TRASH_TEXT := "Later.\n\nA robot drags a heavy trash bag out of the cubicle row.\nBehind it, a screen blinks: PRESS SHIFT."
const GO_BACK_TEXT := "Would you like to go back and accept?"
const DECLINED_TEXT := "You declined. The position remains open."
## What the intercom says each time the player walks out of the opening (the last one repeats).
const LEAVE_LINES := [
	"You must remain in your cubicle during your shift.",
	"Fung AI reminds you: the hallway is not your cubicle.",
	"Noted.",
]
const PLANT_LINE := "It is plastic. It is Fung AI property."
const DUCK_LINE := "Squeak."
const CLOCK_OUT_TEXT := "Clock out? Fung AI wishes you a restful six hours."
const CLOCK_OUT_KEYS := "Y / Enter: clock out     N / Esc: stay"
const CLOSE_TAB_TEXT := "You may close the tab."
const MAINTENANCE_SUB := "authorized personnel and ducks"
const NO_CLONE := "no record on file"
const NEW_GAME := "APPLY FOR JOB"
const OLD_LAYOUT := "recorded against an older site layout"
## The shift on file (docs/shift-save.md): its room, h:mm on shift, the owed total.
## The money is never shown before the statement (it would give the ending away).
const CLONE_NOTE := "clone held at %s, %s on shift"
## New game (or begin orientation) with a shift on file: its room and owed total.
const DISCARD_TEXT := "A shift is in progress. Your clone held at the %s will be discarded. Fung AI does not refund clones."
const DESKTOP_ONLY := "needs the desktop build"
const STATEMENT_NOTICE := "1 new statement"

## Seconds a line "thinks" before SHIFT is accepted (random in this range).
const PAUSE_MIN := 5.0
const PAUSE_MAX := 8.0
## Decline: seconds from the last line to death, and the heartbeat's beat intervals at start and end.
const DYING_SECONDS := 25.0
const BEAT_SLOW := 1.1
const BEAT_FAST := 0.35
## Seconds of black after death, of the trash-bag scene, of the accept fade, of the transfer note
## when orientation is skipped, and of the clock-out fade.
const DEATH_BLACK := 2.0
const TRASH_SECONDS := 5.0
const ACCEPT_SECONDS := 3.0
const TRANSFER_SECONDS := 2.0
const CLOCK_OUT_SECONDS := 1.2
## The camera's move onto the screen, and how long the F9 hint shows.
const ZOOM_SECONDS := 0.8
const SKIP_HINT_SECONDS := 4.0
## Zoomed: the eye this far in front of the screen.
const SCREEN_DISTANCE := 0.35
## Meters from the eye that E reaches.
const REACH := 2.5
## The leaving freeze, and how far inside the opening the player is set back (voxels).
const FREEZE_SECONDS := 1.5
## How far into the hallway the player may go past the opening (meters, straight out and to the
## side) before the red light flashes and they are set back inside.
const HALL_DEPTH := 1.2
const HALL_SIDE := 0.5
const FLASH_PERIOD := 0.3
const FLASH_ENERGY := 6.0
const SET_BACK := 6.0
## A subtitle stays this long per character, and at least MIN_SUBTITLE seconds.
const SECONDS_PER_CHAR := 0.06
const MIN_SUBTITLE := 3.0
## Payroll: seconds between the statement's lines, and the most rows on the screen at once.
const LINE_GAP := 0.45
const STATEMENT_ROWS := 11
const STATEMENT_ROWS_DONE := 5
## The console's pixels (the screen voxels are 6 x 4, a 3:2 face: square texels).
const SCREEN_PIXELS := Vector2i(300, 200)
## Log lines kept on the screen.
const SCREEN_LINES := 4
const FONT_SIZE := 8
## Console colors: text, dim, bright, header, the amber caret, warnings.
const GREEN := Color(0.75, 0.95, 0.8)
const DIM := Color(0.35, 0.55, 0.42)
const BRIGHT := Color(0.85, 1.0, 0.9)
const HEADER := Color(0.45, 0.9, 0.6)
const AMBER := Color(0.95, 0.68, 0.16)
const RED := Color(1.0, 0.35, 0.3)
const BLUE := Color(0.6, 0.75, 1.0)
const BACKGROUND := Color(0.02, 0.05, 0.03)

enum State { ROOM, FROZEN, READING, CLOCK_OUT, CLOSING, ZOOM, SCREEN, LOG, DYING, DEAD, TRASH, GO_BACK, ACCEPTED }
enum Page { SPLASH, SIGN_IN, MAIN, SINGLEPLAYER, MULTIPLAYER, HOST, JOIN, SETTINGS, LOG, STATEMENT, MAINTENANCE, NEW_LEVEL, TRANSFER, DISCARD }

## Multiplies every pause (tests set it near zero).
var pause_scale := 1.0
## Off: an accepted orientation emits finished(true) without starting the session (tests).
var auto_start := true
var state := State.ROOM
var page := Page.SPLASH
## Times the player has walked out of the opening this shift.
var exits := 0
## Log: lines shown so far, whether the email has been offered / is open, whether declined.
var shown := 0
var email_sent := false
var email_open := false
var declined := false
var level: LevelData
var player: Player
## The chosen line on a menu page (an index into its selectable lines).
var cursor := 0
## The status line under the menu (errors, "Created x").
var status := ""
## How the shift was begun: "new_game", "host" or "join" (after orientation), "continue" or
## "host_continue" (a resumed shift, no orientation). What _start does.
var begun_by := ""

var _pause_left := 0.0
var _state_time := 0.0
var _beat_left := 0.0
var _blink := 0.0
## The screen redraws at 10 Hz (and at once on _render) instead of every frame.
var _screen_redraw_left := 0.0
## What _fit_subtitle last fitted (text and viewport size), so it only re-fits on a change.
var _fit_key := ""
var _fit_size := Vector2.ZERO
var _hint_time := INF
var _done := false
var _rng := RandomNumberGenerator.new()
## Signed out: the next SHIFT on the splash asks for the name again. Nobody is signed in when the
## scene opens, even with a name on file: the sign-in page comes up with the name filled in and
## Enter confirms it.
var _signed_out := true
## The page the sign-in field returns to: SPLASH (then MAIN) or SETTINGS (changing the name).
var _name_from := Page.SPLASH
## Typed fields: the sign-in name, the join address, the new level's name.
var _name_field := ""
var _address_field := ""
var _new_name := ""
var _new_size := 0
var _new_fill := 0
## Maintenance: the levels and the chosen one.
var _levels: PackedStringArray = []
var _level_index := 0
## Join: dialing, accepted, or the reason it ended ("" for none).
var _dialing := false
var _joined := false
var _join_error := ""
var _host_error := ""
## ShiftSave.summary() as of the last page opened that shows it ({} for none).
var _save := {}
## What DISCARD's confirm goes on to: "new_game" or "host".
var _discard_for := ""
## Statement: "" (none), "waiting", "rolling" or "done"; the rows shown so far ([left, right, color]).
var _statement := ""
var _statement_rows: Array[Array] = []
var _statement_lines: Array = []
var _statement_total := 0
var _transfer_left := -1.0
var _waiting_for_host := false
var _reading := ""
var _subtitle_left := 0.0
var _freeze_left := 0.0
var _ever_captured := false

# The room.
var _world: VoxelWorld
var _zoom_camera := Camera3D.new()
var _monitor_box := AABB()
var _screen_center := Vector3.ZERO
var _screen_normal := Vector3.BACK
var _leave_box := AABB()
## The red light over the opening that flashes while the player is set back from the hallway.
var _hall_light := OmniLight3D.new()
## id -> {box: AABB (meters), label: String}
var _interactables := {}
const SCREEN_REDRAW_INTERVAL := 0.1
var _viewport := SubViewport.new()
var _zoom_tween: Tween

# The console, drawn on the screen.
var _console := VBoxContainer.new()
var _header := Label.new()
var _body := VBoxContainer.new()
var _log_box := VBoxContainer.new()
var _log := VBoxContainer.new()
var _prompt := Label.new()
var _notification := Label.new()
var _footer := Label.new()
var _settings_menu: SettingsMenu
## Labels and blocks that blink on the current page.
var _blinkers: Array[CanvasItem] = []
var _cursor_block: ColorRect

# Over everything: the prompts, the subtitle, the reader, the clock-out panel, the email, the
# vignette, the black and the overlay texts.
var _layer := CanvasLayer.new()
var _use_prompt := Label.new()
var _crosshair := Label.new()
var _click_hint := Label.new()
var _hint := Label.new()
var _subtitle_panel := PanelContainer.new()
var _subtitle := Label.new()
var _reader: PanelContainer
var _reader_title := Label.new()
var _reader_text := Label.new()
var _clock_panel: PanelContainer
var _email: PanelContainer
var _email_scroll := ScrollContainer.new()
var _vignette := ColorRect.new()
var _black := ColorRect.new()
var _overlay_text := Label.new()
var _buttons := HBoxContainer.new()


func _ready() -> void:
	_rng.randomize()
	_name_field = str(GameSettings.get_value("name"))
	_address_field = str(GameSettings.get_value("address"))
	_build_overlay()
	_build_console()
	if not _build_room():
		push_error("cubicle: level '%s' is missing or has no monitor" % LEVEL)
	Net.players_changed.connect(_on_players_changed)
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_on_session_ended)
	if not Net.pending_statement.is_empty():
		_statement = "waiting"
		_statement_lines = Net.pending_statement.duplicate()
		_statement_total = Net.pending_total
		page = Page.STATEMENT
	else:
		status = Net.end_reason
		Net.end_reason = ""
	_update_nameplate()
	_render()


func _exit_tree() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- Driving it --------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_blink += delta
	_screen_redraw_left -= delta
	if _screen_redraw_left <= 0.0:
		_screen_redraw_left = SCREEN_REDRAW_INTERVAL
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_state_time += delta
	_hint_time += delta
	_hint.visible = _hint_time < SKIP_HINT_SECONDS and page == Page.LOG and state == State.LOG
	for item in _blinkers:
		if is_instance_valid(item):
			item.visible = fmod(_blink, 1.2) < 0.8
	if _subtitle_left > 0.0:
		_subtitle_left -= delta
		if _subtitle_left <= 0.0:
			_subtitle_panel.visible = false
	if _subtitle_panel.visible:
		_fit_subtitle()
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_ever_captured = _ever_captured or captured
	_click_hint.visible = state == State.ROOM and not _ever_captured and DisplayServer.get_name() != "headless"
	_crosshair.visible = state == State.ROOM and captured
	var aimed := aimed() if state == State.ROOM and player != null else ""
	_use_prompt.visible = aimed != ""
	if aimed != "":
		_use_prompt.text = "[E] " + str(_interactables[aimed].label)
	match state:
		State.ROOM:
			_check_leaving()
		State.FROZEN:
			_freeze_left -= delta
			_hall_light.light_energy = FLASH_ENERGY if fmod(_state_time, FLASH_PERIOD) < FLASH_PERIOD * 0.5 else 0.0
			if _freeze_left <= 0.0:
				_unfreeze_after_leaving()
		State.READING:
			if player and _interactables.has(_reading):
				var box: AABB = _interactables[_reading].box
				if _distance_to_box(player.camera.global_position, box) > REACH + 1.0:
					close_reader()
		State.SCREEN:
			if page == Page.TRANSFER and _transfer_left > 0.0:
				_transfer_left -= delta
				if _transfer_left <= 0.0:
					_finish(true)
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
			if t >= 1.0 and not _done:
				_finish(true)
		State.CLOSING:
			_black.modulate.a = clampf(_state_time / CLOCK_OUT_SECONDS, 0.0, 1.0)
			if _state_time >= CLOCK_OUT_SECONDS and not _done:
				_done = true
				if OS.has_feature("web"):
					_overlay_text.text = CLOSE_TAB_TEXT
					_overlay_text.visible = true
				else:
					get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	var viewport := get_viewport()
	var handled := false
	match state:
		State.ROOM:
			handled = _room_input(event)
		State.READING:
			if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel") or _is_key(event, KEY_BACKSPACE):
				close_reader()
				handled = true
		State.CLOCK_OUT:
			if event is InputEventKey and event.pressed and not event.echo:
				match event.keycode:
					KEY_Y, KEY_ENTER, KEY_KP_ENTER:
						clock_out()
					KEY_N, KEY_ESCAPE, KEY_BACKSPACE:
						close_clock_out()
				handled = true
		State.SCREEN, State.LOG, State.DYING, State.DEAD, State.TRASH, State.GO_BACK, State.ACCEPTED:
			if event is InputEventKey:
				handled = handle_key(event)
			elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				if state == State.LOG and email_sent and not email_open:
					open_email()
					handled = true
		State.ZOOM, State.FROZEN, State.CLOSING:
			handled = event is InputEventKey
	if handled and viewport:
		viewport.set_input_as_handled()


func _room_input(event: InputEvent) -> bool:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and captured
	if click or (event.is_action_pressed("interact") and InputSetup.is_playing()):
		var id := aimed()
		if id != "":
			interact(id)
		return true
	if event.is_action_pressed("ui_cancel"):
		open_clock_out()
		return true
	return false


## The interactable the player's camera is aimed at within REACH ("" for none): the nearest box the
## ray hits, except that a box enclosing another hit box yields to it (the duck stands inside the
## computer desk's box, and the player aiming at the duck means the duck).
func aimed() -> String:
	if player == null or not player.is_inside_tree():
		return ""
	var from := player.camera.global_position
	var direction := -player.camera.global_basis.z
	var hits := {}
	for id: String in _interactables:
		var hit = (_interactables[id].box as AABB).intersects_ray(from, direction)
		if hit != null and from.distance_to(hit) <= REACH:
			hits[id] = from.distance_to(hit)
	var best := ""
	for id: String in hits:
		var box: AABB = _interactables[id].box
		var encloses_another := false
		for other: String in hits:
			if other != id and box.encloses(_interactables[other].box):
				encloses_another = true
				break
		if encloses_another:
			continue
		if best == "" or hits[id] < hits[best]:
			best = id
	return best


## What E does on an interactable, by id.
func interact(id: String) -> void:
	if not _interactables.has(id) or state != State.ROOM:
		return
	var object: Dictionary = level.objects.get(id, {})
	if id == MONITOR_ID:
		use_monitor()
	elif object.get("name") == "rubber_duck":
		use_duck()
	elif object.get("name") == "sleeping_bag":
		open_clock_out()
	elif object.get("name") == "fake_plant":
		_say(PLANT_LINE)
	elif object.get("use") == "note":
		_open_reader(id)


## E on the duck: a squeak, then the computer on its Site maintenance page.
func use_duck() -> void:
	Sfx.play("ui_pop", -4.0, 0.1, 1.6)
	_say(DUCK_LINE)
	use_monitor(Page.MAINTENANCE)


# --- Leaving the cubicle ------------------------------------------------------------------------------

## The player may step through the opening and a little way into the hallway (HALL_DEPTH straight
## out, HALL_SIDE to either side of the opening); past that they are stopped.
func _check_leaving() -> void:
	if player == null or _leave_box.size == Vector3.ZERO:
		return
	var feet := player.global_position
	var beyond := feet.z - _leave_box.end.z
	if beyond <= 0.0:
		return
	var aside := maxf(_leave_box.position.x - feet.x, feet.x - _leave_box.end.x)
	if beyond > HALL_DEPTH or aside > HALL_SIDE:
		_on_leave()


func _on_leave() -> void:
	exits += 1
	Sfx.play("build_denied", -2.0, 0.0)
	_say(LEAVE_LINES[mini(exits, LEAVE_LINES.size()) - 1], true)
	player.velocity = Vector3.ZERO
	player.process_mode = Node.PROCESS_MODE_DISABLED
	state = State.FROZEN
	_state_time = 0.0
	_freeze_left = FREEZE_SECONDS
	_hall_light.light_energy = FLASH_ENERGY


func _unfreeze_after_leaving() -> void:
	_hall_light.light_energy = 0.0
	var feet := player.global_position
	feet.x = clampf(feet.x, _leave_box.position.x + 0.3, _leave_box.end.x - 0.3)
	feet.z = _leave_box.position.z - SET_BACK * _world.voxel_size
	feet.y = _leave_box.position.y
	player.teleport(feet)
	player.process_mode = Node.PROCESS_MODE_INHERIT
	state = State.ROOM
	_capture_mouse()


# --- Clocking out -------------------------------------------------------------------------------------

func open_clock_out() -> void:
	if state != State.ROOM:
		return
	state = State.CLOCK_OUT
	_freeze_player(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_clock_panel.visible = true
	Sfx.play("ui_blip", -6.0, 0.0)


func close_clock_out() -> void:
	if state != State.CLOCK_OUT:
		return
	_clock_panel.visible = false
	_freeze_player(false)
	state = State.ROOM
	_capture_mouse()


## Fades to black and quits (on the web: asks to close the tab).
func clock_out() -> void:
	if state != State.CLOCK_OUT:
		return
	_clock_panel.visible = false
	state = State.CLOSING
	_state_time = 0.0
	_black.visible = true
	_black.modulate.a = 0.0
	_overlay_text.visible = false


# --- Reading notes ------------------------------------------------------------------------------------

func _open_reader(id: String) -> void:
	_reading = id
	state = State.READING
	var text := str(level.objects[id].get("text", "")).strip_edges()
	_reader_title.text = "Nameplate" if id == NAMEPLATE_ID else "Note"
	_reader_text.text = text if text != "" else "(blank)"
	_reader.visible = true
	_fit_center(_reader)


func close_reader() -> void:
	_reading = ""
	_reader.visible = false
	if state == State.READING:
		state = State.ROOM
		_capture_mouse()


# --- The computer -----------------------------------------------------------------------------------

## E (or a click) on the monitor: the camera moves onto its screen and the console takes over.
## start_page opens a page other than the one the screen shows (the duck's maintenance page).
func use_monitor(start_page := -1) -> void:
	if state != State.ROOM:
		return
	if start_page >= 0:
		page = start_page as Page
		cursor = 0
	elif page in [Page.MAINTENANCE, Page.NEW_LEVEL]:
		page = _home_page()
		cursor = 0
	state = State.ZOOM
	_state_time = 0.0
	_freeze_player(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_render()
	var target := Transform3D(Basis.looking_at(-_screen_normal, Vector3.UP), _screen_center + _screen_normal * SCREEN_DISTANCE)
	_zoom_camera.fov = player.camera.fov if player else 70.0
	_zoom_camera.global_transform = player.camera.global_transform if player else target
	_zoom_camera.current = true
	_tween_camera(target, func() -> void: _on_zoomed_in())


## From the top page: the camera moves back to the player's eyes and the room is theirs again, the
## mouse captured at once (the key that stepped away is the gesture the web build needs for it).
func zoom_out() -> void:
	if state != State.SCREEN:
		return
	state = State.ZOOM
	_state_time = 0.0
	_capture_mouse()
	var target := player.camera.global_transform if player else _zoom_camera.global_transform
	_tween_camera(target, func() -> void:
		if player:
			player.camera.current = true
		_freeze_player(false)
		state = State.ROOM)


func _tween_camera(target: Transform3D, then: Callable) -> void:
	if _zoom_tween:
		_zoom_tween.kill()
	var seconds := ZOOM_SECONDS * pause_scale
	if seconds <= 0.01:
		_zoom_camera.global_transform = target
		then.call()
		return
	_zoom_tween = create_tween()
	_zoom_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_zoom_tween.tween_property(_zoom_camera, "global_transform", target, seconds)
	_zoom_tween.finished.connect(then)


func _on_zoomed_in() -> void:
	if state != State.ZOOM:
		return
	state = State.SCREEN
	if page == Page.STATEMENT and _statement == "waiting":
		_roll_statement()
	elif page == Page.MAINTENANCE:
		_refresh_levels()
	_render()


func _freeze_player(frozen: bool) -> void:
	if player:
		player.velocity = Vector3.ZERO
		player.process_mode = Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT


## Back in the room after a panel or the screen: the mouse is captured again without a click.
func _capture_mouse() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


static func _is_key(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == keycode


func _home_page() -> Page:
	return Page.MAIN if _signed_in() else Page.SPLASH


func _signed_in() -> bool:
	return str(GameSettings.get_value("name")).strip_edges() != "" and not _signed_out


# --- The console's keys -------------------------------------------------------------------------------

## A key on the console (the screen is in use). True if it was the console's.
func handle_key(event: InputEventKey) -> bool:
	if not event.pressed:
		return false
	if state in [State.LOG, State.DYING, State.DEAD, State.TRASH, State.GO_BACK, State.ACCEPTED]:
		return _log_key(event)
	if state != State.SCREEN:
		return true
	if page == Page.SETTINGS and _settings_menu and _settings_menu.handle_key(event):
		return true
	match event.keycode:
		KEY_ESCAPE:
			if not event.echo:
				back()
		KEY_UP:
			move_cursor(-1)
		KEY_DOWN:
			move_cursor(1)
		KEY_LEFT:
			step_choice(-1)
		KEY_RIGHT:
			step_choice(1)
		KEY_ENTER, KEY_KP_ENTER:
			if not event.echo:
				press_enter()
		KEY_SHIFT:
			if not event.echo:
				press_shift()
		KEY_BACKSPACE:
			# Erases in a field; elsewhere it is Esc's twin.
			if _field_item() != {}:
				_erase()
			elif not event.echo:
				back()
		_:
			if event.unicode >= 32 and _field_item() != {}:
				type_text(char(event.unicode))
			else:
				return false
	return true


func _log_key(event: InputEventKey) -> bool:
	if event.echo:
		return true
	match event.keycode:
		KEY_F9:
			_finish(true)
		KEY_SHIFT:
			press_shift()
		KEY_ESCAPE:
			if state in [State.LOG, State.DYING] and not email_open:
				_abort_orientation()
		KEY_ENTER, KEY_KP_ENTER, KEY_E:
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
	return true


## SHIFT: signs in on the splash and after the statement, advances the log, chooses elsewhere.
func press_shift() -> void:
	if state in [State.LOG, State.DYING, State.DEAD, State.TRASH, State.GO_BACK, State.ACCEPTED]:
		_log_shift()
		return
	if state != State.SCREEN:
		return
	match page:
		Page.SPLASH:
			_sign_in()
		Page.STATEMENT:
			if _statement == "done":
				_clear_statement()
				_sign_in()
		Page.TRANSFER, Page.SIGN_IN, Page.JOIN, Page.NEW_LEVEL:
			if _field_item() == {}:
				press_enter()
		_:
			press_enter()


## Enter: chooses the line under the caret (submits a field).
func press_enter() -> void:
	if state != State.SCREEN:
		return
	if page == Page.SPLASH:
		_sign_in()
		return
	if page == Page.STATEMENT:
		press_shift()
		return
	var item := _current_item()
	if item.is_empty():
		return
	if item.get("dim", false):
		Sfx.play("build_denied", -6.0, 0.0)
		if str(item.get("note", "")) != "":
			status = str(item.note)
			_render()
		return
	var action: Callable = item.get("action", Callable())
	if action.is_valid():
		Sfx.play("ui_click", -8.0, 0.0)
		action.call()


## Esc: one page back; from a top page the camera zooms out.
func back() -> void:
	if state != State.SCREEN:
		return
	match page:
		Page.SPLASH, Page.MAIN, Page.MAINTENANCE:
			zoom_out()
		Page.STATEMENT:
			if _statement == "done":
				_clear_statement()
				open_page(Page.SPLASH)
				zoom_out()
		Page.SIGN_IN:
			open_page(_name_from)
		Page.SINGLEPLAYER, Page.MULTIPLAYER, Page.SETTINGS:
			open_page(Page.MAIN)
		Page.HOST:
			Net.close_session()
			_host_error = ""
			open_page(Page.MULTIPLAYER)
		Page.JOIN:
			if _dialing or _joined:
				_dialing = false
				_joined = false
				Net.leave()
			_join_error = ""
			open_page(Page.MULTIPLAYER)
		Page.NEW_LEVEL:
			open_page(Page.MAINTENANCE)
		Page.DISCARD:
			open_page(Page.HOST if _discard_for == "host" else Page.SINGLEPLAYER)
		Page.TRANSFER:
			pass


## Shows a page (the caret on its first line).
func open_page(to: Page) -> void:
	if to != page:
		status = ""
	page = to
	cursor = 0
	if to == Page.MAINTENANCE:
		_refresh_levels()
	elif to == Page.HOST:
		_open_host()
	if to in [Page.SINGLEPLAYER, Page.HOST, Page.DISCARD]:
		_save = ShiftSave.summary() if ShiftSave.exists() else {}
	_render()
	var items := _selectable()
	while cursor < items.size() - 1 and items[cursor].get("dim", false):
		cursor += 1
	_render()


func move_cursor(step: int) -> void:
	var count := _selectable().size()
	if count == 0:
		return
	cursor = posmod(cursor + step, count)
	Sfx.play("ui_blip", -12.0, 0.0)
	_render()


## Left / right on a choice line (the level, the new level's size and start).
func step_choice(step: int) -> void:
	var item := _current_item()
	var change: Callable = item.get("step", Callable())
	if change.is_valid():
		change.call(step)
		Sfx.play("ui_blip", -12.0, 0.0)
		_render()


## Types into the field under the caret (letters, digits, space and, in addresses, . : -).
func type_text(text: String) -> void:
	var item := _field_item()
	if item.is_empty():
		return
	var value := _get_field(item.field)
	for c in text:
		var ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == " "
		if item.field == "address":
			ok = ok or c in [".", ":", "-"]
		elif item.field == "new_name":
			ok = ok or c in ["_", "-"]
		if ok and value.length() < int(item.get("max", GameSettings.NAME_LENGTH)):
			value += c
	_set_field(item.field, value)
	_render()


func _erase() -> void:
	var item := _field_item()
	if item.is_empty():
		return
	var value := _get_field(item.field)
	_set_field(item.field, value.left(maxi(0, value.length() - 1)))
	_render()


func _get_field(field: String) -> String:
	match field:
		"name": return _name_field
		"address": return _address_field
		"new_name": return _new_name
	return ""


func _set_field(field: String, value: String) -> void:
	match field:
		"name": _name_field = value
		"address": _address_field = value
		"new_name": _new_name = value


# --- The pages' actions ----------------------------------------------------------------------------------

func _sign_in() -> void:
	if _signed_in():
		open_page(Page.MAIN)
	else:
		_name_field = str(GameSettings.get_value("name"))
		_name_from = Page.SPLASH
		open_page(Page.SIGN_IN)


## Settings' Name row: the sign-in field again, returning to SETTINGS.
func _change_name() -> void:
	_name_field = str(GameSettings.get_value("name"))
	_name_from = Page.SETTINGS
	open_page(Page.SIGN_IN)


func _submit_name() -> void:
	var entered := _name_field.strip_edges()
	if entered == "":
		Sfx.play("build_denied", -6.0, 0.0)
		status = "Fung AI requires a name."
		_render()
		return
	GameSettings.set_value("name", entered)
	Net.player_name = entered
	_signed_out = false
	_update_nameplate()
	open_page(Page.MAIN if _name_from == Page.SPLASH else _name_from)


func _sign_out() -> void:
	_signed_out = true
	open_page(Page.SPLASH)


## New game: orientation, after DISCARD when a shift is on file.
func _new_game() -> void:
	if not _save.is_empty():
		_open_discard("new_game")
		return
	_begin_orientation("new_game")


## The shift on file can be resumed (it exists and the site's layout still matches it).
func _can_continue() -> bool:
	return not _save.is_empty() and bool(_save.get("layout_ok", false))


## CONTINUE's note: the room and the time on shift (h:mm).
func _clone_note() -> String:
	var seconds := int(_save.get("elapsed", 0))
	@warning_ignore("integer_division")
	var on_shift := "%d:%02d" % [seconds / 3600, (seconds / 60) % 60]
	return CLONE_NOTE % [str(_save.get("vat_room", "")), on_shift]


## CONTINUE (singleplayer): the shift on file resumes solo, no orientation.
func _continue() -> void:
	if not _can_continue():
		return
	begun_by = "continue"
	_done = false
	_finish(true)


## CONTINUE SHIFT (host): the waiting-room session is reopened as the resumed laboratory (anyone
## already connected is dropped and rejoins by address, straight into the level) and entered at once.
func _host_continue() -> void:
	if not _can_continue():
		return
	var error := Net.open_session(Net.DEFAULT_PORT, STORY_LEVEL, "play", {shift = true, resume = true})
	if error != OK:
		_host_error = "Couldn't open a shift on port %d (%s). Is another copy already hosting?" % [Net.DEFAULT_PORT, error_string(error)]
		Sfx.play("build_denied", -6.0, 0.0)
		_render()
		return
	begun_by = "host_continue"
	_done = false
	_finish(true)


## The discard warning before a new shift replaces the one on file; for_what: "new_game" or "host".
func _open_discard(for_what: String) -> void:
	_discard_for = for_what
	open_page(Page.DISCARD)
	cursor = 1 # KEEP IT: the safe line is under the caret.
	_render()


## DISCARD AND CLOCK IN: the shift on file is cleared, then orientation as usual.
func _discard_and_clock_in() -> void:
	ShiftSave.clear()
	_save = {}
	var by := _discard_for
	_discard_for = ""
	if by == "host":
		open_page(Page.HOST)
		_host_begin()
	else:
		_begin_orientation("new_game")


func _open_host() -> void:
	_host_error = ""
	if Net.in_session and Net.is_host():
		return
	var error := Net.open_session(Net.DEFAULT_PORT, WAITING_LEVEL, "play", {shift = true})
	if error != OK:
		_host_error = "Couldn't open a shift on port %d (%s). Is another copy already hosting?" % [Net.DEFAULT_PORT, error_string(error)]


func _host_begin() -> void:
	if _host_error != "" or not Net.in_session:
		Sfx.play("build_denied", -6.0, 0.0)
		return
	if not _save.is_empty():
		_open_discard("host")
		return
	_begin_orientation("host")


func _dial() -> void:
	var target := _address_field.strip_edges()
	var port := Net.DEFAULT_PORT
	if ":" in target:
		port = int(target.get_slice(":", 1))
		target = target.get_slice(":", 0)
	if target == "":
		Sfx.play("build_denied", -6.0, 0.0)
		_join_error = "Enter the host's address."
		_render()
		return
	GameSettings.set_value("address", _address_field.strip_edges())
	_join_error = ""
	_joined = false
	var error := Net.join(target, port)
	if error != OK:
		_join_error = "Couldn't dial (%s)." % error_string(error)
	else:
		_dialing = true
		status = "Dialing %s:%d..." % [target, port]
	_render()


func _join_begin() -> void:
	if not _joined:
		_dial()
		return
	_begin_orientation("join")


func _on_players_changed() -> void:
	if page in [Page.HOST, Page.JOIN]:
		_render()


func _on_session_started() -> void:
	if not _dialing:
		return
	_dialing = false
	_joined = true
	if Net.session.get("resume", false):
		# A resumed shift: no orientation, the transfer note and into the level.
		begun_by = "join"
		_done = false
		_show_transfer()
		return
	_render()


func _on_session_ended(reason: String) -> void:
	_dialing = false
	_joined = false
	var in_orientation := page in [Page.LOG, Page.TRANSFER] or _waiting_for_host or state in [State.LOG, State.DYING, State.DEAD, State.TRASH, State.GO_BACK, State.ACCEPTED]
	if begun_by == "join" and in_orientation:
		_reset_orientation()
		begun_by = ""
		page = Page.JOIN
		cursor = 0
	if page == Page.JOIN:
		_join_error = reason if reason != "" else "The line went dead."
		status = ""
		_render()


func _open_join() -> void:
	_join_error = ""
	open_page(Page.JOIN)


func _step_level(step: int) -> void:
	if not _levels.is_empty():
		_level_index = posmod(_level_index + step, _levels.size())


func _step_size(step: int) -> void:
	_new_size = posmod(_new_size + step, SIZES.size())


func _step_fill(step: int) -> void:
	_new_fill = posmod(_new_fill + step, FILLS.size())


## Maintenance: plays, hosts, edits or joins the chosen level directly (no orientation, no waiting
## room), as the old menu's "Testing and editing" did.
func _maintenance(action: String) -> void:
	var level_name := _chosen_level()
	if level_name == "" and action != "join":
		status = "Create a level first."
		Sfx.play("build_denied", -6.0, 0.0)
		_render()
		return
	GameSettings.set_value("level", level_name)
	match action:
		"solo":
			Net.start_solo(level_name, "play")
		"host", "edit":
			var mode := "edit" if action == "edit" else "play"
			if not Net.can_network():
				Net.start_solo(level_name, mode)
				return
			var error := Net.host(Net.DEFAULT_PORT, level_name, mode)
			if error != OK:
				status = "Couldn't host on port %d (%s)." % [Net.DEFAULT_PORT, error_string(error)]
				_render()
		"join":
			var target := str(GameSettings.get_value("address")).strip_edges()
			var port := Net.DEFAULT_PORT
			if ":" in target:
				port = int(target.get_slice(":", 1))
				target = target.get_slice(":", 0)
			var error := Net.join(target, port) if target != "" else ERR_INVALID_PARAMETER
			status = "Dialing %s:%d..." % [target, port] if error == OK else "Couldn't dial (%s)." % error_string(error)
			_render()


func _refresh_levels() -> void:
	_levels = LevelData.list()
	var want := str(GameSettings.get_value("level"))
	_level_index = maxi(0, Array(_levels).find(want))


func _chosen_level() -> String:
	return _levels[_level_index] if _level_index < _levels.size() else ""


func _create_level() -> void:
	var level_name := _new_name.strip_edges().to_snake_case().validate_filename()
	if level_name == "":
		status = "Name the new level."
	elif level_name in LevelData.list():
		status = "There is already a level called %s." % level_name
	else:
		var created := LevelData.create(level_name, SIZES[_new_size].chunks, FILLS[_new_fill].fill, self)
		var error := created.save()
		if error != OK:
			status = "Couldn't save the level: %s" % error_string(error)
		else:
			GameSettings.set_value("level", level_name)
			_new_name = ""
			open_page(Page.MAINTENANCE)
			status = "Created %s. EDIT LEVEL to start building." % level_name
	if status != "" and page == Page.NEW_LEVEL:
		Sfx.play("build_denied", -6.0, 0.0)
	_render()


# --- Orientation (the log) and starting the shift ---------------------------------------------------

## Orientation, then the start: the thought log, or the transfer note when it's skipped.
func _begin_orientation(by: String) -> void:
	begun_by = by
	_done = false
	if str(GameSettings.get_value("orientation")) == "skip" or "--skip-intro" in OS.get_cmdline_user_args():
		_show_transfer()
		return
	_begin_session()


## The transfer note for a moment, then the start (orientation skipped, or a resumed shift joined).
func _show_transfer() -> void:
	page = Page.TRANSFER
	_transfer_left = TRANSFER_SECONDS * maxf(pause_scale, 0.01)
	_render()


func _begin_session() -> void:
	page = Page.LOG
	state = State.LOG
	_state_time = 0.0
	_hint_time = 0.0
	shown = 0
	email_sent = false
	email_open = false
	declined = false
	for child in _log.get_children():
		child.free()
	_render()
	_header.text = SESSION_STARTED
	Sfx.play("terminal_beep", -10.0, 0.1)
	_start_pause()


func _log_shift() -> void:
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
			# The transfer note on the monitor, then the fade carries it over the black.
			for child in _log.get_children():
				child.free()
			_add_console_line(ACCEPT_TEXT, BRIGHT)
			_prompt.visible = false
			_notification.visible = false
			_black.visible = true
			_black.modulate.a = 0.0
			_overlay_text.text = ACCEPT_TEXT
			_overlay_text.visible = false
			_overlay_text.modulate = Color.WHITE
			Sfx.play("harvest_chime", -8.0, 0.0)


## Orientation is over. Accepted: the shift starts (_start). Declined and not going back: the main
## page, the session (if any) closed.
func _finish(accepted: bool) -> void:
	if _done:
		return
	_done = true
	_transfer_left = -1.0
	finished.emit(accepted)
	if accepted:
		if auto_start:
			_start()
		return
	var by := begun_by
	begun_by = ""
	_reset_orientation()
	state = State.SCREEN
	if by == "host":
		Net.close_session()
	elif by == "join":
		_joined = false
		Net.leave()
	open_page(Page.MAIN)
	status = DECLINED_TEXT
	_render()


## Starts the shift by how the session was begun (docs/cubicle-menu.md, section 4).
func _start() -> void:
	match begun_by:
		"new_game":
			Net.start_solo(STORY_LEVEL, "play", {shift = true})
		"continue":
			Net.start_solo(STORY_LEVEL, "play", {shift = true, resume = true})
		"host", "host_continue":
			Net.enter_level()
		"join":
			if not Net.level_open:
				_waiting_for_host = true
				if _black.visible:
					_overlay_text.text = ACCEPT_TEXT + "\n\n" + WAITING_TEXT
					_overlay_text.visible = true
				else:
					_render()
			Net.enter_level()


## Esc during the log: back to the page orientation began from.
func _abort_orientation() -> void:
	var by := begun_by
	begun_by = ""
	_reset_orientation()
	state = State.SCREEN
	match by:
		"host": open_page(Page.HOST)
		"join": open_page(Page.JOIN)
		_: open_page(Page.SINGLEPLAYER)


func _reset_orientation() -> void:
	_done = false
	email_open = false
	email_sent = false
	declined = false
	shown = 0
	_pause_left = 0.0
	_transfer_left = -1.0
	_waiting_for_host = false
	_email.visible = false
	_black.visible = false
	_overlay_text.visible = false
	_buttons.visible = false
	_vignette.material.set_shader_parameter("strength", 0.0)
	_console.visible = true
	_notification.visible = false
	if state in [State.LOG, State.DYING, State.DEAD, State.TRASH, State.GO_BACK, State.ACCEPTED]:
		state = State.SCREEN


func _start_pause() -> void:
	_pause_left = _rng.randf_range(PAUSE_MIN, PAUSE_MAX) * pause_scale
	_prompt.text = "thinking..."
	_prompt.visible = true


func _send_email() -> void:
	email_sent = true
	_notification.visible = true
	Sfx.play("ui_blip", -4.0, 0.0)


func _add_console_line(text: String, color: Color) -> void:
	var line := _console_label(text, color)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.add_child(line)
	while _log.get_child_count() > SCREEN_LINES:
		_log.get_child(0).free()


func _show_line(index: int) -> void:
	_add_console_line("> " + LOG_LINES[index], GREEN)
	Sfx.play("terminal_beep", -12.0, 0.05)


func _rebuild_log() -> void:
	for child in _log.get_children():
		child.free()
	for i in range(maxi(0, shown - SCREEN_LINES), shown):
		_show_line(i)


# --- Payroll ----------------------------------------------------------------------------------------

## Rolls the statement left by the last shift line by line, then Guy Fung's note and the sign-in
## prompt; the nameplate's numbers are updated once it has rolled.
func _roll_statement() -> void:
	_statement = "rolling"
	_statement_rows.clear()
	_render()
	await get_tree().create_timer(LINE_GAP * pause_scale).timeout
	for line in _statement_lines:
		if not is_inside_tree() or _statement != "rolling":
			return
		var text := str(line)
		var parts := text.split("|")
		var color := RED if text.begins_with("TOTAL") else (Color(0.6, 1.0, 0.6) if text.begins_with("NET PAY") else GREEN)
		_statement_rows.append([parts[0], parts[1] if parts.size() > 1 else "", color])
		Sfx.play("register_tick", -8.0, 0.02)
		_render()
		await get_tree().create_timer(LINE_GAP * pause_scale).timeout
	if not is_inside_tree() or _statement != "rolling":
		return
	_statement = "done"
	GameSettings.set_value("shifts_worked", int(GameSettings.get_value("shifts_worked")) + 1)
	GameSettings.set_value("balance_owed", maxi(0, int(GameSettings.get_value("balance_owed")) - _statement_total))
	Net.pending_statement = []
	Net.pending_total = 0
	_update_nameplate()
	_render()


func _clear_statement() -> void:
	_statement = ""
	_statement_rows.clear()
	_statement_lines = []


## The nameplate by the opening: the name on file, the job and the shifts worked (the balance is
## kept but never shown here; the statement is the first the player hears of it).
func _update_nameplate() -> void:
	if level == null or not level.objects.has(NAMEPLATE_ID):
		return
	var employee := str(GameSettings.get_value("name")).strip_edges()
	level.objects[NAMEPLATE_ID].text = "%s\nLLM Operator\nShifts worked: %d" % [
		employee if employee != "" else "EMPLOYEE", int(GameSettings.get_value("shifts_worked"))]


# --- The pages ----------------------------------------------------------------------------------------

## The current page's lines: {kind: "title" / "text" / "item" / "field" / "pair" / "gap", text, color,
## action, dim, note, step (choice lines), field, blink}.
func _items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var web := not Net.can_network()
	match page:
		Page.SPLASH:
			items.append({kind = "gap"})
			items.append({kind = "title", text = GAME_NAME})
			items.append({kind = "gap"})
			items.append({kind = "text", text = SIGN_IN_PROMPT, color = BRIGHT, blink = true})
			if _signed_in():
				items.append({kind = "text", text = "signed in: %s" % GameSettings.get_value("name"), color = DIM})
		Page.SIGN_IN:
			items.append({kind = "text", text = "Employee name:"})
			items.append({kind = "field", field = "name", action = _submit_name, max = GameSettings.NAME_LENGTH})
		Page.MAIN:
			items.append({kind = "text", text = "signed in: %s" % GameSettings.get_value("name"), color = DIM})
			items.append({kind = "gap"})
			items.append({kind = "item", text = "SINGLEPLAYER", action = func() -> void: open_page(Page.SINGLEPLAYER)})
			items.append({kind = "item", text = "MULTIPLAYER", action = func() -> void: open_page(Page.MULTIPLAYER), dim = web, note = DESKTOP_ONLY if web else ""})
			items.append({kind = "item", text = "SETTINGS", action = func() -> void: open_page(Page.SETTINGS)})
			items.append({kind = "item", text = "SIGN OUT", action = _sign_out})
		Page.SINGLEPLAYER:
			if _can_continue():
				items.append({kind = "item", text = "CONTINUE", action = _continue, detail = _clone_note()})
			else:
				items.append({kind = "item", text = "CONTINUE", dim = true, note = NO_CLONE if _save.is_empty() else OLD_LAYOUT})
			items.append({kind = "item", text = NEW_GAME, action = _new_game})
			items.append({kind = "item", text = "BACK", action = back})
		Page.DISCARD:
			items.append({kind = "text", text = DISCARD_TEXT % str(_save.get("vat_room", "")), color = AMBER})
			items.append({kind = "gap"})
			items.append({kind = "item", text = "DISCARD AND CLOCK IN", action = _discard_and_clock_in})
			items.append({kind = "item", text = "KEEP IT", action = back})
		Page.MULTIPLAYER:
			items.append({kind = "item", text = "HOST A SHIFT", action = func() -> void: open_page(Page.HOST)})
			items.append({kind = "item", text = "JOIN A SHIFT", action = _open_join})
			items.append({kind = "item", text = "BACK", action = back})
		Page.HOST:
			if _host_error != "":
				items.append({kind = "text", text = _host_error, color = RED})
			else:
				for line in LabHud.hosting_info(multiplayer).split("\n"):
					items.append({kind = "text", text = line, color = GREEN if line.begins_with("Hosting") else DIM})
				# CONTINUE SHIFT's two lines take the gaps' room, so the footer stays on the screen.
				var resumable := _can_continue()
				if not resumable:
					items.append({kind = "gap"})
				items.append({kind = "text", text = "Staff on shift:"})
				for peer_id: int in Net.players:
					var entry: Dictionary = Net.players[peer_id]
					items.append({kind = "text", text = "  %s  %s" % [entry.name, "· host (you)" if peer_id == multiplayer.get_unique_id() else "· in orientation"], color = BRIGHT})
				if resumable:
					items.append({kind = "item", text = "CONTINUE SHIFT", action = _host_continue, detail = _clone_note()})
				else:
					items.append({kind = "gap"})
				items.append({kind = "item", text = "BEGIN ORIENTATION", action = _host_begin})
			items.append({kind = "item", text = "CLOSE THE SHIFT" if _host_error == "" else "BACK", action = back})
		Page.JOIN:
			items.append({kind = "text", text = "Host address:"})
			items.append({kind = "field", field = "address", action = _dial, max = 40})
			if _joined:
				items.append({kind = "text", text = "Accepted. %d staff on. Press SHIFT to begin orientation." % Net.players.size(), color = BRIGHT})
				items.append({kind = "item", text = "BEGIN ORIENTATION", action = _join_begin})
			elif _dialing:
				items.append({kind = "text", text = status, color = GREEN, blink = true})
			elif _join_error != "":
				items.append({kind = "text", text = _join_error, color = RED})
				items.append({kind = "text", text = "Enter: retry  ·  Esc: back", color = DIM})
			var recent: Array = GameSettings.get_value("recent_addresses")
			if not _joined and not _dialing and recent.size() > 0:
				items.append({kind = "gap"})
				items.append({kind = "text", text = "Recent:", color = DIM})
				for address in recent.slice(0, 3):
					var dial_it := func() -> void:
						_address_field = str(address)
						_dial()
					items.append({kind = "item", text = str(address), action = dial_it})
		Page.SETTINGS:
			pass # The SettingsMenu control (_render).
		Page.STATEMENT:
			if _statement == "waiting":
				items.append({kind = "gap"})
				items.append({kind = "text", text = STATEMENT_NOTICE, color = BLUE, blink = true})
			else:
				# Rolled: the last rows (the total among them) make room for the note and the prompt.
				var rows := STATEMENT_ROWS if _statement == "rolling" else STATEMENT_ROWS_DONE
				for row in _statement_rows.slice(maxi(0, _statement_rows.size() - rows)):
					items.append({kind = "pair", text = row[0], right = row[1], color = row[2]})
				if _statement == "done":
					items.append({kind = "gap"})
					items.append({kind = "text", text = str(Lines.ENDING.note).replace("\n\n", "\n"), color = Color(0.85, 0.85, 0.75)})
					items.append({kind = "text", text = SIGN_IN_PROMPT, color = BRIGHT, blink = true})
		Page.MAINTENANCE:
			items.append({kind = "text", text = MAINTENANCE_SUB, color = DIM})
			items.append({kind = "gap"})
			var level_text := "LEVEL  < %s >" % _chosen_level() if not _levels.is_empty() else "LEVEL  (none)"
			items.append({kind = "item", text = level_text, step = _step_level})
			items.append({kind = "item", text = "NEW LEVEL", action = func() -> void: open_page(Page.NEW_LEVEL)})
			items.append({kind = "item", text = "PLAY SOLO", action = _maintenance.bind("solo")})
			items.append({kind = "item", text = "HOST CO-OP", action = _maintenance.bind("host"), dim = web, note = DESKTOP_ONLY if web else ""})
			items.append({kind = "item", text = "EDIT LEVEL", action = _maintenance.bind("edit")})
			var address := str(GameSettings.get_value("address"))
			items.append({kind = "item", text = "JOIN THE EDITOR AT %s" % (address if address != "" else "(no address)"), action = _maintenance.bind("join"), dim = web, note = DESKTOP_ONLY if web else ""})
			items.append({kind = "item", text = "BACK", action = back})
		Page.NEW_LEVEL:
			items.append({kind = "text", text = "Level name:"})
			items.append({kind = "field", field = "new_name", action = _create_level, max = 32})
			items.append({kind = "item", text = "SIZE   < %s >" % SIZES[_new_size].label, step = _step_size})
			items.append({kind = "item", text = "START  < %s >" % FILLS[_new_fill].label, step = _step_fill})
			items.append({kind = "item", text = "CREATE", action = _create_level})
			items.append({kind = "item", text = "BACK", action = back})
		Page.TRANSFER:
			items.append({kind = "gap"})
			items.append({kind = "text", text = ACCEPT_TEXT, color = BRIGHT})
			if _waiting_for_host:
				items.append({kind = "gap"})
				items.append({kind = "text", text = WAITING_TEXT, color = GREEN, blink = true})
	if status != "" and page in [Page.SPLASH, Page.SIGN_IN, Page.MAIN, Page.MAINTENANCE, Page.NEW_LEVEL, Page.SINGLEPLAYER, Page.MULTIPLAYER]:
		items.append({kind = "gap"})
		items.append({kind = "text", text = status, color = AMBER})
	return items


func _selectable() -> Array[Dictionary]:
	var items := _items()
	var out: Array[Dictionary] = []
	for item in items:
		if item.kind in ["item", "field"]:
			out.append(item)
	return out


func _current_item() -> Dictionary:
	var items := _selectable()
	if items.is_empty():
		return {}
	cursor = clampi(cursor, 0, items.size() - 1)
	return items[cursor]


func _field_item() -> Dictionary:
	var item := _current_item()
	return item if item.get("kind") == "field" else {}


func _page_title() -> String:
	match page:
		Page.SIGN_IN: return "FUNG AI  |  CHANGE NAME" if _name_from == Page.SETTINGS else "FUNG AI  |  SIGN IN"
		Page.MAIN: return "FUNG AI  |  MAIN"
		Page.SINGLEPLAYER: return "FUNG AI  |  SINGLEPLAYER"
		Page.MULTIPLAYER: return "FUNG AI  |  MULTIPLAYER"
		Page.HOST: return "FUNG AI  |  HOST A SHIFT"
		Page.JOIN: return "FUNG AI  |  JOIN A SHIFT"
		Page.SETTINGS: return "FUNG AI  |  SETTINGS"
		Page.STATEMENT: return str(Lines.ENDING.title)
		Page.MAINTENANCE: return "FUNG AI  |  SITE MAINTENANCE"
		Page.NEW_LEVEL: return "FUNG AI  |  NEW LEVEL"
		Page.TRANSFER: return "FUNG AI  |  PEOPLE OPERATIONS"
		Page.DISCARD: return "FUNG AI  |  SHIFT ON FILE"
		Page.LOG: return SESSION_STARTED
	return CONSOLE_TITLE


func _footer_text() -> String:
	match page:
		Page.SPLASH: return "SHIFT: sign in    Esc: step away"
		Page.SIGN_IN, Page.JOIN, Page.NEW_LEVEL: return "type    Enter: select    Esc: back"
		Page.SETTINGS: return "arrows: change    Esc: back"
		Page.STATEMENT: return "SHIFT: sign in" if _statement == "done" else ""
		Page.LOG, Page.TRANSFER: return ""
		Page.MAIN, Page.MAINTENANCE: return "arrows    SHIFT: select    Esc: step away"
	return "arrows    SHIFT: select    Esc: back"


## Redraws the console for the current page.
func _render() -> void:
	if not is_inside_tree():
		return
	_blinkers.clear()
	_cursor_block = null
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var on_log := page == Page.LOG
	_log_box.visible = on_log
	_body.visible = not on_log
	_header.text = _page_title()
	_footer.text = _footer_text()
	_footer.visible = _footer.text != ""
	if on_log:
		return
	for child in _body.get_children():
		if child != _settings_menu:
			child.free()
	if page == Page.SETTINGS:
		if _settings_menu == null:
			_settings_menu = SettingsMenu.create(1, GREEN, true)
			_settings_menu.closed.connect(func() -> void: open_page(Page.MAIN))
			_settings_menu.rename.connect(_change_name)
			_body.add_child(_settings_menu)
		_settings_menu.visible = true
		return
	if _settings_menu:
		# Queued: its closed signal (Esc) is what brings us here.
		_body.remove_child(_settings_menu)
		_settings_menu.queue_free()
		_settings_menu = null
	_current_item() # Clamps the cursor.
	var index := -1
	for item in _items():
		match item.kind:
			"gap":
				var gap := Control.new()
				gap.custom_minimum_size.y = 6
				_body.add_child(gap)
			"title":
				var title := Label.new()
				title.text = item.text
				title.label_settings = PixelFont.settings(FONT_SIZE * 3, BRIGHT, 0, 3)
				title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				_body.add_child(title)
			"text":
				var label := _console_label(item.text, item.get("color", GREEN))
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				if page == Page.SPLASH or page == Page.STATEMENT and item.get("blink", false):
					label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				_body.add_child(label)
				if item.get("blink", false):
					_blinkers.append(label)
			"pair":
				var row := HBoxContainer.new()
				var left := _console_label(item.text, item.color)
				left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				left.clip_text = true
				row.add_child(left)
				row.add_child(_console_label(item.right, item.color))
				_body.add_child(row)
			"item", "field":
				var line := HBoxContainer.new()
				line.add_theme_constant_override("separation", 2)
				index += 1
				var is_chosen := index == cursor
				var caret := _console_label(">" if is_chosen else "", AMBER)
				caret.custom_minimum_size.x = FONT_SIZE
				line.add_child(caret)
				if item.kind == "field":
					var value := _console_label(_get_field(item.field), BRIGHT)
					line.add_child(value)
					var block := ColorRect.new()
					block.color = BRIGHT if is_chosen else DIM
					block.custom_minimum_size = Vector2(5, 7)
					block.size_flags_vertical = Control.SIZE_SHRINK_CENTER
					line.add_child(block)
					if is_chosen:
						_blinkers.append(block)
						_cursor_block = block
				else:
					var dim: bool = item.get("dim", false)
					var label := _console_label(item.text, DIM if dim else (BRIGHT if is_chosen else GREEN))
					line.add_child(label)
					if dim and str(item.get("note", "")) != "":
						var note := _console_label(" (%s)" % item.note, DIM)
						note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
						note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						line.add_child(note)
				_body.add_child(line)
				if str(item.get("detail", "")) != "":
					# A lit line's note, under it and indented past the caret.
					var detail := _console_label(item.detail, DIM)
					detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					var indent := MarginContainer.new()
					indent.add_theme_constant_override("margin_left", FONT_SIZE + 2)
					indent.add_child(detail)
					_body.add_child(indent)


func _console_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.label_settings = PixelFont.settings(FONT_SIZE, color, 0, 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# --- The room ------------------------------------------------------------------------------------------

## Loads levels/cubicle into a world of its own: terrain, props stamped as play mode stamps them
## (the other cubicles' monitors switched off), lights from the light markers, the console quad over
## the monitor's screen voxels, the interactables, the leaving trigger, and the Player at the spawn.
## False if the level or its monitor is missing.
func _build_room() -> bool:
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
	VoxelMaterials.apply_to(_world)
	add_child(_world)
	_world.set_data(level.voxels)
	var props := Props.new(_world, 0)
	for object: Dictionary in level.objects.values():
		if object.kind == "prop":
			props.place(object.name, object.origin, int(object.facing))
	for id: String in level.objects:
		var object: Dictionary = level.objects[id]
		if object.kind == "prop" and object.name == "terminal" and id != MONITOR_ID:
			var off := LevelSchema.prop_box(object)
			_world.replace_in_box(Vector3i(off.position), Vector3i(off.end), VoxelMaterials.RUBBER, PackedByteArray([VoxelMaterials.SCREEN]))
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
		elif object.kind == "marker" and object.type == "trigger" and object.get("id") == LEAVE_ID:
			var box := LevelSchema.marker_box(object)
			_leave_box = AABB(box.position * vs, box.size * vs)
			# The red light over the hallway side of the opening, off until someone strays.
			_hall_light.light_color = Color(1.0, 0.12, 0.08)
			_hall_light.omni_range = 6.0
			_hall_light.light_energy = 0.0
			_hall_light.shadow_enabled = false
			_hall_light.position = Vector3(_leave_box.get_center().x, _leave_box.end.y - 0.2, _leave_box.end.z + 0.4)
			add_child(_hall_light)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = level.settings.get("ambient_color", Color(0.5, 0.5, 0.56))
	env.ambient_light_energy = level.settings.get("ambient_energy", 0.25)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = not OS.has_feature("web")
	env.glow_intensity = 0.9
	env.glow_bloom = 0.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.015, 0.015, 0.02)
	env.fog_density = 0.01
	environment.environment = env
	add_child(environment)

	# What E reaches: the computer, the duck, the bag, the plant, the notes.
	for id: String in level.objects:
		var object: Dictionary = level.objects[id]
		if object.kind != "prop":
			continue
		var label := ""
		if id == MONITOR_ID:
			label = "Use computer"
		elif object.name == "rubber_duck":
			label = "Rubber duck"
		elif object.name == "sleeping_bag":
			label = "Sleeping bag"
		elif object.name == "fake_plant":
			label = "Fake plant"
		elif object.get("use") == "note":
			label = "Read"
		if label != "":
			var box := LevelSchema.prop_box(object)
			_interactables[id] = {box = AABB(box.position * vs, box.size * vs), label = label}

	# The monitor: its box, its screen's face (the SCREEN voxels' front, by the prop's facing).
	var monitor: Dictionary = level.objects.get(MONITOR_ID, {})
	if monitor.is_empty():
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
		var face := screen_box.position + screen_box.size * 0.5
		_screen_center = face + _screen_normal * (screen_box.size * _screen_normal.abs()).length() * 0.5
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
	_zoom_camera.near = 0.02
	add_child(_zoom_camera)
	_spawn_player(vs)
	return true


## The ordinary Player at spawn 1: walking, unarmed, its flashlight off, no networking.
func _spawn_player(vs: float) -> void:
	var feet := Vector3.ZERO
	var yaw := 0.0
	for object: Dictionary in level.objects.values():
		if object.kind == "marker" and object.type == "spawn" and int(object.get("index", 1)) == 1:
			feet = Vector3(object.position) * vs
			yaw = deg_to_rad(float(object.yaw))
	player = PLAYER_SCENE.instantiate()
	player.name = "Player"
	player.world = _world
	add_child(player)
	player.teleport(feet)
	player.rotation.y = yaw
	player.set_armed(false)
	player.flashlight.visible = false
	player.camera.current = true
	# Eyes on the screen: the head pitched down toward it.
	var eye := feet + Vector3.UP * (player.standing_height - player.eye_offset)
	var toward := _screen_center - eye
	player.head.rotation.x = atan2(toward.y, Vector2(toward.x, toward.z).length())


# --- The console (drawn on the screen) --------------------------------------------------------------

func _build_console() -> void:
	_viewport.size = SCREEN_PIXELS
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.transparent_bg = false
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_viewport)
	var background := ColorRect.new()
	background.color = BACKGROUND
	_viewport.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_console)
	_console.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_console.offset_left = 6.0
	_console.offset_top = 4.0
	_console.offset_right = -6.0
	_console.offset_bottom = -4.0
	_console.add_theme_constant_override("separation", 2)
	_header.text = CONSOLE_TITLE
	_header.label_settings = PixelFont.settings(FONT_SIZE, HEADER, 0, 1)
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_console.add_child(_header)
	var rule := ColorRect.new()
	rule.color = Color(0.25, 0.5, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	_console.add_child(rule)
	_body.add_theme_constant_override("separation", 2)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.clip_contents = true
	_console.add_child(_body)
	_log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_box.add_theme_constant_override("separation", 2)
	_log_box.visible = false
	_console.add_child(_log_box)
	_log.add_theme_constant_override("separation", 3)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_box.add_child(_log)
	_notification.text = EMAIL_NOTICE
	_notification.label_settings = PixelFont.settings(FONT_SIZE, BLUE, 0, 1)
	_notification.visible = false
	_log_box.add_child(_notification)
	_prompt.label_settings = PixelFont.settings(FONT_SIZE, BRIGHT, 0, 1)
	_prompt.visible = false
	_log_box.add_child(_prompt)
	_footer.label_settings = PixelFont.settings(FONT_SIZE, DIM, 0, 1)
	_console.add_child(_footer)


# --- Over everything -----------------------------------------------------------------------------------

func _build_overlay() -> void:
	_layer.layer = 10
	add_child(_layer)
	# Pixel text (PixelFont) stays hard-edged: everything on the layer draws with nearest filtering.
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_layer.child_entered_tree.connect(func(child: Node) -> void:
		if child is CanvasItem:
			PixelFont.nearest(child))

	# The use prompt at the bottom center, the crosshair, the first frame's hint, the F9 hint.
	_use_prompt.label_settings = _label(16, Color(1.0, 0.95, 0.8))
	_use_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_use_prompt.visible = false
	_layer.add_child(_use_prompt)
	_use_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_use_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_use_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_use_prompt.offset_bottom = -48.0
	_crosshair.text = "+"
	_crosshair.label_settings = _label(16, Color(1, 1, 1, 0.7))
	_layer.add_child(_crosshair)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	_click_hint.text = CLICK_HINT
	_click_hint.label_settings = _label(16, Color(1.0, 0.95, 0.8))
	_click_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_layer.add_child(_click_hint)
	_click_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_click_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_click_hint.grow_vertical = Control.GROW_DIRECTION_BOTH
	_hint.text = SKIP_HINT
	_hint.label_settings = _label(16, Color(1, 1, 1, 0.55))
	_hint.visible = false
	_layer.add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_hint.position = Vector2(12, 8)

	# The subtitle, in the intercom's style.
	_subtitle_panel.add_theme_stylebox_override("panel", _style(Color(0.02, 0.03, 0.03, 0.82), Color(0.4, 0.75, 1.0, 0.7), 1, 12))
	_subtitle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_panel.visible = false
	_subtitle.label_settings = _label(16, Color(0.85, 0.93, 1.0))
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_panel.add_child(_subtitle)
	_layer.add_child(_subtitle_panel)

	# The reader, in the reader panel's style.
	_reader = PanelContainer.new()
	_reader.add_theme_stylebox_override("panel", _style(Color(0.03, 0.06, 0.05, 0.94), Color(0.3, 0.8, 0.6, 0.8), 2, 18))
	_reader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var reader_column := VBoxContainer.new()
	reader_column.add_theme_constant_override("separation", 10)
	_reader.add_child(reader_column)
	_reader_title.label_settings = _label(16, Color(0.55, 1.0, 0.8))
	reader_column.add_child(_reader_title)
	_reader_text.label_settings = _label(16, Color(0.85, 0.95, 0.9))
	_reader_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reader_text.custom_minimum_size = Vector2(480, 0)
	reader_column.add_child(_reader_text)
	var reader_hint := Label.new()
	reader_hint.text = "E or Esc to close"
	reader_hint.label_settings = _label(16, Color(1, 1, 1, 0.5))
	reader_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	reader_column.add_child(reader_hint)
	_reader.visible = false
	_layer.add_child(_reader)

	# The clock-out prompt, in the console's style.
	_clock_panel = PanelContainer.new()
	_clock_panel.add_theme_stylebox_override("panel", _style(Color(BACKGROUND, 0.97), Color(0.25, 0.5, 0.35), 2, 20))
	var clock_column := VBoxContainer.new()
	clock_column.add_theme_constant_override("separation", 14)
	_clock_panel.add_child(clock_column)
	var clock_text := Label.new()
	clock_text.text = CLOCK_OUT_TEXT
	clock_text.label_settings = _label(16, BRIGHT)
	clock_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clock_text.custom_minimum_size = Vector2(520, 0)
	clock_column.add_child(clock_text)
	var clock_keys := Label.new()
	clock_keys.text = CLOCK_OUT_KEYS
	clock_keys.label_settings = _label(16, AMBER)
	clock_column.add_child(clock_keys)
	_clock_panel.visible = false
	_layer.add_child(_clock_panel)
	_clock_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_clock_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_clock_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	# The email: a window over the monitor (centered, scrolling).
	_email = PanelContainer.new()
	_email.add_theme_stylebox_override("panel", _style(Color(0.93, 0.93, 0.9), Color(0.5, 0.5, 0.5), 2, 16))
	_email.custom_minimum_size = Vector2(620, 0)
	var email_column := VBoxContainer.new()
	email_column.add_theme_constant_override("separation", 8)
	_email.add_child(email_column)
	for line in ["From: " + EMAIL_FROM, "Subject: " + EMAIL_SUBJECT]:
		var head := Label.new()
		head.text = line
		head.label_settings = _label(16, Color(0.15, 0.15, 0.2))
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.custom_minimum_size = Vector2(580, 0)
		email_column.add_child(head)
	_email_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_email_scroll.custom_minimum_size = Vector2(580, 220)
	var body := Label.new()
	body.text = EMAIL_BODY + "\n\n" + EMAIL_FINE_PRINT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(560, 0)
	body.label_settings = _label(16, Color(0.1, 0.1, 0.12))
	_email_scroll.add_child(body)
	email_column.add_child(_email_scroll)
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 16)
	choices.alignment = BoxContainer.ALIGNMENT_CENTER
	for entry: Array in [["ACCEPT (A)", accept], ["DECLINE (D)", decline]]:
		var button := Button.new()
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(entry[1])
		choices.add_child(button)
	email_column.add_child(choices)
	_email.visible = false
	_layer.add_child(_email)
	_email.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_email.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_email.grow_vertical = Control.GROW_DIRECTION_BOTH

	# The vignette, the black, the overlay text and buttons.
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
// Pixel art: 6 px blocks, the darkness in 5 hard steps (no dither, no gradient).
void fragment() {
	vec2 block = floor(FRAGCOORD.xy / 6.0);
	vec2 uv = (block * 6.0 + 3.0) * SCREEN_PIXEL_SIZE;
	float d = distance(uv, vec2(0.5)) * 1.45;
	float edge = mix(1.2, 0.05, strength);
	float a = clamp((d - edge + 0.35) / 0.6, 0.0, 1.0);
	a = ceil(clamp(a + strength * 0.25 * a, 0.0, 1.0) * 5.0) / 5.0;
	COLOR = vec4(0.05, 0.0, 0.0, a);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("strength", 0.0)
	_vignette.material = material
	_layer.add_child(_vignette)
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.color = Color.BLACK
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.visible = false
	_layer.add_child(_black)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var overlay := VBoxContainer.new()
	overlay.add_theme_constant_override("separation", 20)
	_overlay_text.label_settings = _label(24, Color.WHITE)
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
	overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
	overlay.grow_vertical = Control.GROW_DIRECTION_BOTH


## A line at the bottom of the screen in the intercom's style; intercom lines get its chime and
## prefix.
func _say(text: String, intercom := false) -> void:
	_subtitle.text = ("[Intercom] " + text) if intercom else text
	_subtitle_left = maxf(MIN_SUBTITLE, _subtitle.text.length() * SECONDS_PER_CHAR)
	_subtitle_panel.visible = true
	if intercom:
		Sfx.play("intercom_chime", -6.0, 0.0)
	_fit_subtitle()


## The subtitle shown now ("" when none).
func subtitle_text() -> String:
	return _subtitle.text if _subtitle_panel.visible else ""


func _fit_subtitle() -> void:
	var viewport := get_viewport().get_visible_rect().size
	if _subtitle.text == _fit_key and viewport == _fit_size:
		return
	_fit_key = _subtitle.text
	_fit_size = viewport
	var width := minf(900.0, viewport.x - 40.0)
	_subtitle.custom_minimum_size.x = minf(width - 24.0, _subtitle.label_settings.font.get_string_size(_subtitle.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _subtitle.label_settings.font_size).x + 4.0)
	_subtitle_panel.size = _subtitle_panel.get_combined_minimum_size()
	_subtitle_panel.position = Vector2((viewport.x - _subtitle_panel.size.x) * 0.5, viewport.y - _subtitle_panel.size.y - 96.0)


func _fit_center(panel: Control) -> void:
	var viewport := get_viewport().get_visible_rect().size
	panel.size = panel.get_combined_minimum_size()
	panel.position = (viewport - panel.size) * 0.5


## The pixel font (PixelFont) at about size px.
static func _label(size: int, color := Color.WHITE) -> LabelSettings:
	return PixelFont.settings(size, color, 0, 1 if size <= 10 else 2)


## Hard-edged panel style: no rounded corners.
static func _style(fill: Color, border: Color, border_width: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_content_margin_all(margin)
	style.set_corner_radius_all(0)
	return style


func _set_buttons(entries: Array) -> void:
	for child in _buttons.get_children():
		child.free()
	for entry: Array in entries:
		var button := Button.new()
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(entry[1])
		_buttons.add_child(button)
	_buttons.visible = true


static func _distance_to_box(point: Vector3, box: AABB) -> float:
	return point.distance_to(point.clamp(box.position, box.end))
