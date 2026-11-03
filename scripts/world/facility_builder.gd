class_name FacilityBuilder
extends RefCounted
## Generates the underground facility: layered ground, then rooms lined with painted concrete and
## joined by corridors, the hatch shaft with its ladder, lights, and furniture from the prop
## library (assets/vox/props).
##
## Layout (voxel coordinates, 10cm voxels, floor at y = 40):
##   Atrium (center) with the hatch shaft in its north ceiling and a ladder up the north wall.
##   East: lab. West: break room. South: storage, then the grow hall at the far end.

const M := preload("res://scripts/voxel/voxel_materials.gd")
const P := preload("res://scripts/world/props.gd")

const FLOOR_Y := 40
const WALL := 3 # Thickness of room linings.

const ATRIUM := {from = Vector3i(206, 40, 206), to = Vector3i(306, 90, 306)}
const LAB := {from = Vector3i(356, 40, 206), to = Vector3i(456, 80, 306)}
const BREAK_ROOM := {from = Vector3i(76, 40, 216), to = Vector3i(156, 78, 296)}
const STORAGE := {from = Vector3i(216, 40, 356), to = Vector3i(296, 78, 416)}
const GROW_HALL := {from = Vector3i(146, 40, 436), to = Vector3i(366, 82, 496)}
const CORRIDORS := [
	{from = Vector3i(306, 40, 241), to = Vector3i(356, 72, 271)}, # Atrium - lab.
	{from = Vector3i(156, 40, 241), to = Vector3i(206, 72, 271)}, # Atrium - break room.
	{from = Vector3i(241, 40, 306), to = Vector3i(271, 72, 356)}, # Atrium - storage.
	{from = Vector3i(241, 40, 416), to = Vector3i(271, 72, 436)}, # Storage - grow hall.
]

## The shaft rises from the atrium ceiling to the top of the world. The ladder runs up its north
## wall from the atrium floor; the hatch plate seals the shaft at ceiling height.
const SHAFT_FROM := Vector3i(236, 90, 206)
const SHAFT_TO_XZ := Vector2i(276, 236)
const LADDER_X := Vector2i(251, 261)
const LADDER_Z := 206

var world: VoxelWorld
var lights: Node3D
var props: Props
var rng := RandomNumberGenerator.new()


## Builds everything and returns {spawn, spawn_yaw, hatch_from, hatch_to, hatch_control,
## ladder_foot (world space, on the atrium floor in front of the ladder), hatch_height, shaft_top,
## spore_beds: Array[AABB] (world space, the substrate surfaces), props: Props (with every
## placement, for live reload)}.
func build(voxel_world: VoxelWorld, lights_parent: Node3D, seed: int) -> Dictionary:
	world = voxel_world
	lights = lights_parent
	rng.seed = seed
	props = Props.new(world, seed + 1)

	_ground(seed)
	var rooms := [ATRIUM, LAB, BREAK_ROOM, STORAGE, GROW_HALL]
	for room in rooms + CORRIDORS:
		_shell(room)
	for room in rooms + CORRIDORS:
		world.fill_box(room.from, room.to, M.AIR)
	for room in rooms + CORRIDORS:
		_paint_walls(room)

	_shaft()
	_atrium()
	_lab()
	_break_room()
	_storage()
	var beds := _grow_hall()
	for corridor in CORRIDORS:
		_corridor(corridor)

	var size: Vector3i = world.get_size_in_voxels()
	var top := world.voxel_to_world(Vector3i(0, size.y - 1, 0)).y
	return {
		props = props,
		spawn = _to_world(Vector3(256, FLOOR_Y, 270)),
		spawn_yaw = PI, # Forward is -Z at yaw 0; PI faces +Z, down the storage corridor to the grow hall.
		hatch_from = Vector3i(SHAFT_FROM.x, SHAFT_FROM.y, LADDER_Z + 1),
		hatch_to = Vector3i(SHAFT_TO_XZ.x, SHAFT_FROM.y + 3, SHAFT_TO_XZ.y),
		hatch_control = _to_world(Vector3(256, SHAFT_FROM.y - 20, LADDER_Z + 3)),
		ladder_foot = _to_world(Vector3(256, FLOOR_Y, LADDER_Z + 3)),
		hatch_height = _to_world(Vector3(0, SHAFT_FROM.y, 0)).y,
		shaft_top = top,
		spore_beds = beds,
	}


# --- Ground ---------------------------------------------------------------------------------------

func _ground(seed: int) -> void:
	var size: Vector3i = world.get_size_in_voxels()
	world.fill_all(M.ROCK)
	var layers := PackedByteArray([M.BEDROCK, M.DEEP_STONE, M.ROCK, M.CLAY, M.ROCK, M.GRAVEL, M.ROCK, M.DIRT, M.ROCK])
	var tops := PackedFloat32Array([5, 34, 66, 76, 108, 114, 150, 166, 200])
	world.fill_layers(Vector3i.ZERO, Vector3i(size.x, 200, size.z), layers, tops, 7.0, 110.0, seed)

	# Pockets of loose ground, clustered so they read as deposits rather than polka dots.
	var hosts := PackedByteArray([M.ROCK, M.DEEP_STONE, M.CLAY])
	var kinds := [M.SAND, M.DIRT, M.GRAVEL, M.CLAY, M.SAND, M.DIRT]
	for i in 260:
		var kind: int = kinds[i % kinds.size()]
		var center := Vector3(rng.randf() * size.x, rng.randf_range(8.0, 190.0), rng.randf() * size.z)
		for j in rng.randi_range(2, 4):
			var offset := Vector3(rng.randf_range(-12, 12), rng.randf_range(-5, 5), rng.randf_range(-12, 12))
			world.replace_in_sphere(_to_world(center + offset), rng.randf_range(0.5, 1.6), kind, hosts)


# --- Rooms ----------------------------------------------------------------------------------------

## Solid lining around a room: painted walls, a concrete floor slab and ceiling.
func _shell(room: Dictionary) -> void:
	var outer_from: Vector3i = room.from - Vector3i(WALL, WALL, WALL)
	var outer_to: Vector3i = room.to + Vector3i(WALL, WALL, WALL)
	world.fill_box(outer_from, outer_to, M.WALL_PAINT)
	world.fill_box(outer_from, Vector3i(outer_to.x, room.from.y, outer_to.z), M.CONCRETE)
	world.fill_box(Vector3i(outer_from.x, room.to.y, outer_from.z), outer_to, M.CONCRETE)


## Darker band along the bottom of every wall.
func _paint_walls(room: Dictionary) -> void:
	var from: Vector3i = room.from - Vector3i(WALL, 0, WALL)
	var to: Vector3i = room.to + Vector3i(WALL, 0, WALL)
	world.replace_in_box(Vector3i(from.x, room.from.y, from.z), Vector3i(to.x, room.from.y + 11, to.z), M.WALL_LOWER, PackedByteArray([M.WALL_PAINT]))
	world.replace_in_box(Vector3i(from.x, room.from.y + 11, from.z), Vector3i(to.x, room.from.y + 12, to.z), M.STEEL, PackedByteArray([M.WALL_PAINT]))


func _floor_pattern(room: Dictionary, a: int, b: int, tile: int) -> void:
	var y: int = room.from.y - 1
	for z in range(room.from.z, room.to.z, tile):
		for x in range(room.from.x, room.to.x, tile):
			var material := a if ((x - room.from.x) / tile + (z - room.from.z) / tile) % 2 == 0 else b
			world.fill_box(Vector3i(x, y, z), Vector3i(mini(x + tile, room.to.x), y + 1, mini(z + tile, room.to.z)), material)


## A recessed lamp strip in the ceiling with a real light under it.
func _ceiling_light(room: Dictionary, x: int, z: int, color: Color, energy: float, light_range: float, shadows := false) -> void:
	var y: int = room.to.y
	world.fill_box(Vector3i(x - 2, y, z - 6), Vector3i(x + 2, y + 1, z + 6), M.STEEL)
	world.fill_box(Vector3i(x - 1, y, z - 5), Vector3i(x + 1, y + 1, z + 5), M.LAMP)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = shadows
	light.shadow_normal_bias = 3.0
	lights.add_child(light)
	light.position = _to_world(Vector3(x, y - 3, z))
	light.add_to_group("work_light")


## Red light that only comes on when the power dies.
func _emergency_light(x: int, y: int, z: int) -> void:
	world.fill_box(Vector3i(x - 1, y, z - 1), Vector3i(x + 1, y + 1, z + 1), M.EMERGENCY)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.12, 0.08)
	light.light_energy = 0.0
	light.omni_range = 7.0
	light.set_meta("on_energy", 0.7)
	lights.add_child(light)
	light.position = _to_world(Vector3(x, y - 2, z))
	light.add_to_group("emergency_light")


func _atrium() -> void:
	var r := ATRIUM
	var f: int = r.from.y
	# Hazard stripes at the foot of the ladder.
	for x in range(LADDER_X.x - 8, LADDER_X.y + 8, 2):
		world.fill_box(Vector3i(x, f - 1, r.from.z), Vector3i(x + 1, f, r.from.z + 14), M.WARNING)

	# Lockers along the west wall, with a bench in front of them.
	for z in range(222, 292, 5):
		props.place("locker", Vector3i(r.from.x, f, z), P.EAST)
	props.place("bench", Vector3i(r.from.x + 10, f, 235), P.EAST)
	props.place("bench", Vector3i(r.from.x + 10, f, 262), P.EAST)

	# Control desk beside the ladder, crates and barrels in the south-east corner.
	props.place("desk", Vector3i(272, f, r.from.z), P.SOUTH)
	props.place("chair", Vector3i(278, f, r.from.z + 9), P.NORTH)
	props.place("crate_8", Vector3i(286, f, 286))
	props.place("crate_6", Vector3i(296, f, 288))
	props.place("crate_5", Vector3i(288, f + 8, 287))
	props.place("barrel_hazard", Vector3i(298, f, 276))
	props.place("barrel", Vector3i(292, f, 278))
	props.place("corkboard_a", Vector3i(r.to.x - 1, f + 14, 230), P.WEST)
	props.place("trash_can", Vector3i(214, f, 300))

	_ceiling_light(r, 222, 256, Color(1, 0.88, 0.7), 2.2, 14.0, true)
	_ceiling_light(r, 290, 256, Color(1, 0.88, 0.7), 1.8, 12.0)
	_ceiling_light(r, 256, 290, Color(1, 0.88, 0.7), 1.6, 12.0)
	_emergency_light(256, r.to.y - 1, 300)
	_emergency_light(230, r.to.y - 1, 212)


func _shaft() -> void:
	var size: Vector3i = world.get_size_in_voxels()
	var from := SHAFT_FROM
	var to := Vector3i(SHAFT_TO_XZ.x, size.y, SHAFT_TO_XZ.y)
	world.fill_box(from - Vector3i(WALL, 0, WALL), to + Vector3i(WALL, 0, WALL), M.CONCRETE)
	world.fill_box(from, to, M.AIR)

	# Hazard paint on the atrium ceiling around the opening.
	world.replace_in_box(Vector3i(from.x - 6, from.y, from.z), Vector3i(to.x + 6, from.y + 1, to.z + 6), M.WARNING, PackedByteArray([M.CONCRETE]))

	# Ladder from the atrium floor all the way up: two rails and a rung every 3 voxels.
	for x in [LADDER_X.x, LADDER_X.y - 1]:
		world.fill_box(Vector3i(x, FLOOR_Y, LADDER_Z), Vector3i(x + 1, size.y, LADDER_Z + 1), M.LADDER)
	for y in range(FLOOR_Y + 2, size.y, 3):
		world.fill_box(Vector3i(LADDER_X.x + 1, y, LADDER_Z), Vector3i(LADDER_X.y - 1, y + 1, LADDER_Z + 1), M.LADDER)

	# Lamps up both side walls, fading into the dark above. Concrete rings break up the tube.
	for y in range(from.y + 14, size.y - 2, 28):
		world.fill_box(Vector3i(from.x - 1, y, 218), Vector3i(from.x, y + 2, 224), M.LAMP)
		world.fill_box(Vector3i(to.x, y, 218), Vector3i(to.x + 1, y + 2, 224), M.LAMP)
	for y in range(from.y + 28, size.y - 2, 28):
		world.fill_box(Vector3i(from.x, y, from.z + 1), Vector3i(from.x + 1, y + 2, to.z), M.STEEL)
		world.fill_box(Vector3i(to.x - 1, y, from.z + 1), Vector3i(to.x, y + 2, to.z), M.STEEL)
		world.fill_box(Vector3i(from.x, y, to.z - 1), Vector3i(to.x, y + 2, to.z), M.STEEL)


func _lab() -> void:
	var r := LAB
	var f: int = r.from.y
	_floor_pattern(r, M.TILE_LIGHT, M.TILE_DARK, 5)

	# Sample shelves along the north wall.
	for x in range(362, 444, 14):
		props.place("shelf_lab_" + "ab"[(x / 14) % 2], Vector3i(x, f, r.from.z), P.SOUTH)
	# Two rows of lab benches with stools.
	var bench := 0
	for x in [372, 410]:
		for z in [236, 266]:
			props.place("lab_bench_" + "abc"[bench % 3], Vector3i(x, f, z), P.NORTH if z == 236 else P.SOUTH)
			bench += 1
			for sx in range(x + 3, x + 24, 7):
				props.place("stool", Vector3i(sx, f, z - 5 if z == 236 else z + 9))
	# Fume hoods on the east wall, desks with computers along the south wall.
	props.place("fume_hood", Vector3i(r.to.x - 8, f, 220), P.WEST)
	props.place("fume_hood", Vector3i(r.to.x - 8, f, 236), P.WEST)
	for x in [366, 392, 418]:
		props.place("desk", Vector3i(x, f, r.to.z - 7), P.NORTH)
		props.place("chair", Vector3i(x + 6, f, r.to.z - 12), P.SOUTH)
	props.place("whiteboard", Vector3i(r.from.x, f + 14, 214), P.EAST)
	props.place("spore_tank", Vector3i(r.to.x - 6, f, 290))
	props.place("spore_tank", Vector3i(r.to.x - 6, f, 284))

	_ceiling_light(r, 386, 250, Color(0.85, 0.95, 1.0), 2.0, 13.0, true)
	_ceiling_light(r, 430, 250, Color(0.85, 0.95, 1.0), 1.8, 12.0)
	_ceiling_light(r, 406, 290, Color(0.85, 0.95, 1.0), 1.4, 10.0)
	_emergency_light(406, r.to.y - 1, 210)


func _break_room() -> void:
	var r := BREAK_ROOM
	var f: int = r.from.y
	# Plank flooring.
	for z in range(r.from.z, r.to.z, 3):
		world.fill_box(Vector3i(r.from.x, f - 1, z), Vector3i(r.to.x, f, z + 3), M.WOOD if (z / 3) % 2 == 0 else M.PLANK)

	# Kitchen along the north wall: counters, fridge, coffee, water cooler.
	props.place("counter_sink", Vector3i(84, f, r.from.z), P.SOUTH)
	props.place("counter_coffee", Vector3i(100, f, r.from.z), P.SOUTH)
	props.place("fridge", Vector3i(113, f, r.from.z), P.SOUTH)
	props.place("water_cooler", Vector3i(124, f, r.from.z), P.SOUTH)
	props.place("vending_machine", Vector3i(r.from.x, f, 262), P.EAST)
	props.place("trash_can", Vector3i(130, f, r.from.z + 1))

	# Table with chairs in the middle, couch against the south wall.
	props.place("table_large", Vector3i(104, f, 248), P.NORTH)
	for x in [106, 114]:
		props.place("chair", Vector3i(x, f, 243), P.SOUTH)
		props.place("chair", Vector3i(x, f, 259), P.NORTH)
	props.place("couch", Vector3i(96, f, r.to.z - 8), P.NORTH)
	props.place("table_small", Vector3i(100, f, r.to.z - 18), P.NORTH)
	props.place("corkboard_small", Vector3i(r.from.x + 30, f + 16, r.to.z - 1), P.NORTH)
	props.place("corkboard_tall", Vector3i(r.from.x, f + 15, 230), P.EAST)

	_ceiling_light(r, 116, 256, Color(1, 0.85, 0.65), 1.8, 11.0, true)
	_emergency_light(116, r.to.y - 1, 292)


func _storage() -> void:
	var r := STORAGE
	var f: int = r.from.y
	# Back-to-back shelving with an aisle down the middle to the grow hall corridor.
	for x in [222, 236, 264, 278]:
		props.place("shelf_storage_a", Vector3i(x, f, r.from.z + 18), P.SOUTH)
		props.place("shelf_storage_b", Vector3i(x, f, r.from.z + 23), P.NORTH)
	for i in 6:
		var x := rng.randi_range(r.from.x + 2, 228) if i % 2 == 0 else rng.randi_range(282, r.to.x - 9)
		props.place("crate_%d" % rng.randi_range(5, 8), Vector3i(x, f, rng.randi_range(r.from.z + 34, r.to.z - 10)))
	props.place("plank_stack", Vector3i(r.from.x + 2, f, r.from.z + 2), P.SOUTH)
	props.place("sandbags", Vector3i(r.to.x - 14, f, r.from.z + 2), P.SOUTH)
	for x in [r.from.x + 2, r.from.x + 8]:
		props.place("barrel_hazard" if x == r.from.x + 2 else "barrel", Vector3i(x, f, r.to.z - 7))

	_ceiling_light(r, 256, 386, Color(1, 0.9, 0.7), 1.4, 11.0)
	_emergency_light(256, r.to.y - 1, 412)


## Returns the substrate surfaces of the grow beds (world-space AABBs).
func _grow_hall() -> Array[AABB]:
	var r := GROW_HALL
	var f: int = r.from.y
	var beds: Array[AABB] = []
	for z in [446, 474]:
		for x in [156, 191, 286, 321]:
			props.place("grow_bed", Vector3i(x, f, z), P.NORTH)
			var surface_from := _to_world(Vector3(x + 1, f + 3, z + 1))
			beds.append(AABB(surface_from, Vector3(28, 0, 10) * world.voxel_size))
	for x in [r.from.x + 2, r.to.x - 6]:
		props.place("spore_tank", Vector3i(x, f, r.from.z + 2))
	props.place("shelf_lab_a", Vector3i(r.from.x + 8, f, r.from.z), P.SOUTH)
	# Irrigation pipe along the north wall.
	world.fill_box(Vector3i(r.from.x, r.to.y - 4, r.from.z), Vector3i(r.to.x, r.to.y - 3, r.from.z + 1), M.PIPE)
	world.fill_box(Vector3i(r.from.x, r.to.y - 4, r.to.z - 1), Vector3i(r.to.x, r.to.y - 3, r.to.z), M.PIPE)

	# Dim violet grow lights.
	for x in [176, 336]:
		_ceiling_light(r, x, 466, Color(0.75, 0.45, 1.0), 1.6, 12.0)
	_emergency_light(256, r.to.y - 1, 492)
	return beds


func _corridor(corridor: Dictionary) -> void:
	var from: Vector3i = corridor.from
	var to: Vector3i = corridor.to
	var along_x: bool = (to.x - from.x) > (to.z - from.z)
	# Pipes along both upper edges.
	if along_x:
		world.fill_box(Vector3i(from.x, to.y - 2, from.z), Vector3i(to.x, to.y - 1, from.z + 1), M.PIPE)
		world.fill_box(Vector3i(from.x, to.y - 4, to.z - 1), Vector3i(to.x, to.y - 3, to.z), M.STEEL)
		_ceiling_light(corridor, (from.x + to.x) / 2, (from.z + to.z) / 2, Color(1, 0.9, 0.75), 1.0, 7.0)
	else:
		world.fill_box(Vector3i(from.x, to.y - 2, from.z), Vector3i(from.x + 1, to.y - 1, to.z), M.PIPE)
		world.fill_box(Vector3i(to.x - 1, to.y - 4, from.z), Vector3i(to.x, to.y - 3, to.z), M.STEEL)
		_ceiling_light(corridor, (from.x + to.x) / 2, (from.z + to.z) / 2, Color(1, 0.9, 0.75), 1.0, 7.0)


func _to_world(voxel: Vector3) -> Vector3:
	return world.global_position + voxel * world.voxel_size
