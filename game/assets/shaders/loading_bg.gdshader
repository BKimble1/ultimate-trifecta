shader_type canvas_item;
// Match loading background (V5): a calm night sky behind the runners.
// Vertical gradient, a soft moonlit glow, a faint horizon, the moonlit
// ground the runners stand on, a few still stars (no twinkle) and a little
// dither so the large gradients never band.  Static: nothing animates.

uniform vec3 top : source_color = vec3(0.035, 0.055, 0.13);
uniform vec3 mid : source_color = vec3(0.075, 0.13, 0.27);
uniform vec3 ground : source_color = vec3(0.05, 0.085, 0.18);
uniform vec3 glow : source_color = vec3(0.24, 0.36, 0.66);
uniform vec2 aspect = vec2(1.0, 1.0);      // screen size (canvas units)
uniform vec2 glow_c = vec2(0.5, 0.42);     // glow centre (UV)
uniform float horizon = 0.66;              // horizon line (UV y)
uniform vec2 pool_c = vec2(0.5, 0.82);     // where the runners stand (UV)
uniform float pool_w = 0.3;                // pool half-width (fraction of width)

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = UV;
	vec3 c = mix(top, mid, smoothstep(0.0, horizon, uv.y));
	c = mix(c, ground, smoothstep(horizon - 0.02, horizon + 0.12, uv.y));
	// moonlit glow behind the group
	vec2 d = (uv - glow_c) * vec2(aspect.x / aspect.y, 1.0);
	c += glow * 0.32 * exp(-dot(d, d) * 5.5);
	// faint horizon line of light
	c += glow * 0.06 * exp(-pow((uv.y - horizon) * 38.0, 2.0));
	// the moonlit ground under the runners
	vec2 g = (uv - pool_c) / vec2(pool_w, pool_w * 0.22 * aspect.x / aspect.y);
	c += glow * 0.14 * exp(-dot(g, g) * 1.4);
	// still stars, sparse, upper sky only
	vec2 cell = floor(uv * aspect / 22.0);
	float h = hash12(cell);
	if (h > 0.965 && uv.y < horizon * 0.62) {
		vec2 sp = (fract(uv * aspect / 22.0) - vec2(hash12(cell + 7.1), hash12(cell + 3.7))) * 22.0;
		c += vec3(0.75, 0.8, 1.0) * (0.25 + 0.35 * fract(h * 41.0)) * smoothstep(1.3, 0.0, length(sp));
	}
	// dither (±0.5/255) against banding
	c += (hash12(FRAGCOORD.xy) - 0.5) / 255.0;
	COLOR = vec4(c, 1.0) * COLOR;
}
