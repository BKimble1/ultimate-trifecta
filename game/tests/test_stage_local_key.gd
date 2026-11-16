extends RefCounted
## 2.2 build 14 on iPhone: Game Center's sign-in changes the local player's id
## (the device id gives way to the Game Center id) while the party roster can
## still carry the old one.  The stage kept a character under each id, two
## runners on one mark ("three eyes").  One local character, whichever id.
var t


func _entry(key: String, local: bool) -> Dictionary:
	return {"key": key, "role": TC.Role.RUNNER, "cosmetic": Cosmetics.DEFAULT.duplicate(), "name": "", "is_bot": false,
		"local": local, "arrive": false}


func _shown(stage: DormStage) -> int:
	var n := 0
	for c in stage.get_children():
		if c is CharacterView and not c.is_queued_for_deletion():
			n += 1
	return n


func test_one_local_character_across_an_id_change() -> void:
	var stage := DormStage.new()
	t.add_child(stage)
	stage.set_mode("lobby", false)
	stage.sync_party([_entry("device-uid", true)])
	var v: CharacterView = stage.local_character()
	t.check(v != null, "a local character")
	# home: sync_stage_local with the Game Center id, not exclusive (in a room)
	stage.sync_party([_entry("G:12345", true)], false)
	t.check(stage.chars.size() == 1, "still one character on file (%d)" % stage.chars.size())
	t.check(_shown(stage) == 1, "one character shown (%d)" % _shown(stage))
	t.check(stage.local_character() == v, "the same character, re-filed")
	# the lobby roster still carries the old id (exclusive), with a friend
	stage.sync_party([_entry("device-uid", true), _entry("friend", false)])
	await t.get_tree().process_frame
	t.check(stage.chars.size() == 2, "the local runner and the friend (%d)" % stage.chars.size())
	t.check(_shown(stage) == 2, "two shown (%d)" % _shown(stage))
	t.check(stage.local_character() == v, "the local character kept")
	# any id the screens hold finds it
	t.check(stage.emote("G:12345", 0), "emote by the new id")
	t.check(stage.emoting("device-uid"), "emoting by the old id")
	stage.queue_free()
