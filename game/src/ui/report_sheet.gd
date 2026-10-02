class_name ReportSheet
extends Control
## Report a player (their name or behaviour) or one typed message (V6),
## with honest states: pick a reason -> "Sending…" -> "Sent" with the
## service's receipt, shown only after the moderation service confirmed it.
## A failure says why and offers Try again; nothing is ever shown as
## reported unless the service has it.  Without the service there is no
## report button that pretends: the sheet says reports are unavailable and
## points to Mute and Block (and the support contact when one is set up).
## Reports reach the owner's moderation queue (service/tools/admin.mjs;
## docs/MODERATION.md).

signal finished(ok: bool)

const PLAYER_REASONS := [["name", "Offensive name"], ["harassment", "Harassment or bullying"], ["cheating", "Cheating"],
	["inappropriate", "Inappropriate behaviour"], ["other", "Something else"]]
const MESSAGE_REASONS := [["harassment", "Harassment or bullying"], ["inappropriate", "Inappropriate message"],
	["spam", "Spam"], ["other", "Something else"]]

var kind := "player"          # player | message
var target_name := ""
var pid := ""
var token := ""               # message reports: the signed message
var context: Dictionary = {}
var receipt := ""
var state := "choose"         # choose | sending | sent | failed | unavailable
## tests: replaces the service call: func(kind, reason) -> Dictionary
var send_fn: Callable
var _panel: PanelContainer
var _body: VBoxContainer
var _last_reason := ""


static func open(parent: Control, opts: Dictionary) -> ReportSheet:
	var s := ReportSheet.new()
	s.kind = String(opts.get("kind", "player"))
	s.target_name = String(opts.get("name", "this player"))
	s.pid = String(opts.get("pid", ""))
	s.token = String(opts.get("token", ""))
	s.context = opts.get("context", {})
	if opts.has("send_fn"):
		s.send_fn = opts["send_fn"]
	parent.add_child(s)
	if parent is Screen:
		(parent as Screen).push_modal(s, s.close)
	return s


static func available(p_pid: String, p_kind: String = "player") -> bool:
	if p_kind == "message":
		return Cloud.configured() and Cloud.has_feature("message_reports")
	return Cloud.configured() and p_pid != ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UIKit.theme()


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(UIKit.NAVY, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and state != "sending":
			close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = UIKit.panel(Color(UIKit.SLATE, 0.99), UIKit.R_PANEL, 28)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_panel)
	_body = UIKit.vbox(12)
	_body.custom_minimum_size = Vector2(minf(560.0, get_viewport().get_visible_rect().size.x * 0.7), 0)
	_panel.add_child(_body)
	if not send_fn.is_valid() and not available(pid, kind):
		_show_unavailable()
	else:
		_show_choose()
	Motion.appear(_panel, 8.0, UIKit.T_FAST)


func close() -> void:
	if state == "sending":
		return   # the request is out: wait for its answer
	finished.emit(state == "sent")
	queue_free()


func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()


func _title(t: String) -> void:
	var l := UIKit.styled(t, "headline")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)


func _text(t: String, col: Color = UIKit.IVORY_MUTED) -> Label:
	var l := UIKit.styled(t, "body", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)
	return l


func _show_choose() -> void:
	state = "choose"
	_clear()
	_title(("Report this message from %s" if kind == "message" else "Report %s") % target_name)
	_text("What's wrong? Our moderators review every report.")
	var reasons: Array = MESSAGE_REASONS if kind == "message" else PLAYER_REASONS
	var first: Button = null
	for rr in reasons:
		var reason: String = rr[0]
		var b := UIKit.secondary(String(rr[1]), Vector2(0, 68))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _send(reason))
		_body.add_child(b)
		if first == null:
			first = b
	var cancel := UIKit.quiet("Cancel", Vector2(200, 68))
	cancel.pressed.connect(close)
	_body.add_child(cancel)
	UIKit.soft_focus.call_deferred(first)


func _send(reason: String) -> void:
	_last_reason = reason
	state = "sending"
	_clear()
	_title("Sending your report…")
	_text("This takes a moment. Your report goes to the game's moderators.")
	var r: Dictionary
	if send_fn.is_valid():
		r = await send_fn.call(kind, reason)
	elif kind == "message":
		r = await Cloud.report_message(token, reason)
	else:
		r = await Cloud.report(pid, reason, "", context)
	if not is_inside_tree():
		return
	if bool(r.get("ok", false)) and String(r.get("receipt", "")) != "":
		receipt = String(r["receipt"])
		state = "sent"
		_clear()
		_title("Report sent")
		_text("Thanks. Our moderators will review it.\nReceipt: %s" % receipt, UIKit.IVORY)
		_text("You can also mute or block %s." % target_name)
		var done := UIKit.primary("Done", Vector2(220, 80), 26)
		done.pressed.connect(close)
		_body.add_child(done)
		UIKit.soft_focus.call_deferred(done)
	else:
		state = "failed"
		_clear()
		_title("The report wasn't sent")
		_text(Cloud.explain(r), UIKit.AMBER)
		var row := UIKit.hbox(12)
		var again := UIKit.secondary("Try again", Vector2(220, 72))
		again.pressed.connect(func() -> void: _send(_last_reason))
		row.add_child(again)
		var cancel := UIKit.quiet("Close", Vector2(180, 72))
		cancel.pressed.connect(close)
		row.add_child(cancel)
		_body.add_child(row)
		UIKit.soft_focus.call_deferred(again)


func _show_unavailable() -> void:
	state = "unavailable"
	_clear()
	_title("Reports aren't available here")
	_text("Reports go to the game's moderators through the online moderation service, which isn't available for this player in this party. Nothing has been sent.")
	_text("You can mute or block %s from their player card." % target_name)
	var support := Cloud.link("support_url")
	if support != "":
		_text("Need help? %s" % support)
	var ok := UIKit.secondary("OK", Vector2(200, 72))
	ok.pressed.connect(close)
	_body.add_child(ok)
	UIKit.soft_focus.call_deferred(ok)
