class_name VoxelMaterials
## Material table for the voxel world. Ids are stored in one byte per voxel; 0 is air and 255 is
## reserved by VoxelWorld for the world boundary.

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

## Emission groups: lamps on facility power go dark at night; emergency lights only glow then.
const POWERED := 1
const EMERGENCY_ONLY := 2

## Hardness 255 can never be carved. Shrooms dig through hardness 2 and below.
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
	PLANK: {name = "Plank", color = Color(0.60, 0.44, 0.26), hardness = 1},
	HATCH: {name = "Hatch", color = Color(0.32, 0.33, 0.30), hardness = 255},
	TILE_LIGHT: {name = "Tile", color = Color(0.82, 0.83, 0.80), hardness = 3},
	TILE_DARK: {name = "Tile", color = Color(0.52, 0.56, 0.56), hardness = 3},
	WALL_PAINT: {name = "Painted wall", color = Color(0.66, 0.70, 0.62), hardness = 5},
	WALL_LOWER: {name = "Painted wall", color = Color(0.33, 0.43, 0.40), hardness = 5},
	WARNING: {name = "Warning paint", color = Color(0.90, 0.72, 0.10), hardness = 5},
	LADDER: {name = "Ladder", color = Color(0.85, 0.68, 0.15), hardness = 6},
	PIPE: {name = "Pipe", color = Color(0.68, 0.42, 0.24), hardness = 3},

	WOOD: {name = "Wood", color = Color(0.50, 0.33, 0.19), hardness = 1},
	STEEL: {name = "Steel", color = Color(0.56, 0.58, 0.61), hardness = 3},
	PLASTIC: {name = "Plastic", color = Color(0.88, 0.88, 0.85), hardness = 1},
	GLASS: {name = "Glass", color = Color(0.68, 0.84, 0.88), hardness = 1},
	CLOTH: {name = "Cloth", color = Color(0.22, 0.30, 0.48), hardness = 1},
	RUBBER: {name = "Rubber", color = Color(0.11, 0.11, 0.12), hardness = 1},
	WATER: {name = "Water", color = Color(0.33, 0.55, 0.85), hardness = 1, emission = 0.15},
	LIQUID_GREEN: {name = "Sample", color = Color(0.30, 0.90, 0.40), hardness = 1, emission = 0.6},
	LIQUID_BLUE: {name = "Sample", color = Color(0.30, 0.60, 1.00), hardness = 1, emission = 0.6},
	LIQUID_PINK: {name = "Sample", color = Color(0.95, 0.40, 0.70), hardness = 1, emission = 0.6},
	SUBSTRATE: {name = "Substrate", color = Color(0.24, 0.16, 0.11), hardness = 2},

	GLOW: {name = "Glow", color = Color(0.35, 0.95, 0.75), hardness = 1, emission = 1.0},
	LAMP: {name = "Lamp", color = Color(1.00, 0.94, 0.78), hardness = 1, emission = 1.0, group = POWERED},
	SCREEN: {name = "Screen", color = Color(0.30, 0.65, 0.95), hardness = 1, emission = 0.8, group = POWERED},
	EMERGENCY: {name = "Emergency light", color = Color(1.00, 0.15, 0.10), hardness = 1, emission = 1.0, group = EMERGENCY_ONLY},

	SHROOM_CAP: {name = "Cap", color = Color(0.45, 0.22, 0.55), hardness = 1, emission = 0.3},
	SHROOM_STEM: {name = "Stem", color = Color(0.85, 0.82, 0.74), hardness = 1, emission = 0.05},
	SHROOM_SPOT: {name = "Spot", color = Color(0.35, 1.00, 0.80), hardness = 1, emission = 1.0},
	SHROOM_GILL: {name = "Gills", color = Color(0.30, 0.14, 0.34), hardness = 1, emission = 0.25},
	SHROOM_EYE: {name = "Eye", color = Color(0.90, 1.00, 0.60), hardness = 1, emission = 1.5},
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


## 256x2 lookup texture for the terrain shader. Row 0: rgb albedo, alpha emission strength.
## Row 1: r = on facility power, g = emergency light.
static func build_palette() -> ImageTexture:
	var image := Image.create(256, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 0, 1, 0))
	for id in DEFS:
		var def: Dictionary = DEFS[id]
		var c: Color = def.color
		image.set_pixel(id, 0, Color(c.r, c.g, c.b, def.get("emission", 0.0)))
		var group: int = def.get("group", 0)
		image.set_pixel(id, 1, Color(1.0 if group == POWERED else 0.0, 1.0 if group == EMERGENCY_ONLY else 0.0, 0.0, 1.0))
	image.set_pixel(255, 0, DEFS[BEDROCK].color)
	image.set_pixel(255, 1, Color(0, 0, 0, 1))
	return ImageTexture.create_from_image(image)


static func apply_to(world: VoxelWorld) -> void:
	world.material_hardness = build_hardness()
	var shader_material := world.material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("palette", build_palette())
		shader_material.set_shader_parameter("voxel_size", world.voxel_size)
