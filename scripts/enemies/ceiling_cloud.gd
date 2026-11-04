class_name CeilingCloud
extends Enemy
## The ceiling poison cloud: a bulbous sac hanging from the ceiling. On its first host tick it
## climbs to the nearest ceiling voxel above where it spawned (spawners with `on_ceiling`, or any
## spawn point under a ceiling) and hangs there with no gravity. When a player passes within
## TRIGGER_RANGE underneath it (and in its sight, Combat.can_see), or it takes any damage, it drops: a poison Cloud on the floor below
## and a wet `burst`. If the voxel it hangs from is carved away it falls and bursts where it lands.
## Counterplay: shoot it from far off, so the cloud forms away from you.

## Horizontal meters from it a player under it sets it off.
const TRIGGER_RANGE := 2.5
## How far below it a player still counts as underneath.
const TRIGGER_DEPTH := 8.0
const CLOUD_RADIUS := 3.0
const CLOUD_SECONDS := 8.0
## The cloud forms this far above the floor below it.
const CLOUD_LIFT := 1.0

## Host: hanging from its ceiling voxel.
var attached := false
## Host: the ceiling voxel it hangs from.
var anchor_voxel := Vector3i.ZERO
## Host: it's falling (lost its ceiling); it bursts on landing.
var falling := false

var _placed := false
var _dropping := false


func _init() -> void:
	kind = "ceiling_cloud"
	max_health = 20.0
	speed = 0.0
	knockback_scale = 0.0
	damage = 0.0
	attack_range = 0.0
	body_size = Vector3(0.8, 0.9, 0.8)
	death_sound = "burst"


## Host: hangs, watches for players underneath and for its ceiling going.
func _physics_process(delta: float) -> void:
	if not alive or manager == null or not manager.simulating:
		return
	if not _placed:
		_placed = true
		# Emerging (a ceiling spawner): hang where it would, then drop in out of the ceiling to there.
		if emerging > 0.0:
			global_position = _emerge_goal
		attach()
		if emerging > 0.0:
			_emerge_goal = global_position
			global_position = _emerge_goal - Vector3.UP * EMERGE_DEPTH * emerge_from
	if _emerge_tick(delta):
		return
	_tick_statuses(delta)
	if not alive:
		return
	if _dropping:
		manager.kill(id)
		return
	if attached:
		if world.get_voxel(anchor_voxel) == 0:
			attached = false
			falling = true
		elif _player_below():
			manager.kill(id)
		return
	# Falling (or never found a ceiling): plain gravity, bursting when it lands after a fall.
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y -= gravity * delta
	var result: Dictionary = world.move_box(global_position, body_size, velocity * delta, 0.0, on_floor)
	global_position = result.position
	on_floor = result.on_floor
	if on_floor:
		velocity.y = 0.0
		if falling:
			manager.kill(id)
			return
	if global_position.y < KILL_HEIGHT:
		manager.despawn(id)


## Host: moves up to hang under the nearest ceiling above. Returns whether it found one.
func attach() -> bool:
	var ceiling: Dictionary = manager.ceiling_point(global_position + Vector3.UP * 0.1)
	if ceiling.is_empty():
		attached = false
		return false
	global_position = ceiling.position - Vector3.UP * bounds.size.y
	anchor_voxel = ceiling.voxel
	attached = true
	falling = false
	velocity = Vector3.ZERO
	return true


func _player_below() -> bool:
	for player in manager.frame_targets():
		var offset: Vector3 = player.global_position - global_position
		if offset.y < 0.0 and offset.y > -TRIGGER_DEPTH and Vector2(offset.x, offset.z).length() < TRIGGER_RANGE \
				and Combat.sees_player(world, get_center(), player):
			return true
	return false


## Host: any hit sets it off (on the next tick, so the hit itself still lands and flashes).
func _on_damaged(_amount: float, _kind: String, _peer: int) -> void:
	_dropping = true


## Every peer: bursts; on the host, the poison cloud forms on the floor below it.
func die() -> void:
	if not alive:
		return
	if manager != null and manager.simulating:
		var center := get_center()
		var down: Dictionary = world.raycast(center, Vector3.DOWN, 30.0)
		var floor_at: Vector3 = down.position if down.hit else center
		var at := floor_at + Vector3.UP * minf(CLOUD_LIFT, center.y - floor_at.y)
		Cloud.spawn("poison", at, CLOUD_RADIUS, CLOUD_SECONDS)
	super()


## Hangs still: a slow sway and a pulse instead of the walking bob.
func _animate(delta: float) -> void:
	super(delta)
	if _visual == null:
		return
	var t := Time.get_ticks_msec() * 0.002 + id * 1.3
	_visual.rotation.z = sin(t) * 0.05
	_visual.rotation.x = cos(t * 0.8) * 0.04
	var pulse := 1.0 + sin(t * 2.3) * 0.03
	_visual.scale *= Vector3(pulse, 1.0 / pulse, pulse)
