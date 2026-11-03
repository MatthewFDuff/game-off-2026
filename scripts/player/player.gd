class_name Player
extends Node3D
## First-person controller that collides directly against the voxel grid through
## VoxelWorld.move_box. The node's position is the player's feet (bottom center of the box).
##
## In co-op, each peer is the multiplayer authority of its own player and simulates it locally,
## streaming its state to net_peers. Everyone else's copy is remote: no camera or input, just a
## placeholder body that interpolates between the received states.

## from is the attacker's world position.
signal damaged(amount: float, from: Vector3)
signal died

@export var world: VoxelWorld

@export_group("Health")
@export var max_health := 100.0
@export var regen_delay := 4.0
@export var regen_rate := 8.0

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
@export var climb_speed := 2.6

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

@export_group("Camera Feel")
## Trauma lost per second; the shake strength is trauma squared.
@export var shake_decay := 1.5
## Head offset in meters at full trauma.
@export var shake_offset := 0.08
## Camera roll / pitch / yaw in radians at full trauma.
@export var shake_angle := 0.04
@export var hurt_shake := 0.35
## How quickly recoil pitch settles back, per second.
@export var recoil_recovery := 14.0

var velocity := Vector3.ZERO
var on_floor := false
var crouching := false
var flying := false
var on_ladder := false
var health := max_health
var is_dead := false

var _since_damage := 0.0
var _ladder_cooldown := 0.0
var _height := standing_height
var _step_offset := 0.0
var _eye_height := standing_height - eye_offset
var _previous_position := Vector3.ZERO
var _trauma := 0.0
var _recoil := 0.0
var _shake_noise := FastNoiseLite.new()

## Larger per-tick moves than this are teleports, not movement, and skip camera interpolation.
const MAX_INTERPOLATED_STEP := 2.0
## Movement states sent per second to the other peers.
const NET_SEND_RATE := 30.0
## Remote players are drawn this far in the past so there's always a newer state to blend toward.
const REMOTE_DELAY := 0.1

## False on the copies of other peers' players.
var is_local := true
## Peers to stream this player's state to. Set by the level; empty in single-player.
var net_peers: Array[int] = []
var display_name := ""

var _send_timer := 0.0
## Received [time, position, yaw, pitch], oldest first.
var _remote_states: Array[Array] = []
var _body: MeshInstance3D
var _name_tag: Label3D

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var muzzle_flash: OmniLight3D = $Head/Camera3D/MuzzleFlash


func _ready() -> void:
	InputSetup.ensure_actions()
	_height = standing_height
	_previous_position = global_position
	_shake_noise.frequency = 0.9
	_shake_noise.seed = randi()
	is_local = is_multiplayer_authority()
	if not is_local:
		camera.current = false
		set_process_input(false)
		set_process_unhandled_input(false)
		head.position = Vector3(0.0, standing_height - eye_offset, 0.0)
		_build_remote_body()


## Name and color shown over remote players.
func set_display(player_name: String, color: Color) -> void:
	display_name = player_name
	if _name_tag:
		_name_tag.text = player_name
		_name_tag.modulate = color


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
	elif event.is_action_pressed("toggle_fly") and OS.is_debug_build():
		flying = not flying
		velocity = Vector3.ZERO
	elif event.is_action_pressed("toggle_flashlight"):
		flashlight.visible = not flashlight.visible


func _physics_process(delta: float) -> void:
	if world == null or not is_local:
		return
	_previous_position = global_position
	_since_damage += delta
	if not is_dead and _since_damage > regen_delay:
		health = minf(max_health, health + regen_rate * delta)
	if is_dead:
		velocity = Vector3.ZERO
	elif flying:
		_fly(delta)
	else:
		_walk(delta)

	# Smooth the camera over step-ups instead of snapping it up a ledge.
	_step_offset = move_toward(_step_offset, 0.0, maxf(absf(_step_offset) * 12.0, 1.0) * delta)
	_eye_height = lerpf(_eye_height, _height - eye_offset, 1.0 - exp(-15.0 * delta))
	_send_state(delta)


func _process(delta: float) -> void:
	if not is_local:
		_interpolate_remote()
		return
	var key_look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if key_look != Vector2.ZERO:
		_look(key_look * key_look_speed * delta)

	# Movement runs at the physics rate, but the screen refreshes faster. Interpolate the camera
	# between the last two physics positions so it moves smoothly at any frame rate.
	if _previous_position.distance_squared_to(global_position) > MAX_INTERPOLATED_STEP * MAX_INTERPOLATED_STEP:
		_previous_position = global_position # Moved by something other than walking; don't smear.
	var smoothed := _previous_position.lerp(global_position, Engine.get_physics_interpolation_fraction())
	head.position = Vector3(0.0, _eye_height + _step_offset, 0.0) + global_basis.inverse() * (smoothed - global_position)
	_apply_shake(delta)


## Adds camera trauma (0..1). Small values for gunfire, ~0.35 for a hit, ~0.6 for a blast.
func add_shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Kicks the view up by pitch radians; it settles back on its own without moving the aim pitch.
func add_recoil(pitch: float) -> void:
	_recoil += pitch


## Shake and recoil ride on top of the interpolated head: translation on the head, rotation on the
## camera, so neither the look pitch nor the step smoothing is touched.
func _apply_shake(delta: float) -> void:
	_recoil = lerpf(_recoil, 0.0, 1.0 - exp(-recoil_recovery * delta))
	if _trauma <= 0.0:
		camera.rotation = Vector3(_recoil, 0.0, 0.0)
		return
	_trauma = maxf(0.0, _trauma - shake_decay * delta)
	var strength := _trauma * _trauma
	var t := Time.get_ticks_msec() * 0.06
	var n := _shake_noise
	head.position += Vector3(n.get_noise_2d(t, 0.0), n.get_noise_2d(t, 100.0), 0.0) * shake_offset * strength
	var angle := shake_angle * strength
	camera.rotation = Vector3(_recoil + n.get_noise_2d(t, 200.0) * angle, n.get_noise_2d(t, 300.0) * angle, n.get_noise_2d(t, 400.0) * angle)


## from is where the hit came from, for knockback.
func take_damage(amount: float, from: Vector3) -> void:
	if is_dead:
		return
	health -= amount
	_since_damage = 0.0
	var push := global_position - from
	push.y = 0.0
	velocity += push.normalized() * 4.0 + Vector3.UP * 2.0
	add_shake(hurt_shake)
	damaged.emit(amount, from)
	if health <= 0.0:
		health = 0.0
		is_dead = true
		died.emit()


## Moves the player without the camera smoothing across the gap.
func teleport(feet: Vector3) -> void:
	global_position = feet
	_previous_position = feet
	velocity = Vector3.ZERO


## Turns by look.x radians of yaw and look.y radians of pitch (positive is right / down).
func _look(look: Vector2) -> void:
	rotate_y(-look.x)
	head.rotation.x = clampf(head.rotation.x - look.y, -PI * 0.49, PI * 0.49)


## Direction from the player to a ladder they're touching, or zero if none.
func _ladder_direction() -> Vector3:
	# Rungs are one voxel tall, so check every voxel layer the body spans, not a few sample heights.
	var reach := width * 0.5 + 0.06
	var feet: Vector3i = world.world_to_voxel(global_position + Vector3.UP * 0.05)
	var layers := ceili(_height / world.voxel_size)
	for direction in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var column: Vector3i = world.world_to_voxel(global_position + Vector3.UP * 0.05 + direction * reach)
		for y in layers:
			if world.get_voxel(Vector3i(column.x, feet.y + y, column.z)) == VoxelMaterials.LADDER:
				return direction
	return Vector3.ZERO


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

	_ladder_cooldown -= delta
	var ladder := _ladder_direction() if _ladder_cooldown <= 0.0 else Vector3.ZERO
	on_ladder = ladder != Vector3.ZERO and not crouching

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var acceleration := ground_acceleration if on_floor or on_ladder else air_acceleration
	if on_ladder:
		speed = minf(speed, climb_speed)
	horizontal = horizontal.move_toward(wish * speed, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if on_ladder:
		# Forward/back climbs. Without input the player just hangs on.
		var climb := Input.get_axis("move_back", "move_forward")
		velocity.y = climb * climb_speed
		if Input.is_action_just_pressed("jump"):
			velocity = -ladder * 3.0 + Vector3.UP * 2.0
			_ladder_cooldown = 0.4
			on_ladder = false
	else:
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


#region Networking

func _send_state(delta: float) -> void:
	if net_peers.is_empty():
		return
	_send_timer -= delta
	if _send_timer > 0.0:
		return
	_send_timer += 1.0 / NET_SEND_RATE
	for peer_id in net_peers:
		_net_state.rpc_id(peer_id, global_position, rotation.y, head.rotation.x, crouching, flashlight.visible)


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(feet: Vector3, yaw: float, pitch: float, is_crouching: bool, light_on: bool) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _remote_states.is_empty():
		global_position = feet # First state: appear there instead of sliding in from the spawn.
	_remote_states.append([now, feet, yaw, pitch])
	if _remote_states.size() > 16:
		_remote_states.pop_front()
	if is_crouching != crouching:
		crouching = is_crouching
		_body.scale.y = crouching_height / standing_height if crouching else 1.0
		head.position.y = (crouching_height if crouching else standing_height) - eye_offset
	flashlight.visible = light_on


func _interpolate_remote() -> void:
	if _remote_states.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0 - REMOTE_DELAY
	var newest: Array = _remote_states.back()
	var a: Array = newest
	var b: Array = newest
	for i in range(_remote_states.size() - 1, 0, -1):
		if _remote_states[i - 1][0] <= t:
			a = _remote_states[i - 1]
			b = _remote_states[i]
			break
	var span: float = b[0] - a[0]
	var f := clampf((t - a[0]) / span, 0.0, 1.0) if span > 0.0 else 1.0
	global_position = (a[1] as Vector3).lerp(b[1], f)
	rotation.y = lerp_angle(a[2], b[2], f)
	head.rotation.x = lerpf(a[3], b[3], f)


## Placeholder voxel figure for other players, until the real character model exists.
func _build_remote_body() -> void:
	const M := preload("res://scripts/voxel/voxel_materials.gd")
	var body_size := Vector3i(6, 15, 4)
	var voxels := PackedByteArray()
	voxels.resize(body_size.x * body_size.y * body_size.z)
	for z in body_size.z:
		for y in body_size.y:
			for x in body_size.x:
				var id := M.CLOTH if y < 7 else M.WALL_PAINT
				if y < 7 and x in [2, 3]:
					id = M.AIR # Gap between the legs.
				voxels[x + y * body_size.x + z * body_size.x * body_size.y] = id
	_body = _model_instance(body_size, voxels, self)
	_body.position = Vector3(-body_size.x, 0.0, -body_size.z) * 0.5 * world.voxel_size

	var head_size := Vector3i(4, 4, 4)
	var head_voxels := PackedByteArray()
	head_voxels.resize(64)
	head_voxels.fill(M.PLASTIC)
	for x in [0, 3]:
		head_voxels[x + 2 * 4] = M.GLASS # Eyes on the front (z = 0, facing -Z).
	var head_mesh := _model_instance(head_size, head_voxels, head)
	head_mesh.position = Vector3(-2.0, -1.5, -2.0) * world.voxel_size

	_name_tag = Label3D.new()
	_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_tag.fixed_size = true
	_name_tag.pixel_size = 0.0012
	_name_tag.font_size = 24
	_name_tag.outline_size = 8
	_name_tag.no_depth_test = true
	_name_tag.position = Vector3(0.0, standing_height + 0.35, 0.0)
	_name_tag.text = display_name
	add_child(_name_tag)


func _model_instance(size: Vector3i, voxels: PackedByteArray, parent: Node3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = world.build_model_mesh(size, voxels)
	instance.material_override = world.material
	parent.add_child(instance)
	return instance

#endregion
