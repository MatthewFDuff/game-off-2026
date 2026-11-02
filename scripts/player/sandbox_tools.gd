class_name SandboxTools
extends Node
## Foundation test tools: a hitscan rifle that chips voxels, an explosive that carves craters, and
## block placement. These are stand-ins until the real weapon and build systems exist.

@export var player: Player
@export var camera: Camera3D
@export var debris: VoxelDebris

@export_group("Rifle")
@export var rifle_fire_rate := 10.0
@export var rifle_radius := 0.14
@export var rifle_power := 4
@export var rifle_range := 120.0

@export_group("Explosive")
@export var blast_radius := 1.2
@export var blast_power := 6
@export var blast_cooldown := 0.35

@export_group("Build")
@export var block_size := 0.5
@export var build_range := 6.0

const PLACEABLE := [VoxelMaterials.PLANK, VoxelMaterials.CONCRETE, VoxelMaterials.METAL, VoxelMaterials.GLOW]

var place_material: int = PLACEABLE[0]
var _cooldown := 0.0


func _process(delta: float) -> void:
	_cooldown -= delta
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	for i in PLACEABLE.size():
		if Input.is_action_just_pressed("material_%d" % (i + 1)):
			place_material = PLACEABLE[i]

	if Input.is_action_pressed("fire") and _cooldown <= 0.0:
		_cooldown = 1.0 / rifle_fire_rate
		_shoot()
	elif Input.is_action_just_pressed("alt_fire") and _cooldown <= 0.0:
		_cooldown = blast_cooldown
		_explode()
	elif Input.is_action_just_pressed("place"):
		_place_block()


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
	var start := Time.get_ticks_usec()
	var removed: Dictionary = player.world.carve_sphere(hit.position, blast_radius, blast_power)
	var ms := (Time.get_ticks_usec() - start) / 1000.0
	print("blast: %d voxels removed, carve + remesh %.2f ms" % [_total(removed), ms])
	debris.burst(hit.position, hit.normal, removed)


func _place_block() -> void:
	var hit := _aim(build_range)
	if not hit.hit:
		return
	var world := player.world
	var cells := int(round(block_size / world.voxel_size))
	# Snap to a block grid on the air side of the face that was hit.
	var target: Vector3i = world.world_to_voxel(hit.position + hit.normal * world.voxel_size * 0.5)
	var from := Vector3i(floori(float(target.x) / cells), floori(float(target.y) / cells), floori(float(target.z) / cells)) * cells
	var to := from + Vector3i(cells, cells, cells)

	var origin := world.voxel_to_world(from) - Vector3.ONE * world.voxel_size * 0.5
	if AABB(origin, Vector3.ONE * block_size).intersects(player.get_body_aabb()):
		return
	world.fill_box(from, to, place_material, true)


func _total(removed: Dictionary) -> int:
	var total := 0
	for count in removed.values():
		total += count
	return total
