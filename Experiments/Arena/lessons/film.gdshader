shader_type spatial;
// A few seconds of something being done, on a torn scrap of paper. Drawn over
// the wash, so it isn't painted twice.
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D film : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(6.0, 6.0);
uniform float rate = 18.0;
uniform float now = 0.0;


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
	float frame = mod(floor(now * rate), grid.x * grid.y);
	vec2 cell = vec2(mod(frame, grid.x), floor(frame / grid.x));
	vec2 in_cell = clamp(UV, vec2(0.004), vec2(0.996));
	ALBEDO = texture(film, (cell + in_cell) / grid).rgb;
	vec2 from_edge = min(UV, 1.0 - UV) * vec2(1.78, 1.0);
	float torn = noise(UV * vec2(34.0, 20.0)) * 0.018 + noise(UV * vec2(120.0, 70.0)) * 0.009;
	float d = min(from_edge.x, from_edge.y) - torn;
	// A line of ink round it.
	ALBEDO = mix(ALBEDO, vec3(0.004), smoothstep(0.02, 0.012, d));
	ALPHA = smoothstep(0.0, 0.004, d);
}
