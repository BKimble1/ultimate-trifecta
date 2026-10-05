class_name Cosmetics
extends RefCounted
## Runner appearance, schema 2 ("Create Your Runner").  Appearance only: no
## item changes speed, reach, hitboxes or anything else in the simulation.
##
## Stable identity.  Every catalog entry has a string key (used in saves and
## in code) and an explicit numeric ID (used on the wire).  IDs are never
## renumbered or reused; a new item gets a new ID.  Nothing depends on
## dictionary order (the V1/V2 5-byte format did, which is why it is retired).
##
## Saved form (profile "appearance"):
##   {"schema": 2, "outfit": "pj", "pattern": "stripes", "color": "sky", ...}
## Wire form (encode/decode): [WIRE_MAGIC, SCHEMA, n, (field_id, value_id) * n]
## Unknown field IDs are skipped and unknown value IDs fall back to the
## field's default, so a newer client's extra fields never break an older
## decoder within the same protocol version.

const SCHEMA := 2
const WIRE_MAGIC := 0xA7   # > any V1/V2 legacy first byte (those were 0..5)

## field key -> wire field ID (stable)
const FIELDS := {
	"outfit": 1, "pattern": 2, "color": 3, "trim": 4, "skin": 5, "face": 6, "brows": 7, "marks": 8,
	"hair": 9, "hair_color": 10, "hat": 11, "shoes": 12, "emote": 13,
}

## field -> {key: {id, name, cost, ...}}.  cost 0 = owned by everyone.
const CATALOG := {
	"outfit": {
		"pj": {"id": 1, "name": "Pajamas", "cost": 0},
		"swim": {"id": 2, "name": "Swim Trunks", "cost": 0},
		"robe": {"id": 3, "name": "Fluffy Robe", "cost": 90},
		"duck": {"id": 4, "name": "Duck Mascot", "cost": 160},
		"frog": {"id": 5, "name": "Frog Onesie", "cost": 200},
		# V6 Shop outfits.  "includes" lists exactly what the outfit draws.
		"moonlight_runner": {"id": 6, "name": "Moonlight Runner", "cost": 900, "includes": [
			"Midnight track jacket with a stand-up collar and a silver zip",
			"Track trousers with ribbed ankle cuffs",
			"Reflective silver piping on the sleeves and legs",
			"Gold crescent-moon emblem on the chest"]},
		"starry_sleeper": {"id": 7, "name": "Starry Sleeper", "cost": 750, "includes": [
			"Indigo star-print pajama top and trousers with cream piping",
			"Lavender sleep mask worn pushed up on the forehead (hidden under a nightcap, swim cap, beanie or headband)"]},
		"varsity_sprinter": {"id": 8, "name": "Varsity Sprinter", "cost": 800, "includes": [
			"Varsity jacket in your colour with ivory sleeves and striped rib trim",
			"Chenille T letter on the chest and a number 3 on the back",
			"Track shorts with side stripes, and striped crew socks"]},
		"raincoat_explorer": {"id": 9, "name": "Raincoat Explorer", "cost": 650, "includes": [
			"Glossy yellow raincoat with wooden toggles, flap pockets and a folded hood",
			"Teal rain boots (worn instead of your shoes with this outfit)"]},
		"campus_courier": {"id": 10, "name": "Campus Courier", "cost": 550, "includes": [
			"Short-sleeve shirt in your colour under a teal utility vest",
			"Messenger bag with a cross-body strap",
			"Cargo shorts and crew socks",
			"Courier cap (shown when no other hat is worn)"]},
		"lantern_scout": {"id": 11, "name": "Lantern Scout", "cost": 700, "includes": [
			"Scout shirt and green vest with five merit badges",
			"Neckerchief with a woggle",
			"Belt with a small glowing lantern (decoration only: it lights nothing)",
			"Shorts and knee socks"]},
		# V6 Season 1 · After Hours rewards (the pass grants them)
		"after_hours_hoodie": {"id": 12, "name": "After Hours Hoodie", "cost": 600, "season": 1, "includes": [
			"Violet hoodie with a gold moon print, kangaroo pocket and folded hood",
			"Charcoal joggers"]},
		"night_owl": {"id": 13, "name": "Night Owl Onesie", "cost": 800, "season": 1, "includes": [
			"Owl onesie with a feathered belly, wing sleeves and tail feathers",
			"Owl hood with eyes, beak and ear tufts (replaces hat and hair while worn)"]},
		"glow_jogger": {"id": 14, "name": "Glow Jogger", "cost": 600, "season": 1, "includes": [
			"Running top and leggings with glowing stripes in your colour",
			"Running shorts and glowing wristbands"]},
		"library_cardigan": {"id": 15, "name": "Library Cardigan", "cost": 600, "season": 1, "includes": [
			"Oatmeal cable-knit cardigan with elbow patches and a pencil in the pocket",
			"Collared shirt and tie",
			"Corduroy trousers"]},
		# Pass 8 rotating Shop outfits (scheduled Shop offers sell them for
		# Coins; owning one is permanent).  Each draws its own footwear
		# (OUTFIT_OWN_SHOES); the cadet and pumpkin caps are headwear worn
		# with no hat (OUTFIT_HEADWEAR); Cloud Nine and Bedtime Bandit wear
		# their hoods up (HOOD_OUTFITS).  tools/character/outfits_p8.py.
		"midnight_mechanic": {"id": 16, "name": "Midnight Mechanic", "cost": 900, "includes": [
			"Cobalt work coverall with a zip front, collar and webbing belt",
			"Sleeves rolled to the forearm, and cream work gloves",
			"Stitched wrench and gear patches, a chest pocket, knee patches and a leg pocket",
			"Turned-up cuffs and tan lace-up work boots (worn instead of your shoes with this outfit)"]},
		"moonwalk_cadet": {"id": 17, "name": "Moonwalk Cadet", "cost": 1200, "includes": [
			"Soft quilted ivory space suit with a teal neck ring, belt and trim",
			"Chest control panel, mission patch and a small life-support pack",
			"Ivory gloves with teal gauntlets",
			"Compact space boots (worn instead of your shoes with this outfit)",
			"Padded cadet cap with ear pads and a clear visor lifted up off the face (shown when no other hat is worn)"]},
		"pumpkin_pajamas": {"id": 18, "name": "Pumpkin Pajamas", "cost": 800, "includes": [
			"Rust pumpkin-ribbed pajama top with a leaf collar, cream piping and a pocket",
			"Cream pinstripe pajama trousers cut at mid-shin",
			"Soft rust-and-cream striped socks (worn instead of your shoes with this outfit)",
			"Knitted pumpkin cap with a stem, leaf and vine (shown when no other hat is worn)"]},
		"arcade_sprinter": {"id": 19, "name": "Arcade Sprinter", "cost": 900, "includes": [
			"Cropped retro track jacket with cyan and magenta panels, white piping and a stand collar",
			"Pixel lightning bolts on the chest and back, and striped knit cuffs",
			"Navy track shorts and striped tube socks",
			"Rounded magenta-and-white high-tops (worn instead of your shoes with this outfit)"]},
		"cloud_nine": {"id": 20, "name": "Cloud Nine", "cost": 1000, "includes": [
			"Plush sky-blue hoodie with a cloud pocket, a cloud on the back and cream cuffs",
			"Hood worn up with a puffy cloud rim and cloud tufts (replaces hat and hair while worn)",
			"Plush joggers with cream cuffs",
			"Cushioned cloud slippers (worn instead of your shoes with this outfit)"]},
		"bedtime_bandit": {"id": 21, "name": "Bedtime Bandit", "cost": 1000, "includes": [
			"Charcoal raccoon sleep suit with a cream belly and a moon on the chest",
			"Raccoon hood with round ears and a mask band above the face (replaces hat and hair while worn)",
			"Ringed raccoon tail",
			"Footed paws with cream soles (worn instead of your shoes with this outfit)"]},
	},
	"pattern": {
		"plain": {"id": 1, "name": "Plain", "cost": 0, "per_m": 0.0},
		"stripes": {"id": 2, "name": "Stripes", "cost": 0, "per_m": 13.0},
		"pinstripes": {"id": 3, "name": "Pinstripes", "cost": 40, "per_m": 26.0},
		"bands": {"id": 4, "name": "Wide Bands", "cost": 40, "per_m": 7.0},
	},
	"color": {
		"sky": {"id": 1, "name": "Sky", "cost": 0, "rgb": Color(0.36, 0.55, 0.95)},
		"bubblegum": {"id": 2, "name": "Bubblegum", "cost": 0, "rgb": Color(0.95, 0.42, 0.55)},
		"lime": {"id": 3, "name": "Lime", "cost": 0, "rgb": Color(0.55, 0.85, 0.45)},
		"sunny": {"id": 4, "name": "Sunny", "cost": 0, "rgb": Color(0.98, 0.78, 0.30)},
		"grape": {"id": 5, "name": "Grape", "cost": 0, "rgb": Color(0.72, 0.50, 0.95)},
		"teal": {"id": 6, "name": "Teal", "cost": 0, "rgb": Color(0.30, 0.82, 0.82)},
		"tangerine": {"id": 7, "name": "Tangerine", "cost": 0, "rgb": Color(0.98, 0.58, 0.28)},
		"cloud": {"id": 8, "name": "Cloud", "cost": 0, "rgb": Color(0.92, 0.92, 0.95)},
		"navy": {"id": 9, "name": "Midnight", "cost": 30, "rgb": Color(0.22, 0.28, 0.58)},
		"mint": {"id": 10, "name": "Mint", "cost": 30, "rgb": Color(0.56, 0.92, 0.76)},
		"coral": {"id": 11, "name": "Coral", "cost": 30, "rgb": Color(0.98, 0.50, 0.44)},
		"plum": {"id": 12, "name": "Plum", "cost": 30, "rgb": Color(0.56, 0.30, 0.62)},
	},
	## "auto" derives the trim from the main colour (the V2 look)
	"trim": {
		"auto": {"id": 1, "name": "Matching", "cost": 0},
		"white": {"id": 2, "name": "White", "cost": 0, "rgb": Color(0.97, 0.96, 0.93)},
		"cream": {"id": 3, "name": "Cream", "cost": 0, "rgb": Color(1.0, 0.91, 0.74)},
		"navy": {"id": 4, "name": "Midnight", "cost": 20, "rgb": Color(0.22, 0.28, 0.58)},
		"pink": {"id": 5, "name": "Pink", "cost": 20, "rgb": Color(1.0, 0.68, 0.78)},
		"gold": {"id": 6, "name": "Gold", "cost": 20, "rgb": Color(1.0, 0.80, 0.36)},
	},
	"skin": {
		"tone1": {"id": 1, "name": "Tone 1", "cost": 0, "rgb": Color(1.0, 0.87, 0.77)},
		"tone2": {"id": 2, "name": "Tone 2", "cost": 0, "rgb": Color(0.98, 0.82, 0.68)},
		"tone3": {"id": 3, "name": "Tone 3", "cost": 0, "rgb": Color(0.96, 0.74, 0.62)},
		"tone4": {"id": 4, "name": "Tone 4", "cost": 0, "rgb": Color(0.87, 0.66, 0.50)},
		"tone5": {"id": 5, "name": "Tone 5", "cost": 0, "rgb": Color(0.79, 0.59, 0.43)},
		"tone6": {"id": 6, "name": "Tone 6", "cost": 0, "rgb": Color(0.66, 0.46, 0.32)},
		"tone7": {"id": 7, "name": "Tone 7", "cost": 0, "rgb": Color(0.45, 0.30, 0.22)},
		"tone8": {"id": 8, "name": "Tone 8", "cost": 0, "rgb": Color(0.33, 0.22, 0.16)},
	},
	## held face shape keys on the base mesh (expressions play on top)
	"face": {
		"classic": {"id": 1, "name": "Classic", "cost": 0, "keys": {}},
		"bright": {"id": 2, "name": "Bright", "cost": 0, "keys": {"face_bright": 1.0}},
		"sleepy": {"id": 3, "name": "Sleepy", "cost": 0, "keys": {"face_sleepy": 1.0}},
	},
	"brows": {
		"arched": {"id": 1, "name": "Arched", "cost": 0, "keys": {}},
		"flat": {"id": 2, "name": "Straight", "cost": 0, "keys": {"brow_flat": 1.0}},
		"raised": {"id": 3, "name": "Raised", "cost": 0, "keys": {"brow_up": 0.35}},
	},
	"marks": {
		"none": {"id": 1, "name": "None", "cost": 0, "parts": []},
		"freckles": {"id": 2, "name": "Freckles", "cost": 0, "parts": ["freckles"]},
	},
	"hair": {
		"tuft": {"id": 1, "name": "Tuft", "cost": 0, "parts": ["hair"]},
		"bob": {"id": 2, "name": "Bob", "cost": 0, "parts": ["hair_bob"]},
		"curly": {"id": 3, "name": "Curls", "cost": 0, "parts": ["hair_curly"]},
		"buns": {"id": 4, "name": "Space Buns", "cost": 0, "parts": ["hair_buns", "hair_buns_knots"]},
	},
	"hair_color": {
		"black": {"id": 1, "name": "Black", "cost": 0, "rgb": Color("151010")},
		"espresso": {"id": 2, "name": "Espresso", "cost": 0, "rgb": Color("1f1712")},
		"dark_brown": {"id": 3, "name": "Dark Brown", "cost": 0, "rgb": Color("2e1e15")},
		"brown": {"id": 4, "name": "Brown", "cost": 0, "rgb": Color("4a3222")},
		"auburn": {"id": 5, "name": "Auburn", "cost": 0, "rgb": Color("7a3420")},
		"ginger": {"id": 6, "name": "Ginger", "cost": 0, "rgb": Color("b8743f")},
		"blonde": {"id": 7, "name": "Blonde", "cost": 0, "rgb": Color("d9b26a")},
		"silver": {"id": 8, "name": "Silver", "cost": 0, "rgb": Color("d6d3cf")},
		"blue": {"id": 9, "name": "Blueberry", "cost": 40, "rgb": Color("4a7fd6")},
		"pink": {"id": 10, "name": "Candy", "cost": 40, "rgb": Color("e889b5")},
	},
	"hat": {
		"none": {"id": 1, "name": "No Hat", "cost": 0, "parts": []},
		"nightcap": {"id": 2, "name": "Nightcap", "cost": 0, "parts": ["hat_nightcap"]},
		"swimcap": {"id": 3, "name": "Swim Cap + Goggles", "cost": 0, "parts": ["hat_swimcap"]},
		"party": {"id": 4, "name": "Party Hat", "cost": 60, "parts": ["hat_party"]},
		"headphones": {"id": 5, "name": "Headphones", "cost": 110, "parts": ["hat_headphones"]},
		"crown": {"id": 6, "name": "Paper Crown", "cost": 240, "parts": ["hat_crown"]},
		# V6 Season 1 · After Hours
		"headlamp": {"id": 7, "name": "Headlamp", "cost": 300, "season": 1, "parts": ["hat_headlamp"]},
		"pompom_beanie": {"id": 8, "name": "Pom-Pom Beanie", "cost": 300, "season": 1, "parts": ["hat_beanie"]},
		"glow_headband": {"id": 9, "name": "Glow Headband", "cost": 250, "season": 1, "parts": ["hat_glowband"]},
		"owl_ears": {"id": 10, "name": "Owl Ears", "cost": 300, "season": 1, "parts": ["hat_owlears"]},
	},
	"shoes": {
		"slippers": {"id": 1, "name": "Bunny Slippers", "cost": 0, "parts": ["shoe_slippers"]},
		"sneakers": {"id": 2, "name": "High-Tops", "cost": 50, "parts": ["shoe_hightops"]},
		"flippers": {"id": 3, "name": "Flippers", "cost": 130, "parts": ["shoe_flippers"]},
		# V6 Season 1 · After Hours
		"glow_sneakers": {"id": 4, "name": "Glow Sneakers", "cost": 350, "season": 1, "parts": ["shoe_glow"]},
		"moon_boots": {"id": 5, "name": "Moon Boots", "cost": 400, "season": 1, "parts": ["shoe_moonboots"]},
	},
	## signature move: played when you ready up in the lobby and at results
	"emote": {
		"wave": {"id": 1, "name": "Wave", "cost": 0},
		"cheer": {"id": 2, "name": "Cheer", "cost": 0},
		"laugh": {"id": 3, "name": "Giggle", "cost": 0},
		"shrug": {"id": 4, "name": "Shrug", "cost": 0},
		"dance": {"id": 5, "name": "Wiggle Dance", "cost": 80},
		"point": {"id": 6, "name": "Point", "cost": 0},
		# V6 Season 1 · After Hours (wire value = TC.EMOTES index; ids follow it)
		"stargaze": {"id": 7, "name": "Stargaze", "cost": 250, "season": 1},
		"victory_lap": {"id": 8, "name": "Victory Lap", "cost": 250, "season": 1},
		"shush": {"id": 9, "name": "Shush", "cost": 200, "season": 1},
		"moon_shuffle": {"id": 10, "name": "Moon Shuffle", "cost": 300, "season": 1},
	},
}

## field order in the creator (and the order fields are written on the wire)
const ORDER := ["outfit", "pattern", "color", "trim", "skin", "face", "brows", "marks", "hair", "hair_color",
	"hat", "shoes", "emote"]

const DEFAULT := {
	"schema": SCHEMA, "outfit": "pj", "pattern": "stripes", "color": "sky", "trim": "auto", "skin": "tone2",
	"face": "classic", "brows": "arched", "marks": "none", "hair": "tuft", "hair_color": "brown",
	"hat": "nightcap", "shoes": "slippers", "emote": "wave",
}

const OUTFIT_PARTS := {"pj": ["pj"], "swim": ["swim", "body_skin"], "robe": ["robe", "body_skin"], "duck": ["duck"], "frog": ["frog"],
	"moonlight_runner": ["moonlight"], "starry_sleeper": ["starry"], "varsity_sprinter": ["varsity"],
	"raincoat_explorer": ["raincoat"], "campus_courier": ["courier"], "lantern_scout": ["scout"],
	"after_hours_hoodie": ["hoodie"], "night_owl": ["owl"], "glow_jogger": ["jogger"], "library_cardigan": ["cardigan"],
	"midnight_mechanic": ["mechanic"], "moonwalk_cadet": ["cadet"], "pumpkin_pajamas": ["pumpkin"], "arcade_sprinter": ["arcade"],
	"cloud_nine": ["cloud"], "bedtime_bandit": ["bandit"]}
## hoods replace hats and hair entirely
const HOOD_OUTFITS := ["duck", "frog", "night_owl", "cloud_nine", "bedtime_bandit"]
## V6: outfits whose own footwear replaces the chosen shoes (drawn in the outfit's part)
## (Pass 8: every rotating outfit: its trousers end over, or tuck into, that footwear)
const OUTFIT_OWN_SHOES := ["raincoat_explorer", "midnight_mechanic", "moonwalk_cadet", "pumpkin_pajamas", "arcade_sprinter",
	"cloud_nine", "bedtime_bandit"]
## V6: headwear that comes with an outfit (a separate part), and the hats it
## is worn with.  With any other hat the chosen hat wins and this is hidden.
const OUTFIT_HEADWEAR := {
	"starry_sleeper": {"parts": ["acc_sleepmask"], "with_hats": ["none", "party", "headphones", "crown", "owl_ears"]},
	"campus_courier": {"parts": ["acc_courier_cap"], "with_hats": ["none"]},
	"moonwalk_cadet": {"parts": ["acc_cadet_cap"], "with_hats": ["none"]},
	"pumpkin_pajamas": {"parts": ["acc_pumpkin_cap"], "with_hats": ["none"]},
}
## Headwear that is worn the way a hat is, for the hair rules below: the
## courier, cadet and pumpkin caps behave like a cap, the sleep mask like a headband.
const HEADWEAR_AS_HAT := {"acc_courier_cap": "@cap", "acc_sleepmask": "@mask", "acc_cadet_cap": "@cap", "acc_pumpkin_cap": "@cap"}
## hair/hat compatibility: which hair parts each hat hides
const HAT_HIDES_HAIR := {
	"nightcap": ["hair", "hair_bob", "hair_curly", "hair_buns", "hair_buns_knots"],
	"swimcap": ["hair", "hair_bob", "hair_curly", "hair_buns", "hair_buns_knots"],
	"headphones": ["hair_buns_knots"],
	"crown": ["hair_buns_knots"],
	"headlamp": ["hair_buns_knots"],
	"pompom_beanie": ["hair_buns_knots"],
	"glow_headband": ["hair_buns_knots"],
	"owl_ears": ["hair_buns_knots"],
	"@cap": ["hair_buns_knots"],
	"@mask": ["hair_buns_knots"],
}
## V5/V6: hair drawn as a variant under a hat, so nothing pokes through the
## band or shell: the curly crop with a smooth band on top (V5, `_hat`) or
## with curls only below a cap's edge (V6, `_low`), and the tuft without its
## forelock (V6, `hair_hat`).  hat (or headwear rule) -> {part: variant}.
const HAT_HAIR_VARIANT := {
	"crown": {"hair_curly": "hair_curly_hat"}, "headphones": {"hair_curly": "hair_curly_hat"},
	"headlamp": {"hair_curly": "hair_curly_hat"},
	"pompom_beanie": {"hair": "hair_hat", "hair_curly": "hair_curly_low"},
	"glow_headband": {"hair": "hair_hat", "hair_curly": "hair_curly_hat"},
	"owl_ears": {"hair_curly": "hair_curly_hat"},
	"@cap": {"hair": "hair_hat", "hair_curly": "hair_curly_low"},
	"@mask": {"hair": "hair_hat", "hair_curly": "hair_curly_hat"},
}
## only these outfits show the pattern (the others are single-material)
const PATTERNED_OUTFITS := ["pj", "robe"]

# --- V1/V2 legacy (5-byte wire format and the "cosmetic" save dictionary)
const LEGACY_OUTFITS := ["pj_stripes", "pj_plain", "swim", "robe", "duck", "frog"]
const LEGACY_HATS := ["none", "nightcap", "swimcap", "party", "headphones", "crown"]
const LEGACY_SHOES := ["slippers", "sneakers", "flippers"]
const LEGACY_COLORS := ["sky", "bubblegum", "lime", "sunny", "grape", "teal", "tangerine", "cloud"]
const LEGACY_SKINS := ["tone2", "tone4", "tone6", "tone7", "tone3"]
## V2 picked the hair colour from the skin tone; keep each migrated runner's look
const LEGACY_HAIR_BY_SKIN := ["brown", "dark_brown", "espresso", "black", "ginger"]


static func entry(field: String, key: String) -> Dictionary:
	return CATALOG.get(field, {}).get(key, {})


static func keys_of(field: String) -> Array:
	return CATALOG.get(field, {}).keys()


static func cost(field: String, key: String) -> int:
	return int(entry(field, key).get("cost", 0))


static func is_legacy(c: Dictionary) -> bool:
	if c.has("schema"):
		return false
	# V1/V2 stored colour and skin as palette indices (ints; floats after JSON)
	for f in ["color", "skin"]:
		if typeof(c.get(f, null)) in [TYPE_INT, TYPE_FLOAT]:
			return true
	return String(c.get("outfit", "")) in ["pj_stripes", "pj_plain"]


## V1/V2 cosmetic dictionary -> schema 2 appearance (same look).
static func migrate_legacy(c: Dictionary) -> Dictionary:
	var out := DEFAULT.duplicate()
	var o := String(c.get("outfit", "pj_stripes"))
	match o:
		"pj_stripes":
			out["outfit"] = "pj"
			out["pattern"] = "stripes"
		"pj_plain":
			out["outfit"] = "pj"
			out["pattern"] = "plain"
		_:
			if CATALOG["outfit"].has(o):
				out["outfit"] = o
				out["pattern"] = "plain"
	if CATALOG["hat"].has(String(c.get("hat", ""))):
		out["hat"] = String(c["hat"])
	if CATALOG["shoes"].has(String(c.get("shoes", ""))):
		out["shoes"] = String(c["shoes"])
	var ci := clampi(int(c.get("color", 0)), 0, LEGACY_COLORS.size() - 1)
	out["color"] = LEGACY_COLORS[ci]
	var si := clampi(int(c.get("skin", 0)), 0, LEGACY_SKINS.size() - 1)
	out["skin"] = LEGACY_SKINS[si]
	out["hair_color"] = LEGACY_HAIR_BY_SKIN[si]
	return out


## Any input (schema 2, legacy, partial, hostile) -> a complete valid appearance.
static func sanitize(c: Dictionary) -> Dictionary:
	if is_legacy(c):
		return migrate_legacy(c)
	var out := DEFAULT.duplicate()
	for f in ORDER:
		var v = c.get(f, null)
		if typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME:
			if CATALOG[f].has(String(v)):
				out[f] = String(v)
	return out


## Owned-item key used in the profile ("hat:crown").  Free items need no entry.
static func own_key(field: String, key: String) -> String:
	return "%s:%s" % [field, key]


## Legacy owned keys -> schema 2 keys ("outfit:pj_stripes" -> "outfit:pj").
static func migrate_owned(owned: Array) -> Array:
	var out: Array = []
	for k in owned:
		var s := String(k)
		if s == "outfit:pj_stripes" or s == "outfit:pj_plain":
			s = "outfit:pj"
		var parts := s.split(":")
		if parts.size() == 2 and CATALOG.has(parts[0]) and CATALOG[parts[0]].has(parts[1]) and not out.has(s):
			out.append(s)
	return out


static func color_of(c: Dictionary) -> Color:
	return entry("color", String(c.get("color", "sky"))).get("rgb", Color(0.36, 0.55, 0.95))


static func skin_color(c: Dictionary) -> Color:
	return entry("skin", String(c.get("skin", "tone2"))).get("rgb", Color(0.98, 0.82, 0.68))


static func hair_color(c: Dictionary) -> Color:
	return entry("hair_color", String(c.get("hair_color", "brown"))).get("rgb", Color("4a3222"))


## [primary, secondary (trim), dark] tints for the character shader
static func tints(c: Dictionary) -> Array:
	var prim := color_of(c)
	var sec := prim.lerp(Color.WHITE, 0.55) if prim.get_luminance() < 0.72 else prim.darkened(0.28)
	var tr: Dictionary = entry("trim", String(c.get("trim", "auto")))
	if tr.has("rgb"):
		sec = tr["rgb"]
	return [prim, sec, prim.darkened(0.38)]


static func stripes_per_m(c: Dictionary) -> float:
	if not String(c.get("outfit", "pj")) in PATTERNED_OUTFITS:
		return 0.0
	return float(entry("pattern", String(c.get("pattern", "plain"))).get("per_m", 0.0))


## Mesh parts to show for a runner with this appearance (Night Watch wears
## the uniform whatever the appearance says; CharacterView handles that).
static func runner_parts(c: Dictionary) -> Array:
	var a := sanitize(c)
	var want: Array = ["base"]
	want.append_array(OUTFIT_PARTS[a["outfit"]])
	if not a["outfit"] in OUTFIT_OWN_SHOES:
		want.append_array(entry("shoes", a["shoes"])["parts"])
	want.append_array(entry("marks", a["marks"])["parts"])
	if a["outfit"] in HOOD_OUTFITS:
		return want
	want.append_array(entry("hat", a["hat"])["parts"])
	want.append_array(headwear_parts(a))
	var hidden: Array = []
	var swap: Dictionary = {}
	for k in head_rules(a):
		hidden.append_array(HAT_HIDES_HAIR.get(k, []))
		swap.merge(HAT_HAIR_VARIANT.get(k, {}))
	for p in entry("hair", a["hair"])["parts"]:
		if not p in hidden:
			want.append(swap.get(p, p))
	return want


## Parts an outfit's own headwear adds (V6: the sleep mask with no hat or a
## party hat, headphones, crown or owl ears; the courier cap with no hat).
static func headwear_parts(c: Dictionary) -> Array:
	var a := sanitize(c)
	if a["outfit"] in HOOD_OUTFITS:
		return []
	var hw: Dictionary = OUTFIT_HEADWEAR.get(a["outfit"], {})
	if hw.is_empty() or not a["hat"] in hw["with_hats"]:
		return []
	return hw["parts"]


## Which of the player's own choices an outfit draws instead (Shop and Locker
## copy, Pass 8): "hat" and "hair" for hoods, "shoes" for outfits with their
## own footwear.  An outfit's headwear (OUTFIT_HEADWEAR) only shows with the
## hats listed there, so it never replaces a chosen hat.
static func outfit_replaces(outfit: String) -> Array:
	var out: Array = []
	if outfit in HOOD_OUTFITS:
		out.append_array(["hat", "hair"])
	if outfit in OUTFIT_OWN_SHOES:
		out.append("shoes")
	return out


## Keys of HAT_HIDES_HAIR / HAT_HAIR_VARIANT in effect: the chosen hat, plus
## the outfit's own headwear when it is worn ("@cap", "@mask").
static func head_rules(c: Dictionary) -> Array:
	var a := sanitize(c)
	var keys: Array = [a["hat"]]
	for part in headwear_parts(a):
		keys.append(HEADWEAR_AS_HAT[part])
	return keys


## Held face shape-key weights for this appearance.
static func face_keys(c: Dictionary) -> Dictionary:
	var a := sanitize(c)
	var out: Dictionary = {}
	for f in ["face", "brows"]:
		var k: Dictionary = entry(f, a[f]).get("keys", {})
		for n in k:
			out[n] = float(out.get(n, 0.0)) + float(k[n])
	return out


static func bot_cosmetic(seed_v: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var out := DEFAULT.duplicate()
	for f in ORDER:
		var ks: Array = keys_of(f)
		out[f] = ks[rng.randi() % ks.size()]
	return out


## Versioned wire format (explicit field and value IDs).
static func encode(c: Dictionary) -> PackedByteArray:
	var a := sanitize(c)
	var b := PackedByteArray([WIRE_MAGIC, SCHEMA, ORDER.size()])
	for f in ORDER:
		b.append(int(FIELDS[f]))
		b.append(int(entry(f, a[f])["id"]))
	return b


## Inverse of encode().  Accepts the legacy 5-byte format too (old saves or
## captures); anything malformed decodes to a valid appearance, never an error.
static func decode(b: PackedByteArray) -> Dictionary:
	if b.size() == 5 and b[0] < LEGACY_OUTFITS.size():
		return migrate_legacy({
			"outfit": LEGACY_OUTFITS[b[0]],
			"hat": LEGACY_HATS[b[1]] if b[1] < LEGACY_HATS.size() else "none",
			"shoes": LEGACY_SHOES[b[2]] if b[2] < LEGACY_SHOES.size() else "slippers",
			"color": int(b[3]), "skin": int(b[4]),
		})
	var out := DEFAULT.duplicate()
	if b.size() < 3 or b[0] != WIRE_MAGIC or b[1] < 2:
		return out
	var n := mini(int(b[2]), (b.size() - 3) / 2)
	var by_fid := {}
	for f in FIELDS:
		by_fid[int(FIELDS[f])] = f
	for i in n:
		var fid := int(b[3 + i * 2])
		var vid := int(b[4 + i * 2])
		if not by_fid.has(fid):
			continue
		var f: String = by_fid[fid]
		for k in CATALOG[f]:
			if int(CATALOG[f][k]["id"]) == vid:
				out[f] = k
				break
	return out


## Wire bytes for a valid appearance are at most this long (decoders bound reads).
static func max_wire_size() -> int:
	return 3 + 2 * 32   # room for up to 32 fields
