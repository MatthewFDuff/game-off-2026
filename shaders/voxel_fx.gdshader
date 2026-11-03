shader_type spatial;
// Effect cubes (VoxelFx): particles, shots, splats and cloud volumes drawn as flat voxels.
// snap: each instance (a particle, a shot) becomes an axis-aligned cube whose center sits on a
// `grid` world grid and whose edge is a multiple of `size_step`, so effects move and shrink in voxel
// steps instead of sliding and scaling smoothly. Without snap the mesh is drawn as built (cloud
// volumes, splats: already blocky meshes).
// Alpha below 1 is a screen-door dither (an ordered 4x4 pattern in `dither_px` screen pixels): no
// soft blending, no sorting, and fades read as pixels dropping out.
// Faces are shaded by direction (top bright, sides darker, bottom darkest), so cubes read as cubes
// under the flat, unshaded color.
render_mode unshaded, cull_disabled, skip_vertex_transform, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform bool snap = true;
// Edge of the mesh (meters) when unscaled; snap needs it to size the cube.
uniform float cube_size = 0.1;
uniform float grid = 0.05;
uniform float size_step = 0.05;
uniform float dither_px = 2.0;

varying vec3 face;

void vertex() {
	vec3 world;
	if (snap) {
		vec3 origin = MODEL_MATRIX[3].xyz;
		float edge = cube_size * length(MODEL_MATRIX[0].xyz);
		float snapped = floor(edge / size_step + 0.5) * size_step;
		vec3 center = (floor(origin / grid) + 0.5) * grid;
		world = center + VERTEX / cube_size * snapped;
		face = NORMAL;
	} else {
		world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		face = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(face, 0.0)).xyz);
}

void fragment() {
	vec4 color = COLOR * tint;
	ivec2 cell = ivec2(floor(FRAGCOORD.xy / dither_px)) % 4;
	int index = cell.y * 4 + cell.x;
	const float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	if (color.a < (bayer[index] + 0.5) / 16.0) {
		discard;
	}
	float light = face.y > 0.5 ? 1.0 : (face.y < -0.5 ? 0.6 : (abs(face.x) > 0.5 ? 0.85 : 0.75));
	ALBEDO = color.rgb * light;
}
