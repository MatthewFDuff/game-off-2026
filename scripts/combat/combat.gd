class_name Combat
## Hit detection against the voxel world and enemies, for every weapon. Enemies register in the
## Enemy.GROUP node group, so each query is a loop over them. Queries only find enemies; damage goes
## through EnemyManager.request_hit so the host applies it.


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
	for enemy in enemies():
		if enemy in ignore:
			continue
		var hit := enemy.ray_test(from, dir)
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
	for enemy in enemies():
		var box := enemy.world_bounds()
		var closest := center.clamp(box.position, box.end)
		if closest.distance_squared_to(center) <= radius * radius:
			found.append(enemy)
	return found


## Enemies whose bounds overlap a world-space box (melee swings).
static func box_hit(box: AABB) -> Array[Enemy]:
	var found: Array[Enemy] = []
	for enemy in enemies():
		if enemy.world_bounds().intersects(box):
			found.append(enemy)
	return found


## Every living enemy in the scene.
static func enemies() -> Array[Enemy]:
	var found: Array[Enemy] = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return found
	for node in tree.get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy and enemy.alive:
			found.append(enemy)
	return found
