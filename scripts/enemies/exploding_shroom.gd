class_name ExplodingShroom
extends Enemy
## The exploding shroom: a swollen, spotted cap that runs straight at its target. Within FUSE_RANGE
## it stops, pulses white and orange and hisses (FUSE_TIME), then blows: it carves the terrain
## (WorldSync.carve_sphere, so assets in the blast break and the payroll counts them) and hurts
## every enemy and player within blast_reach. Killed before then, it still goes off, smaller
## (dud_*). The host decides; the fuse flash and the blast are sent to every peer.

## Meters from its target at which it lights its fuse.
const FUSE_RANGE := 2.0
## Seconds from lighting to the blast.
const FUSE_TIME := 0.8
const FUSE_COLORS := [Color(1.0, 1.0, 1.0, 0.75), Color(1.0, 0.45, 0.05, 0.75)]

@export_group("Blast")
## Full blast: carve radius, the hardest voxel it breaks, damage, and how far the damage reaches.
@export var blast_radius := 1.5
@export var blast_power := 5
@export var blast_damage := 40.0
@export var blast_reach := 3.0
## Killed early: the smaller blast.
@export var dud_radius := 0.8
@export var dud_damage := 15.0
@export var dud_reach := 1.6

## Host: seconds until the blast once lit, below zero while unlit.
var fuse := -1.0
## Host: it went off (so dying from its own blast doesn't go off again).
var exploded := false
## Every peer: seconds of fuse flashing left.
var _pulse := 0.0

static var _fuse_material: StandardMaterial3D


## The kind's stats. Set in _ready (before the base), since instancing the scene resets exports
## to the base defaults after _init.
func _configure() -> void:
	kind = "exploding"
	max_health = 20.0
	speed = 3.6
	damage = 10.0
	# It doesn't bite players: it blows up next to them.
	attack_range = 0.0
	attack_sound = ""
	death_sound = "blast"


func _ready() -> void:
	_configure()
	super()


func _physics_process(delta: float) -> void:
	super(delta)
	if not alive or manager == null or not manager.simulating or fuse < 0.0:
		return
	fuse -= delta # Burns down even when frozen.
	if fuse <= 0.0:
		explode(true)


func _think(delta: float) -> Dictionary:
	if fuse >= 0.0:
		return {direction = Vector3.ZERO, facing = Vector3.ZERO, breach = false}
	var target := manager.nearest_player(global_position)
	if target:
		var to_target := target.global_position - global_position
		if Vector2(to_target.x, to_target.z).length() < FUSE_RANGE and absf(to_target.y) < 1.6:
			_light_fuse()
			return {direction = Vector3.ZERO, facing = Vector3(to_target.x, 0.0, to_target.z), breach = false}
	return super(delta)


## Host: starts the fuse here and on every peer.
func _light_fuse() -> void:
	fuse = FUSE_TIME
	show_fuse()
	for peer_id in manager._peers():
		_fuse_lit.rpc_id(peer_id)


@rpc("authority", "reliable")
func _fuse_lit() -> void:
	show_fuse()


## Every peer: the fuse flash and hiss.
func show_fuse() -> void:
	_pulse = FUSE_TIME
	Sfx.play_at("fuse", get_center(), 0.0, 0.05)


## Host: blows up (full: the fuse ran out, else the smaller one from being killed). Carves, damages
## enemies (EnemyManager.damage) and players (on their own peers), shows it everywhere, and on a
## full blast kills itself.
func explode(full: bool) -> void:
	if exploded:
		return
	exploded = true
	var at := get_center()
	var radius := blast_radius if full else dud_radius
	var reach := blast_reach if full else dud_reach
	var amount := blast_damage if full else dud_damage
	if manager.world_sync:
		manager.world_sync.carve_sphere(at, radius, blast_power, Vector3.UP)
	for victim in Combat.sphere_hit(at, reach):
		if victim != self:
			manager.damage(victim.id, amount, at, "blast")
	for player in manager.targets():
		var box := player.get_body_aabb()
		if at.clamp(box.position, box.end).distance_to(at) <= reach:
			manager.damage_player(player, amount, at)
	show_blast(at, radius)
	for peer_id in manager._peers():
		_blasted.rpc_id(peer_id, at, radius)
	if full:
		manager.kill(id)


@rpc("authority", "reliable")
func _blasted(at: Vector3, radius: float) -> void:
	show_blast(at, radius)


## Every peer: a flash of light where it went off (the carve brings the debris, the death its
## sound and body burst).
func show_blast(at: Vector3, radius: float) -> void:
	_pulse = 0.0
	if manager == null:
		return
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 6.0
	light.omni_range = radius * 6.0
	manager.add_child(light)
	light.global_position = at
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.35)
	tween.tween_callback(light.queue_free)


## Killed (host): goes off small on the way out, unless this is its own blast.
func die() -> void:
	if alive and manager and manager.simulating and not exploded:
		explode(false)
	super()


func _process(delta: float) -> void:
	super(delta)
	if _pulse <= 0.0 or _mesh == null:
		return
	_pulse -= delta
	if _pulse <= 0.0:
		_mesh.material_overlay = tint_material()
		return
	if _fuse_material == null:
		_fuse_material = StandardMaterial3D.new()
		_fuse_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fuse_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Faster as it burns down; the material is shared, so every lit shroom pulses in step.
	var burnt := 1.0 - _pulse / FUSE_TIME
	var wave := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU * lerpf(4.0, 12.0, burnt))
	_fuse_material.albedo_color = (FUSE_COLORS[0] as Color).lerp(FUSE_COLORS[1], wave)
	_mesh.material_overlay = _fuse_material
	_visual.scale *= 1.0 + burnt * 0.18 + wave * 0.04
