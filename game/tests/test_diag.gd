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


## V6: physics catch-up frames, a sustained run counted as a spiral (and
## marked on the timeline), the stall context, bounded timeline, summary text.
func test_v6_catchup_spiral_and_stall_context() -> void:
	var was: bool = Diag.enabled
	Diag.clear()
	Diag.enabled = true
	Diag.context("match")
	for i in 10:
		Diag._record(16.7)
		Diag._record_v6(16.7, 0.0167, 1)
	for i in Diag.SPIRAL_FRAMES + 5:
		Diag._record(95.0 if i == 20 else 60.0)
		Diag._record_v6(95.0 if i == 20 else 60.0, 0.06, 6)     # six ticks every frame
	var s: Dictionary = Diag.stats("match")
	var sh: PackedInt32Array = s["steps"]
	t.eq(sh[1], 10, "single-tick frames counted")
	t.check(sh[6] >= Diag.SPIRAL_FRAMES, "six-tick frames counted")
	t.eq(int(s["spirals"]), 1, "a sustained catch-up run is one spiral")
	t.eq(Diag.marker_count("catchup_spiral"), 1, "and it is marked on the timeline")
	var last: Dictionary = Diag.stalls()[-1]
	t.check(last.has("before") and (last["before"] as Array).size() <= Diag.STALL_CONTEXT, "a stall keeps the frames before it (bounded)")
	t.eq(int(last["steps"]), 6, "with its tick count")
	for i in Diag.TIMELINE + 50:
		Diag._record_v6(16.7, 0.0, 1)
	t.eq(Diag.timeline().size(), Diag.TIMELINE, "timeline is bounded")
	var txt := Diag.summary()
	t.check(txt.contains("Simulation (V6)") and txt.contains("catch-up spirals"), "summary reports ticks per frame and spirals")
	t.check(txt.contains("Pipelines compiled"), "and pipeline compilations")
	Diag.clear()
	Diag.enabled = was


## V6: backgrounding is marked, and the time away is not a stall.
func test_background_resume_is_marked_not_counted_as_a_stall() -> void:
	var was: bool = Diag.enabled
	Diag.clear()
	Diag.enabled = true
	Diag.context("match")
	var d: Node = Diag
	d._last_us = Time.get_ticks_usec() - 30 * 1000 * 1000    # "30 s ago"
	d.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	d.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	t.eq(int(d._last_us), 0, "the interval across the time away is dropped")
	t.eq(Diag.marker_count("app_paused"), 1, "going to the background is on the timeline")
	t.eq(Diag.marker_count("app_resumed"), 1, "and coming back")
	d._process(1.0 / 60.0)    # first frame back: starts a fresh interval
	t.eq(int(Diag.stats("match").get("over50", 0)), 0, "no stall recorded for the time away")
	Diag.clear()
	Diag.enabled = was


## V6: counts at each round start (a leak across rounds is a steady climb).
func test_counts_at_each_round_start() -> void:
	var was: bool = Diag.enabled
	Diag.clear()
	Diag.enabled = true
	for i in 14:
		Diag.context("loading")
		Diag.context("match")
		Diag.context("match")      # the same context again is not a new round
	t.eq(Diag._round_starts.size(), 12, "bounded: the first round and the last eleven")
	t.check(Diag.summary().contains("At each round start"), "in the shared summary")
	Diag.clear()
	t.check(Diag._round_starts.is_empty(), "cleared with the rest")
	Diag.context("menu")
	Diag.enabled = was
