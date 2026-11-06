class_name LevelView
extends Node3D
## Shows a level's objects. Light markers become real lights in both modes, and in play they follow
## LevelPlay.power (facility lights off and emergency lights on during backup power), as do the lamp
## and emergency voxels (the terrain shader's facility_power). In edit mode props are
## drawn as meshes (they're only stamped into the voxels for play) and markers as colored gizmos
## with their id, and the selection gets an outline. Mycelium nodes also show their network: each
## cluster (Mycelium) voxelized into a mesh, redrawn when one of its nodes changes; play stamps it.

## How fast (per second) the voxel lamps fade between powered and emergency.
const LAMP_FADE := 3.0

@export var lab: Lab

var mode := "play"

## id -> Node3D (prop mesh or marker gizmo), edit mode only.
var _nodes := {}
## id -> Light3D
var _lights := {}
## id -> what a light needs each frame, cached at _add_light: {light, base (energy), emergency,
## flicker ("" / "subtle" / "broken"), at (voxel position, for the rooms holding it), phase_a /
## phase_b (the flicker offsets), steady (its energy before flickering, for the cull), room_flicker
## (a room's lights flicker over it), written (the energy last set)}.
var _light_info := {}
## Light infos that animate (a flicker field or a flickering room, and lit); the rest only change
## when the power, the mode or the room lights do (_refresh_lights).
var _animated: Array[Dictionary] = []
## What _refresh_lights last saw: [mode, backup, play active, rules lights_version]; [] = stale.
var _lights_state: Array = []
## The Compatibility renderer draws only a few dozen lights, so only the LIGHT_BUDGET nearest lit
## lights (by distance past their range, from the active camera) are visible, re-picked every
## LIGHT_CULL_INTERVAL seconds.
const LIGHT_BUDGET := 20
## Vertical distance counts this much more when picking lights, so lamps on the floor above or
## below (a slab away) lose to the ones in the room.
const LIGHT_VERTICAL_WEIGHT := 4.0
const LIGHT_CULL_INTERVAL := 0.25
var _cull_time := 0.0
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

## Edit mode: Mycelium cluster key -> its meshes (MeshInstance3D), and whether to redraw them.
var mycelium_meshes := {}
var _mycelium_ids := {}
var _mycelium_dirty := false
## Play: the moving parts of props (the security cameras' heads), started and stopped with the mode.
var motion := PropMotion.new()


func _ready() -> void:
	_selection.mesh = ImmediateMesh.new()
	_selection.material_override = _line_material(Color(1.0, 0.85, 0.2))
	_selection.visible = false
	add_child(_selection)
	motion.name = "PropMotion"
	motion.view = self
	add_child(motion)


func set_mode(new_mode: String) -> void:
	mode = new_mode
	rebuild()
	motion.set_active(mode == "play")


func rebuild() -> void:
	for node in _nodes.values() + _lights.values():
		node.queue_free()
	_nodes.clear()
	_lights.clear()
	_light_info.clear()
	_animated.clear()
	_lights_state = []
	_clear_mycelium()
	_selection.visible = false
	if lab.level == null:
		return
	for object: Dictionary in lab.level.objects.values():
		_add(object)


## An object was added, changed or removed (LevelEdits.object_set).
func object_set(remove_id: String, object: Dictionary) -> void:
	if _mycelium_ids.has(remove_id) or object.get("type") == Mycelium.TYPE:
		_mycelium_dirty = true
	_remove(remove_id)
	if not object.is_empty():
		_remove(object.id)
		_add(object)


## Live reload: redraw every placement of a prop.
func reload_prop(prop_name: String) -> void:
	# A moving part's file (a camera head) is drawn into its body's mesh too.
	for body: String in PropMotion.PARTS:
		if PropMotion.PARTS[body].part == prop_name:
			reload_prop(body)
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
	# A wall (or an opening in one) outlines its own prism, square to it even at 45°.
	var corners := LevelBuild.corners_of(object, lab.level.objects)
	if not corners.is_empty():
		draw_corners(_selection.mesh, corners)
		return
	var box := LevelBuild.box_of(object, lab.level.objects)
	draw_box(_selection.mesh, box.grow(0.3))


## A prop's mesh, turned to face `facing`, built once and shared. A prop with a moving part
## (PropMotion) is drawn whole, its part at rest, as editor views show it.
func prop_mesh(prop_name: String, facing: int) -> ArrayMesh:
	var key := "%s:%d" % [prop_name, facing]
	if not _prop_meshes.has(key):
		var turned := PropMotion.display_model(prop_name, facing)
		if turned.is_empty():
			return null
		_prop_meshes[key] = lab.world.build_model_mesh(turned.size, turned.voxels)
	return _prop_meshes[key]


## World position of a point in voxel units.
func to_world(voxel: Vector3) -> Vector3:
	return lab.world.global_position + voxel * lab.world.voxel_size


## True when the level is on backup power (LevelPlay.power): facility lights go out and emergency
## lights come on. Facility and restored power are the other way round; editing shows them all.
func on_backup() -> bool:
	if lab == null or not is_instance_valid(lab):
		return false
	return mode == "play" and lab.play != null and lab.play.active and lab.play.power == "backup"


func _process(delta: float) -> void:
	if lab == null or not is_instance_valid(lab):
		return
	_flicker_time += delta
	if _mycelium_dirty:
		refresh_mycelium()
	var backup := on_backup()
	var lamp_target := 0.0 if backup else 1.0
	if _lamp_power != lamp_target:
		_lamp_power = move_toward(_lamp_power, lamp_target, delta * LAMP_FADE)
		var shader := lab.world.material as ShaderMaterial
		if shader:
			shader.set_shader_parameter("facility_power", _lamp_power)
	var rules: LevelPlay.Rules = lab.play.rules if mode == "play" and lab.play and lab.play.active else null
	# The steady energies change only with the mode, the power or the room lights.
	var version: int = rules.lights_version if rules else -1
	var state := [mode, backup, rules != null, version]
	if state != _lights_state:
		_lights_state = state
		_refresh_lights(backup, rules)
	# Then only the visible lights that flicker animate (the cull hides all but LIGHT_BUDGET).
	for info: Dictionary in _animated:
		var light: Light3D = info.light
		if not light.visible:
			continue
		var energy: float = info.steady
		# A room's lights flickering (sprinklers, `lights=...:flicker`: InteractRules).
		if info.room_flicker:
			var f: float = _flicker_time * 9.0 + info.phase_a
			energy *= 0.0 if fmod(f, 2.3) < 0.5 or fmod(f * 1.3, 1.7) < 0.3 else 1.0
		match info.flicker:
			"subtle":
				energy *= 0.92 + 0.08 * sin(_flicker_time * 13.0 + info.phase_c)
			"broken":
				var t: float = _flicker_time * 7.0 + info.phase_b
				energy *= 0.0 if fmod(t, 5.3) < 0.4 or fmod(t * 1.7, 3.1) < 0.15 else 1.0
		if energy != info.written:
			info.written = energy
			light.light_energy = energy
	_cull_time -= delta
	if _cull_time <= 0.0:
		_cull_time = LIGHT_CULL_INTERVAL
		_cull_lights()


## Every light's steady energy (on or off by the power and mode, cut by its rooms' lights) and
## whether it animates, written only where it changed. Runs when the mode, the power or
## InteractRules.room_lights changes, not every frame.
func _refresh_lights(backup: bool, rules: LevelPlay.Rules) -> void:
	# The rooms with a lights mode, boxes made once (room_lights order: "off" wins, else the last).
	var rooms: Array = []
	if rules:
		for room: String in rules.room_lights:
			rooms.append([rules.room_box(room), str(rules.room_lights[room])])
	_animated.clear()
	for light_id: String in _light_info:
		var info: Dictionary = _light_info[light_id]
		var on: bool = mode == "edit" or (backup == info.emergency)
		var energy: float = info.base if on else 0.0
		var cut := ""
		for entry: Array in rooms:
			if (entry[0] as AABB).has_point(info.at):
				if entry[1] == "off":
					cut = "off"
					break
				cut = entry[1]
		if cut == "off":
			energy = 0.0
		info.steady = energy
		info.room_flicker = cut == "flicker"
		if energy > 0.0 and (info.room_flicker or info.flicker == "subtle" or info.flicker == "broken"):
			_animated.append(info)
		if energy != info.written:
			info.written = energy
			(info.light as Light3D).light_energy = energy


## Keeps the nearest lit lights visible and hides the rest (see LIGHT_BUDGET). Lit means its steady
## energy, so a flickering light isn't dropped for catching it in an off beat.
func _cull_lights() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var at := camera.global_position
	var scored: Array = []
	for info: Dictionary in _light_info.values():
		var light: Light3D = info.light
		if info.steady <= 0.0:
			light.visible = false
			continue
		var offset := light.global_position - at
		var score := Vector2(offset.x, offset.z).length() + absf(offset.y) * LIGHT_VERTICAL_WEIGHT
		scored.append([score, light])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in scored.size():
		scored[i][1].visible = i < LIGHT_BUDGET


func _add(object: Dictionary) -> void:
	if object.kind == "marker" and object.type == "light":
		_add_light(object)
	if mode != "edit" or LevelSchema.is_structure(object):
		return # Rooms and openings are the voxels themselves; the selection outline shows them.
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
		if object.type == Mycelium.TYPE:
			_mycelium_ids[object.id] = true
			_mycelium_dirty = true
	add_child(node)
	_nodes[object.id] = node


## Edit mode: redraws the mycelium clusters that changed (a node moved, was added or removed, or
## its fields changed) and drops the ones that are gone. Play stamps them instead.
func refresh_mycelium() -> void:
	_mycelium_dirty = false
	if mode != "edit" or lab.level == null:
		_clear_mycelium()
		return
	var plan := Mycelium.plan(lab.level.objects, lab.world)
	var kept := {}
	for cluster: Dictionary in Mycelium.clusters(plan):
		var key: String = cluster.key
		if mycelium_meshes.has(key):
			kept[key] = mycelium_meshes[key]
			mycelium_meshes.erase(key)
			continue
		var parts: Array = []
		for model: Dictionary in Mycelium.cluster_models(plan, cluster, lab.world):
			var mesh_instance := MeshInstance3D.new()
			mesh_instance.mesh = lab.world.build_model_mesh(model.size, model.voxels)
			mesh_instance.material_override = lab.world.material
			mesh_instance.position = to_world(Vector3(model.origin))
			add_child(mesh_instance)
			parts.append(mesh_instance)
		kept[key] = parts
	_clear_mycelium()
	mycelium_meshes = kept


func _clear_mycelium() -> void:
	for parts: Array in mycelium_meshes.values():
		for node: Node in parts:
			node.queue_free()
	mycelium_meshes.clear()
	if mode != "edit":
		_mycelium_ids.clear()


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
	if _light_info.erase(id):
		_lights_state = [] # _animated may hold it: rebuilt next frame.
	_mycelium_ids.erase(id)


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
	var id_hash := light.get_instance_id()
	_light_info[object.id] = {light = light, base = float(object.energy), emergency = object.power == "emergency",
			flicker = str(object.flicker), at = Vector3(object.position), phase_a = float(id_hash % 53),
			phase_b = float(id_hash % 97), phase_c = float(id_hash), steady = 0.0, room_flicker = false,
			written = light.light_energy}
	_lights_state = [] # Its energy is worked out next frame.


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
	# Depth-tested, so markers in rooms out of sight (under the cutaway's rock) don't show through.
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
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(Vector3(box.end.x if i & 1 else box.position.x, box.end.y if i & 2 else box.position.y, box.end.z if i & 4 else box.position.z))
	draw_corners(mesh, corners)


## The edges of a box given as 8 corners in voxels, bit 0 / 1 / 2 of the index picking the far
## side along its three edges (LevelBuild.prism_corners).
func draw_corners(mesh: ImmediateMesh, voxel_corners: Array[Vector3]) -> void:
	mesh.clear_surfaces()
	var corners: Array[Vector3] = []
	for c in voxel_corners:
		corners.append(to_world(c))
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
