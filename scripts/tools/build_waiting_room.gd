extends SceneTree
## Builds res://levels/waiting_room/: Fung AI Site 3 reception, where co-op players wait after the
## cubicle intro until everyone has signed in (docs/story.md, "The waiting room"; the play-time
## logic is scripts/story/waiting_room.gd). One room, a staff closet behind a locked door, and the
## admittance corridor behind the blast door `d_admit`. Refuses to overwrite an existing level
## unless --force is given.
##   godot --headless --path . --script res://scripts/tools/build_waiting_room.gd [-- --force]
## tests/waiting_room_test.gd calls build() into a scratch folder.

const LEVEL_NAME := "waiting_room"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const P := preload("res://scripts/world/props.gd")
const SIZE := Vector3i(6, 3, 6)
const T := 5
const FLOOR_Y := 30
const H := 35
## Inside of the reception room, [from, to).
const ROOM := [Vector3i(36, FLOOR_Y, 56), Vector3i(156, FLOOR_Y + H, 136)]
const CLOSET := [Vector3i(161, FLOOR_Y, 86), Vector3i(181, FLOOR_Y + H, 106)]
const CORRIDOR := [Vector3i(86, FLOOR_Y, 21), Vector3i(106, FLOOR_Y + H, 51)]
const DOOR_SIZES := {door_single = [12, 22], door_blast = [24, 24]}

const SIGN_IN_TEXT := "FUNG AI  |  SITE 3  |  RECEPTION\n\nPress E to sign in.\n\nPlease wait to be admitted. Your shift is important to us."
const NOTES := [
	["corkboard_a", "HANG IN THERE.\n(The cat is also a Fung AI asset. $40.)"],
	["corkboard_b", "CLONES ARE PROPERTY.\nCoffee is $4.\nPlease do not lick the specimens.\n- Fung AI People Operations"],
	["whiteboard", "Fung AI Quarterly: \"Mushrooms, the new silicon?\"\n\nQ3 highlights: 40 new racks. 0 incidents (reported). Night shift hiring: open."],
	["corkboard_small", "Fine print, illustrated: a small drawing of you, a small drawing of a clone of you, an equals sign, a dollar sign."],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var existing := LevelData.RES_DIR.path_join(LEVEL_NAME).path_join("level.json")
	if FileAccess.file_exists(existing) and "--force" not in OS.get_cmdline_user_args():
		print("build_waiting_room: %s exists; pass --force to overwrite" % existing)
		quit(1)
		return
	var result := build(root)
	print("build_waiting_room: saved %s (%d objects): %s" % [LEVEL_NAME, result.level.objects.size(), error_string(result.error)])
	result.world.free()
	quit(0 if result.error == OK else 1)


## Builds and saves the level. Returns {level, world, error}; the caller frees the world.
static func build(parent: Node) -> Dictionary:
	var world := VoxelWorld.new()
	world.size_in_chunks = SIZE
	world.immediate_remesh_limit = 0
	world.detach_floating = false
	parent.add_child(world)
	FacilityBuilder.make_ground(world, 3)

	var level := LevelData.new()
	level.name = LEVEL_NAME
	level.settings = LevelData.default_settings(SIZE, "rock")
	level.settings.room_thickness = T
	level.settings.start_power = "facility"
	level.settings.ambient_energy = 0.3

	var rooms := {
		reception = _room(level, "reception", "Reception", ROOM[0], ROOM[1], M.TILE_LIGHT, M.WALL_PAINT, 0),
		closet = _room(level, "closet", "Staff only", CLOSET[0], CLOSET[1], M.CONCRETE, M.CONCRETE_PANEL, 1),
		corridor = _room(level, "admittance", "Admittance", CORRIDOR[0], CORRIDOR[1], M.CONCRETE, M.CONCRETE_PANEL, 2),
	}
	_door(level, rooms.reception, rooms.closet, "door_single", "d_staff", {door_locked = true})
	_door(level, rooms.reception, rooms.corridor, "door_blast", "d_admit", {door_locked = true})

	var room: Dictionary = rooms.reception
	# The desk and its terminal face the room from the north wall; chairs along the south wall.
	_prop(level, room, "desk", 0.5, 0.06, P.SOUTH)
	_prop(level, room, "chair", 0.5, 0.0, P.SOUTH)
	_prop(level, room, "terminal", 0.62, 0.06, P.SOUTH, {id = "reception", text = SIGN_IN_TEXT, on_use = "signed_in", value = 0})
	for i in 5:
		_prop(level, room, "chair", 0.12 + 0.19 * i, 0.97, P.NORTH)
	_prop(level, room, "table_small", 0.3, 0.72, P.NORTH)
	_prop(level, room, "table_small", 0.7, 0.72, P.NORTH)
	_prop(level, room, "couch", 0.08, 0.5, P.EAST)
	_prop(level, room, "vending_machine", 0.03, 0.06, P.SOUTH, {use = "note", text = "OUT OF ORDER.\n\n$4 has been deducted from your wages for the attempt."})
	_prop(level, room, "water_cooler", 0.14, 0.06, P.SOUTH)
	_prop(level, room, "trash_can", 0.2, 0.06)
	_prop(level, room, "spore_tank", 0.9, 0.08, P.NORTH, {value = 6000})
	_prop(level, room, "locker", 0.97, 0.3, P.WEST)
	_prop(level, room, "locker", 0.97, 0.42, P.WEST)
	_prop(level, room, "locker", 0.97, 0.54, P.WEST)
	_wall_prop(level, room, "corkboard_small", "n", 0.84, 14, {use = "note", text = "AQUARIUM. Do not tap the glass. It taps back."})
	_wall_prop(level, room, NOTES[0][0], "w", 0.5, 14, {use = "note", text = NOTES[0][1]})
	_wall_prop(level, room, NOTES[1][0], "e", 0.8, 14, {use = "note", text = NOTES[1][1]})
	_wall_prop(level, room, NOTES[2][0], "s", 0.5, 16, {use = "note", text = NOTES[2][1]})
	_wall_prop(level, room, NOTES[3][0], "n", 0.3, 14, {use = "note", text = NOTES[3][1]})
	_prop(level, rooms.closet, "shelf_storage_a", 0.5, 0.05, P.SOUTH)
	_prop(level, rooms.closet, "barrel", 0.2, 0.8)

	var extent: Vector3i = room.to - room.from
	for i in 4:
		var spawn := LevelSchema.new_marker("spawn", Vector3(room.from) + Vector3((0.3 + 0.13 * i) * extent.x, 0.0, 0.55 * extent.z), 180.0)
		spawn.index = i + 1
		_add(level, "", spawn)
	for s: Vector2 in [Vector2(0.25, 0.5), Vector2(0.75, 0.5)]:
		var light := LevelSchema.new_marker("light", Vector3(room.from) + Vector3(s.x * extent.x, float(H - 4), s.y * extent.z))
		light.color = Color(1.0, 0.95, 0.85)
		light.energy = 1.6
		light.range = 9.0
		_add(level, "", light)
	var hall: Dictionary = rooms.corridor
	var hall_light := LevelSchema.new_marker("light", Vector3(hall.from) + Vector3(10.0, float(H - 4), 15.0))
	hall_light.color = Color(1.0, 0.3, 0.2)
	hall_light.energy = 1.2
	hall_light.range = 6.0
	_add(level, "", hall_light)
	_add(level, "", LevelSchema.new_marker("speaker", Vector3(room.from) + Vector3(0.5 * extent.x, 25.0, 0.3 * extent.z)))
	_add(level, "", LevelSchema.new_marker("speaker", Vector3(hall.from) + Vector3(10.0, 25.0, 15.0)))

	var structural := level.objects.values().filter(func(o: Dictionary) -> bool: return LevelSchema.is_structure(o))
	var op := LevelStructure.op({}, level.objects, structural, level.settings, world.get_size_in_voxels())
	WorldSync.run_op(world, op)
	# Rain-streaked "window" strip high on the south wall: glass over the rock.
	world.fill_box(Vector3i(room.from.x + 20, FLOOR_Y + 22, room.to.z), Vector3i(room.to.x - 20, FLOOR_Y + 30, room.to.z + T), M.GLASS)
	level.voxels = world.get_data()
	return {level = level, world = world, error = level.save()}


static func _add(level: LevelData, id: String, object: Dictionary) -> void:
	object.id = id if id != "" else level.new_id(object.get("type", object.get("kind", "o")))
	level.objects[object.id] = object


static func _room(level: LevelData, id: String, name: String, from: Vector3i, to: Vector3i, floor: int, wall: int, order: int) -> Dictionary:
	var room := LevelSchema.new_room(from, to, floor, wall, M.CONCRETE, T, order)
	room.name = name
	_add(level, id, room)
	return room


## A door in the wall between a and b (same rules as lab_builder.gd: the panel in the gap's middle
## layer, a doorway through the gap and a slot the panel slides into).
static func _door(level: LevelData, a: Dictionary, b: Dictionary, kind: String, id: String, fields: Dictionary) -> void:
	var wall := {}
	for axis in [0, 2]:
		var other := 2 if axis == 0 else 0
		var lo: int = maxi(a.from[other], b.from[other])
		var hi: int = mini(a.to[other], b.to[other])
		if hi - lo < 10:
			continue
		if a.to[axis] <= b.from[axis]:
			wall = {axis = axis, other = other, gap_lo = a.to[axis], gap_hi = b.from[axis], lo = lo, hi = hi}
		elif b.to[axis] <= a.from[axis]:
			wall = {axis = axis, other = other, gap_lo = b.to[axis], gap_hi = a.from[axis], lo = lo, hi = hi}
	if wall.is_empty():
		push_error("build_waiting_room: %s and %s don't share a wall" % [a.id, b.id])
		return
	var w: int = DOOR_SIZES[kind][0]
	var h: int = DOOR_SIZES[kind][1]
	var center: int = clampi((wall.lo + wall.hi) / 2, wall.lo + w / 2 + 3, wall.hi - w / 2 - 3)
	var depth: int = wall.gap_hi - wall.gap_lo
	var ahead := (depth - 1) / 2
	var origin := Vector3i.ZERO
	origin[wall.axis] = wall.gap_lo + ahead
	origin[wall.other] = center - w / 2
	origin.y = a.from.y
	var prop := LevelSchema.new_prop(kind, origin, P.EAST if wall.axis == 0 else P.NORTH)
	var offset := Vector3i.ZERO
	offset[wall.other] = w if center + w / 2 + w + 2 <= wall.hi else -w
	prop.door_offset = offset
	prop.door_ahead = ahead
	prop.door_behind = depth - 1 - ahead
	prop.value = 0
	for key in fields:
		prop[key] = fields[key]
	_add(level, id, prop)
	var size := Vector3i.ONE
	size[wall.other] = w
	size.y = h
	var through_from := origin
	through_from[wall.axis] = wall.gap_lo
	var through_to := origin + size
	through_to[wall.axis] = wall.gap_hi
	_add(level, "", LevelSchema.new_opening(through_from, through_to, a.id, "doorway", prop.id))
	_add(level, "", LevelSchema.new_opening(origin + offset, origin + offset + size, a.id, "slot", prop.id))


static func _prop(level: LevelData, room: Dictionary, name: String, fx: float, fz: float, facing := P.NORTH, fields := {}) -> void:
	var size := Vector3i(LevelSchema.prop_box({kind = "prop", name = name, origin = Vector3i.ZERO, facing = facing}).size)
	var free: Vector3i = room.to - room.from - size
	var origin := Vector3i(room.from.x + roundi(fx * free.x), room.from.y, room.from.z + roundi(fz * free.z))
	var prop := LevelSchema.new_prop(name, origin.clamp(room.from, (room.to - size).max(room.from)), facing)
	var id: String = fields.get("id", "")
	for key in fields:
		if key != "id":
			prop[key] = fields[key]
	_add(level, id, prop)


static func _wall_prop(level: LevelData, room: Dictionary, name: String, side: String, f: float, up: int, fields := {}) -> void:
	var facing: int = {n = P.SOUTH, s = P.NORTH, e = P.WEST, w = P.EAST}[side]
	var size := Vector3i(LevelSchema.prop_box({kind = "prop", name = name, origin = Vector3i.ZERO, facing = facing}).size)
	var free: Vector3i = room.to - room.from - size
	var origin := Vector3i(0, room.from.y + up, 0)
	match side:
		"n":
			origin.z = room.from.z
			origin.x = room.from.x + roundi(f * free.x)
		"s":
			origin.z = room.to.z - size.z
			origin.x = room.from.x + roundi(f * free.x)
		"e":
			origin.x = room.to.x - size.x
			origin.z = room.from.z + roundi(f * free.z)
		"w":
			origin.x = room.from.x
			origin.z = room.from.z + roundi(f * free.z)
	var prop := LevelSchema.new_prop(name, origin, facing)
	for key in fields:
		prop[key] = fields[key]
	_add(level, "", prop)
