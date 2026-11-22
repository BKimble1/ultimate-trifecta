shader_type spatial;
// (build 33) The soft glowing disc a hologram stands on (CharacterView
// set_hologram): a bright rim, a faint fill, slow rings moving out.  Additive,
// no depth writes (it never hides the shoes or the rug).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 pad_color : source_color = vec3(0.30, 0.72, 1.0);
instance uniform float holo_fade = 1.0;
instance uniform float holo_motion = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float rim = smoothstep(0.80, 0.92, r) * (1.0 - smoothstep(0.92, 1.0, r));
	float fill = (1.0 - smoothstep(0.0, 0.95, r)) * 0.18;
	float wave = (1.0 - smoothstep(0.0, 0.06, abs(r - fract(TIME * 0.35 * holo_motion)))) * 0.25 * (1.0 - r) * holo_motion;
	float a = (rim * 0.85 + fill + wave) * holo_fade;
	ALBEDO = pad_color * a * 1.2;
	ALPHA = 1.0;
}
