class_name ControlsOverlay
extends Control
## F1 controls cheat sheet, listing the bindings from InputSetup so it never goes stale; with a pad
## plugged in or in use it lists the pad's buttons too (and Back toggles it), rebuilt when the
## device changes. Esc closes it too, and B or Start on a pad.

var _title := Label.new()
var _grid := GridContainer.new()


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
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 24)
	column.add_child(_grid)
	_rebuild()
	Pad.device_changed.connect(_rebuild)


## The title and rows for the device in use (InputSetup.describe_play_controls).
func _rebuild() -> void:
	_title.text = "Controls (F1 / Back)" if InputSetup.shows_pad() else "Controls (F1)"
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for row in InputSetup.describe_play_controls():
		var label := Label.new()
		label.text = row.label
		_grid.add_child(label)
		var keys := Label.new()
		keys.text = row.keys
		keys.modulate = Color(0.75, 1.0, 0.8)
		_grid.add_child(keys)


## Shows the sheet for a few seconds (the story does this when the player first gets the gun).
func show_for(seconds: float) -> void:
	visible = true
	await get_tree().create_timer(seconds).timeout
	visible = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("show_controls"):
		visible = not visible
		get_viewport().set_input_as_handled()
	elif visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pad_back")):
		visible = false
