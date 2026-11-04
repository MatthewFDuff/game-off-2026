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
##
## Shifts (docs/shift-save.md): in a story shift (Net.session.shift) the host keeps the one shift
## save (ShiftSave) through save_shift, which LevelPlay calls at checkpoints, seals and the generator,
## LabHud's Leave shift calls, and closing the window calls. With Net.session.resume the host loads
## that save as the level opens, before any peer can enter (the one time the world is replaced
## without WorldSync; peers get it in the late-join snapshot), and spawns at the checkpoint vat.
## Newcomers to a play level with a checkpoint set land at that vat too.

signal player_spawned(player: Player)
signal player_despawned(peer_id: int)
## A short player-facing note (reloads, saves, asset damage, errors).
signal notice(text: String)
## The mode changed on this peer ("edit" or "play").
signal mode_changed(mode: String)
## Host: a joining peer has the level, its world and the players, and is now in peers_in_level
## (EnemyManager sends it the enemies here).
signal peer_entered(peer_id: int)

## Loaded when a player spawns, not preloaded: player.tscn's scripts reach Lab, and a preload here
## mid-way through loading player.tscn gets an empty scene.
const PLAYER_SCENE_PATH := "res://scenes/player.tscn"
## Seconds dead before respawning (at the clone vat, or a spawn).
const RESPAWN_DELAY := 3.0
## The death fade: how red it gets and how long it takes to come in and to clear after respawning.
const DEATH_FADE_ALPHA := 0.55
const DEATH_FADE_IN := 0.6
const DEATH_FADE_OUT := 0.8
## The host's notice when the shift on file can't be resumed (missing, broken or another layout).
const STALE_SHIFT_NOTE := "The shift on file was recorded against an older site layout. Starting fresh."

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
@export var glass: Glass
@export var mycelium: Mycelium

var level: LevelData
var mode := "play"
## Peers whose level is loaded and synced, the host included. Kept current on every peer.
var peers_in_level: Array[int] = []
## peer id -> Player
var players := {}

## Host, in play: the edit-mode world to restore, and the stamped props (for live reload).
var _edit_base := PackedByteArray()
var _props: Props
## This peer: clones grown for the local player since play began (the respawn toast counts them).
var clones := 0
## Host: seconds of play in this story shift so far (from the save when resumed; counts in play).
var shift_seconds := 0.0
## Host: clones the party had grown when the resumed shift was saved; Story starts its deaths here.
var resumed_deaths := 0
## Host: this level was resumed from the shift save.
var resumed := false
## The HUD's story node (Story sets it), for the death count a save keeps.
var story: Story
## This peer, joining: where the host put the new player (_entry_spot), used when play starts here.
var _entry_at: Array = []
var _fade: ColorRect


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
	# Read before play starts, so Story's deaths begin at the saved count when play starts.
	var save: Dictionary = _load_shift() if Net.session.get("resume", false) and Net.session.mode == "play" else {}
	_set_mode_locally(Net.session.mode)
	if not save.is_empty():
		resumed = _resume_shift(save)
	world.remesh_all_now()
	print("level %s loaded in %d ms" % [level.name, Time.get_ticks_msec() - start])
	peers_in_level = [1]
	if resumed:
		_spawn_player(1, respawn_point(), respawn_yaw())
	else:
		_spawn_player(1, spawn_point(0), spawn_yaw(0))


func _process(delta: float) -> void:
	if multiplayer.is_server() and in_shift():
		shift_seconds += delta


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_shift()


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


# --- The shift save (host) ------------------------------------------------------------------------

## Playing a story shift here: Net.session.shift, in play, and not the waiting room.
func in_shift() -> bool:
	return bool(Net.session.get("shift", false)) and mode == "play" and level != null and level.name != "waiting_room"


## Host: keeps the shift on file (ShiftSave): play's state, the world, the director, the item spots,
## the clock and the clone count. A no-op on peers, outside a shift and during the finale.
func save_shift() -> void:
	if not multiplayer.is_server() or not in_shift() or not play.active or (director and director.finale_active):
		return
	var record := play.capture()
	record.level = level.name
	record.level_hash = ShiftSave.level_hash(level.name)
	record.saved_at = int(Time.get_unix_time_from_system())
	record.elapsed = shift_seconds
	record.deaths = story.deaths if story else resumed_deaths
	record.director = director.save_state() if director else {}
	if items:
		record.items_taken = items.taken_spots()
		record.items_loose = items.loose()
	record.party = Net.players.values().map(func(entry: Dictionary) -> String: return str(entry.name))
	record.vat_room = ShiftSave.room_of(level, play.checkpoint)
	var error := ShiftSave.write(record, world.get_data())
	if error != OK:
		notify("Fung AI could not keep your clone on file (%s)." % error_string(error), false)


## Host: the shift save for this level, or {} (with the fallback notice) if it's missing, broken or
## recorded against another layout. Sets the clock and the clone count from it.
func _load_shift() -> Dictionary:
	var save := ShiftSave.load()
	if save.is_empty() or not save.get("layout_ok", false) or str(save.get("level", "")) != level.name:
		notify(STALE_SHIFT_NOTE)
		return {}
	shift_seconds = float(save.get("elapsed", 0.0))
	resumed_deaths = int(save.get("deaths", 0))
	return save


## Host, as the level opens (play started, no peer in yet): the saved world, then play's state, the
## director's spawners and the item spots. False (and a fresh start) if the world was refused.
func _resume_shift(save: Dictionary) -> bool:
	if not play.replace_world(save.voxels):
		shift_seconds = 0.0
		resumed_deaths = 0
		if story:
			story.deaths = 0
		notify(STALE_SHIFT_NOTE)
		return false
	play.restore(save)
	if director:
		director.restore(save.get("director", {}))
	if items and (save.has("items_taken") or save.has("items_loose")):
		items.restore(save.get("items_taken", []), save.get("items_loose", []))
	return true


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
			if mycelium:
				mycelium.plan_level() # Links see the walls, not the props.
			_props = Props.new(world, 0)
			for object: Dictionary in level.objects.values():
				if object.kind == "prop":
					_props.place(object.name, object.origin, object.facing)
			if mycelium:
				mycelium.stamp_level() # Into air only, after the props.
		elif not _edit_base.is_empty() and mode == "play":
			world.set_data(_edit_base)
			_edit_base = PackedByteArray()
			_props = null
	mode = new_mode
	world.detach_floating = mode == "play"
	view.set_mode(mode)
	if mode == "play":
		clones = 0
		play.start()
		_attach_story()
	for player: Player in players.values():
		if not player.is_local:
			player.editing = mode == "edit" # Hides their gun while editing.
	var me := local_player()
	if me:
		me.set_editing(mode == "edit")
		if mode == "play":
			var index := _player_index(multiplayer.get_unique_id())
			# A joiner starts where the host put it (the checkpoint vat, if the party has one).
			me.teleport(_entry_at[0] if not _entry_at.is_empty() else spawn_point(index))
			me.rotation.y = _entry_at[1] if not _entry_at.is_empty() else spawn_yaw(index)
			_entry_at = []
			me.revive()
	mode_changed.emit(mode)


## Story nodes that live with particular levels (named, so RPC paths match on every peer).
func _attach_story() -> void:
	if level and level.name == "waiting_room" and not has_node("WaitingRoom"):
		var room := WaitingRoom.new()
		room.name = "WaitingRoom"
		room.lab = self
		add_child(room)


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
	var player: Player = load(PLAYER_SCENE_PATH).instantiate()
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
	# Everyone's copy: the owner sends what they're doing in the editor, the others draw it.
	var presence := EditorPresence.new()
	presence.name = "Presence"
	presence.lab = self
	player.add_child(presence)
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


## This peer, as the host moves the session to another level (Net.change_level): the local player
## stops streaming, since the host's next level doesn't have it yet.
func stop_streaming() -> void:
	var me := local_player()
	if me:
		me.net_peers = []


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
	_death_fade(DEATH_FADE_ALPHA, DEATH_FADE_IN)
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	var me := local_player()
	if me == null or not me.is_dead or mode != "play":
		_death_fade(0.0, DEATH_FADE_OUT)
		return
	me.teleport(respawn_point())
	me.rotation.y = respawn_yaw()
	me.revive()
	clones += 1
	notify("Clone #%d grown. Billed to you." % clones, false)
	_death_fade(0.0, DEATH_FADE_OUT)


## Where the local player respawns: the checkpoint vat (the last one the party reached), else the
## player's own spawn. Never some other vat: the first one in the file can be behind a seal.
func respawn_point() -> Vector3:
	var vat := _checkpoint_vat()
	return view.to_world(vat.position) if not vat.is_empty() else spawn_point(_player_index(multiplayer.get_unique_id()))


## Which way the respawned player faces: from the vat toward the middle of the room it stands in
## (vats sit off to the side, so that's into the room), else the vat's yaw, else the spawn's.
func respawn_yaw() -> float:
	var vat := _checkpoint_vat()
	if vat.is_empty():
		return spawn_yaw(_player_index(multiplayer.get_unique_id()))
	var at: Vector3 = vat.position
	for object: Dictionary in level.objects.values():
		if object.get("kind") != "room":
			continue
		var box := AABB(Vector3(object.from), Vector3(object.to - object.from))
		if not box.has_point(at + Vector3.UP):
			continue
		var to_center := box.get_center() - at
		to_center.y = 0.0
		if to_center.length() > 4.0:
			return atan2(-to_center.x, -to_center.z)
		break
	return deg_to_rad(vat.yaw)


func _checkpoint_vat() -> Dictionary:
	var vat: Dictionary = level.objects.get(play.checkpoint, {}) if level else {}
	return vat if vat.get("kind") == "marker" and vat.get("type") == "clone_vat" else {}


## This peer: tweens the red death overlay to alpha over seconds (made on first use).
func _death_fade(alpha: float, seconds: float) -> void:
	if _fade == null:
		if alpha <= 0.0:
			return
		var layer := CanvasLayer.new()
		layer.name = "DeathFade"
		layer.layer = 50
		add_child(layer)
		_fade = ColorRect.new()
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.color = Color(0.45, 0.0, 0.0, 0.0)
		layer.add_child(_fade)
		# The offsets too: inside the tree, set_anchors_preset alone keeps the 0 x 0 rect.
		_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tween := _fade.create_tween()
	tween.tween_property(_fade, "color:a", alpha, seconds)


## E in play: closes an open note, else uses the door or prop in view (LevelPlay.request_use; the
## host decides). Refusals this peer can see coming ("Locked: needs red keycard") are shown here at
## once; a refused door still goes to the host, which refuses it too (the same toast) and emits
## door_refused, so the intercom can play its clearance line or the door's hint.
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
		if play.is_door(target):
			play.request_use(target)
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
	var yaw := spawn_yaw(index)
	# In play with a checkpoint, a newcomer lands with the party at its vat, not at the start.
	if mode == "play" and not _checkpoint_vat().is_empty():
		feet = respawn_point()
		yaw = respawn_yaw()
	# The newcomer learns about everyone already here, then everyone learns about the newcomer.
	for peer_id: int in players:
		var player: Player = players[peer_id]
		_remote_spawn.rpc_id(newcomer, peer_id, player.global_position, player.rotation.y)
	_remote_spawn.rpc_id(newcomer, newcomer, feet, yaw)
	for peer_id in peers_in_level:
		if peer_id != 1:
			_remote_spawn.rpc_id(peer_id, newcomer, feet, yaw)
	_spawn_player(newcomer, feet, yaw)
	_entry_spot.rpc_id(newcomer, feet, yaw)
	_entry_sent.rpc_id(newcomer)


## The newcomer: where the host put its player, for when play starts here (_set_mode_locally).
@rpc("authority", "reliable")
func _entry_spot(feet: Vector3, yaw: float) -> void:
	_entry_at = [feet, yaw]


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
