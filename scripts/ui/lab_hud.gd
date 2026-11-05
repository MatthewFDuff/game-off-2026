class_name LabHud
extends CanvasLayer
## Co-op level HUD: crosshair, who's in the session, and the pause panel, shown whenever the mouse
## is released ("SHIFT PAUSED": Resume, Settings, Invite for a co-op host, Leave shift). Settings
## and Invite take the buttons' place in the panel until Esc (or the menu's own back) returns.
## Solo play pauses under it; co-op keeps running. In a story shift a line under the buttons says
## what leaving does (the host saves the shift: Lab.save_shift). On a pad the first button takes
## focus when the panel opens, the D-pad and stick move it, A presses, B goes back a page and
## Start resumes (docs/controls.md, 2.5). Placeholder until the real HUD exists.

@export var lab: Lab

var _crosshair := PixelMark.create("cross", Color(1.0, 1.0, 1.0, 0.9))
var _roster := Label.new()
var _pause := PanelContainer.new()
var _pause_info := Label.new()
var _pause_hint := Label.new()
## What Leave shift does to the shift (shift_hint), under the buttons.
var _shift_hint := Label.new()
var _buttons := VBoxContainer.new()
var _invite := VBoxContainer.new()
var _settings_menu: SettingsMenu
var _waiting := Label.new()
var _toast := Label.new()
var _toast_time := 0.0
var _story: Story
var _combat: CombatHud
var _prompt: InteractPrompt
var _controls: ControlsOverlay
var _solo := true


## HUD label settings: the pixel font (PixelFont) at about size px, a drop shadow for outline > 0.
static func _settings(size: int, color := Color.WHITE, outline := 5) -> LabelSettings:
	return PixelFont.settings(size, color, outline)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Everything on the HUD draws with nearest filtering: pixel text and marks stay hard-edged.
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	child_entered_tree.connect(func(child: Node) -> void:
		if child is CanvasItem:
			PixelFont.nearest(child))
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

	_combat = CombatHud.create(lab)
	add_child(_combat)
	_prompt = InteractPrompt.create(lab)
	add_child(_prompt)
	_build_pause()
	if lab.mode != "edit":
		_controls = ControlsOverlay.new()
		add_child(_controls)
		_story = Story.create(lab)
		add_child(_story)
	Net.players_changed.connect(_update_roster)
	lab.player_spawned.connect(func(_p: Player) -> void: _update_roster())
	lab.player_despawned.connect(func(_id: int) -> void: _update_roster())
	_update_roster()


func _process(delta: float) -> void:
	# The Lab is torn down before its HUD on quit.
	if lab == null or not is_instance_valid(lab):
		return
	_toast_time -= delta
	# While the ending's statement shows, nothing of the HUD draws under it.
	var ending := _story != null and _story.ending.shown
	# The level editor shows its own toasts and roster.
	_toast.visible = _toast_time > 0.0 and lab.mode != "edit" and not ending
	_roster.visible = lab.mode != "edit" and not ending
	_combat.suppressed = ending
	_prompt.visible = not ending
	if ending and _controls:
		_controls.visible = false
	var playing := InputSetup.is_playing()
	# While editing, the editor's own menu (EditorHud) stands in for the pause menu.
	var was_paused := _pause.visible
	_pause.visible = not playing and not _waiting.visible and lab.mode != "edit" and not ending
	if not _pause.visible and not _buttons.visible:
		_show_buttons()
	elif _pause.visible and not was_paused:
		_update_shift_hint()
		_recenter_pause()
		_focus_first()
	if _pause.visible:
		_update_pause_hint()
	_crosshair.visible = playing and not ending
	# Solo play pauses with the mouse released; co-op and the editor keep running.
	var solo := multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	get_tree().paused = solo and lab.mode != "edit" and not playing and not _waiting.visible
	if _waiting.visible and lab.local_player() != null:
		_waiting.visible = false


func _build_pause() -> void:
	_pause.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_pause.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pause.theme = _pause_theme()
	add_child(_pause)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_pause.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title := Label.new()
	title.text = "SHIFT PAUSED"
	title.label_settings = _settings(32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_solo = multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	_update_pause_hint()
	_pause_hint.label_settings = _settings(16, Color(0.7, 0.7, 0.7), 0)
	_pause_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_pause_hint)

	_buttons.add_theme_constant_override("separation", 8)
	column.add_child(_buttons)
	_add_button("Resume", InputSetup.resume_play)
	_add_button("Settings", _show_settings)
	if hosting_info(multiplayer) != "":
		_add_button("Invite", _show_invite)
	_add_button("Leave shift", func() -> void:
		lab.save_shift()
		Net.leave())
	_shift_hint.label_settings = _settings(16, Color(0.7, 0.7, 0.7), 0)
	_shift_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_buttons.add_child(_shift_hint)

	_invite.add_theme_constant_override("separation", 8)
	_invite.visible = false
	column.add_child(_invite)
	_pause_info.label_settings = _settings(16, Color(0.85, 0.85, 0.85), 0)
	_pause_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_invite.add_child(_pause_info)
	var back := Button.new()
	back.text = "Back"
	back.focus_mode = Control.FOCUS_ALL
	back.pressed.connect(_show_buttons)
	_invite.add_child(back)

	_settings_menu = SettingsMenu.create(2, Color(0.9, 0.9, 0.9))
	_settings_menu.visible = false
	_settings_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_settings_menu.closed.connect(_show_buttons)
	column.add_child(_settings_menu)
	_update_pause_info()


func _add_button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(action)
	_buttons.add_child(button)


## How to resume, by device ("Click to resume." / "Press Start to resume."); co-op adds that the
## shift runs on.
func _update_pause_hint() -> void:
	var how := "Press Start to resume." if Pad.active else "Click to resume."
	var text := how if _solo else how + " The shift does not pause for you."
	if _pause_hint.text != text:
		_pause_hint.text = text


## Gives the shown page's first button the focus, so a pad can work the panel at once.
func _focus_first() -> void:
	var page := _buttons if _buttons.visible else _invite
	for child in page.get_children():
		if child is Button and child.visible:
			child.grab_focus()
			return


## The pause panel's look: a flat near-black box with a hard border, square buttons.
static func _pause_theme() -> Theme:
	var theme := PixelFont.theme().duplicate() as Theme
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.04, 0.05, 0.04, 0.94)
	panel.border_color = Color(0.55, 0.6, 0.55)
	panel.set_border_width_all(2)
	panel.anti_aliasing = false
	theme.set_stylebox("panel", "PanelContainer", panel)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = {normal = Color(0.12, 0.13, 0.12), hover = Color(0.2, 0.22, 0.2), pressed = Color(0.95, 0.68, 0.16, 0.35), focus = Color(0, 0, 0, 0), disabled = Color(0.08, 0.08, 0.08)}[state]
		box.border_color = Color(0.95, 0.68, 0.16) if state == "focus" else Color(0.35, 0.38, 0.35)
		box.set_border_width_all(2 if state == "focus" else 1)
		box.draw_center = state != "focus"
		box.anti_aliasing = false
		box.set_content_margin_all(8)
		theme.set_stylebox(state, "Button", box)
	return theme


## Shrinks the panel to its contents and centers it again (they change with the page shown).
func _recenter_pause() -> void:
	_pause.reset_size()
	_pause.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func _show_buttons() -> void:
	_update_shift_hint()
	_buttons.visible = true
	_invite.visible = false
	if _settings_menu:
		_settings_menu.visible = false
	_recenter_pause()
	if _pause.visible:
		_focus_first()


func _update_shift_hint() -> void:
	_shift_hint.text = shift_hint(lab)
	_shift_hint.visible = _shift_hint.text != ""


func _show_settings() -> void:
	_buttons.visible = false
	_settings_menu.visible = true
	get_viewport().gui_release_focus()
	_recenter_pause()


func _show_invite() -> void:
	_update_pause_info()
	_buttons.visible = false
	_invite.visible = true
	_recenter_pause()
	_focus_first()


## The pause panel's keys and pad buttons: Start (or Esc) on the buttons page resumes; the settings
## page takes its keys (and pad presses) through SettingsMenu.handle_key; Esc, B or Start on the
## invite page goes back. _pause.visible is last frame's, so the Start that just paused (the
## Player's _input releasing play) doesn't resume here too; a Start this takes is marked handled,
## which the Player checks.
func _input(event: InputEvent) -> void:
	if not _pause.visible or get_viewport().is_input_handled():
		return
	if _buttons.visible:
		if event.is_action_pressed("ui_cancel"):
			InputSetup.resume_play()
			get_viewport().set_input_as_handled()
		return
	if _settings_menu.visible:
		if _settings_menu.handle_key(event):
			get_viewport().set_input_as_handled()
	elif _invite.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pad_back")):
		_show_buttons()
		get_viewport().set_input_as_handled()


func _update_pause_info() -> void:
	_pause_info.text = hosting_info(multiplayer)


## The pause menu's line about the shift: where the host's clone is held and that leaving saves, a
## peer's reminder that the host keeps it, or "" outside a story shift.
static func shift_hint(level: Lab) -> String:
	if level == null or not level.in_shift():
		return ""
	if not level.multiplayer.is_server():
		return "The host keeps the shift. You can rejoin by address."
	return "Your clone is held at the %s. Leaving saves the shift." % ShiftSave.room_of(level.level, level.play.checkpoint)


## How friends reach this host ("" when not hosting). The editor's menu shows it too.
static func hosting_info(api: MultiplayerAPI) -> String:
	if not api.is_server() or api.multiplayer_peer is OfflineMultiplayerPeer:
		return ""
	var addresses := Array(IP.get_local_addresses()).filter(func(a: String) -> bool: return a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."))
	return "Hosting on port %d\nLAN: %s\nFriends outside your network join your public IP\n(port-forward UDP %d)" % [Net.DEFAULT_PORT, ", ".join(addresses), Net.DEFAULT_PORT]


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
