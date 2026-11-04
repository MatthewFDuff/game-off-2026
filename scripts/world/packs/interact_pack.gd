extends RefCounted
## Interactables (docs/prop-build-plan.md E): the art for props with behavior. The rules are in
## LevelPlay (the `use` values below, LevelSchema.USES) and, for props that react to being shot or
## burnt (the fire extinguisher, the gas cylinder) or cut down (the hanging crate), by name there.
##
## Wall props (switches, the alarm pull, the eyewash, the defibrillator) have their back plate at
## the high z edge and their front at z = 0, like the plant pack's breaker panel. The hanging loads
## are ceiling props drawn from y = 0 up with their anchor plate as the top layer; their chain is a
## single column of STEEL, so one shot cuts it and the load drops (detach_floating)
## and crushes what is under it (LevelPlay).
##
## The flipped tables and desks are the base pack's table and desk tipped forward onto their front
## edge, in the same footprint: the top stands up at z = 0 as cover, the legs point back. The `flip`
## use swaps a prop for its `<name>_flipped` twin.
##
## FIELDS is this pack's per-name field defaults for new props (LevelSchema.new_prop): what a fresh
## vending machine charges and drops, the water cooler's and the coffee counter's buff, and so on.

const P := preload("res://scripts/world/props.gd")
const M := preload("res://scripts/voxel/voxel_materials.gd")

const CATEGORY := "Interact"
const MOUNTS := {
	"switch_": "wall", "light_switch": "wall", "alarm_pull": "wall", "eyewash": "wall", "defib": "wall",
	"crate_hanging": "ceiling", "pallet_hanging": "ceiling",
}
const VALUES := {
	"switch_": 60, "light_switch": 15, "alarm_pull": 90, "eyewash": 350, "emergency_shower": 900, "defib": 1800,
	"fire_extinguisher": 120, "gas_cylinder": 300, "crate_hanging": 200, "pallet_hanging": 450, "radio": 80,
	"jukebox": 2500, "vending_machine_glass": 1700, "table_flipped": 300, "table_small_flipped": 220,
	"table_large_flipped": 400, "desk_flipped": 600, "desk_empty_flipped": 450,
}
## The built-in props' uses (vending machine, coffee counter, printers, the duck, the breakers and
## the extinguisher cabinet) live here too, beside the new ones. water_cooler is LevelSchema's own.
const USES := {
	"switch_": "switch", "light_switch": "switch", "alarm_pull": "switch", "breaker_panel": "switch", "fuse_box": "switch",
	"vending_machine": "vendor", "counter_coffee": "vendor", "eyewash": "eyewash", "emergency_shower": "eyewash",
	"defib": "defib", "fire_extinguisher": "extinguisher", "extinguisher_cabinet": "container",
	"table": "flip", "desk": "flip", "printer_station": "printer", "copier": "printer", "radio": "radio",
	"jukebox": "radio", "rubber_duck": "squeak",
	# Twins and lookalikes that don't flip.
	"table_flipped": "none", "table_small_flipped": "none", "table_large_flipped": "none", "table_overgrown": "none",
	"desk_flipped": "none", "desk_empty_flipped": "none", "desk_overgrown": "none",
}
## Field defaults for new props by name prefix (LevelSchema.new_prop merges them over PROP_FIELDS').
const FIELDS := {
	"vending_machine": {price = 3, contents = "snack"},
	"counter_coffee": {price = 1, buff = "reload"},
	"water_cooler": {buff = "speed"},
	"extinguisher_cabinet": {contents = "flask_foam"},
	"alarm_pull": {once = true},
	"defib": {charges = 2},
	"printer_station": {text = "MEMO: Fung AI reminds all staff that printer toner is billed per page."},
	"copier": {text = "COPY OF A COPY: \"Do not feed the specimens. They are fed by the building.\""},
}


static func entries(add: Callable) -> void:
	add.call("switch_lever", func(p: Props, o: Vector3i) -> void: switch_lever(p, o))
	add.call("switch_button", func(p: Props, o: Vector3i) -> void: switch_button(p, o))
	add.call("switch_sprinkler", func(p: Props, o: Vector3i) -> void: switch_sprinkler(p, o))
	add.call("light_switch", func(p: Props, o: Vector3i) -> void: light_switch(p, o))
	add.call("alarm_pull", func(p: Props, o: Vector3i) -> void: alarm_pull(p, o))
	add.call("eyewash_station", func(p: Props, o: Vector3i) -> void: eyewash(p, o))
	add.call("emergency_shower", func(p: Props, o: Vector3i) -> void: emergency_shower(p, o))
	add.call("defib_cabinet", func(p: Props, o: Vector3i) -> void: defib_cabinet(p, o))
	add.call("fire_extinguisher", func(p: Props, o: Vector3i) -> void: fire_extinguisher(p, o))
	add.call("gas_cylinder", func(p: Props, o: Vector3i) -> void: gas_cylinder(p, o, M.WARNING))
	add.call("gas_cylinder_oxygen", func(p: Props, o: Vector3i) -> void: gas_cylinder(p, o, M.WALL_LOWER))
	add.call("crate_hanging", func(p: Props, o: Vector3i) -> void: crate_hanging(p, o))
	add.call("pallet_hanging", func(p: Props, o: Vector3i) -> void: pallet_hanging(p, o))
	add.call("table_flipped", func(p: Props, o: Vector3i) -> void: table_flipped(p, o, 12, 8))
	add.call("table_small_flipped", func(p: Props, o: Vector3i) -> void: table_flipped(p, o, 10, 6))
	add.call("table_large_flipped", func(p: Props, o: Vector3i) -> void: table_flipped(p, o, 16, 10))
	add.call("desk_flipped", func(p: Props, o: Vector3i) -> void: desk_flipped(p, o, 16, true))
	add.call("desk_empty_flipped", func(p: Props, o: Vector3i) -> void: desk_flipped(p, o, 16, false))
	add.call("radio", func(p: Props, o: Vector3i) -> void: radio(p, o))
	add.call("jukebox", func(p: Props, o: Vector3i) -> void: jukebox(p, o))
	add.call("vending_machine_glass", func(p: Props, o: Vector3i) -> void: vending_glass(p, o))


# --- Switches ------------------------------------------------------------------------------------

## A 4 x 7 steel plate with a dark slot and a lever up in it, red knob on top.
static func switch_lever(p: Props, o: Vector3i) -> void:
	p.begin(o, 4, 2, P.NORTH)
	p.box(Vector3i(0, 0, 1), Vector3i(4, 7, 2), M.STEEL)
	p.box(Vector3i(1, 1, 0), Vector3i(3, 6, 1), M.HATCH) # Slot.
	p.box(Vector3i(1, 3, 0), Vector3i(3, 4, 1), M.METAL) # Pivot.
	p.box(Vector3i(1, 4, 0), Vector3i(3, 6, 1), M.RED_PAINT) # Knob.


## A 3 x 3 steel plate with a red push button.
static func switch_button(p: Props, o: Vector3i) -> void:
	p.begin(o, 3, 2, P.NORTH)
	p.box(Vector3i(0, 0, 1), Vector3i(3, 3, 2), M.STEEL)
	p.box(Vector3i(1, 1, 0), Vector3i(2, 2, 1), M.RED_PAINT)


## The sprinkler's manual valve: a steel plate, a pipe stub and a red valve wheel, a warning band.
static func switch_sprinkler(p: Props, o: Vector3i) -> void:
	p.begin(o, 5, 2, P.NORTH)
	p.box(Vector3i(0, 0, 1), Vector3i(5, 7, 2), M.STEEL)
	p.box(Vector3i(0, 6, 1), Vector3i(5, 7, 2), M.WARNING)
	p.box(Vector3i(2, 0, 0), Vector3i(3, 6, 1), M.PIPE)
	p.box(Vector3i(1, 2, 0), Vector3i(4, 3, 1), M.RED_PAINT) # Wheel rim.
	p.box(Vector3i(1, 4, 0), Vector3i(4, 5, 1), M.RED_PAINT)
	p.box(Vector3i(1, 3, 0), Vector3i(2, 4, 1), M.RED_PAINT)
	p.box(Vector3i(3, 3, 0), Vector3i(4, 4, 1), M.RED_PAINT)


## A white plastic plate with a black rocker.
static func light_switch(p: Props, o: Vector3i) -> void:
	p.begin(o, 2, 2, P.NORTH)
	p.box(Vector3i(0, 0, 1), Vector3i(2, 3, 2), M.PLASTIC)
	p.box(Vector3i(0, 1, 0), Vector3i(1, 2, 1), M.RUBBER)


## A red fire alarm pull station: a box with a white pull bar and a white label strip.
static func alarm_pull(p: Props, o: Vector3i) -> void:
	p.begin(o, 4, 2, P.NORTH)
	p.box(Vector3i(0, 0, 1), Vector3i(4, 6, 2), M.RED_PAINT)
	p.box(Vector3i(0, 0, 0), Vector3i(4, 6, 1), M.RED_PAINT)
	p.box(Vector3i(1, 4, 0), Vector3i(3, 5, 1), M.PLASTIC) # Label.
	p.box(Vector3i(1, 2, 0), Vector3i(3, 3, 1), M.PLASTIC) # Pull bar.


# --- Safety stations -----------------------------------------------------------------------------

## An 8 x 12 eyewash: a green sign plate, a steel bowl with two yellow nozzles, a yellow push paddle,
## the supply pipe down to the floor.
static func eyewash(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 4, P.NORTH)
	p.box(Vector3i(1, 0, 3), Vector3i(7, 12, 4), M.STEEL) # Back plate.
	p.box(Vector3i(2, 9, 3), Vector3i(6, 11, 4), M.WALL_LOWER) # Sign.
	p.box(Vector3i(3, 10, 3), Vector3i(5, 11, 4), M.PLASTIC)
	p.box(Vector3i(3, 0, 2), Vector3i(5, 6, 3), M.PIPE) # Supply.
	p.box(Vector3i(0, 6, 0), Vector3i(8, 7, 3), M.STEEL) # Bowl.
	p.box(Vector3i(0, 7, 0), Vector3i(8, 8, 1), M.STEEL)
	p.box(Vector3i(0, 7, 0), Vector3i(1, 8, 3), M.STEEL)
	p.box(Vector3i(7, 7, 0), Vector3i(8, 8, 3), M.STEEL)
	p.box(Vector3i(2, 7, 1), Vector3i(3, 8, 2), M.WARNING) # Nozzles.
	p.box(Vector3i(5, 7, 1), Vector3i(6, 8, 2), M.WARNING)
	p.box(Vector3i(7, 4, 0), Vector3i(8, 6, 2), M.WARNING) # Paddle.


## A free-standing emergency shower: a yellow pipe column, an arm out to a yellow head, a pull rod
## with a triangle handle, and a steel drain grate to stand on.
static func emergency_shower(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 8, P.NORTH)
	for z in range(0, 8, 2):
		p.box(Vector3i(0, 0, z), Vector3i(8, 1, z + 1), M.STEEL) # Grate slats.
	p.box(Vector3i(0, 0, 0), Vector3i(1, 1, 8), M.STEEL)
	p.box(Vector3i(7, 0, 0), Vector3i(8, 1, 8), M.STEEL)
	p.box(Vector3i(0, 1, 6), Vector3i(2, 26, 8), M.WARNING) # Column.
	p.box(Vector3i(1, 24, 3), Vector3i(2, 25, 6), M.WARNING) # Arm.
	p.box(Vector3i(1, 24, 3), Vector3i(4, 25, 4), M.WARNING)
	p.box(Vector3i(2, 22, 2), Vector3i(6, 24, 6), M.WARNING) # Head.
	p.box(Vector3i(3, 21, 3), Vector3i(5, 22, 5), M.STEEL) # Rose.
	p.box(Vector3i(6, 14, 3), Vector3i(7, 22, 4), M.STEEL) # Pull rod.
	p.box(Vector3i(5, 13, 3), Vector3i(8, 14, 4), M.WARNING) # Handle.
	p.box(Vector3i(5, 12, 3), Vector3i(6, 13, 4), M.WARNING)
	p.box(Vector3i(7, 12, 3), Vector3i(8, 13, 4), M.WARNING)
	p.box(Vector3i(5, 11, 3), Vector3i(8, 12, 4), M.WARNING)


## A white wall cabinet with a green band, a red heart and the yellow unit behind a glass door.
static func defib_cabinet(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 3, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(6, 8, 3), M.PLASTIC)
	p.box(Vector3i(1, 1, 0), Vector3i(5, 5, 2), M.AIR)
	p.box(Vector3i(1, 1, 1), Vector3i(5, 4, 2), M.WARNING) # The unit.
	p.box(Vector3i(2, 2, 0), Vector3i(4, 3, 1), M.GLASS) # Door glint.
	p.box(Vector3i(0, 5, 0), Vector3i(6, 8, 1), M.WALL_LOWER) # Band.
	p.box(Vector3i(2, 6, 0), Vector3i(4, 7, 1), M.RED_PAINT) # Heart.
	p.box(Vector3i(1, 6, 0), Vector3i(2, 7, 1), M.RED_PAINT)
	p.box(Vector3i(4, 6, 0), Vector3i(5, 7, 1), M.RED_PAINT)
	p.box(Vector3i(2, 7, 0), Vector3i(3, 8, 1), M.RED_PAINT)
	p.box(Vector3i(3, 5, 0), Vector3i(4, 6, 1), M.RED_PAINT)


# --- Hazards -------------------------------------------------------------------------------------

## A red extinguisher standing on the floor: a rounded body, a white label, a steel neck and handle,
## a black hose down the side.
static func fire_extinguisher(p: Props, o: Vector3i) -> void:
	p.begin(o, 3, 3, P.NORTH)
	p.box(Vector3i(1, 0, 0), Vector3i(2, 6, 3), M.RED_PAINT)
	p.box(Vector3i(0, 0, 1), Vector3i(3, 6, 2), M.RED_PAINT)
	p.box(Vector3i(1, 2, 0), Vector3i(2, 4, 1), M.PLASTIC) # Label.
	p.box(Vector3i(1, 6, 1), Vector3i(2, 7, 2), M.METAL) # Neck.
	p.box(Vector3i(0, 7, 1), Vector3i(3, 8, 2), M.STEEL) # Handle.
	p.box(Vector3i(2, 3, 0), Vector3i(3, 6, 1), M.RUBBER) # Hose.


## A tall gas cylinder: a rounded STEEL body (soft enough for a shot to hole it, which is what
## sets it off), a band in band, a steel valve and a cap.
static func gas_cylinder(p: Props, o: Vector3i, band: int) -> void:
	p.begin(o, 3, 3, P.NORTH)
	p.box(Vector3i(1, 0, 0), Vector3i(2, 13, 3), M.STEEL)
	p.box(Vector3i(0, 0, 1), Vector3i(3, 13, 2), M.STEEL)
	p.box(Vector3i(1, 10, 0), Vector3i(2, 11, 3), band)
	p.box(Vector3i(0, 10, 1), Vector3i(3, 11, 2), band)
	p.box(Vector3i(1, 13, 1), Vector3i(2, 14, 2), M.STEEL) # Valve.
	p.box(Vector3i(0, 14, 1), Vector3i(3, 15, 2), M.STEEL) # Cap.
	p.box(Vector3i(1, 1, 0), Vector3i(2, 3, 1), M.PLASTIC) # Label.


## A wooden crate on a single chain from a ceiling plate: crate y 0-8, hook y 8, chain y 9-20,
## plate y 20 (the top, flush with the ceiling).
static func crate_hanging(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 8, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(8, 8, 8), M.WOOD)
	for y in [1, 4, 6]:
		p.box(Vector3i(0, y, 0), Vector3i(8, y + 1, 8), M.PLANK)
	p.box(Vector3i(3, 8, 3), Vector3i(5, 9, 5), M.METAL) # Hook plate.
	_chain(p, 4, 4, 9, 20)
	p.box(Vector3i(3, 20, 3), Vector3i(6, 21, 6), M.STEEL) # Ceiling plate.


## A pallet of concrete blocks on a single chain: pallet y 0, load y 1-6, chain y 7-17, plate y 17.
static func pallet_hanging(p: Props, o: Vector3i) -> void:
	p.begin(o, 10, 10, P.NORTH)
	for x in [0, 4, 8]:
		p.box(Vector3i(x, 0, 0), Vector3i(x + 2, 1, 10), M.WOOD)
	p.box(Vector3i(1, 1, 1), Vector3i(9, 6, 9), M.CONCRETE)
	p.box(Vector3i(1, 3, 1), Vector3i(9, 4, 9), M.CONCRETE_PANEL)
	p.box(Vector3i(4, 6, 0), Vector3i(6, 7, 10), M.STEEL) # Strap over the top.
	_chain(p, 5, 5, 7, 17)
	p.box(Vector3i(4, 17, 4), Vector3i(7, 18, 7), M.STEEL)


## A one-voxel chain column of STEEL at (x, z) from y0 to y1 (STEEL, not METAL: a shot must cut it).
static func _chain(p: Props, x: int, z: int, y0: int, y1: int) -> void:
	p.box(Vector3i(x, y0, z), Vector3i(x + 1, y1, z + 1), M.STEEL)


# --- Flipped furniture ---------------------------------------------------------------------------

## The base pack's table (top at y 6, legs at the corners) tipped forward: the top stands at z = 0,
## w wide and d tall; the legs run back along z from it at its corners.
static func table_flipped(p: Props, o: Vector3i, w: int, d: int) -> void:
	p.begin(o, w, d, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(w, d, 1), M.WOOD)
	for x in [0, w - 1]:
		for y in [0, d - 1]:
			p.box(Vector3i(x, y, 1), Vector3i(x + 1, y + 1, mini(7, d)), M.STEEL)


## The base pack's desk (top at y 7, a drawer stack at the left back, a steel side panel at the
## right) tipped forward: top at z = 0, the drawer stack and side panel running back, the computer
## knocked onto the floor behind it.
static func desk_flipped(p: Props, o: Vector3i, w: int, with_computer: bool) -> void:
	p.begin(o, w, 7, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(w, 7, 1), M.WOOD)
	p.box(Vector3i(0, 3, 1), Vector3i(4, 7, 7), M.WOOD) # Drawer stack.
	p.box(Vector3i(1, 2, 2), Vector3i(3, 3, 3), M.STEEL) # Its handle.
	p.box(Vector3i(w - 1, 0, 1), Vector3i(w, 7, 7), M.STEEL) # Side panel.
	if with_computer:
		p.box(Vector3i(w / 2 - 2, 0, 3), Vector3i(w / 2 + 2, 1, 6), M.RUBBER) # Monitor, face down.
		p.box(Vector3i(w / 2 - 1, 0, 2), Vector3i(w / 2 + 1, 1, 3), M.STEEL)


# --- Toys ----------------------------------------------------------------------------------------

## A boombox: a black body, two speaker cones, a tuning strip, a handle and an antenna.
static func radio(p: Props, o: Vector3i) -> void:
	p.begin(o, 7, 3, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(7, 4, 3), M.RUBBER)
	p.box(Vector3i(0, 1, 0), Vector3i(2, 3, 1), M.HATCH) # Speakers.
	p.box(Vector3i(5, 1, 0), Vector3i(7, 3, 1), M.HATCH)
	p.box(Vector3i(3, 2, 0), Vector3i(4, 3, 1), M.SCREEN) # Dial.
	p.box(Vector3i(2, 3, 0), Vector3i(5, 4, 1), M.STEEL) # Buttons.
	p.box(Vector3i(1, 4, 1), Vector3i(2, 5, 2), M.STEEL) # Handle.
	p.box(Vector3i(5, 4, 1), Vector3i(6, 5, 2), M.STEEL)
	p.box(Vector3i(1, 5, 1), Vector3i(6, 6, 2), M.STEEL)
	p.box(Vector3i(6, 4, 2), Vector3i(7, 9, 3), M.STEEL) # Antenna.


## A jukebox: a wooden cabinet with a rounded top, a lit arch, a glass record window and a grille.
static func jukebox(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 5, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(8, 14, 5), M.WOOD)
	p.box(Vector3i(1, 14, 0), Vector3i(7, 15, 5), M.WOOD)
	p.box(Vector3i(2, 15, 0), Vector3i(6, 16, 5), M.WOOD)
	p.box(Vector3i(0, 12, 0), Vector3i(1, 14, 1), M.LAMP) # Lit arch.
	p.box(Vector3i(7, 12, 0), Vector3i(8, 14, 1), M.LAMP)
	p.box(Vector3i(1, 14, 0), Vector3i(2, 15, 1), M.LAMP)
	p.box(Vector3i(6, 14, 0), Vector3i(7, 15, 1), M.LAMP)
	p.box(Vector3i(2, 15, 0), Vector3i(6, 16, 1), M.LAMP)
	p.box(Vector3i(2, 9, 0), Vector3i(6, 13, 1), M.GLASS) # Window.
	p.box(Vector3i(3, 10, 1), Vector3i(5, 12, 2), M.RUBBER) # Record.
	p.box(Vector3i(1, 7, 0), Vector3i(7, 8, 1), M.SCREEN) # Selector strip.
	for x in range(1, 7, 2):
		p.box(Vector3i(x, 1, 0), Vector3i(x + 1, 6, 1), M.HATCH) # Grille.


## A snack machine with a glass front (shoot it for a snack, LevelPlay): a steel cabinet, rows of
## colored snacks behind the glass, a lit keypad and the dispensing slot.
static func vending_glass(p: Props, o: Vector3i) -> void:
	p.begin(o, 9, 8, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(9, 20, 8), M.STEEL)
	p.box(Vector3i(1, 5, 0), Vector3i(6, 18, 3), M.AIR)
	var colors := [M.PLASTIC, M.WARNING, M.RED_PAINT, M.CLOTH, M.WALL_LOWER]
	for row in 4:
		var y := 6 + row * 3
		p.box(Vector3i(1, y - 1, 1), Vector3i(6, y, 3), M.STEEL) # Shelf.
		for x in range(1, 6):
			p.box(Vector3i(x, y, 2), Vector3i(x + 1, y + 2, 3), colors[(x + row) % colors.size()])
	p.box(Vector3i(1, 5, 0), Vector3i(6, 18, 1), M.GLASS) # The front.
	p.box(Vector3i(7, 10, 0), Vector3i(8, 13, 1), M.SCREEN) # Keypad.
	p.box(Vector3i(1, 1, 0), Vector3i(6, 3, 1), M.RUBBER) # Slot.
