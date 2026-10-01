class_name LoadingScreen
extends Screen
## Brief loading card with a gameplay tip (no long intro movie).

var info: Dictionary = {}

func build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.18)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	move_child(bg, 0)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := UIKit.label("Sneaking out of Puddlesworth Hall…", 40, UIKit.TEXT, true, HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(l)
	var tip := UIKit.label(["Diving into water from a run is faster than climbing in.", "Carts can't go up stairs, through bollards or into the woods.",
		"A splash briefly marks that spot for the Night Watch — move on quickly!", "Getting caught keeps your splashes. You pop back near your last one.",
		"Four runners home before time runs out wins it for everyone."][randi() % 5], 26, UIKit.MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(tip)

func _go_back() -> void:
	pass
