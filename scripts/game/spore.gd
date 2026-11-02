class_name Spore
extends Node3D
## A planted spore. Dormant during the day; at night it swells into a mushroom and, once fully
## grown, uproots as a Shroom.

signal matured(spore: Spore)

@export var growth_time := 7.0

var growing := false
var _growth := 0.0
var _delay := 0.0
var _stem := MeshInstance3D.new()
var _cap := MeshInstance3D.new()


## Materials are shared across all spores and shrooms so the night glow can fade them together.
func setup(stem_material: Material, cap_material: Material) -> void:
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.06
	stem_mesh.bottom_radius = 0.09
	stem_mesh.height = 0.5
	stem_mesh.material = stem_material
	_stem.mesh = stem_mesh
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.2
	cap_mesh.height = 0.2
	cap_mesh.material = cap_material
	_cap.mesh = cap_mesh
	add_child(_stem)
	add_child(_cap)
	_apply_growth()


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
	_apply_growth()
	if _growth >= 1.0:
		growing = false
		matured.emit(self)


func _apply_growth() -> void:
	# A dormant spore is a small bump. Fully grown, it is about the size of a Shroom.
	var t := ease(_growth, 0.6)
	var stem_scale := lerpf(0.25, 1.6, t)
	_stem.scale = Vector3(stem_scale, stem_scale, stem_scale)
	_stem.position.y = 0.25 * stem_scale
	var cap_scale := lerpf(0.4, 2.2, t)
	_cap.scale = Vector3(cap_scale, cap_scale * 0.8, cap_scale)
	_cap.position.y = 0.5 * stem_scale
	# Shake while about to burst.
	_cap.rotation.z = sin(Time.get_ticks_msec() * 0.03) * 0.15 * maxf(0.0, _growth - 0.8) * 5.0
