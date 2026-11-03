extends SceneTree
## Headless smoke test that the committed laboratory (res://levels/laboratory) plays:
##   godot --headless --path . --script res://tests/laboratory_play_test.gd
## Starts it solo, checks the spawn is in the yard on facility power with every door registered,
## then teleports the local player along the story: dying before any checkpoint respawns at the
## player's own spawn; signing in unlocks the blast door and the stair seal closes it without a
## lock (after the outbreak it refuses "No power"); the training terminal's trigger puts the power
## on backup and unlocks grow room 0 (its shrooms wait for the pickup); the lobby vent spawner wakes once the case trigger fires; the
## blue keycard opens the lift; reaching a clone vat sets the checkpoint; dying on floor 0 and after
## each seal (the stairs, the airlock, the cage ladder's foot) respawns at the vat past the seal, on
## that floor, with the seal door still locked and the floors behind turned off; the generator
## starts the finale and the elevator door opens when it ends.
##
## Game types are left untyped (see editor_test.gd).

const Layout := preload("res://scripts/tools/lab_layout.gd")

var _failures := 0
var _lab
var _me
var _notes := []
var _fired := []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Net").start_solo("laboratory", "play")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	_lab = current_scene
	_me = _lab.local_player()
	var play = _lab.play
	var director = _lab.director
	director.scale_per_player = 0.0
	await _frames(20)
	_check("playing on facility power", _lab.mode == "play" and play.active and play.power == "facility", play.power)
	var yard: Dictionary = _lab.level.objects.yard
	var feet: Vector3 = (_me.global_position - _lab.world.global_position) / _lab.world.voxel_size
	_check("spawned in the yard", AABB(Vector3(yard.from), Vector3(yard.to - yard.from)).has_point(feet), str(feet))
	var doors := 0
	for object in _lab.level.objects.values():
		if LevelSchema.is_door(object):
			doors += 1
			if not play.is_door(object.id):
				_check("door %s registered" % object.id, false)
	_check("every door is registered (%d)" % doors, doors > 40)
	_check("the blast door is locked until someone signs in", play.door_refusal("d_g_blast") == "Locked", play.door_refusal("d_g_blast"))
	_check("grow room 0 starts locked", play.is_door_locked("d_0_grow"))
	_check("no enemies before the outbreak", _lab.enemies.get_child_count() == 0, str(_lab.enemies.get_child_count()))
	_check("the player starts unarmed", not _me.has_weapon and not _me.weapon.fire())
	var fired := _fired
	play.triggered.connect(func(id: String, _peer: int) -> void: fired.append(id))
	_lab.notice.connect(func(text: String) -> void: _notes.append(text))
	var me_id: int = _lab.multiplayer.get_unique_id()

	# No checkpoint yet: a clone is grown at the player's own spawn, never at some vat.
	await _die_and_respawn()
	_check("with no checkpoint the player respawns at their spawn", _in_room("yard") and play.checkpoint == "", str(_feet()))
	_check("the respawn toast counts the clone", "Clone #1 grown. Billed to you." in _notes, str(_notes))

	# Signing in unlocks the blast door; the stair seal closes it behind the party, unlocked.
	_teleport_to("gatehouse", 0.5, 0.5)
	await _frames(3)
	play._use("term_g_signin", me_id)
	var signed := await _wait_until(func() -> bool: return play.door_refusal("d_g_blast") == "", 2.0)
	_check("signing in unlocks the blast door", signed and "say_signin" in fired, play.door_refusal("d_g_blast"))
	play._use("d_g_blast", me_id)
	var blast_open := await _wait_until(func() -> bool: return play.is_door_open("d_g_blast"), 4.0)
	_check("the blast door opens once signed in", blast_open)
	_teleport_to("stair_g0", 0.5, 0.8)
	var sealed_g := await _wait_until(func() -> bool: return "t_g_seal" in fired and not play.is_door_open("d_g_blast"), 6.0)
	_check("the stair seal closes the blast door without locking it", sealed_g and not play.is_door_locked("d_g_blast"), str(fired))

	# Floor 0's vat is on the way to the training room.
	_teleport_marker("vat_0")
	var at_vat_0 := await _wait_until(func() -> bool: return play.checkpoint == "vat_0", 3.0)
	_check("the break room vat is floor 0's checkpoint", at_vat_0, play.checkpoint)

	# The training terminal: power to backup, grow room 0 unlocked and open, its spawner on.
	_teleport_to("training", 0.5, 0.5)
	await _frames(5)
	# The training terminal is an experiment: SHIFT runs each step, the last one fires the outbreak.
	play._use("term_training", _lab.multiplayer.get_unique_id())
	await _frames(2)
	for i in Lines.EXPERIMENT.size():
		play.request_step("term_training")
		await _frames(2)
	var outbreak := await _wait_until(func() -> bool: return "t_0_outbreak" in fired, 8.0)
	await _frames(3)
	_check("the experiment's last step fires the outbreak trigger", outbreak, str(fired))
	_check("power goes to backup", play.power == "backup", play.power)
	var grow_open := await _wait_until(func() -> bool: return play.is_door_open("d_0_grow"), 3.0)
	_check("grow room 0 unlocks and opens", not play.is_door_locked("d_0_grow") and grow_open)
	_check("the grow room stays quiet until the player is armed", not director.spawners.s_0_grow_1.active and _lab.enemies.get_child_count() == 0)
	_check("the blast door now refuses for want of power", play.door_refusal("d_g_blast") == "No power", play.door_refusal("d_g_blast"))

	# The case trigger wakes the lobby vent; the blue card opens the lift.
	_teleport_to("grow_0", 0.85, 0.7)
	await _frames(5)
	_check("the case trigger wakes the lobby vent", director.spawners.s_0_lobby_vent_1.active)
	play.smash_glass("case_grow0")
	await _frames(3)
	var gun = null
	for pickup in _lab.items.pickups.values():
		if pickup.item == "spore_shooter":
			gun = pickup
	if gun:
		_me.teleport(gun.global_position - Vector3.UP * 0.35)
	var armed := await _wait_until(func() -> bool: return _me.has_weapon, 3.0)
	_check("the case drops the spore shooter and picking it up arms the player", armed, "dropped: %s" % (gun != null))
	await _frames(3)
	_check("arming wakes the grow room spawner", director.spawners.s_0_grow_1.active)
	var spawned := await _wait_until(func() -> bool: return _lab.enemies.get_child_count() > 0, 12.0)
	_check("shrooms come out of the grow beds", spawned, str(_lab.enemies.get_child_count()))
	_check("the lift refuses without the blue card", play.door_refusal("d_0_lift").contains("blue"), play.door_refusal("d_0_lift"))
	play.add_keycard("blue")
	_check("the blue card opens the lift", play.door_refusal("d_0_lift") == "")

	# Dying on floor 0 after the outbreak: back at the break room vat, still on floor 0.
	_teleport_to("lobby", 0.5, 0.5)
	await _die_and_respawn()
	_check("dying on floor 0 respawns at its vat", _near_marker("vat_0") and _on_floor(Layout.Y.f0), "%s, checkpoint %s" % [_feet(), play.checkpoint])

	# Checkpoint: walking up to the cultivation clone vat.
	_teleport_to("clone_bay_m1", 0.5, 0.75)
	var checked := await _wait_until(func() -> bool: return play.checkpoint == "vat_m1", 3.0)
	_check("reaching a vat sets the checkpoint", checked, str(play.checkpoint))

	# The seals: each locks the way back and turns off the floors behind it, and the next vat is past it.
	await _seal_and_die("t_m1_stair_seal", "stair_m1_m2", 0.5, 0.85, "d_m1_stair", "vat_m2_lobby", "server_hall", Layout.Y.m2, ["s_0_grow_1", "s_m1_hall1_1"])
	await _seal_and_die("t_m2_airlock", "airlock", 0.5, 0.5, "d_m2_airlock_out", "vat_m3_decon", "gallery", Layout.Y.m3, ["s_m2_hall_1", "s_m2_cool_1"])
	await _seal_and_die("t_m3_cage_foot", "cage_shaft", 0.8, 0.53, "d_m3_cage", "vat_m4_foot", "drift", Layout.Y.dig, ["s_m3_tc2_1", "s_m3_tc3_2"])

	# The generator: finale, then the elevator opens.
	_teleport_to("generator_hall", 0.5, 0.2)
	await _frames(5)
	_check("the exit is shut before the finale", play.is_door_locked("d_m4_exit") and not play.is_door_open("d_m4_exit"))
	var generator: Dictionary = _lab.level.objects.generator
	generator.finale_seconds = 2.0
	play._use("generator", _lab.multiplayer.get_unique_id())
	await _frames(5)
	_check("the generator restores power and starts the finale", play.power == "restored" and director.finale_active, "%s / %s" % [play.power, director.finale_active])
	var survived := await _wait_until(func() -> bool: return "finale_survived" in fired, 8.0)
	_check("the finale ends with finale_survived", survived, str(fired))
	var exit_open := await _wait_until(func() -> bool: return play.is_door_open("d_m4_exit"), 6.0)
	_check("the elevator unlocks and opens", not play.is_door_locked("d_m4_exit") and exit_open)

	print("laboratory_play_test: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


## Walks into a seal's trigger (with some of the floor's spawners on), checks it locked the door and
## turned them off, reaches the next vat, dies in a room further on and checks the clone comes back
## at that vat on that floor, with the seal still locked behind.
func _seal_and_die(trigger: String, room: String, fx: float, fz: float, door: String, vat: String, further: String, floor_y: int, spawners: Array) -> void:
	var director = _lab.director
	for id: String in spawners:
		director.set_spawner_active(id, true)
	_teleport_to(room, fx, fz)
	var sealed := await _wait_until(func() -> bool: return trigger in _fired and _lab.play.is_door_locked(door), 4.0)
	_check("%s locks %s" % [trigger, door], sealed, str(_fired.slice(-4)))
	var quiet := spawners.filter(func(id: String) -> bool: return director.spawners[id].active).is_empty()
	_check("%s turns off the spawners behind it" % trigger, quiet, str(spawners))
	_teleport_marker(vat)
	var reached := await _wait_until(func() -> bool: return _lab.play.checkpoint == vat, 3.0)
	_check("%s is the checkpoint past %s" % [vat, trigger], reached, _lab.play.checkpoint)
	_teleport_to(further, 0.5, 0.5)
	await _frames(3)
	await _die_and_respawn()
	_check("dying after %s respawns at %s on its floor, the seal still locked" % [trigger, vat],
			_near_marker(vat) and _on_floor(floor_y) and _lab.play.is_door_locked(door), "%s, checkpoint %s" % [_feet(), _lab.play.checkpoint])


## Kills the local player and waits for the clone.
func _die_and_respawn() -> void:
	_me.take_damage(_me.health + 1.0, _me.global_position)
	await _frames(2)
	var revived := await _wait_until(func() -> bool: return not _me.is_dead, _lab.RESPAWN_DELAY + 3.0)
	await _frames(2)
	if not revived:
		_check("the player respawns", false)


## The local player's feet in voxels.
func _feet() -> Vector3:
	return (_me.global_position - _lab.world.global_position) / _lab.world.voxel_size


func _in_room(room_id: String) -> bool:
	var room: Dictionary = _lab.level.objects[room_id]
	return AABB(Vector3(room.from), Vector3(room.to - room.from)).grow(1.0).has_point(_feet())


## On a floor's band: between its floor (Layout.Y) and its ceiling.
func _on_floor(floor_y: int) -> bool:
	var y := _feet().y
	return y >= floor_y - 1.0 and y < floor_y + Layout.H


func _near_marker(id: String) -> bool:
	return _feet().distance_to(_lab.level.objects[id].position) < 10.0


func _teleport_marker(id: String) -> void:
	_me.teleport(_lab.view.to_world(_lab.level.objects[id].position))


func _teleport_to(room_id: String, fx: float, fz: float) -> void:
	var room: Dictionary = _lab.level.objects[room_id]
	var extent: Vector3i = room.to - room.from
	var voxel := Vector3(room.from) + Vector3(fx * extent.x, 0.0, fz * extent.z)
	_me.teleport(_lab.view.to_world(voxel))


func _wait_until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return condition.call()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failures += 1
		print("  FAIL %s%s" % [name, "" if detail == "" else ": " + detail])
