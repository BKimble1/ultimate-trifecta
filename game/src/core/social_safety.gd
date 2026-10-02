class_name SocialSafety
extends RefCounted
## Mute and block, applied the same way everywhere (V6): party room roster
## and stage, chat, the round (names over heads, reveal, map, feed) and
## results/standings.
##   Mute (this party): hides that player's chat and emotes.
##   Block (kept on this device, and on the service when signed in): hides
##     their chat and emotes, shows "Blocked player" instead of their name,
##     keeps you out of parties together from then on, and the host removes
##     them from the host's own party.
## Identity is the verified profile id when there is one, else the player's
## Game Center / device id.  Nothing here changes what other players see.

const BLOCKED_NAME := "Blocked player"


static func is_blocked(uid: String, pid: String = "") -> bool:
	return Save.is_blocked(pid, uid)


static func is_muted(session: Object, uid: String) -> bool:
	if session == null or not is_instance_valid(session):
		return false
	var m: Variant = session.get("muted")
	return m is Dictionary and (m as Dictionary).has(uid)


## Chat and emotes from this player are not shown.
static func is_hidden(session: Object, uid: String, pid: String = "") -> bool:
	return is_blocked(uid, pid) or is_muted(session, uid)


## The name to draw for a player record ({uid, pid?, name, is_bot?}).
static func name_of(e: Dictionary) -> String:
	if not bool(e.get("is_bot", false)) and is_blocked(String(e.get("uid", "")), String(e.get("pid", ""))):
		return BLOCKED_NAME
	return String(e.get("name", ""))


## A display copy of a roster / results record with the shown name.
static func display_entry(e: Dictionary) -> Dictionary:
	var d := e.duplicate()
	d["name"] = name_of(e)
	return d
