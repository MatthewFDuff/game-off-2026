class_name FastShroom
extends Enemy
## The fast shroom: a lean, forward-tipped runner. Twice the basic shroom's speed and half its
## health, and once it's within ZIGZAG_RANGE of its target it weaves side to side (a sine offset
## across its heading), so it's hard to track as it closes. A quick, weaker bite.

## Meters from its target within which it zigzags.
const ZIGZAG_RANGE := 6.0
## Weaves per second, and how far across its heading it leans (0..1 of its wish direction).
const ZIGZAG_RATE := 1.4
const ZIGZAG_AMOUNT := 0.9

var _zigzag_phase := randf() * TAU


## The kind's stats. Set in _ready (before the base), since instancing the scene resets exports
## to the base defaults after _init.
func _configure() -> void:
	kind = "fast"
	max_health = 15.0
	speed = 5.0
	acceleration = 30.0
	damage = 8.0
	attack_range = 1.0
	attack_cooldown = 0.8
	attack_windup = 0.2
	attack_sound = "bite"
	body_size = Vector3(0.55, 1.1, 0.55)


func _ready() -> void:
	_configure()
	super()


func _think(delta: float) -> Dictionary:
	var out := super(delta)
	var direction: Vector3 = out.direction
	if direction == Vector3.ZERO:
		return out
	var target := manager.nearest_player(global_position)
	if target == null:
		return out
	var to_target := target.global_position - global_position
	var flat := Vector2(to_target.x, to_target.z).length()
	if flat > ZIGZAG_RANGE or flat < attack_range * 1.5:
		return out
	_zigzag_phase += delta * ZIGZAG_RATE * TAU
	var across := direction.cross(Vector3.UP).normalized()
	out.direction = (direction + across * sin(_zigzag_phase) * ZIGZAG_AMOUNT).normalized()
	return out
