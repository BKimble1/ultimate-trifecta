class_name NetTransport
extends RefCounted
## Abstract packet transport. Peer ids are local handles only; game identity
## travels inside messages. Implementations: LoopbackTransport (tests, with
## latency/jitter/loss), EnetTransport (desktop/LAN dev clients),
## GameKitTransport (iOS internet play via Game Center GKMatch).

signal peer_joined(peer: int)
signal peer_left(peer: int)
signal packet_received(peer: int, data: PackedByteArray)

var is_host := false
var kind := "base"


func send(_peer: int, _data: PackedByteArray, _reliable: bool) -> void:
	pass


func broadcast(data: PackedByteArray, reliable: bool) -> void:
	for p in peers():
		send(p, data, reliable)


func peers() -> Array:
	return []


func poll(_dt: float) -> void:
	pass


func close() -> void:
	pass


func peer_uid(_peer: int) -> String:
	return ""


func peer_name(_peer: int) -> String:
	return ""


func is_open() -> bool:
	return true
