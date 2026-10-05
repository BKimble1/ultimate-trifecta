extends RefCounted
## Shared setup for the commerce tests: an isolated Save profile and wallet
## file, the test-double service (src/dev/fake_commerce_service.gd) behind
## Cloud, and the simulated store (src/dev/test_store_adapter.gd) behind
## Purchases.  end() restores everything the tests touched.

const FakeService := preload("res://src/dev/fake_commerce_service.gd")
const TestStore := preload("res://src/dev/test_store_adapter.gd")

var t
var svc
var store
var _save_data: Dictionary
var _wallet_path := ""
var _wallet_state: Dictionary
var _offers_path := ""


func _init(test_runner) -> void:
	t = test_runner


func begin(with_service: bool = true, with_store: bool = true) -> void:
	_save_data = Save.data.duplicate(true)
	_wallet_path = Wallet.path
	_wallet_state = Wallet.state.duplicate(true)
	Wallet.path = "user://wallet_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Wallet.path))
	Wallet.state = Wallet.blank_state()
	Save.data = Save.default_profile()
	# Pass 8: the Shop's offers cache and clocks, isolated per test
	_offers_path = Offers.path
	Offers.ticks_override = Callable()
	Offers.wall_override = Callable()
	Offers.reset("user://shop_offers_test.json")
	Cloud.token = ""
	Cloud.profile = {}
	if with_service:
		svc = FakeService.new()
		svc.install()
		Cloud.state = "signed_out"
	else:
		svc = null
		FakeService.uninstall()
	if with_store:
		store = TestStore.new()
		Purchases.use_adapter(store)
	else:
		store = null
		Purchases.use_adapter(StoreAdapter.new())
	await frames(2)


func end() -> void:
	FakeService.uninstall()
	Purchases.use_adapter(StoreAdapter.new())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Wallet.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Wallet.path + ".tmp"))
	Wallet.path = _wallet_path
	Wallet.state = _wallet_state
	Offers.reset("user://shop_offers_test.json")
	Offers.ticks_override = Callable()
	Offers.wall_override = Callable()
	Offers.path = _offers_path
	Offers.reload_as_new_run()
	Wallet.syncing = false
	Wallet._auto_at = -1.0
	Save.data = _save_data
	if App.screen and is_instance_valid(App.screen):
		App.screen.queue_free()
	App.screen = null
	App._clear_background()
	await frames(2)


func frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## Sign in through the double and wait for the wallet snapshot.
func sign_in(gc: String = "T:_tester") -> void:
	svc.gc_player = gc
	Cloud.token = ""
	await Cloud.sign_in()
	await Wallet.refresh()
	await frames(2)


## Waits until `cond` is true (or `max_frames` pass).
func until(cond: Callable, max_frames: int = 120) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await t.get_tree().process_frame
	return bool(cond.call())
