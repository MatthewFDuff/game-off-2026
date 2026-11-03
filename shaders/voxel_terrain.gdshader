shader_type spatial;
// Terrain shader for VoxelWorld chunk meshes.
// Vertex COLOR.r is baked ambient occlusion (0 = fully occluded), COLOR.g is material id / 255.
// Pattern materials (palette row 1 blue = layer + 1) take each voxel's color from a tiled image,
// one pixel per voxel, picked by the face's plane so walls, floors and ceilings all tile.

uniform sampler2D palette : source_color, filter_nearest;
uniform sampler2DArray patterns : source_color, filter_nearest;
uniform float voxel_size = 0.1;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.7;
uniform float voxel_variation : hint_range(0.0, 0.5) = 0.12;
uniform float edge_darkening : hint_range(0.0, 0.5) = 0.08;
uniform float emission_energy = 2.5;
// 1 while the facility has power. Powered lamps fade out with it; emergency lights fade in.
uniform float facility_power : hint_range(0.0, 1.0) = 1.0;
// Level editor cutaway: nothing above this world height is drawn (EditorCamera sets it; the cut
// face itself is EditorCamera's cap plane).
uniform float cut_height = 1e9;
// Level editor walls-down: above walls_down_height, nothing between the camera and the point it
// orbits (walls_down_point, looking along walls_down_dir in x / z) is drawn, so you can see into
// a room from a low angle. Off when walls_down_dir is zero.
uniform vec3 walls_down_point;
uniform vec2 walls_down_dir;
uniform float walls_down_height = 1e9;

varying vec3 world_position;
varying vec3 world_normal;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = NORMAL;
}

void fragment() {
	if (world_position.y > cut_height) {
		discard;
	}
	if (dot(world_position.xz - walls_down_point.xz, walls_down_dir) < -0.3 && world_position.y > walls_down_height) {
		discard;
	}
	int id = int(round(COLOR.g * 255.0));
	vec4 entry = texelFetch(palette, ivec2(id, 0), 0);
	vec4 flags = texelFetch(palette, ivec2(id, 1), 0);
	float light_switch = mix(1.0, facility_power, flags.r) * mix(1.0, 1.0 - facility_power, flags.g);

	// Nudge into the solid voxel so every pixel of a face agrees on which voxel it belongs to.
	vec3 cell = floor((world_position - world_normal * voxel_size * 0.5) / voxel_size);
	float variation = (hash(cell) - 0.5) * 2.0 * voxel_variation;

	// Faint darkening at voxel edges so 10cm detail reads on large flat merged faces.
	vec3 f = fract(world_position / voxel_size);
	vec3 edge_distance = min(f, 1.0 - f) + abs(world_normal);
	float edge = 1.0 - smoothstep(0.0, 0.08, min(edge_distance.x, min(edge_distance.y, edge_distance.z)));

	float ao = mix(1.0, 0.25 + 0.75 * COLOR.r, ao_strength);
	vec3 base = entry.rgb;
	int layer = int(round(flags.b * 255.0));
	if (layer > 0) {
		vec4 dims = texelFetch(palette, ivec2(id, 2), 0);
		ivec2 size = max(ivec2(round(dims.rg * 255.0)), ivec2(1));
		ivec3 c = ivec3(cell);
		vec3 n = abs(world_normal);
		// Floors and ceilings use x/z; walls use their own horizontal axis and y, flipped so the
		// image's top is up.
		ivec2 uv = n.y > 0.5 ? c.xz : (n.x > 0.5 ? ivec2(c.z, -c.y - 1) : ivec2(c.x, -c.y - 1));
		uv = ((uv % size) + size) % size;
		base = texelFetch(patterns, ivec3(uv, layer - 1), 0).rgb;
		variation *= 0.4; // The pattern already varies; keep a little per-voxel life.
	}
	vec3 albedo = base * (1.0 + variation) * (1.0 - edge * edge_darkening);

	ALBEDO = albedo * ao;
	ROUGHNESS = 0.9;
	EMISSION = entry.rgb * entry.a * emission_energy * light_switch;
}
