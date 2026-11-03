class_name EditorTool
extends Node
## The level editor for the local player: aims a cursor, runs the tools and draws their previews.
## Active in edit mode while the mouse is captured; Tab frees the mouse for the panel (EditorHud).
## Every change goes through LevelEdits, so it's shared and undoable.
##
## Keys: 1-7 tools, LMB / RMB use the tool, Alt+LMB pick (material or prop), Q cancel, R rotate,
## G grid snap, V free cursor (Ctrl+wheel distance), [ ] brush size, B brush shape, M move,
## Ctrl+D duplicate, X / Delete delete, Ctrl+Z / Ctrl+Y undo / redo, Ctrl+S save, F5 play-test,
## wheel fly speed, Tab panel.

## Tool, material or selection changed (the HUD redraws its panel).
signal changed

enum Tool { BOX, ROOM, BRUSH, REPLACE, PROP, MARKER, SELECT }

const TOOL_NAMES := ["Box", "Room", "Brush", "Replace", "Prop", "Marker", "Select"]
const TOOL_HINTS := [
	"LMB two corners: fill · RMB two corners: carve",
	"LMB two corners (inside of the room): carve it and line it",
	"LMB hold: paint · RMB hold: carve · [ ] size · B shape",
	"LMB on the material to replace, then the far corner",
	"LMB place · R / RMB rotate · Alt+LMB pick a placed prop's type",
	"LMB place the marker · facing follows your view",
	"LMB select · M move · Ctrl+D duplicate · R rotate · X delete",
]
const SNAPS := [1, 5, 10]
## How far the cursor reaches, in meters.
const REACH := 80.0
const DAB_INTERVAL := 0.06

var lab: Lab
var player: Player

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
## Tab freed the mouse to use the panel (so the HUD doesn't show the pause menu).
var panel_open := false

## Cursor this frame: the empty cell in front of the aimed surface, the solid cell aimed at, and
## the placed object under the crosshair.
var has_cursor := false
var cell := Vector3i.ZERO
var solid_cell := Vector3i.ZERO
var object_under := ""

## First corner of a box tool, and whether it carves.
var _corner: Variant = null
var _corner_carve := false
var _replace_source := 0
## Object being moved / duplicated (a copy with the pending changes), its original id ("" = new).
var _grab := {}
var _grab_id := ""
## 0 none, 1 painting, 2 carving
var _stroke := 0
var _dab_timer := 0.0

var _cursor_lines := MeshInstance3D.new()
var _volume := MeshInstance3D.new()
var _ghost := MeshInstance3D.new()


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
	for node in [_cursor_lines, _volume, _ghost]:
		node.visible = false
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lab.view.add_child.call_deferred(node)
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
	for node in [_cursor_lines, _volume, _ghost]:
		if is_instance_valid(node):
			node.queue_free()


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
	lab.view.set_selected(id)
	changed.emit()


## Drops the pending corner / move / stroke.
func cancel() -> void:
	_corner = null
	_grab = {}
	_grab_id = ""
	_end_stroke()


# --- Per frame -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		panel_open = false
	if not is_active():
		for node in [_cursor_lines, _volume, _ghost]:
			node.visible = false
		return
	if not selected.is_empty() and not lab.level.objects.has(selected):
		select("") # Removed by someone else (or undone).
	_update_cursor()
	if _stroke != 0 and InputSetup.is_playing():
		_dab_timer -= delta
		if _dab_timer <= 0.0:
			_dab_timer = DAB_INTERVAL
			_dab()
	_update_previews()


func _update_cursor() -> void:
	var camera := player.camera
	var from := camera.global_position
	var direction := -camera.global_basis.z
	var world := lab.world
	object_under = ""
	var object_distance := INF
	for object: Dictionary in lab.level.objects.values():
		if object.id == _grab_id:
			continue
		var box := LevelSchema.box_of(object)
		var hit = AABB(lab.view.to_world(box.position), box.size * world.voxel_size).intersects_ray(from, direction)
		if hit != null and from.distance_to(hit) < object_distance:
			object_distance = from.distance_to(hit)
			object_under = object.id

	if free_cursor:
		has_cursor = true
		cell = world.world_to_voxel(from + direction * free_distance)
		solid_cell = cell
		return
	var hit: Dictionary = world.raycast(from, direction, REACH)
	has_cursor = hit.hit or object_under != ""
	if hit.hit:
		solid_cell = hit.voxel
		cell = hit.voxel + Vector3i(hit.normal)
	# Props and markers aren't voxels while editing; placing on top of one uses its surface.
	if object_under != "" and (not hit.hit or object_distance < hit.distance) and tool in [Tool.PROP, Tool.MARKER, Tool.SELECT]:
		cell = world.world_to_voxel(from + direction * (object_distance - 0.05))


## A cell snapped down to the grid.
func snapped_cell(c: Vector3i) -> Vector3i:
	var s := snap()
	return Vector3i(floori(c.x / float(s)) * s, floori(c.y / float(s)) * s, floori(c.z / float(s)) * s)


## The grid-aligned box covering two corner cells, as [from, to).
func box_between(a: Vector3i, b: Vector3i) -> Array[Vector3i]:
	var sa := snapped_cell(a)
	var sb := snapped_cell(b)
	return [sa.min(sb), sa.max(sb) + Vector3i.ONE * snap()]


func _corner_cell(carve: bool) -> Vector3i:
	return solid_cell if carve or tool in [Tool.ROOM, Tool.REPLACE] else cell


# --- Input ---------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5 and Net.session.mode == "edit":
		lab.request_mode("play" if lab.mode == "edit" else "edit")
		get_viewport().set_input_as_handled()
		return
	if not is_active():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		panel_open = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if panel_open else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if not InputSetup.is_playing():
		return
	if event is InputEventMouseButton:
		_mouse(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		if _key(event):
			get_viewport().set_input_as_handled()


func _mouse(event: InputEventMouseButton) -> void:
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
	if event.alt_pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pick()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		_primary()
	else:
		_secondary()


## Returns true if the key was used.
func _key(event: InputEventKey) -> bool:
	if event.ctrl_pressed:
		match event.keycode:
			KEY_Z:
				if event.shift_pressed:
					lab.edits.redo()
				else:
					lab.edits.undo()
			KEY_Y:
				lab.edits.redo()
			KEY_S:
				lab.request_save()
			KEY_D:
				_duplicate()
			_:
				return false
		return true
	if event.keycode >= KEY_1 and event.keycode <= KEY_7:
		set_tool((event.keycode - KEY_1) as Tool)
		return true
	match event.keycode:
		KEY_Q:
			cancel()
		KEY_R:
			_rotate()
		KEY_G:
			snap_index = (snap_index + 1) % SNAPS.size()
		KEY_V:
			free_cursor = not free_cursor
		KEY_BRACKETLEFT:
			brush_size = maxi(brush_size - 1, 1)
		KEY_BRACKETRIGHT:
			brush_size = mini(brush_size + 1, 20)
		KEY_B:
			brush_cube = not brush_cube
		KEY_M:
			_start_move()
		KEY_X, KEY_DELETE:
			delete_selected()
		_:
			return false
	changed.emit()
	return true


func _primary() -> void:
	if not has_cursor:
		return
	match tool:
		Tool.BOX, Tool.ROOM, Tool.REPLACE:
			_corner_click(false)
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
	match tool:
		Tool.BOX:
			if has_cursor:
				_corner_click(true)
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


func _corner_click(carve: bool) -> void:
	if _corner == null:
		_corner_carve = carve
		_corner = _corner_cell(carve)
		if tool == Tool.REPLACE:
			_replace_source = lab.world.get_voxel(_corner)
		return
	var box := box_between(_corner, _corner_cell(_corner_carve))
	match tool:
		Tool.BOX:
			lab.edits.voxel_op({type = "box", from = box[0], to = box[1], material = VoxelMaterials.AIR if _corner_carve else material})
		Tool.ROOM:
			lab.edits.voxel_op({type = "room", from = box[0], to = box[1], floor = room_floor, wall = room_wall,
					ceiling = room_ceiling, thickness = room_thickness, solid_only = lab.level.settings.get("fill", "rock") == "rock"})
		Tool.REPLACE:
			if _replace_source != 0:
				lab.edits.voxel_op({type = "replace", from = box[0], to = box[1], material = material, source = _replace_source})
	_corner = null


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


## Alt+LMB: take the material (voxel tools) or the prop type (prop tool) under the cursor.
func _pick() -> void:
	if tool == Tool.PROP and object_under != "" and lab.level.objects[object_under].kind == "prop":
		prop_name = lab.level.objects[object_under].name
		facing = lab.level.objects[object_under].facing
	elif has_cursor and lab.world.get_voxel(solid_cell) != 0:
		material = lab.world.get_voxel(solid_cell)
		lab.notify("Material: " + VoxelMaterials.get_material_name(material), false)
	changed.emit()


func _rotate() -> void:
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
	if selected != "":
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


## Puts the moved / duplicated object where the cursor is.
func _commit_move() -> void:
	var object := _grab.duplicate()
	_place_grab(object)
	lab.edits.put_object(object, _grab_id)
	cancel()


func _place_grab(object: Dictionary) -> void:
	if object.kind == "prop":
		object.origin = _prop_origin(object.name, object.facing)
	else:
		object.position = _marker_position()


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


## The player's view direction as a marker yaw, to 45 degrees.
func _view_yaw() -> float:
	return snappedf(rad_to_deg(player.rotation.y), 45.0)


# --- Previews ------------------------------------------------------------------------------------

func _update_previews() -> void:
	_cursor_lines.visible = has_cursor and tool in [Tool.BOX, Tool.ROOM, Tool.BRUSH, Tool.REPLACE]
	_volume.visible = false
	_ghost.visible = false
	if _cursor_lines.visible:
		var target := _corner_cell(_corner_carve if _corner != null else false)
		var box: AABB
		if tool == Tool.BRUSH:
			box = AABB(Vector3(cell) - Vector3.ONE * (brush_size - 1), Vector3.ONE * (brush_size * 2 - 1))
		else:
			var s := snapped_cell(target)
			box = AABB(Vector3(s), Vector3.ONE * snap())
		lab.view.draw_box(_cursor_lines.mesh, box)
	if _corner != null and has_cursor:
		var box := box_between(_corner, _corner_cell(_corner_carve))
		var color := Color(0.3, 1.0, 0.4)
		if _corner_carve:
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
	# Ghost of the prop being placed or moved, or of a moved marker's box.
	var ghost := {}
	if not _grab.is_empty():
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
