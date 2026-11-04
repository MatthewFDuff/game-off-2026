extends RefCounted
## Office props (docs/prop-build-plan.md D3). Desk-top items (monitors, keyboard, mug, photo frame,
## lunch box) are floor mount, so they can stand on a desk or table as well as on the ground.
## Cubicle partitions are 15 tall: a steel frame around grey cloth.

const P := preload("res://scripts/world/props.gd")
const M := preload("res://scripts/voxel/voxel_materials.gd")

const CATEGORY := "Office"
const MOUNTS := {
	"cubicle_partition": "floor", "filing_cabinet": "floor", "printer_station": "floor", "copier": "floor",
	"coat_rack": "floor", "standing_desk": "floor", "monitor_": "floor", "keyboard_mouse": "floor",
	"mug": "floor", "photo_frame": "floor", "lunch_box": "floor", "jacket_chair": "floor", "cot": "floor",
}
const VALUES := {
	"cubicle_partition": 220, "filing_cabinet_2": 140, "filing_cabinet_4": 220, "printer_station": 650,
	"copier": 1400, "coat_rack": 60, "standing_desk": 800, "monitor_": 350, "keyboard_mouse": 60,
	"mug": 5, "photo_frame": 12, "lunch_box": 10, "jacket_chair": 90, "cot": 130,
}
const USES := {"filing_cabinet": "container", "lunch_box": "container"}


static func entries(add: Callable) -> void:
	add.call("cubicle_partition_straight", func(p: Props, o: Vector3i) -> void: partition(p, o, false))
	add.call("cubicle_partition_corner", func(p: Props, o: Vector3i) -> void: partition(p, o, true))
	add.call("filing_cabinet_2", func(p: Props, o: Vector3i) -> void: filing_cabinet(p, o, 2))
	add.call("filing_cabinet_4", func(p: Props, o: Vector3i) -> void: filing_cabinet(p, o, 4))
	add.call("printer_station", func(p: Props, o: Vector3i) -> void: printer_station(p, o))
	add.call("copier", func(p: Props, o: Vector3i) -> void: copier(p, o))
	add.call("coat_rack", func(p: Props, o: Vector3i) -> void: coat_rack(p, o))
	add.call("standing_desk", func(p: Props, o: Vector3i) -> void: standing_desk(p, o))
	add.call("monitor_single", func(p: Props, o: Vector3i) -> void: monitor(p, o, false))
	add.call("monitor_arm", func(p: Props, o: Vector3i) -> void: monitor(p, o, true))
	add.call("keyboard_mouse", func(p: Props, o: Vector3i) -> void: keyboard_mouse(p, o))
	add.call("mug", func(p: Props, o: Vector3i) -> void: mug(p, o))
	add.call("photo_frame", func(p: Props, o: Vector3i) -> void: photo_frame(p, o))
	add.call("lunch_box", func(p: Props, o: Vector3i) -> void: lunch_box(p, o))
	add.call("jacket_chair", func(p: Props, o: Vector3i) -> void: jacket_chair(p, o))
	add.call("cot", func(p: Props, o: Vector3i) -> void: cot(p, o))


static func b(p: Props, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, m: int) -> void:
	p.box(Vector3i(x0, y0, z0), Vector3i(x1, y1, z1), m)


## Straight: 20 wide, 2 thick. Corner: an L, 20 x 20 with 2-thick arms along the west side (z) and
## the north side... drawn along x at z = 0 and along z at x = 0.
static func partition(p: Props, o: Vector3i, corner: bool) -> void:
	var d := 20 if corner else 2
	p.begin(o, 20, d, P.NORTH)
	_panel_x(p, 0, 0, 20)
	if corner:
		_panel_z(p, 0, 2, 20)


static func _panel_x(p: Props, x: int, z: int, len: int) -> void:
	b(p, x, 1, z, x + len, 15, z + 2, M.CLOTH)
	b(p, x, 14, z, x + len, 15, z + 2, M.STEEL)         # Top rail.
	b(p, x, 1, z, x + len, 2, z + 2, M.STEEL)           # Bottom rail.
	for px in [x, x + len - 1]:
		b(p, px, 0, z, px + 1, 15, z + 2, M.STEEL)      # Posts.
	b(p, x + len / 2, 2, z, x + len / 2 + 1, 14, z + 2, M.STEEL)  # Mid post.
	for fx in [x + 1, x + len - 3]:
		b(p, fx, 0, z - (0 if z == 0 else 0), fx + 2, 1, z + 2, M.RUBBER)  # Feet.


static func _panel_z(p: Props, x: int, z: int, len: int) -> void:
	b(p, x, 1, z, x + 2, 15, z + len - 2, M.CLOTH)
	b(p, x, 14, z, x + 2, 15, z + len - 2, M.STEEL)
	b(p, x, 1, z, x + 2, 2, z + len - 2, M.STEEL)
	b(p, x, 0, z + len - 3, x + 2, 15, z + len - 2, M.STEEL)
	b(p, x, 2, z + (len - 2) / 2, x + 2, 14, z + (len - 2) / 2 + 1, M.STEEL)
	b(p, x, 0, z + 1, x + 2, 1, z + 3, M.RUBBER)


static func filing_cabinet(p: Props, o: Vector3i, drawers: int) -> void:
	var h := drawers * 4 - 1 + 2
	p.begin(o, 5, 6, P.NORTH)
	b(p, 0, 0, 0, 5, h, 6, M.METAL)
	b(p, 0, 0, 0, 5, 1, 1, M.RUBBER)
	for i in drawers:
		var y := 1 + i * 4
		b(p, 1, y, 0, 4, y + 1, 1, M.RUBBER)           # Drawer seam.
		b(p, 2, y + 2, 0, 3, y + 3, 1, M.STEEL)        # Pull.


static func printer_station(p: Props, o: Vector3i) -> void:
	p.begin(o, 10, 7, P.NORTH)
	b(p, 0, 0, 0, 10, 6, 7, M.METAL)
	b(p, 1, 1, 0, 9, 5, 1, M.RUBBER)                   # Cupboard doors.
	b(p, 5, 1, 0, 6, 5, 1, M.METAL)
	b(p, 1, 6, 1, 9, 9, 6, M.PLASTIC)                  # Printer.
	b(p, 2, 6, 0, 8, 7, 1, M.RUBBER)                   # Output tray.
	b(p, 2, 9, 3, 8, 10, 6, M.PLASTIC)                 # Paper feed.
	b(p, 7, 8, 0, 8, 9, 1, M.SCREEN)


static func copier(p: Props, o: Vector3i) -> void:
	p.begin(o, 10, 8, P.NORTH)
	b(p, 0, 0, 0, 10, 10, 8, M.PLASTIC)
	b(p, 0, 0, 0, 10, 1, 8, M.RUBBER)
	b(p, 0, 10, 0, 10, 11, 8, M.STEEL)                 # Lid.
	b(p, 1, 9, 1, 9, 10, 7, M.GLASS)                   # Platen.
	b(p, 1, 5, 0, 9, 6, 1, M.RUBBER)                   # Paper drawer seams.
	b(p, 1, 2, 0, 9, 3, 1, M.RUBBER)
	b(p, 6, 7, 0, 9, 9, 1, M.SCREEN)                   # Control panel.


static func coat_rack(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 6, P.NORTH)
	b(p, 1, 0, 1, 5, 1, 5, M.STEEL)                    # Base.
	b(p, 2, 1, 2, 4, 2, 4, M.STEEL)
	b(p, 2, 2, 2, 3, 20, 3, M.WOOD)                    # Pole.
	b(p, 0, 18, 2, 6, 19, 3, M.WOOD)                   # Hooks along x...
	b(p, 2, 18, 0, 3, 19, 6, M.WOOD)                   # ...and z.
	b(p, 0, 12, 2, 1, 18, 3, M.CLOTH)                  # A coat on one hook.
	b(p, 5, 15, 2, 6, 18, 3, M.RUBBER)                 # A scarf on another.


static func standing_desk(p: Props, o: Vector3i) -> void:
	p.begin(o, 16, 8, P.NORTH)
	b(p, 0, 11, 0, 16, 12, 8, M.WOOD)
	for x in [1, 14]:
		b(p, x, 0, 1, x + 1, 11, 7, M.STEEL)           # Frames.
		b(p, x - 1, 0, 0, x + 2, 1, 8, M.STEEL)        # Feet.
	b(p, 7, 10, 0, 9, 11, 2, M.SCREEN)                 # Height control.


## Single: a 7 x 4 stand-mounted screen. On arm: a clamp, an arm and the screen out front.
static func monitor(p: Props, o: Vector3i, on_arm: bool) -> void:
	p.begin(o, 7, 5, P.NORTH)
	if on_arm:
		b(p, 3, 0, 3, 5, 1, 5, M.STEEL)                # Clamp.
		b(p, 4, 1, 4, 5, 6, 5, M.STEEL)                # Arm up.
		b(p, 3, 6, 3, 5, 7, 4, M.STEEL)                # Joint.
		b(p, 0, 5, 2, 7, 11, 3, M.RUBBER)
		b(p, 1, 6, 1, 6, 10, 2, M.SCREEN)
	else:
		b(p, 1, 0, 1, 6, 1, 4, M.STEEL)                # Foot.
		b(p, 3, 1, 3, 4, 3, 4, M.STEEL)                # Neck.
		b(p, 0, 3, 3, 7, 8, 4, M.RUBBER)
		b(p, 1, 4, 2, 6, 7, 3, M.SCREEN)


static func keyboard_mouse(p: Props, o: Vector3i) -> void:
	p.begin(o, 9, 3, P.NORTH)
	b(p, 0, 0, 0, 6, 1, 3, M.RUBBER)                   # Keyboard.
	b(p, 7, 0, 1, 8, 1, 3, M.PLASTIC)                  # Mouse.


static func mug(p: Props, o: Vector3i) -> void:
	p.begin(o, 3, 2, P.NORTH)
	b(p, 0, 0, 0, 2, 2, 2, M.PLASTIC)
	b(p, 0, 1, 0, 2, 2, 2, M.PLASTIC)
	b(p, 2, 0, 0, 3, 1, 1, M.PLASTIC)                  # Handle.
	b(p, 2, 1, 0, 3, 2, 1, M.PLASTIC)


static func photo_frame(p: Props, o: Vector3i) -> void:
	p.begin(o, 4, 2, P.NORTH)
	b(p, 0, 0, 1, 4, 4, 2, M.WOOD)
	b(p, 1, 1, 1, 3, 3, 2, M.LIQUID_BLUE)              # Photograph.
	b(p, 2, 2, 1, 3, 3, 2, M.WARNING)
	b(p, 1, 0, 0, 3, 1, 1, M.WOOD)                     # Stand.


static func lunch_box(p: Props, o: Vector3i) -> void:
	p.begin(o, 5, 3, P.NORTH)
	b(p, 0, 0, 0, 5, 3, 3, M.LIQUID_BLUE)
	b(p, 0, 2, 0, 5, 3, 3, M.PLASTIC)                  # Lid.
	b(p, 2, 3, 1, 3, 4, 2, M.STEEL)                    # Latch.


## Office chair 4 x 5: the back is at z = 3, a cloth jacket slung over it and hanging behind.
static func jacket_chair(p: Props, o: Vector3i) -> void:
	p.begin(o, 4, 5, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(1, 4, 1), M.STEEL)
	p.box(Vector3i(3, 0, 0), Vector3i(4, 4, 1), M.STEEL)
	p.box(Vector3i(0, 0, 2), Vector3i(1, 4, 3), M.STEEL)
	p.box(Vector3i(3, 0, 2), Vector3i(4, 4, 3), M.STEEL)
	b(p, 0, 4, 0, 4, 5, 3, M.CLOTH)                    # Seat.
	b(p, 0, 5, 3, 4, 10, 4, M.CLOTH)                   # Back.
	b(p, 0, 8, 2, 4, 11, 3, M.WALL_LOWER)              # Jacket over the top, front panel...
	b(p, 0, 9, 3, 4, 11, 4, M.WALL_LOWER)
	b(p, 0, 5, 4, 4, 11, 5, M.WALL_LOWER)              # ...and back panel.
	b(p, 0, 5, 4, 1, 8, 5, M.WALL_LOWER)


static func cot(p: Props, o: Vector3i) -> void:
	p.begin(o, 18, 8, P.NORTH)
	for x in [1, 16]:
		b(p, x, 0, 0, x + 1, 3, 1, M.STEEL)            # Crossed legs, side view.
		b(p, x, 0, 7, x + 1, 3, 8, M.STEEL)
		b(p, x, 1, 1, x + 1, 2, 7, M.STEEL)
	b(p, 0, 3, 0, 18, 4, 1, M.STEEL)                   # Side rails.
	b(p, 0, 3, 7, 18, 4, 8, M.STEEL)
	b(p, 1, 3, 1, 17, 4, 7, M.CLOTH)                   # Canvas.
	b(p, 1, 4, 2, 5, 5, 6, M.PLASTIC)                  # Pillow.
	b(p, 6, 4, 1, 17, 5, 7, M.PLANK)                   # Blanket.
