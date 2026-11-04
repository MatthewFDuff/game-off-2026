class_name AlarmShroom
extends Enemy
## The alarm shroom: a tall stem with a trumpet for a cap, rooted to the spot. It never chases or
## bites. Every LOOK_INTERVAL the host checks for a line of sight (Combat.can_see: voxels, glass is clear) from
## its trumpet to each living player within SIGHT_RANGE; on seeing one it winds up a scream
## (WINDUP seconds, pulsing red), then calls a horde (HordeDirector.start_horde) and tells everyone.
## Hitting it during the wind-up chokes the scream off. After a scream it rests COOLDOWN seconds.

const SIGHT_RANGE := 25.0
const LOOK_INTERVAL := 0.5
const WINDUP := 1.5
const COOLDOWN := 30.0
## Seconds before it can try again after being interrupted.
const INTERRUPT_COOLDOWN := 4.0
const PULSE_COLOR := Color(1.0, 0.1, 0.08, 0.6)
## What every peer shows (_scream_state).
enum Scream { CHOKED, WINDING_UP, SCREAMED }

## Horde size it calls (0: the director's own horde_size).
@export var horde_count := 0

## Host: seconds of wind-up left, below zero when not screaming.
var scream := -1.0
## Host: seconds before it looks again after a scream.
var cooldown := 0.0
var _look := 0.0
## Every peer: seconds of red pulse left.
var _pulse := 0.0

static var _pulse_material: StandardMaterial3D


## The kind's stats. Set in _ready (before the base), since instancing the scene resets exports
## to the base defaults after _init.
func _configure() -> void:
	kind = "alarm"
	max_health = 40.0
	speed = 0.0
	damage = 0.0
	attack_range = 0.0
	attack_sound = ""
	knockback_scale = 0.0
	body_size = Vector3(0.6, 2.4, 0.6)


func _ready() -> void:
	_configure()
	super()
	if manager:
		manager.enemy_damaged.connect(_on_enemy_damaged)


## Rooted: it never digs.
func _breach(_direction: Vector3) -> void:
	_stuck_time = 0.0


func _think(_delta: float) -> Dictionary:
	var out := {direction = Vector3.ZERO, facing = Vector3.ZERO, breach = false}
	var target := manager.nearest_player(global_position)
	if target and target.global_position.distance_to(global_position) < SIGHT_RANGE:
		var to_target := target.global_position - global_position
		out.facing = Vector3(to_target.x, 0.0, to_target.z)
	return out


func _physics_process(delta: float) -> void:
	super(delta)
	if not alive or manager == null or not manager.simulating or emerging > 0.0:
		return
	if scream >= 0.0:
		scream -= delta
		if scream <= 0.0:
			scream = -1.0
			cooldown = COOLDOWN
			_call_horde()
		return
	cooldown -= delta
	if cooldown > 0.0:
		return
	_look -= delta
	if _look > 0.0:
		return
	_look = LOOK_INTERVAL
	if sees_player():
		scream = WINDUP
		_broadcast(Scream.WINDING_UP)


## Host: whether any living player within SIGHT_RANGE is in clear view of the trumpet.
func sees_player() -> bool:
	var mouth := global_position + Vector3.UP * (bounds.size.y - 0.15)
	for player in manager.frame_targets():
		var eye := player.global_position + Vector3.UP * player.get_body_size().y * 0.85
		var to := eye - mouth
		var distance := to.length()
		if distance > SIGHT_RANGE or distance < 0.01:
			continue
		if Combat.can_see(world, mouth, eye):
			return true
	return false


func _call_horde() -> void:
	_broadcast(Scream.SCREAMED)
	var lab := manager.lab
	if lab == null:
		return
	if lab.director:
		lab.director.start_horde(horde_count if horde_count > 0 else lab.director.horde_size)
	lab.notify("An alarm shroom screamed. A horde is coming!")


## Host: a hit during the wind-up chokes the scream.
func _on_enemy_damaged(enemy: Enemy, _amount: float, _zone: String) -> void:
	if enemy != self or scream < 0.0 or not alive:
		return
	scream = -1.0
	cooldown = INTERRUPT_COOLDOWN
	_broadcast(Scream.CHOKED)


func _broadcast(state: Scream) -> void:
	show_scream(state)
	for peer_id in manager._peers():
		_scream_state.rpc_id(peer_id, state)


@rpc("authority", "reliable")
func _scream_state(state: int) -> void:
	show_scream(state as Scream)


## Every peer: the wind-up (shriek and red pulse), its end, or being choked off.
func show_scream(state: Scream) -> void:
	match state:
		Scream.WINDING_UP:
			_pulse = WINDUP
			play_sound("shroom_scream", get_center() + Vector3.UP * bounds.size.y * 0.4, 4.0, 0.05)
		Scream.SCREAMED:
			_pulse = 0.0
			Sfx.play_at("alarm", get_center(), 2.0, 0.05, 0.8)
		_:
			_pulse = 0.0
			play_sound("shroom_hit", get_center(), 0.0, 0.1, 0.6)
	if _pulse <= 0.0 and _mesh:
		_mesh.material_overlay = tint_material()


func _process(delta: float) -> void:
	super(delta)
	if _pulse <= 0.0 or _mesh == null:
		return
	_pulse -= delta
	if _pulse <= 0.0:
		_mesh.material_overlay = tint_material()
		return
	if _pulse_material == null:
		_pulse_material = StandardMaterial3D.new()
		_pulse_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_pulse_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var built := 1.0 - _pulse / WINDUP
	var wave := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU * lerpf(3.0, 9.0, built))
	var color := PULSE_COLOR
	color.a *= 0.3 + 0.7 * wave
	_pulse_material.albedo_color = color
	_mesh.material_overlay = _pulse_material
	# The trumpet swells and shudders as the scream builds.
	_visual.scale *= Vector3(1.0 + wave * 0.05, 1.0 + built * 0.12, 1.0 + wave * 0.05)
	_visual.rotation.z += sin(Time.get_ticks_msec() * 0.05) * 0.03 * built
