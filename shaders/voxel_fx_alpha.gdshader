shader_type spatial;
// Translucent effect cubes (VoxelFx.alpha_material): the same grid-snapped, face-shaded cubes as
// voxel_fx.gdshader, but alpha-blended for real (no dither). Drawn back faces culled and without
// depth writes, in the transparent pass; emitters using it sort their cubes by view depth. Keep
// the cube count low.
render_mode unshaded, blend_mix, cull_back, depth_draw_never, skip_vertex_transform, shadows_disabled, fog_disabled;

#include "res://shaders/voxel_fx_snap.gdshaderinc"

void fragment() {
	vec4 color = COLOR * tint;
	ALBEDO = color.rgb * face_light(face);
	ALPHA = color.a;
}
