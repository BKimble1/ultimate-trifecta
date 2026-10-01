extends RefCounted
var t


func test_layout_and_builder_load() -> void:
	var lay := CampusLayout.new()
	t.eq(lay.waters.size(), 6, "six water locations")
	t.check(lay.dorm_doors.size() >= 3, "multiple dorm entrances")
	var root := Node3D.new()
	t.add_child(root)
	var b := CampusBuilder.new(lay)
	b.build_collision(root)
	t.check(root.get_child_count() >= 2, "collision bodies built")
	root.queue_free()
