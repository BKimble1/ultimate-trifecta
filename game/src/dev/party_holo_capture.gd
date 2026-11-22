extends "res://src/dev/lobby_light_capture.gd"
## (build 33) Development-only evidence (src/dev: never exported) for the
## party lobby's ready checks, the leader's crown, Leave party in the header
## and party members still in a round shown as holograms.  A party of three
## on the in-process loopback transport (no network; fictional names):
##   01_ready      the leader's (host's) lobby: the leader and Pip ready
##                 (checks beside their names), Rowan not yet, Start waiting
##   02_all_ready  everyone ready: Start is on, Not ready beside it
##   03_hologram   Pip left the round for the party lobby: Pip's lobby with
##                 the host and Rowan as holograms on their marks ("In a
##                 round" on their cards)
## Run with tools/capture_party_holo.sh OUT_DIR (956x440 pt at @2x under
## Xvfb, the Mobile renderer on llvmpipe: look and layout evidence only).

const PARTY := [
	["Pip", {"outfit": "pj", "pattern": "stripes", "color": "bubblegum", "skin": "tone3", "hair": "buns", "hair_color": "brown", "hat": "nightcap"}],
	["Rowan", {"outfit": "raincoat_explorer", "skin": "tone6", "hair": "curly", "hair_color": "black", "hat": "none"}],
]


func _run() -> void:
	await _wait(0.5)
	_setup_profile()
	Save.data["cosmetic"] = _look({"outfit": "moonwalk_cadet", "skin": "tone5", "hair": "tuft", "hair_color": "black"})
	App.goto_title()
	await _wait(1.0)
	# the party: this device hosts (and leads); two guests
	_hub = LoopbackTransport.Hub.new(9)
	var ht := LoopbackTransport.new(_hub, true)
	_host = NetSession.new()
	_host.name = "HoloCaptureHost"
	add_child(_host)
	_host.start_host(ht, "MOON42", Save.player_uid(), Save.party_name(), Save.data["cosmetic"], "any")
	App.session = _host
	for i in PARTY.size():
		var g: Array = PARTY[i]
		var ct := LoopbackTransport.new(_hub, false)
		var c := NetSession.new()
		c.name = "HoloCaptureGuest%d" % i
		add_child(c)
		c.start_client(ct, "MOON42", "guest-%d" % i, String(g[0]), _look(g[1]), "any")
		_clients.append(c)
		_hub.link(ht.id, ct.id)
		await _wait(0.3)
	App.show_lobby()
	await _wait(1.5)
	_host.set_local_ready(true)
	_clients[0].set_local_ready(true)
	await _wait(2.5)
	await _portraits_idle()
	await snap("01_ready")
	_clients[1].set_local_ready(true)
	await _wait(2.0)
	await snap("02_all_ready")
	# a round starts (nothing renders it here: the host's phase is enough),
	# and Pip leaves it for the party lobby
	_host.host_start_match(5)
	await _wait(1.0)
	_clients[0].leave_round()
	await _wait(1.0)
	# Pip's device: the party lobby, the others still in the round
	App.session = _clients[0]
	Save.data["uid"] = "guest-0"
	Save.data["cosmetic"] = _look(PARTY[0][1])
	App.show_lobby()
	await _wait(3.0)
	await _portraits_idle()
	await snap("03_hologram")
	printerr("CAPTURE-DONE")
	get_tree().quit()
