class_name Lab
extends Node3D
## Co-op level scene. Every peer builds the level locally (for now the generated facility, until
## the level editor saves real levels), then a joining peer asks the host to enter: the host sends
## its world snapshot, spawns the newcomer's player everywhere and tells the newcomer about the
## players already there. Once the newcomer has all that, it confirms, and only then is it added to
## peers_in_level, so nobody streams movement for players it hasn't spawned yet.
##
## Players are named after their peer id under Players, so RPC paths match on every peer, and each
## is the multiplayer authority of its own player.

signal player_spawned(player: Player)
signal player_despawned(peer_id: int)

const PLAYER_SCENE := preload("res://scenes/player.tscn")

@export var world: VoxelWorld
@export var world_sync: WorldSync
@export var lights: Node3D
@export var players_root: Node3D
@export var debris: VoxelDebris
@export var seed := 2026

var info := {}
## Peers whose level is loaded and synced, the host included. Kept current on every peer.
var peers_in_level: Array[int] = []
## peer id -> Player
var players := {}


func _ready() -> void:
	_build_level()
	world_sync.carved.connect(func(center: Vector3, normal: Vector3, removed: Dictionary) -> void: debris.burst(center, normal, removed))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Net.players_changed.connect(_on_roster_changed)

	if multiplayer.is_server():
		peers_in_level = [1]
		_spawn_player(1, _spawn_point(0))
	else:
		_request_entry.rpc_id(1)


func local_player() -> Player:
	return players.get(multiplayer.get_unique_id())


func _build_level() -> void:
	VoxelMaterials.apply_to(world)
	var start := Time.get_ticks_msec()
	var immediate_limit := world.immediate_remesh_limit
	world.immediate_remesh_limit = 0
	world.detach_floating = false
	info = FacilityBuilder.new().build(world, lights, seed)
	world.remesh_all_now()
	world.immediate_remesh_limit = immediate_limit
	world.detach_floating = true
	print("level built in %d ms" % (Time.get_ticks_msec() - start))


## Spawn spots fan out sideways from the level spawn, skipping any that land inside a wall.
func _spawn_point(index: int) -> Vector3:
	var base: Vector3 = info.spawn
	var right := Vector3.RIGHT.rotated(Vector3.UP, info.spawn_yaw)
	for offset: int in [index, -index, index + 2, -index - 2]:
		var feet := base + right * 1.0 * offset
		if not world.box_overlaps_solid(AABB(feet - Vector3(0.3, -0.05, 0.3), Vector3(0.6, 1.75, 0.6))):
			return feet
	return base


func _spawn_player(peer_id: int, feet: Vector3) -> void:
	if players.has(peer_id):
		return
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.world = world
	var rifle := Rifle.new()
	rifle.name = "Rifle"
	rifle.world_sync = world_sync
	player.add_child(rifle)
	player.set_multiplayer_authority(peer_id)
	players_root.add_child(player)
	player.teleport(feet)
	player.rotation.y = info.spawn_yaw
	player.set_display(Net.players.get(peer_id, {}).get("name", "Expendable"), Net.player_color(peer_id))
	players[peer_id] = player
	_update_send_targets()
	player_spawned.emit(player)


func _despawn_player(peer_id: int) -> void:
	var player: Player = players.get(peer_id)
	if player:
		players.erase(peer_id)
		player.queue_free()
		player_despawned.emit(peer_id)


## The local player streams its movement to everyone else in the level.
func _update_send_targets() -> void:
	var me := local_player()
	if me:
		me.net_peers = peers_in_level.filter(func(id: int) -> bool: return id != multiplayer.get_unique_id())


@rpc("any_peer", "reliable")
func _request_entry() -> void:
	if not multiplayer.is_server():
		return
	var newcomer := multiplayer.get_remote_sender_id()
	if newcomer in peers_in_level:
		return
	world_sync.send_snapshot(newcomer)
	var feet := _spawn_point(peers_in_level.size())
	# The newcomer learns about everyone already here, then everyone learns about the newcomer.
	for peer_id: int in players:
		var player: Player = players[peer_id]
		_remote_spawn.rpc_id(newcomer, peer_id, player.global_position)
	_remote_spawn.rpc_id(newcomer, newcomer, feet)
	for peer_id in peers_in_level:
		if peer_id != 1:
			_remote_spawn.rpc_id(peer_id, newcomer, feet)
	_spawn_player(newcomer, feet)
	_entry_sent.rpc_id(newcomer)


@rpc("authority", "reliable")
func _entry_sent() -> void:
	_confirm_entry.rpc_id(1)


@rpc("any_peer", "reliable")
func _confirm_entry() -> void:
	var newcomer := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and players.has(newcomer) and newcomer not in peers_in_level:
		peers_in_level.append(newcomer)
		_broadcast_in_level()


func _broadcast_in_level() -> void:
	_update_send_targets()
	for peer_id in peers_in_level:
		if peer_id != 1:
			_set_in_level.rpc_id(peer_id, peers_in_level)


@rpc("authority", "reliable")
func _remote_spawn(peer_id: int, feet: Vector3) -> void:
	_spawn_player(peer_id, feet)


@rpc("authority", "reliable")
func _set_in_level(ids: Array) -> void:
	peers_in_level.assign(ids)
	_update_send_targets()


func _on_peer_disconnected(peer_id: int) -> void:
	_despawn_player(peer_id)
	if multiplayer.is_server() and peer_id in peers_in_level:
		peers_in_level.erase(peer_id)
		_broadcast_in_level()


func _on_roster_changed() -> void:
	for peer_id: int in players:
		if Net.players.has(peer_id):
			players[peer_id].set_display(Net.players[peer_id].name, Net.player_color(peer_id))
