class_name ShopScreen
extends Screen
## The Shop (V6): every purchase in the game, and nothing else.
##
##   top     the navigation bar (Play · Locker · Shop · Season Pass) and the
##           Coins chip
##   left    the runner in the dorm, wearing whatever item is selected: drag
##           to turn, Idle / Run / Emote.  This is the one interactive 3D
##           preview (the dorm stage already on screen); cards use cached
##           portraits, never a live viewport each.
##   right   sections (Featured · Outfits · Accessories · Coins · Season 1)
##           over item cards: a picture, the full name, and the exact price
##           (Coins, or the App Store's localized price) or Owned.  Tapping
##           a card previews it on the runner and opens its detail sheet:
##           what it is, exactly what it includes, the price, its state and
##           one purchase action (+ Back).
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
const CARD_W := 158.0
const CARD_GAP := 12.0
const THUMB_FRAMING := {"outfit": "body", "pattern": "body", "hat": "head", "shoes": "feet"}
const SWATCH_FIELDS := ["color", "trim", "hair_color"]

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
	var view := get_viewport().get_visible_rect().size
	back_action = _go_hub
	var top := UIKit.hbox(14)
	content.add_child(top)
	var back := UIKit.icon_button("back")
	back.tooltip_text = "Back"
	back.accessibility_name = "Back"
	back.pressed.connect(_go_back)
	top.add_child(back)
	var nav := NavShell.make("shop")
	nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nav)
	top.add_child(WalletChip.new())

	var mid := UIKit.hbox(16)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(mid)
	_stage_area = ShopStageDrag.new()
	(_stage_area as ShopStageDrag).shop = self
	_stage_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(_stage_area)
	_stage_area.add_child(_preview_controls())

	panel = UIKit.panel(Color(UIKit.SLATE, 0.95), UIKit.R_PANEL, 16)
	var aspect := view.x / maxf(1.0, view.y)
	panel.custom_minimum_size = Vector2(clampf(view.x * (0.56 if aspect > 1.7 else 0.6), 560.0, 900.0), 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(panel)
	var pvb := UIKit.vbox(10)
	pvb.name = "GridView"
	panel.add_child(pvb)
	pvb.add_child(_section_strip())
	banner = UIKit.styled("", "caption", UIKit.AMBER)
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pvb.add_child(banner)
	scroll = UIKit.scroll_area()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	pvb.add_child(scroll)
	body = UIKit.vbox(12)
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
	Motion.settle_in(panel)
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
		var w := get_viewport().get_visible_rect().size.x
		var r := _stage_area.get_global_rect()
		App.stage.set_wardrobe_region((r.get_center().x + r.size.x * 0.12) / maxf(1.0, w), r.size.x / maxf(1.0, w))


# ------------------------------------------------------------------ preview
func _preview_controls() -> Control:
	var pv := UIKit.vbox(8)
	var hint := UIKit.chip("Drag to turn", Color(UIKit.NAVY, 0.6), UIKit.IVORY_MUTED, 18)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pv.add_child(hint)
	var row := UIKit.hbox(8)
	for spec in [["idle", "Idle"], ["run", "Run"], ["emote", "Emote"]]:
		var b := UIKit.quiet(String(spec[1]), Vector2(110, 0), UIKit.T_CAPTION)
		b.name = "Preview_" + String(spec[0])
		var kind: String = spec[0]
		b.pressed.connect(func() -> void: _preview_action(kind))
		row.add_child(b)
	pv.add_child(row)
	pv.move_child(row, 0)
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
		b.custom_minimum_size.y = maxf(56.0, UIKit.touch_min())
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
	sc.custom_minimum_size.y = maxf(56.0, UIKit.touch_min()) + 4.0
	return sc


func select_section(key: String) -> void:
	if detail != null:
		_close_detail()
	if key == section and not cards.is_empty():
		return
	_scroll_of[section] = scroll.scroll_vertical
	Portraits.cancel_shared("shop:")
	section = key
	_build_section()
	Motion.settle_in(body, UIKit.T_FAST)


func _columns() -> int:
	var w := panel.custom_minimum_size.x - 40.0
	return clampi(int(floor((w + CARD_GAP) / (CARD_W + CARD_GAP))), 3, 6)


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
		"featured":
			intro = "New this season, and two skins you can buy directly from the App Store."
		"outfits":
			intro = "Every outfit in the Shop. Prices are exact; everything is cosmetic."
		"accessories":
			intro = "Hats, shoes, colours, patterns and emotes."
		"coins":
			intro = "Coins buy anything in the Shop, including Season 1 Premium. Purchased Coins never expire and never add XP."
		"season":
			intro = "Season 1 · After Hours: 30 tiers you earn by playing. Premium adds a second track of rewards."
	var il := UIKit.styled(intro, "caption", UIKit.IVORY_MUTED)
	il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(il)
	if section == "season":
		body.add_child(_season_offer())
	else:
		var cols := _columns()
		var g := GridContainer.new()
		g.columns = cols if section != "coins" else mini(cols, 3)
		g.add_theme_constant_override("h_separation", int(CARD_GAP))
		g.add_theme_constant_override("v_separation", int(CARD_GAP))
		var w := (panel.custom_minimum_size.x - 40.0 - CARD_GAP * float(g.columns - 1)) / float(g.columns)
		for it in items:
			var card := ShopCard.new()
			card.setup(self, String(it["id"]), maxf(CARD_W, w))
			card.pressed.connect(_open_detail.bind(String(it["id"])))
			g.add_child(card)
			cards.append(card)
		body.add_child(g)
		if items.is_empty():
			body.add_child(UIKit.styled("Nothing here right now.", "body", UIKit.IVORY_MUTED))
	if section in ["featured", "outfits", "coins"]:
		body.add_child(_restore_row())
	_refresh_states()
	var at := int(_scroll_of.get(section, 0))
	(func() -> void:
		await get_tree().process_frame
		if is_instance_valid(scroll):
			scroll.scroll_vertical = at).call()


func _restore_row() -> Control:
	var row := UIKit.hbox(12)
	var l := UIKit.styled("Bought a skin from the App Store on another device?", "caption", UIKit.IVORY_MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
func _season_offer() -> Control:
	var id := String(Catalogue.season(Catalogue.current_season_id()).get("premium_item", "season:s1:premium"))
	var card := ShopCard.new()
	card.setup(self, id, panel.custom_minimum_size.x - 40.0)
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
	var can := Wallet.can_transact()
	banner.text = "" if bool(can["ok"]) else String(can["message"])
	banner.visible = banner.text != ""
	for c in cards:
		if is_instance_valid(c):
			c.refresh()
	if detail != null:
		_refresh_detail()


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
	Motion.settle_in(detail, UIKit.T_FAST)
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
	var v := UIKit.vbox(10)
	v.name = "Detail"
	var top := UIKit.hbox(10)
	var back := UIKit.quiet("‹ Back to Shop", Vector2(0, 0), UIKit.T_CAPTION)
	back.name = "DetailBack"
	back.pressed.connect(_close_detail)
	top.add_child(back)
	top.add_child(UIKit.spacer_h())
	v.add_child(top)
	var sc := UIKit.scroll_area()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var inner := UIKit.vbox(10)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(inner)
	var head := UIKit.hbox(16)
	inner.add_child(head)
	var art := ShopCard.art_for(self, id, 150.0, "shop:detail")
	head.add_child(art)
	var hv := UIKit.vbox(4)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(UIKit.styled(Catalogue.type_label(id) + _kind_note(id), "overline", UIKit.IVORY_MUTED))
	var name_l := UIKit.styled(Catalogue.display_name(id), "headline")
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		inner.add_child(b)
	var inc := UIKit.styled(_includes_text(id), "caption", UIKit.IVORY_MUTED)
	inc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(inc)
	var status := UIKit.styled("", "caption", UIKit.AMBER)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(status)
	var act_row := UIKit.hbox(12)
	v.add_child(act_row)
	var second := UIKit.quiet("", Vector2(200, 84))
	second.name = "DetailSecondary"
	second.pressed.connect(_on_secondary)
	act_row.add_child(second)
	act_row.add_child(UIKit.spacer_h())
	var action := UIKit.primary("", Vector2(330, 88), 26)
	action.name = "DetailAction"
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
				status.text = String(can["message"])
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
			status.text = String(st["message"])
			if Catalogue.kind(id) == "apple_skin":
				second.text = "Restore"
				second.visible = true
		_:
			price_l.text = ""
			action.text = "Not sold"
			action.disabled = true
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
	var buy := UIKit.primary("Buy for %s" % Catalogue.format_coins(price), Vector2(300, 84), 26)
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


## Left area: drag to turn the previewed runner.
class ShopStageDrag:
	extends Control
	var shop: ShopScreen
	var _last := -1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventScreenTouch or e is InputEventMouseButton:
			var pressed: bool = e.pressed
			_last = e.position.x if pressed else -1.0
			shop._drag_from = _last
		elif (e is InputEventScreenDrag or e is InputEventMouseMotion) and _last >= 0.0:
			shop.drag_turn(e.position.x - _last)
			_last = e.position.x


## A Shop card: picture (a cached portrait of your runner wearing it, a
## swatch, an emote icon, Coins or the Season emblem), the full name, and
## the exact price or Owned.
class ShopCard:
	extends Button
	var shop: ShopScreen
	var id := ""
	var name_l: Label
	var price_l: Label
	var coin: Control
	var art: Control

	func setup(s: ShopScreen, item_id: String, w: float) -> void:
		shop = s
		id = item_id
		name = "Card_" + item_id.replace(":", "_")
		var wide := Catalogue.kind(id) == "season_premium"
		var img := (w - 24.0) if not wide else 150.0
		UIKit.make_card(self, Vector2(w, (img + 112.0) if not wide else 210.0), Color(UIKit.SLATE_HI, 0.96))
		var box: BoxContainer = UIKit.vbox(4) if not wide else UIKit.hbox(18)
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 10
		box.offset_right = -10
		box.offset_top = 10
		box.offset_bottom = -8
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIKit.face_of(self).add_child(box)
		art = ShopCard.art_for(s, id, img, "shop:%s" % id)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(art)
		var tv := UIKit.vbox(4)
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_child(tv)
		name_l = UIKit.styled(Catalogue.display_name(id), "label" if not wide else "headline", UIKit.IVORY,
			HORIZONTAL_ALIGNMENT_CENTER if not wide else HORIZONTAL_ALIGNMENT_LEFT)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_l.max_lines_visible = 2
		if not wide:
			name_l.add_theme_font_size_override("font_size", 20)
			name_l.custom_minimum_size = Vector2(w - 20.0, 54.0)
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(name_l)
		if wide:
			var sum := UIKit.styled(ShopScreen.premium_summary(String(Catalogue.item(id).get("season", "s1"))), "caption", UIKit.IVORY_MUTED)
			sum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sum.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tv.add_child(sum)
		var row := UIKit.hbox(6)
		row.alignment = BoxContainer.ALIGNMENT_CENTER if not wide else BoxContainer.ALIGNMENT_BEGIN
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		coin = CommerceArt.Pic.new("coin", "", Color.WHITE, 22)
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(coin)
		price_l = UIKit.styled("", "num", UIKit.AMBER)
		price_l.add_theme_font_size_override("font_size", 20)
		price_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(price_l)
		tv.add_child(row)

	func refresh() -> void:
		var st: Dictionary = shop.state_of(id)
		price_l.text = String(st["text"])
		price_l.add_theme_color_override("font_color", st["col"])
		coin.visible = String(st["kind"]) == "coins"
		accessibility_name = "%s, %s%s" % [Catalogue.display_name(id), Catalogue.type_label(id),
			", " + String(st["text"]) + (" Coins" if String(st["kind"]) == "coins" else "")]

	## The picture for an item: runner items are cached portraits of your
	## runner wearing it; colours are swatches; emotes an icon; packs Coins.
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


## The picture well (as in the Locker): a portrait, or drawn art.
class ShopPic:
	extends Control
	var tex: Texture2D
	var pic_key := ""
	var coins := 0
	var glyph := ""
	var swatch := Color(0, 0, 0, 0)

	func request(s: ShopScreen, item_id: String, framing: String, owner: String) -> void:
		var look: Dictionary = s.saved.duplicate()
		var parts := Catalogue.split(item_id)
		look[String(parts[0])] = String(parts[1])
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
			draw_texture_rect(tex, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false)
		elif coins > 0:
			var n := 1 if coins <= 500 else (2 if coins <= 1500 else 3)
			for i in n:
				CommerceArt.coin(self, c + Vector2((float(i) - float(n - 1) * 0.5) * s * 0.2, -s * 0.06 + float(i % 2) * s * 0.05), s * 0.2)
			var f := UIKit.font_num(800)
			var txt := Catalogue.format_coins(coins)
			var fs := int(s * 0.16)
			var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, Vector2(c.x - w * 0.5, size.y - s * 0.1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.AMBER)
		elif swatch.a > 0.0:
			draw_circle(c + Vector2(0, 2), s * 0.3, swatch.darkened(0.4))
			draw_circle(c, s * 0.3, swatch)
			draw_circle(c + Vector2(-s * 0.09, -s * 0.1), s * 0.06, Color(1, 1, 1, 0.22))
		elif glyph != "":
			CommerceArt.glyph(self, glyph, c, s * 0.28, UIKit.AMBER)
		else:
			# until the portrait is ready: a faint runner silhouette
			var col := Color(UIKit.IVORY, 0.1)
			draw_circle(c + Vector2(0, -s * 0.16), s * 0.13, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.2, s * 0.32), c + Vector2(-s * 0.16, s * 0.02),
				c + Vector2(0, -s * 0.03), c + Vector2(s * 0.16, s * 0.02), c + Vector2(s * 0.2, s * 0.32)]), col)
