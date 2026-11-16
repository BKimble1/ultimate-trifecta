shader_type spatial;
// (2.2 build 16) The Censored outfit's pixel blur: a soft box over the shorts
// area made of big square "pixels" in the wearer's skin tones (each cell a
// little lighter or darker, a hint of shading), so it reads as a TV-style
// censor mosaic.  The cells are in the box's own space, so they stay put on
// the body as it moves.
render_mode diffuse_lambert_wrap, specular_disabled, cull_back;

uniform vec3 skin : source_color = vec3(0.95, 0.76, 0.62);
uniform float cell = 0.045;

varying vec3 obj;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	obj = VERTEX;
}

void fragment() {
	vec3 c = floor(obj / cell);
	float h = hash(c);
	float h2 = hash(c + vec3(7.1, 3.3, 5.7));
	// lighter and darker skin squares, a few warmer ones
	vec3 col = skin * mix(0.78, 1.16, h);
	col = mix(col, col * vec3(1.06, 0.92, 0.88), step(0.72, h2));
	// a faint grid between the squares
	vec3 f = fract(obj / cell);
	float edge = min(min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)), min(f.z, 1.0 - f.z));
	col *= mix(0.9, 1.0, smoothstep(0.0, 0.08, edge));
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
