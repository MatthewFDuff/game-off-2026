class_name PropPlacement
## Where a prop goes when it's placed at the cursor, by its mount (PropCatalog.mount_of):
##   floor    on an upward face its bottom rests on the surface; on a wall it drops to the floor
##            below, back against the wall, facing away from it; under a ceiling it drops to the floor
##   wall     on a wall face: back flush against it, facing out, bottom on the grid
##   ceiling  under a downward face: top flush against it
##   door     in a wall: a thin panel in the wall's middle layer, standing on the floor; it cuts a
##            doorway through the wall and a pocket beside it to slide into (LevelEdits)
##   any      floor, wall or ceiling, by the face
## Facing on a wall is automatic (out from it); the R rotation turns it from there, or sets it on a
## floor or ceiling. Along the surface the prop snaps to the grid, but always sits flush on it.
##
## A placement is valid when the prop overlaps no solid voxel and no other prop, and touches
## something on its mount side (a voxel or another prop: a lamp can stand on a desk). An overlapping
## ghost moves to the nearest free spot: sideways up to its footprint (grid snapping can overlap a
## wall by more than half), else out along the face's normal up to PUSH voxels (a crate aimed under
## a desk ends up on it).

const P := preload("res://scripts/world/props.gd")
const EditorIndex := preload("res://scripts/editor/editor_index.gd")

## Outward normals of each facing (a prop's front points that way).
const FACING_NORMALS: Array[Vector3i] = [Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0)]
## Farthest a ghost is pushed out along the normal, in voxels.
const PUSH := 32
## Deepest wall a door looks through, in voxels.
const MAX_WALL := 30


static func facing_of(normal: Vector3i) -> int:
	var i := FACING_NORMALS.find(normal)
	return i if i >= 0 else P.NORTH


## {origin, facing, valid, reason, mount} (+ door_ahead, door_behind, door_offset for doors) for
## prop_name at the cursor: cell is the empty cell in front of the aimed surface, solid the aimed
## voxel, normal the surface's outward normal. rotation is the R turns. ignore: a prop id not to
## collide with (the one being moved).
static func place(world: VoxelWorld, objects: Dictionary, prop_name: String, rotation: int, cell: Vector3i, solid: Vector3i,
		normal: Vector3i, grid: int, ignore := "") -> Dictionary:
	var mount := PropCatalog.mount_of(prop_name)
	var side := normal.y == 0 and normal != Vector3i.ZERO
	if mount == "any":
		mount = "floor" if normal == Vector3i.UP else ("ceiling" if normal == Vector3i.DOWN else "wall")
	var facing := (facing_of(normal) + rotation) % 4 if side and mount != "ceiling" else rotation % 4
	var size := _size(prop_name, facing)
	var out := {origin = cell, facing = facing, valid = false, reason = "", mount = mount}
	if (mount == "wall" or mount == "door") and not side:
		out.reason = "goes on a wall"
		return out
	if mount == "ceiling" and normal != Vector3i.DOWN:
		out.reason = "hangs from a ceiling"
		return out

	var from := Vector3i.ZERO
	# Centered on the cursor along the surface, on the grid.
	for a in [0, 2]:
		var start := cell[a] - size[a] / 2
		from[a] = roundi(float(start) / grid) * grid if grid > 1 else start
	if side:
		var n := 0 if normal.x != 0 else 2
		# Back flush against the wall: the box starts at the empty cell in front of it.
		from[n] = cell[n] if normal[n] > 0 else cell[n] + 1 - size[n]
	match mount:
		"floor":
			from.y = cell.y if normal == Vector3i.UP else RoomTools.floor_under(world, cell)
		"wall":
			var bottom := cell.y - size.y / 2
			from.y = roundi(float(bottom) / grid) * grid if grid > 1 else bottom
		"ceiling":
			from.y = cell.y + 1 - size.y
		"door":
			return _door(world, objects, out, solid, normal, from, size, cell)
	var free: Variant = _push_out(world, objects, from, size, normal, ignore)
	if free == null:
		out.origin = from
		out.reason = "no room for it here"
		return out
	from = free
	out.origin = from
	var box := AABB(Vector3(from), Vector3(size))
	if not touches(world, objects, box, mount, facing, ignore):
		out.reason = "needs something to sit on" if mount == "floor" else ("needs a wall behind it" if mount == "wall" else "needs a ceiling above it")
		return out
	out.valid = true
	return out


## A door: a panel in the wall's middle layer, on the floor, centered on the cursor along the wall;
## the wall in front of and behind it, and the slide (its width along the wall). The wall is as
## deep as the solid voxels until air on its far side; in rock with no far side in reach, it's the
## room's lining.
static func _door(world: VoxelWorld, objects: Dictionary, out: Dictionary, solid: Vector3i, normal: Vector3i, from: Vector3i, size: Vector3i,
		cell: Vector3i) -> Dictionary:
	var n := 0 if normal.x != 0 else 2
	var along := 2 if n == 0 else 0
	var depth := 0
	while depth < MAX_WALL and world.get_voxel(solid - normal * depth) != 0:
		depth += 1
	if depth >= MAX_WALL:
		var room_id := EditorIndex.room_at_of(objects, AABB(Vector3(solid) + Vector3.ONE * 0.25, Vector3.ONE * 0.5))
		depth = int(objects[room_id].thickness) if room_id != "" else 3
	var thickness: int = size[n]
	if depth < thickness:
		out.reason = "the wall is too thin"
		return out
	var ahead := (depth - thickness) / 2
	var near: int = solid[n] - normal[n] * ahead
	var far: int = near - normal[n] * (thickness - 1)
	from[n] = mini(near, far)
	from.y = RoomTools.floor_under(world, cell)
	var offset := Vector3i.ZERO
	offset[along] = size[along]
	out.origin = from
	out.door_ahead = ahead
	out.door_behind = depth - thickness - ahead
	out.door_offset = offset
	out.valid = true
	return out


## The prop's size turned to facing, in voxels.
static func _size(prop_name: String, facing: int) -> Vector3i:
	var box := LevelSchema.prop_box({kind = "prop", name = prop_name, origin = Vector3i.ZERO, facing = facing})
	return Vector3i(box.size)


## Whether the box overlaps solid voxels or another prop.
static func overlaps(world: VoxelWorld, objects: Dictionary, box: AABB, ignore := "") -> bool:
	var from := Vector3i(box.position)
	var to := Vector3i(box.end)
	var voxels: PackedByteArray = world.get_box(from, to)
	if voxels.count(0) != voxels.size():
		return true
	return _hits_prop(objects, box, ignore)


static func _hits_prop(objects: Dictionary, box: AABB, ignore: String) -> bool:
	# The editor's index (cached boxes in a grid) when these are the level's objects.
	var indexed: Variant = EditorIndex.hits_prop_of(objects, box, ignore)
	if indexed != null:
		return indexed
	for object: Dictionary in objects.values():
		if object.kind == "prop" and object.id != ignore and LevelSchema.prop_box(object).intersects(box):
			return true
	return false


## Touching something on the mount side: the layer under a floor prop, behind a wall prop (opposite
## its front), above a ceiling prop.
static func touches(world: VoxelWorld, objects: Dictionary, box: AABB, mount: String, facing: int, ignore := "") -> bool:
	var slab := box
	match mount:
		"wall":
			var back := -FACING_NORMALS[facing]
			var n := 0 if back.x != 0 else 2
			slab.size[n] = 1.0
			slab.position[n] = box.end[n] if back[n] > 0 else box.position[n] - 1.0
		"ceiling":
			slab.size.y = 1.0
			slab.position.y = box.end.y
		_:
			slab.size.y = 1.0
			slab.position.y = box.position.y - 1.0
	var voxels: PackedByteArray = world.get_box(Vector3i(slab.position), Vector3i(slab.end))
	if voxels.count(0) != voxels.size():
		return true
	return _hits_prop(objects, slab.grow(-0.01), ignore)


## The nearest free spot for the box: as it is, then sideways (up to its footprint), then pushed
## out along the normal (up to PUSH). null when there's none.
static func _push_out(world: VoxelWorld, objects: Dictionary, from: Vector3i, size: Vector3i, normal: Vector3i, ignore: String) -> Variant:
	var push := normal if normal != Vector3i.ZERO else Vector3i.UP
	var axis := 0 if push.x != 0 else (1 if push.y != 0 else 2)
	if not overlaps(world, objects, AABB(Vector3(from), Vector3(size)), ignore):
		return from
	var sideways: Array[Vector3i] = []
	for a in [0, 2]:
		if a == axis:
			continue
		for step in range(1, size[a] + 1):
			var offset := Vector3i.ZERO
			offset[a] = step
			sideways.append(offset)
			sideways.append(-offset)
	sideways.sort_custom(func(p: Vector3i, q: Vector3i) -> bool: return absi(p.x + p.z) < absi(q.x + q.z))
	for offset in sideways:
		var at := from + offset
		if not overlaps(world, objects, AABB(Vector3(at), Vector3(size)), ignore):
			return at
	for step in range(1, PUSH + 1):
		var at := from + push * step
		if not overlaps(world, objects, AABB(Vector3(at), Vector3(size)), ignore):
			return at
	return null


## Props that are floating (nothing on their mount side) or inside something, as [{id, reason}],
## for the level check. Doors are in walls on purpose and are left out.
static func problems(world: VoxelWorld, objects: Dictionary, within := AABB()) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var ids: Array = objects.keys()
	ids.sort()
	for id: String in ids:
		var object: Dictionary = objects[id]
		if object.kind != "prop" or LevelSchema.is_door(object):
			continue
		var box := LevelSchema.prop_box(object)
		if within.has_volume() and not within.intersects(box):
			continue
		var mount := PropCatalog.mount_of(object.name)
		# "any" props are held by whichever of floor, wall (behind them) or ceiling they touch.
		var mounts: Array = ["floor", "wall", "ceiling"] if mount == "any" else [mount]
		var voxels: PackedByteArray = world.get_box(Vector3i(box.position), Vector3i(box.end))
		if voxels.count(0) != voxels.size():
			found.append({id = id, reason = "inside a wall or floor"})
		elif not mounts.any(func(m: String) -> bool: return touches(world, objects, box, m, int(object.facing), id)):
			found.append({id = id, reason = "floating"})
	return found
