class_name EditorPresence
extends Node3D
## What each person is doing in the level editor, shown to everyone else in their color. One per
## player, on every peer (same path, so the owner's RPCs land on the others' copies). The owner's
## copy reads its EditorTool and sends a small state about ten times a second, only when it
## changed (and now and then anyway, for anyone who missed one): which view, the builder camera,
## the cursor, the tool's preview box (or, for walls, their prisms) or prop ghost, and the
## selection. Other copies draw it: a camera gizmo with the name for builder-view users (their
## parked body is hidden), the cursor box, the preview, the selection outline (a wall's own prism),
## and "<name> is moving this" over what they hold a soft lock on (LevelEdits.locks).

const SEND_INTERVAL := 0.1
## Sent anyway this often even when nothing changed (the state is unreliable).
const KEEPALIVE := 2.0
const BOX_ALPHA := 0.18

var lab: Lab
var player: Player
## The owner's last state (remote copies: what was received).
var state := {}

## Whether this is the owner's copy (Player.is_local isn't set yet when this is ready).
var _local := false
var _send_timer := 0.0
var _since_sent := 0.0
var _sent := {}
var _color := Color.WHITE
var _gizmo: MeshInstance3D
var _name_tag: Label3D
var _cursor: MeshInstance3D
var _selection: MeshInstance3D
var _preview: MeshInstance3D
## Walls being drawn or reshaped: their prisms' edges.
var _prisms: MeshInstance3D
var _ghost: MeshInstance3D
## "<name>" over what they're moving or resizing (their soft lock).
var _lock_tag: Label3D


func _ready() -> void:
	player = get_parent() as Player
	_color = Net.player_color(player.get_multiplayer_authority())
	_local = player.get_multiplayer_authority() == multiplayer.get_unique_id()
	if _local:
		return
	var lines := LevelView._line_material(_color)
	_cursor = _lines(lines)
	_selection = _lines(lines)
	_prisms = _lines(lines)
	_preview = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_preview.mesh = box
	var fill := StandardMaterial3D.new()
	fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill.cull_mode = BaseMaterial3D.CULL_DISABLED
	fill.albedo_color = Color(_color, BOX_ALPHA)
	_preview.material_override = fill
	_ghost = MeshInstance3D.new()
	_ghost.transparency = 0.5
	_gizmo = MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.5, 0.4, 0.5)
	_gizmo.mesh = prism
	var solid := StandardMaterial3D.new()
	solid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	solid.albedo_color = _color
	_gizmo.material_override = solid
	_name_tag = Label3D.new()
	_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_tag.fixed_size = true
	_name_tag.pixel_size = 0.0012
	_name_tag.font_size = 24
	_name_tag.outline_size = 8
	_name_tag.no_depth_test = true
	_name_tag.modulate = _color
	_name_tag.position = Vector3(0.0, 0.45, 0.0)
	_gizmo.add_child(_name_tag)
	_lock_tag = _name_tag.duplicate()
	_lock_tag.position = Vector3.ZERO
	for node in [_cursor, _selection, _preview, _prisms, _ghost, _gizmo, _lock_tag]:
		node.visible = false
		node.top_level = true # World space, wherever the player stands.
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)


func _lines(material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = ImmediateMesh.new()
	mesh.material_override = material
	return mesh


func _process(delta: float) -> void:
	if _local:
		_send(delta)
	else:
		_show()


# --- Owner ---------------------------------------------------------------------------------------

func _send(delta: float) -> void:
	_send_timer -= delta
	_since_sent += delta
	if _send_timer > 0.0:
		return
	_send_timer = SEND_INTERVAL
	var tool := player.get_node_or_null("EditorTool") as EditorTool
	state = tool.presence_state() if tool and lab.mode == "edit" else {}
	if state == _sent and _since_sent < KEEPALIVE:
		return
	_sent = state
	_since_sent = 0.0
	for peer_id in player.net_peers:
		_receive.rpc_id(peer_id, state)


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive(new_state: Dictionary) -> void:
	state = new_state


# --- Everyone else -------------------------------------------------------------------------------

func _show() -> void:
	var editing := lab.mode == "edit" and not state.is_empty()
	var builder: bool = editing and state.get("builder", false)
	player.set_body_visible(not builder)
	_gizmo.visible = builder
	if builder:
		_gizmo.global_transform = state.camera
		# The prism points along its +Y; turn it to point where the camera looks (-Z).
		_gizmo.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
		_name_tag.text = player.display_name
	var cursor: Variant = state.get("cursor") if editing else null
	_cursor.visible = cursor != null
	if cursor != null:
		lab.view.draw_box(_cursor.mesh, cursor)
	var preview: Variant = state.get("preview") if editing else null
	_preview.visible = preview != null
	if preview != null:
		var box: AABB = preview
		var size := box.size * lab.world.voxel_size
		_preview.scale = size
		_preview.global_position = lab.view.to_world(box.position) + size * 0.5
	var prisms: Array = state.get("prisms", []) if editing else []
	_prisms.visible = not prisms.is_empty()
	if _prisms.visible:
		_draw_prisms(_prisms.mesh, prisms)
	var ghost: Dictionary = state.get("ghost", {}) if editing else {}
	_ghost.visible = not ghost.is_empty()
	if _ghost.visible:
		_ghost.mesh = lab.view.prop_mesh(ghost.name, ghost.facing)
		_ghost.material_override = lab.world.material
		_ghost.global_position = lab.view.to_world(Vector3(ghost.origin))
	var selected: Dictionary = lab.level.objects.get(state.get("selected", ""), {}) if editing and lab.level else {}
	_selection.visible = not selected.is_empty()
	_lock_tag.visible = false
	if _selection.visible:
		var box := LevelBuild.box_of(selected, lab.level.objects).grow(0.3)
		var corners := LevelBuild.corners_of(selected, lab.level.objects)
		if corners.is_empty():
			lab.view.draw_box(_selection.mesh, box)
		else:
			lab.view.draw_corners(_selection.mesh, corners) # A wall square to itself, 45° too.
		if lab.edits.locks.get(selected.id, 0) == player.get_multiplayer_authority():
			_lock_tag.visible = true
			_lock_tag.text = "%s is moving this" % player.display_name
			_lock_tag.global_position = lab.view.to_world(Vector3(box.get_center().x, box.end.y, box.get_center().z))


## Prisms (8 voxel-space corners each, LevelView.draw_corners order) as edges in one mesh.
func _draw_prisms(mesh: ImmediateMesh, prisms: Array) -> void:
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for corners in prisms:
		if corners.size() != 8:
			continue
		for edge in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
			mesh.surface_add_vertex(lab.view.to_world(corners[edge[0]]))
			mesh.surface_add_vertex(lab.view.to_world(corners[edge[1]]))
	mesh.surface_end()


## Where to look at this person from: their builder camera's pivot, or their feet.
func focus_point() -> Vector3:
	if state.get("builder", false):
		return state.get("pivot", player.global_position)
	return player.global_position
