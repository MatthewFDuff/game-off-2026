class_name EnemyManager
extends Node3D
## Owns the level's enemies (its children, named "E<id>" so RPC paths match on every peer). The
## host spawns, simulates and kills them and tells the peers in the level; peers only draw them.
## Runs while the level is in play mode; switching back to edit clears every enemy on every peer.
##
## Shots are shooter-authoritative: the shooting peer finds the hit (Combat.ray_hit) and calls
## request_hit, the host applies it (crit multiplier, knockback) and broadcasts the hit flash and,
## if it died, the death. Enemy attacks damage players on the player's own peer, like Lab._kill.
##
## The host also keeps the world's flow field pointed at every living player (a multi-target
## field, so each enemy heads for its nearest player; refreshed all through play, since the
## director wakes spawners by it), and streams positions at STATE_RATE.
##
## Status effects (Enemy.apply_status) run on the host; each change of an enemy's active set goes
## to the peers (_statuses) so every peer tints it. Hits blast chunks off enemies (Enemy.chip): the
## host carves them, batches them to the peers (send_chunks, _chunks) who carve the same and burst
## the debris, and kills an enemy whose remaining share drops below Enemy.CARVE_DEATH_SHARE.
## Clouds (Cloud) are children here too ("C<id>"): the host owns them and applies their effects,
## the peers get a spawn message and draw them.

signal enemy_spawned(enemy: Enemy)
## Host: a hit landed. amount includes the crit multiplier; zone is the hit zone name.
signal enemy_damaged(enemy: Enemy, amount: float, zone: String)
## Host: an enemy was killed (not despawned), just before it bursts.
signal enemy_died(enemy: Enemy)
## This peer: one of its own shots hit an enemy (the HUD's hit marker).
signal local_hit(enemy: Enemy, point: Vector3)
## Every peer: a cloud appeared (on the host, with its effects; elsewhere, its looks).
signal cloud_spawned(cloud: Cloud)
## Host: the flow field was just refreshed (refresh_flow); HordeDirector re-reads its walk distances.
signal flow_refreshed

## The manager's node group (Cloud.spawn finds it through this).
const GROUP := "enemy_manager"
const CLOUD_SCENE := preload("res://scenes/cloud.tscn")
## Most clouds at once; the oldest goes first.
const MAX_CLOUDS := 24

## kind -> scene. Spawner markers name kinds from here.
const KINDS := {basic = "res://scenes/enemies/basic.tscn",
		fast = "res://scenes/enemies/fast.tscn", exploding = "res://scenes/enemies/exploding.tscn",
		alarm = "res://scenes/enemies/alarm.tscn", giant = "res://scenes/enemies/giant.tscn",
		ranged = "res://scenes/enemies/ranged.tscn",
		mommy = "res://scenes/enemies/mommy.tscn", spore = "res://scenes/enemies/spore.tscn",
		ceiling_cloud = "res://scenes/enemies/ceiling_cloud.tscn", tentacle = "res://scenes/enemies/tentacle.tscn"}
## Most enemies alive at once, whatever the spawners ask for.
const MAX_ENEMIES := 80
## Position updates per second to peers.
const STATE_RATE := 10.0
## Flow field refreshes per second.
const FLOW_RATE := 5.0
## Meters of walking the flow field covers around the players. Not lower: HordeDirector picks the
## finale's spawners by walking distance up to finale_range_factor (2) x wake_range (40 m) = 80 m,
## and ranks horde spawners by it; a shorter field would leave those unreached (INF).
const FLOW_RANGE := 80.0
## Most enemies per position packet (_states), so one stays under a typical 1400-byte MTU (20
## bytes an enemy) and losing one fragment never drops the whole roster's update.
const STATES_PER_PACKET := 50
## Hit flash and sound (_hit_fx): at most one per enemy per this many seconds (the flamethrower
## and multi-pellet shots land many hits a second).
const HIT_FX_INTERVAL := 0.1
## Separation's neighbour cells.
const _AROUND := [-1, 0, 1]
## A shared empty list for crowd cells with nobody in them (never modified).
const _NOBODY := []
## Requests from peers are clamped to this so a bad packet can't do anything silly.
const MAX_DAMAGE := 1000.0
## Knockback speed (m/s) by damage kind.
const KNOCKBACK := {rifle = 1.2, shotgun = 2.5, flame = 0.0, blast = 7.0, ricochet = 1.5, homing = 2.0,
		poison = 0.5, melee = 6.0, flask = 0.5, enemy = 2.0, status = 0.0}
## Longest status (seconds) a peer can ask for.
const MAX_STATUS := 30.0
## Seconds a sunk enemy (sink) takes to go down into the floor.
const SINK_TIME := 0.5
## Separation: enemies closer than CROWD_RANGE meters push apart; the crowd is bucketed in columns
## of CROWD_CELL meters (at least CROWD_RANGE, so the 3 x 3 cells around one hold every neighbour).
const CROWD_RANGE := 0.9
const CROWD_CELL := 1.0

@export var lab: Lab
@export var world: VoxelWorld
@export var world_sync: WorldSync
@export var debris: VoxelDebris

## In play mode.
var active := false
## Host in play mode: enemies move and attack here.
var simulating := false
## id -> Enemy
var enemies := {}
## id -> Cloud
var clouds := {}
## Host: floor spans the flow field reached at its last refresh (0: the field is empty, e.g. no
## living player stands on a floor).
var flow_reached := 0
## Host: lure points (LevelPlay: a radio playing, a squeaked duck): key -> {at: Vector3, radius,
## until: msec it ends, -1 = until cleared}. Enemies within its radius that can't see a player go to
## it (Enemy._think).
var lures := {}

var _next_id := 1
var _next_cloud := 1
var _flow_timer := 0.0
var _state_timer := 0.0
var _scenes := {}
## Host, during a peer's hit (request_hit): that peer's id, else 0 (Enemy._on_damaged).
var _hit_peer := 0
## Host: separation's buckets, Vector2i column -> [Enemy], and the physics frame they were built.
var _crowd_cells := {}
var _crowd_frame := -1
## Host: msec of the last flow field refresh (Enemy.flow_here drops older lookups).
var flow_msec := 0
## Host: counts every time an enemy leaves `enemies` (killed, despawned, sunk, cleared), so the
## director only re-checks its spawners' alive lists when something went.
var removed_version := 0
## targets() as of the frame _targets_frame (Engine.get_process_frames, see frame_targets).
var _targets: Array[Player] = []
var _targets_frame := -1
## Damage kind -> the AmmoType whose status a batched hit of that kind gives (request_hits).
var _kind_status := {}
## kind -> its collision box (Enemy.body_size), read once from an unspawned instance (body_size_of).
static var _body_sizes := {}


func _ready() -> void:
	add_to_group(GROUP)
	lab.mode_changed.connect(func(mode: String) -> void:
		if mode == "play":
			start()
		else:
			stop())
	lab.peer_entered.connect(_send_roster)
	var watch := get_node_or_null("/root/VoxWatch")
	if watch:
		watch.changed.connect(_on_vox_changed)


func start() -> void:
	active = true
	simulating = multiplayer.is_server()
	_flow_timer = 0.0


## Leaves play: every enemy goes, on this peer (each peer stops on its own mode change).
func stop() -> void:
	active = false
	simulating = false
	clear()


## Removes every enemy and cloud on this peer, no effects.
func clear() -> void:
	for enemy: Enemy in enemies.values():
		enemy.alive = false
		enemy.remove_from_group(Enemy.GROUP)
		enemy.queue_free()
	enemies.clear()
	removed_version += 1
	for cloud: Cloud in clouds.values():
		cloud.queue_free()
	clouds.clear()
	lures.clear()
	_crowd_cells.clear()
	_crowd_frame = -1
	_targets.clear()
	_targets_frame = -1


func get_enemy(id: int) -> Enemy:
	return enemies.get(id)


## Living enemies, optionally only of one kind.
func alive_count(of_kind := "") -> int:
	var n := 0
	for enemy: Enemy in enemies.values():
		if enemy.alive and (of_kind == "" or enemy.kind == of_kind):
			n += 1
	return n


# --- Spawning (host) -----------------------------------------------------------------------------

## Host: spawns an enemy of a kind (see KINDS) standing at feet. Returns it, or null when not in
## play or at MAX_ENEMIES. emerge (spawners): 1 rises out of the floor, -1 drops out of the ceiling
## (Enemy.begin_emerge), on every peer; 0 just appears.
func spawn(kind: String, feet: Vector3, yaw := randf() * TAU, emerge := 0) -> Enemy:
	if not simulating or enemies.size() >= MAX_ENEMIES:
		return null
	if not KINDS.has(kind):
		push_warning("unknown enemy kind '%s', spawning basic" % kind)
		kind = "basic"
	var id := _next_id
	_next_id += 1
	var enemy := _create(id, kind, feet, yaw, emerge)
	for peer_id in _peers():
		_spawned.rpc_id(peer_id, id, kind, feet, yaw, emerge)
	enemy_spawned.emit(enemy)
	return enemy


## A kind's collision box (Enemy.body_size: width, height, depth) without spawning one: its scene
## is instanced once (outside the tree, its _configure run as _ready would) and the size cached.
## Unknown kinds read as basic. HordeDirector sizes its spawn clearance from this.
static func body_size_of(kind: String) -> Vector3:
	if not KINDS.has(kind):
		kind = "basic"
	if not _body_sizes.has(kind):
		var enemy: Enemy = (load(KINDS[kind]) as PackedScene).instantiate()
		if enemy.has_method("_configure"):
			enemy.call("_configure")
		_body_sizes[kind] = enemy.body_size
		enemy.free()
	return _body_sizes[kind]


## Host: removes an enemy everywhere without a death (fell out of the level, cleanup).
func despawn(id: int) -> void:
	if not multiplayer.is_server() or not enemies.has(id):
		return
	_remove(id)
	for peer_id in _peers():
		_removed.rpc_id(peer_id, id)


## Host: removes an enemy everywhere without a death, sinking it into the floor over SINK_TIME (a
## spawner turned off, see HordeDirector.set_spawner_active). No drops, no death sound, and it
## can't be hit or attack on the way down.
func sink(id: int) -> void:
	if not multiplayer.is_server() or not enemies.has(id):
		return
	_sink(id)
	for peer_id in _peers():
		_sunk.rpc_id(peer_id, id)


## Host: kills an enemy everywhere: it pops into debris.
func kill(id: int) -> void:
	var enemy: Enemy = enemies.get(id)
	if not multiplayer.is_server() or enemy == null or not enemy.alive:
		return
	if enemy.has_pending_chunks():
		send_chunks(enemy) # So every peer's death burst is the same remains.
	enemy_died.emit(enemy)
	enemies.erase(id)
	removed_version += 1
	enemy.die()
	for peer_id in _peers():
		_died.rpc_id(peer_id, id)


func _create(id: int, kind: String, feet: Vector3, yaw: float, emerge := 0) -> Enemy:
	if not _scenes.has(kind):
		_scenes[kind] = load(KINDS[kind])
	var enemy: Enemy = _scenes[kind].instantiate()
	enemy.name = "E%d" % id
	enemy.id = id
	enemy.variant = id
	enemy.manager = self
	enemy.world = world
	enemy.position = to_local(feet)
	enemy.rotation.y = yaw
	add_child(enemy)
	enemies[id] = enemy
	enemy.begin_emerge(emerge)
	return enemy


## Every peer: takes an enemy out of play now and lowers it out of sight, then frees it.
func _sink(id: int) -> void:
	var enemy: Enemy = enemies.get(id)
	if enemy == null:
		return
	enemies.erase(id)
	removed_version += 1
	enemy.alive = false
	enemy.remove_from_group(Enemy.GROUP)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	var depth := maxf(enemy.world_bounds().size.y, 0.5) + 0.1
	var tween := enemy.create_tween()
	tween.tween_property(enemy, "global_position", enemy.global_position - Vector3.UP * depth, SINK_TIME)
	tween.tween_callback(enemy.queue_free)


func _remove(id: int) -> void:
	var enemy: Enemy = enemies.get(id)
	if enemy:
		enemies.erase(id)
		removed_version += 1
		enemy.alive = false
		enemy.remove_from_group(Enemy.GROUP)
		enemy.queue_free()


## Host peers that get enemy messages: everyone in the level but the host.
func _peers() -> Array[int]:
	var out: Array[int] = []
	if multiplayer.is_server():
		for peer_id in lab.peers_in_level:
			if peer_id != 1:
				out.append(peer_id)
	return out


## Host: a peer finished joining; tell it about every enemy already here.
func _send_roster(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	for enemy: Enemy in enemies.values():
		if enemy.alive:
			_spawned.rpc_id(peer_id, enemy.id, enemy.kind, enemy.global_position, enemy.rotation.y, 0)
			if not enemy.carve_points.is_empty():
				_chunks.rpc_id(peer_id, enemy.id, enemy.carve_points, enemy.carve_radii, false)
			if not enemy.shown_statuses.is_empty():
				_statuses.rpc_id(peer_id, enemy.id, enemy.shown_statuses)
	for cloud: Cloud in clouds.values():
		if cloud.age < cloud.seconds:
			_cloud_spawned.rpc_id(peer_id, cloud.id, cloud.type, cloud.global_position, cloud.radius, cloud.seconds - cloud.age)


@rpc("authority", "reliable")
func _spawned(id: int, kind: String, feet: Vector3, yaw: float, emerge: int) -> void:
	if not enemies.has(id) and KINDS.has(kind):
		_create(id, kind, feet, yaw, emerge)


@rpc("authority", "reliable")
func _removed(id: int) -> void:
	_remove(id)


@rpc("authority", "reliable")
func _sunk(id: int) -> void:
	_sink(id)


@rpc("authority", "reliable")
func _died(id: int) -> void:
	var enemy: Enemy = enemies.get(id)
	if enemy:
		enemies.erase(id)
		removed_version += 1
		enemy.die()


# --- Damage --------------------------------------------------------------------------------------

## Any peer: this peer's attack hit enemy id at point (world space). kind is "rifle", "blast",
## "melee" and so on, for knockback. The host applies it.
func request_hit(id: int, damage: float, point: Vector3, kind := "rifle") -> void:
	var enemy: Enemy = enemies.get(id)
	if enemy and enemy.alive:
		local_hit.emit(enemy, point)
	if multiplayer.is_server():
		_apply_hit(id, damage, point, kind)
	else:
		_request_hit.rpc_id(1, id, damage, point, kind)


@rpc("any_peer", "reliable")
func _request_hit(id: int, damage: float, point: Vector3, kind: String) -> void:
	if _from_level() and is_finite(damage) and point.is_finite():
		_apply_hit(id, damage, point, kind)


func _apply_hit(id: int, damage: float, point: Vector3, kind: String) -> void:
	var enemy: Enemy = enemies.get(id)
	if enemy == null or not enemy.alive or not simulating or enemy.emerging > 0.0:
		return
	var zone := enemy.zone_at(point)
	var crit: float = enemy.hit_zones[zone].get("crit", 1.0) if enemy.hit_zones.has(zone) else 1.0
	var sender := multiplayer.get_remote_sender_id()
	_hit_peer = sender if sender != 0 else multiplayer.get_unique_id()
	_damage(enemy, clampf(damage, 0.0, MAX_DAMAGE) * crit, point, kind, zone, true)
	_hit_peer = 0


## Any peer: one attack hit several enemies at once (a flamethrower cone check): ids[i] takes
## damage at points[i]. One message to the host for the lot. The host applies each as request_hit
## does, then the status a hit of this kind gives (an AmmoType of that kind with a status: the
## flame's burning), so no second message is needed.
func request_hits(ids: PackedInt32Array, damage: float, points: PackedVector3Array, kind := "rifle") -> void:
	if ids.is_empty() or points.size() != ids.size():
		return
	for i in ids.size():
		var enemy: Enemy = enemies.get(ids[i])
		if enemy and enemy.alive:
			local_hit.emit(enemy, points[i])
	if multiplayer.is_server():
		_apply_hits(ids, damage, points, kind)
	else:
		_request_hits.rpc_id(1, ids, damage, points, kind)


@rpc("any_peer", "reliable")
func _request_hits(ids: PackedInt32Array, damage: float, points: PackedVector3Array, kind: String) -> void:
	if _from_level() and is_finite(damage) and points.size() == ids.size() and ids.size() <= MAX_ENEMIES:
		for point in points:
			if not point.is_finite():
				return
		_apply_hits(ids, damage, points, kind)


func _apply_hits(ids: PackedInt32Array, damage: float, points: PackedVector3Array, kind: String) -> void:
	var status := _status_of_kind(kind)
	for i in ids.size():
		_apply_hit(ids[i], damage, points[i], kind)
		if status:
			_apply_status(ids[i], status.status, status.status_seconds)


## The AmmoType (with a status) whose hits are of damage kind, or null. Statuses come from the
## host's own table, not the request.
func _status_of_kind(kind: String) -> AmmoType:
	if not _kind_status.has(kind):
		var found: AmmoType = null
		for type in AmmoType.all():
			if type.kind == kind and type.status != "":
				found = type
				break
		_kind_status[kind] = found
	return _kind_status[kind]


## Host: damages enemy id directly (statuses, enemies fighting each other). from is where it came
## from, for knockback by kind (KNOCKBACK); fx is the hit flash and sound on every peer. Frozen
## enemies take more (Enemy.damage_taken), as they do from request_hit.
func damage(id: int, amount: float, from: Vector3, kind := "enemy", fx := true) -> void:
	var enemy: Enemy = enemies.get(id)
	if enemy == null or not enemy.alive or not simulating or enemy.emerging > 0.0:
		return
	_damage(enemy, clampf(amount, 0.0, MAX_DAMAGE), from, kind, "body", fx)


func _damage(enemy: Enemy, amount: float, point: Vector3, kind: String, zone: String, fx: bool) -> void:
	amount *= enemy.damage_taken()
	var away := enemy.get_center() - point
	away.y = 0.0
	var strength := float(KNOCKBACK.get(kind, 1.0))
	var push := away.normalized() * strength + Vector3.UP * strength * 0.3
	enemy.apply_hit(amount, push)
	if kind != "status": # Burning and poison ticks don't blast chunks off.
		enemy.chip(point, amount)
	enemy._on_damaged(amount, kind, _hit_peer)
	enemy_damaged.emit(enemy, amount, zone)
	var now := Time.get_ticks_msec()
	if fx and now - enemy.last_hit_fx_msec >= int(HIT_FX_INTERVAL * 1000.0):
		enemy.last_hit_fx_msec = now
		_hit_fx(enemy.id, point)
		for peer_id in _peers():
			_hit_fx.rpc_id(peer_id, enemy.id, point)
	if enemy.health <= 0.0 or enemy.remaining_share() < Enemy.CARVE_DEATH_SHARE:
		kill(enemy.id)


## Host: sends an enemy's queued chunks (Enemy.take_pending_chunks) to every peer in one reliable
## message, and bursts what they removed here (each peer bursts its own on arrival). Enemy._process
## calls it at most every Enemy.CHUNK_INTERVAL, kill right before a death.
func send_chunks(enemy: Enemy) -> void:
	var pending := enemy.take_pending_chunks()
	var points: PackedVector3Array = pending[0]
	if points.is_empty():
		return
	for peer_id in _peers():
		_chunks.rpc_id(peer_id, enemy.id, points, pending[1], true)
	_burst_chunks(enemy, points, pending[2])


## Peers: chunks the host blasted off enemy id (local points and radii, meters). fx: burst their
## debris (false for a late joiner's catch-up list).
@rpc("authority", "reliable")
func _chunks(id: int, points: PackedVector3Array, radii: PackedFloat32Array, fx: bool) -> void:
	var enemy: Enemy = enemies.get(id)
	if enemy == null or points.size() != radii.size() or points.size() > 4096:
		return
	var removed := enemy.apply_chunks(points, radii)
	if fx:
		_burst_chunks(enemy, points, removed)


## Every peer: the debris of a batch of chunks, from the middle of where they came off.
func _burst_chunks(enemy: Enemy, points: PackedVector3Array, removed: Dictionary) -> void:
	if debris == null or removed.is_empty() or points.is_empty():
		return
	var middle := Vector3.ZERO
	for point in points:
		middle += point
	middle /= points.size()
	var at := enemy.global_transform * middle
	var out := at - enemy.get_center()
	out.y = maxf(out.y, 0.0) + 0.5
	debris.burst(at, out.normalized(), removed)


## Any peer: this peer's attack gave enemy id a status ("burning", "poisoned", ...) for seconds.
## The host applies it (Enemy.apply_status).
func request_status(id: int, status: String, seconds: float) -> void:
	if multiplayer.is_server():
		_apply_status(id, status, seconds)
	else:
		_request_status.rpc_id(1, id, status, seconds)


@rpc("any_peer", "reliable")
func _request_status(id: int, status: String, seconds: float) -> void:
	if _from_level() and is_finite(seconds):
		_apply_status(id, status, seconds)


func _apply_status(id: int, status: String, seconds: float) -> void:
	var enemy: Enemy = enemies.get(id)
	if enemy and enemy.alive and simulating:
		enemy.apply_status(status, clampf(seconds, 0.0, MAX_STATUS))


## Host: an enemy's set of active statuses changed; every peer tints it.
func statuses_changed(enemy: Enemy) -> void:
	var names := PackedStringArray(enemy.statuses.keys())
	names.sort()
	enemy.show_statuses(names)
	for peer_id in _peers():
		_statuses.rpc_id(peer_id, enemy.id, names)


@rpc("authority", "reliable")
func _statuses(id: int, names: PackedStringArray) -> void:
	var enemy: Enemy = enemies.get(id)
	if enemy:
		enemy.show_statuses(names)


## Every peer: hit flash and sound.
@rpc("authority", "unreliable")
func _hit_fx(id: int, point: Vector3) -> void:
	var enemy: Enemy = enemies.get(id)
	if enemy:
		enemy.flash()
		Sfx.play_at("shroom_hit", point, -4.0)


## Host: an enemy's attack landed on a player. Each player runs its own health, so this goes to
## the player's peer.
func damage_player(player: Player, amount: float, from: Vector3) -> void:
	var peer_id := player.get_multiplayer_authority()
	if peer_id == multiplayer.get_unique_id():
		player.take_damage(amount, from)
	else:
		_hurt.rpc_id(peer_id, amount, from)


@rpc("authority", "reliable")
func _hurt(amount: float, from: Vector3) -> void:
	var me := lab.local_player()
	if me:
		me.take_damage(amount, from)


## Host: gives a player a status (clouds: "poisoned", "burning"). Like damage, it runs on the
## player's own peer (Player.apply_status).
func status_player(player: Player, status: String, seconds: float) -> void:
	var peer_id := player.get_multiplayer_authority()
	if peer_id == multiplayer.get_unique_id():
		player.apply_status(status, seconds)
	else:
		_player_status.rpc_id(peer_id, status, seconds)


@rpc("authority", "reliable")
func _player_status(status: String, seconds: float) -> void:
	var me := lab.local_player()
	if me:
		me.apply_status(status, clampf(seconds, 0.0, MAX_STATUS))


## Host: a tentacle (enemy id) grabs a player, or lets go (id 0). The player's own peer runs the
## pull toward anchor (Player.set_held); the host's copy only records who holds it.
func hold_player(player: Player, enemy_id: int, anchor: Vector3) -> void:
	var holder := str(enemy_id) if enemy_id > 0 else ""
	var peer_id := player.get_multiplayer_authority()
	player.set_held(holder, anchor)
	if peer_id != multiplayer.get_unique_id():
		_player_held.rpc_id(peer_id, holder, anchor)


@rpc("authority", "reliable")
func _player_held(holder: String, anchor: Vector3) -> void:
	var me := lab.local_player()
	if me:
		me.set_held(holder, anchor)


## Host: the nearest point under the ceiling straight above at (the bottom face of the first solid
## voxel within max_up meters), or {} if there's none. {position, voxel (Vector3i)}.
func ceiling_point(at: Vector3, max_up := 20.0) -> Dictionary:
	var up: Dictionary = world.raycast(at + Vector3.UP * 0.05, Vector3.UP, max_up)
	if not up.hit:
		return {}
	var point: Vector3 = up.position
	return {position = point, voxel = world.world_to_voxel(point + Vector3.UP * world.voxel_size * 0.5)}


# --- Clouds --------------------------------------------------------------------------------------

## Any peer: a cloud of type (Cloud.TYPES) at a world point; radius and seconds below zero take the
## type's defaults. The host creates it and tells the peers. Returns it on the host, else null.
func request_cloud(type: String, at: Vector3, radius := -1.0, seconds := -1.0) -> Cloud:
	if not active or not Cloud.TYPES.has(type):
		return null
	if multiplayer.is_server():
		return _spawn_cloud(type, at, radius, seconds)
	_request_cloud.rpc_id(1, type, at, radius, seconds)
	return null


@rpc("any_peer", "reliable")
func _request_cloud(type: String, at: Vector3, radius: float, seconds: float) -> void:
	if _from_level() and active and Cloud.TYPES.has(type) and at.is_finite() and is_finite(radius) and is_finite(seconds):
		_spawn_cloud(type, at, minf(radius, 8.0), minf(seconds, MAX_STATUS))


func _spawn_cloud(type: String, at: Vector3, radius: float, seconds: float) -> Cloud:
	if clouds.size() >= MAX_CLOUDS:
		var oldest: int = clouds.keys().min()
		clouds[oldest].queue_free()
		clouds.erase(oldest)
	var id := _next_cloud
	_next_cloud += 1
	var cloud := _create_cloud(id, type, at, radius, seconds, true)
	for peer_id in _peers():
		_cloud_spawned.rpc_id(peer_id, id, type, at, cloud.radius, cloud.seconds)
	return cloud


func _create_cloud(id: int, type: String, at: Vector3, radius: float, seconds: float, host: bool) -> Cloud:
	var cloud: Cloud = CLOUD_SCENE.instantiate()
	cloud.name = "C%d" % id
	cloud.manager = self
	cloud.setup(id, type, at, radius, seconds, host)
	clouds[id] = cloud
	add_child(cloud)
	cloud_spawned.emit(cloud)
	return cloud


@rpc("authority", "reliable")
func _cloud_spawned(id: int, type: String, at: Vector3, radius: float, seconds: float) -> void:
	if active and not clouds.has(id) and Cloud.TYPES.has(type):
		_create_cloud(id, type, at, radius, seconds, false)


## Every peer: a cloud ran out (each peer frees its own on its own timer).
func cloud_ended(cloud: Cloud) -> void:
	if clouds.get(cloud.id) == cloud:
		clouds.erase(cloud.id)


## Host: ends a cloud early on every peer (a spore cloud going up in flames, see Fire).
func end_cloud(id: int) -> void:
	if not multiplayer.is_server():
		return
	_cloud_removed(id)
	for peer_id in _peers():
		_cloud_removed.rpc_id(peer_id, id)


@rpc("authority", "reliable")
func _cloud_removed(id: int) -> void:
	var cloud: Cloud = clouds.get(id)
	if cloud:
		clouds.erase(id)
		cloud.queue_free()


## Host: an enemy attacked (hit or miss), for its sound and lunge everywhere.
func enemy_attacked(enemy: Enemy) -> void:
	enemy.play_attack()
	for peer_id in _peers():
		_attacked.rpc_id(peer_id, enemy.id)


@rpc("authority", "unreliable")
func _attacked(id: int) -> void:
	var enemy: Enemy = enemies.get(id)
	if enemy:
		enemy.play_attack()


# --- Targets and steering ------------------------------------------------------------------------

## Players enemies go after (and the flow field leads to): in the level (peers_in_level: a joiner's
## player is spawned on the host before it has the level, standing where it will land), alive
## (remote players' deaths arrive with their state packets), not editing.
func targets() -> Array[Player]:
	var out: Array[Player] = []
	for peer_id: int in lab.players:
		var player: Player = lab.players[peer_id]
		if is_instance_valid(player) and not player.is_dead and not player.editing and peer_id in lab.peers_in_level:
			out.append(player)
	return out


## targets(), read once per frame and shared (don't modify it): for the per-enemy, per-tick
## lookups (nearest_player, is_far, the kinds' own checks), at most a frame stale.
func frame_targets() -> Array[Player]:
	var frame := Engine.get_process_frames()
	if _targets_frame != frame:
		_targets_frame = frame
		_targets = targets()
	return _targets


## Host: whether every target player is farther than meters from at (true with none). Enemy's
## simulation LOD.
func is_far(at: Vector3, meters: float) -> bool:
	var limit := meters * meters
	for player in frame_targets():
		if is_instance_valid(player) and player.global_position.distance_squared_to(at) <= limit:
			return false
	return true


## Host: whether a request comes from a peer in the level (a joiner still loading, or a peer
## that has left, can't hit, status or spawn anything).
func _from_level() -> bool:
	return multiplayer.is_server() and multiplayer.get_remote_sender_id() in lab.peers_in_level


## The nearest target to a position, or null.
func nearest_player(at: Vector3) -> Player:
	var best: Player = null
	var best_distance := INF
	for player in frame_targets():
		if not is_instance_valid(player):
			continue
		var distance := player.global_position.distance_squared_to(at)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


## Meters to the nearest target (INF if none). Works on every peer.
func nearest_player_distance(at: Vector3) -> float:
	var best := nearest_player(at)
	return best.global_position.distance_to(at) if best else INF


## The nearest other living enemy within max_range of enemy (raging targets), or null.
func nearest_enemy(enemy: Enemy, max_range := 20.0) -> Enemy:
	var best: Enemy = null
	var best_distance := max_range * max_range
	for other: Enemy in enemies.values():
		if other == enemy or not other.alive:
			continue
		var distance := other.global_position.distance_squared_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = other
	return best


## Host: a lure at a world point for enemies within radius meters, for seconds (below zero: until
## clear_lure). A second one under the same key replaces it.
func set_lure(key: String, at: Vector3, radius: float, seconds := -1.0) -> void:
	lures[key] = {at = at, radius = radius, until = Time.get_ticks_msec() + int(seconds * 1000.0) if seconds >= 0.0 else -1}


func clear_lure(key: String) -> void:
	lures.erase(key)


## Host: whether any lure is live (expired ones go).
func has_lures() -> bool:
	if lures.is_empty():
		return false
	var now := Time.get_ticks_msec()
	for key: String in lures.keys():
		if int(lures[key].until) >= 0 and now > int(lures[key].until):
			lures.erase(key)
	return not lures.is_empty()


## Host: the nearest live lure point whose radius reaches at, or null.
func lure_for(at: Vector3) -> Variant:
	var best: Variant = null
	var best_distance := INF
	var now := Time.get_ticks_msec()
	for lure: Dictionary in lures.values():
		if int(lure.until) >= 0 and now > int(lure.until):
			continue
		var distance := (lure.at as Vector3).distance_to(at)
		if distance <= float(lure.radius) and distance < best_distance:
			best_distance = distance
			best = lure.at
	return best


## Push away from nearby enemies so a crowd spreads out instead of stacking. Only the enemies in the
## grid cells around it are checked (_crowd_cells), not every enemy against every other.
func separation(enemy: Enemy) -> Vector3:
	if _crowd_frame != Engine.get_physics_frames():
		_build_crowd()
	var push := Vector3.ZERO
	var at := enemy.global_position
	var cx := floori(at.x / CROWD_CELL)
	var cz := floori(at.z / CROWD_CELL)
	for dz: int in _AROUND:
		for dx: int in _AROUND:
			for other: Variant in _crowd_cells.get(Vector2i(cx + dx, cz + dz), _NOBODY):
				if not is_instance_valid(other) or other == enemy:
					continue
				var offset: Vector3 = at - (other as Enemy).global_position
				offset.y = 0.0
				var distance: float = offset.length()
				if distance < CROWD_RANGE and distance > 0.001:
					push += offset / distance * (CROWD_RANGE - distance) / CROWD_RANGE
	return push


## Host, once per physics frame: buckets the enemies by CROWD_CELL columns for separation.
func _build_crowd() -> void:
	_crowd_frame = Engine.get_physics_frames()
	_crowd_cells.clear()
	for other: Enemy in enemies.values():
		var at := other.global_position
		var cell := Vector2i(floori(at.x / CROWD_CELL), floori(at.z / CROWD_CELL))
		if _crowd_cells.has(cell):
			_crowd_cells[cell].append(other)
		else:
			_crowd_cells[cell] = [other]


## Host: points the flow field at every living player now (the director ranks spawners by it
## even when no enemy is alive to keep it fresh).
func refresh_flow() -> void:
	if not simulating:
		return
	_flow_timer = 1.0 / FLOW_RATE
	var points := PackedVector3Array()
	for player in targets():
		points.append(player.global_position)
	world.update_flow_field(points, FLOW_RANGE)
	flow_reached = world.flow_reached if not points.is_empty() else 0
	flow_msec = Time.get_ticks_msec()
	flow_refreshed.emit()


func _physics_process(delta: float) -> void:
	if not simulating:
		return
	_flow_timer -= delta
	if _flow_timer <= 0.0:
		refresh_flow()
	if enemies.is_empty():
		return
	_state_timer -= delta
	var peers := _peers()
	if _state_timer > 0.0 or peers.is_empty():
		return
	_state_timer = 1.0 / STATE_RATE
	# In packets of at most STATES_PER_PACKET enemies (see there).
	var all: Array = enemies.values()
	for start in range(0, all.size(), STATES_PER_PACKET):
		var count := mini(STATES_PER_PACKET, all.size() - start)
		var ids := PackedInt32Array()
		var positions := PackedVector3Array()
		var yaws := PackedFloat32Array()
		ids.resize(count)
		positions.resize(count)
		yaws.resize(count)
		for i in count:
			var enemy: Enemy = all[start + i]
			ids[i] = enemy.id
			positions[i] = enemy.global_position
			yaws[i] = enemy.rotation.y
		for peer_id in peers:
			_states.rpc_id(peer_id, ids, positions, yaws)


@rpc("authority", "unreliable_ordered")
func _states(ids: PackedInt32Array, positions: PackedVector3Array, yaws: PackedFloat32Array) -> void:
	for i in ids.size():
		var enemy: Enemy = enemies.get(ids[i])
		if enemy:
			enemy.push_state(positions[i], yaws[i])


## Live reload: re-skin every enemy whose kind's .vox changed.
func _on_vox_changed(paths: PackedStringArray) -> void:
	var kinds := {}
	for path in paths:
		if path.begins_with(EnemyModels.DIR):
			kinds[EnemyModels.forget(path)] = true
	for kind: String in kinds:
		Enemy.forget_meshes(kind)
	for enemy: Enemy in enemies.values():
		if kinds.has(enemy.kind):
			enemy.build_body()
