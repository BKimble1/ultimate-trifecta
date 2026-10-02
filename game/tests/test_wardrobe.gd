extends RefCounted
## V5 wardrobe: readable names, pictures that land on every card showing a
## look, stale thumbnail work dropped on category changes, and Apply / Undo
## that say what they will do.
var t
var _stage: DormStage


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _open() -> CreatorScreen:
	_stage = DormStage.new()
	t.add_child(_stage)
	App.stage = _stage
	_stage.set_mode("wardrobe", false)
	App.sync_stage_local()
	var c := CreatorScreen.new()
	t.add_child(c)
	return c


func _close(c: CreatorScreen) -> void:
	c.queue_free()
	if is_instance_valid(_stage):
		_stage.queue_free()
	App.stage = null
	await _frames(2)


func test_every_item_name_is_readable_without_ellipsis() -> void:
	# the narrowest card the layout ever makes (3 columns on a compact phone)
	var w := CreatorScreen.CARD_W
	var f := UIKit.font_w(600)
	var too_long: Array[String] = []
	for field in Cosmetics.ORDER:
		if field in CreatorScreen.SWATCH_FIELDS:
			continue
		for k in Cosmetics.keys_of(field):
			var nm := String(Cosmetics.entry(field, k)["name"])
			var para := TextParagraph.new()
			para.add_string(nm, f, 20)
			para.width = w - 20.0
			para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
			var lines := para.get_line_count()
			var widest := 0.0
			for i in lines:
				widest = maxf(widest, para.get_line_width(i))
			if lines > 2 or widest > w - 20.0 + 0.5:
				too_long.append("%s (%d lines)" % [nm, lines])
	t.eq(too_long, [] as Array[String], "every item name fits in two lines at the narrowest card, at full size (no shrinking, no ellipsis)")
	# the supplied playtest screenshot's trimmed names, by name
	for nm in ["Swim Trunks", "Frog Onesie", "Wide Bands", "Fluffy Robe", "Duck Mascot", "Swim Cap + Goggles", "Bunny Slippers", "Pinstripes"]:
		t.check(not too_long.any(func(s: String) -> bool: return s.begins_with(nm)), "%s reads in full" % nm)


func test_a_picture_lands_on_every_card_showing_that_look() -> void:
	var saved_cos: Variant = Save.data["cosmetic"]
	Save.data["cosmetic"] = Cosmetics.sanitize({})
	var c := _open()
	await _frames(3)
	# the equipped outfit card and the selected pattern card show the same look
	var outfit_card: CreatorScreen.ItemCard = null
	var pattern_card: CreatorScreen.ItemCard = null
	for card in c.cards:
		if card.field == "outfit" and card.key == String(c.draft["outfit"]):
			outfit_card = card
		if card.field == "pattern" and card.key == String(c.draft["pattern"]):
			pattern_card = card
	t.check(outfit_card != null and pattern_card != null, "both cards exist")
	t.eq(outfit_card.pic_key, pattern_card.pic_key, "(V4 bug setup) the two cards share one picture key")
	var tex := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	Portraits.shared().portrait_ready.emit(outfit_card.pic_key, tex)
	t.check(outfit_card.pic.texture == tex and pattern_card.pic.texture == tex, "the finished picture lands on both (V4 left the equipped one on a placeholder)")
	t.check(not (outfit_card.holder as CreatorScreen.PicHolder).placeholder, "no placeholder left")
	# a stale picture (a look no card shows any more) lands nowhere
	var other := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	Portraits.shared().portrait_ready.emit("0:stale:body", other)
	t.check(outfit_card.pic.texture == tex, "a stale picture doesn't replace it")
	await _close(c)
	Save.data["cosmetic"] = saved_cos


func test_rapid_category_switching_drops_stale_work() -> void:
	var c := _open()
	await _frames(2)
	var ps := Portraits.shared()
	for round_i in 3:
		for i in CreatorScreen.TABS.size():
			c._step_tab(1)
			await _frames(1)
	# whatever was queued for earlier categories is gone; only the current
	# category's cards may be waiting (headless never renders)
	var cur := {}
	for card in c.cards:
		cur["tile:%s:%s" % [card.field, card.key]] = true
	var stale := ps._queue.filter(func(q: Dictionary) -> bool: return String(q["owner"]).begins_with("tile:") and not cur.has(String(q["owner"])))
	t.eq(stale.size(), 0, "no queued pictures for categories no longer shown")
	t.check(ps._queue.size() <= Portraits.MAX_QUEUE, "the queue stays bounded")
	var selected := 0
	for k in c.tab_btns:
		if UIKit.face_of(c.tab_btns[k]).selected:
			selected += 1
	t.eq(selected, 1, "exactly one category is selected")
	await _close(c)


func test_apply_and_undo_say_what_they_do() -> void:
	var saved_cos: Variant = Save.data["cosmetic"]
	var saved_coins: Variant = Save.data["coins"]
	var saved_owned: Variant = Save.data["owned"]
	Save.data["cosmetic"] = Cosmetics.sanitize({})
	Save.data["coins"] = 0
	Save.data["owned"] = []
	var c := _open()
	await _frames(2)
	t.eq(c.apply_btn.text, "Wearing this", "unchanged: the button says so")
	t.check(c.apply_btn.disabled and not c.undo_btn.visible, "and is unavailable, with nothing to undo")
	c._pick("hat", "none")     # free
	t.eq(c.apply_btn.text, "Save look", "a change: Save look (never a price)")
	t.check(not c.apply_btn.disabled, "available")
	t.check(c.undo_btn.visible, "Undo appears")
	c._on_cancel()
	t.eq(c.draft, c.saved, "Undo returns to the saved look")
	c._pick("hat", "none")
	c._on_apply()
	t.eq(String(Cosmetics.sanitize(Save.data["cosmetic"])["hat"]), "none", "saved")
	t.eq(int(Save.data["coins"]), 0, "saving never spends")
	t.eq(c.apply_btn.text, "Wearing this", "and the button returns to its resting state")
	await _close(c)
	Save.data["cosmetic"] = saved_cos
	Save.data["coins"] = saved_coins
	Save.data["owned"] = saved_owned


## V6 Locker: only owned and free items are shown; what isn't owned is a
## "View in Shop" link, never a price; nothing in the Locker can spend.
func test_locker_shows_only_owned_items() -> void:
	var saved_owned: Variant = Save.data["owned"]
	var saved_cos: Variant = Save.data["cosmetic"]
	Save.data["owned"] = ["hat:crown"]
	Save.data["cosmetic"] = Cosmetics.sanitize({})
	var c := _open()
	await _frames(2)
	c._select_tab("hat")
	await _frames(2)
	var keys: Array = c.cards.map(func(x: Variant) -> String: return String(x.key))
	t.check(keys.has("crown") and keys.has("none") and keys.has("nightcap"), "owned (pre-V6 crown) and free hats shown: %s" % [keys])
	t.check(not keys.has("headphones") and not keys.has("party"), "unowned hats are not in the Locker")
	t.check(c.discover.size() == 1 and c.discover[0].accessibility_name.contains("View in Shop"), "one 'View in Shop' link for the rest")
	for card in c.cards:
		t.check(not String(card.state_l.text).contains("coin") and not String(card.state_l.text).contains("¢"), "%s shows no price" % card.key)
	c._select_tab("colours")
	await _frames(2)
	t.check(c.swatches.all(func(sw: Variant) -> bool: return Wallet.owns(sw.field, sw.key)), "only owned colours")
	t.check(c.discover.size() >= 1, "more colours: a Shop link")
	c._select_tab("profile")
	await _frames(2)
	t.check(c.cards.size() >= 2, "Profile: 'None' for the name card and the badge")
	t.check(c.cards.all(func(x: Variant) -> bool: return x.key == "" or Wallet.owns_id(String(x.key))), "only owned name cards / badges")
	await _close(c)
	Save.data["owned"] = saved_owned
	Save.data["cosmetic"] = saved_cos


func test_category_strip_fits_narrow_panels() -> void:
	var c := _open()
	await _frames(2)
	var row := (c.tab_btns["outfit"] as Control).get_parent() as HBoxContainer
	var strip := row.get_parent() as ScrollContainer
	var wide := c.tabs_width(row, UIKit.T_LABEL, 18) + 40.0
	strip.size.x = wide
	await _frames(2)
	t.eq((c.tab_btns["outfit"] as Button).get_theme_font_size("font_size"), UIKit.T_LABEL, "room to spare: full-size labels")
	# the iPhone SE panel: every category must show whole, no cut-off word
	var narrow := c.tabs_width(row, UIKit.T_CAPTION, 10) + 2.0
	t.check(narrow < wide - 60.0, "a narrower panel (%d vs %d)" % [narrow, wide])
	strip.size.x = narrow
	await _frames(2)
	t.check(row.get_combined_minimum_size().x <= narrow + 0.5, "every category fits whole (%d of %d)" % [row.get_combined_minimum_size().x, narrow])
	for k in c.tab_btns:
		var b := c.tab_btns[k] as Button
		t.check(b.size.x >= UIKit.touch_min() - 0.5, "%s stays a full touch target" % k)
		# and its face draws the whole word (no trim inside the face's padding)
		var face := UIKit.face_of(b)
		var text_w := b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
		t.check(text_w <= face.size.x - 2.0 * face.text_pad() + 0.5, "%s: the word fits inside its face (%d of %d)" % [b.text, text_w, face.size.x - 2.0 * face.text_pad()])
	await _close(c)


## V6: each category keeps its scroll position; switching quickly never
## lands one category's position on another, and a screen closed before the
## restore leaves nothing to run.
func test_category_positions_survive_rapid_switching() -> void:
	var saved_size: Vector2i = t.get_tree().root.size
	t.get_tree().root.size = Vector2i(1280, 720)
	var c := _open()
	await _frames(4)
	c._select_tab("face")
	await _frames(4)
	var room: int = int(c.scroll.get_v_scroll_bar().max_value - c.scroll.size.y)
	t.check(room >= 40, "the face list scrolls here (%d px of room)" % room)
	var pos := mini(room, 300)
	c.scroll.scroll_vertical = pos
	await _frames(2)
	# away and back within frames: the restore pending for one category must
	# never land on another, and face's own position comes back
	c._select_tab("hat")
	c._select_tab("hair")
	c._select_tab("face")
	await _frames(3)
	t.eq(c.scroll.scroll_vertical, pos, "the category comes back where it was")
	t.eq(int(c._scroll_of.get("hair", -1)), 0, "a category switched through at once keeps its top")
	c._select_tab("hair")
	await _frames(3)
	t.eq(c.scroll.scroll_vertical, 0, "and opens at its own position, not face's")
	c._select_tab("face")
	await _frames(3)
	t.eq(c.scroll.scroll_vertical, pos, "face again")
	# closed with a restore pending: nothing runs against a freed screen
	c._select_tab("hair")
	c.queue_free()
	await _frames(3)
	t.check(not is_instance_valid(c), "the screen is gone and no restore ran on it")
	if is_instance_valid(_stage):
		_stage.queue_free()
	App.stage = null
	t.get_tree().root.size = saved_size
	await _frames(2)
