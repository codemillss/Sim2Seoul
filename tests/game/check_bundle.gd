extends SceneTree
func _initialize() -> void:
	var config = load("res://resources/world_config.tres")
	var result: Dictionary = config.read_runtime()
	result.erase("world")
	print("E03_BUNDLE_RESULT "+JSON.stringify(result))
	quit(0)
