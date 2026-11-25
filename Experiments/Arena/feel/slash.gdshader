shader_type spatial;
// One thin stroke pulled through a body: drawn in an instant, then drying out
// from where it began. Drawn after the wash pass.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 ink_color : source_color = vec3(0.78, 0.03, 0.03);
uniform float age = 0.0;
uniform float seed = 0.0;
uniform vec2 way = vec2(1.0, 0.0);


void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}


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
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}


void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float t = dot(p, way) * 0.5 + 0.5;
	float across = dot(p, vec2(-way.y, way.x));
	// Bowed a little, as a real pull of the arm is.
	across += 0.07 * (t - 0.5) * (t - 0.5) * 4.0 - 0.035;
	float tip = smoothstep(-0.08, 0.1, age) * 1.05;
	float tail = smoothstep(0.2, 1.0, age) * 0.95;
	float swell = pow(max(sin(PI * pow(clamp(t, 0.0, 1.0), 0.7)), 0.0), 1.4);
	float half_width = 0.026 * swell * (1.0 - 0.75 * smoothstep(0.12, 0.9, age));
	// Runs to a point wherever the brush has got to.
	half_width *= smoothstep(tip, tip - 0.35, t);
	half_width *= 0.8 + 0.4 * noise(vec2(t * 14.0 + seed, 2.0));
	float body = smoothstep(half_width, half_width - 0.006, abs(across));
	float hairs = noise(vec2(t * 5.0 + seed, across * 420.0 + 300.0));
	body *= smoothstep(age * 0.8 - 0.1, age * 0.8 + 0.1, hairs + 0.15);
	body *= step(tail, t) * step(t, tip);
	ALBEDO = ink_color;
	ALPHA = body;
}
