class_name InputOwner
extends RefCounted
## Who owns movement input right now (V6).  Movement (walking in the party
## room, running in a round) reads the stick and keys only while no menu
## owns input: an open chat drawer, keyboard or sheet takes ownership, so
## typing, tapping a phrase or scrolling never moves or tags anyone.  Taking
## and releasing ownership both reset the touch/press state (Controls), so
## a finger or key that was down when a menu opened never "sticks" when it
## closes.  Owners are named; taking twice or releasing an unknown owner is
## harmless.

static var _owners: Array[String] = []


static func take(who: String) -> void:
	if not _owners.has(who):
		_owners.append(who)
	_reset()


static func release(who: String) -> void:
	if _owners.has(who):
		_owners.erase(who)
		_reset()


static func menu_owns() -> bool:
	return not _owners.is_empty()


static func owners() -> Array[String]:
	return _owners.duplicate()


## Scene changes (a round starting, leaving the party) drop every owner.
static func clear() -> void:
	_owners.clear()
	_reset()


static func _reset() -> void:
	if Engine.get_main_loop() != null:
		Controls.reset_touch()
