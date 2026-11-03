class_name LevelStructure
## Turns room and opening objects (LevelSchema) into WorldSync "structure" ops: the region a change
## can touch (the old and new boxes of what changed, linings included), the rooms and openings
## there before and after, and the level's base (what's left where no room is: rock for rock
## levels, any natural rock counting as base, or air). VoxelWorld.apply_structure does the voxels.

const M := preload("res://scripts/voxel/voxel_materials.gd")

## Materials that count as untouched ground in rock levels (layered rock and its pockets).
const NATURAL := [M.ROCK, M.DIRT, M.CLAY, M.SAND, M.GRAVEL, M.DEEP_STONE]


static func base_of(settings: Dictionary) -> int:
	return M.ROCK if settings.get("fill", "rock") == "rock" else M.AIR


static func base_set(settings: Dictionary) -> PackedByteArray:
	return PackedByteArray(NATURAL) if settings.get("fill", "rock") == "rock" else PackedByteArray([M.AIR])


## The voxels a room or opening shapes: a room's inside and lining, an opening's box.
static func bounds(object: Dictionary) -> AABB:
	if object.kind == "room":
		return LevelSchema.room_outer(object)
	return LevelSchema.box_of(object)


## The op for objects going from before to after (id -> object, the whole level's objects or just
## its rooms and openings), given what changed (old and new versions). {} if nothing structural
## changed or it's all outside the world.
static func op(before: Dictionary, after: Dictionary, changed: Array, settings: Dictionary, world_size: Vector3i) -> Dictionary:
	var region := AABB()
	var any := false
	for object: Dictionary in changed:
		if object.is_empty() or not LevelSchema.is_structure(object):
			continue
		var box := bounds(object)
		region = box if not any else region.merge(box)
		any = true
	if not any:
		return {}
	var from := Vector3i(region.position.floor()).max(Vector3i.ZERO)
	var to := Vector3i(region.end.ceil()).min(world_size)
	if from.x >= to.x or from.y >= to.y or from.z >= to.z:
		return {}
	var area := AABB(Vector3(from), Vector3(to - from))
	var packed_before := _pack(before, area)
	var packed_after := _pack(after, area)
	return {type = "structure", from = from, to = to, before_rooms = packed_before[0], after_rooms = packed_after[0],
			before_openings = packed_before[1], after_openings = packed_after[1], base = base_of(settings), base_set = base_set(settings)}


## The newest room whose lining (or inside) holds the box's center, or "".
static func room_at(objects: Dictionary, box: AABB) -> String:
	var center := box.get_center()
	var best := ""
	var best_order := -1
	for object: Dictionary in objects.values():
		if object.kind == "room" and LevelSchema.room_outer(object).has_point(center) and int(object.order) > best_order:
			best = object.id
			best_order = int(object.order)
	return best


## The order a new room gets: newer than every other.
static func next_order(objects: Dictionary) -> int:
	var order := 0
	for object: Dictionary in objects.values():
		if object.kind == "room":
			order = maxi(order, int(object.order) + 1)
	return order


## Rooms (oldest first) and openings touching region, packed for apply_structure.
static func _pack(objects: Dictionary, region: AABB) -> Array[PackedInt32Array]:
	var rooms: Array[Dictionary] = []
	var openings := PackedInt32Array()
	for object: Dictionary in objects.values():
		if object.kind == "room" and bounds(object).intersects(region):
			rooms.append(object)
		elif object.kind == "opening" and bounds(object).intersects(region):
			for v: Vector3i in [object.from, object.to]:
				openings.append_array([v.x, v.y, v.z])
	rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.order < b.order if a.order != b.order else str(a.id) < str(b.id))
	var packed := PackedInt32Array()
	for room in rooms:
		var from: Vector3i = room.from
		var to: Vector3i = room.to
		packed.append_array([from.x, from.y, from.z, to.x, to.y, to.z, room.floor, room.wall, room.ceiling, room.thickness])
	return [packed, openings]
