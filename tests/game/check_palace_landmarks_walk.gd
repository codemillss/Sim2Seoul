extends "res://test_support/check_walkable_milestone.gd"
## L02 uses the frozen W04 observer and itinerary with an explicit new scene.
func _run() -> void:
	itinerary=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/walkable_itinerary.json"))
	if itinerary.get("task")!="W04":push_error("W04 itinerary required");quit(1);return
	scene=load("res://scenes/world/palace_landmarks.tscn").instantiate();root.add_child(scene)
	if not scene.runtime_ok:push_error("W03 production scene did not load");quit(1);return
	scene.input_router.set_script(load("res://test_support/daehanmun_probe_input.gd"));scene.input_router.isolate_movement_bindings()
	if not scene.input_router.menu_toggle_requested.is_connected(scene.toggle_menu):scene.input_router.menu_toggle_requested.connect(scene.toggle_menu)
	if variant not in ["normal","seam_teleport","omit_court"] and not _fault():push_error("Unknown W04 fault");quit(1);return
	await _wait(1)
	var shape: CapsuleShape3D=scene.player.get_node("CollisionShape").shape
	var actor:={"height":shape.height,"radius":shape.radius,"layer":scene.player.collision_layer,"mask":scene.player.collision_mask,"walk_mps":scene.player.walk_speed_mps,"run_mps":scene.player.run_speed_mps,"gravity":scene.player.gravity_mps2,"safe_margin":scene.player.safe_margin,"camera_mask":scene.rig.arm.collision_mask,"camera_probe_radius":scene.rig.arm.shape.radius,"player_camera_path_matches":scene.player.movement_camera==scene.rig.camera,"boundary_script":scene.player.get_script().resource_path}
	var visuals: Dictionary=load("res://test_support/palace_visual_observation.gd").collect(scene)
	var warm: Dictionary=await _warmup();await _wait(1)
	var initial:={"point":_v(scene.player.global_position),"valid":scene.player.spawn_valid,"volume_guard_clear":scene.city.volume_clear(scene.player.spawn_transform.origin,1.7,.3)}
	var cases:=[]
	var journey: Dictionary=await _integrated(cases)
	await _capture("journey_end")
	var after_tick:=Engine.get_physics_frames()
	var events: Array=await _events()
	var resource: Resource=scene.city.boundary_resource
	var record:={"schema_version":1,"task":"W04","suite":suite,"fault":variant,"engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"physics_hz":Engine.physics_ticks_per_second,"render_fps":fps},"plan_sha256":FileAccess.get_sha256("res://data/generated/walkable_itinerary.json"),"w03_sha256":FileAccess.get_sha256("res://data/generated/public_walk.json"),"inventory":_inventory(),"spawn":initial,"actor":actor,"cases":cases,"journey":journey,"events_start_physics_tick":after_tick,"events_end_physics_tick":Engine.get_physics_frames(),"events":events,"rays":_rays(),"captures":capture_names,"warmup":warm,"boundary":{"contract_id":resource.contract_id,"runtime_path":resource.runtime_path,"movement_edge_margin_m":resource.movement_edge_margin_m,"road_center_exclusion_m":resource.road_center_exclusion_m,"guide_exists":scene.get_node("Presentation/BoundaryGuide") is MeshInstance3D,"guide_child_count":scene.get_node("Presentation/BoundaryGuide").get_child_count(),"guide_surface":_guide_observation()},"external_movement_events_ignored":scene.input_router.external_movement_events,"scope":"W04 automatic integrated physical journey only; human handling/OS focus, real terrain/access, M4, NPC/vehicles and V0 unverified"}
	record["l02_visuals"]=visuals
	record["l02_scene"]="res://scenes/world/palace_landmarks.tscn"
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var file:=FileAccess.open(output_path,FileAccess.WRITE)
	if file==null:push_error("W04 fresh output required");quit(1);return
	file.store_string(JSON.stringify(record)+"\n");print("W04_PROBE_DONE segments=",cases.size());scene.queue_free();quit(0)
