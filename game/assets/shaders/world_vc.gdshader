shader_type spatial;
// Static campus geometry: vertex colour albedo (with baked AO and warm lamp
// light), per-vertex emission (CUSTOM0.x), gentle foliage sway (CUSTOM0.y)
// and, from V5, a material id (UV.x) that picks world-space detail, bump and
// highlights (world_common).  Cheap enough for mobile: two small mipmapped
// masks, no tangents, no extra lights.
render_mode diffuse_lambert, specular_schlick_ggx;

#include "res://assets/shaders/world_common.gdshaderinc"
