class_name PlantTool
extends Node
## Plants spores on floors during the day shift [E].

@export var player: Player
@export var camera: Camera3D
@export var shrooms: ShroomManager
@export var state: GameState
@export var director: ShiftDirector
@export var build_tool: BuildTool
@export var plant_range := 4.0


func _process(_delta: float) -> void:
	if not Input.is_action_just_pressed("plant") or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if director.phase != ShiftDirector.Phase.DAY or (build_tool and build_tool.active):
		return
	var hit: Dictionary = player.world.raycast(camera.global_position, -camera.global_basis.z, plant_range)
	if not hit.hit or hit.normal != Vector3.UP:
		director.message_posted.emit("Spores need a floor to grow on.", 2.0)
		return
	if not shrooms.can_plant(hit.position):
		director.message_posted.emit("Too close to another spore.", 2.0)
		return
	shrooms.plant(hit.position)
	state.planted += 1
	state.changed.emit()
