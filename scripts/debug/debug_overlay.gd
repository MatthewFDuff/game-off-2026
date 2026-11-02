extends CanvasLayer
## F3 overlay with frame timing and voxel world stats.

@export var world: VoxelWorld
@export var player: Player
@export var tools: SandboxTools

@onready var label: Label = $Label

var _timer := 0.0


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_debug"):
		visible = not visible
	_timer -= delta
	if not visible or _timer > 0.0 or world == null:
		return
	_timer = 0.25

	var s: Dictionary = world.get_stats()
	var lines := PackedStringArray([
		"FPS %d  (%.1f ms)" % [Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second())],
		"chunks %d  meshed %d  expanded %d  dirty %d" % [s.chunks, s.chunks_meshed, s.chunks_expanded, s.chunks_dirty],
		"triangles %s" % String.num_int64(s.triangles),
		"mesh last %.2f ms  max %.2f ms  built %d" % [s.last_mesh_ms, s.max_mesh_ms, s.meshes_built],
	])
	if player:
		var p := player.global_position
		lines.append("pos %.1f %.1f %.1f  %s%s" % [p.x, p.y, p.z, "floor" if player.on_floor else "air", "  FLY" if player.flying else ""])
	if tools:
		lines.append("place: %s  [1-4]" % VoxelMaterials.get_material_name(tools.place_material))
	lines.append("LMB rifle  RMB blast  E place  arrows look  F fly  T light  F3 hide")
	label.text = "\n".join(lines)
