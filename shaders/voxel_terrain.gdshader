shader_type spatial;
// Terrain shader for VoxelWorld chunk meshes, editor variant: with the level editor's cutaway and
// walls-down (discard). Scenes use this one; VoxelWorld swaps to voxel_terrain_play.gdshader while
// no cutaway is set. The body is in voxel_terrain.gdshaderinc.
#define VOXEL_TERRAIN_CUTAWAY
#include "res://shaders/voxel_terrain.gdshaderinc"
