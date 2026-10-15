extends "res://test_support/check_pedestrians.gd"
## Static review views only; no movement or timing acceptance.
func _run() -> void:
	scene=load("res://scenes/world/pedestrian_walk.tscn").instantiate()
	root.add_child(scene)
	if not scene.runtime_ok:push_error("N02 inspection scene rejected");quit(1);return
	scene.input_router.set_script(load("res://test_support/daehanmun_probe_input.gd"))
	scene.input_router.isolate_movement_bindings()
	for route in scene.pedestrian_bundle.routes:route_map[route.id]=route
	await _wait(1.)
	scene.set_pedestrians_running(false)
	for actor in scene.pedestrians:
		var row: Dictionary=actor.snapshot()
		var p:=_at(actor,row.station_m-5.)
		var delta: Vector3=actor.global_position-p
		await _pose(p,atan2(-delta.x,-delta.z)+deg_to_rad(30.))
		await _capture(row.route_id)
	var record:={"task":"N02","scope":"Paused review views with a 30-degree orbit; not motion or performance evidence.","bundle_sha256":FileAccess.get_sha256("res://data/generated/pedestrians.json"),"captures":capture_names,"npcs":_npc_rows()}
	FileAccess.open(output_path,FileAccess.WRITE).store_string(JSON.stringify(record)+"\n")
	scene.queue_free();quit(0)
