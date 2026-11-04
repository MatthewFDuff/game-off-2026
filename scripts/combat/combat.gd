class_name Combat
## Hit detection against the voxel world and enemies, for every weapon. Enemies register in the
## Enemy.GROUP node group, so each query is a loop over them. Queries only find enemies; damage goes
## through EnemyManager.request_hit so the host applies it.
##
## The group is read once and kept (_group) until an enemy enters the tree (Enemy._ready calls
## invalidate) or the physics frame changes; each query skips the dead, freed and emerging ones as
## it goes, so a kill or a finished emergence within the frame shows at once.

## Every Enemy.GROUP member as last read, and the physics frame it was read in (-1: stale).
static var _group: Array = []
static var _group_frame := -1


## The nearest thing a ray hits within range: a voxel (world.raycast) or an enemy (its bounds, then
## its named hit zones). ignore lists enemies to pass through (piercing). Returns
## {hit, position, normal, distance, enemy (Enemy or null), zone (String, "" for voxels),
## crit (multiplier), material (voxel hits, else 0)}.
static func ray_hit(world: VoxelWorld, from: Vector3, direction: Vector3, max_range: float, ignore: Array = []) -> Dictionary:
	var dir := direction.normalized()
	var result := {hit = false, position = from + dir * max_range, normal = Vector3.ZERO, distance = max_range,
			enemy = null, zone = "", crit = 1.0, material = 0}
	var voxel: Dictionary = world.raycast(from, dir, max_range)
	if voxel.hit:
		result.hit = true
		result.position = voxel.position
		result.normal = voxel.normal
		result.distance = voxel.distance
		result.material = voxel.material
	for node: Variant in _live():
		if not _hittable(node) or (not ignore.is_empty() and node in ignore):
			continue
		var enemy: Enemy = node
		# The bounding sphere first (cheap); the full test only for rays that can reach it in range.
		if not enemy.ray_could_hit(from, dir, result.distance):
			continue
		var hit := enemy.ray_test(from, dir, result.distance)
		if not hit.is_empty() and hit.distance < result.distance:
			result.hit = true
			result.position = hit.position
			result.normal = hit.normal
			result.distance = hit.distance
			result.enemy = enemy
			result.zone = hit.zone
			result.crit = hit.crit
			result.material = 0
	return result


## Enemies whose bounds come within radius of center (blasts, clouds).
static func sphere_hit(center: Vector3, radius: float) -> Array[Enemy]:
	var found: Array[Enemy] = []
	for node: Variant in _live():
		if not _hittable(node):
			continue
		var enemy: Enemy = node
		var box := enemy.world_bounds()
		var closest := center.clamp(box.position, box.end)
		if closest.distance_squared_to(center) <= radius * radius:
			found.append(enemy)
	return found


## Enemies whose bounds overlap a world-space box (melee swings).
static func box_hit(box: AABB) -> Array[Enemy]:
	var found: Array[Enemy] = []
	for node: Variant in _live():
		if _hittable(node) and (node as Enemy).world_bounds().intersects(box):
			var enemy: Enemy = node
			found.append(enemy)
	return found


## Every living enemy in the scene that can be hit (not still emerging, see Enemy.emerging). A new
## array each call; the queries here use the shared _live() list instead.
static func enemies() -> Array[Enemy]:
	var found: Array[Enemy] = []
	for node: Variant in _live():
		if _hittable(node):
			found.append(node)
	return found


## Whether a member of the cached group can be hit right now.
static func _hittable(node: Variant) -> bool:
	if not is_instance_valid(node):
		return false
	var enemy := node as Enemy
	return enemy != null and enemy.alive and enemy.emerging <= 0.0 and enemy.is_inside_tree()


## The cached Enemy.GROUP (read again once per physics frame or after invalidate). Shared: don't
## modify it, and check _hittable on each.
static func _live() -> Array:
	var frame := Engine.get_physics_frames()
	if _group_frame == frame:
		return _group
	_group.clear()
	_group_frame = frame
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return _group
	for node in tree.get_nodes_in_group(Enemy.GROUP):
		if node is Enemy:
			_group.append(node)
	return _group


## An enemy joined the group: the next query reads it again.
static func invalidate() -> void:
	_group_frame = -1


# --- Line of sight -------------------------------------------------------------------------------

## Most voxel raycasts one can_see makes (each glass voxel it looks through costs one more).
const SIGHT_STEPS := 6
## Volume change (dB) for an enemy sound with no line of sight to the listener (muffle_db).
const MUFFLED_DB := -14.0
## Beyond this many meters muffle_db skips the check (Sfx's voices fade out by 45 m anyway).
const MUFFLE_RANGE := 40.0
## VoxelMaterials.GLASS, GLASS_TEMPERED and GLASS_CRACKED (not named, so this compiles before the autoloads).
const _GLASS := [19, 46, 47]


## Whether nothing solid lies between two points: a voxel raycast (enemies and players don't
## block). Glass is see-through. A start point inside a solid voxel (a cloud centered on the floor,
## a head brushing a ceiling) steps out of it first, up to half a meter, so only what's between
## the two points counts. No world: true.
static func can_see(world: VoxelWorld, from: Vector3, to: Vector3) -> bool:
	if world == null:
		return true
	var offset := to - from
	var distance := offset.length()
	if distance < 0.01:
		return true
	var dir := offset / distance
	var step := world.voxel_size * 0.5
	var start := 0.0
	# Out of the voxel the start is buried in, if it is.
	while start < 0.5 and world.get_voxel(world.world_to_voxel(from + dir * start)) != 0:
		start += step
	for i in SIGHT_STEPS:
		if start >= distance:
			return true
		var hit: Dictionary = world.raycast(from + dir * start, dir, distance - start)
		if not hit.hit:
			return true
		var at := start + float(hit.distance)
		# The end point itself resting in a surface (feet on a floor) isn't something in between.
		if at >= distance - step:
			return true
		if not int(hit.material) in _GLASS:
			return false
		start = at + step
	return false


## Whether a box (a coarse fire cell, say) is in sight of a point: can_see to its middle, or the
## first solid voxel a ray toward the middle meets lies in the box (grown by a voxel), so what's in
## the way is the box's own contents (the burning voxels themselves). No world: true.
static func can_see_box(world: VoxelWorld, from: Vector3, box: AABB) -> bool:
	var to := box.get_center()
	if world == null or can_see(world, from, to):
		return true
	var offset := to - from
	var distance := offset.length()
	if distance < 0.01:
		return true
	var dir := offset / distance
	var start := 0.0
	while start < 0.5 and world.get_voxel(world.world_to_voxel(from + dir * start)) != 0:
		start += world.voxel_size * 0.5
	var hit: Dictionary = world.raycast(from + dir * start, dir, maxf(distance - start, 0.0))
	return hit.hit and box.grow(world.voxel_size).has_point(hit.position)


## Whether a player's chest is in sight of a point.
static func sees_player(world: VoxelWorld, from: Vector3, player: Player) -> bool:
	return can_see(world, from, chest(player))


## A player's chest (where sight checks aim): 60% of their body height above the feet.
static func chest(player: Player) -> Vector3:
	return player.global_position + Vector3.UP * player.get_body_size().y * 0.6


## Volume change for an enemy's sound at a point on this peer: MUFFLED_DB when the listening
## camera has no line of sight to it (through a floor or wall), else 0.
static func muffle_db(world: VoxelWorld, at: Vector3) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if world == null or tree == null or tree.root == null:
		return 0.0
	var camera := tree.root.get_camera_3d()
	if camera == null or not camera.is_inside_tree():
		return 0.0
	var ear := camera.global_position
	if ear.distance_squared_to(at) > MUFFLE_RANGE * MUFFLE_RANGE:
		return 0.0
	return 0.0 if can_see(world, at, ear) else MUFFLED_DB
