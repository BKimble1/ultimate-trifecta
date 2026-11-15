class_name SeasonCard
extends RefCounted
## Season 1 on Home (2.2): one compact card above Play with Friends, the way
## live games surface their pass on the front screen: the season's name with
## its snowflake, your tier, the Season XP bar to the next tier, and how many
## rewards wait to be claimed.  Tap: the Season Pass.  With no game service
## in the build it says how Season XP is earned instead of showing numbers
## that can't move.

const ICE := Color("9fe3ff")


static func make(width: float = 400.0) -> Button:
	var sid := Catalogue.current_season_id()
	var sd := Catalogue.season(sid)
	var b := UIKit.card_button(Vector2(width, 0), Color(UIKit.SLATE, 0.94))
	b.name = "SeasonCard"
	var v := UIKit.vbox(6)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 16
	v.offset_right = -16
	v.offset_top = 10
	v.offset_bottom = -12
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# overline: snowflake · SEASON 1 · WINTER BREAK · Premium
	var head := UIKit.hbox(8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flake := Icons.IconRect.new("snowflake", ICE, 22)
	flake.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flake.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(flake)
	var title := "SEASON %d · %s" % [int(sd.get("number", 1)), String(sd.get("name", "")).to_upper()]
	var ov := UIKit.styled(title, "overline", UIKit.AMBER)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ov.clip_text = true
	head.add_child(ov)
	var live := Wallet.service_state() != "off"
	var st: Dictionary = Wallet.season_state(sid) if live else {"xp": 0, "premium": false}
	var claim_n := Wallet.claimable(sid).size() if live else 0
	if claim_n > 0:
		var badge := UIKit.chip("%d to claim" % claim_n, UIKit.AMBER, UIKit.NAVY, UIKit.T_OVERLINE + 1)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(badge)
	elif bool(st.get("premium", false)):
		var prem := UIKit.chip("Premium", Color(UIKit.AMBER, 0.2), UIKit.AMBER_HI, UIKit.T_OVERLINE + 1)
		prem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(prem)
	v.add_child(head)
	var xp := int(st.get("xp", 0))
	var tier := maxi(1, Economy.tier_for_xp(sid, xp))
	var top := Economy.max_tier(sid)
	var row := UIKit.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := UIKit.styled("Tier %d" % tier, "label")
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tl)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(60, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", UIKit.box(Color(UIKit.NAVY, 0.75), 5, 0, Color.WHITE, 0))
	bar.add_theme_stylebox_override("fill", UIKit.box(UIKit.TEAL, 5, 0, Color.WHITE, 0))
	bar.max_value = 1.0
	bar.step = 0.001
	var cap_txt := ""
	if not live:
		bar.value = 0.0
		cap_txt = "Play online rounds"
	elif tier >= top:
		bar.value = 1.0
		cap_txt = "Max tier"
	else:
		var lo := Economy.tier_xp(sid, tier)
		var hi := Economy.tier_xp(sid, tier + 1)
		bar.value = clampf(float(xp - lo) / float(maxi(1, hi - lo)), 0.0, 1.0)
		cap_txt = "%d / %d XP" % [xp - lo, hi - lo]
	row.add_child(bar)
	var cap := UIKit.styled(cap_txt, "caption", UIKit.IVORY_MUTED)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	v.add_child(row)
	b.add_child(v)
	b.custom_minimum_size.y = maxf(UIKit.touch_min(), 84.0)
	b.accessibility_name = "Season %d, %s. Tier %d of %d.%s Open the Season Pass." % [int(sd.get("number", 1)), sd.get("name", ""), tier, top,
		(" %d rewards to claim." % claim_n) if claim_n > 0 else ""]
	b.tooltip_text = "Season Pass"
	b.pressed.connect(func() -> void: App.goto(SeasonScreen))
	return b
