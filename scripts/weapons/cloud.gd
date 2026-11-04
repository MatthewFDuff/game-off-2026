class_name Cloud
extends Node3D
## An area effect left by a flask or poison ammo: a sphere (center, radius) that lasts `seconds`.
## The host owns it: every TICK it gives its status to the enemies inside (Combat.sphere_hit,
## through Enemy.apply_status) and, for fire and poison, to the players inside (their own peer
## runs the damage, through EnemyManager.status_player). Effects only reach bodies in sight of the
## center and within its squat vertical extent (reaches), never through a floor, wall or ceiling.
## Every other peer gets a spawn message from
## EnemyManager and only draws it (an opaque voxel stain on the floor, cubes rising from it in a
## motion per type, and a tinted light: VoxelFx; nothing dithered), freeing it on its own timer.
##
## Types (TYPES): fire (a burning pool that sets flammable voxels alight through Fire),
## poison (a cloud), rage (enemies turn on each other), freeze (an instant burst: frozen, once,
## and it puts out fire),
## spore (a thick grey-white cloud that blinds players inside, from spore shrooms),
## foam (a fire extinguisher's burst: enemies inside are slowed, it puts out fire and clears the
## spore and poison clouds it overlaps, every tick: `clears`).
##
## Spawn one from any peer with Cloud.spawn(type, at, radius, seconds); it goes through the host.

## Host: seconds between status applications.
const TICK := 0.25
## Host: seconds between fire setting voxels alight a little further out.
const BURN_STEP := 0.5
## Host: the effect's vertical extent (reaches): feet from this far below the center to this far
## above it count, 2.5 m in all, so a cloud never works through a floor.
const REACH_BELOW := 1.75
const REACH_ABOVE := 0.75
## type -> settings. status / status_seconds go to enemies inside; player_status / player_seconds
## to players inside ("" for none). instant types apply once at spawn and only show for seconds.
const TYPES := {
	fire = {color = Color(1.0, 0.45, 0.12), radius = 2.5, seconds = 6.0, status = "burning", status_seconds = 3.0,
			player_status = "burning", player_seconds = 3.0, ignites = true, sound = "flame"},
	poison = {color = Color(0.45, 1.0, 0.3), radius = 3.0, seconds = 8.0, status = "poisoned", status_seconds = 3.0,
			player_status = "poisoned", player_seconds = 3.0},
	rage = {color = Color(1.0, 0.2, 0.25), radius = 3.0, seconds = 4.0, status = "raging", status_seconds = 5.0},
	freeze = {color = Color(0.55, 0.85, 1.0), radius = 3.0, seconds = 0.5, status = "frozen", status_seconds = 5.0,
			instant = true, douses = true},
	# Spore shrooms: no damage, players inside are blinded (Player fogs their screen). particles /
	# puff make it a dense, thick cloud.
	spore = {color = Color(0.82, 0.82, 0.78), radius = 4.0, seconds = 8.0, status = "",
			player_status = "blinded", player_seconds = 3.0, particles = 140, puff = 0.35, alpha = 0.5, sound = "spore_puff"},
	# Fire extinguishers (LevelPlay) and foam flasks: slows enemies, douses, clears gas clouds.
	foam = {color = Color(0.93, 0.95, 0.97), radius = 4.0, seconds = 6.0, status = "slowed", status_seconds = 1.0,
			douses = true, clears = ["spore", "poison"], particles = 90, sound = "foam_spray"},
}

## Unique per session, the same on every peer (the node is named after it).
var id := 0
var type := "poison"
var radius := 3.0
var seconds := 6.0
## Seconds since it appeared.
var age := 0.0
var manager: EnemyManager
## The host applies effects; other peers only draw.
var authoritative := false

var _tick := 0.0
var _burn_timer := 0.0
var _burned_radius := 0.0
var _stain: MeshInstance3D
var _stain_material: ShaderMaterial
## Index into STAIN_STEPS the stain shows, -1 hidden.
var _stain_step := -1
var _light: OmniLight3D
var _particles: CPUParticles3D
## Rage: the rising cubes' own material, so their pulse doesn't recolor every effect.
var _cube_material: ShaderMaterial
## Spore: a few big translucent cubes (true alpha blending) drifting through the swarm.
var _fog: CPUParticles3D
var _handed_off := false


## Any peer: asks the host for a cloud of type centered at a world point; radius and seconds below
## zero take the type's defaults. Returns the Cloud on the host, null elsewhere (or out of play).
static func spawn(cloud_type: String, at: Vector3, cloud_radius := -1.0, cloud_seconds := -1.0) -> Cloud:
	var tree := Engine.get_main_loop() as SceneTree
	var found := tree.get_first_node_in_group(EnemyManager.GROUP) if tree else null
	var enemies := found as EnemyManager
	if enemies == null:
		return null
	return enemies.request_cloud(cloud_type, at, cloud_radius, cloud_seconds)


## Settings of a type (TYPES), or {}.
static func settings(cloud_type: String) -> Dictionary:
	return TYPES.get(cloud_type, {})


func setup(cloud_id: int, cloud_type: String, at: Vector3, cloud_radius: float, cloud_seconds: float, host: bool) -> void:
	id = cloud_id
	type = cloud_type
	var defs := settings(cloud_type)
	radius = cloud_radius if cloud_radius > 0.0 else float(defs.get("radius", 3.0))
	seconds = cloud_seconds if cloud_seconds > 0.0 else float(defs.get("seconds", 6.0))
	authoritative = host
	top_level = true
	position = at


func _ready() -> void:
	global_position = position
	_build()
	var defs := settings(type)
	if defs.has("sound"):
		Sfx.play_at(defs.sound, global_position, -2.0, 0.1, 0.6)
	if authoritative:
		_apply()
		if defs.get("douses", false):
			Fire.douse_at(global_position, radius)


func _physics_process(delta: float) -> void:
	age += delta
	if age >= seconds:
		if manager:
			manager.cloud_ended(self)
		queue_free()
		return
	if not authoritative or manager == null or not manager.simulating or settings(type).get("instant", false):
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick += TICK
		_apply()
	if settings(type).get("ignites", false):
		_burn_timer -= delta
		if _burn_timer <= 0.0:
			_burn_timer = BURN_STEP
			_ignite()


## Host: the status to everything inside (reaches).
func _apply() -> void:
	if manager == null or not manager.simulating:
		return
	var defs := settings(type)
	if defs.get("status", "") != "":
		for enemy in Combat.sphere_hit(global_position, radius + REACH_BELOW):
			if reaches(enemy.world_bounds(), enemy.get_center()):
				manager.request_status(enemy.id, defs.status, defs.status_seconds)
	if defs.get("player_status", "") != "":
		for player in manager.targets():
			if reaches(player.get_body_aabb(), Combat.chest(player)):
				manager.status_player(player, defs.player_status, defs.player_seconds)
	if defs.has("clears"):
		for other: Cloud in manager.clouds.values():
			if other != self and other.type in defs.clears and not other.is_queued_for_deletion() 					and other.global_position.distance_to(global_position) < radius + other.radius * 0.5:
				manager.end_cloud(other.id)
	if defs.get("douses", false) and not defs.get("instant", false):
		Fire.douse_at(global_position, radius)


## Host: whether the cloud's effect reaches a body (its world box, and the point sight aims at).
## The effect is a squat column, not a sphere, so it never reaches the floor above or below: the
## box must come within radius across, its feet must be between REACH_BELOW under the center and
## REACH_ABOVE over it, and the center must see `aim` (Combat.can_see: walls and slabs block it).
func reaches(box: AABB, aim: Vector3) -> bool:
	var center := global_position
	var feet := box.position.y
	if feet < center.y - REACH_BELOW or feet > center.y + REACH_ABOVE:
		return false
	var closest := center.clamp(box.position, box.end)
	if Vector2(closest.x - center.x, closest.z - center.z).length() > radius:
		return false
	return Combat.can_see(manager.world if manager else null, center, aim)


## Host, fire: sets everything flammable (Fire) in a sphere alight, the sphere growing to the full
## radius over the first few seconds so the burn spreads instead of popping all at once. The pool
## engulfs what it touches, inside and out; the fire it starts carries on after the pool is gone.
func _ignite() -> void:
	_burned_radius = minf(radius, _burned_radius + radius * BURN_STEP / minf(seconds * 0.6, 4.0))
	Fire.ignite_at(global_position, _burned_radius, Fire.MAX_IGNITE, false)


# --- Looks (every peer) --------------------------------------------------------------------------
# A stain of opaque 0.1 m tiles on the floor under the center, grown out in STAIN_STEPS and shrunk
# back at the end, and opaque cubes rising off it in a motion per type:
#   fire    rise fast, flickering white / orange / red, and vanish
#   poison  drift up slowly, the swarm swaying from side to side
#   spore   rise and spread outward in a slow spiral, a few big truly translucent fog cubes among them
#   freeze  float up slowly and hang (the looks outlive the instant cloud by LINGER)
#   rage    jitter in place and pulse red
# Nothing is dithered.

## The stain's size steps (fractions of the radius), one every STAIN_STEP seconds.
const STAIN_STEPS := [0.4, 0.7, 1.0]
const STAIN_STEP := 0.15
## The stain sits this far over the floor, so it never fights the floor's faces.
const STAIN_LIFT := 0.01
## Instant clouds (freeze): their stain and cubes stay this long after the cloud itself is gone.
const LINGER := 1.6
## Lights: only the LIGHTS clouds nearest the camera glow (each light is a forward pass on every
## chunk it touches), picked every LIGHT_REFRESH seconds. Spore and foam clouds never do (UNLIT).
const LIGHTS := 3
const LIGHT_REFRESH := 0.25
const UNLIT := ["spore", "foam"]

## Every cloud with a light, and when (msec) the nearest were last picked (_pick_lights).
static var _lit_clouds: Array = []
static var _lights_msec := -1000000


func _build() -> void:
	var defs := settings(type)
	var color: Color = defs.get("color", Color.WHITE)
	var instant: bool = defs.get("instant", false)
	var floor_offset := _find_floor() - global_position.y

	_stain_material = VoxelFx.material(1.0, false, _stain_color())
	_stain = MeshInstance3D.new()
	_stain.name = "Stain"
	_stain.material_override = _stain_material
	_stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stain.position = Vector3(0.0, floor_offset + STAIN_LIFT, 0.0)
	_stain.visible = false
	add_child(_stain)
	_set_stain_step(0)

	if not type in UNLIT:
		_light = OmniLight3D.new()
		_light.light_color = color
		_light.light_energy = 0.0
		_light.omni_range = radius * 2.0
		_light.shadow_enabled = false
		_light.position = Vector3(0.0, floor_offset + 0.6, 0.0)
		_light.visible = false
		add_child(_light)
		_lit_clouds.append(self)
		_lights_msec = -1000000 # Pick again now that there's a new one.

	_particles = _rising_cubes(color, instant)
	_particles.name = "Particles"
	_particles.position = Vector3(0.0, floor_offset + 0.08, 0.0)
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_particles.emission_ring_axis = Vector3.UP
	_particles.emission_ring_height = 0.1
	_particles.emission_ring_radius = radius * 0.85
	_particles.emission_ring_inner_radius = 0.0
	_particles.direction = Vector3.UP
	add_child(_particles)
	_particles.emitting = true

	if type == "spore":
		_fog = VoxelFx.alpha_particles(1.0, [Color(color, 0.22), Color(color.lightened(0.1), 0.3), Color(color, 0.22)], 0.7)
		_fog.name = "Fog"
		_fog.position = _particles.position + Vector3(0.0, 0.4, 0.0)
		_fog.amount = 6 if OS.has_feature("web") else 12
		_fog.lifetime = 4.0
		_fog.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		_fog.emission_ring_axis = Vector3.UP
		_fog.emission_ring_height = 0.6
		_fog.emission_ring_radius = radius * 0.7
		_fog.emission_ring_inner_radius = 0.0
		_fog.direction = Vector3.UP
		_fog.spread = 30.0
		_fog.initial_velocity_min = 0.05
		_fog.initial_velocity_max = 0.2
		_fog.gravity = Vector3(0.0, 0.05, 0.0)
		_fog.tangential_accel_min = 0.1
		_fog.tangential_accel_max = 0.2
		add_child(_fog)
		_fog.emitting = true


## The rising cubes of this type (not yet placed or emitting).
func _rising_cubes(color: Color, instant: bool) -> CPUParticles3D:
	var defs := settings(type)
	var p: CPUParticles3D
	match type:
		"fire":
			# Hot cubes flickering through white, orange and red as they shoot up, shrinking out.
			p = VoxelFx.particles(0.1, [Color(1.0, 0.95, 0.7), Color(1.0, 0.6, 0.12), Color(1.0, 0.95, 0.7),
					Color(0.9, 0.25, 0.06), Color(1.0, 0.6, 0.12), Color(0.8, 0.18, 0.05)], 0.55)
			p.lifetime = 0.7
			p.spread = 6.0
			p.initial_velocity_min = 1.8
			p.initial_velocity_max = 3.2
			p.gravity = Vector3(0.0, 1.5, 0.0)
			p.damping_min = 0.5
			p.damping_max = 1.0
		"spore":
			# A dense swarm rising and spiralling outward (tangential and radial pull about the center).
			p = VoxelFx.particles(0.2, [color.lightened(0.15), color, color.darkened(0.12), color.darkened(0.25)], 0.6)
			p.lifetime = 3.2
			p.spread = 20.0
			p.initial_velocity_min = 0.25
			p.initial_velocity_max = 0.5
			p.gravity = Vector3(0.0, 0.12, 0.0)
			p.tangential_accel_min = 0.5
			p.tangential_accel_max = 0.9
			p.radial_accel_min = 0.2
			p.radial_accel_max = 0.4
			p.damping_min = 0.1
			p.damping_max = 0.2
		"freeze":
			# A puff of frost that floats up, slows to a stop and hangs, then shrinks away.
			p = VoxelFx.particles(0.1, [Color.WHITE, Color(0.8, 0.93, 1.0), color, color.darkened(0.15)], 0.75)
			p.lifetime = LINGER
			p.explosiveness = 0.85
			p.spread = 15.0
			p.initial_velocity_min = 0.8
			p.initial_velocity_max = 1.5
			p.gravity = Vector3.ZERO
			p.damping_min = 1.2
			p.damping_max = 2.0
		"foam":
			# A heavy white froth: big cubes thrown out low that sink back and settle.
			p = VoxelFx.particles(0.2, [Color.WHITE, color, color.darkened(0.08), color.darkened(0.15)], 0.7)
			p.lifetime = 2.2
			p.spread = 60.0
			p.initial_velocity_min = 0.6
			p.initial_velocity_max = 1.4
			p.gravity = Vector3(0.0, -0.6, 0.0)
			p.damping_min = 0.6
			p.damping_max = 1.0
		"rage":
			# Cubes that barely rise and jitter (_process shakes their pull), pulsing red.
			p = VoxelFx.particles(0.1, [Color(1.0, 0.35, 0.35), color, color.darkened(0.3)], 0.6)
			_cube_material = VoxelFx.material(0.1)
			p.material_override = _cube_material
			p.lifetime = 1.4
			p.spread = 10.0
			p.initial_velocity_min = 0.9
			p.initial_velocity_max = 1.5
			p.damping_min = 2.5
			p.damping_max = 3.5
		_:
			# Poison (and anything else): slow gas cubes drifting up, swayed by _process.
			p = VoxelFx.particles(0.2, [color.lightened(0.25), color, color.darkened(0.2), color.darkened(0.4)], 0.6)
			p.lifetime = 3.0
			p.spread = 10.0
			p.initial_velocity_min = 0.2
			p.initial_velocity_max = 0.45
			p.gravity = Vector3(0.0, 0.08, 0.0)
			p.damping_min = 0.2
			p.damping_max = 0.4
	p.amount = 24 if instant else int(defs.get("particles", 40))
	if OS.has_feature("web"):
		p.amount = maxi(p.amount / 2, 8) # The web build runs every particle on its one thread.
	p.one_shot = instant
	return p


func _exit_tree() -> void:
	_lit_clouds.erase(self)


## Every peer, every LIGHT_REFRESH: lights only the LIGHTS lit clouds nearest the camera.
static func _pick_lights(viewport: Viewport) -> void:
	var now := Time.get_ticks_msec()
	if now - _lights_msec < int(LIGHT_REFRESH * 1000.0):
		return
	_lights_msec = now
	var camera := viewport.get_camera_3d() if viewport else null
	var eye := camera.global_position if camera else Vector3.ZERO
	var ranked: Array = []
	for i in range(_lit_clouds.size() - 1, -1, -1):
		var cloud: Variant = _lit_clouds[i]
		if not is_instance_valid(cloud):
			_lit_clouds.remove_at(i)
			continue
		var lit_cloud: Cloud = cloud
		if lit_cloud._light:
			ranked.append([lit_cloud.global_position.distance_squared_to(eye), lit_cloud])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in ranked.size():
		(ranked[i][1] as Cloud)._light.visible = i < LIGHTS


## The floor under the center: the first solid voxel straight down (within the cloud's reach),
## else the center's own height.
func _find_floor() -> float:
	var world := manager.world if manager else null
	if world == null:
		return global_position.y
	for lift: float in [0.3, 0.05]:
		var hit: Dictionary = world.raycast(global_position + Vector3.UP * lift, Vector3.DOWN, REACH_BELOW + lift + 0.5)
		if hit.get("hit", false) and float(hit.distance) > 0.0:
			return (hit.position as Vector3).y
	return global_position.y


## The stain's color now: fire flickers, rage pulses, the rest hold.
func _stain_color() -> Color:
	var color: Color = settings(type).get("color", Color.WHITE)
	match type:
		"fire":
			return color.darkened(0.1) if int(age * 12.0) % 3 == 0 else color.darkened(0.4)
		"rage":
			return color.darkened(0.25 if int(age * 4.0) % 2 == 0 else 0.6)
		"freeze":
			return color.lightened(0.35)
		"spore":
			return color.darkened(0.1)
		"foam":
			return color
	return color.darkened(0.3)


## Shows stain size step (STAIN_STEPS index; -1 hides it).
func _set_stain_step(step: int) -> void:
	if step == _stain_step or _stain == null:
		return
	_stain_step = step
	_stain.visible = step >= 0
	if step >= 0:
		_stain.mesh = VoxelFx.stain(radius * float(STAIN_STEPS[step]), 0.1, id % 3)


func _process(_delta: float) -> void:
	if _stain == null or _handed_off:
		return
	var instant: bool = settings(type).get("instant", false)
	var count := STAIN_STEPS.size()
	var grown := int(age / STAIN_STEP) + 1
	var left := count if instant else int(maxf(seconds - age, 0.0) / STAIN_STEP) + 1
	_set_stain_step(mini(mini(grown, left), count) - 1)
	_stain_material.set_shader_parameter("tint", _stain_color())
	if _light:
		_pick_lights(get_viewport())
		if _light.visible:
			var fade := clampf((seconds - age) / minf(1.0, seconds), 0.0, 1.0)
			var flicker := 1.0 + (sin(age * 23.0) * 0.15 if type == "fire" else 0.0)
			_light.light_energy = 2.0 * fade * flicker
	match type:
		"poison":
			_particles.gravity = Vector3(sin(age * 1.6) * 0.9, 0.08, cos(age * 1.1) * 0.6)
		"rage":
			_particles.gravity = Vector3(randf_range(-12.0, 12.0), 0.6, randf_range(-12.0, 12.0))
			_cube_material.set_shader_parameter("tint", Color.WHITE if int(age * 4.0) % 2 == 0 else Color(0.55, 0.45, 0.45))
	if not instant and age > seconds - 0.8:
		_particles.emitting = false
		if _fog:
			_fog.emitting = false
	if instant and age >= seconds - 0.15:
		_hand_off()


## Instant clouds: the stain and the hanging cubes move to a node of their own that outlives the
## cloud by LINGER, shrinks the stain away in steps and frees itself.
func _hand_off() -> void:
	var parent := get_parent()
	if parent == null:
		return
	_handed_off = true
	var looks := Node3D.new()
	looks.name = "CloudLooks%d" % id
	parent.add_child(looks)
	looks.top_level = true
	looks.global_transform = global_transform
	var stain := _stain
	var stain_radius := radius
	var variant := id % 3
	_particles.reparent(looks)
	stain.reparent(looks)
	var tween := looks.create_tween()
	tween.tween_interval(maxf(LINGER - STAIN_STEP * STAIN_STEPS.size(), 0.1))
	for i in range(STAIN_STEPS.size() - 2, -2, -1):
		var step := i
		tween.tween_callback(func() -> void:
			stain.visible = step >= 0
			if step >= 0:
				stain.mesh = VoxelFx.stain(stain_radius * float(STAIN_STEPS[step]), 0.1, variant))
		tween.tween_interval(STAIN_STEP)
	tween.tween_callback(looks.queue_free)
	_stain = null
