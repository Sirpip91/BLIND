shader_type spatial;
// Ink thrown off a clash: a small blot with needles flung out of it, always
// flat to the eye. Drawn after the wash pass.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 ink_color : source_color = vec3(0.035, 0.035, 0.045);
// 0 the moment it lands, 1 gone.
uniform float age = 0.0;
uniform float seed = 0.0;
// Which way it's thrown, and how strongly: 0 bursts evenly.
uniform vec2 thrown = vec2(0.0);
uniform float blot = 0.16;


void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
			INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}


float hash(float n) {
	uint h = uint(int(n) + 32768) * 374761393u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return float((h ^ (h >> 16u)) & 65535u) / 65535.0;
}

float noise(float n) {
	float f = fract(n);
	return mix(hash(floor(n)), hash(floor(n) + 1.0), f * f * (3.0 - 2.0 * f));
}


void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float r = length(p);
	float angle = atan(p.y, p.x) / TAU + 0.5;
	float grown = 1.0 - pow(1.0 - clamp(age * 3.2, 0.0, 1.0), 3.0);

	// Needles: each its own length, fattest in the middle, off the blot.
	float count = 34.0;
	float id = floor(angle * count);
	float pick = hash(id + seed * 7.0);
	float off = abs(fract(angle * count) - 0.5 - (hash(id + 90.0 + seed) - 0.5) * 0.4);
	float along_thrown = dot(normalize(p + 1e-5), normalize(thrown + 1e-5));
	float bias = mix(1.0, smoothstep(-0.2, 1.0, along_thrown) * 1.35, min(length(thrown), 1.0));
	float reach = (0.18 + 0.8 * pick * pick) * grown * bias;
	float tail = reach * smoothstep(0.25, 1.0, age);
	float body = smoothstep(tail, tail + 0.12, r) * (1.0 - smoothstep(reach - 0.1, reach, r));
	float width = 0.2 * body * mix(0.35, 1.0, hash(id + 31.0 + seed)) / max(r * 2.6, 0.45);
	float needle = smoothstep(width, width * 0.55, off) * step(0.3, pick) * step(0.02, body);

	// Drops that came loose from the ends.
	float drop_at = reach + 0.07 * hash(id + 60.0);
	float drop = step(length(vec2((r - drop_at) * 1.0, off * r * 0.19 * 1.6)), 0.013 * step(0.55, pick) * bias);

	float edge = blot * (0.75 + 0.5 * noise(angle * 26.0 + seed) + 0.2 * noise(angle * 80.0)) * grown * (1.0 - age);
	float core = smoothstep(edge + 0.012, edge - 0.012, r);

	ALBEDO = ink_color;
	ALPHA = max(max(needle, drop), core) * (1.0 - smoothstep(0.55, 1.0, age));
}
