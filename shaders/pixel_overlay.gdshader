shader_type canvas_item;
// Fullscreen status overlays (CombatHud: burning / poisoned vignette, damage flash, blinded fog)
// as pixel art: the screen is cut into `cell` px blocks, the density is quantized into `levels`
// rings from the edge in, and each block is fully on or off by an ordered 4x4 dither. No smooth
// gradient anywhere. The color is the node's color; its alpha (and modulate) scale the density.
// inner: how far in (0 center, 1 the corners) the edge glow starts; below 0 it covers the screen
// evenly (flash, fog).

uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float inner = 0.45;
uniform float cell = 4.0;
uniform float levels = 4.0;
uniform float max_alpha = 1.0;

void fragment() {
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 block = floor(FRAGCOORD.xy / cell);
	vec2 center = (block + 0.5) * cell;
	float density = 1.0;
	if (inner >= 0.0) {
		vec2 d = (center - size * 0.5) / (size * 0.5);
		float r = length(d) / 1.41421;
		density = clamp((r - inner) / max(1.0 - inner, 0.001), 0.0, 1.0);
		density = ceil(density * levels) / levels;
	}
	density *= amount * COLOR.a;
	ivec2 p = ivec2(mod(block, 4.0));
	const float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	float threshold = (bayer[p.y * 4 + p.x] + 0.5) / 16.0;
	COLOR = vec4(COLOR.rgb, density > threshold ? max_alpha : 0.0);
}
