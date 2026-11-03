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
## The interact key was pressed (local player, while playing).
signal interacted

@export var world: VoxelWorld

@export_group("Health")
@export var max_health := 100.0
@export var regen_delay := 4.0
@export var regen_rate := 8.0

@export_group("Movement")
@export var walk_speed := 5.5
@export var crouch_speed := 2.2
## Quake-style: speed gained per second toward the wish speed is acceleration x wish speed.
@export var ground_acceleration := 10.0
## Friction on the ground, per second; below stop_speed it brakes as if moving at stop_speed, so
## you come to a clean stop.
@export var ground_friction := 6.0
@export var stop_speed := 1.5
## In the air, acceleration only adds speed along the wish direction up to air_wish_speed (m/s), so
## strafing while turning curves and slowly gains speed (bunny hopping)...
@export var air_acceleration := 12.0
@export var air_wish_speed := 1.0
## ...up to this horizontal speed (m/s); faster than that, the air only steers.
@export var max_air_speed := 8.8
@export var jump_velocity := 5.2
## Letting go of jump while still rising keeps this much of the upward speed.
@export var jump_cut := 0.5
## Jump this long after walking off a ledge still works.
@export var coyote_time := 0.1
## A jump pressed this long before landing fires on landing (and skips that landing's friction).
@export var jump_buffer := 0.12
@export var gravity := 16.0
@export var step_height := 0.45
@export var fly_speed := 12.0
@export var climb_speed := 2.6
## Camera dip on landing: meters per m/s of fall speed, at most land_dip_max.
@export var land_dip := 0.012
@export var land_dip_max := 0.14

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
## Status effects on this player (local player only): name -> seconds left. Clouds give them
## through EnemyManager.status_player; cleared on revive. See STATUS_DPS.
var statuses := {}

var _since_damage := 0.0
var _ladder_cooldown := 0.0
var _height := standing_height
var _step_offset := 0.0
## Seconds of coyote time and jump buffer left.
var _coyote := 0.0
var _buffered := 0.0
## Rising from a jump (jump_cut applies once if jump is let go).
var _jumping := false
var _land_offset := 0.0
var _eye_height := standing_height - eye_offset
var _previous_position := Vector3.ZERO
var _trauma := 0.0
var _recoil := 0.0
var _shake_noise := FastNoiseLite.new()

## Damage per second of each player status. blinded (spore clouds) does no damage: it fogs this
## player's screen (BLIND_*).
const STATUS_DPS := {poisoned = 2.0, burning = 6.0, blinded = 0.0}
## Blinded: the fog overlay's color and how opaque it gets; fades in / out at BLIND_FADE per second.
const BLIND_COLOR := Color(0.78, 0.78, 0.74)
const BLIND_MAX := 0.93
const BLIND_FADE := 2.5
## Held by a tentacle (set_held): pulled toward the anchor at HELD_PULL m/s until within HELD_CLOSE.
const HELD_PULL := 2.0
const HELD_CLOSE := 0.9

## The id (as a String) of the tentacle holding this player, "" when free. Set through
## EnemyManager.hold_player on the player's own peer (and the host's copy, for bookkeeping).
var held_by := ""
## Where the holding tentacle is (feet), what the pull heads for.
var held_anchor := Vector3.ZERO
## 0..1, how fogged this (local) player's screen is from being blinded.
var blind_amount := 0.0
var _blind_overlay: ColorRect
## Status damage lands in steps this many seconds apart.
const STATUS_TICK := 0.5
var _status_tick := 0.0

## Larger per-tick moves than this are teleports, not movement, and skip camera interpolation.
const MAX_INTERPOLATED_STEP := 2.0
## Movement states sent per second to the other peers.
const NET_SEND_RATE := 30.0
## Remote players are drawn this far in the past so there's always a newer state to blend toward.
const REMOTE_DELAY := 0.1

## False on the copies of other peers' players.
var is_local := true
## Carrying the spore shooter (levels with `start_unarmed` begin without it; the case drops it).
## Replicated with the movement state so every peer hides or shows the gun.
var has_weapon := true
## Level editor: flying with no weapon or collision.
var editing := false
## Level editor builder view (EditorCamera): the player stays put and leaves the mouse free.
var builder_view := false
## Peers to stream this player's state to. Set by the level; empty in single-player.
var net_peers: Array[int] = []
var display_name := ""

var _send_timer := 0.0
## Received [time, position, yaw, pitch], oldest first.
var _remote_states: Array[Array] = []
var _body: MeshInstance3D
var _head_mesh: MeshInstance3D
var _name_tag: Label3D

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var muzzle_flash: OmniLight3D = $Head/Camera3D/MuzzleFlash
## The Weapon and Inventory children. Untyped on purpose: naming Weapon here would compile the
## enemy and level scripts (and the autoloads they use) wherever Player is named.
@onready var weapon = $Weapon
@onready var inventory = $Inventory


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
		var watch := get_node_or_null("/root/VoxWatch")
		if watch:
			watch.changed.connect(_on_vox_changed)


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
	# Handled in _input so no UI or other node can swallow the way out of mouse capture. The level
	# editor handles Esc itself (it backs out of a tool step first).
	if event.is_action_pressed("ui_cancel") and not editing:
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
		if editing and (builder_view or not EditorInput.world_may_use(event)):
			return
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().gui_release_focus() # A text field mustn't keep typing while we fly.
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_fly") and OS.is_debug_build() and not editing:
		flying = not flying
		velocity = Vector3.ZERO
	elif event.is_action_pressed("interact") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		interacted.emit()
	elif event.is_action_pressed("toggle_flashlight"):
		flashlight.visible = not flashlight.visible


func _physics_process(delta: float) -> void:
	if world == null or not is_local:
		return
	_previous_position = global_position
	_since_damage += delta
	if not is_dead and _since_damage > regen_delay:
		health = minf(max_health, health + regen_rate * delta)
	_tick_statuses(delta)
	if is_dead:
		velocity = Vector3.ZERO
	elif flying:
		_fly(delta)
	else:
		_walk(delta)

	# Smooth the camera over step-ups instead of snapping it up a ledge.
	_step_offset = move_toward(_step_offset, 0.0, maxf(absf(_step_offset) * 12.0, 1.0) * delta)
	_land_offset = lerpf(_land_offset, 0.0, 1.0 - exp(-10.0 * delta))
	_eye_height = lerpf(_eye_height, _height - eye_offset, 1.0 - exp(-15.0 * delta))
	_send_state(delta)


func _process(delta: float) -> void:
	if not is_local:
		_interpolate_remote()
		return
	var key_look := _vector("look_left", "look_right", "look_up", "look_down")
	if key_look != Vector2.ZERO:
		_look(key_look * key_look_speed * delta)

	# Movement runs at the physics rate, but the screen refreshes faster. Interpolate the camera
	# between the last two physics positions so it moves smoothly at any frame rate.
	if _previous_position.distance_squared_to(global_position) > MAX_INTERPOLATED_STEP * MAX_INTERPOLATED_STEP:
		_previous_position = global_position # Moved by something other than walking; don't smear.
	var smoothed := _previous_position.lerp(global_position, Engine.get_physics_interpolation_fraction())
	head.position = Vector3(0.0, _eye_height + _step_offset - _land_offset, 0.0) + global_basis.inverse() * (smoothed - global_position)
	_apply_shake(delta)
	_update_blind(delta)


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
	var push := global_position - from
	push.y = 0.0
	velocity += push.normalized() * 4.0 + Vector3.UP * 2.0
	add_shake(hurt_shake)
	_lose_health(amount, from)


func _lose_health(amount: float, from: Vector3) -> void:
	health -= amount
	_since_damage = 0.0
	damaged.emit(amount, from)
	if health <= 0.0:
		health = 0.0
		is_dead = true
		died.emit()


## A status ("poisoned", "burning", "blinded": STATUS_DPS) for seconds; a longer time replaces
## what's left.
func apply_status(status: String, seconds: float) -> void:
	if STATUS_DPS.has(status) and not is_dead:
		statuses[status] = maxf(float(statuses.get(status, 0.0)), seconds)


## Local player, every frame: fades the blinded fog overlay (a fullscreen layer on this peer's own
## screen, made the first time it's needed) in while blinded and out after.
func _update_blind(delta: float) -> void:
	var goal := BLIND_MAX if statuses.has("blinded") else 0.0
	blind_amount = move_toward(blind_amount, goal, BLIND_FADE * delta)
	if blind_amount <= 0.0 and _blind_overlay == null:
		return
	if _blind_overlay == null:
		var layer := CanvasLayer.new()
		layer.name = "BlindLayer"
		layer.layer = 5
		add_child(layer)
		_blind_overlay = ColorRect.new()
		_blind_overlay.name = "BlindOverlay"
		_blind_overlay.color = BLIND_COLOR
		_blind_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_blind_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.add_child(_blind_overlay)
	# A slow churn so it reads as drifting spores, not a flat wall.
	var churn := 1.0 - 0.06 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.003))
	_blind_overlay.modulate.a = blind_amount * churn
	_blind_overlay.visible = blind_amount > 0.0


## Grabbed by a tentacle (holder: its enemy id as a String) or let go (""). While held, _walk
## ignores movement input and pulls toward anchor; shooting, melee and throwing still work.
func set_held(holder: String, anchor: Vector3) -> void:
	held_by = holder
	held_anchor = anchor


func is_held() -> bool:
	return held_by != ""


## Local: the holder is gone on this peer (died, despawned, play stopped) though no release came.
func _holder_gone() -> bool:
	var manager = get_tree().get_first_node_in_group("enemy_manager") if is_inside_tree() else null
	return manager == null or not manager.enemies.has(int(held_by))


func _tick_statuses(delta: float) -> void:
	if statuses.is_empty() or is_dead:
		_status_tick = 0.0
		return
	var amount := 0.0
	_status_tick += delta
	var ticked := _status_tick >= STATUS_TICK
	if ticked:
		_status_tick -= STATUS_TICK
	for status: String in statuses.keys():
		if ticked:
			amount += float(STATUS_DPS.get(status, 0.0)) * STATUS_TICK
		statuses[status] = float(statuses[status]) - delta
		if statuses[status] <= 0.0:
			statuses.erase(status)
	if amount > 0.0:
		_lose_health(amount, global_position) # No knockback or shake: the HUD vignette shows it.


## Level editor on / off: editing flies through everything.
func set_editing(on: bool) -> void:
	editing = on
	flying = on
	if not on:
		builder_view = false
	velocity = Vector3.ZERO


## Remote players: shows or hides their figure (the level editor hides it while they're in the
## builder view, where they're a camera instead).
func set_body_visible(shown: bool) -> void:
	for node in [_body, _head_mesh, _name_tag]:
		if node:
			node.visible = shown


## Arms or disarms the player (the spore shooter, melee and flasks all need the weapon).
func set_armed(on: bool) -> void:
	has_weapon = on


## Back to full health after dying.
func revive() -> void:
	health = max_health
	is_dead = false
	velocity = Vector3.ZERO
	statuses.clear()
	held_by = ""


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

	var input := _vector("move_left", "move_right", "move_forward", "move_back")
	if held_by != "" and _holder_gone():
		held_by = ""
	var held := held_by != ""
	if held:
		input = Vector2.ZERO
	var wish := (global_basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := walk_speed
	if crouching:
		speed = crouch_speed
	if held:
		# Dragged toward the tentacle, then held there.
		var to_anchor := Vector3(held_anchor.x - global_position.x, 0.0, held_anchor.z - global_position.z)
		wish = to_anchor.normalized() if to_anchor.length() > HELD_CLOSE else Vector3.ZERO
		speed = HELD_PULL

	_ladder_cooldown -= delta
	var ladder := _ladder_direction() if _ladder_cooldown <= 0.0 and not held else Vector3.ZERO
	on_ladder = ladder != Vector3.ZERO and not crouching

	# Coyote time and the jump buffer: a jump goes when both are open.
	_coyote = coyote_time if on_floor else _coyote - delta
	_buffered = jump_buffer if _just("jump") else _buffered - delta
	var jump := not on_ladder and not held and _buffered > 0.0 and _coyote > 0.0

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if on_ladder:
		horizontal = horizontal.move_toward(wish * minf(speed, climb_speed), ground_acceleration * speed * delta)
	elif on_floor:
		# No friction on the frame a buffered jump leaves the ground: chained hops keep their speed.
		if not jump:
			horizontal = _friction(horizontal, delta)
		horizontal = _accelerate(horizontal, wish, speed, ground_acceleration * speed * delta)
	else:
		horizontal = _air_accelerate(horizontal, wish, speed, delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if on_ladder:
		# Forward/back climbs. Without input the player just hangs on.
		var climb := float(_held("move_forward")) - float(_held("move_back"))
		velocity.y = climb * climb_speed
		if _just("jump"):
			velocity = -ladder * 3.0 + Vector3.UP * 2.0
			_ladder_cooldown = 0.4
			on_ladder = false
	else:
		velocity.y -= gravity * delta
		if jump:
			velocity.y = jump_velocity
			_coyote = 0.0
			_buffered = 0.0
			_jumping = true
		elif _jumping and velocity.y > 0.0 and not _held("jump"):
			velocity.y *= jump_cut # Let go early: a shorter hop.
			_jumping = false
		if velocity.y <= 0.0:
			_jumping = false

	var start := global_position
	var falling := -velocity.y
	var was_on_floor := on_floor
	var result: Dictionary = world.move_box(start, get_body_size(), velocity * delta, step_height, on_floor)
	global_position = result.position
	on_floor = result.on_floor
	_step_offset -= result.step_up
	if on_floor and not was_on_floor and falling > 3.0:
		_land_offset = minf(falling * land_dip, land_dip_max)

	if (on_floor and velocity.y < 0.0) or (result.hit_ceiling and velocity.y > 0.0):
		velocity.y = 0.0
	if result.hit_wall:
		# Keep only the velocity that actually turned into movement so we don't grind into walls.
		var moved := (global_position - start) / delta
		velocity.x = moved.x
		velocity.z = moved.z


## Crouching on the ground lowers the head; in the air it pulls the feet up instead (a crouch-jump
## clears higher ledges), and standing back up in the air lets them down if there's room.
func _update_crouch() -> void:
	var wants_crouch := _held("crouch")
	var tuck := standing_height - crouching_height
	if wants_crouch and not crouching:
		crouching = true
		_height = crouching_height
		if not on_floor:
			var raised := AABB(global_position + Vector3(-width * 0.5, tuck, -width * 0.5), Vector3(width, crouching_height, width))
			if not world.box_overlaps_solid(raised):
				global_position.y += tuck
				_previous_position.y += tuck
				_eye_height -= tuck # The head stays put; the feet came up.
	elif not wants_crouch and crouching:
		var standing := AABB(global_position - Vector3(width * 0.5, 0.0, width * 0.5), Vector3(width, standing_height, width))
		var lowered := AABB(standing.position - Vector3(0.0, tuck, 0.0), standing.size)
		if not world.box_overlaps_solid(standing):
			crouching = false
			_height = standing_height
		elif not on_floor and not world.box_overlaps_solid(lowered):
			crouching = false
			_height = standing_height
			global_position.y -= tuck
			_previous_position.y -= tuck
			_eye_height += tuck


## Quake friction: slows horizontal speed, braking at least as hard as at stop_speed.
func _friction(horizontal: Vector3, delta: float) -> Vector3:
	var speed := horizontal.length()
	if speed < 0.001:
		return Vector3.ZERO
	var drop := maxf(speed, stop_speed) * ground_friction * delta
	return horizontal * (maxf(speed - drop, 0.0) / speed)


## Adds speed along wish (unit) until the speed along it reaches wish_speed, at most step.
static func _accelerate(horizontal: Vector3, wish: Vector3, wish_speed: float, step: float) -> Vector3:
	if wish == Vector3.ZERO:
		return horizontal
	var add := wish_speed - horizontal.dot(wish)
	if add <= 0.0:
		return horizontal
	return horizontal + wish * minf(step, add)


## Air control: only air_wish_speed along the wish direction, so turning while strafing curves the
## path and gains a little speed each time; past max_air_speed it can steer but not speed up.
func _air_accelerate(horizontal: Vector3, wish: Vector3, wish_speed: float, delta: float) -> Vector3:
	var before := horizontal.length()
	var out := _accelerate(horizontal, wish, minf(wish_speed, air_wish_speed), air_acceleration * wish_speed * delta)
	var after := out.length()
	var cap := maxf(before, max_air_speed)
	if after > cap:
		out *= cap / after
	return out


func _fly(delta: float) -> void:
	var input := _vector("move_left", "move_right", "move_forward", "move_back")
	var up := float(_held("jump")) - float(_held("crouch"))
	var wish := head.global_basis * Vector3(input.x, 0.0, input.y) + Vector3.UP * up
	var speed := fly_speed * (3.0 if _input_live() and Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	global_position += wish.normalized() * speed * delta
	on_floor = false


#region Networking

# Polled input counts only while the mouse is captured (or headless) and no editor modal or text
# field has the keys, and not under the editor's builder view (whose WASD pans the camera);
# otherwise typing or a menu would walk the player around.
func _input_live() -> bool:
	return InputSetup.is_playing() and not builder_view and not EditorInput.blocks_keyboard()


func _vector(negative_x: String, positive_x: String, negative_y: String, positive_y: String) -> Vector2:
	return Input.get_vector(negative_x, positive_x, negative_y, positive_y) if _input_live() else Vector2.ZERO


func _held(action: String) -> bool:
	return _input_live() and Input.is_action_pressed(action)


func _just(action: String) -> bool:
	return _input_live() and Input.is_action_just_pressed(action)


func _send_state(delta: float) -> void:
	if net_peers.is_empty():
		return
	_send_timer -= delta
	if _send_timer > 0.0:
		return
	_send_timer += 1.0 / NET_SEND_RATE
	for peer_id in net_peers:
		_net_state.rpc_id(peer_id, global_position, rotation.y, head.rotation.x, crouching, flashlight.visible, is_dead, has_weapon)


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(feet: Vector3, yaw: float, pitch: float, is_crouching: bool, light_on: bool, dead: bool, armed := true) -> void:
	has_weapon = armed
	var now := Time.get_ticks_msec() / 1000.0
	if _remote_states.is_empty():
		global_position = feet # First state: appear there instead of sliding in from the spawn.
	_remote_states.append([now, feet, yaw, pitch])
	if _remote_states.size() > 16:
		_remote_states.pop_front()
	if is_crouching != crouching:
		crouching = is_crouching
		if _body:
			_body.scale.y = crouching_height / standing_height if crouching else 1.0
		head.position.y = (crouching_height if crouching else standing_height) - eye_offset
	flashlight.visible = light_on
	is_dead = dead # So the host's enemies stop chasing a dead remote player.


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


## Other players' figure, from assets/vox/characters: the body stands on its bottom center, the
## head turns with the look pitch around its center.
func _build_remote_body() -> void:
	_build_body_meshes()
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


func _build_body_meshes() -> void:
	var body := _load_character("player_body")
	if not body.is_empty():
		_body = _model_instance(body, self)
		_body.position = Vector3(-body.size.x * 0.5, 0.0, -body.size.z * 0.5) * world.voxel_size
		_body.scale.y = crouching_height / standing_height if crouching else 1.0
	var head_model := _load_character("player_head")
	if not head_model.is_empty():
		_head_mesh = _model_instance(head_model, head)
		_head_mesh.position = -Vector3(head_model.size) * 0.5 * world.voxel_size


## Live reload: rebuild the figure when its .vox files change.
func _on_vox_changed(paths: PackedStringArray) -> void:
	var touched := false
	for path in paths:
		if path.begins_with("res://assets/vox/characters/"):
			_characters.erase(path.get_file().get_basename())
			touched = true
	if not touched:
		return
	for mesh in [_body, _head_mesh]:
		if mesh:
			mesh.queue_free()
	_body = null
	_head_mesh = null
	_build_body_meshes()


static var _characters := {}


static func _load_character(name: String) -> Dictionary:
	if not _characters.has(name):
		_characters[name] = VoxFile.load_model("res://assets/vox/characters/%s.vox" % name)
	return _characters[name]


func _model_instance(model: Dictionary, parent: Node3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = world.build_model_mesh(model.size, model.voxels)
	instance.material_override = world.material
	parent.add_child(instance)
	return instance

#endregion
