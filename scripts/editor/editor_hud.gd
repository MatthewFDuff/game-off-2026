class_name EditorHud
extends CanvasLayer
## The level editor's screen, in the paper style (editor only; the game's HUD has its own): a top
## bar (level, who's here, undo / redo / save / play-test, help, menu), a tool rail on the left, an
## inspector card on the right (the tool's options or the selection's properties), a catalog drawer
## along the bottom (materials, props or marker types), a hint line, toasts, and the help and menu
## modals. Visible in edit mode.
##
## In the builder view the mouse is always free; in the walk view Esc frees it for the panels and
## clicking the world takes it back. Input rules are in
## EditorInput: buttons never take keyboard focus, Tab never moves focus, panels keep their clicks
## and wheel, and modals keep everything.

const THEME := preload("res://assets/ui/editor_theme.tres")
const INSPECTOR_WIDTH := 272
const DRAWER_HEIGHT := 158
const BAR_HEIGHT := 52
const MARGIN := 10
const TILE_SIZE := Vector2(86, 86)
const ICON_SIZE := 48
const ROOM_TARGETS := {floor = "Floor", wall = "Walls", ceiling = "Ceiling"}

@export var lab: Lab

var tool: EditorTool
var thumbnails := PropThumbnails.new()

var _root := Control.new()
var _level_label := Label.new()
var _roster := HBoxContainer.new()
## peer id -> the label showing which view they're in.
var _roster_views := {}
var _tool_buttons: Array[Button] = []
var _inspector: PanelContainer
var _inspector_title := Label.new()
var _content := VBoxContainer.new()
var _grid_buttons: Array[Button] = []
var _free_cursor_button: Button
var _view_buttons: Array[Button] = []
var _cut_buttons: Array[Button] = []
var _cut_row: HBoxContainer
var _walls_button: Button
var _drawer: PanelContainer
var _drawer_header := HBoxContainer.new()
var _drawer_tabs := HBoxContainer.new()
var _drawer_tiles := HFlowContainer.new()
var _search := LineEdit.new()
var _drawer_open := true
var _category := "All"
## Which lining the catalog sets for the room tool.
var _room_target := "wall"
var _rail: PanelContainer
var _hint: PanelContainer
var _hint_label := Label.new()
var _toast: PanelContainer
## Sizes of the volume being built (Room / Box / Replace), top center.
var _readout: PanelContainer
var _readout_label := RichTextLabel.new()
var _toast_label := Label.new()
var _toast_time := 0.0
var _help: Control
var _menu: Control
var _menu_info := Label.new()
var _shown_tool := -1
var _shown_selection := ""
var _icons := {}
## The level check's last results (props floating or inside walls), shown with nothing selected.
var _problems: Array[Dictionary] = []
var _problems_checked := false
## prop name -> its catalog tile, for thumbnails that finish rendering later.
var _prop_tiles := {}


func _ready() -> void:
	thumbnails.view = lab.view
	add_child(thumbnails)
	thumbnails.rendered.connect(_on_thumbnail)
	get_tree().node_added.connect(_on_node_added)

	_root.theme = THEME
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	EditorInput.ui_root = _root

	_build_top_bar()
	_build_tool_rail()
	_build_inspector()
	_build_drawer()
	_build_hint()
	_build_toast()
	_build_readout()
	_help = _build_help()
	_menu = _build_menu()

	lab.edits.object_set.connect(_on_object_set)
	lab.notice.connect(_show_toast)
	Net.players_changed.connect(_update_roster)
	lab.player_spawned.connect(func(_p: Player) -> void: _update_roster())
	lab.player_despawned.connect(func(_id: int) -> void: _update_roster())
	_update_roster()
	visible = false


func _exit_tree() -> void:
	EditorInput.close_modal(_help)
	EditorInput.close_modal(_menu)


func _process(delta: float) -> void:
	if lab == null or not is_instance_valid(lab):
		return
	if tool == null:
		var me := lab.local_player()
		if me == null:
			return
		tool = me.get_node("EditorTool")
		tool.changed.connect(_refresh)
		tool.menu_requested.connect(func() -> void: _set_modal(_menu, true))
		_refresh()
	visible = lab.mode == "edit"
	if not visible:
		# Play-testing: modals mustn't keep holding the keys.
		_set_modal(_help, false)
		_set_modal(_menu, false)
		return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and EditorInput.text_focused():
		get_viewport().gui_release_focus()
	_level_label.text = lab.level.name if lab.level else ""
	for peer_id: int in _roster_views:
		var other: Player = lab.players.get(peer_id)
		var label: Label = _roster_views[peer_id]
		if peer_id == multiplayer.get_unique_id():
			label.text = "builder" if tool.builder else "walk"
		elif other and other.has_node("Presence"):
			var seen: Dictionary = other.get_node("Presence").state
			label.text = "" if seen.is_empty() else ("builder" if seen.get("builder", false) else "walk")
	for i in _tool_buttons.size():
		_tool_buttons[i].set_pressed_no_signal(i == tool.tool)
	for i in _grid_buttons.size():
		_grid_buttons[i].set_pressed_no_signal(i == tool.snap_index)
	_free_cursor_button.set_pressed_no_signal(tool.free_cursor)
	_free_cursor_button.visible = not tool.builder
	for i in _view_buttons.size():
		_view_buttons[i].set_pressed_no_signal((i == 0) == tool.builder)
	_cut_row.visible = tool.builder
	for i in _cut_buttons.size():
		_cut_buttons[i].set_pressed_no_signal(i == tool.camera.cut_mode)
	_walls_button.set_pressed_no_signal(tool.camera.walls_down)
	_hint_label.text = _hint_text()
	var readout := tool.volume_readout()
	_readout.visible = readout != ""
	if readout != _readout_label.text:
		_readout_label.text = readout
	_toast.offset_top = BAR_HEIGHT + MARGIN + (48 if _readout.visible else 0)
	_toast_time -= delta
	_toast.visible = _toast_time > 0.0
	_toast.modulate.a = clampf(_toast_time * 2.0, 0.0, 1.0)
	if tool.tool != _shown_tool or (tool.tool == EditorTool.Tool.SELECT and tool.selected != _shown_selection):
		_refresh()


func _hint_text() -> String:
	var view := InputSetup.describe("editor_view")
	if tool.volume.is_active():
		if tool.volume.step == VolumeSteps.Step.FLOOR:
			return "Click the far corner of the floor  ·  wheel: size, Shift+wheel: the other side  ·  type a size (2.5 m, 25v)  ·  Tab: next size  ·  RMB / Backspace: back"
		return "Click to build  ·  move the mouse or wheel: height  ·  type a size  ·  Tab: next size  ·  RMB / Backspace: back to the floor  ·  Esc: cancel"
	if tool.builder:
		var parts: Array[String] = [EditorTool.TOOL_HINTS[tool.tool], "Grid %d" % tool.snap()]
		var camera := tool.camera
		if camera.is_cutting():
			parts.append("Cut %.1f m (%s)" % [camera.cut_layer * lab.world.voxel_size, EditorCamera.CUT_NAMES[camera.cut_mode]])
		parts.append("RMB drag orbit · WASD pan · wheel zoom")
		parts.append("%s: walk" % view)
		return "  ·  ".join(parts)
	if not InputSetup.is_playing():
		return "Click the world to walk and aim  ·  %s: builder view  ·  Esc: menu  ·  %s: help" % [view, InputSetup.describe("editor_help")]
	var parts: Array[String] = [EditorTool.TOOL_HINTS[tool.tool], "Grid %d" % tool.snap(),
			("Fly %.0f (wheel)" % tool.player.fly_speed) if tool.player.flying else "Walking (%s flies)" % InputSetup.describe("editor_fly")]
	if tool.free_cursor:
		parts.append("Free cursor %.1f m (Ctrl+wheel)" % tool.free_distance)
	parts.append("%s: builder view" % view)
	parts.append("Esc: use the panels")
	return "  ·  ".join(parts)


# --- Input ---------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.keycode == KEY_TAB:
		get_viewport().set_input_as_handled() # No focus hopping between controls.
		# Sizing a volume: Tab moves to the next size.
		if event.pressed and not event.echo and tool != null and tool.volume.is_active() and not EditorInput.blocks_keyboard():
			tool.next_size()
		return
	if InputSetup.pressed(event, "editor_help") and not EditorInput.text_focused():
		_set_modal(_help, not _help.visible)
		get_viewport().set_input_as_handled()
	elif InputSetup.pressed(event, "editor_back"):
		var focused := get_viewport().gui_get_focus_owner()
		if EditorInput.text_focused():
			if focused.has_meta("revert"):
				focused.get_meta("revert").call()
			focused.release_focus()
		elif _help.visible:
			_set_modal(_help, false)
		elif _menu.visible:
			_set_modal(_menu, false)
		else:
			return
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if visible and InputSetup.pressed(event, "editor_catalog") and EditorInput.world_may_use(event):
		_drawer_open = not _drawer_open
		if _drawer_open:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_layout()
		get_viewport().set_input_as_handled()


## Every button in the editor UI: no keyboard focus (so Space and Enter never press one) and a click.
func _on_node_added(node: Node) -> void:
	if not _root.is_ancestor_of(node):
		return
	if node is BaseButton:
		node.focus_mode = Control.FOCUS_NONE
		node.pressed.connect(func() -> void: Sfx.play("ui_click", -8.0, 0.05))
	elif node is ItemList or node is ScrollContainer:
		node.focus_mode = Control.FOCUS_NONE


# --- Frame ---------------------------------------------------------------------------------------

## A paper surface that keeps the mouse (clicks and the wheel never fall through to the world).
func _surface(variation: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = variation
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	return panel


func _button(text: String, variation: String, tip: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.tooltip_text = tip
	button.pressed.connect(action)
	return button


func _label(text: String, variation := "Label", font_size := 0) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)
	return label


func _build_top_bar() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = MARGIN
	bar.offset_right = -MARGIN
	bar.offset_top = MARGIN
	bar.custom_minimum_size.y = BAR_HEIGHT - MARGIN
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 8)
	_root.add_child(bar)

	var level := _surface("PaperPill")
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 8)
	level_row.add_child(_label("Level editor", "MutedLabel", 12))
	_level_label.theme_type_variation = "HeaderTitle"
	_level_label.add_theme_font_size_override("font_size", 18)
	level_row.add_child(_level_label)
	level.add_child(level_row)
	bar.add_child(level)

	_roster.add_theme_constant_override("separation", 6)
	_roster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_roster)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	var actions := _surface("PaperPill")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_button("Undo", "ChipButton", "Undo your last edit (%s)" % InputSetup.describe("editor_undo"), func() -> void: lab.edits.undo()))
	row.add_child(_button("Redo", "ChipButton", "Redo (%s)" % InputSetup.describe("editor_redo"), func() -> void: lab.edits.redo()))
	row.add_child(_button("Save", "ChipButton", "Save the level (%s)" % InputSetup.describe("editor_save"), lab.request_save))
	row.add_child(_button("Play-test", "PrimaryButton", "Play the level; press %s again to come back (%s)" % [InputSetup.describe("editor_playtest"), InputSetup.describe("editor_playtest")],
			func() -> void: lab.request_mode("play")))
	row.add_child(_button("?", "ChipButton", "Keys and controls (%s)" % InputSetup.describe("editor_help"), func() -> void: _set_modal(_help, true)))
	row.add_child(_button("Menu", "ChipButton", "Session, save and leave (Esc with the mouse free)", func() -> void: _set_modal(_menu, true)))
	actions.add_child(row)
	bar.add_child(actions)


## Jumps the view to someone: the builder camera looks at where they are or look, the walk view
## stands next to them.
func _go_to(peer_id: int) -> void:
	var other: Player = lab.players.get(peer_id)
	if other == null or tool == null or peer_id == multiplayer.get_unique_id():
		return
	var presence := other.get_node_or_null("Presence") as EditorPresence
	var point: Vector3 = presence.focus_point() if presence else other.global_position
	if tool.builder:
		tool.camera.pivot = point
	else:
		tool.player.teleport(point + Vector3(1.0, 0.0, 0.0))
		tool.player.flying = true


func _update_roster() -> void:
	_roster_views.clear()
	for child in _roster.get_children():
		child.queue_free()
	for peer_id: int in Net.players:
		var entry: Dictionary = Net.players[peer_id]
		var chip := PanelContainer.new()
		var style := PaperPalette.card(PaperPalette.RADIUS_CHIP, 3)
		style.border_color = entry.color
		style.set_content_margin_all(6)
		style.content_margin_left = 10
		style.content_margin_right = 10
		chip.add_theme_stylebox_override("panel", style)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var tags: Array[String] = []
		if peer_id == 1:
			tags.append("host")
		if peer_id == multiplayer.get_unique_id():
			tags.append("you")
		else:
			tags.append("click to go to them")
		chip.tooltip_text = ", ".join(tags)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_label(entry.name, "Label", 14))
		var view := _label("", "MutedLabel", 11)
		row.add_child(view)
		_roster_views[peer_id] = view
		chip.add_child(row)
		chip.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_go_to(peer_id))
		_roster.add_child(chip)


func _build_tool_rail() -> void:
	var rail := _surface("PaperCard")
	_rail = rail
	rail.position = Vector2(MARGIN, BAR_HEIGHT + MARGIN)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	rail.add_child(column)
	for i in EditorTool.TOOL_NAMES.size():
		var button := PopButton.new()
		button.text = "%s  %s" % [InputSetup.describe(EditorTool.TOOL_ACTIONS[i]), EditorTool.TOOL_NAMES[i]]
		button.theme_type_variation = "ToggleButton"
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 14)
		button.tooltip_text = "%s (%s)\n%s" % [EditorTool.TOOL_NAMES[i], InputSetup.describe(EditorTool.TOOL_ACTIONS[i]), EditorTool.TOOL_ABOUT[i]]
		button.pressed.connect(func() -> void: tool.set_tool(i as EditorTool.Tool))
		column.add_child(button)
		_tool_buttons.append(button)
	_root.add_child(rail)
	rail.resized.connect(_layout)


func _build_inspector() -> void:
	_inspector = _surface("PaperCard")
	_inspector.anchor_left = 1.0
	_inspector.anchor_right = 1.0
	_inspector.anchor_bottom = 1.0
	_inspector.offset_left = -INSPECTOR_WIDTH - MARGIN
	_inspector.offset_right = -MARGIN
	_inspector.offset_top = BAR_HEIGHT + MARGIN
	_root.add_child(_inspector)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_inspector.add_child(column)
	_inspector_title.theme_type_variation = "HeaderTitle"
	_inspector_title.add_theme_font_size_override("font_size", 20)
	column.add_child(_inspector_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)
	column.add_child(HSeparator.new())

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 4)
	grid.add_child(_label("Grid", "MutedLabel", 12))
	for i in EditorTool.SNAPS.size():
		var chip := _button(str(EditorTool.SNAPS[i]), "ChipButton", "Snap corners to %d voxel%s (%s cycles)" % [EditorTool.SNAPS[i], "" if EditorTool.SNAPS[i] == 1 else "s", InputSetup.describe("editor_grid")],
				func() -> void:
					tool.snap_index = i
					tool.changed.emit())
		chip.toggle_mode = true
		grid.add_child(chip)
		_grid_buttons.append(chip)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(gap)
	_free_cursor_button = _button("Free cursor", "ChipButton", "Aim at a point in the air instead of a surface (%s); Ctrl+wheel sets the distance" % InputSetup.describe("editor_free_cursor"),
			func() -> void:
				tool.free_cursor = not tool.free_cursor
				tool.changed.emit())
	_free_cursor_button.toggle_mode = true
	grid.add_child(_free_cursor_button)
	column.add_child(grid)

	var view := HBoxContainer.new()
	view.add_theme_constant_override("separation", 4)
	view.add_child(_label("View", "MutedLabel", 12))
	for i in 2:
		var chip := _button(["Builder", "Walk"][i], "ChipButton", ["Orbit from above with the mouse free", "First person: walk, or fly with %s" % InputSetup.describe("editor_fly")][i] + " (%s switches)" % InputSetup.describe("editor_view"),
				func() -> void: tool.set_view(i == 0))
		chip.toggle_mode = true
		view.add_child(chip)
		_view_buttons.append(chip)
	column.add_child(view)

	_cut_row = HBoxContainer.new()
	_cut_row.add_theme_constant_override("separation", 4)
	_cut_row.add_child(_label("Cut", "MutedLabel", 12))
	var cut_tips := ["Show everything", "Cut at the ceiling of the room you're looking at", "Set the height with %s / %s" % [InputSetup.describe("editor_cut_up"), InputSetup.describe("editor_cut_down")]]
	for i in EditorCamera.CUT_NAMES.size():
		var chip := _button(EditorCamera.CUT_NAMES[i], "ChipButton", "%s (%s cycles)" % [cut_tips[i], InputSetup.describe("editor_cut_mode")],
				func() -> void: tool.camera.set_cut_mode(i as EditorCamera.Cut))
		chip.toggle_mode = true
		_cut_row.add_child(chip)
		_cut_buttons.append(chip)
	_walls_button = _button("Walls", "ChipButton", "Walls down: hide walls between the camera and the room you're looking at (%s)" % InputSetup.describe("editor_walls_down"),
			func() -> void: tool.camera.set_walls_down(not tool.camera.walls_down))
	_walls_button.toggle_mode = true
	_cut_row.add_child(_walls_button)
	column.add_child(_cut_row)


func _build_drawer() -> void:
	_drawer = _surface("PaperCard")
	_drawer.anchor_top = 1.0
	_drawer.anchor_right = 1.0
	_drawer.anchor_bottom = 1.0
	_drawer.offset_left = MARGIN
	_drawer.offset_right = -INSPECTOR_WIDTH - MARGIN * 2
	_drawer.offset_top = -DRAWER_HEIGHT - MARGIN
	_drawer.offset_bottom = -MARGIN
	_root.add_child(_drawer)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_drawer.add_child(column)
	_drawer_header.add_theme_constant_override("separation", 6)
	column.add_child(_drawer_header)
	_drawer_tabs.add_theme_constant_override("separation", 4)
	_drawer_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drawer_header.add_child(_drawer_tabs)
	_search.placeholder_text = "Search"
	_search.custom_minimum_size.x = 150
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void: _fill_drawer())
	_search.set_meta("revert", func() -> void: pass)
	_drawer_header.add_child(_search)
	_drawer_header.add_child(_button("Hide", "ChipButton", "Hide the catalog (%s)" % InputSetup.describe("editor_catalog"),
			func() -> void:
				_drawer_open = false
				_layout()))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_drawer_tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drawer_tiles.add_theme_constant_override("h_separation", 6)
	_drawer_tiles.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_drawer_tiles)


func _build_hint() -> void:
	_hint = _surface("PaperPill")
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Between the tool rail and the inspector (_layout), wrapping when it's long.
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_label.theme_type_variation = "MutedLabel"
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_child(_hint_label)
	_root.add_child(_hint)


func _build_readout() -> void:
	_readout = _surface("PaperPill")
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout.anchor_left = 0.5
	_readout.anchor_right = 0.5
	_readout.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_readout.offset_top = BAR_HEIGHT + MARGIN
	_readout_label.bbcode_enabled = true
	_readout_label.fit_content = true
	_readout_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_readout_label.scroll_active = false
	_readout_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout_label.add_theme_color_override("default_color", PaperPalette.INK)
	_readout_label.add_theme_font_size_override("normal_font_size", 16)
	_readout_label.add_theme_font_size_override("bold_font_size", 16)
	_readout_label.add_theme_font_override("bold_font", preload("res://assets/ui/fonts/Lato-Black.ttf"))
	_readout.add_child(_readout_label)
	_readout.visible = false
	_root.add_child(_readout)


func _build_toast() -> void:
	_toast = _surface("PaperPill")
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = BAR_HEIGHT + MARGIN
	_toast_label.add_theme_font_size_override("font_size", 14)
	_toast.add_child(_toast_label)
	_toast.visible = false
	_root.add_child(_toast)


func _show_toast(text: String) -> void:
	_toast_label.text = text
	_toast_time = 4.0


## Where the drawer, inspector and hint sit, depending on whether the drawer is showing.
## The catalog has something for the tool: everything but Select and Opening, and Select with a room
## (its linings).
func _drawer_has_content() -> bool:
	if tool.tool == EditorTool.Tool.OPENING:
		return false
	return tool.tool != EditorTool.Tool.SELECT or _room_selected()


func _room_selected() -> bool:
	return tool.tool == EditorTool.Tool.SELECT and tool.selection().get("kind") == "room"


func _layout() -> void:
	var drawer_shown := _drawer_open and tool != null and _drawer_has_content()
	_drawer.visible = drawer_shown
	var bottom := DRAWER_HEIGHT + MARGIN * 2 if drawer_shown else MARGIN
	_inspector.offset_bottom = -MARGIN
	_hint.offset_bottom = -bottom
	_hint.offset_top = -bottom
	_hint.offset_left = _rail.position.x + _rail.size.x + MARGIN
	_hint.offset_right = -(INSPECTOR_WIDTH + MARGIN * 2)


# --- Modals --------------------------------------------------------------------------------------

## A sheet over a scrim, hidden. Returns the root; the sheet's column is its "body" meta.
func _modal(title: String) -> Control:
	var modal := Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.visible = false
	var scrim := ColorRect.new()
	scrim.color = PaperPalette.SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(center)
	var sheet := _surface("MenuPanel")
	center.add_child(sheet)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	sheet.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var heading := HBoxContainer.new()
	var title_label := _label(title, "HeaderTitle", 24)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title_label)
	heading.add_child(_button("Close", "ChipButton", "Close (Esc)", func() -> void: _set_modal(modal, false)))
	column.add_child(heading)
	modal.set_meta("body", column)
	_root.add_child(modal)
	return modal


func _set_modal(modal: Control, open: bool) -> void:
	if modal == null or modal.visible == open:
		return
	modal.visible = open
	if open:
		EditorInput.open_modal(modal)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if modal == _menu:
			_menu_info.text = LabHud.hosting_info(multiplayer)
			_menu_info.visible = _menu_info.text != ""
	else:
		EditorInput.close_modal(modal)


func _build_help() -> Control:
	var modal := _modal("Level editor keys")
	var body: VBoxContainer = modal.get_meta("body")
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	body.add_child(columns)
	var sections := [
		["Tools", [["Select", "editor_tool_select"], ["Room", "editor_tool_room"], ["Box", "editor_tool_box"],
			["Brush", "editor_tool_brush"], ["Replace", "editor_tool_replace"], ["Opening", "editor_tool_opening"], ["Prop", "editor_tool_prop"],
			["Marker", "editor_tool_marker"], ["Brush size", "editor_brush_smaller", "editor_brush_bigger"]]],
		["Editing", [["Rotate", "editor_rotate"], ["Grid snap", "editor_grid"], ["Free cursor", "editor_free_cursor"],
			["Move selection", "editor_move"], ["Duplicate", "editor_duplicate"], ["Delete", "editor_delete"],
			["Undo", "editor_undo"], ["Redo", "editor_redo"]]],
		["Session", [["Save", "editor_save"], ["Play-test", "editor_playtest"], ["Catalog", "editor_catalog"],
			["Help", "editor_help"], ["Back out / menu", "editor_back"],
			["Use the tool", "LMB / RMB"], ["Pick material or prop", "Alt+LMB"]]],
		["Builder view", [["Switch view", "editor_view"], ["Orbit", "RMB / MMB drag"], ["Pan", "WASD, Shift+MMB drag"],
			["Zoom", "Wheel"], ["Turn 45°", "editor_orbit_left", "editor_orbit_right"], ["Frame selection", "editor_frame"],
			["Whole level", "editor_frame_all"], ["Cut height", "editor_cut_up", "editor_cut_down"], ["Cut mode", "editor_cut_mode"],
			["Walls down", "editor_walls_down"],
			["Brush carve", "Shift+LMB"]]],
		["Walk view", [["Move", "WASD, Space / Ctrl"], ["Fly on / off", "editor_fly"], ["Fly speed", "Wheel, Shift fast"]]],
		["Room, Box, Replace", [["Corner, floor, height", "LMB ×3"], ["Size", "Wheel"], ["Other floor side", "Shift+Wheel"],
			["Type a size", "2.5 (m), 25v"], ["Next size", "Tab"], ["Keep typed size", "Enter"], ["Step back", "RMB / Backspace"]]],
	]
	for section: Array in sections:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 6)
		var column := VBoxContainer.new()
		column.add_child(_label(section[0], "Label", 18))
		column.add_child(grid)
		columns.add_child(column)
		for row: Array in section[1]:
			grid.add_child(_label(row[0], "BodyText", 14))
			var keys: Array[String] = []
			for key: String in row.slice(1):
				keys.append(InputSetup.describe(key) if InputSetup.EDITOR_KEYS.has(key) else key)
			grid.add_child(_label(" ".join(keys), "AccentLabel", 14))
	body.add_child(_label("Walk view: Esc frees the mouse to use the panels; click the world to take it back.", "MutedBody", 12))
	return modal


func _build_menu() -> Control:
	var modal := _modal("Menu")
	var body: VBoxContainer = modal.get_meta("body")
	body.custom_minimum_size.x = 320
	body.add_child(_button("Back to editing", "PrimaryButton", "", func() -> void:
		_set_modal(modal, false)
		tool.resume()))
	body.add_child(_button("Save", "Button", InputSetup.describe("editor_save"), lab.request_save))
	body.add_child(_button("Keys and controls", "Button", InputSetup.describe("editor_help"), func() -> void: _set_modal(_help, true)))
	_menu_info.theme_type_variation = "MutedBody"
	_menu_info.add_theme_font_size_override("font_size", 12)
	body.add_child(_menu_info)
	body.add_child(_button("End session" if multiplayer.is_server() else "Leave to menu", "DangerButton",
			"Unsaved changes are lost", func() -> void: Net.leave()))
	return modal


# --- Inspector -----------------------------------------------------------------------------------

## Rebuilds the inspector and the catalog for the current tool.
func _refresh() -> void:
	if tool == null:
		return
	var tool_changed := tool.tool != _shown_tool or (tool.tool == EditorTool.Tool.SELECT and tool.selected != _shown_selection)
	_shown_tool = tool.tool
	_shown_selection = tool.selected
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_inspector_title.text = EditorTool.TOOL_NAMES[tool.tool]
	match tool.tool:
		EditorTool.Tool.BOX, EditorTool.Tool.REPLACE:
			_material_row("Material", tool.material)
			_note("Pick one in the catalog, or Alt+click a voxel. " + ("Click the material to replace, then the floor, then the height." if tool.tool == EditorTool.Tool.REPLACE else "Click a corner, the floor, then the height (RMB first to carve). While sizing, the wheel or typing (2.5, 25v) sets a size."))
		EditorTool.Tool.BRUSH:
			_number_row("Size", tool.brush_size, 1, 20, 1, func(v: float) -> void: tool.brush_size = int(v))
			_check_row("Cube", tool.brush_cube, func(on: bool) -> void: tool.brush_cube = on)
			_material_row("Material", tool.material)
		EditorTool.Tool.ROOM:
			_heading("Lining")
			for target: String in ROOM_TARGETS:
				var row := _material_row(ROOM_TARGETS[target], tool.get("room_" + target))
				row.modulate.a = 1.0 if target == _room_target else 0.7
			_number_row("Thickness", tool.room_thickness, 1, 10, 1, func(v: float) -> void: tool.room_thickness = int(v))
			_note("Click a corner, the far corner of the floor, then the height; the box is the inside of the room. Start on cut rock (the cutaway's cross section) to dig down to the floor you're looking at. In rock levels the lining only recolors rock, so it joins rooms it touches.")
		EditorTool.Tool.PROP:
			_heading(tool.prop_name.replace("_", " ").capitalize())
			var mounts := {floor = "Stands on what you aim at (on a wall: on the floor, back to the wall).",
					wall = "Hangs on a wall, facing out.", ceiling = "Hangs from a ceiling.",
					door = "Goes into a wall and cuts its own doorway; it slides along the wall to open.",
					any = "Sits on a floor, wall or ceiling."}
			_note("%s %s or RMB turns it. A red ghost has no spot: it would float or overlap. Alt+click a placed prop to pick its type." % [
					mounts.get(PropCatalog.mount_of(tool.prop_name), ""), InputSetup.describe("editor_rotate")])
		EditorTool.Tool.MARKER:
			_heading(LevelSchema.MARKERS[tool.marker_type].label)
			_note("Facing follows your view. Select a placed marker to change its properties.")
		EditorTool.Tool.OPENING:
			var types := HBoxContainer.new()
			types.add_theme_constant_override("separation", 4)
			var group := ButtonGroup.new()
			for type: String in LevelSchema.OPENING_TYPES:
				if type == "slot":
					continue # A sliding door's pocket; doors make those.
				var chip := _button(type.capitalize(), "ChipButton", "", func() -> void:
					tool.opening_type = type
					var sizes := {doorway = [12, 22], window = [12, 10], hole = [10, 10]}
					tool.opening_width = sizes[type][0]
					tool.opening_height = sizes[type][1]
					_refresh())
				chip.toggle_mode = true
				chip.button_group = group
				chip.button_pressed = type == tool.opening_type
				types.add_child(chip)
			_content.add_child(types)
			var meters: float = lab.world.voxel_size
			_number_row("Width (m)", tool.opening_width * meters, 0.1, 20.0, 0.1, func(v: float) -> void: tool.opening_width = maxi(roundi(v / meters), 1))
			_number_row("Height (m)", tool.opening_height * meters, 0.1, 20.0, 0.1, func(v: float) -> void: tool.opening_height = maxi(roundi(v / meters), 1))
			if tool.opening_type == "window":
				_number_row("Sill (m)", tool.opening_sill * meters, 0.0, 10.0, 0.1, func(v: float) -> void: tool.opening_sill = roundi(v / meters))
			_note("Click a wall to cut it through. Doorways start at the room's floor, windows at the sill, holes at the cursor. Door props cut their own opening; this never adds a door.")
		EditorTool.Tool.SELECT:
			_selection()
	if tool_changed:
		_category = "All"
		_search.text = ""
		_fill_drawer()
	else:
		_sync_drawer()
	_layout()


func _heading(text: String) -> void:
	_content.add_child(_label(text, "Label", 16))


func _note(text: String) -> void:
	var label := _label(text, "MutedBody", 12)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(INSPECTOR_WIDTH - 40, 0)
	_content.add_child(label)


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := _label(text, "Label", 13)
	label.custom_minimum_size = Vector2(96, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	_content.add_child(row)
	return row


func _material_row(text: String, id: int) -> HBoxContainer:
	var value := HBoxContainer.new()
	var swatch := TextureRect.new()
	swatch.texture = _material_icon(id)
	swatch.custom_minimum_size = Vector2(22, 22)
	swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	swatch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	value.add_child(swatch)
	value.add_child(_label(VoxelMaterials.get_material_name(id), "BodyText", 13))
	return _row(text, value)


func _number_row(text: String, value: float, low: float, high: float, step: float, on_commit: Callable) -> PaperNumber:
	var field := PaperNumber.make(value, low, high, step)
	field.committed.connect(on_commit)
	_row(text, field)
	return field


func _check_row(text: String, value: bool, on_change: Callable) -> void:
	var check := CheckBox.new()
	check.button_pressed = value
	check.toggled.connect(on_change)
	_row(text, check)


func _selection() -> void:
	var object: Dictionary = lab.level.objects.get(tool.selected, {})
	if object.is_empty():
		_inspector_title.text = "Select"
		_note("Click a room, opening, prop or marker in the world to select it.")
		_content.add_child(_button("Check level", "Button", "List props that float or sit inside a wall", func() -> void:
			_problems = PropPlacement.problems(lab.world, lab.level.objects)
			_problems_checked = true
			_refresh()))
		if _problems_checked:
			if _problems.is_empty():
				_note("No floating or buried props.")
			for problem: Dictionary in _problems:
				var id: String = problem.id
				var entry := _button("%s: %s" % [id, problem.reason], "ChipButton", "Select it", func() -> void:
					if lab.level.objects.has(id):
						tool.select(id)
						if tool.builder:
							tool.frame_selection())
				entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
				entry.clip_text = true
				_content.add_child(entry)
		# Every room, to pick one that's hard to click (under rock, far away).
		var rooms: Array = lab.level.objects.values().filter(func(o: Dictionary) -> bool: return o.kind == "room")
		if not rooms.is_empty():
			_heading("Rooms")
			rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
			for room: Dictionary in rooms:
				var id: String = room.id
				var size: Vector3 = Vector3(room.to - room.from) * lab.world.voxel_size
				var entry := _button("%s  %.1f × %.1f × %.1f m" % [room.name if room.name != "" else id, size.x, size.z, size.y], "ChipButton", "Select it", func() -> void:
					if lab.level.objects.has(id):
						tool.select(id)
						if tool.builder:
							tool.frame_selection())
				entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
				entry.clip_text = true
				_content.add_child(entry)
		return
	match object.kind:
		"prop":
			_inspector_title.text = object.name.replace("_", " ").capitalize()
		"room":
			_inspector_title.text = object.name if object.name != "" else "Room"
		"opening":
			_inspector_title.text = str(object.type).capitalize()
		_:
			_inspector_title.text = LevelSchema.MARKERS[object.type].label
	if object.kind == "room":
		var size: Vector3 = Vector3(object.to - object.from) * lab.world.voxel_size
		_note("%.1f × %.1f × %.1f m. Drag the handles on its walls, ceiling and corners to resize it (or click one to pick it up; the wheel nudges it)." % [size.x, size.z, size.y])
		for target: String in ROOM_TARGETS:
			var row := _material_row(ROOM_TARGETS[target], object[target])
			row.modulate.a = 1.0 if target == _room_target else 0.7
	elif object.kind == "opening" and object.door != "":
		_note("Cut by the door %s: move or delete the door to change it." % object.door)
	for field: Dictionary in LevelSchema.fields_for(object):
		_field(object, field)
	if object.kind == "room":
		_check_row("Move contents with it", tool.move_contents, func(on: bool) -> void: tool.move_contents = on)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	for action in [["Move", "Button", "editor_move", tool._start_move], ["Duplicate", "Button", "editor_duplicate", tool._duplicate],
			["Delete", "DangerButton", "editor_delete", tool.delete_selected]]:
		var button := _button(action[0], action[1], InputSetup.describe(action[2]), func() -> void:
			action[3].call()
			tool.resume())
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(button)
	_content.add_child(buttons)


## One property row; changing it sends the edited object to LevelEdits.
func _field(object: Dictionary, field: Dictionary) -> void:
	var key: String = field.key
	var label: String = field.get("label", key.capitalize())
	var value = object.get(key)
	var commit := func(new_value) -> void:
		var current: Dictionary = lab.level.objects.get(tool.selected, {})
		if current.is_empty() or current.get(key) == new_value:
			return
		var changed := current.duplicate()
		changed[key] = new_value
		lab.edits.put_object(changed, current.id)
		if key == "id":
			tool.select(new_value) # Follows the rename (fixed up by the host if it was taken).
	match field.type:
		"string":
			var edit := LineEdit.new()
			edit.text = str(value)
			edit.set_meta("revert", func() -> void: edit.text = str(value))
			edit.text_submitted.connect(func(_text: String) -> void: edit.release_focus())
			edit.focus_exited.connect(func() -> void: commit.call(edit.text.strip_edges()))
			_row(label, edit)
		"text":
			var area := TextEdit.new()
			area.text = str(value)
			area.custom_minimum_size = Vector2(0, 90)
			area.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			area.focus_exited.connect(func() -> void: commit.call(area.text))
			_row(label, area)
		"int", "float":
			var is_int: bool = field.type == "int"
			_number_row(label, value, field.get("min", -1000000), field.get("max", 1000000), 1.0 if is_int else 0.1,
					func(v: float) -> void: commit.call(int(v) if is_int else v))
		"bool":
			_check_row(label, value, func(on: bool) -> void: commit.call(on))
		"color":
			var picker := ColorPickerButton.new()
			picker.color = value
			picker.custom_minimum_size.y = 30
			picker.popup_closed.connect(func() -> void: commit.call(picker.color))
			_row(label, picker)
		"enum":
			var option := OptionButton.new()
			var options: Array = field.options
			for o in options:
				option.add_item(str(o))
			# Facing is stored as a number, other enums as their text.
			option.select(value if key == "facing" else options.find(value))
			option.item_selected.connect(func(i: int) -> void: commit.call(i if key == "facing" else options[i]))
			_row(label, option)
		"vector3i":
			var row := HBoxContainer.new()
			var fields: Array[PaperNumber] = []
			for axis in 3:
				var number := PaperNumber.make(value[axis], field.get("min", -1024), field.get("max", 1024))
				number.custom_minimum_size.x = 40
				number.add_theme_constant_override("minimum_character_width", 1)
				number.add_theme_font_size_override("font_size", 14)
				number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				fields.append(number)
				row.add_child(number)
			for number in fields:
				number.committed.connect(func(_v: float) -> void:
					commit.call(Vector3i(int(fields[0].value), int(fields[1].value), int(fields[2].value))))
			# Label above, so three numbers get the card's width.
			var block := VBoxContainer.new()
			block.add_theme_constant_override("separation", 2)
			block.add_child(_label(label + "  (x, y, z)", "Label", 13))
			block.add_child(row)
			_content.add_child(block)


func _on_object_set(remove_id: String, object: Dictionary) -> void:
	if tool == null or tool.tool != EditorTool.Tool.SELECT:
		return
	var id: String = object.get("id", "")
	if remove_id == tool.selected and id != "" and id != remove_id:
		tool.select(id) # Renamed.
	elif (remove_id == tool.selected or id == tool.selected) and not _inspector_has_focus():
		_refresh()


func _inspector_has_focus() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused != null and _inspector.is_ancestor_of(focused)


# --- Catalog -------------------------------------------------------------------------------------

## Rebuilds the catalog's tabs and tiles for the current tool.
func _fill_drawer() -> void:
	for parent: Control in [_drawer_tabs, _drawer_tiles]:
		for child in parent.get_children():
			parent.remove_child(child)
			child.queue_free()
	_prop_tiles.clear()
	if tool == null:
		return
	var filter := _search.text.strip_edges().to_lower()
	var group := ButtonGroup.new()
	match tool.tool:
		EditorTool.Tool.BOX, EditorTool.Tool.BRUSH, EditorTool.Tool.REPLACE, EditorTool.Tool.ROOM, EditorTool.Tool.SELECT:
			if tool.tool == EditorTool.Tool.SELECT and not _room_selected():
				return
			if tool.tool == EditorTool.Tool.ROOM or _room_selected():
				_drawer_tabs.add_child(_label("Lines the", "MutedLabel", 12))
				var tabs := ButtonGroup.new()
				for target: String in ROOM_TARGETS:
					var tab := _button(ROOM_TARGETS[target], "ChipButton", "The catalog sets the room's %s" % ROOM_TARGETS[target].to_lower(), func() -> void:
						_room_target = target
						_refresh())
					tab.toggle_mode = true
					tab.button_group = tabs
					tab.button_pressed = target == _room_target
					_drawer_tabs.add_child(tab)
			else:
				_drawer_tabs.add_child(_label("Materials", "Label", 15))
			for id: int in _material_ids():
				var material_name := VoxelMaterials.get_material_name(id)
				if filter != "" and not material_name.to_lower().contains(filter):
					continue
				var tile := _tile(material_name, _material_icon(id), group, "Palette index %d" % id)
				tile.set_meta("value", id)
				tile.pressed.connect(func() -> void: _pick_material(id))
		EditorTool.Tool.PROP:
			var names := _prop_names()
			var categories: Array[String] = ["All"]
			for prop_name in names:
				var category := PropCatalog.category_of(prop_name)
				if not category in categories:
					categories.append(category)
			var tabs := ButtonGroup.new()
			for category in categories:
				var tab := _button(category, "ChipButton", "", func() -> void:
					_category = category
					_fill_drawer())
				tab.toggle_mode = true
				tab.button_group = tabs
				tab.button_pressed = category == _category
				_drawer_tabs.add_child(tab)
			for prop_name in names:
				if _category != "All" and PropCatalog.category_of(prop_name) != _category:
					continue
				if filter != "" and not prop_name.contains(filter.replace(" ", "_")):
					continue
				var tile := _tile(prop_name.replace("_", " "), thumbnails.get_texture(prop_name), group, prop_name)
				tile.set_meta("value", prop_name)
				tile.pressed.connect(func() -> void:
					tool.prop_name = prop_name
					_refresh())
				_prop_tiles[prop_name] = tile
		EditorTool.Tool.MARKER:
			_drawer_tabs.add_child(_label("Markers", "Label", 15))
			for type: String in LevelSchema.MARKERS:
				var label: String = LevelSchema.MARKERS[type].label
				if filter != "" and not label.to_lower().contains(filter):
					continue
				var tile := _tile(label, _swatch(LevelSchema.MARKERS[type].color), group, label)
				tile.set_meta("value", type)
				tile.pressed.connect(func() -> void:
					tool.marker_type = type
					_refresh())
	_sync_drawer()


func _tile(text: String, icon: Texture2D, group: ButtonGroup, tip: String) -> Button:
	var tile := Button.new()
	tile.theme_type_variation = "ToggleButton"
	tile.toggle_mode = true
	tile.button_group = group
	tile.text = text
	tile.icon = icon
	tile.tooltip_text = tip
	tile.expand_icon = true
	tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	tile.clip_text = true
	tile.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tile.add_theme_font_size_override("font_size", 11)
	tile.add_theme_constant_override("icon_max_width", ICON_SIZE)
	# The theme tints button icons ink (they're meant to be glyphs); these are pictures.
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		tile.add_theme_color_override("icon_%s_color" % state, Color.WHITE)
	tile.custom_minimum_size = TILE_SIZE
	_drawer_tiles.add_child(tile)
	return tile


## Marks the tile matching the tool's current choice.
func _sync_drawer() -> void:
	var current: Variant = null
	match tool.tool:
		EditorTool.Tool.BOX, EditorTool.Tool.BRUSH, EditorTool.Tool.REPLACE:
			current = tool.material
		EditorTool.Tool.ROOM:
			current = tool.get("room_" + _room_target)
		EditorTool.Tool.SELECT:
			current = tool.selection().get(_room_target)
		EditorTool.Tool.PROP:
			current = tool.prop_name
		EditorTool.Tool.MARKER:
			current = tool.marker_type
	for tile in _drawer_tiles.get_children():
		if tile is Button and tile.has_meta("value"):
			tile.set_pressed_no_signal(tile.get_meta("value") == current)


func _pick_material(id: int) -> void:
	if _room_selected():
		var room := tool.selection().duplicate()
		if room.get(_room_target) != id:
			room[_room_target] = id
			lab.edits.put_object(room, room.id)
	elif tool.tool == EditorTool.Tool.ROOM:
		tool.set("room_" + _room_target, id)
	else:
		tool.material = id
	_refresh()


func _material_ids() -> Array:
	var ids := VoxelMaterials.DEFS.keys()
	ids.sort()
	return ids


## A material's swatch, or its pattern for pattern materials.
func _material_icon(id: int) -> Texture2D:
	var key := "material_%d" % id
	if not _icons.has(key):
		var pattern: String = VoxelMaterials.DEFS.get(id, {}).get("pattern", "")
		var image: Image = VoxelMaterials.load_pattern(pattern) if pattern != "" else null
		if image == null:
			return _swatch(VoxelMaterials.get_color(id))
		image = image.duplicate()
		image.resize(ICON_SIZE, ICON_SIZE, Image.INTERPOLATE_NEAREST)
		_icons[key] = ImageTexture.create_from_image(image)
	return _icons[key]


func _swatch(color: Color) -> Texture2D:
	var key := color.to_html()
	if not _icons.has(key):
		var image := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
		image.fill(color)
		_icons[key] = ImageTexture.create_from_image(image)
	return _icons[key]


func _prop_names() -> PackedStringArray:
	var names := PackedStringArray()
	for file in DirAccess.get_files_at(Props.library_dir):
		if file.get_extension() == "vox":
			names.append(file.get_basename())
	names.sort()
	return names


func _on_thumbnail(prop_name: String, texture: Texture2D) -> void:
	if _prop_tiles.has(prop_name) and is_instance_valid(_prop_tiles[prop_name]):
		_prop_tiles[prop_name].icon = texture
