extends SceneTree
var scene: Node3D
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_settings_path="/private/tmp/exp21-probe-settings.json"
	root.add_child(scene)
	for tick in range(6):await physics_frame
	print("EXP21_STARTUP_PROBE ",JSON.stringify({"runtime_ok":scene.runtime_ok,"error":scene.exploration_error,"terrain":scene.terrain_surface.snapshot() if is_instance_valid(scene.terrain_surface) else {},"player":str(scene.player.global_position),"spawn_valid":scene.player.spawn_valid,"population":scene.neighborhood_population.snapshot().get("actual_walkers") if is_instance_valid(scene.neighborhood_population) else -1}))
	quit(0 if scene.runtime_ok else 1)
