class_name WalletChip
extends Button
## The Coins balance as a compact chip (V6): the gold Coin and the number in
## tabular digits.  Updates its text in place when the wallet changes (the
## screen around it is never rebuilt).  Tap: the Shop's Coins section.
## Before any account it shows the pre-V6 balance kept on this device; a
## small dot means an operation is still finishing.

var _num: Label
var _dot: Control


func _init() -> void:
	UIKit.make_card(self, Vector2(0, UIKit.touch_min()), Color(UIKit.SLATE, 0.92))
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var f := UIKit.face_of(self)
	var h := UIKit.hbox(10)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 14
	h.offset_right = -16
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := CommerceArt.Pic.new("coin", "", Color.WHITE, 30)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(c)
	_num = UIKit.styled("", "num", UIKit.AMBER)
	_num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_num.size_flags_vertical = Control.SIZE_FILL
	h.add_child(_num)
	# (2.2 build 18) a + : the Coin packs are one tap away
	var plus := PlusBadge.new()
	plus.name = "Plus"
	plus.custom_minimum_size = Vector2(30, 30)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(plus)
	f.add_child(h)
	_dot = NavShell.Dot.new()
	_dot.visible = false
	f.add_child(_dot)
	UIKit.fit_card(self, h, 30.0)
	pressed.connect(func() -> void:
		if App.screen is ShopScreen and (App.screen as ShopScreen).is_inside_tree():
			(App.screen as ShopScreen).select_section("coins")
			return
		ShopScreen.focus_section = "coins"
		NavShell.go("shop"))


func _ready() -> void:
	Wallet.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_instance_valid(_num):
		return
	_num.text = Wallet.balance_label()
	_dot.visible = Wallet.pending_ops() > 0
	var where := " on this device" if Wallet.balance_is_device() else ""
	accessibility_name = "%s Coins%s. Get more Coins." % [Wallet.balance_label(), where]
	tooltip_text = "%s Coins%s" % [Wallet.balance_label(), where]


# ---------------------------------------------------------------------------
# (2.3) Coins flying home: after a round that paid Coins, a burst of coins
# from `from` (screen point) arcs into this chip one after another; each
# landing pops the chip and counts the number up to the new balance.
# ---------------------------------------------------------------------------
var _flying := false


func fly_in(amount: int, from: Vector2) -> void:
	if amount <= 0 or _flying or not is_inside_tree():
		return
	_flying = true
	var target := Wallet.balance()
	var start := maxi(0, target - amount) if target >= 0 else -1
	if start >= 0:
		_num.text = Catalogue.format_coins(start)
	var n := clampi(amount / 10 + 4, 5, 14)
	var layer := CanvasLayer.new()
	layer.layer = 20
	get_tree().root.add_child(layer)
	var to := get_global_rect().get_center() + Vector2(-get_global_rect().size.x * 0.25, 0)
	var rm := UIKit.reduced_motion()
	var landed := [0]
	for i in n:
		var c := CommerceArt.Pic.new("coin", "", Color.WHITE, 44)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.size = Vector2(44, 44)
		var jitter := Vector2(randf_range(-90, 90), randf_range(-50, 50))
		var p0 := from + jitter - c.size * 0.5
		c.position = p0
		c.scale = Vector2.ZERO
		c.pivot_offset = c.size * 0.5
		layer.add_child(c)
		var delay := 0.08 * float(i) if not rm else 0.0
		var dur := 0.75 if not rm else 0.01
		var tw := c.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(c, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var ctrl := p0 + Vector2((to.x - p0.x) * 0.2, -220.0)
		tw.tween_method(func(u: float) -> void:
			if is_instance_valid(c):
				var a := p0.lerp(ctrl, u)
				var b := ctrl.lerp(to - c.size * 0.5, u)
				c.position = a.lerp(b, u)
				c.scale = Vector2.ONE * lerpf(1.0, 0.55, u), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			if is_instance_valid(c):
				c.queue_free()
			landed[0] += 1
			Sfx.play("pickup", null, -6.0, 1.0 + 0.05 * float(landed[0]))
			if start >= 0 and is_instance_valid(_num):
				_num.text = Catalogue.format_coins(start + int(round(float(amount) * float(landed[0]) / float(n))))
			UIKit.press_feedback(self)
			if landed[0] >= n:
				_flying = false
				refresh()
				if is_instance_valid(layer):
					layer.queue_free())


## (2.2 build 18) the green + on the chip
class PlusBadge:
	extends Control

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c + Vector2(0, 1.5), r, Color(0, 0, 0, 0.25), true, -1.0, true)
		draw_circle(c, r, Color("3ccf7a"), true, -1.0, true)
		draw_circle(c + Vector2(0, -r * 0.35), r * 0.55, Color(1, 1, 1, 0.16), true, -1.0, true)
		var a := r * 0.5
		draw_line(c - Vector2(a, 0), c + Vector2(a, 0), Color.WHITE, 3.5, true)
		draw_line(c - Vector2(0, a), c + Vector2(0, a), Color.WHITE, 3.5, true)
