shader_type spatial;
// Terrain shader for VoxelWorld chunk meshes.
// Vertex COLOR.r is baked ambient occlusion (0 = fully occluded), COLOR.g is material id / 255.

uniform sampler2D palette : source_color, filter_nearest;
uniform float voxel_size = 0.1;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.7;
uniform float voxel_variation : hint_range(0.0, 0.5) = 0.12;
uniform float edge_darkening : hint_range(0.0, 0.5) = 0.08;
uniform float emission_energy = 2.5;

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
	int id = int(round(COLOR.g * 255.0));
	vec4 entry = texelFetch(palette, ivec2(id, 0), 0);

	// Nudge into the solid voxel so every pixel of a face agrees on which voxel it belongs to.
	vec3 cell = floor((world_position - world_normal * voxel_size * 0.5) / voxel_size);
	float variation = (hash(cell) - 0.5) * 2.0 * voxel_variation;

	// Faint darkening at voxel edges so 10cm detail reads on large flat merged faces.
	vec3 f = fract(world_position / voxel_size);
	vec3 edge_distance = min(f, 1.0 - f) + abs(world_normal);
	float edge = 1.0 - smoothstep(0.0, 0.08, min(edge_distance.x, min(edge_distance.y, edge_distance.z)));

	float ao = mix(1.0, 0.25 + 0.75 * COLOR.r, ao_strength);
	vec3 albedo = entry.rgb * (1.0 + variation) * (1.0 - edge * edge_darkening);

	ALBEDO = albedo * ao;
	ROUGHNESS = 0.9;
	EMISSION = entry.rgb * entry.a * emission_energy;
}
