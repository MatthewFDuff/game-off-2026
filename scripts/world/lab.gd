class_name Lab
extends Node3D
## Co-op level scene: plays or edits a level (Net.session). The host loads the level file; a joining
## peer asks to enter and the host sends it the level (settings and objects), then its world, then
## spawns the newcomer's player everywhere and tells the newcomer about the players already there.
## Once the newcomer has all that, it confirms, and only then is it added to peers_in_level, so
## nobody streams movement for players it hasn't spawned yet.
##
## Modes. Edit: everyone flies, the world holds the level's base voxels and props are meshes
## (LevelView), so they stay editable. Play: the host stamps the props into the world and LevelPlay
## runs doors, triggers and assets. Switching from play back to edit restores the world exactly as
## it was, so nothing done while play-testing reaches the level. Enemies (EnemyManager, spawned by
## the HordeDirector) and pickups (ItemManager) only exist in play and are cleared on the way back
## to edit.
##
## Players are named after their peer id under Players, so RPC paths match on every peer, and each
## is the multiplayer authority of its own player.

signal player_spawned(player: Player)
signal player_despawned(peer_id: int)
## A short player-facing note (reloads, saves, asset damage, errors).
signal notice(text: String)
## The mode changed on this peer ("edit" or "play").
signal mode_changed(mode: String)
## Host: a joining peer has the level, its world and the players, and is now in peers_in_level
## (EnemyManager sends it the enemies here).
signal peer_entered(peer_id: int)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
## Seconds dead before respawning (at the clone vat, or a spawn).
const RESPAWN_DELAY := 3.0

@export var world: VoxelWorld
@export var world_sync: WorldSync
@export var players_root: Node3D
@export var debris: VoxelDebris
@export var edits: LevelEdits
@export var view: LevelView
@export var play: LevelPlay
@export var environment: WorldEnvironment
@export var enemies: EnemyManager
@export var director: HordeDirector
@export var items: ItemManager
@export var fire: Fire

var level: LevelData
var mode := "play"
## Peers whose level is loaded and synced, the host included. Kept current on every peer.
var peers_in_level: Array[int] = []
## peer id -> Player
var players := {}

## Host, in play: the edit-mode world to restore, and the stamped props (for live reload).
var _edit_base := PackedByteArray()
var _props: Props


func _ready() -> void:
	VoxelMaterials.apply_to(world)
	world_sync.carved.connect(func(center: Vector3, normal: Vector3, removed: Dictionary) -> void: debris.burst(center, normal, removed))
	world_sync.blob_received.connect(_on_blob)
	world_sync.snapshot_applied.connect(_on_snapshot)
	edits.object_set.connect(view.object_set)
	play.killed_in_zone.connect(func(_id: String, peer_id: int) -> void: _kill(peer_id))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Net.players_changed.connect(_on_roster_changed)
	VoxWatch.changed.connect(_on_vox_changed)

	if not multiplayer.is_server():
		_request_entry.rpc_id(1)
		return
	var start := Time.get_ticks_msec()
	level = LevelData.load_level(Net.session.level)
	if level == null:
		Net.leave.call_deferred("Level '%s' wasn't found." % Net.session.level)
		return
	_apply_settings()
	world.set_data(level.voxels)
	_set_mode_locally(Net.session.mode)
	world.remesh_all_now()
	print("level %s loaded in %d ms" % [level.name, Time.get_ticks_msec() - start])
	peers_in_level = [1]
	_spawn_player(1, spawn_point(0), spawn_yaw(0))


func local_player() -> Player:
	return players.get(multiplayer.get_unique_id())


func is_editing() -> bool:
	return mode == "edit"


## Shows a note on this peer.
func notify(text: String, everyone := true) -> void:
	notice.emit(text)
	if everyone and multiplayer.is_server():
		for peer_id in peers_in_level:
			if peer_id != 1:
				_notice.rpc_id(peer_id, text)


## Host: shows a note to one peer.
func notify_peer(peer_id: int, text: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		notice.emit(text)
	else:
		_notice.rpc_id(peer_id, text)


@rpc("authority", "reliable")
func _notice(text: String) -> void:
	notice.emit(text)


# --- Modes and saving ----------------------------------------------------------------------------

## Any peer: switches everyone between "edit" and "play".
func request_mode(new_mode: String) -> void:
	if multiplayer.is_server():
		_change_mode(new_mode)
	else:
		_request_mode.rpc_id(1, new_mode)


@rpc("any_peer", "reliable")
func _request_mode(new_mode: String) -> void:
	if multiplayer.is_server():
		_change_mode(new_mode)


func _change_mode(new_mode: String) -> void:
	if new_mode == mode or not new_mode in ["edit", "play"]:
		return
	_set_mode_locally(new_mode)
	world.remesh_all_now()
	for peer_id in peers_in_level:
		if peer_id != 1:
			_mode_changed.rpc_id(peer_id, new_mode)
	world_sync.resend_snapshots()
	notify("Play-testing (F5 to go back to editing)" if new_mode == "play" else "Editing (changes made while playing were undone)")


@rpc("authority", "reliable")
func _mode_changed(new_mode: String) -> void:
	_set_mode_locally(new_mode)


## Entering play (host): keep the edit world, stamp the props. Leaving: put the edit world back.
func _set_mode_locally(new_mode: String) -> void:
	# Stop play first: restoring the edit world would otherwise count as wrecking every asset.
	play.stop()
	if multiplayer.is_server():
		if new_mode == "play":
			if mode == "edit" or _edit_base.is_empty():
				_edit_base = world.get_data()
			_props = Props.new(world, 0)
			for object: Dictionary in level.objects.values():
				if object.kind == "prop":
					_props.place(object.name, object.origin, object.facing)
		elif not _edit_base.is_empty() and mode == "play":
			world.set_data(_edit_base)
			_edit_base = PackedByteArray()
			_props = null
	mode = new_mode
	world.detach_floating = mode == "play"
	view.set_mode(mode)
	if mode == "play":
		play.start()
	for player: Player in players.values():
		if not player.is_local:
			player.editing = mode == "edit" # Hides their gun while editing.
	var me := local_player()
	if me:
		me.set_editing(mode == "edit")
		if mode == "play":
			var index := _player_index(multiplayer.get_unique_id())
			me.teleport(spawn_point(index))
			me.rotation.y = spawn_yaw(index)
			me.revive()
	mode_changed.emit(mode)


## Any peer: asks the host to save the level.
func request_save() -> void:
	if multiplayer.is_server():
		_save()
	else:
		_request_save.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_save() -> void:
	if multiplayer.is_server():
		_save()


func _save() -> void:
	level.voxels = world.get_data() if mode == "edit" else _edit_base
	var error := level.save()
	if error == OK:
		notify("Saved %s (%s)" % [level.name, LevelData.save_dir().path_join(level.name)])
	else:
		notify("Couldn't save %s: %s" % [level.name, error_string(error)])


func _apply_settings() -> void:
	var env := environment.environment
	env.ambient_light_color = level.settings.get("ambient_color", env.ambient_light_color)
	env.ambient_light_energy = level.settings.get("ambient_energy", env.ambient_light_energy)
	env.fog_light_color = level.settings.get("fog_color", env.fog_light_color)
	env.fog_density = level.settings.get("fog_density", env.fog_density)


# --- Spawning ------------------------------------------------------------------------------------

## Where the index-th player (0-based) starts: the spawn marker for that player, else the first
## spawn fanned out sideways, else the middle of the level.
func spawn_point(index: int) -> Vector3:
	var spawns := _spawn_markers()
	if spawns.is_empty():
		var size := Vector3(world.get_size_in_voxels())
		return view.to_world(Vector3(size.x * 0.5, size.y * 0.6, size.z * 0.5))
	for marker in spawns:
		if marker.index == index + 1:
			return view.to_world(marker.position)
	var base := view.to_world(spawns[0].position)
	var right := Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(spawns[0].yaw))
	return base + right * float(index)


func spawn_yaw(index: int) -> float:
	var spawns := _spawn_markers()
	for marker in spawns:
		if marker.index == index + 1:
			return deg_to_rad(marker.yaw)
	return deg_to_rad(spawns[0].yaw) if not spawns.is_empty() else 0.0


func _spawn_markers() -> Array[Dictionary]:
	var spawns: Array[Dictionary] = []
	if level:
		for object: Dictionary in level.objects.values():
			if object.kind == "marker" and object.type == "spawn":
				spawns.append(object)
	spawns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.index < b.index)
	return spawns


## Join order of a peer, for picking its spawn.
func _player_index(peer_id: int) -> int:
	var ids: Array = Net.players.keys()
	ids.sort()
	return maxi(ids.find(peer_id), 0)


func _spawn_player(peer_id: int, feet: Vector3, yaw: float) -> void:
	if players.has(peer_id):
		return
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.world = world
	var weapon: Weapon = player.get_node("Weapon")
	weapon.world_sync = world_sync
	weapon.enemies = enemies
	if peer_id == multiplayer.get_unique_id():
		var tool := EditorTool.new()
		tool.name = "EditorTool"
		tool.lab = self
		player.add_child(tool)
	player.set_multiplayer_authority(peer_id)
	players_root.add_child(player)
	player.teleport(feet)
	player.rotation.y = yaw
	player.set_display(Net.players.get(peer_id, {}).get("name", "Expendable"), Net.player_color(peer_id))
	player.editing = mode == "edit"
	if player.is_local:
		player.set_editing(mode == "edit")
		player.died.connect(_on_local_died)
		player.interacted.connect(_on_local_interact)
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


# --- Death (play) --------------------------------------------------------------------------------

## Host: kills a player (kill zones). Each player runs its own health, so this goes to its owner.
func _kill(peer_id: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		_die_here()
	else:
		_die.rpc_id(peer_id)


@rpc("authority", "reliable")
func _die() -> void:
	_die_here()


func _die_here() -> void:
	var me := local_player()
	if me and not me.is_dead:
		me.take_damage(me.health + 1.0, me.global_position)


func _on_local_died() -> void:
	notify("You died. Respawning...", false)
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	var me := local_player()
	if me == null or not me.is_dead or mode != "play":
		return
	var vats := level.objects.values().filter(func(o: Dictionary) -> bool: return o.kind == "marker" and o.type == "clone_vat")
	var index := _player_index(multiplayer.get_unique_id())
	me.teleport(view.to_world(vats[0].position) if not vats.is_empty() else spawn_point(index))
	me.rotation.y = deg_to_rad(vats[0].yaw) if not vats.is_empty() else spawn_yaw(index)
	me.revive()


## E in play: closes an open note, else uses the door or prop in view (LevelPlay.request_use; the
## host decides). Refusals this peer can see coming ("Locked: needs red keycard") are shown here.
func _on_local_interact() -> void:
	if mode != "play":
		return
	if play.reading != "":
		play.close_reading()
		return
	var me := local_player()
	if me == null or me.is_dead:
		return
	var target := play.interactables.in_view(me.camera)
	if target == "":
		return
	var refusal := play.interactables.local_refusal(target, me)
	if refusal != "":
		notify(refusal, false)
	else:
		play.request_use(target)


# --- Entering ------------------------------------------------------------------------------------

@rpc("any_peer", "reliable")
func _request_entry() -> void:
	if not multiplayer.is_server():
		return
	var newcomer := multiplayer.get_remote_sender_id()
	if newcomer in peers_in_level:
		return
	_entry_mode.rpc_id(newcomer, mode)
	world_sync.send_blob(newcomer, "level", level.encode_info())
	world_sync.send_snapshot(newcomer)
	var index := _player_index(newcomer)
	var feet := spawn_point(index)
	# The newcomer learns about everyone already here, then everyone learns about the newcomer.
	for peer_id: int in players:
		var player: Player = players[peer_id]
		_remote_spawn.rpc_id(newcomer, peer_id, player.global_position, player.rotation.y)
	_remote_spawn.rpc_id(newcomer, newcomer, feet, spawn_yaw(index))
	for peer_id in peers_in_level:
		if peer_id != 1:
			_remote_spawn.rpc_id(peer_id, newcomer, feet, spawn_yaw(index))
	_spawn_player(newcomer, feet, spawn_yaw(index))
	_entry_sent.rpc_id(newcomer)


@rpc("authority", "reliable")
func _entry_mode(host_mode: String) -> void:
	mode = host_mode


func _on_blob(tag: String, bytes: PackedByteArray) -> void:
	if tag == "level":
		level = LevelData.decode_info(bytes)
		_apply_settings()


## A joiner's world arrived (or the host resent it after a mode switch).
func _on_snapshot() -> void:
	if level and view.mode != mode:
		_set_mode_locally(mode)


@rpc("authority", "reliable")
func _entry_sent() -> void:
	_set_mode_locally(mode)
	_confirm_entry.rpc_id(1)


@rpc("any_peer", "reliable")
func _confirm_entry() -> void:
	var newcomer := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and players.has(newcomer) and newcomer not in peers_in_level:
		peers_in_level.append(newcomer)
		_broadcast_in_level()
		peer_entered.emit(newcomer)


func _broadcast_in_level() -> void:
	_update_send_targets()
	for peer_id in peers_in_level:
		if peer_id != 1:
			_set_in_level.rpc_id(peer_id, peers_in_level)


@rpc("authority", "reliable")
func _remote_spawn(peer_id: int, feet: Vector3, yaw: float) -> void:
	_spawn_player(peer_id, feet, yaw)


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


# --- Live reload ---------------------------------------------------------------------------------

## Edited props: in edit mode each peer redraws its meshes; in play the host swaps the stamped
## props through WorldSync, so co-op peers get the host's version. Characters and shrooms reload
## themselves on each peer.
func _on_vox_changed(paths: PackedStringArray) -> void:
	var notes: Array[String] = []
	for path in paths:
		var prop := Props.name_for_path(path)
		if path.begins_with(VoxelMaterials.PATTERN_DIR):
			VoxelMaterials.apply_to(world)
			notes.append("Reloaded pattern " + path.get_file())
		elif prop == "":
			notes.append("Reloaded " + path.get_file())
		elif mode == "edit":
			Props.reload_prop(prop)
			view.reload_prop(prop)
			notes.append("Reloaded %s.vox" % prop)
		elif multiplayer.is_server() and _props:
			notes.append(_props.reload_placements(prop, world_sync.stamp_model))
	if not notes.is_empty():
		notify("\n".join(notes), false)
