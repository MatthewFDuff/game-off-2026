class_name Ending
extends Control
## The payroll statement: fade to black, then the night's accounts one line at a time with a cash
## register tick (wages, every broken asset by name, clones grown, the total owed in red), Guy
## Fung's note, and a button back to the menu. The host builds the lines (begin) and sends them to
## every peer; each peer plays the screen.

const FADE_SECONDS := 2.0
const LINE_GAP := 0.45
const MAX_WIDTH := 640.0

var lab: Lab
var shown := false
var total := 0
var _lines: Array[String] = []
var _black := ColorRect.new()
var _panel := PanelContainer.new()
var _column := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _button := Button.new()


func _ready() -> void:
	name = "Ending"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_black.color = Color(0, 0, 0, 0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_black)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.04, 0.97)
	style.border_color = Color(0.55, 1.0, 0.8, 0.8)
	style.set_border_width_all(2)
	style.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.visible = false
	add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	_panel.add_child(outer)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll)
	_column.add_theme_constant_override("separation", 4)
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_column)
	_button.text = "Back to menu"
	_button.visible = false
	_button.pressed.connect(func() -> void: Net.leave())
	outer.add_child(_button)


## Host: works the statement out and shows it everywhere. clones is how many respawns the night took.
func begin(clones: int) -> void:
	if not multiplayer.is_server() or shown:
		return
	var play := lab.play
	var lines: Array[String] = []
	var wages := int(Lines.ENDING.wages)
	lines.append("Shift wages|+$%d" % wages)
	var owed := 0
	var names: Array = play.damage_by_name.keys()
	names.sort()
	if names.is_empty():
		lines.append("Property damage|$0")
	else:
		lines.append("Property damage:|")
		for asset_name: String in names:
			var dollars := int(play.damage_by_name[asset_name])
			owed += dollars
			lines.append("   %s|-$%d" % [asset_name.replace("_", " "), dollars])
	var clone_cost := clones * int(Lines.ENDING.clone_cost)
	owed += clone_cost
	lines.append("Clones grown: %d x $%d|-$%d" % [clones, int(Lines.ENDING.clone_cost), clone_cost])
	lines.append("Doors forced|-$0")
	var net := wages - owed
	lines.append("TOTAL OWED TO FUNG AI|-$%d" % (-net) if net < 0 else "NET PAY|+$%d" % net)
	for peer_id in Net.players:
		if peer_id != multiplayer.get_unique_id() and lab.players.has(peer_id):
			_show.rpc_id(peer_id, lines, net)
	_show(lines, net)


@rpc("authority", "reliable")
func _show(lines: Array, net: int) -> void:
	if shown:
		return
	shown = true
	total = net
	_lines.assign(lines)
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tween := create_tween()
	tween.tween_property(_black, "color", Color(0, 0, 0, 1), FADE_SECONDS)
	tween.tween_callback(_roll)


func _roll() -> void:
	_panel.visible = true
	_fit()
	_add(str(Lines.ENDING.title), "", Color(0.55, 1.0, 0.8), 18)
	await get_tree().create_timer(LINE_GAP).timeout
	for line in _lines:
		var parts := line.split("|")
		var is_total := line.begins_with("TOTAL") or line.begins_with("NET PAY")
		var color := Color(1.0, 0.35, 0.3) if line.begins_with("TOTAL") else (Color(0.6, 1.0, 0.6) if line.begins_with("NET PAY") else Color(0.85, 0.95, 0.9))
		_add(parts[0], parts[1] if parts.size() > 1 else "", color, 18 if is_total else 15)
		Sfx.play("register_tick", -8.0, 0.02)
		await get_tree().create_timer(LINE_GAP).timeout
	await get_tree().create_timer(LINE_GAP).timeout
	_add(str(Lines.ENDING.note), "", Color(0.85, 0.85, 0.75), 15)
	_button.visible = true
	_fit()


func _add(left: String, right: String, color: Color, size: int) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = left
	label.label_settings = LabHud._settings(size, color, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if right != "":
		var amount := Label.new()
		amount.text = right
		amount.label_settings = LabHud._settings(size, color, 0)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(amount)
	_column.add_child(row)
	_fit()
	_scroll.scroll_vertical = 100000


## Centered, never wider or taller than the viewport.
func _fit() -> void:
	var viewport := get_viewport_rect().size
	var width := minf(MAX_WIDTH, viewport.x - 40.0)
	_column.custom_minimum_size.x = width - 48.0
	_scroll.custom_minimum_size = Vector2(width - 40.0, minf(_column.get_combined_minimum_size().y + 4.0, viewport.y * 0.7))
	_panel.size = _panel.get_combined_minimum_size()
	_panel.position = (viewport - _panel.size) * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if visible and _button.visible and event.is_action_pressed("ui_cancel"):
		Net.leave()
