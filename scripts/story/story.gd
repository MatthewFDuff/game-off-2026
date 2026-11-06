class_name Story
extends Node
## The story glue in play: LabHud adds it. It owns the Intercom (subtitles), the Experiment's
## effects and the Ending, and wires them to the level: trigger ids play intercom lines
## (Lines.INTERCOM), keycard doors say "clearance required / accepted", the first pickup of the
## spore shooter (LevelPlay arms the whole party and fires `armed`) shows everyone the controls
## sheet, the host counts deaths for the payroll, the `ending` trigger rolls the statement, and the
## yard rains. Levels without these triggers get nothing.

## How long the controls sheet shows when the gun is first picked up.
const CONTROLS_SECONDS := 6.0
const YARD_ROOM := "yard"
const RAIN_MARGIN := 2.0
## Meters over the yard's floor the drops start from, and how far inside its walls they stay.
const RAIN_HEIGHT := 12.0
const RAIN_INSET := 1.0

var lab: Lab
var intercom: Intercom
var experiment: Experiment
var ending: Ending
## Host: respawns the night took (players seen going from alive to dead). A resumed shift starts
## from the saved count (Lab.resumed_deaths, set before play starts).
var deaths := 0
var _was_dead := {}
var _rain: GPUParticles3D
var _raining := false


static func create(level: Lab) -> Story:
	var story := Story.new()
	story.lab = level
	return story


func _ready() -> void:
	name = "Story"
	intercom = Intercom.new()
	intercom.lab = lab
	add_child(intercom)
	experiment = Experiment.new()
	experiment.lab = lab
	add_child(experiment)
	ending = Ending.new()
	ending.lab = lab
	add_child(ending)
	lab.story = self
	var play := lab.play
	play.triggered.connect(_on_triggered)
	play.door_refused.connect(func(_id: String, _peer: int) -> void: intercom.say("gate_locked"))
	play.door_passed.connect(func(_id: String, _peer: int) -> void: intercom.say("gate_open"))
	if lab.items:
		lab.items.local_picked.connect(_on_local_picked)
	play.party_armed.connect(func() -> void: _on_local_picked("spore_shooter"))
	lab.player_spawned.connect(_on_player_spawned)
	deaths = lab.resumed_deaths
	lab.mode_changed.connect(func(_mode: String) -> void:
		_was_dead.clear()
		deaths = lab.resumed_deaths)


## Host: a trigger id fired; the intercom has a line for it, or it's the ending.
func _on_triggered(id: String, _peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if id == "ending":
		ending.begin(deaths)
		return
	intercom.say(id)


func _on_local_picked(item: String) -> void:
	if item != "spore_shooter":
		return
	for node in get_parent().get_children():
		if node is ControlsOverlay:
			node.show_for(CONTROLS_SECONDS)


## Late joiners and respawns: the local player is armed if the level doesn't start unarmed or the
## party has the spore shooter (LevelPlay.armed, which the host replicates and sends late joiners).
func _on_player_spawned(player: Player) -> void:
	if player.is_local and lab.mode == "play":
		player.set_armed(lab.play.is_armed_here())


func _process(_delta: float) -> void:
	if lab.mode != "play":
		_set_rain(false)
		return
	if multiplayer.is_server():
		for peer_id: int in lab.players:
			var player: Player = lab.players[peer_id]
			if player.is_dead and not _was_dead.get(peer_id, false):
				deaths += 1
			_was_dead[peer_id] = player.is_dead
	var me := lab.local_player()
	_set_rain(me != null and _in_yard(me.global_position))


func _in_yard(at: Vector3) -> bool:
	var room: Dictionary = lab.level.objects.get(YARD_ROOM, {})
	if room.is_empty():
		return false
	var box := AABB(lab.view.to_world(Vector3(room.from)), Vector3(room.to - room.from) * lab.world.voxel_size)
	return box.grow(RAIN_MARGIN).has_point(at)


## Rain over the yard: a cheap particle sheet above it and a looping wash, only while someone's out
## there to see it.
func _set_rain(on: bool) -> void:
	if on == _raining:
		return
	_raining = on
	if on:
		if _rain == null:
			_rain = _make_rain()
			lab.add_child(_rain)
		_rain.emitting = true
		Sfx.set_ambience("rain", -16.0, 1.0)
	else:
		if _rain:
			_rain.emitting = false
		Sfx.stop_ambience(1.0)


func _make_rain() -> GPUParticles3D:
	var room: Dictionary = lab.level.objects.get(YARD_ROOM, {})
	var size := Vector3(room.to - room.from) * lab.world.voxel_size
	var center := lab.view.to_world(Vector3(room.from + room.to) * 0.5)
	var rain := GPUParticles3D.new()
	rain.amount = 1200
	rain.lifetime = 1.6
	# The drops start RAIN_HEIGHT over the yard's floor and fall below it in their lifetime, so
	# the visibility box (local to the emitter) reaches from a little above it to the ground and
	# below: a box that only covered the air above the drops had the whole sheet culled whenever
	# the camera didn't look up at it (rain that came and went with the view angle).
	rain.visibility_aabb = AABB(Vector3(-size.x, -RAIN_HEIGHT - 4.0, -size.z), Vector3(size.x * 2.0, RAIN_HEIGHT + 6.0, size.z * 2.0))
	rain.position = Vector3(center.x, lab.world.global_position.y + room.from.y * lab.world.voxel_size + RAIN_HEIGHT, center.z)
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Inside the yard's walls with a margin, not over them: drops have no collision, so any that
	# started past the yard fell through the gatehouse roof and showed indoors.
	material.emission_box_extents = Vector3(maxf(size.x * 0.5 - RAIN_INSET, 1.0), 0.2, maxf(size.z * 0.5 - RAIN_INSET, 1.0))
	material.direction = Vector3.DOWN
	material.spread = 2.0
	material.initial_velocity_min = 7.0
	material.initial_velocity_max = 9.0
	material.gravity = Vector3(0.0, -3.0, 0.0)
	rain.process_material = material
	# Drops are voxel streaks (VoxelFx: one 0.05 m cube wide, snapped to the effect grid), faint by
	# true alpha blending (no dither).
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.3, 0.05)
	mesh.material = VoxelFx.alpha_material(0.05, true, Color(0.7, 0.8, 0.9, 0.45))
	rain.draw_pass_1 = mesh
	return rain
