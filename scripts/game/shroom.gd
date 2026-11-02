class_name Shroom
extends Node3D
## A grown mushroom that hunts the player. Follows the world's flow field, attacks in melee, and
## digs through soft voxels (planks, dirt) when something blocks its way.

signal died(shroom: Shroom)

@export var max_health := 60.0
@export var speed := 3.0
@export var acceleration := 25.0
@export var gravity := 16.0
@export var step_height := 0.45
@export var body_size := Vector3(0.7, 1.2, 0.7)

@export_group("Attack")
@export var attack_range := 1.1
@export var attack_damage := 12.0
@export var attack_cooldown := 0.9

@export_group("Breaching")
## Voxels at or below this hardness can be chewed through.
@export var breach_power := 2
## Extra room cut around the body so it doesn't snag on the edges of its own hole.
@export var breach_margin := 0.1
## How far ahead of its feet the bite is centered.
@export var breach_reach := 0.5
@export var breach_cooldown := 0.45
## Seconds of failing to move before it starts digging.
@export var stuck_threshold := 0.35

var world: VoxelWorld
var player: Player
var manager: ShroomManager
var health := max_health
var velocity := Vector3.ZERO
var on_floor := false

var _attack_timer := 0.0
var _breach_timer := 0.0
var _stuck_time := 0.0
var _flash := 0.0
var _visual := Node3D.new()


func setup(manager_node: ShroomManager, variant: int) -> void:
	manager = manager_node
	health = max_health
	var model := manager.get_model(ShroomModels.MAX_STAGE, variant, true)
	var mesh := MeshInstance3D.new()
	mesh.mesh = model.mesh
	mesh.position = model.offset
	mesh.material_override = manager.get_material()
	_visual.add_child(mesh)
	add_child(_visual)


## Center of the body, for distance checks.
func get_center() -> Vector3:
	return global_position + Vector3.UP * body_size.y * 0.5


## Distance along a normalized ray to this shroom, or -1 on a miss. The body is two spheres.
func hit_test(origin: Vector3, direction: Vector3) -> float:
	var best := -1.0
	for sphere in [[0.45, 0.45], [0.95, 0.5]]:
		var t := _ray_sphere(origin, direction, global_position + Vector3.UP * sphere[0], sphere[1])
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


func take_damage(amount: float, push: Vector3 = Vector3.ZERO) -> void:
	if health <= 0.0:
		return
	health -= amount
	_flash = 1.0
	velocity += push
	if health <= 0.0:
		died.emit(self)
		queue_free()


func _physics_process(delta: float) -> void:
	if world == null or player == null:
		return
	_attack_timer -= delta
	_breach_timer -= delta

	var to_player := player.global_position - global_position
	var flat_distance := Vector2(to_player.x, to_player.z).length()
	var direction := Vector3.ZERO
	var wants_breach := false

	if flat_distance < attack_range and absf(to_player.y) < 1.6:
		if _attack_timer <= 0.0 and not player.is_dead:
			_attack_timer = attack_cooldown
			player.take_damage(attack_damage, global_position)
	else:
		var target := player.global_position
		if flat_distance > 2.5:
			var flow: Dictionary = world.get_flow(global_position)
			if flow.valid and not flow.at_target:
				target = flow.next
				wants_breach = flow.breach
		direction = Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
		if direction.length() > 0.01:
			direction = direction.normalized()

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
	if (_stuck_time > stuck_threshold or (wants_breach and result.hit_wall)) and _breach_timer <= 0.0:
		_breach(direction)

	_animate(direction, delta)


func _breach(direction: Vector3) -> void:
	_breach_timer = breach_cooldown
	var forward := (direction if direction.length() > 0.1 else -global_basis.z).normalized()
	# A body-sized bite just ahead, starting above the floor so it never digs the ground away.
	var bite_size := Vector3(body_size.x + breach_margin * 2.0, body_size.y + breach_margin, body_size.z + breach_margin * 2.0)
	var point := global_position + forward * breach_reach + Vector3.UP * (bite_size.y * 0.5 + 0.02)
	var removed: Dictionary = world.carve_box(AABB(point - bite_size * 0.5, bite_size), breach_power)
	if removed.is_empty():
		if on_floor:
			velocity.y = 5.0 # Can't dig this; try hopping over instead.
	else:
		manager.debris.burst(point, -forward, removed)
		_stuck_time = 0.0


func _animate(direction: Vector3, delta: float) -> void:
	if direction.length() > 0.1:
		var yaw := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-10.0 * delta))
	var speed_ratio := Vector2(velocity.x, velocity.z).length() / speed
	var t := Time.get_ticks_msec() * 0.012 + get_instance_id() % 100
	_visual.position.y = absf(sin(t)) * 0.08 * speed_ratio
	_visual.rotation.z = sin(t) * 0.12 * speed_ratio
	_flash = maxf(0.0, _flash - delta * 6.0)
	_visual.scale = Vector3.ONE * (1.0 + _flash * 0.15)


static func _ray_sphere(origin: Vector3, direction: Vector3, center: Vector3, radius: float) -> float:
	var oc := origin - center
	var b := oc.dot(direction)
	var c := oc.dot(oc) - radius * radius
	var discriminant := b * b - c
	if discriminant < 0.0:
		return -1.0
	var root := sqrt(discriminant)
	var t := -b - root
	if t < 0.0:
		t = -b + root
	return t if t >= 0.0 else -1.0
