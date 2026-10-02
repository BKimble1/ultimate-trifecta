// Shared body of the static campus shaders (world_vc / world_foliage).
uniform float emission_boost = 1.6;
uniform float wind_strength = 1.0;
uniform vec3 moon_rim_color : source_color = vec3(0.35, 0.45, 0.85);

varying float v_emis;

#ifdef NEAR_PART
// Followed character for the canopy see-through: xyz = world point at the
// character's chest, w = radius in metres around it (0 = off).  Set every
// frame by MatchController.
uniform vec4 focus = vec4(0.0);
#endif

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	v_emis = UV2.x;
	float sway = UV2.y * wind_strength;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 off = vec3(0.0);   // world-space displacement
	if (sway > 0.0) {
		float t = TIME;
		off.x += sin(t * 1.3 + wp.x * 0.21 + wp.z * 0.13) * 0.09 * sway;
		off.z += cos(t * 1.1 + wp.x * 0.17 - wp.z * 0.11) * 0.07 * sway;
	}
#ifdef NEAR_PART
	// Foliage parts around the camera instead of dissolving: vertices inside
	// a sphere around the camera are pushed out toward its surface, so a
	// canopy the follow camera passes through never fills the screen.
	// Smooth, no screen-door pattern.
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 d = wp + off - cam;
	float dl = length(d);
	const float PART_R = 2.6;
	if (dl < PART_R && dl > 1e-3) {
		float k = smoothstep(0.0, 1.0, 1.0 - dl / PART_R);
		off += d / dl * (mix(dl, PART_R, k) - dl);
	}
#endif
	// campus meshes are rigid (no scale): the inverse basis is its transpose
	VERTEX += transpose(mat3(MODEL_MATRIX)) * off;
}

void fragment() {
#ifdef NEAR_PART
	// See-through: canopy that lies between the camera and the followed
	// character is cut away inside a circle around the character (measured
	// in the camera's view, so its on-screen size matches the character).
	// A clean edge, no dither; only in the camera pass (perspective), so tree
	// shadows on the character stay intact.
	// Near clear: the vertex parting pushes canopy within PART_R onto a
	// sphere around the camera, so a camera inside a big canopy saw the
	// inside of a green bubble with only the circle below open (measured:
	// 84% of the frame).  Foliage closer than NEAR_CLEAR is cut away instead
	// (clean spherical edge, no dither; camera pass only).
	const float NEAR_CLEAR = 3.2;
	if (PROJECTION_MATRIX[3][3] < 0.5 && length(VERTEX) < NEAR_CLEAR) {
		discard;
	}
	if (focus.w > 0.0 && PROJECTION_MATRIX[3][3] < 0.5) {
		vec3 fv = (VIEW_MATRIX * vec4(focus.xyz, 1.0)).xyz;
		if (fv.z < -0.5 && VERTEX.z > fv.z + 0.8) {
			vec2 a = VERTEX.xy / -VERTEX.z;
			vec2 b = fv.xy / -fv.z;
			if (distance(a, b) < focus.w / -fv.z) {
				discard;
			}
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
