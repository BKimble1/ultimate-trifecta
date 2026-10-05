class_name SeasonScreen
extends Screen
## Season Pass (V6): Season 1 · After Hours.  Final release sweep layout
## (docs/final/season.md; the owner's screenshot IMG_3043 showed Record
## Breaker as a small swaying figure in the side panel above long state
## text, a dense header row, a description running below the panel, and the
## dorm's own runner barely visible behind the track):
##
##   top     Back, the navigation bar and the Coins chip (one 44 pt row)
##   stage   the left column is the dorm stage the Shop and Locker use
##           (App.stage, "wardrobe" framing): the selected reward on the
##           player's runner, head to shoes, at about twice the old preview's
##           height on a phone or more.  It starts in a well-lit
##           three-quarter view; drag sideways to turn it (StageTurn: one
##           finger owns the turn, a vertical drag or a tap does nothing);
##           under it three quiet tools: Run / Idle (an emote reward: Play),
##           a quarter Turn and Reset view.  The controller's right stick
##           turns it, R3 resets.  A slow sway shows the sides until the
##           player first turns it, never under Reduced Motion.  Coins,
##           badges, name cards and progress runs are drawn big in the same
##           place instead (the runner steps aside).  Previewing never
##           changes the saved look, inventory or a purchase: the saved look
##           is put back on the runner when the screen goes.
##   side    the selected reward next to the stage (Reward), or the
##           Challenges page (two 44 pt tabs): the tier and track, the name,
##           a state chip (Locked, Needs Premium, Ready to claim, Earned,
##           Claiming…, Claimed, Equipped), the requirements from the account
##           ("15,300 XP to unlock", "Needs Premium · 1,500 Coins"), the
##           flavour text lower in a finger-scrollable area, and
##           one action fixed at the bottom (Claim, Get / View Premium,
##           Equip, View in Locker, Show Tier N)
##   pass    one panel: the season (name, tier, XP to the next tier, Free
##           track or Premium) with Claim all; when claiming can't work, one
##           restrained status line under it ("Rewards unavailable right
##           now" and why, said once); the navigation chips (You're at, Next
##           reward, 30 / 50 / 100: a shorter form on a narrow panel); and the
##           tiers on one horizontal track (finger swipes scroll it from
##           anywhere; a swipe never claims): every tier column has its Free
##           reward above and its Premium reward below, both rows always
##           whole, sized from the height the panel leaves.  A run of
##           progress tiers (no reward on either track) is one narrow column
##           of numbered steps.
##
## States kept apart: progression (locked / earned), Premium entitlement,
## claimed, and whether claiming works right now (the service).  A reward can
## be earned while claiming is unavailable: it then reads "Earned", never
## "Ready to claim" over a dead button.  Rules shown and enforced by the
## service: XP only from eligible online rounds and challenges (never from
## Coins), no paid tier skips, Premium bought later lets you claim every
## Premium reward already earned, claiming is idempotent, claimed rewards
## are permanent.

## V6's fixed cell size (kept for callers); V7 cells size from the region.
const CELL := 132.0
const GAP := 8.0
const TIER_H := 28.0
## cell width : height
const CELL_ASPECT := 0.8
const CELL_MAX_H := 240.0
## the caption under a cell's art ("Outfit", "50 Coins")
const CAPTION_H := 24.0
const CAPTION_FS := 19
## the width of a run column relative to a reward column
const RUN_ASPECT := 0.56
## the stage column and the side panel's share of the content width
const FIG_SHARE := 0.23
const SIDE_SHARE := 0.25
## the figure's width (metres, arms and a run's stride) that must fit the
## stage column; the dorm stage fits the tallest look's height to the column
const FIG_W := 1.0
## the three-quarter start pose: radians from facing the camera
const START_TURN := 0.42
## the right stick's turn rate (radians a second at full tilt)
const STICK_TURN := 2.6
## reward kinds worn by the runner (shown on the stage)
const WORN := ["outfit", "hat", "shoes", "hair", "emote"]

var sid := "s1"
var track_scroll: ScrollContainer
var track_region: Control
## the pass panel: the season header, its status line, the navigation and
## the track
var track_panel: PanelContainer
var columns: Dictionary = {}          # tier -> Control
var cells: Array = []                 # RewardCell
var title_l: Label
var tier_lbl: Label
var xp_lbl: Label
var bar: ProgressBar
## "Season 1 · Premium" / "Season 1 · Free track"
var premium_chip: Label
var claim_all_btn: Button
## the status line when claiming is unavailable: its short headline and why
var status_row: Control
var banner: Label
var status_l: Label
var detail_box: VBoxContainer
var detail_panel: PanelContainer
var _legend: Array = []
var cell_size := CELL
var cell_w := CELL * CELL_ASPECT
var focus_tier := 1
var focus_track := "free"
var _busy := false
var _d: Dictionary = {}
## the stage column: the turn area (StageTurn) over the preview tools
var fig_zone: VBoxContainer
var turn: StageTurn
var plate: RewardArt
var tools: HBoxContainer
var pose_btn: Button
var turn_btn: Button
var reset_btn: Button
## the saved look when the screen opened (put back on the runner when it goes)
var saved: Dictionary = {}
## the item on the stage's runner ("" = none: the runner shows the saved look
## or steps aside for a picture)
var preview_id := ""
var preview_run := false
var _preview_emote := -1
var _preview_t := 0.0
var _restored := false
## Pass 8: the side panel's pages ("reward" | "challenges") and the
## Challenges page's parts (ChallengeCard per goal, the group headers)
var side_page := "reward"
var _side: VBoxContainer
var _tabs: Dictionary = {}
var challenge_page: VBoxContainer
var challenge_cards: Array = []
var _ch: Dictionary = {}
var _ch_timer: Timer
## Pass 9: the navigation row (NavChip: now, next reward, milestones by
## tier), the progress-run columns (ProgressRun) and every column once in
## track order
var nav_row: HBoxContainer
var now_chip: NavChip
var next_chip: NavChip
var milestone_chips: Dictionary = {}
var runs: Array = []
var _cols: Array = []
## the region the pass panel lives in (its width never grows)
var pass_host: Control


func build() -> void:
	sid = Catalogue.current_season_id()
	saved = Cosmetics.sanitize(Save.data["cosmetic"])
	if App.stage:
		App.stage.set_mode("wardrobe")
		App.sync_stage_local()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	TitleScreen.add_shades(self, 0.45, 0.0)
	back_action = _go_hub
	content.add_theme_constant_override("separation", UIKit.SP_M)
	nav_bar("pass")

	var mid := UIKit.hbox(UIKit.SP_L)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(mid)
	mid.add_child(_figure_zone())

	detail_panel = UIKit.panel(Color(UIKit.SLATE, 0.96), UIKit.R_PANEL, UIKit.PAD_PANEL + 2)
	detail_panel.name = "DetailPanel"
	var side_host := UIKit.region(detail_panel)
	side_host.name = "SideRegion"
	side_host.size_flags_horizontal = Control.SIZE_FILL
	mid.add_child(side_host)
	_build_detail()
	_build_challenges()

	track_panel = UIKit.panel(Color(UIKit.SLATE, 0.93), UIKit.R_PANEL, UIKit.PAD_PANEL)
	track_panel.name = "TrackPanel"
	var pv := UIKit.vbox(UIKit.SP_S)
	pv.name = "PassColumn"
	track_panel.add_child(pv)
	pv.add_child(_header())
	pv.add_child(_status_line())
	# the chips never widen the panel: they take a shorter form on a narrow
	# panel (_fit_nav), and scroll sideways only as a last resort
	var nav_strip := UIKit.scroll_area(true)
	nav_strip.name = "NavStrip"
	nav_strip.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	nav_strip.custom_minimum_size.y = UIKit.row_h()
	nav_strip.add_child(_nav_row())
	pv.add_child(nav_strip)
	var tv := UIKit.hbox(UIKit.SP_S)
	tv.name = "TrackView"
	tv.add_child(_track_legend())
	track_scroll = UIKit.scroll_area(true)
	track_scroll.name = "Track"
	track_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	track_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_scroll.follow_focus = true
	tv.add_child(track_scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(GAP))
	track_scroll.add_child(row)
	# Pass 9: a run of progress tiers is one column
	var run_at := {}
	for run in Economy.progress_runs(sid):
		run_at[int(run[0])] = run
	var past := 0
	for t in Catalogue.season_tiers(sid):
		var n := int(t["tier"])
		if n <= past:
			continue
		if run_at.has(n):
			row.add_child(_run_column(int(run_at[n][0]), int(run_at[n][1])))
			past = int(run_at[n][1])
		else:
			row.add_child(_column(t))
	# the track takes the height the header, status and navigation leave,
	# and never more
	track_region = UIKit.region(tv)
	track_region.name = "TrackRegion"
	pv.add_child(track_region)
	track_region.resized.connect(_fit_cells)
	track_scroll.resized.connect(_fit_cells)
	pass_host = UIKit.region(track_panel)
	pass_host.name = "PassRegion"
	mid.add_child(pass_host)
	pass_host.resized.connect(_fit_pass)
	mid.resized.connect(_fit_layout)
	_fit_layout()

	var st := season()
	var tier := maxi(1, Economy.tier_for_xp(sid, int(st["xp"])))
	var first := Wallet.claimable(sid) if bool(Wallet.can_transact()["ok"]) else []
	if not first.is_empty():
		focus(int(first[0]["tier"]), String(first[0]["track"]))
	else:
		# the next reward ahead (Pass 9: past progress tiers), else the last tier
		var nxt := Economy.next_reward_tier(sid, tier, bool(st["premium"]))
		var at := nxt if nxt > 0 else Economy.max_tier(sid)
		focus(at, best_track(at))
	_refresh()
	show_side("reward")
	_scroll_to.call_deferred(focus_tier)
	Wallet.changed.connect(_refresh)
	Wallet.challenge_completed.connect(_on_challenge_completed)
	Cloud.changed.connect(_refresh)
	if Cloud.signed_in():
		Wallet.refresh()
	focus_first(claim_all_btn if claim_all_btn.visible else _cell(focus_tier, focus_track))
	UIKit.fade_in(track_panel)
	UIKit.fade_in(detail_panel)
	turn.resized.connect(_frame_stage)
	get_viewport().size_changed.connect(_frame_stage)
	_frame_stage.call_deferred()


## Column widths from the allocated content width (never from what a child
## asks for): the stage column and the side panel take their shares, the
## pass panel the rest.  A 2D picture or a figure is fitted to the stage
## column; the side panel's labels wrap to its width.
func _fit_layout() -> void:
	var cw := content_size().x
	if cw < 10.0 or not is_instance_valid(fig_zone):
		return
	fig_zone.custom_minimum_size.x = clampf(roundf(cw * FIG_SHARE), 250.0, 380.0)
	(detail_panel.get_parent() as Control).custom_minimum_size.x = clampf(roundf(cw * SIDE_SHARE), 270.0, 380.0)


## The pass panel's inner width, from the region it lives in (never from
## the panel or its rows, which could keep a once-widened panel wide).
func pass_w() -> float:
	if not is_instance_valid(pass_host) or pass_host.size.x < 2.0:
		return 0.0
	var sb := track_panel.get_theme_stylebox("panel")
	return pass_host.size.x - sb.get_margin(SIDE_LEFT) - sb.get_margin(SIDE_RIGHT)


## Rows of the pass panel that size from its width: the navigation chips'
## form and the status line's wrapping width.
func _fit_pass() -> void:
	var w := pass_w()
	if w < 10.0:
		return
	_fit_nav()
	status_l.custom_minimum_size.x = maxf(10.0, w - 60.0)


# ------------------------------------------------------------------ stage
## The stage column: the turn area (the runner stands in it on the dorm
## stage; StageTurn owns the drag) with the big 2D picture for rewards that
## aren't worn, and the three preview tools under it.
func _figure_zone() -> Control:
	fig_zone = UIKit.vbox(UIKit.SP_S)
	fig_zone.name = "FigureZone"
	fig_zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
	turn = StageTurn.new()
	turn.name = "StageTurn"
	turn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	turn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turn.tooltip_text = "Drag to turn"
	turn.touched_first.connect(_on_turn_touched)
	turn.turned.connect(func(_d: float) -> void: _refresh_tools())
	fig_zone.add_child(turn)
	plate = RewardArt.new()
	plate.name = "Plate"
	plate.screen = self
	plate.big = true
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.visible = false
	turn.add_child(plate)
	tools = UIKit.hbox(UIKit.SP_S)
	tools.name = "PreviewTools"
	tools.alignment = BoxContainer.ALIGNMENT_CENTER
	# the row keeps its height when its tools are hidden (a picture has
	# nothing to turn): the stage framing never jumps between rewards
	tools.custom_minimum_size.y = UIKit.row_h()
	pose_btn = _tool("Run", "PreviewPose", _on_pose)
	turn_btn = _tool("Turn", "PreviewTurn", func() -> void: turn.step(1))
	reset_btn = _tool("Reset", "PreviewReset", func() -> void: turn.reset())
	for b in [pose_btn, turn_btn, reset_btn]:
		tools.add_child(b)
	fig_zone.add_child(tools)
	return fig_zone


## A quiet tool under the stage (the Shop's Idle / Run / Emote style): a
## short word on a whole 44 pt target.
func _tool(text: String, nm: String, act: Callable) -> Button:
	# content-sized (never trimmed), at least a 44 pt square
	var b := UIKit.quiet(text, Vector2(0, UIKit.row_h()), UIKit.T_CAPTION)
	b.name = nm
	b.pressed.connect(act)
	return b


## Tell the dorm stage where the stage column is: the runner is centred in
## it and fitted, hat to shoes, between its top and the tools (the tallest
## look's height), and narrow enough for the column's width.
func _frame_stage() -> void:
	if not App.stage or not is_instance_valid(turn) or not turn.is_inside_tree():
		return
	var vs := get_viewport().get_visible_rect().size
	var r := turn.get_global_rect()
	if r.size.x < 2.0 or r.size.y < 2.0:
		return
	var zw := r.size.x / maxf(1.0, vs.x)
	# DormStage fits a 1.45 m wide figure to the width share it is given:
	# give it the share at which an FIG_W wide figure fills the column
	var w := zw * 1.45 / FIG_W
	App.stage.set_wardrobe_region(r.get_center().x / maxf(1.0, vs.x), w, (r.position.y + UIKit.SP_S) / maxf(1.0, vs.y),
		(r.end.y - UIKit.SP_XS) / maxf(1.0, vs.y))


func _stage_char() -> CharacterView:
	return App.stage.local_character() if App.stage and is_instance_valid(App.stage) else null


## The saved look with `id` on (a hat, shoes, an outfit: the Shop's
## "try it on"); an emote plays on the saved look.
func preview_look(id: String) -> Dictionary:
	var look := saved.duplicate()
	if id != "" and Catalogue.is_runner_item(id) and not id.begins_with("emote:"):
		var s := Catalogue.split(id)
		look[String(s[0])] = String(s[1])
	return Cosmetics.sanitize(look)


## Is this reward shown on the runner (worn, with its art in the build)?
func worn_on_stage(r: Dictionary) -> bool:
	var id := String(r.get("item", ""))
	if id == "" or not Catalogue.is_runner_item(id):
		return false
	return WORN.has(String(Catalogue.split(id)[0])) and Catalogue.has_art(id) and _stage_char() != null


## Show the selected reward in the stage column: worn items on the runner
## (the turn and the tools work), anything else as a big picture (the
## runner steps aside), a progress run as its steps.
func _stage_show(r: Dictionary, run: Array = []) -> void:
	var v := _stage_char()
	var wear := run.is_empty() and worn_on_stage(r)
	plate.reward = {} if wear else r
	plate.run = run
	plate.state = "" if not run.is_empty() else display_state(focus_tier, focus_track)
	plate.visible = not wear
	plate.request()
	turn.enabled = wear
	for b in [pose_btn, turn_btn, reset_btn]:
		(b as Control).visible = wear
	if not wear:
		turn.release()
		preview_id = ""
		_preview_emote = -1
		if v:
			v.visible = false
		_refresh_tools()
		return
	var id := String(r["item"])
	v.visible = true
	var look := preview_look(id)
	if v.cosmetic != look:
		v.set_appearance(TC.Role.RUNNER, look)
		turn.settle()
	preview_id = id
	var eid := TC.EMOTES.find(String(Catalogue.split(id)[1])) if id.begins_with("emote:") else -1
	if eid != _preview_emote:
		_preview_emote = eid
		_preview_t = 0.0
		if eid >= 0:
			preview_run = false
			_play_emote()
	_refresh_tools()


func _play_emote() -> void:
	if _preview_emote >= 0 and App.stage and _stage_char() != null:
		App.stage.emote(Save.player_uid(), _preview_emote)


## Run / Idle for a worn item; an emote reward plays again.
func _on_pose() -> void:
	if _preview_emote >= 0:
		_preview_t = 0.0
		_play_emote()
	else:
		preview_run = not preview_run
	Sfx.play("click")
	_refresh_tools()


func _on_turn_touched() -> void:
	_refresh_tools()


func _refresh_tools() -> void:
	if not is_instance_valid(pose_btn):
		return
	if _preview_emote >= 0:
		pose_btn.text = "Play"
		pose_btn.accessibility_name = "Play the emote again"
	else:
		pose_btn.text = "Idle" if preview_run else "Run"
		pose_btn.accessibility_name = "Idle preview" if preview_run else "Run preview"
	turn_btn.accessibility_name = "Turn a quarter"
	reset_btn.accessibility_name = "Reset view"
	reset_btn.disabled = turn.at_start()
	for b in [pose_btn, turn_btn, reset_btn]:
		UIKit.face_of(b).queue_redraw()


func _process(delta: float) -> void:
	var v := _stage_char()
	if v == null or _restored:
		return
	if not turn.enabled:
		# a picture is shown: the runner stays aside (the stage re-places its
		# characters when its framing changes)
		v.visible = false
		return
	v.visible = true
	if has_modal():
		turn.release()
	elif Controls.active_joy >= 0:
		# controller: the right stick turns the runner (as in the Shop and Locker)
		var rx := InputRouter.radial(Vector2(Input.get_joy_axis(Controls.active_joy, JOY_AXIS_RIGHT_X), 0.0), 0.2, 0.95).x
		if rx != 0.0:
			turn.turn_by(rx * STICK_TURN * delta)
	var cam := App.stage.cam
	var base := atan2(-(cam.global_position.x - v.global_position.x), -(cam.global_position.z - v.global_position.z))
	v.set_facing(turn.facing(base + START_TURN))
	if _preview_emote >= 0:
		# the emote plays again every few seconds (Reduced Motion: once)
		_preview_t += delta
		var dur := float(DormStage.EMOTE_S.get(String(TC.EMOTES[_preview_emote]), 2.4)) + 1.2
		if _preview_t >= dur and not UIKit.reduced_motion():
			_preview_t = 0.0
			_play_emote()
		return
	if App.stage.emoting(Save.player_uid()):
		return
	var rs := v.rs.duplicate()
	rs["vel"] = (Basis(Vector3.UP, v.rotation.y) * Vector3(0, 0, -5.0)) if preview_run else Vector3.ZERO
	rs["state"] = TC.PState.ACTIVE
	rs["on_floor"] = true
	rs["pos"] = v.global_position
	v.apply_state(rs)


## Controller: R3 resets the view; the shoulders (Q / E) switch the side
## panel's pages.
func _unhandled_input(event: InputEvent) -> void:
	if not has_modal():
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed \
				and (event as InputEventJoypadButton).button_index == JOY_BUTTON_RIGHT_STICK and turn.enabled:
			turn.reset()
			get_viewport().set_input_as_handled()
			return
		for dir in ["menu_prev", "menu_next"]:
			if event.is_action_pressed(dir):
				show_side("challenges" if side_page == "reward" else "reward")
				UIKit.soft_focus(_tabs[side_page] as Button)
				get_viewport().set_input_as_handled()
				return
	super(event)


## Give the runner its saved look back (and its place, standing still): on
## Back, on any navigation away and when the screen goes for any other
## reason (a party invite, a match starting).  Previewing never saved
## anything; this only undoes the presentation.
func restore_stage() -> void:
	if _restored:
		return
	_restored = true
	turn.release()
	var v := _stage_char()
	if v == null:
		return
	v.visible = true
	v.set_appearance(TC.Role.RUNNER, Cosmetics.sanitize(Save.data["cosmetic"]))
	var rs := v.rs.duplicate()
	rs["vel"] = Vector3.ZERO
	rs["emote"] = -1
	v.apply_state(rs)


func _go_hub() -> void:
	restore_stage()
	NavShell.go_hub()


func confirm_leave(go: Callable) -> void:
	restore_stage()
	go.call()


func _exit_tree() -> void:
	restore_stage()


# ------------------------------------------------------------------ header
## The season in a compact hierarchy: "Season 1 · Premium" over the
## season's name and the tier, the bar with the XP to the next tier, and
## Claim all beside it.
func _header() -> Control:
	var h := UIKit.hbox(UIKit.SP_M)
	h.name = "Header"
	var v := UIKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	var s: Dictionary = Catalogue.season(sid)
	premium_chip = UIKit.styled("", "overline", UIKit.IVORY_MUTED)
	premium_chip.name = "TrackLine"
	UIKit.fit_text(premium_chip, [UIKit.T_OVERLINE, 15, 14])
	v.add_child(premium_chip)
	var tr := UIKit.hbox(UIKit.SP_M)
	title_l = UIKit.styled(String(s.get("name", "")), "headline")
	title_l.name = "SeasonName"
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.fit_text(title_l, [UIKit.T_HEADLINE, 24, 22])
	tr.add_child(title_l)
	tier_lbl = UIKit.styled("", "num", UIKit.TEAL, HORIZONTAL_ALIGNMENT_RIGHT)
	tier_lbl.add_theme_font_size_override("font_size", 24)
	tier_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	tr.add_child(tier_lbl)
	v.add_child(tr)
	var br := UIKit.hbox(UIKit.SP_S)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(40, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", UIKit.box(Color(UIKit.NAVY, 0.7), 5, 0, Color.WHITE, 0))
	bar.add_theme_stylebox_override("fill", UIKit.box(UIKit.TEAL, 5, 0, Color.WHITE, 0))
	bar.max_value = 1.0
	bar.step = 0.001
	br.add_child(bar)
	xp_lbl = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	xp_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	br.add_child(xp_lbl)
	v.add_child(br)
	claim_all_btn = UIKit.primary("Claim all", Vector2(0, UIKit.row_h()), UIKit.T_LABEL + 1)
	claim_all_btn.name = "ClaimAll"
	claim_all_btn.custom_minimum_size.x = UIKit.row_h() * 2.1
	claim_all_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	claim_all_btn.pressed.connect(_claim_all)
	h.add_child(claim_all_btn)
	return h


## Claiming unavailable: one restrained line under the header, said once
## ("Rewards unavailable right now" and the reason).  The Reward page then
## only says what it means for that reward ("It stays earned").
func _status_line() -> Control:
	var p := PanelContainer.new()
	p.name = "Status"
	p.add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.AMBER, 0.1), UIKit.R_SMALL, 0, Color.WHITE, 8))
	var h := UIKit.hbox(UIKit.SP_S)
	p.add_child(h)
	var ic := Icons.IconRect.new("info", UIKit.AMBER, 20)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := UIKit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	banner = UIKit.styled("Rewards unavailable right now", "label", UIKit.AMBER)
	banner.name = "Unavailable"
	banner.add_theme_font_size_override("font_size", 19)
	v.add_child(banner)
	status_l = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	status_l.name = "StatusReason"
	status_l.add_theme_font_size_override("font_size", 17)
	status_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status_l)
	p.visible = false
	status_row = p
	return p


func _track_legend() -> Control:
	var v := UIKit.vbox(int(GAP))
	v.name = "Legend"
	v.add_child(spacer(TIER_H))
	for spec in [["Free", UIKit.IVORY], ["Premium", UIKit.AMBER]]:
		var l := UIKit.styled(String(spec[0]), "overline", spec[1])
		l.custom_minimum_size = Vector2(0, CELL + 12.0)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		v.add_child(l)
		_legend.append(l)
	return v


## Cells fill the track's height exactly: both rows, the tier numbers, the
## gaps and the scrollbar fit the region the header, the status line and the
## navigation row leave (phone and iPad alike); width follows the height.
## No minimum beyond a 44 pt target.
func _fit_cells() -> void:
	if not is_instance_valid(track_region):
		return
	var h := track_region.size.y
	if h < 2.0:
		return
	var hbar := track_scroll.get_h_scroll_bar().get_combined_minimum_size().y
	var c := floorf((h - hbar - TIER_H - GAP * 2.0 - 2.0) * 0.5)
	c = clampf(c, UIKit.touch_min(), CELL_MAX_H)
	var w := floorf(clampf(c * CELL_ASPECT, UIKit.touch_min(), 210.0))
	# a narrow, tall track (the iPad, beside the stage and the side panel)
	# keeps three reward columns or more in view: cells get taller, not wider
	var tw := track_scroll.size.x
	if tw > 2.0:
		w = floorf(maxf(UIKit.touch_min(), minf(w, (tw + GAP) / 3.4 - GAP)))
	if absf(c - cell_size) < 1.0 and absf(w - cell_w) < 1.0:
		return
	cell_size = c
	cell_w = w
	for cell in cells:
		(cell as Control).custom_minimum_size = Vector2(w, c)
	for l in _legend:
		(l as Control).custom_minimum_size.y = c
	for run in runs:
		(run as Control).custom_minimum_size = Vector2(run_w(), c * 2.0 + GAP)
	for col in _cols:
		((col as Control).get_meta(&"tier_label") as Control).custom_minimum_size.x = run_w() if (col as Control).has_meta(&"run") else w
	_scroll_to.call_deferred(focus_tier)
## Pass 9: a progress-run column's width (narrower than a reward, never
## under 44 pt).
func run_w() -> float:
	return floorf(maxf(UIKit.touch_min(), cell_w * RUN_ASPECT))


func _column(t: Dictionary) -> Control:
	var tier := int(t["tier"])
	var v := UIKit.vbox(int(GAP))
	v.name = "Tier_%d" % tier
	var lbl := UIKit.styled("%d" % tier, "num", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	lbl.custom_minimum_size = Vector2(CELL * CELL_ASPECT, TIER_H)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(lbl)
	for track in ["free", "premium"]:
		var cell := RewardCell.new()
		cell.setup(self, tier, track)
		cell.pressed.connect(_on_cell.bind(tier, track))
		v.add_child(cell)
		cells.append(cell)
	columns[tier] = v
	v.set_meta(&"tier_label", lbl)
	v.set_meta(&"tiers", [tier, tier])
	_cols.append(v)
	return v


## Pass 9: one column for a run of progress tiers (no reward on either
## track): its tier range on top and one tall card with a step per tier.
func _run_column(first: int, last: int) -> Control:
	var v := UIKit.vbox(int(GAP))
	v.name = "Tiers_%d_%d" % [first, last]
	var lbl := UIKit.styled(("%d–%d" % [first, last]) if last > first else "%d" % first, "num", UIKit.IVORY_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	lbl.custom_minimum_size = Vector2(CELL * CELL_ASPECT * RUN_ASPECT, TIER_H)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIKit.fit_text(lbl, [UIKit.T_LABEL, 19, 17, 15])
	v.add_child(lbl)
	var run := ProgressRun.new()
	run.setup(self, first, last)
	run.pressed.connect(_on_run.bind(first))
	v.add_child(run)
	runs.append(run)
	for n in range(first, last + 1):
		columns[n] = v
	v.set_meta(&"tier_label", lbl)
	v.set_meta(&"tiers", [first, last])
	v.set_meta(&"run", run)
	_cols.append(v)
	return v


func _cell(tier: int, track: String) -> Control:
	for c in cells:
		if c.tier == tier and c.track == track:
			return c
	return null


## Pass 9: the progress-run column holding `tier` (null for a reward tier).
func run_of(tier: int) -> ProgressRun:
	for r in runs:
		if r.first <= tier and tier <= r.last:
			return r
	return null


## A tap on a cell selects it; a blank Free slot explains that tier's
## Premium reward instead.
func _on_cell(tier: int, track: String) -> void:
	if track == "free" and Economy.reward_at(sid, tier, "free").is_empty():
		focus(tier, "premium", true)
	else:
		focus(tier, track)


## Pass 9: a tap on a progress run explains it (the player's own tier when
## it is inside the run).
func _on_run(first: int) -> void:
	var r := run_of(first)
	var tier := clampi(current_tier(), r.first, r.last) if r != null else first
	focus(tier, "progress")


## Bring a tier's column into view (a little left of centre), clamped.
## Pass 9: `animate` (the navigation's jumps) glides there unless Reduced
## Motion is on; a finger on the track always wins.
func _scroll_to(tier: int, animate: bool = false) -> void:
	await get_tree().process_frame
	if not is_instance_valid(track_scroll) or not columns.has(tier) or TouchScroll.is_dragging(track_scroll):
		return
	var col: Control = columns[tier]
	var room := track_scroll.get_h_scroll_bar().max_value - track_scroll.size.x
	var to := clampf(col.position.x - track_scroll.size.x * 0.35, 0.0, maxf(0.0, room))
	# start at a column's edge: no half-cut column at the left of the track
	if to > 0.0 and to < room:
		var edge := 0.0
		for c in _cols:
			var cx := (c as Control).position.x
			if cx <= to + 1.0:
				edge = cx
		to = edge
	to = roundf(to)
	if animate and not UIKit.reduced_motion() and is_inside_tree():
		Motion.animate(track_scroll, "scroll_horizontal", int(to), Motion.CAMERA)
	else:
		Motion.stop(track_scroll, "scroll_horizontal")
		track_scroll.scroll_horizontal = int(to)


# ------------------------------------------------------------------ navigation
## Pass 9: the row above the track.  Every chip is a whole 44 pt target and
## only moves the track and the detail (no claim, no purchase here).  Final
## sweep: on a narrow pass panel the chips take a shorter form (one line:
## the flag and your tier, the star and the next reward's tier, the
## milestone's picture and number) rather than run off the panel; their
## accessibility names keep the whole sentence.
func _nav_row() -> Control:
	nav_row = UIKit.hbox(UIKit.SP_S)
	nav_row.name = "TrackNav"
	nav_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	now_chip = NavChip.new()
	now_chip.setup(self, "NavNow", "You're at", "Tier 1", "flag")
	now_chip.pressed.connect(jump_current)
	nav_row.add_child(now_chip)
	next_chip = NavChip.new()
	next_chip.setup(self, "NavNext", "Next reward", "", "star")
	next_chip.pressed.connect(jump_next_reward)
	nav_row.add_child(next_chip)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav_row.add_child(gap)
	var featured := Catalogue.season_featured(sid)
	for m in Catalogue.season_milestones(sid):
		var chip := NavChip.new()
		var skin := featured_skin(int(m)) if featured.has(int(m)) else ""
		chip.setup(self, "Milestone_%d" % int(m), "Tier", "%d" % int(m), "" if skin != "" else "medal", skin)
		chip.pressed.connect(jump_to.bind(int(m)))
		nav_row.add_child(chip)
		milestone_chips[int(m)] = chip
	nav_row.resized.connect(_fit_nav)
	return nav_row


## The chips' form for the row's width: the full two-line chips when they
## fit, else shorter ones.
func _fit_nav() -> void:
	var avail := pass_w()
	if not is_instance_valid(nav_row) or avail < 2.0:
		return
	var chips: Array = [now_chip, next_chip] + milestone_chips.values()
	for level in [0, 1, 2]:
		var need := float(nav_row.get_theme_constant("separation")) * float(nav_row.get_child_count() - 1)
		for c in chips:
			need += (c as NavChip).width_at(level)
		if need <= avail or level == 2:
			for c in chips:
				(c as NavChip).set_level(level)
			return


## The wallet's Season state, read once per frame (a refresh of 88 cells
## and their columns asks for it a few hundred times); a wallet change
## (_refresh) reads it again at once.
var _st: Dictionary = {}
var _st_frame := -1


func season() -> Dictionary:
	var f := Engine.get_process_frames()
	if f != _st_frame or _st.is_empty():
		_st = Wallet.season_state(sid)
		_st_frame = f
	return _st


## The tier the player's recorded Season XP reaches (at least 1).
func current_tier() -> int:
	return maxi(1, Economy.tier_for_xp(sid, int(season()["xp"])))


## Pass 9: the featured skin at a tier ("outfit:dr_doom"; "" when none).
func featured_skin(tier: int) -> String:
	for track in ["premium", "free"]:
		var id := String(Economy.reward_at(sid, tier, track).get("item", ""))
		if id.begins_with("outfit:"):
			return id
	return ""


## The cell a jump to `tier` selects: a progress tier's run, a featured
## skin, a reward ready to claim, else the Free reward (the Premium one when
## there is none).
func best_track(tier: int) -> String:
	if not Economy.has_reward(sid, tier):
		return "progress"
	if Catalogue.season_featured(sid).has(tier) and not Economy.reward_at(sid, tier, "premium").is_empty():
		return "premium"
	for track in ["free", "premium"]:
		if cell_state(tier, track) == "claimable":
			return track
	return "free" if not Economy.reward_at(sid, tier, "free").is_empty() else "premium"


func jump_to(tier: int) -> void:
	var t := clampi(tier, 1, Economy.max_tier(sid))
	focus(t, best_track(t))
	_scroll_to(t, true)


func jump_current() -> void:
	jump_to(current_tier())


func jump_next_reward() -> void:
	var st := season()
	var n := Economy.next_reward_tier(sid, current_tier(), bool(st["premium"]))
	jump_to(n if n > 0 else Economy.max_tier(sid))


func _refresh_nav() -> void:
	if not is_instance_valid(nav_row):
		return
	var st := season()
	var xp := int(st["xp"])
	var tier := current_tier()
	now_chip.set_text_lines("You're at", "Tier %d" % tier, "", "%d" % tier)
	now_chip.accessibility_name = "Go to your tier, Season Pass Tier %d of %d" % [tier, Economy.max_tier(sid)]
	var n := Economy.next_reward_tier(sid, tier, bool(st["premium"]))
	if n > 0:
		var need := maxi(0, Economy.tier_xp(sid, n) - xp)
		next_chip.set_text_lines("Next reward", "Tier %d · %s XP" % [n, Catalogue.format_coins(need)], "Tier %d" % n, "%d" % n)
		next_chip.accessibility_name = "Go to the next reward, Tier %d, %s Season XP away" % [n, Catalogue.format_coins(need)]
	else:
		next_chip.set_text_lines("Next reward", "All reached", "", "All")
		next_chip.accessibility_name = "Every reward tier reached. Go to Tier %d" % Economy.max_tier(sid)
	for m in milestone_chips:
		var chip: NavChip = milestone_chips[m]
		var skin := featured_skin(int(m)) if Catalogue.season_featured(sid).has(int(m)) else ""
		var what := Catalogue.display_name(skin) if skin != "" else _tier_summary(int(m))
		chip.reached = tier >= int(m)
		chip.accessibility_name = "Go to Tier %d: %s%s" % [int(m), what, ", reached" if tier >= int(m) else ""]
		chip.queue_redraw()
	_fit_nav()


## "Library Cardigan and Season 1 Finisher" (a tier's rewards, for screen readers).
func _tier_summary(tier: int) -> String:
	var parts: Array = []
	for track in ["premium", "free"]:
		var r := Economy.reward_at(sid, tier, track)
		if not r.is_empty():
			parts.append(reward_name(r))
	return " and ".join(parts) if not parts.is_empty() else "progress tier"


# ------------------------------------------------------------------ state
## Can rewards be claimed right now?  {ok, reason}: the reason is short and
## player-facing, said once on the status line (the release notes keep the
## technical cause: a build with no service URL is "off").
func claim_status() -> Dictionary:
	var can := Wallet.can_transact()
	if bool(can["ok"]):
		return {"ok": true, "reason": ""}
	var reason := ""
	match Wallet.service_state():
		"off":
			reason = "Season rewards and progress aren't available in this version."
		"signed_out":
			reason = "Sign in with Game Center to claim rewards."
		"syncing":
			reason = "Checking your account…"
		"offline":
			# the last sign-in failed: no network (the game's own "Check your
			# connection" message), or Game Center didn't sign in
			if Cloud.state == "error" and not Cloud.last_error.contains("connection"):
				reason = "Game Center didn't sign in. Your rewards are kept; try again later."
			else:
				reason = "You're offline. Claiming comes back when you reconnect."
		_:
			reason = String(can["message"])
	return {"ok": false, "reason": reason}


func _refresh() -> void:
	if not is_inside_tree():
		return
	_st_frame = -1
	var st := season()
	var xp := int(st["xp"])
	var prog := Economy.tier_progress(sid, xp)
	var s: Dictionary = Catalogue.season(sid)
	tier_lbl.text = "Tier %d / %d" % [maxi(1, int(prog["tier"])), Economy.max_tier(sid)]
	bar.value = float(prog["frac"])
	if int(prog["next"]) < 0:
		xp_lbl.text = "Every tier reached"
	else:
		xp_lbl.text = "%s / %s XP" % [Catalogue.format_coins(int(prog["into"])), Catalogue.format_coins(int(prog["into"]) + int(prog["need"]))]
	var prem := bool(st["premium"])
	premium_chip.text = "Season %d · %s" % [int(s.get("number", 1)), "Premium" if prem else "Free track"]
	premium_chip.add_theme_color_override("font_color", UIKit.AMBER if prem else UIKit.IVORY_MUTED)
	title_l.accessibility_name = "Season %d, %s" % [int(s.get("number", 1)), String(s.get("name", ""))]
	var n := Wallet.claimable(sid).size()
	var cs := claim_status()
	var ok := bool(cs["ok"])
	claim_all_btn.visible = ok
	status_row.visible = not ok
	banner.visible = not ok
	status_l.text = String(cs["reason"])
	claim_all_btn.text = ("Claim all (%d)" % n) if n > 0 else "Nothing to claim"
	claim_all_btn.disabled = n == 0 or _busy
	claim_all_btn.accessibility_name = ("Claim all, %d rewards" % n) if n > 0 else "Nothing to claim"
	tier_lbl.accessibility_name = "Season Pass tier %d of %d" % [maxi(1, int(prog["tier"])), Economy.max_tier(sid)]
	var tier := int(prog["tier"])
	for col in _cols:
		var span: Array = (col as Control).get_meta(&"tiers")
		var lbl: Label = (col as Control).get_meta(&"tier_label")
		lbl.add_theme_color_override("font_color", UIKit.TEAL if int(span[0]) <= tier and tier <= int(span[1]) else (UIKit.IVORY if int(span[1]) < tier else UIKit.IVORY_DIM))
	for c in cells:
		c.refresh()
	for r in runs:
		r.refresh()
	_refresh_nav()
	_refresh_detail()
	_refresh_challenges()


func cell_state(tier: int, track: String) -> String:
	var st := season()
	return Economy.cell_state(sid, tier, track, int(st["xp"]), bool(st["premium"]), st["claimed"])


## What a cell shows: the rules' state, except that a claimable reward is
## "earned" while claiming is unavailable (no claim affordance then).
## Pass 9: "pending" while its claim waits in the outbox (it finishes by
## itself), "service_update" when the game service's table doesn't have the
## tier yet (an older service: earned, never a Claim that does nothing).
func display_state(tier: int, track: String) -> String:
	var s := cell_state(tier, track)
	if s == "claimable":
		if Wallet.claim_pending(sid, tier, track):
			return "pending"
		if tier > int(season()["service_tiers"]):
			return "service_update"
		if not bool(claim_status()["ok"]):
			return "earned"
	return s


static func reward_name(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	if r.has("coins"):
		return "%s Coins" % Catalogue.format_coins(int(r["coins"]))
	return Catalogue.display_name(String(r["item"]))


static func reward_type(r: Dictionary) -> String:
	if r.has("coins"):
		return "Coins"
	return Catalogue.type_label(String(r.get("item", "")))


## The short caption under a cell's art: what it is.
static func reward_caption(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	if r.has("coins"):
		return "%s Coins" % Catalogue.format_coins(int(r["coins"]))
	return reward_type(r)




# ------------------------------------------------------------------ detail
var _from_empty := false


## Select a reward cell (or, Pass 9, a progress tier: track "progress",
## also chosen for any tier without a reward): the stage shows it and the
## side panel says what it is and needs.
func focus(tier: int, track: String, from_empty: bool = false) -> void:
	if not Economy.has_reward(sid, tier):
		track = "progress"
	elif track == "progress":
		track = best_track(tier)
	focus_tier = tier
	focus_track = track
	_from_empty = from_empty
	for c in cells:
		UIKit.set_selected(c, c.tier == tier and c.track == track)
	for r in runs:
		UIKit.set_selected(r, track == "progress" and r.first <= tier and tier <= r.last)
	_refresh_detail()
	show_side("reward")


## The Reward page: the tier and track, the name, a state chip, the
## requirements from the account, then (finger-scrollable) the description,
## what it includes and the rules; the reason an action is unavailable and
## the one action stay at the bottom, outside the scroll.
func _build_detail() -> void:
	var v := UIKit.vbox(UIKit.SP_S)
	v.name = "RewardPage"
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side_box().add_child(v)
	var over := UIKit.styled("", "overline", UIKit.IVORY_MUTED)
	over.name = "TierTrack"
	# (one line that never widens the panel: "Tiers 41–44 · Progress")
	UIKit.fit_text(over, [UIKit.T_OVERLINE, 15, 14])
	v.add_child(over)
	var name_l := UIKit.styled("", "headline")
	name_l.name = "RewardName"
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(name_l)
	var row := UIKit.hbox(UIKit.SP_S)
	row.name = "StateRow"
	var chip := StateChip.new()
	chip.name = "StateChip"
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chip)
	var type_l := UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	type_l.name = "RewardType"
	type_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIKit.fit_text(type_l, [UIKit.T_CAPTION, 18, 16])
	row.add_child(type_l)
	v.add_child(row)
	var state_l := UIKit.styled("", "body", UIKit.IVORY)
	state_l.name = "Requirement"
	state_l.add_theme_font_size_override("font_size", 21)
	state_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(state_l)
	var sc := UIKit.scroll_area()
	sc.name = "DetailInfo"
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	detail_box = UIKit.vbox(UIKit.SP_S)
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(detail_box)
	var blurb_l := UIKit.styled("", "body", UIKit.AMBER_HI)
	blurb_l.name = "Blurb"
	blurb_l.add_theme_font_size_override("font_size", 21)
	blurb_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(blurb_l)
	var incl_l := UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	incl_l.name = "Includes"
	incl_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(incl_l)
	var rule_l := UIKit.styled("", "caption", UIKit.IVORY_DIM)
	rule_l.name = "Rules"
	rule_l.add_theme_font_size_override("font_size", 18)
	rule_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(rule_l)
	# Pass 9: a featured skin whose art isn't in this build says so plainly
	# (drawn in the stage column's neutral picture); the label keeps the
	# text for screen readers and tests
	var note := UIKit.styled("", "caption", UIKit.IVORY_MUTED)
	note.name = "ArtNote"
	note.visible = false
	detail_box.add_child(note)
	# why the action is unavailable, and the action itself, stay at the
	# bottom of the panel, outside the scroll: never below the fold
	var reason_l := UIKit.styled("", "caption", UIKit.AMBER)
	reason_l.name = "Reason"
	reason_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(reason_l)
	var action := UIKit.secondary("", Vector2(0, UIKit.row_h()), UIKit.T_LABEL + 1)
	action.name = "DetailAction"
	action.pressed.connect(_on_detail_action)
	v.add_child(action)
	_d = {"over": over, "art": plate, "note": note, "name": name_l, "type": type_l, "chip": chip, "blurb": blurb_l, "includes": incl_l,
		"rules": rule_l, "state": state_l, "reason": reason_l, "action": action, "scroll": sc, "page": v}
	# wrapping labels get their width from the panel's allocated width, so
	# they never report a first-frame height for an unknown width
	detail_panel.resized.connect(_fit_detail)
	(detail_panel.get_parent() as Control).resized.connect(_fit_detail)
	v.resized.connect(_fit_detail)


## The side panel's inner width, from the region it lives in (which never
## grows), not from the panel itself: a label sized from the panel's own
## width kept a once-widened panel wide (Pass 9: a long action label had
## pushed it past the screen edge on the iPhone SE).
func _side_w() -> float:
	if not is_instance_valid(detail_panel):
		return 0.0
	var sb := detail_panel.get_theme_stylebox("panel")
	var host := detail_panel.get_parent() as Control
	var outer := host.size.x if host != null and host.size.x > 1.0 else detail_panel.size.x
	return outer - sb.get_margin(SIDE_LEFT) - sb.get_margin(SIDE_RIGHT) - 10.0


func _fit_detail() -> void:
	if _d.is_empty() or not is_instance_valid(detail_panel):
		return
	var w := _side_w()
	if w < 10.0:
		return
	for k in ["name", "state", "reason"]:
		(_d[k] as Control).custom_minimum_size.x = w
	# the scroll keeps room for its bar
	for k in ["blurb", "includes", "rules", "note"]:
		(_d[k] as Control).custom_minimum_size.x = w - 14.0
	# the action's label is set a little smaller rather than widening the
	# panel
	var action: Button = _d["action"]
	var f := action.get_theme_font("font")
	for fs in [UIKit.T_LABEL + 1, UIKit.T_LABEL, UIKit.T_CAPTION, 18]:
		action.add_theme_font_size_override("font_size", fs)
		if f.get_string_size(action.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 40.0 <= w + 10.0:
			break


func _refresh_detail() -> void:
	if _d.is_empty():
		return
	var action: Button = _d["action"]
	var reason_l: Label = _d["reason"]
	action.visible = true
	action.disabled = false
	reason_l.text = ""
	for k in ["note", "blurb", "includes", "rules"]:
		(_d[k] as Label).text = ""
	if focus_track == "progress":
		_refresh_progress_detail()
	else:
		_refresh_reward_detail()
	for k in ["blurb", "includes", "rules"]:
		(_d[k] as Label).visible = (_d[k] as Label).text != ""
	plate.note = (_d["note"] as Label).text
	plate.accessibility_name = plate.note
	reason_l.visible = reason_l.text != ""
	UIKit._apply(action, UIKit.AMBER if action.text == "Claim" and not action.disabled else UIKit.SLATE_HI,
		UIKit.NAVY if action.text == "Claim" and not action.disabled else UIKit.IVORY)
	action.accessibility_name = "%s, %s%s" % [(_d["name"] as Label).text, action.text, ", unavailable" if action.disabled else ""]
	plate.queue_redraw()
	_fit_detail()


## Is a claimed item on the player now (their saved look or profile)?
func is_equipped(id: String) -> bool:
	var parts := Catalogue.split(id)
	var field := String(parts[0])
	if Catalogue.is_profile_item(id):
		return String(Save.profile_style().get(field, "")) == id
	return Catalogue.is_runner_item(id) and String(Cosmetics.sanitize(Save.data["cosmetic"]).get(field, "")) == String(parts[1])


func _refresh_reward_detail() -> void:
	var r := Economy.reward_at(sid, focus_tier, focus_track)
	var st := display_state(focus_tier, focus_track)
	var cs := claim_status()
	var prem_track := focus_track == "premium"
	var over: Label = _d["over"]
	over.text = "Tier %d · %s" % [focus_tier, "Premium track" if prem_track else "Free track"]
	over.add_theme_color_override("font_color", UIKit.AMBER if prem_track else UIKit.IVORY_MUTED)
	_stage_show(r)
	(_d["name"] as Label).text = reward_name(r) if not r.is_empty() else "No Free reward at this tier"
	(_d["type"] as Label).text = reward_type(r) if not r.is_empty() else ""
	var id := String(r.get("item", ""))
	if id != "":
		(_d["blurb"] as Label).text = Catalogue.blurb(id) if Catalogue.kind(id) == "season_reward" else ""
		var inc := Catalogue.includes_text(id)
		(_d["includes"] as Label).text = ("Includes: " + inc) if inc != "" else ""
		if Catalogue.is_runner_item(id) and not Catalogue.has_art(id):
			(_d["note"] as Label).text = "Preview not available in this build."
	var action: Button = _d["action"]
	var state_l: Label = _d["state"]
	var reason_l: Label = _d["reason"]
	var chip: StateChip = _d["chip"]
	var xp := int(season()["xp"])
	var need := Economy.tier_xp(sid, focus_tier) - xp
	var into := "wallet" if r.has("coins") else "Locker"
	var lead := ("No Free reward at Tier %d. " % focus_tier) if _from_empty else ""
	var premium_line := "Needs Premium · %s Coins" % Catalogue.format_coins(Catalogue.price(String(Catalogue.season(sid).get("premium_item", ""))))
	var rules := "Season XP comes from online rounds and challenges. Tiers can't be bought."
	match st:
		"empty":
			chip.set_state("", "No reward", UIKit.IVORY_MUTED)
			state_l.text = "The Free track skips this tier."
			action.visible = false
		"locked":
			chip.set_state("lock", "Locked", UIKit.IVORY_MUTED)
			var lines: Array = [lead + "%s XP to unlock" % Catalogue.format_coins(maxi(0, need))]
			if prem_track and not bool(season()["premium"]):
				lines.append(premium_line)
				action.text = "View Premium"
			else:
				action.visible = false
			state_l.text = "\n".join(lines)
			(_d["rules"] as Label).text = rules
		"premium_locked":
			# reached: Premium (bought later too) unlocks it; the Shop's
			# Premium page says it unlocks everything already earned
			chip.set_state("lock", "Needs Premium", UIKit.AMBER)
			state_l.text = lead + "Reached Tier %d.\n%s" % [focus_tier, premium_line]
			action.text = "Get Premium" if bool(cs["ok"]) else "View Premium"
			if not bool(cs["ok"]):
				reason_l.text = "Premium can't be bought right now."
		"claimable":
			chip.set_state("plus", "Ready to claim", UIKit.AMBER)
			state_l.text = lead + "Earned at Tier %d. Claim it to add it to your %s." % [focus_tier, into]
			action.text = "Claim"
			action.disabled = _busy
		"earned":
			# claiming is unavailable (the status line says why, once): the
			# reward is not lost
			chip.set_state("check", "Earned", UIKit.TEAL)
			state_l.text = lead + "Earned at Tier %d. It stays earned: claim it when rewards are available." % focus_tier
			action.text = "Claim"
			action.disabled = true
		"pending":
			chip.set_state("rotate", "Claiming…", UIKit.AMBER)
			state_l.text = lead + "Earned at Tier %d. Your claim is on its way and finishes by itself, never twice." % focus_tier
			action.text = "Claiming…"
			action.disabled = true
		"service_update":
			chip.set_state("check", "Earned", UIKit.TEAL)
			state_l.text = lead + "Earned at Tier %d, not claimed yet. It stays earned." % focus_tier
			reason_l.text = "Claiming for this tier isn't open yet."
			action.text = "Claim"
			action.disabled = true
		"claimed":
			if r.has("coins"):
				chip.set_state("check", "Claimed", UIKit.TEAL)
				state_l.text = lead + "Claimed: added to your Coins."
				action.visible = false
			elif is_equipped(id):
				chip.set_state("check", "Equipped", UIKit.TEAL)
				state_l.text = lead + "Claimed. You're using it now."
				action.text = "View in Locker"
			else:
				chip.set_state("check", "Claimed", UIKit.TEAL)
				state_l.text = lead + "Claimed. It's yours to keep, in your Locker."
				action.text = "Equip" if Catalogue.is_runner_item(id) or Catalogue.is_profile_item(id) else "View in Locker"


## Pass 9: a progress tier: no reward here, what it leads to, where you are.
func _refresh_progress_detail() -> void:
	var r := run_of(focus_tier)
	var first := r.first if r != null else focus_tier
	var last := r.last if r != null else focus_tier
	var over: Label = _d["over"]
	over.text = ("Tiers %d–%d · Progress" % [first, last]) if last > first else "Tier %d · Progress" % first
	over.add_theme_color_override("font_color", UIKit.IVORY_MUTED)
	_stage_show({}, [first, last])
	(_d["name"] as Label).text = "Progress tiers" if last > first else "Progress tier"
	(_d["type"] as Label).text = "No reward"
	var xp := int(season()["xp"])
	var tier := current_tier()
	var chip: StateChip = _d["chip"]
	if tier > last:
		chip.set_state("check", "Reached", UIKit.TEAL)
	elif tier >= first:
		chip.set_state("flag", "You're here", UIKit.TEAL)
	else:
		chip.set_state("lock", "Ahead", UIKit.IVORY_MUTED)
	var nxt := last + 1 if last < Economy.max_tier(sid) else -1
	var leads := ""
	if nxt > 0:
		var parts: Array = []
		for track in ["free", "premium"]:
			var w := Economy.reward_at(sid, nxt, track)
			if not w.is_empty():
				parts.append("%s (%s)" % [reward_name(w), "Free" if track == "free" else "Premium"])
		leads = ("They count toward Tier %d: %s." if last > first else "It counts toward Tier %d: %s.") % [nxt, " and ".join(parts)]
	var where := ""
	if tier > last:
		where = "Reached."
	elif tier >= first:
		where = "You're at Tier %d." % tier
	else:
		where = "Tier %d needs %s more Season XP." % [first, Catalogue.format_coins(maxi(0, Economy.tier_xp(sid, first) - xp))]
	if nxt > 0 and tier < nxt:
		where += " %s more Season XP to Tier %d." % [Catalogue.format_coins(maxi(0, Economy.tier_xp(sid, nxt) - xp)), nxt]
	(_d["state"] as Label).text = ("%s %s" % [leads, where]).strip_edges()
	var action: Button = _d["action"]
	action.visible = nxt > 0
	action.text = "Show Tier %d" % nxt


func _on_detail_action() -> void:
	if focus_track == "progress":
		var r := run_of(focus_tier)
		var nxt := (r.last if r != null else focus_tier) + 1
		if nxt <= Economy.max_tier(sid):
			jump_to(nxt)
		return
	var st := display_state(focus_tier, focus_track)
	var id := String(Economy.reward_at(sid, focus_tier, focus_track).get("item", ""))
	match st:
		"premium_locked", "locked":
			if (_d["action"] as Button).text.ends_with("Premium"):
				ShopScreen.focus_section = "season"
				ShopScreen.focus_item = String(Catalogue.season(sid).get("premium_item", ""))
				NavShell.go("shop")
		"claimable":
			_claim([{"tier": focus_tier, "track": focus_track}])
		"claimed":
			if (_d["action"] as Button).text == "Equip":
				equip(id)
			else:
				NavShell.go("locker")


## Equip a claimed reward from the pass: the Locker's own save path (owned
## items only; never spends), the party sees it, the stage shows it.
func equip(id: String) -> void:
	if id == "" or not Wallet.owns_id(id):
		return
	var parts := Catalogue.split(id)
	if Catalogue.is_profile_item(id):
		Save.set_profile_style(String(parts[0]), id)
	elif Catalogue.is_runner_item(id):
		var look := Cosmetics.sanitize(Save.data["cosmetic"]).duplicate()
		look[String(parts[0])] = String(parts[1])
		var r := Save.apply_appearance(look)
		if not bool(r["ok"]):
			dialog("%s isn't in your Locker any more." % Catalogue.display_name(id))
			return
		saved = Cosmetics.sanitize(Save.data["cosmetic"])
		App.sync_stage_local()
		App.sync_cloud_appearance()
		if App.session and is_instance_valid(App.session) and App.session.phase == TC.Phase.LOBBY and App.session.mode != NetSession.Mode.OFFLINE:
			App.session.set_local_cosmetic(saved)
	else:
		return
	Save.save_now()
	Sfx.play("pickup")
	UIKit.toast(self, "Equipped", 1.6)
	_refresh_detail()


func _claim_all() -> void:
	_claim([])


func _claim(which: Array) -> void:
	if _busy or not bool(claim_status()["ok"]):
		return
	_busy = true
	_refresh()
	var r: Dictionary = await Wallet.claim(sid, which)
	_busy = false
	if not is_inside_tree():
		return
	if bool(r.get("ok", false)):
		var got: Array = r.get("claimed", [])
		if not got.is_empty():
			Sfx.play("pickup")
			UIKit.toast(self, ("Claimed %d reward%s" % [got.size(), "" if got.size() == 1 else "s"]) if got.size() != 1 else "Claimed!", 2.0)
		elif String(r.get("message", "")) == "":
			# another device or a retried request claimed it first, or this
			# screen was a step behind the service (the reply's snapshot has
			# already refreshed it)
			var sk: Array = r.get("skipped", [])
			var dup := sk.all(func(x: Variant) -> bool: return x is Dictionary and String(x.get("reason", "")) == "already_claimed")
			UIKit.toast(self, "Already claimed" if dup else "Nothing claimed: your Season Pass was refreshed", 2.0)
		if String(r.get("message", "")) != "":
			dialog(String(r["message"]))
	else:
		dialog(String(r.get("message", "")))
	_refresh()


## The selected reward's state on the Reward page: a small pill with an icon
## and a word (shape and word, never colour alone).
class StateChip:
	extends PanelContainer
	var icon: Icons.IconRect
	var text_l: Label
	var col := UIKit.IVORY

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := UIKit.hbox(6)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(h)
		icon = Icons.IconRect.new("lock", UIKit.IVORY, 18)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(icon)
		text_l = UIKit.styled("", "label", UIKit.IVORY)
		text_l.add_theme_font_size_override("font_size", 19)
		h.add_child(text_l)
		set_state("lock", "", UIKit.IVORY)

	func set_state(kind: String, t: String, c: Color) -> void:
		col = c
		icon.visible = kind != ""
		icon.kind = kind if kind != "" else "lock"
		icon.col = c
		icon.queue_redraw()
		text_l.text = t
		text_l.add_theme_color_override("font_color", c)
		var sb := UIKit.box(Color(c, 0.14), 999, 1, Color(c, 0.4), 10)
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		add_theme_stylebox_override("panel", sb)
		accessibility_name = t

## One reward cell on the track: its picture, what it is, and a small state
## mark in the corner (lock, plus, check).  Premium cells carry a thin gold
## edge; blank Free slots stay quiet.
class RewardCell:
	extends Button
	var screen: SeasonScreen
	var tier := 0
	var track := "free"
	var art: RewardArt
	var state := ""

	func setup(s: SeasonScreen, t: int, tr: String) -> void:
		screen = s
		tier = t
		track = tr
		name = "Cell_%d_%s" % [t, tr]
		var reward := Economy.reward_at(s.sid, t, tr)
		UIKit.make_card(self, Vector2(SeasonScreen.CELL * SeasonScreen.CELL_ASPECT, SeasonScreen.CELL), Color(UIKit.SLATE_HI, 0.96))
		var f := UIKit.face_of(self)
		if reward.is_empty():
			# a blank Free slot: quiet, aligned, still tappable (it explains
			# the tier's Premium reward)
			var q := UIKit.box(Color(UIKit.SLATE_LO, 0.18), UIKit.R_CARD, 0, Color.WHITE, 0)
			var qs := UIKit.box(Color(UIKit.SLATE_LO, 0.4), UIKit.R_CARD, 2, UIKit.TEAL, 0)
			f.styles = {"normal": q, "hover": q, "pressed": q, "disabled": q, "selected": qs}
		elif tr == "premium":
			var bg := UIKit.SLATE_HI.lerp(Color("6a5226"), 0.2)
			var n := UIKit.card_box(Color(bg, 0.97), UIKit.R_CARD, 1.0)
			n.border_width_top = 2
			n.border_color = Color(UIKit.AMBER, 0.55)
			var sel := UIKit.card_box(Color(bg.lightened(0.04), 0.97), UIKit.R_CARD, 1.0)
			sel.set_border_width_all(3)
			sel.border_color = UIKit.TEAL
			f.styles = {"normal": n, "hover": UIKit._with_bg(n, bg.lightened(0.05)), "pressed": UIKit.card_box(bg.darkened(0.08), UIKit.R_CARD, 0.0),
				"disabled": n, "selected": sel}
		art = RewardArt.new()
		art.screen = s
		art.cell = self
		art.reward = reward
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		f.add_child(art)
		art.request()

	func refresh() -> void:
		state = screen.display_state(tier, track)
		art.state = state
		art.queue_redraw()
		disabled = false
		var r := Economy.reward_at(screen.sid, tier, track)
		var label: String = {"locked": "locked", "premium_locked": "earned, needs Premium", "claimable": "ready to claim",
			"earned": "earned, claiming unavailable right now", "claimed": "claimed", "empty": "no Free reward",
			"pending": "earned, claim on its way", "service_update": "earned, the game service needs an update to claim it"}.get(state, state)
		accessibility_name = "Tier %d %s: %s, %s" % [tier, track, SeasonScreen.reward_name(r) if not r.is_empty() else "none", label]


## A reward's picture (cell or the stage column's plate): a cached portrait
## of the real runner for outfits (full body), hats (close) and shoes
## (feet), the refined emote glyph, the badge, the name card as equipped
## (your name), or a Coin pile; in a cell also its caption and state mark.
## Locked art stays readable (slightly muted), never darkened out.  Final
## sweep: `big` is the stage column's picture for rewards that aren't worn
## (and progress runs): drawn large on a soft scrim over the dorm.
class RewardArt:
	extends Control
	var screen: SeasonScreen
	var cell: Button
	var big := false
	var reward: Dictionary = {}
	## Pass 9: a progress run [first, last] (the detail's picture of it), and
	## a line drawn at the foot of the detail's picture ("Preview not
	## available in this build.")
	var run: Array = []
	var note := ""
	var state := ""
	var tex: Texture2D
	var pic_key := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func request() -> void:
		tex = null
		pic_key = ""
		if reward.has("item") and Catalogue.is_runner_item(String(reward["item"])):
			var id := String(reward["item"])
			var parts := Catalogue.split(id)
			var f := String(parts[0])
			if Cosmetics.entry(f, String(parts[1])).is_empty():
				queue_redraw()
				return
			var framing := CommerceArt.framing_for(f)
			if framing != "" and f != "emote":
				var look := CommerceArt.preview_look(Save.data["cosmetic"], f, String(parts[1]))
				var ps := Portraits.shared()
				pic_key = Portraits.key_for(look, TC.Role.RUNNER, framing)
				var t := ps.portrait(look, TC.Role.RUNNER, "pass:%s%s" % [id, "" if cell else ":plate"], framing)
				if ps.has_picture(pic_key):
					tex = t
				elif not ps.portrait_ready.is_connected(_on_pic):
					ps.portrait_ready.connect(_on_pic)
		queue_redraw()

	func _on_pic(k: String, t: Texture2D) -> void:
		if k == pic_key and is_instance_valid(self):
			tex = t
			queue_redraw()

	## The art's rect: the cell minus its padding and caption; on the stage
	## column a centred picture well (room above for the hat line, below
	## for the note).
	func art_rect() -> Rect2:
		if cell == null:
			if not big:
				return Rect2(Vector2.ZERO, size)
			# a well shaped for what it holds: a name card is a wide plate, a
			# progress run tall, everything else about square
			var w := size.x * 0.88
			var h := minf(size.y * 0.78, w * 1.25)
			if not run.is_empty():
				h = size.y * 0.86
			elif String(reward.get("item", "")).begins_with("card:"):
				h = minf(h, w * 0.62)
			elif not reward.is_empty():
				h = minf(h, w * 1.0)
			return Rect2(Vector2((size.x - w) * 0.5, (size.y - h) * 0.44), Vector2(w, h))
		var pad := 8.0
		return Rect2(Vector2(pad, pad), Vector2(size.x - pad * 2.0, size.y - pad * 2.0 - SeasonScreen.CAPTION_H))

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if cell == null:
			r = art_rect()
			draw_style_box(UIKit.box(Color(UIKit.NAVY, 0.5 if big else 0.38), UIKit.R_PANEL if big else UIKit.R_SMALL), r)
		if not run.is_empty() and screen != null:
			# the run's steps, tall, centred in the well
			var sr := r.grow(-14.0)
			var sw := minf(sr.size.x, 150.0)
			SeasonScreen.draw_steps(self, Rect2(Vector2(sr.get_center().x - sw * 0.5, sr.position.y), Vector2(sw, sr.size.y)),
				int(run[0]), int(run[1]), screen.current_tier(), true)
			return
		if cell == null and note != "":
			var nf := UIKit.font_w(500)
			var nfs := 17
			while nfs > 13 and nf.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x > r.size.x - 16.0:
				nfs -= 1
			draw_string(nf, Vector2(r.position.x + 8.0, r.end.y - 10.0), note, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 16.0, nfs, UIKit.IVORY_MUTED)
		if reward.is_empty():
			# a quiet dash, centred
			var c0 := size * 0.5
			draw_line(c0 + Vector2(-8, 0), c0 + Vector2(8, 0), Color(UIKit.IVORY, 0.25), 3.0, true)
			return
		var dim := state == "locked"
		var ar := art_rect() if not big else art_rect().grow(-18.0)
		var c := ar.get_center()
		var s := minf(ar.size.x, ar.size.y)
		if reward.has("coins"):
			CommerceArt.coin_pile(self, c, s * 0.28, int(reward["coins"]), dim)
		else:
			var id := String(reward["item"])
			var kind := String(Catalogue.split(id)[0])
			if kind == "badge":
				CommerceArt.badge(self, id, c, s * 0.44, dim)
			elif kind == "card":
				var w := ar.size.x * (0.96 if cell else 0.92)
				var h := minf(w / 2.5, ar.size.y * 0.8)
				var nm := Save.player_name()
				CommerceArt.name_card(self, Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), id, nm,
					String(Save.profile_style().get("badge", "")), int(clampf(h * 0.36, 14.0, 30.0)))
				if dim:
					draw_rect(Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), Color(UIKit.SLATE, 0.25))
			elif kind == "emote":
				var eid := TC.EMOTES.find(String(Catalogue.split(id)[1]))
				var col := UIKit.AMBER.lerp(Color("8d8a86"), 0.4) if dim else UIKit.AMBER
				Icons.draw_shape(self, Icons.emote_icon(eid) if eid >= 0 else "smile", c, s * (0.36 if cell else 0.4), col)
			elif tex != null:
				# a cell crops the portrait to fill it; the detail shows the
				# whole picture (the full figure, hat to shoes)
				var mod := Color(0.84, 0.84, 0.88) if dim else Color.WHITE
				if cell:
					_draw_cover(tex, ar, mod)
				else:
					draw_texture_rect(tex, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, mod)
			else:
				var col2 := Color(UIKit.IVORY, 0.1)
				draw_circle(c + Vector2(0, -s * 0.16), s * 0.13, col2)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.2, s * 0.32), c + Vector2(-s * 0.16, s * 0.02),
					c + Vector2(0, -s * 0.03), c + Vector2(s * 0.16, s * 0.02), c + Vector2(s * 0.2, s * 0.32)]), col2)
		if cell == null:
			return
		# caption: what it is
		var f := UIKit.font_w(600)
		var cap := SeasonScreen.reward_caption(reward)
		var fs := SeasonScreen.CAPTION_FS
		# a narrow cell sets the caption a size or two smaller, never trimmed
		while fs > 15 and f.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 10.0:
			fs -= 1
		var cy := size.y - 8.0 - SeasonScreen.CAPTION_H * 0.5 + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5
		draw_string(f, Vector2(5.0, cy), cap, HORIZONTAL_ALIGNMENT_CENTER, size.x - 10.0, fs,
			UIKit.IVORY if state != "locked" else UIKit.IVORY_MUTED)
		# state marks (shape + colour, never colour alone)
		var corner := Vector2(size.x - 18.0, 18.0)
		match state:
			"locked":
				draw_circle(corner, 11.0, Color(UIKit.NAVY, 0.8), true, -1.0, true)
				Icons.draw_shape(self, "lock", corner, 7.0, UIKit.IVORY_MUTED)
			"premium_locked":
				draw_circle(corner, 11.0, UIKit.AMBER, true, -1.0, true)
				Icons.draw_shape(self, "lock", corner, 7.0, UIKit.NAVY)
			"claimable":
				var g := UIKit.box(Color(0, 0, 0, 0), UIKit.R_CARD, 2, Color(UIKit.AMBER, 0.85), 0)
				g.draw_center = false
				draw_style_box(g, r.grow(-3.0))
				draw_circle(corner, 11.0, UIKit.AMBER, true, -1.0, true)
				Icons.draw_shape(self, "plus", corner, 7.0, UIKit.NAVY)
			"claimed":
				draw_circle(corner, 11.0, UIKit.TEAL, true, -1.0, true)
				Icons.draw_shape(self, "check", corner, 7.0, UIKit.NAVY)
			"pending":
				# Pass 9: a claim on its way (an amber ring, no fill)
				draw_arc(corner, 9.5, 0.0, TAU, 20, UIKit.AMBER, 2.5, true)
				Icons.draw_shape(self, "rotate", corner, 6.0, UIKit.AMBER)

	## A square portrait cropped to cover `rect` (no letterbox bars).
	func _draw_cover(t: Texture2D, rect: Rect2, mod: Color) -> void:
		var src := t.get_size()
		if src.x <= 0.0 or src.y <= 0.0:
			return
		var k := maxf(rect.size.x / src.x, rect.size.y / src.y)
		var vis := rect.size / k
		draw_texture_rect_region(t, rect, Rect2((src - vis) * 0.5, vis), mod)


## Pass 9: the steps of a progress run, top to bottom: a dot per tier
## (filled teal when reached, ringed at your tier, quiet ahead) joined by a
## line, each with its number.  `big`: the detail's picture.
static func draw_steps(ci: CanvasItem, rect: Rect2, first: int, last: int, tier: int, big: bool = false) -> void:
	var n := last - first + 1
	if n <= 0 or rect.size.y < 4.0:
		return
	var f := UIKit.font_num(700)
	var fs := 22 if big else 19
	if big and rect.size.x > rect.size.y * 1.4:
		# a wide, short picture (the detail): the steps run left to right
		var stepx := rect.size.x / float(n)
		var d := clampf(minf(stepx * 0.12, rect.size.y * 0.1), 5.0, 12.0)
		var cy := rect.position.y + rect.size.y * 0.4
		for i in n:
			var t := first + i
			var x := rect.position.x + stepx * (float(i) + 0.5)
			if i < n - 1:
				ci.draw_line(Vector2(x + d + 3.0, cy), Vector2(x + stepx - d - 3.0, cy), Color(UIKit.IVORY, 0.45 if t < tier else 0.18), 2.5, true)
			if t <= tier:
				ci.draw_circle(Vector2(x, cy), d, UIKit.TEAL, true, -1.0, true)
			else:
				ci.draw_arc(Vector2(x, cy), d, 0.0, TAU, 18, Color(UIKit.IVORY, 0.35), 2.0, true)
			if t == tier:
				ci.draw_arc(Vector2(x, cy), d + 5.0, 0.0, TAU, 22, UIKit.TEAL, 2.5, true)
			var col := UIKit.TEAL if t == tier else (UIKit.IVORY if t <= tier else UIKit.IVORY_MUTED)
			var tw := f.get_string_size("%d" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			ci.draw_string(f, Vector2(x - tw * 0.5, cy + d + 10.0 + f.get_ascent(fs)), "%d" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		return
	var step := rect.size.y / float(n)
	var dot := clampf(step * 0.16, 4.0, 11.0 if big else 9.0)
	var x := rect.get_center().x - 26.0 if big else rect.position.x + maxf(dot + 6.0, rect.size.x * 0.28)
	for i in n:
		var t := first + i
		var y := rect.position.y + step * (float(i) + 0.5)
		if i < n - 1:
			ci.draw_line(Vector2(x, y + dot + 2.0), Vector2(x, y + step - dot - 2.0), Color(UIKit.IVORY, 0.45 if t < tier else 0.18), 2.0, true)
		var reached := t <= tier
		if reached:
			ci.draw_circle(Vector2(x, y), dot, UIKit.TEAL, true, -1.0, true)
		else:
			ci.draw_arc(Vector2(x, y), dot, 0.0, TAU, 18, Color(UIKit.IVORY, 0.35), 2.0, true)
		if t == tier:
			ci.draw_arc(Vector2(x, y), dot + 4.0, 0.0, TAU, 22, UIKit.TEAL, 2.0, true)
		var col := UIKit.TEAL if t == tier else (UIKit.IVORY if reached else UIKit.IVORY_MUTED)
		ci.draw_string(f, Vector2(x + dot + 8.0, y + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5), "%d" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Pass 9: one column for a run of progress tiers (no reward on either
## track), as tall as both reward rows: a quiet card with a numbered step
## per tier (final sweep: without a "No reward" line in every run; the
## missing picture, the steps and the tap-through detail say it, and so does
## its accessibility name).  A tap explains it in the detail; a swipe that
## starts on it scrolls the track.
class ProgressRun:
	extends Button
	var screen: SeasonScreen
	var first := 0
	var last := 0
	var art: Control

	func setup(s: SeasonScreen, f: int, l: int) -> void:
		screen = s
		first = f
		last = l
		name = "Run_%d_%d" % [f, l]
		UIKit.make_card(self, Vector2(SeasonScreen.CELL * 0.5, SeasonScreen.CELL * 2.0 + SeasonScreen.GAP), Color(UIKit.SLATE_LO, 0.5))
		var face := UIKit.face_of(self)
		var q := UIKit.box(Color(UIKit.SLATE_LO, 0.32), UIKit.R_CARD, 0, Color.WHITE, 0)
		var qs := UIKit.box(Color(UIKit.SLATE_LO, 0.5), UIKit.R_CARD, 3, UIKit.TEAL, 0)
		face.styles = {"normal": q, "hover": q, "pressed": q, "disabled": q, "selected": qs}
		art = Control.new()
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.draw.connect(_draw_art)
		face.add_child(art)

	func refresh() -> void:
		var tier := screen.current_tier()
		var where := "reached" if tier > last else (("you're at Tier %d" % tier) if tier >= first else "ahead")
		accessibility_name = "%s: progress tier%s, no reward, %s" % [("Tiers %d to %d" % [first, last]) if last > first else "Tier %d" % first,
			"s" if last > first else "", where]
		art.queue_redraw()

	func _draw_art() -> void:
		var r := Rect2(Vector2.ZERO, art.size)
		SeasonScreen.draw_steps(art, Rect2(r.position + Vector2(6, 12), r.size - Vector2(12, 24)), first, last, screen.current_tier())


## Pass 9: a navigation chip on the row above the track: a small picture
## (an icon, or a featured skin's face) and two lines ("Next reward" /
## "Tier 40 · 1,050 XP").  A whole 44 pt target that only moves the view.
class NavChip:
	extends Button
	var screen: SeasonScreen
	var top_l: Label
	var main_l: Label
	var glyph := ""
	var skin := ""
	var reached := false
	var pic: Control
	var tex: Texture2D
	var pic_key := ""

	func setup(s: SeasonScreen, nm: String, top: String, main: String, icon_kind: String = "", skin_id: String = "") -> void:
		screen = s
		name = nm
		glyph = icon_kind
		skin = skin_id
		UIKit.make_card(self, Vector2(UIKit.touch_min(), UIKit.row_h()), Color(UIKit.SLATE_HI, 0.96))
		var m := MarginContainer.new()
		margins = m
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		m.add_theme_constant_override("margin_left", 10)
		m.add_theme_constant_override("margin_right", 14)
		m.add_theme_constant_override("margin_top", 4)
		m.add_theme_constant_override("margin_bottom", 4)
		UIKit.face_of(self).add_child(m)
		var h := UIKit.hbox(8)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		m.add_child(h)
		pic = Control.new()
		pic.custom_minimum_size = Vector2(1, 1) * clampf(UIKit.row_h() * 0.62, 30.0, 52.0)
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pic.draw.connect(_draw_pic)
		h.add_child(pic)
		var v := UIKit.vbox(0)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(v)
		top_l = UIKit.styled(top, "caption", UIKit.IVORY_MUTED)
		top_l.add_theme_font_size_override("font_size", 16)
		v.add_child(top_l)
		main_l = UIKit.styled(main, "label", UIKit.IVORY)
		main_l.add_theme_font_size_override("font_size", 20)
		v.add_child(main_l)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for n in m.find_children("*", "Control", true, false):
			(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		forms = [[top, main], [top, main], ["", main]]
		_apply_level()
		if skin != "":
			_request()

	## The chip's text at each level: [caption, line] for 0 (the whole
	## thing), 1 (shorter: "Next reward" / "Tier 45"), 2 (one short line on a
	## narrow row: "45").
	var forms: Array = []
	var level := 0
	var margins: MarginContainer

	## The picture's side and the chip's side margins at a level (the
	## one-line form is tighter).
	func pic_side(l: int) -> float:
		return clampf(UIKit.row_h() * (0.62 if l < 2 else 0.48), 26.0, 52.0)

	func pads(l: int) -> Vector2:
		return Vector2(10, 14) if l < 2 else Vector2(8, 10)

	func set_text_lines(top: String, main: String, mid: String = "", short: String = "") -> void:
		forms = [[top, main], [top, mid if mid != "" else main], ["", short if short != "" else main]]
		_apply_level()

	func set_level(l: int) -> void:
		level = clampi(l, 0, 2)
		_apply_level()

	func _apply_level() -> void:
		if forms.is_empty():
			return
		var f: Array = forms[level]
		top_l.text = String(f[0])
		top_l.visible = String(f[0]) != ""
		main_l.text = String(f[1])
		pic.custom_minimum_size = Vector2.ONE * pic_side(level)
		margins.add_theme_constant_override("margin_left", int(pads(level).x))
		margins.add_theme_constant_override("margin_right", int(pads(level).y))
		custom_minimum_size.x = width_at(level)

	## The chip's width at a level (the row picks the largest that fits).
	func width_at(l: int) -> float:
		if forms.is_empty():
			return UIKit.touch_min()
		var f: Array = forms[clampi(l, 0, 2)]
		var tw := main_l.get_theme_font("font").get_string_size(String(f[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, main_l.get_theme_font_size("font_size")).x
		if String(f[0]) != "":
			tw = maxf(tw, top_l.get_theme_font("font").get_string_size(String(f[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, top_l.get_theme_font_size("font_size")).x)
		var pd := pads(l)
		return maxf(UIKit.touch_min(), ceilf(pd.x + pic_side(l) + 8.0 + tw + pd.y + 2.0))

	## The featured skin's face: the cached head portrait when its art is
	## in the build (Portraits), a neutral head otherwise.
	func _request() -> void:
		var parts := Catalogue.split(skin)
		if Cosmetics.entry(String(parts[0]), String(parts[1])).is_empty():
			return
		var look := CommerceArt.preview_look(Save.data["cosmetic"], "outfit", String(parts[1]))
		var ps := Portraits.shared()
		pic_key = Portraits.key_for(look, TC.Role.RUNNER, "head")
		var t := ps.portrait(look, TC.Role.RUNNER, "pass:nav:%s" % skin, "head")
		if ps.has_picture(pic_key):
			tex = t
		elif not ps.portrait_ready.is_connected(_on_pic):
			ps.portrait_ready.connect(_on_pic)

	func _on_pic(k: String, t: Texture2D) -> void:
		if k == pic_key and is_instance_valid(self):
			tex = t
			pic.queue_redraw()

	func _draw_pic() -> void:
		var r := Rect2(Vector2.ZERO, pic.size)
		var c := r.get_center()
		var rad := minf(r.size.x, r.size.y) * 0.5
		if skin != "":
			pic.draw_circle(c, rad, Color(UIKit.NAVY, 0.7), true, -1.0, true)
			if tex != null:
				pic.draw_texture_rect(tex, r.grow(-2.0), false)
			else:
				# a neutral head and shoulders (the skin's art isn't in this build)
				pic.draw_circle(c + Vector2(0, -rad * 0.18), rad * 0.36, Color(UIKit.IVORY, 0.32), true, -1.0, true)
				pic.draw_arc(c + Vector2(0, rad * 0.9), rad * 0.62, PI * 1.08, PI * 1.92, 16, Color(UIKit.IVORY, 0.32), rad * 0.22, true)
			pic.draw_arc(c, rad - 1.0, 0.0, TAU, 32, UIKit.AMBER if reached else Color(UIKit.AMBER, 0.55), 2.0, true)
			return
		Icons.draw_shape(pic, glyph, c, rad * 0.8, UIKit.TEAL if glyph == "flag" else UIKit.AMBER)


# ------------------------------------------------------------------ challenges
## Pass 8 (docs/ECONOMY.md §10).  The side panel: a two-page switch
## ("Reward" | "Challenges", one 44 pt row of whole finger targets) over its
## pages.  Final sweep: Reward first (it names what the stage shows).
func _side_box() -> VBoxContainer:
	if _side != null:
		return _side
	_side = UIKit.vbox(UIKit.SP_S)
	_side.name = "Side"
	detail_panel.add_child(_side)
	var row := UIKit.hbox(UIKit.SP_S)
	row.name = "SideTabs"
	_side.add_child(row)
	for spec in [["reward", "Reward"], ["challenges", "Challenges"]]:
		var b := UIKit.quiet(String(spec[1]), Vector2(0, UIKit.row_h()), UIKit.T_LABEL)
		b.name = "Tab_" + String(spec[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(show_side.bind(String(spec[0])))
		row.add_child(b)
		_tabs[String(spec[0])] = b
	return _side


## Show one page of the side panel: "challenges" or "reward" (a tapped
## reward shows its detail; the Challenges tab comes back to the goals).
func show_side(page: String) -> void:
	side_page = page
	if is_instance_valid(challenge_page):
		challenge_page.visible = page == "challenges"
	if _d.has("page"):
		(_d["page"] as Control).visible = page == "reward"
	for k in _tabs:
		UIKit.set_selected(_tabs[k], k == page)
		(_tabs[k] as Button).accessibility_name = "%s%s" % [(_tabs[k] as Button).text, ", shown" if k == page else ""]
	if page == "challenges":
		_refresh_challenges()


## Challenges · Earn Season XP: the role line once, an honest status when
## the service can't show progress, then Daily and Weekly with their local
## reset time, one card per goal, and how pinning works.
func _build_challenges() -> void:
	challenge_page = UIKit.vbox(UIKit.SP_S)
	challenge_page.name = "ChallengesPage"
	challenge_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side_box().add_child(challenge_page)
	# one line each (they shrink to fit a narrow phone panel)
	var head := UIKit.styled("Challenges · Earn Season XP", "label", UIKit.IVORY)
	head.name = "ChallengesHeading"
	UIKit.fit_text(head, [UIKit.T_LABEL, UIKit.T_CAPTION, 18, 17])
	challenge_page.add_child(head)
	var role := UIKit.styled(ChallengeRules.ROLE_LINE, "caption", UIKit.IVORY_MUTED)
	role.name = "RoleLine"
	UIKit.fit_text(role, [UIKit.T_CAPTION, 18, 17, 16])
	challenge_page.add_child(role)
	var status := UIKit.styled("", "caption", UIKit.AMBER)
	status.name = "ChallengeStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.visible = false
	challenge_page.add_child(status)
	var sc := UIKit.scroll_area()
	sc.name = "ChallengeList"
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	challenge_page.add_child(sc)
	var list := UIKit.vbox(UIKit.SP_S)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var groups := {}
	for d in ChallengeRules.defs():
		var kind := String(d["period"])
		if not groups.has(kind):
			var gh := UIKit.styled("", "overline", UIKit.IVORY_MUTED)
			gh.name = "Group_" + kind
			UIKit.fit_text(gh, [UIKit.T_OVERLINE, 15, 14])
			list.add_child(gh)
			groups[kind] = gh
		var card := ChallengeCard.new()
		card.setup(self, String(d["id"]))
		card.pressed.connect(_toggle_pin.bind(String(d["id"])))
		list.add_child(card)
		challenge_cards.append(card)
	var hint := UIKit.styled("Tap a goal to pin it: it shows in your pause menu.", "caption", UIKit.IVORY_MUTED)
	hint.name = "PinHint"
	hint.add_theme_font_size_override("font_size", 18)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(hint)
	_ch = {"head": head, "role": role, "status": status, "scroll": sc, "list": list, "groups": groups, "hint": hint, "day": -1}
	detail_panel.resized.connect(_fit_challenges)
	# reset times and a new period are checked twice a minute (labels are
	# updated in place: nothing is rebuilt)
	_ch_timer = Timer.new()
	_ch_timer.wait_time = 30.0
	_ch_timer.timeout.connect(_on_challenge_tick)
	add_child(_ch_timer)
	_ch_timer.start()


## Wrapping labels get their width from the panel's allocated width.
func _fit_challenges() -> void:
	if _ch.is_empty() or not is_instance_valid(detail_panel):
		return
	var w := _side_w()
	if w < 10.0:
		return
	(_ch["status"] as Control).custom_minimum_size.x = w
	(_ch["hint"] as Control).custom_minimum_size.x = w - 24.0


func _refresh_challenges() -> void:
	if _ch.is_empty() or not is_inside_tree():
		return
	var st := Wallet.challenge_status()
	var status: Label = _ch["status"]
	status.text = String(st["text"])
	if Wallet.service_state() == "off":
		# the pass's status line already says why; this page says what it
		# means here (no developer wording on screen)
		status.text = "Preview only. No progress or Season XP is added right now."
	status.visible = status.text != ""
	var cards := Wallet.challenge_cards()
	var now := Wallet.server_now()
	for kind in _ch["groups"]:
		var end := 0
		for c in cards:
			if String(c["period"]) == kind:
				end = int(c["resets_at"])
		(_ch["groups"][kind] as Label).text = "%s · %s" % [ChallengeRules.period_label(String(kind)), ChallengeRules.reset_text(end, now)]
	for cc in challenge_cards:
		for c in cards:
			if String(c["id"]) == cc.id:
				cc.refresh(c, bool(st["live"]) and bool(c["known"]))
	_ch["day"] = ChallengeRules.day_start(now)


## A new UTC day while the screen is open: the old progress belongs to the
## old period, so ask the service for the new one.
func _on_challenge_tick() -> void:
	var day := ChallengeRules.day_start(Wallet.server_now())
	var rolled := int(_ch.get("day", -1)) >= 0 and day != int(_ch["day"])
	_refresh_challenges()
	if rolled and Cloud.signed_in() and not Wallet.syncing:
		Wallet.refresh()


func _toggle_pin(id: String) -> void:
	var was := Wallet.pinned_challenge_id() == id
	Wallet.pin_challenge("" if was else id)
	UIKit.toast(self, "Unpinned" if was else "Pinned: it shows in your pause menu", 1.6)


## A real milestone (the service reported a goal complete): said once.
func _on_challenge_completed(card: Dictionary) -> void:
	if not is_inside_tree():
		return
	UIKit.toast(self, "%s complete · %s" % [String(card.get("name", "")), ChallengeRules.xp_text(int(card.get("xp", 0)))], 2.4)
	Sfx.play("pickup")


## One goal: its name and task, its progress (bar and "4/6"), "+50 Season
## XP", a flag when pinned and a check when complete.  The whole card is one
## touch target that pins or unpins it (a swipe that starts on it scrolls
## the list instead).  Without the service's progress for this period the
## bar and count are hidden: the card is a readable preview, never a fake 0.
class ChallengeCard:
	extends Button
	var screen: SeasonScreen
	var id := ""
	var name_l: Label
	var task_l: Label
	var bar: ProgressBar
	var count_l: Label
	var xp_l: Label
	var mark: Icons.IconRect
	var _was_done := -1    # -1 before the first refresh: a goal already done doesn't pop
	var body: VBoxContainer
	var card: Dictionary = {}
	var live := false

	func setup(s: SeasonScreen, cid: String) -> void:
		screen = s
		id = cid
		name = "Challenge_" + cid
		UIKit.make_card(self, Vector2(0, UIKit.touch_min()), Color(UIKit.SLATE_HI, 0.96))
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var m := MarginContainer.new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		m.add_theme_constant_override("margin_left", 14)
		m.add_theme_constant_override("margin_right", 12)
		m.add_theme_constant_override("margin_top", 9)
		m.add_theme_constant_override("margin_bottom", 10)
		UIKit.face_of(self).add_child(m)
		body = UIKit.vbox(3)
		m.add_child(body)
		var r1 := UIKit.hbox(8)
		name_l = UIKit.styled("", "label", UIKit.IVORY)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIKit.fit_text(name_l, [UIKit.T_LABEL - 1, UIKit.T_CAPTION - 1, 17])
		r1.add_child(name_l)
		mark = Icons.IconRect.new("flag", UIKit.AMBER, 22)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.visible = false
		r1.add_child(mark)
		body.add_child(r1)
		task_l = UIKit.styled("", "caption", UIKit.IVORY_MUTED)
		task_l.add_theme_font_size_override("font_size", 18)
		UIKit.fit_text(task_l, [18, 16, 15])
		body.add_child(task_l)
		var r3 := UIKit.hbox(8)
		bar = ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.step = 0.001
		bar.custom_minimum_size = Vector2(36, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", UIKit.box(Color(UIKit.NAVY, 0.7), 4, 0, Color.WHITE, 0))
		bar.add_theme_stylebox_override("fill", UIKit.box(UIKit.TEAL, 4, 0, Color.WHITE, 0))
		r3.add_child(bar)
		count_l = UIKit.styled("", "num", UIKit.IVORY)
		count_l.add_theme_font_size_override("font_size", 19)
		r3.add_child(count_l)
		xp_l = UIKit.styled("", "caption", UIKit.AMBER, HORIZONTAL_ALIGNMENT_RIGHT)
		xp_l.add_theme_font_size_override("font_size", 17)
		r3.add_child(xp_l)
		body.add_child(r3)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for n in m.find_children("*", "Control", true, false):
			(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.minimum_size_changed.connect(_fit)
		_fit()

	func _fit() -> void:
		if is_instance_valid(body):
			custom_minimum_size.y = maxf(UIKit.touch_min(), body.get_combined_minimum_size().y + 19.0)

	func refresh(c: Dictionary, is_live: bool) -> void:
		card = c
		live = is_live
		name_l.text = String(c["name"])
		task_l.text = String(c["task"])
		var goal := maxi(1, int(c["goal"]))
		var prog := clampi(int(c["progress"]), 0, goal)
		var done := live and bool(c["completed"])
		var pinned := bool(c["pinned"])
		bar.visible = live
		count_l.visible = live
		if live:
			bar.value = float(prog) / float(goal)
			count_l.text = "%d/%d" % [prog, goal]
		xp_l.text = ("Done · " if done else "") + ChallengeRules.xp_text(int(c["xp"]))
		xp_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not live else Control.SIZE_FILL
		xp_l.add_theme_color_override("font_color", UIKit.TEAL if done else (UIKit.AMBER if live else UIKit.IVORY_MUTED))
		mark.visible = done or pinned
		mark.kind = "check" if done else "flag"
		mark.col = UIKit.TEAL if done else UIKit.AMBER
		mark.queue_redraw()
		# Pass 8: a goal completed while its card is on screen confirms with
		# the shared motion (once; nothing under Reduced Motion)
		if done and _was_done == 0:
			Motion.confirm(mark)
		_was_done = 1 if done else 0
		UIKit.set_selected(self, pinned)
		var prog_t := ("%d of %d" % [prog, goal]) if live else "progress not available"
		accessibility_name = "%s, %s challenge: %s. %s. %s%s. %s" % [String(c["name"]), ChallengeRules.period_label(String(c["period"])), String(c["task"]),
			prog_t, ChallengeRules.xp_text(int(c["xp"])), ", complete" if done else "", "Pinned; tap to unpin" if pinned else "Tap to pin"]
