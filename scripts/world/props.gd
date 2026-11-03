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
## Off: place() only records placements (converting generated layouts into level objects).
var stamp_into_world := true


## Stamps the library prop `name` (assets/vox/props/<name>.vox) with its footprint's min corner at
## origin. Returns the footprint, or Vector2i.ZERO if the prop doesn't exist.
func place(name: String, origin: Vector3i, facing := NORTH) -> Vector2i:
	var model := load_prop(name)
	if model.is_empty():
		return Vector2i.ZERO
	var turned := orient(model, facing)
	if stamp_into_world:
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


# --- Interactables (phase 5) -----------------------------------------------------------------

## Vent grate: a 1 x 1.2 m grille of soft plastic slats (enemies dig through it, a few shots break
## it), sized to sit in a vent_duct's mouth.
func vent_grate(origin: Vector3i, facing: int) -> void:
	_begin(origin, 10, 1, facing)
	box(Vector3i(0, 0, 0), Vector3i(10, 12, 1), M.RUBBER)
	box(Vector3i(1, 1, 0), Vector3i(9, 11, 1), M.AIR)
	for y in range(2, 11, 2):
		box(Vector3i(1, y, 0), Vector3i(9, y + 1, 1), M.PLASTIC)


## Door placeholder panel, one voxel thick so it can slide into a pocket inside a 3+ voxel wall
## (LevelEdits cuts the doorway and the pocket). kind: "single" (window strip), "security" (a
## keycard stripe), "blast" (hazard stripes), "hatch" (a grate).
func door_panel(origin: Vector3i, facing: int, w: int, h: int, kind: String) -> void:
	_begin(origin, w, 1, facing)
	match kind:
		"blast":
			box(Vector3i(0, 0, 0), Vector3i(w, h, 1), M.STEEL)
			box(Vector3i(0, h / 2 - 1, 0), Vector3i(w, h / 2 + 1, 1), M.HAZARD_STRIPES)
		"hatch":
			box(Vector3i(0, 0, 0), Vector3i(w, h, 1), M.RUBBER)
			for y in range(2, h - 1, 2):
				box(Vector3i(1, y, 0), Vector3i(w - 1, y + 1, 1), M.PLASTIC)
		_:
			box(Vector3i(0, 0, 0), Vector3i(w, h, 1), M.METAL)
			box(Vector3i(w / 2 - 2, h - 8, 0), Vector3i(w / 2 + 2, h - 3, 1), M.GLASS)
			if kind == "security":
				box(Vector3i(0, h / 2, 0), Vector3i(w, h / 2 + 1, 1), M.WARNING)
				box(Vector3i(w - 3, h / 2 - 3, 0), Vector3i(w - 1, h / 2 - 1, 1), M.SCREEN)


## Vent duct: a 2 m section, open at both ends, sheet metal walls around a 1 m wide, 1.2 m tall
## crawl space (a crouching player fits).
func vent_duct(origin: Vector3i, facing: int) -> void:
	_begin(origin, 12, 20, facing)
	box(Vector3i(0, 0, 0), Vector3i(12, 14, 20), M.METAL)
	box(Vector3i(1, 1, 0), Vector3i(11, 13, 20), M.AIR)
	for z in [0, 19]:
		box(Vector3i(0, 0, z), Vector3i(1, 14, z + 1), M.STEEL)
		box(Vector3i(11, 0, z), Vector3i(12, 14, z + 1), M.STEEL)
		box(Vector3i(0, 13, z), Vector3i(12, 14, z + 1), M.STEEL)


## Terminal: a steel desk with a tower and a big monitor whose screen faces the front.
func terminal(origin: Vector3i, facing: int) -> void:
	_begin(origin, 12, 7, facing)
	box(Vector3i(0, 7, 0), Vector3i(12, 8, 7), M.STEEL)
	_legs(12, 7, 7)
	box(Vector3i(9, 0, 2), Vector3i(11, 6, 6), M.RUBBER) # Tower.
	box(Vector3i(10, 4, 1), Vector3i(11, 5, 2), M.GLOW)
	box(Vector3i(3, 8, 1), Vector3i(9, 9, 3), M.RUBBER) # Keyboard.
	box(Vector3i(5, 8, 5), Vector3i(7, 10, 6), M.STEEL) # Stand.
	box(Vector3i(2, 10, 4), Vector3i(10, 16, 6), M.RUBBER) # Monitor.
	box(Vector3i(3, 11, 4), Vector3i(9, 15, 5), M.SCREEN)


## Cabinet: tall metal storage with two doors.
func cabinet(origin: Vector3i, facing: int) -> void:
	_begin(origin, 8, 4, facing)
	box(Vector3i(0, 0, 0), Vector3i(8, 20, 4), M.METAL)
	box(Vector3i(4, 1, 0), Vector3i(5, 19, 1), M.RUBBER) # Gap between the doors.
	box(Vector3i(3, 9, 0), Vector3i(4, 12, 1), M.STEEL)
	box(Vector3i(5, 9, 0), Vector3i(6, 12, 1), M.STEEL)
	box(Vector3i(0, 0, 0), Vector3i(8, 1, 1), M.RUBBER)


## Desk with a stack of drawers on each side.
func drawer_desk(origin: Vector3i, facing: int) -> void:
	_begin(origin, 16, 8, facing)
	box(Vector3i(0, 7, 0), Vector3i(16, 8, 8), M.WOOD)
	for x0 in [0, 11]:
		box(Vector3i(x0, 0, 0), Vector3i(x0 + 5, 7, 8), M.WOOD)
		for y in [1, 3, 5]:
			box(Vector3i(x0, y, 0), Vector3i(x0 + 5, y + 2, 1), M.PLASTIC)
			box(Vector3i(x0 + 2, y + 1, 0), Vector3i(x0 + 3, y + 2, 1), M.STEEL)


## Medkit station: a white wall box with a red cross, hung 1 m up.
func medkit_station(origin: Vector3i, facing: int) -> void:
	_begin(origin, 6, 2, facing)
	box(Vector3i(0, 10, 0), Vector3i(6, 16, 2), M.PLASTIC)
	box(Vector3i(2, 11, 0), Vector3i(4, 15, 1), M.EMERGENCY)
	box(Vector3i(1, 12, 0), Vector3i(5, 14, 1), M.EMERGENCY)
	box(Vector3i(0, 10, 1), Vector3i(6, 11, 2), M.STEEL)


## Ammo bench: a heavy workbench with ammo cans, a vise and a lamp.
func ammo_bench(origin: Vector3i, facing: int) -> void:
	_begin(origin, 14, 7, facing)
	box(Vector3i(0, 7, 0), Vector3i(14, 8, 7), M.DIAMOND_PLATE)
	_legs(14, 7, 7)
	box(Vector3i(1, 2, 1), Vector3i(13, 3, 6), M.STEEL) # Lower shelf.
	for i in 3:
		box(Vector3i(1 + i * 3, 8, 3), Vector3i(3 + i * 3, 10, 6), M.WARNING if i % 2 == 0 else M.METAL)
	box(Vector3i(2, 3, 2), Vector3i(5, 5, 5), M.WARNING)
	box(Vector3i(10, 8, 1), Vector3i(12, 10, 3), M.STEEL) # Vise.
	box(Vector3i(10, 10, 1), Vector3i(11, 11, 3), M.RUBBER)
	box(Vector3i(12, 8, 6), Vector3i(13, 14, 7), M.STEEL) # Lamp arm.
	box(Vector3i(11, 13, 4), Vector3i(13, 14, 6), M.LAMP)


## Generator: a big machine on a striped plinth, a lever on its front, an exhaust pipe and a light.
func generator(origin: Vector3i, facing: int) -> void:
	_begin(origin, 20, 12, facing)
	box(Vector3i(0, 0, 0), Vector3i(20, 2, 12), M.HAZARD_STRIPES)
	box(Vector3i(1, 2, 2), Vector3i(19, 14, 12), M.METAL)
	box(Vector3i(1, 2, 1), Vector3i(19, 3, 2), M.WARNING)
	for x in range(3, 13, 3):
		box(Vector3i(x, 5, 1), Vector3i(x + 1, 12, 2), M.STEEL) # Cooling fins.
	box(Vector3i(14, 6, 1), Vector3i(18, 12, 2), M.RUBBER) # Control panel.
	box(Vector3i(15, 10, 0), Vector3i(16, 11, 1), M.EMERGENCY)
	box(Vector3i(17, 10, 0), Vector3i(18, 11, 1), M.LAMP)
	box(Vector3i(16, 7, 0), Vector3i(17, 8, 1), M.STEEL) # Lever pivot.
	box(Vector3i(16, 8, 0), Vector3i(17, 11, 1), M.WARNING) # Lever.
	box(Vector3i(15, 11, 0), Vector3i(18, 12, 1), M.RUBBER) # Grip.
	box(Vector3i(3, 14, 6), Vector3i(5, 19, 8), M.PIPE) # Exhaust.
	box(Vector3i(1, 14, 2), Vector3i(19, 15, 12), M.DIAMOND_PLATE)


## Emergency glass case: a wall case, 1 m up, with a glass front over a hollow inside.
func glass_case(origin: Vector3i, facing: int) -> void:
	_begin(origin, 8, 3, facing)
	box(Vector3i(0, 9, 0), Vector3i(8, 19, 3), M.WARNING)
	box(Vector3i(1, 10, 0), Vector3i(7, 18, 2), M.AIR)
	box(Vector3i(1, 10, 0), Vector3i(7, 18, 1), M.GLASS)
	box(Vector3i(2, 13, 2), Vector3i(6, 14, 3), M.RUBBER) # Mount on the back wall.


# --- Lab in use ---------------------------------------------------------------------------------

## Specimen case: the training room's experiment. A glass box on a steel plinth with one glowing
## shroom inside on a bed of substrate and two electrode rods coming down from the lid on either
## side of it (the thing the experiment shocks). Glass voxels draw opaque, so the panes are open
## with a glass rim and a few glints: the shroom stays in sight.
func specimen_case(origin: Vector3i, facing: int) -> void:
	_begin(origin, 12, 12, facing)
	box(Vector3i(0, 0, 0), Vector3i(12, 4, 12), M.STEEL)
	box(Vector3i(0, 3, 0), Vector3i(12, 4, 1), M.HAZARD_STRIPES)
	box(Vector3i(9, 1, 0), Vector3i(11, 3, 1), M.SCREEN) # Readout on the plinth.
	_glass_panes(Vector3i(0, 4, 0), Vector3i(12, 15, 12))
	box(Vector3i(0, 15, 0), Vector3i(12, 16, 12), M.STEEL) # Lid.
	box(Vector3i(1, 4, 1), Vector3i(11, 5, 11), M.SUBSTRATE)
	# The shroom: a stem, a capped head with gills under it and a glowing crown.
	box(Vector3i(5, 5, 5), Vector3i(7, 9, 7), M.SHROOM_STEM)
	box(Vector3i(3, 9, 3), Vector3i(9, 10, 9), M.SHROOM_GILL)
	box(Vector3i(3, 10, 3), Vector3i(9, 11, 9), M.SHROOM_CAP)
	box(Vector3i(4, 11, 4), Vector3i(8, 12, 8), M.SHROOM_CAP)
	box(Vector3i(4, 10, 3), Vector3i(5, 11, 4), M.SHROOM_SPOT)
	box(Vector3i(7, 10, 8), Vector3i(8, 11, 9), M.SHROOM_SPOT)
	box(Vector3i(5, 11, 4), Vector3i(6, 12, 5), M.GLOW)
	box(Vector3i(5, 12, 5), Vector3i(7, 13, 7), M.GLOW)
	box(Vector3i(5, 7, 4), Vector3i(7, 8, 5), M.SHROOM_EYE)
	# Electrodes: rods from the lid, warning-striped tips just off the cap.
	for x in [1, 10]:
		box(Vector3i(x, 9, 5), Vector3i(x + 1, 15, 7), M.STEEL)
		box(Vector3i(x, 8, 5), Vector3i(x + 1, 9, 7), M.WARNING)
	box(Vector3i(1, 15, 5), Vector3i(2, 16, 6), M.EMERGENCY)
	box(Vector3i(10, 15, 6), Vector3i(11, 16, 7), M.EMERGENCY)


## Vial cabinet: a steel cabinet with glass doors and four shelves of colored vials.
func vial_cabinet(origin: Vector3i, facing: int) -> void:
	_begin(origin, 12, 5, facing)
	box(Vector3i(0, 0, 0), Vector3i(12, 20, 5), M.STEEL)
	box(Vector3i(1, 2, 0), Vector3i(11, 19, 4), M.AIR)
	box(Vector3i(0, 0, 0), Vector3i(12, 1, 1), M.RUBBER)
	for y in [2, 6, 10, 14]:
		box(Vector3i(1, y, 1), Vector3i(11, y + 1, 4), M.STEEL)
		var x := 1
		while x < 11:
			var tall := rng.randi_range(1, 2)
			var liquid: int = SAMPLES[rng.randi() % SAMPLES.size()]
			var z := rng.randi_range(1, 2)
			box(Vector3i(x, y + 1, z), Vector3i(x + 1, y + 1 + tall, z + 1), liquid)
			box(Vector3i(x, y + 1 + tall, z), Vector3i(x + 1, y + 2 + tall, z + 1), M.RUBBER)
			x += rng.randi_range(1, 2)
	# Glass doors (open panes with a rim and glints, as glass voxels draw opaque).
	box(Vector3i(1, 18, 0), Vector3i(11, 19, 1), M.GLASS)
	box(Vector3i(6, 2, 0), Vector3i(7, 19, 1), M.STEEL) # Door frames.
	box(Vector3i(5, 9, 0), Vector3i(6, 11, 1), M.RUBBER) # Handles.
	box(Vector3i(7, 9, 0), Vector3i(8, 11, 1), M.RUBBER)
	for g in [Vector3i(2, 16, 0), Vector3i(3, 15, 0), Vector3i(8, 13, 0), Vector3i(9, 12, 0)]:
		box(g, g + Vector3i(1, 1, 1), M.GLASS)


## Specimen jar: a small jar of green fluid with a shroom floating in it, pressed against the glass.
func specimen_jar(origin: Vector3i, facing: int) -> void:
	_begin(origin, 4, 4, facing)
	box(Vector3i(0, 0, 0), Vector3i(4, 1, 4), M.STEEL)
	box(Vector3i(0, 1, 0), Vector3i(4, 4, 4), M.LIQUID_GREEN)
	for x in [0, 3]:
		for z in [0, 3]:
			box(Vector3i(x, 1, z), Vector3i(x + 1, 5, z + 1), M.GLASS)
	box(Vector3i(1, 1, 0), Vector3i(2, 3, 1), M.SHROOM_STEM)
	box(Vector3i(1, 3, 0), Vector3i(3, 4, 1), M.SHROOM_CAP)
	box(Vector3i(2, 3, 0), Vector3i(3, 4, 1), M.GLOW)
	box(Vector3i(0, 4, 0), Vector3i(4, 5, 4), M.GLASS)
	box(Vector3i(1, 5, 1), Vector3i(3, 6, 3), M.RUBBER) # Lid.


## A grow bed with a crop of young shrooms coming up through the substrate, a few of them glowing.
func grow_bed_shrooms(origin: Vector3i, facing: int, w := 30, d := 12) -> void:
	grow_bed(origin, facing, w, d)
	for x in range(2, w - 2, 3):
		for z in range(2, d - 2, 3):
			var at := Vector3i(x + rng.randi_range(0, 1), 3, z + rng.randi_range(0, 1))
			if at.x >= w - 2 or at.z >= d - 2 or rng.randf() < 0.2:
				continue
			var stem := rng.randi_range(1, 3)
			box(at, at + Vector3i(1, stem, 1), M.SHROOM_STEM)
			var top := at + Vector3i(0, stem, 0)
			if rng.randf() < 0.5:
				box(top, top + Vector3i(2, 1, 2), M.SHROOM_CAP)
			else:
				box(top, top + Vector3i(1, 1, 1), M.SHROOM_CAP)
			if rng.randf() < 0.3:
				box(top + Vector3i(0, 1, 0), top + Vector3i(1, 2, 1), M.GLOW)
			elif rng.randf() < 0.3:
				box(top, top + Vector3i(1, 1, 1), M.SHROOM_SPOT)


## Lab table with a microscope, flasks, beakers and a tube rack set out on it.
func lab_table_gear(origin: Vector3i, facing: int, w := 16, d := 8) -> void:
	table(origin, facing, w, d, M.PLASTIC)
	box(Vector3i(1, 2, 1), Vector3i(w - 1, 3, d - 1), M.STEEL) # Lower shelf.
	_beaker(Vector3i(2, 3, 2), M.LIQUID_BLUE)
	_microscope(Vector3i(1, 7, 3))
	_flask(Vector3i(5, 7, 1), SAMPLES[rng.randi() % SAMPLES.size()])
	_tube_rack(Vector3i(9, 7, 1))
	_beaker(Vector3i(9, 7, 5), SAMPLES[rng.randi() % SAMPLES.size()])
	_beaker(Vector3i(12, 7, 4), SAMPLES[rng.randi() % SAMPLES.size()])
	# A specimen jar (fluid to the glass, the shroom against the front).
	box(Vector3i(5, 7, 4), Vector3i(9, 8, 8), M.STEEL)
	box(Vector3i(5, 8, 4), Vector3i(9, 11, 8), M.LIQUID_GREEN)
	box(Vector3i(6, 8, 4), Vector3i(7, 10, 5), M.SHROOM_STEM)
	box(Vector3i(6, 10, 4), Vector3i(8, 11, 5), M.SHROOM_CAP)
	box(Vector3i(7, 10, 4), Vector3i(8, 11, 5), M.GLOW)
	box(Vector3i(5, 11, 4), Vector3i(9, 12, 8), M.GLASS)
	box(Vector3i(6, 12, 5), Vector3i(8, 13, 7), M.RUBBER)


## A pot of substrate with one shroom growing out of it.
func shroom_pot(origin: Vector3i) -> void:
	_begin(origin, 4, 4, NORTH)
	box(Vector3i(0, 0, 0), Vector3i(4, 3, 4), M.CLAY)
	box(Vector3i(1, 2, 1), Vector3i(3, 3, 3), M.SUBSTRATE)
	box(Vector3i(1, 3, 1), Vector3i(2, 6, 2), M.SHROOM_STEM)
	box(Vector3i(0, 6, 0), Vector3i(3, 7, 3), M.SHROOM_CAP)
	box(Vector3i(1, 7, 1), Vector3i(2, 8, 2), M.SHROOM_CAP)
	box(Vector3i(2, 6, 0), Vector3i(3, 7, 1), M.SHROOM_SPOT)
	box(Vector3i(0, 5, 0), Vector3i(3, 6, 3), M.SHROOM_GILL)
	box(Vector3i(1, 5, 1), Vector3i(2, 6, 2), M.SHROOM_STEM)


# --- Parts placed in the current prop's frame ---------------------------------------------------

## The walls of a glass box over [from, to) in the prop's frame: steel corner posts, a glass rim at
## the bottom and top of each pane and two glints across it; the panes themselves are left open
## (glass voxels draw opaque, and the point of a case is to see what's in it).
func _glass_panes(from: Vector3i, to: Vector3i) -> void:
	var w := to.x - from.x
	var d := to.z - from.z
	for y in [from.y, to.y - 1]:
		box(Vector3i(from.x, y, from.z), Vector3i(to.x, y + 1, from.z + 1), M.GLASS)
		box(Vector3i(from.x, y, to.z - 1), Vector3i(to.x, y + 1, to.z), M.GLASS)
		box(Vector3i(from.x, y, from.z), Vector3i(from.x + 1, y + 1, to.z), M.GLASS)
		box(Vector3i(to.x - 1, y, from.z), Vector3i(to.x, y + 1, to.z), M.GLASS)
	for x in [from.x, to.x - 1]:
		for z in [from.z, to.z - 1]:
			box(Vector3i(x, from.y, z), Vector3i(x + 1, to.y, z + 1), M.STEEL)
	var h := to.y - from.y
	for i in 2:
		var y := from.y + h - 3 - i
		box(Vector3i(from.x + 2 + i, y, from.z), Vector3i(from.x + 3 + i, y + 1, from.z + 1), M.GLASS)
		box(Vector3i(to.x - 3 - i, y - 4, to.z - 1), Vector3i(to.x - 2 - i, y - 3, to.z), M.GLASS)
		box(Vector3i(from.x, y, from.z + 2 + i), Vector3i(from.x + 1, y + 1, from.z + 3 + i), M.GLASS)
		box(Vector3i(to.x - 1, y - 4, to.z - 3 - i), Vector3i(to.x, y - 3, to.z - 2 - i), M.GLASS)


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
			"jars":
				# Specimen jars: green fluid, a shroom speck, a rubber lid.
				box(p, p + Vector3i(2, 3, 2), M.LIQUID_GREEN if rng.randf() < 0.7 else M.LIQUID_PINK)
				box(p + Vector3i(rng.randi_range(0, 1), 1, 0), p + Vector3i(rng.randi_range(0, 1) + 1, 2, 1), M.SHROOM_CAP if rng.randf() < 0.6 else M.GLOW)
				box(p + Vector3i(0, 3, 0), p + Vector3i(2, 4, 2), M.GLASS)
				box(p + Vector3i(0, 4, 0), p + Vector3i(2, 5, 2), M.RUBBER)
				x += 3
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
