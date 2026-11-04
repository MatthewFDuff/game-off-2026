class_name PropCatalog
## The placeholder props: each library name with the Props generator call that draws it, facing
## north at the origin. tools/export_vox.gd writes these to assets/vox/props/<name>.vox; after
## that the .vox files are the source of truth and can be edited freely in MagicaVoxel.
##
## Props with random dressing (shelf stock, bench equipment, board scribbles) get a few lettered
## variants, each from its own fixed seed.
##
## Props come in packs, one file each under scripts/world/packs/. To add a pack:
##   1. Write scripts/world/packs/<name>_pack.gd (copy ceiling_pack.gd's header):
##        extends RefCounted
##        const CATEGORY := "Ceiling"            # editor tab for every prop the pack draws ("" = by prefix)
##        const MOUNTS := {"duct_": "ceiling"}   # name prefix -> floor | wall | ceiling | door | any
##        const VALUES := {"duct_": 150}         # name prefix -> payroll value in $
##        const USES := {}                       # name prefix -> default use (LevelSchema USES)
##        static func entries(add: Callable) -> void:
##            add.call("duct_straight", func(p: Props, o: Vector3i) -> void: _duct(p, o))
##      Draw with p.begin(o, w, d, P.NORTH) and p.box(from, to, material) in the prop's frame,
##      inside its w x d footprint and from y = 0 up (generate() warns about anything outside).
##   2. Add one line to PACKS below.
## A pack's CATEGORY is the tab for every prop it draws. The other tables are merged after the
## built-in ones (MOUNTS here, LevelSchema's ASSET_VALUES and DEFAULT_USES); the longest matching
## prefix wins, and a prefix two tables give different values gets a warning. Then run tools/export_vox.gd (never --force) for the files.

const P := preload("res://scripts/world/props.gd")

## The prop packs, in catalog order.
const PACKS := [
	preload("res://scripts/world/packs/base_pack.gd"),
	preload("res://scripts/world/packs/ceiling_pack.gd"),
	preload("res://scripts/world/packs/lighting_pack.gd"),
	preload("res://scripts/world/packs/corridor_pack.gd"),
	preload("res://scripts/world/packs/compute_pack.gd"),
	preload("res://scripts/world/packs/plant_pack.gd"),
	preload("res://scripts/world/packs/mine_pack.gd"),
	preload("res://scripts/world/packs/kitchen_pack.gd"),
	preload("res://scripts/world/packs/bathroom_pack.gd"),
	preload("res://scripts/world/packs/office_pack.gd"),
	preload("res://scripts/world/packs/exec_pack.gd"),
	preload("res://scripts/world/packs/story_pack.gd"),
	preload("res://scripts/world/packs/specimen_pack.gd"),
	preload("res://scripts/world/packs/decon_pack.gd"),
	preload("res://scripts/world/packs/security_pack.gd"),
	preload("res://scripts/world/packs/interact_pack.gd"),
]


## Editor catalog tabs, by prop name prefix. Props from new .vox files that match none go in Other.
const CATEGORIES := {
	"Lab": ["lab_bench", "lab_table", "fume_hood", "shelf_lab", "spore_tank", "grow_bed", "specimen", "vial_cabinet", "shroom_pot", "clone_vat"],
	"Office": ["desk", "chair", "table", "couch", "whiteboard", "corkboard", "locker", "bench", "stool", "fake_plant", "rubber_duck", "sleeping_bag"],
	"Kitchen": ["counter", "fridge", "water_cooler", "vending_machine", "trash_can"],
	"Storage": ["shelf_storage", "crate", "barrel", "plank_stack", "sandbags"],
	"Doors": ["door_", "vent_hatch"],
}


## What a prop attaches to when placed (PropPlacement), by name prefix; anything else stands on the
## floor. "door" props go into a wall and cut their own doorway.
const MOUNTS := {
	"whiteboard": "wall", "corkboard": "wall", "vent_grate": "wall",
	"door_": "door", "vent_hatch": "door",
}


static func mount_of(prop_name: String) -> String:
	var mounts := merged("MOUNTS", MOUNTS)
	var best := ""
	for prefix: String in mounts:
		if prop_name.begins_with(prefix) and prefix.length() > best.length():
			best = prefix
	return mounts.get(best, "floor")


## A pack's CATEGORY wins for the props it draws (so an overgrown desk sits in Story, not
## Office); the prefix table covers the base pack and props from .vox files no pack draws.
static func category_of(prop_name: String) -> String:
	_index()
	if _pack_category.has(prop_name):
		return _pack_category[prop_name]
	for category: String in CATEGORIES:
		for prefix: String in CATEGORIES[category]:
			if prop_name.begins_with(prefix):
				return category
	return "Other"


## A table (MOUNTS, VALUES or USES) with every pack's merged in after the built-in one, built once.
static func merged(table: String, built_in: Dictionary) -> Dictionary:
	if not _merged.has(table):
		var out := built_in.duplicate()
		for pack: Script in PACKS:
			var extra: Dictionary = pack.get_script_constant_map().get(table, {})
			for prefix: String in extra:
				if out.has(prefix) and out[prefix] != extra[prefix]:
					push_warning("prop pack %s: %s[%s] is already %s" % [pack.resource_path.get_file(), table, prefix, out[prefix]])
					continue
				out[prefix] = extra[prefix]
		_merged[table] = out
	return _merged[table]


static var _merged := {}
## Prop name -> its pack's CATEGORY, for packs that have one.
static var _pack_category := {}
static var _indexed := false


static func _index() -> void:
	if _indexed:
		return
	_indexed = true
	for pack: Script in PACKS:
		var category: String = pack.get_script_constant_map().get("CATEGORY", "")
		if category == "":
			continue
		pack.entries(func(name: String, _draw: Callable) -> void: _pack_category[name] = category)


## [{name: String, draw: Callable(props: Props, origin: Vector3i)}], every pack's in PACKS order.
static func entries() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var seen := {}
	var add := func(name: String, draw: Callable) -> void:
		if seen.has(name):
			push_warning("prop %s is drawn by two packs; keeping the first" % name)
			return
		seen[name] = true
		list.append({name = name, draw = draw})
	for pack: Script in PACKS:
		pack.entries(add)
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
