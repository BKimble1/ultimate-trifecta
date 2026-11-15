shader_type spatial;
// Season 1 (holiday) bulbs in the dorm common room: tree fairy lights, the
// strings along the walls and the star.  Unshaded and bright enough to pass
// the room's glow threshold.  Vertex colour is the bulb's colour (sRGB);
// UV.x is the kind (0 bulb, 1 star), UV.y the bulb's own phase (0..1), so
// neighbouring bulbs never blink together.  `twinkle` 0 holds every bulb
// steady (Reduced Motion).
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float twinkle : hint_range(0.0, 1.0) = 1.0;
uniform float energy = 2.3;

varying float v_phase;
varying float v_kind;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	v_phase = UV.y;
	v_kind = UV.x;
}

void fragment() {
	vec3 c = srgb_to_linear(COLOR.rgb);
	float tw;
	if (v_kind > 0.5) {
		// the star: steady, with a slow shimmer
		tw = 1.0 + 0.14 * twinkle * sin(TIME * 1.7);
	} else {
		// each bulb breathes at its own rate and phase, never fully dark
		float rate = 0.9 + fract(v_phase * 7.31) * 1.4;
		float s = 0.5 + 0.5 * sin(TIME * rate + v_phase * 6.2831);
		tw = mix(1.0, 0.42 + 0.68 * s * s, twinkle);
	}
	ALBEDO = c * energy * tw;
}
