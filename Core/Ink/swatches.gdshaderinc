// Shared by the ink materials: samples the hand-drawn swatch sheet and turns
// a light level into layered strokes.

uniform sampler2D swatches : source_color, filter_linear_mipmap, hint_default_white;

group_uniforms swatch_rects;
// Light to dark, as (x, y, w, h) in UV space of the swatch sheet.
uniform vec4 swatch_0 = vec4(0.3906, 0.3906, 0.2148, 0.2148);
uniform vec4 swatch_1 = vec4(0.0537, 0.3906, 0.2148, 0.2148);
uniform vec4 swatch_2 = vec4(0.3906, 0.0537, 0.2148, 0.2148);
uniform vec4 swatch_3 = vec4(0.0537, 0.0537, 0.2148, 0.2148);
uniform vec4 swatch_4 = vec4(0.3906, 0.7227, 0.2148, 0.2148);
uniform vec4 swatch_5 = vec4(0.0537, 0.7227, 0.2148, 0.2148);

group_uniforms ink;
uniform float swatch_size = 2.0;
// The sheets' background grey, so it maps to paper rather than a grey tint.
uniform float sheet_paper = 0.8;
uniform vec3 ink_color : source_color = vec3(0.05, 0.05, 0.06);
// White: the outline pass tints everything to paper, and overlapping lights
// that erase past white simply clip instead of showing as bright strokes.
uniform vec3 paper_color : source_color = vec3(1.0);
group_uniforms;

varying vec3 world_pos;
varying vec3 world_normal;


float sheet_ink(float value) {
	return clamp(1.0 - value / sheet_paper, 0.0, 1.0);
}

float swatch_at(vec2 p, vec4 rect) {
	vec2 uv = rect.xy + fract(p) * rect.zw;
	return sheet_ink(textureGrad(swatches, uv, dFdx(p) * rect.zw, dFdy(p) * rect.zw).r);
}

vec4 swatch_rect(int index) {
	vec4 rects[6] = { swatch_0, swatch_1, swatch_2, swatch_3, swatch_4, swatch_5 };
	return rects[clamp(index, 0, 5)];
}

// Projects onto whichever world plane the surface mostly faces. A hard
// switch rather than a triplanar blend: blended hatching turns to mush, a
// switch reads as a new stroke direction.
vec2 planar_coords(vec3 pos, vec3 normal, float angle) {
	vec3 p = pos / swatch_size;
	vec3 n = abs(normalize(normal));
	vec2 q = (n.x > n.y && n.x > n.z) ? p.zy : ((n.y > n.z) ? p.xz : p.xy);
	return mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * q;
}

// Fills the light and dark swatch inks for light() to pick from.
void sample_swatches(vec3 pos, vec3 normal, float angle, out vec3 light_inks, out vec3 dark_inks) {
	vec2 q = planar_coords(pos, normal, angle);
	light_inks = vec3(swatch_at(q, swatch_0), swatch_at(q, swatch_1), swatch_at(q, swatch_2));
	dark_inks = vec3(swatch_at(q, swatch_3), swatch_at(q, swatch_4), swatch_at(q, swatch_5));
}

// Every stroke from every swatch: the starting point lights erase from, so
// no light level can need a stroke that isn't there to keep.
float all_swatches(vec3 light_inks, vec3 dark_inks) {
	vec3 m = max(light_inks, dark_inks);
	return max(m.x, max(m.y, m.z));
}

// 0 = bare paper, 6 = darkest swatch.
float swatch_ink(float level, vec3 light_inks, vec3 dark_inks) {
	float inks[7] = { 0.0, light_inks.x, light_inks.y, light_inks.z, dark_inks.x, dark_inks.y, dark_inks.z };
	int i = clamp(int(floor(level)), 0, 5);
	float f = level - float(i);
	// The darker swatch layers over the lighter one, like adding strokes to
	// a drawing, rather than cross-fading the two.
	return max(inks[i], inks[i + 1] * smoothstep(0.25, 0.75, f));
}

float light_tone(vec3 normal, vec3 light, vec3 light_color, float attenuation) {
	float energy = dot(light_color / PI, vec3(1.0 / 3.0));
	return clamp(dot(normal, light), 0.0, 1.0) * attenuation * energy;
}
