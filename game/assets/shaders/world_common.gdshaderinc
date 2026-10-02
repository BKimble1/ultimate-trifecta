// Shared body of the static campus shaders (world_vc / world_foliage).
//
// V5: every vertex carries a material id in UV.x (MeshKit.mat, and the
// Blender kit's meshes) and one parameter in UV.y.  The id picks a world-
// space detail pattern from two small tileable masks (campus_detail_a/b,
// mipmapped, see tools/campus/make_textures.py), a bump derived from that
// pattern, and a roughness/specular pair.  Colours still come from vertex
// colours (with the baked light field), so the textures carry shape only.
//
//   0 plain          1 lawn            2 flagstone path   3 gravel path
//   4 asphalt        5 brick           6 roof shingles    7 dressed stone
//   8 wood planks   10 leaves         11 bark            12 rock
//  13 petals (tinted per instance: INSTANCE_CUSTOM.rgb)  14 metal
//  15 glass         16 tiles          17 plaster        18 paving verge
//  19 gravel verge  20 flowing water (fountain jets; UV.y runs along)
//
// 18 blends a path into the lawn beside it: COLOR is the path's colour,
// COLOR.a the position across the verge (0 path side .. 1 lawn side) and
// UV.y the lawn's colour there, packed as r*65536 + g*256 + b (flat).
//
// Lighting: a soft hemisphere fill (cool sky above, warm bounce below) is
// added on top of the engine's ambient so shade reads moonlit rather than
// flat blue; small metal and glass carry refined highlights, everything
// else stays soft.
uniform float emission_boost = 1.6;
uniform float wind_strength = 1.0;
uniform vec3 moon_rim_color : source_color = vec3(0.35, 0.45, 0.85);
uniform sampler2D detail_a : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_b : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// 1 Standard, lower in Battery Saver (no bump, flatter detail)
uniform float detail_level = 1.0;
uniform vec3 sky_fill : source_color = vec3(0.10, 0.12, 0.20);
// light field (V5, sampled here instead of baked into vertices): R soft AO,
// G warm lamp/window light, B cool pool/fountain light; one texel per 2 m
uniform sampler2D light_field : hint_default_black, filter_linear, repeat_disable;
uniform vec2 field_origin = vec2(-161.0, -151.0);
uniform vec2 field_size = vec2(322.0, 302.0);
uniform float field_on = 0.0;
const vec3 FIELD_WARM = vec3(0.42, 0.26, 0.09);
const vec3 FIELD_COOL = vec3(0.05, 0.20, 0.24);
uniform vec3 ground_bounce : source_color = vec3(0.10, 0.08, 0.07);

varying float v_emis;
varying flat float v_mat;
varying flat float v_param;
varying float v_flow;
varying vec3 v_wp;
varying vec3 v_tint;

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
	v_emis = CUSTOM0.x;
	v_mat = UV.x;
	v_param = UV.y;
	v_flow = UV.y;
	v_tint = vec3(1.0);
	if (UV.x > 12.5 && UV.x < 13.5) {
		v_tint = INSTANCE_CUSTOM.rgb;
	}
	float sway = CUSTOM0.y * wind_strength;
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
	v_wp = wp + off;
	// world-space offset back into model space (MultiMesh trees are scaled)
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
}

// Bump from a scalar height via screen-space derivatives (no tangents
// needed): k is the pattern's relief in metres.
vec3 bump_normal(vec3 n, vec3 pos, float h, float k) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	return normalize(abs(det) * n - k * grad);
}

// lawn: fine blades, broad patches (some drier and warmer)
vec3 lawn(vec3 c, vec2 xz, float fade, out float h) {
	float g = texture(detail_a, xz * 0.35).r;
	float macro = texture(detail_a, xz * 0.023 + vec2(0.37, 0.11)).r;
	float macro2 = texture(detail_a, xz * 0.061 + vec2(0.71, 0.29)).r;
	h = g;
	c *= mix(1.0, 0.78 + 0.44 * g, fade);
	// broad patches: some lusher and cooler, some drier and warmer
	c *= mix(0.8, 1.16, macro) * mix(0.92, 1.06, macro2);
	c = mix(c, c * vec3(1.16, 1.03, 0.74), smoothstep(0.58, 0.85, macro) * 0.6);
	c = mix(c, c * vec3(0.86, 0.98, 1.08), smoothstep(0.42, 0.18, macro) * 0.5);
	return c;
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
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	// light field: AO fades with height, walls darken toward their foot,
	// warm/cool light pools on up-facing surfaces (sRGB maths, as V4 baked)
	float lf_mul = 1.0;
	vec3 lf_add = vec3(0.0);
	if (field_on > 0.5) {
		vec2 fuv = (v_wp.xz - field_origin) / field_size;
		if (fuv.x >= 0.0 && fuv.y >= 0.0 && fuv.x <= 1.0 && fuv.y <= 1.0) {
			vec4 lf = texture(light_field, fuv);
			float hgt = max(v_wp.y, 0.0);
			lf_mul = 1.0 - 0.5 * lf.r * clamp(1.0 - hgt / 2.5, 0.0, 1.0);
			if (abs(wn.y) < 0.5 && v_wp.y < 1.4) {
				lf_mul *= mix(0.74, 1.0, clamp(v_wp.y / 1.4, 0.0, 1.0));
			}
			float face = clamp(wn.y, 0.0, 1.0) * 0.6 + 0.4;
			lf_add = (FIELD_WARM * lf.g + FIELD_COOL * lf.b) * clamp(1.0 - hgt / 4.0, 0.0, 1.0) * face;
		}
	}
	vec3 base = srgb_to_linear(COLOR.rgb * lf_mul + lf_add);
	int m = int(v_mat + 0.5);
	float dist = length(VERTEX);
	// pattern contrast fades out with distance (no shimmer far away)
	float fade = (1.0 - smoothstep(45.0, 140.0, dist)) * detail_level;
	vec3 n = NORMAL;
	float h = 0.5;
	float relief = 0.0;
	float rough = 0.9;
	float spec = 0.08;
	float metal = 0.0;
	// wall coordinates: along the dominant horizontal axis, and height
	vec2 wall_uv = vec2(abs(wn.x) > abs(wn.z) ? v_wp.z : v_wp.x, v_wp.y);
	if (m == 1) {
		base = lawn(base, v_wp.xz, fade, h);
		if (v_param > 0.5) {
			// mowing stripes on the formal lawns (soft, anti-aliased)
			float sx = v_wp.x / 5.0;
			float tri = abs(fract(sx) - 0.5) * 2.0;
			float aa = fwidth(sx) * 2.0;
			base *= 1.0 + 0.07 * (smoothstep(0.5 - aa, 0.5 + aa, tri) - 0.5) * fade;
		}
		relief = 0.025;
		rough = 0.95;
		spec = 0.04;
	} else if (m == 2 || m == 18 || m == 19) {
		// flagstones ~0.25 m: soft joints, gentle per-stone tone
		vec4 t = texture(detail_a, v_wp.xz * 0.5);
		float stone = t.g;
		vec3 p = base * mix(1.0, mix(0.74, 1.0, stone) * (0.92 + 0.14 * t.b), fade);
		if (m == 19) {
			float gr0 = texture(detail_a, v_wp.xz * 0.55).a;
			p = base * mix(1.0, 0.72 + 0.5 * gr0, fade);
			stone = gr0;
		}
		h = stone;
		relief = 0.008;
		if (m >= 18) {
			// path verge: lawn creeps over the paving with a ragged edge
			float packed = v_param;
			vec3 lc = vec3(floor(packed / 65536.0), mod(floor(packed / 256.0), 256.0), mod(packed, 256.0)) / 255.0;
			float lh;
			vec3 l = lawn(srgb_to_linear(lc * lf_mul + lf_add), v_wp.xz, fade, lh);
			float ragged = texture(detail_a, v_wp.xz * 0.9).r * 0.6 + texture(detail_a, v_wp.xz * 0.13).r * 0.4;
			float across = COLOR.a;
			float tl = smoothstep(0.42, 0.58, across + (ragged - 0.5) * 0.75);
			// worn soil between the stones and the grass
			p = mix(p, p * vec3(0.6, 0.55, 0.46), smoothstep(0.2, 0.45, across) * 0.65 * (1.0 - stone * 0.5));
			base = mix(p, l, tl);
			h = mix(stone, lh, tl);
		} else {
			base = p;
		}
		rough = 0.86;
		spec = 0.12;
	} else if (m == 3) {
		float gr = texture(detail_a, v_wp.xz * 0.55).a;
		base *= mix(1.0, 0.72 + 0.5 * gr, fade);
		h = gr;
		relief = 0.012;
		rough = 0.92;
		spec = 0.06;
	} else if (m == 4) {
		float g = texture(detail_a, v_wp.xz * 1.1).a;
		float patch = texture(detail_a, v_wp.xz * 0.05).r;
		base *= mix(1.0, (0.9 + 0.2 * g) * (0.92 + 0.16 * patch), fade);
		h = g;
		relief = 0.004;
		rough = 0.8;
		spec = 0.18;
	} else if (m == 5 || m == 7) {
		// brick (0.5 x 0.2 m) or dressed stone blocks (1.25 x 0.5 m)
		vec2 s = m == 5 ? vec2(0.5, 0.625) : vec2(0.2, 0.25);
		vec4 t = texture(detail_b, wall_uv * s);
		base *= mix(1.0, mix(0.62, 1.0, t.r) * (0.85 + 0.3 * t.g), fade);
		h = t.r;
		relief = 0.015;
		rough = 0.88;
		spec = 0.1;
	} else if (m == 6) {
		// roof shingles: courses follow height, tabs along the eave
		vec4 t = texture(detail_b, vec2(wall_uv.x * 0.4, wall_uv.y * 0.55));
		base *= mix(1.0, 0.62 + 0.45 * t.b, fade);
		h = t.b;
		relief = 0.03;
		rough = 0.62;
		spec = 0.3;
	} else if (m == 8) {
		vec4 t = texture(detail_b, vec2(v_wp.x * 0.5 + v_wp.y * 0.3, v_wp.z * 0.5 + v_wp.y * 0.3));
		base *= mix(1.0, 0.6 + 0.45 * t.a, fade);
		h = t.a;
		relief = 0.01;
		rough = 0.8;
		spec = 0.1;
	} else if (m == 10) {
		// leaves: clumpy light/dark variation, a soft moonlit sheen
		float g = texture(detail_a, (v_wp.xz + v_wp.y * 0.6) * 0.8).r;
		base *= mix(1.0, 0.8 + 0.42 * g, fade);
		h = g;
		relief = 0.05;
		rough = 0.72;
		spec = 0.22;
	} else if (m == 11) {
		float g = texture(detail_b, vec2((v_wp.x + v_wp.z) * 1.6, v_wp.y * 0.35)).a;
		base *= mix(1.0, 0.72 + 0.4 * g, fade);
		h = g;
		relief = 0.02;
		rough = 0.9;
		spec = 0.05;
	} else if (m == 12) {
		float g = texture(detail_a, wall_uv * 0.45 + v_wp.xz * 0.2).r;
		float gr = texture(detail_a, wall_uv * 0.9).a;
		base *= mix(1.0, (0.82 + 0.3 * g) * (0.9 + 0.2 * gr), fade);
		h = g * 0.6 + gr * 0.4;
		relief = 0.04;
		rough = 0.8;
		spec = 0.14;
	} else if (m == 13) {
		base *= v_tint;
		rough = 0.6;
		spec = 0.2;
	} else if (m == 14) {
		rough = 0.32;
		spec = 0.55;
		metal = 0.5;
	} else if (m == 15) {
		rough = 0.12;
		spec = 0.6;
	} else if (m == 16) {
		// square tiles (pool deck, coping): 0.5 m grid with grout lines
		vec2 g = fract(v_wp.xz * 2.0);
		vec2 aa = fwidth(v_wp.xz * 2.0) * 1.5;
		float grout = smoothstep(0.0, 0.04 + aa.x, g.x) * smoothstep(0.0, 0.04 + aa.x, 1.0 - g.x) *
			smoothstep(0.0, 0.04 + aa.y, g.y) * smoothstep(0.0, 0.04 + aa.y, 1.0 - g.y);
		base *= mix(1.0, mix(0.72, 1.0, grout), fade);
		h = grout;
		relief = 0.004;
		rough = 0.35;
		spec = 0.35;
	} else if (m == 20) {
		// falling water: bright streaks running down the jet
		float f = fract(v_flow * 3.0 - TIME * 1.6);
		base *= 0.75 + 0.5 * smoothstep(0.0, 0.5, f) * smoothstep(1.0, 0.5, f);
		rough = 0.1;
		spec = 0.5;
	} else if (m == 17) {
		float g = texture(detail_a, wall_uv * 0.12).r;
		base *= mix(1.0, 0.9 + 0.2 * g, fade);
		rough = 0.9;
		spec = 0.06;
	}
	if (relief > 0.0 && fade > 0.01) {
		n = bump_normal(n, VERTEX, h, relief * fade);
	}
	NORMAL = n;
	ALBEDO = base;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = metal;
	EMISSION = base * v_emis * emission_boost;
	// hemisphere fill: cool from the sky, a dim warm bounce from below
	vec3 wn2 = (INV_VIEW_MATRIX * vec4(n, 0.0)).xyz;
	EMISSION += base * mix(ground_bounce, sky_fill, clamp(wn2.y * 0.5 + 0.5, 0.0, 1.0));
	float rim = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 3.0);
	EMISSION += moon_rim_color * rim * (m == 10 ? 0.035 : 0.05);
}
