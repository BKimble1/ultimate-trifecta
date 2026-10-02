shader_type spatial;
// Dorm common room behind the menus (DormStage).  Vertex colour albedo;
// vertex alpha selects a surface treatment (round(a * 10)):
//   10 plain painted / plastic      9 varnished wood (grain + plank seams)
//    8 fabric (weave, soft sheen)   7 wallpaper (quiet stripe + dots)
//    6 glossy (ceramic, lamp glass, poster gloss)
// CUSTOM0.x = emission strength (string lights, lamp shade, window lights).
// Cheap procedural detail (value noise, a few sines), no textures.
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

uniform float emission_boost = 1.6;
uniform vec3 rim_color : source_color = vec3(0.4, 0.42, 0.6);

varying vec3 v_wp;
varying vec3 v_wn;
varying float v_emis;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_emis = CUSTOM0.x;
}

void fragment() {
	vec3 base = srgb_to_linear(COLOR.rgb);
	int m = int(round(COLOR.a * 10.0));
	float rough = 0.88;
	float spec = 0.2;
	vec3 emit = vec3(0.0);
	bool up = v_wn.y > 0.7;
	if (m == 9) {
		// wood: grain runs along the plank (Z on the floor, X on furniture tops)
		vec2 g = up ? v_wp.xz : vec2(v_wp.x + v_wp.z, v_wp.y);
		float lane = floor(g.x / 0.75);
		float grain = vnoise(vec2(g.x * 22.0, g.y * 0.9 + lane * 7.3)) * 0.6 + vnoise(vec2(g.x * 60.0, g.y * 2.5)) * 0.4;
		float rings = sin((g.x * 40.0 + vnoise(g * vec2(3.0, 0.4)) * 6.0)) * 0.5 + 0.5;
		base *= 0.84 + 0.2 * grain + 0.06 * rings;
		// staggered plank ends on the floor
		if (up) {
			float endz = fract((v_wp.z + hash12(vec2(lane, 3.0)) * 2.0) / 2.2);
			base *= mix(0.72, 1.0, smoothstep(0.0, 0.006, endz) * smoothstep(1.0, 0.994, endz));
			float sidex = fract(v_wp.x / 0.75);
			base *= mix(0.78, 1.0, smoothstep(0.0, 0.012, sidex) * smoothstep(1.0, 0.988, sidex));
		}
		rough = 0.42 + 0.25 * grain;   // varnish: soft sheen that breaks up with the grain
		spec = 0.4;
	} else if (m == 8) {
		// fabric: fine weave + a fuzzy sheen at grazing angles
		vec2 q = up ? v_wp.xz : vec2(v_wp.x + v_wp.z, v_wp.y);
		float weave = sin(q.x * 160.0) * sin(q.y * 160.0) * 0.5 + 0.5;
		float fuzz = vnoise(q * 9.0);
		base *= 0.9 + 0.08 * weave + 0.08 * fuzz;
		rough = 0.97;
		spec = 0.08;
		float sheen = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
		emit += base * sheen * 0.18;
	} else if (m == 7) {
		// wallpaper: a quiet vertical stripe with small dots
		float stripe = smoothstep(0.46, 0.5, fract(v_wp.x * 2.2 + v_wp.z * 2.2)) * smoothstep(0.62, 0.58, fract(v_wp.x * 2.2 + v_wp.z * 2.2));
		vec2 dp = vec2(v_wp.x + v_wp.z, v_wp.y) * 4.4;
		float dots = 1.0 - smoothstep(0.08, 0.12, length(fract(dp + vec2(0.5 * floor(dp.y), 0.0)) - 0.5));
		base *= 0.96 + 0.07 * stripe + 0.05 * dots;
		rough = 0.9;
	} else if (m == 6) {
		rough = 0.25;
		spec = 0.55;
	}
	// soft contact shade where walls meet the floor and under furniture
	float ao = 1.0;
	if (!up && abs(v_wn.y) < 0.5) {
		ao = mix(0.72, 1.0, smoothstep(0.0, 0.7, v_wp.y));
	} else if (up && v_wp.y < 0.05) {
		float dw = min(v_wp.z + 3.48, v_wp.x + 5.98);
		ao = mix(0.74, 1.0, smoothstep(0.0, 0.9, dw));
	}
	ALBEDO = base * ao;
	ROUGHNESS = rough;
	SPECULAR = spec;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = base * v_emis * emission_boost + rim_color * rim * 0.05 + emit;
}
