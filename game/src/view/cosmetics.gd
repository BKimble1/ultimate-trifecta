class_name Cosmetics
extends RefCounted
## The V1 wardrobe. Appearance only — no item changes gameplay.

const OUTFITS := {
	"pj_stripes": {"name": "Striped PJs", "cost": 0, "kind": "pj", "stripes": 7.0},
	"pj_plain": {"name": "Comfy PJs", "cost": 0, "kind": "pj", "stripes": 0.0},
	"swim": {"name": "Swim Trunks", "cost": 0, "kind": "swim"},
	"robe": {"name": "Fluffy Robe", "cost": 90, "kind": "robe"},
	"duck": {"name": "Duck Mascot", "cost": 160, "kind": "duck"},
	"frog": {"name": "Frog Onesie", "cost": 200, "kind": "frog"},
}

const HATS := {
	"none": {"name": "No Hat", "cost": 0},
	"nightcap": {"name": "Nightcap", "cost": 0},
	"swimcap": {"name": "Swim Cap + Goggles", "cost": 0},
	"party": {"name": "Party Hat", "cost": 60},
	"headphones": {"name": "Headphones", "cost": 110},
	"crown": {"name": "Paper Crown", "cost": 240},
}

const SHOES := {
	"slippers": {"name": "Bunny Slippers", "cost": 0},
	"sneakers": {"name": "High-Tops", "cost": 50},
	"flippers": {"name": "Flippers", "cost": 130},
}

const COLORS := [
	Color(0.36, 0.55, 0.95), Color(0.95, 0.42, 0.55), Color(0.55, 0.85, 0.45), Color(0.98, 0.78, 0.30),
	Color(0.72, 0.50, 0.95), Color(0.30, 0.82, 0.82), Color(0.98, 0.58, 0.28), Color(0.92, 0.92, 0.95),
]
const COLOR_NAMES := ["Sky", "Bubblegum", "Lime", "Sunny", "Grape", "Teal", "Tangerine", "Cloud"]

const SKINS := [Color(0.98, 0.82, 0.68), Color(0.87, 0.66, 0.50), Color(0.66, 0.46, 0.32), Color(0.45, 0.30, 0.22), Color(0.96, 0.74, 0.62)]

const DEFAULT := {"outfit": "pj_stripes", "hat": "nightcap", "shoes": "slippers", "color": 0, "skin": 0}


static func sanitize(c: Dictionary) -> Dictionary:
	var out := DEFAULT.duplicate()
	if OUTFITS.has(c.get("outfit", "")):
		out["outfit"] = c["outfit"]
	if HATS.has(c.get("hat", "")):
		out["hat"] = c["hat"]
	if SHOES.has(c.get("shoes", "")):
		out["shoes"] = c["shoes"]
	out["color"] = clampi(int(c.get("color", 0)), 0, COLORS.size() - 1)
	out["skin"] = clampi(int(c.get("skin", 0)), 0, SKINS.size() - 1)
	return out


static func bot_cosmetic(seed_v: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var outfits := OUTFITS.keys()
	var hats := HATS.keys()
	var shoes := SHOES.keys()
	return {
		"outfit": outfits[rng.randi() % outfits.size()],
		"hat": hats[rng.randi() % hats.size()],
		"shoes": shoes[rng.randi() % shoes.size()],
		"color": rng.randi() % COLORS.size(),
		"skin": rng.randi() % SKINS.size(),
	}


static func item_cost(slot: String, id: String) -> int:
	var table: Dictionary = OUTFITS if slot == "outfit" else (HATS if slot == "hat" else SHOES)
	return int(table.get(id, {}).get("cost", 0))


## Compact wire format: 5 bytes.
static func encode(c: Dictionary) -> PackedByteArray:
	var s := sanitize(c)
	var b := PackedByteArray()
	b.append(OUTFITS.keys().find(s["outfit"]))
	b.append(HATS.keys().find(s["hat"]))
	b.append(SHOES.keys().find(s["shoes"]))
	b.append(int(s["color"]))
	b.append(int(s["skin"]))
	return b


static func decode(b: PackedByteArray) -> Dictionary:
	if b.size() < 5:
		return DEFAULT.duplicate()
	var o := OUTFITS.keys()
	var h := HATS.keys()
	var s := SHOES.keys()
	return sanitize({
		"outfit": o[b[0]] if b[0] < o.size() else "pj_stripes",
		"hat": h[b[1]] if b[1] < h.size() else "none",
		"shoes": s[b[2]] if b[2] < s.size() else "slippers",
		"color": b[3], "skin": b[4],
	})
