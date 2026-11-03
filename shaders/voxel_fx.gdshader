shader_type spatial;
// Effect cubes (VoxelFx): particles, shots, stains and splats drawn as flat, opaque voxels (the
// shared vertex snap is in voxel_fx_snap.gdshaderinc). Always opaque, never dithered: translucent
// cubes use voxel_fx_alpha.gdshader (true blending) instead. Fog is off: the lab's height fog
// otherwise dims these unshaded colors to mud a few meters away.
render_mode unshaded, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

#include "res://shaders/voxel_fx_snap.gdshaderinc"

void fragment() {
	ALBEDO = (COLOR * tint).rgb * face_light(face);
}
