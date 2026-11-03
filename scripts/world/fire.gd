class_name Fire
extends Node3D
## Fire that spreads through the voxels. Flammable materials (VoxelMaterials: burn, catch, ash) catch
## from burning neighbours, burn for a while as EMBER voxels, then leave air or CHAR. Air left behind
## drops loose pieces (VoxelWorld.detach_floating), so a burnt-through shelf or wall falls.
##
## The host owns it. Only burning voxels cost anything: each is visited once every TICK (spread
## over the physics frames), rolls its neighbours (heat rises: SPREAD), and its edits pile up and go
## out as one WorldSync.set_voxels every FLUSH, so a whole room on fire is a few RPCs a second.
## Every peer keeps the burning set from those batches (for flames, lights and crackle), and the
## host also burns what stands in it (enemies and players get "burning"), lets burning enemies
## set fire to what they walk on, boils lab samples into their clouds, and makes spore and poison
## clouds touching fire go up in a fireball. Water next to a burning voxel puts it out, and so
## does a freeze cloud (douse).
##
## Light one from any peer with Fire.ignite_at(at, radius); it goes through the host.

## The node group (Fire.find).
const GROUP := "fire"
## Host: seconds between visits to each burning voxel.
const TICK := 0.25
## Host: seconds between batches of edits.
const FLUSH := 0.1
## Most voxels burning at once; past this nothing new catches.
const MAX_BURNING := 2500
## Most voxels one ignite can light, and its largest radius (meters).
const MAX_IGNITE := 400
const MAX_IGNITE_RADIUS := 3.0
## Neighbours a burning voxel can light, and how much more (or less) likely than `catch`.
const SPREAD := [[Vector3i.UP, 1.0], [Vector3i.LEFT, 0.5], [Vector3i.RIGHT, 0.5], [Vector3i.FORWARD, 0.5],
		[Vector3i.BACK, 0.5], [Vector3i.DOWN, 0.25]]
const FACES := [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]
## Chance per second a sample next to fire boils away a voxel, and seconds between clouds of a type.
const BOIL := 0.6
const REACT_COOLDOWN := 2.0
## Voxels a side of the coarse cells fire is counted in (flames, heat checks).
const CELL := 10
## Host: seconds between burning what stands in fire.
const HEAT_CHECK := 0.5
## Status seconds from standing in fire.
const HEAT_SECONDS := 2.0
## Chance per heat check a burning enemy lights what it stands on.
const TRAIL_CHANCE := 0.4
## Clouds that go up when fire reaches them, and the fireball's damage.
const COMBUSTIBLE := ["spore", "poison"]
const FIREBALL_DAMAGE := 30.0
const FIREBALL_PLAYER_DAMAGE := 15.0
## Flame emitters and lights around the nearest burning cells, and how far they reach.
const FX_EMITTERS := 12
const FX_LIGHTS := 3
const FX_RANGE := 60.0
const FX_REFRESH := 0.3

@export var lab: Lab
@export var world: VoxelWorld
@export var world_sync: WorldSync
@export var enemies: EnemyManager

## Every peer: key -> Vector3i, every voxel on fire.
var burning := {}
## Every peer: coarse cell (CELL voxels a side) -> how many voxels in it are burning.
var cells := {}

## Host: key -> [seconds left, material it was, Vector3i].
var _fuel := {}
## Host: edits for the next batch, key -> [Vector3i, material].
var _pending := {}
## Host: keys left to visit this round.
var _round: Array = []
var _flush_timer := 0.0
var _heat_timer := 0.0
## Host: cloud type -> seconds until a sample can make another.
var _react_wait := {}
var _rng := RandomNumberGenerator.new()

# Per material id, from VoxelMaterials.
var _burn := PackedFloat32Array()
var _catch := PackedFloat32Array()
var _ash := PackedFloat32Array()
var _reacts := {}
var _flammable := PackedByteArray()

var _emitters: Array[CPUParticles3D] = []
var _lights: Array[OmniLight3D] = []
var _fx_timer := 0.0
var _crackle_timer := 0.0
var _flicker := 0.0


## Every peer: the level's Fire, or null.
static func find() -> Fire:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.get_first_node_in_group(GROUP) as Fire if tree else null


## Any peer: lights flammable voxels in a sphere (world space). exposed_only keeps to voxels with air
## on a face, so a solid block burns from the outside in.
static func ignite_at(at: Vector3, radius: float, max_count := 40, exposed_only := true) -> void:
	var fire := find()
	if fire:
		fire.ignite(at, radius, max_count, exposed_only)


## Any peer: puts out every burning voxel in a sphere (world space), leaving char.
static func douse_at(at: Vector3, radius: float) -> void:
	var fire := find()
	if fire:
		fire.douse(at, radius)


static func key_of(p: Vector3i) -> int:
	return p.x | (p.y << 12) | (p.z << 24)


static func is_ember(material: int) -> bool:
	return material == VoxelMaterials.EMBER or material == VoxelMaterials.EMBER_DEEP


func _ready() -> void:
	add_to_group(GROUP)
	_build_tables()
	world_sync.voxels_set.connect(_on_voxels_set)
	lab.mode_changed.connect(func(_mode: String) -> void: clear())
	lab.peer_entered.connect(_send_burning)
	_build_fx()


func _build_tables() -> void:
	_burn.resize(256)
	_catch.resize(256)
	_ash.resize(256)
	for id: int in VoxelMaterials.DEFS:
		var def: Dictionary = VoxelMaterials.DEFS[id]
		if def.has("burn"):
			_burn[id] = def.burn
			_catch[id] = def.get("catch", 0.5)
			_ash[id] = def.get("ash", 0.0)
			_flammable.append(id)
		if def.has("reacts"):
			_reacts[id] = def.reacts
	_flammable.sort()


## Every peer: forgets every fire (leaving play). The voxels are the level's business.
func clear() -> void:
	burning.clear()
	cells.clear()
	_fuel.clear()
	_pending.clear()
	_round.clear()
	_react_wait.clear()


## Host, in play.
func _simulating() -> bool:
	return enemies != null and enemies.simulating


# --- Lighting and putting out --------------------------------------------------------------------

## Any peer: see ignite_at.
func ignite(at: Vector3, radius: float, max_count := 40, exposed_only := true) -> void:
	if enemies == null or not enemies.active:
		return
	if multiplayer.is_server():
		_ignite(at, radius, max_count, exposed_only)
	else:
		_request_ignite.rpc_id(1, at, radius, max_count, exposed_only)


@rpc("any_peer", "reliable")
func _request_ignite(at: Vector3, radius: float, max_count: int, exposed_only: bool) -> void:
	if multiplayer.is_server():
		_ignite(at, radius, max_count, exposed_only)


func _ignite(at: Vector3, radius: float, max_count: int, exposed_only: bool) -> void:
	if not _simulating():
		return
	var found := world.find_in_sphere(at, minf(radius, MAX_IGNITE_RADIUS), _flammable, exposed_only, clampi(max_count, 0, MAX_IGNITE))
	for i in found.size() / 3:
		var p := Vector3i(found[i * 3], found[i * 3 + 1], found[i * 3 + 2])
		_light(p, world.get_voxel(p))


## Host: sets one voxel of material burning (if it isn't already, and there's room).
func _light(p: Vector3i, material: int) -> void:
	var key := key_of(p)
	if _fuel.has(key) or _pending.has(key) or burning.has(key) or _fuel.size() >= MAX_BURNING:
		return
	_fuel[key] = [_burn[material] * _rng.randf_range(0.7, 1.3), material, p]
	_pending[key] = [p, VoxelMaterials.EMBER if _rng.randf() < 0.6 else VoxelMaterials.EMBER_DEEP]


## Any peer: see douse_at.
func douse(at: Vector3, radius: float) -> void:
	if multiplayer.is_server():
		_douse(at, radius)
	else:
		_request_douse.rpc_id(1, at, radius)


@rpc("any_peer", "reliable")
func _request_douse(at: Vector3, radius: float) -> void:
	if multiplayer.is_server():
		_douse(at, minf(radius, MAX_IGNITE_RADIUS * 2.0))


func _douse(at: Vector3, radius: float) -> void:
	if not _simulating():
		return
	var center := world.world_to_voxel(at)
	var r := radius / world.voxel_size
	for key: int in _fuel.keys():
		var p: Vector3i = _fuel[key][2]
		if Vector3(p - center).length() <= r:
			_fuel.erase(key)
			_pending[key] = [p, VoxelMaterials.CHAR]


# --- Burning (host) ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _simulating():
		return
	for type: String in _react_wait.keys():
		_react_wait[type] -= delta
		if _react_wait[type] <= 0.0:
			_react_wait.erase(type)
	# Each burning voxel once per TICK, a share of them every frame.
	if _round.is_empty() and not _fuel.is_empty():
		_round = _fuel.keys()
	var visits := mini(_round.size(), ceili(_fuel.size() * delta / TICK))
	for i in visits:
		_visit(_round.pop_back())
	_flush_timer -= delta
	if _flush_timer <= 0.0:
		_flush_timer = FLUSH
		_flush()
	_heat_timer -= delta
	if _heat_timer <= 0.0:
		_heat_timer = HEAT_CHECK
		_heat()


func _visit(key: int) -> void:
	# Still waiting to land in the world: next round.
	if _pending.has(key) or not _fuel.has(key):
		return
	var fuel: Array = _fuel[key]
	var p: Vector3i = fuel[2]
	var here := world.get_voxel(p)
	if not is_ember(here):
		# Shot or blown away (or replaced) since it caught. The batch tells the peers.
		_fuel.erase(key)
		_pending[key] = [p, here]
		return
	fuel[0] -= TICK
	var doused := false
	if fuel[0] > 0.0:
		for spread: Array in SPREAD:
			var q: Vector3i = p + spread[0]
			var next := world.get_voxel(q)
			if next == VoxelMaterials.WATER:
				doused = true
			elif _catch[next] > 0.0:
				if _rng.randf() < _catch[next] * spread[1] * TICK and _exposed(q):
					_light(q, next)
			elif _reacts.has(next) and _rng.randf() < BOIL * TICK:
				_boil(q, _reacts[next])
	if fuel[0] <= 0.0 or doused:
		_fuel.erase(key)
		var left := VoxelMaterials.CHAR if doused or _rng.randf() < _ash[fuel[1]] else VoxelMaterials.AIR
		_pending[key] = [p, left]


## Air on at least one face (the inside of a solid block can't burn until it's opened up).
func _exposed(p: Vector3i) -> bool:
	for face: Vector3i in FACES:
		if world.get_voxel(p + face) == VoxelMaterials.AIR:
			return true
	return false


## Host: a sample voxel next to fire boils away, sometimes into its cloud.
func _boil(p: Vector3i, cloud_type: String) -> void:
	var key := key_of(p)
	if _pending.has(key):
		return
	_pending[key] = [p, VoxelMaterials.AIR]
	if not _react_wait.has(cloud_type):
		_react_wait[cloud_type] = REACT_COOLDOWN
		enemies.request_cloud(cloud_type, world.voxel_to_world(p))


func _flush() -> void:
	if _pending.is_empty():
		return
	var points := PackedInt32Array()
	var materials := PackedByteArray()
	points.resize(_pending.size() * 3)
	materials.resize(_pending.size())
	var i := 0
	for edit: Array in _pending.values():
		var p: Vector3i = edit[0]
		points[i * 3] = p.x
		points[i * 3 + 1] = p.y
		points[i * 3 + 2] = p.z
		materials[i] = edit[1]
		i += 1
	_pending.clear()
	world_sync.set_voxels(points, materials)


## Every peer: a batch landed; whatever it set to an ember is burning, anything else isn't.
func _on_voxels_set(points: PackedInt32Array, materials: PackedByteArray, _removed: Dictionary) -> void:
	for i in materials.size():
		var p := Vector3i(points[i * 3], points[i * 3 + 1], points[i * 3 + 2])
		var key := key_of(p)
		if is_ember(materials[i]):
			if not burning.has(key):
				burning[key] = p
				var cell := _cell_of(p)
				cells[cell] = cells.get(cell, 0) + 1
		elif burning.has(key):
			burning.erase(key)
			var cell := _cell_of(p)
			var left: int = cells.get(cell, 1) - 1
			if left <= 0:
				cells.erase(cell)
			else:
				cells[cell] = left


static func _cell_of(p: Vector3i) -> Vector3i:
	return Vector3i(floori(p.x / float(CELL)), floori(p.y / float(CELL)), floori(p.z / float(CELL)))


## Host: a peer joined mid-fire; it has the voxels from the snapshot, this gives it the flames.
func _send_burning(peer_id: int) -> void:
	if not multiplayer.is_server() or burning.is_empty():
		return
	var points := PackedInt32Array()
	var materials := PackedByteArray()
	for p: Vector3i in burning.values():
		points.append_array([p.x, p.y, p.z])
		materials.append(VoxelMaterials.EMBER)
	_burning_list.rpc_id(peer_id, points, materials)


@rpc("authority", "reliable")
func _burning_list(points: PackedInt32Array, materials: PackedByteArray) -> void:
	if points.size() == materials.size() * 3:
		_on_voxels_set(points, materials, {})


# --- Heat (host) ---------------------------------------------------------------------------------

func _heat() -> void:
	for enemy: Enemy in enemies.enemies.values():
		if not enemy.alive:
			continue
		if in_fire(enemy.global_position):
			enemies.request_status(enemy.id, "burning", HEAT_SECONDS)
		elif enemy.has_status("burning") and _rng.randf() < TRAIL_CHANCE:
			_ignite(enemy.global_position + Vector3.UP * 0.05, 0.3, 3, true)
	for player in enemies.targets():
		if in_fire(player.global_position):
			enemies.status_player(player, "burning", HEAT_SECONDS)
	_combust_clouds()


## Every peer: whether someone standing at feet is in (or right against) fire.
func in_fire(feet: Vector3) -> bool:
	if burning.is_empty():
		return false
	var v := world.world_to_voxel(feet)
	var cell := _cell_of(v)
	var near := false
	for dy in [-1, 0]:
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if cells.has(cell + Vector3i(dx, dy, dz)):
					near = true
	if not near:
		return false
	# Around the feet and up the legs, about 0.3 m out.
	for y in [-1, 2, 5, 8]:
		for z in [-3, 0, 3]:
			for x in [-3, 0, 3]:
				if is_ember(world.get_voxel(v + Vector3i(x, y, z))):
					return true
	return false


## Every peer: whether any fire is within radius (meters) of a point.
func near_fire(at: Vector3, radius: float) -> bool:
	var reach := radius + CELL * world.voxel_size
	for cell: Vector3i in cells:
		if cell_center(cell).distance_to(at) <= reach:
			return true
	return false


## World position of a coarse cell's middle.
func cell_center(cell: Vector3i) -> Vector3:
	return world.voxel_to_world(cell * CELL) + Vector3.ONE * (CELL - 1) * 0.5 * world.voxel_size


## Host: spore and poison clouds touching fire (or a fire cloud) go up in a fireball.
func _combust_clouds() -> void:
	var fire_clouds: Array[Cloud] = []
	for cloud: Cloud in enemies.clouds.values():
		if cloud.type == "fire":
			fire_clouds.append(cloud)
	for cloud: Cloud in enemies.clouds.values():
		if not cloud.type in COMBUSTIBLE or cloud.is_queued_for_deletion():
			continue
		var lit := near_fire(cloud.global_position, cloud.radius)
		for flame in fire_clouds:
			lit = lit or flame.global_position.distance_to(cloud.global_position) < flame.radius + cloud.radius
		if lit:
			_fireball(cloud)


func _fireball(cloud: Cloud) -> void:
	var at := cloud.global_position
	var radius := cloud.radius
	enemies.end_cloud(cloud.id)
	enemies.request_cloud("fire", at, radius * 0.8, 3.0)
	for victim in Combat.sphere_hit(at, radius):
		enemies.damage(victim.id, FIREBALL_DAMAGE, at, "blast")
	for player in enemies.targets():
		var box := player.get_body_aabb()
		if at.clamp(box.position, box.end).distance_to(at) <= radius:
			enemies.damage_player(player, FIREBALL_PLAYER_DAMAGE, at)
	_ignite(at, radius, MAX_IGNITE, true)
	_whoosh(at, radius)
	for peer_id in enemies._peers():
		_whoosh.rpc_id(peer_id, at, radius)


@rpc("authority", "reliable")
func _whoosh(at: Vector3, radius: float) -> void:
	Sfx.play_at("blast", at, 0.0, 0.1, 0.7)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.55, 0.2)
	flash.light_energy = 6.0
	flash.omni_range = radius * 3.0
	add_child(flash)
	flash.global_position = at
	var tween := flash.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.6)
	tween.tween_callback(flash.queue_free)
	VoxelFx.blast(self, at, radius, Color(1.0, 0.45, 0.12))


# --- Looks (every peer) --------------------------------------------------------------------------

func _build_fx() -> void:
	# Voxel flames: 0.1 m cubes (one terrain voxel) rising in grid steps, white-hot -> orange ->
	# red -> a dithered wisp of smoke, shrinking out a step at a time.
	var steps := [Color(1.0, 0.92, 0.5), Color(1.0, 0.6, 0.12), Color(0.85, 0.25, 0.06), Color(0.15, 0.12, 0.1, 0.5)]
	for i in FX_EMITTERS:
		var flames := VoxelFx.particles(0.1, steps, 0.5)
		flames.name = "Flames%d" % i
		flames.top_level = true
		flames.amount = 18
		flames.lifetime = 0.9
		flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		flames.emission_box_extents = Vector3.ONE * CELL * 0.5 * world.voxel_size
		flames.direction = Vector3.UP
		flames.spread = 15.0
		flames.gravity = Vector3(0.0, 2.0, 0.0)
		flames.initial_velocity_min = 0.3
		flames.initial_velocity_max = 0.9
		add_child(flames)
		_emitters.append(flames)
	for i in FX_LIGHTS:
		var light := OmniLight3D.new()
		light.name = "Glow%d" % i
		light.top_level = true
		light.visible = false
		light.light_color = Color(1.0, 0.5, 0.15)
		light.omni_range = 5.0
		light.shadow_enabled = false
		add_child(light)
		_lights.append(light)


func _process(delta: float) -> void:
	_flicker += delta
	for i in _lights.size():
		if _lights[i].visible:
			_lights[i].light_energy = 1.6 + sin(_flicker * 17.0 + i * 2.1) * 0.3 + sin(_flicker * 7.3 + i) * 0.25
	_fx_timer -= delta
	if _fx_timer > 0.0:
		return
	_fx_timer = FX_REFRESH
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera else Vector3.ZERO
	var nearest: Array = []
	for cell: Vector3i in cells:
		var at := cell_center(cell)
		var distance := at.distance_to(eye)
		if distance <= FX_RANGE:
			nearest.append([distance, at])
	nearest.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in _emitters.size():
		var flames := _emitters[i]
		if i < nearest.size():
			flames.global_position = nearest[i][1]
			flames.emitting = true
		else:
			flames.emitting = false
	for i in _lights.size():
		_lights[i].visible = i < nearest.size()
		if _lights[i].visible:
			_lights[i].global_position = nearest[i][1]
	_crackle_timer -= FX_REFRESH
	if not nearest.is_empty() and _crackle_timer <= 0.0:
		_crackle_timer = _rng.randf_range(0.8, 1.6)
		Sfx.play_at("flame", nearest[0][1], -14.0, 0.25, 0.7)
