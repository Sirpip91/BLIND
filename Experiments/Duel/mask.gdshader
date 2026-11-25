shader_type spatial;
// A stand-in oni mask drawn straight onto a sphere: slanted eyes, a wide
// mouth, and cracks that spread as its wearer's composure goes.
render_mode unshaded;

uniform float cracks : hint_range(0.0, 1.0) = 0.0;
// Red running down from the eyes.
uniform float fury : hint_range(0.0, 1.0) = 0.0;
uniform vec3 eye_color : source_color = vec3(0.85, 0.05, 0.04);

varying vec3 at;


void vertex() {
	at = VERTEX;
}


vec2 hash2(vec2 p) {
	uvec2 q = uvec2(ivec2(p) + ivec2(32768));
	uint h = q.x * 374761393u + q.y * 668265263u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	h = h ^ (h >> 16u);
	return vec2(float(h & 65535u), float((h >> 8u) & 65535u)) / 65535.0;
}

// Distance to the nearest border between random cells.
float shatter(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float first = 8.0;
	float second = 8.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 o = vec2(float(x), float(y));
			float d = length(o + hash2(i + o) - f);
			if (d < first) {
				second = first;
				first = d;
			} else {
				second = min(second, d);
			}
		}
	}
	return second - first;
}


void fragment() {
	vec2 p = at.xy / 0.125;
	float front = step(at.z, 0.02);
	float value = 0.95;
	vec2 m = vec2(abs(p.x), p.y);
	// Brow, eye, cheek and mouth.
	float brow = smoothstep(0.06, 0.03, abs(m.y - 0.36 - (m.x - 0.3) * 0.55)) * step(0.08, m.x) * step(m.x, 0.72);
	vec2 e = vec2(m.x - 0.36, m.y - 0.14 - (m.x - 0.36) * 0.4);
	float eye = step(length(e * vec2(1.0, 2.6)), 0.21);
	float pupil = step(length(e * vec2(1.0, 1.5)), 0.085);
	float nose = smoothstep(0.05, 0.02, abs(m.x - 0.1 - (0.1 - p.y) * 0.1)) * step(-0.18, p.y) * step(p.y, 0.15);
	float lip = -0.46 + m.x * m.x * 0.35;
	float mouth = step(abs(p.y - lip), 0.13 - m.x * 0.1) * step(m.x, 0.6);
	float teeth = step(0.35, fract(p.x * 4.5)) * step(abs(p.y - lip), 0.07);
	value = mix(value, 0.04, max(max(brow, eye), max(nose, mouth)));
	value = mix(value, 0.9, teeth * mouth);
	// Cracks start at the brow and work outward.
	float spread = smoothstep(0.0, 0.25, cracks * 1.5 - length(p - vec2(0.25, 0.4)) * 0.55);
	float line = smoothstep(0.02 + 0.07 * cracks, 0.0, shatter(p * 2.3 + 4.0)) * spread;
	value = mix(value, 0.03, line);
	vec3 color = vec3(pow(value, 2.2));
	// Light through the cracks as it's about to go.
	color = mix(color, eye_color, max(pupil, line * smoothstep(0.6, 1.0, cracks)));
	float track = smoothstep(0.16, 0.05, abs(m.x - 0.36 - (0.1 - p.y) * 0.06)) * step(p.y, 0.1) * step(0.1 - fury * (0.75 + 0.3 * hash2(vec2(sign(p.x) + 2.0, 5.0)).x), p.y);
	color = mix(color, eye_color, max(track, eye * fury));
	ALBEDO = mix(vec3(0.002), color, front);
}
