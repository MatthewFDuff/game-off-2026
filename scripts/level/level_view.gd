class_name LevelView
extends Node3D
## Shows a level's objects. Light markers become real lights in both modes, and in play they follow
## LevelPlay.power (facility lights off and emergency lights on during backup power), as do the lamp
## and emergency voxels (the terrain shader's facility_power). In edit mode props are
## drawn as meshes (they're only stamped into the voxels for play) and markers as colored gizmos
## with their id, and the selection gets an outline.

## How fast (per second) the voxel lamps fade between powered and emergency.
const LAMP_FADE := 3.0

@export var lab: Lab

var mode := "play"

## id -> Node3D (prop mesh or marker gizmo), edit mode only.
var _nodes := {}
## id -> Light3D
var _lights := {}
## "name:facing" -> ArrayMesh
var _prop_meshes := {}
var _selection := MeshInstance3D.new()
var _flicker_time := 0.0
## The terrain shader's facility_power (1 = lamp voxels lit, 0 = emergency voxels lit), faded.
var _lamp_power := 1.0
## Editor cutaway (EditorCamera): marker gizmos from this voxel layer up are hidden, like the voxels
## and props there (which the terrain shader cuts).
var _cut_layer := NO_CUT

const NO_CUT := 1 << 30


func _ready() -> void:
	_selection.mesh = ImmediateMesh.new()
	_selection.material_override = _line_material(Color(1.0, 0.85, 0.2))
	_selection.visible = false
	add_child(_selection)


func set_mode(new_mode: String) -> void:
	mode = new_mode
	rebuild()


func rebuild() -> void:
	for node in _nodes.values() + _lights.values():
		node.queue_free()
	_nodes.clear()
	_lights.clear()
	_selection.visible = false
	if lab.level == null:
		return
	for object: Dictionary in lab.level.objects.values():
		_add(object)


## An object was added, changed or removed (LevelEdits.object_set).
func object_set(remove_id: String, object: Dictionary) -> void:
	_remove(remove_id)
	if not object.is_empty():
		_remove(object.id)
		_add(object)


## Live reload: redraw every placement of a prop.
func reload_prop(prop_name: String) -> void:
	for facing in 4:
		_prop_meshes.erase("%s:%d" % [prop_name, facing])
	for object: Dictionary in lab.level.objects.values():
		if object.kind == "prop" and object.name == prop_name:
			object_set(object.id, object)


## Outlines the selected object, or hides the outline for "".
func set_selected(id: String) -> void:
	var object: Dictionary = lab.level.objects.get(id, {}) if lab.level else {}
	_selection.visible = not object.is_empty()
	if object.is_empty():
		return
	var box := LevelSchema.box_of(object)
	draw_box(_selection.mesh, box.grow(0.3))


## A prop's mesh, turned to face `facing`, built once and shared.
func prop_mesh(prop_name: String, facing: int) -> ArrayMesh:
	var key := "%s:%d" % [prop_name, facing]
	if not _prop_meshes.has(key):
		var model := Props.load_prop(prop_name)
		if model.is_empty():
			return null
		var turned := Props.orient(model, facing)
		_prop_meshes[key] = lab.world.build_model_mesh(turned.size, turned.voxels)
	return _prop_meshes[key]


## World position of a point in voxel units.
func to_world(voxel: Vector3) -> Vector3:
	return lab.world.global_position + voxel * lab.world.voxel_size


## True when the level is on backup power (LevelPlay.power): facility lights go out and emergency
## lights come on. Facility and restored power are the other way round; editing shows them all.
func on_backup() -> bool:
	return mode == "play" and lab.play != null and lab.play.active and lab.play.power == "backup"


func _process(delta: float) -> void:
	_flicker_time += delta
	var backup := on_backup()
	var lamp_target := 0.0 if backup else 1.0
	if _lamp_power != lamp_target:
		_lamp_power = move_toward(_lamp_power, lamp_target, delta * LAMP_FADE)
		var shader := lab.world.material as ShaderMaterial
		if shader:
			shader.set_shader_parameter("facility_power", _lamp_power)
	for light: Light3D in _lights.values():
		var base: float = light.get_meta("energy")
		var emergency: bool = light.get_meta("emergency")
		var on := mode == "edit" or (backup == emergency)
		var energy := base if on else 0.0
		match light.get_meta("flicker"):
			"subtle":
				energy *= 0.92 + 0.08 * sin(_flicker_time * 13.0 + light.get_instance_id())
			"broken":
				var t := _flicker_time * 7.0 + light.get_instance_id() % 97
				energy *= 0.0 if fmod(t, 5.3) < 0.4 or fmod(t * 1.7, 3.1) < 0.15 else 1.0
		light.light_energy = energy


func _add(object: Dictionary) -> void:
	if object.kind == "marker" and object.type == "light":
		_add_light(object)
	if mode != "edit":
		return
	var node: Node3D
	if object.kind == "prop":
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = prop_mesh(object.name, object.facing)
		mesh_instance.material_override = lab.world.material
		mesh_instance.position = to_world(Vector3(object.origin))
		node = mesh_instance
	else:
		node = _gizmo(object)
		node.visible = LevelSchema.marker_box(object).position.y < _cut_layer
	add_child(node)
	_nodes[object.id] = node


## Hides marker gizmos at or above a voxel layer (NO_CUT shows them all).
func set_cut(layer: int) -> void:
	if layer == _cut_layer:
		return
	_cut_layer = layer
	if lab.level == null:
		return
	for id: String in _nodes:
		var object: Dictionary = lab.level.objects.get(id, {})
		if object.get("kind") == "marker":
			_nodes[id].visible = LevelSchema.marker_box(object).position.y < layer


func _remove(id: String) -> void:
	if id == "":
		return
	for table in [_nodes, _lights]:
		var node: Node = table.get(id)
		if node:
			node.queue_free()
			table.erase(id)


func _add_light(object: Dictionary) -> void:
	var light: Light3D
	if object.light == "spot":
		var spot := SpotLight3D.new()
		spot.spot_range = object.range
		spot.spot_angle = object.angle
		spot.rotation_degrees = Vector3(object.pitch, object.yaw, 0.0)
		light = spot
	else:
		var omni := OmniLight3D.new()
		omni.omni_range = object.range
		light = omni
	light.light_color = object.color
	light.shadow_enabled = object.shadows
	light.shadow_normal_bias = 3.0
	light.set_meta("energy", float(object.energy))
	light.set_meta("emergency", object.power == "emergency")
	light.set_meta("flicker", object.flicker)
	light.position = to_world(object.position)
	add_child(light)
	_lights[object.id] = light


## Editor marker: a see-through box (the trigger volume, or a small cube) with an outline and label.
func _gizmo(object: Dictionary) -> Node3D:
	var info: Dictionary = LevelSchema.MARKERS[object.type]
	var color: Color = info.color
	var box := LevelSchema.marker_box(object)
	var root := Node3D.new()
	root.position = to_world(box.position)

	var fill := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = box.size * lab.world.voxel_size
	fill.mesh = cube
	fill.position = cube.size * 0.5
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, 0.18 if object.has("size") else 0.5)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	fill.material_override = material
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fill)

	var outline := MeshInstance3D.new()
	outline.mesh = ImmediateMesh.new()
	outline.material_override = _line_material(color)
	draw_box(outline.mesh, AABB(Vector3.ZERO, box.size))
	outline.position = -to_world(Vector3.ZERO) # draw_box works in world units from the voxel origin.
	root.add_child(outline)

	# Facing arrow for markers where it matters.
	if object.type in ["spawn", "clone_vat", "horde"] or (object.type == "light" and object.light == "spot"):
		var arrow := MeshInstance3D.new()
		arrow.mesh = ImmediateMesh.new()
		arrow.material_override = outline.material_override
		var mesh: ImmediateMesh = arrow.mesh
		var forward := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(object.yaw)) * 0.6
		var center := Vector3(box.size.x, 1.0, box.size.z) * 0.5 * lab.world.voxel_size
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		mesh.surface_add_vertex(center)
		mesh.surface_add_vertex(center + forward)
		mesh.surface_end()
		root.add_child(arrow)

	var label := Label3D.new()
	label.text = "%s\n%s" % [object.id, info.label]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0009
	label.font_size = 22
	label.outline_size = 6
	label.modulate = color
	label.position = Vector3(box.size.x * 0.5, box.size.y + 2.0, box.size.z * 0.5) * lab.world.voxel_size
	root.add_child(label)
	return root


## Draws a box's 12 edges as lines. box is in voxel units; the mesh is in world units.
func draw_box(mesh: ImmediateMesh, box: AABB) -> void:
	mesh.clear_surfaces()
	var lo := to_world(box.position)
	var hi := to_world(box.end)
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(Vector3(hi.x if i & 1 else lo.x, hi.y if i & 2 else lo.y, hi.z if i & 4 else lo.z))
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for edge in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		mesh.surface_add_vertex(corners[edge[0]])
		mesh.surface_add_vertex(corners[edge[1]])
	mesh.surface_end()


static func _line_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	material.render_priority = 10
	return material
