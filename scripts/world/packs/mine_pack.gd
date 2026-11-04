extends RefCounted
## Mine and cavern props (docs/prop-build-plan.md D2). Floor props, except the stalactites and the
## hanging rope (mount "ceiling": drawn from y = 0 up with the top layer against the ceiling) and
## the lantern ("any": a plate on its back and on its top, so it hangs from a ceiling or sits on a
## wall, like fixture_bulkhead). The timber frame is a doorway-sized arch, 24 wide and 26 tall,
## 4 deep. Rails are 10 x 10 modules one voxel tall: a straight runs west to east with the rails at
## z = 3 and 6, a curve turns from the west side to the south side (centre radius 5).

const P := preload("res://scripts/world/props.gd")
const M := preload("res://scripts/voxel/voxel_materials.gd")

const CATEGORY := "Mine"
const MOUNTS := {"lantern": "any", "stalactite": "ceiling", "rope_hanging": "ceiling"}
const VALUES := {
	"timber_support": 400, "mine_cart": 500, "rail_": 60, "lantern": 90, "stalactite": 0, "stalagmite": 0,
	"rock_pile": 20, "drill_rig": 1800, "ore_bucket": 120, "rope_coil": 40, "rope_hanging": 40,
}
const USES := {}

const SIZES := {"small": [3, 6], "medium": [5, 12], "large": [7, 18]} # width, height


static func entries(add: Callable) -> void:
	add.call("timber_support_frame", func(p: Props, o: Vector3i) -> void: timber_frame(p, o))
	add.call("mine_cart", func(p: Props, o: Vector3i) -> void: mine_cart(p, o))
	add.call("rail_straight", func(p: Props, o: Vector3i) -> void: rail(p, o, false))
	add.call("rail_curve", func(p: Props, o: Vector3i) -> void: rail(p, o, true))
	add.call("lantern", func(p: Props, o: Vector3i) -> void: lantern(p, o))
	for s in SIZES:
		var w: int = SIZES[s][0]
		var h: int = SIZES[s][1]
		add.call("stalactite_" + s, func(p: Props, o: Vector3i) -> void: spike(p, o, w, h, true))
		add.call("stalagmite_" + s, func(p: Props, o: Vector3i) -> void: spike(p, o, w, h, false))
	add.call("rock_pile", func(p: Props, o: Vector3i) -> void: rock_pile(p, o))
	add.call("drill_rig", func(p: Props, o: Vector3i) -> void: drill_rig(p, o))
	add.call("ore_bucket", func(p: Props, o: Vector3i) -> void: ore_bucket(p, o))
	add.call("rope_coil", func(p: Props, o: Vector3i) -> void: rope_coil(p, o))
	add.call("rope_hanging", func(p: Props, o: Vector3i) -> void: rope_hanging(p, o))


## A timber arch, 24 x 4 x 26: two posts on stone footings, a cap beam, corner braces and wedges.
static func timber_frame(p: Props, o: Vector3i) -> void:
	p.begin(o, 24, 4, P.NORTH)
	for x in [0, 21]:
		p.box(Vector3i(x, 0, 0), Vector3i(x + 3, 2, 4), M.ROCK)
		p.box(Vector3i(x, 2, 0), Vector3i(x + 3, 23, 4), M.WOOD)
	p.box(Vector3i(0, 23, 0), Vector3i(24, 26, 4), M.WOOD)
	for i in 4: # Braces: 45 degree struts from post to beam.
		p.box(Vector3i(3 + i, 19 - i, 1), Vector3i(4 + i, 23 - i, 3), M.PLANK)
		p.box(Vector3i(20 - i, 19 - i, 1), Vector3i(21 - i, 23 - i, 3), M.PLANK)
	p.box(Vector3i(8, 22, 0), Vector3i(10, 23, 4), M.PLANK) # Wedges under the beam.
	p.box(Vector3i(14, 22, 0), Vector3i(16, 23, 4), M.PLANK)
	p.box(Vector3i(0, 14, 0), Vector3i(3, 15, 1), M.PLANK) # Nailed lagging boards.
	p.box(Vector3i(21, 8, 0), Vector3i(24, 9, 1), M.PLANK)


## An ore cart: a steel box on four wheels with a rim and a heap of ore, 14 x 8 x 10.
static func mine_cart(p: Props, o: Vector3i) -> void:
	p.begin(o, 14, 8, P.NORTH)
	for x in [2, 10]:
		for z in [0, 6]:
			p.box(Vector3i(x, 0, z), Vector3i(x + 2, 2, z + 2), M.STEEL)
	p.box(Vector3i(2, 1, 1), Vector3i(12, 2, 7), M.STEEL) # Axles.
	p.box(Vector3i(0, 2, 0), Vector3i(14, 3, 8), M.PIPE) # Floor.
	p.box(Vector3i(0, 3, 0), Vector3i(14, 9, 8), M.METAL)
	p.box(Vector3i(1, 4, 1), Vector3i(13, 9, 7), M.AIR)
	p.box(Vector3i(0, 8, 0), Vector3i(14, 9, 1), M.STEEL) # Rim.
	p.box(Vector3i(0, 8, 7), Vector3i(14, 9, 8), M.STEEL)
	p.box(Vector3i(0, 8, 0), Vector3i(1, 9, 8), M.STEEL)
	p.box(Vector3i(13, 8, 0), Vector3i(14, 9, 8), M.STEEL)
	p.box(Vector3i(1, 3, 1), Vector3i(13, 7, 7), M.ROCK)
	p.box(Vector3i(3, 7, 2), Vector3i(11, 9, 6), M.GRAVEL)
	p.box(Vector3i(5, 9, 3), Vector3i(8, 10, 5), M.ROCK)
	p.box(Vector3i(6, 9, 3), Vector3i(7, 10, 4), M.GLOW) # A glowing nugget.


## Track: wooden ties with two steel rails over them, one voxel tall. The curve runs from the west
## side to the south side round the south-west corner (centre at x = 0, z = 10).
static func rail(p: Props, o: Vector3i, curve: bool) -> void:
	p.begin(o, 10, 10, P.NORTH)
	if not curve:
		for x in [1, 4, 7]:
			p.box(Vector3i(x, 0, 2), Vector3i(x + 1, 1, 8), M.WOOD)
		for z in [3, 6]:
			p.box(Vector3i(0, 0, z), Vector3i(10, 1, z + 1), M.STEEL)
		return
	for z in 10:
		for x in 10:
			var v := Vector2(x + 0.5, z + 0.5 - 10.0)
			var r := v.length()
			var a := atan2(-v.y, v.x) # 0 at the west entry, PI/2 at the south exit.
			var material := -1
			if absf(r - 3.5) <= 0.5 or absf(r - 6.5) <= 0.5:
				material = M.STEEL
			elif r > 2.5 and r < 7.5:
				for t in [PI / 12, PI / 4, 5 * PI / 12]:
					if absf(a - t) < 0.1:
						material = M.WOOD
			if material >= 0:
				p.box(Vector3i(x, 0, z), Vector3i(x + 1, 1, z + 1), material)


## A lantern: a steel cage round a glowing core, with a plate on its back and on its top so it hangs
## or sits on a wall. 4 x 4 x 8.
static func lantern(p: Props, o: Vector3i) -> void:
	p.begin(o, 4, 4, P.NORTH)
	p.box(Vector3i(0, 7, 0), Vector3i(4, 8, 4), M.STEEL)
	p.box(Vector3i(0, 0, 3), Vector3i(4, 8, 4), M.STEEL)
	p.box(Vector3i(0, 0, 0), Vector3i(3, 1, 3), M.STEEL)
	for x in [0, 2]:
		p.box(Vector3i(x, 1, 0), Vector3i(x + 1, 7, 1), M.STEEL)
		p.box(Vector3i(x, 1, 2), Vector3i(x + 1, 7, 3), M.STEEL)
	p.box(Vector3i(1, 2, 1), Vector3i(2, 6, 2), M.GLOW)


## A cave spike, a cone of rock: stalactites hang with the base at the ceiling (top layer at
## y = height - 1), stalagmites stand with the base on the floor. width x width x height.
static func spike(p: Props, o: Vector3i, w: int, h: int, hanging: bool) -> void:
	p.begin(o, w, w, P.NORTH)
	var c := (w - 1) / 2.0
	for k in h: # k = layers from the base.
		var y := h - 1 - k if hanging else k
		var r := (w / 2.0) * (1.0 - float(k) / h) + 0.3
		for z in w:
			for x in w:
				if Vector2(x - c, z - c).length() <= r:
					p.box(Vector3i(x, y, z), Vector3i(x + 1, y + 1, z + 1), M.ROCK if k < h - 2 or w < 5 else M.DEEP_STONE)


## A heap of broken rock, 12 x 10 x 7: a mound with gravel on its flanks.
static func rock_pile(p: Props, o: Vector3i) -> void:
	p.begin(o, 12, 10, P.NORTH)
	for z in 10:
		for x in 12:
			var d := Vector2((x + 0.5 - 6.0) / 6.0, (z + 0.5 - 5.0) / 5.0).length()
			var h := int(round(7.0 * (1.0 - d)))
			if h <= 0:
				continue
			p.box(Vector3i(x, 0, z), Vector3i(x + 1, h, z + 1), M.GRAVEL if d > 0.6 else M.ROCK)
	p.box(Vector3i(5, 6, 4), Vector3i(7, 7, 6), M.DEEP_STONE)


## A pneumatic drill rig, 14 x 10 x 20: a base sled, a mast with a drill steel, a motor on a slide.
static func drill_rig(p: Props, o: Vector3i) -> void:
	p.begin(o, 14, 10, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(14, 2, 10), M.STEEL) # Sled.
	p.box(Vector3i(0, 0, 0), Vector3i(14, 1, 2), M.HAZARD_STRIPES)
	p.box(Vector3i(5, 2, 4), Vector3i(9, 6, 8), M.METAL) # Compressor body.
	p.box(Vector3i(6, 6, 5), Vector3i(8, 7, 7), M.WARNING)
	for z in [3, 6]: # Mast: two rails.
		p.box(Vector3i(2, 2, z), Vector3i(3, 19, z + 1), M.STEEL)
	p.box(Vector3i(2, 19, 3), Vector3i(3, 20, 7), M.STEEL)
	p.box(Vector3i(1, 2, 2), Vector3i(4, 3, 8), M.PLANK)
	p.box(Vector3i(1, 10, 3), Vector3i(4, 15, 7), M.EMERGENCY) # Drill motor on the slide.
	p.box(Vector3i(2, 15, 4), Vector3i(3, 17, 6), M.WARNING)
	p.box(Vector3i(2, 2, 4), Vector3i(3, 10, 6), M.STEEL) # Drill steel.
	p.box(Vector3i(2, 2, 4), Vector3i(3, 3, 6), M.GLOW)
	p.box(Vector3i(3, 4, 5), Vector3i(5, 5, 6), M.RUBBER) # Air hose to the body.
	p.box(Vector3i(10, 2, 5), Vector3i(14, 3, 6), M.RUBBER)


## An ore bucket, 5 x 5 x 7: tapered steel pail, ore on top, a swung handle.
static func ore_bucket(p: Props, o: Vector3i) -> void:
	p.begin(o, 5, 5, P.NORTH)
	p.box(Vector3i(1, 0, 1), Vector3i(4, 1, 4), M.STEEL)
	p.box(Vector3i(0, 1, 0), Vector3i(5, 5, 5), M.METAL)
	p.box(Vector3i(1, 4, 1), Vector3i(4, 5, 4), M.ROCK)
	p.box(Vector3i(2, 5, 2), Vector3i(3, 6, 3), M.GRAVEL)
	p.box(Vector3i(0, 5, 2), Vector3i(1, 7, 3), M.STEEL)
	p.box(Vector3i(4, 5, 2), Vector3i(5, 7, 3), M.STEEL)
	p.box(Vector3i(1, 6, 2), Vector3i(4, 7, 3), M.STEEL)


## A coil of rope, 6 x 6 x 3: two stacked rings with a loose tail.
static func rope_coil(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 6, P.NORTH)
	for z in 6:
		for x in 6:
			var r := Vector2(x + 0.5 - 3.0, z + 0.5 - 3.0).length()
			if r >= 1.2 and r <= 3.0:
				p.box(Vector3i(x, 0, z), Vector3i(x + 1, 2, z + 1), M.CLOTH)
			if r >= 1.2 and r <= 2.5:
				p.box(Vector3i(x, 2, z), Vector3i(x + 1, 3, z + 1), M.CLOTH)
	p.box(Vector3i(5, 0, 0), Vector3i(6, 1, 1), M.WOOD)


## A hanging rope: 2 x 2 x 20 from the ceiling, a knot near the bottom and a frayed end.
static func rope_hanging(p: Props, o: Vector3i) -> void:
	p.begin(o, 2, 2, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(2, 20, 2), M.CLOTH)
	p.box(Vector3i(0, 15, 0), Vector3i(2, 17, 2), M.WOOD)
	p.box(Vector3i(0, 0, 0), Vector3i(1, 3, 1), M.AIR)
	p.box(Vector3i(1, 0, 1), Vector3i(2, 1, 2), M.AIR)
