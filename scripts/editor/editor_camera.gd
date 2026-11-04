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
## Walls-down (H) hides, above knee height, whatever is between the camera and the pivot, so a room
## can be seen into from a low angle (the shaders' walls_down_*; the aim ray skips it too).
##
## Auto puts the cut at the ceiling of the selected room, or else of the room the pivot stands in; Manual is moved with
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
## Numpad 4 / 6 / 8 / 2 step, degrees.
const TURN_STEP := 15.0
## Pixels a right drag moves before it orbits instead of clicking.
const DRAG_THRESHOLD := 5.0
## Pan speed in view distances per second.
const PAN_SPEED := 1.1
const SMOOTHING := 14.0
## Aim reach in meters.
const REACH := 250.0
## Nothing is cut away (the shader's cut_height).
const NO_CUT := 1e9
const ORTHO_BACK := 120.0

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
## Walls-down on, and how high the walls stay (meters above the pivot).
var walls_down := false
const WALLS_DOWN_HEIGHT := 0.6
## Build mode (empty levels, EditorTool): the cut sits here (the active storey's ceiling, cut away)
## whenever cutting isn't off; -1 for the usual Auto / Manual. And Page Up / Down call this with +1 /
## -1 to change storeys instead of moving the cut, when it's set.
var storey_cut := -1
var on_storey_key := Callable()
## Orthographic (numpad 5): no perspective, for lining up a layout; the zoom distance sets its size.
var orthographic := false
## Off while a tool step uses the wheel to size things.
var zoom_enabled := true
## Auto cut: the ceiling layer of the room being worked on (the selected one), -1 for the room under
## the pivot.
var focus_ceiling := -1

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
	active = false
	_set_shader_cut(NO_CUT)
	if is_instance_valid(lab):
		_set_shader_walls_down()


func set_active(on: bool) -> void:
	active = on
	camera.current = on
	if not on:
		_cap.visible = false
		_set_shader_cut(NO_CUT)
		_set_shader_walls_down()
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


func mouse_position() -> Vector2:
	return _mouse


## The camera ray through the mouse, as [origin, direction].
func mouse_ray() -> Array[Vector3]:
	return [camera.project_ray_origin(_mouse), camera.project_ray_normal(_mouse)]


func is_cutting() -> bool:
	return active and cut_mode != Cut.OFF and cut_layer > 0 and cut_layer < lab.world.get_size_in_voxels().y


## World height of the cut plane.
func cut_y() -> float:
	return lab.world.global_position.y + cut_layer * lab.world.voxel_size


## What raycast's answer depends on besides the ray: on, the cut, walls-down and where it is.
func pick_state() -> Array:
	return [active, cut_mode, cut_layer, walls_down, _shown_pivot, _shown_yaw]


## VoxelWorld.raycast that sees what the cutaway shows: it starts at the cut plane (so it hits the
## cap first) and misses anything above the cut. distance is from origin, as usual; cap is true
## on a hit on the cap.
func raycast(origin: Vector3, direction: Vector3, reach := REACH) -> Dictionary:
	var world := lab.world
	if not is_cutting():
		return _raycast_walls_down(origin, direction, reach)
	var top := cut_y() - 0.001
	var start := origin
	var skipped := 0.0
	if origin.y > top:
		if direction.y >= 0.0:
			return {hit = false}
		skipped = (origin.y - top) / -direction.y
		start = origin + direction * skipped
	var hit: Dictionary = _raycast_walls_down(start, direction, reach - skipped)
	if not hit.hit:
		return hit
	if hit.voxel.y >= cut_layer:
		return {hit = false}
	if hit.normal == Vector3.ZERO:
		hit.normal = Vector3.UP # Started inside a solid voxel: that's the cap, facing up.
		hit.cap = true
	hit.distance += skipped
	return hit


## True where walls-down hides things (the shader's test): above the walls' height on the
## camera's side of the pivot.
func _hidden_by_walls_down(point: Vector3) -> bool:
	if not active or not walls_down:
		return false
	return point.y > _shown_pivot.y + WALLS_DOWN_HEIGHT and _side_of_pivot(point) < -0.3


func _forward_flat() -> Vector2:
	return Vector2(-sin(deg_to_rad(_shown_yaw)), -cos(deg_to_rad(_shown_yaw)))


func _side_of_pivot(point: Vector3) -> float:
	return (Vector2(point.x, point.z) - Vector2(_shown_pivot.x, _shown_pivot.z)).dot(_forward_flat())


## How far along the ray it leaves the walls-down hidden region (0 if it starts outside): where it
## drops below the walls' height or crosses to the pivot's side, whichever comes first.
func _exit_walls_down(origin: Vector3, direction: Vector3) -> float:
	if not _hidden_by_walls_down(origin):
		return 0.0
	var leave := INF
	if direction.y < 0.0:
		leave = (origin.y - (_shown_pivot.y + WALLS_DOWN_HEIGHT)) / -direction.y
	var along := Vector2(direction.x, direction.z).dot(_forward_flat())
	if along > 0.0:
		leave = minf(leave, (-0.3 - _side_of_pivot(origin)) / along)
	return leave + 0.001 if leave < INF else INF


## VoxelWorld.raycast past what walls-down hides, from where the ray enters the world: outside it
## the world reads as solid, so a camera above or beside it would hit itself. The world's outer
## faces aren't drawn either (rock at the edge shows nothing from outside), so a ray coming in
## through solid goes on to the first air before it can hit anything.
func _raycast_walls_down(origin: Vector3, direction: Vector3, reach: float) -> Dictionary:
	var world := lab.world
	var box := AABB(world.global_position, Vector3(world.get_size_in_voxels()) * world.voxel_size)
	if box.has_point(origin):
		return _raycast_walls_down_inside(origin, direction, reach)
	var entry = box.intersects_ray(origin, direction)
	if entry == null:
		return {hit = false}
	var dir := direction.normalized()
	var skipped: float = origin.distance_to(entry) + 0.0005
	skipped += _solid_run(origin + dir * skipped, dir, reach - skipped)
	if skipped >= reach:
		return {hit = false}
	var hit := _raycast_walls_down_inside(origin + dir * skipped, direction, reach - skipped)
	if hit.hit:
		hit.distance += skipped
	return hit


## How far a ray starting inside the world goes through solid voxels before it reaches air (0 when
## it starts in air; past reach when it never does inside the world).
func _solid_run(origin: Vector3, dir: Vector3, reach: float) -> float:
	var world := lab.world
	var size: Vector3i = world.get_size_in_voxels()
	var o := (origin - world.global_position) / world.voxel_size
	var pos := Vector3i(o.floor())
	var step := Vector3i.ZERO
	var t_max := Vector3.INF
	var t_delta := Vector3.INF
	for a in 3:
		if dir[a] > 0.0:
			step[a] = 1
			t_delta[a] = 1.0 / dir[a]
			t_max[a] = (pos[a] + 1 - o[a]) * t_delta[a]
		elif dir[a] < 0.0:
			step[a] = -1
			t_delta[a] = -1.0 / dir[a]
			t_max[a] = (o[a] - pos[a]) * t_delta[a]
	var max_t := reach / world.voxel_size
	var t := 0.0
	while t <= max_t:
		if pos.x < 0 or pos.y < 0 or pos.z < 0 or pos.x >= size.x or pos.y >= size.y or pos.z >= size.z:
			return reach + 1.0 # Out the far side: nothing in the world to see.
		if world.get_voxel(pos) == 0:
			return t * world.voxel_size + (0.0005 if t > 0.0 else 0.0)
		var a := 0 if t_max.x < t_max.y and t_max.x < t_max.z else (1 if t_max.y < t_max.z else 2)
		t = t_max[a]
		t_max[a] += t_delta[a]
		pos[a] += step[a]
	return reach + 1.0


func _raycast_walls_down_inside(origin: Vector3, direction: Vector3, reach: float) -> Dictionary:
	var travelled := _exit_walls_down(origin, direction.normalized())
	if travelled >= reach:
		return {hit = false}
	var from := origin + direction.normalized() * travelled
	var step := direction.normalized() * lab.world.voxel_size * 0.5
	for i in 64:
		var hit: Dictionary = lab.world.raycast(from, direction, reach - travelled)
		if not hit.hit or not _hidden_by_walls_down(lab.view.to_world(Vector3(hit.voxel) + Vector3.ONE * 0.5)):
			if hit.hit:
				hit.distance += travelled
			return hit
		# Step just past the hidden voxel and look again.
		var past: Vector3 = hit.position + step
		travelled += from.distance_to(past)
		from = past
	return {hit = false}


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
			if on_storey_key.is_valid():
				on_storey_key.call(1)
			else:
				move_cut(cut_step)
		elif InputSetup.pressed(event, "editor_cut_down"):
			if on_storey_key.is_valid():
				on_storey_key.call(-1)
			else:
				move_cut(-cut_step)
		elif InputSetup.pressed(event, "editor_cut_mode") and not event.echo:
			set_cut_mode((cut_mode + 1) % CUT_NAMES.size() as Cut)
		elif InputSetup.pressed(event, "editor_walls_down") and not event.echo:
			set_walls_down(not walls_down)
		elif zoom_enabled and _numpad_view(event):
			pass # While a tool step sizes something, the numpad types sizes instead.
		else:
			used = false
		if used:
			get_viewport().set_input_as_handled()


## The numpad view keys; true if the key was one.
func _numpad_view(event: InputEvent) -> bool:
	var views := {
		editor_view_front = func() -> void: view_from(0.0, PITCH_MIN),
		editor_view_back = func() -> void: view_from(180.0, PITCH_MIN),
		editor_view_right = func() -> void: view_from(90.0, PITCH_MIN),
		editor_view_left = func() -> void: view_from(-90.0, PITCH_MIN),
		editor_view_top = func() -> void: view_from(snappedf(yaw, 90.0), PITCH_MAX),
		editor_view_around = func() -> void: yaw += 180.0,
		editor_view_ortho = func() -> void: set_orthographic(not orthographic),
		editor_turn_left = func() -> void: turn(TURN_STEP),
		editor_turn_right = func() -> void: turn(-TURN_STEP),
		editor_tilt_up = func() -> void: turn(0.0, -TURN_STEP),
		editor_tilt_down = func() -> void: turn(0.0, TURN_STEP),
		editor_zoom_in = func() -> void: zoom(1.0 / ZOOM_STEP),
		editor_zoom_out = func() -> void: zoom(ZOOM_STEP),
	}
	for action: String in views:
		if InputSetup.pressed(event, action):
			views[action].call()
			return true
	return false


func zoom(factor: float) -> void:
	distance = clampf(distance * factor, DISTANCE_MIN, DISTANCE_MAX)


func _drag(relative: Vector2) -> void:
	if _drag_pans:
		# Pans in the screen's plane: looking straight ahead, up / down raises and lowers the view;
		# looking down, it moves forward and back.
		var scale := _shown_distance * 0.0015
		var tilt := deg_to_rad(pitch)
		_pan(Vector3(-relative.x, relative.y * cos(tilt), -relative.y * sin(tilt)) * scale)
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
	pivot.y = clampf(pivot.y, lo.y, hi.y)
	pivot.z = clampf(pivot.z, lo.z, hi.z)


func set_cut_mode(mode: Cut) -> void:
	if mode == Cut.MANUAL and not is_cutting():
		cut_layer = _auto_layer(cut_layer)
	cut_mode = mode
	if mode == Cut.AUTO:
		_update_auto_cut(true)
	lab.notify("Cutaway: %s" % CUT_NAMES[mode], false)


func set_walls_down(on: bool) -> void:
	walls_down = on
	lab.notify("Walls down" if on else "Walls up", false)


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
	if storey_cut >= 0 and cut_mode != Cut.OFF:
		cut_layer = storey_cut
	elif cut_mode == Cut.AUTO:
		_update_auto_cut(false)

	var blend := 1.0 - exp(-SMOOTHING * delta)
	_shown_pivot = _shown_pivot.lerp(pivot, blend)
	_shown_yaw = lerpf(_shown_yaw, yaw, blend)
	_shown_pitch = lerpf(_shown_pitch, pitch, blend)
	_shown_distance = lerpf(_shown_distance, distance, blend)
	_place_camera()
	_update_cut()
	_set_shader_walls_down()


func _place_camera() -> void:
	var basis := Basis.from_euler(Vector3(deg_to_rad(-_shown_pitch), deg_to_rad(_shown_yaw), 0.0))
	# Orthographic stands well back (the zoom is its size, not its distance), so nothing near the
	# pivot is behind it.
	var back := maxf(_shown_distance, ORTHO_BACK) if orthographic else _shown_distance
	camera.global_transform = Transform3D(basis, _shown_pivot + basis * Vector3(0.0, 0.0, back))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if orthographic else Camera3D.PROJECTION_PERSPECTIVE
	# The same height of view at the pivot as in perspective, so switching doesn't jump.
	camera.size = 2.0 * _shown_distance * tan(deg_to_rad(camera.fov * 0.5))


## Numpad views (Blender's keys): a straight-on view of the side the yaw faces, keeping the pivot.
func view_from(yaw_degrees: float, pitch_degrees: float) -> void:
	yaw = _nearest_turn(yaw_degrees)
	pitch = clampf(pitch_degrees, PITCH_MIN, PITCH_MAX)


## Turns by degrees (numpad 4 / 6) or tilts (numpad 8 / 2).
func turn(yaw_degrees: float, pitch_degrees := 0.0) -> void:
	yaw += yaw_degrees
	pitch = clampf(pitch + pitch_degrees, PITCH_MIN, PITCH_MAX)


func set_orthographic(on: bool) -> void:
	orthographic = on
	lab.notify("Orthographic" if on else "Perspective", false)


## The yaw equal to target (mod 360) closest to the current one, so the view turns the short way.
func _nearest_turn(target: float) -> float:
	return yaw + wrapf(target - yaw, -180.0, 180.0)


## Auto cut: the ceiling over the pivot. Over solid ground (between rooms) it keeps the last one, so
## panning across a wall doesn't flash the whole roof back. force also takes it from solid.
func _update_auto_cut(force: bool) -> void:
	if focus_ceiling > 0:
		cut_layer = focus_ceiling
		return
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


## Walls-down uniforms, on the terrain and the cap.
func _set_shader_walls_down() -> void:
	var on := active and walls_down
	var forward := Vector2(-sin(deg_to_rad(_shown_yaw)), -cos(deg_to_rad(_shown_yaw)))
	for material in [lab.world.material as ShaderMaterial, _cap_material]:
		if material:
			material.set_shader_parameter("walls_down_point", _shown_pivot)
			material.set_shader_parameter("walls_down_dir", forward if on else Vector2.ZERO)
			material.set_shader_parameter("walls_down_height", _shown_pivot.y + WALLS_DOWN_HEIGHT if on else NO_CUT)


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
