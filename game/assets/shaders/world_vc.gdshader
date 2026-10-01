shader_type spatial;
// Static campus geometry: vertex colour albedo, per-vertex emission (UV2.x)
// and gentle foliage sway (UV2.y). Cheap enough for mobile.
render_mode diffuse_lambert, specular_disabled;

#include "res://assets/shaders/world_common.gdshaderinc"
