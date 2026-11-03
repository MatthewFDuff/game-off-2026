class_name Enemy
extends Node3D
## Base for every enemy. The host simulates it (EnemyManager.simulating): it follows the world's
## flow field toward the nearest player, digs through soft voxels when blocked, and attacks in
## melee range. Every other peer only draws it, interpolating the position and yaw the manager
## streams at ~10 Hz. The node's position is its feet (bottom center of its collision box), and the
## body faces -Z.
##
## Subclasses (one per kind, see EnemyManager.KINDS) change the stats in _init and override
## _setup_hit_zones, _attack or _think for their behavior. The body is the kind's .vox model
## (EnemyModels), live-reloaded.

const GROUP := "enemies"
## Peers draw enemies this far in the past, so there's always a newer state to blend toward.
const REMOTE_DELAY := 0.15
## Below this height (meters) an enemy has fallen out of the level and is removed.
const KILL_HEIGHT := -20.0

@export var kind := "basic"
@export var max_health := 30.0
@export var speed := 2.5
@export var acceleration := 20.0
@export var gravity := 16.0
@export var step_height := 0.45
## Collision box (width, height, depth); hits use the model's bounds instead.
@export var body_size := Vector3(0.7, 1.2, 0.7)
## How much hits push it around (0 = immovable).
@export var knockback_scale := 1.0

@export_group("Attack")
@export var damage := 10.0
@export var attack_range := 1.1
@export var attack_cooldown := 1.0
## Seconds it rears back before an attack lands, so players can see it coming.
@export var attack_windup := 0.3
@export var attack_sound := "bite"

@export_group("Breaching")
## Voxels at or below this hardness can be dug through.
@export var breach_power := 2
@export var breach_radius := 0.55
## How far ahead of its feet the dig is centered.
@export var breach_reach := 0.5
@export var breach_cooldown := 0.6
## Seconds of failing to move before it starts digging.
@export var stuck_threshold := 0.4

@export_group("Feedback")
@export var hit_flash_time := 0.1
@export var hit_flash_color := Color(1.0, 1.0, 1.0, 0.7)

## Unique per session, the same on every peer (the node is named after it).
var id := 0
## Which of the kind's models it wears (the same on every peer).
var variant := 0
var manager: EnemyManager
var world: VoxelWorld
var health := 0.0
## False once dying; dead enemies are ignored by hit tests.
var alive := true
var velocity := Vector3.ZERO
var on_floor := false
## Named parts that take extra damage: name -> {box: AABB (local: feet at the origin, facing -Z),
## crit: float}. Anything else inside bounds is the "body" (crit 1).
var hit_zones := {}
## The model's box in local space.
var bounds := AABB(Vector3(-0.35, 0.0, -0.35), Vector3(0.7, 1.2, 0.7))

var _visual: Node3D
var _mesh: MeshInstance3D
var _flash := 0.0
var _squash := 0.0
var _strike := 0.0
var _windup := 0.0
var _attack_timer := 0.0
var _breach_timer := 0.0
var _stuck_time := 0.0
## Peers: received [time, position, yaw], oldest first.
var _remote_states: Array[Array] = []
var _last_position := Vector3.ZERO
var _move_speed := 0.0

## "kind:variant" -> ArrayMesh, shared by every enemy wearing that model.
static var _meshes := {}
static var _flash_material: StandardMaterial3D


func _ready() -> void:
	add_to_group(GROUP)
	health = max_health
	_visual = get_node_or_null("Visual")
	if _visual == null:
		_visual = Node3D.new()
		_visual.name = "Visual"
		add_child(_visual)
	build_body()
	_last_position = global_position


## (Re)builds the body mesh from the kind's model, and the bounds and hit zones from its size.
func build_body() -> void:
	if world == null:
		return
	var model := EnemyModels.model(kind, variant)
	if model.is_empty():
		return
	var key := "%s:%d" % [kind, variant]
	if not _meshes.has(key):
		_meshes[key] = world.build_model_mesh(model.size, model.voxels)
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_visual.add_child(_mesh)
	_mesh.mesh = _meshes[key]
	_mesh.material_override = world.material
	var size := Vector3(model.size) * world.voxel_size
	_mesh.position = Vector3(-size.x * 0.5, 0.0, -size.z * 0.5)
	bounds = AABB(_mesh.position, size)
	hit_zones.clear()
	_setup_hit_zones(model)


## Live reload: drop the cached meshes so build_body reads the new files.
static func forget_meshes(of_kind: String) -> void:
	for key: String in _meshes.keys():
		if key.begins_with(of_kind + ":"):
			_meshes.erase(key)


## Subclasses add named hit zones here (crit spots), sized from the model.
func _setup_hit_zones(_model: Dictionary) -> void:
	pass


## Center of the body, for distances and effects.
func get_center() -> Vector3:
	return global_position + Vector3.UP * bounds.size.y * 0.5


## The model's box in world space (turned with the enemy, so slightly larger when not square on).
func world_bounds() -> AABB:
	return global_transform * bounds


## Where a ray (normalized direction) first meets this enemy: {distance, position, normal, zone,
## crit}, or {} on a miss. Named zones win over the body.
func ray_test(from: Vector3, direction: Vector3) -> Dictionary:
	var inverse := global_transform.affine_inverse()
	var local_from := inverse * from
	var local_dir := (inverse.basis * direction).normalized()
	var body := _ray_box(bounds, local_from, local_dir)
	if body.is_empty():
		return {}
	var best := {}
	for zone_name: String in hit_zones:
		var zone: Dictionary = hit_zones[zone_name]
		var hit := _ray_box(zone.box, local_from, local_dir)
		if not hit.is_empty() and (best.is_empty() or hit.t < best.t):
			best = hit
			best.zone = zone_name
			best.crit = zone.get("crit", 1.0)
	if best.is_empty():
		best = body
		best.zone = "body"
		best.crit = 1.0
	return {distance = best.t, position = global_transform * (local_from + local_dir * best.t),
			normal = (global_basis * best.normal).normalized(), zone = best.zone, crit = best.crit}


## The zone containing a world point (where a shot landed), "body" if none.
func zone_at(point: Vector3) -> String:
	var local := global_transform.affine_inverse() * point
	for zone_name: String in hit_zones:
		if (hit_zones[zone_name].box as AABB).grow(0.05).has_point(local):
			return zone_name
	return "body"


## Slab test: {t, normal} where the ray enters the box (t = 0 when it starts inside), or {}.
static func _ray_box(box: AABB, from: Vector3, dir: Vector3) -> Dictionary:
	var t_near := -INF
	var t_far := INF
	var normal := Vector3.ZERO
	for axis in 3:
		var low: float = box.position[axis]
		var high: float = box.end[axis]
		if absf(dir[axis]) < 0.000001:
			if from[axis] < low or from[axis] > high:
				return {}
			continue
		var t1: float = (low - from[axis]) / dir[axis]
		var t2: float = (high - from[axis]) / dir[axis]
		if t1 > t2:
			var swap := t1
			t1 = t2
			t2 = swap
		if t1 > t_near:
			t_near = t1
			normal = Vector3.ZERO
			normal[axis] = -signf(dir[axis])
		t_far = minf(t_far, t2)
		if t_near > t_far or t_far < 0.0:
			return {}
	if t_near < 0.0:
		return {t = 0.0, normal = -dir}
	return {t = t_near, normal = normal}


# --- Host simulation -----------------------------------------------------------------------------

## Host: takes a hit (EnemyManager applies the crit multiplier first). push is the knockback.
func apply_hit(amount: float, push: Vector3) -> void:
	health -= amount
	velocity += push * knockback_scale
	_squash = 1.0


func _physics_process(delta: float) -> void:
	if not alive or manager == null or not manager.simulating:
		return
	_attack_timer -= delta
	_breach_timer -= delta
	var think := _think(delta)
	var direction: Vector3 = think.direction
	direction += manager.separation(self) * 0.8
	if direction.length() > 1.0:
		direction = direction.normalized()

	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(direction * speed, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y -= gravity * delta

	var start := global_position
	var result: Dictionary = world.move_box(start, body_size, velocity * delta, step_height, on_floor)
	global_position = result.position
	on_floor = result.on_floor
	if (on_floor and velocity.y < 0.0) or (result.hit_ceiling and velocity.y > 0.0):
		velocity.y = 0.0

	var moved := Vector2(global_position.x - start.x, global_position.z - start.z).length()
	var intended := Vector2(velocity.x, velocity.z).length() * delta
	if direction.length() > 0.3 and moved < intended * 0.3:
		_stuck_time += delta
	else:
		_stuck_time = maxf(0.0, _stuck_time - delta * 2.0)
	if result.hit_wall:
		var actual := (global_position - start) / delta
		velocity.x = actual.x
		velocity.z = actual.z
	if (_stuck_time > stuck_threshold or (think.breach and result.hit_wall)) and _breach_timer <= 0.0:
		_breach(direction)

	var facing: Vector3 = think.facing
	if facing.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-facing.x, -facing.z), 1.0 - exp(-10.0 * delta))
	if global_position.y < KILL_HEIGHT:
		manager.despawn(id)


## Host, every physics tick: decides where to go. Returns {direction (horizontal, length <= 1),
## facing, breach (the path ahead is through a barricade)}. The default chases the nearest player
## along the flow field and attacks in range.
func _think(delta: float) -> Dictionary:
	var out := {direction = Vector3.ZERO, facing = Vector3.ZERO, breach = false}
	var target := manager.nearest_player(global_position)
	if target == null:
		_windup = 0.0
		return out
	var to_target := target.global_position - global_position
	var flat := Vector2(to_target.x, to_target.z).length()
	out.facing = Vector3(to_target.x, 0.0, to_target.z)
	var in_reach := flat < attack_range and absf(to_target.y) < 1.6
	if _windup > 0.0:
		# Committed: hold still, then land it only if the target didn't back off.
		_windup -= delta
		if _windup <= 0.0:
			_windup = 0.0
			_attack_timer = attack_cooldown
			_attack(target, flat < attack_range * 1.25 and absf(to_target.y) < 1.6)
		return out
	if in_reach:
		if _attack_timer <= 0.0:
			_windup = attack_windup
		return out
	var goal := target.global_position
	if flat > 2.0:
		var flow: Dictionary = world.get_flow(global_position)
		if flow.valid and not flow.at_target:
			goal = flow.next
			out.breach = flow.breach
	var direction := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	out.direction = direction.normalized() if direction.length() > 0.01 else Vector3.ZERO
	if out.direction != Vector3.ZERO:
		out.facing = out.direction
	return out


## Host: the wind-up finished. connects is false when the target got out of reach in time.
func _attack(target: Player, connects: bool) -> void:
	manager.enemy_attacked(self)
	if connects:
		manager.damage_player(target, damage, global_position)


## Host: digs a body-sized hole ahead (through WorldSync, so every peer's world agrees).
func _breach(direction: Vector3) -> void:
	_breach_timer = breach_cooldown
	var forward := (direction if direction.length() > 0.1 else -global_basis.z).normalized()
	forward.y = 0.0
	# Centered above the floor so it never digs the ground away.
	var point := global_position + forward * breach_reach + Vector3.UP * (breach_radius + 0.08)
	manager.world_sync.carve_sphere(point, breach_radius, breach_power, -forward)
	if on_floor:
		velocity.y = 3.5 # Hop, in case it's a ledge it can't dig.
	_stuck_time = 0.0


# --- Every peer ----------------------------------------------------------------------------------

## Peers: a state from the host.
func push_state(feet: Vector3, yaw: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _remote_states.is_empty():
		global_position = feet
		rotation.y = yaw
	_remote_states.append([now, feet, yaw])
	if _remote_states.size() > 12:
		_remote_states.pop_front()


func _interpolate_remote() -> void:
	if _remote_states.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0 - REMOTE_DELAY
	var newest: Array = _remote_states.back()
	var a: Array = newest
	var b: Array = newest
	for i in range(_remote_states.size() - 1, 0, -1):
		if _remote_states[i - 1][0] <= t:
			a = _remote_states[i - 1]
			b = _remote_states[i]
			break
	var span: float = b[0] - a[0]
	var f := clampf((t - a[0]) / span, 0.0, 1.0) if span > 0.0 else 1.0
	global_position = (a[1] as Vector3).lerp(b[1], f)
	rotation.y = lerp_angle(a[2], b[2], f)


func _process(delta: float) -> void:
	if manager and not manager.simulating:
		_interpolate_remote()
	var step := global_position - _last_position
	_last_position = global_position
	if delta > 0.0:
		_move_speed = lerpf(_move_speed, Vector2(step.x, step.z).length() / delta, 1.0 - exp(-10.0 * delta))
	_animate(delta)


## Every peer: white flash and squash (a hit landed).
func flash() -> void:
	_flash = hit_flash_time
	_squash = 1.0
	if _mesh:
		if _flash_material == null:
			_flash_material = StandardMaterial3D.new()
			_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.albedo_color = hit_flash_color
		_mesh.material_overlay = _flash_material


## Every peer: the attack lands (sound, lunge).
func play_attack() -> void:
	_strike = 1.0
	if attack_sound != "":
		Sfx.play_at(attack_sound, get_center(), -4.0, 0.1)


## Every peer: pops into debris and frees itself.
func die() -> void:
	if not alive:
		return
	alive = false
	remove_from_group(GROUP)
	Sfx.play_at("shroom_pop", get_center())
	if manager and manager.debris:
		manager.debris.burst(get_center(), Vector3.UP, _debris_counts())
	queue_free()


## Material id -> voxel count of the body, for the death burst.
func _debris_counts() -> Dictionary:
	var counts := {}
	var model := EnemyModels.model(kind, variant)
	var voxels: PackedByteArray = model.get("voxels", PackedByteArray())
	for i in voxels.size():
		if voxels[i] != 0:
			counts[voxels[i]] = counts.get(voxels[i], 0) + 1
	return counts


func _animate(delta: float) -> void:
	if _visual == null:
		return
	var ratio := clampf(_move_speed / maxf(speed, 0.1), 0.0, 1.5)
	var t := Time.get_ticks_msec() * 0.012 + id * 1.7
	_visual.position.y = absf(sin(t)) * 0.08 * ratio
	_visual.rotation.z = sin(t) * 0.12 * ratio
	# Rear back through the wind-up (host only knows it), snap forward on the attack.
	var rear := 1.0 - _windup / attack_windup if _windup > 0.0 and attack_windup > 0.0 else 0.0
	_strike = maxf(0.0, _strike - delta * 6.0)
	_visual.rotation.x = rear * rear * 0.45 - _strike * 0.35
	var grow := 1.0 + rear * 0.12
	# Hit squash: wide and short, springing back with a little overshoot.
	_squash = maxf(0.0, _squash - delta * 5.0)
	var squish := cos((1.0 - _squash) * PI * 1.5) * _squash
	_visual.scale = Vector3(grow * (1.0 + squish * 0.25), grow * (1.0 - squish * 0.2), grow * (1.0 + squish * 0.25))
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0 and _mesh:
			_mesh.material_overlay = null
