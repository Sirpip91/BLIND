shader_type spatial;
// The painted sword in red, over its own black shape. Drawn after the ink
// pass so the colour survives the black-and-white filter.
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://Core/Ink/swatches.gdshaderinc"

uniform sampler2D painting : source_color, filter_linear_mipmap, hint_default_white;
// The edge burns hotter, from the sword's own glow map.
uniform sampler2D glow_map : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform vec3 color : source_color = vec3(1.0, 0.06, 0.04);
uniform vec3 edge_color : source_color = vec3(1.0, 0.55, 0.45);
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
// A thin light running up the blade.
uniform float glint : hint_range(0.0, 1.0) = 0.0;
uniform float flare : hint_range(0.0, 1.0) = 0.0;
// The model's lowest and highest points.
uniform float bottom = -0.23;
uniform float top = 0.755;

varying vec3 local_pos;


void vertex() {
	local_pos = VERTEX;
	// A hair off the surface so it never fights the black for depth.
	VERTEX += NORMAL * 0.0005;
}


void fragment() {
	float ink = sheet_ink(texture(painting, UV).r);
	float up = (local_pos.y - bottom) / (top - bottom);
	// Drawn out of the dark from the pommel to the tip.
	float seen = smoothstep(up, up + 0.25, reveal * 1.25) * step(0.001, reveal);
	float at = 1.15 - glint * 1.3;
	float streak = (1.0 - smoothstep(0.0, 0.16, abs(up - at))) * step(0.02, glint);
	// The whole blade shows faintly behind the glint.
	seen = max(seen, smoothstep(0.0, 0.6, glint) * 0.4);
	vec3 red = mix(color, color * 0.06, ink);
	red = mix(red, edge_color, texture(glow_map, UV).r);
	ALBEDO = mix(red, vec3(1.0), max(flare * 0.8, streak * 0.6));
	ALPHA = clamp(max(seen, streak), 0.0, 1.0);
}
