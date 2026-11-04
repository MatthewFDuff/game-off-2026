extends SceneTree
## One side of a two-process co-op test (tools/net_test.sh coop_audit_net_test):
##   godot --headless --path . --script res://tests/coop_audit_net_test.gd -- --role=host
##   godot --headless --path . --script res://tests/coop_audit_net_test.gd -- --role=client
##
## Late joiners and the movement stream:
## - the host loads explosive ammo before the client joins; the client's copy of the host must show
##   it (Weapon tells peers that join later what is loaded, not only on a change);
## - while the client is spawned on the host but hasn't confirmed its entry, enemies don't target
##   it (EnemyManager.targets keeps to peers_in_level);
## - the client teleports 12 m (a respawn at the vat, say); the host's copy must jump there, never
##   be drawn sliding through the space between (Player._net_state snaps on a teleport).
##
## Game types are left untyped here (see net_test.gd).

const PORT := 24697
## Where the client hovers first (in the air, so its avatar can't seem settled there before it
## teleports in), and how far it jumps from there.
const CLIENT_SPOT := Vector3(0.0, 3.0, 2.0)
const JUMP := Vector3(0.0, 12.0, 0.0)

var _failures := 0
var _port := PORT


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var role := "host"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		elif arg.begins_with("--port="):
			_port = int(arg.trim_prefix("--port="))
	var net: Node = root.get_node("Net")
	if role == "host":
		await _host(net)
	else:
		await _client(net)
	print("%s: %s" % [role.to_upper(), "PASS" if _failures == 0 else "FAIL (%d)" % _failures])
	quit(1 if _failures > 0 else 0)


func _host(net: Node) -> void:
	net.player_name = "Host"
	_check("host starts", net.host(_port) == OK)
	var lab = await _wait_for_lab()
	if lab == null:
		return
	await _wait_seconds(0.5)
	var me = lab.local_player()
	_check("host gets explosive ammo", me.inventory.add("ammo_explosive"))
	_check("host loads explosive", me.weapon.select("explosive"))
	print("READY")

	if not await _wait_until(func() -> bool: return lab.players.size() == 2, 120.0):
		_check("client spawned on the host", false)
		return
	var client_id: int = lab.players.keys().filter(func(id: int) -> bool: return id != 1)[0]
	var avatar = lab.players[client_id]
	var targeted_early := [false]
	var entered := await _wait_until(func() -> bool:
		if client_id not in lab.peers_in_level and avatar in lab.enemies.targets():
			targeted_early[0] = true
		return client_id in lab.peers_in_level, 60.0)
	_check("client confirmed entry", entered)
	_check("enemies don't target a player still entering", not targeted_early[0])
	_check("enemies target the client once it's in", avatar in lab.enemies.targets())

	var start: Vector3 = lab.spawn_point(0) + CLIENT_SPOT
	var settled := await _wait_until(func() -> bool: return avatar.global_position.distance_to(start) < 0.3, 20.0)
	_check("client avatar settles at its spot", settled, str(avatar.global_position))
	var between := [0]
	var jumped := await _wait_until(func() -> bool:
		var at: Vector3 = avatar.global_position
		if at.distance_to(start) > 0.5 and at.distance_to(start + JUMP) > 0.5:
			between[0] += 1
		return at.distance_to(start + JUMP) < 0.3, 20.0)
	_check("client avatar follows the teleport", jumped, str(avatar.global_position))
	_check("the teleport snaps, no slide through the gap", between[0] == 0, "%d frames in between" % between[0])
	await _wait_seconds(1.0)
	print("HASH coop_audit")


func _client(net: Node) -> void:
	net.player_name = "Zack"
	_check("client connects", net.join("127.0.0.1", _port) == OK)
	var lab = await _wait_for_lab()
	if lab == null:
		return
	if not await _wait_until(func() -> bool: return lab.local_player() != null and lab.players.has(1), 60.0):
		_check("players spawned", false)
		return
	var me = lab.local_player()
	var streaming := await _wait_until(func() -> bool: return me.net_peers == [1], 30.0)
	_check("sends state to the host", streaming, str(me.net_peers))
	var host_avatar = lab.players[1]
	var ammo := await _wait_until(func() -> bool: return host_avatar.weapon.current == "explosive", 10.0)
	_check("a late joiner sees the host's loaded ammo", ammo, host_avatar.weapon.current)
	me.flying = true # Hovers in place: nothing but the teleports moves it.
	me.velocity = Vector3.ZERO
	var start: Vector3 = lab.spawn_point(0) + CLIENT_SPOT
	me.teleport(start)
	await _wait_seconds(2.0)
	me.teleport(start + JUMP)
	await _wait_seconds(3.0)
	print("HASH coop_audit")


func _wait_for_lab():
	if not await _wait_until(func() -> bool: return current_scene != null and current_scene.name == "Lab", 60.0):
		_check("level loaded", false, "t=%d scene=%s" % [Time.get_ticks_msec(), current_scene])
		return null
	return current_scene


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await process_frame
	return true


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
