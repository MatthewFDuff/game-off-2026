class_name BuildTool
extends Node3D
## Build mode: aim at a surface, see a ghost of the piece, place it. Pieces only fill air, so they
## fit around jagged blast holes, and must touch existing solid voxels so they can't float.

signal piece_placed(piece: Dictionary, voxels_placed: int)

@export var player: Player
@export var camera: Camera3D
## Pays for pieces. Building is free without one.
@export var state: GameState
@export var build_range := 6.0
## Fraction of a piece's voxels that must land in open air for it to be placeable.
@export var min_free_fraction := 0.25

var active := false
## Off outside the day shift. Turning it off also leaves build mode.
var allowed := true:
	set(value):
		allowed = value
		if not allowed:
			active = false
var piece_index := 0
var turned := false

var _ghost := MeshInstance3D.new()
var _ghost_mesh := BoxMesh.new()
var _ghost_material := StandardMaterial3D.new()
var _target := {}


func _ready() -> void:
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.no_depth_test = true
	_ghost_mesh.material = _ghost_material
	_ghost.mesh = _ghost_mesh
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.top_level = true
	_ghost.visible = false
	add_child(_ghost)


func get_piece() -> Dictionary:
	return BuildPieces.PIECES[piece_index]


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_build") and allowed:
		active = not active
	if not active or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_ghost.visible = false
		_target = {}
		return

	for i in BuildPieces.PIECES.size():
		if Input.is_action_just_pressed("slot_%d" % (i + 1)):
			piece_index = i
	if Input.is_action_just_pressed("rotate_piece"):
		turned = not turned

	_target = _find_target()
	_update_ghost()
	if Input.is_action_just_pressed("fire") and _target.get("valid", false):
		if state and not state.spend(get_piece().cost):
			return
		var placed: int = player.world.stamp(_target.origin, _target.size, _target.voxels, true)
		piece_placed.emit(get_piece(), placed)


func _find_target() -> Dictionary:
	var world := player.world
	var hit: Dictionary = world.raycast(camera.global_position, -camera.global_basis.z, build_range)
	if not hit.hit or hit.normal == Vector3.ZERO:
		return {}

	var shape := BuildPieces.oriented(get_piece(), hit.normal, turned)
	var size: Vector3i = shape.size
	var normal_axis := (hit.normal as Vector3).abs().max_axis_index()
	var cell: Vector3i = hit.voxel + Vector3i(hit.normal)

	# Center the piece on the aimed cell across the surface, extending away from it.
	var origin := cell - size / 2
	origin[normal_axis] = cell[normal_axis] if hit.normal[normal_axis] > 0.0 else cell[normal_axis] - size[normal_axis] + 1

	var check: Dictionary = world.check_stamp(origin, size, shape.voxels)
	var total := size.x * size.y * size.z
	var bounds := AABB(world.voxel_to_world(origin) - Vector3.ONE * world.voxel_size * 0.5, Vector3(size) * world.voxel_size)
	var affordable := state == null or state.can_afford(get_piece().cost)
	var valid: bool = affordable and check.supported > 0 and check.free >= maxi(1, int(total * min_free_fraction)) \
			and not bounds.intersects(player.get_body_aabb())
	return {origin = origin, size = size, voxels = shape.voxels, bounds = bounds, valid = valid}


func _update_ghost() -> void:
	if _target.is_empty():
		_ghost.visible = false
		return
	var bounds: AABB = _target.bounds
	_ghost.visible = true
	# Slightly oversized so the ghost doesn't z-fight with surfaces it is flush against.
	_ghost_mesh.size = bounds.size + Vector3.ONE * 0.01
	_ghost.global_position = bounds.get_center()
	_ghost_material.albedo_color = Color(0.3, 1.0, 0.4, 0.35) if _target.valid else Color(1.0, 0.25, 0.2, 0.35)
