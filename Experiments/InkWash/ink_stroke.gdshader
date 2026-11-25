shader_type spatial;
// One stroke of a loaded brush running dry. UV.x is metres along it and UV.y
// crosses it, so each bristle keeps its own track. Drawn after the wash pass.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 ink_color : source_color = vec3(0.035, 0.035, 0.045);
uniform vec3 tint : source_color = vec3(0.85, 0.05, 0.04);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
// 0 fresh, 1 gone.
uniform float age = 0.0;
uniform float total = 1.0;
uniform float seed = 0.0;
// Where along the stroke the brush presses hardest.
uniform float press_at : hint_range(0.0, 1.0) = 0.4;
uniform float dryness : hint_range(0.0, 1.5) = 0.95;
// Water carried out past the ink.
uniform float water : hint_range(0.0, 1.0) = 0.3;


// Whole numbers, because the usual fract() hash rounds differently from one
// cell to the next here and leaves a visible step.
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
	float along = clamp(UV.x / max(total, 0.001), 0.0, 1.0);
	// -1 to 1 across, wandering a little as a hand does.
	float across = UV.y * 2.0 - 1.0 + (noise(vec2(UV.x * 4.0, seed)) - 0.5) * 0.22;

	float press = along < press_at ? sin(along / press_at * PI * 0.5) : cos((along - press_at) / (1.0 - press_at) * PI * 0.5);
	// An uneven hand: the stroke swells and thins along its length.
	float half_width = 0.8 * pow(max(press, 0.0), 0.9) * (0.72 + 0.45 * noise(vec2(UV.x * 3.0 + seed, 9.0)));

	// Hairs are long along the stroke and fine across it; each runs out of
	// ink at its own point.
	float coarse = noise(vec2(across * 8.0 + seed, UV.x * 0.9 + seed));
	float hairs = noise(vec2(across * 24.0 + seed, UV.x * 1.7 + 5.0));
	float fine = noise(vec2(across * 64.0, UV.x * 5.0 + seed));
	float speck = noise(vec2(across * 40.0, UV.x * 60.0 + seed));
	float bristle = coarse * 0.36 + hairs * 0.36 + fine * 0.18 + speck * 0.1;

	float fray = (hairs - 0.5) * mix(0.3, 1.1, along) * half_width + (speck - 0.5) * 0.06;
	float inside = smoothstep(half_width + 0.02, half_width - 0.03, abs(across) + fray);

	float rim = clamp(abs(across) / max(half_width, 0.01), 0.0, 1.0);
	float dry = 0.12 + dryness * smoothstep(0.02, 0.95, along) * 0.62 + 0.16 * rim * rim;
	// The thin end dries first.
	dry += age * (0.45 + 0.6 * along);
	float wet = smoothstep(dry - 0.03, dry + 0.04 + 0.08 * age, bristle + 0.1);

	float wash_edge = half_width * 1.2 + (noise(vec2(UV.x * 11.0, seed + 3.0)) - 0.5) * 0.35;
	float wash = smoothstep(wash_edge + 0.05, wash_edge - 0.12, abs(across)) * (1.0 - smoothstep(0.25, 0.85, along + (coarse - 0.5) * 0.5));
	// Water leaves a faint tide line where it stopped.
	wash *= 0.6 + 0.4 * smoothstep(wash_edge - 0.3, wash_edge - 0.1, abs(across));
	wash *= water * smoothstep(0.0, 0.1, along) * (1.0 - age);

	float ink = inside * wet;
	float coloured = smoothstep(0.45, 0.6, noise(vec2(across * 7.0 + seed + 40.0, UV.x * 0.9))) * tint_amount;
	ALBEDO = mix(ink_color, tint, max(coloured, (1.0 - ink) * tint_amount));
	ALPHA = max(ink * (1.0 - smoothstep(0.65, 1.0, age)), wash);
}
