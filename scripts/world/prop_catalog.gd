class_name PropCatalog
## The placeholder props: each library name with the Props generator call that draws it, facing
## north at the origin. tools/export_vox.gd writes these to assets/vox/props/<name>.vox; after
## that the .vox files are the source of truth and can be edited freely in MagicaVoxel.
##
## Props with random dressing (shelf stock, bench equipment, board scribbles) get a few lettered
## variants, each from its own fixed seed.

const P := preload("res://scripts/world/props.gd")


## Editor catalog tabs, by prop name prefix. Props from new .vox files that match none go in Other.
const CATEGORIES := {
	"Lab": ["lab_bench", "fume_hood", "shelf_lab", "spore_tank", "grow_bed"],
	"Office": ["desk", "chair", "table", "couch", "whiteboard", "corkboard", "locker", "bench", "stool"],
	"Kitchen": ["counter", "fridge", "water_cooler", "vending_machine", "trash_can"],
	"Storage": ["shelf_storage", "crate", "barrel", "plank_stack", "sandbags"],
}


static func category_of(prop_name: String) -> String:
	for category: String in CATEGORIES:
		for prefix: String in CATEGORIES[category]:
			if prop_name.begins_with(prefix):
				return category
	return "Other"


## [{name: String, draw: Callable(props: Props, origin: Vector3i)}]
static func entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var add := func(name: String, draw: Callable) -> void: list.append({name = name, draw = draw})

	add.call("table_small", func(p: Props, o: Vector3i) -> void: p.table(o, P.NORTH, 10, 6))
	add.call("table", func(p: Props, o: Vector3i) -> void: p.table(o, P.NORTH, 12, 8))
	add.call("table_large", func(p: Props, o: Vector3i) -> void: p.table(o, P.NORTH, 16, 10))
	add.call("chair", func(p: Props, o: Vector3i) -> void: p.chair(o, P.NORTH))
	add.call("stool", func(p: Props, o: Vector3i) -> void: p.stool(o))
	add.call("bench", func(p: Props, o: Vector3i) -> void: p.bench(o, P.NORTH, 14))
	add.call("couch", func(p: Props, o: Vector3i) -> void: p.couch(o, P.NORTH))
	add.call("desk", func(p: Props, o: Vector3i) -> void: p.desk(o, P.NORTH, 16))
	add.call("desk_empty", func(p: Props, o: Vector3i) -> void: p.desk(o, P.NORTH, 16, false))
	for v in ["a", "b", "c"]:
		add.call("lab_bench_" + v, func(p: Props, o: Vector3i) -> void: p.lab_bench(o, P.NORTH, 26, 7))
	for v in ["a", "b"]:
		add.call("shelf_lab_" + v, func(p: Props, o: Vector3i) -> void: p.shelf(o, P.NORTH, 12, 20, 4, "lab"))
		add.call("shelf_storage_" + v, func(p: Props, o: Vector3i) -> void: p.shelf(o, P.NORTH, 12, 20, 4, "storage"))
	add.call("fume_hood", func(p: Props, o: Vector3i) -> void: p.fume_hood(o, P.NORTH))
	add.call("fridge", func(p: Props, o: Vector3i) -> void: p.fridge(o, P.NORTH))
	add.call("water_cooler", func(p: Props, o: Vector3i) -> void: p.water_cooler(o, P.NORTH))
	add.call("counter_sink", func(p: Props, o: Vector3i) -> void: p.counter(o, P.NORTH, 16, true))
	add.call("counter_coffee", func(p: Props, o: Vector3i) -> void: p.counter(o, P.NORTH, 12, false))
	add.call("vending_machine", func(p: Props, o: Vector3i) -> void: p.vending_machine(o, P.NORTH))
	add.call("locker", func(p: Props, o: Vector3i) -> void: p.locker(o, P.NORTH))
	for s in [5, 6, 7, 8]:
		add.call("crate_%d" % s, func(p: Props, o: Vector3i) -> void: p.crate(o, s))
	add.call("barrel", func(p: Props, o: Vector3i) -> void: p.barrel(o))
	add.call("barrel_hazard", func(p: Props, o: Vector3i) -> void: p.barrel(o, true))
	add.call("trash_can", func(p: Props, o: Vector3i) -> void: p.trash_can(o))
	add.call("grow_bed", func(p: Props, o: Vector3i) -> void: p.grow_bed(o, P.NORTH, 30, 12))
	add.call("spore_tank", func(p: Props, o: Vector3i) -> void: p.spore_tank(o))
	add.call("plank_stack", func(p: Props, o: Vector3i) -> void: p.plank_stack(o, P.NORTH, 5))
	add.call("sandbags", func(p: Props, o: Vector3i) -> void: p.sandbags(o, P.NORTH))
	add.call("whiteboard", func(p: Props, o: Vector3i) -> void: p.wall_board(o, P.NORTH, 18, 9, true))
	for v in ["a", "b", "c"]:
		add.call("corkboard_" + v, func(p: Props, o: Vector3i) -> void: p.wall_board(o, P.NORTH, 16, 9, false))
	add.call("corkboard_small", func(p: Props, o: Vector3i) -> void: p.wall_board(o, P.NORTH, 12, 8, false))
	add.call("corkboard_tall", func(p: Props, o: Vector3i) -> void: p.wall_board(o, P.NORTH, 10, 12, false))
	add.call("vent_grate", func(p: Props, o: Vector3i) -> void: p.vent_grate(o, P.NORTH))
	add.call("vent_duct", func(p: Props, o: Vector3i) -> void: p.vent_duct(o, P.NORTH))
	add.call("terminal", func(p: Props, o: Vector3i) -> void: p.terminal(o, P.NORTH))
	add.call("cabinet", func(p: Props, o: Vector3i) -> void: p.cabinet(o, P.NORTH))
	add.call("drawer_desk", func(p: Props, o: Vector3i) -> void: p.drawer_desk(o, P.NORTH))
	add.call("medkit_station", func(p: Props, o: Vector3i) -> void: p.medkit_station(o, P.NORTH))
	add.call("ammo_bench", func(p: Props, o: Vector3i) -> void: p.ammo_bench(o, P.NORTH))
	add.call("generator", func(p: Props, o: Vector3i) -> void: p.generator(o, P.NORTH))
	add.call("glass_case", func(p: Props, o: Vector3i) -> void: p.glass_case(o, P.NORTH))
	return list


## Draws a catalog entry into a scratch world and returns it as a model whose box is the prop's
## frame: its footprint, from the floor up to the top of the tallest voxel.
static func generate(entry: Dictionary) -> Dictionary:
	var world := VoxelWorld.new()
	world.size_in_chunks = Vector3i(2, 2, 2)
	world.out_of_bounds_solid = false
	world.immediate_remesh_limit = 0 # Never shown; skip meshing.
	var origin := Vector3i(8, 8, 8)
	var props := Props.new(world, 0)
	props.rng.seed = hash(entry.name)
	entry.draw.call(props, origin)
	var footprint := Vector2i(props._w, props._d)

	var top := 0
	var lo := Vector3i(origin.x, origin.y, origin.z)
	var hi := lo + Vector3i(footprint.x, 0, footprint.y)
	var grid := world.get_size_in_voxels()
	const MARGIN := 6 # How far outside the footprint to look for stray voxels.
	for y in range(origin.y, grid.y):
		for z in range(lo.z - MARGIN, hi.z + MARGIN):
			for x in range(lo.x - MARGIN, hi.x + MARGIN):
				if world.get_voxel(Vector3i(x, y, z)) != 0:
					top = maxi(top, y - origin.y + 1)
					if x < lo.x or z < lo.z or x >= hi.x or z >= hi.z:
						push_warning("prop %s draws outside its footprint at %s" % [entry.name, Vector3i(x, y, z)])
	var size := Vector3i(footprint.x, maxi(top, 1), footprint.y)
	var voxels := PackedByteArray()
	voxels.resize(size.x * size.y * size.z)
	for z in size.z:
		for y in size.y:
			for x in size.x:
				voxels[x + y * size.x + z * size.x * size.y] = world.get_voxel(origin + Vector3i(x, y, z))
	world.free()
	return {size = size, voxels = voxels}
