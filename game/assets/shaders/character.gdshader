shader_type spatial;
// Characters: vertex/uniform colour with a moonlit rim so silhouettes read at night.
render_mode diffuse_lambert, specular_schlick_ggx;

uniform vec3 albedo : source_color = vec3(1.0);
uniform vec3 rim_color : source_color = vec3(0.55, 0.7, 1.0);
uniform float rim_strength = 0.45;
uniform float emission = 0.0;
instance uniform vec3 flash_color : source_color = vec3(1.0, 1.0, 1.0);
instance uniform float flash = 0.0;
uniform float stripes = 0.0;
uniform vec3 stripe_color : source_color = vec3(1.0);
uniform float use_vertex_color = 0.0;

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
	ALBEDO = base;
	ROUGHNESS = 0.7;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	EMISSION = rim_color * rim * rim_strength + base * emission + flash_color * flash;
}
