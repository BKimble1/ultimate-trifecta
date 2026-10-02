class_name Admission
extends RefCounted
## Host-side check of the admission credential a joiner presents in HELLO.
## The service signs it (RS256) after checking the room, capacity, blocks,
## version and the joiner's verified Game Center identity; the host verifies
## it offline with the service's public key (game/config/service.cfg) and
## binds it to the Game Center player who actually sent it.

const AUD := "trifecta-host"
const LEEWAY_S := 90   # device clocks drift; tokens live 120 s


static func _b64url(s: String) -> PackedByteArray:
	var t := s.replace("-", "+").replace("_", "/")
	while t.length() % 4 != 0:
		t += "="
	return Marshalls.base64_to_raw(t)


## Returns {ok, claims} or {ok:false, error}.  expect: {code, gc (sender's
## teamPlayerID), now (unix seconds), seen (Dictionary of used jti)}.
static func verify(token: String, key: CryptoKey, expect: Dictionary) -> Dictionary:
	if key == null:
		return {"ok": false, "error": "no_key"}
	if token.length() < 20 or token.length() > 4096:
		return {"ok": false, "error": "malformed"}
	var parts := token.split(".")
	if parts.size() != 3:
		return {"ok": false, "error": "malformed"}
	var header: Variant = JSON.parse_string(_b64url(parts[0]).get_string_from_utf8())
	var claims: Variant = JSON.parse_string(_b64url(parts[1]).get_string_from_utf8())
	if not (header is Dictionary) or not (claims is Dictionary) or String(header.get("alg", "")) != "RS256":
		return {"ok": false, "error": "malformed"}
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((parts[0] + "." + parts[1]).to_utf8_buffer())
	var digest := ctx.finish()
	if not Crypto.new().verify(HashingContext.HASH_SHA256, digest, _b64url(parts[2]), key):
		return {"ok": false, "error": "signature"}
	var now := int(expect.get("now", int(Time.get_unix_time_from_system())))
	if String(claims.get("aud", "")) != AUD:
		return {"ok": false, "error": "audience"}
	if int(claims.get("exp", 0)) + LEEWAY_S < now or int(claims.get("iat", 0)) - LEEWAY_S > now:
		return {"ok": false, "error": "expired"}
	if String(claims.get("code", "")) != String(expect.get("code", "")):
		return {"ok": false, "error": "room"}
	if expect.has("gc") and String(claims.get("gc", "")) != String(expect["gc"]):
		return {"ok": false, "error": "player"}
	var jti := String(claims.get("jti", ""))
	var seen: Dictionary = expect.get("seen", {})
	if jti == "" or seen.has(jti):
		return {"ok": false, "error": "replayed"}
	var slot := int(claims.get("slot", -1))
	if slot < 1 or slot > 7:
		return {"ok": false, "error": "slot"}
	return {"ok": true, "claims": claims}


static func load_public_key(pem: String) -> CryptoKey:
	if pem.strip_edges() == "":
		return null
	var k := CryptoKey.new()
	if k.load_from_string(pem, true) != OK:
		return null
	return k
