shader_type spatial;
// Any painted skin, brought down to how much ink it is.
render_mode diffuse_lambert, specular_disabled, cull_disabled;

uniform sampler2D painting : source_color, filter_linear_mipmap, hint_default_white;
// What the darkest and lightest of the painting come out as.
uniform float dark : hint_range(0.0, 1.0) = 0.0;
uniform float light : hint_range(0.0, 1.0) = 0.65;
// And how much of the painting's own range counts as dark and light.
uniform float dark_from : hint_range(0.0, 1.0) = 0.02;
uniform float light_from : hint_range(0.0, 1.0) = 0.4;


void fragment() {
	float value = dot(texture(painting, UV).rgb, vec3(0.2126, 0.7152, 0.0722));
	ALBEDO = vec3(mix(dark, light, smoothstep(dark_from, light_from, value)));
	ROUGHNESS = 1.0;
}
