shader_type sky;
// Night sky: gradient, twinkling stars and a soft moon. Very cheap.

uniform vec3 top_color : source_color = vec3(0.04, 0.06, 0.18);
uniform vec3 horizon_color : source_color = vec3(0.20, 0.24, 0.46);
uniform vec3 ground_color : source_color = vec3(0.05, 0.06, 0.12);
uniform vec3 moon_dir = vec3(-0.45, 0.62, -0.64);
uniform vec3 moon_color : source_color = vec3(1.0, 0.97, 0.86);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.6, h));
	if (h < 0.0) {
		col = mix(horizon_color, ground_color, smoothstep(0.0, 0.2, -h));
	}
	if (AT_CUBEMAP_PASS == false && h > 0.05) {
		vec3 cell = floor(d * 140.0);
		float r = hash(cell);
		if (r > 0.985) {
			vec3 cc = (cell + 0.5) / 140.0;
			float dist = length(d - normalize(cc));
			float tw = 0.6 + 0.4 * sin(TIME * (1.0 + r * 4.0) + r * 50.0);
			col += vec3(0.9, 0.92, 1.0) * smoothstep(0.004, 0.0, dist) * tw * smoothstep(0.05, 0.3, h);
		}
	}
	vec3 md = normalize(moon_dir);
	float m = dot(d, md);
	col += moon_color * smoothstep(0.9993, 0.9996, m) * 1.6;
	col += moon_color * pow(max(m, 0.0), 300.0) * 0.35;
	COLOR = col;
}
