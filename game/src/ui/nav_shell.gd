class_name NavShell
extends HBoxContainer
## V6 navigation: Play · Locker · Shop · Season Pass, one reusable bar used
## by home, the party lobby, the Locker, the Shop and the Season Pass.
##   Play         the hub you came from (the party lobby while you're in a
##                party, else home); the party stays intact while you shop
##   Locker       owned and free items: browse, preview, equip, save
##   Shop         every purchase (Coins, skins, Coin packs, Season 1)
##   Season Pass  progress, tiers and claims
## Tabs are pill buttons with an icon and a label.  When the bar doesn't fit
## (iPhone SE, iPad 4:3 next to other controls) the inactive tabs keep only
## their icon (their name stays in the accessibility label and tooltip);
## the active tab always shows its name.  A small dot marks something to
## act on (rewards to claim, a purchase being delivered).
## Leaving a screen with unsaved changes asks first (the screen's
## `confirm_leave(go)`).

const TABS := [
	["play", "Play", "house"],
	["locker", "Locker", "hanger"],
	["shop", "Shop", "bag"],
	["pass", "Season Pass", "pass"],
]
const PAD := 16.0
const ICON := 30.0

var active := "play"
var buttons: Dictionary = {}       # tab -> Button
var _dots: Dictionary = {}         # tab -> Control
var compact := false
var compact_level := -1


static func make(active_tab: String) -> NavShell:
	var n := NavShell.new()
	n.active = active_tab
	return n


func _init() -> void:
	add_theme_constant_override("separation", 6)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	for t in TABS:
		var key: String = t[0]
		var b := UIKit.card_button(Vector2(0, maxf(UIKit.touch_min(), 64.0)), Color(UIKit.SLATE, 0.92))
		b.name = "Tab_" + key
		b.tooltip_text = String(t[1])
		b.accessibility_name = String(t[1])
		var f := UIKit.face_of(b)
		var sel := UIKit.card_box(Color(UIKit.TEAL.darkened(0.45), 0.92), 999, 1.0)
		sel.set_border_width_all(2)
		sel.border_color = UIKit.TEAL
		f.styles = {"normal": UIKit.card_box(Color(UIKit.SLATE, 0.9), 999, 1.0, 16, 0.08),
			"hover": UIKit.card_box(Color(UIKit.SLATE_HI, 0.95), 999, 1.0, 16, 0.1),
			"pressed": UIKit.card_box(Color(UIKit.SLATE_LO, 0.95), 999, 0.0), "disabled": UIKit.box(Color(UIKit.SLATE_LO, 0.7), 999),
			"selected": sel}
		var tab := TabFace.new()
		tab.icon = String(t[2])
		tab.text = String(t[1])
		tab.btn = b
		tab.set_anchors_preset(Control.PRESET_FULL_RECT)
		f.add_child(tab)
		var dot := Dot.new()
		dot.visible = false
		f.add_child(dot)
		_dots[key] = dot
		b.pressed.connect(func() -> void: NavShell.go(key))
		add_child(b)
		buttons[key] = b
		UIKit.set_selected(b, key == active)
		if key == active:
			b.accessibility_name = "%s, current tab" % t[1]
	apply_level(0)
	resized.connect(_fit)
	var p := get_parent() as Control
	if p:
		p.resized.connect(_fit)
	Wallet.changed.connect(_refresh_dots)
	Purchases.state_changed.connect(func(_p: String) -> void: _refresh_dots())
	_fit.call_deferred()
	_refresh_dots()


## Width the bar needs at a level: 0 every label, 1 only the active tab's
## label, 2 icons only.
func needed_width(level: int) -> float:
	var f := UIKit.font_w(600)
	var w := 0.0
	for t in TABS:
		var show_label: bool = level == 0 or (level == 1 and String(t[0]) == active)
		var lw := f.get_string_size(String(t[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.T_LABEL).x if show_label else 0.0
		w += maxf(UIKit.touch_min(), PAD * 2.0 + ICON + (lw + 10.0 if show_label else 0.0))
	return w + 6.0 * (TABS.size() - 1)


## The space the bar may use: its row's width minus its siblings (so it
## shrinks to icons instead of pushing the row off screen).
func available_width() -> float:
	var p := get_parent() as Control
	if p is BoxContainer:
		var others := 0.0
		var n := 0
		for c in p.get_children():
			if c is Control and c != self and (c as Control).visible and not (c as Control).top_level:
				others += (c as Control).get_combined_minimum_size().x
				n += 1
		return p.size.x - others - float(p.get_theme_constant("separation")) * n
	return size.x


func _fit() -> void:
	var avail := available_width()
	if avail <= 0.0:
		return
	var level := 0
	while level < 2 and needed_width(level) > avail + 0.5:
		level += 1
	apply_level(level)


func apply_level(level: int) -> void:
	if level == compact_level and not buttons.is_empty() and (buttons.values()[0] as Control).custom_minimum_size.x > 0.0:
		return
	compact_level = level
	compact = level > 0
	var f := UIKit.font_w(600)
	for t in TABS:
		var b: Button = buttons[t[0]]
		var show_label: bool = level == 0 or (level == 1 and String(t[0]) == active)
		var lw := f.get_string_size(String(t[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.T_LABEL).x if show_label else 0.0
		b.custom_minimum_size.x = maxf(UIKit.touch_min(), PAD * 2.0 + ICON + (lw + 10.0 if show_label else 0.0))
		var tf := UIKit.face_of(b).get_child(0) as TabFace
		if tf:
			tf.show_label = show_label
			tf.queue_redraw()


func _refresh_dots() -> void:
	if not is_inside_tree():
		return
	var sid := Catalogue.current_season_id()
	(_dots["pass"] as Control).visible = Wallet.synced() and not Wallet.claimable(sid).is_empty()
	var busy := false
	for pid in Catalogue.product_ids():
		if Purchases.delivering(pid):
			busy = true
	(_dots["shop"] as Control).visible = busy or Wallet.pending_ops() > 0 and Wallet.synced()


## Navigate to a tab.  The current screen may ask first (unsaved Locker look).
static func go(tab: String) -> void:
	var scr: Variant = App.screen
	if scr != null and is_instance_valid(scr) and (scr as Object).has_method("confirm_leave"):
		(scr as Object).call("confirm_leave", func() -> void: NavShell.open(tab))
		return
	open(tab)


static func open(tab: String) -> void:
	match tab:
		"play":
			go_hub()
		"locker":
			var c := CreatorScreen.new()
			c.back_action_override = NavShell.go_hub
			App._ensure_background()
			App._show(c)
		"shop":
			App.goto(ShopScreen)
		"pass":
			App.goto(SeasonScreen)


## The hub: the party lobby while in an online party (it stays intact), else home.
static func go_hub() -> void:
	var s: Variant = App.session
	if s != null and is_instance_valid(s) and (s as NetSession).mode != NetSession.Mode.OFFLINE:
		App.show_lobby()
	else:
		App.goto_title()


## The tab's look: icon and (when room) label, centred.
class TabFace:
	extends Control
	var icon := ""
	var text := ""
	var show_label := true
	var btn: Button

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := UIKit.face_of(btn) if btn else null
		var col := UIKit.IVORY if f == null or f.selected else UIKit.IVORY_MUTED
		var font := UIKit.font_w(600)
		var lw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.T_LABEL).x if show_label else 0.0
		var total := NavShell.ICON + (lw + 10.0 if show_label else 0.0)
		var x := (size.x - total) * 0.5
		var cy := size.y * 0.5
		CommerceArt.glyph(self, icon, Vector2(x + NavShell.ICON * 0.5, cy), NavShell.ICON * 0.42, UIKit.TEAL if f != null and f.selected else col)
		if show_label:
			var asc := font.get_ascent(UIKit.T_LABEL)
			var desc := font.get_descent(UIKit.T_LABEL)
			draw_string(font, Vector2(x + NavShell.ICON + 10.0, cy + (asc - desc) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.T_LABEL, col)


class Dot:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(14, 14)

	func _ready() -> void:
		var p := get_parent() as Control
		if p:
			var place := func() -> void: position = Vector2(p.size.x - 20.0, 4.0)
			p.resized.connect(place)
			place.call()

	func _draw() -> void:
		draw_circle(size * 0.5, 6.0, UIKit.AMBER)
		draw_arc(size * 0.5, 6.0, 0, TAU, 16, UIKit.NAVY, 2.0, true)
