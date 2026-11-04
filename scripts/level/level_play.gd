class_name LevelPlay
extends Node
## Play-mode runtime for a level's objects: doors, triggers, kill zones, company assets, the props
## players use with E (LevelSchema.USES), keycards and the power state. The host runs all of it and
## tells the peers; peers ask the host (request_use) and draw the results.
##
## Doors are voxels while still, so collision, bullets, enemies and damage need nothing special.
## While a door moves, its voxels are erased, a mesh of it slides, and it's stamped again where it
## stops. Asset damage is the share of an asset's voxels that are gone, priced at its value.
##
## Usable props keep their state in prop_state (id -> {used, charges}); the host changes it and
## sends it to everyone, late joiners included. Keycards are party-wide: one player picking a
## keycard up opens its doors for everyone. So is the spore shooter in `start_unarmed` levels: the
## first pickup (or the "armed" trigger) arms every player, late joiners and respawns included.
## Power is "facility" (normal), "backup" (emergency lights only; terminals that need power and
## powered doors refuse) or "restored" (the generator ran).
##
## Trigger actions: a trigger marker's `actions` field runs whenever its id fires (its volume, a
## terminal's or the generator's `on_use`, the director's "finale_survived" / "finale_failed", a
## spawner's `on_dead`), comma-separated: `power=facility|backup|restored`, `lock=<door>`,
## `unlock=<door>`, `open=<door>`, `close=<door>` (story moves, locks ignored), `on=<spawner>`,
## `off=<spawner>`, `horde`, `wake` (HordeDirector.wake: spawning begins in a `spawns_dormant`
## level), `wither` (Mycelium.wither: the colony greys and crumbles), `pulse` / `pulse=<0..1>`
## (Mycelium.pulse: the veins throb), `lights=<room>:off|on|flicker` (the lights in a room's or
## trigger volume's box) and `sprinkle=<room>` (sprinklers for 8 s: fire out, clouds gone, lights
## flicker; both InteractRules). The host runs them; the results replicate as usual.
##
## The newer uses (switch, vendor, eyewash, defib, extinguisher, flip, printer, radio, squeak), the
## props that react by name (extinguishers, gas cylinders), crushing fragments and forced doors are
## InteractRules (the "Rules" child). The payroll keeps purchases (vendor prices: charge) and forced
## doors (force_door, FORCED_DOOR_FEE each) beside the damage.
##
## Checkpoint: the clone vat the party reached last (any living player within CHECKPOINT_REACH of
## its marker); Lab respawns the dead there. The host decides and tells everyone.
##
## Shift saves (docs/shift-save.md): the host asks Lab.save_shift() when the checkpoint changes, after
## a trigger whose actions lock a door, and as the generator starts (before it changes anything, so
## a resume restarts the finale at the generator). capture() is what the save holds of this node;
## restore() puts it back after Lab has replaced the world (replace_world).

## Host: a trigger fired. peer_id is the player who set it off (for "all", the last one in). Also
## fired by terminals and the generator with their `on_use` id.
signal triggered(id: String, peer_id: int)
## Every peer: the party got the spore shooter (arm_party); everyone here is armed now.
signal party_armed
## Host: an asset lost dollars worth of voxels. total is all asset damage so far.
signal asset_damaged(id: String, dollars: int, total: int)
## Host: a player walked into a kill zone.
signal killed_in_zone(id: String, peer_id: int)
## Every peer: the power state changed ("facility", "backup" or "restored").
signal power_changed(state: String)
## Host: a player used a prop (after the host accepted it).
signal prop_used(id: String, peer_id: int)
## This peer: a note or terminal opened on screen (id), or closed ("").
signal reading_changed(id: String)
## Every peer: a usable prop's state changed (the host decided); sound is what played at it.
signal state_changed(id: String, state: Dictionary, sound: String)
## Host: a keycard or locked door refused a player.
signal door_refused(id: String, peer_id: int)
## Host: a keycard door was opened by a player who had its card.
signal door_passed(id: String, peer_id: int)

## How close (meters) a player must be to use a door or prop.
const DOOR_REACH := 3.0
## Extra meters the host allows a peer's use request, since its player's position here lags its own.
const USE_SLACK := 2.0
## Meters from a clone vat marker that makes it the checkpoint.
const CHECKPOINT_REACH := 3.0
const POWER_STATES := ["facility", "backup", "restored"]
## Rounds an ammo bench gives per use.
const STATION_AMMO := 20
const Rules := preload("res://scripts/interact/interact_rules.gd")
## Dollars a forced door costs on the payroll.
const FORCED_DOOR_FEE := 500

@export var lab: Lab

var active := false
## Host: dollars of asset damage per asset name since play started (the payroll statement).
var damage_by_name := {}
## Host: dollars of asset damage since play started.
var total_damage := 0
## Host: dollars charged to the payroll per thing bought (vending machines, coffee), since play
## started (the payroll statement's purchases).
var purchases := {}
## Host: ids of doors forced (broken through) since play started, FORCED_DOOR_FEE each.
var forced_doors: Array[String] = []
## Every peer (the host decides): "facility", "backup" or "restored".
var power := "facility"
## Every peer (the host decides): keycard colors the party holds ("red", ...).
var keycards: Array[String] = []
## Every peer (the host decides): the party has the spore shooter (see is_armed_here). Only matters
## in `start_unarmed` levels; set by the first spore_shooter pickup or the "armed" trigger.
var armed := false
## Every peer (the host decides): usable prop id -> {used: bool, charges: int}. Props not in here
## are untouched (see state_of).
var prop_state := {}
## This peer: the note or terminal on screen, or "".
var reading := ""
## Every peer (the host decides): the clone vat marker id the party respawns at, or "" (the first).
var checkpoint := ""
## Finds what the local player is looking at and words the prompt.
var interactables := Interactables.new(self)
## The newer uses, the props that react by name, room lights and sprinklers (a child, "Rules").
var rules: Rules

## id -> {object, model (turned), origin: Vector3i, open: bool, moving: bool}
var _doors := {}
## id -> {origin, size, voxels, total, intact, value, name}
var _assets := {}
## Every peer: usable (non-door) prop id -> its box in world space.
var _usables := {}
## Host: glass case id -> {origin, size, voxels (its GLASS voxels only), intact}
var _glass := {}
## Trigger ids that already fired (one-shot ones). (_inside is unused now: each volume in _volumes
## keeps the peers inside it, for edge detection.)
var _fired := {}
var _inside := {}
## Host: the assets, glass cases and every non-door prop (by LevelSchema.prop_box) in chunk indexes,
## so a voxel change or a shattered pane only tests what is in the chunks it touched. Built at start;
## an asset that moves or changes size is put back with index_asset.
var _asset_index := ChunkIndex.new()
var _glass_index := ChunkIndex.new()
var _prop_index := ChunkIndex.new()
## Every peer: usable (non-door) props by voxel box, for Interactables (usables_near).
var _usable_index := ChunkIndex.new()
## Host: the clone vats, triggers and kill zones, with their world-space boxes, built at start, so
## the physics tick doesn't walk every object in the level. Each is {object, vat: bool, kill: bool,
## at (a vat's point), box (a volume's), inside: Array[int] (peers in it last tick)}.
var _volumes: Array[Dictionary] = []
## The spare peers-inside list a volume swaps with each tick (no allocation per tick).
var _scratch_inside: Array[int] = []


func _ready() -> void:
	rules = Rules.new()
	rules.name = "Rules"
	rules.play = self
	add_child(rules)
	lab.peer_entered.connect(_send_state)
	triggered.connect(_run_actions)
	triggered.connect(func(id: String, _peer_id: int) -> void:
		if id == "armed":
			arm_party(_peer_id))
	# The host's own player spawns after play starts; joiners' players may too.
	lab.player_spawned.connect(func(player: Player) -> void:
		if player.is_local and active:
			player.set_armed(is_armed_here()))
	if lab.items:
		lab.items.picked.connect(_on_picked)


## Every peer, when play begins (props already stamped by the host).
func start() -> void:
	active = true
	total_damage = 0
	damage_by_name.clear()
	_doors.clear()
	_assets.clear()
	_usables.clear()
	_glass.clear()
	_asset_index.clear()
	_glass_index.clear()
	_prop_index.clear()
	_usable_index.clear()
	_fired.clear()
	_inside.clear()
	prop_state.clear()
	keycards.clear()
	armed = false
	purchases.clear()
	forced_doors.clear()
	checkpoint = ""
	close_reading()
	_apply_armed()
	var start_power := str(lab.level.settings.get("start_power", "facility"))
	power = start_power if start_power in POWER_STATES else "facility"
	power_changed.emit(power)
	var host := multiplayer.is_server()
	_volumes = []
	for object: Dictionary in lab.level.objects.values():
		if object.kind == "marker":
			if host:
				_add_volume(object)
			continue
		if object.kind != "prop":
			continue
		if host and not object.door:
			_prop_index.insert(object.id, LevelSchema.prop_box(object))
		var turned := Props.oriented(object.name, object.facing)
		if turned.is_empty():
			continue
		if object.door:
			_doors[object.id] = {object = object, model = turned, origin = object.origin, open = false, moving = false}
			continue
		if object.get("use", "none") != "none":
			_usables[object.id] = AABB(lab.view.to_world(Vector3(object.origin)), Vector3(turned.size) * lab.world.voxel_size)
			_usable_index.insert(object.id, AABB(Vector3(object.origin), Vector3(turned.size)))
		if not host:
			continue
		if object.value > 0:
			var intact: int = lab.world.count_matching(object.origin, turned.size, turned.voxels)
			_assets[object.id] = {origin = object.origin, size = turned.size, voxels = turned.voxels,
					total = maxi(intact, 1), intact = intact, value = object.value, name = object.name}
			index_asset(object.id)
		if object.get("use") == "glass_case":
			var glass: PackedByteArray = turned.voxels.duplicate()
			for i in glass.size():
				if glass[i] != VoxelMaterials.GLASS:
					glass[i] = 0
			var intact_glass: int = lab.world.count_matching(object.origin, turned.size, glass)
			if intact_glass > 0:
				_glass[object.id] = {origin = object.origin, size = turned.size, voxels = glass, intact = intact_glass}
				_glass_index.insert(object.id, AABB(Vector3(object.origin), Vector3(turned.size)))
	if multiplayer.is_server() and not lab.world.voxels_changed.is_connected(_on_voxels_changed):
		lab.world.voxels_changed.connect(_on_voxels_changed)
	rules.start()


func stop() -> void:
	active = false
	rules.stop()
	_doors.clear()
	_assets.clear()
	_usables.clear()
	_glass.clear()
	_asset_index.clear()
	_glass_index.clear()
	_prop_index.clear()
	_usable_index.clear()
	_volumes = []
	close_reading()
	if lab.world.voxels_changed.is_connected(_on_voxels_changed):
		lab.world.voxels_changed.disconnect(_on_voxels_changed)


## Host peers that get state messages: everyone in the level but the host.
func _peers() -> Array[int]:
	var out: Array[int] = []
	if multiplayer.is_server():
		for peer_id in lab.peers_in_level:
			if peer_id != 1:
				out.append(peer_id)
	return out


## Host: a clone vat, trigger or kill zone marker joins _volumes (others are ignored).
func _add_volume(object: Dictionary) -> void:
	if object.type == "clone_vat":
		_volumes.append({object = object, vat = true, kill = false, at = lab.view.to_world(object.position)})
	elif object.type == "trigger" or object.type == "kill_zone":
		var box := LevelSchema.marker_box(object)
		var inside: Array[int] = []
		_volumes.append({object = object, vat = false, kill = object.type == "kill_zone",
				box = AABB(lab.view.to_world(box.position), box.size * lab.world.voxel_size), inside = inside})


## Host: puts an asset's index entry where its record now says (call after it moves or changes
## size; an id no longer in _assets is dropped).
func index_asset(id: String) -> void:
	var asset: Dictionary = _assets.get(id, {})
	if asset.is_empty():
		_asset_index.remove(id)
	else:
		_asset_index.insert(id, AABB(Vector3(asset.origin), Vector3(asset.size)))


## Every peer: ids of the usable (non-door) props whose voxel box comes within reach meters of a
## world point, for Interactables. In level order.
func usables_near(at: Vector3, reach: float) -> Array:
	var voxel := lab.world.voxel_size
	var center := (at - lab.world.global_position) / voxel
	var half := Vector3.ONE * (reach / voxel + 1.0)
	return _usable_index.query(AABB(center - half, half * 2.0))


# --- Doors ---------------------------------------------------------------------------------------

## The door the player is looking at within reach, or "".
func door_in_view(camera: Camera3D) -> String:
	var id := interactables.in_view(camera)
	return id if _doors.has(id) else ""


## True when the door is locked (door_locked) or needs a keycard the party doesn't have.
func is_door_locked(id: String) -> bool:
	if not _doors.has(id):
		return false
	var key := door_key(id)
	return _doors[id].object.door_locked or (key != "" and key not in keycards)


## The keycard color a door needs ("red"), or "".
func door_key(id: String) -> String:
	if not _doors.has(id):
		return ""
	return str(_doors[id].object.get("door_key", "")).strip_edges().trim_prefix("keycard_")


## Why a door won't open right now ("Locked", "Locked: needs red keycard", "No power"), or "".
func door_refusal(id: String) -> String:
	if not _doors.has(id):
		return ""
	var object: Dictionary = _doors[id].object
	if object.door_locked:
		return "Locked"
	var key := door_key(id)
	if key != "" and key not in keycards:
		return "Locked: needs %s keycard" % key
	if object.get("door_power", false) and power == "backup":
		return "No power"
	return ""


func is_door(id: String) -> bool:
	return _doors.has(id)


func is_door_open(id: String) -> bool:
	return _doors.has(id) and _doors[id].open


## A door's current box in world space (it moves when opened).
func door_box(id: String) -> AABB:
	var door: Dictionary = _doors[id]
	return AABB(lab.view.to_world(Vector3(door.origin)), Vector3(door.model.size) * lab.world.voxel_size)


## Ids of every door, then every usable prop.
func usable_ids() -> Array:
	return _doors.keys() + _usables.keys()


## A usable thing's box in world space (an empty AABB if unknown).
func box_of(id: String) -> AABB:
	if _doors.has(id):
		return door_box(id)
	return _usables.get(id, AABB())


## Any peer: asks the host to open or close a door (the interact key). Locked doors refuse.
func request_toggle(id: String) -> void:
	request_use(id)


## Host (story scripts): opens or closes a door, locked or not.
func set_door(id: String, open: bool) -> void:
	var door: Dictionary = _doors.get(id, {})
	if door.is_empty() or door.moving or door.open == open:
		return
	var closed: Vector3i = door.object.origin
	var target: Vector3i = closed + door.object.door_offset if open else closed
	var distance := Vector3(target - door.origin).length() * lab.world.voxel_size
	var duration := maxf(distance / maxf(door.object.door_speed, 0.1), 0.05)
	door.moving = true
	# Where it is going, for a shift saved mid-slide (capture).
	door.target = target
	door.target_open = open
	lab.world_sync.stamp_model(door.origin, door.model.size, door.model.voxels, true)
	_door_motion(id, door.origin, target, duration, open)
	for peer_id in lab.world_sync.synced_peers():
		_door_motion.rpc_id(peer_id, id, door.origin, target, duration, open)
	await get_tree().create_timer(duration).timeout
	if not active or not _doors.has(id):
		return
	lab.world_sync.stamp_model(target, door.model.size, door.model.voxels)
	_door_settled(id, target, open)
	# Same audience as the motion and the voxels, so a peer still entering hears it end too.
	for peer_id in lab.world_sync.synced_peers():
		_door_settled.rpc_id(peer_id, id, target, open)


## Host (story scripts): locks or unlocks a door.
func set_door_locked(id: String, locked: bool) -> void:
	if not _doors.has(id):
		return
	_doors[id].object.door_locked = locked
	if multiplayer.is_server():
		for peer_id in _peers():
			_door_locked.rpc_id(peer_id, id, locked)


@rpc("authority", "reliable")
func _door_locked(id: String, locked: bool) -> void:
	if _doors.has(id):
		_doors[id].object.door_locked = locked


## Every peer: slides a mesh of the door while its voxels are gone. The door is `moving` (E on it
## does nothing) until _door_settled.
@rpc("authority", "reliable")
func _door_motion(id: String, from: Vector3i, to: Vector3i, duration: float, open: bool) -> void:
	var door: Dictionary = _doors.get(id, {})
	if door.is_empty():
		return
	door.origin = from
	door.moving = true
	door.target = to
	door.target_open = open
	var mesh := MeshInstance3D.new()
	mesh.mesh = lab.view.prop_mesh(door.object.name, door.object.facing)
	mesh.material_override = lab.world.material
	mesh.position = lab.view.to_world(Vector3(from))
	lab.view.add_child(mesh)
	var tween := mesh.create_tween()
	tween.tween_property(mesh, "position", lab.view.to_world(Vector3(to)), duration)
	# Linger a frame past the end so the stamped voxels are there before the mesh goes.
	tween.tween_interval(0.1)
	tween.tween_callback(mesh.queue_free)


## Every peer: the door is stamped at origin and has stopped, open or closed. Peers learn `open`
## here, so their prompt and their E (request_use) say the right way.
@rpc("authority", "reliable")
func _door_settled(id: String, origin: Vector3i, open: bool) -> void:
	var door: Dictionary = _doors.get(id, {})
	if door.is_empty():
		return
	door.origin = origin
	door.open = open
	door.moving = false
	rules.door_moved(id)


# --- Using things (E) ---------------------------------------------------------------------------

## Any peer: asks the host to use a door or prop (the interact key). The host checks it's allowed
## (locks, keycards, power, charges) and tells the user why not if it isn't. A peer's E on a door
## asks for the way it saw it go (the host ignores it if the door is already that way or moving),
## so a stale view or two players pressing E at once don't shut a door the other just opened.
func request_use(id: String) -> void:
	if multiplayer.is_server():
		_use(id, multiplayer.get_unique_id())
	elif _doors.has(id):
		_request_door.rpc_id(1, id, not _doors[id].open)
	else:
		_request_use.rpc_id(1, id)


@rpc("any_peer", "reliable")
func _request_use(id: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if _can_use(sender, id):
		_use(id, sender)


@rpc("any_peer", "reliable")
func _request_door(id: String, open: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if _can_use(sender, id):
		_use(id, sender, 1 if open else 0)


## Host: a peer's request counts only from a player in the level, alive, and near the thing (its
## own in_view reach, with slack for where its state packets lag behind it).
func _can_use(peer_id: int, id: String) -> bool:
	if not multiplayer.is_server() or peer_id not in lab.peers_in_level:
		return false
	var player: Player = lab.players.get(peer_id)
	if player == null or not is_instance_valid(player) or player.is_dead:
		return false
	var box := box_of(id)
	if box.size == Vector3.ZERO:
		return true # Not a door or usable; _use sorts it out.
	var eye: Vector3 = player.global_position + Vector3.UP * player.standing_height
	return eye.clamp(box.position, box.end).distance_to(eye) <= DOOR_REACH + USE_SLACK


## A prop's state: {used, charges}, defaults (unused, its charges field) if it hasn't been touched.
func state_of(id: String) -> Dictionary:
	if prop_state.has(id):
		return prop_state[id]
	var object: Dictionary = lab.level.objects.get(id, {}) if lab.level else {}
	return {used = false, charges = int(object.get("charges", 0))}


## Host: what E does (see LevelSchema.USES). door_open: for a door, 1 open or 0 close (what the
## user saw); -1 toggles.
func _use(id: String, peer_id: int, door_open := -1) -> void:
	if not active:
		return
	if _doors.has(id):
		var door: Dictionary = _doors[id]
		var open: bool = not door.open if door_open < 0 else door_open == 1
		if door.moving or open == door.open:
			return
		var why := door_refusal(id)
		if why != "":
			lab.notify_peer(peer_id, why)
			door_refused.emit(id, peer_id)
		else:
			if open and door_key(id) != "":
				door_passed.emit(id, peer_id)
			set_door(id, open)
		return
	var object: Dictionary = lab.level.objects.get(id, {})
	if object.get("kind") != "prop":
		return
	var state := state_of(id).duplicate()
	match str(object.get("use", "none")):
		"container":
			if state.used:
				return
			state.used = true
			_set_state(id, state, "drawer_open")
			_drop_contents(object)
		"note":
			_show_text(peer_id, id)
		"terminal":
			if object.get("needs_power", false) and power == "backup":
				lab.notify_peer(peer_id, "No power")
				return
			_show_text(peer_id, id)
			if str(object.get("steps", "")).strip_edges() != "":
				return # An experiment: SHIFT runs its steps (request_step); it's used up when they're done.
			if not state.used:
				state.used = true
				_set_state(id, state, "")
				if str(object.get("on_use", "")) != "":
					triggered.emit(object.on_use, peer_id)
		"station_medkit", "station_ammo":
			if state.charges <= 0:
				lab.notify_peer(peer_id, "It's empty")
				return
			state.charges -= 1
			state.used = true
			_set_state(id, state, "station_use")
			if object.use == "station_medkit":
				_heal_peer(peer_id)
			else:
				_ammo_peer(peer_id, str(object.get("station_ammo_type", "")))
		"generator":
			if state.used or power != "backup":
				lab.notify_peer(peer_id, "It's running" if state.used or power == "restored" else "Not needed: the power is on")
				return
			# Saved before anything changes: a resume puts the party back at the generator, not mid-finale.
			lab.save_shift()
			state.used = true
			_set_state(id, state, "")
			set_power("restored")
			if str(object.get("on_use", "")) != "":
				triggered.emit(object.on_use, peer_id)
			if lab.director:
				lab.director.finale(float(object.get("finale_seconds", 120.0)))
		"glass_case":
			smash_glass(id)
		_:
			if not rules.use(id, object, state, peer_id):
				return
	prop_used.emit(id, peer_id)


## Any peer: runs the next step of an experiment terminal (SHIFT while reading it).
func request_step(id: String) -> void:
	if multiplayer.is_server():
		_step(id, multiplayer.get_unique_id())
	else:
		_request_step.rpc_id(1, id)


@rpc("any_peer", "reliable")
func _request_step(id: String) -> void:
	if multiplayer.is_server():
		_step(id, multiplayer.get_remote_sender_id())


## Host: one step of an experiment: prints its results (the last step's one at a time), then
## marks the terminal used and fires its `on_use`.
func _step(id: String, peer_id: int) -> void:
	if not active:
		return
	var object: Dictionary = lab.level.objects.get(id, {})
	var steps := Lines.parse_steps(str(object.get("steps", "")))
	if steps.is_empty():
		return
	var state := state_of(id).duplicate()
	var index := int(state.get("step", 0))
	if state.used or index >= steps.size():
		return
	var last := index == steps.size() - 1
	state.step = index + 1
	state.reveal = 1 if last else 0
	_set_state(id, state, _step_sound(index))
	if not last:
		return
	while int(state.reveal) < steps[index].results.size():
		await get_tree().create_timer(Lines.REVEAL_SECONDS).timeout
		if not active or state_of(id).get("step", 0) != state.step:
			return
		state = state_of(id).duplicate()
		state.reveal = int(state.reveal) + 1
		# The last result is the crash: Experiment plays it in grow room 0, not at the terminal.
		_set_state(id, state, "terminal_beep" if int(state.reveal) < steps[index].results.size() else "")
	state = state_of(id).duplicate()
	state.used = true
	_set_state(id, state, "")
	if str(object.get("on_use", "")) != "":
		triggered.emit(object.on_use, peer_id)


## What the tank does on a step: the Lines table's effect for it, else a beep.
static func _step_sound(index: int) -> String:
	if index < Lines.EXPERIMENT.size():
		match str(Lines.EXPERIMENT[index].effect):
			"zap": return "zap"
			"water": return "splash"
			"light": return "ui_blip"
			"prod": return "station_use"
	return "terminal_beep"


## The text a note or terminal shows now: its `text`, plus for an experiment the steps run so far
## (the last one's results as far as revealed), the next prompt, or what it says when done.
func reading_text(id: String) -> String:
	var object: Dictionary = lab.level.objects.get(id, {})
	var text := str(object.get("text", "")).strip_edges()
	var steps := Lines.parse_steps(str(object.get("steps", "")))
	if steps.is_empty():
		return text
	var state := state_of(id)
	var index := int(state.get("step", 0))
	var lines: Array[String] = []
	if text != "":
		lines.append(text)
	for i in mini(index, steps.size()):
		lines.append("\n" + steps[i].prompt)
		var shown: int = steps[i].results.size() if i < steps.size() - 1 else int(state.get("reveal", 0))
		for r in mini(shown, steps[i].results.size()):
			lines.append("  " + steps[i].results[r])
	if state.used:
		lines.append("\n" + Lines.EXPERIMENT_DONE)
	elif index < steps.size():
		lines.append("\n" + steps[index].prompt + "   [SHIFT]")
	return "\n".join(lines)


## Host: puts a prop back to its starting state (unused, full charges), e.g. a retried generator.
func reset_prop(id: String) -> void:
	if not multiplayer.is_server():
		return
	var object: Dictionary = lab.level.objects.get(id, {})
	_set_state(id, {used = false, charges = int(object.get("charges", 0))}, "")


## Host: sets a prop's state everywhere and plays sound (if any) at the prop.
func _set_state(id: String, state: Dictionary, sound: String) -> void:
	_apply_state(id, state, sound)
	for peer_id in _peers():
		_prop_state_changed.rpc_id(peer_id, id, state, sound)


@rpc("authority", "reliable")
func _prop_state_changed(id: String, state: Dictionary, sound: String) -> void:
	_apply_state(id, state, sound)


func _apply_state(id: String, state: Dictionary, sound: String) -> void:
	prop_state[id] = state
	state_changed.emit(id, state, sound)
	if reading == id:
		reading_changed.emit(id) # The reader re-reads the text (experiment steps).
	if sound == "":
		return
	var box := box_of(id)
	Sfx.play_at(sound, box.get_center())
	if sound == "glass_break":
		lab.debris.burst(box.get_center(), front_of(lab.level.objects.get(id, {})), {VoxelMaterials.GLASS: 16})


## A prop's front direction in the world (where its front faces).
static func front_of(object: Dictionary) -> Vector3:
	match int(object.get("facing", Props.NORTH)):
		Props.EAST:
			return Vector3.RIGHT
		Props.SOUTH:
			return Vector3.BACK
		Props.WEST:
			return Vector3.LEFT
	return Vector3.FORWARD


## Host: spawns a prop's contents (comma-separated pickup names) on the floor in front of it, side
## by side.
func _drop_contents(object: Dictionary) -> void:
	var items: Array[String] = []
	for part in str(object.get("contents", "")).split(",", false):
		if part.strip_edges() != "":
			items.append(part.strip_edges())
	if items.is_empty() or lab.items == null:
		return
	var box := LevelSchema.prop_box(object)
	var world_box := AABB(lab.view.to_world(box.position), box.size * lab.world.voxel_size)
	var front := front_of(object)
	var side := front.cross(Vector3.UP)
	var center := world_box.get_center()
	var reach := absf(world_box.size.dot(front)) * 0.5 + 0.45
	for i in items.size():
		var at := center + front * reach + side * (i - (items.size() - 1) * 0.5) * 0.4
		var down: Dictionary = lab.world.raycast(Vector3(at.x, world_box.position.y + minf(world_box.size.y, 1.5), at.z), Vector3.DOWN, 4.0)
		var floor_y: float = down.position.y if down.hit else world_box.position.y
		lab.items.spawn(items[i], Vector3(at.x, floor_y + ItemManager.HOVER, at.z))


## Host: shows a note's or terminal's text to the player who used it.
func _show_text(peer_id: int, id: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		open_reading(id)
	else:
		_read.rpc_id(peer_id, id)


@rpc("authority", "reliable")
func _read(id: String) -> void:
	open_reading(id)


## This peer: puts a note's or terminal's text on screen (InteractPrompt draws it).
func open_reading(id: String) -> void:
	reading = id
	Sfx.play("terminal_beep", -4.0)
	reading_changed.emit(id)


func close_reading() -> void:
	if reading == "":
		return
	reading = ""
	reading_changed.emit("")


## Host: a medkit station heals its user. Each peer runs its own player, so this goes to the user's
## peer (like enemy bites).
func _heal_peer(peer_id: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		_heal_here()
	else:
		_heal.rpc_id(peer_id)


@rpc("authority", "reliable")
func _heal() -> void:
	_heal_here()


func _heal_here() -> void:
	var me := lab.local_player()
	if me and not me.is_dead:
		me.health = me.max_health
		lab.notify("Healed to full", false)


## Host: an ammo bench gives its user STATION_AMMO rounds of ammo_type ("" = their loaded type).
func _ammo_peer(peer_id: int, ammo_type: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		_ammo_here(ammo_type)
	else:
		_ammo.rpc_id(peer_id, ammo_type)


@rpc("authority", "reliable")
func _ammo(ammo_type: String) -> void:
	_ammo_here(ammo_type)


## The user's peer: picks the type (the bench's, else the loaded one, else the first limited type
## they have rounds of, else shotgun) and adds the rounds.
func _ammo_here(ammo_type: String) -> void:
	var me := lab.local_player()
	if me == null or me.inventory == null:
		return
	var type: AmmoType = AmmoType.by_name(ammo_type.trim_prefix("ammo_")) if ammo_type != "" else null
	if type == null and me.weapon:
		type = AmmoType.by_name(str(me.weapon.current))
	if type == null or type.infinite:
		type = null
		for candidate in AmmoType.all():
			if not candidate.infinite and me.inventory.count(candidate.name) > 0:
				type = candidate
				break
	if type == null:
		type = AmmoType.by_name("shotgun")
	if type and me.inventory.add("ammo_" + type.name, STATION_AMMO):
		lab.notify("+%d %s ammo" % [STATION_AMMO, type.label], false)


## Host: breaks a glass case's glass (E, or story code): its GLASS voxels go through WorldSync and
## the contents drop.
func smash_glass(id: String) -> void:
	var glass: Dictionary = _glass.get(id, {})
	if glass.is_empty():
		return
	_break_glass(id)
	lab.world_sync.stamp_model(glass.origin, glass.size, glass.voxels, true)


## Host: a glass case broke (shot or smashed). Once per case.
func _break_glass(id: String) -> void:
	var state := state_of(id).duplicate()
	if state.used:
		return
	state.used = true
	_set_state(id, state, "glass_break")
	_drop_contents(lab.level.objects.get(id, {}))


## Host: a glass pane shattered (Glass; voxels already cleared, carved more went in the hit itself).
## Props holding any of it react by name; glass outside every prop goes on the payroll as
## "glass_pane" at Glass.PRICE a voxel (a prop's own glass is billed as its asset damage).
func glass_shattered(voxels: Array, carved: int, at: Vector3) -> void:
	if not active or not multiplayer.is_server():
		return
	var points: Array = voxels if not voxels.is_empty() else [lab.world.world_to_voxel(at)]
	var lo: Vector3i = points[0]
	var hi: Vector3i = points[0]
	for p: Vector3i in points:
		lo = lo.min(p)
		hi = hi.max(p)
	var bounds := AABB(Vector3(lo), Vector3(hi - lo + Vector3i.ONE))
	# The props near the pane (ChunkIndex, in level order), not every prop in the level.
	var boxes := {}
	for id: String in _prop_index.query(bounds):
		boxes[id] = _prop_index.boxes[id]
	var held := {}
	var loose := 0
	for p: Vector3i in voxels:
		var inside := false
		for id: String in boxes:
			if (boxes[id] as AABB).has_point(Vector3(p) + Vector3.ONE * 0.5):
				held[id] = true
				inside = true
				break
		if not inside:
			loose += 1
	if voxels.is_empty():
		for id: String in boxes:
			held[id] = true
	if held.is_empty():
		loose += carved
	if loose > 0:
		bill("glass_pane", loose * Glass.PRICE, at)
	for id: String in held:
		_glass_reaction(lab.level.objects[id], boxes[id])


## Host: damage that isn't a placed asset's voxels (a loose glass pane), on the payroll as what.
func bill(what: String, dollars: int, at: Vector3) -> void:
	if dollars <= 0:
		return
	total_damage += dollars
	damage_by_name[what] = int(damage_by_name.get(what, 0)) + dollars
	asset_damaged.emit(what, dollars, total_damage)


## Host: a prop whose glass shattered, by name: a spore tank vents its spores, a clone vat drains,
## a light fixture goes dark, an aquarium spills.
func _glass_reaction(object: Dictionary, box: AABB) -> void:
	var prop_name: String = object.name
	var from := Vector3i(box.position)
	var to := Vector3i(box.end)
	if prop_name.begins_with("spore_tank"):
		_swap_in_box(from, to, [VoxelMaterials.LIQUID_GREEN], VoxelMaterials.AIR)
		Cloud.spawn("spore", lab.view.to_world(box.get_center()), SporeShroom.CLOUD_RADIUS, SporeShroom.CLOUD_SECONDS)
	elif prop_name.begins_with("clone_vat"):
		_swap_in_box(from, to, [VoxelMaterials.LIQUID_GREEN, VoxelMaterials.LIQUID_BLUE, VoxelMaterials.LIQUID_PINK, VoxelMaterials.WATER], VoxelMaterials.AIR)
		Sfx.play_at("splash", lab.view.to_world(box.get_center()))
	elif prop_name.begins_with("fixture_"):
		_swap_in_box(from, to, [VoxelMaterials.LAMP], VoxelMaterials.CHAR)
	elif prop_name.begins_with("aquarium"):
		var spilled := _swap_in_box(from, to, [VoxelMaterials.WATER], VoxelMaterials.AIR)
		_puddle(from, to, spilled)
	elif prop_name.begins_with("vending_machine"):
		# Shot for a free snack: it drops, and the snack goes on the bill as damage anyway.
		var snack := object.duplicate()
		snack.contents = "snack"
		_drop_contents(snack)
		bill(prop_name + "_snack", maxi(int(object.get("price", 0)), 1), lab.view.to_world(box.get_center()))


## Host: every voxel of the sources materials in [from, to) becomes material, in one batch. Returns
## how many changed.
func _swap_in_box(from: Vector3i, to: Vector3i, sources: Array, material: int) -> int:
	var size := to - from
	var voxels := lab.world.get_box(from, to)
	var points := PackedInt32Array()
	var materials := PackedByteArray()
	for i in voxels.size():
		if voxels[i] in sources:
			points.append_array([from.x + i % size.x, from.y + (i / size.x) % size.y, from.z + i / (size.x * size.y)])
			materials.append(material)
	if not materials.is_empty():
		lab.world_sync.set_voxels(points, materials)
	return materials.size()


## Host: up to count water voxels as a one-voxel sheet on the floor around [from, to).
func _puddle(from: Vector3i, to: Vector3i, count: int) -> void:
	var points := PackedInt32Array()
	var materials := PackedByteArray()
	for z in range(from.z - 5, to.z + 5):
		for x in range(from.x - 5, to.x + 5):
			if materials.size() >= count:
				break
			var p := Vector3i(x, from.y, z)
			if lab.world.get_voxel(p) != VoxelMaterials.AIR:
				continue
			for drop in 8:
				if lab.world.get_voxel(p + Vector3i.DOWN) != VoxelMaterials.AIR:
					break
				p += Vector3i.DOWN
			if lab.world.get_voxel(p + Vector3i.DOWN) != VoxelMaterials.AIR:
				points.append_array([p.x, p.y, p.z])
				materials.append(VoxelMaterials.WATER)
	if not materials.is_empty():
		lab.world_sync.set_voxels(points, materials)


# --- Keycards and power ----------------------------------------------------------------------------

## Host: someone picked up an item; keycards and the spore shooter go to the whole party.
func _on_picked(item: String, _peer_id: int) -> void:
	if not active:
		return
	if item == "spore_shooter":
		arm_party(_peer_id)
	elif item.begins_with("keycard_"):
		add_keycard(item.trim_prefix("keycard_"))
	elif item.begins_with("paper_") and lab.level.objects.has(item.trim_prefix("paper_")):
		_show_text(_peer_id, item.trim_prefix("paper_")) # A printed page: its printer's text.


## Host: dollars charged to the payroll for something peer_id bought (a vendor's price), listed as
## purchases on the statement.
func charge(what: String, dollars: int, peer_id: int) -> void:
	if dollars <= 0:
		return
	purchases[what] = int(purchases.get(what, 0)) + dollars


## Host: a door was broken through (InteractRules): FORCED_DOOR_FEE on the payroll, once per door.
func force_door(id: String) -> void:
	if id in forced_doors:
		return
	forced_doors.append(id)


## Host (story scripts too): the party has the spore shooter; every player is armed from now on,
## late joiners (_full_state) and respawns included, and the "armed" trigger fires once (its
## intercom line, its actions: the grow room spawner). peer_id is who picked it up. Repeats do
## nothing.
func arm_party(peer_id := 1) -> void:
	if not multiplayer.is_server() or not active or armed:
		return
	armed = true
	_apply_armed()
	party_armed.emit()
	triggered.emit("armed", peer_id)
	for peer in _peers():
		_armed_changed.rpc_id(peer, true)


@rpc("authority", "reliable")
func _armed_changed(on: bool) -> void:
	armed = on
	_apply_armed()
	if on:
		party_armed.emit()


## Every peer: whether a player here carries the gun now (the level doesn't start unarmed, or the
## party has picked it up). Story applies it to spawned players.
func is_armed_here() -> bool:
	return armed or lab.level == null or not bool(lab.level.settings.get("start_unarmed", false))


## This peer: arms or disarms the local player as is_armed_here says.
func _apply_armed() -> void:
	var me := lab.local_player()
	if me:
		me.set_armed(is_armed_here())


## Host (story scripts too): the party has a keycard ("red" or "keycard_red").
func add_keycard(color: String) -> void:
	color = color.trim_prefix("keycard_")
	if color == "" or color in keycards:
		return
	keycards.append(color)
	for peer_id in _peers():
		_keycards_changed.rpc_id(peer_id, keycards)


@rpc("authority", "reliable")
func _keycards_changed(cards: Array) -> void:
	keycards.assign(cards)


## Host (story scripts, the generator): changes the power state everywhere. Lights follow it
## (LevelView), as do powered doors and terminals.
func set_power(state: String) -> void:
	if not multiplayer.is_server() or state == power or state not in POWER_STATES:
		return
	_apply_power(state)
	for peer_id in _peers():
		_power_changed.rpc_id(peer_id, state)


@rpc("authority", "reliable")
func _power_changed(state: String) -> void:
	_apply_power(state)


func _apply_power(state: String, quiet := false) -> void:
	if state == power:
		return
	power = state
	if not quiet:
		Sfx.play("power_down" if state == "backup" else "power_up", -3.0)
	power_changed.emit(state)


## Host: the party's checkpoint changed (a player reached a clone vat).
func set_checkpoint(id: String) -> void:
	if not multiplayer.is_server() or id == checkpoint:
		return
	checkpoint = id
	for peer_id in _peers():
		_checkpoint_changed.rpc_id(peer_id, id)
	lab.notify("Checkpoint: clone vat ready")
	lab.save_shift()


@rpc("authority", "reliable")
func _checkpoint_changed(id: String) -> void:
	checkpoint = id


## Host: a trigger id fired; if it names a trigger marker, its `actions` run (see the top).
func _run_actions(id: String, _peer_id: int) -> void:
	if not active or not multiplayer.is_server():
		return
	var object: Dictionary = lab.level.objects.get(id, {})
	if object.get("kind") != "marker" or object.get("type") != "trigger":
		return
	var seals := false
	for part in str(object.get("actions", "")).split(",", false):
		var item := part.strip_edges()
		if item == "":
			continue
		var key := item.get_slice("=", 0).strip_edges()
		var value := item.get_slice("=", 1).strip_edges() if item.contains("=") else ""
		match key:
			"power":
				if value in POWER_STATES:
					set_power(value)
				else:
					push_warning("trigger %s: unknown power state '%s'" % [id, value])
			"lock", "unlock":
				if _doors.has(value):
					set_door_locked(value, key == "lock")
					seals = seals or key == "lock"
				else:
					push_warning("trigger %s: '%s' isn't a door" % [id, value])
			"open", "close":
				if _doors.has(value):
					set_door(value, key == "open")
				else:
					push_warning("trigger %s: '%s' isn't a door" % [id, value])
			"on", "off":
				if lab.director and lab.director.spawners.has(value):
					lab.director.set_spawner_active(value, key == "on")
				else:
					push_warning("trigger %s: '%s' isn't a spawner" % [id, value])
			"horde":
				if lab.director:
					lab.director.start_horde(lab.director.horde_size)
			"wake":
				if lab.director:
					lab.director.wake()
			"wither", "pulse":
				var mycelium := Mycelium.find()
				if mycelium and key == "wither":
					mycelium.wither()
				elif mycelium:
					mycelium.pulse(float(value) if value != "" else 1.0)
			"lights", "sprinkle":
				rules.run_action(id, key, value)
			_:
				push_warning("trigger %s: unknown action '%s'" % [id, item])
	# A seal: the way back is shut, so this is where the shift is kept. Deferred, so the trigger's
	# other listeners (the director's `activates`) are in the save too.
	if seals:
		lab.save_shift.call_deferred()


# --- Shift saves (host) ----------------------------------------------------------------------------

## Trigger ids that have fired (one-shot volume triggers), for the shift save.
func fired() -> Array:
	return _fired.keys()


## Host: what a shift save keeps of play: power, keycards, armed, prop_state, doors (id -> [origin
## as [x, y, z], open, locked]; a door mid-slide is recorded where it is going and listed in
## doors_settle, since its voxels are lifted out of the world while it moves), checkpoint, fired and
## the ledger (damage_by_name, total_damage).
func capture() -> Dictionary:
	var doors := {}
	var settle: Array = []
	for id: String in _doors:
		var door: Dictionary = _doors[id]
		var moving: bool = door.moving and door.has("target")
		var origin: Vector3i = door.target if moving else door.origin
		doors[id] = [[origin.x, origin.y, origin.z], door.target_open if moving else door.open, bool(door.object.door_locked)]
		if moving:
			settle.append(id)
	return {
		power = power,
		keycards = Array(keycards),
		armed = armed,
		prop_state = prop_state.duplicate(true),
		doors = doors,
		doors_settle = settle,
		checkpoint = checkpoint,
		fired = fired(),
		damage_by_name = damage_by_name.duplicate(),
		total_damage = total_damage,
		purchases = purchases.duplicate(),
		forced_doors = Array(forced_doors),
	}


## Host, resuming a shift before any peer is in the level: replaces the world with a saved one
## without the swap counting as damage or breaking glass (the voxel-change handler is off for it).
## Returns false if the data was refused.
func replace_world(voxels: PackedByteArray) -> bool:
	var counting := lab.world.voxels_changed.is_connected(_on_voxels_changed)
	if counting:
		lab.world.voxels_changed.disconnect(_on_voxels_changed)
	var ok := lab.world.set_data(voxels)
	if counting:
		lab.world.voxels_changed.connect(_on_voxels_changed)
	return ok


## Host, resuming a shift from a delta save (ShiftSave format 2), before any peer is in the level:
## the saved chunks go over the world as just built for play (VoxelWorld.set_chunks_data, which
## emits voxels_changed per chunk), with the voxel-change handler off as in replace_world. False if
## the data was refused.
func replace_chunks(slots: PackedInt32Array, data: PackedByteArray) -> bool:
	if slots.is_empty():
		return data.is_empty()
	var counting := lab.world.voxels_changed.is_connected(_on_voxels_changed)
	if counting:
		lab.world.voxels_changed.disconnect(_on_voxels_changed)
	var ok := lab.world.set_chunks_data(slots, data)
	if counting:
		lab.world.voxels_changed.connect(_on_voxels_changed)
	return ok


## Host, resuming a shift (after replace_world and start): power (quietly), keycards, armed, prop
## states (applied with no sound), doors, the checkpoint, fired triggers and the ledger, then every
## asset's and glass case's intact voxels are counted again from the world as it now is.
func restore(record: Dictionary) -> void:
	if not multiplayer.is_server() or not active:
		return
	var state := str(record.get("power", power))
	if state in POWER_STATES:
		_apply_power(state, true)
	keycards.assign(Array(record.get("keycards", [])).map(func(card) -> String: return str(card)))
	armed = bool(record.get("armed", false))
	_apply_armed()
	var props: Dictionary = record.get("prop_state", {})
	for id: String in props:
		_apply_state(id, _restored_state(id, props[id]), "")
	var doors: Dictionary = record.get("doors", {})
	for id: String in doors:
		if not _doors.has(id) or not doors[id] is Array or doors[id].size() < 3:
			continue
		var at: Array = doors[id][0]
		_doors[id].origin = Vector3i(int(at[0]), int(at[1]), int(at[2]))
		_doors[id].open = bool(doors[id][1])
		_doors[id].object.door_locked = bool(doors[id][2])
		rules.door_moved(id)
	# Doors saved mid-slide had no voxels in the saved world: stamp them where they stopped.
	for id in record.get("doors_settle", []):
		if _doors.has(str(id)):
			var door: Dictionary = _doors[str(id)]
			lab.world_sync.stamp_model(door.origin, door.model.size, door.model.voxels)
	checkpoint = str(record.get("checkpoint", ""))
	_fired.clear()
	for id in record.get("fired", []):
		_fired[str(id)] = true
	damage_by_name.clear()
	var ledger: Dictionary = record.get("damage_by_name", {})
	for what: String in ledger:
		damage_by_name[what] = int(ledger[what])
	total_damage = int(record.get("total_damage", 0))
	purchases.clear()
	var bought: Dictionary = record.get("purchases", {})
	for what: String in bought:
		purchases[what] = int(bought[what])
	forced_doors.assign(Array(record.get("forced_doors", [])).map(func(door) -> String: return str(door)))
	for asset: Dictionary in _assets.values():
		asset.intact = lab.world.count_matching(asset.origin, asset.size, asset.voxels)
	for glass: Dictionary in _glass.values():
		glass.intact = lab.world.count_matching(glass.origin, glass.size, glass.voxels)


## A saved prop state with JSON's floats made ints again. An experiment saved mid-reveal (its last
## step run, not yet used up) goes back one step: the reveal's timer didn't survive the save, so
## SHIFT runs the last step again.
func _restored_state(id: String, saved: Dictionary) -> Dictionary:
	var out := {}
	for key: String in saved:
		var value = saved[key]
		out[key] = int(value) if value is float and value == floorf(value) else value
	out.used = bool(out.get("used", false))
	var steps := Lines.parse_steps(str(lab.level.objects.get(id, {}).get("steps", "")))
	if not steps.is_empty() and not out.used and int(out.get("step", 0)) >= steps.size():
		out.step = steps.size() - 1
		out.reveal = 0
	return out


## Host: a late joiner gets the power, keycards, whether the party is armed, prop states, door
## locks, where doors are, and the checkpoint. A door mid-slide goes as moving, toward its target
## (the joiner is synced already, so the slide's _door_settled reaches it).
func _send_state(peer_id: int) -> void:
	if not multiplayer.is_server() or not active:
		return
	var doors := {}
	for id: String in _doors:
		var door: Dictionary = _doors[id]
		var moving: bool = door.moving and door.has("target")
		doors[id] = [door.origin, door.open, door.object.door_locked, moving,
				door.target if moving else door.origin, door.target_open if moving else door.open]
	_full_state.rpc_id(peer_id, power, keycards, armed, prop_state, doors, checkpoint)


@rpc("authority", "reliable")
func _full_state(state: String, cards: Array, party_armed: bool, props: Dictionary, doors: Dictionary, vat: String) -> void:
	_apply_power(state, true)
	keycards.assign(cards)
	armed = party_armed
	_apply_armed()
	checkpoint = vat
	prop_state = props.duplicate(true)
	for id: String in doors:
		if _doors.has(id):
			var door: Dictionary = _doors[id]
			door.origin = doors[id][0]
			door.open = doors[id][1]
			door.object.door_locked = doors[id][2]
			door.moving = doors[id][3]
			door.target = doors[id][4]
			door.target_open = doors[id][5]


# --- Triggers and kill zones (host) ----------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not active or not multiplayer.is_server():
		return
	# The volumes start() listed (in level order, as the full walk had them), not every object.
	var players := lab.players
	var reach_squared := CHECKPOINT_REACH * CHECKPOINT_REACH
	var volumes := _volumes # start() replaces the list, so a restart mid-loop can't upset this one.
	for volume: Dictionary in volumes:
		if not active:
			return
		var object: Dictionary = volume.object
		if volume.vat:
			if object.id != checkpoint:
				var at: Vector3 = volume.at
				for peer_id: int in players:
					var player: Player = players[peer_id]
					if not player.is_dead and player.global_position.distance_squared_to(at) <= reach_squared:
						set_checkpoint(object.id)
						break
			continue
		var world_box: AABB = volume.box
		var inside := _scratch_inside
		inside.clear()
		for peer_id: int in players:
			var player: Player = players[peer_id]
			if not player.is_dead and world_box.has_point(player.global_position + Vector3.UP * 0.5):
				inside.append(peer_id)
		var before: Array[int] = volume.inside
		volume.inside = inside
		_scratch_inside = before # Swapped: last tick's list is next volume's scratch.
		if volume.kill:
			for peer_id in inside:
				killed_in_zone.emit(object.id, peer_id)
			continue
		# The last one in (in players order) who wasn't in last tick.
		var entered := 0
		var any_entered := false
		for peer_id in inside:
			if not before.has(peer_id):
				entered = peer_id
				any_entered = true
		if not any_entered or (_fired.has(object.id) and not object.repeat):
			continue
		if object.who == "all" and inside.size() < players.size():
			continue
		_fired[object.id] = true
		triggered.emit(object.id, entered)


# --- Assets (host) -------------------------------------------------------------------------------

func _on_voxels_changed(from: Vector3i, to: Vector3i) -> void:
	var changed := AABB(Vector3(from), Vector3(to - from + Vector3i.ONE))
	rules.voxels_changed(changed)
	# Only the records whose box the change touches (ChunkIndex.query tests each box, as the full
	# scans did; the indexes are kept current where records move: index_asset).
	for id: String in _glass_index.query(changed):
		var glass: Dictionary = _glass.get(id, {})
		if glass.is_empty():
			continue
		var intact_glass: int = lab.world.count_matching(glass.origin, glass.size, glass.voxels)
		if intact_glass < glass.intact:
			glass.intact = intact_glass
			_break_glass(id)
	for id: String in _asset_index.query(changed):
		var asset: Dictionary = _assets.get(id, {})
		if asset.is_empty():
			continue
		var intact: int = lab.world.count_matching(asset.origin, asset.size, asset.voxels)
		if intact >= asset.intact:
			continue
		var before := _worth(asset, asset.intact)
		asset.intact = intact
		var lost := before - _worth(asset, intact)
		if lost <= 0:
			continue
		total_damage += lost
		damage_by_name[asset.name] = int(damage_by_name.get(asset.name, 0)) + lost
		asset_damaged.emit(id, lost, total_damage)


func _worth(asset: Dictionary, intact: int) -> int:
	return roundi(float(asset.value) * intact / asset.total)


## A spatial hash of voxel-space boxes keyed by chunk (VoxelWorld's 32-voxel chunks), so a voxel
## change only tests the records in the chunks it covers instead of every asset in the level. A
## record goes into every chunk its box touches (a prop spans 1 to 4 usually). query() returns the
## keys whose box strictly intersects the given one (AABB.intersects, as the full scans did), in
## insertion order; a query covering more chunks than there are records just scans them all.
class ChunkIndex extends RefCounted:
	const SHIFT := 5 # 32 voxels a chunk.

	## key -> AABB (voxel space). Insertion order is query order (insert moves a key to the end).
	var boxes := {}
	## Vector3i chunk -> Array of keys.
	var _cells := {}
	## key -> insertion number, for sorting a query's hits back into insertion order.
	var _order := {}
	var _next := 0
	## The same entries as flat lists in insertion order, for a wide query's straight scan.
	var _keys: Array = []
	var _aabbs: Array[AABB] = []

	func clear() -> void:
		boxes.clear()
		_cells.clear()
		_order.clear()
		_keys.clear()
		_aabbs.clear()
		_next = 0

	func size() -> int:
		return boxes.size()

	func has(key: Variant) -> bool:
		return boxes.has(key)

	## Adds key with box, or moves it there if it's already in.
	func insert(key: Variant, box: AABB) -> void:
		if boxes.has(key):
			remove(key)
		boxes[key] = box
		_order[key] = _next
		_next += 1
		_keys.append(key)
		_aabbs.append(box)
		var lo := _lo(box)
		var hi := _hi(box)
		for z in range(lo.z, hi.z + 1):
			for y in range(lo.y, hi.y + 1):
				for x in range(lo.x, hi.x + 1):
					var cell := Vector3i(x, y, z)
					var list: Array = _cells.get(cell, [])
					if list.is_empty():
						_cells[cell] = list
					list.append(key)

	func remove(key: Variant) -> void:
		if not boxes.has(key):
			return
		var box: AABB = boxes[key]
		boxes.erase(key)
		_order.erase(key)
		var at := _keys.find(key) # Rare (a record moved), so a linear find is fine.
		_keys.remove_at(at)
		_aabbs.remove_at(at)
		var lo := _lo(box)
		var hi := _hi(box)
		for z in range(lo.z, hi.z + 1):
			for y in range(lo.y, hi.y + 1):
				for x in range(lo.x, hi.x + 1):
					var cell := Vector3i(x, y, z)
					var list: Array = _cells.get(cell, [])
					list.erase(key)
					if list.is_empty():
						_cells.erase(cell)

	## Keys whose box intersects box, in insertion order.
	func query(box: AABB) -> Array:
		var out: Array = []
		if boxes.is_empty():
			return out
		var lo := _lo(box)
		var hi := _hi(box)
		var cells := (hi.x - lo.x + 1) * (hi.y - lo.y + 1) * (hi.z - lo.z + 1)
		# Wide (a scattered batch's union box): one straight pass over the flat lists beats walking
		# the cells and deduplicating.
		if cells * 2 > _aabbs.size():
			var aabbs := _aabbs
			for i in aabbs.size():
				if box.intersects(aabbs[i]):
					out.append(_keys[i])
			return out
		var seen := {}
		for z in range(lo.z, hi.z + 1):
			for y in range(lo.y, hi.y + 1):
				for x in range(lo.x, hi.x + 1):
					var list: Array = _cells.get(Vector3i(x, y, z), [])
					for key: Variant in list:
						if seen.has(key):
							continue
						seen[key] = true
						if box.intersects(boxes[key]):
							out.append(key)
		if out.size() > 1:
			var order := _order
			out.sort_custom(func(a: Variant, b: Variant) -> bool: return order[a] < order[b])
		return out

	static func _lo(box: AABB) -> Vector3i:
		var p := box.position.floor()
		return Vector3i(int(p.x) >> SHIFT, int(p.y) >> SHIFT, int(p.z) >> SHIFT)

	## The last chunk the box reaches (its end is exclusive; a flat box stays in its first chunk).
	static func _hi(box: AABB) -> Vector3i:
		var p := box.position.floor()
		var e := (box.end - Vector3.ONE * 0.001).floor().max(p)
		return Vector3i(int(e.x) >> SHIFT, int(e.y) >> SHIFT, int(e.z) >> SHIFT)
