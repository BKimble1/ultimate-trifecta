extends RefCounted
## Beta diagnostics: bounded, in-memory, attributes stalls to the latest
## state marker, and the shareable summary carries no names, room codes or
## Game Center identifiers.
var t


func test_ring_histogram_and_stall_attribution() -> void:
	var was: bool = Diag.enabled
	Diag.clear()
	Diag.enabled = true
	Diag.context("match")
	for i in 120:
		Diag._record(16.7)
	Diag.mark("tag")
	Diag._record(140.0)
	for i in 3000:
		Diag._record(16.7)
	var s: Dictionary = Diag.stats("match")
	t.eq(int(s["n"]), 3121, "every frame counted")
	t.eq(int(s["over50"]), 1, "one stall over 50 ms")
	t.eq(int(s["over100"]), 1, "and over 100 ms")
	t.near(Diag.percentile(s["hist"], int(s["n"]), 0.5), 16.5, 1.0, "p50 from the 1 ms histogram")
	t.check(Diag.percentile(s["hist"], int(s["n"]), 0.99) < 20.0, "p99 unaffected by one stall")
	t.eq(String(Diag.stalls()[-1]["mark"]), "tag", "stall attributed to the marker just before it")
	t.eq(Diag.recent(10).size(), 10, "recent window")
	for i in 500:
		Diag.mark("m%d" % i)
	t.check(Diag._marks.size() <= Diag.MAX_MARKS, "marker list is bounded")
	for i in 500:
		Diag._record(80.0)
	t.check(Diag.stalls().size() <= Diag.MAX_STALLS, "stall list is bounded")
	t.eq(Diag._ring.size(), Diag.RING, "interval ring is fixed size")
	Diag.clear()
	Diag.enabled = was


func test_summary_has_no_identifiers() -> void:
	var was: bool = Diag.enabled
	Diag.clear()
	Diag.enabled = true
	Diag.context("lobby")
	for i in 30:
		Diag._record(17.0)
	Diag.net_sample(0.12, 0.03)
	var old_name := String(Save.data.get("name", ""))
	Save.data["name"] = "Zebra Quokka"
	var txt: String = Diag.summary()
	t.check(txt.contains("Frame interval") and txt.contains("lobby"), "per-context table present")
	t.check(not txt.contains("Zebra Quokka"), "no player name")
	t.check(not txt.contains(Save.player_uid()), "no player id")
	t.check(txt.contains("unavailable"), "unsupported counters say unavailable")
	Save.data["name"] = old_name
	Diag.clear()
	Diag.enabled = was
