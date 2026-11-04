class_name EnemyModels
## Enemy bodies: MagicaVoxel files in assets/vox/enemies/, one or more per kind
## (`<kind>_<variant>.vox`, or a single `<kind>.vox`). The files are the source of truth; the
## generators here only write the placeholders (scripts/tools/export_vox.gd) and stand in when a
## kind has no file yet. Models face -Z and stand on the bottom center of their box.

const DIR := "res://assets/vox/enemies/"
## Placeholder variants written per kind.
const VARIANTS := {basic = ShroomModels.VARIANTS,
		fast = 3, exploding = 2, alarm = 2, giant = 2, ranged = 2,
		mommy = 1, spore = 2, ceiling_cloud = 2, tentacle = 2}

## path -> model ({size, voxels}), loaded once and dropped on live reload.
static var _cache := {}


## The .vox paths for a kind, sorted, so every peer picks the same variant for the same id.
static func paths(kind: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file in DirAccess.get_files_at(DIR):
		if file.get_extension() != "vox":
			continue
		var base := file.get_basename()
		if base == kind or (base.begins_with(kind + "_") and base.trim_prefix(kind + "_").is_valid_int()):
			found.append(DIR + file)
	found.sort()
	return found


## The model for an enemy of this kind: variant picks among its files (wrapping).
static func model(kind: String, variant: int) -> Dictionary:
	var files := paths(kind)
	if files.is_empty():
		var key := "generated:%s:%d" % [kind, variant]
		if not _cache.has(key):
			_cache[key] = generate(kind, variant % VARIANTS.get(kind, 1))
		return _cache[key]
	var path := files[posmod(variant, files.size())]
	if not _cache.has(path):
		var loaded := VoxFile.load_model(path)
		_cache[path] = loaded if not loaded.is_empty() else generate(kind, variant)
	return _cache[path]


## Live reload: forget a file so the next model() reads it again. Returns the kind it belongs to.
static func forget(path: String) -> String:
	_cache.erase(path)
	var base := path.get_file().get_basename()
	var suffix := base.get_slice("_", base.get_slice_count("_") - 1)
	return base.trim_suffix("_" + suffix) if suffix.is_valid_int() else base


## Placeholder model for a kind. New kinds add a generator here.
static func generate(kind: String, variant: int) -> Dictionary:
	match kind:
		"basic":
			return ShroomModels.build(ShroomModels.MAX_STAGE, variant, true)
		"fast":
			return _fast(variant)
		"exploding":
			return _exploding(variant)
		"alarm":
			return _alarm(variant)
		"giant":
			return _giant(variant)
		"ranged":
			return _ranged(variant)
		"mommy":
			return _mommy(variant)
		"spore":
			return _spore(variant)
		"ceiling_cloud":
			return _ceiling_cloud(variant)
		"tentacle":
			return _tentacle(variant)
	push_warning("no placeholder model for enemy kind '%s'" % kind)
	return ShroomModels.build(ShroomModels.MAX_STAGE, variant, true)


# --- Roster placeholders: mommy, spore, ceiling_cloud, tentacle ----------------------------------

const _BROOD_M := preload("res://scripts/voxel/voxel_materials.gd")


## A size-boxed model filled by shape(x, y, z) -> material id.
static func _brood_fill(size: Vector3i, shape: Callable) -> Dictionary:
	var voxels := PackedByteArray()
	voxels.resize(size.x * size.y * size.z)
	for z in size.z:
		for y in size.y:
			for x in size.x:
				voxels[x + y * size.x + z * size.x * size.y] = shape.call(x, y, z)
	return {size = size, voxels = voxels}


static func _brood_rng(kind: String, variant: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + variant * 7919
	return rng


## Mommy shroom: a huge, wide, low cap covered in small bumps (budding young), on a squat stem,
## with a glowing underside.
static func _mommy(variant: int) -> Dictionary:
	var rng := _brood_rng("mommy", variant)
	var size := Vector3i(25, 16, 25)
	var c := 12.0
	var stem_top := 6
	var cap_r := 12.0
	var cap_h := 7.0
	var bumps: Array[Vector3] = []
	for i in 22:
		var angle := rng.randf() * TAU
		var along := sqrt(rng.randf()) * 0.85
		var dome := sqrt(maxf(0.0, 1.0 - along * along))
		bumps.append(Vector3(c + cos(angle) * along * cap_r, stem_top + 0.5 + dome * cap_h, c + sin(angle) * along * cap_r))
	return _brood_fill(size, func(x: int, y: int, z: int) -> int:
		var dx := x - c
		var dz := z - c
		var flat := sqrt(dx * dx + dz * dz)
		if y <= stem_top and flat <= 4.5 - y * 0.15:
			return _BROOD_M.SHROOM_STEM
		var dy := y - stem_top - 0.5
		if dy >= -1.0:
			var shell := (dx * dx + dz * dz) / (cap_r * cap_r) + dy * dy / (cap_h * cap_h)
			if shell <= 1.0:
				return _BROOD_M.GLOW if dy < 0.5 else _BROOD_M.SHROOM_CAP
		for bump in bumps:
			if Vector3(x, y, z).distance_to(bump) <= 1.3:
				return _BROOD_M.SHROOM_SPOT
		return _BROOD_M.AIR)


## Spore shroom: a fat puffball on a stubby foot, pocked with dark vents.
static func _spore(variant: int) -> Dictionary:
	var rng := _brood_rng("spore", variant)
	var size := Vector3i(9, 10, 9)
	var c := 4.0
	var r := 4.2 + rng.randf_range(-0.2, 0.3)
	var vents: Array[Vector3] = []
	for i in 6:
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		vents.append(Vector3(c, 5.5, c) + dir * r)
	return _brood_fill(size, func(x: int, y: int, z: int) -> int:
		var p := Vector3(x, y, z)
		if y <= 1 and Vector2(x - c, z - c).length() <= 2.0:
			return _BROOD_M.SHROOM_STEM
		if p.distance_to(Vector3(c, 5.5, c)) <= r:
			for vent in vents:
				if p.distance_to(vent) <= 1.2:
					return _BROOD_M.SHROOM_GILL
			if z == 0 and y == 6 and (x == 3 or x == 5):
				return _BROOD_M.SHROOM_EYE
			return _BROOD_M.SHROOM_STEM if (x + y + z) % 5 == 0 else _BROOD_M.SHROOM_CAP
		return _BROOD_M.AIR)


## Ceiling poison cloud: an upside-down bulbous sac (narrow root at the top, swollen below) with
## green drips hanging from its bottom. Stands on the bottom of its box like every model; it hangs
## with the top touching the ceiling. The sac is CLOTH with steel bands, the insulated duct's
## lagging (ceiling_pack.gd duct_insulated), so among the lagging it reads as ducting until it moves.
static func _ceiling_cloud(variant: int) -> Dictionary:
	var rng := _brood_rng("ceiling_cloud", variant)
	var size := Vector3i(8, 10, 8)
	var c := 3.5
	var drips := {}
	for i in 4:
		drips[Vector2i(rng.randi_range(2, 5), rng.randi_range(2, 5))] = rng.randi_range(1, 2)
	return _brood_fill(size, func(x: int, y: int, z: int) -> int:
		var flat := Vector2(x - c, z - c).length()
		if y >= 8:
			return _BROOD_M.CLOTH if flat <= 1.6 else _BROOD_M.AIR
		var dy := y - 5.0
		if y >= 2 and flat * flat / 14.0 + dy * dy / 10.0 <= 1.0:
			return _BROOD_M.STEEL if y == 6 else _BROOD_M.CLOTH # A lagging band round the middle.
		var key := Vector2i(x, z)
		if y < 2 and drips.has(key) and y >= 2 - int(drips[key]):
			return _BROOD_M.LIQUID_GREEN
		return _BROOD_M.AIR)


## Tentacle fungi: a lumpy central mass with 4 to 6 voxel tentacles sprawled out on the floor,
## thinning and curling toward the tips.
static func _tentacle(variant: int) -> Dictionary:
	var rng := _brood_rng("tentacle", variant)
	var size := Vector3i(31, 9, 31)
	var c := 15.0
	var count := 4 + variant % 3 + (1 if rng.randf() < 0.5 else 0)
	count = clampi(count, 4, 6)
	var arms: Array[PackedVector3Array] = []
	for i in count:
		var angle := TAU * i / count + rng.randf_range(-0.3, 0.3)
		var curl := rng.randf_range(-0.08, 0.08)
		var points := PackedVector3Array()
		var length := rng.randf_range(11.0, 14.5)
		for step in 30:
			var t := step / 29.0
			var a := angle + curl * t * length
			var d := 3.0 + t * length
			points.append(Vector3(c + cos(a) * d, 1.0 + sin(t * PI * 2.0) * 0.8 * (1.0 - t), c + sin(a) * d))
		arms.append(points)
	return _brood_fill(size, func(x: int, y: int, z: int) -> int:
		var p := Vector3(x, y, z)
		var core := Vector3(c, 3.0, c)
		var offset := p - core
		if Vector3(offset.x, offset.y * 1.3, offset.z).length() <= 4.6:
			if y >= 6 and (x + z) % 3 == 0:
				return _BROOD_M.SHROOM_EYE
			return _BROOD_M.SHROOM_GILL if (x * 7 + y * 3 + z) % 6 == 0 else _BROOD_M.SHROOM_CAP
		for points in arms:
			for i in points.size():
				var radius := lerpf(1.6, 0.5, float(i) / (points.size() - 1))
				if p.distance_to(points[i]) <= radius:
					return _BROOD_M.SHROOM_SPOT if i % 5 == 0 else _BROOD_M.SHROOM_STEM
		return _BROOD_M.AIR)


# --- Roster placeholders: fast, exploding, alarm, giant, ranged ------------------------------------

const _ROSTER_M := preload("res://scripts/voxel/voxel_materials.gd")


## Fast shroom: a thin stem leaning forward (-Z) under a small cap.
static func _fast(variant: int) -> Dictionary:
	var rng := _roster_rng("fast", variant)
	var lean := 0.3 + rng.randf_range(-0.05, 0.08)
	var cap_r := 3.0 + rng.randf_range(-0.3, 0.4)
	var stem_top := 10
	var model := _roster_sculpt(Vector3i(9, 12, 12), func(x: int, y: int, z: int) -> int:
		var cz := 7.5 - minf(y, stem_top) * lean
		var dx := x - 4.0
		var dz := z - cz
		var flat := sqrt(dx * dx + dz * dz)
		var dy := y - stem_top + 0.5
		if dy >= 0.0 and (dx * dx + dz * dz) / (cap_r * cap_r) + dy * dy / (2.4 * 2.4) <= 1.0:
			return _ROSTER_M.SHROOM_GILL if y == stem_top and flat > 1.2 and flat < cap_r - 0.8 else _ROSTER_M.SHROOM_CAP
		if y <= stem_top and flat <= (1.6 if y == 0 else 1.25):
			return _ROSTER_M.SHROOM_STEM
		return _ROSTER_M.AIR)
	_roster_speckle(model, _ROSTER_M.SHROOM_CAP, _ROSTER_M.SHROOM_SPOT, 0.15, rng, stem_top + 1)
	_roster_eyes(model, 7, [3, 5])
	return model


## Exploding shroom: a short stem under a swollen, bulbous cap thick with bright spots.
static func _exploding(variant: int) -> Dictionary:
	var rng := _roster_rng("exploding", variant)
	var swell := rng.randf_range(-0.3, 0.3)
	var model := _roster_sculpt(Vector3i(13, 14, 13), func(x: int, y: int, z: int) -> int:
		var dx := x - 6.0
		var dz := z - 6.0
		var flat := sqrt(dx * dx + dz * dz)
		var dy := y - 8.5
		var rx := 6.2 + swell
		if y >= 4 and (dx * dx + dz * dz) / (rx * rx) + dy * dy / (5.2 * 5.2) <= 1.0:
			return _ROSTER_M.SHROOM_CAP
		if y <= 4 and flat <= (2.2 if y == 0 else 1.8):
			return _ROSTER_M.SHROOM_STEM
		return _ROSTER_M.AIR)
	_roster_speckle(model, _ROSTER_M.SHROOM_CAP, _ROSTER_M.SHROOM_SPOT, 0.3, rng)
	_roster_speckle(model, _ROSTER_M.SHROOM_CAP, _ROSTER_M.SHROOM_EYE, 0.08, rng)
	_roster_eyes(model, 2, [5, 7])
	return model


## Alarm shroom: a tall thin stem topped with an upturned trumpet of a cap, glowing at the rim.
static func _alarm(variant: int) -> Dictionary:
	var rng := _roster_rng("alarm", variant)
	var stem_top := 17 + rng.randi_range(-1, 1)
	var model := _roster_sculpt(Vector3i(9, 26, 9), func(x: int, y: int, z: int) -> int:
		var dx := x - 4.0
		var dz := z - 4.0
		var flat := sqrt(dx * dx + dz * dz)
		if y >= stem_top:
			var t := float(y - stem_top) / float(25 - stem_top)
			var r := 1.2 + t * t * 3.2
			if flat <= r:
				if flat >= r - 1.3:
					return _ROSTER_M.SHROOM_SPOT if y == 25 else _ROSTER_M.SHROOM_CAP
				if y <= stem_top + 1:
					return _ROSTER_M.SHROOM_GILL
				return _ROSTER_M.SHROOM_SPOT if y == stem_top + 2 else _ROSTER_M.AIR
			return _ROSTER_M.AIR
		if flat <= (1.6 if y == 0 else 1.1):
			return _ROSTER_M.SHROOM_STEM
		return _ROSTER_M.AIR)
	_roster_eyes(model, stem_top - 4, [3, 5])
	return model


## Giant: a wide stem under a broad flat cap, with two antennae strands rising from the cap and
## dangling outward, glowing at the tips. Giant.ANTENNA_FROM: everything in the top 40% of the
## model is antennae (the crit zone, and what breaks off).
static func _giant(variant: int) -> Dictionary:
	var rng := _roster_rng("giant", variant)
	var spread := 5 + rng.randi_range(0, 1)
	var model := _roster_sculpt(Vector3i(26, 40, 26), func(x: int, y: int, z: int) -> int:
		var dx := x - 12.5
		var dz := z - 12.5
		var flat := sqrt(dx * dx + dz * dz)
		var dy := y - 18.5
		if dy >= 0.0 and (dx * dx + dz * dz) / (12.5 * 12.5) + dy * dy / 25.0 <= 1.0:
			return _ROSTER_M.SHROOM_GILL if y == 19 and flat > 7.0 and flat < 11.5 else _ROSTER_M.SHROOM_CAP
		if y < 19 and flat <= (8.0 if y < 2 else 6.5 - y * 0.05):
			return _ROSTER_M.SHROOM_STEM
		return _ROSTER_M.AIR)
	_roster_speckle(model, _ROSTER_M.SHROOM_CAP, _ROSTER_M.SHROOM_SPOT, 0.06, rng, 20)
	var size: Vector3i = model.size
	var voxels: PackedByteArray = model.voxels
	for side: int in [-1, 1]:
		var x0: int = 12 + side * spread if side > 0 else 12 - spread
		var cells: Array[Vector3i] = []
		for y in range(23, 37): # Up out of the cap...
			cells.append(Vector3i(x0, y, 12))
		for out in range(0, 5): # ...across at the top...
			for y in [37, 38]:
				cells.append(Vector3i(x0 + side * out, y, 12))
		for y in range(33, 37): # ...and hanging down outside.
			cells.append(Vector3i(x0 + side * 4, y, 12))
		for cell in cells:
			for t in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1)]:
				var p: Vector3i = cell + t
				voxels[p.x + p.y * size.x + p.z * size.x * size.y] = _ROSTER_M.SHROOM_GILL
		for y in [31, 32]: # The glowing tip.
			for t in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1)]:
				var p: Vector3i = Vector3i(x0 + side * 4, y, 12) + t
				voxels[p.x + p.y * size.x + p.z * size.x * size.y] = _ROSTER_M.SHROOM_EYE
	model.voxels = voxels
	for y in [12, 13]:
		_roster_eyes(model, y, [9, 10, 15, 16])
	return model


## Ranged shooter: a squat body under a low cap, with a wide open mouth on the front glowing green
## at the back.
static func _ranged(variant: int) -> Dictionary:
	var rng := _roster_rng("ranged", variant)
	var girth := rng.randf_range(-0.3, 0.3)
	var model := _roster_sculpt(Vector3i(13, 11, 13), func(x: int, y: int, z: int) -> int:
		var dx := x - 6.0
		var dz := z - 6.0
		var cap_dy := y - 6.5
		if cap_dy >= 0.0 and (dx * dx + dz * dz) / (6.4 * 6.4) + cap_dy * cap_dy / 9.0 <= 1.0:
			return _ROSTER_M.SHROOM_CAP
		var rx := 5.5 + girth
		var body_dy := y - 3.5
		if y <= 7 and (dx * dx + dz * dz) / (rx * rx) + body_dy * body_dy / 16.0 <= 1.0:
			if z <= 4 and y >= 2 and y <= 5 and absf(dx) <= 3.0:
				return _ROSTER_M.AIR # The mouth.
			if z == 5 and y >= 2 and y <= 5 and absf(dx) <= 3.0:
				return _ROSTER_M.LIQUID_GREEN
			return _ROSTER_M.SHROOM_STEM
		return _ROSTER_M.AIR)
	_roster_speckle(model, _ROSTER_M.SHROOM_CAP, _ROSTER_M.SHROOM_SPOT, 0.12, rng, 8)
	_roster_eyes(model, 6, [4, 8])
	return model


static func _roster_rng(kind: String, variant: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + variant * 7919
	return rng


## A model of size filled from shape(x, y, z) -> material id.
static func _roster_sculpt(size: Vector3i, shape: Callable) -> Dictionary:
	var voxels := PackedByteArray()
	voxels.resize(size.x * size.y * size.z)
	for z in size.z:
		for y in size.y:
			for x in size.x:
				voxels[x + y * size.x + z * size.x * size.y] = shape.call(x, y, z)
	return {size = size, voxels = voxels}


## Swaps exposed voxels of material from (at or above min_y) for to, each with a chance.
static func _roster_speckle(model: Dictionary, from: int, to: int, chance: float, rng: RandomNumberGenerator, min_y := 0) -> void:
	var size: Vector3i = model.size
	var voxels: PackedByteArray = model.voxels
	for z in size.z:
		for y in range(min_y, size.y):
			for x in size.x:
				var i := x + y * size.x + z * size.x * size.y
				if voxels[i] == from and ShroomModels._exposed(voxels, size, x, y, z) and rng.randf() < chance:
					voxels[i] = to
	model.voxels = voxels


## Glowing eyes: the front-most (-Z) solid voxel of each column x at height y.
static func _roster_eyes(model: Dictionary, y: int, columns: Array) -> void:
	var size: Vector3i = model.size
	var voxels: PackedByteArray = model.voxels
	for x: int in columns:
		for z in size.z:
			var i := x + y * size.x + z * size.x * size.y
			if voxels[i] != _ROSTER_M.AIR:
				voxels[i] = _ROSTER_M.SHROOM_EYE
				break
	model.voxels = voxels
