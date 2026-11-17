class_name SeasonPill
extends Button
## (2.2 build 18) Home's Season Pass progress: the pass emblem, your tier, a
## thin bar to the next tier and the next outfit or item you can earn
## ("2 tiers to Night Owl").  Tap: the Season Pass.  Updates in place when
## the wallet changes; hidden before there is any season data.

const W := 360.0
var _tier: Label
var _next: Label
var _bar: Bar


func _init() -> void:
	name = "SeasonPill"
	UIKit.make_card(self, Vector2(W, 0), Color(UIKit.SLATE, 0.86))
	var f := UIKit.face_of(self)
	var h := UIKit.hbox(10)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -12
	h.offset_top = 6
	h.offset_bottom = -6
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.add_child(h)
	var ic := CommerceArt.Pic.new("glyph", "pass", UIKit.AMBER, 34)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := UIKit.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var top := UIKit.hbox(8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tier = UIKit.styled("", "label", UIKit.IVORY)
	_tier.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_tier)
	_next = UIKit.styled("", "caption", UIKit.AMBER)
	_next.add_theme_font_size_override("font_size", 16)
	_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_next.clip_text = true
	_next.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_next.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_next)
	v.add_child(top)
	_bar = Bar.new()
	_bar.custom_minimum_size = Vector2(0, 8)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_bar)
	custom_minimum_size = Vector2(W, maxf(UIKit.touch_min(), 58.0))
	pressed.connect(func() -> void: NavShell.go("pass"))


func _ready() -> void:
	Wallet.changed.connect(refresh)
	refresh()


## The next tier at or above `from` whose reward (free, or Premium when
## owned) is an item: [tier, item id], or [-1, ""].
static func next_item(sid: String, from: int, premium: bool) -> Array:
	for t in Catalogue.season_tiers(sid):
		var tier := int(t["tier"])
		if tier <= from:
			continue
		for track in (["free", "premium"] if premium else ["free"]):
			var r: Variant = t.get(track)
			if r is Dictionary and (r as Dictionary).has("item"):
				return [tier, String(r["item"])]
	return [-1, ""]


func refresh() -> void:
	var sid := Catalogue.current_season_id()
	if sid == "" or Catalogue.season_tiers(sid).is_empty():
		visible = false
		return
	var st := Wallet.season_state(sid)
	var p := Economy.tier_progress(sid, int(st["xp"]))
	var tier := int(p["tier"])
	_tier.text = "Tier %d" % tier
	_bar.frac = float(p["frac"])
	_bar.queue_redraw()
	var nx := SeasonPill.next_item(sid, tier, bool(st["premium"]))
	if int(nx[0]) < 0:
		_next.text = "Every tier reached" if int(p["next"]) < 0 else ""
	else:
		var away := int(nx[0]) - tier
		_next.text = ("%d tier%s to %s" % [away, "" if away == 1 else "s", Catalogue.display_name(String(nx[1]))])
	accessibility_name = "Season Pass, tier %d. %s" % [tier, _next.text]


class Bar:
	extends Control
	var frac := 0.0

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UIKit.box(Color(UIKit.NAVY, 0.8), 999), r)
		if frac > 0.0:
			var w := maxf(size.y, size.x * clampf(frac, 0.0, 1.0))
			draw_style_box(UIKit.box(UIKit.AMBER, 999), Rect2(Vector2.ZERO, Vector2(w, size.y)))
