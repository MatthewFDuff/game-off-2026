class_name LevelPlay
extends Node
## Play-mode runtime for a level's objects: doors, triggers, kill zones and company assets. The host
## runs all of it; peers only see doors move.
##
## Doors are voxels while still, so collision, bullets, enemies and damage need nothing special.
## While a door moves, its voxels are erased, a mesh of it slides, and it's stamped again where it
## stops. Asset damage is the share of an asset's voxels that are gone, priced at its value.

## Host: a trigger fired. peer_id is the player who set it off (for "all", the last one in).
signal triggered(id: String, peer_id: int)
## Host: an asset lost dollars worth of voxels. total is all asset damage so far.
signal asset_damaged(id: String, dollars: int, total: int)
## Host: a player walked into a kill zone.
signal killed_in_zone(id: String, peer_id: int)

## How close (meters) a player must be to use a door.
const DOOR_REACH := 3.0

@export var lab: Lab

var active := false
## Host: dollars of asset damage since play started.
var total_damage := 0

## id -> {object, model (turned), origin: Vector3i, open: bool, moving: bool}
var _doors := {}
## id -> {origin, size, voxels, total, intact, value, name}
var _assets := {}
## Trigger ids that already fired (one-shot ones) and peers inside each (for edge detection).
var _fired := {}
var _inside := {}
## Damage not yet announced: id -> dollars. Announced in batches so a burst of fire is one line.
var _pending_notes := {}
var _note_timer := 0.0


## Every peer, when play begins (props already stamped by the host).
func start() -> void:
	active = true
	total_damage = 0
	_doors.clear()
	_assets.clear()
	_fired.clear()
	_inside.clear()
	for object: Dictionary in lab.level.objects.values():
		if object.kind != "prop":
			continue
		var model := Props.load_prop(object.name)
		if model.is_empty():
			continue
		var turned := Props.orient(model, object.facing)
		if object.door:
			_doors[object.id] = {object = object, model = turned, origin = object.origin, open = false, moving = false}
		elif object.value > 0 and multiplayer.is_server():
			var intact: int = lab.world.count_matching(object.origin, turned.size, turned.voxels)
			_assets[object.id] = {origin = object.origin, size = turned.size, voxels = turned.voxels,
					total = maxi(intact, 1), intact = intact, value = object.value, name = object.name}
	if multiplayer.is_server() and not lab.world.voxels_changed.is_connected(_on_voxels_changed):
		lab.world.voxels_changed.connect(_on_voxels_changed)


func stop() -> void:
	active = false
	_doors.clear()
	_assets.clear()
	if lab.world.voxels_changed.is_connected(_on_voxels_changed):
		lab.world.voxels_changed.disconnect(_on_voxels_changed)


# --- Doors ---------------------------------------------------------------------------------------

## The door the player is looking at within reach, or "".
func door_in_view(camera: Camera3D) -> String:
	var from := camera.global_position
	var direction := -camera.global_basis.z
	var best := ""
	var best_distance := DOOR_REACH
	for id: String in _doors:
		var door: Dictionary = _doors[id]
		var box := AABB(lab.view.to_world(Vector3(door.origin)), Vector3(door.model.size) * lab.world.voxel_size)
		var hit = box.intersects_ray(from, direction)
		if hit != null and from.distance_to(hit) < best_distance:
			best_distance = from.distance_to(hit)
			best = id
	return best


func is_door_locked(id: String) -> bool:
	return _doors.has(id) and _doors[id].object.door_locked


## Any peer: asks the host to open or close a door (the interact key). Locked doors refuse.
func request_toggle(id: String) -> void:
	if multiplayer.is_server():
		_toggle_request(id)
	else:
		_request_toggle.rpc_id(1, id)


@rpc("any_peer", "reliable")
func _request_toggle(id: String) -> void:
	if multiplayer.is_server():
		_toggle_request(id)


func _toggle_request(id: String) -> void:
	if _doors.has(id) and not _doors[id].object.door_locked:
		set_door(id, not _doors[id].open)


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


# --- Triggers and kill zones (host) ----------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not active or not multiplayer.is_server():
		return
	for object: Dictionary in lab.level.objects.values():
		if object.kind != "marker" or not object.type in ["trigger", "kill_zone"]:
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
	var lines: Array[String] = []
	for id: String in _pending_notes:
		lines.append("-$%d  %s" % [_pending_notes[id], _assets[id].name.replace("_", " ") if _assets.has(id) else id])
	_pending_notes.clear()
	lab.notify("\n".join(lines))
