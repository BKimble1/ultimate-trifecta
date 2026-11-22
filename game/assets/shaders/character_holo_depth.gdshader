shader_type spatial;
// (build 33) The hologram's first pass (CharacterView.set_hologram): the
// character's own front-most surface into the depth buffer, no colour.  It
// draws before every hologram colour pass (render_priority), so the colour
// pass (character_holo.gdshader, this material's next_pass) blends only the
// surface nearest the camera: no inner faces (the body under the pyjamas,
// the far arm, the inside of the head) show through the translucency, and
// overlapping parts never sort against each other.  It sits 2 mm behind the
// true surface along the view ray, so the colour pass never z-fights it.
render_mode unshaded, depth_draw_always, cull_back, shadows_disabled, skip_vertex_transform, fog_disabled;

void vertex() {
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += normalize(VERTEX) * 0.002;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
