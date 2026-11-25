shader_type spatial;
// The painted glow map burning hot: white paint lights first, greys join in
// as the sword heats up, black never does. Runs as a second pass after the
// ink pass so the colour survives the black-and-white filter.
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

// Read as plain numbers, not colour: grey 128 means half.
uniform sampler2D glow_map : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform vec3 glow_color : source_color = vec3(1.0);
// Colour of the hottest paint.
uniform vec3 core_color : source_color = vec3(1.0);
// 0 at rest, 1 fully hot.
uniform float heat : hint_range(0.0, 1.0) = 0.0;
// How much of the glow stays on at rest; 0 leaves the painting untouched.
uniform float rest_glow : hint_range(0.0, 1.0) = 0.0;
// How far the hottest paint turns to core_color.
uniform float white_hot = 0.35;
// How bright the glow map must be to light up, at heat 0 and at heat 1.
uniform float glow_from_cold = 0.75;
uniform float glow_from_hot = 0.1;
uniform float pulse_speed = 3.0;
// How far up the blade the glow has reached, for charging. 1 is all of it.
uniform float sweep : hint_range(0.0, 1.0) = 1.0;
uniform float blade_from = 0.065;
uniform float blade_to = 0.755;

varying vec3 local_pos;


void vertex() {
	local_pos = VERTEX;
	// A hair off the surface so it never fights the blade for depth.
	VERTEX += NORMAL * 0.0004;
}


void fragment() {
	float paint = texture(glow_map, UV).r;
	float from = mix(glow_from_cold, glow_from_hot, heat);
	float lit = smoothstep(from, from + 0.2, paint);
	float front = mix(blade_from, blade_to + 0.1, sweep);
	lit *= 1.0 - smoothstep(front - 0.08, front, local_pos.y);
	float crest = sweep < 1.0 ? smoothstep(front - 0.25, front - 0.08, local_pos.y) : 0.0;
	float flow = 0.5 + 0.5 * sin(local_pos.y * 28.0 - TIME * pulse_speed);
	float hot = max(paint * paint * mix(0.55, 1.0, flow) * (0.6 + 0.4 * heat), crest);
	ALBEDO = mix(glow_color * 0.75, mix(glow_color, core_color, white_hot), hot);
	ALPHA = lit * max(rest_glow, heat);
}
