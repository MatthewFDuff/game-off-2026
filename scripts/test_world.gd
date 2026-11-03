extends Node3D
## Builds a procedural test facility: a big hall cut into rock with tunnels, pillars, a plank
## barricade and some glowing blobs. Stand-in until real level authoring exists.

@export var world: VoxelWorld
@export var player: Player
@export var seed := 1337


func _ready() -> void:
	VoxelMaterials.apply_to(world)
	var start := Time.get_ticks_msec()

	# Bulk edits would otherwise remesh (and check for loose fragments) after every call.
	# Queue everything, mesh once at the end.
	var immediate_limit := world.immediate_remesh_limit
	world.immediate_remesh_limit = 0
	world.detach_floating = false
	_generate()
	world.remesh_all_now()
	world.immediate_remesh_limit = immediate_limit
	world.detach_floating = true

	print("test world generated in %d ms: %s" % [Time.get_ticks_msec() - start, world.get_stats()])


func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var size: Vector3i = world.get_size_in_voxels()
	var vs := world.voxel_size

	world.fill_all(VoxelMaterials.ROCK)
	world.fill_box(Vector3i.ZERO, Vector3i(size.x, 5, size.z), VoxelMaterials.BEDROCK)

	# Dirt pockets, so carving into the walls turns up a different material.
	for i in 60:
		var p := Vector3(rng.randf() * size.x, rng.randf_range(8, size.y - 8), rng.randf() * size.z) * vs
		world.fill_sphere(p, rng.randf_range(0.6, 2.0), VoxelMaterials.DIRT, false)

	# Main hall: 24m x 5m x 24m with a concrete floor slab.
	var hall_from := Vector3i(200, 22, 200)
	var hall_to := Vector3i(440, 72, 440)
	world.fill_box(Vector3i(hall_from.x, 18, hall_from.z), Vector3i(hall_to.x, 22, hall_to.z), VoxelMaterials.CONCRETE)
	world.fill_box(hall_from, hall_to, VoxelMaterials.AIR)

	# Pillars.
	for px in [260, 380]:
		for pz in [260, 380]:
			world.fill_box(Vector3i(px - 4, 22, pz - 4), Vector3i(px + 4, 72, pz + 4), VoxelMaterials.CONCRETE)

	# A metal wall section on one side of the hall.
	world.fill_box(Vector3i(hall_from.x, 22, 300), Vector3i(hall_from.x + 3, 60, 340), VoxelMaterials.METAL)

	# Winding tunnels leaving the hall in four directions.
	var center := Vector3(320, 32, 320) * vs
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var p: Vector3 = center + direction * 11.0
		var heading: Vector3 = direction
		for step in 70:
			world.carve_sphere(p + Vector3.UP * 0.6, rng.randf_range(1.3, 1.8), 254)
			heading = (heading + Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35))).normalized()
			p += heading * 0.6
			p.y = clampf(p.y + rng.randf_range(-0.12, 0.12), 2.6, 4.5)

	# Plank barricade across the east tunnel mouth.
	for row in range(24, 62, 6):
		world.fill_box(Vector3i(442, row, 300), Vector3i(444, row + 4, 340), VoxelMaterials.PLANK, true)

	# Glowing blobs as a lighting test for the night shift.
	for i in 14:
		var p := Vector3(rng.randf_range(hall_from.x + 10, hall_to.x - 10), 22, rng.randf_range(hall_from.z + 10, hall_to.z - 10)) * vs
		world.fill_sphere(p, rng.randf_range(0.2, 0.45), VoxelMaterials.GLOW, true)

	# Shaft above the middle of the hall.
	world.fill_box(Vector3i(300, hall_to.y, 300), Vector3i(340, size.y, 340), VoxelMaterials.AIR)

	player.teleport(Vector3(320, 22.5, 330) * vs)
