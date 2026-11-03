class_name BasicShroom
extends Enemy
## The basic shroom: a grown hunter with glowing eyes. Small, slow and easy to kill, but it comes
## in numbers and is silent at range, so it can sneak up on you: it only chitters once it's within
## CHITTER_RANGE of a player (checked on each peer, against every player it knows of).

## Meters from the nearest player within which it chitters.
const CHITTER_RANGE := 6.0

var _chitter_time := randf_range(0.5, 3.0)


func _init() -> void:
	kind = "basic"
	max_health = 30.0
	speed = 2.5
	damage = 10.0
	attack_range = 1.1
	attack_cooldown = 1.0
	attack_sound = "bite"


func _process(delta: float) -> void:
	super(delta)
	if not alive or manager == null:
		return
	_chitter_time -= delta
	if _chitter_time > 0.0:
		return
	_chitter_time = randf_range(1.5, 4.0)
	var nearest := manager.nearest_player_distance(global_position)
	if nearest < CHITTER_RANGE:
		Sfx.play_at("shroom_chitter", get_center(), -10.0 + 6.0 * (1.0 - nearest / CHITTER_RANGE), 0.15)
