shader_type spatial;
// A stand-in mask drawn straight onto a sphere: pale, still, and almost
// without expression.
render_mode unshaded;

// A mask is paper; a face is darker.
uniform float paper : hint_range(0.0, 1.0) = 0.93;

varying vec3 at;


void vertex() {
	at = VERTEX;
}


void fragment() {
	vec2 p = at.xy / 0.125;
	float front = step(at.z, 0.02);
	vec2 m = vec2(abs(p.x), p.y);
	// Two narrow eyes, looking slightly down, and a line of a mouth.
	float lid = m.x - 0.36;
	vec2 e = vec2(lid, m.y - 0.16 - lid * 0.12 + lid * lid * 1.2);
	float eye = step(length(e * vec2(1.0, 4.6)), 0.2);
	float brow = smoothstep(0.09, 0.0, abs(m.y - 0.62)) * smoothstep(0.16, 0.0, abs(m.x - 0.34)) * 0.35;
	float nose = smoothstep(0.03, 0.01, abs(m.x - 0.09)) * step(-0.24, p.y) * step(p.y, -0.1) * 0.7;
	float mouth = step(abs(p.y + 0.5 - m.x * m.x * 0.3), 0.035 - m.x * 0.07) * step(m.x, 0.34);
	float value = mix(paper, 0.03, max(max(eye, mouth), max(brow, nose)));
	ALBEDO = mix(vec3(0.002), vec3(pow(value, 2.2)), front);
}
