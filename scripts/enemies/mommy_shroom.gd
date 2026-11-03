class_name MommyShroom
extends Enemy
## The mommy shroom: a huge, rooted brood mother. It never moves or bites; every spawn_interval
## seconds it squashes and births a basic shroom beside it (spawn_pop), up to brood_max of its brood
## alive at once (dead ones free a slot). Killing it pops every shroom it birthed. Placed with a
## horde spawner set to `kinds = mommy` (max_alive 1).

## Seconds between births.
@export var spawn_interval := 4.0
## Most of its brood alive at once.
@export var brood_max := 6
## The kind it births.
const BROOD_KIND := "basic"

## Host: ids of the shrooms it birthed that are still alive.
var brood: Array[int] = []

var _spawn_timer := 4.0


func _init() -> void:
	kind = "mommy"
	max_health = 200.0
	speed = 0.0
	knockback_scale = 0.0
	body_size = Vector3(2.0, 1.6, 2.0)
	damage = 0.0
	attack_range = 0.0
	attack_sound = "spawn_pop"


## Rooted: no chasing or attacking, it just turns to face the nearest player and births its brood.
func _think(delta: float) -> Dictionary:
	var out := {direction = Vector3.ZERO, facing = Vector3.ZERO, breach = false}
	brood.assign(brood.filter(func(e: int) -> bool: return manager.enemies.has(e)))
	var target := manager.nearest_player(global_position)
	if target:
		out.facing = Vector3(target.global_position.x - global_position.x, 0.0, target.global_position.z - global_position.z)
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = spawn_interval
		if brood.size() < brood_max:
			_birth()
	return out


## Host: one basic shroom on the floor beside it.
func _birth() -> void:
	var reach := maxf(bounds.size.x, bounds.size.z) * 0.5 + 0.5
	var feet := global_position
	for attempt in 6:
		var angle := randf() * TAU
		var probe := global_position + Vector3(cos(angle), 0.0, sin(angle)) * reach + Vector3.UP * 0.8
		var down: Dictionary = world.raycast(probe, Vector3.DOWN, 2.0)
		if not down.hit:
			continue
		var spot: Vector3 = down.position
		if not world.box_overlaps_solid(AABB(spot + Vector3(-0.35, 0.02, -0.35), Vector3(0.7, 1.2, 0.7))):
			feet = spot
			break
	var child := manager.spawn(BROOD_KIND, feet)
	if child:
		brood.append(child.id)
		manager.enemy_attacked(self) # The squash and spawn_pop on every peer (play_attack).


## Every peer: a birth (from enemy_attacked): a big squash instead of a lunge.
func play_attack() -> void:
	_squash = 1.0
	Sfx.play_at(attack_sound, get_center(), 0.0, 0.1)


## Every peer: dies; on the host, its whole brood pops with it.
func die() -> void:
	if not alive:
		return
	var host := manager != null and manager.simulating
	super()
	if host:
		for child_id in brood:
			manager.kill(child_id)
	brood.clear()
