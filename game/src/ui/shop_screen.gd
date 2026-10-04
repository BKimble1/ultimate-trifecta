class_name ShopScreen
extends Screen
## The Shop (V6): every purchase in the game, and nothing else.
##
##   top     Back, the navigation bar and the Coins chip (one 44 pt row)
##   left    the runner in the dorm, wearing whatever item is selected: drag
##           to turn, Idle / Run / Emote.  This is the one interactive 3D
##           preview (the dorm stage already on screen); cards use cached
##           portraits, never a live viewport each.
##   right   sections (Featured · Outfits · Accessories · Coins · Season 1)
##           over item cards: a picture, the full name, and the exact price
##           (Coins, or the App Store's localized price) or Owned.  Tapping
##           a card previews it on the runner and opens its detail: what it
##           is, exactly what it includes, the price, its state, why an
##           action is unavailable (right above it) and one action.
##
## V7: the Locker's card system (UIKit.AutoGrid, CreatorScreen card layout):
## columns from the panel's final width, per-type picture wells, outfits
## pictured with no hat and plain shoes (CommerceArt.preview_look), one short
## unavailable line instead of a paragraph, and the detail's status and
## action fixed at its bottom.
##
## Coins: a confirmation shows the item, its cost and the balance left, then
## the service debits and grants atomically (Wallet.spend).  Apple: the tap
## opens Apple's own sheet directly (Purchases.buy).  States are honest:
## loading, available, owned, pending, cancelled, failed, offline/unavailable,
## delivered.  Wallet and purchase updates refresh labels in place; the menu
## is never rebuilt.  No sales, timers, scarcity, loot boxes or pop-ups; an
## owned item is never offered again; Season rewards are never sold here.

const SECTIONS := [
	["featured", "Featured"],
	["outfits", "Outfits"],
	["accessories", "Accessories"],
	["coins", "Coins"],
	["season", "Season 1"],
]
const CARD_W := 144.0
const CARD_GAP := float(UIKit.GAP_CARD)
const THUMB_FRAMING := {"outfit": "body", "pattern": "body", "hat": "hat", "shoes": "feet"}
const SWATCH_FIELDS := ["color", "trim", "hair_color"]
## picture wells beyond the Locker's (CreatorScreen.WELL)
const WELL := {"swatch": 0.62, "coins": 0.62, "glyph": 0.62}

## deep links (set before NavShell.go("shop")): a section and/or an item
static var focus_section := ""
static var focus_item := ""

var section := "featured"
var panel: PanelContainer
var strip_btns: Dictionary = {}
var scroll: ScrollContainer
var body: VBoxContainer
var cards: Array = []                 # ShopCard
var banner: Label
var detail: Control                   # the open detail sheet, or null
var detail_id := ""
var preview_id := ""
var saved: Dictionary = {}
var preview_run := false
var _stage_area: Control
var _yaw := 0.0
var _yaw_set := false
var _spin := 0.0
var _drag_from := -1.0
var _busy_item := ""
var _scroll_of: Dictionary = {}
var _d: Dictionary = {}               # detail widgets


func build() -> void:
	saved = Cosmetics.sanitize(Save.data["cosmetic"])
	if App.stage:
		App.stage.set_mode("wardrobe")
		App.sync_stage_local()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	TitleScreen.add_shades(self, 0.45, 0.0)
	back_action = _go_hub
	content.add_theme_constant_override("separation", UIKit.SP_M)
	nav_bar("shop")

	var mid := UIKit.hbox(UIKit.SP_L)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(mid)
	# the Locker's turn control: one finger owns the turn (test_stage_drag)
	var drag := CreatorScreen.StageDrag.new()
	drag.turned.connect(drag_turn)
	_stage_area = drag
	_stage_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_area.size_flags_stretch_ratio = 1.0
	mid.add_child(_stage_area)
	_stage_area.add_child(_preview_controls())

	panel = UIKit.panel(Color(UIKit.SLATE, 0.95), UIKit.R_PANEL, UIKit.PAD_PANEL)
	panel.name = "ShopPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = CreatorScreen.PANEL_RATIO
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(panel)
	var pvb := UIKit.vbox(UIKit.SP_S)
	pvb.name = "GridView"
	panel.add_child(pvb)
	pvb.add_child(_section_strip())
	banner = UIKit.styled("", "caption", UIKit.AMBER)
	banner.name = "Unavailable"
	banner.clip_text = true
	banner.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pvb.add_child(banner)
	scroll = UIKit.scroll_area()
	scroll.name = "Items"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	scroll.follow_focus = true
	pvb.add_child(scroll)
	body = UIKit.vbox(UIKit.SP_M)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	if focus_section != "":
		section = focus_section
	focus_section = ""
	_build_section()
	if focus_item != "":
		var fi := focus_item
		focus_item = ""
		_open_detail.call_deferred(fi)
	focus_first(strip_btns[section])
	UIKit.fade_in(panel)
	_stage_area.resized.connect(_frame_stage)
	get_viewport().size_changed.connect(_frame_stage)
	_frame_stage.call_deferred()
	Wallet.changed.connect(_refresh_states)
	Purchases.products_changed.connect(_refresh_states)
	Purchases.state_changed.connect(_on_purchase_state)
	Purchases.restore_finished.connect(_on_restore_finished)
	Purchases.load_products()
	var lc := App.stage.local_character() if App.stage else null
	_yaw = lc.rotation.y if lc else 0.0


func _go_hub() -> void:
	if detail != null:
		_close_detail()
		return
	_restore_stage()
	NavShell.go_hub()


func confirm_leave(go: Callable) -> void:
	_restore_stage()
	go.call()


func _restore_stage() -> void:
	Portraits.cancel_shared("shop:")
	var v := App.stage.local_character() if App.stage else null
	if v:
		v.set_appearance(TC.Role.RUNNER, saved)
		var rs := v.rs.duplicate()
		rs["vel"] = Vector3.ZERO
		v.apply_state(rs)


func _exit_tree() -> void:
	Portraits.cancel_shared("shop:")


func _frame_stage() -> void:
	if App.stage and is_instance_valid(_stage_area) and _stage_area.is_inside_tree():
		var vs := get_viewport().get_visible_rect().size
		var r := _stage_area.get_global_rect()
		if r.size.x < 2.0 or r.size.y < 2.0:
			return
		App.stage.set_wardrobe_region((r.get_center().x + r.size.x * 0.12) / maxf(1.0, vs.x), r.size.x / maxf(1.0, vs.x),
			r.position.y / maxf(1.0, vs.y), r.end.y / maxf(1.0, vs.y))


# ------------------------------------------------------------------ preview
## Idle / Run / Emote stacked in the stage's lower-left corner, clear of the
## runner (who stands right of centre), with the turn hint under them.
func _preview_controls() -> Control:
	var pv := UIKit.vbox(UIKit.SP_S)
	for spec in [["idle", "Idle"], ["run", "Run"], ["emote", "Emote"]]:
		var b := UIKit.quiet(String(spec[1]), Vector2(120, 0), UIKit.T_CAPTION)
		b.name = "Preview_" + String(spec[0])
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var kind: String = spec[0]
		b.pressed.connect(func() -> void: _preview_action(kind))
		pv.add_child(b)
	var hint := UIKit.chip("Drag to turn", Color(UIKit.NAVY, 0.6), UIKit.IVORY_MUTED, 18)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pv.add_child(hint)
	_stage_area.resized.connect(func() -> void: pv.position = Vector2(0, _stage_area.size.y - pv.get_combined_minimum_size().y))
	return pv


func _preview_action(kind: String) -> void:
	var v := App.stage.local_character() if App.stage else null
	match kind:
		"idle":
			preview_run = false
		"run":
			preview_run = true
		"emote":
			preview_run = false
			var key := String(_preview_look().get("emote", "wave"))
			var id := TC.EMOTES.find(key)
			if id >= 0 and App.stage and v:
				App.stage.emote(Save.player_uid(), id)
	Sfx.play("click")


## The saved look with the previewed item on.
func _preview_look() -> Dictionary:
	var look := saved.duplicate()
	if preview_id != "" and Catalogue.is_runner_item(preview_id):
		var s := Catalogue.split(preview_id)
		look[String(s[0])] = String(s[1])
	return Cosmetics.sanitize(look)


func preview(id: String) -> void:
	preview_id = id
	var v := App.stage.local_character() if App.stage else null
	if v:
		v.set_appearance(TC.Role.RUNNER, _preview_look())
		if Catalogue.is_runner_item(id) and not UIKit.reduced_motion():
			v.play_arrive()
		if id.begins_with("emote:"):
			_preview_action("emote")


func drag_turn(dx: float) -> void:
	var v := App.stage.local_character() if App.stage else null
	if v == null:
		return
	if not _yaw_set:
		_yaw = v.rotation.y
		_yaw_set = true
	_yaw = wrapf(_yaw + dx * 0.012, -PI, PI)


func _process(delta: float) -> void:
	var v := App.stage.local_character() if App.stage else null
	if v == null:
		return
	if Controls.active_joy >= 0 and not has_modal():
		var rx := InputRouter.radial(Vector2(Input.get_joy_axis(Controls.active_joy, JOY_AXIS_RIGHT_X), 0.0), 0.2, 0.95).x
		if rx != 0.0:
			drag_turn(rx * 220.0 * delta)
	if _drag_from < 0.0 and not UIKit.reduced_motion() and not preview_run:
		_spin += delta * 0.45
	var base := atan2(-(App.stage.cam.global_position.x - v.global_position.x), -(App.stage.cam.global_position.z - v.global_position.z))
	v.set_facing(_yaw if _yaw_set else base - 0.25 + sin(_spin) * 0.5)
	if App.stage.emoting(Save.player_uid()):
		return
	var rs := v.rs.duplicate()
	rs["vel"] = (Basis(Vector3.UP, v.rotation.y) * Vector3(0, 0, -5.0)) if preview_run else Vector3.ZERO
	rs["state"] = TC.PState.ACTIVE
	rs["on_floor"] = true
	rs["pos"] = v.global_position
	v.apply_state(rs)


# ------------------------------------------------------------------ sections
func _section_strip() -> Control:
	var sc := UIKit.scroll_area(true)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = true
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	sc.add_child(row)
	for spec in SECTIONS:
		var key: String = spec[0]
		var b := UIKit.quiet(String(spec[1]), Vector2(0, 0), UIKit.T_LABEL)
		b.name = "Section_" + key
		b.custom_minimum_size.y = UIKit.row_h()
		var f := UIKit.face_of(b)
		var sel := UIKit.box(Color(UIKit.TEAL, 0.16), 999, 0, Color.WHITE)
		sel.set_border_width_all(2)
		sel.border_color = UIKit.TEAL
		var n := UIKit.box(Color(0, 0, 0, 0), 999, 0, Color.WHITE)
		f.styles = {"normal": n, "hover": UIKit.box(Color(UIKit.IVORY, 0.06), 999), "pressed": UIKit.box(Color(UIKit.IVORY, 0.1), 999),
			"disabled": n, "selected": sel}
		f.fg = {"normal": UIKit.IVORY_MUTED, "hover": UIKit.IVORY, "selected": UIKit.IVORY}
		b.pressed.connect(func() -> void: select_section(key))
		row.add_child(b)
		strip_btns[key] = b
	sc.custom_minimum_size.y = UIKit.row_h()
	sc.name = "Sections"
	sc.resized.connect(_fit_strip.bind(sc, row))
	return sc


## The section strip fits its panel like the Locker's categories: tighter
## padding, then a size smaller, before a section would be cut off.
func _fit_strip(strip: ScrollContainer, row: HBoxContainer) -> void:
	var avail := strip.size.x
	if avail <= 0.0:
		return
	var f := UIKit.font_w(600)
	var pick: Array = CreatorScreen.TAB_FITS[CreatorScreen.TAB_FITS.size() - 1]
	for opt in CreatorScreen.TAB_FITS:
		var need := 0.0
		for b in strip_btns.values():
			need += maxf(ceilf(f.get_string_size((b as Button).text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(opt[0])).x) + 2.0 * float(opt[1]), UIKit.touch_min())
		need += float(row.get_theme_constant("separation")) * float(strip_btns.size() - 1)
		if need <= avail:
			pick = opt
			break
	for b in strip_btns.values():
		var btn := b as Button
		btn.add_theme_font_size_override("font_size", int(pick[0]))
		var st := btn.get_theme_stylebox("normal")
		st.content_margin_left = float(pick[1])
		st.content_margin_right = float(pick[1])
		btn.update_minimum_size()
		UIKit.face_of(btn).queue_redraw()


func select_section(key: String) -> void:
	if detail != null:
		_close_detail()
	if key == section and not cards.is_empty():
		return
	_scroll_of[section] = scroll.scroll_vertical
	Portraits.cancel_shared("shop:")
	section = key
	_build_section()
	UIKit.fade_in(body, UIKit.T_FAST)


## The grid's width: the list's final width less its scrollbar's room.
func grid_width() -> float:
	var w := scroll.size.x if is_instance_valid(scroll) else 0.0
	if w < 2.0:
		var cw := content_size().x
		if cw < 2.0:
			cw = get_viewport().get_visible_rect().size.x * 0.8 if is_inside_tree() else 1000.0
		w = (cw - UIKit.SP_L) * CreatorScreen.PANEL_RATIO / (1.0 + CreatorScreen.PANEL_RATIO) - UIKit.PAD_PANEL * 2.0
	var bar := scroll.get_v_scroll_bar().get_combined_minimum_size().x if is_instance_valid(scroll) else 8.0
	return maxf(CARD_W, w - bar - 2.0)


## Cards per row of the current grid: from its final width (AutoGrid).
func _columns() -> int:
	for c in cards:
		if is_instance_valid(c) and (c as Control).get_parent() is GridContainer:
			return ((c as Control).get_parent() as GridContainer).columns
	return UIKit.columns_for(grid_width(), CARD_W, CARD_GAP, 2, 6)


func _build_section() -> void:
	for k in strip_btns:
		UIKit.set_selected(strip_btns[k], k == section)
	for c in body.get_children():
		c.queue_free()
	cards.clear()
	var items := Catalogue.shop_items(section)
	if section in ["featured", "outfits", "accessories"]:
		# an owned item is never shown as buyable: owned ones sort last
		var unowned := items.filter(func(it: Dictionary) -> bool: return not Wallet.owns_id(String(it["id"])))
		var owned := items.filter(func(it: Dictionary) -> bool: return Wallet.owns_id(String(it["id"])))
		items = unowned + owned
	var intro := ""
	match section:
		"coins":
			intro = "Coins buy anything in the Shop. They never expire and never add XP."
		"season":
			intro = "30 tiers you earn by playing. Premium adds a second track of rewards."
	if intro != "":
		var il := UIKit.styled(intro, "caption", UIKit.IVORY_MUTED)
		il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		il.custom_minimum_size.x = grid_width() * 0.95
		body.add_child(il)
	var gw := grid_width()
	if section == "season" or section == "featured":
		# Season 1 Premium leads Featured too (a real offer, never a timer)
		body.add_child(_season_offer(gw))
	if section != "season":
		var min_cell := 190.0 if section == "coins" else CARD_W
		var g := UIKit.AutoGrid.new(min_cell, 2, 6 if section != "coins" else 3, CARD_GAP)
		g.name = "Grid_" + section
		var cols := UIKit.columns_for(gw, min_cell, CARD_GAP, 2, g.max_cols)
		var w := UIKit.cell_width(gw, cols, CARD_GAP)
		for it in items:
			var card := ShopCard.new()
			card.setup(self, String(it["id"]), w)
			card.pressed.connect(_open_detail.bind(String(it["id"])))
			g.add_child(card)
			cards.append(card)
		g.columns = cols
		body.add_child(g)
		if items.is_empty() and section != "featured":
			body.add_child(UIKit.styled("Nothing here right now.", "body", UIKit.IVORY_MUTED))
	if section in ["featured", "outfits", "coins"]:
		body.add_child(_restore_row())
	_refresh_states()
	var at := int(_scroll_of.get(section, 0))
	(func() -> void:
		await get_tree().process_frame
		if is_instance_valid(scroll) and not TouchScroll.is_dragging(scroll):
			scroll.scroll_vertical = at).call()


func _restore_row() -> Control:
	var row := UIKit.hbox(UIKit.SP_M)
	var l := UIKit.styled("Bought a skin on another device?", "caption", UIKit.IVORY_MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var b := UIKit.quiet("Restore Purchases", Vector2(0, 0), UIKit.T_CAPTION)
	b.name = "Restore"
	b.pressed.connect(_restore)
	row.add_child(b)
	return row


func _restore() -> void:
	if Purchases.restoring():
		return
	UIKit.toast(self, "Restoring purchases…")
	Purchases.restore()


func _on_restore_finished(summary: Dictionary) -> void:
	if is_inside_tree():
		dialog(String(summary.get("message", "")))
	_refresh_states()


## Season 1 Premium: what it is and exactly what it adds (counted from the
## Season table, not a slogan), with one card to open.
func _season_offer(gw: float) -> Control:
	var id := String(Catalogue.season(Catalogue.current_season_id()).get("premium_item", "season:s1:premium"))
	var card := ShopCard.new()
	card.setup(self, id, gw)
	card.pressed.connect(_open_detail.bind(id))
	cards.append(card)
	return card


static func premium_summary(sid: String) -> String:
	var counts := {}
	var coins := 0
	var n := 0
	for t in Catalogue.season_tiers(sid):
		var r: Variant = t.get("premium")
		if not (r is Dictionary):
			continue
		n += 1
		if (r as Dictionary).has("coins"):
			coins += int(r["coins"])
			continue
		var id := String(r["item"])
		var label := Catalogue.type_label(id)
		counts[label] = int(counts.get(label, 0)) + 1
	var parts: Array = []
	for k in ["Outfit", "Hat", "Shoes", "Emote", "Name card", "Badge"]:
		if counts.has(k):
			var c := int(counts[k])
			var plural: String = String(k) + ("s" if c != 1 and k != "Shoes" else "")
			if k == "Shoes":
				plural = "pair of shoes" if c == 1 else "pairs of shoes"
			parts.append("%d %s" % [c, plural.to_lower()])
	return "%d Premium rewards over 30 tiers: %s, and %s Coins." % [n, ", ".join(parts), Catalogue.format_coins(coins)]


# ------------------------------------------------------------------ states
## Everything that depends on the wallet or the store, updated in place.
func _refresh_states() -> void:
	if not is_inside_tree():
		return
	banner.text = unavailable_line()
	banner.visible = banner.text != ""
	for c in cards:
		if is_instance_valid(c):
			c.refresh()
	if detail != null:
		_refresh_detail()


## One short line when buying can't work right now ("" when it can); the
## detail repeats it with the reason right above the unavailable action.
func unavailable_line() -> String:
	var can := Wallet.can_transact()
	if bool(can["ok"]):
		return ""
	match Wallet.service_state():
		"off":
			return "Buying is unavailable right now: the game service isn't set up in this build."
		"signed_out":
			return "Buying is unavailable right now: sign in with Game Center."
		"syncing":
			return "Checking your wallet…"
		"offline":
			return "Buying is unavailable right now: you're offline."
	return String(can["message"])


func _on_purchase_state(pid: String) -> void:
	_refresh_states()
	var st: Dictionary = Purchases.states.get(pid, {})
	var s := String(st.get("state", ""))
	if s in ["delivered", "cancelled"] and String(st.get("message", "")) != "":
		UIKit.toast(self, String(st["message"]), 2.4)
		if s == "delivered":
			Sfx.play("pickup")


## A card's or the sheet's price/state: {text, col, kind, owned, price,
## coins, message}.  kind: coins | apple | owned | unavailable
func state_of(id: String) -> Dictionary:
	var k := Catalogue.kind(id)
	if Wallet.owns_id(id) and k != "coin_pack":
		return {"text": "Owned", "col": UIKit.TEAL, "kind": "owned", "owned": true}
	if k == "coin_pack" or k == "apple_skin":
		var pv := Purchases.view(Catalogue.product_of(id))
		var price := String(pv["price"])
		var txt := price if bool(pv["can_buy"]) else String(pv["button"])
		if String(pv["state"]) in ["delivering", "pending_approval", "purchasing"]:
			txt = String(pv["button"])
		return {"text": txt, "col": UIKit.IVORY if bool(pv["can_buy"]) else UIKit.IVORY_MUTED, "kind": "apple", "owned": false,
			"price": price, "message": String(pv["message"]), "state": String(pv["state"]), "can_buy": bool(pv["can_buy"])}
	if k in ["coin_item", "season_premium"]:
		var p := Catalogue.price(id)
		var afford := Wallet.balance() >= p
		return {"text": Catalogue.format_coins(p), "col": UIKit.AMBER if afford else UIKit.IVORY_MUTED, "kind": "coins",
			"owned": false, "coins": p, "afford": afford, "pending": Wallet.pending_for(id)}
	return {"text": "Not sold", "col": UIKit.IVORY_MUTED, "kind": "unavailable", "owned": false}


# ------------------------------------------------------------------ detail
func _open_detail(id: String) -> void:
	if not Catalogue.has(id):
		return
	if detail != null:
		detail.queue_free()
		detail = null
	_scroll_of[section] = scroll.scroll_vertical
	detail_id = id
	if Catalogue.is_runner_item(id):
		preview(id)
	else:
		preview("")
	var grid_view: Control = panel.get_node("GridView")
	grid_view.visible = false
	detail = _detail_sheet(id)
	panel.add_child(detail)
	UIKit.fade_in(detail, UIKit.T_FAST)
	_refresh_detail()
	UIKit.soft_focus.call_deferred(_d["action"])


func _close_detail() -> void:
	if detail != null:
		detail.queue_free()
		detail = null
	detail_id = ""
	_d.clear()
	preview("")
	(panel.get_node("GridView") as Control).visible = true
	var at := int(_scroll_of.get(section, 0))
	(func() -> void:
		await get_tree().process_frame
		if is_instance_valid(scroll):
			scroll.scroll_vertical = at).call()


func _detail_sheet(id: String) -> Control:
	var gw := grid_width()
	var v := UIKit.vbox(UIKit.SP_S)
	v.name = "Detail"
	var top := UIKit.hbox(10)
	var back := UIKit.quiet("‹ Back to Shop", Vector2(0, 0), UIKit.T_CAPTION)
	back.name = "DetailBack"
	back.pressed.connect(_close_detail)
	top.add_child(back)
	top.add_child(UIKit.spacer_h())
	v.add_child(top)
	var sc := UIKit.scroll_area()
	sc.name = "DetailInfo"
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var inner := UIKit.vbox(UIKit.SP_S)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(inner)
	var head := UIKit.hbox(UIKit.SP_L)
	inner.add_child(head)
	var art_w := clampf(gw * 0.27, 120.0, 200.0)
	var art := ShopCard.art_for(self, id, art_w, "shop:detail")
	art.custom_minimum_size.y = roundf(art_w * ShopCard.well_of(id))
	head.add_child(art)
	var hv := UIKit.vbox(4)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(hv)
	hv.add_child(UIKit.styled(Catalogue.type_label(id) + _kind_note(id), "overline", UIKit.IVORY_MUTED))
	var name_l := UIKit.styled(Catalogue.display_name(id), "headline")
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size.x = maxf(80.0, gw - art_w - UIKit.SP_L - 10.0)
	hv.add_child(name_l)
	var price_row := UIKit.hbox(8)
	var coin := CommerceArt.Pic.new("coin", "", Color.WHITE, 30)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price_row.add_child(coin)
	var price_l := UIKit.styled("", "num", UIKit.AMBER)
	price_l.add_theme_font_size_override("font_size", 28)
	price_row.add_child(price_l)
	hv.add_child(price_row)
	var bl := Catalogue.blurb(id)
	if Catalogue.kind(id) == "coin_pack":
		bl = "%s Coins for your wallet. Coins buy anything in the Shop, never expire, and never count as XP." % Catalogue.format_coins(int(Catalogue.item(id).get("coins", 0)))
	if bl != "":
		var b := UIKit.styled(bl, "body", UIKit.IVORY)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = gw - 10.0
		inner.add_child(b)
	var inc := UIKit.styled(_includes_text(id), "caption", UIKit.IVORY_MUTED)
	inc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inc.custom_minimum_size.x = gw - 10.0
	inner.add_child(inc)
	# the state and why an action is unavailable sit right above the action,
	# outside the scroll: never hidden below the fold
	var status := UIKit.styled("", "caption", UIKit.AMBER)
	status.name = "DetailStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = gw - 10.0
	v.add_child(status)
	var act_row := UIKit.hbox(UIKit.SP_M)
	act_row.custom_minimum_size.y = UIKit.row_h()
	v.add_child(act_row)
	var second := UIKit.quiet("", Vector2(0, UIKit.row_h()), UIKit.T_LABEL)
	second.name = "DetailSecondary"
	second.custom_minimum_size.x = UIKit.row_h() * 2.0
	second.pressed.connect(_on_secondary)
	act_row.add_child(second)
	act_row.add_child(UIKit.spacer_h())
	var action := UIKit.primary("", Vector2(0, UIKit.row_h()), 24)
	action.name = "DetailAction"
	action.custom_minimum_size.x = UIKit.row_h() * 3.0
	action.pressed.connect(_on_action)
	act_row.add_child(action)
	_d = {"price": price_l, "coin": coin, "status": status, "action": action, "second": second}
	return v


func _kind_note(id: String) -> String:
	match Catalogue.kind(id):
		"apple_skin":
			return " · App Store"
		"coin_pack":
			return " · App Store"
	return ""


## Exactly what the item adds (its grants, by name and type).
func _includes_text(id: String) -> String:
	match Catalogue.kind(id):
		"coin_pack":
			return "Includes: %s Coins. Consumable: a purchase adds Coins once to the account you're signed in with." % Catalogue.format_coins(int(Catalogue.item(id).get("coins", 0)))
		"season_premium":
			return "Includes: %s Earned and claimed rewards stay yours permanently. No tier skips; Season XP comes only from playing." % premium_summary(String(Catalogue.item(id).get("season", "s1")))
	var parts: Array = []
	for g in Catalogue.grants(id):
		parts.append("%s (%s)" % [Catalogue.display_name(String(g)), Catalogue.type_label(String(g)).to_lower()])
	var t := "Includes: %s." % ", ".join(parts)
	if id.begins_with("outfit:"):
		if String(Catalogue.split(id)[1]) in Cosmetics.HOOD_OUTFITS:
			t += " Its hood covers your hair and hat; your shoes stay as you set them in the Locker."
		else:
			t += " Your colours, hair, hat and shoes stay as you set them in the Locker."
	if Catalogue.kind(id) == "apple_skin":
		t += " Permanent: restore it with Restore Purchases on any device signed in to the same Apple Account."
	return t


func _refresh_detail() -> void:
	if detail == null or _d.is_empty() or detail_id == "":
		return
	var id := detail_id
	var st := state_of(id)
	var price_l: Label = _d["price"]
	var coin: Control = _d["coin"]
	var status: Label = _d["status"]
	var action: Button = _d["action"]
	var second: Button = _d["second"]
	coin.visible = String(st["kind"]) == "coins"
	second.visible = false
	status.text = ""
	match String(st["kind"]):
		"owned":
			price_l.text = "Owned"
			price_l.add_theme_color_override("font_color", UIKit.TEAL)
			if Catalogue.kind(id) == "season_premium":
				action.text = "Open Season Pass"
				status.text = "Premium is unlocked for Season 1. Claim your Premium rewards in the Season Pass."
			else:
				action.text = "Wear it in the Locker"
				status.text = "It's in your Locker."
			action.disabled = false
		"coins":
			price_l.text = "%s Coins" % String(st["text"])
			price_l.add_theme_color_override("font_color", UIKit.AMBER)
			var can := Wallet.can_transact()
			if bool(st.get("pending", false)) or _busy_item == id:
				action.text = "Finishing…"
				action.disabled = true
				status.text = "Your purchase is being confirmed. It finishes by itself, and you won't be charged twice."
			elif not bool(can["ok"]):
				action.text = "Unavailable"
				action.disabled = true
				status.text = unavailable_line()
			elif not bool(st["afford"]):
				var short := int(st["coins"]) - Wallet.balance()
				action.text = "Need %s more Coins" % Catalogue.format_coins(short)
				action.disabled = true
				status.text = "You have %s Coins. Earn more by playing online rounds, or get Coins in the Coins section." % Wallet.balance_label()
				second.text = "Get Coins"
				second.visible = true
			else:
				action.text = ("Unlock for %s" if Catalogue.kind(id) == "season_premium" else "Buy for %s") % ("%s Coins" % String(st["text"]))
				action.disabled = false
				status.text = "You have %s Coins." % Wallet.balance_label()
		"apple":
			price_l.text = String(st["price"]) if String(st["price"]) != "" else ""
			price_l.add_theme_color_override("font_color", UIKit.IVORY)
			action.text = ("Buy for %s" % String(st["price"])) if bool(st["can_buy"]) else String(st["text"])
			action.disabled = not bool(st["can_buy"])
			status.text = unavailable_line() if String(st.get("state", "")) == "service" else String(st["message"])
			if Catalogue.kind(id) == "apple_skin":
				second.text = "Restore"
				second.visible = true
		_:
			price_l.text = ""
			action.text = "Not sold"
			action.disabled = true
	status.visible = status.text != ""
	action.accessibility_name = "%s, %s" % [Catalogue.display_name(id), action.text]


func _on_secondary() -> void:
	var b: Button = _d.get("second")
	if b == null:
		return
	if b.text == "Get Coins":
		select_section("coins")
	elif b.text == "Restore":
		_restore()


func _on_action() -> void:
	var id := detail_id
	var st := state_of(id)
	match String(st["kind"]):
		"owned":
			if Catalogue.kind(id) == "season_premium":
				NavShell.go("pass")
			else:
				_restore_stage()
				NavShell.open("locker")
		"coins":
			if bool(st["afford"]):
				_confirm_spend(id)
		"apple":
			var r := Purchases.buy(Catalogue.product_of(id))
			if not bool(r.get("ok", false)):
				dialog(String(r.get("message", "")))
			_refresh_states()


## Coin purchases are confirmed: the item, its cost, the balance now and the
## balance after.  Nothing is charged before Buy.
func _confirm_spend(id: String) -> void:
	var price := Catalogue.price(id)
	var bal := Wallet.balance()
	var dim := ColorRect.new()
	dim.color = Color(UIKit.NAVY, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var p := UIKit.panel(Color(UIKit.SLATE, 0.99), UIKit.R_PANEL, 28)
	p.name = "ConfirmSpend"
	var v := UIKit.vbox(16)
	p.add_child(v)
	v.add_child(UIKit.styled("Confirm purchase", "overline", UIKit.IVORY_MUTED))
	var head := UIKit.hbox(14)
	head.add_child(ShopCard.art_for(self, id, 96.0, "shop:confirm"))
	var hv := UIKit.vbox(2)
	hv.add_child(UIKit.styled(Catalogue.display_name(id), "headline"))
	hv.add_child(UIKit.styled(Catalogue.type_label(id), "caption", UIKit.IVORY_MUTED))
	head.add_child(hv)
	v.add_child(head)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 40)
	g.add_theme_constant_override("v_separation", 6)
	for row in [["Price", price, UIKit.AMBER], ["Your Coins", bal, UIKit.IVORY], ["Left after", bal - price, UIKit.TEAL]]:
		g.add_child(UIKit.styled(String(row[0]), "label", UIKit.IVORY_MUTED))
		var n := UIKit.styled("%s Coins" % Catalogue.format_coins(int(row[1])), "num", row[2])
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		g.add_child(n)
	v.add_child(g)
	var note := UIKit.styled("Cosmetic only. It goes straight to your Locker.", "caption", UIKit.IVORY_MUTED)
	v.add_child(note)
	var row2 := UIKit.hbox(14)
	row2.alignment = BoxContainer.ALIGNMENT_END
	var cancel := UIKit.quiet("Cancel", Vector2(200, 80))
	cancel.name = "ConfirmCancel"
	var buy := UIKit.primary("Buy for %s Coins" % Catalogue.format_coins(price), Vector2(320, 84), 24)
	buy.name = "ConfirmBuy"
	row2.add_child(cancel)
	row2.add_child(buy)
	v.add_child(row2)
	add_child(p)
	p.position = (get_viewport().get_visible_rect().size - p.get_combined_minimum_size()) * 0.5
	Motion.appear(p, 10.0, UIKit.T_FAST)
	var close := func() -> void:
		if is_instance_valid(dim):
			dim.queue_free()
		if is_instance_valid(p):
			p.queue_free()
	push_modal(p, close)
	cancel.pressed.connect(close)
	buy.pressed.connect(func() -> void:
		close.call()
		_spend(id))
	UIKit.soft_focus.call_deferred(cancel)


func _spend(id: String) -> void:
	_busy_item = id
	_refresh_states()
	var r: Dictionary = await Wallet.spend(id)
	_busy_item = ""
	if not is_inside_tree():
		return
	if bool(r.get("ok", false)):
		Sfx.play("pickup")
		UIKit.toast(self, "%s is in your %s." % [Catalogue.display_name(id), "Season Pass" if Catalogue.kind(id) == "season_premium" else "Locker"], 2.4)
	elif String(r.get("state", "")) == "pending":
		dialog(String(r.get("message", "")))
	else:
		dialog(String(r.get("message", "Something went wrong.")))
	_refresh_states()


## A Shop card, laid out like the Locker's (CreatorScreen card helpers):
## the picture well (a cached portrait of your runner wearing it with
## neutral accessories, a swatch, the emote's glyph, a Coin pile, the Season
## emblem), the full name (the grid's line count) and the price row (exact
## price, or Owned).  Season 1 Premium is one wide card.
class ShopCard:
	extends Button
	var shop: ShopScreen
	var id := ""
	var kind := ""
	var name_l: Label
	var price_l: Label
	var coin: Control
	var art: Control
	var lines := 1
	var wide := false
	var _sum: Label
	var _row: Control
	var _wide_w := 0.0

	## The picture well's height per item (a share of its width).
	static func well_of(item_id: String) -> float:
		var k := ShopCard.kind_of(item_id)
		return float(ShopScreen.WELL.get(k, CreatorScreen.WELL.get(k, 1.0)))

	static func kind_of(item_id: String) -> String:
		var k := Catalogue.kind(item_id)
		var f := String(Catalogue.split(item_id)[0])
		if k == "coin_pack":
			return "coins"
		if k == "season_premium":
			return "glyph"
		if f in ShopScreen.SWATCH_FIELDS:
			return "swatch"
		if f == "emote":
			return "emote"
		return String(ShopScreen.THUMB_FRAMING.get(f, "glyph"))

	func setup(s: ShopScreen, item_id: String, w: float) -> void:
		shop = s
		id = item_id
		name = "Card_" + item_id.replace(":", "_")
		kind = ShopCard.kind_of(id)
		wide = Catalogue.kind(id) == "season_premium"
		UIKit.make_card(self, Vector2(w, 0), Color(UIKit.SLATE_HI, 0.96))
		var face := UIKit.face_of(self)
		if wide:
			_setup_wide(face, w)
			return
		var v := CreatorScreen.card_column(face)
		art = ShopCard.art_for(s, id, 0.0, "shop:%s" % id)
		art.name = "Well"
		art.size_flags_horizontal = Control.SIZE_FILL
		v.add_child(art)
		name_l = CreatorScreen.name_label(Catalogue.display_name(id))
		v.add_child(name_l)
		var row := UIKit.hbox(6)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size.y = CreatorScreen.STATE_H
		coin = CommerceArt.Pic.new("coin", "", Color.WHITE, 20)
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(coin)
		price_l = UIKit.styled("", "num", UIKit.AMBER)
		price_l.add_theme_font_size_override("font_size", 20)
		price_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		price_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(price_l)
		v.add_child(row)
		fit_cell(w, name_lines(w))

	## Season 1 Premium: the emblem, the name, what it adds (counted from the
	## Season table) and the price, in one compact row-shaped card.
	func _setup_wide(face: Control, w: float) -> void:
		var h := UIKit.hbox(UIKit.SP_L)
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 12
		h.offset_right = -12
		h.offset_top = 10
		h.offset_bottom = -10
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_child(h)
		art = ShopCard.art_for(shop, id, 96.0, "shop:%s" % id)
		art.name = "Well"
		art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(art)
		var tv := UIKit.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(tv)
		name_l = UIKit.styled(Catalogue.display_name(id), "label", UIKit.IVORY)
		name_l.clip_text = true
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(name_l)
		_sum = UIKit.styled(ShopScreen.premium_summary(String(Catalogue.item(id).get("season", "s1"))), "caption", UIKit.IVORY_MUTED)
		_sum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_sum.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(_sum)
		var row := UIKit.hbox(6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		coin = CommerceArt.Pic.new("coin", "", Color.WHITE, 22)
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(coin)
		price_l = UIKit.styled("", "num", UIKit.AMBER)
		price_l.add_theme_font_size_override("font_size", 20)
		price_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(price_l)
		tv.add_child(row)
		_row = h
		_wide_w = w
		# the text's height is known once it is themed in the tree
		h.minimum_size_changed.connect(func() -> void: _fit_wide(_wide_w))
		_fit_wide(w)

	## The wide card is as tall as its text needs at this width (the art is
	## centred beside it): nothing spills past the card.
	func _fit_wide(w: float) -> void:
		_wide_w = w
		_sum.custom_minimum_size.x = maxf(100.0, w - 96.0 - UIKit.SP_L - 24.0 - 4.0)
		var need := maxf(96.0, _row.get_combined_minimum_size().y)
		custom_minimum_size = Vector2(w, maxf(UIKit.row_h(), need + 20.0))

	func name_lines(w: float) -> int:
		if wide:
			return 1
		return mini(2, UIKit.lines_for(name_l.text, UIKit.font_w(600), CreatorScreen.NAME_FS, w - CreatorScreen.PAD * 2.0))

	func fit_cell(w: float, n: int) -> void:
		if wide:
			_fit_wide(w)
			return
		lines = n
		var iw := w - CreatorScreen.PAD * 2.0
		var wh := roundf(iw * ShopCard.well_of(id))
		art.custom_minimum_size = Vector2(0, wh)
		name_l.custom_minimum_size = Vector2(iw, CreatorScreen.name_block_h(n))
		name_l.max_lines_visible = n
		custom_minimum_size = Vector2(w, CreatorScreen.PAD * 2.0 + wh + CreatorScreen.ROW_GAP * 2.0 + CreatorScreen.name_block_h(n) + CreatorScreen.STATE_H)

	func refresh() -> void:
		var st: Dictionary = shop.state_of(id)
		price_l.text = String(st["text"])
		price_l.add_theme_color_override("font_color", st["col"])
		coin.visible = String(st["kind"]) == "coins"
		accessibility_name = "%s, %s%s" % [Catalogue.display_name(id), Catalogue.type_label(id),
			", " + String(st["text"]) + (" Coins" if String(st["kind"]) == "coins" else "")]

	## The picture for an item: runner items are cached portraits of your
	## runner wearing it (neutral accessories for outfits); colours are
	## swatches; emotes their glyph; packs a Coin pile; Premium the pass.
	static func art_for(s: ShopScreen, item_id: String, size_u: float, owner: String) -> Control:
		var holder := ShopPic.new()
		holder.custom_minimum_size = Vector2(size_u, size_u)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var k := Catalogue.kind(item_id)
		var f := String(Catalogue.split(item_id)[0])
		if k == "coin_pack":
			holder.coins = int(Catalogue.item(item_id).get("coins", 0))
		elif k == "season_premium":
			holder.glyph = "pass"
		elif f in ShopScreen.SWATCH_FIELDS:
			var e := Cosmetics.entry(f, String(Catalogue.split(item_id)[1]))
			holder.swatch = e.get("rgb", Color.WHITE)
		elif f == "emote":
			var eid := TC.EMOTES.find(String(Catalogue.split(item_id)[1]))
			holder.glyph = Icons.emote_icon(eid) if eid >= 0 else "smile"
		elif ShopScreen.THUMB_FRAMING.has(f):
			holder.request(s, item_id, String(ShopScreen.THUMB_FRAMING[f]), owner)
		else:
			holder.glyph = "star"
		return holder


## The picture well (as in the Locker): a portrait cropped to cover the
## well, or drawn art centred in it.
class ShopPic:
	extends Control
	var tex: Texture2D
	var pic_key := ""
	var coins := 0
	var glyph := ""
	var swatch := Color(0, 0, 0, 0)

	func _init() -> void:
		clip_contents = true

	func request(s: ShopScreen, item_id: String, framing: String, owner: String) -> void:
		var parts := Catalogue.split(item_id)
		var look := CommerceArt.preview_look(s.saved, String(parts[0]), String(parts[1]))
		var ps := Portraits.shared()
		pic_key = Portraits.key_for(look, TC.Role.RUNNER, framing)
		var t := ps.portrait(look, TC.Role.RUNNER, owner, framing)
		if ps.has_picture(pic_key):
			tex = t
		elif not ps.portrait_ready.is_connected(_on_pic):
			ps.portrait_ready.connect(_on_pic)
		queue_redraw()

	func _on_pic(k: String, t: Texture2D) -> void:
		if k != pic_key or not is_instance_valid(self):
			return
		tex = t
		queue_redraw()
		if not UIKit.reduced_motion():
			modulate.a = 0.0
			Motion.animate(self, "modulate:a", 1.0, 0.16)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UIKit.box(Color(UIKit.NAVY, 0.38), UIKit.R_SMALL), r)
		var c := size * 0.5
		var s := minf(size.x, size.y)
		if tex != null:
			var src := tex.get_size()
			var k := maxf(size.x / maxf(1.0, src.x), size.y / maxf(1.0, src.y))
			var vis := size / k
			draw_texture_rect_region(tex, r, Rect2((src - vis) * 0.5, vis))
		elif coins > 0:
			CommerceArt.coin_pile(self, c, s * 0.36, coins)
		elif swatch.a > 0.0:
			draw_circle(c + Vector2(0, 2), s * 0.32, swatch.darkened(0.4), true, -1.0, true)
			draw_circle(c, s * 0.32, swatch, true, -1.0, true)
			draw_circle(c + Vector2(-s * 0.1, -s * 0.11), s * 0.07, Color(1, 1, 1, 0.22), true, -1.0, true)
		elif glyph != "":
			CommerceArt.glyph(self, glyph, c, s * 0.34, UIKit.AMBER)
		else:
			# until the portrait is ready: a faint runner silhouette
			var col := Color(UIKit.IVORY, 0.1)
			draw_circle(c + Vector2(0, -s * 0.16), s * 0.13, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.2, s * 0.32), c + Vector2(-s * 0.16, s * 0.02),
				c + Vector2(0, -s * 0.03), c + Vector2(s * 0.16, s * 0.02), c + Vector2(s * 0.2, s * 0.32)]), col)
