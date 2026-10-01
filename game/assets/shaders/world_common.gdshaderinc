// Shared body of the static campus shaders (world_vc / world_foliage).
uniform float emission_boost = 1.6;
uniform float wind_strength = 1.0;
uniform vec3 moon_rim_color : source_color = vec3(0.35, 0.45, 0.85);

varying float v_emis;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	v_emis = UV2.x;
	float sway = UV2.y * wind_strength;
	if (sway > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float t = TIME;
		VERTEX.x += sin(t * 1.3 + wp.x * 0.21 + wp.z * 0.13) * 0.09 * sway;
		VERTEX.z += cos(t * 1.1 + wp.x * 0.17 - wp.z * 0.11) * 0.07 * sway;
	}
}

#ifdef NEAR_FADE
// 4x4 ordered dither thresholds
const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
#endif

void fragment() {
#ifdef NEAR_FADE
	// Dissolve foliage the follow camera ends up inside or right next to, so a
	// canopy never fills the screen. Only foliage uses this variant (discard
	// costs hidden-surface removal on mobile GPUs).
	float fade = clamp((length(VERTEX) - 0.9) / 2.4, 0.0, 1.0);
	if (fade < 0.999) {
		ivec2 q = ivec2(mod(FRAGCOORD.xy, 4.0));
		if (fade * 16.0 <= BAYER[q.x + q.y * 4] + 0.5) {
			discard;
		}
	}
#endif
	vec3 base = srgb_to_linear(COLOR.rgb);
	ALBEDO = base;
	ROUGHNESS = 0.9;
	EMISSION = base * v_emis * emission_boost;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION += moon_rim_color * rim * 0.06;
}
