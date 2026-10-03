// Shared body of character.gdshader (back faces culled) and
// character_two_sided.gdshader (cull_disabled, for parts whose cloth folds
// over itself, such as the nightcap).  Godot flips the normal on back faces
// of a double-sided material, so a fold lights like the outside fabric.
// Skinned characters (assets/characters/runner.glb, built by tools/character).
// Vertex data contract (see tools/character/geo.py):
//   COLOR.rgb  base albedo, LINEAR (Blender exports glTF COLOR_0 linear and
//              Godot keeps it, so there is no sRGB conversion here)
//   COLOR.a    tint selector: round(a*5) 0 none, 1 hair, 2 skin, 3 secondary,
//              4 dark, 5 primary.  albedo = base * tint
//   UV         x = stripe flag, 1 - y = stripe coordinate in metres
//   UV2        x = roughness, 1 - y = material class (0 cloth, .25 skin,
//              .5 rubber, .75 gloss, .875 lit gloss, 1 emissive)
// Characters cast shadows but do not receive them: at gameplay shadow-map
// resolution self-shadowing (collar on shirt, cap on face) breaks up into
// stipple and jaggies where the wrap lighting meets the shadow terminator.
// The wrap diffuse alone shades the round forms cleanly, and it saves the
// shadow lookups on every skinned pixel.

instance uniform vec3 tint_primary : source_color = vec3(0.36, 0.55, 0.95);
instance uniform vec3 tint_secondary : source_color = vec3(0.70, 0.80, 1.0);
instance uniform vec3 tint_dark : source_color = vec3(0.20, 0.30, 0.60);
instance uniform vec3 tint_skin : source_color = vec3(0.98, 0.82, 0.68);
instance uniform vec3 tint_hair : source_color = vec3(0.32, 0.22, 0.16);
instance uniform float stripes = 0.0;   // stripes per metre, 0 = plain
instance uniform float flash = 0.0;
instance uniform vec3 flash_color : source_color = vec3(1.0);
// environment-dependent rim (warm indoors, cool moonlight outdoors); small on purpose
instance uniform vec3 rim_color : source_color = vec3(0.55, 0.68, 1.0);
instance uniform float rim_strength = 0.10;
// 1 right out of the water, fading to 0: darker, glossier cloth and skin
instance uniform float wet = 0.0;
// V6: a little warm self-light on skin (more under cool moonlight than in the
// warm dorm), so light tones keep their warmth at night instead of going
// grey-lavender; dark tones keep the V4 lift below
instance uniform float skin_warm = 0.0;

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
	if (UV.x > 0.5 && stripes > 0.0) {
		float coord = (1.0 - UV.y) * stripes;
		float f = fract(coord);
		float aa = max(fwidth(coord), 1e-4) * 0.75;
		float band = smoothstep(0.5 - aa, 0.5 + aa, f) * (1.0 - smoothstep(1.0 - aa, 1.0, f));
		alb = mix(alb, base * tint_secondary, band * 0.9);
	}
	float cls = 1.0 - UV2.y;
	float soak = wet * (cls < 0.37 ? (cls < 0.12 ? 1.0 : 0.45) : 0.2);
	alb *= 1.0 - 0.28 * soak;
	ALBEDO = alb;
	ROUGHNESS = clamp(UV2.x * (1.0 - 0.55 * soak), 0.05, 1.0);
	SPECULAR = 0.3;
	vec3 emit = vec3(0.0);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	if (cls < 0.12) {           // matte cloth: low spec, soft sheen at grazing angles
		SPECULAR = 0.18;
		emit += rim_color * rim * rim_strength * (0.6 + 0.4 * alb);
	} else if (cls < 0.37) {    // skin: warm wrap, a little transmission, matte
		SPECULAR = 0.22;
		BACKLIGHT = alb * 0.22;
		emit += rim_color * rim * rim_strength * 0.5;
		// V4: keep darker skin tones readable in the night scenes without
		// lifting light ones (checked across all eight tones, campus and
		// studio light): a little self-light that grows as the tone darkens
		float lum = dot(tint_skin, vec3(0.299, 0.587, 0.114));
		emit += alb * 0.4 * clamp(0.72 - lum, 0.0, 0.5);
		emit += alb * vec3(1.0, 0.62, 0.42) * skin_warm;
	} else if (cls < 0.62) {    // rubber / leather
		SPECULAR = 0.42;
	} else if (cls < 0.81) {    // gloss: buttons, badges, plastic, irises
		SPECULAR = 0.55;
	} else if (cls < 0.94) {    // lit gloss: eye whites keep a little self-light so
		SPECULAR = 0.55;        // faces stay readable in night scenes
		emit += alb * 0.35;
	} else {                    // emissive: eye catch-lights, flashlight lens
		emit += alb * 1.6;
	}
	EMISSION = emit + flash_color * flash;
}
