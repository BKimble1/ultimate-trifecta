extends RefCounted
## (build 30) Every Season Pass reward works in the game, not only in the
## Season Pass: all 100 tiers, both tracks, claim from the service (Premium
## from Apple, never Coins) and land in the Locker; each kind then does what
## it says:
##   outfits, hats, shoes  - worn: the character builds and shows their parts
##   emotes                - in the emote set, with their animation
##   name cards, badges    - equipped, sent to the party with the look (older
##                           builds skip them) and shown on the roster card
##   Coins                 - added to the wallet once
var t
var rig


func _rig() -> Variant:
	rig = preload("res://tests/commerce_rig.gd").new(t)
	return rig


func _season_items() -> Array:
	var out: Array = []
	for tr in Catalogue.season_tiers("s1"):
		for track in ["free", "premium"]:
			var r: Variant = tr.get(track)
			if r is Dictionary and (r as Dictionary).has("item"):
				out.append(String(r["item"]))
	return out


func test_every_reward_claims_and_lands_in_the_locker() -> void:
	await _rig().begin()
	await rig.sign_in()
	var pid := Cloud.profile_id()
	rig.svc.wallet(pid)["season"]["s1"]["xp"] = Economy.tier_xp("s1", Catalogue.season_tiers("s1").size())
	rig.svc.deliver_premium(pid)
	await Wallet.refresh()
	t.check(Wallet.premium("s1"), "Premium (from Apple)")
	var before := Wallet.balance()
	for i in 12:
		if Wallet.claimable("s1").is_empty():
			break
		await Wallet.claim_all("s1")
	t.eq(Wallet.claimable("s1").size(), 0, "every reward claimed")
	var missing: Array = []
	for id in _season_items():
		if not Wallet.owns_id(String(id)):
			missing.append(id)
	t.eq(missing, [], "every Season item is in the Locker")
	t.eq(Wallet.balance() - before, Economy.season_coin_total("s1", "free") + Economy.season_coin_total("s1", "premium"),
		"every Coin reward added once")
	await rig.end()


func test_wearables_show_on_the_runner() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 360)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	t.add_child(vp)
	var stage := DormStage.new()
	vp.add_child(stage)
	stage.set_mode("lobby", false)
	for id in _season_items():
		var f := String(Catalogue.split(id)[0])
		if not f in ["outfit", "hat", "shoes"]:
			continue
		var k := String(Catalogue.split(id)[1])
		t.check(not Cosmetics.entry(f, k).is_empty(), "%s: a %s the game knows" % [id, f])
		if not Catalogue.has_art(id):
			continue
		var look := Cosmetics.DEFAULT.duplicate()
		look[f] = k
		look = Cosmetics.sanitize(look)
		t.eq(String(look[f]), k, "%s: kept when worn" % id)
		stage.sync_party([{"key": "p0", "role": TC.Role.RUNNER, "cosmetic": look, "name": "Comfy Frog", "is_bot": false, "local": true}])
		await t.get_tree().process_frame
		var v: CharacterView = stage.chars["p0"]
		var want: Array = Cosmetics.runner_parts(look)
		var shown: Array = []
		for n in want:
			if v.parts.has(n) and (v.parts[n] as MeshInstance3D).visible:
				shown.append(n)
		t.eq(shown.size(), want.size(), "%s: every part built and shown (%s)" % [id, str(want)])
	stage.queue_free()
	vp.queue_free()
	await t.get_tree().process_frame


func test_emotes_have_their_animation() -> void:
	var vp := SubViewport.new()
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	t.add_child(vp)
	var stage := DormStage.new()
	vp.add_child(stage)
	stage.set_mode("lobby", false)
	stage.sync_party([{"key": "p0", "role": TC.Role.RUNNER, "cosmetic": Cosmetics.DEFAULT.duplicate(), "name": "Comfy Frog", "is_bot": false, "local": true}])
	await t.get_tree().process_frame
	var cv: CharacterView = stage.chars["p0"]
	var lib := cv.anim.get_animation_library("")
	for id in _season_items():
		if not String(id).begins_with("emote:"):
			continue
		var k := String(Catalogue.split(id)[1])
		t.check(TC.EMOTES.has(k), "%s: in the emote set" % id)
		t.check(lib.has_animation("emote_" + k), "%s: its animation exists" % id)
	stage.queue_free()
	vp.queue_free()
	await t.get_tree().process_frame


func test_name_cards_and_badges_reach_the_party() -> void:
	var cards: Array = []
	var badges: Array = []
	for id in _season_items():
		if String(id).begins_with("card:"):
			cards.append(id)
		elif String(id).begins_with("badge:"):
			badges.append(id)
	t.check(cards.size() >= 10 and badges.size() >= 10, "Season name cards (%d) and badges (%d)" % [cards.size(), badges.size()])
	# wire ids: unique within each kind, so no card is shown as another
	for group in [cards, badges]:
		var seen := {}
		for id in group:
			var vid := Protocol.style_vid(String(id))
			t.check(not seen.has(vid), "%s: its own wire id (%d)" % [id, vid])
			seen[vid] = id
	# every card and badge survives the trip; an old build reads the same look
	for i in maxi(cards.size(), badges.size()):
		var c := String(cards[i % cards.size()])
		var bd := String(badges[i % badges.size()])
		var look := Cosmetics.DEFAULT.duplicate()
		look["card"] = c
		look["badge"] = bd
		var b := StreamPeerBuffer.new()
		Protocol.put_appearance(b, look)
		b.seek(0)
		var back := Protocol.get_appearance(b)
		t.eq([String(back.get("card", "")), String(back.get("badge", ""))], [c, bd], "%s + %s: sent and read" % [c, bd])
		b.seek(1)
		var raw: PackedByteArray = b.get_data(b.data_array[0])[1]
		t.eq(Cosmetics.decode(raw), Cosmetics.sanitize(look), "an older build reads the same look and skips the card")
	# a look without them sends nothing extra
	var plain := StreamPeerBuffer.new()
	Protocol.put_appearance(plain, Cosmetics.DEFAULT)
	plain.seek(0)
	t.check(not Protocol.get_appearance(plain).has("card"), "no name card: none read")
	# on the roster card: the plate and the medallion, for the whole party
	var rig2 := NetRig.new()
	t.add_child(rig2)
	rig2.setup(20, 0, 0.0, 1)
	var guest: NetSession = rig2.clients[0]
	await rig2.wait_until(func() -> bool: return guest.local_slot >= 0 and rig2.host.human_count() == 2, 300)
	var he: Dictionary = rig2.host.roster[rig2.host.local_slot]
	he["cosmetic"] = NetSession.with_style(he["cosmetic"].merged({"card": String(cards[0]), "badge": String(badges[0])}, true))
	rig2.host._broadcast_lobby()
	await rig2.wait_until(func() -> bool:
		var e: Variant = guest.roster[rig2.host.local_slot]
		return e != null and String(e["cosmetic"].get("card", "")) == String(cards[0]), 300)
	var seen_by_guest: Dictionary = guest.roster[rig2.host.local_slot]["cosmetic"]
	t.eq([String(seen_by_guest.get("card", "")), String(seen_by_guest.get("badge", ""))], [cards[0], badges[0]], "the guest sees the host's name card and badge")
	var cell := LobbyScreen.SlotCell.new()
	t.add_child(cell)
	cell.show_entry(guest.roster[rig2.host.local_slot], false, false, {}, false)
	await t.get_tree().process_frame
	t.check(cell.plate.visible and cell.plate.card_id == String(cards[0]), "the roster card wears the name card")
	t.check(cell.medal.visible and cell.medal.badge_id == String(badges[0]), "and shows the badge")
	cell.show_entry(guest.roster[guest.local_slot], true, false, {}, false)
	t.check(not cell.plate.visible and not cell.medal.visible, "a player with none: a plain card")
	cell.queue_free()
	rig2.teardown()
	await t.get_tree().process_frame
	await t.get_tree().process_frame
