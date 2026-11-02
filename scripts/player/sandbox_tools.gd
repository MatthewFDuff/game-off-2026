class_name SandboxTools
extends Node
## Foundation test weapons: a hitscan rifle that chips voxels and an explosive that carves craters.
## Stand-ins until the real weapon system exists. Inactive while build mode is on.

## A shot or blast damaged a shroom. killed is true when that hit finished it.
signal shroom_hit(killed: bool)
## kind is "rifle" or "blast", for sound.
signal fired(kind: String)
## The blast charge count changed (spent, bought or refilled).
signal blasts_changed(count: int)
## A blast could not be fired or bought; reason is player-facing text.
signal blast_refused(reason: String)

@export var player: Player
@export var camera: Camera3D
@export var debris: VoxelDebris
@export var build_tool: BuildTool
@export var shrooms: ShroomManager
@export var director: ShiftDirector
@export var state: GameState

@export_group("Rifle")
@export var rifle_fire_rate := 10.0
@export var rifle_radius := 0.14
@export var rifle_power := 4
@export var rifle_range := 120.0
@export var rifle_damage := 20.0

@export_group("Explosive")
@export var blast_radius := 1.2
@export var blast_power := 6
@export var blast_cooldown := 0.35
@export var blast_damage := 150.0
## Charges granted at the start of each day shift.
@export var blasts_per_shift := 3
## Price of one extra charge, bought with the buy_blast action during the day.
@export var blast_cost := 10

@export_group("Feedback")
## Upward kick per rifle shot in radians.
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

## Blasts left. Refilled to blasts_per_shift at every day phase.
var blast_charges := 3
var _cooldown := 0.0
var _refusal_cooldown := 0.0
var _flash_timer := 0.0
var _tracers: Array[MeshInstance3D] = []
var _tracer_life: Array[float] = []
var _next_tracer := 0


func _ready() -> void:
	blast_charges = blasts_per_shift
	if director:
		director.phase_changed.connect(_on_phase_changed)
	if camera == null:
		return
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	for i in 2:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = tracer_color
		var tracer := MeshInstance3D.new()
		tracer.mesh = box
		tracer.material_override = material
		tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tracer.top_level = true
		tracer.visible = false
		camera.add_child(tracer)
		_tracers.append(tracer)
		_tracer_life.append(0.0)


func _process(delta: float) -> void:
	_cooldown -= delta
	_refusal_cooldown -= delta
	_update_effects(delta)
	if not InputSetup.is_playing():
		return
	if Input.is_action_just_pressed("buy_blast"):
		_buy_blast()
	if build_tool and build_tool.active:
		return

	if Input.is_action_pressed("fire") and _cooldown <= 0.0:
		_cooldown = 1.0 / rifle_fire_rate
		_shoot()
	elif Input.is_action_just_pressed("alt_fire") and _cooldown <= 0.0:
		if blast_charges <= 0:
			_refuse("Out of blasts — buy more with [B] during the day ($%d)" % blast_cost)
			return
		_cooldown = blast_cooldown
		_explode()


## Sets the charge count back to blasts_per_shift.
func refill_blasts() -> void:
	blast_charges = blasts_per_shift
	blasts_changed.emit(blast_charges)


func _on_phase_changed(phase: ShiftDirector.Phase) -> void:
	if phase == ShiftDirector.Phase.DAY:
		refill_blasts()


func _buy_blast() -> void:
	if director == null or director.phase != ShiftDirector.Phase.DAY:
		_refuse("Can only buy blasts during the day shift")
		return
	if state == null or not state.spend(blast_cost):
		_refuse("Need $%d to buy a blast" % blast_cost)
		return
	blast_charges += 1
	blasts_changed.emit(blast_charges)


## Emits blast_refused, at most once per 1.5 seconds.
func _refuse(reason: String) -> void:
	if _refusal_cooldown > 0.0:
		return
	_refusal_cooldown = 1.5
	blast_refused.emit(reason)


func _aim(max_distance: float) -> Dictionary:
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	return player.world.raycast(origin, direction, max_distance)


func _shoot() -> void:
	fired.emit("rifle")
	_kick(rifle_recoil, rifle_shake)
	var hit := _aim(rifle_range)
	var target := _hit_shroom(rifle_range, hit, rifle_damage)
	if not target.is_empty():
		_tracer(target.position)
		return
	if not hit.hit:
		_tracer(camera.global_position - camera.global_basis.z * 60.0)
		return
	_tracer(hit.position)
	var removed: Dictionary = player.world.carve_sphere(hit.position, rifle_radius, rifle_power)
	debris.burst(hit.position, hit.normal, removed if not removed.is_empty() else {hit.material: 2})


func _explode() -> void:
	var hit := _aim(rifle_range)
	var target := _shroom_along_aim(rifle_range)
	if not target.is_empty() and (not hit.hit or target.distance < hit.distance):
		# Detonate on the shroom, facing back toward the player.
		hit = {hit = true, position = target.position, normal = camera.global_basis.z}
	if not hit.hit:
		return
	blast_charges -= 1
	blasts_changed.emit(blast_charges)
	fired.emit("blast")
	_kick(blast_recoil, 0.0)
	var removed: Dictionary = player.world.carve_sphere(hit.position, blast_radius, blast_power)
	debris.burst(hit.position, hit.normal, removed)
	if player:
		player.add_shake(blast_shake)
	if shrooms:
		# Same reach as damage_sphere, so the hit marker matches what actually took damage.
		var radius := blast_radius + 1.0
		var caught: Array[Shroom] = []
		for shroom in shrooms.shrooms:
			if shroom.get_center().distance_to(hit.position) < radius:
				caught.append(shroom)
		shrooms.damage_sphere(hit.position, radius, blast_damage)
		if not caught.is_empty():
			var killed := false
			for shroom in caught:
				killed = killed or not is_instance_valid(shroom) or shroom.health <= 0.0
			shroom_hit.emit(killed)


## Damages the shroom under the crosshair if it's closer than the terrain hit. Returns that hit
## ({shroom, distance, position}), or {} if the terrain was in the way.
func _hit_shroom(max_distance: float, terrain_hit: Dictionary, damage: float) -> Dictionary:
	var target := _shroom_along_aim(max_distance)
	if target.is_empty() or (terrain_hit.hit and terrain_hit.distance < target.distance):
		return {}
	var direction := -camera.global_basis.z
	var shroom: Shroom = target.shroom
	shroom.take_damage(damage, direction * 1.5)
	debris.burst(target.position, -direction, {VoxelMaterials.GLOW: 20})
	shroom_hit.emit(shroom.health <= 0.0)
	return target


func _shroom_along_aim(max_distance: float) -> Dictionary:
	if shrooms == null:
		return {}
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	var hit := shrooms.raycast(origin, direction, max_distance)
	if not hit.is_empty():
		hit.position = origin + direction * hit.distance
	return hit


func _kick(recoil: float, shake: float) -> void:
	if player:
		player.add_recoil(recoil)
		if shake > 0.0:
			player.add_shake(shake)
	if player and player.muzzle_flash:
		player.muzzle_flash.visible = true
		_flash_timer = muzzle_flash_time


## Shows a pooled tracer from the gun to point.
func _tracer(point: Vector3) -> void:
	if _tracers.is_empty():
		return
	var from := camera.global_transform * tracer_origin
	var span := point - from
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
		if _flash_timer <= 0.0 and player and player.muzzle_flash:
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
