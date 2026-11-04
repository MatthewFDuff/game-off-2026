extends RefCounted
## Specimen, morgue and waste props (docs/prop-build-plan.md D4). Floor props face north (front at
## z = 0); the trash chute is a wall prop. Colours: red bins are BLOCK_WALL (brick), the dumpster is
## WALL_LOWER green, bags are RUBBER.

const P := preload("res://scripts/world/props.gd")
const M := preload("res://scripts/voxel/voxel_materials.gd")

const CATEGORY := "Specimen"
const MOUNTS := {
	"animal_cage": "floor", "specimen_tank": "floor", "dissection_table": "floor", "cold_store": "floor",
	"body_bag": "floor", "morgue_drawers": "floor", "biohazard_bin": "floor", "incinerator": "floor",
	"dumpster": "floor", "trash_chute": "wall",
}
const VALUES := {
	"animal_cage": 120, "animal_cage_stack": 380, "specimen_tank": 1800, "dissection_table": 1300,
	"cold_store": 900, "body_bag": 25, "morgue_drawers": 2600, "biohazard_bin": 90,
	"incinerator": 4000, "dumpster": 450, "trash_chute": 200,
}
const USES := {}


static func entries(add: Callable) -> void:
	add.call("animal_cage_small", func(p: Props, o: Vector3i) -> void: cage(p, o, 1))
	add.call("animal_cage_stack", func(p: Props, o: Vector3i) -> void: cage(p, o, 3))
	add.call("specimen_tank_tall", func(p: Props, o: Vector3i) -> void: tank(p, o))
	add.call("dissection_table", func(p: Props, o: Vector3i) -> void: dissection_table(p, o))
	add.call("cold_store_rack", func(p: Props, o: Vector3i) -> void: cold_store(p, o))
	add.call("body_bag_table", func(p: Props, o: Vector3i) -> void: body_bag_table(p, o))
	add.call("body_bag_floor", func(p: Props, o: Vector3i) -> void: body_bag_floor(p, o))
	add.call("morgue_drawers", func(p: Props, o: Vector3i) -> void: morgue_drawers(p, o))
	add.call("biohazard_bin", func(p: Props, o: Vector3i) -> void: biohazard_bin(p, o))
	add.call("incinerator", func(p: Props, o: Vector3i) -> void: incinerator(p, o))
	add.call("dumpster", func(p: Props, o: Vector3i) -> void: dumpster(p, o))
	add.call("trash_chute", func(p: Props, o: Vector3i) -> void: trash_chute(p, o))


static func _b(p: Props, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, m: int) -> void:
	p.box(Vector3i(x0, y0, z0), Vector3i(x1, y1, z1), m)


## Lab animal cage(s), 8 wide: a tray, steel bars, a water bottle and a small grey occupant. levels
## 1 is the small cage; 3 stacks them on a steel frame (6 tall each).
static func cage(p: Props, o: Vector3i, levels: int) -> void:
	p.begin(o, 8, 6, P.NORTH)
	var base := 0 if levels == 1 else 2
	if levels > 1:
		for x in [0, 7]:
			for z in [0, 5]:
				_b(p, x, 0, z, x + 1, base + levels * 6 + 1, z + 1, M.STEEL)
		_b(p, 0, 0, 0, 8, 1, 6, M.STEEL)
	for i in levels:
		var y := base + i * 6
		_b(p, 0, y, 0, 8, y + 1, 6, M.PLASTIC) # Tray.
		_b(p, 1, y + 1, 1, 7, y + 2, 5, M.PLANK) # Bedding.
		for x in range(1, 8, 2):
			_b(p, x, y + 1, 0, x + 1, y + 5, 1, M.STEEL) # Front bars.
		_b(p, 0, y + 5, 0, 8, y + 6, 6, M.STEEL) # Roof.
		_b(p, 0, y + 1, 5, 8, y + 5, 6, M.STEEL) # Back wall.
		_b(p, 6, y + 3, 1, 7, y + 5, 2, M.GLASS) # Water bottle.
		_b(p, 6, y + 3, 1, 7, y + 4, 2, M.WATER)
		_b(p, 2 + (i % 2), y + 2, 2, 4 + (i % 2), y + 3, 4, M.TILE_DARK) # Occupant.
		_b(p, 4 + (i % 2), y + 2, 3, 5 + (i % 2), y + 3, 4, M.TILE_DARK)


## Tall specimen tank: glass shell on a steel base, liquid inside and a pale mushroom-limbed shape
## floating in it with glowing eyes.
static func tank(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 8, P.NORTH)
	_b(p, 0, 0, 0, 8, 3, 8, M.STEEL)
	_b(p, 0, 3, 0, 8, 22, 8, M.GLASS)
	_b(p, 1, 3, 1, 7, 21, 7, M.LIQUID_BLUE)
	_b(p, 0, 22, 0, 8, 24, 8, M.STEEL)
	_b(p, 3, 24, 3, 5, 26, 5, M.PIPE) # Feed pipe.
	_b(p, 3, 6, 3, 5, 14, 5, M.SHROOM_STEM) # Body.
	_b(p, 2, 14, 2, 6, 17, 6, M.SHROOM_CAP) # Cap.
	_b(p, 2, 13, 2, 6, 14, 6, M.SHROOM_GILL)
	_b(p, 2, 14, 2, 3, 15, 3, M.SHROOM_EYE)
	_b(p, 5, 14, 2, 6, 15, 3, M.SHROOM_EYE)
	_b(p, 2, 8, 3, 3, 12, 5, M.SHROOM_STEM) # Limbs.
	_b(p, 5, 8, 3, 6, 11, 5, M.SHROOM_STEM)
	_b(p, 1, 3, 3, 7, 4, 5, M.RUBBER) # Weighted base plate.
	_b(p, 0, 23, 0, 1, 24, 8, M.GLOW)


## Dissection table: a steel top with a raised rim and drain channel, a bucket beneath and a tool tray.
static func dissection_table(p: Props, o: Vector3i) -> void:
	p.begin(o, 18, 8, P.NORTH)
	for x in [1, 16]:
		for z in [1, 6]:
			_b(p, x, 0, z, x + 1, 6, z + 1, M.STEEL)
	_b(p, 0, 6, 0, 18, 7, 8, M.STEEL)
	_b(p, 0, 7, 0, 18, 8, 1, M.STEEL) # Rim.
	_b(p, 0, 7, 7, 18, 8, 8, M.STEEL)
	_b(p, 0, 7, 0, 1, 8, 8, M.STEEL)
	_b(p, 17, 7, 0, 18, 8, 8, M.STEEL)
	_b(p, 2, 7, 3, 16, 8, 5, M.TILE_DARK) # Drain channel.
	_b(p, 15, 6, 3, 16, 7, 5, M.RUBBER) # Drain hole.
	_b(p, 4, 7, 3, 11, 8, 5, M.LIQUID_PINK) # Spill along the channel.
	_b(p, 14, 0, 3, 17, 4, 5, M.PLASTIC) # Bucket under the drain.
	_b(p, 15, 3, 3, 16, 4, 5, M.EMBER_DEEP)
	_b(p, 1, 8, 1, 4, 9, 3, M.PLASTIC) # Tool tray.
	_b(p, 1, 9, 1, 2, 10, 2, M.STEEL)
	_b(p, 3, 9, 2, 4, 10, 3, M.STEEL)


## Cold-store rack: four shelves of frosty boxes, jars and wrapped bags.
static func cold_store(p: Props, o: Vector3i) -> void:
	p.begin(o, 14, 6, P.NORTH)
	for x in [0, 13]:
		for z in [0, 5]:
			_b(p, x, 0, z, x + 1, 20, z + 1, M.STEEL)
	for i in 4:
		var y := i * 5
		_b(p, 0, y, 0, 14, y + 1, 6, M.STEEL)
		var x := 1
		while x < 12:
			var w := mini(p.rng.randi_range(2, 4), 13 - x)
			var kind := p.rng.randi_range(0, 2)
			if kind == 0:
				_b(p, x, y + 1, 1, x + w, y + 4, 5, M.PLASTIC) # Frosted box.
				_b(p, x, y + 3, 1, x + w, y + 4, 5, M.TILE_LIGHT)
			elif kind == 1:
				_b(p, x, y + 1, 2, x + w, y + 3, 4, M.LIQUID_BLUE) # Jars.
				_b(p, x, y + 3, 2, x + w, y + 4, 4, M.GLASS)
			else:
				_b(p, x, y + 1, 1, x + w, y + 3, 5, M.TILE_DARK) # Wrapped.
			x += w + 1
	_b(p, 0, 19, 0, 14, 20, 6, M.STEEL)


## A bag on a steel gurney, zipped, with the shape of a person.
static func body_bag_table(p: Props, o: Vector3i) -> void:
	p.begin(o, 20, 8, P.NORTH)
	for x in [1, 18]:
		for z in [1, 6]:
			_b(p, x, 0, z, x + 1, 6, z + 1, M.STEEL)
	_b(p, 0, 6, 0, 20, 7, 8, M.STEEL)
	_b(p, 1, 7, 1, 19, 9, 7, M.RUBBER) # Bag.
	_b(p, 2, 9, 2, 5, 11, 6, M.RUBBER) # Head.
	_b(p, 6, 9, 1, 12, 10, 7, M.RUBBER) # Chest.
	_b(p, 13, 9, 2, 18, 10, 6, M.RUBBER) # Legs.
	_b(p, 1, 9, 3, 18, 10, 4, M.STEEL) # Zipper.
	_b(p, 17, 7, 0, 18, 8, 1, M.WARNING) # Toe tag.


## The same bag on the floor.
static func body_bag_floor(p: Props, o: Vector3i) -> void:
	p.begin(o, 20, 7, P.NORTH)
	_b(p, 0, 0, 1, 20, 2, 6, M.RUBBER)
	_b(p, 1, 2, 2, 5, 3, 5, M.RUBBER) # Head.
	_b(p, 6, 2, 1, 12, 3, 6, M.RUBBER) # Chest.
	_b(p, 13, 2, 2, 19, 3, 5, M.RUBBER) # Legs.
	_b(p, 1, 3, 3, 19, 4, 4, M.STEEL) # Zipper.
	_b(p, 18, 2, 5, 19, 3, 6, M.WARNING)


## Morgue drawer wall: 5 columns x 3 rows of steel doors (30 wide, 22 tall) in a steel case at the
## back, with the middle drawer pulled out over the floor carrying a bagged body.
static func morgue_drawers(p: Props, o: Vector3i) -> void:
	p.begin(o, 30, 12, P.NORTH)
	_b(p, 0, 0, 7, 30, 22, 12, M.STEEL) # Case.
	_b(p, 0, 0, 7, 30, 1, 12, M.RUBBER) # Plinth.
	for c in 5:
		for r in 3:
			var x := c * 6
			var y := 1 + r * 7
			if c == 2 and r == 1:
				_b(p, x + 1, y + 1, 7, x + 5, y + 6, 8, M.RUBBER) # Empty slot.
				_b(p, x + 1, y + 2, 0, x + 5, y + 3, 7, M.STEEL) # Drawer tray, pulled out.
				_b(p, x + 1, y + 3, 1, x + 5, y + 4, 6, M.RUBBER) # Bagged body.
				_b(p, x + 2, y + 4, 2, x + 4, y + 5, 3, M.RUBBER)
				_b(p, x + 2, y + 4, 3, x + 3, y + 5, 4, M.WARNING)
				_b(p, x + 1, y + 1, 0, x + 5, y + 2, 1, M.STEEL) # Drawer front.
			else:
				_b(p, x + 1, y + 1, 6, x + 5, y + 6, 7, M.METAL) # Door proud of the case.
				_b(p, x + 2, y + 4, 5, x + 4, y + 5, 6, M.STEEL) # Handle.
				_b(p, x + 2, y + 2, 5, x + 4, y + 3, 6, M.PLASTIC) # Label.


## Red biohazard bin with a lid and a hazard band.
static func biohazard_bin(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 6, P.NORTH)
	_b(p, 0, 0, 0, 6, 8, 6, M.BLOCK_WALL)
	_b(p, 0, 8, 0, 6, 9, 6, M.RUBBER) # Lid.
	_b(p, 1, 9, 2, 5, 10, 4, M.RUBBER)
	_b(p, 0, 3, 0, 6, 5, 1, M.WARNING)
	_b(p, 2, 3, 0, 4, 5, 1, M.RUBBER)


## Incinerator: a brick-and-steel furnace with a glowing firebox, a char door and a stack.
static func incinerator(p: Props, o: Vector3i) -> void:
	p.begin(o, 16, 10, P.NORTH)
	_b(p, 0, 0, 0, 16, 14, 10, M.BLOCK_WALL)
	_b(p, 0, 0, 0, 16, 2, 10, M.CONCRETE)
	_b(p, 0, 13, 0, 16, 14, 10, M.STEEL)
	_b(p, 3, 3, 0, 13, 10, 1, M.STEEL) # Door.
	_b(p, 4, 4, 0, 12, 9, 1, M.CHAR)
	_b(p, 5, 5, 0, 11, 8, 1, M.EMBER)
	_b(p, 7, 5, 0, 9, 6, 1, M.EMBER_DEEP)
	_b(p, 12, 6, 0, 13, 7, 1, M.WARNING) # Latch.
	_b(p, 2, 14, 2, 8, 24, 8, M.METAL) # Stack.
	_b(p, 2, 24, 2, 8, 25, 8, M.RUBBER)
	_b(p, 3, 24, 3, 7, 25, 7, M.CHAR)
	_b(p, 11, 0, 0, 15, 1, 3, M.CHAR) # Ash spill.


## Dumpster: a green steel skip with an open lid, a rim and casters.
static func dumpster(p: Props, o: Vector3i) -> void:
	p.begin(o, 22, 9, P.NORTH)
	_b(p, 0, 1, 0, 22, 11, 9, M.WALL_LOWER)
	_b(p, 0, 11, 0, 22, 12, 9, M.STEEL) # Rim.
	_b(p, 1, 11, 1, 21, 12, 8, M.AIR)
	_b(p, 1, 10, 1, 21, 11, 8, M.CHAR) # Rubbish inside.
	_b(p, 4, 11, 2, 7, 12, 5, M.PLASTIC)
	_b(p, 12, 11, 3, 15, 13, 6, M.CLOTH)
	_b(p, 11, 12, 8, 22, 15, 9, M.RUBBER) # Lid propped open against the back.
	for x in [1, 19]:
		for z in [1, 6]:
			_b(p, x, 0, z, x + 2, 1, z + 2, M.RUBBER)
	_b(p, 0, 5, 0, 22, 6, 1, M.STEEL)
	_b(p, 5, 3, 0, 9, 5, 1, M.WARNING)


## Wall-mounted trash chute: a hinged steel hatch in a hazard-striped frame.
static func trash_chute(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 3, P.NORTH)
	_b(p, 0, 0, 1, 8, 10, 3, M.STEEL)
	_b(p, 0, 0, 0, 8, 1, 1, M.HAZARD_STRIPES)
	_b(p, 0, 9, 0, 8, 10, 1, M.HAZARD_STRIPES)
	_b(p, 0, 1, 0, 1, 9, 1, M.HAZARD_STRIPES)
	_b(p, 7, 1, 0, 8, 9, 1, M.HAZARD_STRIPES)
	_b(p, 1, 1, 0, 7, 9, 1, M.METAL) # Hatch flap.
	_b(p, 2, 3, 0, 6, 7, 1, M.RUBBER)
	_b(p, 2, 3, 0, 6, 4, 1, M.STEEL)
	_b(p, 3, 7, 0, 5, 8, 1, M.STEEL) # Handle.
	_b(p, 3, 2, 0, 5, 3, 1, M.WARNING)
