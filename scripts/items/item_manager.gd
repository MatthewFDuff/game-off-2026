class_name ItemManager
extends Node3D
## Owns the level's pickups (its children, named "I<id>" so every peer agrees). The host spawns
## them when play starts, one per item spot marker (the marker's `item` names it), and from enemy
## deaths (drop_chance of a random ammo pickup); peers in the level are told, and late joiners get
## the roster. Going back to edit clears them everywhere, like enemies.
##
## Picking up: the host checks every living player each physics tick; the first within
## PICKUP_RADIUS gets it. The host removes it on every peer and sends the item to that player's own
## peer, which adds it to its Inventory (each peer runs its own player, as with damage).
##
## Shift saves: the host remembers which item spots were picked (taken_spots) and what lies loose
## (loose); restore puts both back on a resume.

## Host: a player (peer id) picked up an item.
signal picked(item: String, peer_id: int)
## This peer's player got an item.
signal local_picked(item: String)

const SCENE := preload("res://scenes/pickup.tscn")
## Meters from a player's body (its vertical line from feet to head) that picks an item up.
const PICKUP_RADIUS := 0.8
## Pickups float this far above the marker or the dead enemy's feet.
const HOVER := 0.35

@export var lab: Lab
@export var world: VoxelWorld
@export var enemies: EnemyManager
## Chance an enemy drops an ammo pickup when it dies.
@export_range(0.0, 1.0) var drop_chance := 0.2

## In play mode.
var active := false
## id -> Pickup
var pickups := {}

var _next_id := 1
var _rng := RandomNumberGenerator.new()
## Host: pickup id -> the item spot marker it came from (for the shift save's items_taken).
var _spot_of := {}
## Host: item spot marker ids whose pickup has been taken this play.
var _taken_spots: Array[String] = []


func _ready() -> void:
	_rng.randomize()
	lab.mode_changed.connect(func(mode: String) -> void:
		if mode == "play":
			start()
		else:
			stop())
	lab.peer_entered.connect(_send_roster)
	if enemies:
		enemies.enemy_died.connect(_on_enemy_died)
	var watch := get_node_or_null("/root/VoxWatch")
	if watch:
		watch.changed.connect(_on_vox_changed)


## Every peer, when play begins: a fresh inventory, and (host) the item spots' pickups.
func start() -> void:
	active = true
	var me := lab.local_player()
	if me and me.inventory:
		me.inventory.clear()
	if not multiplayer.is_server():
		return
	clear()
	for object: Dictionary in lab.level.objects.values():
		if object.kind == "marker" and object.type == "item" and String(object.get("item", "")) != "":
			var pickup := spawn(object.item, lab.view.to_world(object.position) + Vector3.UP * HOVER)
			if pickup:
				_spot_of[pickup.id] = object.id


func stop() -> void:
	active = false
	clear()


## Removes every pickup on this peer, no effects.
func clear() -> void:
	for pickup: Pickup in pickups.values():
		pickup.queue_free()
	pickups.clear()
	_spot_of.clear()
	_taken_spots.clear()


## Host: item spot marker ids whose pickups are gone (the shift save's items_taken).
func taken_spots() -> Array:
	return Array(_taken_spots)


## Host: pickups lying about that came from no item spot (container contents, enemy drops), as
## [item, [x, y, z]], so a resumed shift still has the spore shooter a case dropped.
func loose() -> Array:
	var out: Array = []
	for id: int in pickups:
		if not _spot_of.has(id):
			var at: Vector3 = pickups[id].global_position
			out.append([pickups[id].item, [at.x, at.y, at.z]])
	return out


## Host, resuming a shift before any peer is here: the taken spots' pickups go (quietly) and the
## loose ones come back.
func restore(taken: Array, loose_items: Array) -> void:
	if not multiplayer.is_server() or not active:
		return
	for id: int in _spot_of.keys():
		if str(_spot_of[id]) in taken and pickups.has(id):
			pickups[id].queue_free()
			pickups.erase(id)
			_spot_of.erase(id)
	_taken_spots.assign(taken.map(func(spot) -> String: return str(spot)))
	for entry in loose_items:
		if entry is Array and entry.size() == 2 and entry[1] is Array and entry[1].size() == 3:
			spawn(str(entry[0]), Vector3(float(entry[1][0]), float(entry[1][1]), float(entry[1][2])))


## Host: puts an item in the world at a position (the model's middle). Returns it, or null when not
## in play.
func spawn(item: String, at: Vector3) -> Pickup:
	if not multiplayer.is_server() or not active:
		return null
	if not item in GearModels.ITEMS:
		push_warning("item '%s' has no placeholder model; spawning it anyway" % item)
	var id := _next_id
	_next_id += 1
	var pickup := _create(id, item, at)
	for peer_id in _peers():
		_spawned.rpc_id(peer_id, id, item, at)
	return pickup


func _create(id: int, item: String, at: Vector3) -> Pickup:
	var pickup: Pickup = SCENE.instantiate()
	pickup.name = "I%d" % id
	pickup.id = id
	pickup.item = item
	pickup.world = world
	pickup.position = to_local(at)
	add_child(pickup)
	pickups[id] = pickup
	return pickup


func _remove(id: int) -> void:
	var pickup: Pickup = pickups.get(id)
	if pickup:
		pickups.erase(id)
		Sfx.play_at("pickup", pickup.global_position, -6.0)
		pickup.queue_free()


## Host peers that get item messages: everyone in the level but the host.
func _peers() -> Array[int]:
	var out: Array[int] = []
	if multiplayer.is_server():
		for peer_id in lab.peers_in_level:
			if peer_id != 1:
				out.append(peer_id)
	return out


func _send_roster(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	for pickup: Pickup in pickups.values():
		_spawned.rpc_id(peer_id, pickup.id, pickup.item, pickup.global_position)


@rpc("authority", "reliable")
func _spawned(id: int, item: String, at: Vector3) -> void:
	if not pickups.has(id):
		_create(id, item, at)


@rpc("authority", "reliable")
func _taken(id: int) -> void:
	_remove(id)


# --- Picking up (host) ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not active or not multiplayer.is_server() or pickups.is_empty():
		return
	for id: int in pickups.keys():
		var pickup: Pickup = pickups[id]
		var at := pickup.global_position
		for peer_id: int in lab.players:
			var player: Player = lab.players[peer_id]
			if not is_instance_valid(player) or player.is_dead or player.editing:
				continue
			var feet := player.global_position
			var nearest := Vector3(feet.x, clampf(at.y, feet.y, feet.y + player.standing_height), feet.z)
			if nearest.distance_to(at) <= PICKUP_RADIUS:
				_take(id, peer_id)
				break


## Host: peer_id's player got pickup id. Gone everywhere; the item goes to that player's peer.
func _take(id: int, peer_id: int) -> void:
	var pickup: Pickup = pickups.get(id)
	if pickup == null:
		return
	var item := pickup.item
	if _spot_of.has(id):
		_taken_spots.append(str(_spot_of[id]))
		_spot_of.erase(id)
	_remove(id)
	for peer in _peers():
		_taken.rpc_id(peer, id)
	picked.emit(item, peer_id)
	if peer_id == multiplayer.get_unique_id():
		_receive(item)
	else:
		_give.rpc_id(peer_id, item)


@rpc("authority", "reliable")
func _give(item: String) -> void:
	_receive(item)


## This peer's player got an item.
func _receive(item: String) -> void:
	var me := lab.local_player()
	if me == null or me.inventory == null:
		return
	if me.inventory.add(item):
		Sfx.play("pickup", -2.0)
		lab.notify(describe(item), false)
		local_picked.emit(item)


## Player-facing name for an item ("+12 Shotgun ammo", "Fire flask", "Red keycard").
static func describe(item: String) -> String:
	if item == "medkit":
		return "Medkit (+%d health)" % int(Inventory.MEDKIT_HEAL)
	if item.begins_with("ammo_"):
		var type := AmmoType.by_name(item.trim_prefix("ammo_"))
		if type:
			return "+%d %s ammo" % [type.pickup, type.label]
	if item.begins_with("flask_"):
		return "%s flask" % item.trim_prefix("flask_").capitalize()
	if item.begins_with("keycard_"):
		return "%s keycard" % item.trim_prefix("keycard_").capitalize()
	if item == "spore_shooter":
		return "Experimental spore shooter"
	return item.capitalize()


## Host: enemies sometimes drop ammo.
func _on_enemy_died(enemy: Enemy) -> void:
	if not active or not multiplayer.is_server() or _rng.randf() >= drop_chance:
		return
	var choices: Array[String] = []
	for type in AmmoType.all():
		if not type.infinite:
			choices.append(type.name)
	spawn("ammo_" + choices[_rng.randi() % choices.size()], enemy.global_position + Vector3.UP * HOVER)


## Live reload: re-skin pickups whose .vox changed.
func _on_vox_changed(paths: PackedStringArray) -> void:
	var names := {}
	for path in paths:
		if path.begins_with(GearModels.ITEM_DIR):
			names[GearModels.forget(path)] = true
	for pickup: Pickup in pickups.values():
		if names.has(pickup.item):
			pickup.build()
