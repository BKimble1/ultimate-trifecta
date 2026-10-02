shader_type spatial;
// Skinned characters.  The vertex data contract and lighting notes are in
// character.gdshaderinc.
render_mode diffuse_lambert_wrap, specular_schlick_ggx, shadows_disabled;

#include "res://assets/shaders/character.gdshaderinc"
