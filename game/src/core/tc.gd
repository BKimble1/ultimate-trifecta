class_name TC
extends RefCounted
## Shared enums and constants (Trifecta Chase).

enum Role { RUNNER, PATROL, SPECTATOR }

enum PState {
	ACTIVE,      # normal on-foot control
	STUMBLE,     # short controlled stumble after a cart bump
	SPLASHING,   # automatic splash + resurface sequence
	CAPTURED,    # recovery penalty after a valid tag
	FINISHED,    # runner home safe
	IN_CART,     # patrol driving a cart
	ENTERING,    # patrol climbing into cart
	EXITING,     # patrol hopping out of cart
	WAITING,     # patrol held in cart shed during runner head start
}

enum Phase { LOBBY, LOADING, REVEAL, COUNTDOWN, PLAYING, RESULTS, ENDED }

enum Outcome { NONE, RUNNERS_WIN, PATROL_WIN, CANCELLED }

enum Gadget { NONE, TURBO, DECOY, SPLASH_BOMB }

## How a runner met the water (presentation: splash clip + spray shape).
## Carried by SPLASH_* events (field m) and snapshots; no rule reads it.
enum Impact { WALK, JUMP, DIVE }

enum Ev {
	SPLASH_STAMP,     # a, target_index
	SPLASH_NOSTAMP,   # a
	CAPTURE,          # a = runner, b = patrol
	TAG_MISS,         # a = patrol
	FINISH,           # a = runner, value = order
	BUMP,             # a = runner, b = cart
	CART_ENTER,       # a = patrol, b = cart
	CART_EXIT,        # a = patrol, b = cart
	GADGET_PICKUP,    # a, value = gadget
	GADGET_USE,       # a, value = gadget
	BOMB_HIT,         # b = cart
	RESPAWN,          # a
	RECOVER,          # a (out-of-bounds recovery)
	EMOTE,            # a, value = emote id
	PHASE,            # value = phase
	MATCH_END,        # value = outcome
	PLAYER_LEFT,      # a
	PLAYER_BOT_TAKEOVER, # a
	PLAYER_RESUMED,   # a
	COIN_PICKUP,      # V6: a = collector, value = coin index in the round's list
}

# Input button bits (held state) and edge bits (pressed this tick).
const BTN_JUMP := 1
const BTN_SPRINT := 2
const BTN_TAG := 4
const BTN_INTERACT := 8
const BTN_GADGET := 16
const BTN_ACCEL := 32
const BTN_BRAKE := 64

# Collision layers (bit values)
const L_WORLD := 1
const L_CART_BLOCK := 2
const L_CART := 4
const L_CHAR := 8

const EMOTES := ["wave", "cheer", "laugh", "shrug", "dance", "point"]
const EMOTE_LABELS := {"wave": "Wave", "cheer": "Cheer", "laugh": "Ha!", "shrug": "Shrug", "dance": "Dance", "point": "Over here!"}

const GADGET_NAMES := {Gadget.TURBO: "Turbo Sneakers", Gadget.DECOY: "Squeaky Decoy", Gadget.SPLASH_BOMB: "Splash Bomb"}
const GADGET_KEYS := {"turbo": Gadget.TURBO, "decoy": Gadget.DECOY, "splash_bomb": Gadget.SPLASH_BOMB}

## Role cards from the round's actual rules (the counts vary with the party
## settings; never hard-code them).
static func runner_card(cfg: RulesConfig) -> String:
	return " ".join(role_lines(Role.RUNNER, cfg))


static func patrol_card(cfg: RulesConfig) -> String:
	return " ".join(role_lines(Role.PATROL, cfg))


## A role in two short lines (V5): what to do, then the one rule to know.
static func role_lines(r: int, cfg: RulesConfig) -> Array[String]:
	if r == Role.PATROL:
		return ["Stop %d runners getting home before time runs out: cut them off in a cart, hop out and tag." % cfg.runners_needed,
			"A tag sends a runner out for %d s; they keep their splashes." % int(cfg.capture_penalty_s)]
	return ["Splash into the three marked waters, then race back to the dorm. %d home wins it for every runner." % cfg.runners_needed,
		"Caught? You keep your splashes and you're back in %d s." % int(cfg.capture_penalty_s)]


static func role_name(r: int) -> String:
	match r:
		Role.RUNNER: return "Runner"
		Role.PATROL: return "Night Watch"
	return "Spectator"
