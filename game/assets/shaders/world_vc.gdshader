shader_type spatial;
// Static campus geometry: vertex colour albedo (with baked AO and warm lamp
// light), per-vertex emission (CUSTOM0.x) and gentle foliage sway
// (CUSTOM0.y). Cheap enough for mobile.
render_mode diffuse_lambert, specular_disabled;

#include "res://assets/shaders/world_common.gdshaderinc"
