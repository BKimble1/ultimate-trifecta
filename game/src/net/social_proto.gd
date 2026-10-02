class_name SocialProto
extends RefCounted
## V6 social messages beside the game protocol (Protocol).  They use the
## reserved type range 60-79 so the game protocol can grow without clashes;
## NetSession hands every message in the range to SocialNet.
##
##   60 CHAT_SEND     client -> host  (reliable)  u16 nonce, u8 channel, u8 kind,
##                                    quick: u8 phrase | text: long token
##   61 CHAT          host -> clients (reliable)  u32 seq, i8 from slot, u8 channel,
##                                    u8 kind, u16 nonce, quick: u8 phrase | text: long token
##   62 CHAT_REJECT   host -> sender  (reliable)  u16 nonce, u8 reason
##   63 HUB_POSE      client -> host  (unreliable at 10 Hz; reliable on a
##                                    mode change)  u16 seq, u8 mode, i16 x, i16 z,
##                                    u16 yaw, u8 speed, i8 emote
##   64 HUB_STATE     host -> clients (unreliable at 10 Hz while anyone
##                                    walks)  u8 n, n x (u8 slot, the HUB_POSE body)
##   65 CHAT_HISTORY  host -> one client on (re)join (reliable)  u8 n, n x CHAT body
## Clients accept 61, 62, 64 and 65 only from their bound host.

const FIRST := 60
const LAST := 79
const CHAT_SEND := 60
const CHAT := 61
const CHAT_REJECT := 62
const HUB_POSE := 63
const HUB_STATE := 64
const CHAT_HISTORY := 65
const HOST_ONLY := [CHAT, CHAT_REJECT, HUB_STATE, CHAT_HISTORY]

enum Kind { QUICK, TEXT }
enum Reject { RATE, CHANNEL, PHRASE, UNVERIFIED, REPEAT, UNAVAILABLE }
const REJECT_TEXT := ["You're sending messages too fast. Wait a moment.", "That chat isn't open right now.",
	"That message isn't available here.", "That message couldn't be confirmed.", "You just sent that.",
	"Typed chat isn't available in this party."]

## hub pose position scale: 1/64 m, int16
const POS_SCALE := 64.0


static func is_social(type: int) -> bool:
	return type >= FIRST and type <= LAST
