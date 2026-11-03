extends SceneTree
## One side of the two-process co-op test; tools/net_test.sh runs both and compares their output.
##   godot --headless --path . --script res://tests/net_test.gd -- --role=host
##   godot --headless --path . --script res://tests/net_test.gd -- --role=client
##
## The host carves a crater before the client joins (so it reaches the client through the
## snapshot), then each side carves once more after the join, the host directly and the client by
## request. Both print a hash of their whole world at the end, which must match. The host also
## checks the client's player shows up where the client put it.
##
## Game types (Lab, Player) are left untyped here: naming them would compile those scripts before
## the autoloads they use are registered.

const PORT := 24699
const CLIENT_SPOT := Vector3(0.0, 0.0, 2.0) # Offset from the level spawn.

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var role := "host"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
	var net: Node = root.get_node("Net")
	if role == "host":
		await _host(net)
	else:
		await _client(net)
	print("%s: %s" % [role.to_upper(), "PASS" if _failures == 0 else "FAIL (%d)" % _failures])
	quit(1 if _failures > 0 else 0)


func _host(net: Node) -> void:
	net.player_name = "Host"
	_check("host starts", net.host(PORT) == OK)
	var lab = await _wait_for_lab()
	if lab == null:
		return
	var spawn: Vector3 = lab.info.spawn
	lab.world_sync.carve_sphere(spawn + Vector3(3.0, 0.0, 0.0), 1.0, 254)
	print("READY") # The driver starts the client now.

	if not await _wait_until(func() -> bool: return lab.players.size() == 2, 30.0):
		_check("client entered the level", false)
		return
	var client_id: int = lab.players.keys().filter(func(id: int) -> bool: return id != 1)[0]
	_check("client is on the roster", net.players.has(client_id) and net.players[client_id].name == "Zack", str(net.players))
	await _wait_seconds(0.5)
	lab.world_sync.carve_sphere(spawn + Vector3(-3.0, 0.0, 0.0), 1.0, 254)
	var avatar = lab.players[client_id]
	_check("client avatar is remote", not avatar.is_local)
	var follows := await _wait_until(func() -> bool: return avatar.global_position.distance_to(spawn + CLIENT_SPOT) < 0.5, 10.0)
	_check("client avatar follows the client", follows, str(avatar.global_position))
	_check("client confirmed entry", client_id in lab.peers_in_level)
	await _wait_seconds(1.0)
	print("HASH ", _world_hash(lab.world))
	await _wait_seconds(5.0) # Stay up until the client has hashed too.


func _client(net: Node) -> void:
	net.player_name = "Zack"
	_check("client connects", net.join("127.0.0.1", PORT) == OK)
	var lab = await _wait_for_lab()
	if lab == null:
		return
	if not await _wait_until(func() -> bool: return lab.local_player() != null, 30.0):
		_check("local player spawned", false)
		return
	var me = lab.local_player()
	_check("local player is local", me.is_local)
	_check("host avatar spawned", lab.players.has(1) and not lab.players[1].is_local)
	var streaming := await _wait_until(func() -> bool: return me.net_peers == [1], 10.0)
	_check("sends state to the host", streaming, str(me.net_peers))
	me.teleport(lab.info.spawn + CLIENT_SPOT)
	lab.world_sync.carve_sphere(lab.info.spawn + Vector3(0.0, 0.0, -3.0), 1.0, 254)
	await _wait_seconds(4.0)
	print("HASH ", _world_hash(lab.world))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			await _screenshot(lab, me, arg.trim_prefix("--shot="))


## Windowed runs only: turns to face the host's player and saves what the client sees.
func _screenshot(lab, me, path: String) -> void:
	var host_avatar = lab.players[1]
	var to_host: Vector3 = host_avatar.global_position - me.global_position
	me.rotation.y = atan2(-to_host.x, -to_host.z)
	me.head.rotation.x = -0.1
	await _wait_seconds(0.5)
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


func _wait_for_lab():
	if not await _wait_until(func() -> bool: return current_scene != null and current_scene.name == "Lab", 30.0):
		_check("level loaded", false)
		return null
	return current_scene


func _world_hash(world) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(world.get_data())
	return context.finish().hex_encode()


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
