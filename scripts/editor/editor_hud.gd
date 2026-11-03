class_name EditorHud
extends CanvasLayer
## The level editor's screen: a tool bar and status line at the top, and a side panel whose content
## follows the tool (materials, room linings, brush, prop list, marker types, or the selected
## object's properties), with undo / redo / save / play-test buttons. Visible in edit mode. Press
## Tab to free the mouse and use it.

const PANEL_WIDTH := 320

@export var lab: Lab

var tool: EditorTool
var thumbnails := PropThumbnails.new()

var _bar := HBoxContainer.new()
var _tool_buttons: Array[Button] = []
var _status := Label.new()
var _panel := PanelContainer.new()
var _content := VBoxContainer.new()
var _prop_list: ItemList
var _shown_tool := -1
var _shown_selection := ""
var _swatches := {}


func _ready() -> void:
	thumbnails.view = lab.view
	add_child(thumbnails)
	thumbnails.rendered.connect(_on_thumbnail)

	var top := VBoxContainer.new()
	top.position = Vector2(12, 8)
	add_child(top)
	for i in EditorTool.TOOL_NAMES.size():
		var button := Button.new()
		button.text = "%d %s" % [i + 1, EditorTool.TOOL_NAMES[i]]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: tool.set_tool(i as EditorTool.Tool))
		_bar.add_child(button)
		_tool_buttons.append(button)
	top.add_child(_bar)
	_status.label_settings = LabHud._settings(15)
	top.add_child(_status)

	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -PANEL_WIDTH - 8
	_panel.offset_right = -8
	_panel.offset_top = 8
	_panel.offset_bottom = -8
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.085, 0.1, 0.96)
	style.set_content_margin_all(8)
	style.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var column := VBoxContainer.new()
	_panel.add_child(column)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	column.add_child(HSeparator.new())
	var footer := GridContainer.new()
	footer.columns = 2
	column.add_child(footer)
	_footer_button(footer, "Undo (Ctrl+Z)", func() -> void: lab.edits.undo())
	_footer_button(footer, "Redo (Ctrl+Y)", func() -> void: lab.edits.redo())
	_footer_button(footer, "Save (Ctrl+S)", lab.request_save)
	_footer_button(footer, "Play-test (F5)", func() -> void: lab.request_mode("play"))

	lab.edits.object_set.connect(_on_object_set)
	visible = false


func _process(_delta: float) -> void:
	if tool == null:
		var me := lab.local_player()
		if me == null:
			return
		tool = me.get_node("EditorTool")
		tool.changed.connect(_refresh)
		_refresh()
	visible = lab.mode == "edit"
	if not visible:
		return
	for i in _tool_buttons.size():
		_tool_buttons[i].button_pressed = i == tool.tool
	var parts: Array[String] = [
		"Grid %d (G)" % tool.snap(),
		("Free cursor %.1fm (V, Ctrl+wheel)" % tool.free_distance) if tool.free_cursor else "Surface cursor (V)",
		"Fly %.0f (wheel)" % tool.player.fly_speed,
	]
	if tool.tool in [EditorTool.Tool.BOX, EditorTool.Tool.BRUSH, EditorTool.Tool.REPLACE]:
		parts.append("Material: %s" % VoxelMaterials.get_material_name(tool.material))
	if tool.has_cursor:
		parts.append("Cursor %s" % tool.cell)
	_status.text = "  ·  ".join(parts) + "\n" + EditorTool.TOOL_HINTS[tool.tool] + ("" if tool.panel_open else "  ·  Tab: use the panel")
	if tool.tool != _shown_tool or (tool.tool == EditorTool.Tool.SELECT and tool.selected != _shown_selection):
		_refresh()


func _footer_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)


## Rebuilds the side panel for the current tool.
func _refresh() -> void:
	if tool == null:
		return
	_shown_tool = tool.tool
	_shown_selection = tool.selected
	for child in _content.get_children():
		child.queue_free()
	_prop_list = null
	match tool.tool:
		EditorTool.Tool.BOX, EditorTool.Tool.REPLACE:
			_heading("Material (Alt+click a voxel to pick)")
			_material_grid(tool.material, func(id: int) -> void: tool.material = id)
		EditorTool.Tool.BRUSH:
			_heading("Brush")
			_spin_row("Size", tool.brush_size, 1, 20, 1, func(v: float) -> void: tool.brush_size = int(v))
			_check_row("Cube (B)", tool.brush_cube, func(on: bool) -> void: tool.brush_cube = on)
			_heading("Material")
			_material_grid(tool.material, func(id: int) -> void: tool.material = id)
		EditorTool.Tool.ROOM:
			_heading("Room lining")
			_material_option("Floor", tool.room_floor, func(id: int) -> void: tool.room_floor = id)
			_material_option("Walls", tool.room_wall, func(id: int) -> void: tool.room_wall = id)
			_material_option("Ceiling", tool.room_ceiling, func(id: int) -> void: tool.room_ceiling = id)
			_spin_row("Thickness", tool.room_thickness, 1, 10, 1, func(v: float) -> void: tool.room_thickness = int(v))
			_note("Corners mark the inside of the room. In rock levels the lining only recolors rock, so it joins rooms it touches.")
		EditorTool.Tool.PROP:
			_heading("Props (R rotate, facing %s)" % LevelSchema.FACINGS[tool.facing])
			_prop_list = ItemList.new()
			_prop_list.custom_minimum_size = Vector2(0, 560)
			_prop_list.icon_mode = ItemList.ICON_MODE_TOP
			_prop_list.max_columns = 3
			_prop_list.fixed_column_width = 92
			_prop_list.fixed_icon_size = Vector2i(72, 72)
			_prop_list.same_column_width = true
			for prop_name in _prop_names():
				var index := _prop_list.add_item(prop_name.replace("_", " "), thumbnails.get_texture(prop_name))
				_prop_list.set_item_metadata(index, prop_name)
				if prop_name == tool.prop_name:
					_prop_list.select(index)
			_prop_list.item_selected.connect(func(index: int) -> void: tool.prop_name = _prop_list.get_item_metadata(index))
			_content.add_child(_prop_list)
		EditorTool.Tool.MARKER:
			_heading("Marker type")
			for type: String in LevelSchema.MARKERS:
				var button := Button.new()
				button.text = LevelSchema.MARKERS[type].label
				button.toggle_mode = true
				button.button_pressed = type == tool.marker_type
				button.icon = _swatch(LevelSchema.MARKERS[type].color)
				button.alignment = HORIZONTAL_ALIGNMENT_LEFT
				button.pressed.connect(func() -> void:
					tool.marker_type = type
					_refresh())
				_content.add_child(button)
		EditorTool.Tool.SELECT:
			_inspector()


# --- Panel pieces --------------------------------------------------------------------------------

func _heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.modulate = Color(1.0, 0.85, 0.5)
	_content.add_child(label)


func _note(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(PANEL_WIDTH - 30, 0)
	label.modulate = Color(1, 1, 1, 0.6)
	_content.add_child(label)


func _row(text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(110, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	_content.add_child(row)


func _spin_row(text: String, value: float, low: float, high: float, step: float, on_change: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = value
	spin.value_changed.connect(on_change)
	_row(text, spin)
	return spin


func _check_row(text: String, value: bool, on_change: Callable) -> void:
	var check := CheckBox.new()
	check.button_pressed = value
	check.toggled.connect(on_change)
	_row(text, check)


func _material_ids() -> Array:
	var ids := VoxelMaterials.DEFS.keys()
	ids.sort()
	return ids


func _material_grid(current: int, on_pick: Callable) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	var group := ButtonGroup.new()
	for id: int in _material_ids():
		var button := Button.new()
		button.text = "%s" % VoxelMaterials.get_material_name(id)
		button.tooltip_text = "Palette index %d" % id
		button.icon = _swatch(VoxelMaterials.get_color(id))
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = id == current
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.custom_minimum_size = Vector2(PANEL_WIDTH / 2 - 14, 0)
		button.pressed.connect(func() -> void: on_pick.call(id))
		grid.add_child(button)
	_content.add_child(grid)


func _material_option(text: String, current: int, on_pick: Callable) -> void:
	var option := OptionButton.new()
	for id: int in _material_ids():
		option.add_icon_item(_swatch(VoxelMaterials.get_color(id)), VoxelMaterials.get_material_name(id), id)
		if id == current:
			option.select(option.item_count - 1)
	option.item_selected.connect(func(index: int) -> void: on_pick.call(option.get_item_id(index)))
	_row(text, option)


func _swatch(color: Color) -> Texture2D:
	var key := color.to_html()
	if not _swatches.has(key):
		var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		image.fill(color)
		_swatches[key] = ImageTexture.create_from_image(image)
	return _swatches[key]


func _prop_names() -> PackedStringArray:
	var names := PackedStringArray()
	for file in DirAccess.get_files_at(Props.library_dir):
		if file.get_extension() == "vox":
			names.append(file.get_basename())
	names.sort()
	return names


func _on_thumbnail(prop_name: String, texture: Texture2D) -> void:
	if _prop_list == null:
		return
	for i in _prop_list.item_count:
		if _prop_list.get_item_metadata(i) == prop_name:
			_prop_list.set_item_icon(i, texture)


# --- Inspector -----------------------------------------------------------------------------------

func _inspector() -> void:
	var object: Dictionary = lab.level.objects.get(tool.selected, {})
	if object.is_empty():
		_heading("Nothing selected")
		_note("Click a prop or marker to select it.")
		return
	var title: String = object.name.replace("_", " ") if object.kind == "prop" else LevelSchema.MARKERS[object.type].label
	_heading(title)
	for field: Dictionary in LevelSchema.fields_for(object):
		_field(object, field)
	var buttons := HBoxContainer.new()
	for action in [["Move (M)", tool._start_move], ["Duplicate", tool._duplicate], ["Delete", tool.delete_selected]]:
		var button := Button.new()
		button.text = action[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void:
			action[1].call()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
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
			edit.text_submitted.connect(func(text: String) -> void: commit.call(text.strip_edges()))
			edit.focus_exited.connect(func() -> void: commit.call(edit.text.strip_edges()))
			_row(label, edit)
		"int", "float":
			var spin := SpinBox.new()
			spin.min_value = field.get("min", -1000000)
			spin.max_value = field.get("max", 1000000)
			spin.step = 1.0 if field.type == "int" else 0.1
			spin.value = value
			spin.value_changed.connect(func(v: float) -> void: commit.call(int(v) if field.type == "int" else v))
			_row(label, spin)
		"bool":
			var check := CheckBox.new()
			check.button_pressed = value
			check.toggled.connect(func(on: bool) -> void: commit.call(on))
			_row(label, check)
		"color":
			var picker := ColorPickerButton.new()
			picker.color = value
			picker.popup_closed.connect(func() -> void: commit.call(picker.color))
			_row(label, picker)
		"enum":
			var option := OptionButton.new()
			var options: Array = field.options
			for o in options:
				option.add_item(str(o))
			# Facing is stored as a number, other enums as their text.
			var index: int = value if key == "facing" else options.find(value)
			option.select(index)
			option.item_selected.connect(func(i: int) -> void: commit.call(i if key == "facing" else options[i]))
			_row(label, option)
		"vector3i":
			var row := HBoxContainer.new()
			var spins: Array[SpinBox] = []
			for axis in 3:
				var spin := SpinBox.new()
				spin.min_value = -500
				spin.max_value = 500
				spin.value = value[axis]
				spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				spins.append(spin)
				row.add_child(spin)
			for spin in spins:
				spin.value_changed.connect(func(_v: float) -> void:
					commit.call(Vector3i(int(spins[0].value), int(spins[1].value), int(spins[2].value))))
			_row(label, row)


func _on_object_set(remove_id: String, object: Dictionary) -> void:
	if tool == null or tool.tool != EditorTool.Tool.SELECT:
		return
	var id: String = object.get("id", "")
	if remove_id == tool.selected and id != "" and id != remove_id:
		tool.select(id) # Renamed.
	elif (remove_id == tool.selected or id == tool.selected) and not _panel_has_focus():
		_refresh()


func _panel_has_focus() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused != null and _panel.is_ancestor_of(focused)
