extends "res://../tests/game/check_game_underground_connections.gd"
func _run() -> void:
	hashes=_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/b1-lifecycle-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";root.add_child(scene);await _ticks(12)
	metro=scene.city_subway_service;visit=scene.interior_visit;helper=scene.game_underground_connections
	capsule_id=scene.player.get_node("CollisionShape").shape.get_instance_id();exterior_mask=scene.player.collision_mask;exterior_layer=scene.player.collision_layer;exterior_excludes=scene.rig._query.exclude.duplicate()
	if scene.menu.visible:scene.toggle_menu()
	scene._visit_street_detail("subway_cityhall");await _ticks(8);await _tap_e();outdoor_recovery=scene.player._outdoor_recovery.duplicate(true)
	await _place(helper.links[0].station_door);await _tap_e();await _ticks(5);_check("probe_explicit_fixture_enters_B1",visit.active)
	var result: Dictionary=await _lift(0);_check("probe_single_B1_lift",result.ok)
	_finish()
func _finish() -> void:
	if finished:return
	finished=true
	for action: StringName in held:Input.action_release(action)
	held.clear()
	var fixture: Node=root.get_node_or_null("TestOnlyHeldB1Input")
	if is_instance_valid(fixture):fixture.set_physics_process(false);fixture.harness=null;fixture.free()
	if is_instance_valid(_deadline):
		for connection: Dictionary in _deadline.timeout.get_connections():_deadline.timeout.disconnect(connection.callable)
		_deadline=null
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(_json({"task":"narrow_B1_elevator_lifecycle_probe","checks":checks,"scope":"Explicit observer fixture, one B1 entry/elevator only, no full game acceptance. Product sources unmodified. Diagnostic shutdown resource accounting only."}),"  "));file.close();scene.neighborhood_life.audio.stop();scene.neighborhood_life.audio.stream=null;await physics_frame;await physics_frame;scene.queue_free();await process_frame;await process_frame;quit()
