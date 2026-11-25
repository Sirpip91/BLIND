// What impact_frames.gd drives on a hit: a silhouette frame, a negative frame,
// burst lines and a punch-in zoom. The names match the ink pass, so either
// look can be handed to it.

group_uniforms impact;
uniform int impact_mode = 0;
uniform float impact_lines = 0.0;
uniform vec2 impact_center = vec2(0.5);
uniform float impact_seed = 0.0;
uniform float impact_depth = 5.0;
uniform float impact_reach = 1.0;
uniform float impact_rays = 160.0;
uniform int impact_style = 0;
uniform float impact_twist = 0.0;
uniform vec3 impact_color : source_color = vec3(1.0);
uniform float impact_zoom = 0.0;
uniform vec3 impact_shape : source_color = vec3(0.035, 0.035, 0.045);
uniform vec3 impact_back : source_color = vec3(0.93, 0.92, 0.89);
uniform float impact_colored = 0.3;
group_uniforms;


float impact_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 impact_zoomed(vec2 uv) {
	return impact_center + (uv - impact_center) / (1.0 + impact_zoom);
}

vec3 impact_frame(vec3 color, vec2 uv, float depth, vec2 viewport, vec3 paper, vec3 ink) {
	if (impact_mode == 1) {
		color = depth < impact_depth + impact_reach ? impact_shape : impact_back;
	} else if (impact_mode == 2) {
		color = paper + ink - color;
	}
	if (impact_lines <= 0.0) {
		return color;
	}
	vec2 d = (uv - impact_center) * vec2(viewport.x / viewport.y, 1.0);
	float r = length(d);
	float angle = atan(d.y, d.x) / TAU + 0.5;
	if (impact_style == 2) {
		// Gentle: many fine rays wound tight turn into grooves.
		angle += impact_twist * r * 0.06;
	}
	float around = angle * impact_rays;
	float ray_id = floor(around);
	float pick = impact_hash(vec2(ray_id, impact_seed));
	// Each ray starts its own distance out, leaving a clear eye with a ragged
	// edge, and only some angles get a ray at all.
	float eye = impact_style == 1 ? mix(0.38, 0.65, impact_hash(vec2(ray_id, impact_seed + 3.1)))
			: mix(0.08, 0.5, impact_hash(vec2(ray_id, impact_seed + 3.1))) * (1.5 - impact_lines * 0.7);
	float width = mix(0.1, 0.45, pick) * smoothstep(eye, eye + 0.6, r) * 2.0;
	if (impact_style == 1) {
		width *= 0.5;
	}
	float offset = fract(around) - 0.5;
	if (impact_style == 3) {
		offset += 0.35 * (abs(fract(r * 9.0 + pick * 3.0) - 0.5) - 0.25);
	}
	float ray = step(abs(offset), width * 0.5) * step(0.4, pick) * smoothstep(eye, eye + 0.05, r);
	// Dry-brush break-up, so they read as drawn strokes.
	ray *= step(0.25, impact_hash(floor(uv * viewport / 3.0) + ray_id));
	float behind = dot(color, vec3(0.2126, 0.7152, 0.0722));
	vec3 line = behind < 0.4 ? paper : ink;
	if (impact_hash(vec2(ray_id, impact_seed + 9.7)) < impact_colored) {
		line = impact_color;
	}
	return mix(color, line, ray * impact_lines);
}
