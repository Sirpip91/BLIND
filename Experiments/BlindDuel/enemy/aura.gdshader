shader_type spatial;
// A red smoke licking off the edges of a body that is otherwise black.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.9, 0.04, 0.03);
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform float glint : hint_range(0.0, 1.0) = 0.0;
uniform float flare : hint_range(0.0, 1.0) = 0.0;
uniform float swell = 0.05;
// How tightly it clings to the outline; higher leaves more of the body dark.
uniform float cling = 4.0;
uniform float strength = 0.7;

varying vec3 world_pos;


float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float low = mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y);
	float high = mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y);
	return mix(low, high, f.z);
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float licks = noise(world_pos * 5.0 - vec3(0.0, TIME * 1.6, 0.0));
	VERTEX += NORMAL * swell * (0.4 + licks * 1.4);
}


void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), cling);
	float smoke = noise(world_pos * 7.0 - vec3(0.0, TIME * 2.2, 0.0)) * 0.6
			+ noise(world_pos * 16.0 - vec3(0.0, TIME * 3.4, 0.0)) * 0.4;
	float lit = rim * smoothstep(0.42, 0.72, smoke);
	ALBEDO = mix(color, vec3(1.0), flare * 0.7);
	ALPHA = clamp(lit * reveal * strength + flare * rim * 0.8, 0.0, 1.0);
}
