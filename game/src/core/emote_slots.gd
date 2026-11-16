class_name EmoteSlots
extends RefCounted
## The emote loadout (2.2 build 16): five emotes the player has equipped,
## chosen in the Locker (Emotes) from the ones they own.  They are what the
## lobby's Emote button and the in-round emote button offer, in this order,
## and what keys 1-5 (and the pad's D-pad, first four) play.  Slot 1 is also
## the ready-up move (the look's "emote" field follows it).
const N := 5
const DEFAULT := ["wave", "cheer", "laugh", "shrug", "point"]


static func _usable(k: String) -> bool:
	return TC.EMOTES.has(k) and not Cosmetics.entry("emote", k).is_empty() and Save.owns("emote", k)


## The five equipped emote keys (owned ones; gaps filled from the defaults).
static func keys() -> Array:
	var saved: Variant = Save.data.get("emote_slots", [])
	var out: Array = []
	if saved is Array:
		for k in saved:
			if out.size() < N and _usable(String(k)) and not out.has(String(k)):
				out.append(String(k))
	if out.is_empty():
		# a player from before the loadout: their ready move first
		var mine := String(Cosmetics.sanitize(Save.data.get("cosmetic", {})).get("emote", "wave"))
		if _usable(mine):
			out.append(mine)
	for k in DEFAULT:
		if out.size() < N and _usable(String(k)) and not out.has(String(k)):
			out.append(String(k))
	return out


## The equipped emotes as TC.EMOTES indices (wire values).
static func ids() -> Array:
	return keys().map(func(k: String) -> int: return TC.EMOTES.find(k))


## The emote in a slot (-1 when the slot is empty).
static func id_at(slot: int) -> int:
	var a := ids()
	return int(a[slot]) if slot >= 0 and slot < a.size() else -1


## Put an owned emote in a slot; if it is already in another slot the two
## swap.  Saved at once; slot 1 also becomes the ready-up move.
static func put(slot: int, key: String) -> void:
	if not _usable(key) or slot < 0 or slot >= N:
		return
	var a := keys()
	while a.size() < N:
		a.append("")
	var at := a.find(key)
	if at >= 0 and at != slot:
		a[at] = a[slot]
	a[slot] = key
	Save.data["emote_slots"] = a.filter(func(k: String) -> bool: return k != "")
	var c: Dictionary = Save.data.get("cosmetic", {})
	if not c.is_empty() and String(keys()[0]) != String(c.get("emote", "")):
		c["emote"] = String(keys()[0])
		Save.data["cosmetic"] = Cosmetics.sanitize(c)
	Save.mark()
