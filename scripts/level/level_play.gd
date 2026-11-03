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
## `off=<spawner>`, `horde`. The host runs them; the results replicate as usual.
##
## Checkpoint: the clone vat the party reached last (any living player within CHECKPOINT_REACH of
## its marker); Lab respawns the dead there. The host decides and tells everyone.

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
## Meters from a clone vat marker that makes it the checkpoint.
const CHECKPOINT_REACH := 3.0
const POWER_STATES := ["facility", "backup", "restored"]
## Rounds an ammo bench gives per use.
const STATION_AMMO := 20
## Meters from a damaged asset within which a player sees its "-$" toast (everyone is billed).
const DAMAGE_NOTE_RANGE := 15.0

@export var lab: Lab

var active := false
## Host: dollars of asset damage per asset name since play started (the payroll statement).
var damage_by_name := {}
## Host: dollars of asset damage since play started.
var total_damage := 0
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

## id -> {object, model (turned), origin: Vector3i, open: bool, moving: bool}
var _doors := {}
## id -> {origin, size, voxels, total, intact, value, name}
var _assets := {}
## Every peer: usable (non-door) prop id -> its box in world space.
var _usables := {}
## Host: glass case id -> {origin, size, voxels (its GLASS voxels only), intact}
var _glass := {}
## Trigger ids that already fired (one-shot ones) and peers inside each (for edge detection).
var _fired := {}
var _inside := {}
## Host: damage not yet announced: id -> dollars. Announced in batches so a burst of fire is one
## line, and only to players within DAMAGE_NOTE_RANGE of the asset.
var _pending_notes := {}
var _note_timer := 0.0


func _ready() -> void:
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
	_fired.clear()
	_inside.clear()
	prop_state.clear()
	keycards.clear()
	armed = false
	_pending_notes.clear()
	checkpoint = ""
	close_reading()
	_apply_armed()
	var start_power := str(lab.level.settings.get("start_power", "facility"))
	power = start_power if start_power in POWER_STATES else "facility"
	power_changed.emit(power)
	for object: Dictionary in lab.level.objects.values():
		if object.kind != "prop":
			continue
		var model := Props.load_prop(object.name)
		if model.is_empty():
			continue
		var turned := Props.orient(model, object.facing)
		if object.door:
			_doors[object.id] = {object = object, model = turned, origin = object.origin, open = false, moving = false}
			continue
		if object.get("use", "none") != "none":
			_usables[object.id] = AABB(lab.view.to_world(Vector3(object.origin)), Vector3(turned.size) * lab.world.voxel_size)
		if not multiplayer.is_server():
			continue
		if object.value > 0:
			var intact: int = lab.world.count_matching(object.origin, turned.size, turned.voxels)
			_assets[object.id] = {origin = object.origin, size = turned.size, voxels = turned.voxels,
					total = maxi(intact, 1), intact = intact, value = object.value, name = object.name}
		if object.get("use") == "glass_case":
			var glass: PackedByteArray = turned.voxels.duplicate()
			for i in glass.size():
				if glass[i] != VoxelMaterials.GLASS:
					glass[i] = 0
			var intact_glass: int = lab.world.count_matching(object.origin, turned.size, glass)
			if intact_glass > 0:
				_glass[object.id] = {origin = object.origin, size = turned.size, voxels = glass, intact = intact_glass}
	if multiplayer.is_server() and not lab.world.voxels_changed.is_connected(_on_voxels_changed):
		lab.world.voxels_changed.connect(_on_voxels_changed)


func stop() -> void:
	active = false
	_doors.clear()
	_assets.clear()
	_usables.clear()
	_glass.clear()
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
	lab.world_sync.stamp_model(door.origin, door.model.size, door.model.voxels, true)
	_door_motion(id, door.origin, target, duration)
	for peer_id in lab.world_sync.synced_peers():
		_door_motion.rpc_id(peer_id, id, door.origin, target, duration)
	await get_tree().create_timer(duration).timeout
	if not active or not _doors.has(id):
		return
	lab.world_sync.stamp_model(target, door.model.size, door.model.voxels)
	door.origin = target
	door.open = open
	door.moving = false


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


## Every peer: slides a mesh of the door while its voxels are gone.
@rpc("authority", "reliable")
func _door_motion(id: String, from: Vector3i, to: Vector3i, duration: float) -> void:
	var door: Dictionary = _doors.get(id, {})
	if door.is_empty():
		return
	door.origin = from
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
	if not multiplayer.is_server():
		door.origin = to


# --- Using things (E) ---------------------------------------------------------------------------

## Any peer: asks the host to use a door or prop (the interact key). The host checks it's allowed
## (locks, keycards, power, charges) and tells the user why not if it isn't.
func request_use(id: String) -> void:
	if multiplayer.is_server():
		_use(id, multiplayer.get_unique_id())
	else:
		_request_use.rpc_id(1, id)


@rpc("any_peer", "reliable")
func _request_use(id: String) -> void:
	if multiplayer.is_server():
		_use(id, multiplayer.get_remote_sender_id())


## A prop's state: {used, charges}, defaults (unused, its charges field) if it hasn't been touched.
func state_of(id: String) -> Dictionary:
	if prop_state.has(id):
		return prop_state[id]
	var object: Dictionary = lab.level.objects.get(id, {}) if lab.level else {}
	return {used = false, charges = int(object.get("charges", 0))}


## Host: what E does (see LevelSchema.USES).
func _use(id: String, peer_id: int) -> void:
	if not active:
		return
	if _doors.has(id):
		var why := door_refusal(id)
		if why != "":
			lab.notify_peer(peer_id, why)
			door_refused.emit(id, peer_id)
		else:
			if not _doors[id].open and door_key(id) != "":
				door_passed.emit(id, peer_id)
			set_door(id, not _doors[id].open)
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


# --- Keycards and power ----------------------------------------------------------------------------

## Host: someone picked up an item; keycards and the spore shooter go to the whole party.
func _on_picked(item: String, _peer_id: int) -> void:
	if not active:
		return
	if item == "spore_shooter":
		arm_party(_peer_id)
	elif item.begins_with("keycard_"):
		add_keycard(item.trim_prefix("keycard_"))


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
			_:
				push_warning("trigger %s: unknown action '%s'" % [id, item])


## Host: a late joiner gets the power, keycards, whether the party is armed, prop states, door
## locks, where doors are, and the checkpoint.
func _send_state(peer_id: int) -> void:
	if not multiplayer.is_server() or not active:
		return
	var doors := {}
	for id: String in _doors:
		doors[id] = [_doors[id].origin, _doors[id].open, _doors[id].object.door_locked]
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
			_doors[id].origin = doors[id][0]
			_doors[id].open = doors[id][1]
			_doors[id].object.door_locked = doors[id][2]


# --- Triggers and kill zones (host) ----------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not active or not multiplayer.is_server():
		return
	for object: Dictionary in lab.level.objects.values():
		if object.kind != "marker":
			continue
		if object.type == "clone_vat":
			if object.id != checkpoint:
				var at := lab.view.to_world(object.position)
				for player: Player in lab.players.values():
					if not player.is_dead and player.global_position.distance_to(at) <= CHECKPOINT_REACH:
						set_checkpoint(object.id)
						break
			continue
		if not object.type in ["trigger", "kill_zone"]:
			continue
		var box := LevelSchema.marker_box(object)
		var world_box := AABB(lab.view.to_world(box.position), box.size * lab.world.voxel_size)
		var inside: Array[int] = []
		for peer_id: int in lab.players:
			var player: Player = lab.players[peer_id]
			if not player.is_dead and world_box.has_point(player.global_position + Vector3.UP * 0.5):
				inside.append(peer_id)
		var before: Array = _inside.get(object.id, [])
		_inside[object.id] = inside
		if object.type == "kill_zone":
			for peer_id in inside:
				killed_in_zone.emit(object.id, peer_id)
			continue
		var entered := inside.filter(func(id: int) -> bool: return id not in before)
		if entered.is_empty() or (_fired.has(object.id) and not object.repeat):
			continue
		if object.who == "all" and inside.size() < lab.players.size():
			continue
		_fired[object.id] = true
		triggered.emit(object.id, entered.back())


# --- Assets (host) -------------------------------------------------------------------------------

func _on_voxels_changed(from: Vector3i, to: Vector3i) -> void:
	var changed := AABB(Vector3(from), Vector3(to - from + Vector3i.ONE))
	for id: String in _glass.keys():
		var glass: Dictionary = _glass[id]
		if not changed.intersects(AABB(Vector3(glass.origin), Vector3(glass.size))):
			continue
		var intact_glass: int = lab.world.count_matching(glass.origin, glass.size, glass.voxels)
		if intact_glass < glass.intact:
			glass.intact = intact_glass
			_break_glass(id)
	for id: String in _assets:
		var asset: Dictionary = _assets[id]
		if not changed.intersects(AABB(Vector3(asset.origin), Vector3(asset.size))):
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
		_pending_notes[id] = _pending_notes.get(id, 0) + lost


func _worth(asset: Dictionary, intact: int) -> int:
	return roundi(float(asset.value) * intact / asset.total)


func _process(delta: float) -> void:
	if _pending_notes.is_empty():
		return
	_note_timer -= delta
	if _note_timer > 0.0:
		return
	_note_timer = 0.6
	var notes := _pending_notes
	_pending_notes = {}
	if not multiplayer.is_server() or not active:
		return
	for peer_id in lab.peers_in_level:
		var player: Player = lab.players.get(peer_id)
		if player == null:
			continue
		var lines: Array[String] = []
		for id: String in notes:
			if _assets.has(id) and _asset_distance(id, player.global_position) <= DAMAGE_NOTE_RANGE:
				lines.append("-$%d  %s" % [notes[id], _assets[id].name.replace("_", " ")])
		if not lines.is_empty():
			lab.notify_peer(peer_id, "\n".join(lines))


## Host: how far a point is from an asset's box (0 inside it), in meters.
func _asset_distance(id: String, at: Vector3) -> float:
	var asset: Dictionary = _assets[id]
	var box := AABB(lab.view.to_world(Vector3(asset.origin)), Vector3(asset.size) * lab.world.voxel_size)
	return at.clamp(box.position, box.end).distance_to(at)
