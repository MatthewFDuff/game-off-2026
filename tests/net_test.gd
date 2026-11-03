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
## Live reload: the host reads props from a scratch copy of the library, rewrites the fridge as
## solid lamp once the client is in, and both sides must see the lamp fridge (the client only
## through the host's edits). Then the host saves a broken file, which must change nothing.
##
## Enemies: the host spawns one before the client joins (it must reach the client with the roster)
## and two after. They're frozen in place so both sides can hash their ids and positions. The
## client shoots one by request_hit, the host kills another itself, and both must end with the
## same single enemy.
##
## Weapons and pickups: the client fires an explosive at a wall away from the enemies (the host's
## copy of its player must show the ammo it loaded, and the blast must reach both worlds, which
## the world hashes check), and the host walks into a pickup, which must disappear on the client.
##
## Game types (Lab, Player) are left untyped here: naming them would compile those scripts before
## the autoloads they use are registered.

## Default port; tools/net_test.sh passes a random one (--port=) so parallel runs don't collide.
const PORT := 24699
const CLIENT_SPOT := Vector3(0.0, 0.0, 2.0) # Offset from the level spawn.
const SCRATCH_PROPS := "user://net_test_props/"
## The break room fridge's box (voxel space).
const FRIDGE_FROM := Vector3i(113, 40, 216)
const FRIDGE_TO := Vector3i(120, 59, 224)
const LAMP := 21

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
	_copy_props()
	Props.library_dir = SCRATCH_PROPS
	root.get_node("VoxWatch").watch(SCRATCH_PROPS)
	_check("host starts", net.host(_port) == OK)
	var lab = await _wait_for_lab()
	if lab == null:
		return
	var spawn: Vector3 = lab.spawn_point(0)
	lab.world_sync.carve_sphere(spawn + Vector3(3.0, 0.0, 0.0), 1.0, 254)
	var first = _spawn_frozen(lab, spawn + Vector3(1.5, 0.0, 4.0))
	_check("host spawns an enemy", first != null)
	var first_id: int = first.id if first else -1
	print("READY") # The driver starts the client now.

	# Generous: a cold Godot start alone can take half a minute on Windows.
	if not await _wait_until(func() -> bool: return lab.players.size() == 2, 120.0):
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
	var second_id: int = _spawn_frozen(lab, spawn + Vector3(-1.5, 0.0, 4.0)).id
	var third_id: int = _spawn_frozen(lab, spawn + Vector3(0.0, 0.0, 5.5)).id # The client shoots this one.

	_write_lamp_fridge()
	var swapped := await _wait_until(func() -> bool: return _count(lab.world, LAMP) > 500, 5.0)
	_check("edited prop reloads in place", swapped, "%d lamp voxels" % _count(lab.world, LAMP))
	FileAccess.open(SCRATCH_PROPS + "fridge.vox", FileAccess.WRITE).store_string("not a vox file")
	await _wait_seconds(1.5)
	_check("a broken save keeps the old prop", _count(lab.world, LAMP) > 500)

	var shot := await _wait_until(func() -> bool: return not lab.enemies.enemies.has(third_id), 20.0)
	_check("the client's hit kills on the host", shot)
	var second = lab.enemies.get_enemy(second_id)
	if second:
		lab.enemies.request_hit(second_id, 1000.0, second.get_center(), "rifle")
	_check("host kills one itself", lab.enemies.enemies.keys() == [first_id], str(lab.enemies.enemies.keys()))
	_check("the client's loaded ammo shows on its avatar", await _wait_until(func() -> bool: return avatar.weapon.current == "explosive", 10.0),
			avatar.weapon.current)

	# A pickup a little way off, then the host walks into it.
	var pickup = lab.items.spawn("ammo_shotgun", spawn + Vector3(0.0, 0.35, -1.2))
	_check("host spawns a pickup", pickup != null)
	await _wait_seconds(1.0)
	var host_player = lab.local_player()
	host_player.teleport(spawn + Vector3(0.0, 0.0, -1.2))
	var pickup_id: int = pickup.id if pickup else -1
	var taken := await _wait_until(func() -> bool: return not lab.items.pickups.has(pickup_id), 5.0)
	_check("host takes the pickup", taken and host_player.inventory.count("shotgun") == 12, str(host_player.inventory.ammo))

	await _wait_seconds(1.5)
	print("HASH ", _world_hash(lab.world))
	print("HASH ", _enemy_hash(lab))
	print("HASH ", _item_hash(lab))
	await _wait_seconds(5.0) # Stay up until the client has hashed too.


func _client(net: Node) -> void:
	net.player_name = "Zack"
	_check("client connects", net.join("127.0.0.1", _port) == OK)
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
	me.teleport(lab.spawn_point(0) + CLIENT_SPOT)
	lab.world_sync.carve_sphere(lab.spawn_point(0) + Vector3(0.0, 0.0, -3.0), 1.0, 254)
	await _fire_explosive(lab, me)
	var swapped := await _wait_until(func() -> bool: return _count(lab.world, LAMP) > 500, 10.0)
	_check("host's prop reload reaches the client", swapped, "%d lamp voxels" % _count(lab.world, LAMP))

	var enemies = lab.enemies
	var seen := await _wait_until(func() -> bool: return enemies.enemies.size() == 3, 20.0)
	_check("client sees the host's enemies, including one from before it joined", seen and enemies.enemies.keys().has(1), str(enemies.enemies.keys()))
	if seen:
		var target = enemies.enemies[enemies.enemies.keys().max()]
		_check("client enemies are drawn, not simulated", not enemies.simulating and target._mesh != null)
		enemies.request_hit(target.id, 1000.0, target.get_center(), "rifle")
	var down_to_one := await _wait_until(func() -> bool: return enemies.enemies.size() == 1, 20.0)
	_check("deaths reach the client", down_to_one, str(enemies.enemies.keys()))
	var pickup_id := [-1]
	var appeared := await _wait_until(func() -> bool:
		for pickup in lab.items.pickups.values():
			if pickup.item == "ammo_shotgun":
				pickup_id[0] = pickup.id
				return true
		return false, 20.0)
	_check("the host's pickup appears on the client", appeared)
	var gone := await _wait_until(func() -> bool: return not lab.items.pickups.has(pickup_id[0]), 10.0)
	_check("a pickup taken on the host disappears on the client", appeared and gone)
	_check("the client didn't get the host's pickup", me.inventory.count("shotgun") == 0)
	await _wait_seconds(1.5)
	print("HASH ", _world_hash(lab.world))
	print("HASH ", _enemy_hash(lab))
	print("HASH ", _item_hash(lab))
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


## Host: an enemy standing on the floor under at that never moves or attacks, so both sides can
## compare where it is.
func _spawn_frozen(lab, at: Vector3):
	var down: Dictionary = lab.world.raycast(at + Vector3.UP, Vector3.DOWN, 4.0)
	var enemy = lab.enemies.spawn("basic", down.position if down.hit else at)
	if enemy:
		enemy.speed = 0.0
		enemy.attack_range = 0.0
		enemy.damage = 0.0
	return enemy


## Client: fires an explosive at the nearest wall that's well away from the enemies (they stand on
## the +Z side of the spawn) and waits for its blast to come back through the host.
func _fire_explosive(lab, me) -> void:
	var eye: Vector3 = me.camera.global_position
	var enemies_at: Vector3 = lab.spawn_point(0) + Vector3(0.0, 0.0, 4.5)
	var best := Vector3.ZERO
	var best_distance := INF
	for i in 16:
		var direction := Vector3.FORWARD.rotated(Vector3.UP, i * TAU / 16.0)
		var wall: Dictionary = lab.world.raycast(eye, direction, 15.0)
		if wall.hit and wall.distance > 2.5 and wall.position.distance_to(enemies_at) > 6.0 and wall.distance < best_distance:
			best = direction
			best_distance = wall.distance
	_check("found a wall to shoot", best != Vector3.ZERO)
	if best == Vector3.ZERO:
		return
	var impacts := []
	me.weapon.projectile_spawned.connect(func(shot) -> void:
		shot.impacted.connect(func(_shot, at: Vector3, _normal: Vector3, _enemy) -> void: impacts.append(at)))
	var blasts := []
	lab.world_sync.carved.connect(func(at: Vector3, _normal: Vector3, removed: Dictionary) -> void: blasts.append([at, removed]))
	me.inventory.add("ammo_explosive")
	_check("client loads explosive", me.weapon.select("explosive"))
	me.weapon._cooldown = 0.0
	_check("client fires an explosive", me.weapon.fire(best))
	var blasted := await _wait_until(func() -> bool:
		for blast: Array in blasts:
			if not impacts.is_empty() and blast[0].distance_to(impacts[0]) < 0.5:
				return true
		return false, 10.0)
	_check("the client's explosive carves the wall through the host", blasted, "%d impacts, %d carves" % [impacts.size(), blasts.size()])


## Pickup ids and items, sorted.
func _item_hash(lab) -> String:
	var ids: Array = lab.items.pickups.keys()
	ids.sort()
	return "items " + " ".join(ids.map(func(id: int) -> String: return "%d:%s" % [id, lab.items.pickups[id].item]))


## Enemy ids and positions, sorted, as text (so the driver compares them like the world hashes).
func _enemy_hash(lab) -> String:
	var ids: Array = lab.enemies.enemies.keys()
	ids.sort()
	var parts: Array[String] = []
	for id: int in ids:
		var feet: Vector3 = lab.enemies.enemies[id].global_position
		parts.append("%d@%.2f,%.2f,%.2f" % [id, feet.x, feet.y, feet.z])
	return "enemies " + " ".join(parts)


func _copy_props() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCRATCH_PROPS))
	for file in DirAccess.get_files_at(Props.LIBRARY_DIR):
		if file.get_extension() == "vox":
			FileAccess.open(SCRATCH_PROPS + file, FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(Props.LIBRARY_DIR + file))


func _write_lamp_fridge() -> void:
	var model := VoxFile.load_model(SCRATCH_PROPS + "fridge.vox")
	var voxels: PackedByteArray = model.voxels
	for i in voxels.size():
		if voxels[i] != 0:
			voxels[i] = LAMP
	VoxFile.save_model(SCRATCH_PROPS + "fridge.vox", model)


func _count(world, material: int) -> int:
	var n := 0
	for y in range(FRIDGE_FROM.y, FRIDGE_TO.y):
		for z in range(FRIDGE_FROM.z, FRIDGE_TO.z):
			for x in range(FRIDGE_FROM.x, FRIDGE_TO.x):
				n += int(world.get_voxel(Vector3i(x, y, z)) == material)
	return n


func _wait_for_lab():
	if not await _wait_until(func() -> bool: return current_scene != null and current_scene.name == "Lab", 60.0):
		_check("level loaded", false, "t=%d scene=%s" % [Time.get_ticks_msec(), current_scene])
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
