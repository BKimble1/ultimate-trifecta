class_name Albums
extends RefCounted
## Lobby music (2.2 build 16): the albums the player can put on in the
## Locker (Albums).  The chosen one plays wherever the menu music plays
## (home, the party lobby, the Locker, the Shop, the Season Pass); rounds
## and results keep their own music.  Every album is free and owned by
## everyone.  Each loops seamlessly (tools/make_loop.py: the loop end whose
## lead-in matches the loop start, crossfaded).
##   id, title, artist line, audio stream (assets/audio/<stream>.ogg),
##   cover picture for the sleeve ("" draws the game's own sleeve), and two
##   colours for the disc's gradient (from the cover)
const LIST := [
	{"id": "dorm_nights", "title": "Dorm Nights", "by": "Ultimate Trifecta", "stream": "music_menu", "cover": "", "col": Color("3fd0b8"), "col2": Color("1d2a6e")},
	{"id": "lobby_pluck", "title": "Lobby Pluck", "by": "Lobby Records", "stream": "album_pluck",
		"cover": "res://assets/albums/lobby_pluck.png", "col": Color("f0b36a"), "col2": Color("5a3418")},
	{"id": "cozy_christmas", "title": "Cozy Christmas Lobby", "by": "Lobby Records", "stream": "album_cozy",
		"cover": "res://assets/albums/cozy_christmas.png", "col": Color("ffd34d"), "col2": Color("e8508a")},
	{"id": "stardust", "title": "Stardust Reverie", "by": "Lobby Records", "stream": "album_stardust",
		"cover": "res://assets/albums/stardust.png", "col": Color("ffb35c"), "col2": Color("6fd6e0")},
]
const DEFAULT := "dorm_nights"


static func get_album(id: String) -> Dictionary:
	for a in LIST:
		if String(a["id"]) == id:
			return a
	return LIST[0]


static func current() -> String:
	var id := String(Save.get_setting("album", DEFAULT))
	return id if not get_album(id).is_empty() and String(get_album(id)["id"]) == id else DEFAULT


static func title_of(id: String) -> String:
	return String(get_album(id)["title"])


## The audio file the menu music plays now ("music_menu" for the default).
static func stream_key() -> String:
	return String(get_album(current())["stream"])


static func cover(id: String) -> Texture2D:
	var p := String(get_album(id)["cover"])
	return load(p) as Texture2D if p != "" and ResourceLoader.exists(p) else null


## Put an album on: saved, and the menu music changes now if it's playing.
static func choose(id: String) -> void:
	if String(get_album(id)["id"]) != id:
		return
	Save.set_setting("album", id)
	Sfx.restart_menu_music()
