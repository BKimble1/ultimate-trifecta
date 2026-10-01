class_name WardrobeScreen
extends Screen
## Wardrobe: the same character asset on the dorm stage (camera eases in),
## a segmented slot picker and item cards.  Changes apply in place (no
## rebuild) and, inside a room, are sent to the party immediately.
## Coins buy appearance only — never gameplay.

var coins_lbl: Label
var grid: GridContainer
var slot := "outfit"
var tabs: Dictionary = {}
var _spin := 0.0


func build() -> void:
	if App.stage:
		App.stage.set_mode("wardrobe")
		App.sync_stage_local()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade := TextureRect.new()
	shade.texture = TitleScreen._side_gradient()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	move_child(shade, 0)
	var row := UIKit.hbox(0)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	var left := UIKit.vbox(12)
	row.add_child(left)
	var back := UIKit.icon_button("back")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.tooltip_text = "Done"
	back.pressed.connect(_go_back)
	left.add_child(back)
	left.add_child(UIKit.spacer_v())
	coins_lbl = UIKit.label("", 26, UIKit.AMBER, true)
	left.add_child(coins_lbl)
	left.add_child(UIKit.label("Earn coins by playing. Looks only.", 18, UIKit.IVORY_MUTED))
	row.add_child(UIKit.spacer_h())
	var sheet := UIKit.panel(Color(UIKit.SLATE, 0.95), UIKit.R_PANEL, 22)
	sheet.custom_minimum_size = Vector2(minf(600.0, get_viewport().get_visible_rect().size.x * 0.56), 0)
	row.add_child(sheet)
	var v := UIKit.vbox(14)
	sheet.add_child(v)
	v.add_child(UIKit.heading("Outfit", 36))
	var seg := UIKit.hbox(6)
	for s in [["outfit", "Clothes"], ["hat", "Hat"], ["shoes", "Shoes"], ["color", "Colour"], ["skin", "Skin"]]:
		var b := UIKit.quiet(String(s[1]), Vector2(108, 64), 20)
		var sid: String = s[0]
		b.pressed.connect(func() -> void:
			slot = sid
			_refresh())
		seg.add_child(b)
		tabs[sid] = b
	v.add_child(seg)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	v.add_child(sc)
	grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(grid)
	focus_first(tabs["outfit"])
	_refresh()
	UIKit.appear(sheet, Vector2(40, 0), UIKit.T_SHEET)


func _process(delta: float) -> void:
	# slow turntable so the outfit can be seen from the side (still with Reduced Motion)
	if App.stage == null or UIKit.reduced_motion():
		return
	_spin += delta * 0.5
	var v := App.stage.local_character()
	if v:
		var base := atan2(-(App.stage.cam.global_position.x - v.global_position.x), -(App.stage.cam.global_position.z - v.global_position.z))
		v.rotation.y = base - 0.25 + sin(_spin) * 0.55


func _equip_changed() -> void:
	App.sync_stage_local()
	if App.session and is_instance_valid(App.session) and App.session.phase == TC.Phase.LOBBY and App.session.mode != NetSession.Mode.OFFLINE:
		App.session.set_local_cosmetic(Save.data["cosmetic"])
	Sfx.play("pop")


func _refresh() -> void:
	coins_lbl.text = "%d coins" % int(Save.data["coins"])
	for k in tabs:
		var b: Button = tabs[k]
		if k == slot:
			UIKit._apply(b, UIKit.TEAL, UIKit.NAVY)
		else:
			b.add_theme_stylebox_override("normal", UIKit.box(Color(UIKit.SLATE, 0.55), UIKit.R_BUTTON, 2, Color(UIKit.IVORY, 0.22)))
			b.add_theme_color_override("font_color", UIKit.IVORY)
	for c in grid.get_children():
		c.queue_free()
	var cos: Dictionary = Save.data["cosmetic"]
	if slot == "color" or slot == "skin":
		var arr: Array = Cosmetics.COLORS if slot == "color" else Cosmetics.SKINS
		grid.columns = 4
		for i in arr.size():
			var b := UIKit.secondary(Cosmetics.COLOR_NAMES[i] if slot == "color" else "Tone %d" % (i + 1), Vector2(132, 84), 18)
			var col: Color = arr[i]
			var sel := int(cos[slot]) == i
			b.add_theme_stylebox_override("normal", UIKit.box(col, UIKit.R_SMALL, 4 if sel else 0, UIKit.IVORY))
			b.add_theme_stylebox_override("hover", UIKit.box(col.lightened(0.08), UIKit.R_SMALL, 4 if sel else 0, UIKit.IVORY))
			b.add_theme_stylebox_override("pressed", UIKit.box(col.darkened(0.1), UIKit.R_SMALL, 4, UIKit.IVORY))
			var fg := UIKit.NAVY if col.get_luminance() > 0.5 else UIKit.IVORY
			for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				b.add_theme_color_override(k, fg)
			var idx := i
			b.pressed.connect(func() -> void:
				Save.equip(slot, idx)
				_equip_changed()
				_refresh())
			grid.add_child(b)
		return
	grid.columns = 2
	var table: Dictionary = Cosmetics.OUTFITS if slot == "outfit" else (Cosmetics.HATS if slot == "hat" else Cosmetics.SHOES)
	for id in table:
		var item: Dictionary = table[id]
		var owned: bool = Save.owns(slot, id)
		var equipped: bool = String(cos[slot]) == id
		var price := int(item["cost"])
		var affordable := int(Save.data["coins"]) >= price
		var caption := String(item["name"])
		var state := "Wearing" if equipped else ("Owned" if owned else "%d coins" % price)
		var b := UIKit.secondary("", Vector2(270, 92), 22)
		var vb := UIKit.vbox(2)
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.offset_left = 16
		vb.offset_right = -12
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := UIKit.label(caption, 22, UIKit.NAVY if equipped else UIKit.IVORY, true)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(t)
		var st := UIKit.label(state, 17, UIKit.NAVY if equipped else (UIKit.AMBER if (not owned and affordable) else UIKit.IVORY_MUTED))
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(st)
		b.add_child(vb)
		if equipped:
			UIKit._apply(b, UIKit.TEAL, UIKit.NAVY)
		elif not owned and not affordable:
			b.modulate = Color(1, 1, 1, 0.6)
		var iid: String = id
		b.pressed.connect(func() -> void:
			if Save.owns(slot, iid):
				Save.equip(slot, iid)
			elif Save.buy(slot, iid):
				Save.equip(slot, iid)
				Sfx.play("pickup")
			else:
				dialog("Not enough coins yet — play a few rounds!")
				return
			_equip_changed()
			_refresh())
		grid.add_child(b)
