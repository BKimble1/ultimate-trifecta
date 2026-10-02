class_name NameRules
extends RefCounted
## Display names: the full moderation policy, mirrored from the service
## (service/src/names.js, the only authority that *approves* a name for
## online play).  V5 checked only the name's shape here; V6 runs the whole
## policy on the device, for three jobs:
##   - instant feedback (with friendly reasons and safe suggestions) while a
##     player types a name;
##   - revalidating a name saved by an older version;
##   - receiver-side defence: every name that arrives from another device
##     (roster, round start, results, series, chat) is shown only if it
##     passes, otherwise a safe generated name takes its place.
##
## Pipeline (same order as the service):
##   normalise   full-width letters folded, invisible format characters
##               (zero-width, joiners, direction marks, soft hyphen)
##               removed, whitespace runs to one space, trimmed
##   shape       3-16 letters, digits, single spaces or underscores; 2+
##               letters; no long numbers.  Names are ASCII by policy:
##               look-alike letters from other scripts can spell anything
##   words       whole-word lists (split on spaces, underscores, digit runs
##               and lower->Upper changes, and read as leetspeak)
##   substrings  the skeleton (lower case, leet digits read as letters,
##               separators removed, repeated letters collapsed) against the
##               slur / sexual / profanity / threat / impersonation /
##               contact lists, after harmless ALLOW words are cut out
##   reserved    "Player", "Guest", "Night Watch", "Blocked player", ...
## Lists: ModerationTerms (generated with the service's lists).
## Curated names ("Sleepy Otter 42") are the safe names used for shared play
## when the moderation service isn't available (see Save.party_name()).

const MIN_LEN := 3
const MAX_LEN := 16
const FALLBACK := "Player"

const LEET := {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "6": "g", "7": "t", "8": "b", "9": "g", "2": "z"}
const LEET_ALT := {"1": "l", "0": "o", "6": "b"}
const BUILTIN_RESERVED := ["player", "runner", "night watch", "nightwatch", "anonymous", "unknown", "guest", "host",
	"you", "me", "everyone", "nobody", "null", "undefined", "test", "claude", "blocked player"]
const MESSAGES := {
	"length": "Names are 3-16 characters.",
	"characters": "Use letters, numbers, spaces and underscores.",
	"spacing": "Use single spaces between words (no spaces at the start or end).",
	"letters": "Include at least two letters.",
	"slur": "That name isn't allowed. Please pick something kind.",
	"sexual": "That name isn't allowed. Please keep it friendly for everyone.",
	"profanity": "That name isn't allowed. Please keep it friendly for everyone.",
	"threat": "That name isn't allowed. Please keep it friendly for everyone.",
	"impersonation": "Names can't look like staff, the game or a bot.",
	"contact": "Names can't include links, handles or contact details.",
	"reserved": "That name is reserved. Try another.",
	"digits": "Names can't include long numbers (like phone numbers).",
}
## Suggestion words (the service's lists, so suggestions match it).
const ADJ := ["Sleepy", "Cozy", "Fuzzy", "Snug", "Dreamy", "Comfy", "Drowsy", "Moonlit", "Splashy", "Bouncy", "Quiet", "Sneaky",
	"Speedy", "Wobbly", "Snoozy", "Twinkly"]
const ANIMALS := ["Otter", "Panda", "Koala", "Gecko", "Puffin", "Newt", "Walrus", "Moose", "Frog", "Duck", "Badger", "Fox",
	"Owl", "Lamb", "Seal", "Hedgehog"]
## Older versions generated names from these too (Save.generated_name): they
## are curated as well.
const ADJ_V1 := ["Soggy", "Zippy"]
const ANIMALS_V1 := ["Llama"]

## Invisible format characters removed before anything else (code points).
const INVISIBLE := [0x00AD, 0x180E, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
	0x2060, 0x2061, 0x2062, 0x2063, 0x2064, 0x2066, 0x2067, 0x2068, 0x2069, 0xFEFF]

static var _lists: Array = []          # [[category, {col, raw, tok}]] in the service's order
static var _allow: Array = []          # [{raw, col}] longest first
static var _re: Dictionary = {}
static var _cache: Dictionary = {}     # display check results (bounded)


static func _dec(arr: Array) -> Array:
	var out: Array = []
	for s in arr:
		out.append(Marshalls.base64_to_utf8(String(s)))
	return out


static func _list(words: Array, tok: Array) -> Dictionary:
	var col: Array = []
	var raw: Array = []
	for w in words:
		var c := collapse(String(w))
		if (c == String(w) and c.length() >= 3) or (c != String(w) and c.length() >= 4):
			col.append(c)
		if String(w).length() >= 3:
			raw.append(String(w))
	return {"col": col, "raw": raw, "tok": tok}


static func _ensure() -> void:
	if not _lists.is_empty():
		return
	_lists = [
		["slur", _list(_dec(ModerationTerms.SLURS), _dec(ModerationTerms.SLUR_TOKENS))],
		["sexual", _list(_dec(ModerationTerms.SEXUAL), _dec(ModerationTerms.SEXUAL_TOKENS))],
		["profanity", _list(_dec(ModerationTerms.PROFANITY), [])],
		["threat", _list(ModerationTerms.THREATS, ModerationTerms.THREAT_TOKENS)],
		["impersonation", _list(ModerationTerms.STAFF, ModerationTerms.STAFF_TOKENS)],
		["contact", _list(ModerationTerms.CONTACT, ModerationTerms.CONTACT_TOKENS)],
	]
	var al: Array = ModerationTerms.ALLOW.duplicate()
	al.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for w in al:
		_allow.append({"raw": String(w), "col": collapse(String(w))})
	_re = {
		"lowup": RegEx.create_from_string("([a-z])([A-Z])"),
		"alnum": RegEx.create_from_string("([A-Za-z])([0-9])"),
		"numal": RegEx.create_from_string("([0-9])([A-Za-z])"),
		"sep": RegEx.create_from_string("[\\s_]+"),
	}


## The abuse lists (category -> {col, raw, tok}) for ChatRules.
static func lists() -> Array:
	_ensure()
	return _lists


# ---------------------------------------------------------------------------
# Normalising and skeletons
# ---------------------------------------------------------------------------
static func normalize(raw: String) -> String:
	var s := ""
	for i in raw.length():
		var c := raw.unicode_at(i)
		if INVISIBLE.has(c):
			continue
		if c >= 0xFF01 and c <= 0xFF5E:
			c -= 0xFEE0          # full-width ASCII (NFKC folds these on the service)
		elif c == 0x3000 or c == 0x00A0 or (c >= 0x2000 and c <= 0x200A) or c == 0x202F or c == 0x205F:
			c = 32
		elif c == 9 or c == 10 or c == 11 or c == 12 or c == 13 or c == 0x85 or c == 0x2028 or c == 0x2029:
			c = 32
		s += String.chr(c)
	s = s.strip_edges()
	var out := ""
	var space := false
	for ch in s:
		if ch == " ":
			if not space:
				out += " "
			space = true
		else:
			out += ch
			space = false
	return out


static func collapse(s: String) -> String:
	var out := ""
	var prev := ""
	for ch in s:
		if ch != prev:
			out += ch
		prev = ch
	return out


## Stretched letters squeezed to two ("cooooon" -> "coon").
static func squeeze2(s: String) -> String:
	var out := ""
	var prev := ""
	var run := 0
	for ch in s:
		run = run + 1 if ch == prev else 1
		if run <= 2:
			out += ch
		prev = ch
	return out


static func _map(s: String, alt: bool) -> String:
	var out := ""
	for ch in s:
		if alt and LEET_ALT.has(ch):
			out += String(LEET_ALT[ch])
		else:
			out += String(LEET.get(ch, ch))
	return out


## Spelling variants: leet digits read as letters (two readings for 1/0/6),
## separators removed; each as spelled and with "rn"/"vv" read as m/w.
static func variants(name: String) -> Array:
	var base := name.to_lower().replace(" ", "").replace("_", "")
	var out: Array = []
	var seen := {}
	for alt in [false, true]:
		var raw := _map(base, alt)
		for r in [raw, raw.replace("rn", "m").replace("vv", "w")]:
			if not seen.has(r):
				seen[r] = true
				out.append({"raw": r, "col": collapse(r)})
	return out


static func skeletons(name: String) -> Array:
	var out: Array = []
	for v in variants(name):
		if not out.has(v["col"]):
			out.append(v["col"])
	return out


static func _has_letter(s: String) -> bool:
	for ch in s:
		var c := ch.unicode_at(0)
		if (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
			return true
	return false


## Whole words, two ways (as the service): split on spaces/underscores,
## digit runs and lower->Upper changes; and split on spaces/underscores
## with digits read as letters (a number alone stays a number: "Otter 99"
## is not "gg").
static func tokens(name: String) -> Array:
	_ensure()
	var camel := (_re["lowup"] as RegEx).sub(name, "$1 $2", true)
	camel = (_re["alnum"] as RegEx).sub(camel, "$1 $2", true)
	camel = (_re["numal"] as RegEx).sub(camel, "$1 $2", true)
	var out: Array = []
	for t in _split_sep(camel):
		var low := String(t).to_lower()
		if _has_letter(low) and not out.has(low):
			out.append(low)
	for t in _split_sep((_re["lowup"] as RegEx).sub(name, "$1 $2", true)):
		if not _has_letter(String(t)):
			continue
		for alt in [false, true]:
			var m := _map(String(t).to_lower(), alt)
			if m != "" and not out.has(m):
				out.append(m)
	return out


static func _split_sep(s: String) -> Array:
	var out: Array = []
	for part in (_re["sep"] as RegEx).sub(s, " ", true).split(" ", false):
		out.append(part)
	return out


## The first category whose substring terms appear in one spelling (as
## spelled, squeezed and collapsed), after harmless words spelled out in it
## are cut out.  `use` limits the categories (chat: abuse lists only).
static func substring_category(raw_variant: String, use: Array = []) -> String:
	_ensure()
	var s := collapse(raw_variant)
	var r := raw_variant
	for w in _allow:
		if raw_variant.contains(String(w["raw"])):
			s = s.replace(String(w["col"]), "|")
			r = r.replace(String(w["raw"]), "|")
	var r2 := squeeze2(r)
	for pair in _lists:
		var cat: String = pair[0]
		if not use.is_empty() and not use.has(cat):
			continue
		var l: Dictionary = pair[1]
		for term in l["col"]:
			if s.contains(String(term)):
				return cat
		for term in l["raw"]:
			if r.contains(String(term)) or r2.contains(String(term)):
				return cat
	return ""


# ---------------------------------------------------------------------------
# Decisions
# ---------------------------------------------------------------------------
## Character rules (shared with the service): "" or the reason key.
static func shape_key(name: String) -> String:
	if name.length() < MIN_LEN or name.length() > MAX_LEN:
		return "length"
	var letters := 0
	var digits := 0
	for i in name.length():
		var c := name.unicode_at(i)
		var is_letter := (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
		var is_digit := c >= 48 and c <= 57
		if not (is_letter or is_digit or c == 32 or c == 95):
			return "characters"
		if is_letter:
			letters += 1
		if is_digit:
			digits += 1
	if name.contains("  ") or name != name.strip_edges():
		return "spacing"
	if letters < 2:
		return "letters"
	if digits >= 6:
		return "digits"
	return ""


## "" when the shape is fine, else a short message (V5 API, kept).
static func shape_error(name: String) -> String:
	var k := shape_key(name)
	return "" if k == "" else String(MESSAGES[k])


## The full decision: {ok, name} or {ok:false, reason, message, name}.
## reserved: extra reserved names (lower case); `check_reserved` false for
## display checks (a received "Player" fallback is fine to show).
static func moderate(raw: String, reserved: Array = [], check_reserved: bool = true) -> Dictionary:
	_ensure()
	var name := normalize(raw)
	var shape := shape_key(name)
	if shape != "":
		return {"ok": false, "reason": shape, "message": MESSAGES[shape], "name": name}
	var toks := tokens(name)
	for pair in _lists:
		var l: Dictionary = pair[1]
		for t in toks:
			if (l["tok"] as Array).has(t) or (l["tok"] as Array).has(collapse(t)):
				return {"ok": false, "reason": pair[0], "message": MESSAGES[pair[0]], "name": name}
	for v in variants(name):
		var cat := substring_category(String(v["raw"]))
		if cat != "":
			return {"ok": false, "reason": cat, "message": MESSAGES[cat], "name": name}
	if check_reserved:
		var norm := name.to_lower()
		var res: Array = BUILTIN_RESERVED.duplicate()
		res.append_array(reserved)
		var sk := skeletons(name)
		for r in res:
			if norm == String(r) or sk.has(collapse(String(r).replace(" ", "").replace("_", ""))):
				return {"ok": false, "reason": "reserved", "message": MESSAGES["reserved"], "name": name}
	return {"ok": true, "name": name}


## True when a name received from elsewhere may be shown as it is.
static func display_ok(name: String) -> bool:
	if _cache.has(name):
		return bool(_cache[name])
	var ok := normalize(name) == name and bool(moderate(name, [], false)["ok"])
	if _cache.size() > 512:
		_cache.clear()
	_cache[name] = ok
	return ok


## A name received from the network, made safe to show: a name that passes
## the policy is shown as it is (always as plain text, never markup);
## anything else becomes a safe generated name (stable for `seed`, e.g. the
## player's id) or "Player".  A "#1234" discriminator suffix is kept.
static func safe_display(raw: String, seed: String = "") -> String:
	var name := raw
	var disc := ""
	var hidx := raw.rfind("#")
	if hidx > 0 and raw.length() - hidx == 5 and raw.substr(hidx + 1).is_valid_int():
		name = raw.substr(0, hidx)
		disc = raw.substr(hidx)
	if not display_ok(name):
		return generated(seed) if seed != "" else FALLBACK
	return name + disc


# ---------------------------------------------------------------------------
# Curated names
# ---------------------------------------------------------------------------
static func _fnv(text: String) -> int:
	var h := 2166136261
	for i in text.length():
		h = ((h ^ (text.unicode_at(i) & 0xFFFF)) * 16777619) & 0xFFFFFFFF
	return h


## Friendly, valid, different names (the service's algorithm and words).
static func suggestions(seed_text: String = "", n: int = 3, reserved: Array = []) -> Array:
	var h := _fnv(seed_text)
	var out: Array = []
	var i := 0
	while out.size() < n and i < 64:
		h = ((h ^ (i + 7)) * 16777619) & 0xFFFFFFFF
		var s := "%s %s %d" % [ADJ[h % ADJ.size()], ANIMALS[(h >> 8) % ANIMALS.size()], 10 + ((h >> 16) % 90)]
		if s.length() <= MAX_LEN and bool(moderate(s, reserved)["ok"]) and not out.has(s):
			out.append(s)
		i += 1
	return out


## A stable curated name for `seed` (a player's id): "Snug Puffin 37".
static func generated(seed: String) -> String:
	var s := suggestions("party:" + seed, 1)
	return String(s[0]) if not s.is_empty() else "Sleepy Otter"


## Is this one of the game's curated names ("Adjective Animal" with an
## optional 10-99)?  Curated names are what shared play shows when names
## can't be checked by the moderation service.
static func is_curated(name: String) -> bool:
	if normalize(name) != name:
		return false
	var parts := name.split(" ")
	if parts.size() == 3:
		if not parts[2].is_valid_int() or parts[2].length() != 2 or int(parts[2]) < 10:
			return false
	elif parts.size() != 2:
		return false
	var adj := ADJ + ADJ_V1
	var ani := ANIMALS + ANIMALS_V1
	# (a pair can still spell something across the words: "sneaKYSeal")
	return adj.has(parts[0]) and ani.has(parts[1]) and name.length() <= MAX_LEN and display_ok(name)
