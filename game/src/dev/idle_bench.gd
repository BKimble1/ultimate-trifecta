extends Node
## Development-only control for the gameplay bench (src/dev: never exported):
## the machine's own noise floor.  The engine runs an empty scene (no game,
## no rendering work in headless) on the real clock with the same frame cap
## as match_bench, for --secs seconds, and counts the frame intervals that
## the machine alone stretched past 33.3 / 50 / 100 ms (scheduling, other
## processes, the VM).  Long frames that match_bench cannot attribute to any
## instrumented section should be compared with this.
##   tools/gd.sh --headless --path game res://src/dev/idle_bench.tscn -- --fps=60 --secs=180 [--out=FILE.json]

var fps := 60
var secs := 180.0
var out := ""
var _iv := PackedFloat32Array()
var _last := 0
var _t := 0.0


func _ready() -> void:
	process_priority = -100000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fps="):
			fps = int(a.get_slice("=", 1))
		elif a.begins_with("--secs="):
			secs = float(a.get_slice("=", 1))
		elif a.begins_with("--out="):
			out = a.get_slice("=", 1)
	Engine.max_fps = fps


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last > 0:
		_iv.append((now - _last) / 1000.0)
	_last = now
	_t += delta
	if _t < secs:
		return
	var s := _iv.duplicate()
	s.sort()
	var cnt := func(ms: float) -> int:
		var n := 0
		for x in _iv:
			if x > ms:
				n += 1
		return n
	var r := {"fps": fps, "secs": secs, "frames": _iv.size(), "p50": s[int(0.5 * s.size())], "p99": s[int(0.99 * s.size())],
		"max": s[s.size() - 1], "over33": cnt.call(33.3), "over50": cnt.call(50.0), "over100": cnt.call(100.0)}
	printerr("IDLE " + JSON.stringify(r))
	if out != "":
		FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(r, " "))
	get_tree().quit()
