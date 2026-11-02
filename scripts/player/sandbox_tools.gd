class_name SandboxTools
extends Node
## Foundation test weapons: a hitscan rifle that chips voxels and an explosive that carves craters.
## Stand-ins until the real weapon system exists. Inactive while build mode is on.

@export var player: Player
@export var camera: Camera3D
@export var debris: VoxelDebris
@export var build_tool: BuildTool
@export var shrooms: ShroomManager

@export_group("Rifle")
@export var rifle_fire_rate := 10.0
@export var rifle_radius := 0.14
@export var rifle_power := 4
@export var rifle_range := 120.0
@export var rifle_damage := 20.0

@export_group("Explosive")
@export var blast_radius := 1.2
@export var blast_power := 6
@export var blast_cooldown := 0.35
@export var blast_damage := 150.0

var _cooldown := 0.0


func _process(delta: float) -> void:
	_cooldown -= delta
	if not InputSetup.is_playing() or (build_tool and build_tool.active):
		return

	if Input.is_action_pressed("fire") and _cooldown <= 0.0:
		_cooldown = 1.0 / rifle_fire_rate
		_shoot()
	elif Input.is_action_just_pressed("alt_fire") and _cooldown <= 0.0:
		_cooldown = blast_cooldown
		_explode()


func _aim(max_distance: float) -> Dictionary:
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	return player.world.raycast(origin, direction, max_distance)


func _shoot() -> void:
	var hit := _aim(rifle_range)
	if _hit_shroom(rifle_range, hit, rifle_damage):
		return
	if not hit.hit:
		return
	var removed: Dictionary = player.world.carve_sphere(hit.position, rifle_radius, rifle_power)
	debris.burst(hit.position, hit.normal, removed if not removed.is_empty() else {hit.material: 2})


func _explode() -> void:
	var hit := _aim(rifle_range)
	var shroom_hit := _shroom_along_aim(rifle_range)
	if not shroom_hit.is_empty() and (not hit.hit or shroom_hit.distance < hit.distance):
		# Detonate on the shroom, facing back toward the player.
		hit = {hit = true, position = shroom_hit.position, normal = camera.global_basis.z}
	if not hit.hit:
		return
	var removed: Dictionary = player.world.carve_sphere(hit.position, blast_radius, blast_power)
	debris.burst(hit.position, hit.normal, removed)
	if shrooms:
		shrooms.damage_sphere(hit.position, blast_radius + 1.0, blast_damage)


## Damages the shroom under the crosshair if it's closer than the terrain hit. Returns true if so.
func _hit_shroom(max_distance: float, terrain_hit: Dictionary, damage: float) -> bool:
	var shroom_hit := _shroom_along_aim(max_distance)
	if shroom_hit.is_empty() or (terrain_hit.hit and terrain_hit.distance < shroom_hit.distance):
		return false
	var direction := -camera.global_basis.z
	shroom_hit.shroom.take_damage(damage, direction * 1.5)
	debris.burst(shroom_hit.position, -direction, {VoxelMaterials.GLOW: 20})
	return true


func _shroom_along_aim(max_distance: float) -> Dictionary:
	if shrooms == null:
		return {}
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	var hit := shrooms.raycast(origin, direction, max_distance)
	if not hit.is_empty():
		hit.position = origin + direction * hit.distance
	return hit
