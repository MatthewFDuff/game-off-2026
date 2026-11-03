extends SceneTree
## Headless smoke test that the committed laboratory (res://levels/laboratory) plays:
##   godot --headless --path . --script res://tests/laboratory_play_test.gd
## Starts it solo, checks the spawn is in the yard on facility power with every door registered,
## then teleports the local player along the story: the training terminal's trigger puts the power
## on backup and unlocks grow room 0 (its shrooms wait for the pickup); the lobby vent spawner wakes once the case trigger fires; the
## blue keycard opens the lift; reaching a clone vat sets the checkpoint; the generator starts the
## finale and the elevator door opens when it ends.
##
## Game types are left untyped (see editor_test.gd).

var _failures := 0
var _lab
var _me


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
	_check("the blast door needs power but opens now", play.door_refusal("d_g_blast") == "", play.door_refusal("d_g_blast"))
	_check("grow room 0 starts locked", play.is_door_locked("d_0_grow"))
	_check("no enemies before the outbreak", _lab.enemies.get_child_count() == 0, str(_lab.enemies.get_child_count()))
	_check("the player starts unarmed", not _me.has_weapon and not _me.weapon.fire())

	# The training terminal: power to backup, grow room 0 unlocked and open, its spawner on.
	var fired := []
	play.triggered.connect(func(id: String, _peer: int) -> void: fired.append(id))
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
	_check("the blast door now refuses", play.door_refusal("d_g_blast") != "")

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

	# Checkpoint: walking up to the cultivation clone vat.
	_teleport_to("clone_bay_m1", 0.5, 0.75)
	var checked := await _wait_until(func() -> bool: return play.checkpoint == "vat_m1", 3.0)
	_check("reaching a vat sets the checkpoint", checked, str(play.checkpoint))

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
