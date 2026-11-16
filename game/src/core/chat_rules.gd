class_name ChatRules
extends RefCounted
## Typed party chat: the message policy, mirrored from the service
## (service/src/chat_rules.js).  The service approves a typed message by
## signing it (ChatToken); the game runs these rules for instant feedback
## before sending and again on every received message as a receiver-side
## defence, so rejected text is never drawn, not even for a frame.
## Quick Chat phrases (QuickChat) are game-authored and travel as ids.
##
## Pipeline (first failing step decides):
##   normalise   full-width letters folded, invisible format characters
##               removed, tabs/newlines to spaces, space runs collapsed, trimmed
##   empty, length (<= MAX_LEN characters)
##   characters  printable ASCII, Latin-1 / Latin Extended-A letters, curly
##               quotes and the ellipsis (no emoji, no other scripts)
##   markup      < > [ ] { } \ `
##   spam        a character 7+ times in a row, a word 5+ times in a row
##   contact     links, e-mail, @handles, phone numbers, contact apps,
##               "add me"-style phrases
##   words       each word, each chunk with its separators removed, and runs
##               of single letters, against the shared abuse lists (leet,
##               stretched letters, harmless words cut out); threat phrases
##               over 2-3 word windows

const MAX_LEN := 100
const LEET := {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "6": "g", "7": "t", "8": "b", "9": "g", "2": "z", "@": "a", "$": "s", "!": "i"}
const LEET_ALT := {"1": "l", "0": "o", "6": "b", "!": "l"}
const CATS := ["slur", "sexual", "profanity", "threat"]
const CONTACT_WORDS := ["discord", "snapchat", "instagram", "tiktok", "telegram", "whatsapp", "twitter", "youtube",
	"twitch", "paypal", "venmo", "cashapp", "gmail", "yahoo", "hotmail", "icloud", "onlyfans"]
const CONTACT_TOKENS := ["dm", "dms", "snap", "insta", "ig", "fb", "kik", "email", "tel", "ttv", "yt", "whatsapp", "wa"]
const CONTACT_PHRASES := ["addme", "dmme", "textme", "callme", "followme", "messageme", "pmme", "snapme", "mynumber", "myinsta", "mysnap"]
const TLDS := "com|net|org|gg|io|me|co|tv|ly|app|xyz|ru|uk|us|de|fr|info|biz|link|site|online|club|live|to|cc|fun|gay|sex|xxx"
const MESSAGES := {
	"empty": "Type a message first.",
	"length": "Messages are up to 100 characters.",
	"characters": "Use plain letters, numbers and punctuation.",
	"markup": "Use plain letters, numbers and punctuation.",
	"spam": "That looks like spam. Try a shorter message.",
	"contact": "Chat can't include links, handles or contact details.",
	"slur": "That message isn't allowed. Please keep chat kind.",
	"sexual": "That message isn't allowed. Please keep chat friendly for everyone.",
	"profanity": "That message isn't allowed. Please keep chat friendly for everyone.",
	"threat": "That message isn't allowed. Please keep chat friendly for everyone.",
}
const FOLD_GROUPS := [
	["ÀÁÂÃÄÅàáâãäåĀāĂăĄą", "a"], ["ÇçĆćĈĉĊċČč", "c"], ["ĎďĐđÐ", "d"], ["ÈÉÊËèéêëĒēĔĕĖėĘęĚě", "e"],
	["ĜĝĞğĠġĢģ", "g"], ["ĤĥĦħ", "h"], ["ÌÍÎÏìíîïĨĩĪīĬĭĮįİı", "i"], ["Ĵĵ", "j"], ["Ķķĸ", "k"],
	["ĹĺĻļĽľĿŀŁł", "l"], ["ÑñŃńŅņŇňŉŊŋ", "n"], ["ÒÓÔÕÖØòóôõöøŌōŎŏŐő", "o"], ["ŔŕŖŗŘř", "r"],
	["ŚśŜŝŞşŠšſß", "s"], ["ŢţŤťŦŧ", "t"], ["ÙÚÛÜùúûüŨũŪūŬŭŮůŰűŲų", "u"], ["Ŵŵ", "w"], ["ÝýÿŶŷŸ", "y"],
	["ŹźŻżŽž", "z"], ["Ææ", "ae"], ["Œœ", "oe"], ["Þþ", "th"], ["Ĳĳ", "ij"],
]

static var _fold: Dictionary = {}
static var _re: Dictionary = {}
static var _tok: Dictionary = {}
static var _exact: Dictionary = {}


static func _ensure() -> void:
	if not _re.is_empty():
		return
	for g in FOLD_GROUPS:
		for ch in String(g[0]):
			_fold[ch] = String(g[1])
	_re = {
		"links": [
			RegEx.create_from_string("https?\\s*:\\s*//"),
			RegEx.create_from_string("\\bwww\\s*\\."),
			RegEx.create_from_string("[a-z0-9-]{2,}\\s*(\\.|\\(dot\\)|\\[dot\\]|\\sdot\\s)\\s*(" + TLDS + ")\\b"),
			RegEx.create_from_string("[a-z0-9._%+-]+\\s*@\\s*[a-z0-9-]+\\s*\\.\\s*[a-z]{2,}"),
			RegEx.create_from_string("(^|\\s)@[a-z0-9_.]{3,}"),
		],
		"phone": RegEx.create_from_string("\\d(?:[\\s().+-]*\\d){6,}"),
		"markup": RegEx.create_from_string("[<>\\[\\]{}\\\\`]"),
		"repeat": RegEx.create_from_string("(.)\\1{6,}"),
		"nonalnum": RegEx.create_from_string("[^a-z0-9]+"),
		"nonword": RegEx.create_from_string("[^a-z0-9@$!]+"),
		"nonword1": RegEx.create_from_string("[^a-z0-9@$!]"),
		"bang_end": RegEx.create_from_string("!+$"),
		"bang_mid": RegEx.create_from_string("!+(?=[^a-z0-9@$!])"),
		"letter": RegEx.create_from_string("[a-z]"),
	}
	_tok = {
		"slur": NameRules._dec(ModerationTerms.SLUR_TOKENS),
		"sexual": NameRules._dec(ModerationTerms.SEXUAL_TOKENS),
		"profanity": [],
		"threat": ModerationTerms.THREAT_TOKENS,
	}
	_exact = {
		"slur": NameRules._dec(ModerationTerms.SLURS),
		"sexual": NameRules._dec(ModerationTerms.SEXUAL),
		"profanity": NameRules._dec(ModerationTerms.PROFANITY),
		"threat": ModerationTerms.THREATS,
	}


static func fold(s: String) -> String:
	_ensure()
	var out := ""
	for ch in s:
		out += String(_fold.get(ch, ch))
	return out


static func normalize(raw: String) -> String:
	var s := ""
	for i in raw.length():
		var c := raw.unicode_at(i)
		if NameRules.INVISIBLE.has(c):
			continue
		if c >= 0xFF01 and c <= 0xFF5E:
			c -= 0xFEE0
		elif c == 0x3000 or c == 0x00A0 or (c >= 0x2000 and c <= 0x200A) or c == 0x202F or c == 0x205F:
			c = 32
		elif c == 9 or c == 10 or c == 11 or c == 12 or c == 13 or c == 0x85 or c == 0x2028 or c == 0x2029:
			c = 32
		s += String.chr(c)
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
	return out.strip_edges()


static func _allowed_char(cp: int) -> bool:
	if cp >= 0x20 and cp <= 0x7E:
		return true
	if cp >= 0xC0 and cp <= 0x17F and cp != 0xD7 and cp != 0xF7:
		return true
	return cp in [0x2018, 0x2019, 0x201C, 0x201D, 0x2026]


static func _has_letter(s: String) -> bool:
	return (_re["letter"] as RegEx).search(s) != null


static func word_variants(w: String) -> Array:
	var out: Array = []
	for alt in [false, true]:
		var raw := ""
		for ch in w:
			if alt and LEET_ALT.has(ch):
				raw += String(LEET_ALT[ch])
			else:
				raw += String(LEET.get(ch, ch))
		for r in [raw, raw.replace("rn", "m").replace("vv", "w")]:
			if not out.has(r):
				out.append(r)
	return out


## The category of one word, or "".
static func word_category(word: String) -> String:
	_ensure()
	if word == "":
		return ""
	var vs: Array = word_variants(word) if _has_letter(word) else [word]
	for v in vs:
		for cat in CATS:
			for f in [String(v), NameRules.collapse(String(v)), NameRules.squeeze2(String(v))]:
				if (_tok[cat] as Array).has(f) or (_exact[cat] as Array).has(f):
					return cat
	for v in vs:
		var c := NameRules.substring_category(String(v), CATS)
		if c != "":
			return c
	return ""


static func _contact_word(word: String) -> bool:
	if CONTACT_TOKENS.has(word):
		return true
	var vs: Array = word_variants(word) if _has_letter(word) else [word]
	for v in vs:
		for c in CONTACT_WORDS:
			if String(v).contains(c) or NameRules.collapse(String(v)).contains(NameRules.collapse(c)):
				return true
	return false


## {ok, text} or {ok:false, reason, message}.
static func check(raw: String) -> Dictionary:
	_ensure()
	for i in raw.length():
		var cp := raw.unicode_at(i)
		if (cp < 0x20 and not (cp == 9 or cp == 10 or cp == 13)) or (cp >= 0x7F and cp <= 0x9F):
			return _no("characters")
	var text := normalize(raw)
	if text.is_empty():
		return _no("empty")
	if text.length() > MAX_LEN:
		return _no("length")
	for i in text.length():
		if not _allowed_char(text.unicode_at(i)):
			return _no("characters")
	if (_re["markup"] as RegEx).search(text) != null:
		return _no("markup")
	if (_re["repeat"] as RegEx).search(text) != null:
		return _no("spam")
	var lower := fold(text.to_lower())
	var plain: Array = []
	for w in (_re["nonalnum"] as RegEx).sub(lower, " ", true).split(" ", false):
		plain.append(w)
	var run := 1
	for i in range(plain.size() - 1):
		run = run + 1 if plain[i] == plain[i + 1] else 1
		if run > 4:
			return _no("spam")
	for re in _re["links"]:
		if (re as RegEx).search(lower) != null:
			return _no("contact")
	if (_re["phone"] as RegEx).search(lower) != null:
		return _no("contact")
	var words: Array = []
	for ch in lower.split(" ", false):
		var c2 := (_re["bang_end"] as RegEx).sub(ch, "", true)
		c2 = (_re["bang_mid"] as RegEx).sub(c2, "", true)
		var joined := (_re["nonword1"] as RegEx).sub(c2, "", true)
		var parts: Array = []
		for p in (_re["nonword"] as RegEx).sub(c2, " ", true).split(" ", false):
			parts.append(p)
		words.append_array(parts)
		var uniq: Array = [joined]
		for p in parts:
			if not uniq.has(p):
				uniq.append(p)
		for w in uniq:
			if _contact_word(String(w)):
				return _no("contact")
			var cat := word_category(String(w))
			if cat != "":
				return _no(cat)
	var letters := ""
	for w in words + [""]:
		if String(w).length() == 1:
			letters += String(w)
			continue
		if letters.length() >= 3:
			var cat2 := word_category(letters)
			if cat2 != "":
				return _no(cat2)
			if _contact_word(letters):
				return _no("contact")
		letters = ""
	for i in words.size():
		for n in [2, 3]:
			if i + n > words.size():
				continue
			var j := "".join(PackedStringArray(words.slice(i, i + n)))
			var jv: Array = []
			for v in word_variants(j):
				jv.append(NameRules.collapse(String(v)))
			for t in ModerationTerms.THREATS:
				if j == String(t) or jv.has(NameRules.collapse(String(t))):
					return _no("threat")
			for t in CONTACT_PHRASES:
				if j == String(t) or jv.has(NameRules.collapse(String(t))):
					return _no("contact")
	return {"ok": true, "text": text}


# ---------------------------------------------------------------------------
# 2.2: bleeping (device-moderated typed chat)
# ---------------------------------------------------------------------------
## The grawlix a bleeped word becomes (no letters, no leet characters, so it
## can never spell anything and never trips the spam rule).
const BLEEP := "#%&*"
## Categories that are bleeped word by word; anything else that fails the
## policy (threats, contact details, links, spam, markup, odd characters)
## blocks the whole message.
const BLEEPABLE := ["profanity", "sexual", "slur"]


## A bad word (in any of the policy's disguises) turned into grawlix of
## the same length; leading/trailing punctuation kept.
static func _grawlix(chunk: String) -> String:
	var a := 0
	var b := chunk.length()
	while a < b and not chunk[a].to_lower().is_valid_identifier() and not chunk[a].is_valid_int():
		a += 1
	while b > a and not chunk[b - 1].to_lower().is_valid_identifier() and not chunk[b - 1].is_valid_int():
		b -= 1
	var core := ""
	for i in b - a:
		core += BLEEP[i % BLEEP.length()]
	return chunk.substr(0, a) + core + chunk.substr(b)


## The category a whitespace-separated chunk falls in ("" if fine): the
## chunk joined, and each of its parts (as check() reads them).
static func _chunk_category(chunk: String) -> String:
	var lower := fold(chunk.to_lower())
	var c2 := (_re["bang_end"] as RegEx).sub(lower, "", true)
	c2 = (_re["bang_mid"] as RegEx).sub(c2, "", true)
	var cands: Array = [(_re["nonword1"] as RegEx).sub(c2, "", true)]
	for p in (_re["nonword"] as RegEx).sub(c2, " ", true).split(" ", false):
		if not cands.has(p):
			cands.append(p)
	for w in cands:
		var cat := word_category(String(w))
		if cat != "":
			return cat
	return ""


## Typed chat without the service (2.2): {ok, text, bleeped} with every bad
## word replaced by grawlix, or {ok:false, reason, message} when the message
## can't be sent at all (threats, links, handles, phone numbers, spam,
## markup, characters outside the allowed set, empty or too long).  The
## result always passes check() itself, so a receiver can verify it again:
## bleep(bleep(x).text).text == bleep(x).text.
static func bleep(raw: String) -> Dictionary:
	_ensure()
	var first := check(raw)
	if bool(first["ok"]):
		return {"ok": true, "text": String(first["text"]), "bleeped": 0}
	if not BLEEPABLE.has(String(first["reason"])):
		return first
	var text := normalize(raw)
	var chunks: PackedStringArray = text.split(" ", false)
	var n := 0
	for i in chunks.size():
		var cat := _chunk_category(chunks[i])
		if cat == "threat":
			return _no("threat")
		if BLEEPABLE.has(cat):
			chunks[i] = _grawlix(chunks[i])
			n += 1
	# words spelled out a letter at a time ("f u c k"), or split in two
	for size in [2, 3, 4, 5, 6]:
		for i in range(chunks.size() - size + 1):
			var joined := ""
			for k in size:
				joined += chunks[i + k]
			if BLEEP.contains(joined.substr(0, 1)):
				continue
			var cat3 := _chunk_category(joined)
			if cat3 == "threat":
				return _no("threat")
			if BLEEPABLE.has(cat3):
				for k in size:
					chunks[i + k] = _grawlix(chunks[i + k])
				n += 1
	var out := " ".join(chunks)
	var again := check(out)
	if not bool(again["ok"]):
		return again   # anything still caught is never shown
	return {"ok": true, "text": String(again["text"]), "bleeped": n}


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "message": MESSAGES[reason]}


## Receiver-side: true when `text` may be drawn as it is (it must already be
## in normalised form and pass every rule).
static func display_ok(text: String) -> bool:
	var r := check(text)
	return bool(r["ok"]) and String(r["text"]) == text
