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
	print("  blast r=1.2m carve+detach+remesh ms: %s" % [timings])
	world.detach_floating = false
	var no_detach := PackedFloat64Array()
	for i in 3:
		var t := Time.get_ticks_usec()
		world.carve_sphere(Vector3(20.0, 4.0, 24.0 + i * 3.0), 1.2, 6)
		no_detach.append((Time.get_ticks_usec() - t) / 1000.0)
	world.detach_floating = true
	print("  same blast without detach ms: %s" % [no_detach])
	var s: Dictionary = world.get_stats()
	print("  last chunk: pad %.2f  greedy %.2f  upload %.2f ms" % [s.last_pad_ms, s.last_greedy_ms, s.last_upload_ms])

	var bedrock: Dictionary = world.carve_sphere(Vector3(32, 0.3, 32), 0.5, 254)
	_check("bedrock is uncarvable", not bedrock.has(VoxelMaterials.BEDROCK), str(bedrock))

	# Floating fragments: a 5x5x5 cube on a thin stem drops once the stem is cut.
	var fragments := []
	world.fragments_detached.connect(func(f: Array) -> void: fragments.append_array(f))
	world.fill_box(Vector3i(302, 22, 342), Vector3i(303, 40, 343), VoxelMaterials.CONCRETE)
	world.fill_box(Vector3i(300, 40, 340), Vector3i(305, 45, 345), VoxelMaterials.CONCRETE)
	_check("no fragments while cube is attached", fragments.is_empty(), str(fragments))
	var start := Time.get_ticks_usec()
	world.carve_sphere(Vector3(30.25, 3.15, 34.25), 0.12, 6)
	var cut_ms := (Time.get_ticks_usec() - start) / 1000.0
	var cube_gone: bool = world.get_voxel(Vector3i(302, 42, 342)) == VoxelMaterials.AIR
	var stem_base_kept: bool = world.get_voxel(Vector3i(302, 23, 342)) == VoxelMaterials.CONCRETE
	_check("cut stem detaches cube", fragments.size() == 1 and fragments[0].voxel_count >= 125 and cube_gone and stem_base_kept, str(fragments))
	print("  stem cut with fragment detection: %.2f ms" % cut_ms)

	fragments.clear()
	world.carve_sphere(Vector3(20.0, 4.0, 38.0), 1.2, 6)
	_check("blast into a wall detaches nothing large", fragments.all(func(f: Dictionary) -> bool: return f.voxel_count < 200), str(fragments))

	# Building: a plank against the floor is supported, one in mid-air is not.
	var plank := BuildPieces.oriented(BuildPieces.PIECES[0], Vector3.UP, false)
	_check("plank on floor lies flat", plank.size == Vector3i(2, 1, 12), str(plank.size))
	var on_floor: Dictionary = world.check_stamp(Vector3i(330, 22, 300), plank.size, plank.voxels)
	var in_air: Dictionary = world.check_stamp(Vector3i(330, 50, 300), plank.size, plank.voxels)
	_check("plank on floor is supported", on_floor.supported > 0 and on_floor.free == 24, str(on_floor))
	_check("plank in mid-air is unsupported", in_air.supported == 0 and in_air.free == 24, str(in_air))
	var placed: int = world.stamp(Vector3i(330, 22, 300), plank.size, plank.voxels, true)
	_check("stamp places plank", placed == 24 and world.get_voxel(Vector3i(331, 22, 311)) == VoxelMaterials.PLANK, str(placed))
	var wall := BuildPieces.oriented(BuildPieces.PIECES[0], Vector3.RIGHT, false)
	_check("plank on wall runs horizontally", wall.size == Vector3i(1, 2, 12), str(wall.size))
	var turned := BuildPieces.oriented(BuildPieces.PIECES[0], Vector3.RIGHT, true)
	_check("turned plank on wall runs vertically", turned.size == Vector3i(1, 12, 2), str(turned.size))

	# Only-air stamping fits around existing voxels instead of replacing them.
	var overlap: int = world.stamp(Vector3i(330, 22, 300), Vector3i(2, 2, 12), _filled(48, VoxelMaterials.METAL), true)
	_check("only-air stamp skips occupied voxels", overlap == 24 and world.get_voxel(Vector3i(330, 22, 300)) == VoxelMaterials.PLANK, str(overlap))

	# Navigation: flow field toward the player.
	var target := Vector3(32.0, 2.2, 33.0)
	world.update_flow_field(target, 60.0)
	var nav_stats: Dictionary = world.get_stats()
	print("  flow field (first, builds floors): %.2f ms, %d floor cells reached" % [nav_stats.last_flow_ms, nav_stats.flow_reached])
	world.update_flow_field(target, 60.0)
	print("  flow field (repeat): %.2f ms" % world.get_stats().last_flow_ms)
	var across: Dictionary = world.get_flow(Vector3(24.0, 2.2, 40.0))
	_check("flow crosses the hall", across.valid and not across.breach and across.distance > 9.0 and across.distance < 14.0, str(across))
	var step_dir: Vector3 = (across.next - Vector3(24.0, 2.2, 40.0)) if across.valid else Vector3.ZERO
	_check("flow points toward target", step_dir.dot(target - Vector3(24.0, 2.2, 40.0)) > 0.0, str(step_dir))
	var at_target: Dictionary = world.get_flow(target)
	_check("flow at target", at_target.valid and at_target.at_target, str(at_target))

	# A sealed concrete room can't be reached; swap one wall for planks and it's reachable by breaching.
	world.fill_box(Vector3i(210, 22, 210), Vector3i(250, 72, 250), VoxelMaterials.CONCRETE)
	world.fill_box(Vector3i(214, 22, 214), Vector3i(246, 72, 246), VoxelMaterials.AIR)
	var inside := Vector3(23.0, 2.2, 23.0)
	world.update_flow_field(target, 60.0)
	_check("sealed concrete room is unreachable", not world.get_flow(inside).valid, str(world.get_flow(inside)))
	world.fill_box(Vector3i(246, 22, 214), Vector3i(250, 72, 246), VoxelMaterials.PLANK)
	world.update_flow_field(target, 60.0)
	var through_planks: Dictionary = world.get_flow(Vector3(24.4, 2.2, 23.0))
	_check("plank wall is breachable", through_planks.valid and through_planks.breach, str(through_planks))
	var from_inside: Dictionary = world.get_flow(inside)
	_check("room reaches target through planks", from_inside.valid, str(from_inside))

	print("voxel smoke test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _filled(count: int, material: int) -> PackedByteArray:
	var voxels := PackedByteArray()
	voxels.resize(count)
	voxels.fill(material)
	return voxels


func _check(label: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", label, "" if ok else detail])
	if not ok:
		_failures += 1
