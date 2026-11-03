class_name Rifle
extends Node
## Placeholder co-op weapon on each player: a hitscan rifle that chips voxels, and an alt-fire blast
## that carves a crater. The owning peer aims and fires; terrain damage goes through WorldSync so
## every world agrees, and the other peers are sent the shot so they see its tracer and hear it.

## kind is "rifle" or "blast". Emitted for the local player's shots only.
signal fired(kind: String)

@export var world_sync: WorldSync

@export_group("Rifle")
@export var fire_rate := 10.0
@export var chip_radius := 0.14
@export var chip_power := 4
@export var weapon_range := 120.0

@export_group("Blast")
@export var blast_radius := 1.2
@export var blast_power := 6
@export var blast_cooldown := 0.8

@export_group("Feedback")
@export var rifle_recoil := 0.018
@export var rifle_shake := 0.12
@export var blast_recoil := 0.06
@export var blast_shake := 0.6
@export var muzzle_flash_time := 0.05
@export var tracer_time := 0.08
@export var tracer_width := 0.012
@export var tracer_color := Color(1.0, 0.85, 0.55, 0.9)
## Where tracers start, in camera space: just below and right of the view.
@export var tracer_origin := Vector3(0.12, -0.1, -0.35)

var player: Player
var _cooldown := 0.0
var _flash_timer := 0.0
var _tracers: Array[MeshInstance3D] = []
var _tracer_life: Array[float] = []
var _next_tracer := 0


func _ready() -> void:
	player = get_parent() as Player
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	for i in 6:
		var tracer := MeshInstance3D.new()
		tracer.mesh = box
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tracer.material_override = material
		tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tracer.top_level = true
		tracer.visible = false
		add_child(tracer)
		_tracers.append(tracer)
		_tracer_life.append(0.0)


func _process(delta: float) -> void:
	_cooldown -= delta
	_update_effects(delta)
	if not player.is_local or player.is_dead or player.editing or not InputSetup.is_playing():
		return
	if Input.is_action_pressed("fire") and _cooldown <= 0.0:
		_cooldown = 1.0 / fire_rate
		_fire("rifle")
	elif Input.is_action_just_pressed("alt_fire") and _cooldown <= 0.0:
		_cooldown = blast_cooldown
		_fire("blast")


func _fire(kind: String) -> void:
	var camera := player.camera
	var direction := -camera.global_basis.z
	var hit: Dictionary = player.world.raycast(camera.global_position, direction, weapon_range)
	var end: Vector3 = hit.position if hit.hit else camera.global_position + direction * 60.0
	var muzzle := camera.global_transform * tracer_origin

	fired.emit(kind)
	Sfx.play(kind)
	if kind == "rifle":
		player.add_recoil(rifle_recoil)
		player.add_shake(rifle_shake)
	else:
		player.add_recoil(blast_recoil)
		player.add_shake(blast_shake)
	_show_shot(muzzle, end)
	for peer_id in player.net_peers:
		_remote_shot.rpc_id(peer_id, kind, muzzle, end)

	if hit.hit:
		if kind == "rifle":
			world_sync.carve_sphere(hit.position, chip_radius, chip_power, hit.normal)
		else:
			world_sync.carve_sphere(hit.position, blast_radius, blast_power, hit.normal)


@rpc("authority", "call_remote", "unreliable")
func _remote_shot(kind: String, muzzle: Vector3, end: Vector3) -> void:
	Sfx.play_at(kind, muzzle)
	_show_shot(muzzle, end)


func _show_shot(from: Vector3, to: Vector3) -> void:
	player.muzzle_flash.visible = true
	_flash_timer = muzzle_flash_time
	var span := to - from
	var length := span.length()
	if length < 0.05:
		return
	var tracer := _tracers[_next_tracer]
	_tracer_life[_next_tracer] = tracer_time
	_next_tracer = (_next_tracer + 1) % _tracers.size()
	var up := Vector3.UP if absf(span.normalized().y) < 0.99 else Vector3.RIGHT
	var axes := Basis.looking_at(span, up)
	axes.x *= tracer_width
	axes.y *= tracer_width
	axes.z *= length
	tracer.global_transform = Transform3D(axes, from + span * 0.5)
	(tracer.material_override as StandardMaterial3D).albedo_color = tracer_color
	tracer.visible = true


func _update_effects(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			player.muzzle_flash.visible = false
	for i in _tracers.size():
		if _tracer_life[i] <= 0.0:
			continue
		_tracer_life[i] -= delta
		var tracer := _tracers[i]
		if _tracer_life[i] <= 0.0:
			tracer.visible = false
		else:
			var color := tracer_color
			color.a *= _tracer_life[i] / tracer_time
			(tracer.material_override as StandardMaterial3D).albedo_color = color
