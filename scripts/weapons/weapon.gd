class_name Weapon
extends Node
## The shroom shooter, on every player: one gun, swappable ammo (AmmoType). The owning peer aims
## and fires with `fire`, changes ammo with `cycle_ammo` (Shift) or `ammo_1..4`, and spends ammo
## from the player's Inventory (basic is infinite). `alt_fire` is left for flasks (phase 3).
##
## Hits are shooter-authoritative: this peer finds them (Combat) and sends enemy damage to the host
## through EnemyManager.request_hit and terrain damage through WorldSync. The other peers get the
## shot (tracers, flame, sound) and this peer's projectiles as visual copies (spawn, bounce,
## position corrections, impact), and never apply damage from them.
##
## Looks: a view model under the camera for the owner, a third-person model in the head of other
## peers' copies, both from assets/vox/weapons/shroom_shooter.vox (GearModels). Its GLOW voxels
## take the active ammo's color, so co-op partners can see what everyone has loaded.

## Emitted for the local player's shots only.
signal fired(ammo_name: String)
signal ammo_changed(ammo_name: String)
## A projectile this weapon fired (or, on other peers, a copy of one).
signal projectile_spawned(projectile: Projectile)

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const MODEL := "shroom_shooter"
const TRACERS := 16
## Homing projectiles: position corrections per second to the other peers.
const SYNC_RATE := 10.0
## Seconds the flame keeps showing after its last cone check.
const FLAME_LINGER := 0.18

@export var world_sync: WorldSync
@export var enemies: EnemyManager

@export_group("Model")
## Where the muzzle sits: in camera space for the owner's view model, in head space on other peers.
@export var view_offset := Vector3(0.16, -0.15, -0.5)
@export var body_offset := Vector3(0.24, -0.34, -0.42)
## Drawn size of one model voxel (meters).
@export var view_voxel := 0.02
@export var body_voxel := 0.032

@export_group("Feedback")
@export var muzzle_flash_time := 0.05
@export var tracer_time := 0.08
@export var tracer_width := 0.012

var player: Player
var inventory: Inventory
## The loaded ammo type's name and settings.
var current := "basic"
var ammo: AmmoType

var _cooldown := 0.0
var _flash_timer := 0.0
var _flame_time := 0.0
var _kick := 0.0
var _sync_timer := 0.0
var _tracers: Array[MeshInstance3D] = []
var _tracer_life: Array[float] = []
var _tracer_colors: Array[Color] = []
var _next_tracer := 0
## Holds the model; its origin is the muzzle.
var _pivot: Node3D
var _model: Node3D
var _flash_mesh: MeshInstance3D
var _flame: CPUParticles3D
## id -> Projectile (fired here, or copies of the owner's).
var _projectiles := {}
var _next_projectile := 1


func _ready() -> void:
	player = get_parent() as Player
	ammo = AmmoType.by_name(current)
	if player == null:
		return
	if not player.is_node_ready():
		await player.ready
	inventory = player.get_node_or_null("Inventory")
	if inventory:
		inventory.changed.connect(_on_inventory_changed)
	_build_tracers()
	_build_model()
	var watch := get_node_or_null("/root/VoxWatch")
	if watch:
		watch.changed.connect(_on_vox_changed)


func _process(delta: float) -> void:
	if player == null or _pivot == null:
		return
	_cooldown -= delta
	_update_effects(delta)
	if not player.is_local or player.is_dead or player.editing or not InputSetup.is_playing():
		return
	if Input.is_action_just_pressed("cycle_ammo"):
		cycle()
	for slot in 4:
		if Input.is_action_just_pressed("ammo_%d" % (slot + 1)):
			select(AmmoType.ORDER[slot])
	if Input.is_action_pressed("fire"):
		fire()


func _physics_process(delta: float) -> void:
	_sync_timer -= delta
	if _sync_timer > 0.0 or player == null or player.net_peers.is_empty():
		return
	_sync_timer = 1.0 / SYNC_RATE
	for shot: Projectile in _projectiles.values():
		if shot.authoritative and not shot.done and shot.ammo.homing_angle > 0.0:
			for peer_id in player.net_peers:
				_projectile_sync.rpc_id(peer_id, shot.id, shot.global_position, shot.velocity)


# --- Ammo ----------------------------------------------------------------------------------------

## Loads an ammo type (it needs ammo, except basic). Returns false if it can't.
func select(ammo_name: String) -> bool:
	var type := AmmoType.by_name(ammo_name)
	if type == null or (inventory and not inventory.has_ammo(ammo_name)):
		return false
	if ammo_name == current:
		return true
	_load(type)
	_cooldown = maxf(_cooldown, 0.12)
	if player.is_local:
		Sfx.play("ammo_shift", -4.0)
		for peer_id in player.net_peers:
			_remote_ammo.rpc_id(peer_id, ammo_name)
	return true


## Ammo types this player can load, in slot order (basic always).
func available() -> Array[String]:
	var out: Array[String] = []
	for ammo_name: String in AmmoType.ORDER:
		if inventory == null or inventory.has_ammo(ammo_name):
			out.append(ammo_name)
	return out


## The type Shift would load next.
func next_ammo() -> String:
	var types := available()
	if types.is_empty():
		return current
	return types[(types.find(current) + 1) % types.size()]


## Shift: the next type there's ammo for.
func cycle() -> void:
	select(next_ammo())


func _load(type: AmmoType) -> void:
	current = type.name
	ammo = type
	if _model:
		GearModels.set_tint(_model, type.color)
	ammo_changed.emit(current)


func _on_inventory_changed() -> void:
	if inventory and not inventory.has_ammo(current):
		select("basic")


@rpc("authority", "call_remote", "reliable")
func _remote_ammo(ammo_name: String) -> void:
	var type := AmmoType.by_name(ammo_name)
	if type and type != ammo:
		_load(type)


# --- Firing --------------------------------------------------------------------------------------

## Fires the loaded ammo if it's ready and there's ammo; direction defaults to where the camera
## looks. Returns whether it fired.
func fire(direction := Vector3.ZERO) -> bool:
	if _cooldown > 0.0 or player == null or player.world == null:
		return false
	var type := ammo
	if inventory and not inventory.use_ammo(type.name):
		select("basic")
		return false
	_cooldown = 1.0 / type.rate
	var camera := player.camera
	var origin := camera.global_position
	var aim := direction.normalized() if direction != Vector3.ZERO else -camera.global_basis.z
	var muzzle := muzzle_position()
	match type.mode:
		"hitscan":
			_fire_hitscan(type, origin, aim, muzzle)
		"cone":
			_fire_cone(type, origin, aim, muzzle)
		_:
			_fire_projectile(type, origin, aim, muzzle)
	fired.emit(type.name)
	Sfx.play(type.sound, type.sound_db, 0.08, type.sound_pitch)
	player.add_recoil(type.recoil)
	player.add_shake(type.shake)
	_kick = 1.0
	return true


## World position of the muzzle (the model's front).
func muzzle_position() -> Vector3:
	return _pivot.global_position if _pivot else player.camera.global_position


func _fire_hitscan(type: AmmoType, origin: Vector3, aim: Vector3, muzzle: Vector3) -> void:
	var ends := PackedVector3Array()
	# enemy id -> [damage, point]
	var damage := {}
	for i in type.pellets:
		var direction := _spread(aim, type.spread)
		var hit := Combat.ray_hit(player.world, origin, direction, type.reach)
		ends.append(hit.position if hit.hit else origin + direction * minf(type.reach, 60.0))
		if not hit.hit:
			continue
		if hit.enemy:
			var entry: Array = damage.get(hit.enemy.id, [0.0, hit.position])
			entry[0] += type.damage
			damage[hit.enemy.id] = entry
		elif type.carve_radius > 0.0 and world_sync:
			world_sync.carve_sphere(hit.position, type.carve_radius, type.carve_power, hit.normal)
	if enemies:
		for id: int in damage:
			enemies.request_hit(id, damage[id][0], damage[id][1], type.kind)
	_show_shots(type, muzzle, ends)
	for peer_id in player.net_peers:
		_remote_shot.rpc_id(peer_id, type.name, muzzle, ends)


## Flame: every enemy in the cone with a clear line from the camera gets a tick of damage and the
## status (burning).
func _fire_cone(type: AmmoType, origin: Vector3, aim: Vector3, muzzle: Vector3) -> void:
	for enemy in Combat.enemies():
		var center := enemy.get_center()
		var to := center - origin
		var distance := to.length()
		var radius := maxf(enemy.bounds.size.x, enemy.bounds.size.z) * 0.5
		if distance > type.reach + radius:
			continue
		if distance > 0.01 and rad_to_deg(aim.angle_to(to)) > type.spread + rad_to_deg(atan2(radius, distance)):
			continue
		var sight: Dictionary = player.world.raycast(origin, to / maxf(distance, 0.01), distance)
		if sight.hit and sight.distance < distance - radius:
			continue
		if enemies:
			enemies.request_hit(enemy.id, type.damage, center - to.normalized() * radius, type.kind)
			if type.status != "":
				enemies.request_status(enemy.id, type.status, type.status_seconds)
	_show_shots(type, muzzle, PackedVector3Array())
	for peer_id in player.net_peers:
		_remote_shot.rpc_id(peer_id, type.name, muzzle, PackedVector3Array())


## Projectiles leave the muzzle toward whatever the camera ray hits, so they land on the crosshair.
func _fire_projectile(type: AmmoType, origin: Vector3, aim: Vector3, muzzle: Vector3) -> void:
	var target := Combat.ray_hit(player.world, origin, aim, type.reach)
	var direction := aim
	if target.hit and target.distance > 1.5:
		direction = (target.position - muzzle).normalized()
	var id := _next_projectile
	_next_projectile += 1
	var velocity := direction * type.speed
	_spawn_projectile(id, type, muzzle, velocity, true)
	_show_shots(type, muzzle, PackedVector3Array())
	for peer_id in player.net_peers:
		_remote_projectile.rpc_id(peer_id, id, type.name, muzzle, velocity)


## A random direction within degrees of aim.
static func _spread(aim: Vector3, degrees: float) -> Vector3:
	if degrees <= 0.0:
		return aim
	var side := aim.cross(Vector3.UP)
	if side.length() < 0.01:
		side = aim.cross(Vector3.RIGHT)
	side = side.normalized().rotated(aim, randf() * TAU)
	return aim.rotated(side, deg_to_rad(degrees) * sqrt(randf()))


@rpc("authority", "call_remote", "unreliable")
func _remote_shot(ammo_name: String, muzzle: Vector3, ends: PackedVector3Array) -> void:
	var type := AmmoType.by_name(ammo_name)
	if type == null:
		return
	if type != ammo:
		_load(type)
	Sfx.play_at(type.sound, muzzle, type.sound_db, 0.08, type.sound_pitch)
	_show_shots(type, muzzle, ends)


# --- Projectiles ---------------------------------------------------------------------------------

func _spawn_projectile(id: int, type: AmmoType, from: Vector3, velocity: Vector3, shooter: bool) -> Projectile:
	var shot: Projectile = PROJECTILE_SCENE.instantiate()
	shot.name = "P%d" % id
	shot.setup(id, type, player.world, from, velocity, shooter)
	if shooter:
		shot.bounced.connect(_on_bounced)
		shot.hit_enemy.connect(_on_projectile_hit)
		shot.impacted.connect(_on_impacted)
	shot.tree_exiting.connect(func() -> void:
		if _projectiles.get(id) == shot:
			_projectiles.erase(id))
	_projectiles[id] = shot
	add_child(shot)
	projectile_spawned.emit(shot)
	return shot


func _on_bounced(shot: Projectile, at: Vector3, normal: Vector3) -> void:
	Sfx.play_at("ricochet", at, -6.0, 0.15)
	if shot.ammo.carve_radius > 0.0 and world_sync:
		world_sync.carve_sphere(at - normal * 0.05, shot.ammo.carve_radius, shot.ammo.carve_power, normal)
	for peer_id in player.net_peers:
		_projectile_bounced.rpc_id(peer_id, shot.id, at, shot.velocity)


func _on_projectile_hit(shot: Projectile, hit: Dictionary) -> void:
	if enemies:
		enemies.request_hit(hit.enemy.id, shot.ammo.damage, hit.position, shot.ammo.kind)


func _on_impacted(shot: Projectile, at: Vector3, normal: Vector3, enemy: Enemy) -> void:
	var type := shot.ammo
	match type.impact:
		"blast":
			if world_sync:
				world_sync.carve_sphere(at, type.blast_radius, type.blast_power, normal if normal != Vector3.ZERO else Vector3.UP)
			if enemies:
				for victim in Combat.sphere_hit(at, type.splash_radius):
					enemies.request_hit(victim.id, type.blast_damage, victim.get_center(), type.kind)
		"cloud":
			spawn_cloud(type, at)
		_:
			if enemy == null and normal != Vector3.ZERO and type.carve_radius > 0.0 and world_sync:
				world_sync.carve_sphere(at, type.carve_radius, type.carve_power, normal)
	_impact_fx(type, at)
	for peer_id in player.net_peers:
		_projectile_ended.rpc_id(peer_id, shot.id, type.name, at)


## Shooter: a poison impact. Phase 3 replaces this with a host-owned Cloud that applies its status
## for its lifetime; for now every enemy within cloud_radius gets the status once (every peer sees
## a puff, from _impact_fx).
func spawn_cloud(type: AmmoType, at: Vector3) -> void:
	if enemies and type.status != "":
		for enemy in Combat.sphere_hit(at, type.cloud_radius):
			enemies.request_status(enemy.id, type.status, type.status_seconds)


@rpc("authority", "call_remote", "reliable")
func _remote_projectile(id: int, ammo_name: String, from: Vector3, velocity: Vector3) -> void:
	var type := AmmoType.by_name(ammo_name)
	if type == null:
		return
	if type != ammo:
		_load(type)
	Sfx.play_at(type.sound, from, type.sound_db, 0.08, type.sound_pitch)
	_show_shots(type, from, PackedVector3Array())
	_spawn_projectile(id, type, from, velocity, false)


@rpc("authority", "call_remote", "reliable")
func _projectile_bounced(id: int, at: Vector3, velocity: Vector3) -> void:
	Sfx.play_at("ricochet", at, -6.0, 0.15)
	var shot: Projectile = _projectiles.get(id)
	if shot:
		shot.correct(at, velocity)


@rpc("authority", "call_remote", "unreliable_ordered")
func _projectile_sync(id: int, at: Vector3, velocity: Vector3) -> void:
	var shot: Projectile = _projectiles.get(id)
	if shot and not shot.done:
		shot.correct(at, velocity)


@rpc("authority", "call_remote", "reliable")
func _projectile_ended(id: int, ammo_name: String, at: Vector3) -> void:
	var shot: Projectile = _projectiles.get(id)
	if shot:
		shot.queue_free()
	var type := AmmoType.by_name(ammo_name)
	if type:
		_impact_fx(type, at)


## Every peer: what an impact looks and sounds like (the carve brings its own debris).
func _impact_fx(type: AmmoType, at: Vector3) -> void:
	match type.impact:
		"blast":
			Sfx.play_at("blast", at)
			_light_burst(at, type.color, 8.0, 0.3)
		"cloud":
			Sfx.play_at("poison_shot", at, -2.0, 0.1, 0.6)
			_puff(at, type.color, type.cloud_radius)


func _light_burst(at: Vector3, color: Color, light_range: float, seconds: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = light_range
	light.top_level = true
	add_child(light)
	light.global_position = at
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, seconds)
	tween.tween_callback(light.queue_free)


## A translucent ball that swells and fades: the poison cloud stand-in.
func _puff(at: Vector3, color: Color, radius: float) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius * 0.5
	sphere.height = radius
	sphere.radial_segments = 16
	sphere.rings = 8
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, 0.45)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var puff := MeshInstance3D.new()
	puff.mesh = sphere
	puff.material_override = material
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puff.top_level = true
	add_child(puff)
	puff.global_position = at
	puff.scale = Vector3.ONE * 0.4
	var tween := puff.create_tween().set_parallel()
	tween.tween_property(puff, "scale", Vector3.ONE * 1.6, 1.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(material, "albedo_color:a", 0.0, 1.6)
	tween.chain().tween_callback(puff.queue_free)


# --- Looks ---------------------------------------------------------------------------------------

func _build_model() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Model"
	if player.is_local:
		_pivot.position = view_offset
		player.camera.add_child(_pivot)
	else:
		_pivot.position = body_offset
		player.head.add_child(_pivot)
	_rebuild_mesh()

	var flash_box := BoxMesh.new()
	flash_box.size = Vector3(0.06, 0.06, 0.03)
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mesh = MeshInstance3D.new()
	_flash_mesh.mesh = flash_box
	_flash_mesh.material_override = flash_material
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_mesh.position = Vector3(0.0, 0.0, -0.02)
	_flash_mesh.visible = false
	_pivot.add_child(_flash_mesh)

	_flame = CPUParticles3D.new()
	_flame.emitting = false
	_flame.amount = 48
	_flame.lifetime = 0.35
	_flame.local_coords = false
	_flame.direction = Vector3.FORWARD
	_flame.spread = 12.0
	_flame.initial_velocity_min = 7.0
	_flame.initial_velocity_max = 11.0
	_flame.gravity = Vector3(0.0, 2.0, 0.0)
	_flame.damping_min = 6.0
	_flame.damping_max = 9.0
	_flame.scale_amount_min = 0.6
	_flame.scale_amount_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4, 0.9))
	ramp.set_color(1, Color(0.8, 0.15, 0.05, 0.0))
	_flame.color_ramp = ramp
	var puff := BoxMesh.new()
	puff.size = Vector3.ONE * 0.12
	var puff_material := StandardMaterial3D.new()
	puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_material.vertex_color_use_as_albedo = true
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.material = puff_material
	_flame.mesh = puff
	_pivot.add_child(_flame)


## (Re)builds the gun from its .vox, centered on the muzzle.
func _rebuild_mesh() -> void:
	if _model:
		_model.queue_free()
	var model := GearModels.weapon(MODEL)
	_model = GearModels.build(player.world, model, ammo.color, view_voxel if player.is_local else body_voxel, GearModels.muzzle(model))
	_pivot.add_child(_model)


func _build_tracers() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	for i in TRACERS:
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
		_tracer_colors.append(Color.WHITE)


## Muzzle flash, tracers to each end point, and for flame, the fire cone.
func _show_shots(type: AmmoType, from: Vector3, ends: PackedVector3Array) -> void:
	player.muzzle_flash.light_color = type.color.lerp(Color(1.0, 0.8, 0.5), 0.4)
	player.muzzle_flash.visible = true
	_flash_timer = muzzle_flash_time
	if _flash_mesh:
		(_flash_mesh.material_override as StandardMaterial3D).albedo_color = type.color.lightened(0.5)
		_flash_mesh.visible = type.mode != "cone"
	if type.mode == "cone":
		_flame_time = FLAME_LINGER
	var color := Color(type.color.lightened(0.4), 0.9)
	for to in ends:
		var span := to - from
		var length := span.length()
		if length < 0.05:
			continue
		var tracer := _tracers[_next_tracer]
		_tracer_life[_next_tracer] = tracer_time
		_tracer_colors[_next_tracer] = color
		_next_tracer = (_next_tracer + 1) % _tracers.size()
		var up := Vector3.UP if absf(span.normalized().y) < 0.99 else Vector3.RIGHT
		var axes := Basis.looking_at(span, up)
		axes.x *= tracer_width
		axes.y *= tracer_width
		axes.z *= length
		tracer.global_transform = Transform3D(axes, from + span * 0.5)
		(tracer.material_override as StandardMaterial3D).albedo_color = color
		tracer.visible = true


func _update_effects(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			player.muzzle_flash.visible = false
			if _flash_mesh:
				_flash_mesh.visible = false
	for i in _tracers.size():
		if _tracer_life[i] <= 0.0:
			continue
		_tracer_life[i] -= delta
		var tracer := _tracers[i]
		if _tracer_life[i] <= 0.0:
			tracer.visible = false
		else:
			var color := _tracer_colors[i]
			color.a *= _tracer_life[i] / tracer_time
			(tracer.material_override as StandardMaterial3D).albedo_color = color
	_flame_time -= delta
	_flame.emitting = _flame_time > 0.0
	# Kick back on each shot and settle; hidden while editing or dead.
	_kick = maxf(0.0, _kick - delta * 8.0)
	_pivot.visible = not player.editing and not player.is_dead
	var offset := view_offset if player.is_local else body_offset
	_pivot.position = offset + Vector3(0.0, 0.0, _kick * _kick * 0.05)
	_pivot.rotation.x = _kick * _kick * 0.12


## Live reload: rebuild the gun when its .vox changes.
func _on_vox_changed(paths: PackedStringArray) -> void:
	for path in paths:
		if GearModels.forget(path) == MODEL:
			_rebuild_mesh()
