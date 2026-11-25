shader_type canvas_item;
// One pull of a wide brush across a box.

uniform vec4 ink : source_color = vec4(0.02, 0.02, 0.025, 1.0);
uniform float drawn : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
uniform float dryness : hint_range(0.0, 1.0) = 0.5;
uniform vec2 size = vec2(400.0, 80.0);


float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}


void fragment() {
	float x = UV.x * size.x / size.y;
	float y = UV.y * 2.0 - 1.0 + (noise(vec2(x * 0.7, seed)) - 0.5) * 0.18;
	float hairs = noise(vec2(x * 0.5 + seed, y * 13.0)) * 0.55 + noise(vec2(x * 1.6, y * 34.0 + seed)) * 0.45;
	float half_width = 0.72 + 0.12 * noise(vec2(x * 1.1 + seed, 4.0)) - 0.5 * pow(UV.x, 7.0) - 0.4 * pow(1.0 - UV.x, 22.0);
	float on = smoothstep(half_width, half_width - 0.07, abs(y) + (hairs - 0.5) * mix(0.12, 0.5, UV.x));
	float dry = dryness * smoothstep(0.25, 1.0, UV.x);
	on *= smoothstep(dry - 0.2, dry, hairs + 0.12);
	on *= step(0.001, drawn) * smoothstep(0.0, 0.05, drawn * 1.12 - UV.x - (hairs - 0.5) * 0.1);
	COLOR = vec4(ink.rgb, ink.a * on);
}
