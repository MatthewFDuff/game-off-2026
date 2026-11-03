extends SceneTree
## Headless checks for interactables, keycards and power (phase 5):
##   godot --headless --path . --script res://tests/interact_test.gd
## Builds a scratch level (one concrete room) with a prop for every `use`, two doors and two lights,
## plays it solo, and drives the local player: aims at each prop, reads the prompt and presses E
## (the player's interacted signal, as the key does). Checks a container opens once and drops its
## contents, a note and a terminal show their text (the terminal fires its trigger and refuses on
## backup power), a medkit station heals and spends charges, an ammo bench gives ammo, a keycard
## door stays shut until the keycard is picked up, a powered door refuses on backup, a glass case
## drops its contents when a glass voxel is shot (and when smashed with E), the generator restores
## power and starts the finale, lights follow the power, start_power, and that an old prop without
## the new fields loads with defaults.
##
## Game types are left unnamed (see editor_test.gd).

const SCRATCH := "user://interact_test_levels/"
const LEVEL := "interact_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIZE := Vector3i(6, 2, 4)
const FLOOR := 8
const ROOM := [Vector3i(8, FLOOR, 8), Vector3i(184, 40, 120)]
const NORTH := 0
const SOUTH := 2

var _failures := 0
var _lab
var _me


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LevelData.save_dir_override = SCRATCH
	_make_level()
	root.get_node("Net").start_solo(LEVEL, "play")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	_lab = current_scene
	_me = _lab.local_player()
	var play = _lab.play
	await _frames(10)
	_check("playing on facility power", _lab.mode == "play" and play.active and play.power == "facility")
	var fired := []
	play.triggered.connect(func(id: String, _peer: int) -> void: fired.append(id))

	# Lights on facility power: facility on, emergency off.
	await _frames(3)
	_check("facility light on, emergency light off", _energy("light_fac") > 0.0 and _energy("light_emg") == 0.0,
			"%.2f / %.2f" % [_energy("light_fac"), _energy("light_emg")])

	# Container: opens once and drops its three items in front of it.
	await _aim_at("cab")
	_check("container prompt", _prompt_text() == "[E] Open", _prompt_text())
	_me.interacted.emit()
	await _frames(2)
	var dropped := _pickups(["ammo_shotgun", "flask_fire", "keycard_red"])
	_check("container drops its contents", dropped.size() == 3 and play.state_of("cab").used, str(dropped.keys()))
	var cab_box: AABB = play.box_of("cab")
	var in_front := dropped.values().all(func(p) -> bool: return p.global_position.z > cab_box.end.z and absf(p.global_position.x - cab_box.get_center().x) < 1.0)
	_check("contents land in front of it", in_front)
	_check("opened container prompt", _prompt_text() == "Empty", _prompt_text())
	_me.interacted.emit()
	await _frames(2)
	_check("opens only once", _lab.items.pickups.size() == 3, str(_lab.items.pickups.size()))

	# Note: E shows its text, E again closes it.
	await _aim_at("note")
	_check("note prompt", _prompt_text() == "[E] Read", _prompt_text())
	_me.interacted.emit()
	await _frames(2)
	_check("note shows its text", play.reading == "note")
	var panel = _find_prompt()
	_check("reader panel shows the text", panel != null and panel._panel.visible and panel._text.text == "Remember the coffee.", "" if panel == null else panel._text.text)
	_me.interacted.emit()
	await _frames(2)
	_check("E closes it", play.reading == "" and not panel._panel.visible)

	# Keycard door: shut until the party has the red keycard.
	await _aim_at("door_red")
	_check("keycard door prompt", _prompt_text() == "Locked: needs red keycard", _prompt_text())
	_me.interacted.emit()
	await _wait_seconds(0.8)
	_check("keycard door stays shut", not play.is_door_open("door_red"))
	var card = dropped.get("keycard_red")
	if card:
		_me.teleport(card.global_position - Vector3.UP * 0.35)
	var picked := await _wait_until(func() -> bool: return "red" in play.keycards, 3.0)
	_check("picking up the keycard gives it to the party", picked and _me.inventory.has_keycard("red"), str(play.keycards))
	await _aim_at("door_red")
	_check("keycard door prompt opens", _prompt_text() == "[E] Open", _prompt_text())
	_me.interacted.emit()
	var opened := await _wait_until(func() -> bool: return play.is_door_open("door_red"), 3.0)
	_check("keycard door opens", opened)

	# Medkit station: heals to full, spends charges, refuses at full health and when empty.
	await _aim_at("medkit")
	_check("station prompt shows charges", _prompt_text() == "[E] Use medkit station (2 left)", _prompt_text())
	_me.take_damage(40.0, _me.global_position)
	_me.interacted.emit()
	await _frames(2)
	_check("medkit station heals to full", _me.health == _me.max_health and play.state_of("medkit").charges == 1, "%.1f, %s" % [_me.health, play.state_of("medkit")])
	_me.interacted.emit()
	await _frames(2)
	_check("refused at full health", play.state_of("medkit").charges == 1)
	_me.take_damage(30.0, _me.global_position)
	_me.interacted.emit()
	await _frames(2)
	_me.take_damage(30.0, _me.global_position)
	_me.interacted.emit()
	await _frames(2)
	_check("empty station stops healing", play.state_of("medkit").charges == 0 and _me.health < _me.max_health and _prompt_text() == "Medkit station (empty)", _prompt_text())
	_me.health = _me.max_health

	# Ammo bench: 20 rounds of its type.
	await _aim_at("bench")
	_me.interacted.emit()
	await _frames(2)
	_check("ammo bench gives 20 homing rounds", _me.inventory.count("homing") == 20 and play.state_of("bench").charges == 0, str(_me.inventory.ammo))

	# Glass case: shooting out one glass voxel drops its contents, once.
	var glass1: AABB = play.box_of("glass1")
	var glass_point := Vector3(glass1.get_center().x, glass1.position.y + 1.4, glass1.end.z - 0.05)
	_lab.world_sync.carve_sphere(glass_point, 0.12, 1, Vector3.BACK)
	await _frames(2)
	_check("breaking its glass drops the contents", _pickups(["ammo_explosive"]).size() == 1 and play.state_of("glass1").used)
	_lab.world_sync.carve_sphere(glass_point + Vector3.RIGHT * 0.2, 0.12, 1, Vector3.BACK)
	await _frames(2)
	_check("only once", _lab.items.pickups.values().filter(func(p) -> bool: return p.item == "ammo_explosive").size() == 1)
	# The other one is smashed with E.
	await _aim_at("glass2")
	_check("glass case prompt", _prompt_text() == "[E] Smash glass", _prompt_text())
	_me.interacted.emit()
	await _frames(2)
	_check("E smashes the glass and drops the contents", _pickups(["flask_rage"]).size() == 1 and _count_in(play.box_of("glass2"), M.GLASS) == 0,
			"%d glass left" % _count_in(play.box_of("glass2"), M.GLASS))

	# Backup power: lights swap, the powered door and the terminal refuse.
	var powers := []
	play.power_changed.connect(func(state: String) -> void: powers.append(state))
	play.set_power("backup")
	await _frames(3)
	_check("power goes to backup", play.power == "backup" and powers == ["backup"])
	_check("backup: facility light off, emergency light on", _energy("light_fac") == 0.0 and _energy("light_emg") > 0.0,
			"%.2f / %.2f" % [_energy("light_fac"), _energy("light_emg")])
	await _aim_at("door_pow")
	_check("powered door prompt on backup", _prompt_text() == "No power", _prompt_text())
	_me.interacted.emit()
	await _wait_seconds(0.8)
	_check("powered door refuses on backup", not play.is_door_open("door_pow"))
	await _aim_at("term")
	_check("terminal prompt on backup", _prompt_text() == "No power", _prompt_text())
	_me.interacted.emit()
	await _frames(2)
	_check("terminal refuses on backup", play.reading == "" and fired.is_empty(), str(fired))

	# Generator: restores power, fires its trigger, starts the finale.
	await _aim_at("gen")
	_check("generator prompt", _prompt_text() == "[E] Start generator", _prompt_text())
	_me.interacted.emit()
	await _frames(3)
	_check("generator restores power", play.power == "restored")
	_check("generator fires its trigger", "gen_fired" in fired, str(fired))
	_check("generator starts the finale", _lab.director.state == "finale", _lab.director.state)
	_check("running generator prompt", _prompt_text() == "Running", _prompt_text())
	_check("restored: facility light on, emergency light off", _energy("light_fac") > 0.0 and _energy("light_emg") == 0.0)

	# Terminal with power: shows its text and fires its trigger (once).
	await _aim_at("term")
	_me.interacted.emit()
	await _frames(2)
	_check("terminal shows its text", play.reading == "term" and panel._title.text == "TERMINAL")
	_check("terminal fires its trigger", fired.count("term_fired") == 1, str(fired))
	_me.interacted.emit()
	await _frames(1)
	_me.interacted.emit()
	await _frames(2)
	_check("trigger fires once", fired.count("term_fired") == 1 and play.reading == "term", str(fired))
	_me.teleport(_lab.view.to_world(Vector3(96.0, FLOOR, 100.0)))
	await _frames(3)
	_check("walking away closes the terminal", play.reading == "")

	await _aim_at("door_pow")
	_me.interacted.emit()
	var powered := await _wait_until(func() -> bool: return play.is_door_open("door_pow"), 3.0)
	_check("powered door opens on restored power", powered)

	# start_power: a level can begin on backup; replaying resets the props.
	_lab.level.settings.start_power = "backup"
	_lab.request_mode("edit")
	await _frames(3)
	_lab.request_mode("play")
	await _frames(5)
	_check("start_power backup", play.power == "backup")
	_check("replay resets prop state and keycards", not play.state_of("cab").used and play.state_of("medkit").charges == 2 and play.keycards.is_empty())

	print("interact test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## One room; along the north wall (fronts facing south): cabinet, note, terminal, medkit station,
## two glass cases. Along the south wall (facing north): a keycard door, a powered door, the
## generator, an ammo bench. Two lights, a spawn in the middle, and an old-format fridge.
func _make_level() -> void:
	var level := LevelData.new()
	level.name = LEVEL
	level.settings = LevelData.default_settings(SIZE, "rock")
	var world := VoxelWorld.new()
	world.size_in_chunks = SIZE
	world.immediate_remesh_limit = 0
	world.detach_floating = false
	root.add_child(world)
	world.fill_all(M.CONCRETE)
	world.fill_box(ROOM[0], ROOM[1], M.AIR, false)
	level.voxels = world.get_data()
	world.free()

	var add := func(id: String, prop_name: String, origin: Vector3i, facing: int, fields := {}) -> void:
		var prop := LevelSchema.new_prop(prop_name, origin, facing)
		prop.id = id
		prop.merge(fields, true)
		level.objects[id] = prop
	add.call("cab", "cabinet", Vector3i(12, FLOOR, 8), SOUTH, {contents = "ammo_shotgun, flask_fire,keycard_red"})
	add.call("note", "corkboard_a", Vector3i(42, FLOOR, 8), SOUTH, {use = "note", text = "Remember the coffee."})
	add.call("term", "terminal", Vector3i(72, FLOOR, 8), SOUTH, {needs_power = true, on_use = "term_fired", text = "SYSTEM OK"})
	add.call("medkit", "medkit_station", Vector3i(102, FLOOR, 8), SOUTH, {charges = 2})
	add.call("glass1", "glass_case", Vector3i(132, FLOOR, 8), SOUTH, {contents = "ammo_explosive"})
	add.call("glass2", "glass_case", Vector3i(162, FLOOR, 8), SOUTH, {contents = "flask_rage"})
	add.call("door_red", "crate_8", Vector3i(20, FLOOR, 112), NORTH, {door = true, door_offset = Vector3i(10, 0, 0), door_key = "red", use = "none"})
	add.call("door_pow", "crate_8", Vector3i(60, FLOOR, 112), NORTH, {door = true, door_offset = Vector3i(10, 0, 0), door_power = true, use = "none"})
	add.call("gen", "generator", Vector3i(100, FLOOR, 108), NORTH, {on_use = "gen_fired", finale_seconds = 30.0})
	add.call("bench", "ammo_bench", Vector3i(150, FLOOR, 113), NORTH, {charges = 1, station_ammo_type = "homing"})
	_check("new props get their default use", level.objects.cab.use == "container" and level.objects.gen.use == "generator"
			and level.objects.medkit.use == "station_medkit" and level.objects.glass1.use == "glass_case")

	var spawn := LevelSchema.new_marker("spawn", Vector3(96.0, FLOOR, 64.0), 0.0)
	spawn.id = "spawn_1"
	var facility := LevelSchema.new_marker("light", Vector3(60.0, 36.0, 64.0))
	facility.id = "light_fac"
	var emergency := LevelSchema.new_marker("light", Vector3(130.0, 36.0, 64.0))
	emergency.id = "light_emg"
	emergency.power = "emergency"
	for object in [spawn, facility, emergency]:
		level.objects[object.id] = object
	# A prop saved before the phase 5 fields existed (no use, contents, door_key, ...).
	level.objects["old_fridge"] = {kind = "prop", name = "fridge", origin = Vector3i(180, FLOOR, 60), facing = 3, value = 900,
			door = false, door_offset = Vector3i.ZERO, door_speed = 2.0, door_locked = false, id = "old_fridge"}
	level.settings.erase("start_power") # Like a level saved before it existed.
	_check("level saves", level.save() == OK)
	var loaded := LevelData.load_level(LEVEL)
	var old: Dictionary = loaded.objects.get("old_fridge", {}) if loaded else {}
	_check("old prop loads with defaults", old.get("use") == "container" and old.get("contents") == "" and old.get("door_key") == ""
			and old.get("door_power") == false and old.get("charges") == 3 and old.get("finale_seconds") == 120.0, str(old))
	_check("int prop fields load as ints", loaded and loaded.objects.medkit.charges is int)
	_check("text survives the round trip", loaded and loaded.objects.note.text == "Remember the coffee.")


## Stands 1.6 m in front of a prop or door (on the room floor) and looks at the middle of its box.
func _aim_at(id: String) -> void:
	var box: AABB = _lab.play.box_of(id)
	var center := box.get_center()
	var floor_y: float = _lab.view.to_world(Vector3(0, FLOOR, 0)).y
	var front := Vector3.BACK if center.z < _lab.view.to_world(Vector3(0, 0, 64)).z else Vector3.FORWARD
	var face := center + front * box.size.z * 0.5
	var feet := Vector3(face.x, floor_y, face.z) + front * 1.6
	_me.teleport(feet)
	_me.velocity = Vector3.ZERO
	await _frames(4)
	var eye: Vector3 = _me.camera.global_position
	var to := center - eye
	_me.rotation.y = atan2(-to.x, -to.z)
	_me.head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	await _frames(3)


func _prompt_text() -> String:
	return _lab.play.interactables.prompt_for(_me.camera).text


func _find_prompt():
	for node in root.find_children("*", "Control", true, false):
		if node.get_script() and node.get_script().resource_path.ends_with("interact_prompt.gd"):
			return node
	return null


## Pickups of the given items: item -> Pickup.
func _pickups(items: Array) -> Dictionary:
	var out := {}
	for pickup in _lab.items.pickups.values():
		if pickup.item in items:
			out[pickup.item] = pickup
	return out


func _energy(id: String) -> float:
	var light = _lab.view._lights.get(id)
	return light.light_energy if light else -1.0


func _count_in(box: AABB, material: int) -> int:
	var world = _lab.world
	var from := Vector3i(((box.position - world.global_position) / world.voxel_size).round())
	var to := Vector3i(((box.end - world.global_position) / world.voxel_size).round())
	var n := 0
	for y in range(from.y, to.y):
		for z in range(from.z, to.z):
			for x in range(from.x, to.x):
				n += int(world.get_voxel(Vector3i(x, y, z)) == material)
	return n


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await physics_frame
	return true


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(label: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", label, "" if ok else detail])
	if not ok:
		_failures += 1
