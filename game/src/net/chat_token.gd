class_name ChatToken
extends RefCounted
## A typed chat message approved by the service (POST /v1/chat/check): an
## RS256 token over {sub (sender's profile), room, ch, text, name, iat, exp,
## jti}, signed with the same key as admissions, so the game checks it with
## the public key it already ships (game/config/service.cfg).  The host
## checks it before relaying and every receiver checks it again before
## showing the text: neither a modified client nor a modified host can put
## unapproved text on someone's screen.

const AUD := "trifecta-chat"
const LEEWAY_S := 90


## {ok, claims} or {ok:false, error}.  expect: {room, sub (sender's profile
## id), now (unix seconds), seen (jti -> true, optional)}.
static func verify(token: String, key: CryptoKey, expect: Dictionary) -> Dictionary:
	if key == null:
		return {"ok": false, "error": "no_key"}
	if token.length() < 20 or token.length() > 4096:
		return {"ok": false, "error": "malformed"}
	var parts := token.split(".")
	if parts.size() != 3:
		return {"ok": false, "error": "malformed"}
	var header: Variant = JSON.parse_string(Admission._b64url(parts[0]).get_string_from_utf8())
	var claims: Variant = JSON.parse_string(Admission._b64url(parts[1]).get_string_from_utf8())
	if not (header is Dictionary) or not (claims is Dictionary) or String(header.get("alg", "")) != "RS256":
		return {"ok": false, "error": "malformed"}
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((parts[0] + "." + parts[1]).to_utf8_buffer())
	if not Crypto.new().verify(HashingContext.HASH_SHA256, ctx.finish(), Admission._b64url(parts[2]), key):
		return {"ok": false, "error": "signature"}
	if String(claims.get("aud", "")) != AUD:
		return {"ok": false, "error": "audience"}
	var now := int(expect.get("now", int(Time.get_unix_time_from_system())))
	if int(claims.get("exp", 0)) + LEEWAY_S < now or int(claims.get("iat", 0)) - LEEWAY_S > now:
		return {"ok": false, "error": "expired"}
	if String(claims.get("room", "")) != String(expect.get("room", "")):
		return {"ok": false, "error": "room"}
	if String(expect.get("sub", "")) == "" or String(claims.get("sub", "")) != String(expect["sub"]):
		return {"ok": false, "error": "sender"}
	var jti := String(claims.get("jti", ""))
	var seen: Dictionary = expect.get("seen", {})
	if jti == "" or seen.has(jti):
		return {"ok": false, "error": "replayed"}
	if not (claims.get("text") is String) or not ChatRules.display_ok(String(claims["text"])):
		return {"ok": false, "error": "text"}
	return {"ok": true, "claims": claims}
