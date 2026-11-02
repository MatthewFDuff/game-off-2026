extends SceneTree
## Headless checks for the voxel core. Run from the project root:
##   godot --headless --path . --script res://tests/voxel_smoke_test.gd

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: Node3D = load("res://scenes/test_world.tscn").instantiate()
	root.add_child(scene)
	var world: VoxelWorld = scene.get_node("VoxelWorld")
	var player: Player = scene.get_node("Player")
	var vs := world.voxel_size

	for i in 90:
		await physics_frame
	_check("player lands on hall floor", player.on_floor and absf(player.global_position.y - 2.2) < 0.01, "y=%.3f" % player.global_position.y)

	var down: Dictionary = world.raycast(Vector3(32, 5, 33), Vector3.DOWN, 10.0)
	_check("raycast hits floor", down.hit and absf(down.position.y - 2.2) < 0.001 and down.normal == Vector3.UP and down.material == VoxelMaterials.CONCRETE, str(down))

	var up_miss: Dictionary = world.raycast(Vector3(32, 5, 33), Vector3.UP, 1.0)
	_check("short raycast into open air misses", not up_miss.hit)

	var size := Vector3(0.6, 1.75, 0.6)
	var feet := Vector3(30.0, 2.2, 30.0)

	# Step-up: 30cm ledge is climbed, 60cm ledge blocks.
	world.fill_box(Vector3i(303, 22, 290), Vector3i(310, 25, 310), VoxelMaterials.CONCRETE)
	var step: Dictionary = world.move_box(feet, size, Vector3(0.5, -0.01, 0.0), 0.45, true)
	_check("steps up 30cm ledge", absf(step.step_up - 0.3) < 0.001 and step.position.x > 30.4, str(step))

	world.fill_box(Vector3i(303, 25, 290), Vector3i(310, 28, 310), VoxelMaterials.CONCRETE)
	var blocked: Dictionary = world.move_box(feet, size, Vector3(0.5, -0.01, 0.0), 0.45, true)
	_check("blocked by 60cm ledge", blocked.hit_wall and step.step_up > 0.0 and blocked.step_up == 0.0 and absf(blocked.position.x - 30.0) < 0.001, str(blocked))

	# Tunneling: a huge move into a 10cm wall stops flush against it.
	world.fill_box(Vector3i(280, 22, 280), Vector3i(281, 40, 320), VoxelMaterials.PLANK)
	var fast: Dictionary = world.move_box(Vector3(29.0, 2.2, 30.0), size, Vector3(-50.0, 0.0, 0.0), 0.0, false)
	_check("no tunneling through 10cm wall", fast.hit_wall and absf(fast.position.x - (28.1 + 0.3)) < 0.001, str(fast))

	_check("box overlap detects wall", world.box_overlaps_solid(AABB(Vector3(28.05, 2.3, 30), Vector3(0.1, 0.1, 0.1))))
	_check("box resting on floor is not overlapping", not world.box_overlaps_solid(AABB(Vector3(30.7, 2.2, 31), Vector3(0.6, 1.75, 0.6))))

	# Hardness: weak blast leaves metal alone.
	var metal_center := Vector3(20.15, 3.0, 32.0)
	var weak: Dictionary = world.carve_sphere(metal_center, 0.3, 4)
	_check("weak blast does not cut metal", not weak.has(VoxelMaterials.METAL), str(weak))

	# Blast cost including the immediate remesh.
	var timings := PackedFloat64Array()
	for i in 5:
		var at := Vector3(44.0, 4.0, 24.0 + i * 3.0)
		var start := Time.get_ticks_usec()
		var removed: Dictionary = world.carve_sphere(at, 1.2, 6)
		timings.append((Time.get_ticks_usec() - start) / 1000.0)
		if i == 0:
			_check("blast removes voxels", removed.get(VoxelMaterials.ROCK, 0) > 3000, str(removed))
	print("  blast r=1.2m carve+remesh ms: %s" % [timings])
	var s: Dictionary = world.get_stats()
	print("  last chunk: pad %.2f  greedy %.2f  upload %.2f ms" % [s.last_pad_ms, s.last_greedy_ms, s.last_upload_ms])

	var bedrock: Dictionary = world.carve_sphere(Vector3(32, 0.3, 32), 0.5, 254)
	_check("bedrock is uncarvable", not bedrock.has(VoxelMaterials.BEDROCK), str(bedrock))

	print("voxel smoke test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", label, "" if ok else detail])
	if not ok:
		_failures += 1
