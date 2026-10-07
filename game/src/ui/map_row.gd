class_name MapRow
extends RefCounted
## The compact Map row of the party settings and Practice: a small preview,
## the map's title and tag, and "Change" (or a lock when someone else
## picks).  Pressing it opens MapSheet.


static func make(id: String, editable: bool) -> Button:
	var mid := CampusMaps.sanitize(id) if CampusMaps.has(id) else id
	var known := CampusMaps.has(mid)
	var row_h := maxf(UIKit.touch_min(), 84.0)
	var b := UIKit.card_button(Vector2(520, row_h), UIKit.SLATE)
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
	var title := UIKit.styled(CampusMaps.title(mid) if known else "Unknown map — update the game", "label")
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(title)
	if known:
		var tag := UIKit.chip(String(CampusMaps.def(mid)["tag"]), Color(UIKit.NAVY, 0.6), UIKit.IVORY_MUTED)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(tag)
	h.add_child(UIKit.spacer_h())
	if editable:
		var ch := UIKit.styled("Change", "label", UIKit.TEAL)
		ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(ch)
	else:
		var lk := Icons.IconRect.new("lock", UIKit.IVORY_MUTED, 24)
		lk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(lk)
	b.add_child(h)
	b.accessibility_name = "Map: %s%s" % [CampusMaps.title(mid) if known else "unknown, update the game", ". Change" if editable else " (set by the host)"]
	b.tooltip_text = "Map"
	return b
