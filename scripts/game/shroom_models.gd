class_name ShroomModels
## Builds voxel models of mushrooms: a dormant spore lump at stage 0 up to a full-grown shroom at
## MAX_STAGE. Grown hunters get glowing eyes on the front (-Z) of the stem.

const M := preload("res://scripts/voxel/voxel_materials.gd")
const MAX_STAGE := 4
const VARIANTS := 4


## Returns {size: Vector3i, voxels: PackedByteArray} indexed x + y * size.x + z * size.x * size.y.
static func build(stage: int, variant: int, eyes: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant * 7919 + 17
	var g := float(stage) / MAX_STAGE
	var stem_height := roundi(lerpf(1.0, 8.0, g))
	var stem_radius := lerpf(0.7, 1.7, g)
	var cap_radius := lerpf(1.3, 5.2, g) + rng.randf_range(-0.4, 0.5) * g
	var cap_height := lerpf(1.2, 4.0, g) + rng.randf_range(-0.4, 0.6) * g
	var spot_chance := rng.randf_range(0.08, 0.2)

	var width := 2 * ceili(cap_radius) + 1
	var size := Vector3i(width, stem_height + ceili(cap_height) + 1, width)
	var voxels := PackedByteArray()
	voxels.resize(size.x * size.y * size.z)
	var c := (width - 1) * 0.5
	var cap_base := float(stem_height)

	for y in size.y:
		for z in size.z:
			for x in size.x:
				var dx := x - c
				var dz := z - c
				var flat := sqrt(dx * dx + dz * dz)
				var material := M.AIR
				# Stem, with a slightly swollen base.
				var radius := stem_radius * (1.3 if y == 0 and stage > 1 else 1.0)
				if y < stem_height + 1 and flat <= radius:
					material = M.SHROOM_STEM
				# Dome-shaped cap sitting on the stem.
				var dy := y - cap_base + 0.5
				if dy >= 0.0 and (dx * dx + dz * dz) / (cap_radius * cap_radius) + (dy * dy) / (cap_height * cap_height) <= 1.0:
					material = M.SHROOM_CAP
					if y == stem_height and flat < cap_radius - 1.0 and flat > radius:
						material = M.SHROOM_GILL
				voxels[_index(size, x, y, z)] = material

	# Glowing spots on the exposed cap surface.
	for y in range(stem_height + 1, size.y):
		for z in size.z:
			for x in size.x:
				var i := _index(size, x, y, z)
				if voxels[i] == M.SHROOM_CAP and _exposed(voxels, size, x, y, z) and rng.randf() < spot_chance:
					voxels[i] = M.SHROOM_SPOT

	if eyes and stage == MAX_STAGE:
		var eye_y := maxi(1, stem_height - 3)
		for ex in [floori(c) - 1, ceili(c) + 1]:
			for z in size.z:
				var i := _index(size, ex, eye_y, z)
				if voxels[i] == M.SHROOM_STEM:
					voxels[i] = M.SHROOM_EYE
					break
	return {size = size, voxels = voxels}


static func _index(size: Vector3i, x: int, y: int, z: int) -> int:
	return x + y * size.x + z * size.x * size.y


static func _exposed(voxels: PackedByteArray, size: Vector3i, x: int, y: int, z: int) -> bool:
	for offset in [Vector3i.UP, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		var p: Vector3i = Vector3i(x, y, z) + offset
		if p.x < 0 or p.y < 0 or p.z < 0 or p.x >= size.x or p.y >= size.y or p.z >= size.z:
			return true
		if voxels[_index(size, p.x, p.y, p.z)] == M.AIR:
			return true
	return false
