shader_type spatial;
// (build 33) A party member who is still playing a round, shown on their
// lobby mark as a hologram (like a party member "in a match" in Fortnite):
// a translucent, softly glowing blue version of their own character.
//   * the look stays readable: the outfit's own shading (vertex colour x
//     the player's tints, as in character.gdshaderinc) becomes brightness
//     in one blue, so faces, pyjama stripes and hats still read;
//   * a fresnel rim, bright enough to bloom a little in the dorm's glow;
//   * fine scanlines and a slow band rising up the body, in world height
//     (they don't swim with the animation);
//   * a slight flicker now and then (holo_motion 0: none, Reduced Motion);
//   * holo_fade eases it in and out (0..1).
// Drawn after character_holo_depth.gdshader (the material this is the
// next_pass of), which leaves only the nearest surface to blend: no inner
// faces, no sorting between parts.  Unshaded and casting no shadow.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_default, cull_back, shadows_disabled, fog_disabled;

instance uniform vec3 tint_primary : source_color = vec3(0.36, 0.55, 0.95);
instance uniform vec3 tint_secondary : source_color = vec3(0.70, 0.80, 1.0);
instance uniform vec3 tint_dark : source_color = vec3(0.20, 0.30, 0.60);
instance uniform vec3 tint_skin : source_color = vec3(0.98, 0.82, 0.68);
instance uniform vec3 tint_hair : source_color = vec3(0.32, 0.22, 0.16);
instance uniform float holo_fade = 1.0;
instance uniform float holo_seed = 0.0;
instance uniform float holo_motion = 1.0;

uniform vec3 holo_color : source_color = vec3(0.30, 0.72, 1.0);
uniform vec3 rim_color : source_color = vec3(0.62, 0.92, 1.0);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec3 base = COLOR.rgb;
	int sel = int(round(COLOR.a * 5.0));
	vec3 tint = vec3(1.0);
	if (sel == 1) { tint = tint_hair; }
	else if (sel == 2) { tint = tint_skin; }
	else if (sel == 3) { tint = tint_secondary; }
	else if (sel == 4) { tint = tint_dark; }
	else if (sel == 5) { tint = tint_primary; }
	vec3 alb = base * tint;
	// detail as brightness (sqrt lifts the dark outfits so every look reads)
	float lum = sqrt(clamp(dot(alb, vec3(0.299, 0.587, 0.114)), 0.0, 1.0));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	float y = v_world.y;
	float t = TIME * holo_motion;
	// fine scanlines (about 55 per metre), drifting slowly upward
	float lines = smoothstep(0.55, 1.0, 0.5 + 0.5 * sin((y * 55.0 - t * 1.6) * 6.2832));
	// a soft band rising up the body every few seconds
	float band_y = fract(t * 0.22 + holo_seed * 0.37) * 2.6 - 0.4;
	float band = (1.0 - smoothstep(0.0, 0.16, abs(y - band_y))) * holo_motion;
	// now and then a quick flicker (a short dip, never a blackout)
	float slot = floor(t * 7.0 + holo_seed * 13.0);
	float flick = 1.0 - step(0.93, hash(slot + holo_seed)) * 0.35 * holo_motion;
	vec3 col = holo_color * (0.38 + 0.95 * lum);
	col += rim_color * fres * 1.55;
	col += holo_color * (lines * 0.12 + band * 0.45);
	ALBEDO = col * flick;
	ALPHA = clamp(0.34 + 0.25 * lum + fres * 0.55 + lines * 0.06 + band * 0.18, 0.0, 0.92) * flick * holo_fade;
}
