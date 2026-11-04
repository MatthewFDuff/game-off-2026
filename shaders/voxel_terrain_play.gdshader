shader_type spatial;
// Terrain shader for VoxelWorld chunk meshes, play variant: no discard, so early depth tests stay on.
// VoxelWorld uses it whenever the level editor's cutaway is off. The body is in
// voxel_terrain.gdshaderinc.
#include "res://shaders/voxel_terrain.gdshaderinc"
