class_name Pickup
extends Node3D
## An item lying in the level: a small voxel model (GearModels.item, assets/vox/items/<item>.vox)
## that bobs and turns, its GLOW voxels in the item's color. Only drawn here; ItemManager (the
## host) decides who picks it up. The node's position is the middle of the model.

## Drawn size of one model voxel (meters).
const VOXEL := 0.045
const BOB_HEIGHT := 0.06
const BOB_SPEED := 2.2
const TURN_SPEED := 1.2

## Unique per session, the same on every peer (the node is named after it).
var id := 0
## The item's name (Inventory item names: medkit, ammo_<type>, flask_<type>, keycard_<color>).
var item := ""
var world: VoxelWorld

var _model: Node3D
var _time := 0.0

@onready var _visual: Node3D = $Visual


func _ready() -> void:
	_time = id * 1.3
	build()


## (Re)builds the model from the item's .vox.
func build() -> void:
	if _model:
		_model.queue_free()
	var model := GearModels.item(item)
	var center := Vector3(model.get("size", Vector3i.ONE)) * 0.5
	_model = GearModels.build(world, model, GearModels.item_color(item), VOXEL, center)
	_visual.add_child(_model)


func _process(delta: float) -> void:
	_time += delta
	# The bob moves in half-voxel steps, so the pickup steps up and down instead of gliding.
	_visual.position.y = snappedf(sin(_time * BOB_SPEED) * BOB_HEIGHT, VOXEL * 0.5)
	_visual.rotation.y = _time * TURN_SPEED
