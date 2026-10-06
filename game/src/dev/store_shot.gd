extends RefCounted
## App Store screenshot mode for the development capture drivers (src/dev:
## never exported).  `--store-shot` on the command line turns the drivers'
## evidence stamps, labels and debug overlays off, so a frame shows only
## what the game itself draws; images are saved as RGB PNGs (no alpha), as
## App Store Connect wants them.  tools/capture_store_screenshots.sh passes
## it to the store drivers (store_capture.gd, store_match_capture.gd); any
## evidence driver that reads it (lobby_light_capture.gd,
## season_final_capture.gd, friends_capture.gd, capture_shop_p8.gd and its
## Shop subclasses, capture.gd's snap) can re-render its own shots unstamped.
##
## Store mode never changes what the game shows: the fixtures (test-double
## service, simulated store, fictional players) stay what they are, and the
## screenshot README says so.


static func on() -> bool:
	return OS.get_cmdline_user_args().has("--store-shot")


## Store mode: no beta diagnostics overlay, whatever the profile says.
static func quiet_overlays() -> void:
	if not on():
		return
	var tree := Engine.get_main_loop() as SceneTree
	var diag: Node = tree.root.get_node_or_null("Diag") if tree else null
	if diag != null:
		diag.set("enabled", false)
		diag.set("overlay", false)


## The frame as an RGB PNG (App Store Connect rejects images with alpha).
static func save_rgb(img: Image, path: String) -> Error:
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	return img.save_png(path)
