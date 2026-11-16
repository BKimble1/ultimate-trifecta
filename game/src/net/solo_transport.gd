class_name SoloTransport
extends NetTransport
## (2.2) The home party before anyone joins: a host with no network at all.
## The lobby, walking around, emotes and bot rounds run on it exactly as in
## an online party; inviting a friend or sharing the code moves the party to
## a Game Center room (App.open_party), keeping its settings.


func _init() -> void:
	is_host = true
	kind = "solo"


func is_open() -> bool:
	return true
