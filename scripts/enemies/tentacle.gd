class_name Tentacle
extends Enemy
## Tentacle fungi: a rooted mass with tentacles reaching up into the air. Every GRAB_INTERVAL it
## looks for the nearest player within REACH (and in sight) who isn't already held and grabs them
## (tentacle_grab): the player's own peer drags them toward it at Player.HELD_PULL m/s and holds
## them there (no walking or jumping; shooting, melee and throwing still work), and once they're
## within HOLD_RANGE it squeezes for SQUEEZE_DPS. It lets go when it has taken BREAK_DAMAGE since
## the grab, when another player melees it, or when it dies. The hold is host-authoritative
## (EnemyManager.hold_player).

const REACH := 3.5
const GRAB_INTERVAL := 0.3
## Meters (horizontal, its center to the player's feet) within which the held player is squeezed;
## a little over Player.HELD_CLOSE to allow for the replicated position lagging.
const HOLD_RANGE := 1.2
const SQUEEZE_DPS := 8.0
## Squeeze damage lands in steps this many seconds apart.
const SQUEEZE_TICK := 0.5
## Damage since the grab that makes it let go.
const BREAK_DAMAGE := 40.0
## Seconds a released player can't be grabbed again by it, to get clear.
const REGRAB_COOLDOWN := 2.0

## Host: the player it holds, or null.
var held: Player = null
## Host: damage taken since the current grab.
var damage_since_grab := 0.0

var _grab_timer := 0.0
var _squeeze_timer := 0.0
## Host: the player it last let go of, and until when (msec) it leaves them alone.
var _released: Player = null
var _released_until := 0


func _init() -> void:
	kind = "tentacle"
	max_health = 120.0
	speed = 0.0
	knockback_scale = 0.0
	damage = 0.0
	attack_range = 0.0
	body_size = Vector3(1.2, 2.2, 1.2)
	attack_sound = "tentacle_grab"


func _think(delta: float) -> Dictionary:
	var out := {direction = Vector3.ZERO, facing = Vector3.ZERO, breach = false}
	if held != null and (not is_instance_valid(held) or held.is_dead or held.editing or not held.is_held()):
		release()
	if held == null:
		_grab_timer -= delta
		if _grab_timer <= 0.0:
			_grab_timer = GRAB_INTERVAL
			_try_grab()
		return out
	var offset := held.global_position - global_position
	out.facing = Vector3(offset.x, 0.0, offset.z)
	if Vector2(offset.x, offset.z).length() <= HOLD_RANGE:
		_squeeze_timer -= delta
		if _squeeze_timer <= 0.0:
			_squeeze_timer = SQUEEZE_TICK
			manager.damage_player(held, SQUEEZE_DPS * SQUEEZE_TICK, global_position)
	return out


## Host: grabs the nearest free player in reach.
func _try_grab() -> void:
	var best: Player = null
	var best_distance := REACH
	for player in manager.frame_targets():
		if player.is_held() or (player == _released and Time.get_ticks_msec() < _released_until):
			continue
		var offset := player.global_position - global_position
		var distance := Vector2(offset.x, offset.z).length()
		if distance < best_distance and absf(offset.y) < 2.0 and sees(player):
			best_distance = distance
			best = player
	if best:
		grab(best)


## Host: holds player.
func grab(player: Player) -> void:
	held = player
	damage_since_grab = 0.0
	_squeeze_timer = SQUEEZE_TICK
	manager.hold_player(player, id, global_position)
	manager.enemy_attacked(self) # tentacle_grab and a lunge on every peer.


## Host: lets go of whoever it holds.
func release() -> void:
	if held != null and is_instance_valid(held):
		if held.held_by == str(id):
			manager.hold_player(held, 0, Vector3.ZERO)
		_released = held
		_released_until = Time.get_ticks_msec() + int(REGRAB_COOLDOWN * 1000.0)
	held = null
	damage_since_grab = 0.0
	_grab_timer = GRAB_INTERVAL


## Host: enough damage, or a partner's melee (anyone but the held player's own peer), frees them.
func _on_damaged(amount: float, damage_kind: String, peer: int) -> void:
	if held == null:
		return
	damage_since_grab += amount
	var partner_melee := damage_kind == "melee" and peer != 0 and is_instance_valid(held) and peer != held.get_multiplayer_authority()
	if damage_since_grab >= BREAK_DAMAGE or partner_melee:
		release()


## Every peer: dies; on the host it lets go first.
func die() -> void:
	if not alive:
		return
	if manager != null and manager.simulating:
		release()
	super()


## Rooted: no walking bob; a slow writhe instead.
func _animate(delta: float) -> void:
	super(delta)
	if _visual == null:
		return
	var t := Time.get_ticks_msec() * 0.003 + id * 0.9
	_visual.rotation.y = sin(t) * 0.08
