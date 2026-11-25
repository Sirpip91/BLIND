shader_type spatial;
// A black floor that only exists where sound crosses it: each footfall
// spreads like a drop hitting water, drawn as broken ink rings.
render_mode unshaded, shadows_disabled, fog_disabled;

const int MAX = 24;

// x, z, start, life
uniform vec4 drops[MAX];
// radius, strength, rings, seed
uniform vec4 shapes[MAX];
uniform float now = 0.0;
uniform vec3 color : source_color = vec3(0.95, 0.94, 0.91);
uniform float arena_radius = 10.0;
// The edge of the arena, so there's something to find your way by.
uniform float rim = 0.12;
uniform float line_width = 0.005;

varying vec3 world_pos;


float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 p = world_pos.xz;
	// Never thinner than a pixel, or distant rings would sparkle.
	float px = length(fwidth(p));
	float ink = 0.0;
	float wash = 0.0;
	for (int i = 0; i < MAX; i++) {
		float age = now - drops[i].z;
		float life = drops[i].w;
		float radius = shapes[i].x;
		vec2 to = p - drops[i].xy;
		float d = length(to);
		if (life <= 0.0 || age < 0.0 || age > life || d > radius * 1.1 + 0.2) {
			continue;
		}
		float t = age / life;
		float front = radius * (1.0 - (1.0 - t) * (1.0 - t));
		float seed = shapes[i].w;
		// Hand-drawn: the circle wavers, and the pen skips.
		vec2 turn = to / max(d, 0.001);
		float wander = noise(turn * 2.5 + seed) - 0.5;
		float skip = noise(turn * 7.0 + seed * 3.1) * 0.8 + noise(turn * 22.0 + seed) * 0.2;
		d += wander * 0.12 * min(front, 1.0);
		float fade = (1.0 - t) * sqrt(1.0 - t) * shapes[i].y;
		float pen = smoothstep(0.1 + t * 0.25, 0.5 + t * 0.25, skip);
		for (int k = 0; k < 4; k++) {
			if (float(k) >= shapes[i].z) {
				break;
			}
			float ring = front * (1.0 - 0.27 * float(k));
			float w = max(line_width * (1.0 + 0.4 * min(shapes[i].y, 1.5)), px * 0.7);
			float line = 1.0 - smoothstep(w, w + px, abs(d - ring));
			ink = max(ink, line * pen * fade * pow(0.62, float(k)));
		}
		wash = max(wash, smoothstep(front - 0.5, front, d) * step(d, front) * fade * 0.06);
	}
	float edge = abs(length(p) - arena_radius);
	float rim_width = max(0.02, px * 0.7);
	float broken = step(0.3, noise(p / max(length(p), 0.001) * 30.0));
	ink = max(ink, (1.0 - smoothstep(rim_width, rim_width + px, edge)) * rim * broken);
	ALBEDO = color * clamp(ink + wash, 0.0, 1.0);
}
