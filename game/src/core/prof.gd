class_name Prof
extends RefCounted
## Development measurement (V8): CPU time per section of a frame, read by the
## gameplay bench (src/dev/match_bench.gd).  Off in normal play: Prof.t()
## returns 0 and Prof.add() returns at once, so a hook costs one static read.
## Sections accumulate microseconds (and counts) until the bench takes them.

static var on := false
static var acc: Dictionary = {}      # section -> microseconds since the last take()
static var cnt: Dictionary = {}      # counter -> occurrences since the last take()


static func t() -> int:
	return Time.get_ticks_usec() if on else 0


static func add(section: String, t0: int) -> void:
	if not on:
		return
	acc[section] = int(acc.get(section, 0)) + Time.get_ticks_usec() - t0


static func count(counter: String, n: int = 1) -> void:
	if not on:
		return
	cnt[counter] = int(cnt.get(counter, 0)) + n


## The sections and counters since the last take(), then cleared.
static func take() -> Dictionary:
	var out := {"us": acc, "n": cnt}
	acc = {}
	cnt = {}
	return out
