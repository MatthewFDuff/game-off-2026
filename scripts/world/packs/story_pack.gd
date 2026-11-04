extends RefCounted
## Fung AI branding, outbreak traces and the overgrown twins (docs/prop-build-plan.md D4, docs/prop-gaps.md
## section 6). Wall props are one to two voxels deep with their front at z = 0, facing into the room
## like wall_board. Text is drawn as coloured bands (PixelFont is a runtime font, not a voxel tool),
## except the payroll ticker's digits, which use a 3 x 5 pixel digit set.
##
## The overgrown twins are the base generator from props.gd with MYCELIUM blobs climbing the
## edges, MYCELIUM_GLOW veins and ROOT at the base; they keep the base's footprint.

const P := preload("res://scripts/world/props.gd")
const M := preload("res://scripts/voxel/voxel_materials.gd")

const CATEGORY := "Story"
const MOUNTS := {
	"poster_fung": "wall", "org_chart": "wall", "mission_statement": "wall", "employee_board": "wall",
	"payroll_ticker": "wall", "operator_photo_wall": "wall", "scratched_note": "wall",
	"mascot_standee": "floor", "clone_vat_occupied": "floor", "overturned_": "floor",
	"barricade_door": "floor", "skeleton_": "floor", "cocoon": "any",
}
const VALUES := {
	"poster_fung": 30, "org_chart": 60, "mission_statement": 50, "employee_board": 70,
	"mascot_standee": 160, "payroll_ticker": 900, "operator_photo_wall": 120, "clone_vat_occupied": 6000,
	"overturned_desk": 40, "overturned_table": 30, "barricade_door": 120, "scratched_note": 5,
	"skeleton_suit": 1, "skeleton_overgrown": 1, "cocoon": 1,
	"desk_overgrown": 40, "chair_overgrown": 10, "locker_overgrown": 60, "terminal_overgrown": 150,
	"shelf_storage_a_overgrown": 40, "table_overgrown": 30, "couch_overgrown": 50,
}
const USES := {
	"poster_fung": "note", "org_chart": "note", "mission_statement": "note", "employee_board": "note",
	"operator_photo_wall": "note", "scratched_note": "note",
}

## Overgrown twins: base prop name -> footprint [w, d, height of the base].
const TWINS := {
	"desk": [16, 7, 14], "chair": [4, 4, 10], "locker": [5, 5, 20], "terminal": [12, 7, 16],
	"shelf_storage_a": [12, 4, 20], "table": [12, 8, 7], "couch": [18, 8, 9],
}

## Poster colour schemes: background, accent, text, border.
const SCHEMES := {
	"a": [M.CLOTH, M.WARNING, M.PLASTIC, M.STEEL],
	"b": [M.WARNING, M.RUBBER, M.RUBBER, M.STEEL],
	"c": [M.WALL_LOWER, M.PLASTIC, M.PLASTIC, M.RUBBER],
	"d": [M.BLOCK_WALL, M.PLASTIC, M.WARNING, M.RUBBER],
	"e": [M.SHROOM_CAP, M.SHROOM_STEM, M.TILE_LIGHT, M.RUBBER],
	"f": [M.RUBBER, M.EMERGENCY, M.TILE_DARK, M.STEEL],
}

## 3 x 5 pixel digits for the payroll ticker ('#' lit).
const DIGITS := {
	"0": ["###", "# #", "# #", "# #", "###"], "1": [" # ", "## ", " # ", " # ", "###"],
	"2": ["###", "  #", "###", "#  ", "###"], "3": ["###", "  #", "###", "  #", "###"],
	"4": ["# #", "# #", "###", "  #", "  #"], "5": ["###", "#  ", "###", "  #", "###"],
	"6": ["###", "#  ", "###", "# #", "###"], "7": ["###", "  #", "  #", " # ", " # "],
	"8": ["###", "# #", "###", "# #", "###"], "9": ["###", "# #", "###", "  #", "###"],
}


static func entries(add: Callable) -> void:
	for key: String in SCHEMES:
		var scheme: String = key
		add.call("poster_fung_" + scheme, func(p: Props, o: Vector3i) -> void: poster(p, o, scheme))
	add.call("org_chart", func(p: Props, o: Vector3i) -> void: org_chart(p, o))
	add.call("mission_statement", func(p: Props, o: Vector3i) -> void: mission_statement(p, o))
	add.call("employee_board", func(p: Props, o: Vector3i) -> void: employee_board(p, o))
	add.call("mascot_standee", func(p: Props, o: Vector3i) -> void: mascot(p, o))
	add.call("payroll_ticker", func(p: Props, o: Vector3i) -> void: payroll_ticker(p, o))
	add.call("operator_photo_wall", func(p: Props, o: Vector3i) -> void: photo_wall(p, o))
	add.call("clone_vat_occupied", func(p: Props, o: Vector3i) -> void: vat_occupied(p, o))
	add.call("overturned_desk", func(p: Props, o: Vector3i) -> void: overturned_desk(p, o))
	add.call("overturned_table", func(p: Props, o: Vector3i) -> void: overturned_table(p, o))
	add.call("barricade_door", func(p: Props, o: Vector3i) -> void: barricade(p, o))
	add.call("scratched_note", func(p: Props, o: Vector3i) -> void: scratched_note(p, o))
	add.call("skeleton_suit", func(p: Props, o: Vector3i) -> void: skeleton(p, o, false))
	add.call("skeleton_overgrown", func(p: Props, o: Vector3i) -> void: skeleton(p, o, true))
	for key: String in TWINS:
		var base: String = key
		add.call(base + "_overgrown", func(p: Props, o: Vector3i) -> void: overgrown(p, o, base))
	add.call("cocoon", func(p: Props, o: Vector3i) -> void: cocoon(p, o))


static func _b(p: Props, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, m: int) -> void:
	p.box(Vector3i(x0, y0, z0), Vector3i(x1, y1, z1), m)


## Draws character rows at (x0, y0, z): rows[0] is the top row, key maps a character to a material,
## anything else is left alone.
static func _pix(p: Props, rows: Array, key: Dictionary, x0: int, y0: int, z: int) -> void:
	var n := rows.size()
	for i in n:
		var row: String = rows[i]
		for x in row.length():
			var c := row[x]
			if key.has(c):
				_b(p, x0 + x, y0 + n - 1 - i, z, x0 + x + 1, y0 + n - i, z + 1, key[c])


## A band of word-like chunks along x from x0 to x1 at row y, h tall, front layer z.
static func _text_band(p: Props, x0: int, x1: int, y: int, h: int, m: int) -> void:
	var x := x0
	while x < x1:
		var w := mini(p.rng.randi_range(2, 4), x1 - x)
		_b(p, x, y, 0, x + w, y + h, 1, m)
		x += w + 1


## A 12 x 16 Fung AI poster: a border, a mushroom logo, a headline and two lines of small print.
static func poster(p: Props, o: Vector3i, scheme: String) -> void:
	var c: Array = SCHEMES[scheme]
	p.begin(o, 12, 1, P.NORTH)
	_b(p, 0, 0, 0, 12, 16, 1, c[3])
	_b(p, 1, 1, 0, 11, 15, 1, c[0])
	_pix(p, [" ### ", "#####", "  #  ", "  #  "], {"#": c[1]}, 3, 10, 0) # Logo.
	_text_band(p, 2, 10, 7, 2, c[1]) # Headline.
	_text_band(p, 2, 10, 5, 1, c[2])
	_text_band(p, 2, 10, 3, 1, c[2])
	_b(p, 2, 1, 0, 10, 2, 1, c[1]) # Rule.


## Org chart: Guy Fung on top, three directors, and a row of replaceable employees.
static func org_chart(p: Props, o: Vector3i) -> void:
	p.begin(o, 20, 1, P.NORTH)
	_b(p, 0, 0, 0, 20, 14, 1, M.STEEL)
	_b(p, 1, 1, 0, 19, 13, 1, M.PLASTIC)
	_b(p, 8, 10, 0, 12, 13, 1, M.WARNING)
	_b(p, 9, 11, 0, 11, 12, 1, M.RUBBER)
	_b(p, 10, 9, 0, 11, 10, 1, M.RUBBER)
	_b(p, 4, 8, 0, 17, 9, 1, M.RUBBER)
	for x in [2, 8, 14]:
		_b(p, x, 4, 0, x + 4, 8, 1, M.CLOTH)
		_b(p, x + 1, 6, 0, x + 3, 7, 1, M.PLASTIC)
	for i in 6:
		var x := 1 + i * 3
		_b(p, x, 3, 0, x + 1, 4, 1, M.RUBBER)
		_b(p, x - 1 if x > 1 else x, 1, 0, x + 2 if x < 16 else x + 1, 3, 1, M.EMERGENCY if i == 5 else M.TILE_DARK)


## Mission statement plaque: a wooden frame, a headline and paragraphs of small print.
static func mission_statement(p: Props, o: Vector3i) -> void:
	p.begin(o, 16, 1, P.NORTH)
	_b(p, 0, 0, 0, 16, 10, 1, M.WOOD)
	_b(p, 1, 1, 0, 15, 9, 1, M.PLASTIC)
	_b(p, 3, 7, 0, 13, 8, 1, M.WARNING)
	_b(p, 7, 8, 0, 9, 9, 1, M.WARNING)
	for y in [5, 3]:
		_text_band(p, 2, 14, y, 1, M.CLOTH)
	_b(p, 5, 1, 0, 11, 2, 1, M.RUBBER) # Signature.


## Employee of the month board: cork, a pinned portrait, and last months crossed out.
static func employee_board(p: Props, o: Vector3i) -> void:
	p.begin(o, 14, 1, P.NORTH)
	_b(p, 0, 0, 0, 14, 12, 1, M.STEEL)
	_b(p, 1, 1, 0, 13, 11, 1, M.PLANK)
	_b(p, 2, 9, 0, 12, 10, 1, M.WARNING) # Headline.
	_b(p, 4, 3, 0, 10, 9, 1, M.WOOD) # Portrait frame.
	_b(p, 5, 4, 0, 9, 8, 1, M.TILE_LIGHT)
	_b(p, 6, 7, 0, 8, 8, 1, M.RUBBER) # Hair.
	_b(p, 6, 5, 0, 8, 7, 1, M.PIPE) # Face.
	_b(p, 5, 4, 0, 9, 5, 1, M.CLOTH) # Suit.
	_b(p, 5, 2, 0, 9, 3, 1, M.PLASTIC) # Nameplate.
	for x in [1, 10]: # Earlier winners, struck through.
		_b(p, x + 1, 4, 0, x + 3, 7, 1, M.PLASTIC)
		_b(p, x + 1, 4, 0, x + 2, 5, 1, M.EMERGENCY)
		_b(p, x + 2, 5, 0, x + 3, 6, 1, M.EMERGENCY)
		_b(p, x + 1, 6, 0, x + 2, 7, 1, M.EMERGENCY)
	for at in [Vector2i(4, 9), Vector2i(9, 9)]:
		_b(p, at.x, at.y, 0, at.x + 1, at.y + 1, 1, M.EMERGENCY) # Pins.


## Cardboard standee of the Fung AI mushroom: a smiling purple-cap character with an easel foot.
static func mascot(p: Props, o: Vector3i) -> void:
	p.begin(o, 12, 4, P.NORTH)
	var rows := [
		"....PPPP....", "..PPPPPPPP..", ".PPSSPPPPPP.", ".PPSSPPPSSP.", "PPPPPPPPSSPP", "PPSSPPPPPPPP",
		"PPSSPPPSSPPP", "PPPPPPPSSPPP", "KKKKKKKKKKKK", "...TTTTTT...", "...TTTTTT...", "...TKTTKT...",
		"...TKTTKT...", "...TTTTTT...", "...KTTTTK...", "...TKKKKT...", "...TTTTTT...", "..TTTTTTTT..",
	]
	_pix(p, rows, {"P": M.SHROOM_CAP, "S": M.PLASTIC, "T": M.SHROOM_STEM, "K": M.RUBBER}, 0, 0, 0)
	var backing := rows.duplicate()
	for i in backing.size():
		backing[i] = String(backing[i]).replace("P", "W").replace("S", "W").replace("T", "W").replace("K", "W")
	_pix(p, backing, {"W": M.PLANK}, 0, 0, 1)
	_b(p, 3, 0, 2, 4, 7, 3, M.PLANK) # Easel foot.
	_b(p, 8, 0, 2, 9, 7, 3, M.PLANK)
	_b(p, 3, 0, 3, 9, 1, 4, M.PLANK)


## Payroll ticker: a screen with red digits, the running balance every operator owes.
static func payroll_ticker(p: Props, o: Vector3i) -> void:
	p.begin(o, 27, 2, P.NORTH)
	_b(p, 0, 0, 1, 27, 9, 2, M.RUBBER)
	_b(p, 0, 0, 0, 27, 9, 1, M.RUBBER)
	_b(p, 1, 1, 0, 26, 8, 1, M.SCREEN)
	var digits := "412907"
	for i in digits.length():
		_pix(p, DIGITS[digits[i]], {"#": M.EMERGENCY}, 2 + i * 4, 2, 0)
	_b(p, 24, 1, 0, 25, 2, 1, M.EMERGENCY) # Cents blink.


## A wall of past operators: a grid of 5 x 3 small portraits. The last frame is empty, waiting.
static func photo_wall(p: Props, o: Vector3i) -> void:
	p.begin(o, 26, 1, P.NORTH)
	_b(p, 0, 0, 0, 26, 19, 1, M.STEEL)
	var backs := [M.WALL_PAINT, M.TILE_DARK, M.WALL_LOWER, M.PLASTIC, M.TILE_LIGHT]
	for r in 3:
		for c in 5:
			var x := 1 + c * 5
			var y := 1 + r * 6
			if r == 2 and c == 4:
				_b(p, x, y, 0, x + 4, y + 5, 1, M.RUBBER) # The empty frame.
				continue
			_b(p, x, y, 0, x + 4, y + 5, 1, backs[p.rng.randi() % backs.size()])
			_b(p, x, y, 0, x + 4, y + 2, 1, [M.CLOTH, M.RUBBER, M.STEEL][p.rng.randi() % 3]) # Suit.
			_b(p, x + 1, y + 2, 0, x + 3, y + 4, 1, M.PIPE) # Face.
			_b(p, x + 1, y + 4, 0, x + 3, y + 5, 1, [M.RUBBER, M.WOOD, M.WARNING][p.rng.randi() % 3]) # Hair.


## The clone vat with a pale figure floating in it, arms at its sides.
static func vat_occupied(p: Props, o: Vector3i) -> void:
	p.clone_vat(o)
	_b(p, 1, 4, 1, 7, 19, 7, M.LIQUID_GREEN)
	_b(p, 2, 4, 3, 3, 9, 5, M.TILE_LIGHT) # Legs.
	_b(p, 5, 4, 3, 6, 9, 5, M.TILE_LIGHT)
	_b(p, 2, 9, 3, 6, 14, 5, M.TILE_LIGHT) # Torso.
	_b(p, 1, 9, 3, 2, 14, 5, M.TILE_LIGHT) # Arms.
	_b(p, 6, 9, 3, 7, 14, 5, M.TILE_LIGHT)
	_b(p, 2, 14, 2, 6, 18, 6, M.TILE_LIGHT) # Head.
	_b(p, 2, 17, 2, 6, 18, 6, M.WOOD) # Hair.
	_b(p, 3, 15, 2, 5, 16, 3, M.RUBBER) # Closed eyes.
	_b(p, 4, 9, 2, 5, 12, 3, M.RUBBER) # Feed line.


## A desk tipped back on its edge: top upright at the back, the drawer stack lying along the floor.
static func overturned_desk(p: Props, o: Vector3i) -> void:
	p.begin(o, 16, 8, P.NORTH)
	_b(p, 0, 0, 7, 16, 7, 8, M.WOOD) # Top, standing.
	_b(p, 0, 0, 0, 4, 4, 7, M.WOOD) # Drawer stack, lying down.
	_b(p, 1, 4, 5, 3, 5, 6, M.STEEL) # Handle.
	_b(p, 15, 0, 0, 16, 7, 7, M.STEEL) # End panel.
	_b(p, 5, 0, 1, 8, 1, 4, M.PLASTIC) # Papers on the floor.
	_b(p, 9, 0, 3, 12, 1, 6, M.PLASTIC)
	_b(p, 6, 0, 5, 9, 2, 7, M.RUBBER) # Fallen monitor.
	_b(p, 7, 1, 5, 8, 2, 6, M.SCREEN)


## A table on its side: the top is a wall of wood and the legs stick out.
static func overturned_table(p: Props, o: Vector3i) -> void:
	p.begin(o, 12, 7, P.NORTH)
	_b(p, 0, 0, 6, 12, 8, 7, M.WOOD)
	for x in [0, 11]:
		for y in [0, 7]:
			_b(p, x, y, 0 if (x + y) != 11 else 3, x + 1, y + 1, 6, M.STEEL)
	_b(p, 4, 3, 5, 7, 5, 6, M.RUBBER) # Splintered patch.


## A door-sized frame with planks nailed across it. Floor-standing; the planks are the front layer.
static func barricade(p: Props, o: Vector3i) -> void:
	p.begin(o, 12, 3, P.NORTH)
	_b(p, 0, 0, 2, 2, 22, 3, M.METAL) # Frame posts and lintel.
	_b(p, 10, 0, 2, 12, 22, 3, M.METAL)
	_b(p, 0, 20, 2, 12, 22, 3, M.METAL)
	_b(p, 2, 0, 2, 10, 20, 3, M.RUBBER) # The dark doorway.
	var y := 1
	while y < 19:
		var x0 := p.rng.randi_range(0, 2)
		var x1 := 12 - p.rng.randi_range(0, 2)
		_b(p, x0, y, 0, x1, y + 3, 2, M.PLANK)
		_b(p, x0 + 1, y + 1, 0, x0 + 2, y + 2, 1, M.STEEL) # Nails.
		_b(p, x1 - 2, y + 1, 0, x1 - 1, y + 2, 1, M.STEEL)
		_b(p, x0 + 3, y, 0, x0 + 4, y + 3, 1, M.WOOD) # Grain.
		y += 4


## A torn page with scribbles and scratch marks.
static func scratched_note(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 1, P.NORTH)
	_b(p, 0, 0, 0, 8, 6, 1, M.PLASTIC)
	_b(p, 6, 5, 0, 8, 6, 1, M.AIR) # Torn corner.
	_b(p, 0, 0, 0, 2, 1, 1, M.AIR)
	_b(p, 0, 5, 0, 2, 6, 1, M.WARNING) # Tape.
	_text_band(p, 1, 7, 3, 1, M.RUBBER)
	_text_band(p, 1, 7, 1, 1, M.RUBBER)
	for x in range(1, 7, 2):
		_b(p, x, 2, 0, x + 1, 3, 1, M.EMBER_DEEP) # Frantic scratches.
	_b(p, 2, 4, 0, 6, 5, 1, M.EMBER_DEEP)


## A skeleton in a navy suit and red tie lying on its back, 22 long. overgrown: mycelium has
## taken the torso and legs.
static func skeleton(p: Props, o: Vector3i, overgrown_one: bool) -> void:
	p.begin(o, 22, 8, P.NORTH)
	_b(p, 0, 0, 2, 4, 3, 5, M.PLASTIC) # Skull.
	_b(p, 0, 1, 2, 1, 2, 5, M.RUBBER) # Jaw shadow.
	_b(p, 1, 2, 2, 2, 3, 3, M.RUBBER) # Eye sockets.
	_b(p, 1, 2, 4, 2, 3, 5, M.RUBBER)
	_b(p, 4, 0, 1, 12, 2, 7, M.CLOTH) # Jacket.
	for x in [5, 7, 9]:
		_b(p, x, 2, 2, x + 1, 3, 6, M.PLASTIC) # Ribs through the cloth.
	_b(p, 4, 2, 3, 6, 3, 4, M.EMERGENCY) # Tie.
	_b(p, 5, 0, 0, 12, 2, 1, M.CLOTH) # Arms.
	_b(p, 5, 0, 7, 12, 2, 8, M.CLOTH)
	_b(p, 12, 0, 0, 15, 1, 1, M.PLASTIC) # Hand bones.
	_b(p, 12, 0, 7, 14, 1, 8, M.PLASTIC)
	_b(p, 12, 0, 1, 14, 2, 7, M.CLOTH) # Hips.
	_b(p, 14, 0, 1, 20, 2, 3, M.CLOTH) # Trousers.
	_b(p, 14, 0, 4, 20, 2, 6, M.CLOTH)
	_b(p, 20, 0, 1, 22, 1, 3, M.RUBBER) # Shoes.
	_b(p, 20, 0, 4, 22, 1, 6, M.RUBBER)
	if overgrown_one:
		_b(p, 3, 0, 1, 11, 3, 4, M.MYCELIUM)
		_b(p, 8, 0, 4, 18, 2, 7, M.MYCELIUM)
		_b(p, 12, 2, 2, 17, 3, 4, M.MYCELIUM)
		_b(p, 2, 3, 3, 3, 4, 4, M.MYCELIUM)
		for x in range(4, 20, 3):
			_b(p, x, 3, 2 + (x % 3), x + 2, 4, 3 + (x % 3), M.MYCELIUM_GLOW) # Veins.
		_b(p, 14, 2, 0, 20, 3, 1, M.ROOT)
		_b(p, 0, 0, 5, 3, 1, 6, M.ROOT)
		_b(p, 18, 0, 3, 22, 1, 4, M.ROOT)


## The base prop with growth on it. Footprint, shape and stock match the base generator.
static func overgrown(p: Props, o: Vector3i, base: String) -> void:
	var info: Array = TWINS[base]
	p.rng.seed = hash(base) # Same stock as the base prop.
	match base:
		"desk": p.desk(o, P.NORTH, 16)
		"chair": p.chair(o, P.NORTH)
		"locker": p.locker(o, P.NORTH)
		"terminal": p.terminal(o, P.NORTH)
		"shelf_storage_a": p.shelf(o, P.NORTH, 12, 20, 4, "storage")
		"table": p.table(o, P.NORTH, 12, 8)
		"couch": p.couch(o, P.NORTH)
	p.rng.seed = hash(base + "_overgrown")
	grow(p, info[0], info[1], info[2])


## Blobs of mycelium climbing the edges of a w x d x h prop, thin glowing veins and roots.
static func grow(p: Props, w: int, d: int, h: int) -> void:
	var bw := mini(2, w)
	var bd := mini(2, d)
	var count := 3 + (2 if w * d >= 40 else 0)
	for i in count:
		var side := p.rng.randi_range(0, 3)
		var x := 0
		var z := 0
		var vx := 0
		var vz := 0
		match side:
			0:
				x = p.rng.randi_range(0, w - bw)
				vx = x + p.rng.randi_range(0, bw - 1)
			1:
				x = p.rng.randi_range(0, w - bw)
				z = d - bd
				vx = x + p.rng.randi_range(0, bw - 1)
				vz = d - 1
			2:
				z = p.rng.randi_range(0, d - bd)
				vz = z + p.rng.randi_range(0, bd - 1)
			_:
				x = w - bw
				z = p.rng.randi_range(0, d - bd)
				vx = w - 1
				vz = z + p.rng.randi_range(0, bd - 1)
		var top := p.rng.randi_range(2, maxi(3, h * 2 / 3))
		_b(p, x, 0, z, x + bw, top, z + bd, M.MYCELIUM)
		_b(p, x, top, z, x + 1, top + 1, z + 1, M.MYCELIUM) # Lumpy crown.
		_b(p, vx, 1, vz, vx + 1, mini(top + 3, h + 1), vz + 1, M.MYCELIUM_GLOW)
	for k in 2:
		var y := p.rng.randi_range(1, maxi(1, h - 1))
		var x0 := p.rng.randi_range(0, w / 2)
		_b(p, x0, y, 0, mini(x0 + w / 2, w), y + 1, 1, M.MYCELIUM_GLOW) # A vein across the front.
	for at in [Vector2i(0, 0), Vector2i(w - 1, d - 1)]:
		_b(p, at.x, 0, at.y, at.x + 1, 2, at.y + 1, M.ROOT)


## A wrapped human shape, 18 tall plus a neck of strands to the ceiling, with a name tag on the
## chest. Mount "any": hung from a ceiling it hangs, set on the floor it stands.
static func cocoon(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 6, P.NORTH)
	_b(p, 2, 0, 2, 4, 2, 4, M.MYCELIUM) # Feet.
	_b(p, 1, 2, 1, 5, 10, 5, M.MYCELIUM) # Legs.
	_b(p, 0, 10, 1, 6, 15, 5, M.MYCELIUM) # Torso and arms.
	_b(p, 1, 15, 1, 5, 18, 5, M.MYCELIUM) # Head.
	_b(p, 2, 18, 2, 4, 20, 4, M.ROOT) # Strands up.
	for y in [4, 8, 12, 16]:
		_b(p, 1 if y < 10 else 0, y, 1, 5 if y < 10 else 6, y + 1, 5, M.ROOT) # Wrapping bands.
	_b(p, 0, 11, 3, 1, 15, 4, M.MYCELIUM_GLOW) # Veins.
	_b(p, 5, 11, 2, 6, 15, 3, M.MYCELIUM_GLOW)
	_b(p, 3, 3, 1, 4, 10, 2, M.MYCELIUM_GLOW)
	_b(p, 2, 16, 1, 3, 18, 2, M.MYCELIUM_GLOW)
	_b(p, 2, 11, 0, 5, 13, 1, M.PLASTIC) # Name tag.
	_b(p, 2, 12, 0, 4, 13, 1, M.RUBBER)
