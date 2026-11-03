class_name EditorTool
extends Node
## The level editor for the local player: aims a cursor, runs the tools and draws their previews.
## Two views (V switches): the builder view (EditorCamera, the default) orbits from above with the
## mouse free and aims through the mouse; the walk view is first person, aims from the crosshair
## while the mouse is captured, and walks or flies (F). Shortcuts work in both unless the editor UI
## has the keys (EditorInput). Esc backs out one step at a time: the tool step, then the selection,
## then (walk view) frees the mouse for the panels (EditorHud), then opens the menu. Every change
## goes through LevelEdits, so it's shared and undoable.
##
## Keys are the editor_* actions in InputSetup.EDITOR_KEYS. Mouse: LMB / RMB use the tool (in the
## builder view a right drag orbits instead, so Brush carves with Shift+LMB there), Alt+LMB picks a
## material or prop type. Walk view: wheel fly speed, Ctrl+wheel free-cursor distance.

## Tool, material or selection changed (the HUD redraws its panel).
signal changed

## Esc asked for the menu (nothing left to back out of).
signal menu_requested

enum Tool { SELECT, ROOM, BOX, BRUSH, REPLACE, OPENING, PROP, MARKER }

const TOOL_NAMES := ["Select", "Room", "Box", "Brush", "Replace", "Opening", "Prop", "Marker"]
const TOOL_ACTIONS := ["editor_tool_select", "editor_tool_room", "editor_tool_box", "editor_tool_brush",
		"editor_tool_replace", "editor_tool_opening", "editor_tool_prop", "editor_tool_marker"]
## Short how-tos for tooltips.
const TOOL_ABOUT := [
	"Pick a room, opening, prop or marker to move, resize or change it",
	"Carve a room and line its floor, walls and ceiling; it stays resizable",
	"Fill a box with a material, or carve one out",
	"Paint or carve freehand",
	"Swap one material for another inside a box",
	"Cut a doorway, window or hole through a wall (doors cut their own)",
	"Place props from the catalog",
	"Place spawns, lights, triggers and other markers",
]
const TOOL_HINTS := [
	"LMB select · drag a room's handles to resize · M move · Ctrl+D duplicate · R rotate · Delete",
	"LMB corner, LMB floor, LMB height (the inside of the room) · wheel / type sizes · Alt+LMB: room from a carved space",
	"LMB corner, floor, height: fill · RMB first: carve · wheel / type sizes · Tab next size",
	"LMB hold: paint · RMB hold: carve · [ ] size",
	"LMB on the material to replace, then floor and height · wheel / type sizes · RMB back",
	"LMB on a wall: cut the opening through it",
	"LMB place · R / RMB rotate · Alt+LMB pick a placed prop's type",
	"LMB place the marker · facing follows your view",
]
const SNAPS := [1, 5, 10]
## How far the cursor reaches, in meters.
const REACH := 80.0
const DAB_INTERVAL := 0.06

var lab: Lab
var player: Player
## The builder view (true) or the walk view.
var builder := true
var camera := EditorCamera.new()

var tool := Tool.BOX
var material := VoxelMaterials.CONCRETE
var snap_index := 1
var free_cursor := false
var free_distance := 4.0
var brush_size := 3
var brush_cube := false
var prop_name := "chair"
var facing := 0
var marker_type := "light"
var selected := ""
## Room tool linings (from the level's defaults).
var room_floor := VoxelMaterials.CONCRETE
var room_wall := VoxelMaterials.WALL_PAINT
var room_ceiling := VoxelMaterials.CONCRETE
var room_thickness := 3

## Cursor this frame: the empty cell in front of the aimed surface, the solid cell aimed at, the
## surface's normal (on_cap: it's the cutaway's cross section) and the placed object under it.
var has_cursor := false
var cell := Vector3i.ZERO
var solid_cell := Vector3i.ZERO
var cursor_normal := Vector3i.UP
var cursor_on_cap := false
var object_under := ""

## Room / Box / Replace sizing (three clicks), whether the box carves, and what Replace swaps.
var volume := VolumeSteps.new()
var _volume_carve := false
var _replace_source := 0
## Opening tool: what it cuts and its size in voxels (sill: a window's height off the floor).
var opening_type := "doorway"
var opening_width := 12
var opening_height := 22
var opening_sill := 10
## Moving or duplicating a room takes the props and markers inside along.
var move_contents := true
## Resize handles on a selected room.
var handles := RoomHandles.new()
## Last height built per tool, in voxels: the next one starts there.
var _last_height := {Tool.ROOM: 30, Tool.BOX: 10, Tool.REPLACE: 10}
## This frame's aim ray (mouse or crosshair).
var _aim_from := Vector3.ZERO
var _aim_direction := Vector3.FORWARD
## Object being moved / duplicated (a copy with the pending changes), its original id ("" = new),
## and for a duplicate, the id it was copied from.
var _grab := {}
var _grab_id := ""
var _grab_source := ""
## 0 none, 1 painting, 2 carving
var _stroke := 0
var _dab_timer := 0.0

var _cursor_lines := MeshInstance3D.new()
var _volume := MeshInstance3D.new()
var _ghost := MeshInstance3D.new()
## Width, height and length labels on the sized box's edges (Vector3 axis order).
var _size_labels: Array[Label3D] = []

const LABEL_COLOR := Color(0.92, 0.95, 1.0)
const LABEL_ACTIVE_COLOR := Color(1.0, 0.85, 0.3)


func _ready() -> void:
	player = get_parent() as Player
	_cursor_lines.mesh = ImmediateMesh.new()
	_cursor_lines.material_override = LevelView._line_material(Color(1, 1, 1, 0.9))
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_volume.mesh = box
	var volume_material := StandardMaterial3D.new()
	volume_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	volume_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	volume_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	volume_material.no_depth_test = true
	_volume.material_override = volume_material
	_ghost.transparency = 0.45
	volume.world = lab.world
	handles.world = lab.world
	handles.build.call_deferred(lab.view)
	for i in 3:
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.no_depth_test = true
		label.pixel_size = 0.001
		label.font_size = 26
		label.outline_size = 8
		label.outline_modulate = Color(0.06, 0.09, 0.12)
		label.render_priority = 10
		_size_labels.append(label)
	for node in [_cursor_lines, _volume, _ghost] + _size_labels:
		node.visible = false
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lab.view.add_child.call_deferred(node)
	camera.name = "EditorCamera"
	camera.lab = lab
	camera.right_clicked.connect(_on_right_click)
	lab.view.add_child.call_deferred(camera)
	lab.mode_changed.connect(func(_mode: String) -> void: cancel())
	if lab.level:
		_load_room_defaults()
	else:
		lab.world_sync.snapshot_applied.connect(_load_room_defaults, CONNECT_ONE_SHOT)


func _load_room_defaults() -> void:
	var settings: Dictionary = lab.level.settings
	room_floor = settings.get("room_floor", room_floor)
	room_wall = settings.get("room_wall", room_wall)
	room_ceiling = settings.get("room_ceiling", room_ceiling)
	room_thickness = settings.get("room_thickness", room_thickness)


func _exit_tree() -> void:
	for node in [_cursor_lines, _volume, _ghost, camera] + _size_labels:
		if is_instance_valid(node):
			node.queue_free()
	handles.free_meshes()


func is_active() -> bool:
	return lab.mode == "edit" and player.is_local


func snap() -> int:
	return SNAPS[snap_index]


func set_tool(new_tool: Tool) -> void:
	cancel()
	tool = new_tool
	changed.emit()


func select(id: String) -> void:
	selected = id
	handles.cancel()
	var object: Dictionary = lab.level.objects.get(id, {})
	handles.room = object if object.get("kind") == "room" else {}
	lab.view.set_selected(id)
	changed.emit()


## The selected object, {} when none.
func selection() -> Dictionary:
	return lab.level.objects.get(selected, {}) if selected != "" else {}


## Switches between the builder view and the walk view. Into the walk view you land where the
## mouse points (or under the camera), facing the camera's way; out of it the camera looks at you.
func set_view(builder_view: bool) -> void:
	cancel()
	if builder_view == builder:
		return
	builder = builder_view
	if is_active():
		if builder:
			camera.look_from(player.global_position, rad_to_deg(player.rotation.y))
		else:
			_drop_into_walk()
		_apply_view()
	changed.emit()


func _drop_into_walk() -> void:
	var ray := camera.mouse_ray()
	var hit := camera.raycast(ray[0], ray[1])
	var feet := camera.pivot
	if hit.hit:
		var landing: Vector3i = hit.voxel + Vector3i(hit.normal)
		feet = lab.view.to_world(Vector3(landing) + Vector3(0.5, 0.0, 0.5))
	player.teleport(feet)
	player.rotation.y = deg_to_rad(camera.yaw)
	player.head.rotation.x = 0.0
	# Walk if there's room to stand; fly out of anything solid.
	player.flying = lab.world.box_overlaps_solid(player.get_body_aabb())
	player.velocity = Vector3.ZERO


## Points the screen at the current view (also after play-testing, which uses the player's camera).
func _apply_view() -> void:
	var use_builder := builder and is_active()
	player.builder_view = use_builder
	camera.set_active(use_builder)
	if use_builder:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		player.camera.current = true
		resume()


## Back to the world after a panel button: the walk view takes the mouse again.
func resume() -> void:
	if is_active() and not builder and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Where the tools aim on screen: the mouse in the builder view, the crosshair in the walk view.
func pointer() -> Vector2:
	return camera.mouse_position() if builder else get_viewport().get_visible_rect().size * 0.5


## The pointer aims the tools: over the world (not a panel) in the builder view, captured in the
## walk view.
func is_aiming() -> bool:
	if builder:
		return not EditorInput.pointer_over_ui() and not EditorInput.modal_open()
	return InputSetup.is_playing()


## Drops the pending volume / handle / move / stroke.
func cancel() -> void:
	volume.cancel()
	handles.cancel()
	_grab = {}
	_grab_id = ""
	_end_stroke()


# --- Per frame -----------------------------------------------------------------------------------

## Something to back out of with Esc: a volume being sized, a move or a stroke.
func has_step() -> bool:
	return volume.is_active() or handles.is_busy() or not _grab.is_empty() or _stroke != 0


func _process(delta: float) -> void:
	if camera.active != (builder and is_active()):
		_apply_view()
	camera.zoom_enabled = not volume.is_active() and not handles.is_busy()
	if not is_active():
		for node in [_cursor_lines, _volume, _ghost] + _size_labels:
			node.visible = false
		return
	if not selected.is_empty() and not lab.level.objects.has(selected):
		select("") # Removed by someone else (or undone).
	camera.cut_step = snap()
	_update_cursor()
	if volume.is_active() and is_aiming():
		volume.aim(_aim_from, _aim_direction)
	# Keep the handles on the room as it is now (someone else may have changed it); the auto cut
	# opens the selected room.
	var focus := selection()
	camera.focus_ceiling = int(focus.to.y) if focus.get("kind") == "room" else -1
	if not handles.is_busy():
		handles.room = focus if focus.get("kind") == "room" and tool == Tool.SELECT else {}
	handles.update(get_viewport().get_camera_3d(), pointer(), _aim_from, _aim_direction, snap())
	if _stroke != 0:
		_dab_timer -= delta
		if _dab_timer <= 0.0:
			_dab_timer = DAB_INTERVAL
			_dab()
	_update_previews()


func _update_cursor() -> void:
	var from := player.camera.global_position
	var direction := -player.camera.global_basis.z
	if builder:
		var ray := camera.mouse_ray()
		from = ray[0]
		direction = ray[1]
	_aim_from = from
	_aim_direction = direction
	var world := lab.world
	object_under = ""
	cursor_on_cap = false
	if not is_aiming():
		has_cursor = false
		return
	var object_distance := INF
	var cutting := camera.is_cutting()
	for object: Dictionary in lab.level.objects.values():
		if object.id == _grab_id or object.kind == "room" or (object.kind == "opening" and tool != Tool.SELECT):
			continue
		var box := LevelSchema.box_of(object)
		if cutting and box.position.y >= camera.cut_layer:
			continue # Cut away with the voxels above the cut.
		var hit = AABB(lab.view.to_world(box.position), box.size * world.voxel_size).intersects_ray(from, direction)
		if hit != null and from.distance_to(hit) < object_distance:
			object_distance = from.distance_to(hit)
			object_under = object.id

	if free_cursor and not builder:
		has_cursor = true
		cell = world.world_to_voxel(from + direction * free_distance)
		solid_cell = cell
		cursor_normal = Vector3i.UP
		return
	var hit: Dictionary = camera.raycast(from, direction) if builder else world.raycast(from, direction, REACH)
	has_cursor = hit.hit or object_under != ""
	if hit.hit:
		solid_cell = hit.voxel
		cursor_normal = Vector3i(hit.normal)
		cell = hit.voxel + cursor_normal
		cursor_on_cap = hit.get("cap", false)
	# Props and markers aren't voxels while editing; placing on top of one uses its surface.
	if object_under != "" and (not hit.hit or object_distance < hit.distance) and tool in [Tool.PROP, Tool.MARKER, Tool.SELECT]:
		cell = world.world_to_voxel(from + direction * (object_distance - 0.05))
	elif object_under != "" and hit.hit and hit.distance < object_distance:
		object_under = "" # Behind a wall.
	if tool == Tool.SELECT and object_under == "" and hit.hit:
		object_under = room_under()


## The room the cursor is in (the air in front of the aimed surface is inside it) or on (the aimed
## voxel is in its lining); the newest wins. "" when none.
func room_under() -> String:
	var inside_best := ""
	var lining_best := ""
	var inside_order := -1
	var lining_order := -1
	var air := Vector3(cell) + Vector3.ONE * 0.5
	var wall := Vector3(solid_cell) + Vector3.ONE * 0.5
	for object: Dictionary in lab.level.objects.values():
		if object.kind != "room":
			continue
		var order := int(object.order)
		if LevelSchema.box_of(object).has_point(air) and order > inside_order:
			inside_best = object.id
			inside_order = order
		elif LevelSchema.room_outer(object).has_point(wall) and order > lining_order:
			lining_best = object.id
			lining_order = order
	return inside_best if inside_best != "" else lining_best


## A cell snapped down to the grid.
func snapped_cell(c: Vector3i) -> Vector3i:
	var s := snap()
	return Vector3i(floori(c.x / float(s)) * s, floori(c.y / float(s)) * s, floori(c.z / float(s)) * s)


func _starts_on_solid(carve: bool) -> bool:
	return carve or tool == Tool.REPLACE or (tool == Tool.ROOM and cursor_on_cap)


## A volume's start cell under the cursor: the solid voxel for carving and Replace (and a room dug
## down from the cutaway's cross section), otherwise the empty cell in front of the surface. x and
## z snap to the grid; y stays on the surface.
func _start_cell(carve: bool) -> Vector3i:
	var start := cell
	if _starts_on_solid(carve):
		start = solid_cell
	elif tool == Tool.ROOM and cursor_normal.y == 0:
		# A room started on a wall stands on the floor below.
		for i in 200:
			if start.y <= 0 or lab.world.get_voxel(start + Vector3i.DOWN) != 0:
				break
			start.y -= 1
	var snapped := snapped_cell(start)
	return Vector3i(snapped.x, start.y, snapped.z)


# --- Input ---------------------------------------------------------------------------------------

## A stroke ends wherever the button comes up: over a panel too, which the GUI would otherwise eat.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_end_stroke()
		if event.button_index == MOUSE_BUTTON_LEFT and handles.is_busy() and is_active():
			var resized := handles.release(pointer())
			if not resized.is_empty():
				_commit_resize(resized)


func _unhandled_input(event: InputEvent) -> void:
	if not player.is_local:
		return
	if not EditorInput.world_may_use(event):
		return
	if InputSetup.pressed(event, "editor_playtest") and Net.session.mode == "edit":
		lab.request_mode("play" if lab.mode == "edit" else "edit")
		get_viewport().set_input_as_handled()
		return
	if not is_active():
		return
	if InputSetup.pressed(event, "editor_back"):
		back()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if is_aiming():
			_mouse(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		if _key(event):
			get_viewport().set_input_as_handled()


## Esc: drop the tool step, else the selection, else free the mouse, else ask for the menu.
func back() -> void:
	if has_step():
		cancel()
	elif selected != "":
		select("")
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		menu_requested.emit()
	changed.emit()


func _mouse(event: InputEventMouseButton) -> void:
	# A room handle held or picked up: the wheel nudges it.
	if handles.is_busy() and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		handles.nudge(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		get_viewport().set_input_as_handled()
		return
	# Sizing a volume: the wheel grows or shrinks the active size (Shift: the other floor size).
	if volume.is_active() and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		var grow := event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_RIGHT]
		var other := event.shift_pressed or event.button_index in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
		var on_axis := volume.axis
		if other and on_axis != Vector3.AXIS_Y:
			on_axis = Vector3.AXIS_Z if on_axis == Vector3.AXIS_X else Vector3.AXIS_X
		volume.apply_typed()
		volume.nudge(on_axis, 1 if grow else -1)
		get_viewport().set_input_as_handled()
		return
	# Builder view: the camera has the wheel and the right button (a right click comes back as
	# right_clicked).
	if builder and event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
		var up := event.button_index == MOUSE_BUTTON_WHEEL_UP
		if event.ctrl_pressed:
			free_distance = clampf(free_distance * (1.15 if up else 1.0 / 1.15), 1.0, 40.0)
		else:
			player.fly_speed = clampf(player.fly_speed * (1.2 if up else 1.0 / 1.2), 1.0, 60.0)
		changed.emit()
		return
	if not event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	if not event.pressed:
		_end_stroke()
		return
	if event.button_index == MOUSE_BUTTON_LEFT and tool == Tool.SELECT and _grab.is_empty() and handles.press(pointer(), _aim_from, _aim_direction):
		return
	if event.alt_pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pick()
	elif event.shift_pressed and event.button_index == MOUSE_BUTTON_LEFT and tool == Tool.BRUSH:
		if has_cursor:
			_begin_stroke(2)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		_primary()
	else:
		_secondary()


## Returns true if the key was used.
func _key(event: InputEventKey) -> bool:
	if volume.is_active() and _volume_key(event):
		return true
	for i in TOOL_ACTIONS.size():
		if InputSetup.pressed(event, TOOL_ACTIONS[i]):
			set_tool(i as Tool)
			return true
	# F frames the selection in the builder view and toggles flying in the walk view.
	if InputSetup.pressed(event, "editor_view"):
		set_view(not builder)
		return true
	if builder and InputSetup.pressed(event, "editor_frame"):
		frame_selection()
		return true
	if builder and InputSetup.pressed(event, "editor_frame_all"):
		camera.frame_world()
		return true
	if not builder and InputSetup.pressed(event, "editor_fly"):
		player.flying = not player.flying
		player.velocity = Vector3.ZERO
		lab.notify("Flying" if player.flying else "Walking", false)
		return true
	var actions := {
		editor_undo = func() -> void: lab.edits.undo(),
		editor_redo = func() -> void: lab.edits.redo(),
		editor_save = lab.request_save,
		editor_duplicate = _duplicate,
		editor_rotate = _rotate,
		editor_grid = func() -> void: snap_index = (snap_index + 1) % SNAPS.size(),
		editor_free_cursor = func() -> void: free_cursor = not free_cursor,
		editor_brush_smaller = func() -> void: brush_size = maxi(brush_size - 1, 1),
		editor_brush_bigger = func() -> void: brush_size = mini(brush_size + 1, 20),
		editor_move = _start_move,
		editor_delete = delete_selected,
	}
	for action: String in actions:
		if InputSetup.pressed(event, action):
			actions[action].call()
			changed.emit()
			return true
	return false


## Builder view: centers the camera on the selection, or on the cursor.
func frame_selection() -> void:
	if selected != "" and lab.level.objects.has(selected):
		var box := LevelSchema.box_of(lab.level.objects[selected])
		camera.frame(AABB(lab.view.to_world(box.position), box.size * lab.world.voxel_size))
	elif has_cursor:
		camera.pivot = lab.view.to_world(Vector3(cell) + Vector3(0.5, 0.0, 0.5))


func _primary() -> void:
	if volume.is_active():
		_volume_click(false)
		return
	if not has_cursor:
		return
	match tool:
		Tool.BOX, Tool.ROOM, Tool.REPLACE:
			_volume_click(false)
		Tool.OPENING:
			_place_opening()
		Tool.BRUSH:
			_begin_stroke(1)
		Tool.PROP:
			if _grab.is_empty():
				lab.edits.put_object(LevelSchema.new_prop(prop_name, _prop_origin(prop_name, facing), facing))
			else:
				_commit_move()
		Tool.MARKER:
			var marker := LevelSchema.new_marker(marker_type, _marker_position(), _view_yaw())
			lab.edits.put_object(marker)
		Tool.SELECT:
			if _grab.is_empty():
				select(object_under)
			else:
				_commit_move()


func _secondary() -> void:
	# RMB steps back while sizing a volume, starts a carve with Box, and backs out of other steps.
	if handles.is_busy():
		handles.cancel()
		return
	if volume.is_active():
		volume.back()
		changed.emit()
		return
	if has_step():
		cancel()
		return
	match tool:
		Tool.BOX:
			if has_cursor:
				_volume_click(true)
		Tool.BRUSH:
			if has_cursor:
				_begin_stroke(2)
		Tool.PROP:
			if _grab.is_empty():
				_rotate()
			else:
				cancel()
		_:
			cancel()


## Builder view right click (no drag): the tool's RMB action; Brush carves a single dab.
func _on_right_click() -> void:
	if not is_aiming():
		return
	_secondary()
	if _stroke != 0:
		_dab()
		_end_stroke()


## A volume tool click: the start corner, then the floor, then the height (which builds it).
func _volume_click(carve: bool) -> void:
	if not volume.is_active():
		if not has_cursor:
			return
		_volume_carve = carve
		var start := _start_cell(carve)
		var from_solid := _starts_on_solid(carve)
		# Picked on a floor's top (or the cut): the height goes down into it by default.
		var down := from_solid and cursor_normal == Vector3i.UP
		var surface := start.y + (1 if from_solid else 0)
		volume.begin(start, lab.view.to_world(Vector3(0, surface, 0)).y, snap(), -1 if down else 1)
		if tool == Tool.REPLACE:
			_replace_source = lab.world.get_voxel(solid_cell)
		changed.emit()
		return
	if volume.step == VolumeSteps.Step.FLOOR:
		volume.advance(_default_height())
		changed.emit()
		return
	_build_volume()


## The height the height step starts at (signed voxels): the last one used, going down when the
## start was on a floor's top. A room dug from the cutaway reaches down to the floor you're looking
## at, so it lines up with the room beside it.
func _default_height() -> int:
	var height: int = _last_height.get(tool, 10)
	if volume.extent.y > 0:
		return height
	if tool == Tool.ROOM and builder and camera.is_cutting():
		var floor_layer: int = lab.world.world_to_voxel(camera.pivot + Vector3.UP * 0.05).y
		var depth := volume.start.y + 1 - floor_layer
		if depth >= 1 and depth <= 200:
			return -depth
	return -height


func _build_volume() -> void:
	volume.apply_typed()
	var box := volume.box()
	match tool:
		Tool.BOX:
			lab.edits.voxel_op({type = "box", from = box[0], to = box[1], material = VoxelMaterials.AIR if _volume_carve else material})
		Tool.ROOM:
			lab.edits.put_object(LevelSchema.new_room(box[0], box[1], room_floor, room_wall, room_ceiling, room_thickness,
					LevelStructure.next_order(lab.level.objects)))
		Tool.REPLACE:
			if _replace_source != 0:
				lab.edits.voxel_op({type = "replace", from = box[0], to = box[1], material = material, source = _replace_source})
	_last_height[tool] = absi(volume.extent.y)
	volume.cancel()
	changed.emit()


## Keys while sizing a volume: digits, "." and "v" type a size; Backspace erases or steps back;
## Enter keeps the typed size, or clicks when there's none. Tab (from the HUD) is next_size.
func _volume_key(event: InputEventKey) -> bool:
	var code := event.keycode
	if event.ctrl_pressed or event.alt_pressed:
		return false
	var character := ""
	if code >= KEY_0 and code <= KEY_9:
		character = str(code - KEY_0)
	elif code >= KEY_KP_0 and code <= KEY_KP_9:
		character = str(code - KEY_KP_0)
	elif code in [KEY_PERIOD, KEY_KP_PERIOD, KEY_COMMA]:
		character = "."
	elif code == KEY_V and volume.typed != "":
		character = "v"
	if character != "":
		volume.type_char(character)
	elif code == KEY_BACKSPACE:
		if volume.typed != "":
			volume.erase_char()
		else:
			volume.back()
	elif code in [KEY_ENTER, KEY_KP_ENTER]:
		if volume.typed != "":
			volume.apply_typed()
		else:
			_volume_click(_volume_carve)
	else:
		return false
	changed.emit()
	return true


## Tab while sizing: the next dimension.
func next_size() -> void:
	volume.cycle_axis()
	changed.emit()


## The sized volume for the HUD's readout, as BBCode ("" when not sizing): name, the three sizes in
## meters (the active one highlighted, with what's being typed) and in voxels.
func volume_readout() -> String:
	var box := {}
	if handles.is_busy() and not handles.resized.is_empty():
		box = handles.resized
	elif LevelSchema.is_structure(_grab) and has_cursor:
		box = _grab.duplicate()
		_place_grab(box)
	if not box.is_empty():
		var size: Vector3i = box.to - box.from
		var meters := Vector3(size) * lab.world.voxel_size
		var title := "Resize room" if handles.is_busy() else ("Duplicate " if _grab_id == "" else "Move ") + str(box.kind)
		return "[b]%s[/b]   %.1f × %.1f × %.1f m   [color=#%s](%d × %d × %d voxels)[/color]" % [title, meters.x, meters.z, meters.y,
				PaperPalette.INK_MUTED.to_html(false), size.x, size.z, size.y]
	if not volume.is_active():
		return ""
	var size := volume.size()
	var meters: Array[String] = []
	for a in [Vector3.AXIS_X, Vector3.AXIS_Z, Vector3.AXIS_Y]:
		var text := "%.1f" % (size[a] * lab.world.voxel_size)
		if a == Vector3.AXIS_Y and volume.step == VolumeSteps.Step.FLOOR:
			text = "?"
		if a == volume.axis:
			text = "[color=#%s][b][u]%s[/u][/b][/color]" % [PaperPalette.ACCENT.to_html(false), (volume.typed + "_") if volume.typed != "" else text]
		meters.append(text)
	var title: String = TOOL_NAMES[tool] + (" (carve)" if _volume_carve else "")
	var voxels := "%d × %d × %d voxels" % [size.x, size.z, size.y] if volume.step == VolumeSteps.Step.HEIGHT else "%d × %d voxels" % [size.x, size.z]
	return "[b]%s[/b]   %s m   [color=#%s](%s)[/color]" % [title, " × ".join(meters), PaperPalette.INK_MUTED.to_html(false), voxels]


func _begin_stroke(kind: int) -> void:
	_stroke = kind
	_dab_timer = 0.0
	lab.edits.begin_group()


func _end_stroke() -> void:
	if _stroke != 0:
		_stroke = 0
		lab.edits.end_group()


func _dab() -> void:
	if not has_cursor:
		return
	var carve := _stroke == 2
	var target := solid_cell if carve else cell
	var paint := VoxelMaterials.AIR if carve else material
	if brush_cube:
		var half := Vector3i.ONE * (brush_size - 1)
		lab.edits.voxel_op({type = "box", from = target - half, to = target + half + Vector3i.ONE, material = paint})
	else:
		lab.edits.voxel_op({type = "sphere", center = Vector3(target) + Vector3.ONE * 0.5, radius = float(brush_size), material = paint})


## Alt+LMB: take the material (voxel tools) or the prop type (prop tool) under the cursor; with the
## Room tool, adopt the carved space under it as a room.
func _pick() -> void:
	if tool == Tool.ROOM:
		_room_from_space()
		return
	if tool == Tool.PROP and object_under != "" and lab.level.objects[object_under].kind == "prop":
		prop_name = lab.level.objects[object_under].name
		facing = lab.level.objects[object_under].facing
	elif has_cursor and lab.world.get_voxel(solid_cell) != 0:
		material = lab.world.get_voxel(solid_cell)
		lab.notify("Material: " + VoxelMaterials.get_material_name(material), false)
	changed.emit()


func _rotate() -> void:
	if LevelSchema.is_structure(_grab) or (tool == Tool.SELECT and LevelSchema.is_structure(selection())):
		return # Rooms and openings don't turn (yet).
	if not _grab.is_empty():
		_turn(_grab)
	elif tool == Tool.PROP:
		facing = (facing + 1) % 4
	elif tool == Tool.SELECT and selected != "":
		var object: Dictionary = lab.level.objects[selected].duplicate()
		_turn(object)
		lab.edits.put_object(object, selected)
	elif tool == Tool.MARKER:
		return


func _turn(object: Dictionary) -> void:
	if object.kind == "prop":
		object.facing = (object.facing + 1) % 4
	else:
		object.yaw = wrapf(object.yaw - 90.0, -180.0, 180.0)


func delete_selected() -> void:
	if selected == "":
		return
	var object := selection()
	if object.get("kind") == "room":
		# The room fills back in, with its openings; door props in its walls go too.
		var puts: Array = [[selected, {}]]
		for other: Dictionary in lab.level.objects.values():
			if other.kind == "opening" and other.room == selected:
				puts.append([other.door if other.door != "" and lab.level.objects.has(other.door) else other.id, {}])
		lab.edits.put_objects(puts)
	else:
		lab.edits.remove_object(selected)
	select("")


func _start_move() -> void:
	if selected == "":
		return
	_grab = lab.level.objects[selected].duplicate()
	_grab_id = selected


func _duplicate() -> void:
	if selected == "":
		return
	_grab = lab.level.objects[selected].duplicate()
	_grab.id = ""
	_grab_id = ""
	_grab_source = selected


## Puts the moved / duplicated object where the cursor is. A room takes its openings, doors and
## (move_contents) what's inside along.
func _commit_move() -> void:
	var object := _grab.duplicate()
	_place_grab(object)
	if object.kind == "room":
		var objects: Dictionary = lab.level.objects
		if _grab_id != "" and objects.has(_grab_id):
			lab.edits.put_objects(RoomTools.carry(objects, objects[_grab_id], object, move_contents))
		elif objects.has(_grab_source):
			var source: Dictionary = objects[_grab_source]
			lab.edits.put_objects(RoomTools.duplicate(objects, source, object.from - source.from, move_contents))
	else:
		lab.edits.put_object(object, _grab_id)
	cancel()


func _place_grab(object: Dictionary) -> void:
	match object.kind:
		"prop":
			object.origin = _prop_origin(object.name, object.facing)
		"room", "opening":
			# Centered on the cursor; it stands on the floor there, or keeps its height over cut rock.
			var size: Vector3i = object.to - object.from
			var corner := snapped_cell(cell - Vector3i(size.x / 2, 0, size.z / 2))
			var y: int = cell.y if cursor_normal == Vector3i.UP and not cursor_on_cap and object.kind == "room" else object.from.y
			object.from = Vector3i(corner.x, y, corner.z)
			object.to = object.from + size
		_:
			object.position = _marker_position()


## Drops a resized room: one edit with the openings (and doors) in the walls that moved.
func _commit_resize(resized: Dictionary) -> void:
	var objects: Dictionary = lab.level.objects
	if not objects.has(resized.id) or resized == objects[resized.id]:
		return
	lab.edits.put_objects(RoomTools.carry(objects, objects[resized.id], resized, false))


## Room tool, Alt+click: the carved space under the cursor becomes a room object (the voxels stay as
## they are), so rooms built by hand or converted from old levels can be resized too.
func _room_from_space() -> void:
	if not has_cursor:
		return
	var space := RoomTools.space_around(lab.world, cell)
	if space.is_empty():
		lab.notify("Alt+click inside a carved space to make it a room", false)
		return
	for object: Dictionary in lab.level.objects.values():
		if object.kind == "room" and object.from == space.from and object.to == space.to:
			select(object.id)
			return
	var room := LevelSchema.new_room(space.from, space.to, space.floor, space.wall, space.ceiling, space.thickness,
			LevelStructure.next_order(lab.level.objects))
	lab.edits.put_object(room)
	var size: Vector3 = Vector3(space.to - space.from) * lab.world.voxel_size
	lab.notify("Room from space: %.1f × %.1f × %.1f m" % [size.x, size.z, size.y], false)


## Opening tool: the box it would cut at the cursor ([] when not aimed at a wall), and the room
## whose wall it's in.
func opening_at_cursor() -> Dictionary:
	if not has_cursor or cursor_normal.y != 0:
		return {}
	var objects: Dictionary = lab.level.objects
	var room_id := LevelStructure.room_at(objects, AABB(Vector3(solid_cell) + Vector3.ONE * 0.25, Vector3.ONE * 0.5))
	var bottom := RoomTools.floor_under(lab.world, cell) if room_id == "" else int(objects[room_id].from.y)
	match opening_type:
		"window":
			bottom += opening_sill
		"hole":
			bottom = cell.y - opening_height / 2
	var box := RoomTools.opening_box(lab.world, solid_cell, cursor_normal, opening_width, opening_height, bottom, snap())
	return {} if box.is_empty() else {from = box[0], to = box[1], room = room_id}


func _place_opening() -> void:
	var at := opening_at_cursor()
	if at.is_empty():
		lab.notify("Aim at a wall to cut an opening", false)
		return
	lab.edits.put_object(LevelSchema.new_opening(at.from, at.to, at.room, opening_type))


## A prop's origin when placed at the cursor: footprint centered on the cell, snapped to the grid.
func _prop_origin(name: String, prop_facing: int) -> Vector3i:
	var box := LevelSchema.prop_box({kind = "prop", name = name, origin = Vector3i.ZERO, facing = prop_facing})
	var corner := cell - Vector3i(int(box.size.x) / 2, 0, int(box.size.z) / 2)
	var snapped := snapped_cell(corner)
	return Vector3i(snapped.x, cell.y, snapped.z)


func _marker_position() -> Vector3:
	var s := snap()
	var snapped := snapped_cell(cell)
	return Vector3(snapped.x + s * 0.5, cell.y, snapped.z + s * 0.5) if s > 1 else Vector3(cell) + Vector3(0.5, 0.0, 0.5)


## Width / height / length on the edges of the box (world space) nearest the camera; active_axis is
## highlighted (-1: none), and show_height false leaves the height off.
func _place_size_labels(box: AABB, active_axis: int, show_height: bool, typed := "") -> void:
	var eye := get_viewport().get_camera_3d().global_position if get_viewport().get_camera_3d() else box.get_center()
	var near_x := box.end.x if eye.x > box.get_center().x else box.position.x
	var near_z := box.end.z if eye.z > box.get_center().z else box.position.z
	var bottom := box.position.y
	var spots := [
		Vector3(box.get_center().x, bottom, near_z),
		Vector3(near_x, box.get_center().y, near_z),
		Vector3(near_x, bottom, box.get_center().z),
	]
	for a in 3:
		var label := _size_labels[a]
		if a == Vector3.AXIS_Y and not show_height:
			continue
		label.text = "%.1f m" % box.size[a]
		if a == active_axis and typed != "":
			label.text = typed + "_"
		var active := a == active_axis
		label.modulate = LABEL_ACTIVE_COLOR if active else LABEL_COLOR
		label.font_size = 32 if active else 24
		label.position = spots[a]
		label.visible = true


## The view direction as a marker yaw, to 45 degrees.
func _view_yaw() -> float:
	return snappedf(wrapf(camera.yaw if builder else rad_to_deg(player.rotation.y), -180.0, 180.0), 45.0)


# --- Previews ------------------------------------------------------------------------------------

func _update_previews() -> void:
	_cursor_lines.visible = has_cursor and not volume.is_active() and tool in [Tool.BOX, Tool.ROOM, Tool.BRUSH, Tool.REPLACE]
	_volume.visible = false
	_ghost.visible = false
	for label in _size_labels:
		label.visible = false
	if _cursor_lines.visible:
		var box: AABB
		if tool == Tool.BRUSH:
			box = AABB(Vector3(cell) - Vector3.ONE * (brush_size - 1), Vector3.ONE * (brush_size * 2 - 1))
		else:
			# Where the first click would start: a grid cell's footprint on the surface.
			box = AABB(Vector3(_start_cell(false)), Vector3(snap(), 1, snap()))
		lab.view.draw_box(_cursor_lines.mesh, box)
	if volume.is_active():
		var box := volume.box()
		var color := Color(0.3, 1.0, 0.4)
		if _volume_carve:
			color = Color(1.0, 0.3, 0.3)
		elif tool == Tool.ROOM:
			color = Color(0.3, 0.6, 1.0)
		elif tool == Tool.REPLACE:
			color = Color(1.0, 0.85, 0.2)
		(_volume.material_override as StandardMaterial3D).albedo_color = Color(color, 0.25)
		var size := Vector3(box[1] - box[0]) * lab.world.voxel_size
		_volume.scale = size
		_volume.position = lab.view.to_world(Vector3(box[0])) + size * 0.5
		_volume.visible = true
		_place_size_labels(AABB(lab.view.to_world(Vector3(box[0])), size), volume.axis, volume.step == VolumeSteps.Step.HEIGHT, volume.typed)
	# A room being resized or moved, an opening about to be cut or moved: its box.
	var box_preview := {}
	var preview_color := Color(0.3, 0.6, 1.0)
	if handles.is_busy() and not handles.resized.is_empty():
		box_preview = handles.resized
	elif LevelSchema.is_structure(_grab) and has_cursor:
		box_preview = _grab.duplicate()
		_place_grab(box_preview)
	elif tool == Tool.OPENING:
		box_preview = opening_at_cursor()
	if box_preview.get("kind", "opening") == "opening":
		preview_color = Color(1.0, 0.6, 0.2)
	if not box_preview.is_empty():
		(_volume.material_override as StandardMaterial3D).albedo_color = Color(preview_color, 0.25)
		var size := Vector3(box_preview.to - box_preview.from) * lab.world.voxel_size
		_volume.scale = size
		_volume.position = lab.view.to_world(Vector3(box_preview.from)) + size * 0.5
		_volume.visible = true
		var axis := -1
		for a in 3:
			if handles.active[a] != 0:
				axis = a
		_place_size_labels(AABB(lab.view.to_world(Vector3(box_preview.from)), size), axis, true)
	# Ghost of the prop being placed or moved, or of a moved marker's box.
	var ghost := {}
	if not _grab.is_empty() and not LevelSchema.is_structure(_grab):
		ghost = _grab.duplicate()
		_place_grab(ghost)
	elif tool == Tool.PROP:
		ghost = LevelSchema.new_prop(prop_name, _prop_origin(prop_name, facing), facing)
	if not ghost.is_empty() and has_cursor:
		if ghost.kind == "prop":
			_ghost.mesh = lab.view.prop_mesh(ghost.name, ghost.facing)
			_ghost.material_override = lab.world.material
			_ghost.position = lab.view.to_world(Vector3(ghost.origin))
			_ghost.visible = _ghost.mesh != null
		else:
			var box := LevelSchema.marker_box(ghost)
			_cursor_lines.visible = true
			lab.view.draw_box(_cursor_lines.mesh, box)
