class_name EditorCamera
extends Node3D
## The level editor's builder view: a camera orbiting a pivot on the floor, with the mouse always
## free (tools aim with a ray through the mouse, see EditorTool). Right / middle drag orbits,
## Shift+middle drag pans, WASD pans relative to the view, the wheel zooms, Q / E turn 45 degrees.
## A right click that didn't drag is passed on as right_clicked, for the tool's RMB action.
##
## Cutaway: voxels at or above cut_layer aren't drawn (the terrain shader's cut_height) and the
## aim ray passes through them. Where the cut goes through solid voxels, a cap plane shows the cross
## section in the voxels' own colors, darkened and hatched, so walls read as walls from above.
## Auto puts the cut at the ceiling of the room the pivot stands in; Manual is moved with
## Page Up / Down; C cycles Off / Auto / Manual.

## RMB went down and up without orbiting.
signal right_clicked

enum Cut { OFF, AUTO, MANUAL }

const CUT_NAMES := ["Off", "Auto", "Manual"]
const PITCH_MIN := 15.0
const PITCH_MAX := 89.0
const DISTANCE_MIN := 2.0
const DISTANCE_MAX := 90.0
const ZOOM_STEP := 1.15
## Degrees per pixel of drag.
const ORBIT_SPEED := 0.3
## Pixels a right drag moves before it orbits instead of clicking.
const DRAG_THRESHOLD := 5.0
## Pan speed in view distances per second.
const PAN_SPEED := 1.1
const SMOOTHING := 14.0
## Aim reach in meters.
const REACH := 250.0
## Nothing is cut away (the shader's cut_height).
const NO_CUT := 1e9

const CAP_SHADER := preload("res://shaders/editor_cut_cap.gdshader")

var lab: Lab
var active := false
var pivot := Vector3.ZERO
## Degrees; yaw 0 looks along -Z like a player with rotation.y 0.
var yaw := 0.0
var pitch := 55.0
var distance := 14.0
var cut_mode := Cut.AUTO
## Voxel layers from this one up are cut away (while cutting).
var cut_layer := 0
## Page Up / Down step, in voxels (the editor keeps it at the grid snap).
var cut_step := 5
## Off while a tool step uses the wheel to size things.
var zoom_enabled := true

var camera := Camera3D.new()

var _shown_pivot := Vector3.ZERO
var _shown_yaw := 0.0
var _shown_pitch := 55.0
var _shown_distance := 14.0
## Where the pointer is, from its own events (the viewport's idea of it lags or is missing headless).
var _mouse := Vector2.ZERO
var _drag_button := MOUSE_BUTTON_NONE
var _drag_from := Vector2.ZERO
var _dragging := false
var _drag_pans := false
var _cap := MeshInstance3D.new()
var _cap_material := ShaderMaterial.new()
var _cap_image: Image
var _cap_texture: ImageTexture
## The layer the cap shows (cut_layer - 1), -1 when none; dirty when its voxels changed.
var _cap_layer := -1
var _cap_dirty := false


func _ready() -> void:
	camera.near = 0.05
	camera.far = 500.0
	camera.current = false
	add_child(camera)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	_cap.mesh = plane
	_cap.material_override = _cap_material
	_cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cap.visible = false
	_cap_material.shader = CAP_SHADER
	add_child(_cap)
	lab.world.voxels_changed.connect(_on_voxels_changed)


func _exit_tree() -> void:
	_set_shader_cut(NO_CUT)


func set_active(on: bool) -> void:
	active = on
	camera.current = on
	if not on:
		_cap.visible = false
		_set_shader_cut(NO_CUT)
		_drag_button = MOUSE_BUTTON_NONE


## Looks at feet (a player's position) from behind and above, facing yaw_degrees.
func look_from(feet: Vector3, yaw_degrees: float) -> void:
	pivot = feet
	yaw = yaw_degrees
	pitch = 55.0
	distance = 12.0
	if cut_mode == Cut.AUTO:
		_update_auto_cut(true)
	snap_to_target()


## Skips the smoothing (after a jump to a new place).
func snap_to_target() -> void:
	_shown_pivot = pivot
	_shown_yaw = yaw
	_shown_pitch = pitch
	_shown_distance = distance
	_place_camera()


## Centers on a world-space box and backs off far enough to see all of it.
func frame(box: AABB) -> void:
	var center := box.get_center()
	pivot = Vector3(center.x, box.position.y, center.z)
	distance = clampf(box.size.length() * 1.3, 4.0, DISTANCE_MAX)


func frame_world() -> void:
	var size := Vector3(lab.world.get_size_in_voxels()) * lab.world.voxel_size
	pivot = Vector3(lab.world.global_position.x + size.x * 0.5, pivot.y, lab.world.global_position.z + size.z * 0.5)
	distance = clampf(maxf(size.x, size.z) * 1.1, 4.0, DISTANCE_MAX)


## The camera ray through the mouse, as [origin, direction].
func mouse_ray() -> Array[Vector3]:
	return [camera.project_ray_origin(_mouse), camera.project_ray_normal(_mouse)]


func is_cutting() -> bool:
	return active and cut_mode != Cut.OFF and cut_layer > 0 and cut_layer < lab.world.get_size_in_voxels().y


## World height of the cut plane.
func cut_y() -> float:
	return lab.world.global_position.y + cut_layer * lab.world.voxel_size


## VoxelWorld.raycast that sees what the cutaway shows: it starts at the cut plane (so it hits the
## cap first) and misses anything above the cut. distance is from origin, as usual; cap is true
## on a hit on the cap.
func raycast(origin: Vector3, direction: Vector3, reach := REACH) -> Dictionary:
	var world := lab.world
	if not is_cutting():
		return world.raycast(origin, direction, reach)
	var top := cut_y() - 0.001
	var start := origin
	var skipped := 0.0
	if origin.y > top:
		if direction.y >= 0.0:
			return {hit = false}
		skipped = (origin.y - top) / -direction.y
		start = origin + direction * skipped
	var hit: Dictionary = world.raycast(start, direction, reach - skipped)
	if not hit.hit:
		return hit
	if hit.voxel.y >= cut_layer:
		return {hit = false}
	if hit.normal == Vector3.ZERO:
		hit.normal = Vector3.UP # Started inside a solid voxel: that's the cap, facing up.
		hit.cap = true
	hit.distance += skipped
	return hit


# --- Input ---------------------------------------------------------------------------------------

## A drag that started over the world ends wherever the button comes up, so catch the release before
## a panel under the pointer eats it.
func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse = event.position
	var button := event as InputEventMouseButton
	if active and button and not button.pressed and button.button_index == _drag_button:
		_drag_button = MOUSE_BUTTON_NONE
		if button.button_index == MOUSE_BUTTON_RIGHT and not _dragging:
			right_clicked.emit()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	var button := event as InputEventMouseButton
	var motion := event as InputEventMouseMotion
	if motion and _drag_button != MOUSE_BUTTON_NONE:
		if not _dragging and motion.position.distance_to(_drag_from) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			_drag(motion.relative)
		return
	if not EditorInput.world_may_use(event):
		return
	if button and button.pressed:
		match button.button_index:
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_drag_button = button.button_index
				_drag_from = button.position
				_dragging = false
				_drag_pans = button.button_index == MOUSE_BUTTON_MIDDLE and button.shift_pressed
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if not button.ctrl_pressed and zoom_enabled:
					zoom(1.0 / ZOOM_STEP if button.button_index == MOUSE_BUTTON_WHEEL_UP else ZOOM_STEP)
					get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		var used := true
		if InputSetup.pressed(event, "editor_orbit_left"):
			yaw = snappedf(yaw, 45.0) + 45.0
		elif InputSetup.pressed(event, "editor_orbit_right"):
			yaw = snappedf(yaw, 45.0) - 45.0
		elif InputSetup.pressed(event, "editor_cut_up"):
			move_cut(cut_step)
		elif InputSetup.pressed(event, "editor_cut_down"):
			move_cut(-cut_step)
		elif InputSetup.pressed(event, "editor_cut_mode") and not event.echo:
			set_cut_mode((cut_mode + 1) % CUT_NAMES.size() as Cut)
		else:
			used = false
		if used:
			get_viewport().set_input_as_handled()


func zoom(factor: float) -> void:
	distance = clampf(distance * factor, DISTANCE_MIN, DISTANCE_MAX)


func _drag(relative: Vector2) -> void:
	if _drag_pans:
		var scale := _shown_distance * 0.0015
		_pan(Vector3(-relative.x, 0.0, -relative.y) * scale)
		_shown_pivot = pivot
		return
	yaw -= relative.x * ORBIT_SPEED
	pitch = clampf(pitch + relative.y * ORBIT_SPEED, PITCH_MIN, PITCH_MAX)
	_shown_yaw = yaw
	_shown_pitch = pitch


## Moves the pivot by a view-relative offset (x right, z back), kept over the world.
func _pan(offset: Vector3) -> void:
	pivot += Basis(Vector3.UP, deg_to_rad(yaw)) * offset
	var lo := lab.world.global_position
	var hi := lo + Vector3(lab.world.get_size_in_voxels()) * lab.world.voxel_size
	pivot.x = clampf(pivot.x, lo.x, hi.x)
	pivot.z = clampf(pivot.z, lo.z, hi.z)


func set_cut_mode(mode: Cut) -> void:
	if mode == Cut.MANUAL and not is_cutting():
		cut_layer = _auto_layer(cut_layer)
	cut_mode = mode
	if mode == Cut.AUTO:
		_update_auto_cut(true)
	lab.notify("Cutaway: %s" % CUT_NAMES[mode], false)


func move_cut(voxels: int) -> void:
	if cut_mode != Cut.MANUAL:
		if not is_cutting():
			cut_layer = _auto_layer(lab.world.get_size_in_voxels().y)
		cut_mode = Cut.MANUAL
	cut_layer = clampi(cut_layer + voxels, 1, lab.world.get_size_in_voxels().y)


# --- Per frame -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not active:
		return
	var input := Vector2.ZERO
	if not EditorInput.blocks_keyboard() and not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_ALT):
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input != Vector2.ZERO:
		var fast := 3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
		_pan(Vector3(input.x, 0.0, input.y) * distance * PAN_SPEED * fast * delta)
	if cut_mode == Cut.AUTO:
		_update_auto_cut(false)

	var blend := 1.0 - exp(-SMOOTHING * delta)
	_shown_pivot = _shown_pivot.lerp(pivot, blend)
	_shown_yaw = lerpf(_shown_yaw, yaw, blend)
	_shown_pitch = lerpf(_shown_pitch, pitch, blend)
	_shown_distance = lerpf(_shown_distance, distance, blend)
	_place_camera()
	_update_cut()


func _place_camera() -> void:
	var basis := Basis.from_euler(Vector3(deg_to_rad(-_shown_pitch), deg_to_rad(_shown_yaw), 0.0))
	camera.global_transform = Transform3D(basis, _shown_pivot + basis * Vector3(0.0, 0.0, _shown_distance))


## Auto cut: the ceiling over the pivot. Over solid ground (between rooms) it keeps the last one, so
## panning across a wall doesn't flash the whole roof back. force also takes it from solid.
func _update_auto_cut(force: bool) -> void:
	var world := lab.world
	var cell: Vector3i = world.world_to_voxel(pivot + Vector3.UP * 0.05)
	if not force and world.get_voxel(cell) != 0:
		return
	cut_layer = _auto_layer(cut_layer)


## The first solid layer above the air the pivot stands in (climbing out of solid first), or
## fallback when the pivot is outside the world.
func _auto_layer(fallback: int) -> int:
	var world := lab.world
	var size: Vector3i = world.get_size_in_voxels()
	var cell: Vector3i = world.world_to_voxel(pivot + Vector3.UP * 0.05)
	if cell.x < 0 or cell.z < 0 or cell.x >= size.x or cell.z >= size.z:
		return fallback
	var y := clampi(cell.y, 0, size.y - 1)
	while y < size.y and world.get_voxel(Vector3i(cell.x, y, cell.z)) != 0:
		y += 1
	while y < size.y and world.get_voxel(Vector3i(cell.x, y, cell.z)) == 0:
		y += 1
	return y


func _update_cut() -> void:
	if not is_cutting():
		_set_shader_cut(NO_CUT)
		_cap.visible = false
		return
	_set_shader_cut(cut_y() - 0.001)
	lab.view.set_cut(cut_layer)
	var layer := cut_layer - 1
	if layer != _cap_layer or _cap_dirty:
		_rebuild_cap(layer)
	_cap.visible = true


func _set_shader_cut(height: float) -> void:
	if not is_instance_valid(lab):
		return
	if height >= NO_CUT:
		lab.view.set_cut(LevelView.NO_CUT)
	var material := lab.world.material as ShaderMaterial
	if material:
		material.set_shader_parameter("cut_height", height)


## The cap: one plane at the cut, colored per voxel from the layer just under it (air shows through).
func _rebuild_cap(layer: int) -> void:
	var world := lab.world
	var size: Vector3i = world.get_size_in_voxels()
	var bytes := world.get_box(Vector3i(0, layer, 0), Vector3i(size.x, layer + 1, size.z))
	if _cap_image == null or _cap_image.get_width() != size.x or _cap_image.get_height() != size.z:
		_cap_image = Image.create_from_data(size.x, size.z, false, Image.FORMAT_R8, bytes)
		_cap_texture = ImageTexture.create_from_image(_cap_image)
	else:
		_cap_image.set_data(size.x, size.z, false, Image.FORMAT_R8, bytes)
		_cap_texture.update(_cap_image)
	_cap_layer = layer
	_cap_dirty = false
	var extent := Vector3(size) * world.voxel_size
	_cap.scale = Vector3(extent.x, 1.0, extent.z)
	_cap.global_position = world.global_position + Vector3(extent.x * 0.5, (layer + 1) * world.voxel_size, extent.z * 0.5)
	var terrain := world.material as ShaderMaterial
	_cap_material.set_shader_parameter("ids", _cap_texture)
	_cap_material.set_shader_parameter("palette", terrain.get_shader_parameter("palette") if terrain else null)
	_cap_material.set_shader_parameter("origin", world.global_position)
	_cap_material.set_shader_parameter("voxel_size", world.voxel_size)


func _on_voxels_changed(from: Vector3i, to: Vector3i) -> void:
	if _cap_layer >= from.y and _cap_layer <= to.y:
		_cap_dirty = true
