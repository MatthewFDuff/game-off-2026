class_name VoxelMaterials
## Material table for the voxel world. Ids are stored in one byte per voxel; 0 is air and 255 is
## reserved by VoxelWorld for the world boundary.
##
## Pattern materials: a material with `pattern` takes each voxel's color from a small image,
## res://assets/patterns/<pattern>.png (up to 32x32, 1 pixel = 1 voxel), tiled across the world.
## Painting a wall with one gives brickwork without coloring voxels by hand, and the pattern
## carries on inside when it's shot. Its `color` is the plain stand-in (MagicaVoxel, debris).

const AIR := 0
# Ground
const ROCK := 1
const DIRT := 2
const CLAY := 8
const SAND := 9
const GRAVEL := 10
const DEEP_STONE := 11
const BEDROCK := 254
# Building
const CONCRETE := 3
const METAL := 4
const PLANK := 5
const HATCH := 7
const TILE_LIGHT := 12
const TILE_DARK := 13
const WALL_PAINT := 14
const WALL_LOWER := 15
const WARNING := 28
const LADDER := 27
const PIPE := 31
# Furnishings
const WOOD := 16
const STEEL := 17
const PLASTIC := 18
const GLASS := 19
const CLOTH := 20
const RUBBER := 37
const WATER := 25
const LIQUID_GREEN := 22
const LIQUID_BLUE := 23
const LIQUID_PINK := 24
const SUBSTRATE := 26
# Lights
const GLOW := 6
const LAMP := 21
const SCREEN := 29
const EMERGENCY := 30
# Shrooms
const SHROOM_CAP := 32
const SHROOM_STEM := 33
const SHROOM_SPOT := 34
const SHROOM_GILL := 35
const SHROOM_EYE := 36
# Fire (Fire): voxels on fire, and what's left when they go out
const EMBER := 38
const EMBER_DEEP := 45
const CHAR := 39
# Patterned
const BLOCK_WALL := 40
const LARGE_TILE := 41
const CONCRETE_PANEL := 42
const DIAMOND_PLATE := 43
const HAZARD_STRIPES := 44
# Glass that shatters as a pane (Glass). Ids 46 to 49 are claimed by glass (prop-build-plan B).
const GLASS_TEMPERED := 46
const GLASS_CRACKED := 47
const GLASS_SHARDS := 48
# Mycelium networks (Mycelium). Ids 50 to 59 are claimed by mycelium (prop-build-plan C).
const MYCELIUM := 50
const MYCELIUM_GLOW := 51
const ROOT := 52
const MYCELIUM_DEAD := 53
# Interactables (prop-build-plan E). Id 60 is claimed by them.
const RED_PAINT := 60
# Office greenery: a matte leaf green that doesn't glow (the fake plant; the Sample liquids glow).
const LEAF := 61

const PATTERN_DIR := "res://assets/patterns/"
## Largest pattern per side (the shader's pattern layers are this big).
const PATTERN_MAX := 32

## Emission groups: lamps on facility power go dark at night; emergency lights only glow then.
const POWERED := 1
const EMERGENCY_ONLY := 2
## Mycelium veins: emission swings in a slow travelling wave, harder with the shader's pulse_amount
## (Mycelium.pulse). Palette row 2, blue.
const PULSING := 3

## Hardness 255 can never be carved. Shrooms dig through hardness 2 and below.
##
## Fire (Fire): `burn` is the seconds a voxel of it burns, `catch` how readily it catches from a
## burning neighbour (chance per second, before Fire.SPREAD's direction weights), `ash` the chance it
## leaves CHAR instead of air. `reacts` names the Cloud a sample boils into when fire touches it.
const DEFS := {
	ROCK: {name = "Rock", color = Color(0.42, 0.40, 0.38), hardness = 4},
	DIRT: {name = "Dirt", color = Color(0.36, 0.26, 0.18), hardness = 2},
	CLAY: {name = "Clay", color = Color(0.60, 0.40, 0.30), hardness = 3},
	SAND: {name = "Sand", color = Color(0.76, 0.68, 0.48), hardness = 1},
	GRAVEL: {name = "Gravel", color = Color(0.50, 0.49, 0.47), hardness = 2},
	DEEP_STONE: {name = "Deep stone", color = Color(0.27, 0.27, 0.30), hardness = 6},
	BEDROCK: {name = "Bedrock", color = Color(0.16, 0.15, 0.15), hardness = 255},

	CONCRETE: {name = "Concrete", color = Color(0.58, 0.58, 0.56), hardness = 5},
	METAL: {name = "Sheet metal", color = Color(0.45, 0.50, 0.55), hardness = 8},
	PLANK: {name = "Plank", color = Color(0.60, 0.44, 0.26), hardness = 1, burn = 5.0, catch = 0.6, ash = 0.3},
	HATCH: {name = "Hatch", color = Color(0.32, 0.33, 0.30), hardness = 255},
	TILE_LIGHT: {name = "Tile", color = Color(0.82, 0.83, 0.80), hardness = 3},
	TILE_DARK: {name = "Tile", color = Color(0.52, 0.56, 0.56), hardness = 3},
	WALL_PAINT: {name = "Painted wall", color = Color(0.66, 0.70, 0.62), hardness = 5},
	WALL_LOWER: {name = "Painted wall", color = Color(0.33, 0.43, 0.40), hardness = 5},
	WARNING: {name = "Warning paint", color = Color(0.90, 0.72, 0.10), hardness = 5},
	LADDER: {name = "Ladder", color = Color(0.85, 0.68, 0.15), hardness = 6},
	PIPE: {name = "Pipe", color = Color(0.68, 0.42, 0.24), hardness = 3},

	WOOD: {name = "Wood", color = Color(0.50, 0.33, 0.19), hardness = 1, burn = 7.0, catch = 0.5, ash = 0.35},
	STEEL: {name = "Steel", color = Color(0.56, 0.58, 0.61), hardness = 3},
	PLASTIC: {name = "Plastic", color = Color(0.88, 0.88, 0.85), hardness = 1, burn = 3.0, catch = 0.3, ash = 0.15},
	GLASS: {name = "Glass", color = Color(0.68, 0.84, 0.88), hardness = 1},
	CLOTH: {name = "Cloth", color = Color(0.22, 0.30, 0.48), hardness = 1, burn = 2.0, catch = 1.5},
	RUBBER: {name = "Rubber", color = Color(0.11, 0.11, 0.12), hardness = 1, burn = 6.0, catch = 0.25, ash = 0.25},
	WATER: {name = "Water", color = Color(0.33, 0.55, 0.85), hardness = 1, emission = 0.15},
	LIQUID_GREEN: {name = "Sample", color = Color(0.30, 0.90, 0.40), hardness = 1, emission = 0.6, reacts = "poison"},
	LIQUID_BLUE: {name = "Sample", color = Color(0.30, 0.60, 1.00), hardness = 1, emission = 0.6, reacts = "freeze"},
	LIQUID_PINK: {name = "Sample", color = Color(0.95, 0.40, 0.70), hardness = 1, emission = 0.6, reacts = "rage"},
	SUBSTRATE: {name = "Substrate", color = Color(0.24, 0.16, 0.11), hardness = 2, burn = 8.0, catch = 0.2, ash = 0.5},

	GLOW: {name = "Glow", color = Color(0.35, 0.95, 0.75), hardness = 1, emission = 1.0},
	LAMP: {name = "Lamp", color = Color(1.00, 0.94, 0.78), hardness = 1, emission = 1.0, group = POWERED},
	SCREEN: {name = "Screen", color = Color(0.30, 0.65, 0.95), hardness = 1, emission = 0.8, group = POWERED},
	EMERGENCY: {name = "Emergency light", color = Color(1.00, 0.15, 0.10), hardness = 1, emission = 1.0, group = EMERGENCY_ONLY},

	SHROOM_CAP: {name = "Cap", color = Color(0.45, 0.22, 0.55), hardness = 1, emission = 0.3, burn = 1.5, catch = 1.2},
	SHROOM_STEM: {name = "Stem", color = Color(0.85, 0.82, 0.74), hardness = 1, emission = 0.05, burn = 1.5, catch = 1.2},
	SHROOM_SPOT: {name = "Spot", color = Color(0.35, 1.00, 0.80), hardness = 1, emission = 1.0, burn = 1.5, catch = 1.2},
	SHROOM_GILL: {name = "Gills", color = Color(0.30, 0.14, 0.34), hardness = 1, emission = 0.25, burn = 1.5, catch = 1.2},
	SHROOM_EYE: {name = "Eye", color = Color(0.90, 1.00, 0.60), hardness = 1, emission = 1.5, burn = 1.5, catch = 1.2},

	EMBER: {name = "Burning", color = Color(1.00, 0.52, 0.12), hardness = 1, emission = 1.4},
	EMBER_DEEP: {name = "Burning", color = Color(0.90, 0.22, 0.05), hardness = 1, emission = 1.0},
	CHAR: {name = "Char", color = Color(0.09, 0.08, 0.07), hardness = 1},

	BLOCK_WALL: {name = "Block wall", color = Color(0.62, 0.36, 0.28), hardness = 5, pattern = "block_wall"},
	LARGE_TILE: {name = "Large tile", color = Color(0.80, 0.82, 0.80), hardness = 3, pattern = "large_tile"},
	CONCRETE_PANEL: {name = "Concrete panel", color = Color(0.56, 0.57, 0.55), hardness = 5, pattern = "concrete_panel"},
	DIAMOND_PLATE: {name = "Diamond plate", color = Color(0.55, 0.57, 0.60), hardness = 6, pattern = "diamond_plate"},
	HAZARD_STRIPES: {name = "Hazard stripes", color = Color(0.55, 0.45, 0.10), hardness = 5, pattern = "hazard_stripes"},

	# Glass (Glass): tempered takes three hits, cracking on the first; shards are what a pane leaves.
	GLASS_TEMPERED: {name = "Tempered glass", color = Color(0.62, 0.80, 0.92), hardness = 2},
	GLASS_CRACKED: {name = "Cracked glass", color = Color(0.70, 0.82, 0.90), hardness = 2, pattern = "glass_cracked"},
	GLASS_SHARDS: {name = "Glass shards", color = Color(0.80, 0.90, 0.93), hardness = 1},

	# Mycelium (Mycelium): burns like the shrooms; dead mycelium is what wither leaves.
	MYCELIUM: {name = "Mycelium", color = Color(0.72, 0.74, 0.66), hardness = 1, burn = 1.5, catch = 1.2},
	MYCELIUM_GLOW: {name = "Mycelium vein", color = Color(0.40, 0.95, 0.85), hardness = 1, emission = 0.9, group = PULSING, burn = 1.5, catch = 1.2},
	ROOT: {name = "Root", color = Color(0.22, 0.17, 0.14), hardness = 1, burn = 3.0, catch = 0.8, ash = 0.4},
	MYCELIUM_DEAD: {name = "Dead mycelium", color = Color(0.46, 0.46, 0.44), hardness = 1, burn = 1.0, catch = 1.5},

	# Interactables: plain red paint that doesn't glow (fire extinguishers, alarm pulls; EMERGENCY glows).
	RED_PAINT: {name = "Red paint", color = Color(0.72, 0.10, 0.08), hardness = 3},
	# Plastic foliage: no emission at all, burns like the plastic it is.
	LEAF: {name = "Leaf", color = Color(0.24, 0.52, 0.27), hardness = 1, burn = 3.0, catch = 0.3, ash = 0.15},
}


static func get_color(id: int) -> Color:
	return DEFS[id].color if DEFS.has(id) else Color.MAGENTA


static func get_material_name(id: int) -> String:
	return DEFS[id].name if DEFS.has(id) else "Unknown"


static func build_hardness() -> PackedByteArray:
	var hardness := PackedByteArray()
	hardness.resize(256)
	hardness.fill(1)
	for id in DEFS:
		hardness[id] = DEFS[id].hardness
	hardness[255] = 255
	return hardness


## Materials that use a pattern, in a fixed order: their index + 1 is their pattern layer.
static func patterned() -> Array[int]:
	var ids: Array[int] = []
	for id: int in DEFS:
		if DEFS[id].has("pattern"):
			ids.append(id)
	ids.sort()
	return ids


## A pattern's image, read straight from its file (so live reload sees edits), or null.
static func load_pattern(pattern: String) -> Image:
	var path := PATTERN_DIR + pattern + ".png"
	var image := Image.new()
	if FileAccess.file_exists(path):
		# The file itself when it's there (running from the project), so edits show up live.
		image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	elif ResourceLoader.exists(path):
		# Exported games only ship the imported texture.
		image = (load(path) as Texture2D).get_image()
		if image and image.is_compressed():
			image.decompress()
	if image == null or image.is_empty() or image.get_width() > PATTERN_MAX or image.get_height() > PATTERN_MAX:
		push_warning("pattern %s must be a PNG of at most %dx%d" % [path, PATTERN_MAX, PATTERN_MAX])
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


## 256x3 lookup texture for the terrain shader. Row 0: rgb albedo, alpha emission strength.
## Row 1: r = on facility power, g = emergency light, b = pattern layer + 1 (0 = none) / 255.
## Row 2: pattern width and height / 255, b = 1 for PULSING.
static func build_palette() -> ImageTexture:
	var image := Image.create(256, 3, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 0, 1, 0))
	var patterns := patterned()
	for id in DEFS:
		var def: Dictionary = DEFS[id]
		var c: Color = def.color
		image.set_pixel(id, 0, Color(c.r, c.g, c.b, def.get("emission", 0.0)))
		var group: int = def.get("group", 0)
		var layer := 0
		# Row 2 blue: PULSING (the fill would leave it at 1 for everything).
		image.set_pixel(id, 2, Color8(0, 0, 255 if group == PULSING else 0, 255))
		var pattern := load_pattern(def.pattern) if def.has("pattern") else null
		if pattern:
			layer = patterns.find(id) + 1
			image.set_pixel(id, 2, Color8(pattern.get_width(), pattern.get_height(), 255 if group == PULSING else 0, 255))
		image.set_pixel(id, 1, Color(1.0 if group == POWERED else 0.0, 1.0 if group == EMERGENCY_ONLY else 0.0, layer / 255.0, 1.0))
	image.set_pixel(255, 0, DEFS[BEDROCK].color)
	image.set_pixel(255, 1, Color(0, 0, 0, 1))
	return ImageTexture.create_from_image(image)


## Every pattern as one layer (PATTERN_MAX square, image in the top-left corner), in patterned()
## order. Always at least one layer, so the shader has something bound.
static func build_patterns() -> Texture2DArray:
	var layers: Array[Image] = []
	for id in patterned():
		var layer := Image.create(PATTERN_MAX, PATTERN_MAX, false, Image.FORMAT_RGBA8)
		layer.fill(get_color(id))
		var pattern := load_pattern(DEFS[id].pattern)
		if pattern:
			layer.blit_rect(pattern, Rect2i(Vector2i.ZERO, pattern.get_size()), Vector2i.ZERO)
		layers.append(layer)
	if layers.is_empty():
		layers.append(Image.create(PATTERN_MAX, PATTERN_MAX, false, Image.FORMAT_RGBA8))
	var texture := Texture2DArray.new()
	texture.create_from_images(layers)
	return texture


static func apply_to(world: VoxelWorld) -> void:
	world.material_hardness = build_hardness()
	var shader_material := world.material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("palette", build_palette())
		shader_material.set_shader_parameter("patterns", build_patterns())
		shader_material.set_shader_parameter("voxel_size", world.voxel_size)
