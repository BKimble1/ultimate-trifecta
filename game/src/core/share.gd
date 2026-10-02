class_name Share
extends RefCounted
## Native share sheet (iOS UIActivityViewController) through the UTShare
## GDExtension (native/ut_share, addons/ut_share).  Where there's no native
## sheet (desktop, tests, or a build without the extension) the text goes to
## the clipboard and the caller says so; nothing pretends a sheet opened.

const CLASS := "UTShare"


## The extension is loaded (any platform).
static func loaded() -> bool:
	return ClassDB.class_exists(CLASS)


## A native share sheet can be shown on this device.
static func available() -> bool:
	return loaded() and bool(ClassDB.class_call_static(CLASS, "available"))


## Returns true if the native sheet opened, false if we fell back to copying.
static func share_text(text: String, url: String = "") -> bool:
	if available() and bool(ClassDB.class_call_static(CLASS, "share", text, url)):
		return true
	DisplayServer.clipboard_set(text + ("\n" + url if url != "" else ""))
	return false


static func party_message(code: String) -> String:
	return "Join my Ultimate Trifecta party! Open the game, tap Play with Friends, then Join and enter %s." % code
