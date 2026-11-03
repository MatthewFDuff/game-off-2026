class_name VoxFile
## Reads and writes MagicaVoxel .vox files.
##
## Palette index = game material id (VoxelMaterials), so a voxel painted with palette color 3 in
## MagicaVoxel is Concrete in the game, with its hardness and glow. Palette slots that aren't a
## game material are written dark purple; on import they're mapped to the closest material.
##
## Axes: MagicaVoxel is Z-up, the game is Y-up. A game voxel (x, y, z) in a model of size s is
## MagicaVoxel voxel (s.x - 1 - x, z, y). That's a rotation, not a mirror, and it puts a prop's
## front (game z = 0, facing -Z) on MagicaVoxel's front side (-Y).
##
## Models are {size: Vector3i, voxels: PackedByteArray} in game axes, indexed
## x + y * size.x + z * size.x * size.y, 0 = air, the same layout as VoxelWorld.stamp.

const M := preload("res://scripts/voxel/voxel_materials.gd")
## MagicaVoxel's largest model per axis; bigger volumes are split into several models.
const MAX_MODEL := 256
const UNUSED_COLOR := Color(0.25, 0.05, 0.25)


static func load_model(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("can't read %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var model := parse(bytes)
	if model.is_empty():
		push_error("%s isn't a valid .vox file" % path)
	elif not model.unknown_colors.is_empty():
		push_warning("%s uses palette slots that aren't game materials (%s); mapped to the closest material" % [path, model.unknown_colors])
	return model


static func save_model(path: String, model: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(encode(model))
	return OK


# --- Reading ---------------------------------------------------------------------------------------

## Parses a whole .vox file into one game-axes model; all its models are merged where the scene
## places them. Returns {} if the bytes aren't a .vox file. The result also has
## unknown_colors: palette indices used that aren't game materials.
static func parse(bytes: PackedByteArray) -> Dictionary:
	var stream := StreamPeerBuffer.new()
	stream.data_array = bytes
	if bytes.size() < 20 or bytes.slice(0, 4).get_string_from_ascii() != "VOX ":
		return {}
	stream.seek(8)
	if _read_id(stream) != "MAIN":
		return {}
	var main_content := stream.get_32()
	var main_children := stream.get_32()
	stream.seek(stream.get_position() + main_content)
	var end := mini(stream.get_position() + main_children, bytes.size())

	var sizes: Array[Vector3i] = []
	var models: Array[PackedByteArray] = [] # Raw XYZI payloads: x, y, z, color index per voxel.
	var palette := PackedColorArray()
	var nodes := {}
	while stream.get_position() + 12 <= end:
		var id := _read_id(stream)
		var content_size := stream.get_32()
		var children_size := stream.get_32()
		var start := stream.get_position()
		match id:
			"SIZE":
				sizes.append(Vector3i(stream.get_32(), stream.get_32(), stream.get_32()))
			"XYZI":
				var count := stream.get_32()
				models.append(stream.get_data(count * 4)[1])
			"RGBA":
				for i in 256:
					palette.append(Color8(stream.get_u8(), stream.get_u8(), stream.get_u8(), stream.get_u8()))
			"nTRN":
				var node_id := stream.get_32()
				var attributes := _read_dict(stream)
				var child := stream.get_32()
				stream.get_32() # Reserved.
				stream.get_32() # Layer.
				var frames := stream.get_32()
				var frame := _read_dict(stream) if frames > 0 else {}
				nodes[node_id] = {type = "transform", child = child, hidden = attributes.get("_hidden", "0") == "1",
						t = _parse_translation(frame.get("_t", "0 0 0")), r = _parse_rotation(int(frame.get("_r", "4")))}
			"nGRP":
				var node_id := stream.get_32()
				_read_dict(stream)
				var children: Array[int] = []
				for i in stream.get_32():
					children.append(stream.get_32())
				nodes[node_id] = {type = "group", children = children}
			"nSHP":
				var node_id := stream.get_32()
				_read_dict(stream)
				var shape_models: Array[int] = []
				for i in stream.get_32():
					shape_models.append(stream.get_32())
					_read_dict(stream)
				nodes[node_id] = {type = "shape", models = shape_models}
		stream.seek(start + content_size + children_size)

	if sizes.is_empty() or sizes.size() != models.size():
		return {}
	var color_map := _palette_to_materials(palette)

	# Every voxel's position in the scene (MagicaVoxel axes), then merged into one grid.
	var placed: Array[Dictionary] = [] # {model: int, transform: Transform3D}
	if nodes.has(0):
		_collect(nodes, 0, Transform3D.IDENTITY, placed)
	else:
		for i in models.size():
			placed.append({model = i, transform = Transform3D(Basis.IDENTITY, Vector3(sizes[i] / 2))})
	# The bounds come from the model boxes, not the voxels, so empty margins (a prop's frame) survive.
	var points := PackedVector3Array()
	var colors := PackedByteArray()
	var lo := Vector3i.MAX
	var hi := Vector3i.MIN
	for entry: Dictionary in placed:
		var i: int = entry.model
		if i >= models.size():
			continue
		var raw := models[i]
		var half := Vector3(sizes[i] / 2)
		var transform: Transform3D = entry.transform
		for corner in 8:
			var c := Vector3(sizes[i] - Vector3i.ONE) * Vector3(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1)
			var q := Vector3i((transform * (c - half)).round())
			lo = lo.min(q)
			hi = hi.max(q)
		for v in raw.size() / 4:
			var p := Vector3(raw[v * 4], raw[v * 4 + 1], raw[v * 4 + 2]) - half
			points.append(transform * p)
			colors.append(raw[v * 4 + 3])
	if lo == Vector3i.MAX:
		return {}
	var vox_size := hi - lo + Vector3i.ONE
	var size := Vector3i(vox_size.x, vox_size.z, vox_size.y)
	var voxels := PackedByteArray()
	voxels.resize(size.x * size.y * size.z)
	var unknown := {}
	for k in points.size():
		var q := Vector3i(points[k].round()) - lo
		var color := colors[k]
		var material: int = color_map[color]
		if material != color:
			unknown[color] = true
		voxels[(size.x - 1 - q.x) + q.z * size.x + q.y * size.x * size.y] = material
	return {size = size, voxels = voxels, unknown_colors = unknown.keys()}


static func _collect(nodes: Dictionary, node_id: int, parent: Transform3D, out: Array[Dictionary]) -> void:
	var node: Dictionary = nodes.get(node_id, {})
	match node.get("type", ""):
		"transform":
			if not node.hidden:
				_collect(nodes, node.child, parent * Transform3D(node.r, node.t), out)
		"group":
			for child: int in node.children:
				_collect(nodes, child, parent, out)
		"shape":
			for model: int in node.models:
				out.append({model = model, transform = parent})


## Maps each palette index to a game material: itself when it's a material whose color matches,
## otherwise the material with the nearest color.
static func _palette_to_materials(palette: PackedColorArray) -> PackedByteArray:
	var map := PackedByteArray()
	map.resize(256)
	for index in range(1, 256):
		if palette.is_empty() or (M.DEFS.has(index) and _close(palette[index - 1], M.get_color(index))):
			map[index] = index
			continue
		var target := palette[index - 1]
		var best := M.CONCRETE
		var best_distance := INF
		for id: int in M.DEFS:
			var c := M.get_color(id)
			var distance := Vector3(c.r - target.r, c.g - target.g, c.b - target.b).length_squared()
			if distance < best_distance:
				best_distance = distance
				best = id
		map[index] = best
	return map


static func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02


static func _read_id(stream: StreamPeerBuffer) -> String:
	return stream.get_data(4)[1].get_string_from_ascii()


static func _read_string(stream: StreamPeerBuffer) -> String:
	return stream.get_data(stream.get_32())[1].get_string_from_utf8()


static func _read_dict(stream: StreamPeerBuffer) -> Dictionary:
	var dict := {}
	for i in stream.get_32():
		var key := _read_string(stream)
		dict[key] = _read_string(stream)
	return dict


static func _parse_translation(text: String) -> Vector3:
	var parts := text.split(" ", false)
	return Vector3(int(parts[0]), int(parts[1]), int(parts[2])) if parts.size() == 3 else Vector3.ZERO


## MagicaVoxel packs a signed permutation matrix into a byte: bits 0-1 the column of the non-zero
## entry in row 0, bits 2-3 row 1's, bits 4-6 the signs of rows 0-2.
static func _parse_rotation(packed: int) -> Basis:
	var c0 := packed & 3
	var c1 := (packed >> 2) & 3
	var c2 := 3 - c0 - c1
	var rows := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	for r in 3:
		var column: int = [c0, c1, c2][r]
		var row := Vector3.ZERO
		row[column] = -1.0 if packed & (1 << (4 + r)) else 1.0
		rows[r] = row
	# Basis takes columns; transpose the rows into them.
	return Basis(rows[0], rows[1], rows[2]).transposed()


# --- Writing ---------------------------------------------------------------------------------------

## Encodes a game-axes model as a .vox file, split into several models when it's bigger than
## MagicaVoxel allows in one.
static func encode(model: Dictionary) -> PackedByteArray:
	var size: Vector3i = model.size
	var voxels: PackedByteArray = model.voxels
	var vox_size := Vector3i(size.x, size.z, size.y)
	var tiles := Vector3i(ceili(vox_size.x / float(MAX_MODEL)), ceili(vox_size.y / float(MAX_MODEL)), ceili(vox_size.z / float(MAX_MODEL)))

	var children := StreamPeerBuffer.new()
	var placements: Array[Vector3i] = [] # Each model's min corner, MagicaVoxel axes.
	var tile_sizes: Array[Vector3i] = []
	var payloads: Array[PackedByteArray] = []
	for tz in tiles.z:
		for ty in tiles.y:
			for tx in tiles.x:
				var lo := Vector3i(tx, ty, tz) * MAX_MODEL
				var tile := (vox_size - lo).min(Vector3i.ONE * MAX_MODEL)
				var xyzi := PackedByteArray()
				for vz in tile.z:
					for vy in tile.y:
						for vx in tile.x:
							var v := lo + Vector3i(vx, vy, vz)
							var material := voxels[(size.x - 1 - v.x) + v.z * size.x + v.y * size.x * size.y]
							if material != 0:
								xyzi.append_array(PackedByteArray([vx, vy, vz, material]))
				if xyzi.is_empty() and tiles != Vector3i.ONE:
					continue
				placements.append(lo)
				tile_sizes.append(tile)
				payloads.append(xyzi)

	for i in payloads.size():
		var size_chunk := StreamPeerBuffer.new()
		size_chunk.put_32(tile_sizes[i].x)
		size_chunk.put_32(tile_sizes[i].y)
		size_chunk.put_32(tile_sizes[i].z)
		_put_chunk(children, "SIZE", size_chunk.data_array)
		var xyzi_chunk := StreamPeerBuffer.new()
		xyzi_chunk.put_32(payloads[i].size() / 4)
		xyzi_chunk.put_data(payloads[i])
		_put_chunk(children, "XYZI", xyzi_chunk.data_array)

	if payloads.size() > 1:
		_put_scene_graph(children, placements, tile_sizes)
	_put_chunk(children, "RGBA", _palette_bytes())
	for id: int in M.DEFS:
		var properties := _material_properties(id)
		if not properties.is_empty():
			var matl := StreamPeerBuffer.new()
			matl.put_32(id)
			_put_dict(matl, properties)
			_put_chunk(children, "MATL", matl.data_array)

	var out := StreamPeerBuffer.new()
	out.put_data("VOX ".to_ascii_buffer())
	out.put_32(150) # 150 is read by every MagicaVoxel version and most other tools.
	out.put_data("MAIN".to_ascii_buffer())
	out.put_32(0)
	out.put_32(children.data_array.size())
	out.put_data(children.data_array)
	return out.data_array


## Places split models side by side: root transform -> group -> one transform + shape per model.
## Single-model files skip this; every reader places a lone model at the origin.
static func _put_scene_graph(children: StreamPeerBuffer, placements: Array[Vector3i], tile_sizes: Array[Vector3i]) -> void:
	var group_children: Array[int] = []
	_put_transform(children, 0, 1, {})
	for i in placements.size():
		group_children.append(2 + i * 2)
	var group := StreamPeerBuffer.new()
	group.put_32(1)
	_put_dict(group, {})
	group.put_32(group_children.size())
	for child in group_children:
		group.put_32(child)
	_put_chunk(children, "nGRP", group.data_array)
	for i in placements.size():
		var center := placements[i] + tile_sizes[i] / 2
		_put_transform(children, 2 + i * 2, 3 + i * 2, {"_t": "%d %d %d" % [center.x, center.y, center.z]})
		var shape := StreamPeerBuffer.new()
		shape.put_32(3 + i * 2)
		_put_dict(shape, {})
		shape.put_32(1)
		shape.put_32(i)
		_put_dict(shape, {})
		_put_chunk(children, "nSHP", shape.data_array)


## Palette slot i (color index i + 1) holds material i + 1's color.
static func _palette_bytes() -> PackedByteArray:
	var bytes := PackedByteArray()
	for index in range(1, 257):
		var c := M.get_color(index) if M.DEFS.has(index) else UNUSED_COLOR
		if index == 256:
			c = Color.BLACK
		bytes.append_array(PackedByteArray([c.r8, c.g8, c.b8, 255]))
	return bytes


## MagicaVoxel render materials, so lamps glow and glass is see-through in its renderer too.
static func _material_properties(id: int) -> Dictionary:
	var def: Dictionary = M.DEFS[id]
	if def.get("emission", 0.0) >= 0.5:
		return {"_type": "_emit", "_emit": str(def.emission), "_flux": "1"}
	if id == M.GLASS:
		return {"_type": "_glass", "_alpha": "0.5", "_trans": "0.5"}
	return {}


static func _put_transform(stream: StreamPeerBuffer, node_id: int, child: int, frame: Dictionary) -> void:
	var chunk := StreamPeerBuffer.new()
	chunk.put_32(node_id)
	_put_dict(chunk, {})
	chunk.put_32(child)
	chunk.put_32(-1)
	chunk.put_32(0 if node_id != 0 else -1)
	chunk.put_32(1)
	_put_dict(chunk, frame)
	_put_chunk(stream, "nTRN", chunk.data_array)


static func _put_chunk(stream: StreamPeerBuffer, id: String, content: PackedByteArray) -> void:
	stream.put_data(id.to_ascii_buffer())
	stream.put_32(content.size())
	stream.put_32(0)
	stream.put_data(content)


static func _put_dict(stream: StreamPeerBuffer, dict: Dictionary) -> void:
	stream.put_32(dict.size())
	for key: String in dict:
		_put_string(stream, key)
		_put_string(stream, str(dict[key]))


static func _put_string(stream: StreamPeerBuffer, text: String) -> void:
	var bytes := text.to_utf8_buffer()
	stream.put_32(bytes.size())
	stream.put_data(bytes)
