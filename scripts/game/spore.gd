class_name Spore
extends Node3D
## A planted spore. Dormant during the day; at night it swells through the voxel growth stages and,
## once fully grown, uproots as a Shroom.

signal matured(spore: Spore)

@export var growth_time := 7.0

var growing := false
var variant := 0
var _manager: ShroomManager
var _growth := 0.0
var _delay := 0.0
var _stage := -1
var _model := MeshInstance3D.new()


func setup(manager: ShroomManager, model_variant: int) -> void:
	_manager = manager
	variant = model_variant
	add_child(_model)
	_set_stage(0)


## Starts growing after delay seconds.
func start_growing(delay: float) -> void:
	growing = true
	_delay = delay


func _process(delta: float) -> void:
	if not growing:
		return
	if _delay > 0.0:
		_delay -= delta
		return
	_growth = minf(_growth + delta / growth_time, 1.0)
	_set_stage(mini(floori(_growth * ShroomModels.MAX_STAGE + 0.25), ShroomModels.MAX_STAGE))
	# Tremble harder the closer it is to bursting.
	var shake := maxf(0.0, _growth - 0.6) * 0.25
	_model.rotation = Vector3(sin(Time.get_ticks_msec() * 0.031) * shake, 0.0, sin(Time.get_ticks_msec() * 0.027) * shake)
	if _growth >= 1.0:
		growing = false
		matured.emit(self)


func _set_stage(stage: int) -> void:
	if stage == _stage:
		return
	_stage = stage
	var model := _manager.get_model(stage, variant, false)
	_model.mesh = model.mesh
	_model.position = model.offset
	_model.material_override = _manager.get_material()
