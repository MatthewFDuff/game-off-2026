class_name VoxelDebris
extends Node3D
## Spawns short-lived voxel-colored particle bursts where terrain gets carved.

@export var max_particles_per_burst := 48
@export var particles_per_voxel := 0.08

var _cube := BoxMesh.new()


func _ready() -> void:
	_cube.size = Vector3.ONE * 0.06
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	_cube.material = material


## removed maps material id -> voxels removed, as returned by VoxelWorld.carve_sphere.
func burst(at: Vector3, normal: Vector3, removed: Dictionary) -> void:
	var total := 0
	for count in removed.values():
		total += count
	if total == 0:
		return
	var amount := clampi(int(total * particles_per_voxel) + 4, 4, max_particles_per_burst)

	for id in removed:
		var share := maxi(1, int(amount * float(removed[id]) / total))
		_spawn(at, normal, share, VoxelMaterials.get_color(id), total)


func _spawn(at: Vector3, normal: Vector3, amount: int, color: Color, size_hint: int) -> void:
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
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.6 + minf(size_hint / 1000.0, 2.0)
	particles.color = color
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.1 + minf(size_hint / 4000.0, 0.8)
	add_child(particles)
	particles.global_position = at
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
