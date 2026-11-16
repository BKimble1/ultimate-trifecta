shader_type spatial;
// (2.2 build 16) A rift portal: an upright oval that always faces the camera
// (turning about the vertical only), filled with a swirl of violet, cyan and
// pink light that spirals in to a bright core, with a glowing ragged rim.
// Added light, unshaded.  `open` (0..1) grows it from a slit.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float open = 1.0;
uniform float speed = 1.0;
uniform vec3 col_a : source_color = vec3(0.62, 0.35, 1.0);
uniform vec3 col_b : source_color = vec3(0.35, 0.95, 1.0);
uniform vec3 col_c : source_color = vec3(1.0, 0.45, 0.85);

void vertex() {
	// face the camera about Y only (a standing portal)
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = cam - origin;
	to_cam.y = 0.0;
	to_cam = normalize(to_cam + vec3(0.0001));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec3 world = origin + right * VERTEX.x + vec3(0.0, 1.0, 0.0) * VERTEX.y;
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

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	// an oval, narrow while it opens
	vec2 q = vec2(uv.x / max(0.05, open), uv.y);
	float r = length(q);
	float a = atan(q.y, q.x);
	float t = TIME * speed;
	// spiral: the angle twists with the radius and turns with time
	float sw = a + r * 5.0 - t * 2.2;
	float n = noise(vec2(sw * 1.6, r * 6.0 - t * 1.5)) * 0.6 + noise(vec2(sw * 3.1, r * 11.0 + t)) * 0.4;
	float bands = 0.5 + 0.5 * sin(sw * 3.0 + n * 4.0);
	vec3 col = mix(col_a, col_b, bands);
	col = mix(col, col_c, smoothstep(0.55, 1.0, n));
	// bright core, glowing ragged rim, dark-ish between
	float core = smoothstep(0.45, 0.0, r);
	float edge_n = noise(vec2(a * 4.0 + t, t * 0.7)) * 0.12;
	float rim = smoothstep(0.16, 0.0, abs(r - (0.88 + edge_n)));
	float inside = smoothstep(1.0 + edge_n, 0.82 + edge_n, r);
	vec3 c = col * (0.55 + 0.9 * n) * inside + vec3(1.0, 0.95, 1.0) * core * 0.9 + mix(col_b, col_c, 0.5 + 0.5 * sin(a * 3.0 + t)) * rim * 1.6;
	ALBEDO = c;
	ALPHA = clamp((inside * (0.55 + 0.45 * n) + rim + core * 0.6) * open, 0.0, 1.0);
}
