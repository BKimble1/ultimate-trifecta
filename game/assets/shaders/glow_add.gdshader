shader_type spatial;
// Additive soft glow for fake light pools, beacons and flashlight cones.
// UV.y runs 0 (base) -> 1 (tip); UV.x radial for discs (0 centre -> 1 edge).
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.8, 0.45);
uniform float intensity = 0.6;
uniform float mode = 0.0; // 0 disc pool, 1 vertical beam, 2 cone
uniform float pulse = 0.0;
uniform float fade_near = 0.0;

void fragment() {
	float a = 0.0;
	if (mode < 0.5) {
		float r = UV.x;
		a = pow(clamp(1.0 - r, 0.0, 1.0), 2.0);
	} else if (mode < 1.5) {
		float side = pow(clamp(1.0 - abs(dot(NORMAL, VIEW)), 0.0, 1.0), 0.6);
		a = (1.0 - UV.y) * (1.0 - side * 0.85);
		a *= 0.75 + 0.25 * sin(TIME * 2.5 + UV.y * 8.0);
	} else {
		float edge = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
		a = (1.0 - UV.y) * edge * edge;
	}
	if (fade_near > 0.0) {
		float d = length(VERTEX);
		a *= clamp((d - fade_near) / fade_near, 0.0, 1.0);
	}
	float p = 1.0 + pulse * 0.4 * sin(TIME * 4.0);
	ALBEDO = vec3(0.0);
	EMISSION = color * intensity * a * p;
}
