extends RefCounted
## Cafeteria and kitchen props (docs/prop-build-plan.md D3). All stand on the floor; the serving
## counter faces north (customers at z = 0, the glass sneeze guard along the front of the top).

const P := preload("res://scripts/world/props.gd")
const M := preload("res://scripts/voxel/voxel_materials.gd")

const CATEGORY := "Kitchen"
const MOUNTS := {
	"counter_serving": "floor", "tray_stack": "floor", "cafeteria_table": "floor", "stove": "floor",
	"prep_table": "floor", "dish_rack": "floor", "dishwasher": "floor", "bin_row": "floor",
}
const VALUES := {
	"counter_serving": 900, "tray_stack": 25, "cafeteria_table": 350, "stove": 1100,
	"prep_table": 450, "dish_rack": 40, "dishwasher": 1300, "bin_row": 120,
}
const USES := {}


static func entries(add: Callable) -> void:
	add.call("counter_serving", func(p: Props, o: Vector3i) -> void: serving_counter(p, o))
	add.call("tray_stack", func(p: Props, o: Vector3i) -> void: tray_stack(p, o))
	add.call("cafeteria_table_long", func(p: Props, o: Vector3i) -> void: cafeteria_table(p, o))
	add.call("stove", func(p: Props, o: Vector3i) -> void: stove(p, o))
	add.call("prep_table_steel", func(p: Props, o: Vector3i) -> void: prep_table(p, o))
	add.call("dish_rack", func(p: Props, o: Vector3i) -> void: dish_rack(p, o))
	add.call("dishwasher", func(p: Props, o: Vector3i) -> void: dishwasher(p, o))
	add.call("bin_row", func(p: Props, o: Vector3i) -> void: bin_row(p, o))


static func b(p: Props, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, m: int) -> void:
	p.box(Vector3i(x0, y0, z0), Vector3i(x1, y1, z1), m)


## 20 x 8 x 15: steel counter, a tray rail along the front, a glass sneeze guard over the top.
static func serving_counter(p: Props, o: Vector3i) -> void:
	p.begin(o, 20, 8, P.NORTH)
	b(p, 0, 0, 2, 20, 8, 8, M.STEEL)
	b(p, 0, 0, 0, 20, 1, 8, M.RUBBER)                  # Kick plate.
	b(p, 0, 6, 0, 20, 7, 2, M.STEEL)                   # Tray rail.
	for x in [0, 19]:
		b(p, x, 0, 0, x + 1, 7, 2, M.STEEL)
	b(p, 0, 8, 2, 20, 9, 8, M.PLASTIC)                 # Counter top.
	for x in range(3, 18, 5):
		b(p, x, 2, 2, x + 3, 5, 3, M.METAL)            # Cabinet doors seen on the front.
	for x in [1, 18]:
		b(p, x, 9, 2, x + 1, 15, 3, M.STEEL)           # Guard posts.
	b(p, 1, 14, 2, 19, 15, 3, M.STEEL)                 # Top rail.
	b(p, 2, 10, 2, 18, 14, 3, M.GLASS)                 # Sneeze guard.
	for x in [5, 10, 15]:
		b(p, x, 9, 4, x + 3, 10, 7, M.METAL)           # Hot pans.


static func tray_stack(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 4, P.NORTH)
	for y in 8:
		b(p, 0, y, 0, 6, y + 1, 4, M.PLASTIC if y % 2 == 0 else M.RUBBER)


## 30 x 12 x 7: a 6-wide table with a bench stool at each side, joined by steel arms.
static func cafeteria_table(p: Props, o: Vector3i) -> void:
	p.begin(o, 30, 12, P.NORTH)
	b(p, 0, 6, 3, 30, 7, 9, M.PLASTIC)
	for x in [2, 27]:
		b(p, x, 0, 3, x + 1, 6, 9, M.STEEL)            # End frames.
		b(p, x, 3, 0, x + 1, 4, 12, M.STEEL)           # Arms out to the stools.
	for z in [0, 9]:
		for x in range(4, 26, 8):
			b(p, x + 1, 0, z + 1, x + 2, 4, z + 2, M.STEEL)
			b(p, x, 4, z, x + 4, 5, z + 3, M.RUBBER)   # Seat.


static func stove(p: Props, o: Vector3i) -> void:
	p.begin(o, 10, 8, P.NORTH)
	b(p, 0, 0, 0, 10, 8, 8, M.STEEL)
	b(p, 0, 0, 0, 10, 1, 1, M.RUBBER)
	b(p, 1, 2, 0, 9, 6, 1, M.RUBBER)                   # Oven door frame.
	b(p, 2, 3, 0, 8, 5, 1, M.GLASS)                    # Oven window.
	b(p, 2, 6, 0, 8, 7, 1, M.PLASTIC)                  # Handle.
	for x in [1, 3, 5, 7]:
		b(p, x, 7, 0, x + 1, 8, 1, M.EMERGENCY)        # Knobs.
	b(p, 0, 8, 0, 10, 9, 8, M.RUBBER)                  # Hob.
	for x in [1, 6]:
		for z in [1, 5]:
			b(p, x, 9, z, x + 3, 10, z + 2, M.STEEL)   # Burner plates.
	b(p, 0, 9, 7, 10, 13, 8, M.STEEL)                  # Backsplash.


static func prep_table(p: Props, o: Vector3i) -> void:
	p.begin(o, 16, 8, P.NORTH)
	b(p, 0, 7, 0, 16, 8, 8, M.STEEL)
	b(p, 0, 2, 0, 16, 3, 8, M.METAL)                   # Lower shelf.
	for x in [0, 15]:
		for z in [0, 7]:
			b(p, x, 0, z, x + 1, 7, z + 1, M.STEEL)
	b(p, 0, 8, 7, 16, 10, 8, M.STEEL)                  # Back lip.
	b(p, 3, 8, 2, 9, 9, 6, M.WOOD)                     # Chopping board.
	b(p, 11, 8, 3, 13, 10, 5, M.PLASTIC)               # Bowl.


static func dish_rack(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 6, P.NORTH)
	b(p, 0, 0, 0, 8, 1, 6, M.RUBBER)
	for x in range(1, 8, 2):
		b(p, x, 1, 1, x + 1, 5, 2, M.PLASTIC)          # Plates on edge.
		b(p, x, 1, 3, x + 1, 4, 4, M.STEEL)
	for x in [0, 7]:
		b(p, x, 1, 0, x + 1, 3, 6, M.RUBBER)


static func dishwasher(p: Props, o: Vector3i) -> void:
	p.begin(o, 10, 8, P.NORTH)
	b(p, 0, 0, 0, 10, 12, 8, M.STEEL)
	b(p, 0, 0, 0, 10, 1, 1, M.RUBBER)
	b(p, 1, 9, 0, 9, 11, 1, M.RUBBER)                  # Control strip.
	b(p, 2, 10, 0, 4, 11, 1, M.SCREEN)
	b(p, 6, 10, 0, 7, 11, 1, M.EMERGENCY)
	b(p, 1, 8, 0, 9, 9, 1, M.PLASTIC)                  # Handle.
	b(p, 1, 2, 0, 9, 8, 1, M.METAL)                    # Door.


## Three wheelie bins in a row, lids closed, each a different stream.
static func bin_row(p: Props, o: Vector3i) -> void:
	p.begin(o, 18, 6, P.NORTH)
	var colours := [M.LIQUID_GREEN, M.LIQUID_BLUE, M.RUBBER]
	for i in 3:
		var x := i * 6
		b(p, x, 1, 0, x + 6, 9, 6, colours[i])
		b(p, x, 9, 0, x + 6, 10, 6, M.PLASTIC)         # Lid.
		b(p, x + 1, 10, 0, x + 5, 11, 1, M.PLASTIC)    # Lid lip.
		b(p, x + 1, 0, 1, x + 2, 1, 2, M.RUBBER)       # Wheels.
		b(p, x + 4, 0, 1, x + 5, 1, 2, M.RUBBER)
		b(p, x + 1, 5, 0, x + 5, 6, 1, M.PLASTIC)      # Label strip.
