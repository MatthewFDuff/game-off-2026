extends Node
## Session autoload: hosting, joining and the player roster. The host is peer 1 and owns the
## world, enemies and story state; each peer owns its own player's movement.
##
## A session is a level and a mode: "play", or "edit" (the co-op level editor). The host picks
## both; joiners get them when accepted.
##
## The cubicle (MENU_SCENE) opens sessions "staged" (open_session): the server runs and joiners are
## accepted while everyone stays in their own cubicle, and nobody loads the level scene until
## enter_level. The host enters first and announces the level open once its Lab exists (a peer
## entering asks the host's Lab for the world); a peer's enter_level waits for that. host(),
## start_solo() and the launch flags load the level at once, as before.
##
## After a shift, Ending leaves the statement in pending_statement / pending_total for the cubicle
## to roll.
##
## Command-line shortcuts skip the menu (pass them after `--`):
##   --solo            single-player
##   --host[=port]     host a co-op session
##   --join=addr[:port]
##   --edit            with --solo / --host: open the level editor instead of playing
##   --level=lab       which level (default lab)
##   --name=Zack

signal players_changed
## The session is ready to load the level (hosting, solo, or the host accepted our join).
signal session_started
## Joining failed or the connection dropped. reason is player-facing text.
signal session_ended(reason: String)
## The host has loaded the level of a staged session; peers may enter.
signal level_opened

const DEFAULT_PORT := 24680
const MAX_PLAYERS := 4
const LEVEL_SCENE := "res://scenes/lab.tscn"
const MENU_SCENE := "res://scenes/cubicle.tscn"
const DEFAULT_LEVEL := "lab"
const COLORS := [Color(0.95, 0.55, 0.2), Color(0.3, 0.65, 0.95), Color(0.45, 0.85, 0.4), Color(0.9, 0.4, 0.75)]

var player_name := "Expendable"
## peer id -> {name: String, color: Color}
var players := {}
var in_session := false
## {level: String, mode: "play" or "edit"}, plus shift (a story shift begun from the cubicle: the
## host saves it) and resume (the host restores the save when the level loads).
var session := {level = DEFAULT_LEVEL, mode = "play"}
## Why the last session ended, for the menu to show after it loads. Cleared once shown.
var end_reason := ""
## Whether the host has loaded the level (peers may enter).
var level_open := false
## The payroll statement to roll in the cubicle after a shift ("left|right" lines); [] when none.
var pending_statement: Array = []
var pending_total := 0
## This process has loaded the level scene for the current session.
var _entered := false
## A peer asked to enter before the level was open: it enters when the host announces it.
var _enter_when_open := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_handle_command_line.call_deferred()


## ENet isn't available in web builds, which are single-player.
static func can_network() -> bool:
	return not OS.has_feature("web")


func is_host() -> bool:
	return multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id()


## Single-player: loads the level at once. extra is merged into session (shift, resume; see
## docs/shift-save.md).
func start_solo(level := DEFAULT_LEVEL, mode := "play", extra := {}) -> void:
	_reset()
	session = {level = level, mode = mode}
	session.merge(extra, true)
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_add_player(1, player_name)
	_begin()


func host(port := DEFAULT_PORT, level := DEFAULT_LEVEL, mode := "play") -> Error:
	_reset()
	session = {level = level, mode = mode}
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	_add_player(1, player_name)
	_begin()
	return OK


## Host: opens a session (server, roster) without loading the level; the host stays in the cubicle.
## Joiners are accepted with the session marked staged, and stay in theirs until enter_level. extra
## is merged into session (shift, resume) and reaches joiners with it.
func open_session(port := DEFAULT_PORT, level := "waiting_room", mode := "play", extra := {}) -> Error:
	_reset()
	session = {level = level, mode = mode, staged = true, level_open = false}
	session.merge(extra, true)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	_add_player(1, player_name)
	in_session = true
	players_changed.emit()
	session_started.emit()
	return OK


## Host: closes a session opened with open_session; no scene change. Connected peers get
## session_ended("The host closed the shift.") from the dropped connection.
func close_session() -> void:
	_reset()
	session = {level = DEFAULT_LEVEL, mode = "play"}
	players_changed.emit()


## Host: loads the level scene and, once its Lab exists, announces it to every peer. Peer: loads
## the level scene now if the host's is open, else as soon as level_opened fires.
func enter_level() -> void:
	if not in_session or _entered:
		return
	if is_host():
		_entered = true
		get_tree().change_scene_to_file(LEVEL_SCENE)
		# Two frames: the new scene is in the tree and its Lab has run _ready.
		await get_tree().process_frame
		await get_tree().process_frame
		if not in_session:
			return
		_on_level_open()
		_level_open.rpc()
	elif level_open:
		_enter_now()
	else:
		_enter_when_open = true


## Connects to a host. session_started fires once the host accepts us, session_ended if it fails.
func join(address: String, port := DEFAULT_PORT) -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	return OK


## Host: moves the whole session to another level (the waiting room admitting the party to the
## laboratory). The host reloads the level scene first, so its Lab exists by the time the peers
## reload theirs and ask to enter; they then get the new level as a late joiner would.
func change_level(level_name: String) -> void:
	if not is_host() or not in_session:
		return
	session = session.duplicate()
	session.level = level_name
	# Peers stop streaming into the old level first: the host's load can take seconds, and every
	# packet for a player the new level hasn't spawned yet is an error. A frame sends it.
	_level_closing.rpc()
	await get_tree().process_frame
	if not in_session:
		return
	get_tree().change_scene_to_file(LEVEL_SCENE)
	await get_tree().process_frame
	await get_tree().process_frame
	_level_changed.rpc(session)


@rpc("authority", "reliable")
func _level_closing() -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_method("stop_streaming"):
		scene.stop_streaming()


@rpc("authority", "reliable")
func _level_changed(host_session: Dictionary) -> void:
	session = host_session
	# A staged peer still in its cubicle enters the new level when it enters.
	if session.get("staged", false) and not _entered:
		return
	get_tree().change_scene_to_file(LEVEL_SCENE)


## Host and peers: the staged session's level is open.
@rpc("authority", "reliable")
func _level_open() -> void:
	_on_level_open()


func _on_level_open() -> void:
	level_open = true
	session.level_open = true
	level_opened.emit()
	if _enter_when_open:
		_enter_now()


func _enter_now() -> void:
	_enter_when_open = false
	_entered = true
	get_tree().change_scene_to_file(LEVEL_SCENE)


## Leaves the session and returns to the menu (staying put if already there: a staged session
## left from the cubicle).
func leave(reason := "") -> void:
	_reset()
	end_reason = reason
	session_ended.emit(reason)
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != MENU_SCENE:
		get_tree().change_scene_to_file(MENU_SCENE)


func player_color(peer_id: int) -> Color:
	return players[peer_id].color if players.has(peer_id) else Color.WHITE


func _reset() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	in_session = false
	level_open = false
	_entered = false
	_enter_when_open = false


func _begin() -> void:
	in_session = true
	_entered = true
	players_changed.emit()
	session_started.emit()
	get_tree().change_scene_to_file(LEVEL_SCENE)


func _add_player(peer_id: int, display_name: String) -> void:
	var used := players.values().map(func(p: Dictionary) -> Color: return p.color)
	var color: Color = COLORS[0]
	for candidate in COLORS:
		if candidate not in used:
			color = candidate
			break
	players[peer_id] = {name = display_name.strip_edges().left(20), color = color}


func _on_peer_connected(_peer_id: int) -> void:
	pass # Peers register themselves once connected; see _register.


func _on_peer_disconnected(peer_id: int) -> void:
	if is_host() and players.erase(peer_id):
		_sync_players.rpc(players)
		players_changed.emit()


func _on_connected_to_server() -> void:
	_register.rpc_id(1, player_name)


func _on_connection_failed() -> void:
	_reset()
	session_ended.emit("Couldn't reach the host.")


func _on_server_disconnected() -> void:
	# In the lab this goes back to the cubicle; a staged peer still in its cubicle stays there.
	leave("The host closed the shift.")


@rpc("any_peer", "reliable")
func _register(display_name: String) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	_add_player(sender, display_name if display_name.strip_edges() != "" else "Expendable %d" % players.size())
	_accepted.rpc_id(sender, session)
	_sync_players.rpc(players)
	players_changed.emit()


@rpc("authority", "reliable")
func _accepted(host_session: Dictionary) -> void:
	session = host_session
	if not session.get("staged", false):
		_begin()
		return
	# Staged: in the session, still in the cubicle until enter_level (at once if the level is open).
	in_session = true
	level_open = session.get("level_open", false)
	players_changed.emit()
	session_started.emit()


@rpc("authority", "reliable")
func _sync_players(roster: Dictionary) -> void:
	players = roster
	players_changed.emit()


func _handle_command_line() -> void:
	var args := OS.get_cmdline_user_args()
	var level := DEFAULT_LEVEL
	var mode := "edit" if "--edit" in args else "play"
	for arg in args:
		if arg.begins_with("--name="):
			player_name = arg.trim_prefix("--name=")
		elif arg.begins_with("--level="):
			level = arg.trim_prefix("--level=")
	for arg in args:
		if arg == "--solo":
			start_solo(level, mode)
		elif arg == "--host" or arg.begins_with("--host="):
			var port := int(arg.trim_prefix("--host=")) if "=" in arg else DEFAULT_PORT
			host(port, level, mode)
		elif arg.begins_with("--join="):
			var target := arg.trim_prefix("--join=")
			var port := DEFAULT_PORT
			if ":" in target:
				port = int(target.get_slice(":", 1))
				target = target.get_slice(":", 0)
			join(target, port)
