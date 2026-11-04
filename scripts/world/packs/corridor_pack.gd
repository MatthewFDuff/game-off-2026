extends RefCounted
## Corridor and hallway props (docs/prop-build-plan.md D1): handrails, floor markings, signs,
## tape, cleaning gear, the extinguisher cabinet and the evac map.
##
## Wall props are drawn the way PropPlacement puts them: back against the wall at the highest z
## (z = d - 1), front at z = 0, facing north (-z). Wall signs are drawn in viewer coordinates
## (see px): column 0 is the viewer's left, so text and arrows read correctly from the front.
## Handrail pieces are 10 voxels along x, rail 10 voxels up (a person is 18), and line up in any
## facing; the corner returns in to the wall at its east end.
##
## Text is a 3 x 5 block font (GLYPHS): PixelFont is a TTF for HUD labels with no way to write its
## glyphs into voxels, so letters are drawn as blocks.

const P := preload("res://scripts/world/props.gd")
const M := preload("res://scripts/voxel/voxel_materials.gd")

const CATEGORY := "Corridor"
const MOUNTS := {
	"handrail_": "wall", "room_plate_": "wall", "extinguisher_cabinet": "wall", "evac_map": "wall",
	"exit_sign_arrow": "wall",
}
const VALUES := {
	"handrail_": 120, "wet_floor_sign": 25, "caution_tape_post": 30, "caution_tape_run": 15,
	"floor_decal_arrows": 20, "room_plate_": 40, "extinguisher_cabinet": 220, "evac_map": 60,
	"exit_sign_arrow": 130, "bollard": 150, "mop_bucket": 45, "cleaning_cart": 350,
}
const USES := {}

## 3 x 5 glyphs: five rows, top to bottom, "#" is set.
const GLYPHS := {
	"0": ["###", "# #", "# #", "# #", "###"], "1": [" # ", "## ", " # ", " # ", "###"],
	"2": ["###", "  #", "###", "#  ", "###"], "3": ["###", "  #", "###", "  #", "###"],
	"4": ["# #", "# #", "###", "  #", "  #"], "5": ["###", "#  ", "###", "  #", "###"],
	"6": ["###", "#  ", "###", "# #", "###"], "7": ["###", "  #", "  #", " # ", " # "],
	"8": ["###", "# #", "###", "# #", "###"], "9": ["###", "# #", "###", "  #", "###"],
	"B": ["## ", "# #", "## ", "# #", "## "], "E": ["###", "#  ", "## ", "#  ", "###"],
	"X": ["# #", "# #", " # ", "# #", "# #"], "I": ["###", " # ", " # ", " # ", "###"],
	"T": ["###", " # ", " # ", " # ", " # "],
}


static func entries(add: Callable) -> void:
	add.call("handrail_straight", func(p: Props, o: Vector3i) -> void: handrail(p, o, false))
	add.call("handrail_corner", func(p: Props, o: Vector3i) -> void: handrail(p, o, true))
	add.call("wet_floor_sign", func(p: Props, o: Vector3i) -> void: wet_floor_sign(p, o))
	add.call("caution_tape_post", func(p: Props, o: Vector3i) -> void: tape_post(p, o))
	add.call("caution_tape_run", func(p: Props, o: Vector3i) -> void: tape_run(p, o))
	add.call("floor_decal_arrows", func(p: Props, o: Vector3i) -> void: decal_arrows(p, o))
	add.call("room_plate_101", func(p: Props, o: Vector3i) -> void: room_plate(p, o, "101"))
	add.call("room_plate_204", func(p: Props, o: Vector3i) -> void: room_plate(p, o, "204"))
	add.call("room_plate_b12", func(p: Props, o: Vector3i) -> void: room_plate(p, o, "B12"))
	add.call("extinguisher_cabinet", func(p: Props, o: Vector3i) -> void: extinguisher_cabinet(p, o))
	add.call("evac_map", func(p: Props, o: Vector3i) -> void: evac_map(p, o))
	add.call("exit_sign_arrow", func(p: Props, o: Vector3i) -> void: exit_arrow(p, o))
	add.call("bollard", func(p: Props, o: Vector3i) -> void: bollard(p, o))
	add.call("mop_bucket", func(p: Props, o: Vector3i) -> void: mop_bucket(p, o))
	add.call("cleaning_cart", func(p: Props, o: Vector3i) -> void: cleaning_cart(p, o))


# --- Drawing helpers --------------------------------------------------------------------------

## One voxel at the viewer's column vx (0 = left as seen from the front), row y, depth z, in a
## prop w wide.
static func px(p: Props, w: int, vx: int, y: int, z: int, material: int) -> void:
	p.box(Vector3i(w - 1 - vx, y, z), Vector3i(w - vx, y + 1, z + 1), material)


## Block text with its lower-left at viewer column vx, row y, on depth z. Returns the width drawn.
static func text(p: Props, w: int, vx: int, y: int, z: int, s: String, material: int) -> int:
	for i in s.length():
		var rows: Array = GLYPHS.get(s[i], [])
		for r in rows.size():
			for c in 3:
				if rows[r][c] == "#":
					px(p, w, vx + i * 4 + c, y + 4 - r, z, material)
	return s.length() * 4 - 1


# --- Handrails ---------------------------------------------------------------------------------

## A 10 x 8 wall rail: the rail one voxel out at z = 4 and y 8-9 (its top is 1 m up), on arms from
## wall plates. The corner returns to the wall at its east end.
static func handrail(p: Props, o: Vector3i, corner: bool) -> void:
	p.begin(o, 10, 8, P.NORTH)
	p.box(Vector3i(0, 8, 4), Vector3i(10, 10, 5), M.METAL)
	var posts := [1, 5] if corner else [1, 8]
	if corner:
		p.box(Vector3i(8, 8, 5), Vector3i(10, 10, 8), M.METAL)
	for x in posts:
		p.box(Vector3i(x, 5, 7), Vector3i(x + 1, 10, 8), M.STEEL) # Wall plate.
		p.box(Vector3i(x, 7, 4), Vector3i(x + 1, 8, 8), M.STEEL) # Arm.


# --- Floor markings and warning gear -------------------------------------------------------------

## An A-frame sign 11 tall: yellow panels leaning together, with a black bar and a dot on the front.
static func wet_floor_sign(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 6, P.NORTH)
	for y in 10:
		var step := y / 4
		p.box(Vector3i(1, y, step), Vector3i(7, y + 1, step + 1), M.WARNING)
		p.box(Vector3i(1, y, 5 - step), Vector3i(7, y + 1, 6 - step), M.WARNING)
	p.box(Vector3i(1, 10, 2), Vector3i(7, 11, 4), M.WARNING) # Hinged top.
	p.box(Vector3i(2, 5, 1), Vector3i(6, 6, 2), M.RUBBER)
	p.box(Vector3i(3, 7, 1), Vector3i(5, 9, 2), M.RUBBER)
	p.box(Vector3i(3, 3, 1), Vector3i(5, 4, 2), M.RUBBER)


## A stanchion 4 x 4: a flat base, a 2 x 2 post to 1.1 m, a cap, and a stub of tape across it.
## Tape sits at z = 2 and y 8-9 across the whole width, so tape runs join it end to end.
static func tape_post(p: Props, o: Vector3i) -> void:
	p.begin(o, 4, 4, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(4, 1, 4), M.RUBBER)
	p.box(Vector3i(1, 1, 1), Vector3i(3, 11, 3), M.STEEL)
	p.box(Vector3i(1, 11, 1), Vector3i(3, 12, 3), M.WARNING)
	p.box(Vector3i(0, 8, 2), Vector3i(4, 10, 3), M.WARNING)
	p.box(Vector3i(1, 8, 2), Vector3i(2, 10, 3), M.RUBBER)


## A 10-voxel length of tape at the post's height, sagging a voxel in the middle, with black bars.
static func tape_run(p: Props, o: Vector3i) -> void:
	p.begin(o, 10, 4, P.NORTH)
	for x in 10:
		var sag := 1 if x >= 3 and x <= 6 else 0
		p.box(Vector3i(x, 8 - sag, 2), Vector3i(x + 1, 10 - sag, 3), M.RUBBER if x % 4 == 1 else M.WARNING)


## A one-voxel decal, 9 x 15: three yellow chevrons pointing north on a black plate.
static func decal_arrows(p: Props, o: Vector3i) -> void:
	p.begin(o, 9, 15, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(9, 1, 15), M.RUBBER)
	for k in 3:
		for r in 5:
			var z := k * 5 + r
			p.box(Vector3i(4 - r, 0, z), Vector3i(6 - r, 1, z + 1), M.WARNING)
			p.box(Vector3i(3 + r, 0, z), Vector3i(5 + r, 1, z + 1), M.WARNING)


## A 4 x 4 concrete post 0.9 m tall with a yellow band.
static func bollard(p: Props, o: Vector3i) -> void:
	p.begin(o, 4, 4, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(4, 1, 4), M.STEEL)
	p.box(Vector3i(0, 1, 0), Vector3i(4, 9, 4), M.CONCRETE)
	p.box(Vector3i(0, 5, 0), Vector3i(4, 7, 4), M.WARNING)
	p.box(Vector3i(1, 9, 1), Vector3i(3, 10, 3), M.CONCRETE)


# --- Wall signs --------------------------------------------------------------------------------

## A 13 x 9 door plate: a steel back and a white face with the room number in black.
static func room_plate(p: Props, o: Vector3i, label: String) -> void:
	p.begin(o, 13, 2, P.NORTH)
	p.box(Vector3i(0, 0, 1), Vector3i(13, 9, 2), M.STEEL)
	p.box(Vector3i(1, 1, 0), Vector3i(12, 8, 1), M.PLASTIC)
	var width := label.length() * 4 - 1
	text(p, 13, (13 - width) / 2, 2, 0, label, M.RUBBER)


## An 8 x 14 wall box: a steel shell, a glass front and a red extinguisher behind it.
static func extinguisher_cabinet(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 4, P.NORTH)
	p.box(Vector3i(0, 0, 3), Vector3i(8, 14, 4), M.STEEL) # Back.
	p.box(Vector3i(0, 0, 0), Vector3i(8, 14, 3), M.STEEL)
	p.box(Vector3i(1, 1, 0), Vector3i(7, 13, 3), M.AIR)
	p.box(Vector3i(1, 1, 0), Vector3i(7, 13, 1), M.GLASS)
	p.box(Vector3i(2, 2, 1), Vector3i(6, 9, 3), M.RED_PAINT) # Cylinder.
	p.box(Vector3i(3, 9, 1), Vector3i(5, 11, 3), M.METAL) # Valve.
	p.box(Vector3i(5, 10, 1), Vector3i(6, 11, 2), M.RUBBER) # Hose.
	p.box(Vector3i(2, 5, 1), Vector3i(6, 6, 2), M.PLASTIC) # Label.


## A 16 x 11 framed floor plan: white paper, black walls, a red you-are-here dot, a green exit.
static func evac_map(p: Props, o: Vector3i) -> void:
	p.begin(o, 16, 2, P.NORTH)
	p.box(Vector3i(0, 0, 1), Vector3i(16, 11, 2), M.STEEL)
	p.box(Vector3i(0, 0, 0), Vector3i(16, 11, 1), M.STEEL)
	p.box(Vector3i(1, 1, 0), Vector3i(15, 10, 1), M.PLASTIC)
	p.box(Vector3i(2, 2, 0), Vector3i(14, 3, 1), M.RUBBER)
	p.box(Vector3i(2, 8, 0), Vector3i(14, 9, 1), M.RUBBER)
	p.box(Vector3i(2, 2, 0), Vector3i(3, 9, 1), M.RUBBER)
	p.box(Vector3i(13, 2, 0), Vector3i(14, 9, 1), M.RUBBER)
	p.box(Vector3i(7, 3, 0), Vector3i(8, 6, 1), M.RUBBER)
	p.box(Vector3i(4, 5, 0), Vector3i(7, 6, 1), M.RUBBER)
	p.box(Vector3i(9, 6, 0), Vector3i(13, 7, 1), M.RUBBER)
	p.box(Vector3i(5, 3, 0), Vector3i(6, 4, 1), M.EMERGENCY)
	p.box(Vector3i(11, 4, 0), Vector3i(12, 5, 1), M.LIQUID_GREEN)


## A 28 x 9 sign: a black face with a red arrow pointing left and EXIT.
static func exit_arrow(p: Props, o: Vector3i) -> void:
	p.begin(o, 28, 2, P.NORTH)
	p.box(Vector3i(0, 0, 1), Vector3i(28, 9, 2), M.STEEL)
	p.box(Vector3i(1, 1, 0), Vector3i(27, 8, 1), M.RUBBER)
	for vx in range(3, 9):
		px(p, 28, vx, 4, 0, M.EMERGENCY)
	for y in range(3, 6):
		px(p, 28, 4, y, 0, M.EMERGENCY)
	for y in range(2, 7):
		px(p, 28, 5, y, 0, M.EMERGENCY)
	text(p, 28, 11, 2, 0, "EXIT", M.EMERGENCY)


# --- Cleaning gear ----------------------------------------------------------------------------

## A 6 x 6 bucket of water with a mop standing in it, the handle leaning back.
static func mop_bucket(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 8, P.NORTH)
	p.box(Vector3i(1, 0, 2), Vector3i(7, 6, 8), M.PLASTIC)
	p.box(Vector3i(2, 1, 3), Vector3i(6, 6, 7), M.AIR)
	p.box(Vector3i(2, 1, 3), Vector3i(6, 4, 7), M.LIQUID_BLUE)
	p.box(Vector3i(3, 1, 4), Vector3i(5, 6, 6), M.CLOTH) # Mop head.
	p.box(Vector3i(4, 6, 5), Vector3i(5, 11, 6), M.WOOD)
	p.box(Vector3i(4, 10, 4), Vector3i(5, 15, 5), M.WOOD)
	p.box(Vector3i(4, 14, 3), Vector3i(5, 19, 4), M.WOOD)
	p.box(Vector3i(7, 4, 4), Vector3i(8, 5, 6), M.STEEL) # Bucket handle.


## A 20 x 10 janitor cart: wheels, a base tray, a shelf with bottles, a bin bag and a push bar.
static func cleaning_cart(p: Props, o: Vector3i) -> void:
	p.begin(o, 20, 10, P.NORTH)
	for x in [0, 18]:
		for z in [0, 8]:
			p.box(Vector3i(x, 0, z), Vector3i(x + 2, 1, z + 2), M.RUBBER)
	p.box(Vector3i(0, 1, 0), Vector3i(20, 3, 10), M.PLASTIC)
	for x in [0, 9]:
		for z in [0, 9]:
			p.box(Vector3i(x, 3, z), Vector3i(x + 1, 12, z + 1), M.STEEL)
	p.box(Vector3i(0, 6, 0), Vector3i(10, 7, 10), M.PLASTIC) # Shelf.
	p.box(Vector3i(0, 11, 0), Vector3i(10, 12, 10), M.PLASTIC)
	var liquids := [M.LIQUID_BLUE, M.LIQUID_GREEN, M.LIQUID_PINK]
	for i in 3:
		p.box(Vector3i(1 + i * 3, 7, 2), Vector3i(3 + i * 3, 10, 4), liquids[i])
		p.box(Vector3i(1 + i * 3, 10, 2), Vector3i(3 + i * 3, 11, 4), M.PLASTIC)
	p.box(Vector3i(1, 3, 6), Vector3i(8, 6, 9), M.CLOTH) # Folded cloths.
	p.box(Vector3i(11, 3, 1), Vector3i(18, 12, 9), M.RUBBER) # Bin bag.
	p.box(Vector3i(10, 11, 0), Vector3i(19, 12, 10), M.METAL)
	p.box(Vector3i(19, 3, 0), Vector3i(20, 15, 1), M.STEEL) # Push handle.
	p.box(Vector3i(19, 3, 9), Vector3i(20, 15, 10), M.STEEL)
	p.box(Vector3i(19, 14, 1), Vector3i(20, 15, 9), M.STEEL)
