// Shared vertex step of the effect-cube shaders (voxel_fx, voxel_fx_alpha).
// snap: each instance (a particle, a shot) becomes an axis-aligned cube whose center sits on a
// `grid` world grid and whose edge is a multiple of `size_step`, so effects move and shrink in voxel
// steps instead of sliding and scaling smoothly. Without snap the mesh is drawn as built (stains,
// splats: already blocky meshes).

uniform vec4 tint : source_color = vec4(1.0);
uniform bool snap = true;
// Edge of the mesh (meters) when unscaled; snap needs it to size the cube.
uniform float cube_size = 0.1;
uniform float grid = 0.05;
uniform float size_step = 0.05;

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

// Faces are shaded by direction (top bright, sides darker, bottom darkest), so cubes read as cubes
// under the flat, unshaded color.
float face_light(vec3 n) {
	return n.y > 0.5 ? 1.0 : (n.y < -0.5 ? 0.6 : (abs(n.x) > 0.5 ? 0.85 : 0.75));
}
