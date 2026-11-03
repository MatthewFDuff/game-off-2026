class_name EnemyModels
## Enemy bodies: MagicaVoxel files in assets/vox/enemies/, one or more per kind
## (`<kind>_<variant>.vox`, or a single `<kind>.vox`). The files are the source of truth; the
## generators here only write the placeholders (scripts/tools/export_vox.gd) and stand in when a
## kind has no file yet. Models face -Z and stand on the bottom center of their box.

const DIR := "res://assets/vox/enemies/"
## Placeholder variants written per kind.
const VARIANTS := {basic = ShroomModels.VARIANTS}

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
	push_warning("no placeholder model for enemy kind '%s'" % kind)
	return ShroomModels.build(ShroomModels.MAX_STAGE, variant, true)
