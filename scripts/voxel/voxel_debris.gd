class_name VoxelDebris
extends Node3D
## Spawns short-lived voxel-colored particle bursts where terrain gets carved, and crumbles pieces
## that the world reports as detached (no longer connected to anything solid).

@export var world: VoxelWorld
@export var max_particles_per_burst := 48
@export var particles_per_voxel := 0.08
@export var max_particles_per_fragment := 160
## Most debris chip sounds per second, however many bursts there are.
@export var chip_rate := 12.0

var _cube := BoxMesh.new()
var _last_chip_msec := -100000


func _ready() -> void:
	_cube.size = Vector3.ONE * 0.05
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	_cube.material = material
	if world:
		world.fragments_detached.connect(_on_fragments_detached)


func _on_fragments_detached(fragments: Array) -> void:
	for fragment in fragments:
		var bounds: AABB = fragment.aabb
		var total: int = fragment.voxel_count
		var amount := clampi(int(total * 0.25) + 6, 6, max_particles_per_fragment)
		for id in fragment.materials:
			var share := maxi(2, int(amount * float(fragment.materials[id]) / total))
			_spawn(bounds.get_center(), Vector3.DOWN, share, VoxelMaterials.get_color(id), total, bounds.size * 0.5)
		_chip(bounds.get_center(), -4.0)


## removed maps material id -> voxels removed, as returned by VoxelWorld.carve_sphere.
func burst(at: Vector3, normal: Vector3, removed: Dictionary) -> void:
	var total := 0
	for count in removed.values():
		total += count
	if total == 0:
		return
	var amount := clampi(int(total * particles_per_voxel) + 4, 4, max_particles_per_burst)
	_chip(at, -10.0)

	for id in removed:
		var share := maxi(1, int(amount * float(removed[id]) / total))
		_spawn(at, normal, share, VoxelMaterials.get_color(id), total)


func _chip(at: Vector3, volume_db: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_chip_msec < 1000.0 / chip_rate:
		return
	_last_chip_msec = now
	Sfx.play_at("chip", at, volume_db, 0.2)


## box_extents, when set, spawns particles throughout that box instead of from a point.
func _spawn(at: Vector3, normal: Vector3, amount: int, color: Color, size_hint: int, box_extents := Vector3.ZERO) -> void:
	var particles := CPUParticles3D.new()
	particles.mesh = _cube
	particles.amount = amount
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.lifetime = 1.2
	particles.direction = normal if normal != Vector3.ZERO else Vector3.UP
	particles.spread = 55.0
	particles.initial_velocity_min = 1.5
	particles.initial_velocity_max = 3.5 + minf(size_hint / 200.0, 6.0)
	particles.gravity = Vector3(0, -12, 0)
	# Whole voxel sizes, no smooth random scale: 0.05 m chips, 0.1 m chunks from bigger breaks.
	var chunk := 2.0 if size_hint > 200 else 1.0
	particles.scale_amount_min = chunk
	particles.scale_amount_max = chunk
	particles.color = color
	if box_extents != Vector3.ZERO:
		particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		particles.emission_box_extents = box_extents
		particles.initial_velocity_min = 0.0
		particles.initial_velocity_max = 1.5
	else:
		particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		particles.emission_sphere_radius = 0.1 + minf(size_hint / 4000.0, 0.8)
	add_child(particles)
	particles.global_position = at
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
