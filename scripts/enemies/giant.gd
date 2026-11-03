class_name Giant
extends Enemy
## The giant: a huge, slow, tough shroom. Its swing hits every player in an arc in front of it
## (swing_reach, SWING_HALF_ANGLE) that it can see (Enemy.sees) with a heavy shove, and gouges the terrain where it lands. Its
## weak spot is the pair of antennae on top: a `crit` hit zone (5x damage) covering every voxel of
## the model at or above ANTENNA_FROM of its height. Once the crit zone has taken antenna_health
## damage, the antennae break off: the zone goes, those voxels leave the body's mesh on every peer
## (and for late joiners) and it staggers STAGGER_TIME seconds.

## Fraction of the model's height above which voxels are antennae (keep hand-made models' antennae
## up there, clear of the cap).
const ANTENNA_FROM := 0.6
const ANTENNA_CRIT := 5.0
const STAGGER_TIME := 1.5
## Degrees either side of its facing that the swing reaches.
const SWING_HALF_ANGLE := 65.0

## Damage the crit zone takes (after the multiplier) before the antennae break.
@export var antenna_health := 60.0
## Meters from its center the swing reaches (its body is about 0.8 m from center to edge).
@export var swing_reach := 2.8
## Shove (m/s) the swing gives a player on top of the usual hit push, and how much it lifts.
@export var swing_push := 9.0
@export var swing_lift := 3.5
## The gouge in front of it where the swing lands.
@export var swing_carve_radius := 0.6
@export var swing_carve_power := 2

## Every peer: the antennae are gone.
var antennae_broken := false
## Host: crit damage taken so far.
var antenna_damage := 0.0
## Host: seconds of stagger left.
var stagger := 0.0
## Every peer: seconds of the stagger wobble left.
var _wobble := 0.0


## The kind's stats. Set in _ready (before the base), since instancing the scene resets exports
## to the base defaults after _init.
func _configure() -> void:
	kind = "giant"
	max_health = 300.0
	speed = 1.2
	acceleration = 6.0
	step_height = 0.6
	body_size = Vector3(1.6, 2.6, 1.6)
	knockback_scale = 0.1
	damage = 30.0
	attack_range = 2.3
	attack_cooldown = 2.4
	attack_windup = 0.75
	attack_sound = "giant_slam"
	death_sound = "blast"
	breach_power = 2
	breach_radius = 1.0
	breach_reach = 0.9


func _ready() -> void:
	_configure()
	super()
	if manager:
		manager.enemy_damaged.connect(_on_enemy_damaged)
		if manager.lab:
			manager.lab.peer_entered.connect(_on_peer_entered)


## The model's mesh, minus the antennae once they've broken off.
func build_body() -> void:
	super()
	if antennae_broken and _mesh and world:
		var model := EnemyModels.model(kind, variant)
		if not model.is_empty():
			_mesh.mesh = world.build_model_mesh(model.size, without_antennae(model))


func _setup_hit_zones(model: Dictionary) -> void:
	if antennae_broken:
		return
	var box := antenna_box(model)
	if box.size != Vector3.ZERO:
		hit_zones["crit"] = {box = AABB(bounds.position + box.position * world.voxel_size, box.size * world.voxel_size), crit = ANTENNA_CRIT}


## The antennae's voxel box in the model (in voxels from its corner), zero size if it has none.
static func antenna_box(model: Dictionary) -> AABB:
	var size: Vector3i = model.size
	var voxels: PackedByteArray = model.voxels
	var low := Vector3i(size)
	var high := Vector3i(-1, -1, -1)
	for z in size.z:
		for y in range(floori(size.y * ANTENNA_FROM), size.y):
			for x in size.x:
				if voxels[x + y * size.x + z * size.x * size.y] != 0:
					low = low.min(Vector3i(x, y, z))
					high = high.max(Vector3i(x, y, z))
	if high.x < 0:
		return AABB()
	return AABB(Vector3(low), Vector3(high - low + Vector3i.ONE))


## The model's voxels with the antennae cleared.
static func without_antennae(model: Dictionary) -> PackedByteArray:
	var size: Vector3i = model.size
	var voxels: PackedByteArray = (model.voxels as PackedByteArray).duplicate()
	var start := floori(size.y * ANTENNA_FROM) * size.x
	for z in size.z:
		var layer := z * size.x * size.y
		for i in range(start, size.x * size.y):
			voxels[layer + i] = 0
	return voxels


# --- Host ----------------------------------------------------------------------------------------

func _think(delta: float) -> Dictionary:
	if stagger > 0.0:
		stagger -= delta
		_windup = 0.0
		return {direction = Vector3.ZERO, facing = Vector3.ZERO, breach = false}
	return super(delta)


## The swing: every player in the arc in front is hit and shoved, and the ground there gouged.
func _attack(_target: Player, _connects: bool) -> void:
	manager.enemy_attacked(self)
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var arc := cos(deg_to_rad(SWING_HALF_ANGLE))
	for player in manager.targets():
		var to := player.global_position - global_position
		if absf(to.y) > 2.0:
			continue
		to.y = 0.0
		var distance := to.length()
		if distance > swing_reach or (distance > 0.3 and forward.dot(to / distance) < arc):
			continue
		if not sees(player): # Never through a wall.
			continue
		var away := to / distance if distance > 0.3 else forward
		manager.damage_player(player, damage, global_position)
		shove(player, away * swing_push + Vector3.UP * swing_lift)
	if manager.world_sync:
		var point := global_position + forward * (body_size.x * 0.5 + 0.7) + Vector3.UP * 0.3
		manager.world_sync.carve_sphere(point, swing_carve_radius, swing_carve_power, -forward)


## Host: adds velocity to a player, on its own peer (each player runs its own movement).
func shove(player: Player, push: Vector3) -> void:
	var peer_id := player.get_multiplayer_authority()
	if peer_id == multiplayer.get_unique_id():
		player.velocity += push
	else:
		_shoved.rpc_id(peer_id, push)


@rpc("authority", "reliable")
func _shoved(push: Vector3) -> void:
	var me := manager.lab.local_player() if manager and manager.lab else null
	if me:
		me.velocity += push.limit_length(20.0)


func _on_enemy_damaged(enemy: Enemy, amount: float, zone: String) -> void:
	if enemy != self or zone != "crit" or antennae_broken or not alive:
		return
	antenna_damage += amount
	if antenna_damage >= antenna_health and health > 0.0:
		stagger = STAGGER_TIME
		_windup = 0.0
		show_antennae_broken()
		for peer_id in manager._peers():
			_antennae_broke.rpc_id(peer_id)


## Host: a late joiner gets the spawn from the manager first, then this.
func _on_peer_entered(peer_id: int) -> void:
	if multiplayer.is_server() and antennae_broken and alive and peer_id != 1:
		_antennae_broke.rpc_id(peer_id)


@rpc("authority", "reliable")
func _antennae_broke() -> void:
	show_antennae_broken()


# --- Every peer ----------------------------------------------------------------------------------

## The antennae snap off: the mesh loses them, they burst into debris, and it reels.
func show_antennae_broken() -> void:
	if antennae_broken:
		return
	antennae_broken = true
	_wobble = STAGGER_TIME
	var model := EnemyModels.model(kind, variant)
	var box := antenna_box(model) if not model.is_empty() else AABB()
	build_body()
	hit_zones.erase("crit")
	var at := global_transform * (bounds.position + (box.position + box.size * 0.5) * world.voxel_size) if box.size != Vector3.ZERO else get_center()
	play_sound("shroom_pop", at, 4.0, 0.05, 0.7)
	play_sound("melee_hit", at, 0.0, 0.05, 0.6)
	if manager and manager.debris:
		manager.debris.burst(at, Vector3.UP, {VoxelMaterials.SHROOM_GILL: 40, VoxelMaterials.SHROOM_EYE: 8})


func _process(delta: float) -> void:
	super(delta)
	if _wobble > 0.0 and _visual:
		_wobble = maxf(0.0, _wobble - delta)
		var t := _wobble / STAGGER_TIME
		_visual.rotation.z += sin(Time.get_ticks_msec() * 0.012) * 0.18 * t
		_visual.rotation.x += 0.12 * t
