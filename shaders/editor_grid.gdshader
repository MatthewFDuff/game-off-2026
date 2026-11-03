shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
// Level editor grid (EditorTool): faint lines at the grid snap on the surface under the cursor,
// lined up with the world's voxels and fading out around the cursor.

uniform vec3 origin;
uniform float spacing = 0.5;
uniform vec3 center;
uniform float radius = 3.0;
uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 0.35);

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 grid = (world_position.xz - origin.xz) / spacing;
	vec2 distance_to_line = abs(fract(grid - 0.5) - 0.5) / fwidth(grid);
	float line = 1.0 - min(min(distance_to_line.x, distance_to_line.y), 1.0);
	float fade = 1.0 - smoothstep(radius * 0.4, radius, distance(world_position.xz, center.xz));
	ALBEDO = color.rgb;
	ALPHA = color.a * line * fade;
	if (ALPHA < 0.01) {
		discard;
	}
}
