class_name BuildTools
extends RefCounted
## Build mode's Floor and Ceiling tools (EditorTool, empty levels): aiming at the storey's floor or
## ceiling plane, snapping to what's there, dragging a rectangle, and filling what walls close in.
## Press, drag, release paints a rectangle (Shift erases); a click without a drag fills the space
## the storey's walls close in around it (Shift+click erases it). Everything goes through
## LevelEdits.add_slab_shape.

## Snap priority within reach of the aim (voxels): wall ends and shape corners, then wall lines and
## shape edges, then the grid.
const CORNER_REACH := 3.0
const LINE_REACH := 2.0
## _on_segment: off the segment.
const OFF := Vector2i(-1073741824, 0)

var world: VoxelWorld
var view: LevelView
var edits: LevelEdits

## Which slab the tool paints ("floor" or "ceiling"), on which storey, at which plane (voxel y).
var kind := "floor"
var storey := 0
var plane_y := 0
## This frame's aim: the raw point on the plane (voxel x, z), whether there is one, and where it
## snaps to with what ("corner", "on wall", "edge", "grid").
var has_aim := false
var aim := Vector2.ZERO
var snapped := Vector2i.ZERO
var snapped_to := ""
## The drag: active, its start corner, erasing, and the column pressed (for a click's fill).
var dragging := false
var start := Vector2i.ZERO
var erase := false
var _pressed_column := Vector2i.ZERO


## Aims along a ray (world space) at the plane, snapping with grid (voxels).
func update_aim(from: Vector3, direction: Vector3, objects: Dictionary, grid: int) -> void:
	var y := world.global_position.y + plane_y * world.voxel_size
	has_aim = false
	if absf(direction.y) < 1e-4:
		return
	var t := (y - from.y) / direction.y
	if t <= 0.0:
		return
	var point := (from + direction * t - world.global_position) / world.voxel_size
	var size: Vector3i = world.get_size_in_voxels()
	aim = Vector2(clampf(point.x, 0.0, size.x), clampf(point.z, 0.0, size.z))
	has_aim = true
	var snap := snap_point(aim, objects, grid)
	snapped = snap.point
	snapped_to = snap.kind


## The point p (voxel x, z) snaps to: {point: Vector2i, kind}.
func snap_point(p: Vector2, objects: Dictionary, grid: int) -> Dictionary:
	var corners: Array[Vector2i] = []
	var lines: Array = [] # [a, b] (Vector2i) segments
	for wall in LevelBuild.walls_on(objects, storey):
		var a := Vector2i(wall.a.x, wall.a.z)
		var b := Vector2i(wall.b.x, wall.b.z)
		corners.append_array([a, b])
		lines.append([a, b, "on wall"])
	for slab_kind in ["floor", "ceiling"]:
		var slab: Dictionary = objects.get(LevelBuild.slab_id(slab_kind, storey), {})
		for s: Array in slab.get("shapes", []):
			var count := int(s[2])
			if count < 3:
				continue
			for i in count:
				var q := Vector2i(int(s[3 + i * 2]), int(s[4 + i * 2]))
				var r := Vector2i(int(s[3 + ((i + 1) % count) * 2]), int(s[4 + ((i + 1) % count) * 2]))
				corners.append(q)
				lines.append([q, r, "edge"])
	var corner_reach := maxf(CORNER_REACH, grid * 0.6)
	var best := INF
	var out := {}
	for c in corners:
		var d := p.distance_to(Vector2(c))
		if d < corner_reach and d < best:
			best = d
			out = {point = c, kind = "corner"}
	if not out.is_empty():
		return out
	var line_reach := maxf(LINE_REACH, grid * 0.4)
	for line: Array in lines:
		var q := _on_segment(p, line[0], line[1], grid)
		if q == OFF:
			continue
		var d := p.distance_to(Vector2(q))
		if d < line_reach and d < best:
			best = d
			out = {point = q, kind = line[2]}
	if not out.is_empty():
		return out
	return {point = Vector2i(roundi(p.x / grid) * grid, roundi(p.y / grid) * grid), kind = "grid"}


## The grid point on segment a -> b nearest p: whole steps along it (grid steps along a straight
## one, single voxel steps along a 45° one); OFF when that is past its ends.
static func _on_segment(p: Vector2, a: Vector2i, b: Vector2i, grid: int) -> Vector2i:
	var d := b - a
	var steps := maxi(absi(d.x), absi(d.y))
	if steps == 0:
		return OFF
	var unit := Vector2(d) / steps
	var t := (p - Vector2(a)).dot(unit) / unit.length_squared()
	if d.x == 0 or d.y == 0:
		# Straight: the grid line nearest, or the end.
		var along := float(roundi((Vector2(a) + unit * t)[0 if d.y == 0 else 1] / grid) * grid)
		t = (along - (a.x if d.y == 0 else a.y)) / (unit.x if d.y == 0 else unit.y)
	t = roundf(t)
	if t < 0.0 or t > steps:
		return OFF
	return a + Vector2i(Vector2(unit) * t)


func press(shift: bool) -> void:
	if not has_aim:
		return
	dragging = true
	erase = shift
	start = snapped
	_pressed_column = Vector2i(floori(aim.x), floori(aim.y))


func cancel() -> void:
	dragging = false


## The rectangle being dragged, [lo, hi) in x and z (Vector2i).
func rect() -> Rect2i:
	var lo := start.min(snapped)
	var hi := start.max(snapped)
	return Rect2i(lo, hi - lo)


## Ends the drag: paints (or erases) the rectangle, or for a click, fills the enclosure. Returns
## the toast to show ("" none).
func release(objects: Dictionary, material: int) -> String:
	if not dragging:
		return ""
	dragging = false
	var r := rect()
	if r.size.x > 0 and r.size.y > 0:
		edits.add_slab_shape(kind, storey, LevelBuild.rect_shape(Vector3i(r.position.x, 0, r.position.y), Vector3i(r.end.x, 0, r.end.y), material, not erase))
		return ""
	if r.size.x > 0 or r.size.y > 0:
		return "Drag out an area (it's a line)"
	return fill(objects, _pressed_column, material, not erase)


## Fills (or erases) what the storey's walls close in around a column. The toast to show.
func fill(objects: Dictionary, column: Vector2i, material: int, add := true) -> String:
	var found := LevelBuild.enclosure(objects, storey, column)
	if not found.ok:
		return found.reason
	edits.add_slab_shape(kind, storey, LevelBuild.runs_shape(found.runs, material, add))
	return "%s %s" % [kind.capitalize(), "filled" if add else "erased"]


## Ceiling tool's Auto: one ceiling over every space the storey's walls close in that has floor
## under it. The toast to show.
func auto_ceiling(objects: Dictionary, material: int) -> String:
	var floor_top := LevelBuild.floor_y(LevelBuild.storeys(objects), storey)
	var runs: Array = []
	var rooms := 0
	for region: Array in LevelBuild.enclosures(objects, storey):
		var floored := false
		for run: Array in region:
			for x in range(run[1], run[2]):
				if world.get_voxel(Vector3i(x, floor_top - 1, run[0])) != 0:
					floored = true
					break
			if floored:
				break
		if floored:
			runs.append_array(region)
			rooms += 1
	if runs.is_empty():
		return "No closed-in rooms with a floor on this storey"
	edits.add_slab_shape("ceiling", storey, LevelBuild.runs_shape(runs, material))
	return "Ceiling over %d room%s" % [rooms, "" if rooms == 1 else "s"]
