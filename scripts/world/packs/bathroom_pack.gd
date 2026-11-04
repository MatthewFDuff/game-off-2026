extends RefCounted
## Bathroom props (docs/prop-build-plan.md D3). Wall props are drawn like wall_board and
## vent_grate: footprint w x d, the back (against the wall) at the highest z, the front at z = 0,
## y = 0 the lowest edge (the editor sets the mounting height).

const P := preload("res://scripts/world/props.gd")
const M := preload("res://scripts/voxel/voxel_materials.gd")

const CATEGORY := "Bathroom"
const MOUNTS := {
	"toilet_stall": "floor", "toilet": "floor", "urinal": "wall", "sink_mirror": "wall",
	"shower_cubicle": "floor", "hand_dryer": "wall", "paper_towel": "wall",
	"changing_bench": "floor", "suit_locker": "floor",
}
const VALUES := {
	"toilet_stall": 500, "toilet": 300, "urinal": 280, "sink_mirror": 400, "shower_cubicle": 800,
	"hand_dryer": 220, "paper_towel": 60, "changing_bench": 150, "suit_locker": 260,
}
const USES := {"suit_locker": "container"}


static func entries(add: Callable) -> void:
	add.call("toilet_stall", func(p: Props, o: Vector3i) -> void: toilet_stall(p, o))
	add.call("toilet", func(p: Props, o: Vector3i) -> void: toilet(p, o))
	add.call("urinal", func(p: Props, o: Vector3i) -> void: urinal(p, o))
	add.call("sink_mirror", func(p: Props, o: Vector3i) -> void: sink_mirror(p, o))
	add.call("shower_cubicle", func(p: Props, o: Vector3i) -> void: shower_cubicle(p, o))
	add.call("hand_dryer", func(p: Props, o: Vector3i) -> void: hand_dryer(p, o))
	add.call("paper_towel_dispenser", func(p: Props, o: Vector3i) -> void: paper_towel(p, o))
	add.call("changing_bench", func(p: Props, o: Vector3i) -> void: changing_bench(p, o))
	add.call("suit_locker", func(p: Props, o: Vector3i) -> void: suit_locker(p, o))


static func b(p: Props, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, m: int) -> void:
	p.box(Vector3i(x0, y0, z0), Vector3i(x1, y1, z1), m)


## 20 tall partition panels with a 3-voxel gap under them, open at the front with the door swung
## inward against the left panel. The back is the wall side (z = 9).
static func toilet_stall(p: Props, o: Vector3i) -> void:
	p.begin(o, 10, 10, P.NORTH)
	b(p, 0, 3, 0, 1, 20, 10, M.PLASTIC)                # Left panel.
	b(p, 9, 3, 0, 10, 20, 10, M.PLASTIC)               # Right panel.
	b(p, 1, 3, 9, 9, 20, 10, M.PLASTIC)                # Back panel.
	b(p, 1, 3, 0, 3, 20, 1, M.PLASTIC)                 # Front return.
	b(p, 1, 3, 1, 2, 19, 7, M.WOOD)                    # Door, swung open.
	b(p, 1, 10, 6, 2, 11, 7, M.STEEL)                  # Latch.
	for z in [0, 9]:
		for x in [0, 9]:
			b(p, x, 0, z, x + 1, 3, z + 1, M.STEEL)    # Feet.
	b(p, 4, 0, 6, 7, 1, 9, M.PLASTIC)                  # Toilet base.
	b(p, 4, 1, 6, 7, 5, 9, M.PLASTIC)
	b(p, 5, 4, 6, 6, 5, 8, M.WATER)
	b(p, 4, 5, 8, 7, 8, 9, M.PLASTIC)                  # Cistern.


static func toilet(p: Props, o: Vector3i) -> void:
	p.begin(o, 5, 7, P.NORTH)
	b(p, 1, 0, 3, 4, 3, 6, M.PLASTIC)                  # Pedestal.
	b(p, 0, 3, 1, 5, 5, 6, M.PLASTIC)                  # Bowl.
	b(p, 1, 4, 2, 4, 5, 5, M.WATER)
	b(p, 0, 5, 1, 5, 6, 6, M.WOOD)                     # Seat.
	b(p, 1, 5, 2, 4, 6, 5, M.AIR)
	b(p, 0, 3, 6, 5, 9, 7, M.PLASTIC)                  # Cistern.
	b(p, 2, 9, 6, 3, 10, 7, M.STEEL)                   # Flush button.


## Wall urinal: 4 wide, back at z = 2.
static func urinal(p: Props, o: Vector3i) -> void:
	p.begin(o, 4, 3, P.NORTH)
	b(p, 0, 0, 1, 4, 8, 3, M.PLASTIC)
	b(p, 1, 1, 0, 3, 5, 1, M.PLASTIC)                  # Lip.
	b(p, 1, 2, 1, 3, 5, 2, M.AIR)                      # Basin.
	b(p, 1, 1, 1, 3, 2, 2, M.STEEL)                    # Drain.
	b(p, 1, 6, 1, 3, 7, 2, M.STEEL)                    # Flush pipe.


## Wall sink: 10 wide, 16 tall, back at z = 3; basin at the bottom, tempered mirror above.
static func sink_mirror(p: Props, o: Vector3i) -> void:
	p.begin(o, 10, 4, P.NORTH)
	b(p, 0, 0, 0, 10, 3, 3, M.PLASTIC)                 # Basin shell.
	b(p, 1, 2, 1, 9, 3, 3, M.AIR)
	b(p, 1, 1, 1, 9, 2, 3, M.STEEL)
	b(p, 0, 3, 3, 10, 5, 4, M.PLASTIC)                 # Splashback.
	b(p, 4, 3, 2, 5, 5, 3, M.STEEL)                    # Tap.
	b(p, 4, 5, 1, 5, 6, 3, M.STEEL)
	b(p, 0, 6, 3, 10, 16, 4, M.STEEL)                  # Mirror backing and frame.
	b(p, 1, 7, 2, 9, 15, 3, M.GLASS_TEMPERED)          # Mirror.


## 12 x 12 x 22: tiled tray and two tiled walls, a glass screen on the left and a glass door.
static func shower_cubicle(p: Props, o: Vector3i) -> void:
	p.begin(o, 12, 12, P.NORTH)
	b(p, 0, 0, 0, 12, 1, 12, M.LARGE_TILE)             # Tray.
	b(p, 5, 1, 5, 7, 2, 7, M.STEEL)                    # Drain cover.
	b(p, 0, 1, 11, 12, 22, 12, M.LARGE_TILE)           # Back wall.
	b(p, 11, 1, 0, 12, 22, 11, M.LARGE_TILE)           # Right wall.
	b(p, 0, 1, 0, 1, 22, 1, M.STEEL)                   # Frame post.
	b(p, 0, 21, 0, 12, 22, 1, M.STEEL)                 # Head rail.
	b(p, 0, 3, 1, 1, 21, 11, M.GLASS)                  # Left glass screen.
	b(p, 1, 3, 0, 8, 21, 1, M.GLASS)                   # Front glass door.
	b(p, 7, 10, 0, 8, 12, 1, M.STEEL)                  # Door handle.
	b(p, 6, 14, 10, 7, 20, 11, M.STEEL)                # Riser pipe.
	b(p, 5, 19, 7, 8, 20, 10, M.STEEL)                 # Arm.
	b(p, 5, 18, 7, 8, 19, 9, M.PLASTIC)                # Shower head.
	b(p, 9, 12, 10, 10, 13, 11, M.EMERGENCY)           # Tap.


static func hand_dryer(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 4, P.NORTH)
	b(p, 0, 1, 1, 6, 6, 4, M.STEEL)
	b(p, 1, 0, 1, 5, 1, 3, M.STEEL)                    # Nozzle.
	b(p, 2, 4, 0, 4, 5, 1, M.PLASTIC)                  # Sensor.
	b(p, 3, 5, 0, 4, 6, 1, M.EMERGENCY)
	b(p, 0, 1, 0, 6, 2, 1, M.RUBBER)


static func paper_towel(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 3, P.NORTH)
	b(p, 0, 0, 0, 6, 9, 3, M.PLASTIC)
	b(p, 1, 0, 0, 5, 1, 1, M.AIR)
	b(p, 1, 1, 0, 5, 2, 1, M.RUBBER)                   # Dispensing slot.
	b(p, 2, 2, 0, 4, 3, 1, M.PLASTIC)
	b(p, 2, 6, 0, 4, 7, 1, M.GLASS)                    # Level window.
	b(p, 0, 8, 0, 6, 9, 1, M.STEEL)


static func changing_bench(p: Props, o: Vector3i) -> void:
	p.begin(o, 16, 6, P.NORTH)
	b(p, 0, 4, 0, 16, 5, 6, M.WOOD)
	b(p, 0, 1, 0, 16, 2, 6, M.STEEL)                   # Shoe shelf.
	for x in [1, 14]:
		b(p, x, 0, 1, x + 1, 4, 5, M.STEEL)
	b(p, 2, 2, 1, 5, 3, 4, M.RUBBER)                   # A pair of shoes.
	b(p, 11, 5, 1, 14, 6, 5, M.CLOTH)                  # Folded towel.


## Tall dressing locker for the contamination suits, with louvers.
static func suit_locker(p: Props, o: Vector3i) -> void:
	p.begin(o, 7, 6, P.NORTH)
	b(p, 0, 0, 0, 7, 22, 6, M.METAL)
	b(p, 0, 0, 0, 7, 1, 1, M.RUBBER)
	for y in range(15, 21, 2):
		b(p, 1, y, 0, 6, y + 1, 1, M.RUBBER)           # Louvers.
	b(p, 5, 9, 0, 6, 12, 1, M.STEEL)                   # Handle.
	b(p, 1, 3, 0, 6, 4, 1, M.WARNING)                  # Hazard stripe.
