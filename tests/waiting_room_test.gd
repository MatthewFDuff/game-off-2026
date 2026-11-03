extends SceneTree
## Headless checks for the waiting room (scripts/tools/build_waiting_room.gd, scripts/story/
## waiting_room.gd, Net.change_level):
##   godot --headless --path . --script res://tests/waiting_room_test.gd
## Builds the waiting room into a scratch folder (with a copy of the laboratory beside it), plays it
## solo: the room is carved (the player spawns in air over a floor, unarmed, and the terminal can be
## reached), the WaitingRoom node is attached, the terminal shows 0 of 1 signed in, the admittance
## door is locked, using the terminal signs the player in and offers "Begin shift", using it again
## admits (the door opens), and ADMIT_DELAY later the session's level changes to the laboratory and
## a new Lab loads it. There the player is unarmed until a spore shooter is picked up, which arms the
## party (LevelPlay.armed).
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://waiting_room_test_levels/"
const Builder := preload("res://scripts/tools/build_waiting_room.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LevelData.save_dir_override = SCRATCH
	var result: Dictionary = Builder.build(root)
	_check("the waiting room builds", result.error == OK, error_string(result.error))
	result.world.free()
	var to := SCRATCH.path_join("laboratory")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to))
	for file in ["level.json", "voxels.bin"]:
		FileAccess.open(to.path_join(file), FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes("res://levels/laboratory".path_join(file)))

	root.get_node("Net").start_solo("waiting_room", "play")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	var lab = current_scene
	var play = lab.play
	await _frames(10)
	_check("the waiting room plays", lab.mode == "play" and play.active and lab.level.name == "waiting_room")
	var room = lab.get_node_or_null("WaitingRoom")
	_check("the WaitingRoom node is attached", room != null)
	if room == null:
		quit(1)
		return
	_check("the reception room and the terminal are separate objects",
			lab.level.objects.get("reception_room", {}).get("kind") == "room" and lab.level.objects.reception.kind == "prop")
	_check("the waiting room starts unarmed", lab.level.settings.get("start_unarmed", false) and not lab.local_player().has_weapon)
	_check_spawns(lab)
	_check_reachable(lab, "reception")
	_check("nobody has signed in", room.signed.is_empty() and room.total == 1)
	_check("the terminal says 0 of 1", lab.level.objects.reception.text.contains("Signed in: 0 of 1 connected"), lab.level.objects.reception.text)
	_check("the admittance door is locked", play.is_door_locked("d_admit") and not play.is_door_open("d_admit"))
	_check("the staff door is locked", play.is_door_locked("d_staff"))
	var vending: Dictionary = lab.level.objects.values().filter(func(o) -> bool: return o.kind == "prop" and o.name == "vending_machine")[0]
	_check("the vending machine is a note", vending.use == "note" and vending.text.contains("OUT OF ORDER"))

	play._use("reception", lab.multiplayer.get_unique_id())
	await _frames(3)
	_check("using the terminal signs in", room.signed == [1], str(room.signed))
	_check("the terminal says 1 of 1", lab.level.objects.reception.text.contains("Signed in: 1 of 1 connected"), lab.level.objects.reception.text)
	_check("signing in doesn't admit", not room.admitted and play.is_door_locked("d_admit"))
	_check("the host is offered Begin shift", room.can_begin() and lab.level.objects.reception.text.contains("Begin shift [E]"), lab.level.objects.reception.text)
	play._use("reception", lab.multiplayer.get_unique_id())
	await _frames(3)
	_check("the host's next use begins the shift", room.admitted and not room.can_begin())
	var opened := await _wait_until(func() -> bool: return play.is_door_open("d_admit"), 6.0)
	_check("the admittance door unlocks and opens", opened and not play.is_door_locked("d_admit"))
	var old_scene := lab.get_instance_id()
	var delay: float = room.ADMIT_DELAY
	var changed := await _wait_until(func() -> bool:
		return root.get_node("Net").session.level == "laboratory" and current_scene != null and current_scene.get_instance_id() != old_scene, delay + 8.0)
	_check("the session changes level to the laboratory", changed, str(root.get_node("Net").session))
	var loaded := await _wait_until(func() -> bool:
		return current_scene != null and current_scene.name == "Lab" and current_scene.level != null and current_scene.level.name == "laboratory" and current_scene.local_player() != null, 20.0)
	_check("the laboratory loads and spawns the player", loaded)
	if loaded:
		await _check_arming(current_scene)

	print("waiting_room_test: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


## Every spawn marker stands in air (head height clear) with a floor just below.
func _check_spawns(lab) -> void:
	var world = lab.world
	var spawns: Array = lab.level.objects.values().filter(func(o) -> bool: return o.kind == "marker" and o.type == "spawn")
	_check("the waiting room has spawns", not spawns.is_empty())
	for spawn in spawns:
		var feet: Vector3 = lab.view.to_world(spawn.position)
		var clear := true
		for h in [0.1, 0.5, 1.0, 1.5]:
			clear = clear and world.get_voxel(world.world_to_voxel(feet + Vector3.UP * h)) == 0
		var floor_hit := false
		for d in [0.05, 0.15, 0.3, 0.5]:
			floor_hit = floor_hit or world.get_voxel(world.world_to_voxel(feet + Vector3.DOWN * d)) != 0
		_check("spawn %s stands in air over a floor" % spawn.id, clear and floor_hit, "feet %s" % feet)


## Some standing spot (air at waist height over a floor) is within reach of the prop's box.
func _check_reachable(lab, id: String) -> void:
	var world = lab.world
	var box: AABB = lab.play.box_of(id)
	var reach: float = lab.play.DOOR_REACH
	var spots := 0
	var step := 0.25
	var from := box.position - Vector3(reach, 0.0, reach)
	for ix in int((box.size.x + 2.0 * reach) / step):
		for iz in int((box.size.z + 2.0 * reach) / step):
			var feet := Vector3(from.x + ix * step, box.position.y + 0.05, from.z + iz * step)
			var waist := feet + Vector3.UP * 0.8
			if box.has_point(waist) or waist.clamp(box.position, box.end).distance_to(waist) > reach - 0.5:
				continue
			if world.get_voxel(world.world_to_voxel(waist)) == 0 and world.get_voxel(world.world_to_voxel(feet + Vector3.UP * 1.5)) == 0 \
					and world.get_voxel(world.world_to_voxel(feet + Vector3.DOWN * 0.1)) != 0:
				spots += 1
	_check("the %s terminal can be reached (standing room within %.1f m)" % [id, reach], spots > 8, "%d spots" % spots)


## The laboratory starts unarmed; picking up the spore shooter arms the party.
func _check_arming(lab) -> void:
	await _frames(10)
	var me = lab.local_player()
	_check("the laboratory starts unarmed", not lab.play.armed and not me.has_weapon)
	lab.items.spawn("spore_shooter", me.global_position + Vector3.UP * 0.4)
	var armed := await _wait_until(func() -> bool: return lab.play.armed and me.has_weapon, 5.0)
	_check("picking up the spore shooter arms the party", armed)
	lab.items.spawn("spore_shooter", me.global_position + Vector3.UP * 0.4)
	await _frames(10)
	_check("a second spore shooter is harmless", lab.play.armed and me.has_weapon)


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
