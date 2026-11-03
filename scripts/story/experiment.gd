class_name Experiment
extends Node
## What the training experiment looks and sounds like on every peer. LevelPlay runs the steps
## (host) and replicates the terminal's state; this listens to state_changed and, for a terminal
## with `steps`, flashes a light on the spore tank beside it for each step (by the step's sound)
## and plays the crash in grow room 0 when the last result lands.

## Meters from the terminal within which the nearest spore tank is "the specimen".
const TANK_REACH := 5.0
const FLASH_SECONDS := 0.45
## Sound played at a step -> the flash's color (none: no flash).
const FLASH_COLORS := {zap = Color(0.8, 0.9, 1.0), ui_blip = Color(1.0, 0.95, 0.7), splash = Color(0.5, 0.7, 1.0)}
## The room the crash comes from.
const CRASH_ROOM := "grow_0"

var lab: Lab


func _ready() -> void:
	name = "Experiment"
	lab.play.state_changed.connect(_on_state)


func _on_state(id: String, state: Dictionary, sound: String) -> void:
	var object: Dictionary = lab.level.objects.get(id, {})
	if str(object.get("steps", "")) == "":
		return
	if FLASH_COLORS.has(sound):
		_flash(_tank_near(id), FLASH_COLORS[sound])
	var steps := Lines.parse_steps(str(object.steps))
	var last := steps.size() - 1
	if last >= 0 and int(state.get("step", 0)) == steps.size() and int(state.get("reveal", 0)) >= steps[last].results.size() and not state.get("used", false):
		_crash()


## The nearest spore tank's center (world space), or the terminal's own.
func _tank_near(terminal_id: String) -> Vector3:
	var at: Vector3 = lab.play.box_of(terminal_id).get_center()
	var best := at + Vector3.UP * 0.5
	var best_distance := TANK_REACH
	for object: Dictionary in lab.level.objects.values():
		if object.kind != "prop" or not str(object.name).begins_with("spore_tank"):
			continue
		var box := LevelSchema.prop_box(object)
		var center := lab.view.to_world(box.get_center())
		var distance := center.distance_to(at)
		if distance < best_distance:
			best_distance = distance
			best = center
	return best


func _flash(at: Vector3, color: Color) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = 3.5
	light.position = at + Vector3.UP * 0.3
	lab.add_child(light)
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, FLASH_SECONDS)
	tween.tween_callback(light.queue_free)


func _crash() -> void:
	var room: Dictionary = lab.level.objects.get(CRASH_ROOM, {})
	if room.is_empty():
		Sfx.play("crash", -2.0)
		return
	var center := lab.view.to_world(Vector3(room.from + room.to) * 0.5)
	Sfx.play_at("crash", center, 2.0, 0.05)
