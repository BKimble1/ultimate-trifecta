class_name Catalogue
extends RefCounted
## The one authoritative catalogue (V6): res://config/catalogue.json.
##
## Stable item IDs shared by previews, ownership, Shop, Season Pass, saves,
## networking and the service (service/src/catalogue_data.js is generated
## from the same file):
##   runner items     "<Cosmetics field>:<Cosmetics key>"  e.g. "hat:crown"
##                    (the same strings the save's owned list has used since
##                    V3, so pre-V6 unlocks keep their meaning)
##   profile items    "card:<key>", "badge:<key>"  (UI-only name cards/badges)
##   coin packs       "coins:500", "coins:1500", "coins:3500"
##   season premium   "season:s1:premium"
## Kinds: coin_item (bought with Coins in the Shop), apple_skin (a permanent
## non-consumable bought directly from Apple), coin_pack (consumable Coins
## from Apple), season_premium (bought with Coins), season_reward (earned in
## the Season Pass, never sold under another ID).
##
## Runner art lives in Cosmetics (names, meshes); an item whose art is not in
## Cosmetics is never offered (has_art) and test_catalogue reports it.
## Real-money prices are never stored: StoreKit's localized price is shown.
## Runner options with no catalogue entry and Cosmetics cost 0 are the free
## base options everyone owns.

const PATH := "res://config/catalogue.json"
const PROFILE_FIELDS := ["card", "badge"]
const SELLABLE := ["coin_item", "apple_skin", "coin_pack", "season_premium"]

static var _data: Dictionary = {}
static var _by_id: Dictionary = {}
static var _by_product: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed
		_by_id.clear()
		_by_product.clear()
		for it in _data.get("items", []):
			_by_id[String(it["id"])] = it
		var prods: Dictionary = _data.get("products", {})
		for pid in prods:
			_by_product[String(pid)] = prods[pid]
	return _data


static func version() -> int:
	return int(data().get("catalogue_version", 0))


static func has(id: String) -> bool:
	data()
	return _by_id.has(id)


## The catalogue entry ({} when unknown).
static func item(id: String) -> Dictionary:
	data()
	return _by_id.get(id, {})


static func all_items() -> Array:
	return data().get("items", [])


static func items_of_kind(kind: String) -> Array:
	return all_items().filter(func(it: Dictionary) -> bool: return String(it["kind"]) == kind)


static func kind(id: String) -> String:
	return String(item(id).get("kind", ""))


static func id_for(field: String, key: String) -> String:
	return "%s:%s" % [field, key]


## [field, key] of a runner or profile item ("hat:crown" -> ["hat", "crown"]).
static func split(id: String) -> Array:
	var i := id.find(":")
	if i < 0:
		return ["", id]
	return [id.substr(0, i), id.substr(i + 1)]


static func is_runner_item(id: String) -> bool:
	return Cosmetics.FIELDS.has(String(split(id)[0]))


static func is_profile_item(id: String) -> bool:
	return String(split(id)[0]) in PROFILE_FIELDS


## The art exists: runner items need their Cosmetics entry; profile items,
## coin packs and season access are drawn by the UI.
static func has_art(id: String) -> bool:
	if is_runner_item(id):
		var s := split(id)
		return not Cosmetics.entry(String(s[0]), String(s[1])).is_empty()
	return has(id)


## A free base option everyone owns (no catalogue entry, Cosmetics cost 0).
static func is_free(field: String, key: String) -> bool:
	if Cosmetics.entry(field, key).is_empty():
		return false
	if has(id_for(field, key)):
		return false
	return Cosmetics.cost(field, key) == 0


static func display_name(id: String) -> String:
	var it := item(id)
	if it.has("name"):
		return String(it["name"])
	if is_runner_item(id):
		var s := split(id)
		var e := Cosmetics.entry(String(s[0]), String(s[1]))
		if not e.is_empty():
			return String(e["name"])
	if String(it.get("kind", "")) == "coin_pack":
		return "%s Coins" % format_coins(int(it.get("coins", 0)))
	return String(split(id)[1]).capitalize()


## A short word for what kind of thing it is ("Outfit", "Hat", "Name card").
static func type_label(id: String) -> String:
	var f := String(split(id)[0])
	match f:
		"outfit": return "Outfit"
		"pattern": return "Pattern"
		"color": return "Main color"
		"trim": return "Trim"
		"hair_color": return "Hair color"
		"hat": return "Hat"
		"shoes": return "Shoes"
		"emote": return "Emote"
		"card": return "Name card"
		"badge": return "Badge"
		"coins": return "Coins"
		"season": return "Season access"
	return f.capitalize()


## Price in Coins (0 for items not sold for Coins).
static func price(id: String) -> int:
	var it := item(id)
	if String(it.get("kind", "")) in ["coin_item", "season_premium"]:
		return int(it.get("price", 0))
	return 0


static func blurb(id: String) -> String:
	return String(item(id).get("blurb", ""))


## Every catalogue ID this item grants (one; listed so a bundle could name
## exactly what it includes).
static func grants(id: String) -> Array:
	var g: Variant = item(id).get("grants")
	return (g as Array).duplicate() if g is Array else [id]


# ---------------------------------------------------------------- products
static func products() -> Dictionary:
	data()
	return _by_product


static func product_ids() -> PackedStringArray:
	return PackedStringArray(products().keys())


static func product(pid: String) -> Dictionary:
	return products().get(pid, {})


static func product_of(id: String) -> String:
	return String(item(id).get("product", ""))


static func item_for_product(pid: String) -> String:
	return String(product(pid).get("item", ""))


# ---------------------------------------------------------------- shop
## Shop sections: "featured", "outfits", "accessories", "coins", "season".
## Only items whose art exists are offered.
static func shop_items(section: String) -> Array:
	var out: Array = []
	match section:
		"featured":
			for it in all_items():
				if int(it.get("featured", 0)) > 0 and has_art(String(it["id"])):
					out.append(it)
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["featured"]) < int(b["featured"]))
		"outfits":
			for it in all_items():
				var id := String(it["id"])
				if String(it["kind"]) in ["coin_item", "apple_skin"] and id.begins_with("outfit:") and has_art(id):
					out.append(it)
		"accessories":
			for it in all_items():
				var id2 := String(it["id"])
				if String(it["kind"]) == "coin_item" and not id2.begins_with("outfit:") and has_art(id2):
					out.append(it)
		"coins":
			out = items_of_kind("coin_pack")
		"season":
			out = items_of_kind("season_premium")
	return out


# ---------------------------------------------------------------- seasons
static func season(sid: String) -> Dictionary:
	return data().get("seasons", {}).get(sid, {})


static func current_season_id() -> String:
	return "s1"


static func season_tiers(sid: String) -> Array:
	return season(sid).get("tiers", [])


static func economy() -> Dictionary:
	return data().get("economy", {})


## Every item a season's tiers reference (for art checks and the Locker's
## "earn it in the Season Pass" hint).
static func season_reward_ids(sid: String) -> Array:
	var out: Array = []
	for t in season_tiers(sid):
		for track in ["free", "premium"]:
			var r: Variant = t.get(track)
			if r is Dictionary and (r as Dictionary).has("item"):
				out.append(String(r["item"]))
	return out


## Where an unowned item can be obtained: "shop", "apple", "season" or "".
static func source_of(id: String) -> String:
	match kind(id):
		"coin_item", "season_premium":
			return "shop"
		"apple_skin":
			return "apple"
		"season_reward":
			return "season"
	return ""


## The season tier and track that award this item ([] when none).
static func season_tier_of(id: String) -> Array:
	var sid := String(item(id).get("season", current_season_id()))
	for t in season_tiers(sid):
		for track in ["free", "premium"]:
			var r: Variant = t.get(track)
			if r is Dictionary and String((r as Dictionary).get("item", "")) == id:
				return [sid, int(t["tier"]), track]
	return []


# ---------------------------------------------------------------- formatting
## "1,500" (Coins are always whole; thousands grouped).
static func format_coins(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
