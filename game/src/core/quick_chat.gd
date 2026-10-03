class_name QuickChat
extends RefCounted
## Curated Quick Chat (V6): short, friendly, game-authored phrases that work
## everywhere, with or without the moderation service.  A phrase travels as
## its id (never as text), so nobody can change what it says, and each one
## is offered only where it makes sense:
##   PARTY       the party room before a round
##   TEAM        your own role's team during a round (runners or Night Watch)
##   SPECTATORS  finished runners and watchers during a round (they see
##               the whole campus, so they never talk to active players)
##   ALL         everyone, on the results after a round
## The host checks the id against the channel and the sender's role.

enum Channel { PARTY, TEAM, ALL, SPECTATORS }

const CHANNEL_NAMES := ["Party", "Team", "Everyone", "Spectators"]

## id -> [text, channels, roles]  (roles: [] = any; else TC.Role values,
## checked for TEAM only).  Ids are stable: never reuse or renumber one.
const PHRASES := {
	1: ["Ready!", [Channel.PARTY, Channel.ALL], []],
	2: ["One moment", [Channel.PARTY, Channel.ALL], []],
	3: ["Let's play!", [Channel.PARTY], []],
	4: ["Hi everyone!", [Channel.PARTY], []],
	5: ["Nice outfit!", [Channel.PARTY, Channel.ALL], []],
	6: ["Good luck, everyone!", [Channel.PARTY, Channel.SPECTATORS], []],
	7: ["Be right back", [Channel.PARTY, Channel.ALL], []],
	8: ["Thanks!", [Channel.PARTY, Channel.TEAM, Channel.ALL, Channel.SPECTATORS], []],
	9: ["Change the settings?", [Channel.PARTY], []],
	20: ["Need help", [Channel.TEAM], []],
	21: ["Heading home", [Channel.TEAM], [TC.Role.RUNNER]],
	22: ["On my way", [Channel.TEAM], []],
	23: ["Watch out!", [Channel.TEAM], []],
	24: ["Night Watch nearby!", [Channel.TEAM], [TC.Role.RUNNER]],
	25: ["Going for the water", [Channel.TEAM], [TC.Role.RUNNER]],
	26: ["Runner spotted!", [Channel.TEAM], [TC.Role.PATROL]],
	27: ["Covering the dorm", [Channel.TEAM], [TC.Role.PATROL]],
	28: ["Taking a cart", [Channel.TEAM], [TC.Role.PATROL]],
	29: ["Nice tag!", [Channel.TEAM], [TC.Role.PATROL]],
	30: ["Nice run!", [Channel.TEAM, Channel.ALL, Channel.SPECTATORS], []],
	40: ["Good game!", [Channel.ALL], []],
	41: ["Well played", [Channel.ALL, Channel.SPECTATORS], []],
	42: ["Rematch?", [Channel.ALL], []],
	43: ["So close!", [Channel.ALL, Channel.SPECTATORS], []],
	44: ["Thanks for playing!", [Channel.ALL], []],
	45: ["Go, go, go!", [Channel.SPECTATORS], []],
	46: ["Wow!", [Channel.SPECTATORS, Channel.ALL], []],
}


static func text(id: int) -> String:
	return String(PHRASES[id][0]) if PHRASES.has(id) else ""


## May phrase `id` be sent on `channel` by someone with `role`?
static func allowed(id: int, channel: int, role: int = -1) -> bool:
	if not PHRASES.has(id):
		return false
	var p: Array = PHRASES[id]
	if not (p[1] as Array).has(channel):
		return false
	if channel == Channel.TEAM and not (p[2] as Array).is_empty():
		return (p[2] as Array).has(role)
	return true


## Phrase ids offered for a channel and role, in table order.
static func offered(channel: int, role: int = -1) -> Array:
	var out: Array = []
	for id in PHRASES:
		if allowed(int(id), channel, role):
			out.append(int(id))
	return out
