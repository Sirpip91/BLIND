shader_type spatial;
// Real-light mode: the hand-drawn ink is just the surface colour and Godot's
// own lighting does the rest, so shadows, falloff into darkness and fog
// light shafts are physical while the drawing itself holds still.
render_mode diffuse_lambert, specular_disabled;

#include "res://Core/Ink/swatches.gdshaderinc"

// Mesh UVs into a painted texture; otherwise a swatch projected in world
// space, for things nobody has painted yet.
uniform bool use_painting = false;
uniform sampler2D painting : source_color, filter_linear_mipmap, hint_default_white;
// Part of the painting to stretch over the mesh UVs, as (x, y, w, h), so one
// drawing from a sheet can dress a mesh that wasn't unwrapped for it.
uniform vec4 painting_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform int swatch_index : hint_range(0, 5) = 0;
// Fades the ink, for big surfaces like floors where full strokes are noise.
uniform float ink_amount : hint_range(0.0, 1.0) = 1.0;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}


void fragment() {
	float ink;
	if (use_painting) {
		ink = sheet_ink(texture(painting, painting_rect.xy + fract(UV) * painting_rect.zw).r);
	} else {
		ink = swatch_at(planar_coords(world_pos, world_normal, 0.0), swatch_rect(swatch_index));
	}
	ALBEDO = mix(paper_color, ink_color, ink * ink_amount);
	ROUGHNESS = 1.0;
}
