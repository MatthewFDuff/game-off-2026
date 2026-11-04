extends RefCounted
## Security props (docs/prop-build-plan.md D4): the checkpoint kit at the facility gate. Floor props
## are drawn facing north (front at z = 0, where the visitor stands); the badge reader is a wall
## prop and the camera dome hangs from the ceiling (its top layer is the mounting plate).

const P := preload("res://scripts/world/props.gd")
const M := preload("res://scripts/voxel/voxel_materials.gd")

const CATEGORY := "Security"
const MOUNTS := {
	"turnstile": "floor", "metal_detector": "floor", "guard_desk": "floor", "barrier_arm": "floor",
	"gatehouse_panel": "floor", "badge_reader": "wall", "lanyard": "floor", "camera_dome": "ceiling",
}
const VALUES := {
	"turnstile": 900, "metal_detector": 2200, "guard_desk": 650, "barrier_arm": 800,
	"gatehouse_panel": 1100, "badge_reader": 300, "lanyard": 15, "camera_dome": 450,
}
const USES := {}


static func entries(add: Callable) -> void:
	add.call("turnstile", func(p: Props, o: Vector3i) -> void: turnstile(p, o))
	add.call("metal_detector_gate", func(p: Props, o: Vector3i) -> void: metal_detector(p, o))
	add.call("guard_desk", func(p: Props, o: Vector3i) -> void: guard_desk(p, o))
	add.call("barrier_arm", func(p: Props, o: Vector3i) -> void: barrier_arm(p, o))
	add.call("gatehouse_panel", func(p: Props, o: Vector3i) -> void: gatehouse(p, o))
	add.call("badge_reader", func(p: Props, o: Vector3i) -> void: badge_reader(p, o))
	add.call("lanyard_desk", func(p: Props, o: Vector3i) -> void: lanyard(p, o))
	add.call("camera_dome", func(p: Props, o: Vector3i) -> void: camera_dome(p, o))


static func _b(p: Props, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, m: int) -> void:
	p.box(Vector3i(x0, y0, z0), Vector3i(x1, y1, z1), m)


## Waist-high tripod turnstile: a post with a lit reader and three bars round a hub.
static func turnstile(p: Props, o: Vector3i) -> void:
	p.begin(o, 10, 8, P.NORTH)
	_b(p, 0, 0, 1, 10, 1, 7, M.STEEL) # Base plate.
	_b(p, 0, 1, 2, 3, 10, 6, M.STEEL) # Post.
	_b(p, 0, 10, 2, 3, 11, 6, M.RUBBER)
	_b(p, 0, 7, 1, 3, 9, 2, M.SCREEN) # Reader.
	_b(p, 0, 9, 1, 3, 10, 2, M.GLOW)
	_b(p, 3, 6, 3, 5, 9, 5, M.STEEL) # Hub.
	_b(p, 5, 8, 3, 10, 9, 5, M.STEEL) # Bar to the east.
	_b(p, 3, 7, 0, 5, 8, 3, M.STEEL) # Bar to the front.
	_b(p, 3, 7, 5, 5, 8, 8, M.STEEL) # Bar to the back.
	_b(p, 9, 7, 3, 10, 8, 5, M.WARNING) # Bar tip.


## A 12 wide, 24 tall walk-through arch: two posts, a lintel with a lit panel and an alarm light.
static func metal_detector(p: Props, o: Vector3i) -> void:
	p.begin(o, 12, 4, P.NORTH)
	for x in [0, 10]:
		_b(p, x, 0, 0, x + 2, 22, 4, M.PLASTIC)
		_b(p, x, 0, 0, x + 2, 1, 4, M.STEEL)
		_b(p, x, 4, 0, x + 2, 5, 4, M.RUBBER)
	_b(p, 0, 22, 0, 12, 24, 4, M.PLASTIC)
	_b(p, 2, 21, 0, 3, 22, 4, M.PLASTIC) # Chamfered inner corners.
	_b(p, 9, 21, 0, 10, 22, 4, M.PLASTIC)
	_b(p, 3, 22, 0, 9, 24, 1, M.RUBBER) # Control panel.
	_b(p, 4, 22, 0, 8, 23, 1, M.SCREEN)
	_b(p, 5, 23, 0, 7, 24, 1, M.GLOW)
	_b(p, 0, 10, 0, 1, 14, 1, M.GLOW) # Sensor strips down the posts.
	_b(p, 11, 10, 0, 12, 14, 1, M.GLOW)


## Guard desk: a counter facing the visitor, three monitors on the guard's side, keyboard and radio.
static func guard_desk(p: Props, o: Vector3i) -> void:
	p.begin(o, 22, 9, P.NORTH)
	_b(p, 0, 0, 0, 22, 10, 2, M.CONCRETE_PANEL) # Front counter.
	_b(p, 0, 10, 0, 22, 11, 3, M.STEEL)
	_b(p, 0, 0, 2, 22, 8, 9, M.WOOD) # Work surface block.
	_b(p, 0, 8, 2, 22, 9, 9, M.PLASTIC)
	_b(p, 1, 0, 6, 21, 8, 9, M.RUBBER) # Knee space at the guard's side.
	_b(p, 0, 1, 0, 22, 2, 1, M.HAZARD_STRIPES)
	for x in [2, 9, 16]:
		_b(p, x, 9, 4, x + 4, 10, 6, M.STEEL) # Stand.
		_b(p, x, 10, 4, x + 4, 15, 5, M.RUBBER) # Monitor, backs the visitor.
		_b(p, x + 1, 11, 5, x + 3, 14, 6, M.SCREEN)
	_b(p, 5, 9, 7, 9, 10, 8, M.RUBBER) # Keyboard.
	_b(p, 15, 9, 7, 17, 11, 8, M.RUBBER) # Radio.
	_b(p, 16, 11, 7, 17, 12, 8, M.EMERGENCY)


## Boom barrier, lowered: a housing with a striped arm.
static func barrier_arm(p: Props, o: Vector3i) -> void:
	p.begin(o, 16, 4, P.NORTH)
	_b(p, 0, 0, 0, 4, 11, 4, M.STEEL)
	_b(p, 0, 9, 0, 4, 11, 4, M.WARNING)
	_b(p, 1, 11, 1, 3, 12, 3, M.EMERGENCY) # Light.
	_b(p, 0, 5, 0, 1, 7, 1, M.RUBBER)
	for x in range(4, 16):
		var m := M.WARNING if (x / 2) % 2 == 0 else M.PLASTIC
		_b(p, x, 8, 1, x + 1, 10, 3, m)
	_b(p, 14, 8, 1, 16, 10, 3, M.EMERGENCY) # Reflector tip.
	_b(p, 12, 0, 1, 14, 8, 3, M.STEEL) # Rest post.
	_b(p, 12, 0, 1, 14, 1, 3, M.RUBBER)


## A window wall with a counter, to line a gatehouse hut: concrete panel, a glass window with a
## pass-through slot and a hazard band over it.
static func gatehouse(p: Props, o: Vector3i) -> void:
	p.begin(o, 20, 5, P.NORTH)
	_b(p, 0, 0, 2, 20, 22, 5, M.CONCRETE_PANEL)
	_b(p, 4, 9, 2, 16, 18, 5, M.AIR) # Window opening.
	_b(p, 4, 9, 3, 16, 18, 4, M.GLASS)
	_b(p, 8, 9, 3, 12, 11, 4, M.AIR) # Pass-through slot.
	for y in [8, 18]:
		_b(p, 3, y, 2, 17, y + 1, 5, M.STEEL) # Sill and head.
	for x in [3, 16]:
		_b(p, x, 8, 2, x + 1, 19, 5, M.STEEL) # Jambs.
	_b(p, 3, 8, 0, 17, 9, 2, M.STEEL) # Counter ledge.
	_b(p, 8, 9, 1, 12, 10, 2, M.RUBBER) # Tray.
	_b(p, 0, 20, 2, 20, 22, 3, M.HAZARD_STRIPES)
	_b(p, 0, 0, 2, 20, 1, 5, M.RUBBER)


## Wall-mounted card reader: a plate with a slot and a status light.
static func badge_reader(p: Props, o: Vector3i) -> void:
	p.begin(o, 4, 2, P.NORTH)
	_b(p, 0, 0, 1, 4, 6, 2, M.STEEL)
	_b(p, 1, 1, 0, 3, 5, 1, M.RUBBER)
	_b(p, 1, 4, 0, 3, 5, 1, M.SCREEN)
	_b(p, 1, 3, 0, 2, 4, 1, M.GLOW)
	_b(p, 1, 2, 0, 3, 3, 1, M.STEEL) # Slot.


## A badge on a blue lanyard, lying flat (a desk-top prop).
static func lanyard(p: Props, o: Vector3i) -> void:
	p.begin(o, 8, 5, P.NORTH)
	_b(p, 0, 0, 1, 3, 1, 5, M.PLASTIC) # Badge.
	_b(p, 0, 0, 1, 3, 1, 2, M.WARNING)
	_b(p, 1, 0, 3, 2, 1, 4, M.RUBBER) # Photo.
	_b(p, 3, 0, 2, 4, 2, 3, M.STEEL) # Clip.
	_b(p, 4, 0, 2, 8, 1, 3, M.CLOTH)
	_b(p, 7, 0, 2, 8, 1, 5, M.CLOTH)
	_b(p, 4, 0, 4, 8, 1, 5, M.CLOTH)
	_b(p, 4, 0, 3, 5, 1, 4, M.CLOTH)


## Dome camera: top layer is the mounting plate flush with the ceiling.
static func camera_dome(p: Props, o: Vector3i) -> void:
	p.begin(o, 6, 6, P.NORTH)
	_b(p, 0, 5, 0, 6, 6, 6, M.STEEL) # Plate against the ceiling.
	_b(p, 1, 3, 1, 5, 5, 5, M.PLASTIC) # Base.
	_b(p, 2, 1, 2, 4, 3, 4, M.RUBBER) # Smoked dome.
	_b(p, 1, 2, 2, 2, 3, 4, M.RUBBER)
	_b(p, 4, 2, 2, 5, 3, 4, M.RUBBER)
	_b(p, 2, 2, 1, 4, 3, 2, M.RUBBER)
	_b(p, 2, 2, 4, 4, 3, 5, M.RUBBER)
	_b(p, 2, 0, 2, 4, 1, 4, M.GLASS) # Lens cap.
	_b(p, 3, 2, 1, 4, 3, 2, M.EMERGENCY) # Status light.
