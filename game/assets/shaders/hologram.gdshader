shader_type spatial;
// (2.3) Power-up holograms: an unshaded, additive projection with a bright
// rim, slow scanlines climbing the model and a faint flicker.  Mobile
// renderer friendly (no screen or depth reads).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.3, 1.0, 0.9, 1.0);
uniform float strength = 1.0;
uniform float scan_speed = 1.6;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.2);
	float scan = 0.72 + 0.28 * sin(wpos.y * 46.0 - TIME * scan_speed * 6.0);
	float band = smoothstep(0.0, 0.06, fract(wpos.y * 1.4 - TIME * 0.35)) * 0.25 + 0.75;
	float flick = 0.93 + 0.07 * sin(TIME * 31.0) * sin(TIME * 7.0);
	ALBEDO = tint.rgb * (0.9 + fres * 1.6);
	ALPHA = clamp((0.5 + fres * 0.9) * scan * band * flick * strength, 0.0, 1.0);
}
