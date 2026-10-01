extends RefCounted
var t


func _scripts(path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(path.path_join(f))
	for d in dir.get_directories():
		_scripts(path.path_join(d), out)


func test_all_scripts_compile() -> void:
	var files: Array[String] = []
	_scripts("res://src", files)
	t.check(files.size() > 10, "found project scripts")
	for f in files:
		var s: GDScript = load(f)
		t.check(s != null and s.can_instantiate(), "compiles: " + f)
