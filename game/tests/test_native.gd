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
