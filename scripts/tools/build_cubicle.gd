extends SceneTree
## Builds res://levels/cubicle/: the LLM operator's cubicle for the intro (docs/story.md, act 1;
## the scene is scripts/story/intro.gd). One 3 x 3 m cell of grey partitions: a computer desk with
## its monitor against the north wall, a chair in front of it (where the player sits), a drawer
## desk, a trash can, the "Hang in there" poster and the sticky note. Refuses to overwrite an
## existing level unless --force is given.
##   godot --headless --path . --script res://scripts/tools/build_cubicle.gd [-- --force]
## tests/intro_test.gd calls build() into a scratch folder.

const LEVEL_NAME := "cubicle"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const P := preload("res://scripts/world/props.gd")
const SIZE := Vector3i(2, 2, 2)
const T := 5
const FLOOR_Y := 20
const H := 30
## Inside of the cubicle, [from, to).
const ROOM := [Vector3i(17, FLOOR_Y, 17), Vector3i(47, FLOOR_Y + H, 47)]
## Ids the intro scene looks up.
const MONITOR_ID := "monitor"
const CHAIR_ID := "chair"

const POSTER_TEXT := "HANG\nIN\nTHERE"
const STICKY_TEXT := "PRESS SHIFT WHEN IT STOPS.\nDO NOT READ IT.\n- mgmt"


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
	result.world.free()
	quit(0 if result.error == OK else 1)


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
	level.settings.ambient_energy = 0.2
	level.settings.ambient_color = Color(0.45, 0.45, 0.5)

	var room := LevelSchema.new_room(ROOM[0], ROOM[1], M.TILE_DARK, M.CONCRETE_PANEL, M.CONCRETE, T, 0)
	room.name = "Cubicle"
	_add(level, "cubicle", room)

	# The computer desk faces south (its screen toward the chair), the chair faces north into it.
	_prop(level, room, "terminal", 0.5, 0.0, P.SOUTH, {id = MONITOR_ID, value = 0})
	_prop(level, room, "chair", 0.5, 0.52, P.NORTH, {id = CHAIR_ID, value = 0})
	_prop(level, room, "drawer_desk", 0.0, 0.55, P.EAST, {value = 0})
	_prop(level, room, "trash_can", 0.92, 0.1, P.NORTH, {value = 0})
	_prop(level, room, "stool", 0.05, 0.05, P.NORTH, {value = 0})
	_wall_prop(level, room, "corkboard_tall", "w", 0.2, 14, {use = "note", text = POSTER_TEXT, value = 0})
	_wall_prop(level, room, "corkboard_small", "n", 0.84, 18, {use = "note", text = STICKY_TEXT, value = 0})

	var extent: Vector3i = room.to - room.from
	# A warm desk lamp low over the monitor and a cold cast from the screen.
	var lamp := LevelSchema.new_marker("light", Vector3(room.from) + Vector3(0.5 * extent.x, 22.0, 0.2 * extent.z))
	lamp.color = Color(1.0, 0.85, 0.6)
	lamp.energy = 4.5
	lamp.range = 5.5
	_add(level, "", lamp)
	var screen := LevelSchema.new_marker("light", Vector3(room.from) + Vector3(0.5 * extent.x, 13.0, 0.3 * extent.z))
	screen.color = Color(0.4, 0.75, 1.0)
	screen.energy = 0.6
	screen.range = 2.2
	_add(level, "", screen)
	var spawn := LevelSchema.new_marker("spawn", Vector3(room.from) + Vector3(0.5 * extent.x, 0.0, 0.5 * extent.z), 0.0)
	spawn.index = 1
	_add(level, "", spawn)

	var structural := level.objects.values().filter(func(o: Dictionary) -> bool: return LevelSchema.is_structure(o))
	var op := LevelStructure.op({}, level.objects, structural, level.settings, world.get_size_in_voxels())
	WorldSync.run_op(world, op)
	# Partition tops: a lighter band along the top of every wall, as cubicle walls have.
	for side in 4:
		var from := Vector3i(room.from.x - T, FLOOR_Y + 26, room.from.z - T)
		var to := Vector3i(room.to.x + T, FLOOR_Y + 28, room.to.z + T)
		match side:
			0: to.z = room.from.z
			1: from.z = room.to.z
			2: to.x = room.from.x
			3: from.x = room.to.x
		world.replace_in_box(from, to, M.PLASTIC, PackedByteArray([M.CONCRETE_PANEL]))
	level.voxels = world.get_data()
	return {level = level, world = world, error = level.save()}


static func _add(level: LevelData, id: String, object: Dictionary) -> void:
	object.id = id if id != "" else level.new_id(object.get("type", object.get("kind", "o")))
	level.objects[object.id] = object


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
		prop[key] = fields[key]
	_add(level, "", prop)
