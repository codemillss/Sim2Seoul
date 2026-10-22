extends SceneTree
## Source-sized public facility, physical E and additional physical car on a
## certified block loop. Player-only observer starts are explicitly disclosed.
var scene: Node3D
var safety: Node3D
var facility: Node3D
var patrol: Node3D
var checks: Array=[]
var samples: Array=[]
var captures: Array=[]
var hashes: Dictionary={}
var report_path:="/tmp/sim2seoul-police-facility.json"
var started:=0
var finished:=false
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	started=Time.get_ticks_msec();Engine.max_fps=0;create_timer(480.,true,false,true).timeout.connect(func()->void:if not finished:_check("bounded_wall_timeout",false);_finish())
	run.call_deferred()
func _hashes() -> Dictionary:
	var out: Dictionary={}
	for path: String in ["res://scripts/city_public_safety.gd","res://scripts/city_police_facility.gd","res://scripts/city_police_patrol.gd","res://assets/authored/police_facility.json","res://assets/authored/police_patrol.json","res://scripts/explore_walk.gd","res://scripts/drivable_car_service.gd","res://scripts/interior_visit.gd","res://scripts/player/free_roam_player.gd","res://resources/world_geometry/world.json","res://data/generated/public_walk.json","res://../tests/game/check_police_facility.gd"]:out[path]=FileAccess.get_sha256(path)
	return out
func _json(v: Variant) -> Variant:
	if v is Vector3:return [v.x,v.y,v.z]
	if v is Vector2:return [v.x,v.y]
	if v is Dictionary:
		var out: Dictionary={}
		for key: Variant in v:out[str(key)]=_json(v[key])
		return out
	if v is Array:
		var out: Array=[]
		for row: Variant in v:out.append(_json(row))
		return out
	if v is float:return v if is_finite(v) else null
	return v
func _check(title: String,ok: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":ok,"evidence":_json(evidence)});print("POLICE_FACILITY_CHECK ",title," ",ok)
func _ticks(count: int) -> void:
	for index: int in range(count):await physics_frame;await process_frame
func _key(key: Key,pressed: bool) -> void:
	var event:=InputEventKey.new();event.keycode=key;event.physical_keycode=key;event.pressed=pressed;Input.parse_input_event(event)
func _tap_e() -> void:_key(KEY_E,true);await _ticks(2);_key(KEY_E,false);await _ticks(2)
func _capture(title: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await _ticks(3);await RenderingServer.frame_post_draw;var path:=report_path.get_basename()+"_"+title+".png";var result:=root.get_texture().get_image().save_png(path);_check("native_capture_"+title,result==OK,{"path":path});if result==OK:captures.append({"path":path,"sha256":FileAccess.get_sha256(path)})
func _place_player(point: Vector3,toward: Vector3) -> bool:
	if not facility._external_clear(point):return false
	if not scene._commit_exploration_teleport(point):return false
	var forward:=toward-point;forward.y=0.;scene.player.get_node("Visual").rotation.y=atan2(-forward.x,-forward.z);scene.rig.yaw=scene.player.get_node("Visual").rotation.y;scene.rig.pitch=deg_to_rad(-12.);scene.rig.requested_distance=5.2;scene.rig.current_distance=5.2;scene.rig.snap_to_target_pose();await _ticks(4);return true
func run() -> void:
	hashes=_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/police-facility-test-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8)
	safety=scene.city_public_safety;facility=safety.police_facility;patrol=safety.patrol_vehicle_service
	_check("production_source_facility_and_extra_patrol_loaded",scene.runtime_ok and safety.loaded and facility.loaded and patrol.loaded,{"runtime_error":scene.exploration_error,"safety":safety.snapshot()})
	if not scene.runtime_ok or not facility.loaded or not patrol.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	_check("official_source_police_box_identity_and_52m2_inscribed_lobby",facility.design.source_building_id=="osm:way:1215689854:building" and facility.design.official_address=="서울 중구 세종대로 141" and is_equal_approx(facility.design.lobby.area_m2,52.) and is_zero_approx(facility.design.lobby.outside_source_m2),facility.snapshot())
	_check("source_station_facade_readable_identity_and_civic_elements",is_instance_valid(facility.facade.get_node_or_null("KoreanInstitutionName")) and is_instance_valid(facility.facade.get_node_or_null("ClearEntryLabel")) and is_instance_valid(facility.facade.get_node_or_null("KoreanPublicInstitutionFlag")))
	_check("full_patrol_native_box_preflight_accepts_source_directed_sector",patrol.certificate.accepted and patrol.certificate.samples>500 and patrol.certificate.failures.is_empty() and patrol.total_length_m>250.,patrol.snapshot())
	_check("extra_police_car_visible_beacons_and_original14_separate",patrol._initial_original_ids.size()==14 and patrol.snapshot().original14_car_identities_retained and is_instance_valid(patrol._proxy.get_node_or_null("RedPoliceBeacon")) and is_instance_valid(patrol._proxy.get_node_or_null("BluePoliceBeacon")) and patrol.body.collision_layer==8)
	var departure: Dictionary=safety.rental_clearance_snapshot();_check("all16_rental_fixtures_and8m_departures_remain_clear",departure.reserved_docks==16 and departure.home_violations.is_empty() and departure.posted_violations.is_empty(),departure)
	var view: Dictionary=facility.viewpoint();_check("police_menu_viewpoint_has_retained_native_floor",not view.is_empty() and facility._external_clear(view.point),view)
	if not view.is_empty():await _place_player(view.point,view.toward);await _capture("source_frontage")
	var placed:=await _place_player(facility.entry_point,facility.entry_door);_check("player_only_native_safe_start_can_find_original_building_entrance",placed and facility.can_interact() and scene._street_interact_target()==safety,{"position":scene.player.global_position,"entry":facility.entry_point,"hint":scene.street_interaction_hint()})
	await _tap_e();_check("physical_e_owns_automatic_entry_animation",facility.active and facility.phase=="opening" and scene.player.facility_control,facility.snapshot())
	var opening_before: float=facility._timer;scene.toggle_menu();await _ticks(30);_check("menu_pauses_actual_entry_transition",is_equal_approx(opening_before,facility._timer));scene.toggle_menu();await _ticks(24)
	_check("actual_source_sized_lobby_entry_restores_walking",facility.active and facility.phase=="inside" and scene.player.interior_active and not scene.player.facility_control and scene.player.is_on_floor(),facility.snapshot());await _capture("public_lobby")
	var before: Vector3=scene.player.global_position;_key(KEY_D,true);await _ticks(5);_key(KEY_D,false);await _ticks(3);_check("lobby_native_player_walk_is_usable",scene.player.global_position.distance_to(before)>.15,{"walked_m":scene.player.global_position.distance_to(before)})
	var invalid: bool=scene._commit_exploration_teleport(Vector3(4850,150,4800));_check("invalid_external_transfer_retains_lobby_owner",not invalid and facility.active and scene.player.interior_active)
	await _tap_e();await _ticks(24);_check("physical_e_exit_returns_native_street_and_clears_owner",not facility.active and not scene.player.interior_active and not scene.player.facility_control and scene.player.is_physics_processing() and facility._external_clear(scene.player.global_position+Vector3.UP*.025),facility.snapshot())
	await _tap_e();await _ticks(24);var shortcut_before: int=facility.exit_count;scene._visit_street_detail("bike_station");await _ticks(4);_check("menu_validated_shortcut_cleans_actual_lobby_owner",not facility.active and not scene.player.interior_active and facility.exit_count==shortcut_before+1 and not scene.player.facility_control,facility.snapshot())
	# Player-only raised observer prevents an unrelated on-foot catch from
	# truncating this car route. No original or police actor is relocated.
	var platform:=StaticBody3D.new();platform.name="TestOnlyPatrolObserverPlatform";platform.collision_layer=32;var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(4.,.2,4.);collider.shape=box;platform.add_child(collider);scene.add_child(platform);platform.global_position=scene.player.global_position+Vector3.UP*5.;scene.player.global_position=platform.global_position+Vector3.UP*.12;scene.player.velocity=Vector3.ZERO;scene.player.set_physics_process(false);scene.player.reset_physics_interpolation();scene.rig.snap_to_target_pose();await _ticks(3)
	safety.report_offense("test patrol dispatch report",scene.player.global_position);await _ticks(30);_check("actual_report_dispatches_physical_patrol_with_siren_state",patrol.actual_distance_m>.25 and patrol.emergency_active and patrol.audio_state().siren_active and patrol.state!="parked",patrol.snapshot())
	var car_before: Vector3=patrol.body.global_position;var progress_before: float=patrol.progress_m;scene.toggle_menu();await _ticks(30);_check("menu_pauses_patrol_body_and_progress",patrol.body.global_position.distance_to(car_before)<.001 and is_equal_approx(progress_before,patrol.progress_m));scene.toggle_menu()
	var barrier_frame: Dictionary=patrol._frame(patrol.progress_m+6.);var barrier_pose: Dictionary=patrol._pose(barrier_frame.flat,barrier_frame.direction);var barrier:=StaticBody3D.new();barrier.name="TestOnlyFullSizePatrolRoadBlock";barrier.collision_layer=32;var blocker:=CollisionShape3D.new();var wall:=BoxShape3D.new();wall.size=Vector3(8.,3.,.2);blocker.shape=wall;barrier.add_child(blocker);scene.add_child(barrier);barrier.global_transform=Transform3D(barrier_pose.basis,barrier_pose.point+Vector3.UP*1.5)
	var blocked_before: int=patrol.blocked_ticks;await _ticks(180);_check("full_native_box_yields_to_real_obstacle_without_teleport",patrol.blocked_ticks>blocked_before and patrol.progress_m<progress_before+6. and patrol.maximum_native_step_m<.30,patrol.snapshot());barrier.queue_free();await _ticks(3)
	var stationary_ticks:=0
	for index: int in range(4800):
		await _ticks(1)
		if index%90==0:samples.append(_json({"game_s":float(index)/30.,"patrol":patrol.snapshot()}))
		if patrol.completed_cycles>0 and patrol.state=="parked" and not safety.wanted:break
		if patrol.state=="blocked":stationary_ticks+=1
		else:stationary_ticks=0
		if stationary_ticks>300:break
	_check("actual_sixty_second_offense_expires_without_mutating_timer",not safety.wanted and safety.events.any(func(row: Dictionary)->bool:return row.event=="escaped_after_sixty_seconds"),safety.snapshot())
	_check("physical_patrol_completes_source_loop_and_returns_to_authored_bay",patrol.completed_cycles>=1 and patrol.state=="parked" and patrol.actual_distance_m>250. and Vector2(patrol.body.global_position.x-42.,patrol.body.global_position.z+430.).length()<.15,patrol.snapshot())
	_check("patrol_native_steps_and_original_actor_identity_preserved",patrol.maximum_native_step_m<.30 and patrol.snapshot().original14_car_identities_retained and safety.officers.size()==4,patrol.snapshot());await _capture("returned_police_car")
	platform.queue_free();scene.player.set_physics_process(true);_finish()
func _finish() -> void:
	if finished:return
	finished=true;_check("source_inputs_stable_during_actual_run",hashes==_hashes() and not hashes.values().has(""),{"start":hashes,"end":_hashes()})
	var passed: int=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(_json({"task":"EXP28_SOURCE_POLICE_FACILITY","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"captures":captures,"route_samples":samples,"source_hashes":hashes,"snapshot":safety.snapshot() if is_instance_valid(safety) else {},"elapsed_ms":Time.get_ticks_msec()-started,"scope":"Production native physics, physical E, source52m² lobby, additional full-box patrol loop/obstacle/return and original identities. Only player starts/raised observer and disclosed temporary roadblock are test-authored. Headless does not establish appearance or listening quality."}),"  "));file.close();print("POLICE_FACILITY_RESULT ",passed,"/",checks.size())
	if is_instance_valid(scene):
		if is_instance_valid(scene.neighborhood_life.audio):scene.neighborhood_life.audio.stop();scene.neighborhood_life.audio.stream=null
		scene.queue_free();await process_frame;await process_frame
	quit(0 if passed==checks.size() else 1)
