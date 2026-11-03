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

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _light: OmniLight3D = $Light


func setup(projectile_id: int, type: AmmoType, voxel_world: VoxelWorld, from: Vector3, start_velocity: Vector3, is_shooter: bool) -> void:
	id = projectile_id
	ammo = type
	world = voxel_world
	velocity = start_velocity
	authoritative = is_shooter
	top_level = true
	position = from


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = ammo.color.lightened(0.3) if ammo else Color.WHITE
	_mesh.material_override = material
	if ammo:
		_light.light_color = ammo.color
	if ammo and ammo.flask and world:
		var item := GearModels.item(ammo.name)
		_model = GearModels.build(world, item, ammo.color, 0.03, Vector3(item.get("size", Vector3i.ZERO)) * 0.5)
		add_child(_model)
		_mesh.visible = false
		_light.light_energy = 0.6
	global_position = position
	_face()


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


## Homing: turn toward the nearest enemy within homing_angle of the heading.
func _steer(delta: float) -> void:
	var speed := velocity.length()
	if speed < 0.001:
		return
	var heading := velocity / speed
	var best: Enemy = null
	var best_distance := INF
	var cone := cos(deg_to_rad(ammo.homing_angle))
	for enemy in Combat.enemies():
		var to := enemy.get_center() - global_position
		var distance := to.length()
		if distance < 0.01 or distance > best_distance or heading.dot(to / distance) < cone:
			continue
		best = enemy
		best_distance = distance
	if best == null:
		return
	var wanted := (best.get_center() - global_position).normalized()
	var angle := heading.angle_to(wanted)
	if angle < 0.0001:
		return
	velocity = heading.slerp(wanted, minf(1.0, ammo.homing_turn * delta / angle)) * speed


## Shooter: stops and reports. Copies only hide and wait for the shooter's impact.
func _stop(at: Vector3, normal: Vector3, enemy: Enemy) -> void:
	done = true
	global_position = at
	if authoritative:
		impacted.emit(self, at, normal, enemy)
		queue_free()
	else:
		visible = false
		get_tree().create_timer(2.0).timeout.connect(queue_free)


## Copies: the shooter says where it really is (a bounce, or a homing correction).
func correct(at: Vector3, new_velocity: Vector3) -> void:
	global_position = at
	velocity = new_velocity
	_face()


func _face() -> void:
	if velocity.length() > 0.01 and _mesh:
		var up := Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT
		_mesh.global_basis = Basis.looking_at(velocity, up) * Basis.from_scale(Vector3(1.0, 1.0, 2.5))
