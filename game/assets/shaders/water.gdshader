shader_type spatial;
// Stylised night water (V2): deep blue -> teal by distance from the shore,
// fine moving ripples with moonlit specular, soft fresnel sky, a thin
// shoreline foam line.  Emphasis is limited on purpose:
//   * an active target shows only a slim ring just inside its shoreline in
//     the water's own colour (plus the beacon column above it);
//   * a stamp (for this player) calms the ring away;
//   * a splash sends out one expanding ripple from where it happened.
// The surface itself never glows.
render_mode diffuse_lambert, specular_schlick_ggx, cull_back;

uniform vec3 deep_color : source_color = vec3(0.035, 0.11, 0.19);
uniform vec3 shallow_color : source_color = vec3(0.09, 0.36, 0.42);
uniform vec3 sky_color : source_color = vec3(0.18, 0.26, 0.46);
uniform vec3 highlight_color : source_color = vec3(0.435, 0.847, 0.8);   // muted teal #6FD8CC
uniform vec3 target_color : source_color = vec3(1.0, 0.78, 0.4);
uniform float active = 0.0;
uniform float stamped = 0.0;
uniform float splash_flash = 0.0;      // 1 -> 0 over the ripple's life
uniform vec2 splash_local = vec2(0.0); // splash point in the water's local xz
uniform vec2 shape_half = vec2(5.0, 5.0);
uniform float shape_kind = 0.0; // 0 = ellipse/circle, 1 = rect

varying vec3 v_world;
varying vec2 v_local;

float edge_dist(vec2 local) {
	if (shape_kind > 0.5) {
		vec2 d = shape_half - abs(local);
		return min(d.x, d.y);
	}
	vec2 n = local / shape_half;
	float r = length(n);
	return (1.0 - r) * min(shape_half.x, shape_half.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local = VERTEX.xz;
	float t = TIME;
	VERTEX.y += sin(v_world.x * 0.9 + t * 1.3) * 0.015 + cos(v_world.z * 1.1 + t * 1.1) * 0.015;
}

void fragment() {
	float t = TIME;
	vec2 p = v_world.xz;
	// two scrolling ripple layers -> perturbed normal (small amplitude)
	float r1 = sin(p.x * 2.1 + t * 1.6) * cos(p.y * 1.9 - t * 1.3);
	float r2 = sin((p.x - p.y) * 4.7 - t * 2.4) * 0.5 + sin((p.x * 0.7 + p.y) * 6.3 + t * 2.9) * 0.25;
	float calm = 1.0 - stamped * active * 0.5;
	vec3 n = normalize(vec3((r1 * 0.05 + r2 * 0.035) * calm, 1.0, (cos(p.x * 1.6 + t) * 0.04 + r2 * 0.02) * calm));
	float ed = edge_dist(v_local);
	// expanding splash ripple
	float age = 1.0 - splash_flash;
	float sd = length(v_local - splash_local);
	float wave = 0.0;
	if (splash_flash > 0.001) {
		float front = age * 7.0;
		wave = exp(-pow((sd - front) * 2.2, 2.0)) * splash_flash;
		n.xz += normalize(v_local - splash_local + 1e-4) * wave * 0.35;
		n = normalize(n);
	}
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	float depth_t = smoothstep(0.0, 3.5, ed);
	vec3 col = mix(shallow_color, deep_color, depth_t);
	col = mix(col, sky_color, fres * 0.5);
	// thin shoreline foam line
	float foam = smoothstep(0.45, 0.0, ed) * (0.55 + 0.45 * sin(t * 1.6 + ed * 9.0 + p.x * 0.6));
	col = mix(col, vec3(0.86, 0.92, 0.95), foam * 0.45);
	ALBEDO = col;
	ROUGHNESS = 0.08;
	SPECULAR = 0.55;
	// active target marker: slim pulsing ring ~0.7 m inside the shore
	float pulse = 0.65 + 0.35 * sin(t * 2.4);
	float ring = smoothstep(0.16, 0.0, abs(ed - 0.75)) * active * (1.0 - stamped);
	vec3 emit = target_color * ring * pulse * 1.4;
	emit += highlight_color * wave * 0.6;
	emit += vec3(0.75, 0.85, 0.95) * foam * 0.05;
	emit += col * 0.06;   // never pitch black at night
	EMISSION = emit;
}
