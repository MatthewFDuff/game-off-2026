extends RefCounted
## Executive suite props (docs/prop-build-plan.md D3). All stand on the floor.

const P := preload("res://scripts/world/props.gd")
const M := preload("res://scripts/voxel/voxel_materials.gd")

const CATEGORY := "Executive"
const MOUNTS := {
	"boardroom_table": "floor", "executive_chair": "floor", "trophy_shelf": "floor", "safe": "floor",
	"plush_couch": "floor", "drinks_cabinet": "floor", "globe": "floor", "potted_tree": "floor",
}
const VALUES := {
	"boardroom_table": 4500, "executive_chair": 700, "trophy_shelf": 1800, "safe": 3000,
	"plush_couch": 1600, "drinks_cabinet": 1500, "globe": 400, "potted_tree": 250,
}
const USES := {"safe": "container", "drinks_cabinet": "container"}


static func entries(add: Callable) -> void:
	add.call("boardroom_table", func(p: Props, o: Vector3i) -> void: boardroom_table(p, o))
	add.call("executive_chair", func(p: Props, o: Vector3i) -> void: executive_chair(p, o))
	add.call("trophy_shelf", func(p: Props, o: Vector3i) -> void: trophy_shelf(p, o))
	add.call("safe", func(p: Props, o: Vector3i) -> void: safe(p, o))
	add.call("plush_couch", func(p: Props, o: Vector3i) -> void: plush_couch(p, o))
	add.call("drinks_cabinet", func(p: Props, o: Vector3i) -> void: drinks_cabinet(p, o))
	add.call("globe", func(p: Props, o: Vector3i) -> void: globe(p, o))
	add.call("potted_tree", func(p: Props, o: Vector3i) -> void: potted_tree(p, o))


static func b(p: Props, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, m: int) -> void:
	p.box(Vector3i(x0, y0, z0), Vector3i(x1, y1, z1), m)


## 40 x 16 x 8: a long polished top on two slab pedestals, a steel inlay down the middle.
static func boardroom_table(p: Props, o: Vector3i) -> void:
	p.begin(o, 40, 16, P.NORTH)
	b(p, 0, 7, 0, 40, 8, 16, M.WOOD)
	b(p, 2, 7, 7, 38, 8, 9, M.PLANK)                   # Inlay strip.
	b(p, 1, 6, 1, 39, 7, 15, M.WOOD)                   # Edge skirt.
	for x in [5, 30]:
		b(p, x, 0, 3, x + 5, 6, 13, M.PLANK)           # Pedestals.
		b(p, x - 1, 0, 2, x + 6, 1, 14, M.RUBBER)
	for x in range(10, 31, 5):
		b(p, x, 8, 7, x + 2, 9, 9, M.STEEL)            # Conference pucks.


static func executive_chair(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 6, P.NORTH)
	b(p, 2, 0, 2, 4, 3, 4, M.STEEL)                    # Pedestal.
	b(p, 0, 0, 2, 6, 1, 4, M.STEEL)                    # Star base, x...
	b(p, 2, 0, 0, 4, 1, 6, M.STEEL)                    # ...and z.
	b(p, 0, 3, 0, 6, 4, 6, M.CLOTH)                    # Seat base.
	b(p, 0, 4, 0, 6, 5, 5, M.CLOTH)                    # Cushion.
	b(p, 0, 5, 5, 6, 14, 6, M.CLOTH)                   # High back.
	b(p, 1, 14, 5, 5, 15, 6, M.CLOTH)
	for x in [0, 5]:
		b(p, x, 5, 1, x + 1, 7, 5, M.STEEL)            # Arms.


static func trophy_shelf(p: Props, o: Vector3i) -> void:
	p.begin(o, 14, 5, P.NORTH)
	b(p, 0, 0, 0, 14, 20, 5, M.WOOD)
	for y in [5, 10, 15]:
		b(p, 1, y, 1, 13, y + 1, 5, M.PLANK)           # Display shelves.
	for y in [1, 6, 11, 16]:
		b(p, 1, y, 1, 13, y + 4, 4, M.AIR)             # Alcoves.
	for y in [1, 6, 11, 16]:
		for x in [2, 6, 10]:
			b(p, x, y, 2, x + 2, y + 1, 4, M.STEEL)    # Trophy plinth.
			b(p, x, y + 1, 2, x + 2, y + 3, 4, M.WARNING)  # Gold cup.
			b(p, x + 1, y + 3, 2, x + 2, y + 4, 3, M.WARNING)
	b(p, 1, 1, 0, 13, 5, 1, M.GLASS)                   # Glass door, lower bay (upper bays open).


## Steel safe. The door faces the front with a dial and a handle.
static func safe(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 7, P.NORTH)
	b(p, 0, 0, 0, 8, 9, 7, M.STEEL)
	b(p, 0, 0, 0, 8, 1, 7, M.RUBBER)
	b(p, 1, 1, 0, 7, 8, 1, M.METAL)                    # Door.
	b(p, 3, 5, 0, 5, 7, 1, M.RUBBER)                   # Dial.
	b(p, 3, 6, 0, 4, 7, 1, M.EMERGENCY)
	b(p, 2, 2, 0, 6, 3, 1, M.STEEL)                    # Handle bar.
	b(p, 6, 3, 0, 7, 6, 1, M.RUBBER)                   # Hinges.


static func plush_couch(p: Props, o: Vector3i) -> void:
	p.begin(o, 22, 10, P.NORTH)
	b(p, 0, 1, 0, 22, 4, 10, M.CLOTH)                  # Base.
	b(p, 2, 4, 0, 20, 6, 7, M.CLOTH)                   # Seat cushions.
	b(p, 0, 4, 8, 22, 11, 10, M.CLOTH)                 # Back.
	b(p, 0, 4, 0, 2, 8, 10, M.CLOTH)                   # Rolled arms.
	b(p, 20, 4, 0, 22, 8, 10, M.CLOTH)
	for x in [8, 14]:
		b(p, x, 4, 0, x + 1, 6, 7, M.RUBBER)           # Cushion seams.
	for x in range(3, 20, 3):
		b(p, x, 8, 7, x + 1, 9, 8, M.WOOD)             # Button tufting.
	for x in [0, 21]:
		for z in [0, 9]:
			b(p, x, 0, z, x + 1, 1, z + 1, M.WOOD)     # Feet.


## 14 x 6 x 18: wood cabinet with a glass front over rows of bottles, a drinks tray on top.
static func drinks_cabinet(p: Props, o: Vector3i) -> void:
	p.begin(o, 14, 6, P.NORTH)
	b(p, 0, 0, 0, 14, 8, 6, M.WOOD)                    # Lower cupboard.
	b(p, 6, 3, 0, 8, 4, 1, M.STEEL)                    # Handle.
	b(p, 0, 8, 0, 14, 18, 6, M.WOOD)                   # Upper carcass.
	b(p, 1, 9, 1, 13, 17, 5, M.AIR)
	b(p, 1, 12, 1, 13, 13, 5, M.PLANK)                 # Shelf.
	var drinks := [M.LIQUID_GREEN, M.LIQUID_BLUE, M.LIQUID_PINK]
	for row in 2:
		var y := 9 + row * 4
		for i in 5:
			var x := 2 + i * 2
			b(p, x, y, 2, x + 1, y + 2, 3, drinks[(i + row) % 3])
			b(p, x, y + 2, 2, x + 1, y + 3, 3, M.GLASS)  # Bottle neck.
	b(p, 1, 9, 0, 13, 17, 1, M.GLASS)                  # Glass front.
	b(p, 0, 17, 0, 14, 18, 6, M.PLANK)                 # Top.


static func globe(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 8, P.NORTH)
	b(p, 1, 0, 1, 7, 1, 7, M.WOOD)                     # Foot.
	b(p, 3, 1, 3, 5, 3, 5, M.WOOD)                     # Stem.
	b(p, 2, 3, 3, 6, 11, 5, M.LIQUID_BLUE)             # Sphere, built as three slabs...
	b(p, 3, 3, 2, 5, 11, 6, M.LIQUID_BLUE)
	b(p, 3, 4, 3, 5, 10, 5, M.LIQUID_BLUE)
	b(p, 1, 5, 3, 7, 9, 5, M.LIQUID_BLUE)
	b(p, 3, 5, 1, 5, 9, 7, M.LIQUID_BLUE)
	b(p, 2, 6, 2, 6, 8, 6, M.LIQUID_BLUE)
	b(p, 3, 7, 1, 5, 9, 2, M.LIQUID_GREEN)             # Continents.
	b(p, 1, 6, 3, 2, 8, 4, M.LIQUID_GREEN)
	b(p, 5, 5, 6, 6, 7, 7, M.LIQUID_GREEN)
	b(p, 0, 4, 3, 1, 10, 4, M.STEEL)                   # Meridian ring.
	b(p, 7, 4, 3, 8, 10, 4, M.STEEL)
	b(p, 1, 10, 3, 7, 11, 4, M.STEEL)


static func potted_tree(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 8, P.NORTH)
	b(p, 1, 0, 1, 7, 5, 7, M.PLASTIC)                  # Pot.
	b(p, 2, 4, 2, 6, 5, 6, M.SUBSTRATE)
	b(p, 3, 5, 3, 5, 14, 5, M.WOOD)                    # Trunk.
	b(p, 1, 12, 1, 7, 18, 7, M.LIQUID_GREEN)           # Canopy.
	b(p, 2, 18, 2, 6, 22, 6, M.LIQUID_GREEN)
	b(p, 0, 14, 2, 1, 16, 6, M.LIQUID_GREEN)
	b(p, 7, 14, 2, 8, 16, 6, M.LIQUID_GREEN)
	b(p, 3, 11, 3, 5, 12, 5, M.LIQUID_GREEN)
