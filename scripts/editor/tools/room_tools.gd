class_name RoomTools
## Level editor helpers for rooms and openings (LevelSchema), all static: adopting a carved space as
## a room ("Room from space"), fitting an opening into a wall, and the edits that carry a room's
## openings, door props and contents along when it's resized, moved or duplicated.

## Largest room "Room from space" adopts, per axis, in voxels.
const MAX_SPACE := 400
## How far an opening digs looking for the far side of a wall, in voxels.
const MAX_WALL := 30


## The axis-aligned air box around an empty cell, grown a face at a time while the whole face is air
## (sideways first, then down to the floor and up to the ceiling), and the linings around it:
## {from, to, floor, wall, ceiling, thickness}, or {} when the cell isn't air.
static func space_around(world: VoxelWorld, start: Vector3i) -> Dictionary:
	if world.get_voxel(start) != 0:
		return {}
	var lo := start
	var hi := start + Vector3i.ONE
	var size: Vector3i = world.get_size_in_voxels()
	var directions := [Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(0, -1, 0), Vector3i(0, 1, 0)]
	var open := [true, true, true, true, true, true]
	while open.has(true):
		for i in directions.size():
			if not open[i]:
				continue
			var d: Vector3i = directions[i]
			var face_lo := lo
			var face_hi := hi
			for a in 3:
				if d[a] < 0:
					face_lo[a] = lo[a] - 1
					face_hi[a] = lo[a]
				elif d[a] > 0:
					face_lo[a] = hi[a]
					face_hi[a] = hi[a] + 1
			var axis := 0 if d.x != 0 else (1 if d.y != 0 else 2)
			if face_lo[axis] < 0 or face_hi[axis] > size[axis] or hi[axis] - lo[axis] >= MAX_SPACE:
				open[i] = false
				continue
			var face: PackedByteArray = world.get_box(face_lo, face_hi)
			if face.count(0) != face.size():
				open[i] = false
				continue
			if d[axis] < 0:
				lo[axis] -= 1
			else:
				hi[axis] += 1
	var center := (lo + hi) / 2
	var floor_cell := Vector3i(center.x, lo.y - 1, center.z)
	var ceiling_cell := Vector3i(center.x, hi.y, center.z)
	var wall_cell := Vector3i(lo.x - 1, (lo.y + hi.y) / 2, center.z)
	var thickness := mini(mini(_run(world, floor_cell, Vector3i.DOWN), _run(world, ceiling_cell, Vector3i.UP)), _run(world, wall_cell, Vector3i.LEFT))
	return {from = lo, to = hi, floor = world.get_voxel(floor_cell), wall = world.get_voxel(wall_cell), ceiling = world.get_voxel(ceiling_cell),
			thickness = clampi(thickness, 1, 10)}


## How many voxels from `from` along step share its material (at most 10).
static func _run(world: VoxelWorld, from: Vector3i, step: Vector3i) -> int:
	var material := world.get_voxel(from)
	var count := 0
	while count < 10 and world.get_voxel(from + step * count) == material and material != 0:
		count += 1
	return maxi(count, 1)


## An opening box through the wall at a wall voxel whose face (normal, horizontal) points into a
## room: width x height voxels centered on the cell along the wall, from `bottom` up, and as deep as
## the wall (until air on the far side). [from, to), or [] if the face isn't a wall.
static func opening_box(world: VoxelWorld, solid: Vector3i, normal: Vector3i, width: int, height: int, bottom: int, grid: int) -> Array[Vector3i]:
	if normal.y != 0 or normal == Vector3i.ZERO:
		return []
	var depth_axis := 0 if normal.x != 0 else 2
	var along := 2 if depth_axis == 0 else 0
	var into := -normal
	var depth := 0
	while depth < MAX_WALL and world.get_voxel(solid + into * depth) != 0:
		depth += 1
	var from := Vector3i.ZERO
	var to := Vector3i.ZERO
	var start := solid[along] - width / 2
	start = roundi(float(start) / grid) * grid if grid > 1 else start
	from[along] = start
	to[along] = start + width
	from.y = bottom
	to.y = bottom + height
	var far := solid[depth_axis] + into[depth_axis] * (depth - 1)
	from[depth_axis] = mini(solid[depth_axis], far)
	to[depth_axis] = maxi(solid[depth_axis], far) + 1
	return [from, to]


## The floor under a cell: the first air layer above solid, looking down at most 200 voxels.
static func floor_under(world: VoxelWorld, cell: Vector3i) -> int:
	var y := cell.y
	for i in 200:
		if y <= 0 or world.get_voxel(Vector3i(cell.x, y - 1, cell.z)) != 0:
			break
		y -= 1
	return y


## Which side of a room an opening is on, as the outward direction (Vector3i.ZERO: none).
static func side_of(room: Dictionary, opening: Dictionary) -> Vector3i:
	var center := (Vector3(opening.from) + Vector3(opening.to)) * 0.5
	var from := Vector3(room.from)
	var to := Vector3(room.to)
	if center.x < from.x:
		return Vector3i(-1, 0, 0)
	if center.x > to.x:
		return Vector3i(1, 0, 0)
	if center.z < from.z:
		return Vector3i(0, 0, -1)
	if center.z > to.z:
		return Vector3i(0, 0, 1)
	if center.y > to.y:
		return Vector3i(0, 1, 0)
	if center.y < from.y:
		return Vector3i(0, -1, 0)
	return Vector3i.ZERO


## The puts for a room going from before to after (same id): each opening in a wall that moved goes
## with it, kept within the room's span along the wall; a door's prop moves instead (its opening
## follows it). After a pure move (same size) everything inside comes along too when with_contents.
static func carry(objects: Dictionary, before: Dictionary, after: Dictionary, with_contents: bool) -> Array:
	var puts: Array = [[before.id, after]]
	var moved: Vector3i = after.from - before.from
	var same_size: bool = after.to - after.from == before.to - before.from
	var doors := {}
	for object: Dictionary in objects.values():
		if object.kind != "opening" or object.room != before.id:
			continue
		var side := side_of(before, object)
		var shift := moved if same_size else Vector3i.ZERO
		if not same_size:
			for a in 3:
				if side[a] < 0:
					shift[a] = after.from[a] - before.from[a]
				elif side[a] > 0:
					shift[a] = after.to[a] - before.to[a]
		var from: Vector3i = object.from + shift
		var to: Vector3i = object.to + shift
		# Keep it within the wall: along the wall and up it, inside the room's span.
		for a in 3:
			if side[a] != 0:
				continue
			var size: int = mini(to[a] - from[a], after.to[a] - after.from[a])
			var low := clampi(from[a], after.from[a], after.to[a] - size)
			from[a] = low
			to[a] = low + size
		if from == object.from and to == object.to:
			continue
		if object.door != "" and objects.has(object.door):
			var door: Dictionary = objects[object.door].duplicate()
			door.origin += from - object.from
			puts.append([door.id, door])
			doors[door.id] = true
		else:
			var opening := object.duplicate()
			opening.from = from
			opening.to = to
			puts.append([opening.id, opening])
	if with_contents and same_size and moved != Vector3i.ZERO:
		var inside := AABB(Vector3(before.from), Vector3(before.to - before.from))
		for object: Dictionary in objects.values():
			if not object.kind in ["prop", "marker"] or doors.has(object.id) or not inside.has_point(LevelSchema.box_of(object).get_center()):
				continue
			var copy := object.duplicate()
			if copy.kind == "prop":
				copy.origin += moved
			else:
				copy.position += Vector3(moved)
			puts.append([copy.id, copy])
	return puts


## The puts that duplicate a room at offset: the room (newest), its openings and door props, and
## (with_contents) the props and markers inside. Ids are fresh; openings point at the new room.
static func duplicate(objects: Dictionary, room: Dictionary, offset: Vector3i, with_contents: bool) -> Array:
	var copy := room.duplicate()
	copy.id = ""
	copy.from += offset
	copy.to += offset
	copy.order = LevelStructure.next_order(objects)
	var puts: Array = [["", copy]]
	var inside := AABB(Vector3(room.from), Vector3(room.to - room.from))
	for object: Dictionary in objects.values():
		var take := false
		if object.kind == "opening" and object.room == room.id:
			if object.door != "":
				continue # Its door prop is copied below and cuts its own.
			var opening := object.duplicate()
			opening.id = ""
			opening.from += offset
			opening.to += offset
			opening.room = "$0"
			puts.append(["", opening])
			continue
		if object.kind == "prop" and LevelSchema.is_door(object):
			take = _linked_to(objects, object.id, room.id)
		elif with_contents and object.kind in ["prop", "marker"]:
			take = inside.has_point(LevelSchema.box_of(object).get_center())
		if take:
			var thing := object.duplicate()
			thing.id = ""
			if thing.kind == "prop":
				thing.origin += offset
			else:
				thing.position += Vector3(offset)
			puts.append(["", thing])
	return puts


static func _linked_to(objects: Dictionary, door_id: String, room_id: String) -> bool:
	for object: Dictionary in objects.values():
		if object.kind == "opening" and object.door == door_id and object.room == room_id:
			return true
	return false
