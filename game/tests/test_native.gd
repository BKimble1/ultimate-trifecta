extends RefCounted
## The UTShare GDExtension (native/ut_share) loads into the pinned engine and
## registers its class and static methods; on desktop it reports "no native
## sheet" so the share button copies the code instead of claiming a sheet.
var t


func test_share_extension_registers_and_falls_back_off_device() -> void:
	t.check(ClassDB.class_exists("UTShare"), "UTShare class registered (run tools/build_native.sh)")
	if not ClassDB.class_exists("UTShare"):
		return
	t.check(not ClassDB.can_instantiate("UTShare"), "UTShare is abstract (static methods only)")
	var names := {}
	for m in ClassDB.class_get_method_list("UTShare", true):
		names[m["name"]] = m
	t.check(names.has("share") and names.has("available"), "share() and available() are bound")
	if names.has("share"):
		t.eq(int(names["share"]["flags"]) & METHOD_FLAG_STATIC, METHOD_FLAG_STATIC, "share() is static")
		t.eq((names["share"]["args"] as Array).size(), 2, "share(text, url)")
		t.eq(int(names["share"]["return"]["type"]), TYPE_BOOL, "share() returns bool")
	var on_ios := OS.get_name() == "iOS"
	t.eq(bool(ClassDB.class_call_static("UTShare", "available")), on_ios, "native sheet only on iOS")
	t.eq(bool(ClassDB.class_call_static("UTShare", "share", "Join ✓ ÄÖ party", "")), on_ios, "UTF-8 text crosses the boundary")
	t.eq(bool(ClassDB.class_call_static("UTShare", "share", "text only")), on_ios, "url is optional")
	t.eq(Share.available(), on_ios, "Share wrapper agrees")
	t.eq(Share.share_text(Share.party_message("ACD347")), on_ios, "desktop falls back to the clipboard")
	t.check(Share.party_message("ACD347").contains("ACD347"), "message carries the code")


func test_device_state_for_diagnostics() -> void:
	if not ClassDB.class_exists("UTShare"):
		t.check(false, "UTShare missing")
		return
	t.check(ClassDB.class_has_method("UTShare", "thermal_state") and ClassDB.class_has_method("UTShare", "low_power_mode"),
		"thermal_state() and low_power_mode() are bound")
	var th := int(ClassDB.class_call_static("UTShare", "thermal_state"))
	var lp := int(ClassDB.class_call_static("UTShare", "low_power_mode"))
	if OS.get_name() == "iOS":
		t.check(th >= 0 and th <= 3 and (lp == 0 or lp == 1), "iOS reports real values")
	else:
		t.eq([th, lp], [-1, -1], "desktop reports unavailable (-1), never a made-up state")
	t.eq(Diag.thermal_state(), th, "diagnostics read the same value")


## FINAL_RELEASE_SWEEP: the App Store receipt kind, Cloud's launch routing
## hint (native/ut_share/src/ut_share_ios.m).  Off iOS it is -1, never a
## made-up kind; on a device: 1 "receipt" (App Store), 2 "sandboxReceipt"
## (TestFlight), 0 no receipt URL, 3 another name.
func test_receipt_kind_is_bound_and_honest_off_device() -> void:
	if not ClassDB.class_exists("UTShare"):
		t.check(false, "UTShare missing")
		return
	var m := {}
	for x in ClassDB.class_get_method_list("UTShare", true):
		if x["name"] == "receipt_kind":
			m = x
	t.check(not m.is_empty(), "receipt_kind() is bound")
	if m.is_empty():
		return
	t.eq(int(m["flags"]) & METHOD_FLAG_STATIC, METHOD_FLAG_STATIC, "receipt_kind() is static")
	t.eq((m["args"] as Array).size(), 0, "no arguments")
	t.eq(int(m["return"]["type"]), TYPE_INT, "returns int")
	var k := int(ClassDB.class_call_static("UTShare", "receipt_kind"))
	if OS.get_name() == "iOS":
		t.check(k >= 0 and k <= 3, "iOS answers a kind: %d" % k)
	else:
		t.eq(k, -1, "desktop: unavailable")
	t.eq(Cloud.read_receipt_kind() if not Cloud.receipt_override.is_valid() else k, k, "Cloud reads the same value")
