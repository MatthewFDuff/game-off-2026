extends SceneTree
## One-time conversion of the generated facility into an editable level, res://levels/lab/:
## the rooms and terrain as voxels, every prop as a prop object, every light as a light marker,
## and four player spawns. Refuses to overwrite an existing level unless --force is given.
##   godot --headless --path . --script res://scripts/tools/convert_facility.gd [-- --force]

const LEVEL_NAME := "lab"
const SIZE := Vector3i(16, 10, 16)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var existing := LevelData.RES_DIR.path_join(LEVEL_NAME).path_join("level.json")
	if FileAccess.file_exists(existing) and "--force" not in OS.get_cmdline_user_args():
		print("convert: %s exists; pass --force to overwrite" % existing)
		quit(1)
		return

	var world := VoxelWorld.new()
	world.size_in_chunks = SIZE
	world.immediate_remesh_limit = 0
	world.detach_floating = false
	root.add_child(world)
	var lights := Node3D.new()
	world.add_child(lights)
	var builder := FacilityBuilder.new()
	builder.stamp_props = false
	var info := builder.build(world, lights, 2026)

	var level := LevelData.new()
	level.name = LEVEL_NAME
	level.settings = LevelData.default_settings(SIZE, "rock")
	level.voxels = world.get_data()

	for placement in info.props.placements:
		var prop := LevelSchema.new_prop(placement.name, placement.origin, placement.facing)
		_add(level, "prop", prop)

	for light: Light3D in lights.get_children():
		var marker := LevelSchema.new_marker("light", _to_voxels(world, light.position))
		marker.color = light.light_color
		marker.range = (light as OmniLight3D).omni_range if light is OmniLight3D else 10.0
		marker.shadows = light.shadow_enabled
		if light.is_in_group("emergency_light"):
			marker.power = "emergency"
			marker.energy = float(light.get_meta("on_energy", 0.7))
		else:
			marker.energy = light.light_energy
		_add(level, "light", marker)

	var right := Vector3.RIGHT.rotated(Vector3.UP, info.spawn_yaw)
	for i in 4:
		var feet: Vector3 = info.spawn + right * (i - 1.5) * 1.0
		var spawn := LevelSchema.new_marker("spawn", _to_voxels(world, feet), rad_to_deg(info.spawn_yaw))
		spawn.index = i + 1
		_add(level, "spawn", spawn)

	var error := level.save()
	print("convert: saved %s (%d objects): %s" % [LEVEL_NAME, level.objects.size(), error_string(error)])
	world.free()
	quit(0 if error == OK else 1)


func _add(level: LevelData, prefix: String, object: Dictionary) -> void:
	object.id = level.new_id(prefix)
	level.objects[object.id] = object


func _to_voxels(world: VoxelWorld, world_position: Vector3) -> Vector3:
	return (world_position - world.global_position) / world.voxel_size
