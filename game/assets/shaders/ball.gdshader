shader_type spatial;
// (build 24) The party room's basketball: pebbled orange leather and the
// eight-panel black seams (two great circles and the two curved seams round
// the ends), worked out from the sphere's own coordinates (no texture).
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

uniform vec3 base_col : source_color = vec3(0.86, 0.40, 0.13);
uniform vec3 seam_col : source_color = vec3(0.07, 0.05, 0.04);
uniform float seam_w = 0.045;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	vec3 p = normalize(v_obj);
	float s1 = abs(p.x);
	float s2 = abs(p.y);
	// the curved seams: rings round the z ends that bow toward the x poles
	float s3 = abs(abs(p.z) - 0.6 - 0.2 * (p.x * p.x - p.y * p.y));
	float seam = min(min(s1, s2), s3);
	float aa = max(fwidth(seam), 0.004);
	float m = 1.0 - smoothstep(seam_w - aa, seam_w + aa, seam);
	// pebbles: a fine bumpy grain, a touch darker in the dips
	float peb = hash13(floor(p * 70.0));
	vec3 c = base_col * (0.9 + 0.12 * peb);
	// a slightly deeper colour toward the seams (the channels)
	c *= mix(0.86, 1.0, smoothstep(seam_w, seam_w * 3.0, seam));
	ALBEDO = mix(c, seam_col, m);
	ROUGHNESS = mix(0.58 + 0.1 * peb, 0.75, m);
	SPECULAR = 0.4;
	RIM = 0.25;
	RIM_TINT = 0.6;
}
