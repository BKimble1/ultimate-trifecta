extends Control
## Development-only check: renders the UI font at each weight the UI asks for
## and prints the ink coverage per row, so a weight that silently falls back
## to the default instance shows up as identical numbers.
##   tools/gd.sh --path game res://src/dev/font_weights.tscn -- --out=FILE.png
const WEIGHTS := [400, 500, 600, 650, 700, 800]
## V5: the UI ships only Manrope's static instances (the variable master is
## kept in art_src/fonts); the tabular-digit variants are checked too.
const VAR_WEIGHTS := [600, 800]


static func _variable(w: int) -> Font:
	return UIKit.font_num(w)

var out := ""
var _f := 0
var _labels: Array[Label] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.split("=")[1]
	var bg := ColorRect.new()
	bg.color = Color.WHITE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	for i in WEIGHTS.size() + VAR_WEIGHTS.size():
		var l := Label.new()
		l.text = "Ultimate Trifecta — Ready up! 0123"
		l.add_theme_font_override("font", UIKit.font_w(WEIGHTS[i]) if i < WEIGHTS.size() else _variable(VAR_WEIGHTS[i - WEIGHTS.size()]))
		l.add_theme_font_size_override("font_size", 40)
		l.add_theme_color_override("font_color", Color.BLACK)
		l.position = Vector2(20, 20 + i * 52)
		add_child(l)
		_labels.append(l)


func _process(_d: float) -> void:
	_f += 1
	if _f < 5:
		return
	var img := get_viewport().get_texture().get_image()
	if out != "":
		img.save_png(out)
	var xf := get_viewport().get_final_transform()
	for i in _labels.size():
		var r: Rect2 = xf * _labels[i].get_global_rect()
		var ink := 0.0
		for y in range(int(r.position.y), mini(int(r.end.y), img.get_height())):
			for x in range(int(r.position.x), mini(int(r.end.x), img.get_width())):
				ink += 1.0 - img.get_pixel(x, y).r
		if i < WEIGHTS.size():
			printerr("FONTW static request=%d ink=%.0f font=%s" % [WEIGHTS[i], ink, UIKit.font_w(WEIGHTS[i]).resource_path.get_file()])
		else:
			printerr("FONTW variable wght=%d ink=%.0f" % [VAR_WEIGHTS[i - WEIGHTS.size()], ink])
	get_tree().quit()
