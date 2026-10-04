extends RefCounted
## Portrait jobs (V4): stale requests are skipped and the queue is bounded.
## (Rendering itself needs a display; headless runs only get placeholders.)
var t


func test_newer_request_from_same_owner_replaces_queued_one() -> void:
	var p := Portraits.new()
	p._enqueue({"key": "a", "role": 0, "app": {}, "owner": "cell1"})
	p._enqueue({"key": "b", "role": 0, "app": {}, "owner": "cell2"})
	p._enqueue({"key": "c", "role": 0, "app": {}, "owner": "cell1"})
	t.eq(p.pending(), 2, "cell1's older look is never rendered")
	t.eq(String(p._queue[0]["key"]), "b", "others keep their place")
	t.eq(String(p._queue[1]["key"]), "c", "the newest look is queued")
	t.eq(p.dropped, 1, "counted as skipped")
	p._enqueue({"key": "c", "role": 0, "app": {}, "owner": "sheet"})
	t.eq(p.pending(), 2, "the same look is queued once")
	p.free()


func test_queue_is_bounded() -> void:
	var p := Portraits.new()
	for i in Portraits.MAX_QUEUE + 5:
		p._enqueue({"key": "k%d" % i, "role": 0, "app": {}, "owner": ""})
	t.eq(p.pending(), Portraits.MAX_QUEUE, "bounded")
	t.eq(String(p._queue[0]["key"]), "k5", "oldest requests drop first")
	p.free()


func test_headless_gets_placeholder_without_work() -> void:
	var p := Portraits.new()
	var tex := p.portrait(Cosmetics.DEFAULT)
	t.check(tex is GradientTexture2D, "placeholder")
	t.eq(p.pending(), 0, "nothing queued without a display")
	p.free()


## V7: every key carries the art version (the runner.glb build, generated
## with the asset, plus the renderer's look), so a build with new character
## art can never show a cached picture of the old one.
func test_keys_carry_the_art_version() -> void:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/runner_manifest.json"))
	t.eq(CharacterArt.VERSION, String(m.get("art_version", "")), "CharacterArt matches runner_manifest.json (rebuilt together)")
	t.eq(FileAccess.get_sha256("res://assets/characters/runner.glb"), CharacterArt.GLB_SHA256,
		"CharacterArt names the committed runner.glb (rebuild with tools/character/build.sh)")
	var v := Portraits.art_version()
	t.check(v.begins_with(CharacterArt.VERSION), "the art version starts with the asset's (%s)" % v)
	var k := Portraits.key_of(Cosmetics.DEFAULT, TC.Role.RUNNER)
	t.check(k.begins_with(v + ":"), "a portrait key starts with the art version (%s)" % k)
	t.check(Portraits.key_for(Cosmetics.DEFAULT, TC.Role.RUNNER, "body").begins_with(v + ":"), "so does every framing's key")
	var v6_key := "%d:%s" % [TC.Role.RUNNER, Cosmetics.encode(Cosmetics.DEFAULT).hex_encode()]
	t.check(k != v6_key and not k.begins_with(v6_key), "a V6-style key (no version) never matches")
	t.check(Portraits.key_of(Cosmetics.DEFAULT, TC.Role.RUNNER) != Portraits.key_of(Cosmetics.DEFAULT, TC.Role.PATROL),
		"roles still have their own pictures")
