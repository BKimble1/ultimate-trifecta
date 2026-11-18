shader_type spatial;
// Characters: vertex/uniform colour with a moonlit rim so silhouettes read at night.
render_mode diffuse_lambert, specular_schlick_ggx;

uniform vec3 albedo : source_color = vec3(1.0);
uniform vec3 rim_color : source_color = vec3(0.55, 0.7, 1.0);
uniform float rim_strength = 0.45;
uniform float emission = 0.0;
// (2.2 build 18) plain uniforms: no prop sets them per instance, and every
// instance uniform takes slots in the global buffer for each prop on campus
uniform vec3 flash_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float flash = 0.0;
uniform float stripes = 0.0;
uniform vec3 stripe_color : source_color = vec3(1.0);
uniform float use_vertex_color = 0.0;
// (2.2 build 21) snow on top (the hiding bushes; SnowCover)
global uniform float snow_on;
uniform float snow_caps = 0.0;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void fragment() {
	vec3 base = mix(albedo, srgb_to_linear(COLOR.rgb) * albedo, use_vertex_color);
	if (stripes > 0.0) {
		vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float s = step(0.5, fract((UV.y) * stripes));
		base = mix(base, stripe_color, s * 0.85);
	}
	float rough_v = 0.7;
	if (snow_caps > 0.0 && snow_on > 0.5) {
		vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
		vec3 wp2 = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float breakup = 0.5 + 0.5 * sin(wp2.x * 7.3 + sin(wp2.z * 5.1) * 1.7) * sin(wp2.z * 6.1 + wp2.x * 1.3);
		float cap = smoothstep(0.42, 0.68, wn.y + (breakup - 0.5) * 0.25) * snow_caps;
		base = mix(base, srgb_to_linear(vec3(0.83, 0.87, 0.95)), cap * 0.92);
		rough_v = mix(rough_v, 0.8, cap);
	}
	ALBEDO = base;
	ROUGHNESS = rough_v;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	EMISSION = rim_color * rim * rim_strength + base * emission + flash_color * flash;
}
