extends "res://../tests/game/check_terrain_integration.gd"
## Reproduce a paused original NPC in the geometry-only itinerary, then change
## only its collision layer and continue from the same physical player pose.
var actual_contacts: Array=[]
func _observe_contacts(_delta: float) -> void:
	for index: int in range(scene.player.get_slide_collision_count()):
		var collision: KinematicCollision3D=scene.player.get_slide_collision(index)
		var node: Object=collision.get_collider()
		if node is CharacterBody3D and actual_contacts.size()<20:actual_contacts.append({"collider":String((node as Node).get_path()),"collider_position":(node as Node3D).global_position,"player":scene.player.global_position,"point":collision.get_position(),"normal":collision.get_normal()})
func _run() -> void:
	physics_hz=30
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_physics_hz=physics_hz
	_settings_path="/private/tmp/exp21-block-"+str(OS.get_process_id())+".json";scene.exploration_settings_path=_settings_path;scene.quality_settings_path=_settings_path+".quality";root.add_child(scene);await _ticks(12)
	terrain=scene.terrain_surface;visit=scene.interior_visit
	if scene.menu.visible:scene.toggle_menu()
	scene.set_pedestrians_running(false);scene.set_vehicles_running(false);scene.set_speed_profile("turbo");scene.player.physics_stepped.connect(_observe_contacts)
	var original_poses: Array=[]
	for body: CharacterBody3D in scene.pedestrians:original_poses.append({"id":body.name,"point":body.global_position,"layer":body.collision_layer})
	var itinerary: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/walkable_itinerary.json"))
	var from: Array=itinerary.points_xz[8];var to: Array=itinerary.points_xz[9]
	await _pose("source_point8",Vector3(from[0],terrain.ground_y_world(Vector3(from[0],0,from[1]))+.08,from[1]))
	var target: Vector3=Vector3(to[0],0,to[1]);var before: bool=await _walk_targets("before_paused_original_collision",[target],true)
	await _capture_native("paused_original_blocks_source_route")
	var continuing_at: Vector3=scene.player.global_position
	for body: CharacterBody3D in scene.pedestrians:body.collision_layer=0
	scene.set_speed_profile("brisk");await _ticks(3)
	var after: bool=await _walk_targets("continue_without_original_collision",[target],false)
	await _capture_native("same_pose_continued_after_layer_only")
	var success: bool=not before and after and not actual_contacts.is_empty()
	var report: Dictionary={"task":"EXP21_PAUSED_NPC_FIXTURE_DIAGNOSIS","result":"PASS" if success else "FAIL","original_poses":original_poses,"native_dynamic_contacts":actual_contacts,"before_passed":before,"after_passed":after,"continuation_start_without_pose_assignment":continuing_at,"walks":walks,"captures":captures,"scope":"Explicit sourcepoint8 scenario start. Same sourcepoint9 target; before uses production21m/s, continuation2.24m/s. Only original NPC collision layers disabled between walks, no additional player/body position assignment, source geometry or terrain changes. Expected first failure is diagnostic, not final acceptance."}
	var file: FileAccess=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(_json(report),"  ")+"\n");file.close();print("EXP21_PAUSED_NPC_DIAGNOSIS ",report.result);quit(0 if success else 1)
