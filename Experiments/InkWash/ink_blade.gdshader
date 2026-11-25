shader_type spatial;
// The katana painted as one loaded brush stroke: ink along the spine, a
// wandering wet border where the temper line would be, bare paper at the
// edge. Ink is a supply, thrown off by a swing and soaking back up from the
// guard. Noise is fixed to the blade, so nothing crawls while it's still.
render_mode unshaded, cull_disabled;

uniform sampler2D painting : source_color, filter_linear_mipmap, repeat_disable, hint_default_white;

// How far up the blade the ink has soaked; past 1 is full to the tip.
uniform float fill = 1.3;
// Ink thrown toward the edge (+) or the spine (-) by a turn of the wrist.
uniform float slosh = 0.0;
// Where along the blade the wet highlight sits.
uniform float glint = 0.5;

group_uniforms ink;
uniform float border = 0.5;
uniform float border_wander = 0.62;
uniform float wet_black : hint_range(0.0, 1.0) = 0.05;
uniform float wet_grey : hint_range(0.0, 1.0) = 0.34;
uniform float pale_wash : hint_range(0.0, 1.0) = 0.72;
uniform float dryness : hint_range(0.0, 1.0) = 0.5;
uniform float glint_strength : hint_range(0.0, 1.0) = 0.8;

group_uniforms color;
// Colour bleeding into the ink when the sword is hot.
uniform vec3 tint : source_color = vec3(0.85, 0.05, 0.04);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
uniform float sweep : hint_range(0.0, 1.0) = 1.0;

group_uniforms blade;
// The blade's shape in the model: the spine is a shallow curve in x over y.
uniform float blade_from = 0.065;
uniform float blade_to = 0.757;
uniform float spine_low = -0.016;
uniform float spine_mid = 0.41;
uniform float spine_curve = 0.147;
uniform float blade_width = 0.027;
uniform float tip_length = 0.06;

varying vec3 local_pos;


void vertex() {
	local_pos = VERTEX;
}


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
	float y = local_pos.y;
	float value;
	float bleed = 0.0;
	float deep = 0.0;
	if (y > blade_from) {
		float t = (y - blade_from) / (blade_to - blade_from);
		float spine = spine_low + spine_curve * (y - spine_mid) * (y - spine_mid);
		float width = blade_width * sqrt(clamp((blade_to - y) / tip_length, 0.001, 1.0));
		// 0 along the spine, 1 at the cutting edge.
		float u = clamp((spine - local_pos.x) / width, 0.0, 1.0);

		float soak = t + (noise(vec2(u * 3.0, y * 20.0)) - 0.5) * 0.3;
		float wet = 1.0 - smoothstep(fill - 0.12, fill + 0.08, soak);

		float edge = border + (noise(vec2(y * 15.0, 2.0)) - 0.5) * border_wander
				+ (noise(vec2(y * 55.0, 7.0)) - 0.5) * border_wander * 0.35
				+ (noise(vec2(y * 160.0, u * 4.0)) - 0.5) * border_wander * 0.12;
		edge = (edge + slosh * (0.4 + 0.6 * t)) * mix(0.35, 1.0, wet);
		// Running out toward the tip, where the brush lifts.
		edge *= 1.0 - 0.35 * smoothstep(0.75, 1.0, t);

		float bristle = noise(vec2(u * 13.0, y * 7.0 + 3.0)) * 0.6 + noise(vec2(u * 30.0, y * 16.0)) * 0.4;
		float dry = dryness * (smoothstep(0.45, 1.0, t) * 0.55 + (1.0 - wet) * 0.75);
		float loaded = smoothstep(dry, dry + 0.12, bristle + 0.12);

		float body = (1.0 - smoothstep(edge - 0.02, edge + 0.04, u)) * loaded;
		float halo = (1.0 - smoothstep(edge + 0.1, edge + 0.3, u + (bristle - 0.5) * 0.2)) * mix(0.3, 1.0, wet) * loaded;
		float cloud = smoothstep(0.3, 0.75, noise(vec2(u * 1.6, y * 9.0 + 11.0)) * 0.7 + noise(vec2(u * 5.0, y * 30.0)) * 0.3);
		float ink_value = mix(wet_black, wet_grey, cloud * (0.35 + 0.65 * t));
		// Pigment gathers where the wet border stops.
		float pool = smoothstep(0.09, 0.0, abs(u - edge + 0.04)) * wet * 0.8;
		ink_value = mix(ink_value, wet_black, pool);

		value = mix(1.0, pale_wash, halo);
		value = mix(value, ink_value, body);

		float shine = smoothstep(0.07, 0.0, abs(u - 0.2 - (noise(vec2(y * 18.0, 5.0)) - 0.5) * 0.1));
		shine *= smoothstep(0.22, 0.0, abs(t - glint)) * step(0.45, noise(vec2(u * 8.0, y * 45.0)) + 0.3 * wet);
		value = mix(value, 1.0, shine * glint_strength * body);

		float charged = 1.0 - smoothstep(sweep * 1.1 - 0.1, sweep * 1.1, t);
		// The spine stays ink; colour floods the border and runs back in streaks.
		float flood = smoothstep(edge - 0.2, edge - 0.06, u + (bristle - 0.5) * 0.45);
		bleed = max(body * flood * flood, halo * (1.0 - body) * 0.85) * charged * tint_amount;
		deep = body * (1.0 - cloud) * 0.45;
	} else {
		// Black lacquer, with the painted wrap showing as scraped-back paper.
		float lines = clamp(1.0 - texture(painting, UV).r / 0.8, 0.0, 1.0);
		// The guard's texture is nearly all lines; left light it reads as metal.
		lines *= 1.0 - 0.8 * smoothstep(-0.01, 0.015, y);
		float worn = noise(vec2(local_pos.x * 90.0, y * 35.0)) * 0.6 + noise(vec2(local_pos.x * 300.0, y * 120.0)) * 0.4;
		value = mix(wet_black, 0.22, smoothstep(0.5, 0.8, worn));
		value = mix(value, 0.62, lines * smoothstep(0.25, 0.55, worn + 0.15));
	}
	ALBEDO = mix(vec3(pow(value, 2.2)), tint * (1.0 - deep), bleed);
}
