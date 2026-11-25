shader_type canvas_item;
// Lettering gone over with a brush that's running dry.

uniform float seed = 0.0;
uniform float dryness : hint_range(0.0, 1.0) = 0.35;
// Wiped on from the left.
uniform float drawn : hint_range(0.0, 1.0) = 1.0;
uniform float width = 400.0;

varying vec2 at;


void vertex() {
	at = VERTEX;
}


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
	float hairs = noise(vec2(at.x * 0.02 + seed, at.y * 0.55)) * 0.55 + noise(vec2(at.x * 0.09, at.y * 0.9 + seed)) * 0.45;
	float worn = smoothstep(1.0 - dryness, 1.0 - dryness + 0.16, hairs + 0.18 * noise(at * 0.03 + seed));
	COLOR.a *= 1.0 - worn * 0.85;
	COLOR.a *= smoothstep(0.0, 0.06, drawn * 1.08 - at.x / width + (hairs - 0.5) * 0.08);
}
