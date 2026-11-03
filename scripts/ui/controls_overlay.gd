class_name ControlsOverlay
extends Control
## F1 controls cheat sheet, listing the bindings from InputSetup so it never goes stale.
## Esc closes it too.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var title := Label.new()
	title.text = "Controls (F1 to close)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	column.add_child(grid)
	for row in InputSetup.describe_play_controls():
		var label := Label.new()
		label.text = row.label
		grid.add_child(label)
		var keys := Label.new()
		keys.text = row.keys
		keys.modulate = Color(0.75, 1.0, 0.8)
		grid.add_child(keys)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("show_controls"):
		visible = not visible
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		visible = false
