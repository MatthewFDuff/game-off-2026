extends Node3D
## Main game scene: builds the facility, then hands the hatch, ladder and spawn to the gameplay
## nodes.

@export var world: VoxelWorld
@export var player: Player
@export var hatch: Hatch
@export var director: ShiftDirector
@export var lights: Node3D
@export var seed := 2026

var info := {}


func _ready() -> void:
	VoxelMaterials.apply_to(world)
	var start := Time.get_ticks_msec()

	# Bulk edits would otherwise remesh (and check for loose fragments) after every call.
	var immediate_limit := world.immediate_remesh_limit
	world.immediate_remesh_limit = 0
	world.detach_floating = false
	info = FacilityBuilder.new().build(world, lights, seed)
	world.remesh_all_now()
	world.immediate_remesh_limit = immediate_limit
	world.detach_floating = true

	hatch.configure(world, info.hatch_from, info.hatch_to)
	director.hatch_control_position = info.hatch_control
	director.hatch_height = info.hatch_height
	director.ladder_foot_position = info.ladder_foot
	var beds_center := Vector3.ZERO
	for bed: AABB in info.spore_beds:
		beds_center += bed.get_center()
	if not info.spore_beds.is_empty():
		director.beds_center = beds_center / info.spore_beds.size()
	var watch := get_node_or_null("/root/VoxWatch")
	if watch:
		watch.changed.connect(_on_vox_changed)
	player.teleport(info.spawn)
	player.rotation.y = info.spawn_yaw
	print("facility generated in %d ms: %s" % [Time.get_ticks_msec() - start, world.get_stats()])


## Live reload of edited props (single-player, so straight into the world).
func _on_vox_changed(paths: PackedStringArray) -> void:
	var stamp := func(origin: Vector3i, size: Vector3i, voxels: PackedByteArray, erase: bool) -> void:
		if erase:
			world.erase_stamp(origin, size, voxels)
		else:
			world.stamp(origin, size, voxels, false)
	for path in paths:
		var prop := Props.name_for_path(path)
		if prop != "":
			print(info.props.reload_placements(prop, stamp))
