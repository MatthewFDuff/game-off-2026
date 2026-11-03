extends SceneTree
## Headless checks for the MagicaVoxel pipeline:
##   godot --headless --path . --script res://tests/vox_test.gd [-- <dir to write sample files to>]
##
## Round trips (single and split models), every catalog prop drawn by its generator vs loaded from
## .vox and stamped in all four facings, the shipped library loading cleanly, the facility building
## from it, and meshing models bigger than one chunk.

const M := preload("res://scripts/voxel/voxel_materials.gd")
const P := preload("res://scripts/world/props.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else ""
	_round_trips(out_dir)
	_rotations()
	_prop_parity()
	_library()
	_facility()
	_big_mesh()
	print("vox test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _round_trips(out_dir: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ids := M.DEFS.keys()
	for case in [{name = "single", size = Vector3i(7, 11, 5), fill = 0.5}, {name = "split", size = Vector3i(300, 12, 270), fill = 0.02}]:
		var size: Vector3i = case.size
		var voxels := PackedByteArray()
		voxels.resize(size.x * size.y * size.z)
		for i in voxels.size():
			if rng.randf() < case.fill:
				voxels[i] = ids[rng.randi() % ids.size()]
		# Mark the far corners so the frame is pinned even if the random fill misses them.
		voxels[0] = M.CONCRETE
		voxels[voxels.size() - 1] = M.LAMP
		var bytes := VoxFile.encode({size = size, voxels = voxels})
		var back := VoxFile.parse(bytes)
		_check("%s model round-trips" % case.name, back.size == size and back.voxels == voxels, "size %s" % back.get("size"))
		_check("%s model has no unknown colors" % case.name, back.unknown_colors.is_empty(), str(back.unknown_colors))
		if out_dir != "":
			FileAccess.open(out_dir.path_join("%s.vox" % case.name), FileAccess.WRITE).store_buffer(bytes)

	# Empty margins are part of a prop's frame and must survive.
	var framed := PackedByteArray()
	framed.resize(5 * 4 * 6)
	framed[2 + 1 * 5 + 3 * 20] = M.WOOD
	var back := VoxFile.parse(VoxFile.encode({size = Vector3i(5, 4, 6), voxels = framed}))
	_check("empty margins survive", back.size == Vector3i(5, 4, 6) and back.voxels == framed, str(back.size))


func _rotations() -> void:
	var valid := 0
	var all_ok := true
	for packed in 128:
		var c0 := packed & 3
		var c1 := (packed >> 2) & 3
		if c0 == 3 or c1 == 3 or c0 == c1:
			continue
		valid += 1
		var basis := VoxFile._parse_rotation(packed)
		all_ok = all_ok and is_equal_approx(absf(basis.determinant()), 1.0) and basis.is_conformal()
	_check("rotation bytes decode to signed permutations", all_ok and valid == 48, "%d valid" % valid)
	_check("rotation 4 is identity", VoxFile._parse_rotation(4) == Basis.IDENTITY)


## The library model, turned and stamped, must match the generator drawing the same prop facing
## the same way: proves frames, axes and rotation all line up.
func _prop_parity() -> void:
	var drawn := _scratch_world()
	var stamped := _scratch_world()
	var origin := Vector3i(12, 4, 12)
	var mismatches: Array[String] = []
	var entries := PropCatalog.entries()
	for entry in entries:
		var model := VoxFile.parse(VoxFile.encode(PropCatalog.generate(entry)))
		for facing in [P.NORTH, P.EAST, P.SOUTH, P.WEST]:
			drawn.fill_all(0)
			stamped.fill_all(0)
			var turning := TurningProps.new(drawn, 0)
			turning.rng.seed = hash(entry.name)
			turning.forced_facing = facing
			entry.draw.call(turning, origin)
			var turned := Props.orient(model, facing)
			stamped.stamp(origin, turned.size, turned.voxels, false)
			if drawn.get_data() != stamped.get_data():
				mismatches.append("%s/%d" % [entry.name, facing])
	_check("all %d props match their generators in 4 facings" % entries.size(), mismatches.is_empty(), ", ".join(mismatches.slice(0, 8)))
	drawn.free()
	stamped.free()


## Props whose generators draw with a facing forced in, since catalog entries always face north.
class TurningProps:
	extends Props
	var forced_facing := Props.NORTH

	func _begin(origin: Vector3i, w: int, d: int, _facing: int) -> void:
		super._begin(origin, w, d, forced_facing)


func _library() -> void:
	var bad: Array[String] = []
	var files := _vox_files("res://assets/vox")
	for path in files:
		var model := VoxFile.parse(FileAccess.get_file_as_bytes(path))
		if model.is_empty() or not model.unknown_colors.is_empty():
			bad.append(path.get_file())
	_check("all %d shipped .vox files load cleanly" % files.size(), bad.is_empty() and not files.is_empty(), ", ".join(bad))
	var missing: Array[String] = []
	for entry in PropCatalog.entries():
		if not FileAccess.file_exists(Props.LIBRARY_DIR + entry.name + ".vox"):
			missing.append(entry.name)
	_check("every catalog prop has a .vox", missing.is_empty(), ", ".join(missing))


func _facility() -> void:
	var world := VoxelWorld.new()
	world.size_in_chunks = Vector3i(16, 10, 16)
	world.immediate_remesh_limit = 0
	world.detach_floating = false
	var lights := Node3D.new()
	root.add_child(world)
	world.add_child(lights)
	Props.missing.clear()
	FacilityBuilder.new().build(world, lights, 2026)
	_check("facility places only props that exist", Props.missing.is_empty(), str(Props.missing))
	_check("facility has the fridge", _count(world, Vector3i(113, 40, 216), Vector3i(120, 59, 224), M.PLASTIC) > 100)
	world.free()


func _big_mesh() -> void:
	var world := _scratch_world()
	var size := Vector3i(40, 70, 3)
	var voxels := PackedByteArray()
	voxels.resize(size.x * size.y * size.z)
	voxels.fill(M.STEEL)
	var mesh: ArrayMesh = world.build_model_mesh(size, voxels)
	var has_surface := mesh != null and mesh.get_surface_count() > 0
	var aabb := mesh.get_aabb() if has_surface else AABB()
	_check("models bigger than a chunk mesh in one piece", aabb.size.is_equal_approx(Vector3(size) * world.voxel_size), str(aabb))
	# Greedy-meshed solid box: a handful of quads per block side, and none inside at the seams.
	var quads: int = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 6 if has_surface else 0
	_check("no faces at block seams", quads > 0 and quads <= 6 * 6, "%d quads" % quads)
	world.free()


func _scratch_world() -> VoxelWorld:
	var world := VoxelWorld.new()
	world.size_in_chunks = Vector3i(2, 2, 2)
	world.out_of_bounds_solid = false
	world.immediate_remesh_limit = 0
	return world


func _count(world: VoxelWorld, from: Vector3i, to: Vector3i, material: int) -> int:
	var n := 0
	for y in range(from.y, to.y):
		for z in range(from.z, to.z):
			for x in range(from.x, to.x):
				n += int(world.get_voxel(Vector3i(x, y, z)) == material)
	return n


func _vox_files(dir: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == "vox":
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_vox_files(dir.path_join(sub)))
	return found


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
