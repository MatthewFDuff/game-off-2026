class_name RoomHandles
extends RefCounted
## Resize handles on the selected room (Select tool): one on each wall, one on the ceiling and one on
## each corner (two walls at once). Press on a handle and drag, or click it to pick it up (it follows
## the aim until the next click); the wheel nudges it a grid step outward or back. Dropping it gives
## the resized room; EditorTool turns that into one edit with RoomTools.carry.
##
## Handles are picked on screen (within PICK_PIXELS of the pointer), so they're as easy to grab at
## any zoom, and they're drawn on top of everything.

## Outward directions: four walls, the ceiling, four corners.
const DIRECTIONS: Array[Vector3i] = [Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(0, 1, 0),
		Vector3i(-1, 0, -1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(1, 0, 1)]
const PICK_PIXELS := 18.0
## Pointer travel before a press on a handle counts as a drag.
const DRAG_PIXELS := 4.0
const SIZE_PIXELS := 10.0
const COLOR := Color(1.0, 0.85, 0.3)
const HOVER_COLOR := Color(1.0, 1.0, 1.0)

var world: VoxelWorld
## The room as it is (selected), {} when none.
var room := {}
## The handle being hovered, and the one held or picked up (Vector3i.ZERO: none).
var hover := Vector3i.ZERO
var active := Vector3i.ZERO
## Button still down on the active handle (a drag), or let go of without moving (picked up).
var pressed := false
var picked := false
## The room with the active handle where the aim puts it.
var resized := {}

var _press_at := Vector2.ZERO
var _reference := Vector3.INF
var _nudge := 0
var _markers: Array[MeshInstance3D] = []


## Makes the handle meshes (under parent, hidden).
func build(parent: Node3D) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.vertex_color_use_as_albedo = false
	material.render_priority = 10
	for direction in DIRECTIONS:
		var marker := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		marker.mesh = mesh
		marker.material_override = material.duplicate()
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.visible = false
		parent.add_child(marker)
		_markers.append(marker)


func free_meshes() -> void:
	for marker in _markers:
		if is_instance_valid(marker):
			marker.queue_free()


func is_busy() -> bool:
	return active != Vector3i.ZERO


func cancel() -> void:
	active = Vector3i.ZERO
	pressed = false
	picked = false
	resized = {}
	_nudge = 0
	_reference = Vector3.INF


## Where a handle sits, in world space, on the room box [from, to) (voxels).
func handle_position(box_from: Vector3i, box_to: Vector3i, direction: Vector3i) -> Vector3:
	var p := (Vector3(box_from) + Vector3(box_to)) * 0.5
	for a in 3:
		if direction[a] < 0:
			p[a] = box_from[a]
		elif direction[a] > 0:
			p[a] = box_to[a]
	return world.global_position + p * world.voxel_size


## Per frame: which handle is under the pointer, where the active one is, and the meshes.
func update(camera: Camera3D, pointer: Vector2, origin: Vector3, direction: Vector3, grid: int) -> void:
	if room.is_empty():
		for marker in _markers:
			marker.visible = false
		return
	var shown := resized if not resized.is_empty() else room
	hover = Vector3i.ZERO
	if not is_busy():
		var best := PICK_PIXELS
		for d in DIRECTIONS:
			var at := handle_position(room.from, room.to, d)
			if camera.is_position_behind(at):
				continue
			var distance := camera.unproject_position(at).distance_to(pointer)
			if distance < best:
				best = distance
				hover = d
	elif pressed or picked:
		resized = _resize(origin, direction, grid)
		shown = resized
	for i in DIRECTIONS.size():
		var d := DIRECTIONS[i]
		var marker := _markers[i]
		var at := handle_position(shown.from, shown.to, d)
		marker.visible = not camera.is_position_behind(at) and (not is_busy() or d == active)
		marker.position = at
		# The same size on screen at any distance.
		var size := camera.global_position.distance_to(at) * tan(deg_to_rad(camera.fov) * 0.5) * 2.0 * SIZE_PIXELS / maxf(camera.get_viewport().get_visible_rect().size.y, 1.0)
		marker.scale = Vector3.ONE * size * (1.4 if d == hover or d == active else 1.0)
		(marker.material_override as StandardMaterial3D).albedo_color = HOVER_COLOR if d == hover or d == active else COLOR


## Press on the hovered handle. Returns true if it took the press.
func press(pointer: Vector2, origin: Vector3, direction: Vector3) -> bool:
	if picked:
		return true # The drop happens on release.
	if hover == Vector3i.ZERO or room.is_empty():
		return false
	active = hover
	pressed = true
	_press_at = pointer
	_reference = _aim_point(origin, direction, room.from, room.to)
	_nudge = 0
	resized = room.duplicate()
	return true


## Release: ends a drag (returns the resized room to commit), or picks the handle up after a click
## without a drag; a release while it's picked up drops it. {} when there's nothing to commit yet.
func release(pointer: Vector2) -> Dictionary:
	if not is_busy():
		return {}
	if picked:
		var done := resized
		cancel()
		return done
	pressed = false
	if pointer.distance_to(_press_at) <= DRAG_PIXELS and _nudge == 0 and resized == room:
		picked = true
		return {}
	var done := resized
	cancel()
	return done


## The wheel while a handle is held or picked up: a grid step outward (steps > 0) or back.
func nudge(steps: int) -> void:
	_nudge += steps


func _aim_point(origin: Vector3, direction: Vector3, box_from: Vector3i, box_to: Vector3i) -> Vector3:
	var at := handle_position(box_from, box_to, active)
	if active.y != 0:
		var on_line := VolumeSteps._closest_on_vertical(origin, direction, at)
		return (on_line - world.global_position) / world.voxel_size
	if absf(direction.y) < 1e-4:
		return Vector3.INF
	var t := (at.y - origin.y) / direction.y
	if t <= 0.0:
		return Vector3.INF
	return (origin + direction * t - world.global_position) / world.voxel_size


## The room with the active handle where the aim (and the wheel) put it, faces on the grid, at least
## one voxel across.
func _resize(origin: Vector3, direction: Vector3, grid: int) -> Dictionary:
	var aim := _aim_point(origin, direction, room.from, room.to)
	var box_from: Vector3i = room.from
	var box_to: Vector3i = room.to
	for a in 3:
		if active[a] == 0:
			continue
		var moved := 0
		if aim != Vector3.INF and _reference != Vector3.INF:
			moved = roundi((aim[a] - _reference[a]) / grid) * grid
		moved += _nudge * grid * active[a]
		if active[a] < 0:
			box_from[a] = mini(room.from[a] + moved, room.to[a] - 1)
		else:
			box_to[a] = maxi(room.to[a] + moved, room.from[a] + 1)
	var out := room.duplicate()
	out.from = box_from
	out.to = box_to
	return out
