class_name Intercom
extends Control
## The facility's intercom: subtitles at the bottom of the screen with a chime, one line at a time.
## The host decides what plays (say) and tells every peer the line's id, so the party reads it
## together; each peer queues and shows it. Lines live in Lines.INTERCOM and play once each unless
## they're in Lines.REPEATABLE (those are rate limited instead). Story wires the triggers to it.

## Seconds a line stays for each character, and the least it stays.
const SECONDS_PER_CHAR := 0.06
const MIN_SECONDS := 3.0
## A repeatable line won't play again within this many seconds.
const REPEAT_GAP := 8.0
const MAX_WIDTH := 900.0

var lab: Lab
## Host: line ids said so far (once-only lines).
var said := {}
## Host: id -> msec a repeatable line last played.
var _last := {}
## This peer: ids waiting to show, and the one showing.
var _queue: Array[String] = []
var showing := ""
var _time_left := 0.0
var _panel := PanelContainer.new()
var _label := Label.new()


func _ready() -> void:
	name = "Intercom"
	set_anchors_preset(Control.PRESET_FULL_RECT)
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


## Host: plays a line everywhere, if it hasn't been said (or is repeatable and not too soon).
func say(id: String) -> void:
	if not multiplayer.is_server() or not Lines.INTERCOM.has(id):
		return
	var now := Time.get_ticks_msec()
	if id in Lines.REPEATABLE:
		if now - int(_last.get(id, -100000)) < REPEAT_GAP * 1000.0:
			return
		_last[id] = now
	elif said.has(id):
		return
	said[id] = true
	for peer_id in Net.players:
		if peer_id != multiplayer.get_unique_id() and lab.players.has(peer_id):
			_line.rpc_id(peer_id, id)
	_enqueue(id)


@rpc("authority", "reliable")
func _line(id: String) -> void:
	_enqueue(id)


func _enqueue(id: String) -> void:
	if id not in _queue:
		_queue.append(id)


## Text of a line id ("" for unknown).
static func text_of(id: String) -> String:
	return str(Lines.INTERCOM.get(id, ""))


func _process(delta: float) -> void:
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


## Bottom center, never wider than the viewport.
func _fit() -> void:
	var viewport := get_viewport_rect().size
	var width := minf(MAX_WIDTH, viewport.x - 40.0)
	_label.custom_minimum_size.x = width - 24.0
	_panel.size = _panel.get_combined_minimum_size()
	_panel.position = Vector2((viewport.x - _panel.size.x) * 0.5, viewport.y - _panel.size.y - 96.0)
