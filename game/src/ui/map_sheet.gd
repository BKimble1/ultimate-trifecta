class_name MapSheet
extends RefCounted
## The map chooser: a focused sheet with one large card per map (its
## in-engine preview, title, a small Classic/New tag and one short line),
## opened from the Map row of the party settings or Practice.  The chosen
## map is marked by a teal border, a check and the word "Selected" (never
## by colour alone).  Guests see the host's choice read-only.
##
## Previews are static images captured offline from the finished maps
## (tools/capture_map_previews.sh); nothing here renders a campus.
## Controllers: the cards take focus left/right, A picks, B closes (the
## opener gets focus back: Screen.push_modal).

const CARD_W := 540.0
const PREVIEW_ASPECT := 16.0 / 9.0

static var _tex: Dictionary = {}     # map id -> Texture2D (only the two small previews)


## The preview image of a map (loaded once; null if missing).
static func preview(id: String) -> Texture2D:
	if not _tex.has(id):
		var p := String(CampusMaps.def(id).get("preview", ""))
		_tex[id] = load(p) if p != "" and ResourceLoader.exists(p) else null
	return _tex[id]


## Opens the sheet over `screen`.  editable: the player may pick (the host,
## or Practice); on_pick(id) runs when a map is chosen (the sheet closes).
static func open(screen: Screen, current: String, editable: bool, on_pick: Callable) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(UIKit.NAVY, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var vis := screen.get_viewport().get_visible_rect().size
	var sm := UIKit.safe_margins(screen.get_viewport())
	var avail := vis.x - sm.position.x - sm.size.x - 64.0
	var ids: Array[String] = CampusMaps.ids() if editable else [CampusMaps.sanitize(current)]
	# two cards side by side where they fit at a readable size; otherwise
	# one above the other in a scroll (never two tiny cards)
	var side_by_side := ids.size() == 1 or avail >= 2.0 * 420.0 + 24.0
	var card_w := clampf((avail - 24.0) * 0.5, 420.0, CARD_W) if ids.size() > 1 and side_by_side else minf(avail, CARD_W)
	var p := UIKit.panel(Color(UIKit.SLATE, 0.99), UIKit.R_PANEL, 26)
	var v := UIKit.vbox(16)
	p.add_child(v)
	var head := UIKit.hbox(12)
	head.add_child(UIKit.styled("Map", "headline"))
	head.add_child(UIKit.spacer_h())
	if not editable:
		head.add_child(UIKit.styled("The host picks the map", "caption", UIKit.IVORY_MUTED))
	v.add_child(head)
	var row: BoxContainer = UIKit.hbox(24) if side_by_side else UIKit.vbox(16)
	var cards: Array[Button] = []
	var close := func() -> void:
		if is_instance_valid(root):
			root.queue_free()
	for id in ids:
		var c := _card(id, card_w, id == CampusMaps.sanitize(current), editable)
		var pick_id := id
		if editable:
			c.pressed.connect(func() -> void:
				close.call()
				if on_pick.is_valid():
					on_pick.call(pick_id))
		row.add_child(c)
		cards.append(c)
	if side_by_side:
		v.add_child(row)
	else:
		var sc := UIKit.scroll_area()
		sc.custom_minimum_size = Vector2(card_w + 12.0, minf(vis.y - sm.position.y - sm.size.y - 200.0, 2.0 * (card_w / PREVIEW_ASPECT + 150.0)))
		sc.add_child(row)
		v.add_child(sc)
	var foot := UIKit.hbox(10)
	foot.add_child(UIKit.spacer_h())
	var done := UIKit.secondary("Close" if not editable else "Cancel", Vector2(200, 68))
	done.pressed.connect(close)
	foot.add_child(done)
	v.add_child(foot)
	root.add_child(p)
	screen.add_child(root)
	var sz := p.get_combined_minimum_size()
	p.position = ((vis - sz) * 0.5).max(sm.position + Vector2(8, 8))
	Motion.appear(p, 10.0, UIKit.T_FAST)
	screen.push_modal(root, close)
	# focus: the chosen card (Back/Cancel/B closes; the opener gets focus back)
	var first: Button = cards[0]
	for i in ids.size():
		if ids[i] == CampusMaps.sanitize(current):
			first = cards[i]
	UIKit.soft_focus.call_deferred(first if editable else done)
	return root


## One map card: preview (uncropped, 16:9), title and tag, one line, and the
## selected mark.
static func _card(id: String, w: float, selected: bool, editable: bool) -> Button:
	var d := CampusMaps.def(id)
	var ph := roundf(w / PREVIEW_ASPECT)
	var b := UIKit.card_button(Vector2(w, ph + 150.0), UIKit.SLATE_HI if selected else UIKit.SLATE)
	b.focus_mode = Control.FOCUS_ALL if editable else Control.FOCUS_NONE
	if not editable:
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UIKit.vbox(10)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 12
	v.offset_right = -12
	v.offset_bottom = -12
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var img := TextureRect.new()
	img.texture = preview(id)
	img.custom_minimum_size = Vector2(w - 24.0, ph - 24.0)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(img)
	var t := UIKit.hbox(10)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := UIKit.styled(String(d["title"]), "headline")
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(title)
	var tag := UIKit.chip(String(d["tag"]), Color(UIKit.NAVY, 0.6), UIKit.IVORY_MUTED)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(tag)
	t.add_child(UIKit.spacer_h())
	if selected:
		var mark := UIKit.hbox(6)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := Icons.IconRect.new("check", UIKit.TEAL, 26)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.add_child(ic)
		var sl := UIKit.styled("Selected", "label", UIKit.TEAL)
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.add_child(sl)
		t.add_child(mark)
	v.add_child(t)
	var blurb := UIKit.styled(String(d["blurb"]), "caption", UIKit.IVORY_MUTED)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(w - 24.0, 0)
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(blurb)
	b.add_child(v)
	UIKit.set_selected(b, selected)
	b.accessibility_name = "%s, %s map. %s%s" % [d["title"], String(d["tag"]).to_lower(), d["blurb"], " Selected." if selected else ""]
	b.tooltip_text = String(d["title"])
	return b
