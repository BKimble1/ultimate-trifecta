extends Node
## Development-only (src/dev is excluded from exports): renders the real
## cached item thumbnails through the shared Portraits renderer (the same
## path the wardrobe/Locker and Shop cards use: the item on a look, in the
## card's framing) and saves them as one labelled contact sheet.
##   tools/gd.sh --path game res://src/dev/thumb_sheet.tscn -- --out=FILE.png [--fields=outfit,hat,shoes] [--keys=a,b]
## Needs a display (xvfb-run on Linux): Portraits never renders headless.

const FRAMING := {"outfit": "body", "hat": "head", "shoes": "feet"}
## the look each item is shown on (the default runner, no hat for outfits,
## so an outfit's own headwear shows as it does on a bare-headed runner)
const BASE := {"hat": "none"}

var out := ""
var fields: Array = ["outfit", "hat", "shoes"]
var only: Array = []
var _items: Array = []   # [field, key, cache key]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.split("=")[1]
		elif a.begins_with("--fields="):
			fields = Array(a.split("=")[1].split(","))
		elif a.begins_with("--keys="):
			only = Array(a.split("=")[1].split(","))
	if out == "":
		out = OS.get_user_data_dir().path_join("thumbs.png")
	await get_tree().process_frame
	var ps := Portraits.shared()
	await get_tree().process_frame
	for f in fields:
		for k in Cosmetics.keys_of(f):
			if not only.is_empty() and not k in only:
				continue
			var app := Cosmetics.DEFAULT.duplicate()
			app.merge(BASE, true)
			app[f] = k
			if f == "hat":
				app["hair"] = "bob"
			_items.append([f, k, app])
	# in batches: the renderer's queue is bounded (Portraits.MAX_QUEUE)
	var done: Array = []
	var i := 0
	while i < _items.size():
		var batch := _items.slice(i, i + 12)
		for it in batch:
			ps.portrait(it[2], TC.Role.RUNNER, "sheet:%s:%s" % [it[0], it[1]], FRAMING[it[0]])
		var guard := 0
		while guard < 3000:
			await get_tree().process_frame
			guard += 1
			var all := true
			for it in batch:
				if not ps.has_picture(Portraits.key_for(it[2], TC.Role.RUNNER, FRAMING[it[0]])):
					all = false
			if all:
				break
		await RenderingServer.frame_post_draw
		for it in batch:
			var key := Portraits.key_for(it[2], TC.Role.RUNNER, FRAMING[it[0]])
			var tex: AtlasTexture = ps.portrait(it[2], TC.Role.RUNNER, "", FRAMING[it[0]])
			var img: Image = tex.atlas.get_image().get_region(Rect2i(tex.region))
			done.append([it[0], it[1], img, ps.has_picture(key)])
		i += 12
	_save(done)
	get_tree().quit()


func _save(done: Array) -> void:
	var cols := 6
	var cell := Portraits.SIZE
	var rows := int(ceil(done.size() / float(cols)))
	var sheet := Image.create(cols * cell, rows * (cell + 28), false, Image.FORMAT_RGBA8)
	sheet.fill(Color("1b2440"))
	var lines: Array = []
	for n in done.size():
		var d: Array = done[n]
		var img: Image = d[2]
		img.convert(Image.FORMAT_RGBA8)
		var bg := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
		bg.fill(Color("2c3a5c"))
		bg.blend_rect(img, Rect2i(0, 0, cell, cell), Vector2i.ZERO)
		sheet.blit_rect(bg, Rect2i(0, 0, cell, cell), Vector2i((n % cols) * cell, (n / cols) * (cell + 28)))
		lines.append("%d: %s:%s%s" % [n, d[0], d[1], "" if d[3] else " (placeholder)"])
	sheet.save_png(out)
	var f := FileAccess.open(out.get_basename() + ".txt", FileAccess.WRITE)
	f.store_string("\n".join(PackedStringArray(lines)))
	printerr("THUMBS %s %d items" % [out, done.size()])
