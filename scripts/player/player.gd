class_name Player
extends Node3D
## First-person controller that collides directly against the voxel grid through
## VoxelWorld.move_box. The node's position is the player's feet (bottom center of the box).

@export var world: VoxelWorld

@export_group("Movement")
@export var walk_speed := 4.5
@export var sprint_speed := 7.5
@export var crouch_speed := 2.2
@export var ground_acceleration := 60.0
@export var air_acceleration := 10.0
@export var jump_velocity := 5.2
@export var gravity := 16.0
@export var step_height := 0.45
@export var fly_speed := 12.0

@export_group("Body")
@export var width := 0.6
@export var standing_height := 1.75
@export var crouching_height := 1.1
@export var eye_offset := 0.12

@export_group("Look")
@export var mouse_sensitivity := 0.0025
## Arrow-key look speed in radians per second. A fallback for remote desktop sessions, where
## captured mouse motion often doesn't arrive.
@export var key_look_speed := 2.2

var velocity := Vector3.ZERO
var on_floor := false
var crouching := false
var flying := false

var _height := standing_height
var _step_offset := 0.0
var _eye_height := standing_height - eye_offset
var _previous_position := Vector3.ZERO

## Larger per-tick moves than this are teleports, not movement, and skip camera interpolation.
const MAX_INTERPOLATED_STEP := 2.0

@onready var head: Node3D = $Head
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight


func _ready() -> void:
	InputSetup.ensure_actions()
	_height = standing_height
	_previous_position = global_position


func _notification(what: int) -> void:
	# Never keep the cursor locked when the game window loses focus (alt-tab, editor, etc).
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	# Handled in _input so no UI or other node can swallow the way out of mouse capture.
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# screen_relative ignores the stretch mode's content scaling, so look speed doesn't depend
		# on window size. It arrives as zero in some setups (the editor's embedded game window),
		# so fall back to relative there.
		var motion: Vector2 = event.screen_relative
		if motion == Vector2.ZERO:
			motion = event.relative
		_look(motion * mouse_sensitivity)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_fly"):
		flying = not flying
		velocity = Vector3.ZERO
	elif event.is_action_pressed("toggle_flashlight"):
		flashlight.visible = not flashlight.visible


func _physics_process(delta: float) -> void:
	if world == null:
		return
	_previous_position = global_position
	if flying:
		_fly(delta)
	else:
		_walk(delta)

	# Smooth the camera over step-ups instead of snapping it up a ledge.
	_step_offset = move_toward(_step_offset, 0.0, maxf(absf(_step_offset) * 12.0, 1.0) * delta)
	_eye_height = lerpf(_eye_height, _height - eye_offset, 1.0 - exp(-15.0 * delta))


func _process(delta: float) -> void:
	var key_look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if key_look != Vector2.ZERO:
		_look(key_look * key_look_speed * delta)

	# Movement runs at the physics rate, but the screen refreshes faster. Interpolate the camera
	# between the last two physics positions so it moves smoothly at any frame rate.
	if _previous_position.distance_squared_to(global_position) > MAX_INTERPOLATED_STEP * MAX_INTERPOLATED_STEP:
		_previous_position = global_position # Moved by something other than walking; don't smear.
	var smoothed := _previous_position.lerp(global_position, Engine.get_physics_interpolation_fraction())
	head.position = Vector3(0.0, _eye_height + _step_offset, 0.0) + global_basis.inverse() * (smoothed - global_position)


## Moves the player without the camera smoothing across the gap.
func teleport(feet: Vector3) -> void:
	global_position = feet
	_previous_position = feet
	velocity = Vector3.ZERO


## Turns by look.x radians of yaw and look.y radians of pitch (positive is right / down).
func _look(look: Vector2) -> void:
	rotate_y(-look.x)
	head.rotation.x = clampf(head.rotation.x - look.y, -PI * 0.49, PI * 0.49)


func get_body_size() -> Vector3:
	return Vector3(width, _height, width)


## World-space bounds of the player's collision box.
func get_body_aabb() -> AABB:
	var size := get_body_size()
	return AABB(global_position - Vector3(size.x * 0.5, 0.0, size.z * 0.5), size)


func _walk(delta: float) -> void:
	_update_crouch()

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := (global_basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := walk_speed
	if crouching:
		speed = crouch_speed
	elif Input.is_action_pressed("sprint"):
		speed = sprint_speed

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var acceleration := ground_acceleration if on_floor else air_acceleration
	horizontal = horizontal.move_toward(wish * speed, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	velocity.y -= gravity * delta
	if on_floor and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var start := global_position
	var result: Dictionary = world.move_box(start, get_body_size(), velocity * delta, step_height, on_floor)
	global_position = result.position
	on_floor = result.on_floor
	_step_offset -= result.step_up

	if (on_floor and velocity.y < 0.0) or (result.hit_ceiling and velocity.y > 0.0):
		velocity.y = 0.0
	if result.hit_wall:
		# Keep only the velocity that actually turned into movement so we don't grind into walls.
		var moved := (global_position - start) / delta
		velocity.x = moved.x
		velocity.z = moved.z


func _update_crouch() -> void:
	var wants_crouch := Input.is_action_pressed("crouch")
	if wants_crouch and not crouching:
		crouching = true
		_height = crouching_height
	elif not wants_crouch and crouching:
		var standing := AABB(global_position - Vector3(width * 0.5, 0.0, width * 0.5), Vector3(width, standing_height, width))
		if not world.box_overlaps_solid(standing):
			crouching = false
			_height = standing_height


func _fly(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var up := float(Input.is_action_pressed("jump")) - float(Input.is_action_pressed("crouch"))
	var wish := head.global_basis * Vector3(input.x, 0.0, input.y) + Vector3.UP * up
	var speed := fly_speed * (3.0 if Input.is_action_pressed("sprint") else 1.0)
	global_position += wish.normalized() * speed * delta
	on_floor = false
