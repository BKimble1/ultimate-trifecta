shader_type canvas_item;
// The match loading screen's runner loop (V5, assets/loading/rig_loop_*,
// rendered from the game rig by src/dev/loading_loop_render.tscn and packed
// by tools/make_loading_loop_rig.py): one frame of a grid atlas, drawn with
// premultiplied alpha over the screen's own background.  The frames carry
// their own soft contact shadows, so the runners stand on the screen.
render_mode blend_premul_alpha;

uniform sampler2D frames : filter_linear, repeat_disable;
uniform vec2 grid = vec2(1.0, 1.0);        // columns, rows in the atlas
uniform float frame = 0.0;
uniform float alpha = 1.0;

void fragment() {
	float f = floor(frame + 0.5);
	vec2 cell = vec2(mod(f, grid.x), floor(f / grid.x));
	// stay half a texel inside the cell so filtering never reads the next frame
	vec2 inset = 0.5 * grid / vec2(textureSize(frames, 0));
	vec2 uv = clamp(UV, inset, vec2(1.0) - inset);
	vec4 c = texture(frames, (cell + uv) / grid);
	// premultiplied: the screen's fade (modulate) scales colour and coverage
	COLOR = c * (alpha * COLOR.a);
}
