shader_type canvas_item;
// The match loading screen's character loop (assets/loading, built by
// tools/make_loading_loop.py): one frame of a grid atlas, its edges
// feathered into the screen's background (which continues the
// frame's own side colours), so no edge shows on any aspect ratio.

uniform sampler2D frames : source_color, filter_linear, repeat_disable;
uniform vec2 grid = vec2(1.0, 1.0);        // columns, rows in the atlas
uniform float frame = 0.0;
uniform vec4 feather = vec4(0.09, 0.08, 0.09, 0.04);   // left, top, right, bottom (fraction of the frame)
uniform float alpha = 1.0;

void fragment() {
	float f = floor(frame + 0.5);
	vec2 cell = vec2(mod(f, grid.x), floor(f / grid.x));
	// stay a texel inside the cell so filtering never reads the next frame
	vec2 inset = grid / vec2(textureSize(frames, 0));
	vec2 uv = clamp(UV, inset, vec2(1.0) - inset);
	vec3 c = texture(frames, (cell + uv) / grid).rgb;
	float a = smoothstep(0.0, feather.x, UV.x) * smoothstep(0.0, feather.z, 1.0 - UV.x)
		* smoothstep(0.0, feather.y, UV.y) * smoothstep(0.0, feather.w, 1.0 - UV.y);
	// times the incoming COLOR: the screen's fade (modulate) applies here too
	COLOR = vec4(c, a * alpha) * COLOR;
}
