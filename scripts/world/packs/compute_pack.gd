extends RefCounted
## Server room props (docs/prop-build-plan.md D2): racks, cable cage, CRAC unit, raised floor tiles,
## patch panel, UPS, tape library. All floor props except the patch panel (wall: back at the high z
## edge, like a whiteboard). A server rack is 10 x 10 x 20 voxels (1 m square, 2 m tall). The open
## rack's blinking look is scattered SCREEN dots over a dark front; the dead rack has none.
## The switches for these are the interactables package's job, so USES is empty.

const P := preload("res://scripts/world/props.gd")
const M := preload("res://scripts/voxel/voxel_materials.gd")

const CATEGORY := "Compute"
const MOUNTS := {"patch_panel": "wall"}
const VALUES := {
	"server_rack": 2400, "server_rack_dead": 400, "cable_cage": 150, "crac_unit": 1800,
	"floor_tile": 30, "patch_panel": 220, "ups_cabinet": 900, "tape_library": 3000,
}
const USES := {}


static func entries(add: Callable) -> void:
	add.call("server_rack_closed", func(p: Props, o: Vector3i) -> void: rack(p, o, "closed"))
	add.call("server_rack_open", func(p: Props, o: Vector3i) -> void: rack(p, o, "open"))
	add.call("server_rack_dead", func(p: Props, o: Vector3i) -> void: rack(p, o, "dead"))
	add.call("cable_cage", func(p: Props, o: Vector3i) -> void: cable_cage(p, o))
	add.call("crac_unit", func(p: Props, o: Vector3i) -> void: crac_unit(p, o))
	add.call("floor_tile", func(p: Props, o: Vector3i) -> void: floor_tile(p, o, false))
	add.call("floor_tile_lifted", func(p: Props, o: Vector3i) -> void: floor_tile(p, o, true))
	add.call("patch_panel", func(p: Props, o: Vector3i) -> void: patch_panel(p, o))
	add.call("ups_cabinet", func(p: Props, o: Vector3i) -> void: ups_cabinet(p, o))
	add.call("tape_library", func(p: Props, o: Vector3i) -> void: tape_library(p, o))


## A rack: steel frame and plinth, front at z = 0. closed has a vented door and one status LED;
## open shows dark bays under steel rails with scattered SCREEN dots; dead is the same with no light.
static func rack(p: Props, o: Vector3i, kind: String) -> void:
	p.begin(o, 10, 10, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(10, 1, 10), M.STEEL)
	p.box(Vector3i(0, 1, 1), Vector3i(10, 19, 10), M.METAL)
	p.box(Vector3i(0, 19, 0), Vector3i(10, 20, 10), M.STEEL)
	for x in [0, 9]:
		p.box(Vector3i(x, 1, 0), Vector3i(x + 1, 19, 1), M.STEEL)
	if kind == "closed":
		p.box(Vector3i(1, 1, 0), Vector3i(9, 19, 1), M.METAL)
		for y in range(3, 18, 2):
			p.box(Vector3i(2, y, 0), Vector3i(8, y + 1, 1), M.RUBBER) # Vent slots.
		p.box(Vector3i(8, 17, 0), Vector3i(9, 18, 1), M.LIQUID_GREEN)
		p.box(Vector3i(1, 10, 0), Vector3i(2, 12, 1), M.STEEL) # Handle.
		return
	p.box(Vector3i(1, 1, 0), Vector3i(9, 19, 1), M.RUBBER)
	for y in range(2, 18, 3):
		p.box(Vector3i(1, y + 2, 0), Vector3i(9, y + 3, 1), M.STEEL)
	if kind == "open":
		for y in range(2, 18, 3):
			for x in range(2, 9):
				if p.rng.randf() < 0.4:
					var yy := y + p.rng.randi_range(0, 1)
					p.box(Vector3i(x, yy, 0), Vector3i(x + 1, yy + 1, 1), M.SCREEN)
		for pt in [Vector3i(2, 3, 0), Vector3i(5, 6, 0), Vector3i(7, 9, 0), Vector3i(3, 12, 0), Vector3i(6, 15, 0)]:
			p.box(pt, pt + Vector3i(1, 1, 1), M.SCREEN)


## A wire cage (floor-standing cable enclosure): posts, three rails round and a bundle inside.
static func cable_cage(p: Props, o: Vector3i) -> void:
	p.begin(o, 12, 6, P.NORTH)
	for x in [0, 11]:
		for z in [0, 5]:
			p.box(Vector3i(x, 0, z), Vector3i(x + 1, 10, z + 1), M.STEEL)
	for y in [0, 4, 9]:
		p.box(Vector3i(0, y, 0), Vector3i(12, y + 1, 1), M.STEEL)
		p.box(Vector3i(0, y, 5), Vector3i(12, y + 1, 6), M.STEEL)
		p.box(Vector3i(0, y, 0), Vector3i(1, y + 1, 6), M.STEEL)
		p.box(Vector3i(11, y, 0), Vector3i(12, y + 1, 6), M.STEEL)
	p.box(Vector3i(2, 0, 2), Vector3i(10, 3, 4), M.RUBBER)
	p.box(Vector3i(3, 3, 2), Vector3i(9, 4, 4), M.LIQUID_BLUE)
	p.box(Vector3i(5, 4, 2), Vector3i(8, 5, 3), M.WARNING)


## A computer-room air conditioner: a long cabinet with louvres, a display and a vented top.
static func crac_unit(p: Props, o: Vector3i) -> void:
	p.begin(o, 16, 10, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(16, 1, 10), M.STEEL)
	p.box(Vector3i(0, 1, 0), Vector3i(16, 19, 10), M.PLASTIC)
	p.box(Vector3i(0, 19, 0), Vector3i(16, 20, 10), M.STEEL)
	for y in range(3, 12, 2):
		p.box(Vector3i(1, y, 0), Vector3i(11, y + 1, 1), M.RUBBER)
	p.box(Vector3i(12, 11, 0), Vector3i(15, 17, 1), M.RUBBER)
	p.box(Vector3i(13, 14, 0), Vector3i(14, 16, 1), M.SCREEN)
	p.box(Vector3i(13, 12, 0), Vector3i(14, 13, 1), M.LIQUID_GREEN)
	p.box(Vector3i(1, 13, 0), Vector3i(11, 14, 1), M.STEEL)
	p.box(Vector3i(1, 17, 0), Vector3i(11, 18, 1), M.RUBBER)
	for x in range(2, 15, 3):
		p.box(Vector3i(x, 19, 2), Vector3i(x + 1, 20, 8), M.RUBBER)


## A raised floor tile (6 x 6 x 1). The lifted one leans back from the front edge of an open hole:
## a steel frame round the hole, a pedestal and a cable snaking across the bare slab below.
static func floor_tile(p: Props, o: Vector3i, lifted: bool) -> void:
	if not lifted:
		p.begin(o, 6, 6, P.NORTH)
		p.box(Vector3i(0, 0, 0), Vector3i(6, 1, 6), M.STEEL)
		p.box(Vector3i(1, 0, 1), Vector3i(5, 1, 5), M.METAL)
		p.box(Vector3i(2, 0, 2), Vector3i(4, 1, 4), M.RUBBER)
		return
	p.begin(o, 8, 10, P.NORTH)
	for z in 10:
		for x in 8:
			if x == 0 or x == 7 or z == 0 or z == 9:
				p.box(Vector3i(x, 0, z), Vector3i(x + 1, 1, z + 1), M.STEEL)
	p.box(Vector3i(3, 0, 5), Vector3i(5, 2, 7), M.STEEL)
	p.box(Vector3i(1, 0, 1), Vector3i(7, 1, 2), M.RUBBER)
	p.box(Vector3i(6, 0, 1), Vector3i(7, 1, 5), M.RUBBER)
	p.box(Vector3i(2, 0, 4), Vector3i(7, 1, 5), M.RUBBER)
	p.box(Vector3i(2, 0, 4), Vector3i(3, 1, 8), M.LIQUID_BLUE)
	for k in 8:
		var z := 2 + k * 3 / 8
		p.box(Vector3i(1, k + 1, z), Vector3i(7, k + 2, z + 1), M.STEEL)


## A patch panel on the wall (16 x 3 x 8, back plate at the high z edge): two rows of ports with
## patch cables hanging from some.
static func patch_panel(p: Props, o: Vector3i) -> void:
	p.begin(o, 16, 3, P.NORTH)
	p.box(Vector3i(0, 0, 2), Vector3i(16, 8, 3), M.STEEL)
	p.box(Vector3i(0, 0, 1), Vector3i(16, 1, 2), M.STEEL)
	p.box(Vector3i(0, 7, 1), Vector3i(16, 8, 2), M.STEEL)
	for row in [3, 5]:
		p.box(Vector3i(1, row, 1), Vector3i(15, row + 1, 2), M.RUBBER)
	var cols := [M.LIQUID_BLUE, M.WARNING, M.EMERGENCY, M.LIQUID_GREEN]
	for i in 4:
		var x := 2 + i * 3
		p.box(Vector3i(x, 3, 0), Vector3i(x + 1, 4, 2), cols[i])
		p.box(Vector3i(x, 0, 0), Vector3i(x + 1, 3, 1), cols[i])


## An uninterruptible power supply cabinet: a display, a battery bar and a hazard band.
static func ups_cabinet(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 10, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(8, 1, 10), M.RUBBER)
	p.box(Vector3i(0, 1, 0), Vector3i(8, 14, 10), M.METAL)
	p.box(Vector3i(0, 14, 0), Vector3i(8, 15, 10), M.STEEL)
	p.box(Vector3i(1, 9, 0), Vector3i(7, 13, 1), M.RUBBER)
	p.box(Vector3i(2, 11, 0), Vector3i(6, 12, 1), M.SCREEN)
	p.box(Vector3i(2, 10, 0), Vector3i(5, 11, 1), M.LIQUID_GREEN)
	p.box(Vector3i(5, 10, 0), Vector3i(6, 11, 1), M.WARNING)
	p.box(Vector3i(0, 6, 0), Vector3i(8, 7, 1), M.WARNING)
	p.box(Vector3i(2, 2, 0), Vector3i(6, 5, 1), M.RUBBER)


## A tape library: steel cabinet, a glass window onto rows of cartridges, a picker arm and a display.
static func tape_library(p: Props, o: Vector3i) -> void:
	p.begin(o, 12, 8, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(12, 1, 8), M.STEEL)
	p.box(Vector3i(0, 1, 0), Vector3i(12, 18, 8), M.METAL)
	p.box(Vector3i(0, 17, 0), Vector3i(12, 18, 8), M.STEEL)
	p.box(Vector3i(1, 6, 0), Vector3i(11, 15, 1), M.GLASS)
	p.box(Vector3i(1, 6, 1), Vector3i(11, 15, 5), M.RUBBER)
	var rows := [M.PLASTIC, M.CLOTH, M.LIQUID_BLUE, M.PLASTIC]
	for i in 4:
		var y := 7 + i * 2
		p.box(Vector3i(2, y, 1), Vector3i(5, y + 1, 4), rows[i])
		p.box(Vector3i(6, y, 1), Vector3i(10, y + 1, 4), rows[i])
	p.box(Vector3i(5, 7, 1), Vector3i(6, 14, 4), M.STEEL)
	p.box(Vector3i(8, 2, 0), Vector3i(11, 5, 1), M.RUBBER)
	p.box(Vector3i(9, 3, 0), Vector3i(10, 4, 1), M.SCREEN)
	p.box(Vector3i(1, 2, 0), Vector3i(6, 4, 1), M.RUBBER)
