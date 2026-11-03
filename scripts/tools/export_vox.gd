extends SceneTree
## Writes the placeholder MagicaVoxel models into assets/vox/. Files that already exist are left
## alone (they may have been edited by hand) unless --force is given.
##   godot --headless --path . --script res://scripts/tools/export_vox.gd [-- --force]
##
##   props/       furniture, from PropCatalog
##   shrooms/     growth stages 0-4 x 4 variants, plus the grown hunters with eyes
##   characters/  player body and head
##   pieces/      the old build-mode scrap pieces
##   _palette.vox one cube per game material, to see and pick from the palette
## PALETTE.md lists which palette index is which material. Also writes placeholder pattern images
## for pattern materials into assets/patterns/ (same rule: existing files are kept).

const M := preload("res://scripts/voxel/voxel_materials.gd")
const ROOT := "res://assets/vox/"

var _force := false
var _written := 0
var _kept := 0


func _initialize() -> void:
	_force = "--force" in OS.get_cmdline_user_args()
	for dir in ["props", "shrooms", "characters", "pieces"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT + dir))

	for entry in PropCatalog.entries():
		_save("props/%s.vox" % entry.name, PropCatalog.generate(entry))
	for stage in ShroomModels.MAX_STAGE + 1:
		for variant in ShroomModels.VARIANTS:
			_save("shrooms/stage%d_%d.vox" % [stage, variant], ShroomModels.build(stage, variant, false))
	for variant in ShroomModels.VARIANTS:
		_save("shrooms/stage%d_%d_eyes.vox" % [ShroomModels.MAX_STAGE, variant], ShroomModels.build(ShroomModels.MAX_STAGE, variant, true))
	_save("characters/player_body.vox", _player_body())
	_save("characters/player_head.vox", _player_head())
	for piece in BuildPieces.PIECES:
		_save("pieces/%s.vox" % piece.name.to_snake_case().replace(" ", "_"), BuildPieces.oriented(piece, Vector3.BACK, false))
	_save("_palette.vox", _palette_swatch())
	_write_palette_doc()
	_write_patterns()
	print("vox export: wrote %d, kept %d existing%s" % [_written, _kept, "" if _force else " (use --force to overwrite)"])
	quit()


func _save(relative: String, model: Dictionary) -> void:
	var path := ROOT + relative
	if FileAccess.file_exists(path) and not _force:
		_kept += 1
		return
	var error := VoxFile.save_model(path, model)
	if error != OK:
		push_error("couldn't write %s: %s" % [path, error_string(error)])
		return
	_written += 1


## Placeholder figure, feet at the bottom center of the model, facing -Z.
func _player_body() -> Dictionary:
	var size := Vector3i(6, 15, 4)
	var voxels := PackedByteArray()
	voxels.resize(size.x * size.y * size.z)
	for z in size.z:
		for y in size.y:
			for x in size.x:
				var id := M.CLOTH if y < 7 else M.WALL_PAINT
				if y < 7 and x in [2, 3]:
					id = M.AIR # Gap between the legs.
				voxels[x + y * size.x + z * size.x * size.y] = id
	return {size = size, voxels = voxels}


## Placeholder head, centered on the eyes' pivot, eyes on the front (z = 0, facing -Z).
func _player_head() -> Dictionary:
	var voxels := PackedByteArray()
	voxels.resize(64)
	voxels.fill(M.PLASTIC)
	for x in [0, 3]:
		voxels[x + 2 * 4] = M.GLASS
	return {size = Vector3i(4, 4, 4), voxels = voxels}


## A 2x2x2 cube of every material in a row, in palette order, for reference in MagicaVoxel.
func _palette_swatch() -> Dictionary:
	var ids := M.DEFS.keys()
	ids.sort()
	var size := Vector3i(ids.size() * 3, 2, 2)
	var voxels := PackedByteArray()
	voxels.resize(size.x * size.y * size.z)
	for i in ids.size():
		for z in 2:
			for y in 2:
				for x in 2:
					voxels[i * 3 + x + y * size.x + z * size.x * size.y] = ids[i]
	return {size = size, voxels = voxels}


## Placeholder pattern images, 1 pixel = 1 voxel.
func _write_patterns() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(M.PATTERN_DIR))
	var rng := RandomNumberGenerator.new()
	rng.seed = 40
	var shade := func(c: Color, amount: float) -> Color: return c.lightened(amount) if amount > 0.0 else c.darkened(-amount)
	var make := {
		"block_wall": func() -> Image:
			# Two courses of 7x2 blocks, offset by half a block, with 1-voxel mortar.
			var image := Image.create(8, 6, false, Image.FORMAT_RGBA8)
			var mortar := Color(0.74, 0.71, 0.64)
			for course in 2:
				var tint: Color = shade.call(Color(0.62, 0.34, 0.26), rng.randf_range(-0.12, 0.1))
				for y in range(course * 3, course * 3 + 3):
					for x in 8:
						var seam := (x == 0) if course == 0 else (x == 4)
						image.set_pixel(x, y, mortar if y == course * 3 or seam else shade.call(tint, rng.randf_range(-0.04, 0.04)))
			return image,
		"large_tile": func() -> Image:
			var image := Image.create(10, 10, false, Image.FORMAT_RGBA8)
			for y in 10:
				for x in 10:
					var grout := x == 0 or y == 0
					image.set_pixel(x, y, Color(0.55, 0.57, 0.56) if grout else shade.call(Color(0.86, 0.87, 0.85), rng.randf_range(-0.03, 0.02)))
			return image,
		"concrete_panel": func() -> Image:
			# 2 m x 3 m panels with seams and four bolts.
			var image := Image.create(20, 30, false, Image.FORMAT_RGBA8)
			for y in 30:
				for x in 20:
					var color: Color = shade.call(Color(0.58, 0.59, 0.57), rng.randf_range(-0.05, 0.04))
					if x == 0 or y == 0:
						color = Color(0.38, 0.39, 0.38)
					elif (x == 3 or x == 16) and (y == 3 or y == 26):
						color = Color(0.32, 0.32, 0.33)
					image.set_pixel(x, y, color)
			return image,
		"diamond_plate": func() -> Image:
			var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
			for y in 4:
				for x in 4:
					var raised := (x == 1 and y == 0) or (x == 3 and y == 2)
					image.set_pixel(x, y, Color(0.74, 0.76, 0.79) if raised else Color(0.52, 0.54, 0.57))
			return image,
		"hazard_stripes": func() -> Image:
			var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
			for y in 8:
				for x in 8:
					image.set_pixel(x, y, Color(0.92, 0.74, 0.1) if (x + y) % 8 < 4 else Color(0.12, 0.12, 0.12))
			return image,
	}
	for pattern: String in make:
		var path: String = M.PATTERN_DIR + pattern + ".png"
		if FileAccess.file_exists(path) and not _force:
			_kept += 1
			continue
		make[pattern].call().save_png(path)
		_written += 1


func _write_palette_doc() -> void:
	var path := ROOT + "PALETTE.md"
	if FileAccess.file_exists(path) and not _force:
		return
	var ids := M.DEFS.keys()
	ids.sort()
	var lines: Array[String] = [
		"# Palette",
		"",
		"Generated by `scripts/tools/export_vox.gd`. In MagicaVoxel, a voxel's palette index *is* its game material:",
		"paint with these slots and the game gives the voxel that material's hardness, glow and color.",
		"Slots not listed here are dark purple and get mapped to the closest material on import, with a warning.",
		"Recoloring a listed slot also counts as unlisted. Change a material's color in `scripts/voxel/voxel_materials.gd` instead.",
		"",
		"Pattern materials (marked below) show an image from `assets/patterns/` in the game, 1 pixel per voxel, tiled",
		"across the world. MagicaVoxel shows them as their plain color. Edit the PNGs (up to 32x32) to change them.",
		"",
		"| Index | Material | Hardness | Glows | Pattern |",
		"|---|---|---|---|---|",
	]
	for id: int in ids:
		var def: Dictionary = M.DEFS[id]
		lines.append("| %d | %s | %s | %s | %s |" % [id, def.name, "unbreakable" if def.hardness == 255 else str(def.hardness),
				"yes" if def.get("emission", 0.0) >= 0.5 else "", def.get("pattern", "")])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
