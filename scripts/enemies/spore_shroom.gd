class_name SporeShroom
extends Enemy
## The spore shroom: a slow puffball. When a player comes within RELEASE_RANGE (every
## RELEASE_COOLDOWN at most), and when it dies, it vents a `spore` Cloud around itself that blinds
## the players inside (Player fogs their screen) without hurting them. Kill it from range so the
## spores burst far away.

const RELEASE_RANGE := 4.0
## Seconds between releases (the cloud's lifetime, so they don't stack).
const RELEASE_COOLDOWN := 8.0
const CLOUD_RADIUS := 4.0
const CLOUD_SECONDS := 8.0

var _release_timer := 0.0


func _init() -> void:
	kind = "spore"
	max_health = 25.0
	speed = 1.5
	damage = 5.0
	attack_range = 1.1
	attack_cooldown = 1.2
	body_size = Vector3(0.8, 1.0, 0.8)
	attack_sound = "bite"


func _think(delta: float) -> Dictionary:
	_release_timer -= delta
	if _release_timer <= 0.0 and manager.nearest_player_distance(global_position) < RELEASE_RANGE:
		release()
	return super(delta)


## Host: vents a spore cloud around it.
func release() -> void:
	_release_timer = RELEASE_COOLDOWN
	_squash = 1.0
	Cloud.spawn("spore", get_center(), CLOUD_RADIUS, CLOUD_SECONDS)


## Every peer: dies; on the host it vents its spores one last time.
func die() -> void:
	if not alive:
		return
	if manager != null and manager.simulating:
		Cloud.spawn("spore", get_center(), CLOUD_RADIUS, CLOUD_SECONDS)
	super()
