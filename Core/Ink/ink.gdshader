shader_type spatial;
// Full-screen ink pass. Reads the lit scene's brightness and redraws it as
// pen hatching, so materials stay plain and every imported asset gets the
// look for free. Strokes are laid out in world space (rebuilt from depth)
// rather than screen space, so they stick to surfaces instead of sliding
// over them as the camera moves.
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;

group_uniforms tone;
uniform float exposure = 1.1;
uniform float contrast = 1.25;

group_uniforms hatching;
// Off: materials draw their own strokes and this pass only adds outlines
// and paper. On: everything is redrawn with generated strokes.
uniform bool procedural_hatching = false;
uniform float stroke_spacing = 0.06;
uniform float stroke_wobble = 0.45;
uniform float stroke_breakup = 0.5;

group_uniforms outline;
uniform float outline_px = 1.6;
uniform float depth_edge = 0.03;
uniform float normal_edge = 0.35;
// Distant detail fades into the paper, like an illustrator leaving the
// background loose.
uniform float fade_start = 25.0;
uniform float fade_end = 90.0;

group_uniforms boil;
// Classic hand-drawn boil: cycle a few slightly different "drawings".
uniform float boil_fps = 8.0;
uniform float boil_frames = 3.0;
uniform float boil_amount = 1.0;
// Seconds to use in place of the real clock, so a recording flickers at the
// right speed however long each frame takes to save. Negative: use TIME.
uniform float boil_clock = -1.0;

group_uniforms paper;
uniform vec3 ink_color : source_color = vec3(0.05, 0.05, 0.06);
uniform vec3 paper_color : source_color = vec3(0.95, 0.94, 0.91);
uniform float paper_grain = 0.07;
uniform float vignette = 0.35;
// 0 keeps the game black and white even under warm lamps and tinted fog.
uniform float saturation : hint_range(0.0, 1.0) = 0.0;

group_uniforms impact;
// Driven by impact_frames.gd on a hit, anime style: a silhouette frame, a
// negative frame, burst lines and a punch-in zoom toward the hit.
// 0 = normal, 1 = silhouette (black shapes on white), 2 = negative.
uniform int impact_mode = 0;
uniform float impact_lines = 0.0;
uniform vec2 impact_center = vec2(0.5);
uniform float impact_seed = 0.0;
// View distance to the hit; the silhouette frame blacks out what's in front of it.
uniform float impact_depth = 5.0;
// How far past the hit still counts as in front.
uniform float impact_reach = 1.0;
uniform float impact_rays = 160.0;
// 0 = straight rays, 1 = focus lines from the edges, 2 = spiral, 3 = jagged.
uniform int impact_style = 0;
uniform float impact_twist = 0.0;
uniform vec3 impact_color : source_color = vec3(1.0);
uniform float impact_zoom = 0.0;
// How much colour the punch-in splits off; 0 keeps a zoom black and white.
uniform float impact_split = 1.0;
uniform vec3 impact_fringe : source_color = vec3(0.85, 0.08, 0.06);
// The silhouette frame's two flat colours.
uniform vec3 impact_shape : source_color = vec3(0.05, 0.05, 0.06);
uniform vec3 impact_back : source_color = vec3(0.95, 0.94, 0.91);
// Share of burst lines drawn in impact_color.
uniform float impact_colored = 0.3;


void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// One set of parallel strokes. `weight` 0..1 fattens them as the tone
// darkens, which hides the step where a new layer starts.
float strokes(vec2 uv, float angle, float spacing, float weight, float seed) {
	vec2 dir = vec2(cos(angle), sin(angle));
	vec2 p = vec2(dot(uv, dir), dot(uv, vec2(-dir.y, dir.x))) / spacing;
	float row = floor(p.y);
	// Per-row wobble and gaps, so it reads as separate pen strokes rather
	// than a printed pattern.
	p.y += (vnoise(vec2(p.x * 0.12, row * 1.7 + seed)) - 0.5) * stroke_wobble;
	float gap = vnoise(vec2(p.x * 0.06 + seed * 7.3, row * 3.1));
	float d = abs(fract(p.y) - 0.5);
	float w = mix(0.06, 0.38, weight);
	float aa = fwidth(p.y) * 0.75;
	float line = 1.0 - smoothstep(w - aa, w + aa, d);
	float present = smoothstep(stroke_breakup * 0.6, stroke_breakup * 0.6 + 0.15, gap + weight * 0.5);
	return line * present * smoothstep(0.0, 0.15, weight);
}

float layer(float tone, float start) {
	return clamp((start - tone) / 0.22, 0.0, 1.0);
}

float hatch(vec2 uv, float tone, float seed) {
	float ink = strokes(uv, 0.785, stroke_spacing, layer(tone, 0.85), seed);
	ink = max(ink, strokes(uv, -0.785, stroke_spacing, layer(tone, 0.6), seed + 11.0));
	ink = max(ink, strokes(uv, 0.15, stroke_spacing * 0.7, layer(tone, 0.38), seed + 23.0));
	ink = max(ink, strokes(uv, 1.65, stroke_spacing * 0.5, layer(tone, 0.18), seed + 37.0));
	return ink;
}

float linear_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	if (d < 1e-6) {
		return 1e4;
	}
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec3 view_normal(vec2 uv) {
	return normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0);
}


void fragment() {
	float frame = mod(floor((boil_clock < 0.0 ? TIME : boil_clock) * boil_fps), max(boil_frames, 1.0));
	float seed = frame * 17.0 * boil_amount;
	vec2 jitter = (vec2(hash(vec2(frame, 1.0)), hash(vec2(frame, 2.0))) - 0.5) * boil_amount;

	vec2 uv = SCREEN_UV;
	// Punch-in: the whole frame scales toward the hit.
	uv = impact_center + (uv - impact_center) / (1.0 + impact_zoom);
	float raw_depth = texture(depth_tex, uv).r;
	bool sky = raw_depth < 1e-6;

	float ink = 0.0;
	if (!sky && procedural_hatching) {
		vec4 view = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, raw_depth, 1.0);
		view.xyz /= view.w;
		vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
		vec3 n = normalize((INV_VIEW_MATRIX * vec4(view_normal(uv), 0.0)).xyz);

		vec3 lit = texture(screen_tex, uv).rgb;
		float lum = dot(lit, vec3(0.2126, 0.7152, 0.0722)) * exposure;
		float tone = pow(clamp(lum, 0.0, 1.0), 1.0 / 2.2);
		tone = clamp((tone - 0.5) * contrast + 0.5, 0.0, 1.0);

		world += vec3(jitter.x, jitter.y, -jitter.x) * stroke_spacing * 0.5;
		// Sharp triplanar weights so curved surfaces mostly use one plane
		// instead of a muddy blend of three.
		vec3 w = pow(abs(n), vec3(8.0));
		w /= w.x + w.y + w.z;
		ink = hatch(world.zy, tone, seed) * w.x
				+ hatch(world.xz, tone, seed + 5.0) * w.y
				+ hatch(world.xy, tone, seed + 9.0) * w.z;
	}

	// Outlines from depth jumps (silhouettes) and normal changes (creases).
	vec2 px = outline_px / VIEWPORT_SIZE;
	px *= 1.0 + (vnoise(uv * 40.0 + seed) - 0.5) * 0.8 * boil_amount;
	float dc = linear_depth(uv, INV_PROJECTION_MATRIX);
	vec3 nc = view_normal(uv);
	// Surfaces seen edge-on have big depth steps between neighbouring pixels
	// without being an edge, so the floor would ink itself near the horizon.
	vec4 vp = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, raw_depth, 1.0);
	float facing = abs(dot(nc, normalize(-vp.xyz / vp.w)));
	float depth_thr = sky ? depth_edge : depth_edge / max(facing, 0.05);
	float edge = 0.0;
	vec2 offsets[4] = { vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y) };
	for (int i = 0; i < 4; i++) {
		vec2 o = uv + offsets[i];
		float dn = linear_depth(o, INV_PROJECTION_MATRIX);
		edge = max(edge, step(depth_thr, abs(dn - dc) / min(dc, dn)));
		if (!sky && dn < 1e4) {
			edge = max(edge, step(normal_edge, 1.0 - dot(nc, view_normal(o))));
		}
	}
	ink = max(ink, edge);
	ink *= 1.0 - smoothstep(fade_start, fade_end, min(dc, 1e3));

	vec2 grain_uv = uv * VIEWPORT_SIZE;
	float grain = vnoise(grain_uv * 0.7) * 0.6 + vnoise(grain_uv * 0.05) * 0.4;
	vec3 base = procedural_hatching ? paper_color : min(texture(screen_tex, uv).rgb, vec3(1.0)) * paper_color;
	base = mix(vec3(dot(base, vec3(0.2126, 0.7152, 0.0722))), base, saturation);
	base *= 1.0 - paper_grain * grain;
	float vig = 1.0 - vignette * pow(length(uv - 0.5) * 1.3, 2.5);

	vec3 color = mix(base, ink_color, clamp(ink, 0.0, 1.0)) * vig;
	vec2 aspect = vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);

	if (impact_mode == 1) {
		// Everything up to just past the hit becomes a flat black shape.
		color = (!sky && dc < impact_depth + impact_reach) ? impact_shape : impact_back;
	} else if (impact_mode == 2) {
		color = paper_color + ink_color - color;
	}

	// Only on normal frames: it samples the scene, not the silhouette or negative.
	if (impact_zoom > 0.0 && impact_mode == 0) {
		// A red ghost of the frame pulled out along the zoom, fringing every
		// edge, so the punch-in has a colour kick in a black-and-white world.
		vec2 split = (uv - impact_center) * impact_zoom * 0.12 * impact_split;
		float ghost = dot(min(texture(screen_tex, uv + split).rgb, vec3(1.0)), vec3(0.333));
		float here = dot(min(texture(screen_tex, uv).rgb, vec3(1.0)), vec3(0.333));
		float fringe = clamp(abs(ghost - here) * 1.6, 0.0, 1.0);
		color = mix(color, impact_fringe, fringe * 0.85);
	}

	if (impact_lines > 0.0) {
		vec2 d = (uv - impact_center) * aspect;
		float r = length(d);
		float angle = atan(d.y, d.x) / TAU + 0.5;
		if (impact_style == 2) {
			angle += impact_twist * r;
		}
		float around = angle * impact_rays;
		float ray_id = floor(around);
		float pick = hash(vec2(ray_id, impact_seed));
		// Each ray starts its own distance out, leaving a clear eye with a
		// ragged edge, and only some angles get a ray at all.
		float eye = impact_style == 1 ? mix(0.38, 0.65, hash(vec2(ray_id, impact_seed + 3.1)))
				: mix(0.08, 0.5, hash(vec2(ray_id, impact_seed + 3.1))) * (1.5 - impact_lines * 0.7);
		float width = mix(0.1, 0.45, pick) * smoothstep(eye, eye + 0.6, r) * 2.0;
		if (impact_style == 1) {
			width *= 0.5;
		}
		float offset = fract(around) - 0.5;
		if (impact_style == 3) {
			// Zigzag along the ray, like spikes on a comic starburst.
			offset += 0.35 * (abs(fract(r * 9.0 + pick * 3.0) - 0.5) - 0.25);
		}
		float ray = step(abs(offset), width * 0.5) * step(0.4, pick);
		ray *= smoothstep(eye, eye + 0.05, r);
		// Dry-brush break-up so they read as drawn strokes, not vector lines.
		ray *= step(0.25, hash(floor(uv * VIEWPORT_SIZE / 3.0) + ray_id));
		// Most lines take whichever of ink or paper stands out against what's
		// behind them; some burn in the colour of whatever struck.
		float behind = dot(color, vec3(0.2126, 0.7152, 0.0722));
		vec3 line_color = behind < 0.4 ? paper_color : ink_color;
		if (hash(vec2(ray_id, impact_seed + 9.7)) < impact_colored) {
			line_color = impact_color;
		}
		color = mix(color, line_color, ray * impact_lines);
	}

	ALBEDO = color;
}
