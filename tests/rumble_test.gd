extends SceneTree
## Pad rumble (docs/controls.md, section 6), headless:
##   godot --headless --path . --script res://tests/rumble_test.gd
## Headless has no pads, so the checks read Pad.last_rumble, the record of every rumble that passed
## the gates. Pad.rumble records only while a pad is in use and the Rumble setting is on; a
## stronger request replaces a weaker one in flight and a weaker one waits it out. Then in a
## scratch level (one concrete room): a shot, a melee swing, taking damage and dying rumble with
## the table's strengths, and nothing rumbles while editing or for a remote player's copy. Last,
## the settings menu has the Rumble row after Stick sensitivity and Enter flips it. The Rumble
## setting is saved and restored.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://rumble_test_levels/"
const LEVEL := "rumble_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIZE := Vector3i(8, 3, 8)
const ROOM := [Vector3i(8, 20, 8), Vector3i(248, 100, 248)]
const START := Vector3(12.0, 2.5, 12.0)

var _failures := 0
var _pad
var _settings
var _saved_rumble: Variant


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_pad = root.get_node("Pad")
	_settings = root.get_node("GameSettings")
	_saved_rumble = _settings.get_value("rumble")
	_check("rumble is a setting, On by default", _settings.KEYS.has("rumble") and _settings.KEYS.rumble[1] == true)
	_settings.set_value("rumble", 1)
	_check("an int validates to a bool", _settings.get_value("rumble") is bool and _settings.get_value("rumble") == true)
	_settings.set_value("rumble", "yes")
	_check("junk falls back to On", _settings.get_value("rumble") == true)
	_check_gates()
	_check_priority()

	LevelData.save_dir_override = SCRATCH
	_make_level()
	root.get_node("Net").start_solo(LEVEL, "play")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	var me = current_scene.local_player()
	await _frames(10)
	me.teleport(START)
	await _frames(5)
	_check_weapon(me)
	_check_damage(me)
	_check_settings_menu()
	_finish()


func _check_gates() -> void:
	_pad.active = true
	_settings.set_value("rumble", true)
	_fresh()
	_pad.rumble(0.3, 0.6, 0.2)
	var r: Dictionary = _pad.last_rumble
	_check("active and On: rumble records", not r.is_empty() and is_equal_approx(r.weak, 0.3) and is_equal_approx(r.strong, 0.6) and is_equal_approx(r.seconds, 0.2), str(r))
	_check("...with the time it started", r.get("at", -1) >= 0)
	_fresh()
	_settings.set_value("rumble", false)
	_pad.rumble(0.3, 0.6, 0.2)
	_check("the setting Off: nothing", _pad.last_rumble.is_empty(), str(_pad.last_rumble))
	_settings.set_value("rumble", true)
	_pad.active = false
	_pad.rumble(0.3, 0.6, 0.2)
	_check("no pad in use: nothing", _pad.last_rumble.is_empty(), str(_pad.last_rumble))
	_pad.active = true
	_pad.rumble(2.0, -1.0, 0.1)
	_check("strengths are clamped to 0..1", is_equal_approx(_pad.last_rumble.weak, 1.0) and is_equal_approx(_pad.last_rumble.strong, 0.0), str(_pad.last_rumble))


func _check_priority() -> void:
	_fresh()
	_pad.rumble(0.3, 0.0, 5.0)
	_pad.rumble(0.0, 0.8, 0.2)
	_check("a stronger request replaces a weaker one in flight", is_equal_approx(_pad.last_rumble.strong, 0.8), str(_pad.last_rumble))
	_pad.rumble(0.5, 0.0, 0.2)
	_check("a weaker one waits for the current one to end", is_equal_approx(_pad.last_rumble.strong, 0.8), str(_pad.last_rumble))
	_pad.stop_rumble()
	_pad.rumble(0.5, 0.0, 0.2)
	_check("after stop_rumble the weaker one goes", is_equal_approx(_pad.last_rumble.weak, 0.5), str(_pad.last_rumble))
	_fresh()
	_pad.rumble(0.1, 0.0, 0.001)
	OS.delay_msec(5)
	_pad.rumble(0.05, 0.0, 0.1)
	_check("once the current one ends, a weaker one goes", is_equal_approx(_pad.last_rumble.weak, 0.05), str(_pad.last_rumble))


func _check_weapon(me) -> void:
	var weapon = me.weapon
	_fresh()
	var fired: bool = weapon.fire()
	var r: Dictionary = _pad.last_rumble
	_check("a shot fires", fired)
	_check("a shot rumbles weak 0.25..0.5 for 0.06..0.1 s", not r.is_empty() and r.weak >= 0.25 and r.weak <= 0.5 and r.strong == 0.0 and r.seconds > 0.0 and r.seconds <= 0.1, str(r))
	_check("...and stays inside the ammo's cooldown", not r.is_empty() and r.seconds <= 1.0 / weapon.ammo.rate, str(r))
	_fresh()
	_check("the axe swings", weapon.melee())
	r = _pad.last_rumble
	_check("a melee swing rumbles weak 0.3 for 0.08 s", not r.is_empty() and is_equal_approx(r.weak, 0.3) and is_equal_approx(r.seconds, 0.08), str(r))
	_fresh()
	me.editing = true
	me.rumble(0.5, 0.5, 0.1)
	_check("nothing while editing", _pad.last_rumble.is_empty(), str(_pad.last_rumble))
	me.editing = false
	me.is_local = false
	me.rumble(0.5, 0.5, 0.1)
	_check("nothing for a remote player's copy", _pad.last_rumble.is_empty(), str(_pad.last_rumble))
	me.is_local = true


func _check_damage(me) -> void:
	_fresh()
	var amount: float = me.max_health * 0.25
	me.take_damage(amount, me.global_position + Vector3(1.0, 0.0, 0.0))
	var r: Dictionary = _pad.last_rumble
	_check("taking damage rumbles strong 0.4 + 0.6 x share for 0.2 s", not r.is_empty() and is_equal_approx(r.strong, 0.4 + 0.6 * 0.25) and is_equal_approx(r.seconds, 0.2), str(r))
	_fresh()
	me.take_damage(me.health + 1.0, me.global_position)
	r = _pad.last_rumble
	_check("the player died", me.is_dead)
	_check("death rumbles strong 1.0 for 0.6 s", not r.is_empty() and is_equal_approx(r.strong, 1.0) and is_equal_approx(r.seconds, 0.6), str(r))
	_fresh()
	me.take_damage(10.0, me.global_position)
	_check("...once: a dead player takes no more", _pad.last_rumble.is_empty(), str(_pad.last_rumble))


func _check_settings_menu() -> void:
	var menu_script = load("res://scripts/ui/settings_menu.gd")
	var keys: Array = menu_script.ROWS.map(func(row: Dictionary) -> String: return row.key)
	_check("Rumble follows Stick sensitivity", keys.find("rumble") == keys.find("stick_sensitivity") + 1, str(keys))
	_check("...before the volumes", keys.find("rumble") < keys.find("volume_master"), str(keys))
	var row: Dictionary = menu_script.ROWS[keys.find("rumble")]
	_check("it reads Off / On", row.label == "Rumble" and menu_script.value_text(row, false) == "Off" and menu_script.value_text(row, true) == "On")
	var menu = menu_script.create(1)
	root.add_child(menu)
	_check("Controls is still last", menu.rows[menu.rows.size() - 1].key == "controls")
	_settings.set_value("rumble", true)
	menu.selected = menu.rows.find(row)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	menu.handle_key(enter)
	_check("Enter turns it Off", _settings.get_value("rumble") == false)
	menu.handle_key(enter)
	_check("...and On again", _settings.get_value("rumble") == true)
	menu.queue_free()


## A clean slate: no rumble in flight and no record.
func _fresh() -> void:
	_pad.stop_rumble()
	_pad.last_rumble = {}


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
	var spawn := LevelSchema.new_marker("spawn", START / 0.1, 0.0)
	spawn.id = "spawn_1"
	level.objects[spawn.id] = spawn
	_check("level saves", level.save() == OK)


func _finish() -> void:
	_pad.stop_rumble()
	_pad.active = false
	_settings.set_value("rumble", _saved_rumble)
	print("rumble_test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
