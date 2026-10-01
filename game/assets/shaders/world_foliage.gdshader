shader_type spatial;
// Tree canopies: same look as world_vc plus a dithered fade near the camera.
render_mode diffuse_lambert, specular_disabled;

#define NEAR_FADE
#include "res://assets/shaders/world_common.gdshaderinc"
