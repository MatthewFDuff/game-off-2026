class_name VoxelMaterials
## Material table for the voxel world. Ids are stored in one byte per voxel; 0 is air and 255 is
## reserved by VoxelWorld for the world boundary.

const AIR := 0
const ROCK := 1
const DIRT := 2
const CONCRETE := 3
const METAL := 4
const PLANK := 5
const GLOW := 6
const HATCH := 7
const BEDROCK := 254

## Hardness 255 can never be carved.
const DEFS := {
	ROCK: {name = "Rock", color = Color(0.42, 0.40, 0.38), hardness = 4},
	DIRT: {name = "Dirt", color = Color(0.36, 0.26, 0.18), hardness = 2},
	CONCRETE: {name = "Concrete", color = Color(0.62, 0.62, 0.60), hardness = 5},
	METAL: {name = "Metal", color = Color(0.45, 0.50, 0.55), hardness = 8},
	PLANK: {name = "Plank", color = Color(0.60, 0.44, 0.26), hardness = 1},
	GLOW: {name = "Glow", color = Color(0.35, 0.95, 0.75), hardness = 1, emission = 1.0},
	HATCH: {name = "Hatch", color = Color(0.32, 0.33, 0.30), hardness = 255},
	BEDROCK: {name = "Bedrock", color = Color(0.16, 0.15, 0.15), hardness = 255},
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


## 256x1 lookup texture for the terrain shader: rgb is albedo, alpha is emission strength.
static func build_palette() -> ImageTexture:
	var image := Image.create(256, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 0, 1, 0))
	for id in DEFS:
		var c: Color = DEFS[id].color
		image.set_pixel(id, 0, Color(c.r, c.g, c.b, DEFS[id].get("emission", 0.0)))
	image.set_pixel(255, 0, DEFS[BEDROCK].color)
	return ImageTexture.create_from_image(image)


static func apply_to(world: VoxelWorld) -> void:
	world.material_hardness = build_hardness()
	var shader_material := world.material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("palette", build_palette())
		shader_material.set_shader_parameter("voxel_size", world.voxel_size)
