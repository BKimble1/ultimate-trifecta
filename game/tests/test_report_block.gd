extends RefCounted
## V6 report and block flows: a report is shown as sent only with the
## service's receipt; a failed request says so and offers Try again (never
## "Reported" for a request that went nowhere); without the service the
## sheet says reports are unavailable and sends nothing.  Blocking hides
## the player's name, chat and emotes and the host removes them.
var t


func _labels(n: Node) -> String:
	var out: Array = []
	for l in n.find_children("*", "Label", true, false):
		out.append((l as Label).text)
	return " | ".join(out)


func _buttons(n: Node) -> Array:
	return n.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return not b.is_queued_for_deletion())


func test_report_states_are_honest() -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.add_child(host)
	var calls: Array = []
	var answers: Array = [{"ok": false, "error": "network", "message": "Couldn't reach the game service."},
		{"ok": true, "receipt": "R-ABCDEF1234", "status": "received"}]
	var s := ReportSheet.open(host, {"kind": "message", "name": "Comfy Frog", "pid": "p_x", "token": "tok",
		"send_fn": func(kind: String, reason: String) -> Dictionary:
			calls.append([kind, reason])
			await t.get_tree().process_frame
			return answers[calls.size() - 1]})
	await t.get_tree().process_frame
	t.eq(s.state, "choose", "first: what's wrong")
	t.check(_buttons(s).any(func(b: Button) -> bool: return b.text == "Spam"), "message reasons offered")
	var first: Button = _buttons(s).filter(func(b: Button) -> bool: return b.text == "Harassment or bullying")[0]
	first.pressed.emit()
	t.eq(s.state, "sending", "sending while the request is out")
	s.close()
	t.check(is_instance_valid(s) and not s.is_queued_for_deletion(), "it can't be dismissed mid-request")
	for i in 4:
		await t.get_tree().process_frame
	t.eq(s.state, "failed", "a failed request is shown as failed")
	t.check(not _labels(s).contains("Report sent") and not _labels(s).contains("Receipt"), "never shown as reported")
	var again: Button = _buttons(s).filter(func(b: Button) -> bool: return b.text == "Try again")[0]
	again.pressed.emit()
	for i in 4:
		await t.get_tree().process_frame
	t.eq(s.state, "sent", "the retry went through")
	t.check(_labels(s).contains("R-ABCDEF1234"), "with the service's receipt")
	t.eq(calls, [["message", "harassment"], ["message", "harassment"]], "the same report, sent again")
	s.close()
	# without the service
	var saved_url := Cloud.base_url
	Cloud.base_url = ""
	var u := ReportSheet.open(host, {"kind": "player", "name": "Pip", "pid": ""})
	await t.get_tree().process_frame
	t.eq(u.state, "unavailable", "no service: reports are unavailable")
	t.check(_labels(u).contains("Nothing has been sent"), "and it says nothing was sent")
	Cloud.base_url = saved_url
	host.queue_free()


func test_block_hides_and_the_host_removes() -> void:
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 2)
	var c0: NetSession = rig.clients[0]
	var c1: NetSession = rig.clients[1]
	await rig.wait_until(func() -> bool: return c0.local_slot >= 0 and c1.local_slot >= 0 and rig.host.human_count() == 3, 300)
	await rig.frames(6)
	var saved: Array = (Save.data["blocked"] as Array).duplicate()
	# a guest blocks another guest: hidden on their screen, still in the party
	var e: Dictionary = c1.roster[c0.local_slot].duplicate()
	e["slot"] = c0.local_slot
	await SocialActions.block(c1, e)
	t.eq(SocialSafety.name_of(c1.roster[c0.local_slot]), SocialSafety.BLOCKED_NAME, "their name is hidden")
	t.check(SocialSafety.is_hidden(c1, "uid-c0"), "their chat and emotes are hidden")
	t.check(rig.host.roster[c0.local_slot] != null, "a guest can't remove anyone")
	Save.data["blocked"] = saved.duplicate()
	# the host blocks a guest: removed from the party
	var e2: Dictionary = rig.host.roster[c1.local_slot].duplicate()
	await SocialActions.block(rig.host, e2)
	await rig.frames(10)
	t.check(rig.host.roster[int(e2["slot"])] == null, "the host's block removes them")
	t.eq(String(rig.ended_reason.get(c1, "")), "kicked", "and they are told")
	Save.data["blocked"] = saved
	rig.teardown()
	await t.get_tree().process_frame   # (queued frees happen before the next test)
	await t.get_tree().process_frame
