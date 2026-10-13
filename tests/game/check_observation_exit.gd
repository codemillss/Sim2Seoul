extends SceneTree
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--failure-prefix="):
			scene.observe_prefix = argument.trim_prefix("--failure-prefix=")
	print("E03_EXPECTED_OBSERVATION_FAILURE")
	await scene._quit_project()
