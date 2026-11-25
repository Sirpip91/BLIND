shader_type spatial;
// Ink-shading mode for a hand-painted texture: exactly as drawn in full
// light; where the surface turns from the light or falls in shadow, the
// swatches are drawn over it, the way an illustrator darkens a drawing.
render_mode diffuse_lambert, specular_disabled;

#include "res://Core/Ink/swatches.gdshaderinc"

uniform sampler2D painting : source_color, filter_linear_mipmap, hint_default_white;

group_uniforms shading;
// Light level below which shading strokes start appearing over the paint.
uniform float shade_start = 0.6;
// How dark full shadow gets: 6 reaches the darkest swatch.
uniform float shade_depth = 5.0;
// Turns the shading strokes against the painted ones so they cross-hatch
// rather than vanish into strokes going the same way.
uniform float shade_angle = 1.57;

varying vec3 ink_light;
varying vec3 ink_dark;
varying float painted;
varying float unlit_ink;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}


void fragment() {
	painted = sheet_ink(texture(painting, UV).r);
	vec3 light_inks;
	vec3 dark_inks;
	sample_swatches(world_pos, world_normal, shade_angle, light_inks, dark_inks);
	ink_light = light_inks;
	ink_dark = dark_inks;
	// Unlit, every shading stroke is drawn over the painting; each light
	// erases them back towards the bare painting. Lights add up that way, so
	// any number of them work.
	unlit_ink = max(painted, all_swatches(light_inks, dark_inks));
	ALBEDO = vec3(1.0);
	EMISSION = mix(paper_color, ink_color, unlit_ink);
}


void light() {
	float tone = light_tone(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION);
	float shade = clamp((shade_start - tone) / shade_start, 0.0, 1.0);
	float ink = max(painted, swatch_ink(shade * shade_depth, ink_light, ink_dark));
	DIFFUSE_LIGHT += (paper_color - ink_color) * max(unlit_ink - ink, 0.0);
}
