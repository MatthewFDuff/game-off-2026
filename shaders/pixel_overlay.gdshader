shader_type canvas_item;
// Fullscreen status overlays (CombatHud: burning / poisoned vignette, damage flash; Player: the
// blinded fog) as pixel art: the screen is cut into `cell` px blocks, and no smooth gradient
// anywhere. The color is the node's color; its alpha (and modulate) scale the density.
// inner: how far in (0 center, 1 the corners) the edge glow starts. The edge glow is quantized
// into `levels` rings from the edge in, each block fully on or off by an ordered 4x4 dither.
// Below 0 (the blinded fog) it is a flat tint over the whole screen instead, truly blended, with
// a ragged border of solid blocks `edge` blocks deep (two steps thicker toward the frame).

uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float inner = 0.45;
uniform float cell = 4.0;
uniform float levels = 4.0;
uniform float max_alpha = 1.0;
// Flat mode: how many blocks deep the solid border reaches at most.
uniform float edge = 8.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 block = floor(FRAGCOORD.xy / cell);
	if (inner < 0.0) {
		// Blocks in from the nearest screen edge; the border's depth wobbles per run of blocks.
		vec2 blocks = floor(size / cell);
		vec2 from_edge = min(block, blocks - 1.0 - block);
		float along = from_edge.x < from_edge.y ? block.y : block.x;
		float depth = floor(edge * (0.35 + 0.65 * hash(vec2(floor(along / 3.0), from_edge.x < from_edge.y ? 1.0 : 2.0))));
		float d = min(from_edge.x, from_edge.y);
		float flat_alpha = amount * COLOR.a * max_alpha;
		float a = flat_alpha * 0.82;
		if (d < depth * 0.5) {
			a = flat_alpha;
		} else if (d < depth) {
			a = flat_alpha * 0.92;
		}
		COLOR = vec4(COLOR.rgb, a);
	} else {
		vec2 center = (block + 0.5) * cell;
		vec2 dd = (center - size * 0.5) / (size * 0.5);
		float r = length(dd) / 1.41421;
		float density = clamp((r - inner) / max(1.0 - inner, 0.001), 0.0, 1.0);
		density = ceil(density * levels) / levels;
		density *= amount * COLOR.a;
		ivec2 p = ivec2(mod(block, 4.0));
		const float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
		float threshold = (bayer[p.y * 4 + p.x] + 0.5) / 16.0;
		COLOR = vec4(COLOR.rgb, density > threshold ? max_alpha : 0.0);
	}
}
