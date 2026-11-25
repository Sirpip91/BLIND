shader_type spatial;
// Ink-shading mode: each pixel picks a hand-drawn swatch by how much light
// reaches it, so lighting is drawn as strokes rather than as darkening.
render_mode diffuse_lambert, specular_disabled;

#include "res://Core/Ink/swatches.gdshaderinc"

group_uniforms look;
// Raises every light level; high values leave lit areas as bare paper.
uniform float lightness = 0.0;
// Keeps fully shadowed areas off the very darkest swatch.
uniform float shadow_lift = 0.12;

varying vec3 ink_light;
varying vec3 ink_dark;
varying float unlit_ink;


float level_for(float tone) {
	return (1.0 - clamp(mix(shadow_lift, 1.0, tone) + lightness, 0.0, 1.0)) * 6.0;
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}


void fragment() {
	vec3 light_inks;
	vec3 dark_inks;
	sample_swatches(world_pos, world_normal, 0.0, light_inks, dark_inks);
	ink_light = light_inks;
	ink_dark = dark_inks;
	// Unlit, every stroke is drawn; each light then erases ink back towards
	// paper. Lights add up that way, so any number of them work.
	unlit_ink = all_swatches(light_inks, dark_inks);
	ALBEDO = vec3(1.0);
	EMISSION = mix(paper_color, ink_color, unlit_ink);
}


void light() {
	float ink = swatch_ink(level_for(light_tone(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION)), ink_light, ink_dark);
	DIFFUSE_LIGHT += (paper_color - ink_color) * max(unlit_ink - ink, 0.0);
}
