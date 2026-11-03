class_name RangedShroom
extends Enemy
## The ranged shooter: a squat shroom with a wide mouth that keeps its distance. Farther than FAR
## from its target it walks in along the flow field; closer than NEAR it backs straight off (facing
## the target, never digging backwards); in between it holds. Every SPIT_INTERVAL, with a clear
## line of sight, it spits a slow green glob (a Projectile with the SPIT ammo settings, lobbed to
## land on the target) that does SPIT_DAMAGE and poisons the player it hits, and splats green
## where it lands.
##
## Enemies are host-owned, so the host simulates the glob (passing through other shrooms) and
## checks it against the players each tick; the peers get a visual copy (spawn, then the end with
## the splat), as Weapon does for its remote projectiles. Globs belong to the shroom that spat
## them and go with it.

const NEAR := 8.0
const FAR := 12.0
const SPIT_INTERVAL := 2.0
## Farthest it spits from.
const SPIT_RANGE := 30.0
const SPIT_DAMAGE := 12.0
const POISON_SECONDS := 3.0
## The glob, as AmmoType settings (AmmoType's fields; Projectile reads speed, gravity, reach,
## pierce and color).
const SPIT := {label = "Spit", color = Color(0.45, 1.0, 0.25), mode = "projectile", damage = SPIT_DAMAGE,
		speed = 12.0, gravity = 3.0, reach = 36.0, pierce = true, sound = "spit", kind = "spit"}
const SPLAT_COLOR := Color(0.35, 0.9, 0.2)
## Seconds a splat stays (fading out over the last of them).
const SPLAT_TIME := 5.0
const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")

## id -> Projectile, its globs in flight (host: the real ones, peers: copies).
var spits := {}
var _next_spit := 1
var _spit_timer := randf_range(0.6, SPIT_INTERVAL)
## Host: glob id -> where it was last tick (the swept segment for the player check).
var _spit_last := {}
## Host: backing off this tick (no digging backwards).
var _backing := false

static var _spit_type: AmmoType
static var _blob_material: StandardMaterial3D


## The kind's stats. Set in _ready (before the base), since instancing the scene resets exports
## to the base defaults after _init.
func _configure() -> void:
	kind = "ranged"
	max_health = 25.0
	speed = 2.4
	damage = 0.0
	attack_range = 0.0
	attack_sound = "spit"
	body_size = Vector3(0.9, 1.0, 0.9)


func _ready() -> void:
	_configure()
	super()


## The glob's settings as an AmmoType (shared).
static func spit_type() -> AmmoType:
	if _spit_type == null:
		_spit_type = AmmoType._make("spit", SPIT)
	return _spit_type


## Where globs leave from: the middle of its mouth, just in front of the body.
func mouth() -> Vector3:
	return global_position + Vector3.UP * bounds.size.y * 0.35 - global_basis.z * (bounds.size.z * 0.5 + 0.12)


# --- Host ----------------------------------------------------------------------------------------

func _think(delta: float) -> Dictionary:
	var out := {direction = Vector3.ZERO, facing = Vector3.ZERO, breach = false}
	_backing = false
	var target := manager.nearest_player(global_position)
	if target == null:
		return out
	var to_target := target.global_position - global_position
	var flat_to := Vector3(to_target.x, 0.0, to_target.z)
	var flat := flat_to.length()
	out.facing = flat_to
	if flat > FAR:
		var goal := target.global_position
		var flow: Dictionary = world.get_flow(global_position)
		if flow.valid and not flow.at_target:
			goal = flow.next
			out.breach = flow.breach
		var direction := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
		out.direction = direction.normalized() if direction.length() > 0.01 else Vector3.ZERO
	elif flat < NEAR and flat > 0.01:
		out.direction = -flat_to / flat
		_backing = true
	_spit_timer -= delta
	if _spit_timer <= 0.0:
		if flat < SPIT_RANGE and can_see(target):
			spit_at(target)
			_spit_timer = SPIT_INTERVAL
		else:
			_spit_timer = 0.25
	return out


func _breach(direction: Vector3) -> void:
	if _backing:
		_stuck_time = 0.0
		return
	super(direction)


## Host: a clear line (voxels only) from its mouth to the target's chest.
func can_see(target: Player) -> bool:
	var from := mouth()
	var to := _aim_point(target) - from
	var distance := to.length()
	if distance < 0.01:
		return true
	return not world.raycast(from, to / distance, distance).hit


func _aim_point(target: Player) -> Vector3:
	return target.global_position + Vector3.UP * target.get_body_size().y * 0.6


## Host: spits a glob lobbed to land on the target's chest, here and as a copy on every peer.
func spit_at(target: Player) -> void:
	var type := spit_type()
	var from := mouth()
	var offset := _aim_point(target) - from
	var flight := offset.length() / type.speed
	var velocity := offset / flight + Vector3.UP * 0.5 * type.gravity * flight
	var spit_id := _next_spit
	_next_spit += 1
	manager.enemy_attacked(self) # The spit sound and lunge, everywhere.
	_spawn_spit(spit_id, from, velocity, true)
	for peer_id in manager._peers():
		_spit_fired.rpc_id(peer_id, spit_id, from, velocity)


func _physics_process(delta: float) -> void:
	super(delta)
	if not alive or manager == null or not manager.simulating or spits.is_empty():
		return
	# Globs move after this (children tick after their parent), so this sweeps last tick's step.
	var players := manager.targets()
	for shot: Projectile in spits.values():
		if not is_instance_valid(shot) or shot.done:
			continue
		var at := shot.global_position
		var last: Vector3 = _spit_last.get(shot.id, at)
		_spit_last[shot.id] = at
		for player in players:
			var box := player.get_body_aabb().grow(0.12)
			if box.has_point(at) or box.intersects_segment(last, at) != null:
				_spit_hit(shot, player)
				break


func _spit_hit(shot: Projectile, player: Player) -> void:
	shot.done = true
	manager.damage_player(player, SPIT_DAMAGE, shot.global_position)
	manager.status_player(player, "poisoned", POISON_SECONDS)
	_end_spit(shot.id, shot.global_position, Vector3.ZERO)
	shot.queue_free()


func _on_spit_impacted(shot: Projectile, at: Vector3, normal: Vector3, _enemy: Enemy) -> void:
	_end_spit(shot.id, at, normal)


func _end_spit(spit_id: int, at: Vector3, normal: Vector3) -> void:
	_spit_last.erase(spit_id)
	splat(at, normal)
	for peer_id in manager._peers():
		_spit_ended.rpc_id(peer_id, spit_id, at, normal)


# --- Every peer ----------------------------------------------------------------------------------

func _spawn_spit(spit_id: int, from: Vector3, velocity: Vector3, host: bool) -> Projectile:
	var shot: Projectile = PROJECTILE_SCENE.instantiate()
	shot.name = "S%d" % spit_id
	shot.setup(spit_id, spit_type(), world, from, velocity, host)
	if host:
		shot.impacted.connect(_on_spit_impacted)
	shot.tree_exiting.connect(func() -> void:
		if spits.get(spit_id) == shot:
			spits.erase(spit_id))
	spits[spit_id] = shot
	add_child(shot)
	# A fat green glob instead of the shot's streak.
	(shot.get_node("Mesh") as MeshInstance3D).visible = false
	var blob := MeshInstance3D.new()
	blob.name = "Blob"
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * 0.15
	blob.mesh = cube
	if _blob_material == null:
		_blob_material = StandardMaterial3D.new()
		_blob_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blob_material.albedo_color = spit_type().color
	blob.material_override = _blob_material
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shot.add_child(blob)
	return shot


@rpc("authority", "reliable")
func _spit_fired(spit_id: int, from: Vector3, velocity: Vector3) -> void:
	_spawn_spit(spit_id, from, velocity, false)


@rpc("authority", "reliable")
func _spit_ended(spit_id: int, at: Vector3, normal: Vector3) -> void:
	var shot: Projectile = spits.get(spit_id)
	if shot:
		shot.queue_free()
	splat(at, normal)


## Every peer: a wet sound and, on a surface (normal not zero), a green splat that fades. Splats
## belong to the manager, so they outlive the shroom.
func splat(at: Vector3, normal: Vector3) -> void:
	play_sound("spit", at, -4.0, 0.1, 0.7)
	if normal == Vector3.ZERO or manager == null:
		return
	var disc := MeshInstance3D.new()
	# A ragged patch of voxel squares (VoxelFx.splat) that stays opaque, then shrinks away.
	disc.mesh = VoxelFx.splat(randf_range(0.2, 0.32))
	disc.material_override = VoxelFx.material(1.0, false, SPLAT_COLOR)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	manager.add_child(disc)
	var up := normal.normalized()
	disc.global_basis = Basis(Vector3.RIGHT, PI) if up.dot(Vector3.UP) < -0.99 else Basis(Quaternion(Vector3.UP, up))
	disc.global_position = at + up * 0.012
	var tween := disc.create_tween()
	tween.tween_interval(SPLAT_TIME - 1.5)
	tween.tween_property(disc, "scale", Vector3(0.01, 1.0, 0.01), 1.5)
	tween.tween_callback(disc.queue_free)
