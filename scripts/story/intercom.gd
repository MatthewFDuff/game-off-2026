class_name Intercom
extends Control
## The facility's intercom: subtitles at the bottom of the screen with a chime, one line at a time.
## The host decides what plays (say, say_text, say_after) and tells every peer, so the party reads
## it together; each peer queues and shows it. Lines live in Lines.INTERCOM and play once each
## unless they're in Lines.REPEATABLE (those are rate limited instead). A newer tour line (`say_*`)
## drops a tour line still waiting in the queue, so a quick player isn't read the last room's line.
## While the reader panel or the controls sheet is open, the subtitle moves to the top of the
## screen so it never covers them. Story wires the triggers to it; it listens to door refusals
## itself for the per-door hints (`hint_<door id>`), and resets on a mode change (the editor's F5).

## Seconds a line stays for each character, and the least it stays.
const SECONDS_PER_CHAR := 0.06
const MIN_SECONDS := 3.0
## A repeatable line won't play again within this many seconds.
const REPEAT_GAP := 8.0
const MAX_WIDTH := 900.0
## Pixels between the subtitle and the bottom of the screen, or the top while something's open.
const BOTTOM_GAP := 96.0
const TOP_GAP := 12.0
## Tour lines (the walk-through's room lines) start with this; a newer one drops a queued one.
const TOUR_PREFIX := "say_"
## Free-text lines (say_text) are queued as this prefix and the text.
const TEXT_PREFIX := "@"
## A door's own hint line, played on its first refusal instead of the generic one.
const HINT_PREFIX := "hint_"
const REFUSED_LINE := "gate_locked"
## The training room's nudge: played this long after say_training unless the experiment started,
## and dropped when the outbreak fires.
const NUDGE_LINE := "say_training_nudge"
const NUDGE_AFTER := "say_training"
const NUDGE_SECONDS := 30.0
const NUDGE_CANCEL := "t_0_outbreak"

var lab: Lab
## Host: line ids said so far (once-only lines).
var said := {}
## Host: id -> msec a repeatable line last played.
var _last := {}
## Host: delayed lines, id -> {left: seconds, unless: Callable (true skips the line)}.
var _pending := {}
## Host: the frame a door hint played, so the generic refusal line that follows it is dropped.
var _hint_frame := -1
## This peer: ids waiting to show, and the one showing.
var _queue: Array[String] = []
var showing := ""
var _time_left := 0.0
var _panel := PanelContainer.new()
var _label := Label.new()


func _ready() -> void:
	name = "Intercom"
	# The offsets too: inside the tree, set_anchors_preset alone keeps the old 0 x 0 rect.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.03, 0.82)
	style.border_color = Color(0.4, 0.75, 1.0, 0.7)
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(3)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	_label.label_settings = LabHud._settings(17, Color(0.85, 0.93, 1.0), 0)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_label)
	if lab == null:
		return
	lab.mode_changed.connect(func(_mode: String) -> void: reset())
	if lab.play:
		# Connected before Story's own door_refused handler, so a hint can stand in for gate_locked.
		lab.play.door_refused.connect(_on_door_refused)
		lab.play.triggered.connect(func(id: String, _peer: int) -> void:
			if id == NUDGE_CANCEL:
				cancel_after(NUDGE_LINE))


## Host: plays a line everywhere, if it hasn't been said (or is repeatable and not too soon).
func say(id: String) -> void:
	if not multiplayer.is_server() or not Lines.INTERCOM.has(id):
		return
	if id == REFUSED_LINE and _hint_frame == Engine.get_process_frames():
		return
	var now := Time.get_ticks_msec()
	if id in Lines.REPEATABLE:
		if now - int(_last.get(id, -100000)) < REPEAT_GAP * 1000.0:
			return
		_last[id] = now
	elif said.has(id):
		return
	said[id] = true
	_broadcast(id)
	if id == NUDGE_AFTER:
		say_after(NUDGE_LINE, NUDGE_SECONDS, _experiment_started)


## Host: plays free text everywhere (not from Lines; the waiting room's hold lines), every time.
func say_text(text: String) -> void:
	if not multiplayer.is_server() or text.strip_edges() == "":
		return
	_broadcast(TEXT_PREFIX + text)


## Host: plays line id after seconds (unpaused), unless unless() is true by then or it's cancelled.
## Saying it again before then restarts the wait.
func say_after(id: String, seconds: float, unless := Callable()) -> void:
	if not multiplayer.is_server():
		return
	_pending[id] = {left = seconds, unless = unless}


## Host: drops a delayed line (all of them for "").
func cancel_after(id := "") -> void:
	if id == "":
		_pending.clear()
	else:
		_pending.erase(id)


## True while a delayed line is waiting.
func is_pending(id: String) -> bool:
	return _pending.has(id)


## Forgets what was said and clears the screen: a new play (the editor's F5) tours afresh.
func reset() -> void:
	said.clear()
	_last.clear()
	_pending.clear()
	_queue.clear()
	showing = ""
	_time_left = 0.0
	_panel.visible = false


func _broadcast(entry: String) -> void:
	for peer_id in Net.players:
		if peer_id != multiplayer.get_unique_id() and lab.players.has(peer_id):
			_line.rpc_id(peer_id, entry)
	_enqueue(entry)


@rpc("authority", "reliable")
func _line(entry: String) -> void:
	_enqueue(entry)


func _enqueue(entry: String) -> void:
	if entry in _queue:
		return
	if entry.begins_with(TOUR_PREFIX):
		_queue.assign(_queue.filter(func(queued: String) -> bool: return not queued.begins_with(TOUR_PREFIX)))
	_queue.append(entry)


## Host: a door refused someone. Its own hint line plays the first time, if Lines has one; the
## generic refusal (Story's gate_locked) plays otherwise.
func _on_door_refused(id: String, _peer_id: int) -> void:
	var hint := HINT_PREFIX + id
	if multiplayer.is_server() and Lines.INTERCOM.has(hint) and not said.has(hint):
		say(hint)
		_hint_frame = Engine.get_process_frames()


## The training terminal's experiment has had a step run (any terminal with `steps`).
func _experiment_started() -> bool:
	for id: String in lab.level.objects:
		if str(lab.level.objects[id].get("steps", "")) != "" and int(lab.play.state_of(id).get("step", 0)) > 0:
			return true
	return false


## Text of a line id or free-text entry ("" for unknown).
static func text_of(id: String) -> String:
	if id.begins_with(TEXT_PREFIX):
		return id.substr(TEXT_PREFIX.length())
	return str(Lines.INTERCOM.get(id, ""))


func _process(delta: float) -> void:
	if lab == null or not is_instance_valid(lab):
		return
	if not _pending.is_empty() and not get_tree().paused:
		for id: String in _pending.keys():
			var entry: Dictionary = _pending[id]
			entry.left -= delta
			if entry.left > 0.0:
				continue
			_pending.erase(id)
			var unless: Callable = entry.unless
			if not (unless.is_valid() and unless.call()):
				say(id)
	if showing != "":
		_time_left -= delta
		if _time_left <= 0.0:
			showing = ""
			_panel.visible = false
	if showing == "" and not _queue.is_empty():
		showing = _queue.pop_front()
		var text := "[Intercom] " + text_of(showing)
		_label.text = text
		_time_left = maxf(MIN_SECONDS, text.length() * SECONDS_PER_CHAR)
		_panel.visible = lab.mode == "play"
		Sfx.play("intercom_chime", -6.0, 0.0)
	if _panel.visible:
		_fit()


## True while the reader panel or the controls sheet is open: the subtitle goes to the top.
func overlay_open() -> bool:
	if lab.play and lab.play.reading != "":
		return true
	var hud := get_parent().get_parent() if get_parent() else null
	if hud:
		for node in hud.get_children():
			if node is ControlsOverlay and node.visible:
				return true
	return false


## Bottom center (top center while overlay_open), never wider than the viewport.
func _fit() -> void:
	var viewport := get_viewport_rect().size
	var width := minf(MAX_WIDTH, viewport.x - 40.0)
	_label.custom_minimum_size.x = width - 24.0
	_panel.size = _panel.get_combined_minimum_size()
	var y := TOP_GAP if overlay_open() else viewport.y - _panel.size.y - BOTTOM_GAP
	_panel.position = Vector2((viewport.x - _panel.size.x) * 0.5, y)
