class_name PlantTool
extends Node
## Plants spores in grow-bed substrate during the day shift [E].

@export var player: Player
@export var camera: Camera3D
@export var shrooms: ShroomManager
@export var state: GameState
@export var director: ShiftDirector
@export var build_tool: BuildTool
@export var plant_range := 3.5

var _target := {}


func _process(_delta: float) -> void:
	_target = _find_target()
	if _target.is_empty() or not Input.is_action_just_pressed("interact"):
		return
	if not shrooms.can_plant(_target.position):
		director.message_posted.emit("Too close to another spore.", 2.0)
		return
	shrooms.plant(_target.position)
	state.planted += 1
	state.changed.emit()


## Text for the HUD's interaction prompt, or "" when not aiming at substrate.
func get_prompt() -> String:
	if _target.is_empty():
		return ""
	return "[E] Plant spore (%d / %d)" % [state.planted, state.quota]


func _find_target() -> Dictionary:
	if not InputSetup.is_playing() or director.phase != ShiftDirector.Phase.DAY:
		return {}
	if (build_tool and build_tool.active) or director.is_at_hatch_control():
		return {}
	var hit: Dictionary = player.world.raycast(camera.global_position, -camera.global_basis.z, plant_range)
	if not hit.hit or hit.normal != Vector3.UP or hit.material != VoxelMaterials.SUBSTRATE:
		return {}
	return hit
