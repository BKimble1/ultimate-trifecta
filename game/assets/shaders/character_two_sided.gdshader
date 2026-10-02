shader_type spatial;
// The character shader drawn without back-face culling (see character.gdshaderinc).
render_mode diffuse_lambert_wrap, specular_schlick_ggx, shadows_disabled, cull_disabled;

#include "res://assets/shaders/character.gdshaderinc"
