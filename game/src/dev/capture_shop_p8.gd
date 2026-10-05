extends "res://src/dev/capture_v7_screens.gd"
## Development-only evidence for the Pass 8 Shop (created by capture.gd for
## --capture=shop_p8; src/dev/ is excluded from iOS exports), with the V7
## screens approach: device point scale and safe area, PNG + render report +
## <shot>_layout.json (measured control rects and issues) per shot.
##
## DEV FIXTURE, labelled on every shot: the test-double service
## (fake_commerce_service.gd) serves the offers on a fixed fixture clock
## (2026-10-06 21:45:51 UTC, then real time passing), and the simulated store
## (test_store_adapter.gd) answers with "(test price)" strings.  Nothing here
## is a real schedule run by a deployed service or a real App Store price.
## If every rotating skin has its art, the catalogue's own schedule is used;
## otherwise (before the skins stream's art merges) a fixture schedule over
## the rotating skins that have art, in the same 48 h / 00:00 UTC shape.
##
## Shots: Featured (rotating offers with countdowns, refresh line), its
## Always available block, an offer's detail (countdown + local departure),
## the Coin confirmation, the six Coin packs, All skins with a skin out of
## rotation and that skin's detail, (catalogue schedule only) a slot change
## at 00:00 UTC before/after, "Connect to refresh Shop", and service off.

const FakeService := preload("res://src/dev/fake_commerce_service.gd")
const TestStore := preload("res://src/dev/test_store_adapter.gd")
const FIXTURE_T := "2026-10-06T21:45:51Z"

var svc
var store
var fixture_kind := ""
var _offset_ms := 0.0
var _tag: Label


func _steps() -> Array:
	var all := [
		["shop", _setup], ["shop", _featured], ["shop", _featured_always], ["shop", _detail_offer], ["shop", _confirm_offer],
		["shop", _coins], ["shop", _all_skins_out], ["shop", _detail_out],
	]
	if fixture_kind == "catalogue schedule":
		all += [["shop", _change_before], ["shop", _change_after]]
	all += [["shop", _stale], ["shop", _service_off], ["end", _quit]]
	return all


func _fixture_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _offset_ms


func _set_fixture_time(ms: float) -> void:
	_offset_ms = ms - Time.get_unix_time_from_system() * 1000.0


func _ms(iso: String) -> float:
	return float(Catalogue.parse_utc_ms(iso))


func _tag_text() -> String:
	return "DEV FIXTURE: simulated service clock + %s, simulated store (test prices) · desktop render" % fixture_kind


func _label_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 110
	add_child(layer)
	_tag = UIKit.label(_tag_text(), 15, Color(1, 1, 1, 0.92), true, HORIZONTAL_ALIGNMENT_CENTER)
	var bg := PanelContainer.new()
	bg.add_theme_stylebox_override("panel", UIKit.box(Color(0.6, 0.1, 0.25, 0.82), 8, 0, Color.WHITE, 6))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(_tag)
	layer.add_child(bg)
	var vs := get_viewport().get_visible_rect().size
	bg.position = Vector2((vs.x - bg.get_combined_minimum_size().x) * 0.5, vs.y - bg.get_combined_minimum_size().y - 2.0)


func _all_have_art() -> bool:
	for id in Catalogue.rotation_ids():
		if not Catalogue.has_art(String(id)):
			return false
	return true


## Before the new outfits' art lands: the rotating skins that have art, in
## the schedule's shape (slots 1-2 from Oct 5, slots 3-4 from Oct 6, 48 h).
func _art_only_schedule() -> Array:
	var have: Array = Catalogue.rotation_ids().filter(func(id: String) -> bool: return Catalogue.has_art(id))
	var d0 := _ms("2026-10-05T00:00:00Z")
	var day := 86400000.0
	var out: Array = []
	for i in mini(4, have.size()):
		var s := d0 + (day if i >= 2 else 0.0)
		out.append({"offer_id": "fixture-%d" % (i + 1), "item_id": String(have[i]), "slot": i + 1, "price": Catalogue.price(String(have[i])),
			"revision": 1, "starts_at": s, "ends_at": s + 2.0 * day})
	return out


func _setup() -> float:
	fixture_kind = "catalogue schedule" if _all_have_art() else "art-only fixture schedule"
	_label_overlay()
	svc = FakeService.new()
	svc.install()
	store = TestStore.new()
	Purchases.use_adapter(store)
	svc.clock_ms = _fixture_now
	_set_fixture_time(_ms(FIXTURE_T))
	if fixture_kind != "catalogue schedule":
		svc.use_schedule(_art_only_schedule(), 1)
	cap.set("label", String(cap.get("label")) + " · " + _tag_text())
	_go_online()
	return 4.0


func _go_online() -> void:
	svc.gc_player = "T:_capture"
	await Cloud.sign_in()
	svc.grant(Cloud.profile_id(), 2650)
	await Wallet.refresh()
	await Offers.refresh()


func _shop() -> ShopScreen:
	return App.screen as ShopScreen


func _featured() -> float:
	ShopScreen.focus_section = "featured"
	App.goto(ShopScreen)
	_later(4.5, "shop_featured")
	return 5.0


func _featured_always() -> float:
	var s := _shop()
	if s:
		var a := s.find_child("AlwaysAvailable", true, false) as Control
		if a:
			s.scroll.scroll_vertical = int(a.position.y - 8.0)
	_later(1.4, "shop_featured_always")
	return 2.0


func _first_offer_item() -> String:
	var s := _shop()
	if s and s.rot_grid and s.rot_grid.get_child_count() > 0:
		return (s.rot_grid.get_child(0) as ShopScreen.ShopCard).id
	return "outfit:lantern_scout"


func _detail_offer() -> float:
	var s := _shop()
	if s:
		s.scroll.scroll_vertical = 0
		s._open_detail(_first_offer_item())
	_later(3.0, "shop_detail_offer")
	return 3.6


func _confirm_offer() -> float:
	var s := _shop()
	if s:
		s._on_action()
	_later(1.2, "shop_confirm_offer")
	return 1.8


func _coins() -> float:
	var s := _shop()
	if s:
		if not s._confirm.is_empty():
			(s._confirm["close"] as Callable).call()
		s._close_detail()
		s.select_section("coins")
	_later(1.6, "shop_coins")
	return 2.2


## A skin out of rotation: the fixture service takes one offer away (the
## same fixture time), so All skins and its sheet show the state.
func _all_skins_out() -> float:
	_full = svc.schedule.duplicate(true)
	var keep: Array = svc.schedule.filter(func(o: Dictionary) -> bool: return int(o["slot"]) != 4 or float(o["starts_at"]) > _fixture_now() + 3.0 * 86400000.0)
	svc.use_schedule(keep, int(svc.schedule_revision))
	Offers.refresh()
	var s := _shop()
	if s:
		s.select_section("outfits")
	_later(3.5, "shop_all_skins_out_of_rotation")
	return 4.0


func _out_item() -> String:
	for id in Catalogue.rotation_ids():
		if Catalogue.has_art(String(id)) and Offers.offer_for(String(id)).is_empty() and not Wallet.owns_id(String(id)):
			return String(id)
	return "outfit:varsity_sprinter"


func _detail_out() -> float:
	var s := _shop()
	if s:
		s._open_detail(_out_item())
	_later(2.6, "shop_detail_not_in_rotation")
	return 3.2


## Catalogue schedule only: six seconds before the 00:00 UTC change, then
## after it (the two changing cards replaced in place).
func _change_before() -> float:
	svc.use_schedule(FakeService.new().schedule, int(Catalogue.offers_section().get("schedule_revision", 1)))
	_set_fixture_time(_ms("2026-10-07T00:00:00Z") - 7000.0)
	Offers.refresh()
	var s := _shop()
	if s:
		s._close_detail()
		s.select_section("featured")
		s.scroll.scroll_vertical = 0
	_later(2.5, "shop_change_before")
	return 3.0


func _change_after() -> float:
	_later(5.5, "shop_change_after")
	return 6.0


var _full: Array = []


func _stale() -> float:
	var s := _shop()
	if s:
		s._close_detail()
	_stale_go()
	_later(2.4, "shop_stale_connect_to_refresh")
	return 3.0


## The full schedule back, one last answer cached, then a fresh run offline.
func _stale_go() -> void:
	if not _full.is_empty():
		svc.use_schedule(_full, int(svc.schedule_revision))
	await Offers.refresh()
	var s := _shop()
	svc.network_down = true
	Offers.reload_as_new_run()
	Offers.changed.emit()
	if s:
		s.select_section("outfits")
		s.select_section("featured")


func _service_off() -> float:
	svc.network_down = false
	FakeService.uninstall()
	Purchases.use_adapter(StoreAdapter.new())
	Wallet.state = Wallet.blank_state()
	Offers.reset()
	if _tag:
		_tag.text = "DEV: the test-double service removed (no service in the build: the shipped state today) · desktop render"
	ShopScreen.focus_section = "featured"
	App.goto(ShopScreen)
	_later(2.5, "shop_service_off")
	return 3.0
