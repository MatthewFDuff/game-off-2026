extends Node
## Session autoload: hosting, joining and the player roster. The host is peer 1 and owns the
## world, enemies and story state; each peer owns its own player's movement.
##
## A session is a level and a mode: "play", or "edit" (the co-op level editor). The host picks
## both; joiners get them when accepted.
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

const DEFAULT_PORT := 24680
const MAX_PLAYERS := 4
const LEVEL_SCENE := "res://scenes/lab.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const DEFAULT_LEVEL := "lab"
const COLORS := [Color(0.95, 0.55, 0.2), Color(0.3, 0.65, 0.95), Color(0.45, 0.85, 0.4), Color(0.9, 0.4, 0.75)]

var player_name := "Expendable"
## peer id -> {name: String, color: Color}
var players := {}
var in_session := false
## {level: String, mode: "play" or "edit"}
var session := {level = DEFAULT_LEVEL, mode = "play"}
## Why the last session ended, for the menu to show after it loads. Cleared once shown.
var end_reason := ""


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


func start_solo(level := DEFAULT_LEVEL, mode := "play") -> void:
	_reset()
	session = {level = level, mode = mode}
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


## Connects to a host. session_started fires once the host accepts us, session_ended if it fails.
func join(address: String, port := DEFAULT_PORT) -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	return OK


## Leaves the session and returns to the menu.
func leave(reason := "") -> void:
	_reset()
	end_reason = reason
	session_ended.emit(reason)
	get_tree().change_scene_to_file(MENU_SCENE)


func player_color(peer_id: int) -> Color:
	return players[peer_id].color if players.has(peer_id) else Color.WHITE


func _reset() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	in_session = false


func _begin() -> void:
	in_session = true
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
	leave("The host closed the session.")


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
	_begin()


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
