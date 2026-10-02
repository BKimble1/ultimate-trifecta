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
