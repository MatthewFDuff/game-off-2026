class_name WallHandles
extends RefCounted
## Handles on the selected build mode wall (Select tool): one on each end and one in the middle, on
## top of the wall. Press on one and drag, or click it to pick it up (it follows the aim until the
## next click); the wheel nudges it a grid step. An end goes where the Wall tool would put it (8
## directions from the other end, snapping to wall ends, walls and floor edges); the middle slides
## the wall sideways. Walls joined to a moved end (an end at the same point) follow it, so corners
## stay closed. Dropping it gives one edit: the wall, the joined walls, their openings (kept where
## they are in the world) and, when the wall slides, the doors in it.
##
## The static functions are the same changes for the inspector and the Select tool's actions
## (length, split, merge, delete, move).

enum Handle { NONE, END_A, END_B, MIDDLE }

const PICK_PIXELS := 18.0
const DRAG_PIXELS := 4.0
const SIZE_PIXELS := 10.0
const COLOR := Color(1.0, 0.85, 0.3)
const HOVER_COLOR := Color(1.0, 1.0, 1.0)

var world: VoxelWorld
## The wall as it is (selected), {} when none, and the level's objects (set by update).
var wall := {}
var objects := {}
var hover := Handle.NONE
var active := Handle.NONE
var pressed := false
var picked := false
## The change where the aim puts the active handle: {valid, reason, puts, walls (the changed walls,
## the dragged one first)}.
var result := {}

var _press_at := Vector2.ZERO
var _reference := Vector2.INF
var _nudge := 0
var _aimer := WallTool.new()
var _markers: Array[MeshInstance3D] = []


## Makes the handle meshes (under parent, hidden).
func build(parent: Node3D) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.render_priority = 10
	for i in 3:
		var marker := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		marker.mesh = mesh
		marker.material_override = material.duplicate()
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.visible = false
		parent.add_child(marker)
		_markers.append(marker)
	_aimer.world = world


func free_meshes() -> void:
	for marker in _markers:
		if is_instance_valid(marker):
			marker.queue_free()


func is_busy() -> bool:
	return active != Handle.NONE


func cancel() -> void:
	active = Handle.NONE
	pressed = false
	picked = false
	result = {}
	_nudge = 0
	_reference = Vector2.INF
	_aimer.cancel()


## Where a handle sits (world space) on a wall: an end or the middle, on top of it.
func handle_position(of: Dictionary, handle: Handle) -> Vector3:
	var st := LevelBuild.storeys(objects)
	var e := LevelBuild.ends(of)
	var p := Vector2(e[0]) if handle == Handle.END_A else (Vector2(e[1]) if handle == Handle.END_B else (Vector2(e[0]) + Vector2(e[1])) * 0.5)
	var y := LevelBuild.wall_base(of, st) + LevelBuild.wall_height(of, st)
	return world.global_position + Vector3(p.x, y, p.y) * world.voxel_size


## Per frame: which handle is under the pointer, the change the active one makes, and the meshes.
func update(camera: Camera3D, pointer: Vector2, origin: Vector3, direction: Vector3, grid: int, level_objects: Dictionary) -> void:
	objects = level_objects
	if wall.is_empty() or camera == null:
		for marker in _markers:
			marker.visible = false
		return
	hover = Handle.NONE
	if not is_busy():
		var best := PICK_PIXELS
		for handle in [Handle.MIDDLE, Handle.END_A, Handle.END_B]:
			var at := handle_position(wall, handle)
			if camera.is_position_behind(at):
				continue
			var distance := camera.unproject_position(at).distance_to(pointer)
			if distance < best:
				best = distance
				hover = handle
	elif pressed or picked:
		result = _change(origin, direction, grid)
	var shown: Dictionary = result.walls[0] if not result.is_empty() and not result.walls.is_empty() else wall
	for i in 3:
		var handle: Handle = [Handle.END_A, Handle.END_B, Handle.MIDDLE][i]
		var marker := _markers[i]
		var at := handle_position(shown, handle)
		marker.visible = not camera.is_position_behind(at) and (not is_busy() or handle == active)
		marker.position = at
		var size := camera.global_position.distance_to(at) * tan(deg_to_rad(camera.fov) * 0.5) * 2.0 * SIZE_PIXELS / maxf(camera.get_viewport().get_visible_rect().size.y, 1.0)
		if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
			size = camera.size * SIZE_PIXELS / maxf(camera.get_viewport().get_visible_rect().size.y, 1.0)
		marker.scale = Vector3.ONE * size * (1.4 if handle == hover or handle == active else 1.0)
		(marker.material_override as StandardMaterial3D).albedo_color = HOVER_COLOR if handle == hover or handle == active else (Color(1, 0.3, 0.3) if not result.get("valid", true) else COLOR)


## Press on the hovered handle. True if it took the press.
func press(pointer: Vector2, origin: Vector3, direction: Vector3) -> bool:
	if picked:
		return true # The drop happens on release.
	if hover == Handle.NONE or wall.is_empty():
		return false
	active = hover
	pressed = true
	_press_at = pointer
	_nudge = 0
	_reference = _aim(origin, direction)
	result = {}
	if active != Handle.MIDDLE:
		var e := LevelBuild.ends(wall)
		var st := LevelBuild.storeys(objects)
		_aimer.storey = int(wall.storey)
		_aimer.plane_y = LevelBuild.wall_base(wall, st)
		_aimer.base = _aimer.plane_y
		_aimer.dragging = true
		_aimer.rect_mode = false
		_aimer.erase = false
		_aimer.typed = ""
		_aimer.fixed_length = -1.0
		_aimer.start = e[1] if active == Handle.END_A else e[0]
		_aimer.end = e[0] if active == Handle.END_A else e[1]
	return true


## Release: ends a drag (returns the change to commit: {valid, reason, puts}), or picks the handle
## up after a click without a drag; a release while it's picked up drops it. {} when there's nothing
## to commit yet.
func release(pointer: Vector2) -> Dictionary:
	if not is_busy():
		return {}
	if picked:
		var done := result
		cancel()
		return done
	pressed = false
	var unchanged: bool = result.is_empty() or result.walls.is_empty() or result.walls[0] == wall
	if pointer.distance_to(_press_at) <= DRAG_PIXELS and _nudge == 0 and unchanged:
		picked = true
		return {}
	var done := result
	cancel()
	return done


## The wheel while a handle is held or picked up: a grid step (outward along the wall for an end,
## sideways for the middle).
func nudge(steps: int) -> void:
	_nudge += steps


## The aim on the wall's floor plane (voxel x, z); INF when it misses.
func _aim(origin: Vector3, direction: Vector3) -> Vector2:
	var st := LevelBuild.storeys(objects)
	var y := world.global_position.y + LevelBuild.wall_base(wall, st) * world.voxel_size
	if absf(direction.y) < 1e-4:
		return Vector2.INF
	var t := (y - origin.y) / direction.y
	if t <= 0.0:
		return Vector2.INF
	var p := (origin + direction * t - world.global_position) / world.voxel_size
	return Vector2(p.x, p.z)


func _change(origin: Vector3, direction: Vector3, grid: int) -> Dictionary:
	var e := LevelBuild.ends(wall)
	if active == Handle.MIDDLE:
		var step := _step(wall)
		var side := Vector2i(-step.y, step.x)
		var aim := _aim(origin, direction)
		var moved := 0
		if aim != Vector2.INF and _reference != Vector2.INF:
			moved = roundi((aim - _reference).dot(Vector2(side)) / Vector2(side).length_squared() / grid) * grid
		moved += _nudge * grid
		var offset := side * moved
		return reshape(objects, wall, e[0] + offset, e[1] + offset, offset, true)
	var others := objects.duplicate()
	others.erase(wall.id)
	_aimer.update_aim(origin, direction, others, grid)
	_aimer.update_end(grid)
	var point := _aimer.end + _aimer.direction * (_nudge * grid)
	if active == Handle.END_A:
		return reshape(objects, wall, point, e[1], Vector2i.ZERO, true)
	return reshape(objects, wall, e[0], point, Vector2i.ZERO, true)


## A wall's step: its direction in whole voxels, (1, 0), (1, 1), ...
static func _step(of: Dictionary) -> Vector2i:
	var e := LevelBuild.ends(of)
	var d := e[1] - e[0]
	return Vector2i(signi(d.x), signi(d.y))


# --- Changes -------------------------------------------------------------------------------------

## The wall with its ends at a and b: {valid, reason, puts (for LevelEdits.put_objects), walls}.
## Joined walls (an end where this one's end was) follow when follow_joined; their direction must
## stay one of the 8. Openings stay where they are in the world (clamped into the wall); doors in it
## move by carry (voxels) when that isn't zero.
static func reshape(objects: Dictionary, wall: Dictionary, a: Vector2i, b: Vector2i, carry: Vector2i, follow_joined: bool) -> Dictionary:
	var out := {valid = true, reason = "", puts = [], walls = []}
	var changed := wall.duplicate()
	changed.a = Vector3i(a.x, 0, a.y)
	changed.b = Vector3i(b.x, 0, b.y)
	if a == b or not LevelBuild.is_diagonal_ok(changed.a, changed.b):
		out.valid = false
		out.reason = "Walls run straight or at 45°"
	out.walls.append(changed)
	var old_ends := LevelBuild.ends(wall)
	var moves := {}
	if old_ends[0] != a:
		moves[old_ends[0]] = a
	if old_ends[1] != b:
		moves[old_ends[1]] = b
	var walls := [[wall, changed]]
	if follow_joined and not moves.is_empty():
		for other in LevelBuild.walls_with(objects, wall):
			if other.id == wall.id:
				continue
			var other_ends := LevelBuild.ends(other)
			if not moves.has(other_ends[0]) and not moves.has(other_ends[1]):
				continue
			var follows := other.duplicate()
			var na: Vector2i = moves.get(other_ends[0], other_ends[0])
			var nb: Vector2i = moves.get(other_ends[1], other_ends[1])
			follows.a = Vector3i(na.x, 0, na.y)
			follows.b = Vector3i(nb.x, 0, nb.y)
			if na == nb or not LevelBuild.is_diagonal_ok(follows.a, follows.b):
				out.valid = false
				out.reason = "Joined walls would bend"
			out.walls.append(follows)
			walls.append([other, follows])
	for pair: Array in walls:
		if pair[0] != pair[1]:
			out.puts.append([pair[0].id, pair[1]])
			out.puts.append_array(_reattach(objects, pair[0], pair[1]))
	if carry != Vector2i.ZERO:
		for door in LevelBuild.doors_in(objects, wall):
			var moved := door.duplicate()
			moved.origin += Vector3i(carry.x, 0, carry.y)
			out.puts.append([door.id, moved])
	return out


## Puts that keep a wall's openings where they are in the world when it goes from before to after
## (clamped into it; on wall "$n" when after is the n-th put of a new wall).
static func _reattach(objects: Dictionary, before: Dictionary, after: Dictionary, wall_ref := "") -> Array:
	var puts: Array = []
	var a0 := Vector2(before.a.x, before.a.z)
	var u0 := LevelBuild.wall_unit(before)
	var length := LevelBuild.wall_length(after)
	for opening in LevelBuild.openings_in(objects, before.id):
		var start := a0 + u0 * int(opening.along)
		var along := roundi(LevelBuild.along_of(after, start))
		if u0.dot(LevelBuild.wall_unit(after)) < 0.0:
			along -= int(opening.width) # The wall turned round: its start is the opening's other end.
		var moved := opening.duplicate()
		moved.along = clampi(along, 0, maxi(floori(length) - int(opening.width), 0))
		if wall_ref != "":
			moved.wall = wall_ref
		if moved != opening:
			puts.append([opening.id, moved])
	return puts


## The wall's length set to voxels (b moves along it; walls joined at b follow).
static func with_length(objects: Dictionary, wall: Dictionary, voxels: float) -> Dictionary:
	var e := LevelBuild.ends(wall)
	var step := _step(wall)
	var steps := maxi(roundi(voxels / Vector2(step).length()), 1)
	return reshape(objects, wall, e[0], e[0] + step * steps, Vector2i.ZERO, true)


## Splits a wall in two at its middle (on the grid): puts. Openings go to the half that holds their
## start.
static func split(objects: Dictionary, wall: Dictionary, grid: int) -> Array:
	var e := LevelBuild.ends(wall)
	var step := _step(wall)
	var steps := maxi(absi(e[1].x - e[0].x), absi(e[1].y - e[0].y))
	var at := roundi(steps * 0.5 / grid) * grid if step.x == 0 or step.y == 0 else steps / 2
	if at <= 0 or at >= steps:
		at = steps / 2
	if at <= 0:
		return []
	var middle := e[0] + step * at
	var first := wall.duplicate()
	first.b = Vector3i(middle.x, 0, middle.y)
	var second := wall.duplicate()
	second.erase("id")
	second.a = Vector3i(middle.x, 0, middle.y)
	var puts: Array = [[wall.id, first], ["", second]]
	var cut := LevelBuild.wall_length(first)
	for opening in LevelBuild.openings_in(objects, wall.id):
		if int(opening.along) >= cut:
			var moved := opening.duplicate()
			moved.along = roundi(int(opening.along) - cut)
			moved.wall = "$1"
			puts.append([opening.id, moved])
	return puts


## Merges a wall with a joined wall in line with it and built the same (storey or base, material,
## inner, thickness, height): {ok, reason, puts}. The merged wall keeps this one's id and direction.
static func merge(objects: Dictionary, wall: Dictionary) -> Dictionary:
	var e := LevelBuild.ends(wall)
	var u := LevelBuild.wall_unit(wall)
	for other in LevelBuild.walls_with(objects, wall):
		if other.id == wall.id:
			continue
		var same := true
		for key in ["material", "inner", "thickness", "height"]:
			same = same and int(other[key]) == int(wall[key])
		var u2 := LevelBuild.wall_unit(other)
		if not same or absf(u.cross(u2)) > 0.001:
			continue
		var o := LevelBuild.ends(other)
		var points: Array[Vector2i] = []
		if o[0] == e[1] or o[1] == e[1]:
			points = [e[0], o[1] if o[0] == e[1] else o[0]]
		elif o[0] == e[0] or o[1] == e[0]:
			points = [o[1] if o[0] == e[0] else o[0], e[1]]
		else:
			continue
		var merged := wall.duplicate()
		merged.a = Vector3i(points[0].x, 0, points[0].y)
		merged.b = Vector3i(points[1].x, 0, points[1].y)
		var puts: Array = [[wall.id, merged], [other.id, {}]]
		puts.append_array(_reattach(objects, wall, merged))
		for put: Array in _reattach(objects, other, merged, wall.id):
			puts.append(put)
		# Openings of the other wall that _reattach left unchanged still need the new wall.
		for opening in LevelBuild.openings_in(objects, other.id):
			var listed := puts.any(func(put: Array) -> bool: return put[0] == opening.id)
			if not listed:
				var moved := opening.duplicate()
				moved.wall = wall.id
				puts.append([opening.id, moved])
		return {ok = true, reason = "", puts = puts}
	return {ok = false, reason = "No wall in line with it, built the same, joined to an end", puts = []}


## Deleting a wall: puts that remove it, its openings and the doors in it.
static func removal(objects: Dictionary, wall: Dictionary) -> Array:
	var puts: Array = [[wall.id, {}]]
	for opening in LevelBuild.openings_in(objects, wall.id):
		puts.append([opening.id, {}])
	for door in LevelBuild.doors_in(objects, wall):
		puts.append([door.id, {}])
	return puts
