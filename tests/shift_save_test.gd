extends SceneTree
## Headless checks for the shift save (docs/shift-save.md) on the committed laboratory:
##   godot --headless --path . --script res://tests/shift_save_test.gd
## A solo story shift (Net.session.shift): reach the break room vat (the checkpoint saves), damage
## the gatehouse desk, open the blast door, walk into the stair seal (a trigger with a lock action),
## pick up the blue keycard and die once; save_shift; the summary names the vat's room, the owed
## total (damage plus the clone) and layout_ok; the finale blocks saving. A second Lab resumed from
## the save spawns the player at the vat with the same power, keycards, doors, fired triggers,
## ledger, spawner states, taken item spots, clone count and world. A tampered level_hash makes
## layout_ok false, and resuming it falls back to a fresh start with the notice. The save and the
## level folder are pointed at scratch folders, so the real user:// is untouched.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://shift_save_test/"
const LEVELS_SCRATCH := "user://shift_save_test_levels/"
const STALE := "The shift on file was recorded against an older site layout. Starting fresh."

var _failures := 0
var _lab
var _me


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	ShiftSave.dir_override = SCRATCH
	LevelData.save_dir_override = LEVELS_SCRATCH
	ShiftSave.clear()
	var net = root.get_node("Net")
	_check("no shift on file to begin with", not ShiftSave.exists() and ShiftSave.summary().is_empty())

	# --- The first shift ---------------------------------------------------------------------------
	net.start_solo("laboratory", "play", {shift = true})
	await _enter_lab(null)
	_check("the session is a shift", net.session.get("shift", false) and _lab.in_shift())
	var play = _lab.play
	var director = _lab.director
	director.scale_per_player = 0.0
	var me_id: int = _lab.multiplayer.get_unique_id()
	await _frames(10)

	# The break room vat: the checkpoint, and with it a save.
	_teleport_marker("vat_0")
	var at_vat := await _wait_until(func() -> bool: return play.checkpoint == "vat_0", 3.0)
	_check("reaching the vat sets the checkpoint", at_vat, play.checkpoint)
	_check("the checkpoint saves the shift", ShiftSave.exists() and ShiftSave.summary().get("vat") == "vat_0", str(ShiftSave.summary()))

	# Damage an asset: a hole in the gatehouse desk.
	var desk: Dictionary = _lab.level.objects.desk_gatehouse
	var desk_box := LevelSchema.prop_box(desk)
	var desk_top := Vector3(desk_box.get_center().x, desk_box.end.y - 1.0, desk_box.get_center().z)
	_lab.world_sync.carve_sphere(_lab.view.to_world(desk_top), 0.4, 254)
	var damaged := await _wait_until(func() -> bool: return play.total_damage > 0, 2.0)
	_check("carving the desk is billed", damaged and play.damage_by_name.has("desk_empty"), str(play.damage_by_name))

	# Open the blast door (signing in unlocks it).
	_teleport_to("gatehouse", 0.5, 0.5)
	await _frames(3)
	play._use("term_g_signin", me_id)
	await _wait_until(func() -> bool: return play.door_refusal("d_g_blast") == "", 2.0)
	play._use("d_g_blast", me_id)
	var blast_open := await _wait_until(func() -> bool: return play.is_door_open("d_g_blast") and not play._doors.d_g_blast.moving, 4.0)
	_check("the blast door opens", blast_open)

	# The blue keycard from the security office.
	var card = null
	for pickup in _lab.items.pickups.values():
		if pickup.item == "keycard_blue":
			card = pickup
	if card:
		_me.teleport(card.global_position - Vector3.UP * 0.35)
	var carded := await _wait_until(func() -> bool: return "blue" in play.keycards, 3.0)
	_check("the blue keycard is picked up", carded and not _lab.items.taken_spots().is_empty(), str(_lab.items.taken_spots()))

	# The stair seal: closes and locks the stair door, turns floors 0 and -1 off.
	director.set_spawner_active("s_0_grow_1", true)
	_teleport_to("stair_m1_m2", 0.5, 0.85)
	await _frames(10)
	var sealed := await _wait_until(func() -> bool: return play.is_door_locked("d_m1_stair") and not play._doors.d_m1_stair.moving, 20.0)
	_check("the stair seal locks its door", sealed and "t_m1_stair_seal" in play.fired(), "%s at %s" % [play.fired(), _feet()])
	await _frames(3)
	_check("the seal saves the shift", "t_m1_stair_seal" in ShiftSave.load().get("fired", []))

	# One clone grown, at the break room vat.
	_teleport_to("break_room", 0.3, 0.5)
	await _frames(3)
	await _die_and_respawn()
	_check("the death is counted", _lab.story.deaths == 1, str(_lab.story.deaths))
	_check("the clone comes back at the vat", _near_marker("vat_0"), str(_feet()))
	_teleport_to("break_room", 0.3, 0.5)
	await _frames(5)

	# Save and remember everything to compare.
	_lab.shift_seconds = 125.0
	_lab.save_shift()
	var world_hash := _hash(_lab.world.get_data())
	var expect := _snapshot()
	var summary := ShiftSave.summary()
	_check("the summary names the vat's room", summary.get("vat_room") == "Break room", str(summary.get("vat_room")))
	_check("the summary owes damage plus the clone", summary.get("owed") == play.total_damage + 5000 and summary.get("clones") == 1,
			"%s vs %d" % [summary.get("owed"), play.total_damage + 5000])
	_check("the summary's layout matches", summary.get("layout_ok") == true)
	_check("the summary has the clock and the party", is_equal_approx(float(summary.get("elapsed", 0.0)), 125.0) and summary.get("party", []).size() == 1,
			str(summary))
	_check("the record has every key", ShiftSave.load().has_all(["level", "level_hash", "saved_at", "elapsed", "checkpoint", "power", "keycards",
			"armed", "prop_state", "doors", "fired", "damage_by_name", "total_damage", "deaths", "director", "items_taken", "party",
			"chunk_slots", "chunk_data"]))
	_check("the save is a delta of changed chunks", ShiftSave.load().get("format") == ShiftSave.FORMAT
			and ShiftSave.load().chunk_slots.size() > 0 and ShiftSave.load().chunk_slots.size() < _lab.world.get_stats().get("chunks", 3072),
			str(ShiftSave.load().get("chunk_slots", PackedInt32Array()).size()))

	# The finale blocks saving.
	director.finale_active = true
	play.total_damage += 1000
	_lab.save_shift()
	_check("no save during the finale", ShiftSave.summary().get("owed") == summary.get("owed"), str(ShiftSave.summary().get("owed")))
	play.total_damage -= 1000
	director.finale_active = false

	# --- The resumed shift -------------------------------------------------------------------------
	var first = _lab
	net.start_solo("laboratory", "play", {shift = true, resume = true})
	await _enter_lab(first)
	play = _lab.play
	director = _lab.director
	_check("the shift resumed", _lab.resumed)
	_check("the world is the saved one", _hash(_lab.world.get_data()) == world_hash)
	var got := _snapshot()
	for key: String in expect:
		_check("resumed %s matches" % key, got[key] == expect[key], "%s vs %s" % [got[key], expect[key]])
	_check("the player spawns at the vat", _near_marker("vat_0"), str(_feet()))
	_check("the clock carries on", _lab.shift_seconds >= 125.0, str(_lab.shift_seconds))
	_check("the keycard isn't lying in the office again", not _lab.items.pickups.values().any(func(p) -> bool: return p.item == "keycard_blue"))
	await _frames(5)
	_check("the story counts the saved clone", _lab.story.deaths == 1, str(_lab.story.deaths))
	_check("the seal is still locked", play.is_door_locked("d_m1_stair") and not play.is_door_open("d_m1_stair"))
	_check("no damage counted by the world swap", play.total_damage == expect.total_damage, str(play.total_damage))

	# --- An older whole-world save (format 1) still resumes --------------------------------------------
	var full_record := ShiftSave.load()
	var full_world: PackedByteArray = _lab.world.get_data()
	ShiftSave.write(full_record, full_world)
	var third = _lab
	net.start_solo("laboratory", "play", {shift = true, resume = true})
	await _enter_lab(third)
	_check("a format 1 (whole-world) save resumes", _lab.resumed and _hash(_lab.world.get_data()) == _hash(full_world))

	# --- A save from an older layout -----------------------------------------------------------------
	var path := SCRATCH.path_join("shift.json")
	var record = JSON.parse_string(FileAccess.get_file_as_string(path))
	record.level_hash = "0000"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(record))
	file.close()
	_check("a tampered hash is not layout_ok", ShiftSave.summary().get("layout_ok") == false)
	var second = _lab
	net.start_solo("laboratory", "play", {shift = true, resume = true})
	await _enter_lab(second)
	var toast = _lab.get_node("Hud")._toast
	_check("a stale save starts fresh", not _lab.resumed and _lab.play.checkpoint == "" and _lab.play.keycards.is_empty())
	_check("the stale notice shows", toast.text == STALE, toast.text)
	_check("a fresh start spawns in the yard", _in_room("yard"), str(_feet()))

	ShiftSave.clear()
	_check("clear removes the save", not ShiftSave.exists())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	print("shift_save_test: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


## Waits for a Lab (not the old one) with the local player in it.
func _enter_lab(old) -> void:
	while current_scene == null or current_scene == old or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	_lab = current_scene
	_me = _lab.local_player()


## What the resume must bring back.
func _snapshot() -> Dictionary:
	var play = _lab.play
	var doors := {}
	for id: String in play._doors:
		var door: Dictionary = play._doors[id]
		doors[id] = [door.origin, door.open, door.object.door_locked]
	var spawners := {}
	for id: String in _lab.director.spawners:
		var spawner: Dictionary = _lab.director.spawners[id]
		var boss := str(spawner.object.get("on_dead", "")) != ""
		spawners[id] = [spawner.active, spawner.dead_fired, spawner.spawned if not boss else null]
	var fired: Array = play.fired()
	fired.sort()
	var taken: Array = _lab.items.taken_spots()
	taken.sort()
	return {
		power = play.power,
		keycards = Array(play.keycards),
		armed = play.armed,
		checkpoint = play.checkpoint,
		doors = doors,
		fired = fired,
		damage_by_name = play.damage_by_name.duplicate(),
		total_damage = play.total_damage,
		spawners = spawners,
		dormant = _lab.director.dormant,
		taken = taken,
		prop_used = play.prop_state.keys().filter(func(id: String) -> bool: return play.prop_state[id].used),
	}


func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_MD5)
	context.update(bytes)
	return context.finish().hex_encode()


func _die_and_respawn() -> void:
	_me.take_damage(_me.health + 1.0, _me.global_position)
	await _frames(2)
	var revived := await _wait_until(func() -> bool: return not _me.is_dead, _lab.RESPAWN_DELAY + 3.0)
	await _frames(2)
	if not revived:
		_check("the player respawns", false)


func _feet() -> Vector3:
	return (_me.global_position - _lab.world.global_position) / _lab.world.voxel_size


func _in_room(room_id: String) -> bool:
	var room: Dictionary = _lab.level.objects[room_id]
	return AABB(Vector3(room.from), Vector3(room.to - room.from)).grow(1.0).has_point(_feet())


func _near_marker(id: String) -> bool:
	return _feet().distance_to(_lab.level.objects[id].position) < 10.0


func _teleport_marker(id: String) -> void:
	_me.teleport(_lab.view.to_world(_lab.level.objects[id].position))


func _teleport_to(room_id: String, fx: float, fz: float) -> void:
	var room: Dictionary = _lab.level.objects[room_id]
	var extent: Vector3i = room.to - room.from
	_me.teleport(_lab.view.to_world(Vector3(room.from) + Vector3(fx * extent.x, 0.0, fz * extent.z)))


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
