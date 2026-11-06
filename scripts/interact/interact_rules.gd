class_name InteractRules
extends Node
## The interactables of docs/prop-build-plan.md E: what E does with the newer uses (LevelSchema.USES:
## switch, vendor, eyewash, defib, extinguisher, flip, printer, radio, squeak), the props that react
## to being shot or burnt by name (fire extinguishers burst into foam, gas cylinders vent and skid,
## then explode), crushing under falling pieces (a hanging crate whose chain is shot), forced
## doors, and two trigger actions: `lights=<room>:off|on|flicker` and `sprinkle=<room>` (a room
## object's box, or a trigger marker's volume).
##
## A child of LevelPlay ("Rules", the same path on every peer), which calls in: start / stop, use,
## prompt, refusal, voxels_changed and run_action. Like LevelPlay, the host decides and the peers
## replay: voxel edits go through WorldSync, prop states through LevelPlay._set_state (so the radio's
## on / off reaches late joiners in prop_state), and the room lights and sprinklers through the RPCs
## here. Every peer draws its own looks: radios' loops (reconciled with prop_state), the sprinkler's
## rain and the flicker (LevelView asks light_mode).

## Seconds a vendor's buff lasts.
const BUFF_SECONDS := 20.0
## Statuses (Player.STATUS_DPS) per vendor buff.
const BUFF_STATUS := {speed = "hasted", reload = "caffeinated"}
## Meters a defibrillator reaches a dead teammate.
const DEFIB_REACH := 3.0
## Lures (EnemyManager.set_lure): a radio's reach, a squeak's reach and how long it lasts.
const RADIO_REACH := 20.0
const SQUEAK_REACH := 10.0
const SQUEAK_SECONDS := 4.0
## A fire extinguisher's foam cloud.
const FOAM_RADIUS := 4.0
const FOAM_SECONDS := 6.0
## An emergency shower douses fire this far around it (meters).
const SHOWER_DOUSE := 3.0
## A shot gas cylinder skids this far (meters) over this long, hitting enemies within SKID_REACH of
## its path for SKID_HIT ("blast" knockback).
const SKID_DISTANCE := 6.0
const SKID_SECONDS := 0.6
const SKID_REACH := 1.2
const SKID_HIT := 15.0
## A gas cylinder's explosion (the exploding shroom's, a little bigger).
const GAS_RADIUS := 1.5
const GAS_POWER := 5
const GAS_DAMAGE := 50.0
const GAS_PLAYER_DAMAGE := 30.0
const GAS_REACH := 3.5
## Losing this share of its voxels in one go is a blast, not a shot.
const BLAST_SHARE := 0.25
## Host: seconds between checks for fire reaching a reactive prop.
const FIRE_CHECK := 0.5
## Falling pieces (FallingPieces) of more than CRUSH_VOXELS voxels crush what is in the column they
## fall through. Ceiling tile voxels don't count: a mineral-fibre sheet is too light to hurt.
const CRUSH_VOXELS := 50
const CRUSH_DAMAGE := 80.0
const CRUSH_PLAYER_DAMAGE := 40.0
## A sprinkler runs this long, dousing and clearing clouds every SPRINKLE_TICK.
const SPRINKLE_SECONDS := 8.0
const SPRINKLE_TICK := 0.5
## A door that loses this share of its voxels has been forced (the payroll's doors forced).
const FORCED_SHARE := 0.1
## Radios' looping track: how loud, and how far it carries.
const RADIO_DB := -6.0
const RADIO_RANGE := 30.0

## Every peer: room_lights changed (a room's lights cut, back on or flickering; start / stop).
signal lights_changed

var play: LevelPlay
## Every peer (the host decides): room or trigger id -> "off" or "flicker" (lights=, sprinklers).
## Change it through _room_lights (or bump lights_version), so LevelView sees the change.
var room_lights := {}
## Every peer: counts changes to room_lights, so LevelView recomputes its lights only then.
var lights_version := 0

## Host: reactive prop id -> {kind: "foam" | "gas", origin, size, voxels, total, intact, vented}.
var _reactive := {}
## Host: door id -> its voxels when whole.
var _door_total := {}
## Host: the reactive props and the doors in chunk indexes (LevelPlay.ChunkIndex), so a voxel change
## only tests the ones near it. Moved ones are put back (_skid, door_moved).
var _reactive_index := LevelPlay.ChunkIndex.new()
var _door_index := LevelPlay.ChunkIndex.new()
## Host: room id -> seconds of sprinkling left; and the lights mode it had before.
var _sprinkling := {}
var _sprinkle_before := {}
var _sprinkle_tick := 0.0
var _fire_timer := 0.0
## Every peer: radio prop id -> its looping AudioStreamPlayer3D.
var _radios := {}
var _radio_timer := 0.0
## Every peer: room id -> the sprinkler's rain (CPUParticles3D).
var _rain := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	play.lab.peer_entered.connect(_send_state)


## Every peer, from LevelPlay.start (after its tables are built).
func start() -> void:
	room_lights.clear()
	_lights_changed()
	_reactive.clear()
	_door_total.clear()
	_reactive_index.clear()
	_door_index.clear()
	_sprinkling.clear()
	_sprinkle_before.clear()
	_clear_looks()
	if not multiplayer.is_server():
		return
	var lab := play.lab
	for object: Dictionary in lab.level.objects.values():
		if object.kind != "prop" or object.door:
			continue
		var kind := reactive_kind(str(object.name))
		if kind == "":
			continue
		var turned := Props.oriented(object.name, object.facing)
		if turned.is_empty():
			continue
		var intact: int = lab.world.count_matching(object.origin, turned.size, turned.voxels)
		_reactive[object.id] = {kind = kind, origin = object.origin, size = turned.size, voxels = turned.voxels,
				total = maxi(intact, 1), intact = intact, vented = false}
		_reactive_index.insert(object.id, AABB(Vector3(object.origin), Vector3(turned.size)))
	for id: String in play._doors:
		var door: Dictionary = play._doors[id]
		_door_total[id] = lab.world.count_matching(door.origin, door.model.size, door.model.voxels)
		door_moved(id)
	if lab.falling and not lab.falling.piece_falling.is_connected(_on_piece_falling):
		lab.falling.piece_falling.connect(_on_piece_falling)


func stop() -> void:
	room_lights.clear()
	_lights_changed()
	_reactive.clear()
	_reactive_index.clear()
	_door_index.clear()
	_sprinkling.clear()
	_clear_looks()
	if play.lab.falling and play.lab.falling.piece_falling.is_connected(_on_piece_falling):
		play.lab.falling.piece_falling.disconnect(_on_piece_falling)


## Host: a door stopped somewhere new (LevelPlay._door_settled, restore): its index entry follows.
func door_moved(id: String) -> void:
	var door: Dictionary = play._doors.get(id, {})
	if door.is_empty() or not _door_total.has(id):
		_door_index.remove(id)
		return
	_door_index.insert(id, AABB(Vector3(door.origin), Vector3(door.model.size)))


func _lights_changed() -> void:
	lights_version += 1
	lights_changed.emit()


## The reaction a prop has by name: "foam" (fire extinguishers), "gas" (gas cylinders) or "".
static func reactive_kind(prop_name: String) -> String:
	if prop_name.begins_with("fire_extinguisher"):
		return "foam"
	if prop_name.begins_with("gas_cylinder"):
		return "gas"
	return ""


func _clear_looks() -> void:
	for player: Node in _radios.values():
		player.queue_free()
	_radios.clear()
	for rain: Node in _rain.values():
		rain.queue_free()
	_rain.clear()


# --- E (host) ------------------------------------------------------------------------------------

## Host: what E does for the uses here. Returns false for a use this doesn't know (nothing happened).
func use(id: String, object: Dictionary, state: Dictionary, peer_id: int) -> bool:
	var lab := play.lab
	var prop_name := str(object.name)
	match str(object.get("use", "none")):
		"switch":
			if object.get("once", false) and state.used:
				lab.notify_peer(peer_id, "It won't move")
				return true
			state.used = true
			state.on = not bool(state.get("on", false))
			play._set_state(id, state, "alarm" if prop_name.begins_with("alarm_pull") else "ui_click")
			if prop_name.begins_with("alarm_pull") and lab.director:
				lab.director.start_horde(lab.director.horde_size)
			if str(object.get("on_use", "")) != "":
				play.triggered.emit(object.on_use, peer_id)
			elif prop_name.begins_with("breaker_panel") or prop_name.begins_with("fuse_box") or prop_name.begins_with("light_switch"):
				var room := room_at(_center_voxel(object))
				if room != "":
					set_room_lights(room, "off" if state.on else "on")
		"vendor":
			var price := int(object.get("price", 0))
			state.used = true
			state.uses = int(state.get("uses", 0)) + 1
			play._set_state(id, state, "vend")
			if price > 0:
				play.charge(prop_name, price, peer_id)
			play._drop_contents(object)
			var buff := str(object.get("buff", "none"))
			var player: Player = lab.players.get(peer_id)
			if BUFF_STATUS.has(buff) and player and lab.enemies:
				lab.enemies.status_player(player, BUFF_STATUS[buff], BUFF_SECONDS)
				lab.notify_peer(peer_id, "Refreshed: %s for %d s" % ["faster on your feet" if buff == "speed" else "faster trigger finger", int(BUFF_SECONDS)])
		"eyewash":
			state.used = true
			play._set_state(id, state, "splash")
			_cleanse_peer(peer_id)
			if prop_name.begins_with("emergency_shower"):
				Fire.douse_at(_center(object), SHOWER_DOUSE)
		"defib":
			if state.charges <= 0:
				lab.notify_peer(peer_id, "The defibrillator is flat")
				return true
			state.charges -= 1
			state.used = true
			play._set_state(id, state, "zap")
			var patient := _dead_teammate_near(peer_id)
			if patient != 0:
				_revive_peer(patient)
				lab.notify_peer(peer_id, "Clear! Back on their feet.")
			else:
				play._heal_peer(peer_id)
		"extinguisher":
			if state.used:
				return true
			state.used = true
			play._set_state(id, state, "pickup")
			_take_away(id, object)
			var user: Player = lab.players.get(peer_id)
			if user and lab.items:
				lab.items.spawn("flask_foam", user.global_position + Vector3.UP * ItemManager.HOVER)
		"flip":
			if state.used:
				return true
			if not _flip(id, object):
				lab.notify_peer(peer_id, "It won't tip")
				return true
			state.used = true
			play._set_state(id, state, "thud")
		"printer":
			if state.used:
				lab.notify_peer(peer_id, "PAPER JAM")
				return true
			state.used = true
			play._set_state(id, state, "printer")
			var page := object.duplicate()
			page.contents = "paper_" + id
			play._drop_contents(page)
		"radio":
			state.used = true
			state.on = not bool(state.get("on", false))
			play._set_state(id, state, "ui_click")
			if lab.enemies:
				if state.on:
					lab.enemies.set_lure("radio:" + id, _center(object), RADIO_REACH)
				else:
					lab.enemies.clear_lure("radio:" + id)
		"squeak":
			state.used = true
			state.squeaks = int(state.get("squeaks", 0)) + 1
			play._set_state(id, state, "squeak")
			if lab.enemies:
				lab.enemies.set_lure("duck:" + id, _center(object), SQUEAK_REACH, SQUEAK_SECONDS)
		_:
			return false
	return true


## The prompt for the uses here, from the state this peer knows.
func prompt(id: String, object: Dictionary, state: Dictionary) -> String:
	var prop_name := str(object.get("name", ""))
	match str(object.get("use", "none")):
		"switch":
			if object.get("once", false) and state.used:
				return ""
			if prop_name.begins_with("alarm_pull"):
				return "[E] Pull the fire alarm"
			if prop_name.begins_with("breaker_panel") or prop_name.begins_with("fuse_box"):
				return "[E] Throw the breaker"
			if prop_name.begins_with("light_switch"):
				return "[E] Flip the switch"
			return "[E] Pull"
		"vendor":
			var price := int(object.get("price", 0))
			var what := "Drink" if prop_name.begins_with("water_cooler") else "Coffee" if prop_name.begins_with("counter_coffee") else "Buy a snack"
			return "[E] %s ($%d, billed to payroll)" % [what, price] if price > 0 else "[E] %s" % what
		"eyewash":
			return "[E] Pull the shower" if prop_name.begins_with("emergency_shower") else "[E] Rinse your eyes"
		"defib":
			return "[E] Defibrillator (%d left)" % state.charges if state.charges > 0 else "Defibrillator (flat)"
		"extinguisher":
			return "" if state.used else "[E] Take the extinguisher"
		"flip":
			return "" if state.used else "[E] Flip"
		"printer":
			return "Paper jam" if state.used else "[E] Print"
		"radio":
			return "[E] Turn it off" if state.get("on", false) else "[E] Turn it on"
		"squeak":
			return "[E] Squeeze"
	return ""


## Why the local player can't use this now ("" to ask the host), for the uses here.
func refusal(_id: String, object: Dictionary, state: Dictionary) -> String:
	match str(object.get("use", "none")):
		"switch":
			return "It won't move" if object.get("once", false) and state.used else ""
		"defib":
			return "The defibrillator is flat" if state.charges <= 0 else ""
		"extinguisher", "flip":
			return "Already done" if state.used else ""
	return ""


## A prop's box middle in world space.
func _center(object: Dictionary) -> Vector3:
	var box := LevelSchema.prop_box(object)
	return play.lab.view.to_world(box.get_center())


func _center_voxel(object: Dictionary) -> Vector3:
	return LevelSchema.prop_box(object).get_center()


## Host: the nearest dead player within DEFIB_REACH of peer_id's player (not themselves), or 0.
func _dead_teammate_near(peer_id: int) -> int:
	var user: Player = play.lab.players.get(peer_id)
	if user == null:
		return 0
	var best := 0
	var best_distance := DEFIB_REACH
	for other_id: int in play.lab.players:
		var other: Player = play.lab.players[other_id]
		if other_id == peer_id or not is_instance_valid(other) or not other.is_dead or other_id not in play.lab.peers_in_level:
			continue
		var distance := other.global_position.distance_to(user.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = other_id
	return best


## Host: a dead player gets up where they lie (their peer runs it; the clone respawn then finds
## them alive and stands down).
func _revive_peer(peer_id: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		_revive_here()
	else:
		_revive.rpc_id(peer_id)


@rpc("authority", "reliable")
func _revive() -> void:
	_revive_here()


func _revive_here() -> void:
	var me := play.lab.local_player()
	if me and me.is_dead:
		me.revive()
		me.health = me.max_health * 0.5
		play.lab.notify("Defibrillated. Back on your feet.", false)


## Host: the eyewash rinses Poisoned and Burning off its user (on their own peer).
func _cleanse_peer(peer_id: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		_cleanse_here()
	else:
		_cleanse.rpc_id(peer_id)


@rpc("authority", "reliable")
func _cleanse() -> void:
	_cleanse_here()


func _cleanse_here() -> void:
	var me := play.lab.local_player()
	if me and not me.is_dead:
		me.statuses.erase("poisoned")
		me.statuses.erase("burning")
		play.lab.notify("Rinsed off", false)


## Host: takes a prop's voxels out of the world (picked up), without billing it as damage.
func _take_away(id: String, object: Dictionary) -> void:
	var model := Props.load_prop(object.name)
	if model.is_empty():
		return
	var turned := Props.oriented(object.name, object.facing)
	_reactive.erase(id)
	_reactive_index.remove(id)
	var asset: Variant = play._assets.get(id)
	play._assets.erase(id)
	var origin: Vector3i = object.origin
	play.lab.world_sync.stamp_model(origin, turned.size, turned.voxels, true)
	if asset != null:
		asset.intact = 0
		asset.total = 1
		asset.value = 0
		play._assets[id] = asset


## Host: swaps a prop for its `<name>_flipped` twin in place. False if there is no twin.
func _flip(id: String, object: Dictionary) -> bool:
	var twin := str(object.name) + "_flipped"
	if not FileAccess.file_exists(Props.library_dir + twin + ".vox"):
		return false
	var before := Props.oriented(object.name, object.facing)
	var after := Props.oriented(twin, object.facing)
	if before.is_empty() or after.is_empty():
		return false
	var origin: Vector3i = object.origin
	var asset: Variant = play._assets.get(id)
	play._assets.erase(id) # The swap isn't damage.
	var sync := play.lab.world_sync
	sync.stamp_model(origin, before.size, before.voxels, true)
	sync.stamp_model(origin, after.size, after.voxels)
	if asset != null:
		asset.size = after.size
		asset.voxels = after.voxels
		asset.intact = play.lab.world.count_matching(origin, after.size, after.voxels)
		asset.total = maxi(asset.intact, 1)
		play._assets[id] = asset
		play.index_asset(id)
	return true


# --- Reactions (host) ----------------------------------------------------------------------------

## Host, from LevelPlay._on_voxels_changed: reactive props that lost voxels go off, doors that lost
## enough are forced.
func voxels_changed(changed: AABB) -> void:
	# Only the ones in the chunks the change covers (ChunkIndex), each still tested against its box.
	for id: String in _reactive_index.query(changed):
		var rec: Dictionary = _reactive.get(id, {})
		if rec.is_empty() or rec.get("moving", false):
			continue
		var intact: int = play.lab.world.count_matching(rec.origin, rec.size, rec.voxels)
		if intact >= rec.intact:
			continue
		var lost: int = rec.intact - intact
		rec.intact = intact
		_set_off(id, rec, lost >= int(rec.total) * BLAST_SHARE)
	for id: String in _door_index.query(changed):
		var door: Dictionary = play._doors.get(id, {})
		if door.is_empty() or door.moving or id in play.forced_doors:
			continue
		var intact: int = play.lab.world.count_matching(door.origin, door.model.size, door.model.voxels)
		if intact < int(_door_total[id]) * (1.0 - FORCED_SHARE):
			play.force_door(id)


## Host: a reactive prop was shot (blasted: a big share went at once), or caught fire.
func _set_off(id: String, rec: Dictionary, blasted: bool) -> void:
	var object: Dictionary = play.lab.level.objects.get(id, {})
	if object.is_empty():
		_reactive.erase(id)
		return
	if rec.kind == "foam":
		_reactive.erase(id)
		var at := play.lab.view.to_world(Vector3(rec.origin) + Vector3(rec.size) * 0.5)
		play.lab.world_sync.stamp_model(rec.origin, rec.size, rec.voxels, true)
		Cloud.spawn("foam", at, FOAM_RADIUS, FOAM_SECONDS)
		var state := play.state_of(id).duplicate()
		state.used = true
		play._set_state(id, state, "foam_spray")
	elif rec.vented or blasted:
		_explode(id, rec)
	else:
		_skid(id, rec, object)


## Host: a shot gas cylinder vents: it skids SKID_DISTANCE along the floor in a random direction,
## knocking the enemies in its way back. Next time it goes up.
func _skid(id: String, rec: Dictionary, object: Dictionary) -> void:
	var lab := play.lab
	var voxel := lab.world.voxel_size
	rec.vented = true
	rec.moving = true
	var angle := _rng.randf() * TAU
	var direction := Vector3(cos(angle), 0.0, sin(angle))
	var origin: Vector3i = rec.origin
	var size: Vector3i = rec.size
	var half := Vector3(size.x, 0, size.z) * voxel * 0.5
	var start := lab.view.to_world(Vector3(origin)) + half
	var asset: Variant = play._assets.get(id)
	play._assets.erase(id) # Moving isn't damage.
	lab.world_sync.stamp_model(origin, size, rec.voxels, true)
	# In steps (move_box sweeps one move; a long one stops at the first thing in the way anyway).
	var end := start
	var body := Vector3(size) * voxel * 0.98
	for i in int(SKID_DISTANCE / 0.1):
		var moved: Dictionary = lab.world.move_box(end, body, direction * 0.1 + Vector3.DOWN * 0.02, 0.25, true)
		if Vector2(moved.position.x - end.x, moved.position.z - end.z).length() < 0.02:
			break
		end = moved.position
	var target: Vector3i = lab.world.world_to_voxel(end - half + Vector3(voxel, voxel, voxel) * 0.5)
	target.y = origin.y if absi(target.y - origin.y) > 3 else target.y
	if lab.enemies:
		for enemy: Enemy in lab.enemies.enemies.values():
			if enemy.alive and _distance_to_segment(enemy.global_position, start, end) <= SKID_REACH:
				lab.enemies.damage(enemy.id, SKID_HIT, enemy.global_position - direction, "blast")
	var to := lab.view.to_world(Vector3(target))
	_skid_motion(str(object.name), int(object.facing), lab.view.to_world(Vector3(origin)), to, SKID_SECONDS)
	for peer_id in lab.world_sync.synced_peers():
		_skid_motion.rpc_id(peer_id, str(object.name), int(object.facing), lab.view.to_world(Vector3(origin)), to, SKID_SECONDS)
	await get_tree().create_timer(SKID_SECONDS).timeout
	if not play.active or _reactive.get(id) != rec:
		return
	lab.world_sync.stamp_model(target, size, rec.voxels)
	rec.origin = target
	rec.intact = lab.world.count_matching(target, size, rec.voxels)
	rec.moving = false
	_reactive_index.insert(id, AABB(Vector3(target), Vector3(size)))
	if asset != null:
		asset.origin = target
		asset.intact = rec.intact
		play._assets[id] = asset
		play.index_asset(id)


static func _distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var flat := Vector2(point.x, point.z)
	var from := Vector2(a.x, a.z)
	var to := Vector2(b.x, b.z)
	var along := to - from
	var t := 0.0 if along.length_squared() < 0.0001 else clampf((flat - from).dot(along) / along.length_squared(), 0.0, 1.0)
	return flat.distance_to(from + along * t)


## Every peer: the skidding cylinder's mesh slides while its voxels are lifted out (like a door),
## hissing a white jet behind it.
@rpc("authority", "reliable")
func _skid_motion(prop_name: String, facing: int, from: Vector3, to: Vector3, duration: float) -> void:
	var view := play.lab.view
	var mesh := MeshInstance3D.new()
	mesh.mesh = view.prop_mesh(prop_name, facing)
	mesh.material_override = play.lab.world.material
	mesh.position = from
	view.add_child(mesh)
	var tween := mesh.create_tween()
	tween.tween_property(mesh, "position", to, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_interval(0.1)
	tween.tween_callback(mesh.queue_free)
	Sfx.play_at("gas_hiss", from + Vector3.UP * 0.7)
	VoxelFx.burst(view, from + Vector3.UP * 1.2, [Color.WHITE, Color(0.85, 0.88, 0.9)], 18, 2.5, 0.1, 0.6, Vector3(0.0, 0.5, 0.0), 2.0)


## Host: a gas cylinder blows up like an exploding shroom: carves, sets fire, hurts what the blast
## can see.
func _explode(id: String, rec: Dictionary) -> void:
	_reactive.erase(id)
	var lab := play.lab
	var at := lab.view.to_world(Vector3(rec.origin) + Vector3(rec.size) * 0.5)
	lab.world_sync.stamp_model(rec.origin, rec.size, rec.voxels, true)
	lab.world_sync.carve_sphere(at, GAS_RADIUS, GAS_POWER, Vector3.UP)
	Fire.ignite_at(at, GAS_RADIUS + 1.0, 40)
	if lab.enemies:
		for victim in Combat.sphere_hit(at, GAS_REACH):
			if Combat.can_see(lab.world, at, victim.get_center()):
				lab.enemies.damage(victim.id, GAS_DAMAGE, at, "blast")
		for player in lab.enemies.targets():
			var box := player.get_body_aabb()
			if at.clamp(box.position, box.end).distance_to(at) <= GAS_REACH and Combat.sees_player(lab.world, at, player):
				lab.enemies.damage_player(player, GAS_PLAYER_DAMAGE, at)
	var state := play.state_of(id).duplicate()
	state.used = true
	play._set_state(id, state, "")
	_blast_fx(at, GAS_RADIUS)
	for peer_id in play._peers():
		_blast_fx.rpc_id(peer_id, at, GAS_RADIUS)


@rpc("authority", "reliable")
func _blast_fx(at: Vector3, radius: float) -> void:
	Sfx.play_at("blast", at)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 6.0
	light.omni_range = radius * 6.0
	play.lab.view.add_child(light)
	light.global_position = at
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.35)
	tween.tween_callback(light.queue_free)
	VoxelFx.blast(play.lab.view, at, radius, Color(1.0, 0.6, 0.2))


## Host: a piece heavier than CRUSH_VOXELS (a hanging crate cut down) starts to fall
## (FallingPieces.piece_falling): it crushes the enemies and players in the column it falls
## through, as it starts (the landing is already known). FallingPieces plays the thud as it lands.
func _on_piece_falling(fall: Dictionary) -> void:
	if not play.active or not multiplayer.is_server() or play.lab.enemies == null:
		return
	var heavy := int(fall.voxel_count) - int(fall.materials.get(VoxelMaterials.CEILING_TILE, 0))
	if heavy <= CRUSH_VOXELS:
		return
	var enemies := play.lab.enemies
	var box: AABB = fall.box
	var fell: AABB = fall.column
	var column := AABB(fell.position - Vector3(0.15, 0.0, 0.15), fell.size + Vector3(0.3, 0.0, 0.3))
	for enemy in Combat.box_hit(column):
		enemies.damage(enemy.id, CRUSH_DAMAGE, box.get_center(), "blast")
	for player in enemies.targets():
		if column.intersects(player.get_body_aabb()):
			enemies.damage_player(player, CRUSH_PLAYER_DAMAGE, box.get_center())


func _physics_process(delta: float) -> void:
	if not play.active or not multiplayer.is_server():
		return
	_fire_timer -= delta
	if _fire_timer <= 0.0 and not _reactive.is_empty():
		_fire_timer = FIRE_CHECK
		_check_fire()
	if not _sprinkling.is_empty():
		_sprinkle_tick -= delta
		if _sprinkle_tick <= 0.0:
			_sprinkle_tick = SPRINKLE_TICK
			for room: String in _sprinkling.keys():
				_sprinkling[room] = float(_sprinkling[room]) - SPRINKLE_TICK
				_wet(room)
				if _sprinkling[room] <= 0.0:
					_sprinkling.erase(room)
					set_room_lights(room, str(_sprinkle_before.get(room, "on")))
					_sprinkle_before.erase(room)
					_set_rain(room, false)
					for peer_id in play._peers():
						_set_rain.rpc_id(peer_id, room, false)


## Host: reactive props next to fire, or in a fire cloud, go off.
func _check_fire() -> void:
	var lab := play.lab
	for id: String in _reactive.keys():
		var rec: Dictionary = _reactive.get(id, {})
		if rec.is_empty() or rec.get("moving", false):
			continue
		var at := lab.view.to_world(Vector3(rec.origin) + Vector3(rec.size) * 0.5)
		var hot := lab.fire != null and lab.fire.near_fire(at, 0.2, true)
		if not hot and lab.enemies:
			for cloud: Cloud in lab.enemies.clouds.values():
				if cloud.type == "fire" and cloud.global_position.distance_to(at) <= cloud.radius:
					hot = true
					break
		if hot:
			_set_off(id, rec, true)


# --- Rooms: lights and sprinklers ----------------------------------------------------------------

## Host, from LevelPlay._run_actions: `lights=<room>:off|on|flicker` and `sprinkle=<room>`. Returns
## false for a key it doesn't know.
func run_action(trigger_id: String, key: String, value: String) -> bool:
	match key:
		"lights":
			var room := value.get_slice(":", 0).strip_edges()
			var mode := value.get_slice(":", 1).strip_edges() if value.contains(":") else "off"
			if room_box(room) == AABB() or mode not in ["on", "off", "flicker"]:
				push_warning("trigger %s: lights=%s needs a room or trigger id and on, off or flicker" % [trigger_id, value])
			else:
				set_room_lights(room, mode)
		"sprinkle":
			if room_box(value) == AABB():
				push_warning("trigger %s: sprinkle=%s isn't a room or trigger" % [trigger_id, value])
			else:
				sprinkle(value)
		_:
			return false
	return true


## Host: sprinklers in a room for SPRINKLE_SECONDS: fire out, gas clouds gone, lights flickering.
func sprinkle(room: String) -> void:
	if not _sprinkling.has(room):
		_sprinkle_before[room] = str(room_lights.get(room, "on"))
	_sprinkling[room] = SPRINKLE_SECONDS
	_sprinkle_tick = 0.0
	set_room_lights(room, "flicker")
	_set_rain(room, true)
	for peer_id in play._peers():
		_set_rain.rpc_id(peer_id, room, true)


## Host: one sprinkler tick in a room: douses every fire in its box and ends its clouds.
func _wet(room: String) -> void:
	var lab := play.lab
	var box := room_box(room)
	var world_box := AABB(lab.view.to_world(box.position), box.size * lab.world.voxel_size)
	var center := world_box.get_center()
	Fire.douse_at(center, world_box.size.length() * 0.5)
	if lab.enemies:
		for cloud: Cloud in lab.enemies.clouds.values():
			if world_box.grow(0.5).has_point(cloud.global_position):
				lab.enemies.end_cloud(cloud.id)


## Host: a room's lights "off", "flicker" or back "on", everywhere.
func set_room_lights(room: String, mode: String) -> void:
	_room_lights(room, mode, true)
	for peer_id in play._peers():
		_room_lights.rpc_id(peer_id, room, mode, true)


## Every peer: a room's lights mode; sound is false for a late joiner catching up (_send_state).
@rpc("authority", "reliable")
func _room_lights(room: String, mode: String, sound: bool) -> void:
	if mode == "on":
		room_lights.erase(room)
	else:
		room_lights[room] = mode
	_lights_changed()
	if sound:
		Sfx.play_at("power_down" if mode == "off" else "power_up", play.lab.view.to_world(room_box(room).get_center()), -6.0)


## Every peer: a room's (or trigger volume's) box in voxels, or an empty AABB if id is neither.
func room_box(id: String) -> AABB:
	var object: Dictionary = play.lab.level.objects.get(id, {}) if play.lab.level else {}
	if object.get("kind") == "room":
		return LevelSchema.room_outer(object)
	if object.get("kind") == "marker" and object.get("type") == "trigger":
		return LevelSchema.marker_box(object)
	return AABB()


## The smallest room whose box holds a voxel-space point, or "".
func room_at(point: Vector3) -> String:
	var best := ""
	var best_volume := INF
	for object: Dictionary in play.lab.level.objects.values():
		if object.get("kind") != "room":
			continue
		var box := LevelSchema.room_outer(object)
		if box.has_point(point) and box.get_volume() < best_volume:
			best_volume = box.get_volume()
			best = object.id
	return best


## Every peer, for LevelView: "off", "flicker" or "" for a light marker, by the rooms holding it.
func light_mode(light_id: String) -> String:
	if room_lights.is_empty():
		return ""
	var object: Dictionary = play.lab.level.objects.get(light_id, {})
	if object.is_empty():
		return ""
	var at: Vector3 = object.position
	var mode := ""
	for room: String in room_lights:
		if room_box(room).has_point(at):
			if room_lights[room] == "off":
				return "off"
			mode = room_lights[room]
	return mode


## Every peer: the sprinkler's rain over a room (falling blue-white cubes from its ceiling), or not.
@rpc("authority", "reliable")
func _set_rain(room: String, on: bool) -> void:
	if _rain.has(room):
		_rain[room].queue_free()
		_rain.erase(room)
	if not on:
		return
	var lab := play.lab
	var box := room_box(room)
	var world_box := AABB(lab.view.to_world(box.position), box.size * lab.world.voxel_size)
	var rain := VoxelFx.particles(0.1, [Color(0.75, 0.85, 1.0), Color(0.55, 0.7, 0.95)], 0.8)
	rain.amount = clampi(int(world_box.size.x * world_box.size.z * 4.0), 40, 400)
	rain.lifetime = 1.0
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(world_box.size.x * 0.5, 0.05, world_box.size.z * 0.5)
	rain.direction = Vector3.DOWN
	rain.spread = 2.0
	rain.initial_velocity_min = 3.0
	rain.initial_velocity_max = 4.0
	rain.gravity = Vector3(0.0, -9.0, 0.0)
	lab.view.add_child(rain)
	rain.global_position = Vector3(world_box.get_center().x, world_box.end.y - 0.2, world_box.get_center().z)
	rain.emitting = true
	_rain[room] = rain
	Sfx.play_at("splash", rain.global_position, -2.0)


## Host: a late joiner gets the room lights and the sprinklers running.
func _send_state(peer_id: int) -> void:
	if not multiplayer.is_server() or not play.active:
		return
	for room: String in room_lights:
		_room_lights.rpc_id(peer_id, room, str(room_lights[room]), false)
	for room: String in _sprinkling:
		_set_rain.rpc_id(peer_id, room, true)


# --- Radios (every peer) --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not play.active:
		return
	_radio_timer -= delta
	if _radio_timer > 0.0:
		return
	_radio_timer = 0.25
	# The loops follow prop_state, which late joiners get whole (no state_changed for them).
	for id: String in play.prop_state:
		var object: Dictionary = play.lab.level.objects.get(id, {})
		if object.get("use") != "radio":
			continue
		var on := bool(play.prop_state[id].get("on", false))
		if on and not _radios.has(id):
			_radios[id] = _start_loop(_center(object))
		elif not on and _radios.has(id):
			_radios[id].queue_free()
			_radios.erase(id)


func _start_loop(at: Vector3) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = Sfx.stream("radio_loop")
	player.volume_db = RADIO_DB
	player.unit_size = 4.0
	player.max_distance = RADIO_RANGE
	add_child(player)
	player.global_position = at
	if player.stream and not Sfx.is_muted():
		player.play()
	return player
