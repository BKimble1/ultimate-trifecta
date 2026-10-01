shader_type spatial;
// Stylised night water: layered ripples, soft fresnel sky reflection,
// shoreline foam ring, and an "active target" glow pulse.
render_mode diffuse_lambert, specular_schlick_ggx, cull_back;

uniform vec3 deep_color : source_color = vec3(0.04, 0.16, 0.30);
uniform vec3 shallow_color : source_color = vec3(0.10, 0.42, 0.55);
uniform vec3 sky_color : source_color = vec3(0.32, 0.42, 0.75);
uniform vec3 target_color : source_color = vec3(1.0, 0.8, 0.3);
uniform float active = 0.0;
uniform float stamped = 0.0;
uniform float splash_flash = 0.0;
uniform vec2 shape_half = vec2(5.0, 5.0);
uniform float shape_kind = 0.0; // 0 = ellipse/circle, 1 = rect

varying vec3 v_world;

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
	float t = TIME;
	VERTEX.y += sin(v_world.x * 0.9 + t * 1.7) * 0.025 + cos(v_world.z * 1.1 + t * 1.3) * 0.025;
}

void fragment() {
	vec2 local = (inverse(MODEL_MATRIX) * vec4(v_world, 1.0)).xz;
	float t = TIME;
	float rip = sin(v_world.x * 2.3 + t * 2.1) * cos(v_world.z * 2.1 - t * 1.7);
	rip += 0.5 * sin((v_world.x + v_world.z) * 4.1 - t * 3.0);
	vec3 n = normalize(vec3(rip * 0.08, 1.0, cos(v_world.x * 1.7 + t) * 0.06));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float ed = edge_dist(local);
	float foam = smoothstep(0.9, 0.0, ed) * (0.6 + 0.4 * sin(t * 2.0 + ed * 6.0));
	vec3 col = mix(deep_color, shallow_color, 0.35 + 0.25 * rip);
	col = mix(col, sky_color, fres * 0.55);
	col += vec3(0.8, 0.9, 1.0) * foam * 0.35;
	float pulse = 0.55 + 0.45 * sin(t * 3.0);
	float ring = smoothstep(1.4, 0.2, abs(ed - 1.0 - 0.6 * sin(t * 1.5)));
	vec3 glow = target_color * active * (1.0 - stamped * 0.65) * (0.25 + 0.35 * pulse + ring * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
	EMISSION = glow + col * 0.25 + target_color * splash_flash * 1.5 + vec3(0.6, 0.8, 1.0) * foam * 0.15;
}
