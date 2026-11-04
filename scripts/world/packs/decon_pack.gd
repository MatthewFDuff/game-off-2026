extends RefCounted
## Decontamination props (docs/prop-build-plan.md D4): the shower tunnel, suit storage, signage and
## washdown kit. The tunnel is a 10-voxel module along x (open at both ends, walk-through), 24 tall,
## so modules chain on the 1 m grid.

const P := preload("res://scripts/world/props.gd")
const M := preload("res://scripts/voxel/voxel_materials.gd")

const CATEGORY := "Decon"
const MOUNTS := {
	"decon_tunnel": "floor", "hazmat_suit_rack": "floor", "hazmat_locker": "floor",
	"hazmat_sign": "wall", "sprayer": "floor", "boot_wash": "floor",
}
const VALUES := {
	"decon_tunnel": 3500, "hazmat_suit_rack": 1400, "hazmat_locker": 600,
	"hazmat_sign": 40, "sprayer": 350, "boot_wash": 500,
}
const USES := {}


static func entries(add: Callable) -> void:
	add.call("decon_tunnel", func(p: Props, o: Vector3i) -> void: tunnel(p, o))
	add.call("hazmat_suit_rack", func(p: Props, o: Vector3i) -> void: suit_rack(p, o))
	add.call("hazmat_locker", func(p: Props, o: Vector3i) -> void: hazmat_locker(p, o))
	add.call("hazmat_sign", func(p: Props, o: Vector3i) -> void: hazmat_sign(p, o))
	add.call("sprayer", func(p: Props, o: Vector3i) -> void: sprayer(p, o))
	add.call("boot_wash", func(p: Props, o: Vector3i) -> void: boot_wash(p, o))


static func _b(p: Props, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, m: int) -> void:
	p.box(Vector3i(x0, y0, z0), Vector3i(x1, y1, z1), m)


## Walk-through shower module along x: grated floor and drain, steel side walls with a window
## band, a ceiling of spray nozzles and falling water.
static func tunnel(p: Props, o: Vector3i) -> void:
	p.begin(o, 10, 10, P.NORTH)
	_b(p, 0, 0, 0, 10, 1, 10, M.STEEL) # Floor.
	for x in range(0, 10, 2):
		_b(p, x, 0, 3, x + 1, 1, 7, M.RUBBER) # Grating.
	for z in [0, 9]:
		_b(p, 0, 1, z, 10, 24, z + 1, M.STEEL)
		_b(p, 1, 1, z, 9, 6, z + 1, M.PLASTIC) # Lower panel.
		_b(p, 0, 12, z, 10, 13, z + 1, M.WARNING) # Hazard rail at eye level.
		_b(p, 2, 14, z, 8, 19, z + 1, M.GLASS) # Window.
	for x in [0, 9]:
		_b(p, x, 0, 0, x + 1, 24, 10, M.STEEL) # End frames, open between the walls.
		_b(p, x, 1, 1, x + 1, 22, 9, M.AIR)
		_b(p, x, 21, 1, x + 1, 22, 9, M.STEEL)
	_b(p, 0, 22, 0, 10, 24, 10, M.STEEL) # Roof.
	_b(p, 1, 21, 1, 9, 22, 9, M.PLASTIC) # Spray manifold.
	for x in [2, 5, 8]:
		_b(p, x, 20, 4, x + 1, 21, 6, M.PIPE) # Nozzles.
		_b(p, x, 8, 4, x + 1, 20, 5, M.WATER) # Falling water.
		_b(p, x, 10, 5, x + 1, 17, 6, M.WATER)
	_b(p, 4, 0, 4, 6, 1, 6, M.PIPE) # Drain.
	_b(p, 4, 22, 0, 6, 23, 1, M.EMERGENCY) # Warning lamp.


## Three yellow suits on hangers along a steel rail.
static func suit_rack(p: Props, o: Vector3i) -> void:
	p.begin(o, 14, 5, P.NORTH)
	_b(p, 0, 0, 1, 14, 1, 4, M.STEEL) # Base.
	for x in [0, 13]:
		_b(p, x, 1, 2, x + 1, 22, 3, M.STEEL)
	_b(p, 0, 21, 2, 14, 22, 3, M.STEEL) # Rail.
	for i in 3:
		var x := 1 + i * 4
		_b(p, x + 1, 19, 2, x + 2, 21, 3, M.STEEL) # Hanger.
		_b(p, x, 17, 1, x + 3, 19, 4, M.WARNING) # Head and hood.
		_b(p, x + 1, 17, 1, x + 2, 19, 2, M.GLASS) # Visor.
		_b(p, x, 9, 1, x + 3, 17, 4, M.WARNING) # Torso and arms.
		_b(p, x, 3, 1, x + 1, 9, 3, M.WARNING) # Legs.
		_b(p, x + 2, 3, 1, x + 3, 9, 3, M.WARNING)
		_b(p, x, 1, 1, x + 1, 3, 3, M.RUBBER) # Boots.
		_b(p, x + 2, 1, 1, x + 3, 3, 3, M.RUBBER)
		_b(p, x, 13, 0, x + 3, 14, 1, M.HAZARD_STRIPES) # Belt.


## Tall suit locker: a hazard-banded cabinet with vents and a label.
static func hazmat_locker(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 6, P.NORTH)
	_b(p, 0, 0, 0, 6, 22, 6, M.METAL)
	_b(p, 0, 0, 0, 6, 1, 6, M.RUBBER)
	_b(p, 0, 7, 0, 6, 9, 1, M.HAZARD_STRIPES)
	for y in range(14, 20, 2):
		_b(p, 1, y, 0, 5, y + 1, 1, M.RUBBER) # Vents.
	_b(p, 4, 10, 0, 5, 12, 1, M.STEEL) # Handle.
	_b(p, 1, 2, 0, 4, 5, 1, M.PLASTIC) # Label card.
	_b(p, 1, 4, 0, 4, 5, 1, M.WARNING)
	_b(p, 0, 21, 0, 6, 22, 6, M.STEEL)


## Wall sign: a yellow plate with a black trefoil-ish symbol.
static func hazmat_sign(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 1, P.NORTH)
	_b(p, 0, 0, 0, 8, 8, 1, M.RUBBER)
	_b(p, 1, 1, 0, 7, 7, 1, M.WARNING)
	_b(p, 3, 3, 0, 5, 5, 1, M.RUBBER) # Centre ring.
	_b(p, 3, 5, 0, 5, 6, 1, M.RUBBER) # Top blade.
	_b(p, 2, 2, 0, 3, 3, 1, M.RUBBER) # Lower blades.
	_b(p, 5, 2, 0, 6, 3, 1, M.RUBBER)
	_b(p, 3, 3, 0, 5, 5, 1, M.RUBBER)
	_b(p, 1, 1, 0, 7, 2, 1, M.WARNING)


## Pump sprayer on a little cart: tank, hose and a wand.
static func sprayer(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 5, P.NORTH)
	_b(p, 0, 1, 1, 6, 2, 4, M.STEEL) # Cart bed.
	_b(p, 1, 0, 1, 2, 1, 2, M.RUBBER) # Wheels.
	_b(p, 1, 0, 3, 2, 1, 4, M.RUBBER)
	_b(p, 4, 0, 1, 5, 1, 2, M.RUBBER)
	_b(p, 4, 0, 3, 5, 1, 4, M.RUBBER)
	_b(p, 1, 2, 1, 4, 10, 4, M.WARNING) # Tank.
	_b(p, 1, 10, 1, 4, 11, 4, M.STEEL)
	_b(p, 2, 11, 2, 3, 12, 3, M.RUBBER) # Pump knob.
	_b(p, 4, 6, 2, 5, 7, 3, M.RUBBER) # Hose.
	_b(p, 5, 3, 2, 6, 7, 3, M.RUBBER)
	_b(p, 6, 2, 2, 8, 3, 3, M.STEEL) # Wand.
	_b(p, 7, 2, 2, 8, 3, 3, M.PIPE)
	_b(p, 5, 6, 0, 6, 8, 1, M.STEEL) # Cart handle.


## Boot wash trough: a basin of soapy water with scrub brushes at either end and a hand rail.
static func boot_wash(p: Props, o: Vector3i) -> void:
	p.begin(o, 14, 8, P.NORTH)
	_b(p, 0, 0, 0, 14, 3, 8, M.STEEL)
	_b(p, 1, 2, 1, 13, 3, 7, M.WATER)
	for x in [3, 10]:
		for z in [2, 5]:
			_b(p, x, 3, z, x + 1, 5, z + 1, M.RUBBER) # Brushes.
	_b(p, 6, 3, 3, 8, 4, 5, M.PLASTIC) # Soap block.
	_b(p, 0, 3, 3, 1, 12, 4, M.STEEL) # Rail.
	_b(p, 13, 3, 3, 14, 12, 4, M.STEEL)
	_b(p, 0, 11, 3, 14, 12, 4, M.WARNING)
	_b(p, 0, 0, 0, 14, 1, 1, M.HAZARD_STRIPES)
