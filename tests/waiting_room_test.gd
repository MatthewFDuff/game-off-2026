extends SceneTree
## Headless checks for the waiting room (scripts/tools/build_waiting_room.gd, scripts/story/
## waiting_room.gd, Net.change_level):
##   godot --headless --path . --script res://tests/waiting_room_test.gd
## Builds the waiting room into a scratch folder (with a copy of the laboratory beside it), plays it
## solo: the WaitingRoom node is attached, the terminal shows 0 of 1 signed in, the admittance door
## is locked, using the terminal signs the player in and opens the door, and ADMIT_DELAY later the
## session's level changes to the laboratory and a new Lab loads it.
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
	_check("nobody has signed in", room.signed.is_empty() and room.total == 1)
	_check("the terminal says 0 of 1", lab.level.objects.reception.text.contains("Signed in: 0 of 1"), lab.level.objects.reception.text)
	_check("the admittance door is locked", play.is_door_locked("d_admit") and not play.is_door_open("d_admit"))
	_check("the staff door is locked", play.is_door_locked("d_staff"))
	var vending: Dictionary = lab.level.objects.values().filter(func(o) -> bool: return o.kind == "prop" and o.name == "vending_machine")[0]
	_check("the vending machine is a note", vending.use == "note" and vending.text.contains("OUT OF ORDER"))

	play._use("reception", lab.multiplayer.get_unique_id())
	await _frames(3)
	_check("using the terminal signs in", room.signed == [1], str(room.signed))
	_check("the terminal says 1 of 1", lab.level.objects.reception.text.contains("Signed in: 1 of 1"), lab.level.objects.reception.text)
	_check("everyone signed: admitted", room.admitted)
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

	print("waiting_room_test: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


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
