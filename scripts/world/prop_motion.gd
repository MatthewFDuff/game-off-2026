class_name PropMotion
extends Node3D
## The moving parts of props, in play only: a prop in PARTS is stamped as its fixed body (the
## security camera's arm), and its moving part (the camera's head, a catalog prop of its own) is
## drawn here as a mesh that turns on a pivot under the body, with a small lit cube for an LED.
## Editor views draw body and part together as one still model (display_model), so the level
## editor's view, ghost and thumbnails show the whole prop and nothing moves while editing.
##
## No networking: the motion is a function of the clock and a phase from the prop's id, so every
## peer (a late joiner, a resumed shift) runs the same animation by itself. What a part hangs from
## is read from the voxels each peer already has (WorldSync keeps them the same): once those are
## gone (shot away), the part goes dark, falls to the floor and is gone. A part whose voxels were
## never there when play started (a resumed shift with the arm shot off, a joiner before its world
## arrives) stays hidden until they are, without falling.
##
## Cheap: only parts within REACH of the active camera animate (the lab has a handful of cameras),
## the hang test is a couple of get_voxel calls per part every HANG_INTERVAL, and no lights: the
## LED is an unshaded cube shown and hidden. LevelView owns the node and calls set_active as the
## mode changes.
##
## Other moving props (the hazard beacon's lamp, an extractor fan's blades) join by adding a PARTS
## entry and the motion they need in _animate.

## Prop name -> how its moving part hangs, in the prop's north-facing frame (Props: x across, y up,
## z depth, front at z = 0), in voxels:
##   part: the catalog prop drawn as the moving mesh (its own .vox, editable like any prop)
##   at: the part's min corner in the body's frame
##   pivot: the point it turns about, on a vertical axis
##   hangs_from: the body's stamped cells it hangs from; when none is left it falls
##   led: the LED's cell in the body's frame
##   pan: half the sweep in degrees; period: seconds for a sweep there and back
const PARTS := {
	"security_camera": {part = "security_camera_head", at = Vector3i(0, 0, 0), pivot = Vector3(2.0, 3.0, 3.0),
			hangs_from = [Vector3i(1, 3, 3), Vector3i(2, 3, 3)], led = Vector3i(3, 2, 0), pan = 40.0, period = 6.0},
}
## Parts farther than this (meters) from the active camera keep still: nobody sees them.
const REACH := 40.0
## Seconds between hang tests (all parts, near or far, so one shot from afar still drops its head).
const HANG_INTERVAL := 0.1
## Share of each half sweep spent still at the end it starts from, like a real camera dwelling.
const DWELL := 0.2
## The LED's lit color (the EMERGENCY red) and how a cube of it is drawn a hair proud of its socket.
const LED_COLOR := Color(1.0, 0.15, 0.1)
const LED_SCALE := 1.15
## LED blinks by power: [period in seconds, lit share]. Facility (and restored) power: recording,
## about once a second; backup power: a short flash every two seconds, running on its battery.
const BLINK_POWERED := [1.0, 0.5]
const BLINK_BACKUP := [2.0, 0.1]
## A dropped part falls with this gravity (m/s²), and bursts on the floor or after MAX_FALL seconds.
const GRAVITY := 9.8
const MAX_FALL := 1.5
## How far down (meters) a dropping part looks for the floor.
const FLOOR_REACH := 20.0

var view: LevelView
var active := false

## The play-mode parts: {id, spec, cells (world cells it hangs from), pivot (Node3D), led
## (MeshInstance3D), yaw (the facing's), phase (0-1, from the id), state ("waiting" until its cells
## are seen, "hanging", "falling", "gone"), speed (falling, m/s), fell (seconds), floor_y}.
var _parts: Array[Dictionary] = []
var _hang_time := 0.0


## Starts (play) or stops (edit) the parts: on start, one per placed prop that has a PARTS entry.
func set_active(on: bool) -> void:
	_clear()
	active = on
	if not on or view == null or view.lab == null or view.lab.level == null:
		return
	for object: Dictionary in view.lab.level.objects.values():
		if object.kind == "prop" and PARTS.has(object.name) and not object.get("door", false):
			_add(object)
	_hang_time = HANG_INTERVAL # Test hangs on the first frame.


## The parts in play (for tests and debugging); don't change them.
func parts() -> Array[Dictionary]:
	return _parts


## A prop's model for editor views: the body with its moving part merged in where it rests, turned
## to face `facing`; any other prop's model as it is (Props.oriented). Built on each call: callers
## (LevelView.prop_mesh) cache the meshes.
static func display_model(prop_name: String, facing: int) -> Dictionary:
	var spec: Dictionary = PARTS.get(prop_name, {})
	if spec.is_empty():
		return Props.oriented(prop_name, facing)
	var body := Props.oriented(prop_name, Props.NORTH)
	var part := Props.oriented(spec.part, Props.NORTH)
	if body.is_empty() or part.is_empty():
		return Props.oriented(prop_name, facing)
	var size: Vector3i = body.size
	var voxels: PackedByteArray = body.voxels.duplicate()
	var part_size: Vector3i = part.size
	var at: Vector3i = spec.at
	for z in part_size.z:
		for y in part_size.y:
			for x in part_size.x:
				var material: int = part.voxels[x + y * part_size.x + z * part_size.x * part_size.y]
				var cell := at + Vector3i(x, y, z)
				if material == 0 or cell.x < 0 or cell.y < 0 or cell.z < 0 or cell.x >= size.x or cell.y >= size.y or cell.z >= size.z:
					continue
				var index := cell.x + cell.y * size.x + cell.z * size.x * size.y
				if voxels[index] == 0:
					voxels[index] = material
	return Props.orient({size = size, voxels = voxels}, facing)


## A cell of a w x d north-facing frame in the frame turned to `facing`, the way Props.orient turns
## voxels.
static func turn_cell(cell: Vector3i, w: int, d: int, facing: int) -> Vector3i:
	match facing:
		Props.EAST:
			return Vector3i(d - 1 - cell.z, cell.y, cell.x)
		Props.SOUTH:
			return Vector3i(w - 1 - cell.x, cell.y, d - 1 - cell.z)
		Props.WEST:
			return Vector3i(cell.z, cell.y, w - 1 - cell.x)
	return cell


## A point (voxel units, corners at whole numbers) of a w x d north-facing frame in the turned frame.
static func turn_point(point: Vector3, w: int, d: int, facing: int) -> Vector3:
	match facing:
		Props.EAST:
			return Vector3(d - point.z, point.y, point.x)
		Props.SOUTH:
			return Vector3(w - point.x, point.y, d - point.z)
		Props.WEST:
			return Vector3(point.z, point.y, w - point.x)
	return point


## The yaw (radians about +Y) that turns a north-facing model to `facing`, matching turn_point.
static func facing_yaw(facing: int) -> float:
	match facing:
		Props.EAST:
			return -PI / 2.0
		Props.SOUTH:
			return PI
		Props.WEST:
			return PI / 2.0
	return 0.0


## A sweep from -1 to 1 and back over u in 0-1: each half dwells at its starting end for DWELL of
## it, then eases across (smoothstep), so a camera slows into each end, pauses and turns back.
static func sweep(u: float) -> float:
	var half := fposmod(u * 2.0, 1.0)
	var s := smoothstep(0.0, 1.0, clampf((half - DWELL) / (1.0 - DWELL), 0.0, 1.0))
	return -1.0 + 2.0 * s if fposmod(u, 1.0) < 0.5 else 1.0 - 2.0 * s


## A stable 0-1 phase from a prop id, so the props of one kind aren't in lockstep.
static func phase_of(id: String) -> float:
	return float(posmod(hash(id), 1000)) / 1000.0


func _add(object: Dictionary) -> void:
	var spec: Dictionary = PARTS[object.name]
	var body := Props.oriented(object.name, Props.NORTH)
	var mesh := view.prop_mesh(spec.part, Props.NORTH)
	if body.is_empty() or mesh == null:
		return
	var w: int = body.size.x
	var d: int = body.size.z
	var facing: int = object.facing
	var origin: Vector3i = object.origin
	var voxel_size: float = view.lab.world.voxel_size
	var cells: Array[Vector3i] = []
	for cell: Vector3i in spec.hangs_from:
		cells.append(origin + turn_cell(cell, w, d, facing))
	var pivot_local: Vector3 = spec.pivot
	var pivot := Node3D.new()
	pivot.position = view.to_world(Vector3(origin) + turn_point(pivot_local, w, d, facing))
	pivot.rotation.y = facing_yaw(facing)
	pivot.visible = false
	add_child(pivot)
	var head := MeshInstance3D.new()
	head.mesh = mesh
	head.position = (Vector3(spec.at) - pivot_local) * voxel_size
	pivot.add_child(head)
	var led := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * voxel_size * LED_SCALE
	led.mesh = box
	led.material_override = VoxelFx.shared_material(voxel_size, false, LED_COLOR)
	led.position = (Vector3(spec.led) + Vector3.ONE * 0.5 - pivot_local) * voxel_size
	led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(led)
	_parts.append({id = object.id, spec = spec, cells = cells, pivot = pivot, led = led,
			yaw = facing_yaw(facing), phase = phase_of(object.id), state = "waiting",
			speed = 0.0, fell = 0.0, floor_y = 0.0, height = (pivot_local.y - float(spec.at.y)) * voxel_size})


func _clear() -> void:
	for part: Dictionary in _parts:
		if is_instance_valid(part.pivot): # A dropped part has freed its own.
			part.pivot.queue_free()
	_parts.clear()


func _process(delta: float) -> void:
	if not active or _parts.is_empty():
		return
	_hang_time += delta
	if _hang_time >= HANG_INTERVAL:
		_hang_time = 0.0
		_test_hangs()
	var camera := get_viewport().get_camera_3d()
	var reach_squared := REACH * REACH
	var now := Time.get_ticks_msec() / 1000.0
	var backup := view.lab.play != null and view.lab.play.power == "backup"
	for part: Dictionary in _parts:
		match part.state:
			"hanging":
				var pivot: Node3D = part.pivot
				if camera == null or camera.global_position.distance_squared_to(pivot.global_position) <= reach_squared:
					_animate(part, now, backup)
			"falling":
				_fall(part, delta)


## Every hanging part: a slow pan about its pivot and the LED's blink, both from the clock.
func _animate(part: Dictionary, now: float, backup: bool) -> void:
	var spec: Dictionary = part.spec
	var pivot: Node3D = part.pivot
	var period: float = spec.period
	pivot.rotation.y = part.yaw + deg_to_rad(spec.pan) * sweep(now / period + part.phase)
	var blink: Array = BLINK_BACKUP if backup else BLINK_POWERED
	var led: MeshInstance3D = part.led
	led.visible = fposmod(now / float(blink[0]) + part.phase, 1.0) < float(blink[1])


## Shows parts whose cells have appeared, and drops hanging ones whose cells are all gone.
func _test_hangs() -> void:
	var world := view.lab.world
	for part: Dictionary in _parts:
		if part.state != "waiting" and part.state != "hanging":
			continue
		var held := false
		for cell: Vector3i in part.cells:
			if world.get_voxel(cell) != VoxelMaterials.AIR:
				held = true
				break
		var pivot: Node3D = part.pivot
		if part.state == "waiting" and held:
			part.state = "hanging"
			pivot.visible = true
		elif part.state == "hanging" and not held:
			_drop(part)


## The part's cells are gone: dark, and falling to the floor under it.
func _drop(part: Dictionary) -> void:
	part.state = "falling"
	var led: MeshInstance3D = part.led
	led.visible = false
	var pivot: Node3D = part.pivot
	var from := pivot.global_position
	var hit: Dictionary = view.lab.world.raycast(from + Vector3.DOWN * part.height, Vector3.DOWN, FLOOR_REACH)
	var floor_y: float = (hit.position.y if hit.get("hit", false) else from.y - FLOOR_REACH)
	part.floor_y = floor_y + part.height
	part.speed = 0.0
	part.fell = 0.0


func _fall(part: Dictionary, delta: float) -> void:
	var pivot: Node3D = part.pivot
	part.fell += delta
	part.speed += GRAVITY * delta
	pivot.global_position.y -= part.speed * delta
	if pivot.global_position.y > part.floor_y and part.fell < MAX_FALL:
		return
	part.state = "gone"
	VoxelFx.burst(view, pivot.global_position + Vector3.DOWN * part.height * 0.5,
			[VoxelMaterials.DEFS[VoxelMaterials.PLASTIC].color, VoxelMaterials.DEFS[VoxelMaterials.RUBBER].color],
			10, 1.5, 0.1, 0.5, Vector3(0.0, -GRAVITY, 0.0))
	pivot.queue_free()
