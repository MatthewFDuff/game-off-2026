extends RefCounted
## The original placeholder catalog (offices, labs, storage, doors) as one pack. Its categories,
## mounts, values and uses are PropCatalog's and LevelSchema's built-in tables, so the tables here
## are empty. See prop_catalog.gd for how packs work.

const P := preload("res://scripts/world/props.gd")

const CATEGORY := ""
const MOUNTS := {}
const VALUES := {}
const USES := {}


static func entries(add: Callable) -> void:
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
	add.call("shelf_lab_jars", func(p: Props, o: Vector3i) -> void: p.shelf(o, P.NORTH, 12, 20, 4, "jars"))
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
	add.call("clone_vat", func(p: Props, o: Vector3i) -> void: p.clone_vat(o))
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
	add.call("specimen_case", func(p: Props, o: Vector3i) -> void: p.specimen_case(o, P.NORTH))
	add.call("vial_cabinet", func(p: Props, o: Vector3i) -> void: p.vial_cabinet(o, P.NORTH))
	add.call("specimen_jar", func(p: Props, o: Vector3i) -> void: p.specimen_jar(o, P.NORTH))
	for v in ["a", "b"]:
		add.call("grow_bed_shrooms_" + v, func(p: Props, o: Vector3i) -> void: p.grow_bed_shrooms(o, P.NORTH, 30, 12))
	add.call("lab_table_gear", func(p: Props, o: Vector3i) -> void: p.lab_table_gear(o, P.NORTH))
	add.call("fake_plant", func(p: Props, o: Vector3i) -> void: p.fake_plant(o))
	add.call("rubber_duck", func(p: Props, o: Vector3i) -> void: p.rubber_duck(o))
	add.call("sleeping_bag", func(p: Props, o: Vector3i) -> void: p.sleeping_bag(o))
	add.call("shroom_pot", func(p: Props, o: Vector3i) -> void: p.shroom_pot(o))
	add.call("door_single", func(p: Props, o: Vector3i) -> void: p.door_panel(o, P.NORTH, 12, 22, "single"))
	add.call("door_double", func(p: Props, o: Vector3i) -> void: p.door_panel(o, P.NORTH, 24, 22, "single"))
	add.call("door_security", func(p: Props, o: Vector3i) -> void: p.door_panel(o, P.NORTH, 12, 22, "security"))
	add.call("door_blast", func(p: Props, o: Vector3i) -> void: p.door_panel(o, P.NORTH, 24, 24, "blast"))
	add.call("vent_hatch", func(p: Props, o: Vector3i) -> void: p.door_panel(o, P.NORTH, 12, 12, "hatch"))
