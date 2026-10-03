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
	f.add_child(h)
	_dot = NavShell.Dot.new()
	_dot.visible = false
	f.add_child(_dot)
	UIKit.fit_card(self, h, 30.0)
	pressed.connect(func() -> void:
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
	accessibility_name = "%s Coins%s. Opens the Shop." % [Wallet.balance_label(), where]
	tooltip_text = "%s Coins%s" % [Wallet.balance_label(), where]
