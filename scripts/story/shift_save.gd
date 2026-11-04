class_name ShiftSave
extends RefCounted
## The one saved shift on this machine (docs/shift-save.md): the host writes it at every clone vat,
## seal, the generator, leaving and closing the window, and the cubicle's Continue resumes it. In
## the fiction it is the clone Fung AI keeps on file. One folder, no slots:
##   shift.json   the record (Lab.save_shift builds it; section 1 of the doc lists the keys)
##   voxels.bin   an 8-byte size header plus zstd of: (format 1) VoxelWorld.get_data() at the save;
##                (format 2, what Lab writes) only the chunks changed since the level was built for
##                play: chunk_count int32 slots, then their 32768 raw bytes each
##                (VoxelWorld.get_changed_chunks / get_chunks_data). A format 2 save is a delta on
##                the level as built from its voxels.bin, which level_hash ties it to.
## A record is tied to the level it was made in by level_hash (its level.json text plus voxels.bin
## bytes, as LevelData.load_level would read them), so a shift recorded against an older layout is
## refused instead of loaded into the wrong rooms.

const DIR := "user://shift/"
## What Lab writes now (a chunk delta, write_delta); FORMAT_FULL saves (the whole world, write) are
## still read, so a shift saved before the delta format still loads.
const FORMAT := 2
const FORMAT_FULL := 1
## Bytes of one chunk in get_chunks_data (32³ voxels).
const CHUNK_BYTES := 32768
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


## The whole record plus its world and layout_ok, or {} if missing or invalid. The world is, for a
## format 1 save, "voxels" (the raw VoxelWorld data); for a format 2 save, "chunk_slots"
## (PackedInt32Array) and "chunk_data" (CHUNK_BYTES each), to set_chunks_data onto the level as
## built for play.
static func load() -> Dictionary:
	var record := _read_record()
	if record.is_empty():
		return {}
	var packed := FileAccess.get_file_as_bytes(dir().path_join(VOXELS_FILE))
	if packed.size() < 8 or (record.has("voxels_size") and int(record.voxels_size) != packed.size()):
		return {}
	var raw_size := packed.decode_u64(0)
	var raw := packed.slice(8).decompress(raw_size, FileAccess.COMPRESSION_ZSTD) if raw_size > 0 else PackedByteArray()
	if raw.size() != raw_size:
		return {}
	if int(record.format) == FORMAT_FULL:
		if raw.is_empty():
			return {}
		record.voxels = raw
	else:
		var count := int(record.get("chunk_count", -1))
		if count < 0 or raw.size() != count * (4 + CHUNK_BYTES):
			return {}
		record.chunk_slots = raw.slice(0, count * 4).to_int32_array()
		record.chunk_data = raw.slice(count * 4)
	record.layout_ok = _layout_ok(record)
	return record


## Writes the record (format, level_hash and voxels_size are filled in here) and the world. The
## voxels go first and the record last, each through a temporary file, so a half-written save
## never reads as whole.
## A whole-world save (FORMAT_FULL): voxels is VoxelWorld.get_data().
static func write(record: Dictionary, voxels: PackedByteArray) -> Error:
	return _write(record, voxels, FORMAT_FULL, -1)


## A delta save (FORMAT, what Lab.save_shift writes): the chunk slots changed since the level was
## built for play and their get_chunks_data bytes (CHUNK_BYTES each, in slot order).
static func write_delta(record: Dictionary, slots: PackedInt32Array, chunk_data: PackedByteArray) -> Error:
	if chunk_data.size() != slots.size() * CHUNK_BYTES:
		return ERR_INVALID_DATA
	var raw := slots.to_byte_array()
	raw.append_array(chunk_data)
	return _write(record, raw, FORMAT, slots.size())


static func _write(record: Dictionary, raw: PackedByteArray, format: int, chunk_count: int) -> Error:
	var folder := dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var packed := PackedByteArray()
	packed.resize(8)
	packed.encode_u64(0, raw.size())
	if not raw.is_empty():
		packed.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	var out := record.duplicate(true)
	for key in ["voxels", "layout_ok", "chunk_slots", "chunk_data", "chunk_count"]:
		out.erase(key)
	out.format = format
	if chunk_count >= 0:
		out.chunk_count = chunk_count
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
	if not data is Dictionary or int(data.get("format", 0)) not in [FORMAT, FORMAT_FULL] or str(data.get("level", "")) == "":
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
