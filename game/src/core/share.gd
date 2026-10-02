class_name Share
extends RefCounted
## Native share sheet (iOS UIActivityViewController) through the UTShare iOS
## plugin (ios/plugins/ut_share).  Where the plugin isn't present (desktop,
## or a build without it) the text goes to the clipboard and the caller says
## so; nothing pretends a sheet opened.

const SINGLETON := "UTShare"


static func available() -> bool:
	return Engine.has_singleton(SINGLETON)


## Returns true if the native sheet opened, false if we fell back to copying.
static func share_text(text: String, url: String = "") -> bool:
	if available():
		var s: Object = Engine.get_singleton(SINGLETON)
		s.call("share", text, url)
		return true
	DisplayServer.clipboard_set(text + ("\n" + url if url != "" else ""))
	return false


static func party_message(code: String) -> String:
	return "Join my Ultimate Trifecta party! Open the game, tap Play with Friends and enter %s." % code
