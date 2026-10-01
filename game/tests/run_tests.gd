extends SceneTree
## Headless test entry: godot --headless --path game -s res://tests/run_tests.gd [-- filter]

func _initialize() -> void:
	var runner := preload("res://tests/test_runner.gd").new()
	runner.name = "TestRunner"
	root.add_child(runner)
