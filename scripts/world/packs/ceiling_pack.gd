extends RefCounted
## Ceiling and plenum props and light fixtures (docs/prop-gaps.md section 1). Every prop here hangs
## (mount "ceiling"; fixture_bulkhead is "any": a wall or a ceiling) and is drawn from y = 0 up with
## its top layer against the ceiling, so placed under a ceiling its top is flush with it.
##
## Run pieces (ducts, pipe bundles, cable trays, the gantry rail, the strip light) are 10-voxel
## modules along x with a cross section symmetric across z and at the same depth under the ceiling,
## so pieces line up on the 1 m grid in any facing: a straight runs west to east, a corner turns
## from the west side to the south side, a tee adds the south side, a riser comes down out of the
## ceiling and runs east. Pieces with something hanging lower (the drip, the sagging cable, the
## valve wheel, the hanging tile) are taller, with the run at the same depth under the ceiling.
##
## No CHAIN or lagging material exists yet: chains are STEEL and METAL links, lagging is CLOTH
## (the ceiling_cloud sac wears the same CLOTH, docs/prop-build-plan.md A.5).

const P := preload("res://scripts/world/props.gd")
const M := preload("res://scripts/voxel/voxel_materials.gd")

const CATEGORY := "Ceiling"
const MOUNTS := {
	"duct_": "ceiling", "pipe_bundle": "ceiling", "pipe_valve": "ceiling", "cable_tray": "ceiling",
	"ceiling_tile": "ceiling", "vent_diffuser": "ceiling", "return_grille": "ceiling", "extractor_fan": "ceiling",
	"sprinkler_head": "ceiling", "smoke_detector": "ceiling", "speaker_horn": "ceiling", "security_camera": "ceiling",
	"hazard_beacon": "ceiling", "chain_hoist": "ceiling", "gantry_rail": "ceiling", "service_hatch": "ceiling",
	"fixture_troffer": "ceiling", "fixture_strip": "ceiling", "fixture_pendant": "ceiling", "fixture_emergency": "ceiling",
	"fixture_dead": "ceiling", "fixture_bulkhead": "any",
}
const VALUES := {
	"duct_": 150, "duct_insulated": 220, "duct_end_grille": 120, "pipe_bundle": 300, "pipe_valve": 450,
	"cable_tray": 180, "ceiling_tile": 40, "vent_diffuser": 60, "return_grille": 50, "extractor_fan": 600,
	"sprinkler_head": 45, "smoke_detector": 35, "speaker_horn": 140, "security_camera": 1200, "hazard_beacon": 180,
	"chain_hoist": 1500, "gantry_rail": 700, "service_hatch": 250,
	"fixture_troffer": 160, "fixture_strip": 90, "fixture_bulkhead": 120, "fixture_pendant": 110,
	"fixture_emergency": 140, "fixture_dead": 30,
}
const USES := {}

## Duct run: 7 tall (flange y 0-5, body y 1-4, hanger y 5-6), body z 2-7, flange z 1-8.
const DUCT_H := 7
## Pipe bundle: 5 tall (bracket y 0, pipes y 1-2, rods to y 4), pipes at z 1-2, 4-5, 7-8.
const PIPE_H := 5
const PIPES := [[1, M.PIPE], [4, M.STEEL], [7, M.PLASTIC]]
## Cable tray: 6 tall (rungs y 0, cable y 1-2, rods y 2-5), rails at z 1 and 8.
const TRAY_H := 6
## Ceiling tile grid: tiles and T-bars at y 0, wires up to y 3 (a 3-voxel plenum).
const TILE_H := 4


static func entries(add: Callable) -> void:
	add.call("duct_straight", func(p: Props, o: Vector3i) -> void: duct(p, o, "straight"))
	add.call("duct_corner", func(p: Props, o: Vector3i) -> void: duct(p, o, "corner"))
	add.call("duct_tee", func(p: Props, o: Vector3i) -> void: duct(p, o, "tee"))
	add.call("duct_riser", func(p: Props, o: Vector3i) -> void: duct(p, o, "riser"))
	add.call("duct_insulated", func(p: Props, o: Vector3i) -> void: duct(p, o, "insulated"))
	add.call("duct_drip", func(p: Props, o: Vector3i) -> void: duct(p, o, "drip"))
	add.call("duct_end_grille", func(p: Props, o: Vector3i) -> void: duct(p, o, "end"))
	add.call("pipe_bundle_straight", func(p: Props, o: Vector3i) -> void: pipe_bundle(p, o, false))
	add.call("pipe_bundle_corner", func(p: Props, o: Vector3i) -> void: pipe_bundle(p, o, true))
	add.call("pipe_valve", func(p: Props, o: Vector3i) -> void: pipe_valve(p, o))
	add.call("cable_tray_straight", func(p: Props, o: Vector3i) -> void: cable_tray(p, o, "straight"))
	add.call("cable_tray_corner", func(p: Props, o: Vector3i) -> void: cable_tray(p, o, "corner"))
	add.call("cable_tray_sag", func(p: Props, o: Vector3i) -> void: cable_tray(p, o, "sag"))
	add.call("ceiling_tile_grid", func(p: Props, o: Vector3i) -> void: ceiling_tiles(p, o, ""))
	add.call("ceiling_tile_missing", func(p: Props, o: Vector3i) -> void: ceiling_tiles(p, o, "missing"))
	add.call("ceiling_tile_hanging", func(p: Props, o: Vector3i) -> void: ceiling_tiles(p, o, "hanging"))
	add.call("vent_diffuser", func(p: Props, o: Vector3i) -> void: vent_diffuser(p, o))
	add.call("return_grille", func(p: Props, o: Vector3i) -> void: return_grille(p, o))
	add.call("extractor_fan", func(p: Props, o: Vector3i) -> void: extractor_fan(p, o))
	add.call("sprinkler_head", func(p: Props, o: Vector3i) -> void: sprinkler_head(p, o))
	add.call("smoke_detector", func(p: Props, o: Vector3i) -> void: smoke_detector(p, o))
	add.call("speaker_horn", func(p: Props, o: Vector3i) -> void: speaker_horn(p, o))
	add.call("security_camera", func(p: Props, o: Vector3i) -> void: security_camera(p, o))
	add.call("hazard_beacon", func(p: Props, o: Vector3i) -> void: hazard_beacon(p, o))
	add.call("chain_hoist", func(p: Props, o: Vector3i) -> void: chain_hoist(p, o))
	add.call("gantry_rail", func(p: Props, o: Vector3i) -> void: gantry_rail(p, o))
	add.call("service_hatch", func(p: Props, o: Vector3i) -> void: service_hatch(p, o))
	add.call("fixture_troffer", func(p: Props, o: Vector3i) -> void: troffer(p, o, false))
	add.call("fixture_strip", func(p: Props, o: Vector3i) -> void: strip_light(p, o))
	add.call("fixture_bulkhead", func(p: Props, o: Vector3i) -> void: bulkhead(p, o))
	add.call("fixture_pendant", func(p: Props, o: Vector3i) -> void: pendant(p, o))
	add.call("fixture_emergency", func(p: Props, o: Vector3i) -> void: emergency_light(p, o))
	add.call("fixture_dead", func(p: Props, o: Vector3i) -> void: troffer(p, o, true))


# --- Ducts -------------------------------------------------------------------------------------

## A 10 x 10 duct module. kind: straight, corner, tee, riser, insulated, drip (a drip hangs 4 below),
## end (closed with a grille at the east end).
static func duct(p: Props, o: Vector3i, kind: String) -> void:
	p.begin(o, 10, 10, P.NORTH)
	var y0 := 4 if kind == "drip" else 0
	match kind:
		"corner":
			_duct_x(p, 0, 8, y0, M.METAL)
			_duct_z(p, 2, 10, y0, M.METAL)
			_flange(p, 0, -1, y0)
			_flange(p, -1, 9, y0)
			_mouth(p, 0, -1, y0)
			_mouth(p, -1, 9, y0)
			_hanger(p, Vector3i(4, 0, 4), y0)
		"tee":
			_duct_x(p, 0, 10, y0, M.METAL)
			_duct_z(p, 5, 10, y0, M.METAL)
			for x in [0, 9]:
				_flange(p, x, -1, y0)
				_mouth(p, x, -1, y0)
			_flange(p, -1, 9, y0)
			_mouth(p, -1, 9, y0)
			_hanger(p, Vector3i(2, 0, 4), y0)
			_hanger(p, Vector3i(7, 0, 4), y0)
		"riser":
			_duct_x(p, 2, 10, y0, M.METAL)
			p.box(Vector3i(2, y0 + 1, 2), Vector3i(8, DUCT_H, 8), M.METAL)
			p.box(Vector3i(1, DUCT_H - 1, 1), Vector3i(9, DUCT_H, 9), M.STEEL) # Collar at the ceiling.
			_flange(p, 9, -1, y0)
			_mouth(p, 9, -1, y0)
		"insulated":
			p.box(Vector3i(0, y0, 1), Vector3i(10, y0 + 6, 9), M.CLOTH)
			for x in [2, 7]:
				p.box(Vector3i(x, y0, 1), Vector3i(x + 1, y0 + 6, 9), M.STEEL) # Lagging bands.
			for x in [0, 9]:
				_mouth(p, x, -1, y0)
			_hanger(p, Vector3i(2, 0, 4), y0)
			_hanger(p, Vector3i(7, 0, 4), y0)
		_:
			_duct_x(p, 0, 10, y0, M.METAL)
			_flange(p, 0, -1, y0)
			_mouth(p, 0, -1, y0)
			if kind == "end":
				_flange(p, 9, -1, y0)
				for z in range(3, 7):
					p.box(Vector3i(9, y0 + 2, z), Vector3i(10, y0 + 4, z + 1), M.RUBBER if z % 2 == 0 else M.STEEL)
			else:
				_flange(p, 9, -1, y0)
				_mouth(p, 9, -1, y0)
			_hanger(p, Vector3i(2, 0, 4), y0)
			_hanger(p, Vector3i(7, 0, 4), y0)
			if kind == "drip":
				p.box(Vector3i(3, y0 + 1, 4), Vector3i(7, y0 + 2, 6), M.PIPE) # Rust stain round the leak.
				p.box(Vector3i(4, y0 - 1, 4), Vector3i(6, y0 + 1, 6), M.WATER)
				p.box(Vector3i(5, 0, 5), Vector3i(6, y0 - 1, 6), M.WATER)


static func _duct_x(p: Props, x0: int, x1: int, y0: int, material: int) -> void:
	p.box(Vector3i(x0, y0 + 1, 2), Vector3i(x1, y0 + 5, 8), material)


static func _duct_z(p: Props, z0: int, z1: int, y0: int, material: int) -> void:
	p.box(Vector3i(2, y0 + 1, z0), Vector3i(8, y0 + 5, z1), material)


## A flange ring across the duct at x (or at z when x is -1).
static func _flange(p: Props, x: int, z: int, y0: int) -> void:
	if x >= 0:
		p.box(Vector3i(x, y0, 1), Vector3i(x + 1, y0 + 6, 9), M.STEEL)
	else:
		p.box(Vector3i(1, y0, z), Vector3i(9, y0 + 6, z + 1), M.STEEL)


## The dark inside of an open duct end at x (or z when x is -1).
static func _mouth(p: Props, x: int, z: int, y0: int) -> void:
	if x >= 0:
		p.box(Vector3i(x, y0 + 2, 3), Vector3i(x + 1, y0 + 4, 7), M.RUBBER)
	else:
		p.box(Vector3i(3, y0 + 2, z), Vector3i(7, y0 + 4, z + 1), M.RUBBER)


## A strap from the duct's top to the ceiling: 1 x 2 at (at.x, at.z).
static func _hanger(p: Props, at: Vector3i, y0: int) -> void:
	p.box(Vector3i(at.x, y0 + 5, at.z), Vector3i(at.x + 1, DUCT_H + y0, at.z + 2), M.STEEL)


# --- Pipes and trays ----------------------------------------------------------------------------

## Three parallel pipes (copper, steel, white plastic) on brackets. corner: they bend concentrically
## from the west side to the south side.
static func pipe_bundle(p: Props, o: Vector3i, corner: bool, y0 := 0) -> void:
	p.begin(o, 10, 10, P.NORTH)
	if not corner:
		for x in [2, 7]:
			p.box(Vector3i(x, y0, 0), Vector3i(x + 1, y0 + 1, 10), M.STEEL)
			for z in [0, 9]:
				p.box(Vector3i(x, y0, z), Vector3i(x + 1, y0 + PIPE_H, z + 1), M.STEEL)
		for pipe: Array in PIPES:
			p.box(Vector3i(0, y0 + 1, pipe[0]), Vector3i(10, y0 + 3, pipe[0] + 2), pipe[1])
		return
	p.box(Vector3i(2, y0, 0), Vector3i(3, y0 + 1, 10), M.STEEL)
	p.box(Vector3i(2, y0, 0), Vector3i(3, y0 + PIPE_H, 1), M.STEEL)
	p.box(Vector3i(0, y0, 8), Vector3i(10, y0 + 1, 9), M.STEEL)
	p.box(Vector3i(9, y0, 8), Vector3i(10, y0 + PIPE_H, 9), M.STEEL)
	for pipe: Array in PIPES:
		var a: int = pipe[0]
		var c := 8 - a # The outer pipe turns last, so they never cross.
		p.box(Vector3i(0, y0 + 1, a), Vector3i(c + 2, y0 + 3, a + 2), pipe[1])
		p.box(Vector3i(c, y0 + 1, a), Vector3i(c + 2, y0 + 3, 10), pipe[1])


## A straight bundle with a valve wheel hanging under the middle pipe.
static func pipe_valve(p: Props, o: Vector3i) -> void:
	var y0 := 4
	pipe_bundle(p, o, false, y0)
	p.box(Vector3i(5, 0, 5), Vector3i(6, y0 + 1, 6), M.STEEL) # Stem.
	for z in 10:
		for x in 10:
			var r := Vector2(x - 5, z - 5).length()
			if (r >= 2.2 and r <= 3.2) or (r <= 3.0 and (x == 5 or z == 5)):
				p.box(Vector3i(x, 0, z), Vector3i(x + 1, 1, z + 1), M.WARNING)


## A ladder tray of cable. kind: straight, corner (west to south), sag (a loop hanging 4 below).
static func cable_tray(p: Props, o: Vector3i, kind: String) -> void:
	p.begin(o, 10, 10, P.NORTH)
	var y0 := 4 if kind == "sag" else 0
	if kind == "corner":
		p.box(Vector3i(0, y0, 1), Vector3i(9, y0 + 2, 2), M.STEEL) # Outer rail.
		p.box(Vector3i(8, y0, 1), Vector3i(9, y0 + 2, 10), M.STEEL)
		p.box(Vector3i(0, y0, 8), Vector3i(2, y0 + 2, 9), M.STEEL) # Inner rail.
		p.box(Vector3i(1, y0, 8), Vector3i(2, y0 + 2, 10), M.STEEL)
		for x in range(0, 8, 2):
			p.box(Vector3i(x, y0, 1), Vector3i(x + 1, y0 + 1, 9), M.STEEL)
		for z in range(2, 10, 2):
			p.box(Vector3i(1, y0, z), Vector3i(9, y0 + 1, z + 1), M.STEEL)
		p.box(Vector3i(0, y0 + 1, 2), Vector3i(8, y0 + 2, 8), M.RUBBER)
		p.box(Vector3i(2, y0 + 1, 2), Vector3i(8, y0 + 2, 10), M.RUBBER)
		for at in [Vector2i(1, 1), Vector2i(8, 1), Vector2i(8, 8), Vector2i(1, 8)]:
			p.box(Vector3i(at.x, y0 + 2, at.y), Vector3i(at.x + 1, y0 + TRAY_H, at.y + 1), M.STEEL)
		return
	for z in [1, 8]:
		p.box(Vector3i(0, y0, z), Vector3i(10, y0 + 2, z + 1), M.STEEL)
	for x in range(0, 10, 2):
		p.box(Vector3i(x, y0, 1), Vector3i(x + 1, y0 + 1, 9), M.STEEL)
	p.box(Vector3i(0, y0 + 1, 2), Vector3i(10, y0 + 2, 5), M.RUBBER)
	p.box(Vector3i(0, y0 + 1, 5), Vector3i(10, y0 + 2, 6), M.WARNING)
	p.box(Vector3i(0, y0 + 1, 6), Vector3i(10, y0 + 2, 7), M.CLOTH)
	p.box(Vector3i(0, y0 + 1, 7), Vector3i(10, y0 + 2, 8), M.PIPE)
	p.box(Vector3i(0, y0 + 2, 2), Vector3i(10, y0 + 3, 4), M.RUBBER)
	for x in [1, 8]:
		for z in [1, 8]:
			p.box(Vector3i(x, y0 + 2, z), Vector3i(x + 1, y0 + TRAY_H, z + 1), M.STEEL)
	if kind == "sag":
		# A loop of black cable slipped out between the rungs, each column joined to the next.
		var depth := []
		for x in 10:
			var t := (x - 4.5) / 3.5
			depth.append(roundi((y0 + 1) * (1.0 - t * t)) if absf(t) <= 1.0 else 0)
		for x in range(1, 9):
			var shallow: int = mini(depth[x], mini(depth[x - 1], depth[x + 1]))
			p.box(Vector3i(x, y0 + 1 - depth[x], 3), Vector3i(x + 1, y0 + 2 - shallow, 4), M.RUBBER)


# --- Ceiling surface ----------------------------------------------------------------------------

## A 20 x 20 panel of four tiles on a T-bar grid (the bars on its west and north edges and through
## the middle, so panels side by side share them), hung on wires a plenum below the ceiling.
## kind: "" whole, "missing" (one tile gone, the plenum's cable showing), "hanging" (one tile hinged
## down from the middle bar).
static func ceiling_tiles(p: Props, o: Vector3i, kind: String) -> void:
	p.begin(o, 20, 20, P.NORTH)
	var y0 := 6 if kind == "hanging" else 0
	p.box(Vector3i(0, y0, 0), Vector3i(20, y0 + 1, 20), M.PLASTIC)
	for a in [0, 10]:
		p.box(Vector3i(a, y0, 0), Vector3i(a + 1, y0 + 1, 20), M.STEEL)
		p.box(Vector3i(0, y0, a), Vector3i(20, y0 + 1, a + 1), M.STEEL)
	for x in [0, 10]:
		for z in [5, 15]:
			p.box(Vector3i(x, y0 + 1, z), Vector3i(x + 1, y0 + TILE_H, z + 1), M.STEEL)
	if kind == "":
		return
	p.box(Vector3i(1, y0, 1), Vector3i(10, y0 + 1, 10), M.AIR)
	p.box(Vector3i(0, y0 + 2, 5), Vector3i(20, y0 + 3, 6), M.RUBBER) # A cable across the plenum, on the wires.
	if kind == "hanging":
		# Hinged on the middle bar (x 10), swung down toward x 1: each column reaches the next one up.
		var heights := []
		for x in 11:
			heights.append(y0 - roundi((10 - x) * float(y0) / 9.0))
		for x in range(1, 10):
			p.box(Vector3i(x, maxi(heights[x], 0), 1), Vector3i(x + 1, heights[x + 1] + 1, 10), M.PLASTIC)


## A flush square air diffuser: concentric rings of steel and dark slots.
static func vent_diffuser(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 8, P.NORTH)
	p.box(Vector3i(0, 1, 0), Vector3i(8, 2, 8), M.STEEL)
	for r in 4:
		p.box(Vector3i(r, 0, r), Vector3i(8 - r, 1, 8 - r), M.STEEL if r % 2 == 0 else M.RUBBER)


## A long return-air grille: dark slots between steel slats.
static func return_grille(p: Props, o: Vector3i) -> void:
	p.begin(o, 12, 6, P.NORTH)
	p.box(Vector3i(0, 1, 0), Vector3i(12, 2, 6), M.METAL)
	p.box(Vector3i(0, 0, 0), Vector3i(12, 1, 6), M.STEEL)
	for x in range(1, 11):
		if x % 2 == 1:
			p.box(Vector3i(x, 0, 1), Vector3i(x + 1, 1, 5), M.RUBBER)


## An extractor fan: a sheet-metal housing with a round dark throat and a four-blade fan in it.
static func extractor_fan(p: Props, o: Vector3i) -> void:
	p.begin(o, 10, 10, P.NORTH)
	p.box(Vector3i(0, 1, 0), Vector3i(10, 4, 10), M.METAL)
	p.box(Vector3i(0, 0, 0), Vector3i(10, 1, 10), M.STEEL)
	for z in 10:
		for x in 10:
			var r := Vector2(x - 4.5, z - 4.5).length()
			if r > 4.2:
				continue
			var blade := (x == z or x + z == 9) and r > 1.0
			p.box(Vector3i(x, 0, z), Vector3i(x + 1, 1, z + 1), M.STEEL if blade or r <= 1.0 else M.RUBBER)


## A pendent sprinkler: escutcheon, stem and a brass deflector.
static func sprinkler_head(p: Props, o: Vector3i) -> void:
	p.begin(o, 3, 3, P.NORTH)
	p.box(Vector3i(0, 2, 0), Vector3i(3, 3, 3), M.STEEL)
	p.box(Vector3i(1, 1, 1), Vector3i(2, 2, 2), M.STEEL)
	p.box(Vector3i(1, 0, 0), Vector3i(2, 1, 3), M.PIPE)
	p.box(Vector3i(0, 0, 1), Vector3i(3, 1, 2), M.PIPE)


## A smoke detector with an LED that shows on backup power.
static func smoke_detector(p: Props, o: Vector3i) -> void:
	p.begin(o, 4, 4, P.NORTH)
	p.box(Vector3i(0, 1, 0), Vector3i(4, 2, 4), M.PLASTIC)
	p.box(Vector3i(1, 0, 1), Vector3i(3, 1, 3), M.PLASTIC)
	p.box(Vector3i(1, 0, 1), Vector3i(2, 1, 2), M.EMERGENCY)


## An intercom horn speaker on a short bracket, its bell facing down.
static func speaker_horn(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 6, P.NORTH)
	p.box(Vector3i(2, 4, 2), Vector3i(4, 6, 4), M.STEEL)
	p.box(Vector3i(2, 3, 2), Vector3i(4, 4, 4), M.METAL)
	p.box(Vector3i(1, 2, 1), Vector3i(5, 3, 5), M.METAL)
	p.box(Vector3i(0, 0, 0), Vector3i(6, 2, 6), M.METAL)
	p.box(Vector3i(1, 0, 1), Vector3i(5, 1, 5), M.RUBBER)


## A security camera on an arm, looking north (its front).
static func security_camera(p: Props, o: Vector3i) -> void:
	p.begin(o, 4, 8, P.NORTH)
	p.box(Vector3i(0, 4, 5), Vector3i(4, 5, 8), M.STEEL)
	p.box(Vector3i(1, 3, 4), Vector3i(3, 4, 6), M.STEEL)
	p.box(Vector3i(0, 0, 0), Vector3i(4, 3, 6), M.PLASTIC)
	p.box(Vector3i(1, 0, 0), Vector3i(3, 2, 1), M.RUBBER)
	p.box(Vector3i(1, 1, 0), Vector3i(2, 2, 1), M.GLASS)
	p.box(Vector3i(3, 2, 0), Vector3i(4, 3, 1), M.EMERGENCY)


## A hazard beacon: a dome that lights on backup power (alarm spinning is not built yet).
static func hazard_beacon(p: Props, o: Vector3i) -> void:
	p.begin(o, 4, 4, P.NORTH)
	p.box(Vector3i(0, 4, 0), Vector3i(4, 5, 4), M.STEEL)
	p.box(Vector3i(0, 3, 0), Vector3i(4, 4, 4), M.METAL)
	p.box(Vector3i(1, 0, 1), Vector3i(3, 3, 3), M.EMERGENCY)
	p.box(Vector3i(0, 1, 1), Vector3i(4, 2, 3), M.EMERGENCY)
	p.box(Vector3i(1, 1, 0), Vector3i(3, 2, 4), M.EMERGENCY)


## A chain hoist: a yellow hoist body clamped to the ceiling, a chain of links and a hook.
static func chain_hoist(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 6, P.NORTH)
	p.box(Vector3i(1, 17, 1), Vector3i(5, 18, 5), M.STEEL)
	p.box(Vector3i(1, 12, 1), Vector3i(5, 17, 5), M.WARNING)
	for x in [0, 5]:
		p.box(Vector3i(x, 13, 2), Vector3i(x + 1, 16, 4), M.METAL)
	for y in range(3, 12):
		p.box(Vector3i(3, y, 3), Vector3i(4, y + 1, 4), M.STEEL if y % 2 == 0 else M.METAL)
	p.box(Vector3i(2, 1, 3), Vector3i(4, 3, 4), M.STEEL)
	p.box(Vector3i(1, 0, 3), Vector3i(3, 1, 4), M.WARNING)


## A 1 m module of yellow I-beam gantry rail, flush on the ceiling, with a splice plate at its west end.
static func gantry_rail(p: Props, o: Vector3i) -> void:
	p.begin(o, 10, 4, P.NORTH)
	p.box(Vector3i(0, 4, 0), Vector3i(10, 5, 4), M.WARNING)
	p.box(Vector3i(0, 1, 1), Vector3i(10, 4, 3), M.WARNING)
	p.box(Vector3i(0, 0, 0), Vector3i(10, 1, 4), M.WARNING)
	for z in [0, 3]:
		p.box(Vector3i(0, 1, z), Vector3i(1, 4, z + 1), M.STEEL)


## A service hatch in the ceiling, the twin of the wall vent grate: where ceiling spawners come from.
static func service_hatch(p: Props, o: Vector3i) -> void:
	p.begin(o, 12, 12, P.NORTH)
	p.box(Vector3i(0, 1, 0), Vector3i(12, 2, 12), M.STEEL)
	p.box(Vector3i(0, 0, 0), Vector3i(12, 1, 12), M.STEEL)
	p.box(Vector3i(1, 0, 1), Vector3i(11, 1, 11), M.WARNING)
	p.box(Vector3i(2, 0, 2), Vector3i(10, 1, 10), M.METAL)
	p.box(Vector3i(5, 0, 8), Vector3i(7, 1, 9), M.RUBBER) # Handle.
	for x in [3, 8]:
		p.box(Vector3i(x, 0, 2), Vector3i(x + 1, 1, 3), M.STEEL) # Hinges.


# --- Light fixtures -----------------------------------------------------------------------------
# LAMP voxels glow with facility power and EMERGENCY voxels only on backup (the shader's emission
# groups), so fixtures light up and go dark with the room. The light marker is still the light.

## A 12 x 2 x 6 fluorescent panel. dead: a dark, burnt-out face with one broken tube.
static func troffer(p: Props, o: Vector3i, dead: bool) -> void:
	p.begin(o, 12, 6, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(12, 2, 6), M.METAL)
	p.box(Vector3i(1, 0, 1), Vector3i(11, 1, 5), M.CHAR if dead else M.LAMP)
	if dead:
		p.box(Vector3i(2, 0, 1), Vector3i(8, 1, 2), M.GLASS)


## A 1 m strip light (a run piece): a lit tube with metal end caps.
static func strip_light(p: Props, o: Vector3i) -> void:
	p.begin(o, 10, 2, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(10, 2, 2), M.METAL)
	p.box(Vector3i(1, 0, 0), Vector3i(9, 1, 2), M.LAMP)


## A caged bulkhead lamp on an L bracket (a plate on its back and on its top), so it sits on a wall
## or under a ceiling.
static func bulkhead(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 4, P.NORTH)
	p.box(Vector3i(0, 0, 3), Vector3i(6, 5, 4), M.STEEL)
	p.box(Vector3i(0, 4, 0), Vector3i(6, 5, 4), M.STEEL)
	p.box(Vector3i(1, 2, 1), Vector3i(5, 4, 3), M.METAL)
	p.box(Vector3i(2, 1, 0), Vector3i(4, 3, 2), M.LAMP)
	p.box(Vector3i(1, 0, 0), Vector3i(5, 1, 1), M.STEEL)
	for x in [1, 4]:
		p.box(Vector3i(x, 0, 0), Vector3i(x + 1, 3, 1), M.STEEL)


## A pendant lamp: a cord, a metal shade and the lamp under it.
static func pendant(p: Props, o: Vector3i) -> void:
	p.begin(o, 5, 5, P.NORTH)
	p.box(Vector3i(2, 4, 2), Vector3i(3, 10, 3), M.RUBBER)
	p.box(Vector3i(1, 3, 1), Vector3i(4, 4, 4), M.METAL)
	p.box(Vector3i(0, 1, 0), Vector3i(5, 3, 5), M.METAL)
	p.box(Vector3i(1, 1, 1), Vector3i(4, 3, 4), M.LAMP)
	p.box(Vector3i(2, 0, 2), Vector3i(3, 1, 3), M.LAMP)


## An emergency light: a white box with a red lens that glows only on backup power.
static func emergency_light(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 4, P.NORTH)
	p.box(Vector3i(0, 1, 0), Vector3i(6, 3, 4), M.PLASTIC)
	p.box(Vector3i(1, 0, 1), Vector3i(5, 1, 3), M.EMERGENCY)
