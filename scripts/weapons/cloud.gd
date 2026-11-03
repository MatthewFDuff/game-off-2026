class_name Cloud
extends Node3D
## An area effect left by a flask or poison ammo: a sphere (center, radius) that lasts `seconds`.
## The host owns it: every TICK it gives its status to the enemies inside (Combat.sphere_hit,
## through Enemy.apply_status) and, for fire and poison, to the players inside (their own peer
## runs the damage, through EnemyManager.status_player). Effects only reach bodies in sight of the
## center and within its squat vertical extent (reaches), never through a floor, wall or ceiling.
## Every other peer gets a spawn message from
## EnemyManager and only draws it (a dithered volume of blocks, drifting cube particles and a tinted light: VoxelFx),
## freeing it on its own timer.
##
## Types (TYPES): fire (a burning pool that sets flammable voxels alight through Fire),
## poison (a cloud), rage (enemies turn on each other), freeze (an instant burst: frozen, once,
## and it puts out fire),
## spore (a thick grey-white cloud that blinds players inside, from spore shrooms).
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
var _sphere: MeshInstance3D
var _material: ShaderMaterial
var _light: OmniLight3D
var _particles: CPUParticles3D


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

func _build() -> void:
	var defs := settings(type)
	var color: Color = defs.get("color", Color.WHITE)
	var instant: bool = defs.get("instant", false)
	# The volume: a blocky ellipsoid of cubes (a flat pool for fire), its alpha a pixel dither.
	_material = VoxelFx.material(1.0, false, Color(color, 0.0))
	_material.set_shader_parameter("dither_px", 3.0)
	_sphere = MeshInstance3D.new()
	_sphere.name = "Sphere"
	_sphere.mesh = VoxelFx.volume(5, 0.35 if type == "fire" else 0.8)
	_sphere.material_override = _material
	_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sphere.scale = Vector3.ONE * radius * (0.3 if instant else 0.6)
	add_child(_sphere)

	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 0.0
	_light.omni_range = radius * 2.0
	_light.shadow_enabled = false
	add_child(_light)

	# Cube puffs on the effect grid (0.1 m flames, 0.2 m gas, spore puffs bigger), stepping
	# light -> color -> dark and thinning out by dither.
	var puff_size := 0.1 if type == "fire" else snappedf(float(defs.get("puff", 0.18)), 0.1)
	var steps := [Color(color.lightened(0.35), 0.9), Color(color, 0.75), Color(color.darkened(0.3), 0.45)]
	if type == "fire":
		steps = [Color(1.0, 0.95, 0.55), Color(1.0, 0.65, 0.15), color.darkened(0.2), Color(0.2, 0.15, 0.12, 0.5)]
	_particles = VoxelFx.particles(puff_size, steps, 0.6)
	_particles.name = "Particles"
	_particles.amount = 24 if instant else int(defs.get("particles", 40))
	_particles.lifetime = 0.5 if instant else 1.6
	_particles.explosiveness = 1.0 if instant else 0.0
	_particles.one_shot = instant
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_particles.emission_sphere_radius = radius * (0.2 if instant else 0.8)
	_particles.direction = Vector3.UP
	_particles.spread = 180.0 if instant else 25.0
	_particles.initial_velocity_min = radius * 2.0 if instant else 0.2
	_particles.initial_velocity_max = radius * 3.0 if instant else 0.8
	_particles.gravity = Vector3(0.0, 1.5 if type == "fire" else 0.1, 0.0)
	_particles.damping_min = 2.0
	_particles.damping_max = 4.0
	add_child(_particles)
	_particles.emitting = true


func _process(_delta: float) -> void:
	if _sphere == null:
		return
	var instant: bool = settings(type).get("instant", false)
	var t := clampf(age / maxf(seconds, 0.01), 0.0, 1.0)
	# Swell in over the first half second, hold, fade over the last second.
	var grow := 1.0 - pow(1.0 - clampf(age / (seconds if instant else 0.5), 0.0, 1.0), 3.0)
	var fade := clampf((seconds - age) / minf(1.0, seconds), 0.0, 1.0)
	# In whole steps, so the blocks pop out a layer at a time instead of scaling smoothly.
	grow = ceilf(grow * 4.0) / 4.0
	_sphere.scale = Vector3.ONE * radius * lerpf(0.3 if instant else 0.6, 1.0, grow)
	var flicker := 1.0 + (sin(age * 23.0) * 0.15 if type == "fire" else 0.0)
	var color: Color = settings(type).get("color", Color.WHITE)
	var alpha := (0.5 * (1.0 - t) if instant else float(settings(type).get("alpha", 0.28))) * fade
	_material.set_shader_parameter("tint", Color(color, ceilf(alpha * 8.0) / 8.0))
	_light.light_energy = 2.0 * fade * flicker
	if not instant and age > seconds - 0.8:
		_particles.emitting = false
