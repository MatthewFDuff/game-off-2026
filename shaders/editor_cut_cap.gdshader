shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// Level editor cutaway cap (EditorCamera): a plane at the cut height drawn wherever the voxel layer
// just under the cut is solid, in that voxel's palette color, darkened and hatched so a cross
// section reads as cut. Air is discarded, so rooms under the cut show through.

uniform sampler2D ids : filter_nearest; // R8: material id / 255
uniform sampler2D palette : source_color, filter_nearest;
uniform vec3 origin;
uniform float voxel_size = 0.1;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ivec2 cell = ivec2(floor((world_position.xz - origin.xz) / voxel_size));
	ivec2 size = textureSize(ids, 0);
	if (any(lessThan(cell, ivec2(0))) || any(greaterThanEqual(cell, size))) {
		discard;
	}
	int id = int(round(texelFetch(ids, cell, 0).r * 255.0));
	if (id == 0) {
		discard;
	}
	vec3 color = texelFetch(palette, ivec2(id, 0), 0).rgb * 0.6;
	// Faint diagonal hatching, faded out with distance before it can shimmer.
	float hatch = step(0.8, fract((world_position.x + world_position.z) / (voxel_size * 6.0)));
	float fade = 1.0 - smoothstep(8.0, 20.0, length(world_position - CAMERA_POSITION_WORLD));
	ALBEDO = mix(color, color * 0.8, hatch * fade);
}
