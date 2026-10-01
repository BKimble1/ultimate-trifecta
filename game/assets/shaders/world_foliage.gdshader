shader_type spatial;
// Tree canopies: same look as world_vc, and the canopy parts around the
// camera (NEAR_PART in world_common) instead of a dithered fade.
render_mode diffuse_lambert, specular_disabled;

#define NEAR_PART
#include "res://assets/shaders/world_common.gdshaderinc"
