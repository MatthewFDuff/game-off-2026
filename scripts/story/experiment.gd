class_name Experiment
extends Node
## What the training experiment looks and sounds like on every peer. LevelPlay runs the steps
## (host) and replicates the terminal's state; this listens to state_changed and, for a terminal
## with `steps`, flashes a light inside the specimen case beside it for each step (by the step's
## sound; a zap also sparks between its electrodes) and plays the crash in grow room 0 when the last
## result lands.

## The specimen prop's id (the training room's specimen_case). Without it, the nearest spore tank
## within TANK_REACH meters of the terminal stands in.
const SPECIMEN_ID := "specimen"
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
		var at := _specimen_near(id)
		_flash(at, FLASH_COLORS[sound])
		if sound == "zap":
			_spark(at, int(lab.level.objects.get(SPECIMEN_ID, {}).get("facing", 0)))
	var steps := Lines.parse_steps(str(object.steps))
	var last := steps.size() - 1
	if last >= 0 and int(state.get("step", 0)) == steps.size() and int(state.get("reveal", 0)) >= steps[last].results.size() and not state.get("used", false):
		_crash()


## Where the specimen's shroom is (world space): the middle of the specimen case, else the nearest
## spore tank's center, else the terminal's own.
func _specimen_near(terminal_id: String) -> Vector3:
	var specimen: Dictionary = lab.level.objects.get(SPECIMEN_ID, {})
	if specimen.get("kind") == "prop":
		var box := LevelSchema.prop_box(specimen)
		# The electrode tips, 8.5 voxels up the case (Props.specimen_case).
		return lab.view.to_world(box.position + Vector3(box.size.x * 0.5, 8.5, box.size.z * 0.5))
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


## A short bright arc across the specimen, between the electrodes.
func _spark(at: Vector3, facing: int) -> void:
	var arc := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.75, 0.04, 0.04)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = FLASH_COLORS.zap
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	arc.mesh = mesh
	arc.position = at
	if facing == 1 or facing == 3: # Props.EAST / WEST: the electrodes are along z.
		arc.rotation.y = PI * 0.5
	lab.add_child(arc)
	var tween := arc.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, FLASH_SECONDS * 0.6)
	tween.tween_callback(arc.queue_free)


func _crash() -> void:
	var room: Dictionary = lab.level.objects.get(CRASH_ROOM, {})
	if room.is_empty():
		Sfx.play("crash", -2.0)
		return
	var center := lab.view.to_world(Vector3(room.from + room.to) * 0.5)
	Sfx.play_at("crash", center, 2.0, 0.05)
