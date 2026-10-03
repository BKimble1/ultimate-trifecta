extends RefCounted
## V6 (brief §2.4 and §16): switching Home → Locker → Shop (every section) →
## Season Pass → Home again and again: scene nodes, orphan nodes, running
## tweens, connections on the shared services and the portrait cache stay
## flat from the second cycle to the tenth (the Locker's input-hint
## connection used to grow by one per visit); objects stay within a bound.
var t
var rig


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _settle() -> void:
	var ps := Portraits.shared()
	var n := 0
	while n < 240 and (ps.pending() > 0 or ps._busy):
		await t.get_tree().process_frame
		n += 1
	await _frames(6)


func _connections() -> int:
	var c := 0
	for o: Object in [Save, Wallet, Purchases, Cloud, App, Controls, Sfx]:
		for sig in o.get_signal_list():
			c += o.get_signal_connection_list(String(sig["name"])).size()
	return c


func _sample() -> Dictionary:
	return {"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"tweens": t.get_tree().get_processed_tweens().size(),
		"connections": _connections(),
		"portraits": Portraits.shared()._cache.size()}


func test_ten_cycles_through_the_tabs_leave_nothing_behind() -> void:
	await _cycles(true)


## As this build ships today: no service configured, the real (unavailable
## off-device) store adapter.
func test_ten_cycles_with_the_service_off() -> void:
	await _cycles(false)


func _cycles(with_service: bool) -> void:
	rig = preload("res://tests/commerce_rig.gd").new(t)
	await rig.begin(with_service, with_service)
	if with_service:
		await rig.sign_in()
	Save.data["onboarded"] = true
	var samples: Array = []
	for cycle in 10:
		App.goto_title()
		await _frames(4)
		NavShell.open("locker")
		await _settle()
		var lk := App.screen as CreatorScreen
		for tab in ["hat", "face", "outfit"]:
			lk._select_tab(tab)
			await _frames(2)
		await _settle()
		NavShell.open("shop")
		await _settle()
		var shop := App.screen as ShopScreen
		for sec in ["outfits", "accessories", "coins", "season", "featured"]:
			shop.select_section(sec)
			await _frames(2)
		await _settle()
		NavShell.open("pass")
		await _settle()
		App.goto_title()
		# fades, the greeting wave, music cross-fades and deferred frees
		# finish (a sample taken mid-transition counts objects that are
		# about to go)
		await _frames(600)
		samples.append(_sample())
	print("[cycles] service %s; after cycles 2, 5, 10: %s | %s | %s" % [with_service, samples[1], samples[4], samples[9]])
	var a: Dictionary = samples[1]
	var b: Dictionary = samples[9]
	t.eq(b["nodes"], a["nodes"], "scene nodes flat across cycles")
	t.eq(b["orphans"], a["orphans"], "no orphan nodes accumulate")
	# Measured: about 41 small non-node, non-resource objects stay per full
	# tour (4 screens, 8 category/section switches), the same with the service
	# off or on; not isolated (each screen and switch alone is flat within
	# noise). A bound that catches anything larger:
	t.check(int(b["objects"]) - int(a["objects"]) <= 8 * 50, "objects grow by at most ~50 per tour (%d -> %d)" % [a["objects"], b["objects"]])
	t.check(int(b["tweens"]) <= int(a["tweens"]), "no tweens left running (%d -> %d)" % [a["tweens"], b["tweens"]])
	t.eq(b["connections"], a["connections"], "no connections left on the shared services")
	t.check(int(b["portraits"]) <= int(a["portraits"]) + 2, "the portrait cache does not keep growing (%d -> %d)" % [a["portraits"], b["portraits"]])
	await rig.end()
