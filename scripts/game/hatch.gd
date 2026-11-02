class_name Hatch
extends Node3D
## The hatch in the ceiling that lets daylight into the facility. Closing it slides an unbreakable
## voxel plate across the shaft row by row; opening carves it back out.

## Lights and meshes that only exist while the hatch is open (sunlight, the sky panel).
@export var daylight: Array[Node3D] = []

var world: VoxelWorld
var is_closed := false
var _from := Vector3i.ZERO
var _to := Vector3i.ZERO


## Sets the voxel box the plate fills (from inclusive, to exclusive), sliding along x.
func configure(voxel_world: VoxelWorld, from: Vector3i, to: Vector3i) -> void:
	world = voxel_world
	_from = from
	_to = to


func close(duration: float) -> void:
	await _slide(VoxelMaterials.HATCH, duration)
	is_closed = true
	_set_daylight(false)


func open(duration: float) -> void:
	_set_daylight(true)
	await _slide(VoxelMaterials.AIR, duration)
	is_closed = false


func _slide(material: int, duration: float) -> void:
	var rows := _to.x - _from.x
	var step := 2
	for x in range(_from.x, _to.x, step):
		world.fill_box(Vector3i(x, _from.y, _from.z), Vector3i(mini(x + step, _to.x), _to.y, _to.z), material)
		await get_tree().create_timer(duration * step / rows).timeout


func _set_daylight(on: bool) -> void:
	for node in daylight:
		node.visible = on
