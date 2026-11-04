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
## Then the interactables (prop-build-plan E, _interactables): a switch fires its trigger every
## time and `lights=` cuts a room's lights, a vending machine bills the payroll and drops a snack
## (and shooting its glass drops one more, billed as damage), the water cooler's buff, the eyewash,
## the defibrillator, a fire extinguisher picked up as a foam flask and one shot into foam (slowing
## an enemy, clearing a spore cloud), a gas cylinder that skids when shot and explodes the second
## time, flipping a table, a printer's page, a radio's and a duck's lures, a hanging crate cut down
## onto an enemy, sprinklers, and a forced door on the payroll.
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
## The interactables' row (origin z).
const ROW := 30

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

	await _interactables(fired)

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
	# The interactables' row (fronts facing south, z = ROW).
	add.call("sw", "switch_lever", Vector3i(12, FLOOR, ROW), SOUTH, {on_use = "lights_trig"})
	add.call("vend", "vending_machine_glass", Vector3i(22, FLOOR, ROW), SOUTH)
	add.call("cooler", "water_cooler", Vector3i(40, FLOOR, ROW), SOUTH)
	add.call("eye", "eyewash_station", Vector3i(52, FLOOR, ROW), SOUTH)
	add.call("defib", "defib_cabinet", Vector3i(66, FLOOR, ROW), SOUTH)
	add.call("ext", "fire_extinguisher", Vector3i(80, FLOOR, ROW), SOUTH)
	add.call("ext2", "fire_extinguisher", Vector3i(90, FLOOR, ROW), SOUTH)
	add.call("gas", "gas_cylinder", Vector3i(130, FLOOR, 80), SOUTH) # In the open: it skids and blows up.
	add.call("flip", "table", Vector3i(114, FLOOR, ROW), SOUTH)
	add.call("printer", "printer_station", Vector3i(134, FLOOR, ROW), SOUTH)
	add.call("radio", "radio", Vector3i(156, FLOOR, ROW), SOUTH)
	add.call("duck", "rubber_duck", Vector3i(170, FLOOR, ROW), SOUTH)
	add.call("crate", "crate_hanging", Vector3i(20, ROOM[1].y - 21, 70), SOUTH)
	_check("the interactables get their uses and field defaults", level.objects.sw.use == "switch" and level.objects.vend.use == "vendor"
			and level.objects.vend.price == 3 and level.objects.vend.contents == "snack" and level.objects.cooler.use == "vendor"
			and level.objects.cooler.buff == "speed" and level.objects.ext.use == "extinguisher" and level.objects.flip.use == "flip"
			and level.objects.printer.use == "printer" and level.objects.duck.use == "squeak" and level.objects.defib.use == "defib",
			"%s %s %s" % [level.objects.sw.use, level.objects.vend, level.objects.cooler.use])

	var spawn := LevelSchema.new_marker("spawn", Vector3(96.0, FLOOR, 64.0), 0.0)
	spawn.id = "spawn_1"
	var facility := LevelSchema.new_marker("light", Vector3(60.0, 36.0, 64.0))
	facility.id = "light_fac"
	var emergency := LevelSchema.new_marker("light", Vector3(130.0, 36.0, 64.0))
	emergency.id = "light_emg"
	emergency.power = "emergency"
	# A volume up by the ceiling (nobody walks into it) around the facility light: `lights=` and
	# `sprinkle=` work on it; and the triggers the switch and the test fire.
	var zone := LevelSchema.new_marker("trigger", Vector3(60.0, 30.0, 64.0))
	zone.id = "zone"
	zone.size = Vector3i(40, 10, 40)
	var lights_trig := LevelSchema.new_marker("trigger", Vector3(150.0, 34.0, 20.0))
	lights_trig.id = "lights_trig"
	lights_trig.size = Vector3i(2, 2, 2)
	lights_trig.actions = "lights=zone:off"
	var sprinkle_trig := LevelSchema.new_marker("trigger", Vector3(154.0, 34.0, 20.0))
	sprinkle_trig.id = "sprinkle_trig"
	sprinkle_trig.size = Vector3i(2, 2, 2)
	sprinkle_trig.actions = "sprinkle=zone"
	for object in [spawn, facility, emergency, zone, lights_trig, sprinkle_trig]:
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


## The interactables (prop-build-plan E), on restored power. fired collects the triggers.
func _interactables(fired: Array) -> void:
	var play = _lab.play
	var enemies = _lab.enemies

	# Switch: fires its trigger every time; its `lights=` action cuts the zone's lights.
	await _aim_at("sw")
	_check("switch prompt", _prompt_text() == "[E] Pull", _prompt_text())
	_me.interacted.emit()
	await _frames(3)
	_check("switch fires its trigger", fired.count("lights_trig") == 1, str(fired))
	_check("lights= cuts the room's lights", _energy("light_fac") == 0.0 and play.rules.light_mode("light_fac") == "off",
			"%.2f" % _energy("light_fac"))
	_me.interacted.emit()
	await _frames(3)
	_check("switch fires every time", fired.count("lights_trig") == 2, str(fired))
	play.rules.run_action("test", "lights", "zone:on")
	await _frames(3)
	_check("lights=...:on brings them back", _energy("light_fac") > 0.0)

	# Vendor: bills the payroll and drops a snack; the glass shot out drops another, billed as damage.
	await _aim_at("vend")
	_check("vendor prompt", _prompt_text() == "[E] Buy a snack ($3, billed to payroll)", _prompt_text())
	_me.interacted.emit()
	await _frames(3)
	_check("vending machine charges the payroll", int(play.purchases.get("vending_machine_glass", 0)) == 3, str(play.purchases))
	_check("and drops a snack", _count_items("snack") == 1, str(_count_items("snack")))
	_me.teleport(_lab.view.to_world(Vector3(96.0, FLOOR, 100.0)))
	var vend: AABB = play.box_of("vend")
	_lab.world_sync.carve_sphere(Vector3(vend.get_center().x, vend.position.y + 1.2, vend.end.z - 0.05), 0.12, 1, Vector3.BACK)
	await _frames(6)
	_check("shooting its glass drops another snack", _count_items("snack") == 2, str(_count_items("snack")))
	_check("billed as damage", int(play.damage_by_name.get("vending_machine_glass_snack", 0)) == 3, str(play.damage_by_name))
	_me.health = 50.0
	var snacks: Array = _lab.items.pickups.values().filter(func(p) -> bool: return p.item == "snack")
	if not snacks.is_empty():
		_me.teleport(snacks[0].global_position - Vector3.UP * 0.35)
		await _wait_until(func() -> bool: return _count_items("snack") < snacks.size(), 2.0)
	_check("a snack heals a little", _me.health >= 50.0 + 15.0 - 0.01, "%.1f" % _me.health)
	_me.health = _me.max_health

	# Water cooler: the speed buff.
	await _aim_at("cooler")
	_me.interacted.emit()
	await _frames(3)
	_check("water cooler gives the speed buff", _me.statuses.has("hasted"), str(_me.statuses))

	# Eyewash: clears poisoned and burning.
	_me.apply_status("poisoned", 10.0)
	_me.apply_status("burning", 10.0)
	await _aim_at("eye")
	_me.interacted.emit()
	await _frames(3)
	_check("eyewash clears poisoned and burning", not _me.statuses.has("poisoned") and not _me.statuses.has("burning"), str(_me.statuses))
	_me.health = _me.max_health

	# Defibrillator: no one down near, so it heals the user.
	await _aim_at("defib")
	_check("defib prompt", _prompt_text() == "[E] Defibrillator (2 left)", _prompt_text())
	_me.take_damage(30.0, _me.global_position)
	_me.velocity = Vector3.ZERO
	_me.interacted.emit()
	await _frames(3)
	_check("defib with nobody down heals the user", _me.health == _me.max_health and play.state_of("defib").charges == 1,
			"%.1f, %s" % [_me.health, play.state_of("defib")])

	# Fire extinguisher: E takes it as a foam flask.
	await _aim_at("ext")
	_check("extinguisher prompt", _prompt_text() == "[E] Take the extinguisher", _prompt_text())
	var ext_box: AABB = play.box_of("ext")
	_me.interacted.emit()
	var took := await _wait_until(func() -> bool: return _me.inventory.flask_count("foam") == 1, 3.0)
	_check("E picks the extinguisher up as a foam flask", took and _count_in(ext_box, M.RED_PAINT) == 0,
			"%d foam, %d red left" % [_me.inventory.flask_count("foam"), _count_in(ext_box, M.RED_PAINT)])

	# The other one, shot: a foam cloud that slows an enemy and clears a spore cloud.
	_me.teleport(_lab.view.to_world(Vector3(96.0, FLOOR, 100.0)))
	await _frames(3)
	var ext2: AABB = play.box_of("ext2")
	var spore = _lab.enemies.request_cloud("spore", ext2.get_center() + Vector3.RIGHT * 1.5, 2.0, 20.0)
	var enemy = enemies.spawn("basic", Vector3(ext2.get_center().x - 1.0, ext2.position.y, ext2.get_center().z + 0.8))
	await _frames(3)
	_lab.world_sync.carve_sphere(Vector3(ext2.get_center().x, ext2.position.y + 0.3, ext2.end.z - 0.05), 0.12, 4, Vector3.BACK)
	await _wait_seconds(0.6)
	var foam: Array = enemies.clouds.values().filter(func(c) -> bool: return c.type == "foam")
	_check("a shot extinguisher bursts into foam", foam.size() == 1 and _count_in(ext2, M.RED_PAINT) == 0,
			"%d foam clouds, %d red left" % [foam.size(), _count_in(ext2, M.RED_PAINT)])
	_check("foam clears the spore cloud", spore == null or not enemies.clouds.values().has(spore))
	_check("foam slows the enemy", enemy != null and is_instance_valid(enemy) and enemy.has_status("slowed"),
			"" if enemy == null or not is_instance_valid(enemy) else str(enemy.statuses))
	if enemy and is_instance_valid(enemy):
		enemies.despawn(enemy.id)

	# Gas cylinder: shot, it skids away; shot again, it explodes.
	var gas_rec: Dictionary = play.rules._reactive.get("gas", {})
	var gas_from: Vector3i = gas_rec.get("origin", Vector3i.ZERO)
	var gas_box: AABB = _prop_box("gas")
	_lab.world_sync.carve_sphere(Vector3(gas_box.get_center().x, gas_box.position.y + 0.6, gas_box.end.z - 0.05), 0.12, 4, Vector3.BACK)
	await _wait_seconds(1.0)
	gas_rec = play.rules._reactive.get("gas", {})
	_check("a shot gas cylinder vents and skids", gas_rec.get("vented", false) and gas_rec.get("origin") != gas_from and not gas_rec.get("moving", true),
			str(gas_rec.get("origin")) + " from " + str(gas_from))
	if gas_rec.has("origin"):
		var at: Vector3 = _lab.view.to_world(Vector3(gas_rec.origin) + Vector3(gas_rec.size) * 0.5)
		_lab.world_sync.carve_sphere(at, 0.3, 4, Vector3.UP)
		await _frames(3)
	_check("shot again, it explodes", not play.rules._reactive.has("gas") and play.state_of("gas").used)

	# Flip: the table swaps for its flipped twin.
	await _aim_at("flip")
	_check("flip prompt", _prompt_text() == "[E] Flip it for cover", _prompt_text())
	_me.interacted.emit()
	await _frames(3)
	var twin := Props.orient(Props.load_prop("table_flipped"), SOUTH)
	var standing: int = _lab.world.count_matching(_lab.level.objects.flip.origin, twin.size, twin.voxels)
	var twin_total := Array(twin.voxels).filter(func(v) -> bool: return v != 0).size()
	_check("E flips the table for cover", standing == twin_total and play.state_of("flip").used, "%d / %d" % [standing, twin_total])
	_check("flipping isn't billed", not play.damage_by_name.has("table"), str(play.damage_by_name))

	# Printer: prints its text as a page; picking it up reads it.
	await _aim_at("printer")
	_me.interacted.emit()
	await _frames(3)
	var page = _pickups(["paper_printer"]).get("paper_printer")
	_check("the printer prints a page", page != null and play.state_of("printer").used)
	if page:
		_me.teleport(page.global_position - Vector3.UP * 0.35)
		var read := await _wait_until(func() -> bool: return play.reading == "printer", 2.0)
		_check("picking the page up reads it", read and play.reading_text("printer").begins_with("MEMO"), play.reading)
		play.close_reading()

	# Radio: a lure while it plays; duck: a lure for a few seconds.
	await _aim_at("radio")
	_me.interacted.emit()
	await _frames(3)
	var radio_at: Vector3 = play.box_of("radio").get_center()
	_check("a playing radio lures enemies", play.state_of("radio").get("on", false) and enemies.lure_for(radio_at + Vector3(10, 0, 0)) != null)
	var walker = enemies.spawn("basic", Vector3(radio_at.x - 6.0, _lab.view.to_world(Vector3(0, FLOOR, 0)).y, radio_at.z + 4.0))
	_me.editing = true # Not a target: the enemy has no player to see.
	var before: float = walker.global_position.distance_to(radio_at)
	await _wait_seconds(1.0)
	var after: float = walker.global_position.distance_to(radio_at)
	_check("an enemy that sees nobody goes to the radio", after < before - 1.0, "%.1f -> %.1f" % [before, after])
	_me.editing = false
	enemies.despawn(walker.id)
	await _aim_at("radio")
	_me.interacted.emit()
	await _frames(3)
	_check("turned off, it stops luring", enemies.lure_for(radio_at) == null)
	await _aim_at("duck")
	_me.interacted.emit()
	await _frames(3)
	_check("a squeaked duck lures for a moment", enemies.lure_for(play.box_of("duck").get_center()) != null)

	# Hanging crate: shoot its chain and it crushes the enemy under it.
	_me.teleport(_lab.view.to_world(Vector3(96.0, FLOOR, 100.0)))
	var crate: AABB = _prop_box("crate")
	var victim = enemies.spawn("basic", Vector3(crate.get_center().x, _lab.view.to_world(Vector3(0, FLOOR, 0)).y, crate.get_center().z))
	await _frames(3)
	_lab.world_sync.carve_sphere(Vector3(crate.get_center().x, crate.end.y - 0.6, crate.get_center().z), 0.25, 4, Vector3.DOWN)
	await _frames(3)
	_check("a cut-down crate crushes the enemy under it", not is_instance_valid(victim) or not victim.alive,
			"" if not is_instance_valid(victim) else "%.1f hp, %d wood left in %s" % [victim.health, _count_in(crate, M.WOOD), crate])

	# Sprinklers: clouds in the zone go, its lights flicker, then stop.
	var gas_cloud = _lab.enemies.request_cloud("poison", _lab.view.to_world(Vector3(60.0, 34.0, 64.0)), 1.0, 20.0)
	play.triggered.emit("sprinkle_trig", 1)
	await _frames(4)
	_check("sprinklers clear the clouds in the room", gas_cloud == null or not enemies.clouds.values().has(gas_cloud))
	_check("and flicker its lights", play.rules.light_mode("light_fac") == "flicker")
	await _wait_seconds(play.rules.SPRINKLE_SECONDS + 0.8)
	_check("then stop", play.rules.light_mode("light_fac") == "" and play.rules._sprinkling.is_empty())

	# A door broken through is on the payroll.
	var door: AABB = play.box_of("door_pow")
	_lab.world_sync.carve_sphere(door.get_center(), 0.6, 4, Vector3.BACK)
	await _frames(2)
	_check("a forced door goes on the payroll", "door_pow" in play.forced_doors and play.capture().forced_doors == ["door_pow"], str(play.forced_doors))
	_check("the shift save keeps the purchases", play.capture().purchases.get("vending_machine_glass", 0) == 3)


## A prop's box in world space (props with no use have no LevelPlay box).
func _prop_box(id: String) -> AABB:
	var box: AABB = LevelSchema.prop_box(_lab.level.objects[id])
	return AABB(_lab.view.to_world(box.position), box.size * _lab.world.voxel_size)


func _count_items(item: String) -> int:
	return _lab.items.pickups.values().filter(func(p) -> bool: return p.item == item).size()


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
