extends SceneTree
## Exercise the real E04 reader without constructing geometry on rejected input.
func _initialize() -> void:
	var world: Dictionary = load("res://resources/world_config.tres").read_runtime()
	if not world.get("ok",false):
		print("E04_BUNDLE_RESULT "+JSON.stringify({"ok":false,"world_error":world.get("error")}))
		quit(1)
		return
	var result: Dictionary = load("res://scripts/scale_config.gd").new().read_scale(world)
	result.erase("data")
	print("E04_BUNDLE_RESULT "+JSON.stringify(result))
	quit(0)
