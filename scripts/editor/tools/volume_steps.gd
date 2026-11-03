class_name VolumeSteps
extends RefCounted
## The three-click sizing shared by the Room, Box and Replace tools: click a start corner, click
## the far corner of the floor, click the height. Between clicks the aim ray sizes the box: on the
## floor step it meets the horizontal plane through the start's surface (so it never jumps onto a
## wall), on the height step a vertical line through the floor's center. The wheel nudges the
## active dimension by a grid step, typing sets it exactly (meters, or voxels with a "v"), Tab moves
## to the next dimension. A dimension set by wheel or typing stays put while the mouse moves.
##
## Sizes are signed voxel counts from the start corner (never 0): x and z cover whole grid cells,
## so the start cell is always inside the box; y counts from the start voxel's layer.

enum Step { NONE, FLOOR, HEIGHT }

## Below this much horizontal aim (looking almost straight down), the mouse doesn't set the height;
## the wheel and typing still do.
const MIN_HEIGHT_AIM := 0.2

var world: VoxelWorld
var step := Step.NONE
## The start cell: x and z on the grid, y the layer the box starts from.
var start := Vector3i.ZERO
## Signed size in voxels on each axis.
var extent := Vector3i.ONE
## Active dimension (Vector3 axis index): the wheel and typing change it.
var axis := Vector3.AXIS_X
## Digits typed for the active dimension, "" when none.
var typed := ""
var snap := 5

## World height of the floor step's plane.
var _plane_y := 0.0
## Dimensions set by the wheel or typing: axis -> true.
var _locked := {}
## The aim's height (in voxels) when the height step began, and the height given then.
var _height_ref := NAN
var _height_given := 1


func is_active() -> bool:
	return step != Step.NONE


## Starts sizing at corner. plane_y is the world height of the surface it was picked on.
## height_sign: which way the height goes by default (+1 up, -1 down into the floor).
func begin(corner: Vector3i, plane_y: float, grid: int, height_sign: int) -> void:
	snap = grid
	start = corner
	extent = Vector3i(snap, height_sign, snap)
	_plane_y = plane_y
	_locked.clear()
	typed = ""
	axis = Vector3.AXIS_X
	step = Step.FLOOR


func cancel() -> void:
	step = Step.NONE
	typed = ""
	_locked.clear()


## The next click: from the floor step to the height step (starting at height, signed voxels);
## returns true when the box is done.
func advance(height: int) -> bool:
	apply_typed()
	if step == Step.FLOOR:
		step = Step.HEIGHT
		extent.y = height if height != 0 else 1
		_height_given = extent.y
		_height_ref = NAN
		axis = Vector3.AXIS_Y
		_locked.erase(Vector3.AXIS_Y)
		return false
	return step == Step.HEIGHT


## One step back: the height step returns to the floor, the floor step ends sizing. Returns false
## when there's nothing left.
func back() -> bool:
	typed = ""
	if step == Step.HEIGHT:
		step = Step.FLOOR
		axis = Vector3.AXIS_X
		_locked.erase(Vector3.AXIS_Y)
		return true
	cancel()
	return false


## Follows the aim ray (world space) on the dimensions the wheel or typing haven't set.
func aim(origin: Vector3, direction: Vector3) -> void:
	if step == Step.FLOOR:
		if absf(direction.y) < 1e-4:
			return
		var t := (_plane_y - origin.y) / direction.y
		if t <= 0.0:
			return
		var point := _to_voxels(origin + direction * t)
		for a in [Vector3.AXIS_X, Vector3.AXIS_Z]:
			if not _locked.has(a):
				extent[a] = _extent_to(a, floori(point[a]))
	elif step == Step.HEIGHT and not _locked.has(Vector3.AXIS_Y):
		var flat := Vector2(direction.x, direction.z).length()
		if flat < MIN_HEIGHT_AIM:
			return
		var height := _to_voxels(_closest_on_vertical(origin, direction, _floor_center())).y
		if is_nan(_height_ref):
			_height_ref = height
		var cells := roundi(float(_height_given) / snap) + roundi((height - _height_ref) / snap)
		# Skip zero: crossing the start layer flips the box to the other side.
		if _height_given > 0 and cells <= 0:
			cells -= 1
		elif _height_given < 0 and cells >= 0:
			cells += 1
		extent.y = cells * snap if cells != 0 else _height_given


## The wheel: grows (steps > 0) or shrinks a dimension by grid steps and keeps it there.
func nudge(on_axis: int, steps: int) -> void:
	var amount := absi(extent[on_axis])
	var side := signi(extent[on_axis]) if extent[on_axis] != 0 else 1
	extent[on_axis] = side * maxi(amount + steps * snap, 1)
	_locked[on_axis] = true


## Tab: the next dimension (x, z on the floor step; x, z, y on the height step).
func cycle_axis() -> void:
	apply_typed()
	var order := [Vector3.AXIS_X, Vector3.AXIS_Z] if step == Step.FLOOR else [Vector3.AXIS_X, Vector3.AXIS_Z, Vector3.AXIS_Y]
	axis = order[(order.find(axis) + 1) % order.size()]


## Typing a size: digits, one decimal point, and a "v" suffix for voxels. Applies as it's typed.
func type_char(character: String) -> void:
	if character == ",":
		character = "."
	if character == "." and "." in typed or character == "v" and (typed == "" or typed.ends_with("v")):
		return
	if typed.ends_with("v"):
		return
	typed += character
	_apply(typed)


func erase_char() -> void:
	typed = typed.left(-1)
	if typed != "":
		_apply(typed)


## Enter or Tab: keeps the typed size and clears the field.
func apply_typed() -> void:
	if typed != "":
		_apply(typed)
	typed = ""


func is_locked(on_axis: int) -> bool:
	return _locked.has(on_axis)


## The box as [from, to) in voxels. During the floor step it's the one layer the floor is on.
func box() -> Array[Vector3i]:
	var ext := extent
	if step == Step.FLOOR:
		ext.y = signi(extent.y)
	var from := Vector3i.ZERO
	var to := Vector3i.ZERO
	for a in 3:
		var width := 1 if a == Vector3.AXIS_Y else snap
		if ext[a] > 0:
			from[a] = start[a]
			to[a] = start[a] + ext[a]
		else:
			from[a] = start[a] + width + ext[a]
			to[a] = start[a] + width
	return [from, to]


## The finished size in voxels (unsigned).
func size() -> Vector3i:
	var b := box()
	return b[1] - b[0]


func _apply(text: String) -> void:
	var voxels := 0
	if text.ends_with("v"):
		voxels = text.left(-1).to_int()
	elif text.is_valid_float():
		voxels = roundi(text.to_float() / world.voxel_size)
	if voxels <= 0:
		return
	var side := signi(extent[axis]) if extent[axis] != 0 else 1
	extent[axis] = side * voxels
	_locked[axis] = true


## The signed extent reaching the grid cell holding voxel coordinate v.
func _extent_to(on_axis: int, v: int) -> int:
	var cell := floori(float(v) / snap) * snap
	var offset := cell - start[on_axis]
	return offset + snap if offset >= 0 else offset - snap


func _to_voxels(point: Vector3) -> Vector3:
	return (point - world.global_position) / world.voxel_size


func _floor_center() -> Vector3:
	var b := box()
	var center := (Vector3(b[0]) + Vector3(b[1])) * 0.5
	return world.global_position + Vector3(center.x, start.y, center.z) * world.voxel_size


## The point on the vertical line through anchor closest to the ray.
static func _closest_on_vertical(origin: Vector3, direction: Vector3, anchor: Vector3) -> Vector3:
	var d := direction.normalized()
	var w := origin - anchor
	var b := d.y # up . d
	var denominator := 1.0 - b * b
	if denominator < 1e-6:
		return anchor
	var s := (w.y - b * d.dot(w)) / denominator
	return anchor + Vector3.UP * s
