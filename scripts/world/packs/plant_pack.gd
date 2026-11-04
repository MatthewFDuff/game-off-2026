extends RefCounted
## Utility plant props (docs/prop-build-plan.md D2): pumps, tanks, pipe gallery, valve stand,
## cooling tower, catwalk, boiler, water heater, electrical gear. Floor props except the breaker
## panel, junction box and fuse box (wall: back plate at the high z edge, front at z = 0).
## The pipe gallery and catwalk are 10-voxel modules along x with the cross section symmetric across z,
## so they line up on the 1 m grid in any facing. The catwalk deck top is at y = 12 and is walkable.
## USES stays empty: the interactables package wires the switches, panels and cabinets later.

const P := preload("res://scripts/world/props.gd")
const M := preload("res://scripts/voxel/voxel_materials.gd")

const CATEGORY := "Plant"
const MOUNTS := {"breaker_panel": "wall", "junction_box": "wall", "fuse_box": "wall"}
const VALUES := {
	"pump_housing": 1100, "water_tank": 800, "pipe_gallery": 350, "valve_stand": 300, "cooling_tower": 2500,
	"catwalk": 600, "boiler": 2200, "water_heater": 500, "electrical_cabinet": 700, "breaker_panel": 450,
	"junction_box": 80, "fuse_box": 120, "transformer": 3000, "compressor": 1600,
}
const USES := {}


static func entries(add: Callable) -> void:
	add.call("pump_housing", func(p: Props, o: Vector3i) -> void: pump_housing(p, o))
	add.call("water_tank_round", func(p: Props, o: Vector3i) -> void: tank_round(p, o))
	add.call("water_tank_square", func(p: Props, o: Vector3i) -> void: tank_square(p, o))
	add.call("pipe_gallery_segment", func(p: Props, o: Vector3i) -> void: pipe_gallery(p, o))
	add.call("valve_stand", func(p: Props, o: Vector3i) -> void: valve_stand(p, o))
	add.call("cooling_tower_stack", func(p: Props, o: Vector3i) -> void: cooling_tower(p, o))
	add.call("catwalk_segment", func(p: Props, o: Vector3i) -> void: catwalk(p, o))
	add.call("boiler", func(p: Props, o: Vector3i) -> void: boiler(p, o))
	add.call("water_heater", func(p: Props, o: Vector3i) -> void: water_heater(p, o))
	add.call("electrical_cabinet", func(p: Props, o: Vector3i) -> void: electrical_cabinet(p, o))
	add.call("breaker_panel", func(p: Props, o: Vector3i) -> void: breaker_panel(p, o))
	add.call("junction_box", func(p: Props, o: Vector3i) -> void: junction_box(p, o))
	add.call("fuse_box", func(p: Props, o: Vector3i) -> void: fuse_box(p, o))
	add.call("transformer", func(p: Props, o: Vector3i) -> void: transformer(p, o))
	add.call("compressor", func(p: Props, o: Vector3i) -> void: compressor(p, o))


## Fills the voxel columns of a disc (centre cx, cz; radius r) between y0 and y1.
static func _disc(p: Props, cx: float, cz: float, r: float, y0: int, y1: int, material: int, size: int) -> void:
	for z in size:
		for x in size:
			if Vector2(x + 0.5 - cx, z + 0.5 - cz).length() <= r:
				p.box(Vector3i(x, y0, z), Vector3i(x + 1, y1, z + 1), material)


## A gauge: a dark dial with a lit needle voxel.
static func _gauge(p: Props, at: Vector3i) -> void:
	p.box(at, at + Vector3i(2, 2, 1), M.RUBBER)
	p.box(at + Vector3i(1, 1, 0), at + Vector3i(2, 2, 1), M.EMERGENCY)


## A pump: a pipe-coloured casing with flanged ports on the left, a motor on the right, on a base plate.
static func pump_housing(p: Props, o: Vector3i) -> void:
	p.begin(o, 12, 8, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(12, 1, 8), M.STEEL)
	p.box(Vector3i(1, 1, 1), Vector3i(6, 6, 7), M.PIPE)
	p.box(Vector3i(2, 6, 3), Vector3i(5, 8, 5), M.PIPE) # Discharge port up.
	p.box(Vector3i(2, 8, 2), Vector3i(5, 9, 6), M.STEEL)
	p.box(Vector3i(0, 2, 3), Vector3i(1, 5, 5), M.STEEL)
	p.box(Vector3i(6, 2, 3), Vector3i(7, 5, 5), M.STEEL) # Coupling.
	p.box(Vector3i(7, 1, 1), Vector3i(12, 6, 7), M.METAL)
	for x in range(8, 12, 2):
		p.box(Vector3i(x, 1, 0), Vector3i(x + 1, 6, 1), M.STEEL) # Motor fins.
		p.box(Vector3i(x, 1, 7), Vector3i(x + 1, 6, 8), M.STEEL)
	p.box(Vector3i(10, 6, 3), Vector3i(11, 7, 5), M.WARNING) # Terminal box.


## A round water tank: a drum on legs with two bands, a top lid and a ladder.
static func tank_round(p: Props, o: Vector3i) -> void:
	p.begin(o, 14, 14, P.NORTH)
	for pt in [Vector3i(3, 0, 3), Vector3i(10, 0, 3), Vector3i(3, 0, 10), Vector3i(10, 0, 10)]:
		p.box(pt, pt + Vector3i(1, 3, 1), M.STEEL)
	_disc(p, 7, 7, 7, 3, 4, M.STEEL, 14)
	_disc(p, 7, 7, 7, 4, 18, M.METAL, 14)
	_disc(p, 7, 7, 7, 8, 9, M.STEEL, 14)
	_disc(p, 7, 7, 7, 14, 15, M.STEEL, 14)
	_disc(p, 7, 7, 5, 18, 19, M.STEEL, 14)
	_disc(p, 7, 7, 2, 19, 20, M.STEEL, 14)
	p.box(Vector3i(7, 3, 0), Vector3i(8, 18, 1), M.STEEL) # Ladder rail on the front.
	for y in range(4, 18, 2):
		p.box(Vector3i(6, y, 0), Vector3i(9, y + 1, 1), M.STEEL)


## A square water tank: a plastic box on a steel frame with a lid, a level strip and a pipe.
static func tank_square(p: Props, o: Vector3i) -> void:
	p.begin(o, 14, 14, P.NORTH)
	for x in [0, 13]:
		for z in [0, 13]:
			p.box(Vector3i(x, 0, z), Vector3i(x + 1, 4, z + 1), M.STEEL)
	p.box(Vector3i(0, 4, 0), Vector3i(14, 5, 14), M.STEEL)
	p.box(Vector3i(0, 5, 0), Vector3i(14, 17, 14), M.PLASTIC)
	p.box(Vector3i(0, 17, 0), Vector3i(14, 18, 14), M.STEEL)
	p.box(Vector3i(2, 18, 2), Vector3i(6, 19, 6), M.STEEL) # Manhole.
	p.box(Vector3i(6, 6, 0), Vector3i(8, 16, 1), M.GLASS) # Level strip.
	p.box(Vector3i(6, 6, 0), Vector3i(8, 11, 1), M.WATER)
	p.box(Vector3i(10, 1, 0), Vector3i(11, 8, 1), M.PIPE) # Outlet.


## A pipe gallery module: two pipes (one big, one small) on bracket posts, running west to east.
## 10 x 10 x 11, symmetric across z.
static func pipe_gallery(p: Props, o: Vector3i) -> void:
	p.begin(o, 10, 10, P.NORTH)
	for x in [1, 8]:
		p.box(Vector3i(x, 0, 1), Vector3i(x + 1, 6, 2), M.STEEL)
		p.box(Vector3i(x, 0, 8), Vector3i(x + 1, 6, 9), M.STEEL)
		p.box(Vector3i(x, 5, 1), Vector3i(x + 1, 6, 9), M.STEEL) # Cross bracket.
		p.box(Vector3i(x - 1, 0, 0), Vector3i(x + 2, 1, 10), M.STEEL) # Foot.
	p.box(Vector3i(0, 6, 1), Vector3i(10, 10, 4), M.PIPE) # Big pipe on the bracket.
	p.box(Vector3i(0, 6, 6), Vector3i(10, 10, 9), M.STEEL)
	p.box(Vector3i(0, 10, 4), Vector3i(10, 11, 6), M.METAL) # Bridge conduit between.
	for x in [0, 9]:
		p.box(Vector3i(x, 6, 1), Vector3i(x + 1, 10, 4), M.METAL) # Flanges.
		p.box(Vector3i(x, 6, 6), Vector3i(x + 1, 10, 9), M.METAL)


## A valve stand: a pipe stub on a base with a yoke and a red wheel, 6 x 6 x 14.
static func valve_stand(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 6, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(6, 1, 6), M.STEEL)
	p.box(Vector3i(2, 1, 2), Vector3i(4, 7, 4), M.PIPE)
	p.box(Vector3i(0, 4, 2), Vector3i(6, 7, 4), M.PIPE) # Through pipe.
	p.box(Vector3i(2, 7, 2), Vector3i(4, 10, 4), M.STEEL)
	p.box(Vector3i(3, 10, 2), Vector3i(4, 12, 3), M.STEEL)
	p.box(Vector3i(0, 12, 0), Vector3i(6, 13, 6), M.EMERGENCY) # Wheel rim.
	p.box(Vector3i(1, 12, 1), Vector3i(5, 13, 5), M.AIR)
	p.box(Vector3i(0, 12, 2), Vector3i(6, 13, 4), M.EMERGENCY)
	p.box(Vector3i(2, 12, 0), Vector3i(4, 13, 6), M.EMERGENCY)
	p.box(Vector3i(2, 10, 2), Vector3i(4, 12, 4), M.STEEL)


## A cooling tower stack: a tapering concrete chimney with a rim, a dark mouth and a service ladder.
static func cooling_tower(p: Props, o: Vector3i) -> void:
	p.begin(o, 18, 18, P.NORTH)
	for y in 30:
		var r := 8.6 - 2.2 * sin(float(y) / 30.0 * PI) # Waist near the middle.
		if y < 2:
			r = 8.9
		_disc(p, 9, 9, r, y, y + 1, M.CONCRETE if y < 27 else M.STEEL, 18)
	for y in [8, 20]:
		_disc(p, 9, 9, 8.6 - 2.2 * sin(float(y) / 30.0 * PI), y, y + 1, M.CONCRETE_PANEL, 18)
	_disc(p, 9, 9, 5.0, 29, 30, M.AIR, 18)
	_disc(p, 9, 9, 5.0, 28, 29, M.RUBBER, 18)
	p.box(Vector3i(2, 0, 8), Vector3i(3, 3, 10), M.HAZARD_STRIPES) # Hazard on the base.


## A catwalk module: 10 x 10 x 22, deck top at y = 12 (walkable), deck of diamond plate on frame legs,
## a kick strip and a two-bar rail along each long side. The ends are open.
static func catwalk(p: Props, o: Vector3i) -> void:
	p.begin(o, 10, 10, P.NORTH)
	for x in [0, 9]:
		for z in [0, 9]:
			p.box(Vector3i(x, 0, z), Vector3i(x + 1, 11, z + 1), M.STEEL)
	p.box(Vector3i(0, 5, 0), Vector3i(10, 6, 1), M.STEEL) # Cross braces along the sides.
	p.box(Vector3i(0, 5, 9), Vector3i(10, 6, 10), M.STEEL)
	p.box(Vector3i(0, 10, 0), Vector3i(10, 11, 10), M.STEEL) # Frame under the deck.
	p.box(Vector3i(0, 11, 0), Vector3i(10, 12, 10), M.DIAMOND_PLATE)
	for z in [0, 9]:
		p.box(Vector3i(0, 12, z), Vector3i(10, 13, z + 1), M.HAZARD_STRIPES) # Kick strip.
		for x in [0, 5, 9]:
			p.box(Vector3i(x, 13, z), Vector3i(x + 1, 22, z + 1), M.STEEL)
		p.box(Vector3i(0, 17, z), Vector3i(10, 18, z + 1), M.STEEL)
		p.box(Vector3i(0, 21, z), Vector3i(10, 22, z + 1), M.WARNING)


## A boiler: an upright drum on a firebox base with a flue, gauges and a front door.
static func boiler(p: Props, o: Vector3i) -> void:
	p.begin(o, 14, 12, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(14, 7, 12), M.METAL) # Firebox.
	p.box(Vector3i(0, 7, 0), Vector3i(14, 8, 12), M.STEEL)
	p.box(Vector3i(1, 2, 0), Vector3i(7, 6, 1), M.RUBBER) # Firebox door, burner glow inside.
	p.box(Vector3i(2, 3, 0), Vector3i(6, 4, 1), M.EMBER)
	p.box(Vector3i(7, 2, 0), Vector3i(8, 6, 1), M.STEEL)
	p.box(Vector3i(1, 8, 1), Vector3i(13, 17, 11), M.PIPE) # Drum.
	for y in [10, 14]:
		p.box(Vector3i(1, y, 1), Vector3i(13, y + 1, 11), M.STEEL)
	p.box(Vector3i(1, 17, 1), Vector3i(13, 18, 11), M.STEEL)
	p.box(Vector3i(8, 18, 4), Vector3i(12, 24, 8), M.METAL) # Flue.
	p.box(Vector3i(7, 24, 3), Vector3i(13, 25, 9), M.STEEL)
	_gauge(p, Vector3i(3, 12, 0))
	_gauge(p, Vector3i(7, 12, 0))
	p.box(Vector3i(10, 8, 0), Vector3i(11, 14, 1), M.STEEL) # Sight tube.
	p.box(Vector3i(10, 9, 0), Vector3i(11, 12, 1), M.GLASS)
	p.box(Vector3i(12, 1, 0), Vector3i(13, 7, 1), M.WARNING)


## A domestic water heater: a white round tank with pipes and a thermostat dial, 8 x 8 x 16.
static func water_heater(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 8, P.NORTH)
	_disc(p, 4, 4, 4, 0, 1, M.STEEL, 8)
	_disc(p, 4, 4, 4, 1, 14, M.PLASTIC, 8)
	_disc(p, 4, 4, 4, 14, 15, M.STEEL, 8)
	p.box(Vector3i(2, 15, 3), Vector3i(3, 16, 4), M.PIPE)
	p.box(Vector3i(5, 15, 3), Vector3i(6, 16, 4), M.EMERGENCY) # Hot out.
	p.box(Vector3i(2, 14, 3), Vector3i(3, 15, 4), M.PIPE)
	p.box(Vector3i(5, 14, 3), Vector3i(6, 15, 4), M.EMERGENCY)
	p.box(Vector3i(3, 4, 0), Vector3i(5, 6, 1), M.METAL) # Access panel and dial.
	p.box(Vector3i(3, 5, 0), Vector3i(4, 6, 1), M.EMERGENCY)
	p.box(Vector3i(6, 14, 5), Vector3i(7, 15, 6), M.PIPE)


## A floor electrical cabinet: a tall steel locker with a door, handle, louvres and a warning label.
static func electrical_cabinet(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 6, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(8, 1, 6), M.STEEL)
	p.box(Vector3i(0, 1, 0), Vector3i(8, 20, 6), M.METAL)
	p.box(Vector3i(0, 20, 0), Vector3i(8, 21, 6), M.STEEL)
	p.box(Vector3i(4, 2, 0), Vector3i(5, 19, 1), M.STEEL) # Door seam.
	p.box(Vector3i(3, 10, 0), Vector3i(4, 13, 1), M.STEEL) # Handle.
	for y in range(2, 5):
		p.box(Vector3i(1, y, 0), Vector3i(3, y + 1, 1), M.RUBBER)
	p.box(Vector3i(5, 14, 0), Vector3i(7, 18, 1), M.WARNING)
	p.box(Vector3i(5, 15, 0), Vector3i(7, 17, 1), M.EMERGENCY)


## A wall breaker panel (10 x 2 x 14): a steel box, a door with two columns of breaker switches.
static func breaker_panel(p: Props, o: Vector3i) -> void:
	p.begin(o, 10, 2, P.NORTH)
	p.box(Vector3i(0, 0, 1), Vector3i(10, 14, 2), M.STEEL)
	p.box(Vector3i(0, 0, 0), Vector3i(10, 14, 1), M.METAL)
	p.box(Vector3i(1, 1, 0), Vector3i(9, 13, 1), M.RUBBER)
	for y in range(2, 12, 2):
		p.box(Vector3i(2, y, 0), Vector3i(4, y + 1, 1), M.PLASTIC)
		p.box(Vector3i(6, y, 0), Vector3i(8, y + 1, 1), M.PLASTIC)
	p.box(Vector3i(4, 6, 0), Vector3i(6, 8, 1), M.STEEL) # Main breaker.
	p.box(Vector3i(4, 7, 0), Vector3i(6, 8, 1), M.EMERGENCY)
	p.box(Vector3i(0, 13, 0), Vector3i(10, 14, 1), M.WARNING)


## A wall junction box (6 x 2 x 6): a steel lid with screws and a conduit stub above.
static func junction_box(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 2, P.NORTH)
	p.box(Vector3i(0, 0, 1), Vector3i(6, 6, 2), M.STEEL)
	p.box(Vector3i(0, 0, 0), Vector3i(6, 6, 1), M.METAL)
	for pt in [Vector3i(0, 0, 0), Vector3i(5, 0, 0), Vector3i(0, 5, 0), Vector3i(5, 5, 0)]:
		p.box(pt, pt + Vector3i(1, 1, 1), M.STEEL)
	p.box(Vector3i(2, 2, 0), Vector3i(4, 4, 1), M.WARNING)


## A wall fuse box (8 x 2 x 10): a hinged lid shut over a row of fuse caps, a warning band on top.
static func fuse_box(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 2, P.NORTH)
	p.box(Vector3i(0, 0, 1), Vector3i(8, 10, 2), M.STEEL)
	p.box(Vector3i(0, 0, 0), Vector3i(8, 10, 1), M.METAL)
	p.box(Vector3i(1, 2, 0), Vector3i(7, 7, 1), M.RUBBER)
	for x in [2, 4]:
		p.box(Vector3i(x, 3, 0), Vector3i(x + 1, 6, 1), M.CLOTH)
	p.box(Vector3i(6, 3, 0), Vector3i(7, 6, 1), M.LIQUID_GREEN)
	p.box(Vector3i(0, 8, 0), Vector3i(8, 9, 1), M.WARNING)
	p.box(Vector3i(3, 0, 0), Vector3i(5, 1, 1), M.STEEL) # Latch.


## A transformer: a finned tank on a plinth with three porcelain bushings and a warning label.
static func transformer(p: Props, o: Vector3i) -> void:
	p.begin(o, 14, 10, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(14, 2, 10), M.CONCRETE)
	p.box(Vector3i(1, 2, 1), Vector3i(13, 13, 9), M.METAL)
	for x in range(2, 13, 2):
		p.box(Vector3i(x, 3, 0), Vector3i(x + 1, 12, 1), M.STEEL) # Cooling fins.
		p.box(Vector3i(x, 3, 9), Vector3i(x + 1, 12, 10), M.STEEL)
	p.box(Vector3i(0, 13, 0), Vector3i(14, 14, 10), M.STEEL)
	for x in [3, 6, 9]:
		p.box(Vector3i(x, 14, 4), Vector3i(x + 2, 17, 6), M.PLASTIC)
		p.box(Vector3i(x, 17, 4), Vector3i(x + 2, 18, 6), M.STEEL)
	p.box(Vector3i(5, 6, 0), Vector3i(9, 10, 1), M.WARNING)
	p.box(Vector3i(6, 7, 0), Vector3i(8, 9, 1), M.EMERGENCY)


## A compressor: a horizontal air receiver on a base with a motor and pump on top, a gauge on the end.
static func compressor(p: Props, o: Vector3i) -> void:
	p.begin(o, 16, 8, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(16, 1, 8), M.STEEL)
	for x in [2, 13]:
		p.box(Vector3i(x, 1, 1), Vector3i(x + 1, 3, 7), M.STEEL) # Cradles.
	for x in 16:
		for z in 8:
			for y in range(3, 9):
				if Vector2(z + 0.5 - 4.0, y + 0.5 - 5.0).length() <= 3.2 and x >= 1 and x < 15:
					p.box(Vector3i(x, y, z), Vector3i(x + 1, y + 1, z + 1), M.EMERGENCY if x < 2 else M.PIPE)
	p.box(Vector3i(3, 9, 2), Vector3i(8, 13, 6), M.METAL) # Motor.
	p.box(Vector3i(9, 9, 3), Vector3i(13, 12, 5), M.STEEL) # Pump head.
	p.box(Vector3i(10, 12, 3), Vector3i(12, 13, 5), M.RUBBER)
	_gauge(p, Vector3i(14, 5, 0))
	p.box(Vector3i(2, 13, 3), Vector3i(3, 14, 5), M.WARNING)
