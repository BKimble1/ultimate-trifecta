extends Node
## Minimal test runner: discovers tests/test_*.gd, runs every test_* method
## (methods may await physics frames), prints a summary, exits non-zero on failure.

var failures: Array[String] = []
var checks := 0
var current := ""
var filter := ""
## Script errors raised while a test runs (freed instances, bad calls, ...)
## fail that test, even when its own checks pass.
var _catcher := ErrorCatcher.new()


class ErrorCatcher:
	extends Logger
	var errors: Array[String] = []
	var muted := false

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if muted or error_type != ERROR_TYPE_SCRIPT:
			return
		errors.append("%s (%s:%d in %s)" % [rationale if rationale != "" else code, file.get_file(), line, function])


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	await get_tree().process_frame
	OS.add_logger(_catcher)
	var files: Array[String] = []
	var dir := DirAccess.open("res://tests")
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_runner.gd":
			files.append(f)
	files.sort()
	var total := 0
	var t0 := Time.get_ticks_msec()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			current = f
			check(false, "test script failed to compile")
			continue
		var inst: Object = script.new()
		inst.set("t", self)
		for m in inst.get_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			if filter != "" and not (f + ":" + mname).contains(filter):
				continue
			current = f.trim_suffix(".gd") + "::" + mname
			total += 1
			var before := failures.size()
			var ts := Time.get_ticks_msec()
			_catcher.errors.clear()
			await inst.call(mname)
			for e in _catcher.errors.slice(0, 5):
				failures.append("%s: script error: %s" % [current, e])
			var status := "ok" if failures.size() == before else "FAIL"
			print("[%s] %s (%d ms)" % [status, current, Time.get_ticks_msec() - ts])
		if inst.has_method("cleanup"):
			inst.call("cleanup")
	print("\n%d tests, %d checks, %d failures in %.1fs" % [total, checks, failures.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	for f in failures:
		print("  FAIL: " + f)
	get_tree().quit(1 if failures.size() > 0 else 0)


func check(cond: bool, msg: String) -> bool:
	checks += 1
	if not cond:
		failures.append("%s: %s" % [current, msg])
		_catcher.muted = true
		push_error("%s: %s" % [current, msg])
		_catcher.muted = false
	return cond


func eq(a: Variant, b: Variant, msg: String) -> bool:
	return check(a == b, "%s (got %s, expected %s)" % [msg, str(a), str(b)])


func near(a: float, b: float, tol: float, msg: String) -> bool:
	return check(absf(a - b) <= tol, "%s (got %.4f, expected %.4f ±%.4f)" % [msg, a, b, tol])


func physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
