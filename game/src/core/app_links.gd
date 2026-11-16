class_name AppLinks
extends RefCounted
## The owner's public links (privacy policy, support).  They come from
## res://config/links.cfg, which ships in every build (the export preset's
## include_filter), so they're reachable even when the game service is off
## or unreachable; the service's configuration is the fallback.  Only https
## links are returned; "" means not set (callers hide the link).

const PATH := "res://config/links.cfg"

static var _cfg: ConfigFile


static func get_link(key: String) -> String:
	if _cfg == null:
		_cfg = ConfigFile.new()
		if _cfg.load(PATH) != OK:
			_cfg = ConfigFile.new()
	var v := String(_cfg.get_value("links", key, "")).strip_edges()
	if v.begins_with("https://"):
		return v
	return Cloud.link(key)


## (2.2) The support e-mail address for reports without the moderation
## service ("" when not set: no e-mail report is offered).
static func support_email() -> String:
	if _cfg == null:
		get_link("support_url")
	var v := String(_cfg.get_value("links", "support_email", "")).strip_edges()
	return v if v.contains("@") and v.contains(".") and not v.contains(" ") else ""


## Tests: replace the bundled values.
static func override(values: Dictionary) -> void:
	_cfg = ConfigFile.new()
	for k in values:
		_cfg.set_value("links", String(k), values[k])


static func reset() -> void:
	_cfg = null
