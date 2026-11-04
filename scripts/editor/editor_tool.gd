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

enum Tool { SELECT, ROOM, BOX, BRUSH, REPLACE, OPENING, PROP, MARKER, FLOOR, WALL, CEILING }

const TOOL_NAMES := ["Select", "Room", "Box", "Brush", "Replace", "Opening", "Prop", "Marker", "Floor", "Wall", "Ceiling"]
## The number keys, by place on the rail (1 ... 9, 0, -); the rail's tools depend on the level
## (tools()).
const SLOT_ACTIONS := ["editor_tool_select", "editor_tool_room", "editor_tool_box", "editor_tool_brush",
		"editor_tool_replace", "editor_tool_opening", "editor_tool_prop", "editor_tool_marker", "editor_tool_slot_9", "editor_tool_slot_10",
		"editor_tool_slot_11"]
## The rail in rock levels (carving rooms, then building in them: the first eight keep their keys)
## and in build levels (empty: floors, walls and ceilings on storeys, no Room tool).
const ROCK_TOOLS := [Tool.SELECT, Tool.ROOM, Tool.BOX, Tool.BRUSH, Tool.REPLACE, Tool.OPENING, Tool.PROP, Tool.MARKER,
		Tool.FLOOR, Tool.WALL, Tool.CEILING]
const BUILD_TOOLS := [Tool.SELECT, Tool.FLOOR, Tool.WALL, Tool.CEILING, Tool.BOX, Tool.BRUSH, Tool.REPLACE, Tool.OPENING, Tool.PROP, Tool.MARKER]
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
	"Paint the storey's floor: drag an area, or click inside walls to fill them",
	"Draw walls on the storey: drag a wall, Ctrl+drag a room of four, Shift+drag along walls to erase",
	"Cover the storey: drag an area, click inside walls, or Auto over every closed room",
]
const TOOL_HINTS := [
	"LMB select · drag a room's or wall's handles · M move · Ctrl+D duplicate · R rotate · Delete",
	"LMB corner, LMB floor, LMB height (the inside of the room) · wheel / type sizes · Alt+LMB: room from a carved space",
	"LMB corner, floor, height: fill · RMB first: carve · wheel / type sizes · Tab next size",
	"LMB hold: paint · RMB hold: carve · [ ] size",
	"LMB on the material to replace, then floor and height · wheel / type sizes · RMB back",
	"LMB on a wall: cut the opening through it",
	"LMB place (it sits on what you aim at; red: no spot) · R / RMB turn · Alt+LMB pick a placed prop's type",
	"LMB place the marker · facing follows your view",
	"LMB drag: paint an area · LMB click inside walls: fill · Shift: erase · Alt+LMB: pick a material",
	"LMB drag: a wall (snaps to 8 directions, wall ends, walls, floor edges) · wheel: height · type: length · Ctrl: four walls · Shift: erase along walls",
	"LMB drag: cover an area · LMB click inside walls: fill · Shift: erase · Auto (inspector): every closed room",
]
const SNAPS := [1, 5, 10]
## Rock levels: the tallest wall the Wall tool reaches up to a ceiling with, and how far up it (or the
## Ceiling tool) looks for one (voxels).
const ROCK_WALL_MAX := 80
const ROCK_CEILING_REACH := 200
## How far the cursor reaches, in meters.
const REACH := 80.0
const DAB_INTERVAL := 0.06
const EditorIndex := preload("res://scripts/editor/editor_index.gd")

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
## Off: Box, Brush and Replace leave what the cutaway hides (above the cut) alone.
var edit_hidden := false
var prop_name := "chair"
var facing := 0
var marker_type := "light"
var selected := ""
## Build mode (empty levels): the storey being worked on (LevelBuild). Page Up / Down change it, the
## cutaway opens it, and the cursor lands on its floor plane where nothing else is. Rock levels have
## none: the build tools work on the surface aimed at.
var storey := 0
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
## End and middle handles on a selected wall (build levels).
var wall_handles := WallHandles.new()
## Floor and Ceiling tools (build levels): their aim, snapping and drag.
var build := BuildTools.new()
## Wall tool (build levels): its drag, and the walls it draws: material (room_wall), the left face's
## material (0: none), thickness, height (-1: the storey's; in rock levels, up to the ceiling), and
## whether Ctrl's rectangle also gets a floor and a ceiling.
var wall := WallTool.new()
var wall_inner := 0
var wall_thickness := 2
var wall_height := -1
var wall_slabs := true
## Last height built per tool, in voxels: the next one starts there.
var _last_height := {Tool.ROOM: 30, Tool.BOX: 10, Tool.REPLACE: 10}
## This frame's aim ray (mouse or crosshair), and where it hit the world (world space).
var _aim_from := Vector3.ZERO
var _aim_direction := Vector3.FORWARD
var _hit_point := Vector3.ZERO
## The level's objects indexed for picking (boxes, kinds, a grid), kept in step with its edits.
var index := EditorIndex.new()
## Goes up on every voxel change: the cursor's ray hits voxels.
var _world_version := 0
## What the cursor was last worked out from, and what it came to: the same inputs give the same
## cursor, so _update_cursor skips the work (EditorTool._pick_key).
var _pick_inputs := []
var _pick_outputs := []
## Object being moved / duplicated (a copy with the pending changes), its original id ("" = new),
## and for a duplicate, the id it was copied from.
var _grab := {}
var _grab_id := ""
var _grab_source := ""
## R turns while moving a prop (on a wall, turns from facing out of it).
var _grab_rotation := 0
## The last prop placement (PropPlacement.place) and what it was worked out for.
var _spot := {}
var _spot_key := []
var _invalid_material := StandardMaterial3D.new()
## A pending floating-props check (_warn_floating): when, and where.
var _warn_at := -1.0
var _warn_box := AABB()
## This frame's previews in voxels, for presence_state.
var _cursor_box := AABB()
## The object this person holds a soft lock on while moving or resizing it ("" none).
var _locked := ""
var _preview_box := AABB()
var _ghost_state := {}
## The selected object as its outline was last drawn (LevelView.set_selected).
var _outlined := {}
const WARN_DELAY := 0.4
## 0 none, 1 painting, 2 carving
var _stroke := 0
var _dab_timer := 0.0

var _cursor_lines := MeshInstance3D.new()
var _volume := MeshInstance3D.new()
var _ghost := MeshInstance3D.new()
## The preview box's edges, drawn over everything (its fill is hidden by what's in front, so a room
## dug into rock reads as a hole, not a tower).
var _volume_lines := MeshInstance3D.new()
## A faint grid on the surface under the cursor (builder view).
var _grid := MeshInstance3D.new()
## The Wall tool's preview: the walls being drawn (fill and edges), and their box for presence.
var _wall_fill := MeshInstance3D.new()
var _wall_lines := MeshInstance3D.new()
var _wall_box := AABB()
## The same prisms' corners in voxels, for presence_state.
var _wall_prisms: Array = []
const GRID_RADIUS := 3.0
## The world's limits: its box's edges, and a meter grid on its bottom (in an empty level, the
## ground you build on; the cursor lands on it where there's nothing else).
var _bounds := MeshInstance3D.new()
var _ground := MeshInstance3D.new()
const BOUNDS_COLOR := Color(0.55, 0.75, 1.0, 0.55)
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
	_volume.material_override = volume_material
	_volume_lines.mesh = ImmediateMesh.new()
	_volume_lines.material_override = LevelView._line_material(Color.WHITE)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * GRID_RADIUS * 2.0
	_grid.mesh = plane
	var grid_material := ShaderMaterial.new()
	grid_material.shader = preload("res://shaders/editor_grid.gdshader")
	grid_material.set_shader_parameter("radius", GRID_RADIUS)
	_grid.material_override = grid_material
	_bounds.mesh = ImmediateMesh.new()
	var bounds_material := LevelView._line_material(BOUNDS_COLOR)
	bounds_material.no_depth_test = false # Behind rock in a rock level, so only the open edges show.
	bounds_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bounds.material_override = bounds_material
	_ground.mesh = PlaneMesh.new()
	var ground_material := ShaderMaterial.new()
	ground_material.shader = preload("res://shaders/editor_grid.gdshader")
	ground_material.set_shader_parameter("radius", 1e6) # No fade.
	ground_material.set_shader_parameter("color", Color(BOUNDS_COLOR, 0.32))
	_ground.material_override = ground_material
	_ghost.transparency = 0.45
	_invalid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_invalid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_invalid_material.albedo_color = Color(1.0, 0.25, 0.2, 0.55)
	volume.world = lab.world
	handles.world = lab.world
	build.world = lab.world
	build.view = lab.view
	build.edits = lab.edits
	wall.world = lab.world
	wall.view = lab.view
	wall.edits = lab.edits
	for node in [_wall_fill, _wall_lines]:
		node.mesh = ImmediateMesh.new()
		node.visible = false
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lab.view.add_child.call_deferred(node)
	var wall_fill_material := StandardMaterial3D.new()
	wall_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall_fill_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_wall_fill.material_override = wall_fill_material
	_wall_lines.material_override = LevelView._line_material(Color.WHITE)
	handles.build.call_deferred(lab.view)
	wall_handles.world = lab.world
	wall_handles.build.call_deferred(lab.view)
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
	for node in [_cursor_lines, _volume, _ghost, _volume_lines, _grid, _bounds, _ground] + _size_labels:
		node.visible = false
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lab.view.add_child.call_deferred(node)
	index.lab = lab
	index.attach()
	EditorIndex.current = index
	lab.world.voxels_changed.connect(func(_from: Vector3i, _to: Vector3i) -> void: _world_version += 1)
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
	for node in [_cursor_lines, _volume, _ghost, _volume_lines, _grid, _bounds, _ground, _wall_fill, _wall_lines, camera] + _size_labels:
		if is_instance_valid(node):
			node.queue_free()
	handles.free_meshes()
	wall_handles.free_meshes()
	index.detach()


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
	wall_handles.cancel()
	var object: Dictionary = lab.level.objects.get(id, {})
	handles.room = object if object.get("kind") == "room" else {}
	wall_handles.wall = object if object.get("kind") == "wall" else {}
	lab.view.set_selected(id)
	_outlined = object
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


## Takes the soft lock on an object before moving or resizing it. False (with a toast) when someone
## else has it.
func _hold(id: String) -> bool:
	var holder: int = lab.edits.locked_by_other(id)
	if holder != 0:
		lab.notify("%s is moving that" % Net.players.get(holder, {}).get("name", "Someone"), false)
		return false
	if _locked != id:
		lab.edits.lock(id)
		_locked = id
	return true


func _release() -> void:
	if _locked != "":
		lab.edits.unlock(_locked)
		_locked = ""


## Drops the pending volume / handle / move / stroke.
func cancel() -> void:
	volume.cancel()
	handles.cancel()
	wall_handles.cancel()
	build.cancel()
	wall.cancel()
	_grab = {}
	_grab_id = ""
	_end_stroke()


# --- Per frame -----------------------------------------------------------------------------------

## Something to back out of with Esc: a volume being sized, a move or a stroke.
func has_step() -> bool:
	return volume.is_active() or handles.is_busy() or wall_handles.is_busy() or not _grab.is_empty() or _stroke != 0 or build.dragging or wall.dragging \
			or build.held >= 0


func _process(delta: float) -> void:
	if camera.active != (builder and is_active()):
		_apply_view()
	# The wheel sizes while a tool step has it (in rock levels it also moves a Floor / Ceiling drag's plane).
	camera.zoom_enabled = not volume.is_active() and not handles.is_busy() and not wall_handles.is_busy() and not wall.dragging \
			and not (build.dragging and is_rock_level())
	if not is_active():
		for node in [_cursor_lines, _volume, _ghost, _volume_lines, _grid, _bounds, _ground, _wall_fill, _wall_lines] + _size_labels:
			node.visible = false
		return
	index.sync()
	if not selected.is_empty() and not lab.level.objects.has(selected):
		select("") # Removed by someone else (or undone).
	camera.cut_step = snap()
	_update_storey()
	if not tool in tools():
		set_tool(Tool.SELECT) # Not on this level's rail (Room in a build level).
	_check_floating()
	if _locked != "" and _grab.is_empty() and not handles.is_busy() and not wall_handles.is_busy():
		_release()
	_update_cursor()
	if volume.is_active() and is_aiming():
		volume.aim(_aim_from, _aim_direction)
	_update_build_aim()
	# Keep the handles on the room as it is now (someone else may have changed it); the auto cut
	# opens the selected room.
	var focus := selection()
	camera.focus_ceiling = int(focus.to.y) if focus.get("kind") == "room" else -1
	if not handles.is_busy():
		handles.room = focus if focus.get("kind") == "room" and tool == Tool.SELECT else {}
	handles.update(get_viewport().get_camera_3d(), pointer(), _aim_from, _aim_direction, snap())
	if not wall_handles.is_busy():
		wall_handles.wall = focus if focus.get("kind") == "wall" and tool == Tool.SELECT else {}
	wall_handles.update(get_viewport().get_camera_3d(), pointer(), _aim_from, _aim_direction, snap(), lab.level.objects)
	# A build piece's outline follows it when it changes (resized, someone else's edit).
	if focus != _outlined:
		lab.view.set_selected(selected)
		_outlined = focus
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
	var aiming := is_aiming()
	# Nothing it depends on changed (aim, tool, view, cut, storey, objects, voxels) and nothing else
	# moved the cursor: it's where it was.
	var inputs := _pick_key(from, direction, aiming)
	if inputs == _pick_inputs and _cursor_state() == _pick_outputs:
		return
	_pick_inputs = inputs
	_work_out_cursor(from, direction, aiming)
	_pick_outputs = _cursor_state()


## What the cursor depends on, besides the aim ray (see _update_cursor).
func _pick_key(from: Vector3, direction: Vector3, aiming: bool) -> Array:
	return [from, direction, aiming, tool, _grab_id, builder, free_cursor, free_distance, storey, is_build_level(),
			lab.level.get_instance_id() if lab.level else 0, index.version, _world_version, camera.pick_state(),
			lab.world.global_position]


func _cursor_state() -> Array:
	return [has_cursor, cell, solid_cell, cursor_normal, cursor_on_cap, object_under, _hit_point]


func _work_out_cursor(from: Vector3, direction: Vector3, aiming: bool) -> void:
	var world := lab.world
	object_under = ""
	cursor_on_cap = false
	if not aiming:
		has_cursor = false
		return
	# Cut away with the voxels above the cut.
	var picked := index.pick(from, direction, _grab_id, tool == Tool.SELECT, camera.cut_layer if camera.is_cutting() else -1)
	var object_distance: float = picked.distance
	object_under = picked.id

	if free_cursor and not builder:
		has_cursor = true
		cell = world.world_to_voxel(from + direction * free_distance)
		solid_cell = cell
		cursor_normal = Vector3i.UP
		return
	var hit: Dictionary = camera.raycast(from, direction) if builder else world.raycast(from, direction, REACH)
	if is_build_level():
		# Build mode draws on the active storey's floor: its plane, unless something is in front of it.
		var plane := storey_plane_hit(from, direction)
		if plane.hit and (not hit.hit or plane.distance < hit.distance - 0.01):
			hit = plane
	if not hit.hit:
		hit = _ground_hit(from, direction)
	has_cursor = hit.hit or object_under != ""
	if hit.hit:
		solid_cell = hit.voxel
		_hit_point = from + direction * float(hit.distance)
		cursor_normal = Vector3i(hit.normal)
		cell = hit.voxel + cursor_normal
		cursor_on_cap = hit.get("cap", false)
	# Props and markers aren't voxels while editing; placing on one uses the face of its box.
	if object_under != "" and (not hit.hit or object_distance < hit.distance) and tool in [Tool.PROP, Tool.MARKER, Tool.SELECT]:
		var point := from + direction * object_distance
		var object_box := index.box(object_under)
		cursor_normal = _face_normal(AABB(lab.view.to_world(object_box.position), object_box.size * world.voxel_size), point)
		cell = world.world_to_voxel(point + Vector3(cursor_normal) * 0.05)
		solid_cell = world.world_to_voxel(point - Vector3(cursor_normal) * 0.05)
		cursor_on_cap = false
	elif object_under != "" and hit.hit and hit.distance < object_distance:
		object_under = "" # Behind a wall.
	if tool == Tool.SELECT and object_under == "" and hit.hit:
		object_under = build_under()
		if object_under == "":
			object_under = room_under()


## The tool rail for this level (EditorTool.ROCK_TOOLS or BUILD_TOOLS); the number keys pick by
## place on it.
func tools() -> Array:
	return BUILD_TOOLS if is_build_level() else ROCK_TOOLS


## The material the Floor or Ceiling tool paints.
func _slab_material() -> int:
	return room_ceiling if tool == Tool.CEILING else room_floor


## Floor and Ceiling tools: aim at the storey's floor top or ceiling bottom; the Wall tool at the
## floor top. In rock levels (no storeys) the plane comes from what's aimed at (_update_rock_aim).
func _update_build_aim() -> void:
	_update_wall_aim()
	if not tool in [Tool.FLOOR, Tool.CEILING]:
		build.has_aim = false
		build.cancel()
		return
	build.kind = "ceiling" if tool == Tool.CEILING else "floor"
	if is_rock_level():
		_update_rock_aim(build)
		return
	var st := LevelBuild.storeys(lab.level.objects)
	build.storey = storey
	build.plane_y = LevelBuild.top_y(st, storey) if tool == Tool.CEILING else LevelBuild.floor_y(st, storey)
	if is_aiming():
		build.update_aim(_aim_from, _aim_direction, lab.level.objects, snap())
	elif not build.dragging:
		build.has_aim = false


func _update_wall_aim() -> void:
	if tool != Tool.WALL:
		wall.has_aim = false
		wall.cancel()
		return
	if is_rock_level():
		wall.storey_height = 0
		_update_rock_aim(wall)
	else:
		var st := LevelBuild.storeys(lab.level.objects)
		wall.storey = storey
		wall.plane_y = LevelBuild.floor_y(st, storey)
		wall.storey_height = LevelBuild.storey_height(st, storey)
		if is_aiming():
			wall.update_aim(_aim_from, _aim_direction, lab.level.objects, snap())
		elif not wall.dragging:
			wall.has_aim = false
	wall.update_end(snap())


## Rock levels: builds on what's aimed at (storey -1). The Floor and Wall tools take the floor top
## under the cursor as their plane (and base), the Ceiling tool the underside of what's over that
## floor. A Floor or Ceiling plane held with the wheel (BuildTools.held) stays put instead, its base
## the floor under it. While dragging, the plane stays where the press put it. The aim is where the
## ray meets the plane (on a floor that's the point aimed at; on a wall's face, the point on it).
func _update_rock_aim(aimer: BuildTools) -> void:
	aimer.storey = -1
	if not is_aiming():
		if not aimer.dragging:
			aimer.has_aim = false
		return
	var objects: Dictionary = lab.level.objects
	var surface := _rock_surface()
	var hit := (_hit_point - lab.world.global_position) / lab.world.voxel_size
	if aimer.held >= 0:
		aimer.plane_y = aimer.held
	elif not aimer.dragging:
		if surface.is_empty():
			aimer.has_aim = false
			return
		aimer.plane_y = surface.top
		aimer.base = surface.top
		if aimer == build and tool == Tool.CEILING:
			var over := _ceiling_over(surface.column, surface.top)
			if over < 0:
				aimer.has_aim = false
				return
			aimer.plane_y = over
	aimer.update_aim(_aim_from, _aim_direction, objects, snap())
	if not surface.is_empty() and aimer.held < 0 and (not aimer.has_aim or (not surface.up and not aimer.dragging)):
		aimer.aim_at(Vector2(hit.x, hit.z), objects, snap()) # On a wall's face, or the ray never meets the plane.
	elif aimer.dragging:
		aimer.has_aim = true # The ray left the plane: the drag keeps its last aim.
	if aimer.held >= 0 and not aimer.dragging:
		# A held plane: the floor under it is what the walls snapped to stand on.
		var column := Vector3i(floori(aimer.aim.x), aimer.plane_y, floori(aimer.aim.y))
		aimer.base = aimer.plane_y if tool == Tool.FLOOR else RoomTools.floor_under(lab.world, column)
		aimer.aim_at(aimer.aim, objects, snap())


## Rock levels: the floor under the cursor: {top (voxel y of its top), column (Vector2i), up (aimed
## at the top itself, not a wall or ceiling over it)}; {} when there's none (nothing hit, or the
## cutaway's cross section).
func _rock_surface() -> Dictionary:
	if not has_cursor or cursor_on_cap or not is_aiming():
		return {}
	if cursor_normal == Vector3i.UP:
		return {top = solid_cell.y + 1, column = Vector2i(solid_cell.x, solid_cell.z), up = true}
	return {top = RoomTools.floor_under(lab.world, cell), column = Vector2i(cell.x, cell.z), up = false}


## The bottom of the first solid voxel over a floor top in a column (voxel y), within reach; -1 none.
## skip_walls passes through build walls (the Wall tool's start may be on one).
func _ceiling_over(column: Vector2i, top: int, reach := ROCK_CEILING_REACH, skip_walls := false) -> int:
	var objects: Dictionary = lab.level.objects
	var size_y: int = lab.world.get_size_in_voxels().y
	for y in range(top, mini(top + reach, size_y)):
		var voxel := Vector3i(column.x, y, column.y)
		if lab.world.get_voxel(voxel) == 0:
			continue
		if skip_walls and EditorIndex.wall_at_of(objects, voxel) != "":
			continue
		return y
	return -1


## The height a new wall starts at (voxels): the tool's, or the storey's. In rock levels, up to the
## ceiling over the aim (at most ROCK_WALL_MAX), unless the tool has a height of its own.
func _wall_start_height() -> int:
	if wall_height > 0:
		return wall_height
	if is_rock_level():
		var column := Vector2i(floori(wall.aim.x), floori(wall.aim.y))
		var over := _ceiling_over(column, wall.plane_y, ROCK_WALL_MAX + 1, true)
		return clampi(over - wall.plane_y, 1, ROCK_WALL_MAX) if over > wall.plane_y else LevelBuild.DEFAULT_HEIGHT
	return LevelBuild.storey_height(LevelBuild.storeys(lab.level.objects), storey)


## Rock levels: how high the Floor or Ceiling tool's plane is over the floor under it.
func rock_plane_text() -> String:
	var under := build.base if build.kind == "ceiling" else RoomTools.floor_under(lab.world, Vector3i(floori(build.aim.x), build.plane_y, floori(build.aim.y)))
	var up := build.plane_y - under
	var text := "on the floor" if up == 0 else "%.1f m up" % (up * lab.world.voxel_size)
	return text + (" (held)" if build.held >= 0 else "")


## Ceiling tool's Auto: covers every closed-in room on the storey that has a floor. In rock levels:
## every room closed in by the walls on the floor last aimed at, at the ceiling plane aimed at.
func auto_ceiling() -> void:
	if is_rock_level():
		if build.plane_y <= 0 or build.kind != "ceiling":
			lab.notify("Aim the Ceiling tool at a floor first", false)
			return
		build.storey = -1
	else:
		build.storey = storey
	lab.notify(build.auto_ceiling(lab.level.objects, room_ceiling), false)


## A build mode level (empty): floors, walls and ceilings on storeys.
func is_build_level() -> bool:
	return lab.level != null and lab.level.settings.get("fill", "rock") == "empty"


## A rock level: rooms carved out of rock, and the build tools building on what they aim at.
func is_rock_level() -> bool:
	return lab.level != null and lab.level.settings.get("fill", "rock") == "rock"


## The storey a wall picked at the cursor is preferred on (-1 in rock levels: none).
func _prefer_storey() -> int:
	return storey if is_build_level() else -1


## Floor or Ceiling tool in a rock level: holds the plane a grid step up or down (steps), from where
## it is now. Esc lets it follow the surface again.
func nudge_plane(steps: int) -> void:
	var start := build.held if build.held >= 0 else build.plane_y
	build.held = clampi(start + steps * snap(), 1, lab.world.get_size_in_voxels().y - 1)
	changed.emit()


## The active storey's floor top (voxel y) and the storeys as they are.
func storey_floor() -> int:
	return LevelBuild.floor_y(LevelBuild.storeys(lab.level.objects), storey)


## Where a ray meets the active storey's floor top, inside the world's footprint, as a hit on the
## layer under it (like _ground_hit).
func storey_plane_hit(from: Vector3, direction: Vector3) -> Dictionary:
	var world := lab.world
	var y := world.global_position.y + storey_floor() * world.voxel_size
	if direction.y >= -1e-4 or from.y <= y:
		return {hit = false}
	var distance := (from.y - y) / -direction.y
	var point := from + direction * distance
	var size: Vector3i = world.get_size_in_voxels()
	var voxel: Vector3i = world.world_to_voxel(point + Vector3.UP * 0.01)
	if voxel.x < 0 or voxel.z < 0 or voxel.x >= size.x or voxel.z >= size.z:
		return {hit = false}
	return {hit = true, voxel = Vector3i(voxel.x, voxel.y - 1, voxel.z), normal = Vector3.UP, distance = distance, position = point}


## Keeps the active storey in range (someone else may drop one) and points the camera's cut and
## Page Up / Down at it in build levels.
func _update_storey() -> void:
	if not is_build_level():
		camera.storey_cut = -1
		camera.on_storey_key = Callable()
		return
	var st := LevelBuild.storeys(lab.level.objects)
	storey = clampi(storey, 0, maxi(st.heights.size() - 1, 0))
	# Cut at the top of the walls (the ceiling cut away, so you see in and the cap shows the walls);
	# with the Ceiling tool, over the ceiling, so it shows what is covered.
	camera.storey_cut = LevelBuild.top_y(st, storey) + (int(st.slab) if tool == Tool.CEILING else 0)
	if not camera.on_storey_key.is_valid():
		camera.on_storey_key = change_storey


## Moves to the storey above (step 1) or below (-1). Going past the top adds a storey as tall as the
## top one; coming back down from an empty top storey drops it again.
func change_storey(step: int) -> void:
	var objects: Dictionary = lab.level.objects
	var st: Dictionary = LevelBuild.storeys(objects).duplicate(true)
	var count: int = st.heights.size()
	var target := storey + step
	if target < 0:
		return
	if target >= count:
		st.heights.append(LevelBuild.storey_height(st, count - 1) if count > 0 else LevelBuild.DEFAULT_HEIGHT)
		lab.edits.put_object(st, LevelBuild.STOREYS_ID if objects.has(LevelBuild.STOREYS_ID) else "")
		lab.notify("Storey %d (new)" % (target + 1), false)
	elif step < 0 and storey == count - 1 and storey > 0 and storey_is_empty(storey):
		st.heights.resize(count - 1)
		lab.edits.put_object(st, LevelBuild.STOREYS_ID)
		lab.notify("Storey %d" % (target + 1), false)
	else:
		lab.notify("Storey %d" % (target + 1), false)
	storey = target
	# The camera looks at the storey's floor.
	camera.pivot.y = lab.world.global_position.y + LevelBuild.floor_y(st, storey) * lab.world.voxel_size
	cancel()
	changed.emit()


## Nothing on the storey: no walls, and no floor or ceiling shapes.
func storey_is_empty(index: int) -> bool:
	var objects: Dictionary = lab.level.objects
	for kind in ["floor", "ceiling"]:
		if not objects.get(LevelBuild.slab_id(kind, index), {}).get("shapes", []).is_empty():
			return false
	for object: Dictionary in objects.values():
		if object.kind == "wall" and int(object.storey) == index:
			return false
	return true


## Sets the active storey's wall height (voxels): the walls that follow it and the storeys above move.
func set_storey_height(voxels: int) -> void:
	var objects: Dictionary = lab.level.objects
	var st: Dictionary = LevelBuild.storeys(objects).duplicate(true)
	while st.heights.size() <= storey:
		st.heights.append(LevelBuild.DEFAULT_HEIGHT)
	if int(st.heights[storey]) == voxels or voxels < 1:
		return
	st.heights[storey] = voxels
	lab.edits.put_object(st, LevelBuild.STOREYS_ID if objects.has(LevelBuild.STOREYS_ID) else "")


## Where a ray that hit nothing meets the world's bottom (the ground of an empty level), as a hit on
## the layer under it: the cell above is in the world, the "solid" one just outside it.
func _ground_hit(from: Vector3, direction: Vector3) -> Dictionary:
	var world := lab.world
	var bottom := world.global_position.y
	if direction.y >= -1e-4 or from.y <= bottom:
		return {hit = false}
	var distance := (from.y - bottom) / -direction.y
	if builder and camera.is_cutting() and camera.cut_y() <= bottom:
		return {hit = false}
	var point := from + direction * distance
	var size: Vector3i = world.get_size_in_voxels()
	var voxel: Vector3i = world.world_to_voxel(point + Vector3.UP * 0.01)
	if voxel.x < 0 or voxel.z < 0 or voxel.x >= size.x or voxel.z >= size.z:
		return {hit = false}
	return {hit = true, voxel = Vector3i(voxel.x, -1, voxel.z), normal = Vector3.UP, distance = distance, position = point}


## The outward normal of the box face nearest a point on it.
static func _face_normal(box: AABB, point: Vector3) -> Vector3i:
	var best := INF
	var normal := Vector3i.UP
	for a in 3:
		for side in [-1, 1]:
			var face: float = box.position[a] if side < 0 else box.end[a]
			var distance := absf(point[a] - face)
			if distance < best:
				best = distance
				normal = Vector3i.ZERO
				normal[a] = side
	return normal


## The room the cursor is in (the air in front of the aimed surface is inside it) or on (the aimed
## voxel is in its lining); the newest wins. "" when none.
func room_under() -> String:
	var inside_best := ""
	var lining_best := ""
	var inside_order := -1
	var lining_order := -1
	var air := Vector3(cell) + Vector3.ONE * 0.5
	var wall := Vector3(solid_cell) + Vector3.ONE * 0.5
	index.sync()
	for object: Dictionary in index.of_kind("room").values():
		var order := int(object.order)
		if LevelSchema.box_of(object).has_point(air) and order > inside_order:
			inside_best = object.id
			inside_order = order
		elif LevelSchema.room_outer(object).has_point(wall) and order > lining_order:
			lining_best = object.id
			lining_order = order
	return inside_best if inside_best != "" else lining_best


## The wall (or opening in a wall) under the cursor, for the Select tool; "" none.
func build_under() -> String:
	var objects: Dictionary = lab.level.objects
	for voxel in [cell, solid_cell]:
		var id := EditorIndex.opening_at_of(objects, voxel)
		if id != "":
			return id
	return EditorIndex.wall_at_of(objects, solid_cell, _prefer_storey())


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
	if tool == Tool.ROOM and not _starts_on_solid(carve):
		start.y = maxi(start.y, room_thickness) # On the world's bottom: room for the floor under it.
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
		if event.button_index == MOUSE_BUTTON_LEFT and wall_handles.is_busy() and is_active():
			var done := wall_handles.release(pointer())
			if not done.is_empty():
				_commit_wall_change(done)
		if event.button_index == MOUSE_BUTTON_LEFT and build.dragging and is_active():
			var toast := build.release(lab.level.objects, _slab_material())
			if toast != "":
				lab.notify(toast, false)
			changed.emit()
		if event.button_index == MOUSE_BUTTON_LEFT and wall.dragging and is_active():
			var said := wall.finish(lab.level.objects, room_wall, wall_thickness, wall_inner, wall_slabs, room_floor, room_ceiling)
			if said != "":
				lab.notify(said, false)
			changed.emit()


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
	if wall_handles.is_busy() and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		wall_handles.nudge(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
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
	# Drawing a wall: the wheel sets its height.
	if wall.dragging and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		wall.nudge_height(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1, snap())
		get_viewport().set_input_as_handled()
		return
	# Floor or Ceiling in a rock level: the wheel while dragging, or Ctrl+wheel any time, raises or
	# lowers the plane (the wheel alone zooms otherwise).
	if tool in [Tool.FLOOR, Tool.CEILING] and is_rock_level() and (build.dragging or event.ctrl_pressed) and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and (build.has_aim or build.held >= 0):
		nudge_plane(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
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
	if event.button_index == MOUSE_BUTTON_LEFT and tool == Tool.SELECT and _grab.is_empty() and handles.hover != Vector3i.ZERO \
			and not handles.is_busy() and not _hold(handles.room.get("id", "")):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and tool == Tool.SELECT and _grab.is_empty() and handles.press(pointer(), _aim_from, _aim_direction):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and tool == Tool.SELECT and _grab.is_empty() and wall_handles.hover != WallHandles.Handle.NONE \
			and not wall_handles.is_busy() and not _hold(wall_handles.wall.get("id", "")):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and tool == Tool.SELECT and _grab.is_empty() and wall_handles.press(pointer(), _aim_from, _aim_direction):
		return
	if tool in [Tool.FLOOR, Tool.CEILING] and event.button_index == MOUSE_BUTTON_LEFT and not event.alt_pressed:
		build.press(event.shift_pressed)
		changed.emit()
	elif tool == Tool.WALL and event.button_index == MOUSE_BUTTON_LEFT and not event.alt_pressed:
		wall.begin(event.shift_pressed, event.ctrl_pressed, _wall_start_height())
		changed.emit()
	elif event.alt_pressed and event.button_index == MOUSE_BUTTON_LEFT:
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
	if wall.dragging and _wall_key(event):
		return true
	var rail := tools()
	for i in mini(SLOT_ACTIONS.size(), rail.size()):
		if InputSetup.pressed(event, SLOT_ACTIONS[i]):
			set_tool(rail[i])
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
		editor_edit_hidden = toggle_edit_hidden,
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
		var box := LevelBuild.box_of(lab.level.objects[selected], lab.level.objects)
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
				var spot := prop_spot(prop_name, facing, "")
				if not spot.valid:
					lab.notify("Can't place it: " + spot.reason, false)
					return
				lab.edits.put_object(_placed(LevelSchema.new_prop(prop_name, spot.origin, spot.facing), spot))
			else:
				_commit_move()
		Tool.MARKER:
			var marker := LevelSchema.new_marker(marker_type, _marker_position(marker_type), _view_yaw())
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
			lab.edits.voxel_op(_seen({type = "box", from = box[0], to = box[1], material = VoxelMaterials.AIR if _volume_carve else material}))
		Tool.ROOM:
			lab.edits.put_object(LevelSchema.new_room(box[0], box[1], room_floor, room_wall, room_ceiling, room_thickness,
					LevelStructure.next_order(lab.level.objects)))
		Tool.REPLACE:
			if _replace_source != 0:
				lab.edits.voxel_op(_seen({type = "replace", from = box[0], to = box[1], material = material, source = _replace_source}))
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
	if wall.dragging:
		wall.next_size()
	else:
		volume.cycle_axis()
	changed.emit()


## Keys while drawing a wall: digits, "." and "v" type its length (or height, after Tab);
## Backspace erases; Enter keeps it.
func _wall_key(event: InputEventKey) -> bool:
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
	elif code == KEY_V and wall.typed != "":
		character = "v"
	if character != "":
		wall.type_char(character)
	elif code == KEY_BACKSPACE and wall.typed != "":
		wall.erase_char()
	elif code in [KEY_ENTER, KEY_KP_ENTER]:
		wall.apply_typed()
	else:
		return false
	changed.emit()
	return true


## The sized volume for the HUD's readout, as BBCode ("" when not sizing): name, the three sizes in
## meters (the active one highlighted, with what's being typed) and in voxels.
func volume_readout() -> String:
	var box := {}
	var muted := PaperPalette.INK_MUTED.to_html(false)
	var editing_wall := {}
	if wall_handles.is_busy() and not wall_handles.result.is_empty():
		if not wall_handles.result.valid:
			return "[b]Wall[/b]   [color=#%s]%s[/color]" % [PaperPalette.DANGER.to_html(false), wall_handles.result.reason]
		editing_wall = wall_handles.result.walls[0]
	elif _grab.get("kind") == "wall" and has_cursor:
		editing_wall = _grab.duplicate()
		_place_grab(editing_wall)
	if not editing_wall.is_empty():
		var title := "Wall" if wall_handles.is_busy() else ("Duplicate wall" if _grab_id == "" else "Move wall")
		return "[b]%s[/b]   %.1f m long   [color=#%s](%.0f voxels)[/color]" % [title, LevelBuild.wall_length(editing_wall) * lab.world.voxel_size,
				muted, LevelBuild.wall_length(editing_wall)]
	if handles.is_busy() and not handles.resized.is_empty():
		box = handles.resized
	elif LevelSchema.is_structure(_grab) and has_cursor and _grab.kind != "wall":
		box = _grab.duplicate()
		_place_grab(box)
	if not box.is_empty():
		var size: Vector3i = box.to - box.from
		var meters := Vector3(size) * lab.world.voxel_size
		var title := "Resize room" if handles.is_busy() else ("Duplicate " if _grab_id == "" else "Move ") + str(box.kind)
		return "[b]%s[/b]   %.1f × %.1f × %.1f m   [color=#%s](%d × %d × %d voxels)[/color]" % [title, meters.x, meters.z, meters.y,
				PaperPalette.INK_MUTED.to_html(false), size.x, size.z, size.y]
	if wall.dragging:
		var drawn := wall.segments()
		var what := "Erase walls" if wall.erase else ("Room of walls" if wall.rect_mode else "Wall")
		var voxel := lab.world.voxel_size
		var accent := PaperPalette.ACCENT.to_html(false)
		if wall.rect_mode:
			var r := Vector2(wall.end - wall.start).abs() * voxel
			return "[b]%s[/b]   %.1f × %.1f m, %.1f m tall" % [what, r.x, r.y, wall.height * voxel]
		var length_text := (wall.typed + "_") if wall.typed != "" and not wall.typing_height else "%.1f" % (wall.length() * voxel)
		var height_text := (wall.typed + "_") if wall.typed != "" and wall.typing_height else "%.1f" % (wall.height * voxel)
		if wall.typing_height:
			height_text = "[color=#%s][b][u]%s[/u][/b][/color]" % [accent, height_text]
		else:
			length_text = "[color=#%s][b][u]%s[/u][/b][/color]" % [accent, length_text]
		if drawn.is_empty() and wall.typed == "":
			return "[b]%s[/b]   drag out the wall  ·  wheel: height  ·  type: length" % what
		return "[b]%s[/b]   %s m long × %s m tall   [color=#%s](%.0f × %d voxels)[/color]" % [what, length_text, height_text,
				PaperPalette.INK_MUTED.to_html(false), wall.length(), wall.height]
	if build.dragging:
		var r := build.rect()
		var area := Vector2(r.size) * lab.world.voxel_size
		var what := ("Erase " + build.kind) if build.erase else build.kind.capitalize()
		if build.storey < 0:
			what += ", " + rock_plane_text()
		if r.size.x == 0 and r.size.y == 0:
			return "[b]%s[/b]   release to fill the walls around it, or drag an area" % what
		return "[b]%s[/b]   %.1f × %.1f m   [color=#%s](%d × %d voxels)[/color]" % [what, area.x, area.y, PaperPalette.INK_MUTED.to_html(false), r.size.x, r.size.y]
	if build.held >= 0 and tool in [Tool.FLOOR, Tool.CEILING]:
		return "[b]%s[/b]   %s   [color=#%s]Ctrl+wheel: up / down  ·  Esc: back to the surface[/color]" % [build.kind.capitalize(),
				rock_plane_text(), PaperPalette.INK_MUTED.to_html(false)]
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
		lab.edits.voxel_op(_seen({type = "box", from = target - half, to = target + half + Vector3i.ONE, material = paint}))
	else:
		lab.edits.voxel_op(_seen({type = "sphere", center = Vector3(target) + Vector3.ONE * 0.5, radius = float(brush_size), material = paint}))


func toggle_edit_hidden() -> void:
	edit_hidden = not edit_hidden
	lab.notify("Above the cut: editable" if edit_hidden else "Above the cut: locked", false)
	changed.emit()


## A voxel op kept below the cut (WorldSync's "below") while the cutaway hides what's above it,
## unless edit_hidden.
func _seen(op: Dictionary) -> Dictionary:
	if builder and camera.is_cutting() and not edit_hidden:
		op.below = camera.cut_layer
	return op


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
		var picked := lab.world.get_voxel(solid_cell)
		if tool == Tool.WALL and _on_inner_face(solid_cell, picked):
			wall_inner = picked
			lab.notify("Inner face: " + VoxelMaterials.get_material_name(picked), false)
			changed.emit()
			return
		if tool == Tool.WALL:
			room_wall = picked
		elif tool == Tool.FLOOR:
			room_floor = picked
		elif tool == Tool.CEILING:
			room_ceiling = picked
		else:
			material = picked
		lab.notify("Material: " + VoxelMaterials.get_material_name(picked), false)
	changed.emit()


## Whether a voxel is on the inner (left) face of a build wall that has one, in that face's material.
func _on_inner_face(voxel: Vector3i, picked: int) -> bool:
	var objects: Dictionary = lab.level.objects
	var id := EditorIndex.wall_at_of(objects, voxel, _prefer_storey())
	if id == "":
		return false
	var wall_object: Dictionary = objects[id]
	return int(wall_object.inner) > 0 and picked == int(wall_object.inner) and int(wall_object.thickness) >= 2 \
			and LevelBuild.across_of(wall_object, Vector2(voxel.x + 0.5, voxel.z + 0.5)) < 0.0


func _rotate() -> void:
	if LevelSchema.is_structure(_grab) or (tool == Tool.SELECT and LevelSchema.is_structure(selection())):
		return # Rooms and openings don't turn (yet).
	if _grab.get("kind") == "prop":
		_grab_rotation = (_grab_rotation + 1) % 4
	elif not _grab.is_empty():
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
	if object.get("kind") == "wall":
		lab.edits.put_objects(WallHandles.removal(lab.level.objects, object))
		_warn_floating(LevelBuild.box_of(object, lab.level.objects))
	elif object.get("kind") == "room":
		# The room fills back in, with its openings; door props in its walls go too.
		var puts: Array = [[selected, {}]]
		for other: Dictionary in lab.level.objects.values():
			if other.kind == "opening" and other.room == selected:
				puts.append([other.door if other.door != "" and lab.level.objects.has(other.door) else other.id, {}])
		lab.edits.put_objects(puts)
		_warn_floating(LevelSchema.room_outer(object))
	else:
		lab.edits.remove_object(selected)
	select("")


func _start_move() -> void:
	if selected == "" or not _hold(selected):
		return
	_grab = lab.level.objects[selected].duplicate()
	_grab_id = selected
	_grab_rotation = _start_rotation(_grab)


## A moved prop keeps its facing on floors; on walls it starts facing out of them.
func _start_rotation(object: Dictionary) -> int:
	if object.get("kind") != "prop" or PropCatalog.mount_of(object.name) in ["wall", "door"]:
		return 0
	return int(object.facing)


## The R turns to place the grabbed prop with at the cursor. An "any" prop aimed at a wall faces out
## of it (PropPlacement adds the turns to the wall's facing), so there only the turns pressed since
## the grab count, not the facing it had on a floor or ceiling.
func _grab_turns() -> int:
	if _grab.get("kind") == "prop" and PropCatalog.mount_of(str(_grab.name)) == "any" and cursor_normal.y == 0 and cursor_normal != Vector3i.ZERO:
		return posmod(_grab_rotation - _start_rotation(_grab), 4)
	return _grab_rotation


func _duplicate() -> void:
	if selected == "":
		return
	_grab = lab.level.objects[selected].duplicate()
	_grab.id = ""
	_grab_id = ""
	_grab_source = selected
	_grab_rotation = _start_rotation(_grab)


## Puts the moved / duplicated object where the cursor is. A room takes its openings, doors and
## (move_contents) what's inside along.
func _commit_move() -> void:
	var object := _grab.duplicate()
	_place_grab(object)
	if object.kind == "wall":
		var objects: Dictionary = lab.level.objects
		var e := LevelBuild.ends(object)
		if _grab_id != "" and objects.has(_grab_id):
			var was: Dictionary = objects[_grab_id]
			var change := WallHandles.reshape(objects, was, e[0], e[1], e[0] - LevelBuild.ends(was)[0], false)
			lab.edits.put_objects(change.puts)
		elif objects.has(_grab_source):
			object.erase("id")
			var puts: Array = [["", object]]
			for opening in LevelBuild.openings_in(objects, _grab_source):
				var copy := opening.duplicate()
				copy.erase("id")
				copy.wall = "$0"
				puts.append(["", copy])
			lab.edits.put_objects(puts)
		cancel()
		return
	if object.kind == "room":
		var objects: Dictionary = lab.level.objects
		if _grab_id != "" and objects.has(_grab_id):
			lab.edits.put_objects(RoomTools.carry(objects, objects[_grab_id], object, move_contents))
			_warn_floating(LevelSchema.room_outer(objects[_grab_id]).merge(LevelSchema.room_outer(object)))
		elif objects.has(_grab_source):
			var source: Dictionary = objects[_grab_source]
			lab.edits.put_objects(RoomTools.duplicate(objects, source, object.from - source.from, move_contents))
	elif object.kind == "prop":
		var spot := prop_spot(object.name, _grab_turns(), _grab_id)
		if not spot.valid:
			lab.notify("Can't put it there: " + spot.reason, false)
			return
		lab.edits.put_object(object, _grab_id)
	else:
		lab.edits.put_object(object, _grab_id)
	cancel()


func _place_grab(object: Dictionary) -> void:
	match object.kind:
		"prop":
			_placed(object, prop_spot(object.name, _grab_turns(), _grab_id))
		"wall":
			# Its start on the grid point under the cursor (on the active storey's floor; in a rock
			# level, standing on the floor aimed at).
			var s := snap()
			var e := LevelBuild.ends(object)
			var start := Vector2i(roundi(cell.x / float(s)) * s, roundi(cell.z / float(s)) * s)
			var offset := start - e[0]
			object.a = Vector3i(start.x, 0, start.y)
			object.b = Vector3i(e[1].x + offset.x, 0, e[1].y + offset.y)
			var surface := _rock_surface() if int(object.storey) < 0 else {}
			if not surface.is_empty():
				object.base = surface.top
		"room", "opening":
			# Centered on the cursor; it stands on the floor there, or keeps its height over cut rock.
			var size: Vector3i = object.to - object.from
			var corner := snapped_cell(cell - Vector3i(size.x / 2, 0, size.z / 2))
			var y: int = cell.y if cursor_normal == Vector3i.UP and not cursor_on_cap and object.kind == "room" else object.from.y
			object.from = Vector3i(corner.x, y, corner.z)
			object.to = object.from + size
		_:
			object.position = _marker_position(object.type)


## Drops a resized room: one edit with the openings (and doors) in the walls that moved.
func _commit_resize(resized: Dictionary) -> void:
	var objects: Dictionary = lab.level.objects
	if not objects.has(resized.id) or resized == objects[resized.id]:
		return
	lab.edits.put_objects(RoomTools.carry(objects, objects[resized.id], resized, false))
	_warn_floating(LevelSchema.room_outer(objects[resized.id]).merge(LevelSchema.room_outer(resized)))


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
	var on_wall := wall_opening_at_cursor()
	if not on_wall.is_empty():
		return on_wall
	var room_id := EditorIndex.room_at_of(objects, AABB(Vector3(solid_cell) + Vector3.ONE * 0.25, Vector3.ONE * 0.5))
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
	if at.has("wall"):
		if at.has("reason"):
			lab.notify(at.reason, false)
			return
		lab.edits.put_object(LevelSchema.new_wall_opening(at.wall, at.along, at.width, at.sill, at.height, opening_type))
		return
	lab.edits.put_object(LevelSchema.new_opening(at.from, at.to, at.room, opening_type))


## Opening tool on a build wall: the opening it would cut there (LevelSchema.new_wall_opening's
## fields, with `wall`), centered on the cursor along the wall on the grid; {} when the cursor isn't
## on a wall; with `reason` when it doesn't fit.
func wall_opening_at_cursor() -> Dictionary:
	var objects: Dictionary = lab.level.objects
	var wall_id := EditorIndex.wall_at_of(objects, solid_cell, _prefer_storey())
	if wall_id == "":
		return {}
	var on: Dictionary = objects[wall_id]
	var st := LevelBuild.storeys(objects)
	var length := LevelBuild.wall_length(on)
	var height := LevelBuild.wall_height(on, st)
	var floor_top := LevelBuild.wall_base(on, st)
	var out := {wall = wall_id, width = opening_width, height = mini(opening_height, height), along = 0, sill = 0}
	if length < opening_width:
		out.reason = "The wall is shorter than the opening"
		return out
	var center := LevelBuild.along_of(on, Vector2(solid_cell.x + 0.5, solid_cell.z + 0.5))
	var s := snap()
	out.along = clampi(roundi((center - opening_width * 0.5) / s) * s, 0, floori(length) - opening_width)
	match opening_type:
		"window":
			out.sill = opening_sill
		"hole":
			out.sill = maxi(solid_cell.y - floor_top - opening_height / 2, 0)
	out.sill = clampi(out.sill, 0, maxi(height - 1, 0))
	out.height = mini(opening_height, height - out.sill)
	return out


## Where a prop would go at the cursor (PropPlacement.place), worked out once per change of aim.
func prop_spot(name: String, rotation: int, ignore: String) -> Dictionary:
	var key := [name, rotation, ignore, cell, solid_cell, cursor_normal, snap(), lab.level.objects.size()]
	if key != _spot_key:
		_spot_key = key
		_spot = PropPlacement.place(lab.world, lab.level.objects, name, rotation, cell, solid_cell, cursor_normal, snap(), ignore)
		# A sliding door needs a straight wall; in a 45° one its panel would cut across the steps.
		if _spot.valid and _spot.mount == "door":
			var wall_id := EditorIndex.wall_at_of(lab.level.objects, solid_cell, _prefer_storey())
			if wall_id != "":
				var step := LevelBuild.ends(lab.level.objects[wall_id])
				if step[0].x != step[1].x and step[0].y != step[1].y:
					_spot.valid = false
					_spot.reason = "doors go in straight walls"
	return _spot


## The prop at a placement: its origin and facing, and for doors the wall around it and the slide.
func _placed(prop: Dictionary, spot: Dictionary) -> Dictionary:
	prop.origin = spot.origin
	prop.facing = spot.facing
	for key in ["door_ahead", "door_behind", "door_offset"]:
		if spot.has(key):
			prop[key] = spot[key]
	return prop


## Markers that stand somewhere (spawns, clone vats, horde spawners) go to the floor under the
## cursor; the rest go where it points.
const FLOOR_MARKERS := ["spawn", "clone_vat", "horde"]


func _marker_position(type := "") -> Vector3:
	var s := snap()
	var snapped := snapped_cell(cell)
	var y := RoomTools.floor_under(lab.world, cell) if type in FLOOR_MARKERS else cell.y
	return Vector3(snapped.x + s * 0.5, y, snapped.z + s * 0.5) if s > 1 else Vector3(cell.x + 0.5, y, cell.z + 0.5)


## After a room changed: in a moment (once the host has applied it), a toast if props in the box
## (voxels) were left floating or inside something.
func _warn_floating(box: AABB) -> void:
	_warn_box = box if _warn_at < 0.0 else _warn_box.merge(box)
	_warn_at = Time.get_ticks_msec() / 1000.0 + WARN_DELAY


func _check_floating() -> void:
	if _warn_at < 0.0 or Time.get_ticks_msec() / 1000.0 < _warn_at:
		return
	_warn_at = -1.0
	var found := PropPlacement.problems(lab.world, lab.level.objects, _warn_box)
	if not found.is_empty():
		lab.notify("%d prop%s left floating or inside a wall (Select: Check level)" % [found.size(), "" if found.size() == 1 else "s"], false)


## What this person is doing, for everyone else (EditorPresence): the view and builder camera, the
## cursor box, the preview box or prop ghost (voxels), the selection.
func presence_state() -> Dictionary:
	var out := {builder = builder, selected = selected, storey = storey}
	if builder:
		out.camera = camera.camera.global_transform
		out.pivot = camera.pivot
	if _cursor_lines.visible and _cursor_box.has_volume():
		out.cursor = _cursor_box
	if _volume.visible:
		out.preview = _preview_box
	if _ghost.visible and not _ghost_state.is_empty():
		out.ghost = _ghost_state
	if _wall_fill.visible and _wall_box.has_volume():
		out.erase("preview")
		out.prisms = _wall_prisms.map(func(c: Array) -> PackedVector3Array: return PackedVector3Array(c))
	return out


## The builder view's grid: on the floor under the cursor (or the floor being sized), at the snap.
func _update_grid() -> void:
	var sizing_floor := volume.is_active() and volume.step == VolumeSteps.Step.FLOOR
	var on_plane := (build.has_aim and tool in [Tool.FLOOR, Tool.CEILING]) or (wall.has_aim and tool == Tool.WALL)
	_grid.visible = builder and (sizing_floor or on_plane or (has_cursor and cursor_normal == Vector3i.UP and tool != Tool.SELECT and tool != Tool.BRUSH))
	if not _grid.visible:
		return
	var center: Vector3 = lab.view.to_world(Vector3(cell) + Vector3(0.5, 0.0, 0.5))
	var y := volume.plane_y() if sizing_floor else center.y
	if on_plane:
		var aimer: BuildTools = wall if tool == Tool.WALL else build
		y = lab.view.to_world(Vector3(0, aimer.plane_y, 0)).y
		center = lab.view.to_world(Vector3(aimer.aim.x, aimer.plane_y, aimer.aim.y))
	if sizing_floor:
		var ray_y := _aim_direction.y
		if absf(ray_y) > 1e-4:
			var t := (y - _aim_from.y) / ray_y
			if t > 0.0:
				center = _aim_from + _aim_direction * t
	_grid.global_position = Vector3(center.x, y + 0.003, center.z)
	var material := _grid.material_override as ShaderMaterial
	material.set_shader_parameter("origin", lab.world.global_position)
	material.set_shader_parameter("spacing", snap() * lab.world.voxel_size)
	material.set_shader_parameter("center", center)


## Floor and Ceiling tools: the area being dragged, at the slab it paints (red when erasing), and
## what the aim snaps to.
func _update_build_preview() -> void:
	if not tool in [Tool.FLOOR, Tool.CEILING] or not build.has_aim:
		return
	var st := LevelBuild.storeys(lab.level.objects)
	var y := LevelBuild.slab_range(build.kind, build.storey, st, build.plane_y)
	if build.storey < 0:
		# Rock levels: how high the plane is over the floor under it.
		var label := _size_labels[1]
		label.text = rock_plane_text()
		label.modulate = LABEL_ACTIVE_COLOR if build.held >= 0 else LABEL_COLOR
		label.font_size = 24
		label.position = lab.view.to_world(Vector3(build.aim.x, build.plane_y + 4, build.aim.y))
		label.visible = true
	if build.dragging:
		var r := build.rect()
		var color := Color(1.0, 0.3, 0.3) if build.erase else (Color(0.85, 0.9, 1.0) if build.kind == "ceiling" else Color(0.3, 0.6, 1.0))
		(_volume.material_override as StandardMaterial3D).albedo_color = Color(color, 0.3)
		var box := AABB(Vector3(r.position.x, y.x, r.position.y), Vector3(maxi(r.size.x, 1), y.y - y.x, maxi(r.size.y, 1)))
		var size := box.size * lab.world.voxel_size
		_volume.scale = size
		_volume.position = lab.view.to_world(box.position) + size * 0.5
		_volume.visible = true
		_preview_box = box
		if r.size.x > 0 and r.size.y > 0:
			_place_size_labels(AABB(lab.view.to_world(box.position), size), -1, false)
	elif build.snapped_to != "grid":
		var label := _size_labels[0]
		label.text = build.snapped_to
		label.modulate = LABEL_ACTIVE_COLOR
		label.font_size = 22
		label.position = lab.view.to_world(Vector3(build.snapped.x, build.plane_y + 2, build.snapped.y))
		label.visible = true


## Wall tool: the walls being drawn as see-through prisms with their edges (red when erasing), their
## length and height, and what the aim snaps to.
func _update_wall_preview() -> void:
	_wall_fill.visible = false
	_wall_lines.visible = false
	_wall_box = AABB()
	_wall_prisms = []
	if tool != Tool.WALL or not wall.has_aim:
		return
	var drawn := wall.segments()
	if drawn.is_empty():
		if wall.snapped_to != "grid" and not wall.dragging or (wall.dragging and wall.snapped_to != "grid"):
			_snap_label(wall.snapped, wall.plane_y, wall.snapped_to)
		return
	var color := Color(1.0, 0.3, 0.3) if wall.erase else Color(0.3, 0.6, 1.0)
	var thickness := wall_thickness if not wall.erase else 2
	var y0 := wall.plane_y
	var y1 := wall.plane_y + wall.height
	(_wall_fill.material_override as StandardMaterial3D).albedo_color = Color(color, 0.3)
	(_wall_lines.material_override as StandardMaterial3D).albedo_color = Color(color, 0.9)
	var fill := _wall_fill.mesh as ImmediateMesh
	var lines := _wall_lines.mesh as ImmediateMesh
	fill.clear_surfaces()
	lines.clear_surfaces()
	fill.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for segment: Array in drawn:
		var corners := _wall_corners(segment[0], segment[1], thickness, y0, y1)
		_wall_prisms.append(LevelBuild.prism_corners(Vector2(segment[0]), Vector2(segment[1]), thickness, y0, y1, thickness * 0.5))
		for quad in [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]:
			for i in [0, 1, 2, 0, 2, 3]:
				fill.surface_add_vertex(corners[quad[i]])
		for edge in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
			lines.surface_add_vertex(corners[edge[0]])
			lines.surface_add_vertex(corners[edge[1]])
		var lo := Vector2(segment[0]).min(Vector2(segment[1])) - Vector2.ONE * (thickness * 0.5 + 1.0)
		var hi := Vector2(segment[0]).max(Vector2(segment[1])) + Vector2.ONE * (thickness * 0.5 + 1.0)
		var box := AABB(Vector3(lo.x, y0, lo.y), Vector3(hi.x - lo.x, y1 - y0, hi.y - lo.y))
		_wall_box = box if not _wall_box.has_volume() else _wall_box.merge(box)
	fill.surface_end()
	lines.surface_end()
	_wall_fill.visible = true
	_wall_lines.visible = true
	# Length along the (first) wall's middle, height at its end.
	var a: Vector2i = drawn[0][0]
	var b: Vector2i = drawn[0][1]
	var voxel := lab.world.voxel_size
	var labels := [
		[(Vector2(a) + Vector2(b)) * 0.5, y0, "%.1f m" % (Vector2(b - a).length() * voxel), not wall.typing_height],
		[Vector2(b), (y0 + y1) * 0.5, "%.1f m" % (wall.height * voxel), wall.typing_height],
	]
	for i in labels.size():
		var spot: Array = labels[i]
		var label := _size_labels[i]
		label.text = (wall.typed + "_") if spot[3] and wall.typed != "" else spot[2]
		label.modulate = LABEL_ACTIVE_COLOR if spot[3] else LABEL_COLOR
		label.font_size = 28 if spot[3] else 24
		label.position = lab.view.to_world(Vector3(spot[0].x, spot[1], spot[0].y))
		label.visible = true
	if wall.snapped_to != "grid" and not wall.rect_mode and wall.end == wall.snapped:
		_snap_label(wall.snapped, wall.plane_y, wall.snapped_to)


## Walls being reshaped (handles) or moved, and the Opening tool's cut in a wall, as see-through
## prisms on the Wall tool's preview meshes (red when it can't be done).
func _update_wall_edit_preview() -> void:
	var objects: Dictionary = lab.level.objects
	var prisms: Array = []
	var color := Color(0.3, 0.6, 1.0)
	if wall_handles.is_busy() and not wall_handles.result.is_empty():
		for changed_wall: Dictionary in wall_handles.result.walls:
			prisms.append(LevelBuild.corners_of(changed_wall, objects))
		if not wall_handles.result.valid:
			color = Color(1.0, 0.3, 0.3)
	elif _grab.get("kind") == "wall" and has_cursor:
		var moved := _grab.duplicate()
		_place_grab(moved)
		prisms.append(LevelBuild.corners_of(moved, objects))
	elif tool == Tool.OPENING:
		var at := wall_opening_at_cursor()
		if not at.is_empty():
			var opening := LevelSchema.new_wall_opening(at.wall, at.along, at.width, at.sill, at.height)
			prisms.append(LevelBuild.corners_of(opening, objects))
			color = Color(1.0, 0.3, 0.3) if at.has("reason") else Color(1.0, 0.6, 0.2)
	if prisms.is_empty():
		return
	(_wall_fill.material_override as StandardMaterial3D).albedo_color = Color(color, 0.3)
	(_wall_lines.material_override as StandardMaterial3D).albedo_color = Color(color, 0.9)
	var fill := _wall_fill.mesh as ImmediateMesh
	var lines := _wall_lines.mesh as ImmediateMesh
	fill.clear_surfaces()
	lines.clear_surfaces()
	fill.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	_wall_box = AABB()
	_wall_prisms = prisms
	for voxel_corners: Array in prisms:
		var corners: Array[Vector3] = []
		for c: Vector3 in voxel_corners:
			corners.append(lab.view.to_world(c))
			_wall_box = AABB(c, Vector3.ZERO) if _wall_box.size == Vector3.ZERO and _wall_box.position == Vector3.ZERO else _wall_box.expand(c)
		for quad in [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]:
			for i in [0, 1, 2, 0, 2, 3]:
				fill.surface_add_vertex(corners[quad[i]])
		for edge in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
			lines.surface_add_vertex(corners[edge[0]])
			lines.surface_add_vertex(corners[edge[1]])
	fill.surface_end()
	lines.surface_end()
	_wall_fill.visible = true
	_wall_lines.visible = true


## Drops a wall's handle: one edit with the walls joined to it, their openings and its doors.
func _commit_wall_change(done: Dictionary) -> void:
	if not done.valid:
		lab.notify(done.reason, false)
		return
	if done.puts.is_empty():
		return
	lab.edits.put_objects(done.puts)
	var box := AABB()
	for changed_wall: Dictionary in done.walls:
		var b := LevelBuild.box_of(changed_wall, lab.level.objects)
		box = b if not box.has_volume() else box.merge(b)
	_warn_floating(box)


## Inspector: the selected wall's length (meters), b moving along it.
func set_wall_length(meters: float) -> void:
	var object := selection()
	if object.get("kind") != "wall":
		return
	var done := WallHandles.with_length(lab.level.objects, object, meters / lab.world.voxel_size)
	_commit_wall_change(done)


## Inspector: splits the selected wall in two at its middle.
func split_selected() -> void:
	var object := selection()
	if object.get("kind") != "wall":
		return
	var puts := WallHandles.split(lab.level.objects, object, snap())
	if puts.is_empty():
		lab.notify("Too short to split", false)
		return
	lab.edits.put_objects(puts)


## Inspector: merges the selected wall with a joined wall in line with it.
func merge_selected() -> void:
	var object := selection()
	if object.get("kind") != "wall":
		return
	var done := WallHandles.merge(lab.level.objects, object)
	if not done.ok:
		lab.notify(done.reason, false)
		return
	lab.edits.put_objects(done.puts)


## Inspector: one field of the selected wall (material, inner, thickness, height).
func set_wall_field(key: String, value: int) -> void:
	var object := selection()
	if object.get("kind") != "wall" or int(object.get(key, 0)) == value:
		return
	var changed_wall := object.duplicate()
	changed_wall[key] = value
	lab.edits.put_object(changed_wall, object.id)


## The 8 corners (world space) of a wall's cells from a to b (voxel x, z), the way VoxelWorld lays
## them out: thickness across its line, half of it past each end. Bit 0: along, bit 1: up, bit 2:
## across.
func _wall_corners(a: Vector2i, b: Vector2i, thickness: int, y0: int, y1: int) -> Array[Vector3]:
	var d := Vector2(b - a)
	var length := d.length()
	var u := d / length if length > 0.0 else Vector2(1, 0)
	var across := Vector2(u.y, -u.x)
	var half := thickness * 0.5
	var out: Array[Vector3] = []
	for i in 8:
		var along := length + half if i & 1 else -half
		var side := half if i & 4 else -half
		var p := Vector2(a) + u * along + across * side
		out.append(lab.view.to_world(Vector3(p.x, y1 if i & 2 else y0, p.y)))
	return out


## A label over a snapped point (voxel x, z) saying what it snapped to; the last size label.
func _snap_label(point: Vector2i, y: int, kind: String) -> void:
	var label := _size_labels[2]
	label.text = kind
	label.modulate = LABEL_ACTIVE_COLOR
	label.font_size = 22
	label.position = lab.view.to_world(Vector3(point.x, y + 2, point.y))
	label.visible = true


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

## The world's box edges and its bottom grid, redrawn when the world's size changes.
func _update_bounds() -> void:
	_bounds.visible = true
	_ground.visible = true
	var size: Vector3i = lab.world.get_size_in_voxels()
	if _bounds.get_meta("size", Vector3i.ZERO) == size:
		return
	_bounds.set_meta("size", size)
	lab.view.draw_box(_bounds.mesh, AABB(Vector3.ZERO, Vector3(size)))
	var extent := Vector3(size) * lab.world.voxel_size
	(_ground.mesh as PlaneMesh).size = Vector2(extent.x, extent.z)
	_ground.global_position = lab.world.global_position + Vector3(extent.x * 0.5, 0.002, extent.z * 0.5)
	var material := _ground.material_override as ShaderMaterial
	material.set_shader_parameter("origin", lab.world.global_position)
	material.set_shader_parameter("spacing", 1.0)
	material.set_shader_parameter("center", _ground.global_position)


func _update_previews() -> void:
	_update_bounds()
	_cursor_lines.visible = has_cursor and not volume.is_active() and tool in [Tool.BOX, Tool.ROOM, Tool.BRUSH, Tool.REPLACE]
	if tool in [Tool.FLOOR, Tool.CEILING]:
		_cursor_lines.visible = build.has_aim
	elif tool == Tool.WALL:
		_cursor_lines.visible = wall.has_aim
	_volume.visible = false
	_ghost.visible = false
	_cursor_box = AABB()
	_ghost_state = {}
	for label in _size_labels:
		label.visible = false
	if _cursor_lines.visible:
		var box: AABB
		if tool in [Tool.FLOOR, Tool.CEILING, Tool.WALL]:
			# The point the aim snaps to (the wall's end while drawing), a little square on the plane.
			var aimer: BuildTools = wall if tool == Tool.WALL else build
			var point: Vector2i = wall.end if tool == Tool.WALL and wall.dragging else aimer.snapped
			box = AABB(Vector3(point.x - 1, aimer.plane_y, point.y - 1), Vector3(2, 1, 2))
		elif tool == Tool.BRUSH:
			box = AABB(Vector3(cell) - Vector3.ONE * (brush_size - 1), Vector3.ONE * (brush_size * 2 - 1))
		else:
			# Where the first click would start: a grid cell's footprint on the surface.
			box = AABB(Vector3(_start_cell(false)), Vector3(snap(), 1, snap()))
		lab.view.draw_box(_cursor_lines.mesh, box)
		_cursor_box = box
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
		_preview_box = AABB(Vector3(box[0]), Vector3(box[1] - box[0]))
		_place_size_labels(AABB(lab.view.to_world(Vector3(box[0])), size), volume.axis, volume.step == VolumeSteps.Step.HEIGHT, volume.typed)
	# A room being resized or moved, an opening about to be cut or moved: its box.
	var box_preview := {}
	var preview_color := Color(0.3, 0.6, 1.0)
	if handles.is_busy() and not handles.resized.is_empty():
		box_preview = handles.resized
	elif LevelSchema.is_structure(_grab) and has_cursor and _grab.kind != "wall":
		box_preview = _grab.duplicate()
		_place_grab(box_preview)
	elif tool == Tool.OPENING:
		box_preview = opening_at_cursor()
		if box_preview.has("wall"):
			box_preview = {} # A prism along the wall (_update_wall_edit_preview).
	if box_preview.get("kind", "opening") == "opening":
		preview_color = Color(1.0, 0.6, 0.2)
	if not box_preview.is_empty():
		(_volume.material_override as StandardMaterial3D).albedo_color = Color(preview_color, 0.25)
		var size := Vector3(box_preview.to - box_preview.from) * lab.world.voxel_size
		_volume.scale = size
		_volume.position = lab.view.to_world(Vector3(box_preview.from)) + size * 0.5
		_volume.visible = true
		_preview_box = AABB(Vector3(box_preview.from), Vector3(box_preview.to - box_preview.from))
		var axis := -1
		for a in 3:
			if handles.active[a] != 0:
				axis = a
		_place_size_labels(AABB(lab.view.to_world(Vector3(box_preview.from)), size), axis, true)
	_update_build_preview()
	_update_wall_preview()
	_update_wall_edit_preview()
	# The fill hides behind walls; its edges always show.
	_volume_lines.visible = _volume.visible
	if _volume.visible:
		(_volume_lines.material_override as StandardMaterial3D).albedo_color = Color((_volume.material_override as StandardMaterial3D).albedo_color, 0.9)
		lab.view.draw_box(_volume_lines.mesh, _preview_box)
	_update_grid()
	# Ghost of the prop being placed or moved, or of a moved marker's box.
	var ghost := {}
	if not _grab.is_empty() and not LevelSchema.is_structure(_grab):
		ghost = _grab.duplicate()
		_place_grab(ghost)
	elif tool == Tool.PROP:
		ghost = _placed(LevelSchema.new_prop(prop_name, Vector3i.ZERO, facing), prop_spot(prop_name, facing, ""))
	if not ghost.is_empty() and has_cursor:
		if ghost.kind == "prop":
			_ghost.mesh = lab.view.prop_mesh(ghost.name, ghost.facing)
			# Red where it can't go.
			_ghost.material_override = lab.world.material if _spot.get("valid", false) else _invalid_material
			_ghost.position = lab.view.to_world(Vector3(ghost.origin))
			_ghost.visible = _ghost.mesh != null
			_ghost_state = {name = ghost.name, origin = ghost.origin, facing = ghost.facing}
		else:
			var box := LevelSchema.marker_box(ghost)
			_cursor_lines.visible = true
			lab.view.draw_box(_cursor_lines.mesh, box)
			_cursor_box = box
