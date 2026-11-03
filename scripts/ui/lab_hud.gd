class_name LabHud
extends CanvasLayer
## Co-op level HUD: crosshair, who's in the session, and a pause panel (shown whenever the mouse is
## released) to get back in or leave. Placeholder until the real HUD (payroll and so on) exists.

@export var lab: Lab

var _crosshair := Label.new()
var _roster := Label.new()
var _pause := PanelContainer.new()
var _pause_info := Label.new()
var _waiting := Label.new()
var _toast := Label.new()
var _toast_time := 0.0


static func _settings(size: int, color := Color.WHITE, outline := 5) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	settings.outline_size = outline
	settings.outline_color = Color.BLACK
	return settings


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_crosshair.text = "+"
	_crosshair.label_settings = _settings(22)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_crosshair)

	_roster.label_settings = _settings(16)
	_roster.position = Vector2(16, 12)
	add_child(_roster)

	_waiting.text = "Joining the host's lab..."
	_waiting.label_settings = _settings(28)
	_waiting.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting.visible = not multiplayer.is_server()
	add_child(_waiting)

	_toast.label_settings = _settings(16, Color(0.75, 1.0, 0.8))
	_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_toast.position += Vector2(16, -60)
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_toast)
	lab.notice.connect(func(text: String) -> void:
		_toast.text = text
		_toast_time = 4.0)

	add_child(CombatHud.create(lab))
	_build_pause()
	if lab.mode != "edit":
		add_child(ControlsOverlay.new())
	Net.players_changed.connect(_update_roster)
	lab.player_spawned.connect(func(_p: Player) -> void: _update_roster())
	lab.player_despawned.connect(func(_id: int) -> void: _update_roster())
	_update_roster()


func _process(delta: float) -> void:
	_toast_time -= delta
	_toast.visible = _toast_time > 0.0
	var playing := InputSetup.is_playing()
	var me := lab.local_player()
	var editor: EditorTool = me.get_node_or_null("EditorTool") if me else null
	_pause.visible = not playing and not _waiting.visible and not (editor and editor.panel_open)
	_crosshair.visible = playing
	# Solo play pauses with the mouse released; co-op and the editor keep running.
	var solo := multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	get_tree().paused = solo and lab.mode != "edit" and not playing and not _waiting.visible
	if _waiting.visible and lab.local_player() != null:
		_waiting.visible = false


func _build_pause() -> void:
	_pause.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_pause.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_pause)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_pause.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Click to play"
	title.label_settings = _settings(28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_pause_info.label_settings = _settings(16, Color(0.8, 0.8, 0.8), 0)
	_pause_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_pause_info)

	var resume := Button.new()
	resume.text = "Resume (click)"
	resume.pressed.connect(func() -> void: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	column.add_child(resume)
	var leave := Button.new()
	leave.text = "End session" if multiplayer.is_server() and Net.players.size() > 1 else "Leave to menu"
	leave.pressed.connect(func() -> void: Net.leave())
	column.add_child(leave)
	_update_pause_info()


func _update_pause_info() -> void:
	if not multiplayer.is_server() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_pause_info.text = ""
		return
	var addresses := Array(IP.get_local_addresses()).filter(func(a: String) -> bool: return a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."))
	_pause_info.text = "Hosting on port %d\nLAN: %s\nFriends outside your network join your public IP\n(port-forward UDP %d)" % [Net.DEFAULT_PORT, ", ".join(addresses), Net.DEFAULT_PORT]


func _update_roster() -> void:
	var lines: Array[String] = []
	for peer_id: int in Net.players:
		var entry: Dictionary = Net.players[peer_id]
		var tags: Array[String] = []
		if peer_id == 1:
			tags.append("host")
		if peer_id == multiplayer.get_unique_id():
			tags.append("you")
		if not lab.players.has(peer_id):
			tags.append("loading")
		lines.append("%s%s" % [entry.name, "  (%s)" % ", ".join(tags) if not tags.is_empty() else ""])
	_roster.text = "\n".join(lines) if Net.players.size() > 1 else ""
