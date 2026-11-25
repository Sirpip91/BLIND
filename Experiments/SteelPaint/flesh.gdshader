shader_type spatial;
// The face of a cut, flat as a print: bone in the middle, red, a dark rim.
render_mode unshaded, cull_disabled;

uniform float bone : hint_range(0.0, 1.0) = 0.24;
uniform vec3 red : source_color = vec3(0.6, 0.015, 0.02);
uniform vec3 pale : source_color = vec3(0.9, 0.86, 0.78);


void fragment() {
	float r = UV.x;
	vec3 color = mix(red, red * 0.35, smoothstep(0.82, 0.9, r));
	color = mix(color, red * 0.45, step(r, bone * 1.35) * step(0.01, bone));
	ALBEDO = mix(color, pale, step(r, bone) * step(0.01, bone));
}
