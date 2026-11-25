shader_type spatial;
// Full-screen brush pass. There are no outlines: shapes are told apart by
// value, distance dissolves into bare paper, and edges are torn the way a
// half-dry brush tears them. Every irregularity is fixed to the surface it
// sits on, so it doesn't slide when the camera turns.
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;

group_uniforms tone;
uniform float exposure = 1.0;
uniform float contrast = 1.15;
// Fewer, flatter washes against smooth shading.
uniform float washes : hint_range(2.0, 10.0) = 5.0;
uniform float wash_hardness : hint_range(0.0, 1.0) = 0.55;
// Where a wash dries, pigment collects along its border.
uniform float pooling : hint_range(0.0, 1.0) = 0.2;

group_uniforms brush;
// Pixels, on a 1080 line screen.
uniform float edge_tear = 7.0;
uniform float dry_rim = 9.0;
uniform float dry_amount : hint_range(0.0, 1.0) = 0.55;
uniform float stroke_size = 3.0;
// Metres over which the brush calms down, so thin distant things stay whole.
uniform float calm_distance = 16.0;
// Paper left bare behind a shape that overlaps another.
uniform float gap_rim : hint_range(0.0, 1.0) = 0.45;

group_uniforms mist;
uniform float mist_start = 3.0;
uniform float mist_distance = 22.0;
uniform float mist_limit : hint_range(0.0, 1.0) = 0.93;
uniform float ground_mist : hint_range(0.0, 1.0) = 0.75;
uniform float ground_mist_height = 0.9;
// Hills stand out of the mist, however far they are.
uniform float hill_strength : hint_range(0.0, 1.0) = 0.4;

group_uniforms hands;
// Anything nearer is the sword: never misted, keeps its painted detail, and
// gets a brush line, since a pale blade on pale paper has no other edge.
uniform float hands_distance = 2.0;
uniform float hands_line : hint_range(0.0, 1.0) = 0.9;

group_uniforms paper;
uniform vec3 ink_color : source_color = vec3(0.035, 0.035, 0.045);
uniform vec3 paper_color : source_color = vec3(0.93, 0.92, 0.89);
uniform float grain = 0.05;
// How far the painting stops short of the edge of the sheet.
uniform float border : hint_range(0.0, 1.0) = 0.35;
// Surfaces more vivid than this keep their colour: the one red.
uniform float keep_color : hint_range(0.0, 1.0) = 0.35;


void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
			mix(mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), f.x),
				mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), f.x),
				mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

// Noise fixed to the world whose grain stays about the same size on screen:
// it crossfades between two sizes as the surface gets nearer or further.
float anchored(vec3 p, float size) {
	float level = log2(max(size, 1e-5));
	float a = exp2(floor(level));
	return mix(noise3(p / a), noise3(p / (a * 2.0) + 17.0), fract(level));
}

vec3 world_at(vec2 uv, mat4 inv_proj, mat4 inv_view) {
	// Sky has no depth, so it gets a far one to hang the noise on.
	float d = max(texture(depth_tex, uv).r, 1e-5);
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return (inv_view * vec4(v.xyz / v.w, 1.0)).xyz;
}

float value_at(vec2 uv) {
	vec3 c = min(textureLod(screen_tex, uv, 0.0).rgb * exposure, vec3(1.0));
	return pow(dot(c, vec3(0.2126, 0.7152, 0.0722)), 1.0 / 2.2);
}

// Each pixel takes the mean of whichever neighbouring quarter is most even,
// which flattens detail into dabs while keeping shapes crisp.
float dabs(vec2 uv, vec2 px) {
	float best = 0.0;
	float least = 1e9;
	for (int q = 0; q < 4; q++) {
		vec2 side = vec2((q & 1) == 0 ? -1.0 : 1.0, (q & 2) == 0 ? -1.0 : 1.0);
		float sum = 0.0;
		float squares = 0.0;
		for (int x = 0; x < 3; x++) {
			for (int y = 0; y < 3; y++) {
				float v = value_at(uv + side * vec2(float(x), float(y)) * 0.5 * px);
				sum += v;
				squares += v * v;
			}
		}
		float mean = sum / 9.0;
		float spread = squares / 9.0 - mean * mean;
		if (spread < least) {
			least = spread;
			best = mean;
		}
	}
	return best;
}


void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	float unit = VIEWPORT_SIZE.y / 1080.0;
	vec2 px = vec2(unit) / VIEWPORT_SIZE;
	float per_px = 2.0 * abs(INV_PROJECTION_MATRIX[1][1]) / 1080.0;

	// Edges belong to whichever surface is in front, so the nearest one in
	// reach decides how this pixel is torn.
	vec3 front = world_at(uv, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	float front_dist = distance(front, eye);
	for (int i = 0; i < 12; i++) {
		float a = float(i) * TAU / 12.0;
		float r = edge_tear * ((i & 1) == 0 ? 1.0 : 0.5);
		vec3 p = world_at(uv + vec2(cos(a), sin(a)) * r * px, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
		float d = distance(p, eye);
		if (d < front_dist * 0.93) {
			front_dist = d;
			front = p;
		}
	}
	float hands = smoothstep(hands_distance, hands_distance * 0.85, front_dist);
	// The sword swings through the world, so on it the noise rides the camera.
	vec3 anchor = mix(front, (VIEW_MATRIX * vec4(front, 1.0)).xyz, step(0.5, hands));
	float grain_size = front_dist * per_px;
	float calm = max(1.0 / (1.0 + front_dist / calm_distance), smoothstep(45.0, 90.0, front_dist) * (1.0 - step(5000.0, front_dist)));
	vec2 tear = vec2(anchored(anchor, grain_size * 14.0), anchored(anchor + 41.0, grain_size * 14.0)) - 0.5;
	tear += 0.6 * (vec2(anchored(anchor + 9.0, grain_size * 4.0), anchored(anchor + 67.0, grain_size * 4.0)) - 0.5);
	uv += tear * edge_tear * mix(calm, 0.3, hands) * px;

	vec3 pos = world_at(uv, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	float dist = distance(pos, eye);
	// Beside the sword is still the world behind it.
	hands = smoothstep(hands_distance, hands_distance * 0.85, dist);
	bool sky = texture(depth_tex, uv).r < 1e-6;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(texture(normal_tex, uv).xyz * 2.0 - 1.0, 0.0)).xyz);

	// How much of the surroundings lies behind this surface, or in front of it.
	float open = 0.0;
	float covered = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * TAU / 8.0 + 0.4;
		float r = dry_rim * mix(calm, 0.3, step(0.001, hands)) * ((i & 1) == 0 ? 1.0 : 0.55);
		vec2 o = uv + vec2(cos(a), sin(a)) * r * px;
		vec3 p = world_at(o, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
		// Off the surface's own plane, or a floor seen edge-on would count.
		float behind = -dot(p - pos, n);
		open += step(dist * 0.03, behind) * 0.125;
		covered += step(dist * 0.08, dist - distance(p, eye)) * step(dist * 0.03, abs(behind)) * 0.125;
	}

	float v = mix(dabs(uv, px * stroke_size), value_at(uv), hands);
	v = clamp((v - 0.5) * contrast + 0.5, 0.0, 1.0);

	float size = dist * per_px;
	float bloom = anchored(pos + 5.0, size * 60.0) * 0.65 + anchored(pos + 23.0, size * 18.0) * 0.35;
	// Long along the vertical, so it reads as bristles dragged downward.
	float bristle = anchored(vec3(pos.x, pos.y * 0.1, pos.z) + 3.0, size * 3.0) * 0.6
			+ anchored(pos + 31.0, size * 3.0) * 0.4;

	if (!sky) {
		v = mix(v, 1.0, covered * gap_rim);
		// Mist: thick along the ground, broken up like a wet wash.
		float far = 1.0 - exp(-max(dist - mist_start, 0.0) / mist_distance);
		float low = smoothstep(ground_mist_height * (0.4 + bloom * 1.6), 0.0, pos.y) * ground_mist;
		low *= smoothstep(2.0, 9.0, dist);
		// Hills are dark at the crest and lost at the foot.
		float foot = smoothstep(dist * 0.12, -dist * 0.01, pos.y + (bloom - 0.5) * dist * 0.1);
		float hill = smoothstep(45.0, 90.0, dist);
		low = max(low, foot * hill);
		far = mix(far, 1.0 - hill_strength, hill);
		float mist = min(1.0 - (1.0 - far) * (1.0 - low), mix(mist_limit, 1.0, low));
		v = mix(v, 1.0, mist * (1.0 - hands));
	}

	// Washes: flat steps of value with wandering, slightly darker borders.
	float s = v * washes + (bloom - 0.5) * 1.1;
	float f = fract(s);
	float soft = mix(0.5, 0.06, wash_hardness);
	float stepped = (floor(s) + smoothstep(0.5 - soft, 0.5 + soft, f)) / washes;
	float rim = smoothstep(0.16, 0.0, abs(f - 0.36)) * smoothstep(0.97, 0.75, v) * smoothstep(0.05, 0.2, v);
	stepped -= rim * pooling * 0.2;
	float ink = 1.0 - clamp(mix(stepped, v, hands), 0.0, 1.0);

	// Dry brush: along an outside edge the bristles run out of ink.
	float worn = smoothstep(0.12, 0.6, open) * dry_amount * mix(sqrt(calm), 0.0, hands);
	ink *= 1.0 - smoothstep(1.0 - worn, 1.0 - worn + 0.2, bristle + 0.12) * step(0.01, worn);
	// And in the middle greys it skips a little everywhere.
	float mid = smoothstep(0.15, 0.45, ink) * smoothstep(0.95, 0.6, ink);
	ink *= 1.0 - mid * dry_amount * 0.35 * smoothstep(0.55, 0.8, bristle);

	float line = smoothstep(0.1, 0.35, open) * (0.65 + 0.35 * smoothstep(0.25, 0.5, bristle));
	ink = max(ink, line * hands * hands_line);

	// The sheet itself, which does belong to the screen.
	vec2 sheet = SCREEN_UV * VIEWPORT_SIZE / unit;
	float fibre = noise3(vec3(sheet * 0.9, 1.0)) * 0.5 + noise3(vec3(sheet * vec2(0.03, 0.15), 4.0)) * 0.5;
	ink *= 1.0 + (fibre - 0.5) * 0.3 * (1.0 - ink);
	vec2 from_edge = min(SCREEN_UV, 1.0 - SCREEN_UV) * VIEWPORT_SIZE / VIEWPORT_SIZE.y;
	float torn_edge = noise3(vec3(sheet * 0.012, 8.0)) * 0.6 + noise3(vec3(sheet * 0.06, 2.0)) * 0.3;
	float bare = 1.0 - smoothstep(0.0, 0.22, min(from_edge.x, from_edge.y) - torn_edge * 0.07 + 0.03);
	ink *= 1.0 - bare * border * (1.0 - hands);

	vec3 paper = paper_color * (1.0 - grain * (fibre - 0.3));
	vec3 color = mix(paper, ink_color, 1.0 - pow(1.0 - clamp(ink, 0.0, 1.0), 2.2));
	vec3 raw = textureLod(screen_tex, uv, 0.0).rgb;
	float top = max(raw.r, max(raw.g, raw.b));
	float vivid = (top - min(raw.r, min(raw.g, raw.b))) / max(top, 0.02);
	color = mix(color, raw / max(top, 0.001) * max(top, 0.55), smoothstep(keep_color, keep_color + 0.2, vivid));
	ALBEDO = color;
}
