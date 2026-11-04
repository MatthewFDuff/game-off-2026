extends SceneTree
## Builds res://levels/cubicle/: the LLM operator's cubicle, which is the game's menu
## (docs/cubicle-menu.md; the scene is scripts/story/cubicle.gd). One 3 x 3 m cell of grey
## partitions: a computer desk with its monitor against the north wall (a rubber duck on it), a
## chair in front of it, a drawer desk (a fake plant on it), a trash can, a sleeping bag along the
## south partition, the "Hang in there" poster, the sticky note and the nameplate. A 1 m opening in
## the south partition gives onto a 2 m hallway running east to west, with three dark cubicles on
## its far side (desk, monitor, chair). The trigger `t_leave` fills the opening; the scene keeps the
## player in. Refuses to overwrite an existing level unless --force is given.
##   godot --headless --path . --script res://scripts/tools/build_cubicle.gd [-- --force]
## tests/cubicle_test.gd calls build() into a scratch folder.

const LEVEL_NAME := "cubicle"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const P := preload("res://scripts/world/props.gd")
## 19.2 x 6.4 x 12.8 m.
const SIZE := Vector3i(6, 2, 4)
const T := 5
const FLOOR_Y := 33
const H := 30
## Inside of the operator's cubicle, [from, to): inside one 32-voxel chunk (3, 1, 1) with the faces
## of its lining, so no chunk seam runs across its walls, floor or ceiling.
const ROOM := [Vector3i(97, FLOOR_Y, 33), Vector3i(127, FLOOR_Y + H, 63)]
## The hallway south of it, the length of the row.
const HALL := [Vector3i(46, FLOOR_Y, 68), Vector3i(178, FLOOR_Y + H, 88)]
## The three cubicles across the hallway (x ranges; z from HALL's far lining).
const BAYS := [[62, 92], [97, 127], [132, 162]]
const BAY_Z := [93, 123]
## The opening in the cubicle's south partition: 1 m wide at its east end, up to the partition's
## top band.
const OPENING_X := [117, 127]
const OPENING_HEIGHT := 26
## Ids the scene looks up.
const MONITOR_ID := "monitor"
const CHAIR_ID := "chair"
const DUCK_ID := "duck"
const PLANT_ID := "plant"
const BAG_ID := "sleeping_bag"
const NAMEPLATE_ID := "nameplate"
const LEAVE_ID := "t_leave"

const POSTER_TEXT := "HANG\nIN\nTHERE"
const STICKY_TEXT := "PRESS SHIFT WHEN IT STOPS.\nDO NOT READ IT.\n- mgmt"
## The scene rewrites it with the employee's name and balance.
const NAMEPLATE_TEXT := "EMPLOYEE\nLLM Operator\nBalance owed to Fung AI: $0"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var existing := LevelData.RES_DIR.path_join(LEVEL_NAME).path_join("level.json")
	if FileAccess.file_exists(existing) and "--force" not in OS.get_cmdline_user_args():
		print("build_cubicle: %s exists; pass --force to overwrite" % existing)
		quit(1)
		return
	var result := build(root)
	print("build_cubicle: saved %s (%d objects): %s" % [LEVEL_NAME, result.level.objects.size(), error_string(result.error)])
	if not P.missing.is_empty():
		print("build_cubicle: missing prop models: %s" % ", ".join(P.missing))
	result.world.free()
	quit(0 if result.error == OK and P.missing.is_empty() else 1)


## Builds and saves the level. Returns {level, world, error}; the caller frees the world.
static func build(parent: Node) -> Dictionary:
	var world := VoxelWorld.new()
	world.size_in_chunks = SIZE
	world.immediate_remesh_limit = 0
	world.detach_floating = false
	parent.add_child(world)
	world.fill_all(M.ROCK)

	var level := LevelData.new()
	level.name = LEVEL_NAME
	level.settings = LevelData.default_settings(SIZE, "rock")
	level.settings.room_thickness = T
	level.settings.start_power = "facility"
	level.settings.start_unarmed = true
	level.settings.ambient_energy = 0.12
	level.settings.ambient_color = Color(0.45, 0.45, 0.5)

	var room := _room(level, "cubicle", "Cubicle", ROOM[0], ROOM[1], 0)
	var hall := _room(level, "hallway", "Hallway", HALL[0], HALL[1], 1)
	# The opening: through the cubicle's south partition (which is also the hallway's north one).
	_add(level, "", LevelSchema.new_opening(Vector3i(OPENING_X[0], FLOOR_Y, room.to.z),
			Vector3i(OPENING_X[1], FLOOR_Y + OPENING_HEIGHT, hall.from.z), room.id))

	# The computer desk faces south (its screen toward the chair), the chair faces north into it.
	var desk := _prop(level, room, "terminal", 0.5, 0.0, P.SOUTH, {id = MONITOR_ID, value = 0})
	_prop(level, room, "chair", 0.5, 0.52, P.NORTH, {id = CHAIR_ID, value = 0})
	var drawers := _prop(level, room, "drawer_desk", 0.0, 0.4, P.EAST, {value = 0})
	_prop(level, room, "trash_can", 0.92, 0.1, P.NORTH, {value = 0})
	_prop(level, room, "stool", 0.05, 0.05, P.NORTH, {value = 0})
	# Along the south partition, west of the opening, its head end toward the corner.
	_prop(level, room, "sleeping_bag", 0.0, 1.0, P.EAST, {id = BAG_ID, value = 0})
	# On the desks: the duck beside the keyboard, the plant on the drawer desk by the monitor (the
	# computer desk has no 4 x 4 voxels clear).
	_on_top(level, desk, "rubber_duck", Vector2(1.0, 1.0), P.SOUTH, {id = DUCK_ID, value = 0})
	if not _on_top(level, desk, "fake_plant", Vector2(0.0, 0.0), P.SOUTH, {id = PLANT_ID, value = 0}):
		_on_top(level, drawers, "fake_plant", Vector2(0.5, 0.0), P.SOUTH, {id = PLANT_ID, value = 0})
	_wall_prop(level, room, "corkboard_tall", "w", 0.2, 14, {id = "poster", use = "note", text = POSTER_TEXT, value = 0})
	_wall_prop(level, room, "corkboard_small", "n", 0.84, 18, {id = "sticky", use = "note", text = STICKY_TEXT, value = 0})
	_wall_prop(level, room, "corkboard_small", "e", 1.0, 14, {id = NAMEPLATE_ID, use = "note", text = NAMEPLATE_TEXT, value = 0})

	# Across the hallway: three dark cubicles, each open onto it, a desk against the far partition.
	for i in BAYS.size():
		var bay := _room(level, "bay_%d" % (i + 1), "Cubicle %d" % (i + 1),
				Vector3i(BAYS[i][0], FLOOR_Y, BAY_Z[0]), Vector3i(BAYS[i][1], FLOOR_Y + H, BAY_Z[1]), 2 + i)
		var middle: int = (bay.from.x + bay.to.x) / 2
		_add(level, "", LevelSchema.new_opening(Vector3i(middle - 5, FLOOR_Y, hall.to.z),
				Vector3i(middle + 5, FLOOR_Y + OPENING_HEIGHT, bay.from.z), bay.id))
		_prop(level, bay, "terminal", 0.5, 1.0, P.NORTH, {id = "bay_%d_monitor" % (i + 1), use = "none", value = 0})
		_prop(level, bay, "chair", 0.45 + 0.1 * i, 0.5, P.SOUTH, {value = 0})

	var extent: Vector3i = room.to - room.from
	# A warm desk lamp low over the monitor and a cold cast from the screen.
	var lamp := LevelSchema.new_marker("light", Vector3(room.from) + Vector3(0.5 * extent.x, 22.0, 0.2 * extent.z))
	lamp.color = Color(1.0, 0.85, 0.6)
	lamp.energy = 1.3
	lamp.range = 4.5
	_add(level, "", lamp)
	var screen := LevelSchema.new_marker("light", Vector3(room.from) + Vector3(0.5 * extent.x, 13.0, 0.3 * extent.z))
	screen.color = Color(0.4, 0.75, 1.0)
	screen.energy = 0.5
	screen.range = 2.2
	_add(level, "", screen)
	# The hallway: one dim ceiling light every other bay.
	for i in [0, 2]:
		var bay_light := LevelSchema.new_marker("light", Vector3((BAYS[i][0] + BAYS[i][1]) * 0.5, float(FLOOR_Y + H - 2), (HALL[0].z + HALL[1].z) * 0.5))
		bay_light.color = Color(0.7, 0.8, 1.0)
		bay_light.energy = 0.45
		bay_light.range = 6.0
		_add(level, "", bay_light)
	_add(level, "", LevelSchema.new_marker("speaker", Vector3(room.from) + Vector3(0.5 * extent.x, float(H - 2), 0.5 * extent.z)))

	# Standing beside the chair (east of it), facing the monitor's screen.
	var chair_box := LevelSchema.prop_box(level.objects[CHAIR_ID])
	var desk_box := LevelSchema.prop_box(desk)
	var feet := Vector3(chair_box.end.x + 6.0, float(FLOOR_Y), chair_box.get_center().z + 2.0)
	var toward := desk_box.get_center() - feet
	var spawn := LevelSchema.new_marker("spawn", feet, rad_to_deg(atan2(-toward.x, -toward.z)))
	spawn.index = 1
	_add(level, "", spawn)

	# The doorway's trigger: its full width and height, one voxel deep into the hallway.
	var leave := LevelSchema.new_marker("trigger", Vector3((OPENING_X[0] + OPENING_X[1]) * 0.5, float(FLOOR_Y), (room.to.z + hall.from.z + 1) * 0.5))
	leave.size = Vector3i(OPENING_X[1] - OPENING_X[0], OPENING_HEIGHT, hall.from.z + 1 - room.to.z)
	leave.repeat = true
	_add(level, LEAVE_ID, leave)

	var structural := level.objects.values().filter(func(o: Dictionary) -> bool: return LevelSchema.is_structure(o))
	var op := LevelStructure.op({}, level.objects, structural, level.settings, world.get_size_in_voxels())
	WorldSync.run_op(world, op)
	# Partition tops: a lighter band along the top of every partition, as cubicle walls have.
	var span := world.get_size_in_voxels()
	world.replace_in_box(Vector3i(0, FLOOR_Y + 26, 0), Vector3i(span.x, FLOOR_Y + 28, span.z), M.PLASTIC, PackedByteArray([M.CONCRETE_PANEL]))
	level.voxels = world.get_data()
	return {level = level, world = world, error = level.save()}


static func _add(level: LevelData, id: String, object: Dictionary) -> void:
	object.id = id if id != "" else level.new_id(object.get("type", object.get("kind", "o")))
	if level.objects.has(object.id):
		push_error("build_cubicle: two objects with the id %s" % object.id)
	level.objects[object.id] = object


static func _room(level: LevelData, id: String, name: String, from: Vector3i, to: Vector3i, order: int) -> Dictionary:
	var room := LevelSchema.new_room(from, to, M.TILE_DARK, M.CONCRETE_PANEL, M.CONCRETE, T, order)
	room.name = name
	_add(level, id, room)
	return room


static func _prop(level: LevelData, room: Dictionary, name: String, fx: float, fz: float, facing := P.NORTH, fields := {}) -> Dictionary:
	var size := Vector3i(LevelSchema.prop_box({kind = "prop", name = name, origin = Vector3i.ZERO, facing = facing}).size)
	var free: Vector3i = room.to - room.from - size
	var origin := Vector3i(room.from.x + roundi(fx * free.x), room.from.y, room.from.z + roundi(fz * free.z))
	var prop := LevelSchema.new_prop(name, origin.clamp(room.from, (room.to - size).max(room.from)), facing)
	var id: String = fields.get("id", "")
	for key in fields:
		if key != "id":
			prop[key] = fields[key]
	_add(level, id, prop)
	return prop


## Stands prop `name` on the top of `support` (another prop): the top is the layer above the
## support model's fullest layer (a desk's slab); the spot is the clear, fully supported footprint
## nearest `prefer` (fractions of the support's box in world x and z). False if nothing fits.
static func _on_top(level: LevelData, support: Dictionary, name: String, prefer: Vector2, facing: int, fields := {}) -> bool:
	var base_model := P.load_prop(support.name)
	var model := P.load_prop(name)
	if base_model.is_empty() or model.is_empty():
		return false
	var base := P.orient(base_model, int(support.facing))
	var size: Vector3i = base.size
	var voxels: PackedByteArray = base.voxels
	var filled := func(x: int, y: int, z: int) -> bool: return voxels[x + y * size.x + z * size.x * size.y] != 0
	var top := 0
	var best_count := -1
	for y in size.y:
		var count := 0
		for z in size.z:
			for x in size.x:
				if filled.call(x, y, z):
					count += 1
		if count > best_count:
			best_count = count
			top = y + 1
	var foot := Vector3i(LevelSchema.prop_box({kind = "prop", name = name, origin = Vector3i.ZERO, facing = facing}).size)
	var target := Vector2(prefer.x * (size.x - foot.x), prefer.y * (size.z - foot.z))
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for z0 in size.z - foot.z + 1:
		for x0 in size.x - foot.x + 1:
			var ok := true
			for z in range(z0, z0 + foot.z):
				for x in range(x0, x0 + foot.x):
					if not filled.call(x, top - 1, z):
						ok = false
					for y in range(top, mini(top + foot.y, size.y)):
						if filled.call(x, y, z):
							ok = false
			var distance := Vector2(x0, z0).distance_to(target)
			if ok and distance < best_distance:
				best_distance = distance
				best = Vector2i(x0, z0)
	if best.x < 0:
		return false
	var origin: Vector3i = support.origin + Vector3i(best.x, top, best.y)
	var prop := LevelSchema.new_prop(name, origin, facing)
	for key in fields:
		if key != "id":
			prop[key] = fields[key]
	_add(level, fields.get("id", ""), prop)
	return true


static func _wall_prop(level: LevelData, room: Dictionary, name: String, side: String, f: float, up: int, fields := {}) -> void:
	var facing: int = {n = P.SOUTH, s = P.NORTH, e = P.WEST, w = P.EAST}[side]
	var size := Vector3i(LevelSchema.prop_box({kind = "prop", name = name, origin = Vector3i.ZERO, facing = facing}).size)
	var free: Vector3i = room.to - room.from - size
	var origin := Vector3i(room.from.x, room.from.y + up, room.from.z)
	match side:
		"n":
			origin.x += roundi(f * free.x)
		"s":
			origin.z = room.to.z - size.z
			origin.x += roundi(f * free.x)
		"e":
			origin.x = room.to.x - size.x
			origin.z += roundi(f * free.z)
		"w":
			origin.z += roundi(f * free.z)
	var prop := LevelSchema.new_prop(name, origin, facing)
	for key in fields:
		if key != "id":
			prop[key] = fields[key]
	_add(level, fields.get("id", ""), prop)
