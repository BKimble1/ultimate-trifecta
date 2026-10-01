class_name QualityPreset
extends RefCounted
## The two graphics presets.  They are fixed choices made by the player; the
## game never switches them automatically (no quality oscillation).  UI is
## drawn by the 2D canvas at native resolution in both, so text stays sharp.
##
##   Standard       3D at full window resolution, 2x MSAA, 2-split 2048
##                  moon shadows from the campus and characters, gentle glow,
##                  60 fps cap.  Target: 60 fps on iPhone 14-class devices
##                  (to be confirmed on hardware; see TEST_REPORT.md).
##   Battery Saver  3D at 80% resolution (bilinear upscale, UI unaffected),
##                  2x MSAA, one 1024 shadow split covering 30 m and only
##                  characters/carts cast, no glow, more aggressive mesh LOD,
##                  30 fps cap.
## 4x MSAA is not used: comparing it needs measured GPU headroom on a device.

const STANDARD := 1
const BATTERY := 0

## what apply() last set (read by the dev diagnostics)
static var applied := -1
static var shadow_atlas := 0


static func apply(q: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var root := tree.root
	if q >= STANDARD:
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		root.scaling_3d_scale = 1.0
		root.msaa_3d = Viewport.MSAA_2X
		root.mesh_lod_threshold = 1.0
		RenderingServer.directional_shadow_atlas_set_size(2048, true)
	else:
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		root.scaling_3d_scale = 0.8
		root.msaa_3d = Viewport.MSAA_2X
		root.mesh_lod_threshold = 3.0
		RenderingServer.directional_shadow_atlas_set_size(1024, true)
	applied = q
	shadow_atlas = 2048 if q >= STANDARD else 1024
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	root.use_taa = false
	if OS.has_feature("mobile"):
		Engine.max_fps = 60 if q >= STANDARD else 30


static func label(q: int) -> String:
	return "Standard" if q >= STANDARD else "Battery Saver"
