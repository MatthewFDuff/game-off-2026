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
## to the peers (_statuses) so every peer tints it. Clouds (Cloud) are children here too ("C<id>"):
## the host owns them and applies their effects, the peers get a spawn message and draw them.

signal enemy_spawned(enemy: Enemy)
## Host: a hit landed. amount includes the crit multiplier; zone is the hit zone name.
signal enemy_damaged(enemy: Enemy, amount: float, zone: String)
## Host: an enemy was killed (not despawned), just before it bursts.
signal enemy_died(enemy: Enemy)
## This peer: one of its own shots hit an enemy (the HUD's hit marker).
signal local_hit(enemy: Enemy, point: Vector3)
## Every peer: a cloud appeared (on the host, with its effects; elsewhere, its looks).
signal cloud_spawned(cloud: Cloud)

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
## Meters of walking the flow field covers around the players.
const FLOW_RANGE := 80.0
## Requests from peers are clamped to this so a bad packet can't do anything silly.
const MAX_DAMAGE := 1000.0
## Knockback speed (m/s) by damage kind.
const KNOCKBACK := {rifle = 1.2, shotgun = 2.5, flame = 0.0, blast = 7.0, ricochet = 1.5, homing = 2.0,
		poison = 0.5, melee = 6.0, flask = 0.5, enemy = 2.0, status = 0.0}
## Longest status (seconds) a peer can ask for.
const MAX_STATUS := 30.0
## Seconds a sunk enemy (sink) takes to go down into the floor.
const SINK_TIME := 0.5

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

var _next_id := 1
var _next_cloud := 1
var _flow_timer := 0.0
var _state_timer := 0.0
var _scenes := {}
## Host, during a peer's hit (request_hit): that peer's id, else 0 (Enemy._on_damaged).
var _hit_peer := 0


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
	for cloud: Cloud in clouds.values():
		cloud.queue_free()
	clouds.clear()


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
	enemy_died.emit(enemy)
	enemies.erase(id)
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
	if multiplayer.is_server():
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
	enemy._on_damaged(amount, kind, _hit_peer)
	enemy_damaged.emit(enemy, amount, zone)
	if fx:
		_hit_fx(enemy.id, point)
		for peer_id in _peers():
			_hit_fx.rpc_id(peer_id, enemy.id, point)
	if enemy.health <= 0.0:
		kill(enemy.id)


## Any peer: this peer's attack gave enemy id a status ("burning", "poisoned", ...) for seconds.
## The host applies it (Enemy.apply_status).
func request_status(id: int, status: String, seconds: float) -> void:
	if multiplayer.is_server():
		_apply_status(id, status, seconds)
	else:
		_request_status.rpc_id(1, id, status, seconds)


@rpc("any_peer", "reliable")
func _request_status(id: int, status: String, seconds: float) -> void:
	if multiplayer.is_server():
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
	if multiplayer.is_server() and active and Cloud.TYPES.has(type):
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

## Players enemies go after (and the flow field leads to): in the level, alive (remote players'
## deaths arrive with their state packets), not editing.
func targets() -> Array[Player]:
	var out: Array[Player] = []
	for player: Player in lab.players.values():
		if is_instance_valid(player) and not player.is_dead and not player.editing:
			out.append(player)
	return out


## The nearest target to a position, or null.
func nearest_player(at: Vector3) -> Player:
	var best: Player = null
	var best_distance := INF
	for player in targets():
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


## Push away from nearby enemies so a crowd spreads out instead of stacking.
func separation(enemy: Enemy) -> Vector3:
	var push := Vector3.ZERO
	for other: Enemy in enemies.values():
		if other == enemy:
			continue
		var offset := enemy.global_position - other.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance < 0.9 and distance > 0.001:
			push += offset / distance * (0.9 - distance) / 0.9
	return push


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
	flow_reached = int(world.get_stats().get("flow_reached", 0)) if not points.is_empty() else 0


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
	var ids := PackedInt32Array()
	var positions := PackedVector3Array()
	var yaws := PackedFloat32Array()
	for enemy: Enemy in enemies.values():
		ids.append(enemy.id)
		positions.append(enemy.global_position)
		yaws.append(enemy.rotation.y)
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
