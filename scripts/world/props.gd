class_name Props
extends RefCounted
## Voxel furniture and fittings. Levels place props from the MagicaVoxel library with place();
## the functions below are the generators that drew the original placeholder .vox files
## (tools/export_vox.gd), kept so placeholders can be regenerated.
##
## Each prop lives in its own frame: x across, y up, z depth, with the prop's front at z = 0.
## `facing` turns the prop so its front points north (-Z), east (+X), south (+Z) or west (-X). The
## origin is always the min corner of the footprint at floor level, so use footprint() to line
## props up against walls. A .vox prop's frame is its whole model box.

const M := preload("res://scripts/voxel/voxel_materials.gd")

enum { NORTH, EAST, SOUTH, WEST }

const SAMPLES := [M.LIQUID_GREEN, M.LIQUID_BLUE, M.LIQUID_PINK]
const BOX_COLORS := [M.PLASTIC, M.WOOD, M.CLOTH, M.WARNING, M.METAL, M.PLANK]

var world: VoxelWorld
var rng := RandomNumberGenerator.new()

var _origin := Vector3i.ZERO
var _w := 1
var _d := 1
var _facing := NORTH


func _init(voxel_world: VoxelWorld, seed: int) -> void:
	world = voxel_world
	rng.seed = seed


## Size on the ground (x, z) of a w x d prop with the given facing.
static func footprint(w: int, d: int, facing: int) -> Vector2i:
	return Vector2i(w, d) if facing == NORTH or facing == SOUTH else Vector2i(d, w)


# --- Library ----------------------------------------------------------------------------------

const LIBRARY_DIR := "res://assets/vox/props/"

## Where prop models are read from. Tests point this at a scratch copy.
static var library_dir := LIBRARY_DIR
static var _library := {}
## Names place() was asked for that have no .vox file, for tests and warnings.
static var missing: Array[String] = []


## Every place() call so far: [{name, origin, facing}], so live reload can swap edited props.
var placements: Array[Dictionary] = []


## Stamps the library prop `name` (assets/vox/props/<name>.vox) with its footprint's min corner at
## origin. Returns the footprint, or Vector2i.ZERO if the prop doesn't exist.
func place(name: String, origin: Vector3i, facing := NORTH) -> Vector2i:
	var model := load_prop(name)
	if model.is_empty():
		return Vector2i.ZERO
	var turned := orient(model, facing)
	world.stamp(origin, turned.size, turned.voxels, false)
	placements.append({name = name, origin = origin, facing = facing})
	return Vector2i(turned.size.x, turned.size.z)


## The prop name for a library file path, or "" if the path isn't in the library.
static func name_for_path(path: String) -> String:
	if path.get_base_dir().path_join("") != library_dir.path_join("") or path.get_extension() != "vox":
		return ""
	return path.get_file().get_basename()


## Reads a prop's file again. Returns {old, new} models; new is {} if the file doesn't parse (the
## old model stays loaded then, so a bad save doesn't wipe the prop).
static func reload_prop(name: String) -> Dictionary:
	var old: Dictionary = _library.get(name, {})
	var path := library_dir + name + ".vox"
	var fresh := VoxFile.load_model(path) if FileAccess.file_exists(path) else {}
	if not fresh.is_empty():
		_library[name] = fresh
	return {old = old, new = fresh}


## Live reload: re-reads a prop's file and swaps every placement of it, erasing the old model and
## stamping the new one through stamp(origin, size, voxels, erase) (WorldSync.stamp_model in co-op,
## so peers get the change too). Returns a short note for the player.
func reload_placements(name: String, stamp: Callable) -> String:
	var models := reload_prop(name)
	if models.new.is_empty():
		return "Couldn't read %s.vox, kept the old one" % name
	var count := 0
	for placement in placements:
		if placement.name != name:
			continue
		if not models.old.is_empty():
			var old := orient(models.old, placement.facing)
			stamp.call(placement.origin, old.size, old.voxels, true)
		var fresh := orient(models.new, placement.facing)
		stamp.call(placement.origin, fresh.size, fresh.voxels, false)
		count += 1
	return "Reloaded %s.vox (%d placed)" % [name, count]


## The library model for a prop name, loaded once. {} if there's no such file.
static func load_prop(name: String) -> Dictionary:
	if not _library.has(name):
		var path := library_dir + name + ".vox"
		if not FileAccess.file_exists(path):
			push_error("no prop model at " + path)
			if name not in missing:
				missing.append(name)
			return {}
		_library[name] = VoxFile.load_model(path)
	return _library[name]


## Forgets loaded props so edited .vox files are read again.
static func clear_library() -> void:
	_library.clear()


## Turns a model built facing north to face `facing`, the same way box() maps prop frames.
static func orient(model: Dictionary, facing: int) -> Dictionary:
	if facing == NORTH:
		return model
	var size: Vector3i = model.size
	var voxels: PackedByteArray = model.voxels
	var w := size.x
	var d := size.z
	var turned_size := Vector3i(w, size.y, d) if facing == SOUTH else Vector3i(d, size.y, w)
	var turned := PackedByteArray()
	turned.resize(voxels.size())
	for z in d:
		for y in size.y:
			for x in w:
				var material := voxels[x + y * w + z * w * size.y]
				if material == 0:
					continue
				var to: Vector2i
				match facing:
					EAST:
						to = Vector2i(d - 1 - z, x)
					SOUTH:
						to = Vector2i(w - 1 - x, d - 1 - z)
					_:
						to = Vector2i(z, w - 1 - x)
				turned[to.x + y * turned_size.x + to.y * turned_size.x * turned_size.y] = material
	return {size = turned_size, voxels = turned}


# --- Generators ------------------------------------------------------------------------------------

func table(origin: Vector3i, facing: int, w := 12, d := 8, top := M.WOOD) -> void:
	_begin(origin, w, d, facing)
	box(Vector3i(0, 6, 0), Vector3i(w, 7, d), top)
	_legs(w, d, 6)


func chair(origin: Vector3i, facing: int) -> void:
	_begin(origin, 4, 4, facing)
	_legs(4, 4, 4)
	box(Vector3i(0, 4, 0), Vector3i(4, 5, 4), M.CLOTH)
	box(Vector3i(0, 5, 3), Vector3i(4, 10, 4), M.CLOTH)


func stool(origin: Vector3i) -> void:
	_begin(origin, 3, 3, NORTH)
	box(Vector3i(0, 0, 0), Vector3i(3, 1, 3), M.STEEL)
	box(Vector3i(1, 1, 1), Vector3i(2, 5, 2), M.STEEL)
	box(Vector3i(0, 5, 0), Vector3i(3, 6, 3), M.RUBBER)


func bench(origin: Vector3i, facing: int, w := 12) -> void:
	_begin(origin, w, 4, facing)
	box(Vector3i(0, 4, 0), Vector3i(w, 5, 4), M.WOOD)
	for x in [1, w - 2]:
		box(Vector3i(x, 0, 1), Vector3i(x + 1, 4, 3), M.STEEL)


func couch(origin: Vector3i, facing: int, w := 18) -> void:
	_begin(origin, w, 8, facing)
	box(Vector3i(0, 0, 0), Vector3i(w, 4, 8), M.CLOTH)
	box(Vector3i(0, 4, 6), Vector3i(w, 9, 8), M.CLOTH)
	box(Vector3i(0, 4, 0), Vector3i(2, 6, 6), M.CLOTH)
	box(Vector3i(w - 2, 4, 0), Vector3i(w, 6, 6), M.CLOTH)
	for x in range(2, w - 2, 5):
		box(Vector3i(x, 4, 0), Vector3i(x + 1, 5, 6), M.RUBBER) # Cushion seams.


## Lab bench with a black resin top and random equipment on it.
func lab_bench(origin: Vector3i, facing: int, w := 20, d := 7) -> void:
	_begin(origin, w, d, facing)
	box(Vector3i(0, 0, 0), Vector3i(w, 8, d), M.PLASTIC)
	box(Vector3i(0, 0, 0), Vector3i(w, 1, d), M.RUBBER)
	for x in range(2, w - 2, 5):
		box(Vector3i(x, 6, 0), Vector3i(x + 2, 7, 1), M.STEEL)
	box(Vector3i(0, 8, 0), Vector3i(w, 9, d), M.RUBBER)
	var x := 1
	while x < w - 4:
		match rng.randi_range(0, 4):
			0:
				if x + 6 <= w: # Racks are 6 wide; don't let one hang off the end.
					_tube_rack(Vector3i(x, 9, 1))
				x += 7
			1:
				_microscope(Vector3i(x, 9, 2))
				x += 5
			2:
				_beaker(Vector3i(x, 9, 2), SAMPLES[rng.randi() % SAMPLES.size()])
				x += 3
			3:
				_flask(Vector3i(x, 9, 2), SAMPLES[rng.randi() % SAMPLES.size()])
				x += 4
			_:
				x += 3


func desk(origin: Vector3i, facing: int, w := 14, with_computer := true) -> void:
	_begin(origin, w, 7, facing)
	box(Vector3i(0, 7, 0), Vector3i(w, 8, 7), M.WOOD)
	box(Vector3i(0, 0, 3), Vector3i(4, 7, 7), M.WOOD) # Drawer stack.
	box(Vector3i(1, 5, 2), Vector3i(3, 6, 3), M.STEEL)
	box(Vector3i(w - 1, 0, 0), Vector3i(w, 7, 7), M.STEEL)
	if with_computer:
		_computer(Vector3i(w / 2 - 2, 8, 1))


func shelf(origin: Vector3i, facing: int, w := 12, h := 20, d := 4, stock := "lab") -> void:
	_begin(origin, w, d, facing)
	for x in [0, w - 1]:
		for z in [0, d - 1]:
			box(Vector3i(x, 0, z), Vector3i(x + 1, h, z + 1), M.STEEL)
	for y in range(0, h - 1, 6):
		box(Vector3i(0, y, 0), Vector3i(w, y + 1, d), M.STEEL)
		if y + 6 < h:
			_stock_shelf(Vector3i(1, y + 1, 1), w - 2, stock)
	box(Vector3i(0, h - 1, 0), Vector3i(w, h, d), M.STEEL)


func fume_hood(origin: Vector3i, facing: int, w := 12, d := 8) -> void:
	_begin(origin, w, d, facing)
	var h := 22
	box(Vector3i(0, 0, 0), Vector3i(w, 8, d), M.STEEL)
	box(Vector3i(0, 8, 0), Vector3i(w, 9, d), M.RUBBER)
	box(Vector3i(0, 9, 0), Vector3i(1, h, d), M.STEEL)
	box(Vector3i(w - 1, 9, 0), Vector3i(w, h, d), M.STEEL)
	box(Vector3i(0, 9, d - 1), Vector3i(w, h, d), M.STEEL)
	box(Vector3i(0, h - 4, 0), Vector3i(w, h, d), M.STEEL)
	box(Vector3i(1, 14, 0), Vector3i(w - 1, h - 4, 1), M.GLASS)
	box(Vector3i(2, h - 2, 0), Vector3i(w - 2, h - 1, 1), M.LAMP)
	_flask(Vector3i(2, 9, 3), M.LIQUID_GREEN)
	_beaker(Vector3i(7, 9, 4), M.LIQUID_PINK)


func fridge(origin: Vector3i, facing: int) -> void:
	_begin(origin, 7, 8, facing)
	box(Vector3i(0, 0, 1), Vector3i(7, 19, 8), M.PLASTIC)
	box(Vector3i(0, 12, 1), Vector3i(7, 13, 2), M.STEEL)
	box(Vector3i(5, 4, 0), Vector3i(6, 11, 1), M.STEEL)
	box(Vector3i(5, 14, 0), Vector3i(6, 18, 1), M.STEEL)


func water_cooler(origin: Vector3i, facing: int) -> void:
	_begin(origin, 3, 4, facing)
	box(Vector3i(0, 0, 1), Vector3i(3, 8, 4), M.PLASTIC)
	box(Vector3i(0, 6, 0), Vector3i(1, 7, 1), M.LIQUID_BLUE)
	box(Vector3i(2, 6, 0), Vector3i(3, 7, 1), M.EMERGENCY)
	box(Vector3i(0, 8, 1), Vector3i(3, 12, 4), M.WATER)
	box(Vector3i(1, 12, 2), Vector3i(2, 13, 3), M.PLASTIC)


## Kitchen counter with cabinets, optional sink, and wall cupboards above.
func counter(origin: Vector3i, facing: int, w := 16, sink := true) -> void:
	_begin(origin, w, 6, facing)
	box(Vector3i(0, 0, 0), Vector3i(w, 8, 6), M.WOOD)
	box(Vector3i(0, 0, 0), Vector3i(w, 1, 1), M.RUBBER)
	for x in range(2, w - 1, 4):
		box(Vector3i(x, 6, 0), Vector3i(x + 1, 7, 1), M.STEEL)
	box(Vector3i(0, 8, 0), Vector3i(w, 9, 6), M.PLASTIC)
	box(Vector3i(0, 15, 3), Vector3i(w, 21, 6), M.WOOD)
	for x in range(2, w - 1, 4):
		box(Vector3i(x, 16, 2), Vector3i(x + 1, 17, 3), M.STEEL)
	if sink:
		box(Vector3i(5, 7, 1), Vector3i(10, 9, 5), M.AIR)
		box(Vector3i(5, 6, 1), Vector3i(10, 7, 5), M.STEEL)
		box(Vector3i(7, 9, 5), Vector3i(8, 12, 6), M.STEEL)
		box(Vector3i(7, 11, 3), Vector3i(8, 12, 5), M.STEEL)
		_microwave(Vector3i(w - 6, 9, 1))
	else:
		_coffee_machine(Vector3i(2, 9, 2))


func vending_machine(origin: Vector3i, facing: int) -> void:
	_begin(origin, 9, 8, facing)
	box(Vector3i(0, 0, 0), Vector3i(9, 20, 8), M.STEEL)
	box(Vector3i(1, 5, 0), Vector3i(6, 18, 2), M.AIR)
	for y in range(6, 17, 3):
		for x in range(1, 6):
			box(Vector3i(x, y, 1), Vector3i(x + 1, y + 2, 2), BOX_COLORS[rng.randi() % BOX_COLORS.size()])
		box(Vector3i(1, y - 1, 1), Vector3i(6, y, 2), M.STEEL)
	box(Vector3i(7, 10, 0), Vector3i(8, 13, 1), M.SCREEN)
	box(Vector3i(1, 1, 0), Vector3i(6, 3, 1), M.RUBBER)


func locker(origin: Vector3i, facing: int) -> void:
	_begin(origin, 5, 5, facing)
	box(Vector3i(0, 0, 0), Vector3i(5, 20, 5), M.METAL)
	box(Vector3i(0, 0, 0), Vector3i(1, 20, 1), M.RUBBER) # Seam between lockers.
	for y in [16, 18]:
		box(Vector3i(1, y, 0), Vector3i(4, y + 1, 1), M.RUBBER)
	box(Vector3i(3, 9, 0), Vector3i(4, 11, 1), M.STEEL)


func crate(origin: Vector3i, s := 6) -> void:
	_begin(origin, s, s, NORTH)
	box(Vector3i(0, 0, 0), Vector3i(s, s, s), M.WOOD)
	for y in [0, s - 1]:
		box(Vector3i(0, y, 0), Vector3i(s, y + 1, 1), M.PLANK)
		box(Vector3i(0, y, s - 1), Vector3i(s, y + 1, s), M.PLANK)
		box(Vector3i(0, y, 0), Vector3i(1, y + 1, s), M.PLANK)
		box(Vector3i(s - 1, y, 0), Vector3i(s, y + 1, s), M.PLANK)
	for x in [0, s - 1]:
		for z in [0, s - 1]:
			box(Vector3i(x, 0, z), Vector3i(x + 1, s, z + 1), M.PLANK)


func barrel(origin: Vector3i, hazard := false) -> void:
	_begin(origin, 5, 5, NORTH)
	var body := M.WARNING if hazard else M.STEEL
	box(Vector3i(1, 0, 0), Vector3i(4, 8, 5), body)
	box(Vector3i(0, 0, 1), Vector3i(5, 8, 4), body)
	for y in [1, 6]:
		box(Vector3i(1, y, 0), Vector3i(4, y + 1, 5), M.RUBBER)
		box(Vector3i(0, y, 1), Vector3i(5, y + 1, 4), M.RUBBER)


func trash_can(origin: Vector3i) -> void:
	_begin(origin, 3, 3, NORTH)
	box(Vector3i(0, 0, 0), Vector3i(3, 4, 3), M.STEEL)
	box(Vector3i(1, 3, 1), Vector3i(2, 4, 2), M.AIR)


## Raised grow bed: plank frame around a layer of substrate that spores can be planted in.
func grow_bed(origin: Vector3i, facing: int, w := 30, d := 12) -> void:
	_begin(origin, w, d, facing)
	box(Vector3i(0, 0, 0), Vector3i(w, 4, d), M.PLANK)
	box(Vector3i(1, 1, 1), Vector3i(w - 1, 4, d - 1), M.AIR)
	box(Vector3i(1, 1, 1), Vector3i(w - 1, 3, d - 1), M.SUBSTRATE)


func spore_tank(origin: Vector3i) -> void:
	_begin(origin, 4, 4, NORTH)
	box(Vector3i(0, 0, 0), Vector3i(4, 2, 4), M.STEEL)
	box(Vector3i(0, 2, 0), Vector3i(4, 9, 4), M.GLASS)
	box(Vector3i(1, 2, 0), Vector3i(3, 7, 4), M.LIQUID_GREEN)
	box(Vector3i(0, 9, 0), Vector3i(4, 10, 4), M.STEEL)


func plank_stack(origin: Vector3i, facing: int, layers := 4) -> void:
	_begin(origin, 12, 6, facing)
	for i in layers:
		var z := 0 if i % 2 == 0 else 1
		box(Vector3i(0, i, z), Vector3i(12, i + 1, z + 5), M.PLANK)


func sandbags(origin: Vector3i, facing: int) -> void:
	_begin(origin, 12, 4, facing)
	box(Vector3i(0, 0, 0), Vector3i(6, 3, 4), M.DIRT)
	box(Vector3i(6, 0, 0), Vector3i(12, 3, 4), M.DIRT)
	box(Vector3i(3, 3, 0), Vector3i(9, 5, 4), M.DIRT)


## Flat wall decoration: origin is the min corner of the patch on the wall surface, facing points
## away from the wall (into the room).
func wall_board(origin: Vector3i, facing: int, w := 14, h := 8, whiteboard := true) -> void:
	_begin(origin, w, 1, facing)
	box(Vector3i(0, 0, 0), Vector3i(w, h, 1), M.STEEL)
	if whiteboard:
		box(Vector3i(1, 1, 0), Vector3i(w - 1, h - 1, 1), M.PLASTIC)
		for i in 6:
			var x := rng.randi_range(2, w - 5)
			var y := rng.randi_range(2, h - 3)
			box(Vector3i(x, y, 0), Vector3i(x + rng.randi_range(1, 3), y + 1, 1), [M.LIQUID_BLUE, M.EMERGENCY, M.RUBBER][i % 3])
	else:
		box(Vector3i(1, 1, 0), Vector3i(w - 1, h - 1, 1), BOX_COLORS[rng.randi() % BOX_COLORS.size()])
		box(Vector3i(2, 2, 0), Vector3i(w - 2, 3, 1), M.RUBBER)


# --- Parts placed in the current prop's frame ---------------------------------------------------

func _legs(w: int, d: int, h: int) -> void:
	for x in [0, w - 1]:
		for z in [0, d - 1]:
			box(Vector3i(x, 0, z), Vector3i(x + 1, h, z + 1), M.STEEL)


func _tube_rack(at: Vector3i) -> void:
	box(at, at + Vector3i(6, 1, 2), M.STEEL)
	for i in 3:
		var p := at + Vector3i(1 + i * 2, 1, rng.randi_range(0, 1))
		box(p, p + Vector3i(1, 2, 1), SAMPLES[rng.randi() % SAMPLES.size()])
		box(p + Vector3i(0, 2, 0), p + Vector3i(1, 3, 1), M.GLASS)


func _microscope(at: Vector3i) -> void:
	box(at, at + Vector3i(3, 1, 3), M.STEEL)
	box(at + Vector3i(1, 1, 2), at + Vector3i(2, 5, 3), M.STEEL)
	box(at + Vector3i(0, 2, 0), at + Vector3i(3, 3, 2), M.RUBBER)
	box(at + Vector3i(1, 4, 0), at + Vector3i(2, 5, 2), M.PLASTIC)
	box(at + Vector3i(1, 5, 1), at + Vector3i(2, 6, 2), M.RUBBER)


func _beaker(at: Vector3i, liquid: int) -> void:
	box(at, at + Vector3i(2, 2, 2), liquid)
	box(at + Vector3i(0, 2, 0), at + Vector3i(2, 3, 2), M.GLASS)


func _flask(at: Vector3i, liquid: int) -> void:
	box(at, at + Vector3i(3, 2, 3), liquid)
	box(at + Vector3i(1, 2, 1), at + Vector3i(2, 4, 2), M.GLASS)


func _computer(at: Vector3i) -> void:
	box(at, at + Vector3i(5, 1, 2), M.RUBBER) # Keyboard.
	box(at + Vector3i(2, 0, 3), at + Vector3i(3, 2, 4), M.STEEL)
	box(at + Vector3i(0, 2, 3), at + Vector3i(5, 6, 4), M.RUBBER)
	box(at + Vector3i(1, 3, 2), at + Vector3i(4, 5, 3), M.SCREEN)


func _microwave(at: Vector3i) -> void:
	box(at, at + Vector3i(5, 3, 4), M.STEEL)
	box(at + Vector3i(1, 1, 0), at + Vector3i(3, 2, 1), M.GLASS)
	box(at + Vector3i(4, 1, 0), at + Vector3i(5, 2, 1), M.SCREEN)


func _coffee_machine(at: Vector3i) -> void:
	box(at, at + Vector3i(3, 5, 3), M.RUBBER)
	box(at + Vector3i(0, 0, 0), at + Vector3i(3, 2, 1), M.AIR)
	box(at + Vector3i(1, 0, 0), at + Vector3i(2, 1, 1), M.GLASS)
	box(at + Vector3i(2, 4, 0), at + Vector3i(3, 5, 1), M.EMERGENCY)


func _stock_shelf(at: Vector3i, width: int, stock: String) -> void:
	var x := 0
	while x < width - 1:
		var p := at + Vector3i(x, 0, rng.randi_range(0, 1))
		match stock:
			"lab":
				if rng.randf() < 0.5:
					_beaker(p, SAMPLES[rng.randi() % SAMPLES.size()])
					x += 3
				else:
					box(p, p + Vector3i(1, rng.randi_range(2, 4), 1), SAMPLES[rng.randi() % SAMPLES.size()])
					x += 2
			_:
				var size := rng.randi_range(2, 4)
				box(p, p + Vector3i(mini(size, width - x), mini(size, 5), 2), BOX_COLORS[rng.randi() % BOX_COLORS.size()])
				x += size + 1


# --- Frame ----------------------------------------------------------------------------------------

func _begin(origin: Vector3i, w: int, d: int, facing: int) -> void:
	_origin = origin
	_w = w
	_d = d
	_facing = facing


func _map(x: int, z: int) -> Vector2i:
	match _facing:
		NORTH:
			return Vector2i(x, z)
		EAST:
			return Vector2i(_d - 1 - z, x)
		SOUTH:
			return Vector2i(_w - 1 - x, _d - 1 - z)
		_:
			return Vector2i(z, _w - 1 - x)


## Fills a box given in the current prop's local frame (to exclusive).
func box(from: Vector3i, to: Vector3i, material: int) -> void:
	var a := _map(from.x, from.z)
	var b := _map(to.x - 1, to.z - 1)
	var lo := _origin + Vector3i(mini(a.x, b.x), from.y, mini(a.y, b.y))
	var hi := _origin + Vector3i(maxi(a.x, b.x) + 1, to.y, maxi(a.y, b.y) + 1)
	world.fill_box(lo, hi, material)
