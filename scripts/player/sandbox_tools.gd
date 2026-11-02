class_name SandboxTools
extends Node
## Foundation test weapons: a hitscan rifle that chips voxels and an explosive that carves craters.
## Stand-ins until the real weapon system exists. Inactive while build mode is on.

@export var player: Player
@export var camera: Camera3D
@export var debris: VoxelDebris
@export var build_tool: BuildTool

@export_group("Rifle")
@export var rifle_fire_rate := 10.0
@export var rifle_radius := 0.14
@export var rifle_power := 4
@export var rifle_range := 120.0

@export_group("Explosive")
@export var blast_radius := 1.2
@export var blast_power := 6
@export var blast_cooldown := 0.35

var _cooldown := 0.0


func _process(delta: float) -> void:
	_cooldown -= delta
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or (build_tool and build_tool.active):
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
	if not hit.hit:
		return
	var removed: Dictionary = player.world.carve_sphere(hit.position, rifle_radius, rifle_power)
	debris.burst(hit.position, hit.normal, removed if not removed.is_empty() else {hit.material: 2})


func _explode() -> void:
	var hit := _aim(rifle_range)
	if not hit.hit:
		return
	var removed: Dictionary = player.world.carve_sphere(hit.position, blast_radius, blast_power)
	debris.burst(hit.position, hit.normal, removed)
