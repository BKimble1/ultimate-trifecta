class_name MapRow
extends RefCounted
## The compact Map row of the party settings and Practice: a small preview,
## the map's title and tag, and "Change" (or a lock when someone else
## picks).  Pressing it opens MapSheet.


static func make(id: String, editable: bool) -> Button:
	var mid := CampusMaps.sanitize(id) if CampusMaps.has(id) else id
	var known := CampusMaps.has(mid)
	var row_h := maxf(UIKit.touch_min(), 84.0)
	var b := UIKit.card_button(Vector2(420, row_h), UIKit.SLATE)
	var h := UIKit.hbox(14)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -16
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var img := TextureRect.new()
	img.texture = MapSheet.preview(mid) if known else null
	img.custom_minimum_size = Vector2(roundf((row_h - 16.0) * MapSheet.PREVIEW_ASPECT), row_h - 16.0)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(img)
	# (2.3) the name over its tag (side by side they ran past the card on a
	# phone), and a chevron for "change" as on the playlist tile
	var tv := UIKit.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tv)
	var title := UIKit.styled(CampusMaps.title(mid) if known else "Unknown map — update the game", "label")
	title.add_theme_font_override("font", UIKit.font_w(800))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(title)
	if known:
		var tag := UIKit.styled(String(CampusMaps.def(mid)["tag"]) + ("  ·  Change" if editable else "  ·  Set by the host"), "caption", UIKit.TEAL if editable else UIKit.IVORY_MUTED)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(tag)
	if editable:
		var ch := Icons.IconRect.new("chevron", Color(UIKit.IVORY, 0.7), 26)
		ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ch)
	else:
		var lk := Icons.IconRect.new("lock", UIKit.IVORY_MUTED, 24)
		lk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(lk)
	b.add_child(h)
	b.accessibility_name = "Map: %s%s" % [CampusMaps.title(mid) if known else "unknown, update the game", ". Change" if editable else " (set by the host)"]
	b.tooltip_text = "Map"
	return b
