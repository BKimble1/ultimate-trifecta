extends Control
## Development-only sheet (src/dev: never exported): every V7 emote icon in
## its card well (with the well's centre lines and the icon's bounding
## circle), the badges, Coins and Coin piles, and every name card drawn as
## it appears when equipped.  Renders one PNG and quits.
##   tools/gd.sh --path game --resolution 1800x1800 res://src/dev/menus_art_sheet.tscn -- --out=FILE

var out := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	await get_tree().process_frame
	queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if out != "":
		get_viewport().get_texture().get_image().save_png(out)
		printerr("CAPTURE %s" % out)
	get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UIKit.NAVY)
	var f := UIKit.font_w(600)
	var y := 20.0
	draw_string(f, Vector2(20, y + 18), "Emotes in a 110-unit well (centre lines; circle = icon radius)", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.IVORY_MUTED)
	y += 30
	var x := 20.0
	for i in TC.EMOTES.size():
		var well := Rect2(Vector2(x, y), Vector2(112, 100))
		draw_style_box(UIKit.box(Color(UIKit.NAVY.lightened(0.12), 1.0), UIKit.R_SMALL), well)
		var c := well.get_center()
		var r := minf(well.size.x, well.size.y) * 0.36
		draw_line(Vector2(c.x, well.position.y), Vector2(c.x, well.end.y), Color(1, 0, 0, 0.35), 1.0)
		draw_line(Vector2(well.position.x, c.y), Vector2(well.end.x, c.y), Color(1, 0, 0, 0.35), 1.0)
		draw_arc(c, r, 0, TAU, 48, Color(0, 1, 1, 0.35), 1.0)
		Icons.draw_shape(self, Icons.emote_icon(i), c, r, UIKit.AMBER)
		draw_string(f, Vector2(x, well.end.y + 20), String(TC.EMOTE_LABELS[TC.EMOTES[i]]), HORIZONTAL_ALIGNMENT_CENTER, 112, 16, UIKit.IVORY)
		x += 124
	y += 150
	x = 20.0
	for i in TC.EMOTES.size():
		Icons.draw_shape(self, Icons.emote_icon(i), Vector2(x + 24, y + 24), 22, UIKit.IVORY)
		Icons.draw_shape(self, Icons.emote_icon(i), Vector2(x + 80, y + 24), 14, UIKit.TEAL)
		x += 124
	y += 70
	draw_string(f, Vector2(20, y + 18), "Badges", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.IVORY_MUTED)
	y += 30
	x = 20.0
	for it in Catalogue.all_items():
		var id := String(it["id"])
		if id.begins_with("badge:"):
			CommerceArt.badge(self, id, Vector2(x + 60, y + 60), 56)
			CommerceArt.badge(self, id, Vector2(x + 60, y + 150), 26)
			CommerceArt.badge(self, id, Vector2(x + 60 + 50, y + 150), 26, true)
			draw_string(f, Vector2(x, y + 200), Catalogue.display_name(id), HORIZONTAL_ALIGNMENT_CENTER, 130, 16, UIKit.IVORY)
			x += 150
	y += 220
	draw_string(f, Vector2(20, y + 18), "Coins: 1, piles for 25 / 50 / 500 / 1,500 / 3,500, dimmed", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.IVORY_MUTED)
	y += 30
	x = 20.0
	CommerceArt.coin(self, Vector2(x + 60, y + 60), 50)
	x += 150
	for n in [25, 50, 500, 1500, 3500]:
		CommerceArt.coin_pile(self, Vector2(x + 60, y + 60), 40, n)
		x += 150
	CommerceArt.coin_pile(self, Vector2(x + 60, y + 60), 40, 50, true)
	CommerceArt.coin(self, Vector2(x + 200, y + 60), 16)
	CommerceArt.coin(self, Vector2(x + 240, y + 60), 11)
	y += 140
	draw_string(f, Vector2(20, y + 18), "Name cards as equipped (player name; one with a badge; a small one)", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.IVORY_MUTED)
	y += 30
	x = 20.0
	var k := 0
	for it in Catalogue.all_items():
		var id := String(it["id"])
		if id.begins_with("card:"):
			CommerceArt.name_card(self, Rect2(Vector2(x, y), Vector2(250, 96)), id, "Sleepy Otter", "badge:lantern" if k == 1 else "", 30)
			CommerceArt.name_card(self, Rect2(Vector2(x, y + 110), Vector2(130, 50)), id, "Sleepy Otter", "", 18)
			x += 270
			k += 1
			if k == 5:
				x = 20.0
				y += 180
