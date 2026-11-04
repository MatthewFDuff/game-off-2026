class_name LevelData
extends RefCounted
## A level: settings, the base voxels (terrain and everything built, without props), and its
## objects (props and markers, see LevelSchema). Saved as a folder:
##   voxels.bin   VoxelWorld.get_data(), zstd-compressed
##   level.json   name, settings and objects, pretty-printed with sorted keys for readable diffs
##
## Levels live in res://levels/ (committed) when running from the Godot editor, and in
## user://levels/ otherwise, since an exported game can't write into its own files.

const RES_DIR := "res://levels/"
const USER_DIR := "user://levels/"
const FORMAT := 1

## Settings: size_in_chunks, fill, ambient / fog, room-tool defaults, start_power (the power state
## play begins in: "facility" or "backup"; see LevelPlay.power), start_unarmed (no spore shooter
## until one is picked up; LevelPlay.armed) and spawns_dormant (nothing spawns until a trigger's
## `wake` action; HordeDirector.dormant). Missing keys take defaults.

## Keys whose values are vectors / colors; JSON stores them as arrays / hex strings.
const VECTOR3I_KEYS := ["origin", "size", "door_offset", "size_in_chunks", "from", "to", "a", "b"]
const VECTOR3_KEYS := ["position"]
const COLOR_KEYS := ["color", "ambient_color", "fog_color"]

## Tests point this at a scratch folder so they never write over real levels.
static var save_dir_override := ""

var name := ""
var settings := {}
## id -> object dictionary.
var objects := {}
var voxels := PackedByteArray()
var next_id := 1


static func default_settings(size_in_chunks: Vector3i, fill: String) -> Dictionary:
	return {
		size_in_chunks = size_in_chunks,
		fill = fill,
		ambient_color = Color(0.5, 0.5, 0.56),
		ambient_energy = 0.25,
		fog_color = Color(0.015, 0.015, 0.02),
		fog_density = 0.02,
		room_floor = VoxelMaterials.CONCRETE,
		room_wall = VoxelMaterials.WALL_PAINT,
		room_ceiling = VoxelMaterials.CONCRETE,
		room_thickness = 3,
		start_power = "facility",
	}


## A new level filled with layered rock to carve into ("rock") or nothing but air ("empty").
## Needs a node in the tree to build the terrain under.
static func create(level_name: String, size_in_chunks: Vector3i, fill: String, parent: Node) -> LevelData:
	var level := LevelData.new()
	level.name = level_name
	level.settings = default_settings(size_in_chunks, fill)
	var world := VoxelWorld.new()
	world.size_in_chunks = size_in_chunks
	world.immediate_remesh_limit = 0
	world.detach_floating = false
	parent.add_child(world)
	if fill == "rock":
		FacilityBuilder.make_ground(world, hash(level_name))
	else:
		world.fill_all(VoxelMaterials.AIR)
	level._add_starter(world)
	level.voxels = world.get_data()
	world.free()
	return level


## Somewhere to start from, so a new level isn't solid rock or empty space: a 10 x 10 m room in the
## middle (rock; a room object, so it can be resized) or a floor slab (empty), with a spawn and a light.
func _add_starter(world: VoxelWorld) -> void:
	var size: Vector3i = world.get_size_in_voxels()
	# Rock: a room 4 m down. Empty: a slab on the world's bottom, the ground you build on.
	var floor_y := mini(40, size.y / 4) if settings.fill == "rock" else 3
	var center := Vector3i(size.x / 2, floor_y, size.z / 2)
	var half := Vector3i(50, 0, 50)
	if settings.fill == "rock":
		var room := LevelSchema.new_room(center - half, center + half + Vector3i(0, 35, 0), settings.room_floor, settings.room_wall,
				settings.room_ceiling, settings.room_thickness, 0)
		room.id = new_id("room")
		objects[room.id] = room
		WorldSync.run_op(world, LevelStructure.op({}, {room.id: room}, [room], settings, size))
	else:
		# Build mode: one storey on a starter floor (LevelBuild).
		var storeys := LevelBuild.new_storeys(floor_y)
		var ground := LevelBuild.new_slab("floor", 0)
		ground.shapes.append(LevelBuild.rect_shape(center - half, center + half, settings.room_floor))
		objects[storeys.id] = storeys
		objects[ground.id] = ground
		WorldSync.run_op(world, LevelStructure.op({}, objects, [storeys, ground], settings, size))
	var spawn := LevelSchema.new_marker("spawn", Vector3(center) + Vector3(0.5, 0.0, 10.5), 180.0)
	spawn.id = new_id("spawn")
	objects[spawn.id] = spawn
	var light := LevelSchema.new_marker("light", Vector3(center) + Vector3(0.5, 32.0, 0.5))
	light.range = 16.0
	light.id = new_id("light")
	objects[light.id] = light


## Names of every saved level, from both folders.
static func list() -> PackedStringArray:
	var names := PackedStringArray()
	for dir in [RES_DIR, USER_DIR]:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for sub in DirAccess.get_directories_at(dir):
			if FileAccess.file_exists(dir.path_join(sub).path_join("level.json")) and sub not in names:
				names.append(sub)
	names.sort()
	return names


static func save_dir() -> String:
	if save_dir_override != "":
		return save_dir_override
	return RES_DIR if OS.has_feature("editor") else USER_DIR


## Loads a level by name: the writable folder's copy first, then the shipped one. null if missing.
static func load_level(level_name: String) -> LevelData:
	for dir in [save_dir(), RES_DIR]:
		var folder: String = dir.path_join(level_name)
		if not FileAccess.file_exists(folder.path_join("level.json")):
			continue
		var level := from_json(FileAccess.get_file_as_string(folder.path_join("level.json")))
		if level == null:
			push_error("level %s: level.json is invalid" % level_name)
			return null
		level.name = level_name # The folder decides, so a copied or renamed folder saves to itself.
		var packed := FileAccess.get_file_as_bytes(folder.path_join("voxels.bin"))
		level.voxels = _unpack(packed)
		if level.voxels.is_empty():
			push_error("level %s: voxels.bin is missing or invalid" % level_name)
			return null
		return level
	return null


func save() -> Error:
	var folder := save_dir().path_join(name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(folder.path_join("level.json"), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(to_json())
	file = FileAccess.open(folder.path_join("voxels.bin"), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(_pack(voxels))
	return OK


## A fresh unique id like "light_12".
func new_id(prefix: String) -> String:
	while objects.has("%s_%d" % [prefix, next_id]):
		next_id += 1
	next_id += 1
	return "%s_%d" % [prefix, next_id - 1]


func to_json() -> String:
	var objects_out := {}
	for id: String in objects:
		objects_out[id] = _encode(objects[id])
	var text := JSON.stringify({format = FORMAT, name = name, next_id = next_id, settings = _encode(settings), objects = objects_out}, "\t", true)
	# Keep vectors on one line: [1, 2, 3] rather than five lines each.
	var vectors := RegEx.create_from_string("\\[\\s*(-?[\\d.e+-]+),\\s*(-?[\\d.e+-]+),\\s*(-?[\\d.e+-]+)\\s*\\]")
	return vectors.sub(text, "[$1, $2, $3]", true) + "\n"


static func from_json(text: String) -> LevelData:
	var data = JSON.parse_string(text)
	if not data is Dictionary or not data.has("settings"):
		return null
	var level := LevelData.new()
	level.name = data.get("name", "")
	level.next_id = int(data.get("next_id", 1))
	level.settings = _decode(data.settings)
	for id: String in data.get("objects", {}):
		var object := _decode(data.objects[id])
		object.id = id
		LevelSchema.fill_defaults(object)
		level.objects[id] = object
	return level


## Settings and objects (not voxels) as compressed bytes, for sending to peers.
func encode_info() -> PackedByteArray:
	var text := to_json().to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, text.size())
	out.append_array(text.compress(FileAccess.COMPRESSION_ZSTD))
	return out


static func decode_info(bytes: PackedByteArray) -> LevelData:
	if bytes.size() < 4:
		return null
	var text := bytes.slice(4).decompress(bytes.decode_u32(0), FileAccess.COMPRESSION_ZSTD)
	return from_json(text.get_string_from_utf8())


static func _pack(raw: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(8)
	out.encode_u64(0, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


static func _unpack(packed: PackedByteArray) -> PackedByteArray:
	if packed.size() < 8:
		return PackedByteArray()
	return packed.slice(8).decompress(packed.decode_u64(0), FileAccess.COMPRESSION_ZSTD)


# --- JSON conversion -----------------------------------------------------------------------------

static func _encode(dict: Dictionary) -> Dictionary:
	var out := {}
	for key: String in dict:
		var value = dict[key]
		if key == "id":
			continue # The object map's key.
		match typeof(value):
			TYPE_VECTOR3I:
				out[key] = [value.x, value.y, value.z]
			TYPE_VECTOR3:
				out[key] = [snappedf(value.x, 0.01), snappedf(value.y, 0.01), snappedf(value.z, 0.01)]
			TYPE_COLOR:
				out[key] = "#" + value.to_html(true)
			TYPE_FLOAT:
				out[key] = snappedf(value, 0.001)
			_:
				out[key] = value
	return out


static func _decode(dict: Dictionary) -> Dictionary:
	var out := {}
	for key: String in dict:
		var value = dict[key]
		if key in VECTOR3I_KEYS and value is Array:
			out[key] = Vector3i(int(value[0]), int(value[1]), int(value[2]))
		elif key in VECTOR3_KEYS and value is Array:
			out[key] = Vector3(value[0], value[1], value[2])
		elif key in COLOR_KEYS and value is String:
			out[key] = Color.html(value)
		elif value is float and value == floorf(value) and key in ["facing", "value", "index", "room_floor", "room_wall", "room_ceiling", "room_thickness"]:
			out[key] = int(value) # JSON numbers come back as floats.
		else:
			out[key] = value
	return out
