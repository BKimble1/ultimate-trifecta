class_name NameRules
extends RefCounted
## Local mirror of the service's character rules for display names (3-16
## letters, digits, single internal spaces, underscores; at least two
## letters; no long numbers).  Used for instant feedback while typing and to
## sanitise names received from other players.  Approval of a name for online
## play is decided by the service (service/src/names.js), never here.

const MIN_LEN := 3
const MAX_LEN := 16
const FALLBACK := "Player"


static func normalize(raw: String) -> String:
	var s := raw.strip_edges()
	var out := ""
	var space := false
	for ch in s:
		if ch == " " or ch == "\t" or ch == "\n":
			if not space:
				out += " "
			space = true
		else:
			out += ch
			space = false
	return out


## "" when the shape is fine, else a short message.
static func shape_error(name: String) -> String:
	if name.length() < MIN_LEN or name.length() > MAX_LEN:
		return "Names are %d-%d characters." % [MIN_LEN, MAX_LEN]
	var letters := 0
	var digits := 0
	for i in name.length():
		var c := name.unicode_at(i)
		var is_letter := (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
		var is_digit := c >= 48 and c <= 57
		if not (is_letter or is_digit or c == 32 or c == 95):
			return "Use letters, numbers, spaces and underscores."
		if is_letter:
			letters += 1
		if is_digit:
			digits += 1
	if name.contains("  ") or name != name.strip_edges():
		return "Use single spaces between words."
	if letters < 2:
		return "Include at least two letters."
	if digits >= 6:
		return "Names can't include long numbers."
	return ""


## A name received from the network, made safe to show: valid names pass
## through unchanged (they are drawn as plain text, never markup); anything
## else becomes "Player".  A "#1234" discriminator suffix is kept.
static func safe_display(raw: String) -> String:
	var name := raw
	var disc := ""
	var hidx := raw.rfind("#")
	if hidx > 0 and raw.length() - hidx == 5 and raw.substr(hidx + 1).is_valid_int():
		name = raw.substr(0, hidx)
		disc = raw.substr(hidx)
	if shape_error(name) != "":
		return FALLBACK
	return name + disc
