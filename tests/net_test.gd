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
## Interactables: the client opens the break room fridge (a container the host filled), both must
## see it opened and its pickups, then the host switches to backup power, which the client follows.
##
## Statuses and clouds: the host throws a fire flask (the client must see a fire cloud, drawn only)
## and freezes the last enemy (the client must tint it); both hash the shown statuses once the
## cloud has burned out.
##
## Fire: the host builds a wooden crate where the flask landed; the fire spreads through it in
## WorldSync.set_voxels batches, the client must see it burning, and the world hashes are taken
## once it has burned out on both.
##
## Falling piece: the host builds a concrete block on a thin steel post before the client joins
## (it reaches the client in the snapshot); the client's shot cuts the post, the client must draw
## the block falling and see it land as voxels (the host's stamp), and the world hashes check both
## worlds have it in the same place.
##
## Party arming (after the finale): the client disarms itself as in a `start_unarmed` level, the
## host walks into a spore shooter, and the client must be armed by it (LevelPlay.arm_party); a
## second one changes nothing. Then the client drops its gun and the party flag again, as a late
## joiner entering unarmed would, and the host's entry state (_full_state) must arm it.
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
## The falling piece's post, offset from the level spawn (meters); VoxelMaterials ids.
const PIECE_SPOT := Vector3(1.5, 0.0, -0.6)
const CONCRETE := 3
const STEEL := 17

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
	var fridge_id := _fridge_id(lab)
	_check("the break room fridge is a container", lab.level.objects.get(fridge_id, {}).get("use") == "container")
	if fridge_id != "":
		lab.level.objects[fridge_id].contents = "flask_fire,ammo_homing" # The client opens it.
	_build_piece(lab)
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

	# Interactables: the client opens the fridge; then the host cuts the power.
	var opened := await _wait_until(func() -> bool: return lab.play.state_of(fridge_id).used, 30.0)
	_check("the client's use opens the container on the host", opened)
	_check("the host drops its contents", _items_named(lab, ["flask_fire", "ammo_homing"]) == 2)
	lab.play.set_power("backup")
	_check("host sets backup power", lab.play.power == "backup")

	# Statuses and clouds: the host throws a fire flask away from everyone and freezes the enemy
	# that's left; the client must see the cloud and the tint. The cloud must burn out before the
	# worlds are hashed (it burns shroom voxels through WorldSync while it lasts).
	await _throw_fire_flask(lab, host_player, spawn)
	_crate_under_fire(lab)
	lab.enemies.request_status(first_id, "frozen", 30.0)
	var burned_out := await _wait_until(func() -> bool: return lab.enemies.clouds.is_empty(), 15.0)
	_check("the host's fire cloud burns out", burned_out)
	var fire_out := await _wait_until(func() -> bool: return lab.fire.burning.is_empty(), 60.0)
	_check("the host's fire burns out", fire_out, "%d burning" % lab.fire.burning.size())

	await _wait_seconds(1.5)
	print("HASH ", _world_hash(lab.world))
	print("HASH ", _enemy_hash(lab))
	print("HASH ", _item_hash(lab))
	print("HASH ", _interact_hash(lab))
	print("HASH ", _status_hash(lab))
	await _wait_seconds(3.0) # Stay up until the client has hashed too.

	# Finale: a short one; the client counts it down too (after the hashes: it changes power).
	var survived := [false]
	lab.director.finale_survived.connect(func() -> void: survived[0] = true)
	lab.director.finale(3.0)
	_check("host starts the finale", lab.director.finale_active and lab.play.power == "restored")
	var ended := await _wait_until(func() -> bool: return survived[0], 10.0)
	_check("host finale ends in survival", ended and not lab.director.finale_active)
	await _host_arming(lab, client_id)
	await _wait_seconds(2.0)


## Host: the party-arming checks (see the top).
func _host_arming(lab, client_id: int) -> void:
	var avatar = lab.players[client_id]
	var disarmed := await _wait_until(func() -> bool: return not avatar.has_weapon, 30.0)
	_check("the client starts unarmed", disarmed)
	lab.level.settings.start_unarmed = true
	_check("the party isn't armed yet", not lab.play.armed)
	var me = lab.local_player()
	lab.items.spawn("spore_shooter", me.global_position + Vector3.UP * 0.4)
	var armed := await _wait_until(func() -> bool: return lab.play.armed, 5.0)
	_check("the host's spore shooter pickup arms the party", armed and me.has_weapon)
	var client_armed := await _wait_until(func() -> bool: return avatar.has_weapon, 10.0)
	_check("the client's player is armed by the host's pickup", client_armed)
	lab.items.spawn("spore_shooter", me.global_position + Vector3.UP * 0.4)
	await _wait_seconds(1.0)
	_check("a second spore shooter is harmless", lab.play.armed and me.has_weapon and avatar.has_weapon)
	# The client drops its gun as a late joiner would enter; its entry state must arm it.
	var dropped := await _wait_until(func() -> bool: return not avatar.has_weapon, 20.0)
	_check("the client drops its gun (as a late joiner)", dropped)
	lab.play._send_state(client_id)
	var rearmed := await _wait_until(func() -> bool: return is_instance_valid(avatar) and avatar.has_weapon, 10.0)
	_check("the entry state arms a late joiner", rearmed)


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
	var finale_events := []
	var finale_samples := []
	lab.director.finale_event.connect(func(kind: String) -> void:
		finale_events.append(kind)
		finale_samples.append(lab.director.finale_left))
	_check("local player is local", me.is_local)
	_check("host avatar spawned", lab.players.has(1) and not lab.players[1].is_local)
	var streaming := await _wait_until(func() -> bool: return me.net_peers == [1], 10.0)
	_check("sends state to the host", streaming, str(me.net_peers))
	me.teleport(lab.spawn_point(0) + CLIENT_SPOT)
	lab.world_sync.carve_sphere(lab.spawn_point(0) + Vector3(0.0, 0.0, -3.0), 1.0, 254)
	await _drop_piece(lab)
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

	# Interactables: open the fridge by request; the host's power cut must reach us.
	var fridge_id := _fridge_id(lab)
	await _stand_by(lab, me, fridge_id)
	lab.play.request_use(fridge_id)
	var opened := await _wait_until(func() -> bool: return lab.play.state_of(fridge_id).used, 10.0)
	_check("the client sees the container opened", opened)
	var dropped := await _wait_until(func() -> bool: return _items_named(lab, ["flask_fire", "ammo_homing"]) == 2, 10.0)
	_check("the client sees its contents", dropped)
	var cut := await _wait_until(func() -> bool: return lab.play.power == "backup", 20.0)
	_check("the host's power cut reaches the client", cut, lab.play.power)

	# Statuses and clouds: the host's fire flask shows up here as a fire cloud (drawn, not run), and
	# the enemy it freezes is tinted blue here too. Its fire spreads here in the host's batches.
	var most_burning := [0]
	lab.world_sync.voxels_set.connect(func(_points, _materials, _removed) -> void:
		most_burning[0] = maxi(most_burning[0], lab.fire.burning.size()))
	var fire_clouds := []
	for cloud in lab.enemies.clouds.values():
		fire_clouds.append(cloud)
	lab.enemies.cloud_spawned.connect(func(cloud) -> void: fire_clouds.append(cloud))
	var cloud_seen := await _wait_until(func() -> bool:
		return fire_clouds.any(func(cloud) -> bool: return is_instance_valid(cloud) and cloud.type == "fire" and not cloud.authoritative), 20.0)
	_check("the client sees the host's fire cloud", cloud_seen, str(fire_clouds))
	var tinted := await _wait_until(func() -> bool:
		var survivor = enemies.get_enemy(1)
		return survivor != null and "frozen" in survivor.shown_statuses and survivor.tint_material() != null \
				and survivor._mesh.material_overlay == survivor.tint_material(), 20.0)
	_check("the frozen enemy is tinted on the client", tinted)
	var burned_out := await _wait_until(func() -> bool: return lab.enemies.clouds.is_empty(), 15.0)
	_check("the fire cloud ends on the client", burned_out)
	var fire_out := await _wait_until(func() -> bool: return most_burning[0] > 0 and lab.fire.burning.is_empty(), 60.0)
	_check("the client sees the host's fire spread and burn out", fire_out and most_burning[0] > 20,
			"%d at most, %d left" % [most_burning[0], lab.fire.burning.size()])
	await _wait_seconds(1.5)
	print("HASH ", _world_hash(lab.world))
	print("HASH ", _enemy_hash(lab))
	print("HASH ", _item_hash(lab))
	print("HASH ", _interact_hash(lab))
	print("HASH ", _status_hash(lab))
	# Finale: the host's countdown shows up here and ends in the same outcome.
	var counting := await _wait_until(func() -> bool:
		if lab.director.finale_active:
			finale_samples.append(lab.director.finale_left)
		return "survived" in finale_events, 30.0)
	_check("the client sees the finale start and survive", counting and finale_events == ["started", "survived"], str(finale_events))
	_check("the client's countdown starts near the host's 3 s", finale_samples.size() > 1 and absf(finale_samples[0] - 3.0) < 0.5, str(finale_samples))
	_check("the client's countdown runs down", finale_samples.any(func(left: float) -> bool: return left < 2.0 and left > 0.0), str(finale_samples))
	_check("the client finale is over", not lab.director.finale_active)
	await _client_arming(lab, me)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			await _screenshot(lab, me, arg.trim_prefix("--shot="))


## Client: the party-arming checks (see the top).
func _client_arming(lab, me) -> void:
	lab.level.settings.start_unarmed = true
	lab.play._apply_armed()
	_check("the client is unarmed in a start_unarmed level", not me.has_weapon and not lab.play.armed)
	var armed := await _wait_until(func() -> bool: return lab.play.armed and me.has_weapon, 30.0)
	_check("the host's spore shooter pickup arms the client", armed)
	await _wait_seconds(3.0) # The host picks up a second one meanwhile.
	_check("the client stays armed after a second pickup", lab.play.armed and me.has_weapon)
	lab.play.armed = false
	me.set_armed(false)
	var rearmed := await _wait_until(func() -> bool: return lab.play.armed and me.has_weapon, 20.0)
	_check("the host's entry state (_full_state) carries armed", rearmed)
	await _wait_seconds(2.0) # Stay up until the host has seen us armed again.


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


## The falling piece's post: its bottom voxel, on the floor by the spawn.
func _piece_base(lab) -> Vector3i:
	return lab.world.world_to_voxel(lab.spawn_point(0) + PIECE_SPOT + Vector3.UP * 0.05)


## Host, before the client joins: a 6 x 5 x 6 concrete block on a 2 x 8 x 2 steel post.
func _build_piece(lab) -> void:
	var base := _piece_base(lab)
	var room: PackedByteArray = lab.world.get_box(base + Vector3i(-3, 0, -3), base + Vector3i(5, 14, 5))
	_check("room by the spawn for a falling piece", room.count(0) == room.size() and lab.world.get_voxel(base + Vector3i.DOWN) != 0,
			"%d solid" % (room.size() - room.count(0)))
	lab.world_sync.apply_op({type = "box", from = base, to = base + Vector3i(2, 8, 2), material = STEEL})
	lab.world_sync.apply_op({type = "box", from = base + Vector3i(-2, 8, -2), to = base + Vector3i(4, 13, 4), material = CONCRETE})


## Client: shoots the post's foot (a carve by request); the block must fall here (drawn) and land
## here as voxels, lower down.
func _drop_piece(lab) -> void:
	var base := _piece_base(lab)
	var area := [base + Vector3i(-2, -4, -2), base + Vector3i(4, 13, 4)]
	var before := _count_in(lab.world, area, CONCRETE)
	_check("the client has the host's block on its post", lab.world.get_voxel(base + Vector3i(0, 12, 0)) == CONCRETE
			and lab.world.get_voxel(base + Vector3i(0, 4, 0)) == STEEL)
	lab.world_sync.carve_sphere(lab.view.to_world(Vector3(base) + Vector3(1.0, 1.0, 1.0)), 0.18, 3, Vector3.UP)
	var drawn := [false]
	var landed := await _wait_until(func() -> bool:
		drawn[0] = drawn[0] or not lab.falling.meshes.is_empty()
		return drawn[0] and lab.falling.meshes.is_empty() and _count_in(lab.world, area, CONCRETE) == before \
				and lab.world.get_voxel(base + Vector3i(0, 12, 0)) != CONCRETE, 10.0)
	_check("the client's shot drops the block: drawn falling here, then voxels again lower down", landed,
			"drawn %s, %d of %d concrete" % [drawn[0], _count_in(lab.world, area, CONCRETE), before])


func _count_in(world, box: Array, material: int) -> int:
	var n := 0
	for y in range(box[0].y, box[1].y):
		for z in range(box[0].z, box[1].z):
			for x in range(box[0].x, box[1].x):
				n += int(world.get_voxel(Vector3i(x, y, z)) == material)
	return n


## Host: a wooden crate (through WorldSync, so the client gets it too) on the floor where the fire
## cloud landed, for it to set alight.
func _crate_under_fire(lab) -> void:
	var cloud = null
	for each in lab.enemies.clouds.values():
		if each.type == "fire":
			cloud = each
	if cloud == null:
		return
	var floor_hit: Dictionary = lab.world.raycast(cloud.global_position + Vector3.UP * 0.3, Vector3.DOWN, 3.0)
	var base: Vector3i = lab.world.world_to_voxel(floor_hit.position + Vector3.UP * 0.05) if floor_hit.hit else lab.world.world_to_voxel(cloud.global_position)
	lab.world_sync.apply_op({type = "box", from = base + Vector3i(-6, 0, -6), to = base + Vector3i(6, 8, 6), material = 16}) # VoxelMaterials.WOOD


## Host: throws a fire flask at the floor in the direction with the most room that leads away
## from the enemies and the client (they stand on the +Z side of the spawn).
func _throw_fire_flask(lab, me, spawn: Vector3) -> void:
	var eye: Vector3 = me.camera.global_position
	var others: Vector3 = spawn + Vector3(0.0, 0.0, 3.5)
	var best := Vector3.ZERO
	var best_score := -INF
	for i in 16:
		var direction := Vector3.FORWARD.rotated(Vector3.UP, i * TAU / 16.0)
		var wall: Dictionary = lab.world.raycast(eye, direction, 12.0)
		var reach: float = wall.distance if wall.hit else 12.0
		var landing: Vector3 = eye + direction * minf(reach, 8.0)
		if reach < 5.0 or landing.distance_to(others) < 7.0:
			continue
		var score: float = landing.distance_to(others)
		if score > best_score:
			best = direction
			best_score = score
	_check("found room to throw a flask", best != Vector3.ZERO)
	if best == Vector3.ZERO:
		return
	me.inventory.add("flask_fire")
	me.weapon._flask_cooldown = 0.0
	_check("host has a fire flask selected", me.weapon.flask == "fire", me.weapon.flask)
	_check("host throws a fire flask", me.weapon.throw_flask(best + Vector3.DOWN * 0.2))
	var landed := await _wait_until(func() -> bool:
		return lab.enemies.clouds.values().any(func(cloud) -> bool: return cloud.type == "fire"), 5.0)
	_check("the flask shatters into a fire cloud on the host", landed)


## Enemy ids and their shown statuses (the tints), sorted.
func _status_hash(lab) -> String:
	var ids: Array = lab.enemies.enemies.keys()
	ids.sort()
	return "statuses " + " ".join(ids.map(func(id: int) -> String: return "%d:%s" % [id, ",".join(lab.enemies.enemies[id].shown_statuses)]))


## The power state and the used props, sorted.
func _interact_hash(lab) -> String:
	var used: Array = lab.play.prop_state.keys().filter(func(id: String) -> bool: return lab.play.prop_state[id].used)
	used.sort()
	return "interact %s %s" % [lab.play.power, " ".join(used)]


## Moves the client's player next to a usable thing and waits for the host's copy to follow (the
## host only honours a use request from within reach).
func _stand_by(lab, me, id: String) -> void:
	var box: AABB = lab.play.box_of(id)
	var c := box.get_center()
	me.teleport(Vector3(c.x + box.size.x * 0.5 + 1.0, box.position.y + 0.1, c.z))
	await _wait_seconds(0.4)


## The break room fridge (the first fridge prop).
func _fridge_id(lab) -> String:
	var ids: Array = lab.level.objects.keys().filter(func(id: String) -> bool:
		return lab.level.objects[id].kind == "prop" and lab.level.objects[id].name == "fridge")
	ids.sort()
	return ids[0] if not ids.is_empty() else ""


## How many pickups there are of these items.
func _items_named(lab, items: Array) -> int:
	return lab.items.pickups.values().filter(func(p) -> bool: return p.item in items).size()


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
