shader_type canvas_item;
// Red ink soaking in from the edges of the sheet: a burst when hit, and a
// stain that stays with every wound.

uniform float hurt = 0.0;
uniform float wounds = 0.0;
uniform vec3 ink : source_color = vec3(0.72, 0.03, 0.03);


float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(p) + ivec2(32768));
	uint h = q.x * 374761393u + q.y * 668265263u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return float((h ^ (h >> 16u)) & 65535u) / 65535.0;
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}


void fragment() {
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 from_edge = min(UV, 1.0 - UV) * aspect;
	float edge = min(from_edge.x, from_edge.y);
	vec2 p = UV * aspect;
	float ragged = noise(p * 5.0) * 0.5 + noise(p * 14.0) * 0.32 + noise(p * 34.0) * 0.18;
	float reach = 0.17 * hurt + 0.13 * wounds;
	float soaked = smoothstep(reach, reach - 0.05, edge + ragged * 0.22 + 0.02);
	float thin = smoothstep(reach + 0.08, reach - 0.1, edge + ragged * 0.2);
	COLOR = vec4(ink, max(soaked * 0.8, thin * 0.3) * clamp(hurt + wounds, 0.0, 1.0));
}
