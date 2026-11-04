class_name ShiftSave
extends RefCounted
## The one saved shift on this machine (docs/shift-save.md): the host writes it at every clone vat,
## seal, the generator, leaving and closing the window, and the cubicle's Continue resumes it. In
## the fiction it is the clone Fung AI keeps on file. One folder, no slots:
##   shift.json   the record (Lab.save_shift builds it; section 1 of the doc lists the keys)
##   voxels.bin   VoxelWorld.get_data() at the save, an 8-byte size header plus zstd
## A record is tied to the level it was made in by level_hash (its level.json text plus voxels.bin
## bytes, as LevelData.load_level would read them), so a shift recorded against an older layout is
## refused instead of loaded into the wrong rooms.

const DIR := "user://shift/"
const FORMAT := 1
const RECORD_FILE := "shift.json"
const VOXELS_FILE := "voxels.bin"
## Tests point this at a scratch folder.
static var dir_override := ""

## Level folder -> [json modified time, voxels modified time, hash], so summary() stays cheap.
static var _hash_cache := {}


## The folder the save lives in.
static func dir() -> String:
	return dir_override if dir_override != "" else DIR


## Whether a shift is on file (it may still be stale; summary().layout_ok says).
static func exists() -> bool:
	return FileAccess.file_exists(dir().path_join(RECORD_FILE)) and FileAccess.file_exists(dir().path_join(VOXELS_FILE))


## {} when none. Keys: level, vat (marker id), vat_room (readable), elapsed (seconds), clones (int),
## owed (int: damage plus clones at Lines.ENDING.clone_cost), party (Array of names), saved_at (int),
## layout_ok (bool: the level on disk still matches level_hash). Reads shift.json only.
static func summary() -> Dictionary:
	var record := _read_record()
	if record.is_empty():
		return {}
	var vat := str(record.get("checkpoint", ""))
	var room := str(record.get("vat_room", ""))
	if room == "":
		room = vat.replace("_", " ")
	var clones := int(record.get("deaths", 0))
	return {
		level = str(record.get("level", "")),
		vat = vat,
		vat_room = room,
		elapsed = float(record.get("elapsed", 0.0)),
		clones = clones,
		owed = int(record.get("total_damage", 0)) + clones * int(Lines.ENDING.clone_cost),
		party = Array(record.get("party", [])),
		saved_at = int(record.get("saved_at", 0)),
		layout_ok = _layout_ok(record),
	}


## The whole record plus voxels (key "voxels": the raw VoxelWorld data) and layout_ok, or {} if
## missing or invalid.
static func load() -> Dictionary:
	var record := _read_record()
	if record.is_empty():
		return {}
	var packed := FileAccess.get_file_as_bytes(dir().path_join(VOXELS_FILE))
	if packed.size() < 8 or (record.has("voxels_size") and int(record.voxels_size) != packed.size()):
		return {}
	var voxels := packed.slice(8).decompress(packed.decode_u64(0), FileAccess.COMPRESSION_ZSTD)
	if voxels.is_empty() or voxels.size() != packed.decode_u64(0):
		return {}
	record.voxels = voxels
	record.layout_ok = _layout_ok(record)
	return record


## Writes the record (format, level_hash and voxels_size are filled in here) and the world. The
## voxels go first and the record last, each through a temporary file, so a half-written save
## never reads as whole.
static func write(record: Dictionary, voxels: PackedByteArray) -> Error:
	var folder := dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var packed := PackedByteArray()
	packed.resize(8)
	packed.encode_u64(0, voxels.size())
	packed.append_array(voxels.compress(FileAccess.COMPRESSION_ZSTD))
	var out := record.duplicate(true)
	out.erase("voxels")
	out.erase("layout_ok")
	out.format = FORMAT
	out.voxels_size = packed.size()
	if not out.has("level_hash"):
		out.level_hash = level_hash(str(out.get("level", "")))
	var error := _write_file(folder.path_join(VOXELS_FILE), packed)
	if error != OK:
		return error
	return _write_file(folder.path_join(RECORD_FILE), JSON.stringify(out, "\t", true).to_utf8_buffer())


## Deletes the save (the payroll statement, or Discard in the cubicle).
static func clear() -> void:
	for file in [RECORD_FILE, VOXELS_FILE]:
		var path := dir().path_join(file)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## A hash of a level's level.json text plus its voxels.bin bytes, from the folder LevelData.load_level
## reads (the writable folder's copy first, then the shipped one); "" when the level isn't there.
static func level_hash(level_name: String) -> String:
	if level_name == "":
		return ""
	for base in [LevelData.save_dir(), LevelData.RES_DIR]:
		var folder: String = str(base).path_join(level_name)
		var json_path := folder.path_join("level.json")
		if not FileAccess.file_exists(json_path):
			continue
		var voxels_path := folder.path_join("voxels.bin")
		var stamp := [FileAccess.get_modified_time(json_path), FileAccess.get_modified_time(voxels_path)]
		var cached: Array = _hash_cache.get(folder, [])
		if cached.size() == 3 and cached[0] == stamp[0] and cached[1] == stamp[1]:
			return cached[2]
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(FileAccess.get_file_as_bytes(json_path))
		context.update(FileAccess.get_file_as_bytes(voxels_path))
		var digest := context.finish().hex_encode()
		_hash_cache[folder] = [stamp[0], stamp[1], digest]
		return digest
	return ""


## The readable name of where a marker id stands: the `name` of the room object whose box holds it,
## else the id with underscores as spaces. For no id at all, the room of the first spawn marker.
static func room_of(level: LevelData, marker_id: String) -> String:
	if level == null:
		return marker_id.replace("_", " ")
	var marker: Dictionary = level.objects.get(marker_id, {})
	if marker_id == "":
		for object: Dictionary in level.objects.values():
			if object.get("kind") == "marker" and object.get("type") == "spawn" and (marker.is_empty() or int(object.get("index", 0)) < int(marker.get("index", 0))):
				marker = object
	if marker.get("kind") == "marker":
		var at: Vector3 = marker.position
		for object: Dictionary in level.objects.values():
			if object.get("kind") != "room":
				continue
			var box := AABB(Vector3(object.from), Vector3(object.to - object.from))
			if box.has_point(at + Vector3.UP) and str(object.get("name", "")) != "":
				return str(object.name)
	return marker_id.replace("_", " ") if marker_id != "" else "site entrance"


static func _read_record() -> Dictionary:
	var path := dir().path_join(RECORD_FILE)
	if not FileAccess.file_exists(path) or not FileAccess.file_exists(dir().path_join(VOXELS_FILE)):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or int(data.get("format", 0)) != FORMAT or str(data.get("level", "")) == "":
		return {}
	return data


static func _layout_ok(record: Dictionary) -> bool:
	var expected := str(record.get("level_hash", ""))
	return expected != "" and expected == level_hash(str(record.get("level", "")))


static func _write_file(path: String, bytes: PackedByteArray) -> Error:
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temp, path)
