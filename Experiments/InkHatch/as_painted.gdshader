shader_type spatial;
// The texture exactly as drawn, unlit, with the sheet's grey background
// swapped for the same paper as everything else.
render_mode unshaded;

uniform sampler2D albedo : source_color, filter_linear_mipmap, hint_default_white;
uniform float sheet_paper = 0.8;
uniform vec3 ink_color : source_color = vec3(0.05, 0.05, 0.06);
// White: the outline pass tints everything to paper.
uniform vec3 paper_color : source_color = vec3(1.0);


void fragment() {
	float ink = clamp(1.0 - texture(albedo, UV).r / sheet_paper, 0.0, 1.0);
	ALBEDO = mix(paper_color, ink_color, ink);
}
