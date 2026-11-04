extends RefCounted
## Lighting props (docs/prop-build-plan.md D1): signs and beacons, floor lights, tubes, lamps and
## glowing plants. LAMP glows on facility power, EMERGENCY only on backup, GLOW always (the
## photoluminescent path lights, the arrow decal, the plant pot, the blacklight art). Nothing pulses.
##
## Ceiling props have their top layer against the ceiling. Wall and "any" props have their back at
## the highest z (z = d - 1), front at z = 0, facing north (-z), as PropPlacement sets them.
## The exit sign has a plate on its back and on its top, so it sits on a wall or under a ceiling.

const P := preload("res://scripts/world/props.gd")
const M := preload("res://scripts/voxel/voxel_materials.gd")
const C := preload("res://scripts/world/packs/corridor_pack.gd")

const CATEGORY := "Lighting"
const MOUNTS := {
	"exit_sign": "any", "beacon_rotating": "ceiling", "path_light": "floor", "glow_arrow": "floor",
	"tube_light": "ceiling", "pendant_swaying": "ceiling", "bench_lamp": "floor", "uv_lamp": "wall",
	"blacklight_poster": "wall", "plant_pot_glow": "floor",
}
const VALUES := {
	"exit_sign": 140, "beacon_rotating": 190, "path_light": 40, "glow_arrow": 25, "tube_light": 70,
	"tube_light_dead": 20, "pendant_swaying": 120, "bench_lamp": 55, "uv_lamp": 160,
	"blacklight_poster": 45, "plant_pot_glow": 85,
}
const USES := {}


static func entries(add: Callable) -> void:
	add.call("exit_sign", func(p: Props, o: Vector3i) -> void: exit_sign(p, o))
	add.call("beacon_rotating", func(p: Props, o: Vector3i) -> void: beacon(p, o))
	add.call("path_light", func(p: Props, o: Vector3i) -> void: path_light(p, o))
	add.call("glow_arrow", func(p: Props, o: Vector3i) -> void: glow_arrow(p, o))
	add.call("tube_light", func(p: Props, o: Vector3i) -> void: tube(p, o, false))
	add.call("tube_light_dead", func(p: Props, o: Vector3i) -> void: tube(p, o, true))
	add.call("pendant_swaying", func(p: Props, o: Vector3i) -> void: pendant_swaying(p, o))
	add.call("bench_lamp", func(p: Props, o: Vector3i) -> void: bench_lamp(p, o))
	add.call("uv_lamp", func(p: Props, o: Vector3i) -> void: uv_lamp(p, o))
	add.call("blacklight_poster", func(p: Props, o: Vector3i) -> void: blacklight_poster(p, o))
	add.call("plant_pot_glow", func(p: Props, o: Vector3i) -> void: plant_pot(p, o))


## An 18 x 3 exit sign, 11 tall: a black face with red EXIT, hung on two rods from a top plate and
## held by a back plate. The top plate is against a ceiling, the back plate against a wall.
static func exit_sign(p: Props, o: Vector3i) -> void:
	p.begin(o, 18, 3, P.NORTH)
	p.box(Vector3i(0, 10, 0), Vector3i(18, 11, 3), M.STEEL) # Top plate.
	p.box(Vector3i(0, 0, 2), Vector3i(18, 10, 3), M.STEEL) # Back plate.
	p.box(Vector3i(0, 0, 0), Vector3i(18, 9, 2), M.PLASTIC)
	p.box(Vector3i(1, 1, 0), Vector3i(17, 8, 1), M.RUBBER)
	for x in [3, 14]:
		p.box(Vector3i(x, 9, 1), Vector3i(x + 1, 10, 2), M.STEEL)
	C.text(p, 18, 1, 2, 0, "EXIT", M.EMERGENCY)


## A rotating beacon: a base plate on the ceiling, a dome of red lamp with a reflector across it.
static func beacon(p: Props, o: Vector3i) -> void:
	p.begin(o, 7, 7, P.NORTH)
	p.box(Vector3i(0, 7, 0), Vector3i(7, 8, 7), M.STEEL)
	p.box(Vector3i(1, 6, 1), Vector3i(6, 7, 6), M.METAL)
	p.box(Vector3i(1, 3, 1), Vector3i(6, 6, 6), M.EMERGENCY)
	p.box(Vector3i(2, 1, 2), Vector3i(5, 3, 5), M.EMERGENCY)
	p.box(Vector3i(0, 4, 3), Vector3i(7, 5, 4), M.STEEL) # Reflector blade, a different shade across the dome.
	p.box(Vector3i(2, 0, 2), Vector3i(5, 1, 5), M.METAL)


## A 4 x 4 floor path light: a flat metal case with a glowing lens.
static func path_light(p: Props, o: Vector3i) -> void:
	p.begin(o, 4, 4, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(4, 1, 4), M.METAL)
	p.box(Vector3i(1, 1, 1), Vector3i(3, 2, 3), M.GLOW)


## A one-voxel floor plate 7 x 9 with a glowing arrow pointing north.
static func glow_arrow(p: Props, o: Vector3i) -> void:
	p.begin(o, 7, 9, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(7, 1, 9), M.RUBBER)
	p.box(Vector3i(3, 0, 3), Vector3i(4, 1, 9), M.GLOW)
	p.box(Vector3i(3, 0, 0), Vector3i(4, 1, 1), M.GLOW)
	p.box(Vector3i(2, 0, 1), Vector3i(5, 1, 2), M.GLOW)
	p.box(Vector3i(1, 0, 2), Vector3i(6, 1, 3), M.GLOW)


## A bare 12 x 4 fluorescent tube in its channel. dead: a grey tube, black at both ends.
static func tube(p: Props, o: Vector3i, dead: bool) -> void:
	p.begin(o, 12, 4, P.NORTH)
	p.box(Vector3i(0, 1, 0), Vector3i(12, 2, 4), M.METAL)
	p.box(Vector3i(1, 0, 1), Vector3i(11, 1, 3), M.GLASS if dead else M.LAMP)
	if dead:
		p.box(Vector3i(1, 0, 1), Vector3i(3, 1, 3), M.CHAR)
		p.box(Vector3i(9, 0, 1), Vector3i(11, 1, 3), M.CHAR)
	p.box(Vector3i(0, 0, 1), Vector3i(1, 1, 3), M.STEEL)
	p.box(Vector3i(11, 0, 1), Vector3i(12, 1, 3), M.STEEL)


## A pendant lamp on a long cord that leans a voxel or two, as if mid-swing (the sway itself is
## the game's). 7 x 7, 20 tall.
static func pendant_swaying(p: Props, o: Vector3i) -> void:
	p.begin(o, 7, 7, P.NORTH)
	p.box(Vector3i(2, 19, 2), Vector3i(5, 20, 5), M.STEEL) # Ceiling rose.
	p.box(Vector3i(3, 14, 3), Vector3i(4, 19, 4), M.RUBBER)
	p.box(Vector3i(3, 10, 2), Vector3i(4, 15, 3), M.RUBBER)
	p.box(Vector3i(3, 9, 2), Vector3i(4, 10, 3), M.RUBBER)
	p.box(Vector3i(2, 8, 1), Vector3i(5, 9, 4), M.METAL)
	p.box(Vector3i(1, 5, 0), Vector3i(6, 8, 5), M.METAL)
	p.box(Vector3i(2, 5, 1), Vector3i(5, 8, 4), M.LAMP)
	p.box(Vector3i(2, 4, 1), Vector3i(5, 5, 4), M.LAMP)
	p.box(Vector3i(3, 3, 2), Vector3i(4, 4, 3), M.LAMP)


## A 6 x 6 desk lamp, 10 tall: a base, an arm and a shade over a lit bulb. Stands on a desk top.
static func bench_lamp(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 6, P.NORTH)
	p.box(Vector3i(0, 0, 1), Vector3i(4, 1, 5), M.METAL)
	p.box(Vector3i(1, 1, 2), Vector3i(2, 8, 3), M.STEEL)
	p.box(Vector3i(1, 8, 1), Vector3i(6, 10, 5), M.METAL)
	p.box(Vector3i(2, 7, 2), Vector3i(5, 8, 4), M.LAMP)


## A 12 x 3 wall light, 4 tall: a metal housing with a violet-blue tube along its face.
static func uv_lamp(p: Props, o: Vector3i) -> void:
	p.begin(o, 12, 3, P.NORTH)
	p.box(Vector3i(0, 0, 2), Vector3i(12, 4, 3), M.STEEL)
	p.box(Vector3i(0, 0, 1), Vector3i(12, 4, 2), M.METAL)
	p.box(Vector3i(0, 0, 0), Vector3i(1, 4, 2), M.STEEL)
	p.box(Vector3i(11, 0, 0), Vector3i(12, 4, 2), M.STEEL)
	p.box(Vector3i(1, 1, 0), Vector3i(11, 3, 1), M.LIQUID_BLUE)


## A 12 x 16 framed poster that glows under blacklight: a mushroom and stars on black.
static func blacklight_poster(p: Props, o: Vector3i) -> void:
	p.begin(o, 12, 1, P.NORTH)
	p.box(Vector3i(0, 0, 0), Vector3i(12, 16, 1), M.STEEL)
	p.box(Vector3i(1, 1, 0), Vector3i(11, 15, 1), M.RUBBER)
	p.box(Vector3i(3, 6, 0), Vector3i(9, 7, 0 + 1), M.GLOW)
	p.box(Vector3i(2, 7, 0), Vector3i(10, 10, 1), M.LIQUID_PINK)
	p.box(Vector3i(3, 10, 0), Vector3i(9, 11, 1), M.LIQUID_PINK)
	p.box(Vector3i(4, 8, 0), Vector3i(5, 9, 1), M.GLOW)
	p.box(Vector3i(7, 9, 0), Vector3i(8, 10, 1), M.GLOW)
	p.box(Vector3i(5, 2, 0), Vector3i(7, 6, 1), M.GLOW)
	for at in [Vector2i(2, 12), Vector2i(9, 13), Vector2i(5, 13)]:
		p.box(Vector3i(at.x, at.y, 0), Vector3i(at.x + 1, at.y + 1, 1), M.GLOW)


## A 6 x 6 pot of a plant with glowing fronds, steady (GLOW, never the pulsing mycelium), 12 tall.
static func plant_pot(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 6, P.NORTH)
	p.box(Vector3i(1, 0, 1), Vector3i(5, 4, 5), M.PLASTIC)
	p.box(Vector3i(0, 3, 0), Vector3i(6, 4, 6), M.PLASTIC) # Rim.
	p.box(Vector3i(1, 4, 1), Vector3i(5, 5, 5), M.SUBSTRATE)
	for at in [Vector3i(2, 2, 6), Vector3i(3, 3, 8), Vector3i(2, 3, 10), Vector3i(3, 2, 7)]:
		p.box(Vector3i(at.x, 5, at.y), Vector3i(at.x + 1, 5 + at.z - 3, at.y + 1), M.SHROOM_STEM)
	p.box(Vector3i(1, 9, 1), Vector3i(4, 10, 4), M.GLOW)
	p.box(Vector3i(2, 8, 2), Vector3i(5, 9, 5), M.GLOW)
	p.box(Vector3i(0, 7, 3), Vector3i(2, 8, 5), M.GLOW)
	p.box(Vector3i(4, 6, 0), Vector3i(6, 7, 2), M.GLOW)
	p.box(Vector3i(2, 10, 2), Vector3i(4, 12, 4), M.GLOW)
