extends "res://../tests/game/check_large_outdoor_pool.gd"
## The production hotel shortcut and a labelled outdoor-jump arrival fixture
## both walk to the physical roof lift, use a fresh E, descend and walk out.
var entry_paths: Array=[]

func _unchanged_player_state() -> Dictionary:
	return {"pose":scene.player.global_transform,"velocity":scene.player.velocity,"interior":scene.player.interior_active,"bounds":scene.player.interior_bounds,"frame":scene.player.interior_frame,"rect":scene.player.interior_walkable_rect,"ceiling_unbounded":scene.player.interior_ceiling_unbounded,"spawn":scene.player.spawn_transform,"fall_limit":scene.player.fall_limit_y,"spawn_valid":scene.player.spawn_valid,"free_roam":scene.player.free_roam_enabled,"input_latched":scene.player.input_latched,"gameplay":scene.input_router.gameplay_enabled,"camera_input":scene.rig.input_enabled,"player_physics":scene.player.is_physics_processing(),"visit_active":visit.active,"on_roof":visit.on_roof,"feature_id":String(visit.current_spec.id),"prepared_id":visit.prepared_id,"elevator_open":visit.elevator_open}

func _hotel_shortcut() -> bool:
	scene.toggle_menu()
	var shortcut: Button
	for node: Node in _descendants(scene.get_node("Interface")):
		if node is Button and node.text=="호텔 야외 수영장으로 이동":shortcut=node;break
	_check("shortcut.production_hotel_menu_button_exists",is_instance_valid(shortcut))
	if not is_instance_valid(shortcut):return false
	var old_id: String=String(visit.current_spec.id)
	shortcut.pressed.emit()
	_movement();_e(false);await _ticks(20)
	var helper: Node3D=scene.get_node("ExplorationRooftopAccess")
	roof=helper.ensure_rooftop(HOTEL_ID)
	var row: Dictionary={"name":"normal_hotel_menu_shortcut","kind":"production_menu_button_pressed_signal","start":scene.player.global_position,"pool_entry":roof.pool_entry_point(),"visit_active":visit.active,"interior_active":scene.player.interior_active,"previous_feature_id":old_id,"current_feature_id":String(visit.current_spec.id)}
	entry_paths.append(row)
	_check("shortcut.reaches_real_pool_deck_without_requiring_visit_state",not paused and not scene.menu.visible and not visit.active and not scene.player.interior_active and scene.player.is_on_floor() and scene.player.global_position.distance_to(roof.pool_entry_point())<.15 and String(visit.current_spec.id)==old_id,row)
	return not visit.active and not scene.player.interior_active and scene.player.is_on_floor()

func _far_and_air_rejections() -> void:
	var old_id: String=String(visit.current_spec.id)
	var before: Dictionary=_unchanged_player_state()
	_check("far_pool.no_lift_candidate_or_ground_door_prompt",not is_instance_valid(visit.outdoor_roof_lift_candidate()) and not visit.prompt.visible and not visit.wayfinding.panel.visible,{"player":scene.player.global_position,"lift":roof.lift_point(),"prompt":visit.prompt_text.text})
	_e(true);_e(false);await _ticks(4)
	_check("far_pool.E_preserves_last_selection_pose_mode_and_controls",_unchanged_player_state()==before,{"before":before,"after":_unchanged_player_state()})
	Input.action_press("jump");await _ticks(3)
	var airborne: bool=not scene.player.is_on_floor()
	_e(true);_e(false);await _ticks(3)
	_check("airborne.E_does_not_adopt_roof_or_open_floor_picker",airborne and not visit.active and not visit.elevator_open and not scene.player.interior_active and not is_instance_valid(visit.outdoor_roof_lift_candidate()) and String(visit.current_spec.id)==old_id,{"player":scene.player.global_position,"grounded":scene.player.is_on_floor(),"feature_id":visit.current_spec.id})
	Input.action_release("jump");_movement()
	for tick in range(180):
		await _ticks(1)
		if scene.player.is_on_floor():break
	await _ticks(4)

func _walk_to_roof_lift(title: String, hold_e: bool) -> bool:
	var local: Vector3=roof.frame.affine_inverse()*scene.player.global_position
	var lift: Vector3=roof.frame.affine_inverse()*roof.lift_point()
	if hold_e:_e(true)
	# Open terrace first, then approach the visible lift from its front.
	var path: Array=[roof.frame*Vector3(local.x,.08,lift.z-2.8),roof.lift_point()]
	var walked: bool=await _walk_path(title+".actual_walk_pool_deck_to_physical_lift",path)
	_check(title+".walking_or_held_E_does_not_automatically_adopt",walked and not visit.active and not visit.elevator_open and not scene.player.interior_active,{"held_E":hold_e,"player":scene.player.global_position,"lift":roof.lift_point()})
	_e(false);_movement();await _ticks(4)
	_check(title+".physical_landing_shows_correct_roof_lift_prompt",visit.outdoor_roof_lift_candidate()==roof and visit.prompt.visible and visit.prompt_text.text.contains(String(roof.spec.title)) and visit.prompt_text.text.contains("엘리베이터") and not visit.wayfinding.panel.visible,{"prompt":visit.prompt_text.text,"player":scene.player.global_position,"lift":roof.lift_point()})
	return walked

func _invalid_frame_rejection(title: String) -> bool:
	var frame: Transform3D=roof.frame
	var before: Dictionary=_unchanged_player_state()
	roof.frame=Transform3D(Basis.from_scale(Vector3(2.,1.,1.)),frame.origin)
	var rejected: bool=not visit._adopt_outdoor_roof(roof)
	roof.frame=frame
	var frame_preserved: bool=rejected and _unchanged_player_state()==before
	_check(title+".invalid_roof_frame_rejection_is_transactional",frame_preserved,{"before":before,"after":_unchanged_player_state()})
	if not frame_preserved:return false
	# A flush pool has separate surrounding deck panels and an open basin.
	# Identify the actual landing support instead of assuming one full floor.
	var decks: Array[StaticBody3D]=[];var layers: Array[int]=[];var panel_names: Array[String]=[]
	for body: StaticBody3D in roof.bodies:
		if not String(body.get_meta("geometry_id","")).begins_with("EXP08_rooftop_DeckFloor"):continue
		decks.append(body);layers.append(body.collision_layer);panel_names.append(String(body.name))
	var point: Vector3=scene.player.global_position
	var support: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.35,point-Vector3.UP*.35,scene.player.collision_mask,[scene.player.get_rid()]))
	var support_body: Object=support.get("collider")
	var identified: bool=not decks.is_empty() and support_body in decks and visit.outdoor_roof_lift_candidate()==roof
	_check(title+".missing_support_fixture_identifies_actual_deck_panels",identified,{"deck_panels":panel_names,"actual_landing_support":str(support_body),"player":point})
	if not identified:return false
	# Remove all panels so a seam cannot expose an adjacent support. Restore
	# synchronously before another physics tick can move the player.
	for body: StaticBody3D in decks:body.collision_layer=0
	rejected=not visit._adopt_outdoor_roof(roof)
	for index: int in range(decks.size()):decks[index].collision_layer=layers[index]
	var support_preserved: bool=rejected and _unchanged_player_state()==before and visit.outdoor_roof_lift_candidate()==roof
	_check(title+".missing_actual_roof_support_rejection_is_transactional",support_preserved,{"before":before,"after":_unchanged_player_state(),"restored_deck_panels":panel_names})
	return support_preserved

func _fresh_E_and_descend(title: String) -> bool:
	var before: Transform3D=scene.player.global_transform
	var entries: int=visit.entry_count
	_e(true);_e(false);await _ticks(5)
	var adopted: bool=visit.active and visit.on_roof and visit.elevator_open and visit.entry_count==entries+1 and String(visit.current_spec.id)==HOTEL_ID and visit.rooftop==roof
	_check(title+".fresh_physical_E_adopts_this_roof_and_opens_real_picker",adopted and not scene.player.interior_active and scene.player.global_position.distance_to(before.origin)<.05 and visit.selected_floor==int(roof.spec.floor_count) and visit.elevator_floors.get_child_count()==visit.destination_count(),{"before":before,"after":scene.player.global_transform,"visit":visit.snapshot()})
	if not adopted:return false
	var state: Dictionary=_unchanged_player_state()
	var invalid_rejected: bool=not visit.request_floor(-1) and not visit.request_floor(visit.destination_count())
	_check(title+".invalid_floor_selection_preserves_exterior_pose_and_controls",invalid_rejected and _unchanged_player_state()==state,{"before":state,"after":_unchanged_player_state()})
	var blocker: StaticBody3D=_blocker("ExplicitBlockedGroundLanding",visit.room.elevator_point(0))
	await _ticks(4);state=_unchanged_player_state()
	var blocked_rejected: bool=not visit.request_floor(0)
	_check(title+".blocked_indoor_landing_rejects_before_boarding_transaction",blocked_rejected and _unchanged_player_state()==state,{"before":state,"after":_unchanged_player_state()})
	blocker.queue_free();await _ticks(4)
	var from_floor: int=int(roof.spec.floor_count)
	visit.elevator_floors.get_child(0).pressed.emit()
	var started: bool=visit.in_elevator and visit.selected_floor==0 and scene.player.interior_active and not scene.player.water_snapshot().registered
	_check(title+".real_first_floor_button_begins_roof_to_ground_cabin",started,{"elevator":visit.elevator_snapshot(),"interior_active":scene.player.interior_active,"water":scene.player.water_snapshot()})
	if not started:return false
	var phases: Dictionary={};var ticks: int=0;var fixed: bool=true;var real_camera: bool=true;var closed_motion: bool=true
	var passenger: Vector3=scene.player.global_position
	for tick in range(2400):
		if not visit.in_elevator:break
		await _ticks(1);ticks+=1
		if not visit.in_elevator:break
		var elevator: Dictionary=visit.elevator_snapshot();phases[String(elevator.phase)]=true
		fixed=fixed and scene.player.global_position.distance_to(passenger)<.001
		real_camera=real_camera and visit.cabin.camera.current and scene.get_viewport().get_camera_3d()==visit.cabin.camera
		if String(elevator.phase) in ["accelerating","cruising","decelerating"]:closed_motion=closed_motion and float(elevator.door_open_fraction)<.001
	_movement();_e(false);await _ticks(10)
	var arrived: bool=not visit.in_elevator and visit.active and not visit.on_roof and visit.selected_floor==0 and scene.player.interior_active and scene.player.is_on_floor() and scene.player.interior_bounds==visit.room.interior_bounds
	var row: Dictionary={"name":title,"from_floor":from_floor,"to_floor":0,"ticks":ticks,"phases":phases.keys(),"fixed_passenger":fixed,"actual_cabin_camera":real_camera,"closed_motion_doors":closed_motion,"player":scene.player.global_position,"elevator":visit.elevator_snapshot()}
	rides.append(row)
	_check(title+".actual_cabin_motion_arrives_on_safe_first_floor",arrived and ticks>150 and fixed and real_camera and closed_motion and phases.has("closing") and phases.has("accelerating") and phases.has("decelerating") and phases.has("opening"),row)
	return arrived

func _walk_out(title: String) -> bool:
	var room: Node3D=visit.room
	var path: Array=[room.to_global(Vector3(0.,.08,room.depth*.5-1.65)),room.exit_point()]
	if not await _walk_path(title+".actual_first_floor_walk_to_exit",path):return false
	var expected: Vector3=visit._outside_position
	_e(true);_e(false);await _ticks(10)
	var outside: bool=not visit.active and not scene.player.interior_active and scene.player.is_on_floor() and scene.player.global_position.distance_to(expected)<.15 and not visit._safe_external_point(scene.player.global_position).is_empty()
	_check(title+".fresh_E_walkout_returns_to_this_hotel_source_entrance",outside and scene.player.global_position.distance_to(roof.spec.entrance)<1.0 and scene.player.free_roam_enabled and scene.input_router.gameplay_enabled and scene.rig.input_enabled and not scene.player.water_snapshot().registered,{"expected":expected,"source_entrance":roof.spec.entrance,"actual":scene.player.global_position,"water":scene.player.water_snapshot()})
	return outside

func _direct_jump_arrival_fixture() -> bool:
	# The independent check_outdoor_roof_jumping test observes the full fresh-
	# Space street ascent. Here only its outdoor arrival is a labelled fixture;
	# the following walk, E, cabin ride and walkout are production interactions.
	var point: Vector3=roof.pool_entry_point()
	placements.append({"name":"explicit_direct_jump_roof_arrival","kind":"explicit_test_only_outdoor_roof_arrival_fixture_not_an_observed_ascent","point":point})
	scene.player.global_transform=Transform3D(Basis.IDENTITY,point)
	scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation()
	_movement();_e(false);await _ticks(16)
	var valid: bool=not visit.active and not scene.player.interior_active and scene.player.is_on_floor()
	entry_paths.append({"name":"direct_outdoor_jump_arrival_fixture","kind":"explicit_test_only_supported_arrival_on_existing_source_positioned_roof","position":scene.player.global_position,"physical_ascent_coverage":"check_outdoor_roof_jumping.gd"})
	_check("direct_jump_fixture.starts_on_same_physical_roof_without_visit_or_region_state",valid,{"player":scene.player.global_position,"roof_frame":roof.frame,"lift":roof.lift_point()})
	return valid

func _run() -> void:
	for path: String in ["res://scripts/interior_visit.gd","res://scripts/exploration_rooftop_access.gd","res://scripts/rooftop_space.gd","res://scripts/player/free_roam_player.gd","res://scripts/explore_walk.gd","res://../tests/game/check_direct_roof_lift.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json";root.add_child(scene)
	if not scene.runtime_ok:_check("startup",false);_finish();return
	visit=scene.interior_visit;await _ticks(25);original_inventory=_inventory()
	scene.set_free_roam(true);scene.set_speed_profile("brisk");_movement();await _ticks(4)
	if not await _hotel_shortcut():_finish();return
	await _far_and_air_rejections()
	if not await _walk_to_roof_lift("shortcut",true):_finish();return
	if not _invalid_frame_rejection("shortcut"):_finish();return
	if not await _fresh_E_and_descend("shortcut"):_finish();return
	if not await _walk_out("shortcut"):_finish();return
	if not await _direct_jump_arrival_fixture():_finish();return
	if not await _walk_to_roof_lift("direct_jump_fixture",false):_finish();return
	if not await _fresh_E_and_descend("direct_jump_fixture"):_finish();return
	if not await _walk_out("direct_jump_fixture"):_finish();return
	_check("world.original_source_collision_inventory_preserved",_inventory()==original_inventory,{"original_source_bodies":original_inventory.size()})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	# A failed helper script must not turn an omitted probe into a PASS.
	var required: Array[String]=["shortcut.reaches_real_pool_deck_without_requiring_visit_state","far_pool.E_preserves_last_selection_pose_mode_and_controls","airborne.E_does_not_adopt_roof_or_open_floor_picker","shortcut.invalid_roof_frame_rejection_is_transactional","shortcut.missing_support_fixture_identifies_actual_deck_panels","shortcut.missing_actual_roof_support_rejection_is_transactional","direct_jump_fixture.starts_on_same_physical_roof_without_visit_or_region_state","world.original_source_collision_inventory_preserved"]
	for title: String in ["shortcut","direct_jump_fixture"]:
		for suffix: String in ["actual_walk_pool_deck_to_physical_lift","physical_landing_shows_correct_roof_lift_prompt","fresh_physical_E_adopts_this_roof_and_opens_real_picker","invalid_floor_selection_preserves_exterior_pose_and_controls","blocked_indoor_landing_rejects_before_boarding_transaction","real_first_floor_button_begins_roof_to_ground_cabin","actual_cabin_motion_arrives_on_safe_first_floor","actual_first_floor_walk_to_exit","fresh_E_walkout_returns_to_this_hotel_source_entrance"]:required.append(title+"."+suffix)
	var observed: Array[String]=[];var missing: Array[String]=[]
	for check: Dictionary in checks:observed.append(String(check.name))
	for title: String in required:
		if not title in observed:missing.append(title)
	_check("test.required_interactions_and_rejection_checks_completed",missing.is_empty() and entry_paths.size()==2 and rides.size()==2,{"missing_checks":missing,"entry_paths":entry_paths.size(),"completed_rides":rides.size()})
	var failed: int=0
	for check: Dictionary in checks:
		if not check.passed:failed+=1
	var result: Dictionary={"task":"DIRECT_OUTDOOR_ROOF_LIFT_REENTRY","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"entry_paths":entry_paths,"walks":walks,"rides":rides,"placements":placements,"scope":"One entry uses the actual hotel menu button signal. The other explicitly fixtures only a direct-jump arrival on the same existing source-positioned roof; full physical ascent is covered by check_outdoor_roof_jumping.gd. Every subsequent roof approach and lobby exit uses production Input/move_and_slide, fresh E opens the actual floor picker, and its actual first-floor button starts the full phased cabin ride. Far/air, malformed-frame, missing-roof-support, invalid-floor and blocked-destination failures preserve physical/mode/control/selection state. No native human usability, performance or real-venue access claim."}
	var file: FileAccess=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(result),"\t")+"\n");file.close()
	else:failed+=1;push_error("Cannot save direct roof lift report")
	print("DIRECT_ROOF_LIFT_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)
