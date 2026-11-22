extends SceneTree
## End-to-end check of party codes over the service relay, one side per
## process (tools/relay_e2e.sh runs a host and a guest against `wrangler dev`
## with its real Worker, Durable Object and local D1):
##
##   godot --headless --path game -s res://tests/relay_e2e.gd -- \
##     --no-app --no-gamecenter --service-url=http://127.0.0.1:PORT \
##     --relay-e2e=host|guest --e2e-dir=DIR
##
## DIR holds <role>.json ({token, expires_at, profile, player}) and
## admission_public.pem from the script, and the files the two sides use to
## take turns.  Both sides go through the game's own code: App's party
## code path (host_room_gamekit / join_room_gamekit), Cloud (rooms,
## admission), RelayTransport and NetSession.  Prints "E2E ..." lines; exits
## 0 when every check on this side passed.


func _initialize() -> void:
	# (loaded on the first frame, not preloaded: the game's scripts need the
	# autoloads, which exist only once the tree is up)
	await process_frame
	var side: Node = (load("res://tests/relay_e2e_side.gd") as GDScript).new()
	side.name = "RelayE2E"
	root.add_child(side)
