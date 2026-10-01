class_name WardrobeScreen
extends Screen
## A small real wardrobe. Coins buy appearance only — never gameplay.

var preview: Preview3D
var coins_lbl: Label
var lists: VBoxContainer
var slot := "outfit"
var _spin := 0.0


func build() -> void:
	header("Wardrobe")
	var row := UIKit.hbox(24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	var left := UIKit.vbox(8)
	row.add_child(left)
	preview = Preview3D.new(Vector2i(400, 470))
	left.add_child(preview)
	coins_lbl = UIKit.label("", 28, UIKit.ACCENT, true, HORIZONTAL_ALIGNMENT_CENTER)
	left.add_child(coins_lbl)
	left.add_child(UIKit.label("Earn coins by playing. Cosmetic only.", 20, UIKit.MUTED, false, HORIZONTAL_ALIGNMENT_CENTER))
	var right := UIKit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var tabs := UIKit.hbox(10)
	var first: Button = null
	for s in [["outfit", "Outfit"], ["hat", "Hat"], ["shoes", "Shoes"], ["color", "Colour"], ["skin", "Skin"]]:
		var b := UIKit.button(String(s[1]), Color(0.3, 0.38, 0.7), Vector2(150, 58), 24)
		var sid: String = s[0]
		b.pressed.connect(func() -> void:
			slot = sid
			_refresh())
		tabs.add_child(b)
		if first == null:
			first = b
	right.add_child(tabs)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.follow_focus = true
	lists = UIKit.vbox(8)
	lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(lists)
	right.add_child(sc)
	focus_first(first)
	_refresh()


func _process(delta: float) -> void:
	_spin += delta * 0.6
	for v in preview.views:
		v.rotation.y = PI + sin(_spin) * 0.6


func _refresh() -> void:
	coins_lbl.text = "%d coins" % int(Save.data["coins"])
	preview.clear()
	preview.show_character(TC.Role.RUNNER, Save.data["cosmetic"])
	for c in lists.get_children():
		c.queue_free()
	var cos: Dictionary = Save.data["cosmetic"]
	if slot == "color" or slot == "skin":
		var arr: Array = Cosmetics.COLORS if slot == "color" else Cosmetics.SKINS
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		for i in arr.size():
			var b := UIKit.button(Cosmetics.COLOR_NAMES[i] if slot == "color" else "Tone %d" % (i + 1), arr[i], Vector2(170, 70), 22)
			if int(cos[slot]) == i:
				b.text = "✓ " + b.text
			var idx := i
			b.pressed.connect(func() -> void:
				Save.equip(slot, idx)
				_refresh())
			grid.add_child(b)
		lists.add_child(grid)
		return
	var table: Dictionary = Cosmetics.OUTFITS if slot == "outfit" else (Cosmetics.HATS if slot == "hat" else Cosmetics.SHOES)
	for id in table:
		var item: Dictionary = table[id]
		var owned: bool = Save.owns(slot, id)
		var equipped: bool = String(cos[slot]) == id
		var label := String(item["name"])
		var col := Color(0.25, 0.32, 0.62)
		if equipped:
			label = "✓ " + label + "  (wearing)"
			col = Color(0.3, 0.7, 0.45)
		elif owned:
			label += "  — wear"
		else:
			label += "  — %d coins" % int(item["cost"])
			col = Color(0.6, 0.45, 0.2) if int(Save.data["coins"]) >= int(item["cost"]) else Color(0.3, 0.3, 0.4)
		var b2 := UIKit.button(label, col, Vector2(560, 64), 24)
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var iid: String = id
		b2.pressed.connect(func() -> void:
			if Save.owns(slot, iid):
				Save.equip(slot, iid)
			elif Save.buy(slot, iid):
				Save.equip(slot, iid)
				Sfx.play("pickup")
			else:
				dialog("Not enough coins yet — play a few rounds!")
			_refresh())
		lists.add_child(b2)
