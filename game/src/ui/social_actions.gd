class_name SocialActions
extends RefCounted
## Mute and block, the same from a player card, the chat drawer or a round
## (V6).  See SocialSafety for what they hide.


static func toggle_mute(session: NetSession, uid: String) -> bool:
	if session == null or uid == "":
		return false
	if session.muted.has(uid):
		session.muted.erase(uid)
		return false
	session.muted[uid] = true
	session.social.chat.forget_sender(uid)
	return true


## Block a player: on this device at once (their chat, emotes and name are
## hidden everywhere), on the service when signed in (they can't join your
## parties and you aren't put in theirs), and a host removes them from the
## party.  Returns a short note for the player.
static func block(session: NetSession, e: Dictionary) -> String:
	var pid := String(e.get("pid", ""))
	var uid := String(e.get("uid", ""))
	Save.add_block(pid, uid, String(e.get("name", "")))
	if session != null and is_instance_valid(session):
		session.muted[uid] = true
		session.social.chat.forget_sender(uid)
		if session.is_host():
			var slot := int(e.get("slot", -1))
			if slot >= 0 and session.roster[slot] != null and String(session.roster[slot]["uid"]) == uid:
				if pid != "" and App.party_code != "" and Cloud.configured():
					Cloud.kick_from_room(App.party_code, pid)
				session.kick(slot)
	var note := "Blocked on this device."
	if Cloud.configured() and pid != "":
		var r: Dictionary = await Cloud.block(pid)
		note = "Blocked." if bool(r.get("ok", false)) else "Blocked on this device (the online block didn't go through: %s)." % Cloud.explain(r)
	return note
