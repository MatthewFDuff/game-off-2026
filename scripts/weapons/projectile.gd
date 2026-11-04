class_name Projectile
extends Node3D
## A shot that travels (explosive, ricochet, homing, poison, thrown flasks). Moved every
## physics tick by casting over the whole step (Combat.ray_hit on the shooter, world.raycast on
## the others), so it never tunnels through voxels or enemies however fast it goes.
##
## The shooting peer simulates it (`authoritative`): it finds the hits and hands them to its
## Weapon, which damages through EnemyManager.request_hit and carves through WorldSync. Every other
## peer runs a visual copy that never applies anything; the shooter's Weapon sends it the bounces,
## position corrections (homing) and the final impact, so the copies stay on the real path.

## Shooter only: it bounced off voxels at position (new velocity).
signal bounced(projectile: Projectile, position: Vector3, normal: Vector3)
## Shooter only: it hit an enemy (Combat.ray_hit result). Piercing shots keep going.
signal hit_enemy(projectile: Projectile, hit: Dictionary)
## Shooter only: it stopped. enemy is the Enemy it hit, or null (a voxel, or it ran out of time,
## with normal zero).
signal impacted(projectile: Projectile, position: Vector3, normal: Vector3, enemy: Enemy)

## Most sub-steps per tick (each bounce or pierced enemy starts one).
const MAX_STEPS := 8
## Small distance off a surface after a bounce, so the next cast doesn't start inside it.
const SURFACE_OFFSET := 0.02
## Homing: seconds between picks of the enemy to steer for (it turns toward the pick every tick).
const RETARGET := 0.1

var id := 0
var ammo: AmmoType
var world: VoxelWorld
var velocity := Vector3.ZERO
var authoritative := true
var bounces := 0
var age := 0.0
## Stopped (waiting to be freed, or on a copy, for the shooter's impact).
var done := false
## Enemies already hit (piercing shots damage each once).
var pierced: Array = []
## Flasks: the item model, tumbling in flight.
var _model: Node3D
## Shots: cubes left behind in flight.
var _trail: CPUParticles3D
## Homing: the enemy it steers for, and the time to the next re-check for a nearer one.
var _homing_target: Variant = null
var _retarget := 0.0
## Only explosive and homing shots carry a light (lit), made in _ready; null on the rest.
var _light: OmniLight3D

@onready var _mesh: MeshInstance3D = $Mesh


func setup(projectile_id: int, type: AmmoType, voxel_world: VoxelWorld, from: Vector3, start_velocity: Vector3, is_shooter: bool) -> void:
	id = projectile_id
	ammo = type
	world = voxel_world
	velocity = start_velocity
	authoritative = is_shooter
	top_level = true
	position = from


func _ready() -> void:
	# A grid-snapped cube (VoxelFx) that hops along in voxel steps, dropping a trail of smaller cubes.
	var color := ammo.color.lightened(0.3) if ammo else Color.WHITE
	_mesh.material_override = VoxelFx.shared_material((_mesh.mesh as BoxMesh).size.x, true, color)
	# Lights are a forward pass on every chunk they touch: only the shots that read as glowing get one.
	if lit(ammo):
		_light = OmniLight3D.new()
		_light.name = "Light"
		_light.light_energy = 1.5
		_light.omni_range = 2.5
		_light.omni_attenuation = 1.5
		_light.light_color = ammo.color
		add_child(_light)
	if ammo and ammo.flask and world:
		var item := GearModels.item(ammo.name)
		_model = GearModels.build(world, item, ammo.color, 0.03, Vector3(item.get("size", Vector3i.ZERO)) * 0.5)
		add_child(_model)
		_mesh.visible = false
	elif ammo:
		_trail = VoxelFx.particles(0.05, [color, ammo.color, ammo.color.darkened(0.5)], 0.3)
		_trail.name = "Trail"
		_trail.amount = 5 if OS.has_feature("web") else 10
		_trail.lifetime = 0.25
		_trail.spread = 180.0
		_trail.initial_velocity_max = 0.3
		add_child(_trail)
		_trail.emitting = true
	global_position = position
	_face()


## Whether shots of a type carry a light: explosive ("blast" impacts) and homing ones.
static func lit(type: AmmoType) -> bool:
	return type != null and not type.flask and (type.impact == "blast" or type.homing_angle > 0.0)


func _process(delta: float) -> void:
	if _model and not done:
		_model.rotate_x(-delta * 9.0)


func _physics_process(delta: float) -> void:
	if done or world == null or ammo == null:
		return
	age += delta
	if age > ammo.lifetime():
		_stop(global_position, Vector3.ZERO, null)
		return
	if ammo.homing_angle > 0.0:
		_steer(delta)
	velocity += Vector3.DOWN * ammo.gravity * delta
	var speed := velocity.length()
	if speed < 0.001:
		return
	var direction := velocity / speed
	var remaining := speed * delta
	var at := global_position
	for step in MAX_STEPS:
		var hit := _cast(at, direction, remaining)
		if not hit.hit:
			at += direction * remaining
			break
		remaining -= hit.distance
		if hit.enemy:
			hit_enemy.emit(self, hit)
			if not ammo.pierce:
				_stop(hit.position, hit.normal, hit.enemy)
				return
			pierced.append(hit.enemy)
			at = hit.position + direction * SURFACE_OFFSET
			continue
		if bounces >= ammo.bounces:
			global_position = hit.position
			_stop(hit.position, hit.normal, null)
			return
		bounces += 1
		direction = direction.bounce(hit.normal).normalized()
		velocity = direction * speed
		at = hit.position + hit.normal * SURFACE_OFFSET
		if authoritative:
			bounced.emit(self, at, hit.normal)
	global_position = at
	_face()


## The nearest hit along a step: voxels and (shooter only) enemies not yet pierced.
func _cast(from: Vector3, direction: Vector3, distance: float) -> Dictionary:
	if authoritative:
		return Combat.ray_hit(world, from, direction, distance, pierced)
	var voxel: Dictionary = world.raycast(from, direction, distance)
	if voxel.hit:
		return {hit = true, position = voxel.position, normal = voxel.normal, distance = voxel.distance, enemy = null}
	return {hit = false}


## Homing: turn toward the nearest enemy within homing_angle of the heading. With no target it
## looks every tick; a target it has is kept, re-checked for a nearer one every RETARGET seconds (or
## dropped at once when it dies or leaves the cone).
func _steer(delta: float) -> void:
	var speed := velocity.length()
	if speed < 0.001:
		return
	var heading := velocity / speed
	var cone := cos(deg_to_rad(ammo.homing_angle))
	_retarget -= delta
	var best: Enemy = null
	if _homing_target != null and Combat._hittable(_homing_target) and _in_cone(_homing_target, heading, cone):
		best = _homing_target
	# No target (none yet, or it died or left the cone): look every tick, as before. Only a target
	# it already has is re-checked for a nearer one at RETARGET.
	if best == null or _retarget <= 0.0:
		_retarget = RETARGET
		best = null
		var best_distance := INF
		for node: Variant in Combat._live():
			if not Combat._hittable(node):
				continue
			var enemy: Enemy = node
			var to := enemy.get_center() - global_position
			var distance := to.length()
			if distance < 0.01 or distance > best_distance or heading.dot(to / distance) < cone:
				continue
			best = enemy
			best_distance = distance
	_homing_target = best
	if best == null:
		return
	var wanted := (best.get_center() - global_position).normalized()
	var angle := heading.angle_to(wanted)
	if angle < 0.0001:
		return
	velocity = heading.slerp(wanted, minf(1.0, ammo.homing_turn * delta / angle)) * speed


func _in_cone(enemy: Enemy, heading: Vector3, cone: float) -> bool:
	var to := enemy.get_center() - global_position
	var distance := to.length()
	return distance >= 0.01 and heading.dot(to / distance) >= cone


## Shooter: stops and reports. Copies only hide and wait for the shooter's impact.
func _stop(at: Vector3, normal: Vector3, enemy: Enemy) -> void:
	done = true
	global_position = at
	if authoritative:
		impacted.emit(self, at, normal, enemy)
		queue_free()
	else:
		visible = false
		if _trail:
			_trail.emitting = false
		get_tree().create_timer(2.0).timeout.connect(queue_free)


## Copies: the shooter says where it really is (a bounce, or a homing correction).
func correct(at: Vector3, new_velocity: Vector3) -> void:
	global_position = at
	velocity = new_velocity
	_face()


## Shots are axis-aligned cubes (the shader snaps them), so there is nothing to turn; flasks tumble
## in _process.
func _face() -> void:
	pass
