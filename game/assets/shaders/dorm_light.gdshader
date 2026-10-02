shader_type spatial;
// DormStage light pools (V5): warm lamp light on the floor and wall, cool
// moonlight through the window.  Additive, unshaded, no depth writes, no
// shadows: a few quads instead of extra shadowed lights.
// UV in 0..1 across the quad; shape 0 = round pool, 1 = soft rectangle.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.75, 0.45);
uniform float intensity = 0.25;
uniform float shape = 0.0;
uniform float softness = 0.35;

void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	float a;
	if (shape < 0.5) {
		a = pow(clamp(1.0 - length(d), 0.0, 1.0), 1.8);
	} else {
		vec2 e = smoothstep(vec2(1.0), vec2(1.0 - softness), d);
		a = e.x * e.y * (1.0 - 0.45 * UV.y);
	}
	ALBEDO = vec3(0.0);
	EMISSION = color * intensity * a;
}
