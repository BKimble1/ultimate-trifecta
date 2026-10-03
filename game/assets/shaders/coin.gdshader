shader_type spatial;
// V6 gold coins: one MultiMesh for all of a round's coins, one material.
// The spin and the bob run here (no per-frame CPU work); INSTANCE_CUSTOM.r
// is a phase, .a is 1 while the coin is out and 0 once taken (the instance
// collapses to a point and draws nothing).  Warm gold that reads at night:
// metal highlights plus a restrained emission and a soft rim.
render_mode diffuse_lambert, specular_schlick_ggx, shadows_disabled;

uniform vec3 gold : source_color = vec3(1.0, 0.76, 0.24);
uniform float glow = 0.55;
uniform float spin_speed = 1.8;
uniform float bob = 0.12;

varying float v_alive;

void vertex() {
	float a = TIME * spin_speed + INSTANCE_CUSTOM.r * 6.2831;
	float c = cos(a);
	float s = sin(a);
	VERTEX = vec3(c * VERTEX.x + s * VERTEX.z, VERTEX.y, -s * VERTEX.x + c * VERTEX.z);
	NORMAL = vec3(c * NORMAL.x + s * NORMAL.z, NORMAL.y, -s * NORMAL.x + c * NORMAL.z);
	VERTEX.y += sin(TIME * 2.2 + INSTANCE_CUSTOM.r * 6.2831) * bob;
	v_alive = INSTANCE_CUSTOM.a;
	VERTEX *= INSTANCE_CUSTOM.a;
}

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = gold;
	METALLIC = 0.8;
	ROUGHNESS = 0.32;
	SPECULAR = 0.6;
	EMISSION = gold * (glow + rim * 0.6);
}
