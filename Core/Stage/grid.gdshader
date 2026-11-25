shader_type spatial;

// World-space so the lines stay true metres however the floor is scaled —
// the point is judging the size of imported models at a glance.
uniform vec3 base_color : source_color = vec3(0.32);
uniform vec3 line_color : source_color = vec3(0.18);
uniform vec3 major_color : source_color = vec3(0.08);
uniform float major_every = 10.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 p) {
	vec2 g = abs(fract(p - 0.5) - 0.5) / fwidth(p);
	return 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 col = mix(base_color, line_color, grid_line(p));
	col = mix(col, major_color, grid_line(p / major_every));
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
