class_name SocialNet
extends RefCounted
## V6 party social traffic (chat and walk-around presence) beside the game
## protocol.  NetSession owns one and hands it every message in the
## SocialProto range (60-79); the logic lives in ChatChannel and HubSync so
## NetSession only needs a few hooks.

var session: NetSession
var chat: ChatChannel
var hub: HubSync


func _init(s: NetSession) -> void:
	session = s
	chat = ChatChannel.new(s)
	hub = HubSync.new(s)


func host_packet(peer: int, type: int, b: StreamPeerBuffer) -> void:
	match type:
		SocialProto.CHAT_SEND:
			chat.host_packet(peer, b)
		SocialProto.HUB_POSE:
			hub.host_packet(peer, b)


## From the bound host only (NetSession checks the sender).
func client_packet(type: int, b: StreamPeerBuffer) -> void:
	match type:
		SocialProto.CHAT, SocialProto.CHAT_HISTORY, SocialProto.CHAT_REJECT:
			chat.client_packet(type, b)
		SocialProto.HUB_STATE:
			hub.client_packet(b)


## Host: someone was seated (joined or reconnected).  Their recent party
## chat goes out on the next tick, after the roster that names its senders.
func on_welcome(peer: int, slot: int) -> void:
	if slot >= 0:
		_history_due[peer] = slot


var _history_due: Dictionary = {}


func tick(delta: float) -> void:
	hub.tick(delta)
	if not _history_due.is_empty():
		for peer in _history_due:
			chat.host_send_history(int(peer), int(_history_due[peer]))
		_history_due.clear()
