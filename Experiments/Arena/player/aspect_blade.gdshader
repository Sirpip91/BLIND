shader_type spatial;
// The player's katana, with every colour it has been given painted into it:
// Core's ink blade with more on its palette.
// The katana painted as one loaded brush stroke: ink along the spine, a
// wandering wet border where the temper line would be, bare paper at the
// edge. Ink is a supply, thrown off by a swing and soaking back up from the
// guard. Noise is fixed to the blade, so nothing crawls while it's still.
render_mode unshaded, cull_disabled;

uniform sampler2D painting : source_color, filter_linear_mipmap, repeat_disable, hint_default_white;

// How far up the blade the ink has soaked; past 1 is full to the tip.
uniform float fill = 1.3;
// Ink thrown toward the edge (+) or the spine (-) by a turn of the wrist.
uniform float slosh = 0.0;
// Where along the blade the wet highlight sits.
uniform float glint = 0.5;

// In the player's hands rather than someone else's: see wash.gdshader.
uniform bool held = false;

group_uniforms ink;
uniform float border = 0.5;
uniform float border_wander = 0.62;
uniform float wet_black : hint_range(0.0, 1.0) = 0.05;
uniform float wet_grey : hint_range(0.0, 1.0) = 0.34;
uniform float pale_wash : hint_range(0.0, 1.0) = 0.72;
uniform float dryness : hint_range(0.0, 1.0) = 0.5;
uniform float glint_strength : hint_range(0.0, 1.0) = 0.8;

group_uniforms color;
// Colour bleeding into the ink when the sword is hot.
uniform vec3 tint : source_color = vec3(0.85, 0.05, 0.04);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
uniform float sweep : hint_range(0.0, 1.0) = 1.0;

// What it's been given, how strongly each shows, and how they're laid on.
uniform vec3 colors[4] : source_color;
uniform float strengths[4];
uniform int color_count = 0;
uniform int style = 0;
// How far the paint has run, which goes faster for being swung.
uniform float flow = 0.0;
// How far up the blade the newest of them has got.
uniform float newest : hint_range(0.0, 1.0) = 1.0;
// A wave of light through all of it, from the guard to the point: 1 to 0.
uniform float surge : hint_range(0.0, 1.0) = 0.0;
// How hard it's being swung.
uniform float heat : hint_range(0.0, 1.0) = 0.0;

// Blood on it, from the guard (clean so far) to the point, running that way.
uniform vec3 blood_color : source_color = vec3(0.62, 0.008, 0.014);
uniform float blood : hint_range(0.0, 1.0) = 0.0;
uniform float blood_clean = 0.0;
uniform float blood_seed = 0.0;
uniform float blood_run = 0.0;

group_uniforms blade;
// The blade's shape in the model: the spine is a shallow curve in x over y.
uniform float blade_from = 0.065;
uniform float blade_to = 0.757;
uniform float spine_low = -0.016;
uniform float spine_mid = 0.41;
uniform float spine_curve = 0.147;
uniform float blade_width = 0.027;
uniform float tip_length = 0.06;

varying vec3 local_pos;


void vertex() {
	local_pos = VERTEX;
}


// Whole numbers, because the usual fract() hash rounds differently from one
// cell to the next here and leaves a visible step.
float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(p) + ivec2(32768));
	uint h = q.x * 374761393u + q.y * 668265263u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return float((h ^ (h >> 16u)) & 65535u) / 65535.0;
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}


float cloud(vec2 p) {
	return noise(p) * 0.6 + noise(p * 2.3 + 7.0) * 0.28 + noise(p * 5.1 + 3.0) * 0.12;
}

vec3 pigment(int i, int n) {
	i = clamp(i, 0, n - 1);
	return mix(vec3(0.004), colors[i], strengths[i]);
}

// Wet into wet: what's left is what neither of them takes out of the light.
vec3 wet(vec3 a, vec3 b, float k) {
	return exp(mix(log(a + 0.015), log(b + 0.015), k));
}

// Each takes a length of the blade, and runs into the next. The tide between
// them goes up and down it.
vec4 bled(float t, float u, float y, int n) {
	float tide = 0.75 * sin(flow * 0.6) + 0.35 * sin(flow * 1.1 + t * 6.0);
	float x = t * float(n) + tide * smoothstep(-0.1, 0.2, t) * smoothstep(1.1, 0.8, t);
	x += (cloud(vec2(u * 1.6 + flow * 0.12, y * 15.0 - flow * 0.9)) - 0.5) * 1.5 + (u - 0.4) * 0.55;
	x = clamp(x, 0.0, float(n) - 0.001);
	int i = int(floor(x));
	return vec4(wet(pigment(i, n), pigment(i + 1, n), smoothstep(0.5, 1.0, fract(x)) * step(float(i), float(n) - 1.5)), 0.94);
}

// Floated on water and drawn through with a hair, the water still moving.
vec4 marbled(float t, float u, float y, int n) {
	vec2 p = vec2(u * 0.8, y * 5.5 - flow * 0.22);
	vec2 q = p + 1.3 * vec2(cloud(p * 1.4 + vec2(flow * 0.13, 0.0)), cloud(p * 1.4 + vec2(19.0, flow * 0.17)));
	float s = cloud(q * 1.5 + vec2(flow * 0.07, 3.0)) * float(n) * 2.1 + float(n) * 0.5;
	float f = fract(s);
	float line = smoothstep(0.13, 0.04, min(f, 1.0 - f));
	return vec4(mix(pigment(int(floor(s)) % n, n), vec3(0.004), line), 0.98);
}

// One stroke on top of another. There's always another on its way up the
// blade, and the oldest are always drying off it.
vec4 painted_over(float t, float u, float y, float border_at, int n) {
	vec4 paint = vec4(pigment(0, n), 0.9);
	if (n < 2) {
		// The one colour, gone over again and again.
		float head = fract(flow * 0.16);
		float gloss = smoothstep(0.16, 0.0, abs(t - head * 1.3 + 0.1) + (noise(vec2(u * 18.0, y * 5.0)) - 0.5) * 0.12);
		paint.rgb *= mix(0.72, 1.35, gloss);
		return paint;
	}
	float beat = flow * 0.55;
	float last = floor(beat);
	int layers = n + 2;
	for (int k = layers - 1; k >= 0; k--) {
		float which = last - float(k) + 64.0;
		float age = (beat - last + float(k)) / float(layers);
		float from = 0.85 * hash(vec2(which, 5.0)) - 0.22;
		float s = (t - from) / (0.4 + 0.2 * hash(vec2(which, 9.0)));
		float drawn = k == 0 ? (beat - last) * 1.25 : 1.25;
		if (s < 0.0 || s > min(drawn, 1.0)) {
			continue;
		}
		int i = int(which) % n;
		float middle = border_at * (0.3 + 0.45 * hash(vec2(which, 3.0))) + (noise(vec2(y * 8.0, which * 9.0)) - 0.5) * 0.2;
		float wide = 0.34 * pow(sin(PI * pow(clamp(s, 0.001, 1.0), 0.6)), 0.6);
		float hairs = noise(vec2(u * 22.0 + which * 11.0, y * 6.0)) * 0.6 + noise(vec2(u * 50.0, y * 13.0 + which)) * 0.4;
		float dry = max(s * 0.85 - 0.28, smoothstep(0.45, 1.0, age) * 1.1 - 0.2);
		float on = smoothstep(wide, wide - 0.07, abs(u - middle) + (hairs - 0.5) * 0.12) * smoothstep(dry, dry + 0.16, hairs);
		float rim = on * smoothstep(wide - 0.16, wide - 0.03, abs(u - middle));
		paint.rgb = mix(paint.rgb, pigment(i, n) * (1.0 - 0.55 * rim), on);
		paint.a = max(paint.a, on);
	}
	return paint;
}

// All of them on the brush at once, drawn along in the hairs.
vec4 brushful(float t, float u, float y, float border_at, int n) {
	float run = y * 3.5 - flow * 0.5;
	float lane = u / max(border_at, 0.2) * float(n) + (noise(vec2(u * 14.0, run)) - 0.5) * 1.0 + (noise(vec2(3.0, y * 7.0 - flow * 0.9)) - 0.5) * 1.7;
	float streak = noise(vec2(u * 30.0, y * 5.0 - flow * 1.1)) * 0.6 + noise(vec2(u * 60.0, y * 11.0 - flow * 2.0)) * 0.4;
	return vec4(pigment(int(floor(lane)), n) * mix(0.55, 1.0, smoothstep(0.2, 0.6, streak)), smoothstep(0.16, 0.3, streak));
}

// Stirred together, not quite all the way, and still being stirred.
vec4 stirred(float t, float u, float y, int n) {
	vec3 sum = vec3(0.0);
	float all = 0.0;
	for (int i = 0; i < n; i++) {
		vec2 drift = vec2(sin(flow * 0.31 + float(i) * 2.1), cos(flow * 0.23 + float(i) * 1.7)) * 0.6;
		float much = pow(cloud(vec2(u * 1.3 + float(i) * 13.0, y * 9.0 + float(i) * 5.0 - flow * 0.3) + drift), 7.0) + 0.0004;
		sum += log(pigment(i, n) + 0.012) * much;
		all += much;
	}
	vec3 mixed = exp(sum / all);
	// Two pigments together go dull; a little of that is enough.
	float grey = dot(mixed, vec3(0.33));
	return vec4(max(mix(vec3(grey), mixed, 1.45), 0.0), 0.96);
}

// A black blade with shots of colour driven up it, all the one way: a hard
// bright head, and a tail the black gets back into.
vec4 splashed(float t, float u, float y, int n) {
	vec3 paint = vec3(0.0);
	float shown = 0.0;
	// Curled a little by the black they go through.
	float curl = (cloud(vec2(u * 2.0 + 5.0, y * 11.0 - flow * 0.5)) - 0.5);
	for (int lane = 0; lane < 3; lane++) {
		float l = float(lane);
		float along = y * 5.2 - flow * (0.42 + 0.17 * hash(vec2(l, 2.0))) + l * 17.0 + curl * 0.35;
		for (int k = 0; k <= 1; k++) {
			float shot = floor(along) + float(k);
			vec2 id = vec2(shot, l * 31.0);
			float lucky = hash(id);
			// More of them the harder it's swung.
			float much = smoothstep(lucky - 0.12, lucky + 0.06, mix(0.64, 1.05, heat));
			if (much <= 0.0) {
				continue;
			}
			float head = shot + 0.15 + 0.35 * hash(id + 3.0);
			float tail = mix(0.45, 0.95, hash(id + 7.0)) * mix(0.8, 1.15, heat);
			// 0 at the head, 1 where the last of it goes.
			float s = (head - along) / tail;
			if (s < -0.12 || s > 1.0) {
				continue;
			}
			float middle = 0.08 + 0.22 * l + 0.14 * (hash(id + 11.0) - 0.5) + curl * 0.3;
			float wide = mix(0.14, 0.27, hash(id + 13.0)) * much * mix(1.0, 1.25, heat) * (s < 0.0 ? sqrt(max(1.0 + s / 0.12, 0.0)) : 1.0 - 0.35 * s);
			float hairs = noise(vec2(u * 26.0 + l * 9.0, along * 2.2)) * 0.6 + noise(vec2(u * 60.0, along * 5.0 + l)) * 0.4;
			float body = smoothstep(wide, wide - 0.05, abs(u - middle) + (hairs - 0.5) * 0.16 * max(s, 0.0));
			// The black eats it from behind, hair by hair.
			body *= smoothstep(s * 1.05 - 0.22, s * 1.05 - 0.02, hairs + 0.06);
			if (body <= 0.0) {
				continue;
			}
			vec3 hue = pigment(int(floor(hash(id + 19.0) * 0.999 * float(n))), n);
			float hot = 1.0 - smoothstep(0.0, 0.3, max(s, 0.0));
			vec3 lit = mix(hue * mix(0.85, 0.16, smoothstep(0.1, 1.0, s)), hue * 1.35 + 0.05 * hot, hot);
			// A lip where it piles up.
			lit = mix(lit, sqrt(max(hue, 0.0)), 0.55 * smoothstep(0.05, 0.0, abs(s)) * (0.4 + 0.6 * heat));
			paint = mix(paint, lit, body);
			shown = max(shown, body);
		}
	}
	// Everywhere else it's only breathed on.
	vec3 trace = pigment(int(floor(cloud(vec2(1.0, y * 4.0 - flow * 0.3)) * 1.4 * float(n))) % n, n);
	float smoke = smoothstep(0.52, 0.75, cloud(vec2(u * 2.2, y * 9.0 - flow * 0.7))) * mix(0.16, 0.4, heat);
	paint = mix(trace * 0.55, paint, shown);
	return vec4(paint, max(shown, smoke));
}

// In bands along the temper line, each inside the last, rippling like heat.
vec4 tempered(float t, float u, float y, float border_at, int n) {
	float wander = (noise(vec2(y * 21.0 - flow * 1.6, 4.0)) - 0.5) * 0.16 + (noise(vec2(y * 60.0 - flow * 2.6, 9.0)) - 0.5) * 0.07;
	float swell = 1.0 + 0.22 * sin(y * 11.0 - flow * 1.5);
	float lane = (border_at - u + wander) / (0.17 * swell);
	int i = int(floor(lane));
	float f = fract(lane);
	if (lane < 0.0 || i >= n) {
		return vec4(pigment(0, n), lane < 0.0 ? 0.9 : 0.0);
	}
	return vec4(pigment(i, n) * mix(0.35, 1.0, smoothstep(0.0, 0.2, min(f, 1.0 - f))), 0.97);
}


void fragment() {
	float y = local_pos.y;
	float value;
	float bleed = 0.0;
	float deep = 0.0;
	float bloody = 0.0;
	float blood_dark = 0.0;
	vec3 hue = tint;
	if (y > blade_from) {
		float t = (y - blade_from) / (blade_to - blade_from);
		float spine = spine_low + spine_curve * (y - spine_mid) * (y - spine_mid);
		float width = blade_width * sqrt(clamp((blade_to - y) / tip_length, 0.001, 1.0));
		// 0 along the spine, 1 at the cutting edge.
		float u = clamp((spine - local_pos.x) / width, 0.0, 1.0);

		float soak = t + (noise(vec2(u * 3.0, y * 20.0)) - 0.5) * 0.3;
		float soaked = 1.0 - smoothstep(fill - 0.12, fill + 0.08, soak);

		float edge = border + (noise(vec2(y * 15.0, 2.0)) - 0.5) * border_wander
				+ (noise(vec2(y * 55.0, 7.0)) - 0.5) * border_wander * 0.35
				+ (noise(vec2(y * 160.0, u * 4.0)) - 0.5) * border_wander * 0.12;
		edge = (edge + slosh * (0.4 + 0.6 * t)) * mix(0.35, 1.0, soaked);
		// Running out toward the tip, where the brush lifts.
		edge *= 1.0 - 0.35 * smoothstep(0.75, 1.0, t);

		float bristle = noise(vec2(u * 13.0, y * 7.0 + 3.0)) * 0.6 + noise(vec2(u * 30.0, y * 16.0)) * 0.4;
		float dry = dryness * (smoothstep(0.45, 1.0, t) * 0.55 + (1.0 - soaked) * 0.75);
		float loaded = smoothstep(dry, dry + 0.12, bristle + 0.12);

		float body = (1.0 - smoothstep(edge - 0.02, edge + 0.04, u)) * loaded;
		float halo = (1.0 - smoothstep(edge + 0.1, edge + 0.3, u + (bristle - 0.5) * 0.2)) * mix(0.3, 1.0, soaked) * loaded;
		float cloud_value = smoothstep(0.3, 0.75, noise(vec2(u * 1.6, y * 9.0 + 11.0)) * 0.7 + noise(vec2(u * 5.0, y * 30.0)) * 0.3);
		float ink_value = mix(wet_black, wet_grey, cloud_value * (0.35 + 0.65 * t));
		// Pigment gathers where the wet border stops.
		float pool = smoothstep(0.09, 0.0, abs(u - edge + 0.04)) * soaked * 0.8;
		ink_value = mix(ink_value, wet_black, pool);

		value = mix(1.0, pale_wash, halo);
		value = mix(value, ink_value, body);

		float shine = smoothstep(0.07, 0.0, abs(u - 0.2 - (noise(vec2(y * 18.0, 5.0)) - 0.5) * 0.1));
		shine *= smoothstep(0.22, 0.0, abs(t - glint)) * step(0.45, noise(vec2(u * 8.0, y * 45.0)) + 0.3 * soaked);
		value = mix(value, 1.0, shine * glint_strength * body);

		float charged = 1.0 - smoothstep(sweep * 1.1 - 0.1, sweep * 1.1, t);
		// The spine stays ink; colour floods the border and runs back in streaks.
		float flood = smoothstep(edge - 0.2, edge - 0.06, u + (bristle - 0.5) * 0.45);
		bleed = max(body * flood * flood, halo * (1.0 - body) * 0.85) * charged * tint_amount;
		deep = body * (1.0 - cloud_value) * 0.45;
		float front = newest * 1.35 - 0.15 + (noise(vec2(u * 16.0, y * 5.0)) - 0.5) * 0.2;
		int n = color_count - (newest < 1.0 && t > front ? 1 : 0);
		if (n > 0) {
			vec4 paint;
			switch (style) {
				case 0: paint = bled(t, u, y, n); break;
				case 1: paint = marbled(t, u, y, n); break;
				case 2: paint = painted_over(t, u, y, edge, n); break;
				case 3: paint = brushful(t, u, y, edge, n); break;
				case 4: paint = stirred(t, u, y, n); break;
				case 5: paint = splashed(t, u, y, n); break;
				default: paint = tempered(t, u, y, edge, n); break;
			}
			hue = paint.rgb;
			// What gets past the border is less where the black's the point of it.
			bleed = max(body * paint.a, halo * (1.0 - body) * (style == 5 ? 0.85 * step(0.5, paint.a) : 0.7 * paint.a)) * charged;
			deep *= 0.35;
			// The highlight stays wet paint's, not paper's.
			bleed *= 1.0 - shine * glint_strength * 0.7;
			// Thin in places, so the ink it's laid on shows through.
			float grain = noise(vec2(u * 8.0, y * 6.0 + 40.0)) * 0.5 + noise(vec2(u * 21.0, y * 15.0)) * 0.32 + noise(vec2(u * 50.0, y * 45.0)) * 0.18;
			float thin = smoothstep(0.56, 0.7, grain + 0.05 * smoothstep(0.3, 0.0, u) + 0.04 * t * t);
			bleed *= 1.0 - (style == 5 ? 0.35 : 0.8) * thin * body;
			hue *= mix(0.8, 1.15, smoothstep(0.25, 0.6, noise(vec2(u * 3.0, y * 22.0 + 9.0))));
			hue *= 1.0 - 0.45 * pool;
			float wave = smoothstep(0.22, 0.0, abs(t - (1.0 - surge) * 1.3 + 0.1)) * step(0.001, surge);
			hue = mix(hue * (1.0 + 0.35 * surge), sqrt(max(hue, 0.0)) * 1.1, wave * 0.8);
			bleed = max(bleed, wave * body);
			float lip = smoothstep(0.07, 0.0, abs(t - front)) * step(newest, 0.999);
			hue = mix(hue, sqrt(max(colors[color_count - 1], 0.0)), lip * 0.7);
		}
		if (blood > 0.0) {
			// Most of it out where the cutting's done, in runs along the steel and
			// splashes across it.
			float slip = blood_run * 0.012;
			float runs = noise(vec2(u * 7.0 + blood_seed, (y - slip) * 9.0)) * 0.5 + noise(vec2(u * 17.0 + blood_seed, (y - slip * 2.0) * 24.0)) * 0.3 + noise(vec2(u * 3.0, y * 60.0 + blood_seed)) * 0.2;
			float reach = smoothstep(0.0, 0.55, t) * 0.3 + 0.12 * smoothstep(0.35, 1.0, u);
			float much = blood * 0.62 + reach * smoothstep(0.0, 0.4, blood) - 0.14;
			float line = 1.0 - much;
			bloody = smoothstep(line, line + 0.035, runs) * step(blood_clean, t + (noise(vec2(u * 9.0, y * 12.0)) - 0.5) * 0.12);
			blood_dark = smoothstep(0.1, 0.0, runs - line) * 0.5 + 0.25 * noise(vec2(u * 5.0, y * 40.0));
		}
	} else {
		// Black lacquer, with the painted wrap showing as scraped-back paper.
		float lines = clamp(1.0 - texture(painting, UV).r / 0.8, 0.0, 1.0);
		// The guard's texture is nearly all lines; left light it reads as metal.
		lines *= 1.0 - 0.8 * smoothstep(-0.01, 0.015, y);
		float worn = noise(vec2(local_pos.x * 90.0, y * 35.0)) * 0.6 + noise(vec2(local_pos.x * 300.0, y * 120.0)) * 0.4;
		value = mix(wet_black, 0.22, smoothstep(0.5, 0.8, worn));
		value = mix(value, 0.62, lines * smoothstep(0.25, 0.55, worn + 0.15));
	}
	ROUGHNESS = held ? 0.0 : 1.0;
	vec3 finished = mix(vec3(pow(value, 2.2)), hue * (1.0 - deep), bleed);
	ALBEDO = mix(finished, blood_color * (1.15 - blood_dark), bloody);
}
