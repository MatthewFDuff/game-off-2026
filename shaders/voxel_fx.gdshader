shader_type spatial;
// Effect cubes (VoxelFx): particles, shots, stains and splats drawn as flat, opaque voxels (the
// shared vertex snap is in voxel_fx_snap.gdshaderinc).
// Alpha below 1 is a screen-door dither (an ordered 4x4 pattern in `dither_px` screen pixels), kept
// for the few effects that still fade that way; cloud and fire cubes are fully opaque, and
// translucent cubes use voxel_fx_alpha.gdshader (true blending) instead. Fog is off: the lab's
// height fog otherwise dims these unshaded colors to mud a few meters away.
render_mode unshaded, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

#include "res://shaders/voxel_fx_snap.gdshaderinc"

uniform float dither_px = 2.0;

void fragment() {
	vec4 color = COLOR * tint;
	ivec2 cell = ivec2(floor(FRAGCOORD.xy / dither_px)) % 4;
	int index = cell.y * 4 + cell.x;
	const float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	if (color.a < (bayer[index] + 0.5) / 16.0) {
		discard;
	}
	ALBEDO = color.rgb * face_light(face);
}
