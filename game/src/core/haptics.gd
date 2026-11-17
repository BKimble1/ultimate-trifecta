class_name Haptics
extends RefCounted
## (2.2 build 18) Short vibrations on the phone, when Settings › Controls ›
## Vibration is on.  Nothing on desktop, in tests or under automation.
##   tick     a tab or a choice (the lightest)
##   tap      a confirmation (a button that did something)
##   success  something good landed (a purchase, a reward, home)
##   heavy    a hit (caught, knocked out)

static func _on() -> bool:
	return OS.has_feature("mobile") and bool(Save.get_setting("haptics", true)) and not App.dev_automation


static func tick() -> void:
	if _on():
		Input.vibrate_handheld(8, 0.25)


static func tap() -> void:
	if _on():
		Input.vibrate_handheld(14, 0.4)


static func success() -> void:
	if _on():
		Input.vibrate_handheld(40, 0.6)


static func heavy() -> void:
	if _on():
		Input.vibrate_handheld(70, 0.9)
