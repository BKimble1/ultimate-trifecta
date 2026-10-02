class_name GameKitTransport
extends NetTransport
## Internet transport for iOS private rooms over a Game Center GKMatch
## (GodotApplePlugins). Game Center relays traffic when peers cannot connect
## directly. All plugin access is dynamic so the project parses everywhere.
## Peer ids are local handles mapped from GKPlayer.game_player_id.

const RELIABLE := 0
const UNRELIABLE := 1

var gk_match: Object = null
var _players: Dictionary = {}   # peer id -> GKPlayer
var _ids: Dictionary = {}       # game_player_id -> peer id
var _names: Dictionary = {}
var _next := 2
var last_error := ""


func _init(host: bool) -> void:
	is_host = host
	kind = "gamekit"


func bound() -> bool:
	return gk_match != null


func bind(m: Object) -> void:
	if gk_match == m:
		return
	gk_match = m
	m.connect("data_received", _on_data)
	m.connect("player_changed", _on_player_changed)
	m.connect("did_fail_with_error", func(msg: String) -> void: last_error = msg)
	var plist: Variant = m.get("players")
	if plist is Array:
		for pl in plist:
			_add(pl)


## Identity of a Game Center player: the team-scoped player ID (what the
## service verifies and binds admission to), else the game-scoped one.
func _pid(pl: Object) -> String:
	if pl == null:
		return ""
	var team := String(pl.get("team_player_id"))
	return team if team != "" else String(pl.get("game_player_id"))


func _add(pl: Object) -> int:
	var gid := _pid(pl)
	if gid == "":
		return -1
	if _ids.has(gid):
		return int(_ids[gid])
	var id := _next
	_next += 1
	_ids[gid] = id
	_players[id] = pl
	_names[id] = String(pl.get("display_name"))
	peer_joined.emit(id)
	return id


func _on_player_changed(pl: Object, connected: bool) -> void:
	if connected:
		_add(pl)
	else:
		var gid := _pid(pl)
		if _ids.has(gid):
			var id := int(_ids[gid])
			_ids.erase(gid)
			_players.erase(id)
			peer_left.emit(id)


func _on_data(data: PackedByteArray, pl: Object) -> void:
	var gid := _pid(pl)
	var id := int(_ids.get(gid, -1))
	if id < 0:
		id = _add(pl)
	if id >= 0:
		packet_received.emit(id, data)


func peers() -> Array:
	return _players.keys()


func peer_uid(peer: int) -> String:
	return _pid(_players.get(peer)) if _players.has(peer) else ""


func peer_name(peer: int) -> String:
	return String(_names.get(peer, ""))


func send(peer: int, data: PackedByteArray, reliable: bool) -> void:
	if gk_match == null or not _players.has(peer):
		return
	gk_match.call("send", data, [_players[peer]], RELIABLE if reliable else UNRELIABLE)


func broadcast(data: PackedByteArray, reliable: bool) -> void:
	if gk_match == null or _players.is_empty():
		return
	gk_match.call("send_data_to_all_players", data, RELIABLE if reliable else UNRELIABLE)


func close() -> void:
	if gk_match != null:
		gk_match.call("disconnect")
	gk_match = null
	_players.clear()
	_ids.clear()


func is_open() -> bool:
	return true
