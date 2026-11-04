extends Node
## Settings autoload (`GameSettings`): owns user://settings.cfg, the file the old menu wrote, and
## applies each value where it belongs (docs/cubicle-menu.md, section 6). The cubicle's console
## and the pause panel's SettingsMenu read and write through get_value / set_value; set_value
## saves and applies at once and emits changed(key), which the local Player listens to for its
## look speed and field of view. The player's name, address and level keep the old menu's
## `player/*` keys so existing settings carry over; its `skip_intro` checkbox becomes
## orientation = "skip" the first time the file is read.

signal changed(key: String)

const PATH := "user://settings.cfg"
const NAME_LENGTH := 20
const RECENT_ADDRESSES := 5

## key -> [section, default]
const KEYS := {
	name = ["player", ""],
	address = ["player", "127.0.0.1"],
	level = ["player", "lab"],
	recent_addresses = ["player", []],
	orientation = ["game", "play"],
	shifts_worked = ["game", 0],
	balance_owed = ["game", 0],
	fullscreen = ["display", false],
	fov = ["display", 80],
	mouse_sensitivity = ["controls", 1.0],
	volume_master = ["audio", 10],
	volume_effects = ["audio", 10],
	volume_music = ["audio", 10],
}
const SENSITIVITY_RANGE := [0.5, 3.0, 0.25]
const FOV_RANGE := [60, 110, 5]
const VOLUME_RANGE := [0, 10, 1]

var _file := ConfigFile.new()
var _values := {}


func _ready() -> void:
	_load()
	apply_all()


func get_value(key: String) -> Variant:
	if not KEYS.has(key):
		push_warning("GameSettings: no setting '%s'." % key)
		return null
	return _values.get(key, KEYS[key][1])


## Validates value (clamped and snapped to the key's range), saves the file, applies it, and emits
## changed(key). Setting the address also puts it at the front of recent_addresses.
func set_value(key: String, value: Variant) -> void:
	if not KEYS.has(key):
		push_warning("GameSettings: no setting '%s'." % key)
		return
	_values[key] = _validate(key, value)
	if key == "address" and str(_values[key]) != "":
		var recent: Array = get_value("recent_addresses").duplicate()
		recent.erase(_values[key])
		recent.push_front(_values[key])
		_values.recent_addresses = recent.slice(0, RECENT_ADDRESSES)
	_save()
	_apply(key)
	changed.emit(key)
	if key == "address":
		changed.emit("recent_addresses")


## Applies every setting (at startup).
func apply_all() -> void:
	for key: String in KEYS:
		_apply(key)


## The dB a 0..10 volume setting stands for: 10 is 0 dB, 0 is silent.
static func volume_db(step: int) -> float:
	return linear_to_db(clampf(step / 10.0, 0.0, 1.0)) if step > 0 else Sfx.SILENT_DB * 2.0


func _apply(key: String) -> void:
	match key:
		"name":
			var player_name := str(get_value("name")).strip_edges()
			Net.player_name = player_name if player_name != "" else "Expendable"
		"fullscreen":
			if DisplayServer.get_name() == "headless":
				return
			var full: bool = get_value("fullscreen")
			var mode := DisplayServer.window_get_mode()
			var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
			if full and not is_full:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			elif not full and is_full:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		"volume_master":
			if AudioServer.get_bus_count() > 0:
				var step: int = get_value("volume_master")
				AudioServer.set_bus_mute(0, step <= 0)
				AudioServer.set_bus_volume_db(0, volume_db(maxi(step, 1)))
		"volume_effects", "volume_music":
			Sfx.set_mix(volume_db(get_value("volume_effects")), volume_db(get_value("volume_music")))
		# mouse_sensitivity and fov: the Player reads them; orientation, address, level and the
		# nameplate's numbers: the cubicle reads them.


func _validate(key: String, value: Variant) -> Variant:
	var fallback: Variant = KEYS[key][1]
	match key:
		"name":
			return str(value).strip_edges().left(NAME_LENGTH)
		"address", "level":
			return str(value).strip_edges()
		"recent_addresses":
			if value is Array:
				return (value as Array).map(func(a: Variant) -> String: return str(a)).slice(0, RECENT_ADDRESSES)
			return []
		"orientation":
			return "skip" if str(value) == "skip" else "play"
		"fullscreen":
			return bool(value) if value is bool or value is int else fallback
		"shifts_worked", "balance_owed":
			return int(value) if value is int or value is float else fallback
		"mouse_sensitivity":
			return _snap(value, SENSITIVITY_RANGE, fallback)
		"fov":
			return int(_snap(value, FOV_RANGE, fallback))
		"volume_master", "volume_effects", "volume_music":
			return int(_snap(value, VOLUME_RANGE, fallback))
	return value


static func _snap(value: Variant, range_: Array, fallback: Variant) -> float:
	if not (value is int or value is float):
		return float(fallback)
	return clampf(snappedf(float(value), float(range_[2])), float(range_[0]), float(range_[1]))


func _load() -> void:
	_file = ConfigFile.new()
	_file.load(PATH) # A missing file just leaves the defaults.
	_values.clear()
	for key: String in KEYS:
		var section: String = KEYS[key][0]
		if _file.has_section_key(section, key):
			_values[key] = _validate(key, _file.get_value(section, key))
	# The old menu's "Skip the intro" checkbox, the first time this file is read.
	if not _file.has_section_key("game", "orientation") and _file.get_value("player", "skip_intro", false) == true:
		_values.orientation = "skip"


func _save() -> void:
	# Other sections and keys already in the file (the old menu's skip_intro) are kept as they are.
	for key: String in _values:
		_file.set_value(KEYS[key][0], key, _values[key])
	var error := _file.save(PATH)
	if error != OK:
		push_warning("GameSettings: couldn't save %s (%s)." % [PATH, error_string(error)])
