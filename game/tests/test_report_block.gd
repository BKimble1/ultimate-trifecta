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


## The chat drawer on a phone held sideways: the Quick Chat phrases are one
## sideways strip, so the messages keep most of the height; on an iPad they
## wrap.  Opening a message's actions (Mute, Report, Block) keeps that
## message in view instead of jumping to the newest one.
func test_drawer_fits_a_phone_and_keeps_actions_in_view() -> void:
	var root: Window = t.get_tree().root
	var saved_size: Vector2i = root.size
	var rig := NetRig.new()
	t.add_child(rig)
	rig.setup(20, 0, 0.0, 1)
	var c0: NetSession = rig.clients[0]
	await rig.wait_until(func() -> bool: return c0.local_slot >= 0 and rig.host.human_count() == 2, 300)
	var chat := rig.host.social.chat
	for i in 12:
		var m := chat._make(i + 1, c0.local_slot, QuickChat.Channel.PARTY, SocialProto.Kind.TEXT, 0, "Message number %d" % (i + 1), "")
		chat._insert(m)
	for sz in [Vector2i(2532, 1170), Vector2i(1334, 750), Vector2i(2048, 1536)]:
		root.size = sz
		await t.get_tree().process_frame
		var holder := Control.new()
		holder.set_anchors_preset(Control.PRESET_FULL_RECT)
		t.add_child(holder)
		var d := ChatDrawer.open(holder, rig.host, "lobby")
		for i in 4:
			await t.get_tree().process_frame
		var phone: bool = sz.y < 1536
		t.eq(d.quick_strip != null, phone, "%s: Quick Chat is %s" % [str(sz), "one sideways strip" if phone else "wrapped"])
		if phone:
			t.check(d.scroll.size.y >= d.panel.size.y * 0.35, "%s: the messages keep room (%d of %d)" % [str(sz), d.scroll.size.y, d.panel.size.y])
			t.check(d.quick_box.get_combined_minimum_size().x > d.quick_strip.size.x, "%s: (the strip scrolls sideways)" % str(sz))
		var sv := d.scroll.get_global_rect()
		t.check(sv.size.y > 0.0 and d.scroll.scroll_vertical > 0, "%s: the newest message shows first" % str(sz))
		# actions on the oldest message: it stays in view
		d._open_actions = 1
		d._refresh()
		for i in 4:
			await t.get_tree().process_frame
		var report: Button = null
		for b in _buttons(d):
			if (b as Button).text == "Report message":
				report = b
		t.check(report != null, "%s: the message has its actions" % str(sz))
		if report != null:
			var g := report.get_global_rect()
			t.check(d.scroll.get_global_rect().grow(1.0).encloses(g), "%s: and they are in view (%s in %s)" % [str(sz), str(g), str(d.scroll.get_global_rect())])
		# a new message arriving doesn't scroll them away
		chat._insert(chat._make(40, c0.local_slot, QuickChat.Channel.PARTY, SocialProto.Kind.TEXT, 0, "One more", ""))
		for i in 4:
			await t.get_tree().process_frame
		if report != null:
			var again: Button = null
			for b in _buttons(d):
				if (b as Button).text == "Report message":
					again = b
			t.check(again != null and d.scroll.get_global_rect().grow(1.0).encloses(again.get_global_rect()), "%s: still in view after a new message" % str(sz))
		chat.history.pop_back()
		d.close()
		holder.queue_free()
		await t.get_tree().process_frame
	root.size = saved_size
	rig.teardown()
	await t.get_tree().process_frame   # (queued frees happen before the next test)
	await t.get_tree().process_frame
