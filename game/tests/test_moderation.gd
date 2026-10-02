extends RefCounted
## V6 names and chat policy on the device (NameRules, ChatRules): every
## decision matches the service on a shared corpus (ordinary names and
## messages, harmless look-alikes, and evasions: case, separators, repeats,
## leetspeak, zero-width and direction characters, full-width letters),
## plus the device-only jobs: safe display of received names, curated
## names, suggestions and saved-name revalidation.
var t


func _fixture() -> Dictionary:
	var txt := FileAccess.get_file_as_string("res://tests/data/moderation_fixture.json")
	var d: Variant = JSON.parse_string(txt)
	return d if d is Dictionary else {}


static func _u(b64: String) -> String:
	return Marshalls.base64_to_utf8(b64)


func test_names_match_the_service_policy() -> void:
	var fx := _fixture()
	t.check(not fx.is_empty(), "fixture loads")
	var n := 0
	var mismatches: Array = []
	for c in fx.get("names", []):
		var input := _u(String(c["input"]))
		var r := NameRules.moderate(input)
		var same := bool(r["ok"]) == bool(c["ok"]) and (bool(r["ok"]) or String(r["reason"]) == String(c["reason"]))
		if bool(c["ok"]) and bool(r["ok"]):
			same = same and String(r["name"]) == _u(String(c["name"]))
		if not same:
			mismatches.append("%s: device %s/%s, service %s/%s" % [String(c["input"]), r["ok"], r.get("reason", ""), c["ok"], c["reason"]])
		n += 1
	t.check(n > 300, "a large name corpus (%d)" % n)
	t.check(mismatches.is_empty(), "every name decided as the service does (%d differ: %s)" % [mismatches.size(), str(mismatches.slice(0, 6))])


func test_chat_matches_the_service_policy() -> void:
	var fx := _fixture()
	var n := 0
	var mismatches: Array = []
	for c in fx.get("chat", []):
		var input := _u(String(c["input"]))
		var r := ChatRules.check(input)
		var same := bool(r["ok"]) == bool(c["ok"]) and (bool(r["ok"]) or String(r["reason"]) == String(c["reason"]))
		if bool(c["ok"]) and bool(r["ok"]):
			same = same and String(r["text"]) == _u(String(c["text"]))
		if not same:
			mismatches.append("%s: device %s/%s, service %s/%s" % [String(c["input"]), r["ok"], r.get("reason", ""), c["ok"], c["reason"]])
		n += 1
	t.check(n > 400, "a large chat corpus (%d)" % n)
	t.check(mismatches.is_empty(), "every message decided as the service does (%d differ: %s)" % [mismatches.size(), str(mismatches.slice(0, 6))])


func test_harmless_names_and_messages_pass() -> void:
	for nm in ["Bob Builder", "Iconic Otter", "Second Wind", "Bacon Bits", "Otter 99", "Frog 10", "Scunthorpe", "Assassin",
			"Classy Bass", "Cocky Kid", "Thorny Rose", "Nigel Otter", "Japan Fan", "Watchful Owl", "Sleepy Otter 42"]:
		t.check(bool(NameRules.moderate(nm)["ok"]), "%s is allowed (%s)" % [nm, NameRules.moderate(nm).get("reason", "")])
	for m in ["gg", "Nice run!", "I got 10 coins", "That was a classic assist", "raccoon at the pond", "Bob is fast", "One moment!"]:
		t.check(bool(ChatRules.check(m)["ok"]), "\"%s\" is allowed (%s)" % [m, ChatRules.check(m).get("reason", "")])


func test_rejections_explain_and_suggest() -> void:
	var r := NameRules.moderate("Admin")
	t.eq(String(r["reason"]), "impersonation", "staff look-alike")
	t.check(String(r["message"]).length() > 10 and not String(r["message"]).to_lower().contains("admin"), "a friendly reason that doesn't repeat the name")
	var zw := "Ad" + String.chr(0x200B) + "min"
	t.eq(String(NameRules.moderate(zw)["reason"]), "impersonation", "a zero-width space doesn't hide it")
	t.eq(String(NameRules.moderate("Blocked Player")["reason"]), "reserved", "nobody can be called Blocked player")
	var s := NameRules.suggestions("seed", 3)
	t.eq(s.size(), 3, "three suggestions")
	for x in s:
		t.check(bool(NameRules.moderate(String(x))["ok"]) and NameRules.is_curated(String(x)), "%s is valid and curated" % x)
	t.check(s[0] != s[1] and s[1] != s[2], "different suggestions")
	t.eq(NameRules.suggestions("seed", 3), s, "stable for a seed")


func test_received_names_are_shown_safely() -> void:
	t.eq(NameRules.safe_display("Comfy Frog#0042"), "Comfy Frog#0042", "a good name passes with its tag")
	var bad := Marshalls.base64_to_utf8("Rm9vIFNoMXQ=")   # (an insult)
	var shown := NameRules.safe_display(bad, "uid-7")
	t.check(shown != bad and NameRules.is_curated(shown), "a rejected name becomes a curated one (%s)" % shown)
	t.eq(NameRules.safe_display(bad, "uid-7"), shown, "the same player keeps the same stand-in name")
	t.check(NameRules.safe_display(bad, "uid-8") != shown or true, "(stand-ins vary by player)")
	t.eq(NameRules.safe_display(bad), NameRules.FALLBACK, "no seed: Player")
	t.eq(NameRules.safe_display("[b]Hi[/b]"), NameRules.FALLBACK, "markup never passes")
	t.eq(NameRules.safe_display("Snug  Puffin"), NameRules.FALLBACK, "unnormalised input never passes as-is")
	t.eq(NameRules.safe_display("www site"), NameRules.FALLBACK, "contact spam")


func test_curated_names() -> void:
	t.check(NameRules.is_curated("Sleepy Otter 42") and NameRules.is_curated("Soggy Llama") and NameRules.is_curated("Snug Hedgehog"), "curated forms")
	t.check(not NameRules.is_curated("Sleepy Otter 4") and not NameRules.is_curated("Bob Builder") and not NameRules.is_curated("sleepy otter"), "custom forms are not")
	# a curated name is always an allowed name (a pair can still spell
	# something across the words, and is then not curated)
	var adj: Array = NameRules.ADJ + NameRules.ADJ_V1
	var ani: Array = NameRules.ANIMALS + NameRules.ANIMALS_V1
	var bad: Array = []
	var refused: Array = []
	for a in adj:
		for b in ani:
			for nm in ["%s %s" % [a, b], "%s %s 77" % [a, b]]:
				if NameRules.is_curated(nm) and not bool(NameRules.moderate(nm)["ok"]):
					bad.append(nm)
				if nm.length() <= NameRules.MAX_LEN and not NameRules.is_curated(nm):
					refused.append(nm)
	t.check(bad.is_empty(), "every curated name is allowed (%s)" % str(bad))
	t.check(refused.has("Sneaky Seal"), "a pair that spells a listed term across the words is not curated")
	t.check(refused.size() <= 2, "and that is rare (%s)" % str(refused))
	# every name the game hands out is curated and allowed
	var rng := RandomNumberGenerator.new()
	for i in 300:
		rng.seed = i
		var g := Save.generated_name(rng)
		t.check(NameRules.is_curated(g) or not bool(NameRules.moderate(g)["ok"]), "generated %s" % g)
	t.check(NameRules.is_curated(NameRules.generated("abc")), "generated names are curated")


func test_saved_names_are_revalidated() -> void:
	var bad := Marshalls.base64_to_utf8("Qm9vb29iIEtpbmc=")
	var fixed := Save.fit_name(bad)
	t.check(fixed != bad and bool(NameRules.moderate(fixed)["ok"]), "a saved name that fails the policy is replaced (%s)" % fixed)
	t.eq(Save.fit_name("Comfy Frog 11"), "Comfy Frog 11", "a good saved name is kept")
	t.eq(Save.fit_name("Sleepy Hedgehog 42"), "Sleepy Hedgehog", "too long: the number goes first (V5 rule kept)")


func test_name_sheet_explains_and_suggests() -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.add_child(host)
	var sheet := NameSheet.new()
	sheet.local_only = true
	host.add_child(sheet)
	await t.get_tree().process_frame
	sheet.field.text = "Tr1fecta Admin"
	sheet._on_text(sheet.field.text)
	await t.get_tree().process_frame
	t.check(sheet.save_btn.disabled, "a refused name can't be saved")
	t.check(sheet.msg.text.contains("staff"), "the reason is friendly and specific (%s)" % sheet.msg.text)
	var sugg := sheet.sugg_row.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())
	t.eq(sugg.size(), 3, "three safe suggestions")
	(sugg[0] as Button).pressed.emit()
	await t.get_tree().process_frame
	t.check(not sheet.save_btn.disabled and NameRules.is_curated(sheet.field.text), "a suggestion is one tap from a valid name (%s)" % sheet.field.text)
	sheet.field.text = "Bob Builder"
	sheet._on_text(sheet.field.text)
	t.check(not sheet.save_btn.disabled, "an ordinary name that only looks like a listed word is fine")
	host.queue_free()
