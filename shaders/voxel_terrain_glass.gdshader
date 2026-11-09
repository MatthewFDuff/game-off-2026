shader_type spatial;
// Terrain shader for the see-through faces of VoxelWorld chunk and model meshes (pane glass: their
// second surface, VoxelWorld.glass_material). Alpha blended over the opaque terrain behind it, which
// keeps its early depth tests; writes no depth. It carries the editor cutaway too: on a blended
// surface that writes no depth, discard costs nothing, so there is no play / editor pair to swap.
// VoxelWorld copies the terrain material's uniforms onto it. The body is in
// voxel_terrain.gdshaderinc.
render_mode blend_mix, depth_draw_opaque, cull_back;
#define VOXEL_TERRAIN_GLASS
#define VOXEL_TERRAIN_CUTAWAY
#include "res://shaders/voxel_terrain.gdshaderinc"
