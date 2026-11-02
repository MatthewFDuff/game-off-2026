class_name BuildPieces
## Scrap pieces the player can buy and nail into the facility. Each piece is a small voxel model.
## Sizes are (length, width, thickness) in voxels; when placed, the thickness always faces the
## surface being built against.

const PIECES := [
	{name = "Plank", size = Vector3i(12, 2, 1), material = VoxelMaterials.PLANK, cost = 2},
	{name = "Sheet metal", size = Vector3i(10, 10, 1), material = VoxelMaterials.METAL, cost = 8},
	{name = "Sandbag", size = Vector3i(6, 3, 3), material = VoxelMaterials.DIRT, cost = 4},
	{name = "Concrete block", size = Vector3i(5, 5, 5), material = VoxelMaterials.CONCRETE, cost = 10},
]


## Returns {size: Vector3i, voxels: PackedByteArray} for the piece oriented against a surface with
## the given axis-aligned normal. turned swaps which in-surface axis the piece's length runs along.
static func oriented(piece: Dictionary, normal: Vector3, turned: bool) -> Dictionary:
	var normal_axis := normal.abs().max_axis_index()
	var in_plane := [(normal_axis + 1) % 3, (normal_axis + 2) % 3]
	# Prefer the length running horizontally on walls, so planks go across holes by default.
	if normal_axis != Vector3.AXIS_Y and in_plane[0] == Vector3.AXIS_Y:
		in_plane.reverse()
	if turned:
		in_plane.reverse()

	var dims: Vector3i = piece.size
	var size := Vector3i.ZERO
	size[in_plane[0]] = dims.x
	size[in_plane[1]] = dims.y
	size[normal_axis] = dims.z

	# Box pieces are uniform, so orienting is just a resize. Shaped pieces (e.g. from .vox files)
	# will need their voxels remapped here too.
	var voxels := PackedByteArray()
	voxels.resize(size.x * size.y * size.z)
	voxels.fill(piece.material)
	return {size = size, voxels = voxels}
