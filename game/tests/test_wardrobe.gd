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
	Save.data["cosmetic"] = Cosmetics.sanitize({})
	Save.data["coins"] = 0
	var c := _open()
	await _frames(2)
	t.eq(c.apply_btn.text, "Wearing this", "unchanged: the button says so")
	t.check(c.apply_btn.disabled and not c.undo_btn.visible, "and is unavailable, with nothing to undo")
	c._pick("hat", "crown")    # costs coins
	t.check(c.apply_btn.disabled and c.apply_btn.text.begins_with("Need "), "unaffordable: '%s'" % c.apply_btn.text)
	t.check(c.undo_btn.visible, "Undo appears")
	var dis := UIKit.face_of(c.apply_btn).styles["disabled"] as StyleBoxFlat
	t.check(dis.bg_color.a > 0.95, "the unavailable button stays solid (it explains, it doesn't fade)")
	c._on_cancel()
	t.eq(c.draft, c.saved, "Undo returns to the saved look")
	c._pick("hat", "none")     # free
	t.eq(c.apply_btn.text, "Apply", "a free change: Apply")
	t.check(not c.apply_btn.disabled, "available")
	c._on_apply()
	t.eq(String(Cosmetics.sanitize(Save.data["cosmetic"])["hat"]), "none", "applied and saved")
	t.eq(c.apply_btn.text, "Wearing this", "and the button returns to its resting state")
	await _close(c)
	Save.data["cosmetic"] = saved_cos
	Save.data["coins"] = saved_coins
