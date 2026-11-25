shader_type spatial;
// Red ink where it hit the ground, thrown toward +X: piled up at the far end,
// with runners and drops gone on ahead of it. Cut out rather than faded, so
// the wash pass treats it as painted.
render_mode unshaded, cull_disabled, shadows_disabled;

// Seconds, the same clock each one is stamped with.
uniform float blood_now = 0.0;

varying flat vec4 mark;
varying flat vec3 ink;


void vertex() {
	mark = INSTANCE_CUSTOM;
	ink = pow(COLOR.rgb, vec3(2.2));
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
	float seed = mark.x;
	float age = max(blood_now - mark.y, 0.0);
	float grown = 1.0 - exp(-age * 16.0);
	// Back to round, so nothing in it is smeared by how long the mark is.
	float long = mark.z;
	vec2 p = (UV * 2.0 - 1.0) * vec2(long, 1.0);
	p.x /= long * 0.5 + 0.5;
	float toward = p.x + 0.12;
	float angle = atan(p.y, toward);
	float ahead = max(cos(angle), 0.0);
	float r = length(vec2(toward, p.y));
	float around = noise(vec2(cos(angle), sin(angle)) * 2.3 + seed) * 0.6 + noise(vec2(cos(angle), sin(angle)) * 7.0 + seed * 1.7) * 0.4;
	float spike = pow(noise(vec2(angle * 4.6 + seed * 3.0, seed)), 3.0) * (0.12 + 0.85 * ahead * ahead) * mix(0.4, 1.0, mark.w);
	float edge = (0.2 + 0.2 * around + spike) * grown;
	float on = step(r, edge);
	// Drops that went on ahead.
	vec2 grid = p * 5.0 + seed;
	vec2 cell = floor(grid);
	vec2 spot = vec2(hash(cell + 2.0), hash(cell + 5.0)) * 0.5 + 0.25;
	float lucky = step(0.7 - 0.25 * ahead, hash(cell + 9.0)) * step(-0.1, toward) * step(0.3, r) * step(r, 0.92);
	on = max(on, lucky * step(length((fract(grid) - spot) * vec2(0.7, 1.0)), (0.1 + 0.16 * hash(cell + 13.0)) * grown) * step(abs(p.y), 0.25 + 0.5 * max(toward, 0.0)));
	if (on < 0.5) {
		discard;
	}
	// Thin in the middle, piled up round the rim, browning as it dries.
	float rim = smoothstep(0.5, 1.0, r / max(edge, 0.01));
	float pale = noise(p * 4.0 + seed * 2.0);
	ALBEDO = ink * mix(1.25, 0.5, rim) * mix(0.85, 1.1, pale) * mix(1.0, 0.62, smoothstep(4.0, 40.0, age));
	ROUGHNESS = 1.0;
}
