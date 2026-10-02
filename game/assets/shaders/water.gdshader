shader_type spatial;
// Stylised night water (V2, V5).  Deep blue -> teal by distance from the
// shore, slow moving ripples, a fake reflection of the night sky (gradient
// by fresnel, the moon's glitter path from the sky's moon direction), a
// restrained shoreline foam line.  Opaque: no screen reads, no transparency.
//
// Objective markers (V5): the mesh also carries floating lanterns (UV.x = 9)
// in the water's target colour.  They are collapsed away unless `active`,
// bob gently when active and dim once `stamped`; with the slim shoreline
// glow they are what marks a target, so decorative water never looks like
// one.  Splashes send out expanding ripples: up to RIPPLES sources per
// water (x, z in the water's local xz, age s, strength), aged by Fx.
//
// Variants by uniform: `pool` (clear turquoise, lane lines on the floor,
// wall lights), `fountain` (ripple rings where the four jets land and
// around the plume).
render_mode diffuse_lambert, specular_schlick_ggx, cull_back;

uniform vec3 deep_color : source_color = vec3(0.035, 0.11, 0.19);
uniform vec3 shallow_color : source_color = vec3(0.09, 0.36, 0.42);
uniform vec3 sky_color : source_color = vec3(0.18, 0.26, 0.46);
uniform vec3 sky_top : source_color = vec3(0.05, 0.08, 0.2);
uniform vec3 highlight_color : source_color = vec3(0.435, 0.847, 0.8);   // muted teal #6FD8CC
uniform vec3 target_color : source_color = vec3(1.0, 0.78, 0.4);
uniform vec3 moon_dir = vec3(-0.45, 0.62, -0.64);
uniform float active = 0.0;
uniform float stamped = 0.0;
uniform float pool = 0.0;
uniform float fountain = 0.0;
#define RIPPLES 6
const float RIPPLE_LIFE = 1.8;
const float RIPPLE_SPEED = 3.2;   // m/s
uniform vec4 ripples[RIPPLES];    // x, z, age (s), strength; strength 0 = unused
uniform vec2 shape_half = vec2(5.0, 5.0);
uniform float shape_kind = 0.0; // 0 = ellipse/circle, 1 = rect

varying vec3 v_world;
varying vec2 v_local;
varying float v_marker;
varying float v_emis;

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
	v_marker = UV.x > 8.5 && UV.x < 9.5 ? 1.0 : 0.0;
	v_emis = CUSTOM0.x;
	float t = TIME;
	if (v_marker > 0.5) {
		if (active < 0.5) {
			VERTEX = vec3(0.0);   // collapsed: nothing drawn
		} else {
			// bob and sway a little (each lantern its own phase, UV.y)
			VERTEX.y += sin(t * 1.4 + UV.y) * 0.045;
			VERTEX.x += sin(t * 0.7 + UV.y * 1.3) * 0.06;
		}
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local = VERTEX.xz;
	if (v_marker < 0.5) {
		VERTEX.y += sin(v_world.x * 0.9 + t * 1.1) * 0.012 + cos(v_world.z * 1.1 + t * 0.9) * 0.012;
	}
}

void fragment() {
	float t = TIME;
	if (v_marker > 0.5) {
		// lantern: paper glows in the target colour, dims once stamped
		vec3 c = COLOR.rgb;
		ALBEDO = c * 0.4;
		ROUGHNESS = 0.6;
		SPECULAR = 0.2;
		float glow = v_emis * (1.0 - 0.7 * stamped) * (0.85 + 0.15 * sin(t * 2.2 + v_world.x));
		// saturated paper glow (kept under the bloom threshold's white-out)
		EMISSION = c * c * glow * 1.1;
	} else {
		vec2 p = v_world.xz;
		// two slow scrolling ripple layers -> perturbed normal (small amplitude)
		float r1 = sin(p.x * 1.7 + t * 1.0) * cos(p.y * 1.5 - t * 0.8);
		float r2 = sin((p.x - p.y) * 3.9 - t * 1.5) * 0.5 + sin((p.x * 0.7 + p.y) * 5.6 + t * 1.9) * 0.25;
		float calm = 1.0 - stamped * active * 0.5;
		vec3 n = normalize(vec3((r1 * 0.045 + r2 * 0.03) * calm, 1.0, (cos(p.x * 1.3 + t * 0.7) * 0.035 + r2 * 0.018) * calm));
		float ed = edge_dist(v_local);
		// expanding splash ripples: a leading crest and a softer trailing one
		float wave = 0.0;
		for (int i = 0; i < RIPPLES; i++) {
			vec4 r = ripples[i];
			if (r.w <= 0.001 || r.z >= RIPPLE_LIFE) { continue; }
			float life = 1.0 - r.z / RIPPLE_LIFE;
			float fade = r.w * life * life;
			vec2 dv = v_local - r.xy;
			float sd = length(dv);
			float front = r.z * RIPPLE_SPEED + 0.15;
			float x = (sd - front) * 4.0;
			float w = exp(-x * x) - 0.45 * exp(-pow(x + 2.2, 2.0));
			wave += w * fade;
			n.xz += normalize(dv + 1e-4) * w * fade * 0.3;
		}
		float churn = 0.0;
		if (fountain > 0.5) {
			// rings spreading from where the jets land (and the plume's foot)
			for (int j = 0; j < 4; j++) {
				float a = 6.2831853 * (float(j) + 0.5) / 4.0;
				vec2 lp = vec2(cos(a), sin(a)) * 4.3;
				float d = length(v_local - lp);
				float ring = sin(d * 7.0 - t * 5.0) * exp(-d * 1.1);
				n.xz += normalize(v_local - lp + 1e-4) * ring * 0.12;
				churn += exp(-d * d * 3.0);
			}
		}
		n = normalize(n);
		NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
		vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		float fres = pow(1.0 - clamp(dot(n, vw), 0.0, 1.0), 4.0);
		float depth_t = smoothstep(0.0, 3.5, ed);
		vec3 col = mix(shallow_color, deep_color, depth_t);
		if (pool > 0.5) {
			// clear pool water: tiled floor lanes show through, lit walls
			vec2 lq = v_local;
			float lane = smoothstep(0.12, 0.0, abs(abs(lq.x) - shape_half.x * 0.33)) * step(abs(lq.y), shape_half.y - 1.2);
			float wall_light = 0.0;
			for (int k = 0; k < 3; k++) {
				float zz = (float(k) - 1.0) * shape_half.y * 0.6;
				wall_light += exp(-(pow(abs(lq.x) - shape_half.x, 2.0) * 0.8 + pow(lq.y - zz, 2.0) * 0.35));
			}
			col = mix(col, col * 0.45, lane * 0.6);
			col += vec3(0.10, 0.45, 0.55) * wall_light * 0.6;
		}
		// fake reflection: sky gradient by fresnel, the moon's glitter path
		vec3 rv = reflect(-vw, n);
		vec3 sky = mix(sky_color, sky_top, smoothstep(0.0, 0.6, rv.y));
		col = mix(col, sky, fres * 0.6);
		float glint = pow(max(dot(rv, normalize(moon_dir)), 0.0), 220.0);
		// thin shoreline foam line
		float foam = smoothstep(0.42, 0.0, ed) * (0.55 + 0.45 * sin(t * 1.2 + ed * 9.0 + p.x * 0.6));
		col = mix(col, vec3(0.80, 0.88, 0.92), foam * 0.32);
		col = mix(col, vec3(0.80, 0.90, 0.95), clamp(wave + churn * 0.35, 0.0, 1.0) * 0.14);
		ALBEDO = col;
		ROUGHNESS = 0.12;
		SPECULAR = 0.3;
		// active target: a slim, soft glow just inside the shoreline in the
		// water's own colour (the lanterns carry the rest)
		float pulse = 0.7 + 0.3 * sin(t * 2.0);
		float ring = smoothstep(0.16, 0.0, abs(ed - 0.5)) * active * (1.0 - stamped);
		vec3 emit = target_color * ring * pulse * 0.32;
		// the lanterns' light on the water: a faint tint near the edge
		emit += target_color * active * (1.0 - stamped) * smoothstep(1.6, 0.0, ed) * 0.035;
		emit += highlight_color * max(wave, 0.0) * 0.28;
		emit += vec3(0.75, 0.85, 0.95) * foam * 0.04;
		emit += vec3(1.0, 0.97, 0.88) * glint * 1.4;
		emit += col * 0.06;   // never pitch black at night
		EMISSION = emit;
	}
}
