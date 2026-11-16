shader_type spatial;
// (2.2 build 16, reworked 2.2 build 17) A rift portal: an upright oval that
// always faces the camera (turning about the vertical only).  Inside, a deep
// violet void with nebula bands spiralling in at two depths and specks of
// light drawn towards a bright eye; round it a crackling white-hot rim that
// shifts cyan to pink, and a soft glow beyond it.  Added light, unshaded.
// `open` (0..1) grows it from a slit.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float open = 1.0;
uniform float speed = 1.0;
uniform vec3 col_a : source_color = vec3(0.55, 0.3, 1.0);
uniform vec3 col_b : source_color = vec3(0.3, 0.95, 1.0);
uniform vec3 col_c : source_color = vec3(1.0, 0.42, 0.85);

void vertex() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = cam - origin;
	to_cam.y = 0.0;
	to_cam = normalize(to_cam + vec3(0.0001));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	float sc = length(MODEL_MATRIX[0].xyz);
	vec3 world = origin + (right * VERTEX.x + vec3(0.0, 1.0, 0.0) * VERTEX.y) * sc;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	// the quad is larger than the oval: room for the outer glow
	vec2 uv = (UV * 2.0 - 1.0) * vec2(1.3, 1.18);
	vec2 q = vec2(uv.x / max(0.05, open), uv.y);
	float r = length(q);
	float a = atan(q.y, q.x);
	float t = TIME * speed;
	// two spiral layers at different speeds and scales (depth)
	float s1 = a + r * 5.5 - t * 2.4;
	float s2 = a * 2.0 + r * 9.0 - t * 3.6;
	float n1 = fbm(vec2(s1 * 1.4, r * 5.0 - t * 1.2));
	float n2 = fbm(vec2(s2 * 0.9, r * 8.0 + t * 0.8));
	vec3 neb = mix(col_a, col_b, smoothstep(0.35, 0.75, n1));
	neb = mix(neb, col_c, smoothstep(0.55, 0.9, n2) * 0.8);
	// specks of light falling in along the spiral
	vec2 sp = vec2(a * 6.0 / 6.2832 + r * 1.5, r * 7.0 + t * 1.6);
	float speck = step(0.965, hash(floor(sp * vec2(14.0, 6.0)))) * smoothstep(0.95, 0.2, r);
	// the void: darker towards the middle, then the bright eye
	float edge_n = (fbm(vec2(a * 3.0 + t * 0.6, t * 0.4)) - 0.5) * 0.14;
	float rim_r = 0.86 + edge_n;
	float inside = smoothstep(rim_r + 0.02, rim_r - 0.06, r);
	float depth = mix(0.35, 1.0, smoothstep(0.1, 0.8, r));
	float eye = smoothstep(0.32, 0.0, r);
	// the rim: a crackling white-hot line, colour shifting round it
	float crackle = 0.6 + 0.4 * noise(vec2(a * 18.0, t * 12.0));
	float rim = smoothstep(0.075, 0.0, abs(r - rim_r)) * crackle;
	vec3 rim_col = mix(col_b, col_c, 0.5 + 0.5 * sin(a * 2.0 + t * 1.3));
	// outer glow
	float glow = smoothstep(rim_r + 0.45, rim_r, r) * (1.0 - inside) * 0.6;
	vec3 c = neb * (0.25 + 0.95 * n1) * depth * inside
		+ vec3(1.0) * speck * 1.4
		+ mix(col_c, vec3(1.0), 0.6) * eye * 0.9
		+ (rim_col * 1.4 + vec3(0.6)) * rim
		+ rim_col * glow;
	ALBEDO = c;
	ALPHA = clamp((inside * (0.45 + 0.5 * n1) * depth + rim + eye * 0.6 + glow + speck) * open, 0.0, 1.0);
}
