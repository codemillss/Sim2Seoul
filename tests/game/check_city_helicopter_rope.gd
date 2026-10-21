extends "res://../tests/game/check_city_helicopter.gd"
## EXP25: Engine physical KEY_E/KEY_R and retained capsule movement. The roof
## approach starts at a labelled airborne fixture; final descent is production
## Ctrl plus move_and_slide, followed by ordinary E exit and reboarding.
var _rope_positions: Array[Vector3]=[]
var _identity: Dictionary={}
func _initialize() -> void:
	report_task="EXP25_HELICOPTER_ROOF_ROPE_SPEED"
	report_scope="Production flight, rope and retained native capsule with engine physical KEY_E/KEY_R and priority -200 held-action fixture. Labelled starting fixtures above existing roof/pool/canopy and high-altitude speed lane are test placements; subsequent movement, sweep, braking, landing and restoration use production physics. Completed rope uses explicitly recorded clear-home game recall, not physical return flight. No OS keyboard, human feel, native visual review or long performance claim."
	super._initialize()
func _hashes() -> Dictionary:
	var result:=super._hashes()
	for path: String in ["res://../tests/game/check_city_helicopter_rope.gd","res://scripts/city_helicopter_rope.gd","res://scripts/transport_motion_policy.gd","res://scripts/exploration_rooftop_access.gd","res://scripts/player/exploration_avatar.gd","res://scripts/player/camera_rig.gd"]:result[path]=FileAccess.get_sha256(path)
	return result
func _r(down: bool) -> void:
	var event:=InputEventKey.new();event.keycode=KEY_R;event.physical_keycode=KEY_R;event.device=0;event.pressed=down;Input.parse_input_event(event)
func _tap_r() -> void:_r(true);await _ticks(3);_r(false);await _ticks(3)
func _wait_state(value: String,limit:=240) -> bool:
	for tick: int in range(limit):
		await _ticks(1)
		if service.rope.state==value:return true
	return false
func _start_airborne(height:=10.) -> bool:
	if not service.riding:
		_place_observer();await _ticks(6);await _tap_e();await _ticks(65)
	var y: float=service.body.global_position.y
	_key(service.ASCEND,true)
	for tick: int in range(240):
		await _ticks(1)
		if service.body.global_position.y-y>=height:break
	_key(service.ASCEND,false);await _ticks(20)
	return service.riding and not service._landed()
func _restored() -> bool:
	return not service.riding and service._release.is_empty() and scene.player.is_physics_processing() and not scene.player.facility_control and scene.player.get_node("CollisionShape").shape.get_instance_id()==_identity.shape and scene.player.collision_layer==_identity.layer and scene.player.collision_mask==_identity.mask and scene.exploration_avatar.visible and not service._passenger.visible and is_equal_approx(scene.rig.pivot_height_m,_identity.pivot) and is_equal_approx(scene.rig.distance_max_m,_identity.rig_max)
func _run() -> void:
	_loaded_hashes=_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/helicopter-rope-test-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";root.add_child(scene);await _ticks(10)
	service=scene.get("city_helicopter_service")
	_check("production_scene_and_helicopter_loaded",scene.runtime_ok and is_instance_valid(service) and service.loaded,{"error":scene.exploration_error})
	if not scene.runtime_ok or not is_instance_valid(service) or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	_identity={"shape":scene.player.get_node("CollisionShape").shape.get_instance_id(),"layer":scene.player.collision_layer,"mask":scene.player.collision_mask,"pivot":scene.rig.pivot_height_m,"rig_max":scene.rig.distance_max_m}
	_check("original_street_actors_30_and_AI_cars_14_retained",scene.pedestrians.size()+scene.street_pedestrians.actors.size()+scene.neighborhood_population.walkers.actors.size()==30 and scene.vehicles.size()+scene.neighborhood_population.traffic.vehicles.size()==14)
	_check("actual_existing_roof_has_native_skids_full_rotor_tail_and_exit",not service.roof_landing_site.is_empty(),{"site":service.roof_landing_site,"audit":service.roof_site_audit})
	_check("faster_helicopter_policy_over_selected_run_speed",float(service.motion_policy().maximum_forward_mps)>=scene.player.run_speed_mps*4. and float(service.motion_policy().horizontal_acceleration_mps2)>=float(service.motion_policy().maximum_forward_mps)/1.8,{"policy":service.motion_policy()})
	_check("physical_takeoff_for_rope",await _start_airborne(10.))
	_r(true);Input.flush_buffered_events();scene.toggle_menu()
	for frame: int in range(4):await process_frame
	scene.toggle_menu();await _ticks(6)
	_check("queued_physical_R_before_menu_is_cancelled_on_resume",service.rope.state=="idle" and not service.rope._queued)
	_r(false);await _ticks(3)
	scene.toggle_menu();_r(true)
	for frame: int in range(4):await process_frame
	scene.toggle_menu();await _ticks(6)
	_check("R_held_across_menu_requires_release_and_never_deploys",service.rope.state=="idle")
	_r(false);await _ticks(3);await _tap_r();await _wait_state("lowering")
	_check("fresh_R_brakes_hover_transfers_retained_avatar_and_lowers_rope",service.rope.state=="lowering" and service.rope._line.visible and scene.exploration_avatar.visible and not service._passenger.visible and scene.player.get_node("CollisionShape").shape.get_instance_id()==_identity.shape,{"rope":service.rope.snapshot()})
	if service.rope.state!="lowering":_finish();return
	await _capture("rope_lowering")
	var before: Vector3=scene.player.global_position;var max_step:=0.;var minimum_y:=before.y
	for tick: int in range(30):
		await _ticks(1);var now: Vector3=scene.player.global_position;max_step=maxf(max_step,now.distance_to(before));minimum_y=minf(minimum_y,now.y);before=now
	await _capture("rope_visible_continuous_descent")
	_check("rope_avatar_descends_continuously_at_bounded_speed",minimum_y<service.rope.side_point.y-1. and max_step<=service.rope.SPEED_MPS/float(Engine.physics_ticks_per_second)+.005,{"maximum_step_m":max_step,"minimum_y":minimum_y})
	scene.toggle_menu();var frozen: Vector3=scene.player.global_position;var aircraft_frozen: Transform3D=service.body.global_transform;var travelled: float=service.rope.travelled_m
	for frame: int in range(8):await process_frame
	_check("menu_freezes_actual_rope_player_aircraft_and_progress",scene.player.global_position==frozen and service.body.global_transform==aircraft_frozen and service.rope.travelled_m==travelled)
	scene.toggle_menu();await _ticks(3);await _tap_r()
	_check("R_cancels_descent_with_continuous_upward_retraction",service.rope.state=="retracting")
	var low: float=scene.player.global_position.y
	for tick: int in range(100):
		await _ticks(1)
		if service.rope._returning_to_cabin:break
	await _tap_r();_check("fresh_R_during_final_retraction_keeps_returning_to_cabin",service.rope.state=="retracting" and service.rope._returning_to_cabin)
	await _wait_state("idle",300)
	_check("retraction_returns_same_pilot_to_cabin_without_ejection",service.rope.state=="idle" and service.riding and not scene.exploration_avatar.visible and service._passenger.visible and scene.player.global_position.y>low+1. and service.rope.maximum_step_m<=service.rope.SPEED_MPS/float(Engine.physics_ticks_per_second)+.005,{"rope":service.rope.snapshot()})
	await _ticks(5);await _tap_r();await _wait_state("lowering")
	var blocker:=_fixture(scene.player.global_position-Vector3.UP*1.0,Vector3(1.3,.25,1.3));await _ticks(2)
	await _wait_state("blocked",100);frozen=scene.player.global_position;await _ticks(12)
	_check("new_native_blocker_pauses_descent_without_crossing_capsule",service.rope.state=="blocked" and scene.player.global_position==frozen and service.riding,{"rope":service.rope.snapshot(),"player":frozen})
	blocker.queue_free();await _ticks(4);await _tap_r();await _wait_state("idle",300)
	_check("blocked_rope_can_safely_retract_after_obstacle_clears",service.rope.state=="idle" and service.riding)
	await _ticks(5);await _tap_r();await _wait_state("lowering");await _wait_state("idle",600);await _ticks(65)
	_check("rope_reaches_real_native_support_and_restores_capsule_camera",service.rope.last_result=="completed" and _restored() and scene.player.global_position.y-scene.terrain_surface.ground_y_world(scene.player.global_position)<.2,{"rope":service.rope.snapshot(),"player":scene.player.global_position,"snapshot":service.snapshot()})
	_check("completed_rope_uses_explicit_game_recall_to_clear_home",not service.return_pending and service._landed() and service.events.any(func(row: Dictionary)->bool:return row.event=="game_aircraft_returned_to_clear_home_pad"))
	await _capture("rope_ground_restored")
	await _ticks(4);var walking_start: Vector3=scene.player.global_position;_key("move_forward",true);await _ticks(35)
	var direction: Vector3=scene.player.last_direction;var expected_yaw:=atan2(-direction.x,-direction.z);var observed_yaw: float=scene.player.get_node("Visual").global_rotation.y;var heading_error:=absf(wrapf(observed_yaw-expected_yaw,-PI,PI))
	_key("move_forward",false);await _ticks(3)
	_check("rope_exit_restores_world_walking_and_avatar_heading",scene.player.global_basis.is_equal_approx(Basis.IDENTITY) and scene.player.global_position.distance_to(walking_start)>.5 and direction.length_squared()>.5 and heading_error<.02,{"actual_travel_m":scene.player.global_position.distance_to(walking_start),"world_direction":direction,"expected_yaw":expected_yaw,"actual_global_visual_yaw":observed_yaw,"heading_error_rad":heading_error})
	# Roof flight fixture changes only the aircraft starting pose. Ctrl then
	# uses native aircraft sweeps/move_and_slide to land at the actual deck Y.
	_check("takeoff_again_for_roof_fixture",await _start_airborne(5.))
	if not service.roof_landing_site.is_empty():
		var roof: Dictionary=service.roof_landing_site;service.body.global_transform=Transform3D(Basis(Vector3.UP,roof.yaw),roof.point+Vector3.UP*6.);service._yaw=roof.yaw;service.body.velocity=Vector3.ZERO;service.speed_mps=0.;service.vertical_speed_mps=0.;service._current=service.body.global_transform;service._previous=service._current;await _ticks(4)
		_key(service.DESCEND,true)
		for tick: int in range(240):
			await _ticks(1)
			if service._landed():break
		_key(service.DESCEND,false);await _ticks(8)
		_check("native_Ctrl_lands_all_skids_at_actual_authored_roof_Y",service._landed() and absf(service.body.global_position.y-roof.point.y)<.2,{"position":service.body.global_position,"roof":roof,"fixture":"Aircraft begins 6m above certified existing game roof; actual Ctrl physics performs final landing."})
		await _capture("roof_landed")
		await _tap_e();await _ticks(65)
		_check("rooftop_E_stops_rotor_and_restores_outdoor_walking",_restored() and scene.player.global_position.y>scene.terrain_surface.ground_y_world(scene.player.global_position)+5.,{"player":scene.player.global_position,"snapshot":service.snapshot()})
		await _tap_e();await _ticks(65)
		_check("same_rooftop_allows_fresh_E_reboarding",service.riding and service._landed(),{"snapshot":service.snapshot()})
		await _capture("roof_reboarded")
		_key(service.ASCEND,true);await _ticks(35);_key(service.ASCEND,false);await _ticks(20);await _tap_r();await _wait_state("lowering")
		_check("airborne_rope_can_target_actual_existing_game_deck",service.rope.state=="lowering" and service.rope.target.get("support_kind","")=="game_roof_deck",{"rope":service.rope.snapshot()})
		await _wait_state("idle",600);await _ticks(65)
		_check("roof_rope_landing_restores_player_on_same_deck",_restored() and service.rope.last_result=="completed" and scene.player.global_position.y>scene.terrain_surface.ground_y_world(scene.player.global_position)+5.,{"rope":service.rope.snapshot()})
	# Teleport while descending must keep the validated new target, remove all
	# rope visuals/collision pairs and never reattach the pilot on the next tick.
	_check("new_rope_takeoff_for_external_teleport",await _start_airborne(10.));await _tap_r();await _wait_state("lowering")
	scene.toggle_menu();scene._visit_library_entrance();await _ticks(65)
	_check("teleport_during_rope_restores_avatar_camera_capsule_and_cleans_line",_restored() and service.rope.state=="idle" and not service.rope._line.visible and not service.rope._harness.visible and scene.player.global_position.distance_to(service.body.global_position)>10.,{"snapshot":service.snapshot(),"player":scene.player.global_position})
	# A validated external observer may explicitly recall a parked roof craft.
	# Only this extra parked starting fixture is placed; the actual clear-home
	# recovery API must leave the independent player at the committed observer.
	var observer_before: Vector3=scene.player.global_position
	service.body.global_transform=Transform3D(Basis(Vector3.UP,service.roof_landing_site.yaw),service.roof_landing_site.point);service._yaw=service.roof_landing_site.yaw;service.speed_mps=0.;service.vertical_speed_mps=0.;service.body.velocity=Vector3.ZERO;await _ticks(8)
	var recovery_requested: bool=service.request_home_recovery();await _ticks(35)
	_check("explicit_parked_roof_game_recall_preserves_validated_observer",recovery_requested and service._landed() and service.body.global_position.distance_to(service.helipad.point)<.3 and scene.player.global_position.distance_to(observer_before)<.05 and _restored(),{"fixture":"Parked roof start only; request_home_recovery is the post-validation API and is explicitly a game recall, not flight."})
	# Explicit airborne rejection fixtures: the retained capsule never goes
	# into pool water, a canopy, a bare source roof or an unsupported roof edge.
	_check("takeoff_for_native_rejection_fixtures",await _start_airborne(10.))
	var roof_node: Node3D=scene.exploration_rooftop_access.roofs[service.roof_landing_site.building_id]
	var pool: Node3D=scene.exploration_rooftop_access.roofs[scene.exploration_rooftop_access.REPRESENTATIVE_POOL_ID]
	for fixture: Dictionary in [{"name":"pool_water_floor","point":pool.pool_float_point()+Vector3.UP*12.},{"name":"rooftop_lift_canopy","point":roof_node.frame*Vector3(0,14.,roof_node.depth*.5-1.5)},{"name":"bare_original_source_roof","point":roof_node.frame*Vector3(roof_node.width*.5+2.,14.,0)}]:
		service.body.global_transform=Transform3D(Basis.IDENTITY,fixture.point-service.rope.SIDE_OFFSET);service._yaw=0.;service.body.velocity=Vector3.ZERO;service.speed_mps=0.;service.vertical_speed_mps=0.;service._current=service.body.global_transform;service._previous=service._current;await _ticks(4);await _tap_r();await _ticks(6)
		_check("physical_R_rejects_"+fixture.name,service.riding and service.rope.state=="idle" and not service.rope._line.visible and not service.rope.reason.is_empty(),{"rope":service.rope.snapshot(),"fixture_winch_start":fixture.point,"fixture":"Only the airborne start is placed; fresh R performs actual native support/full capsule checks."})
		if service.rope.active():await _tap_r();await _wait_state("idle",300)
	var saved_pose: Transform3D=service.body.global_transform
	service.body.global_transform=roof_node.frame*Transform3D(Basis.IDENTITY,Vector3(roof_node.width*.5-.3,.12,0))
	_check("roof_edge_never_counts_as_four_skid_landing",not service._landed(),{"fixture":"Synchronous roof-edge eligibility fixture; no physics tick advances at the unsupported pose."})
	service.body.global_transform=saved_pose;await _ticks(3)
	# Faster flight after an explicit high-air starting fixture. Cruise,
	# braking, turn, return and final Ctrl landing remain ordinary inputs.
	scene.set_speed_profile("turbo");service.body.global_transform=Transform3D(Basis.IDENTITY,service.helipad.point+Vector3.UP*160.);service._yaw=0.;service.body.velocity=Vector3.ZERO;service.speed_mps=0.;service.vertical_speed_mps=0.;service._current=service.body.global_transform;service._previous=service._current;await _ticks(5)
	var home: Vector3=service.body.global_position;var top:=0.;_key("move_forward",true)
	for tick: int in range(65):await _ticks(1);top=maxf(top,service.speed_mps)
	_key("move_forward",false)
	_check("actual_turbo_helicopter_reaches_84mps_and_exceeds_21mps_run",top>=float(service.motion_policy().maximum_forward_mps)-.01 and top>=scene.player.run_speed_mps*4. and service.body.global_position.distance_to(home)>80.,{"top_mps":top,"run_mps":scene.player.run_speed_mps,"travel_m":service.body.global_position.distance_to(home),"fixture":"Starts 160m above home with full native volume intact. Subsequent cruise/brake/turn/return/landing use production held inputs."})
	await _capture("turbo_flight")
	await _ticks(80);var stopped: Vector3=service.body.global_position;await _ticks(8)
	_check("actual_turbo_coast_brake_stops_aircraft_without_relocation",absf(service.speed_mps)<.01 and service.body.global_position.distance_to(stopped)<.01,{"stopped":stopped,"distance_from_home_m":stopped.distance_to(home),"policy":service.motion_policy()})
	_key("move_left",true);await _ticks(126);_key("move_left",false);await _ticks(2)
	_key("move_forward",true)
	for tick: int in range(180):
		await _ticks(1)
		var remaining: float=Vector2(service.body.global_position.x-home.x,service.body.global_position.z-home.z).length();var braking: float=service.speed_mps*service.speed_mps/(2.*float(service.motion_policy().horizontal_braking_mps2))
		if service.speed_mps>1. and remaining<=braking+.6:break
	_key("move_forward",false);await _ticks(85)
	_check("controlled_turbo_turn_and_braking_return_over_same_real_pad",Vector2(service.body.global_position.x-home.x,service.body.global_position.z-home.z).length()<5.3 and absf(service.speed_mps)<.01,{"position":service.body.global_position,"home":home,"yaw":service._yaw})
	_key(service.DESCEND,true)
	for tick: int in range(900):
		await _ticks(1)
		if service._landed():break
	_key(service.DESCEND,false);await _ticks(10)
	_check("turbo_Ctrl_descent_lands_on_original_public_native_ground",service._landed(),{"snapshot":service.snapshot()})
	await _tap_e();await _ticks(65);_check("turbo_landed_E_restores_same_native_walking_owner",_restored())
	_check("takeoff_and_rope_for_reset_lifecycle",await _start_airborne(10.));await _tap_r();await _wait_state("lowering");scene.reset_player();await _ticks(65)
	_check("reset_during_rope_cleans_line_capsule_avatar_camera_without_reattach",_restored() and service.rope.state=="idle" and not service.rope._line.visible and not service.return_pending,{"snapshot":service.snapshot(),"player":scene.player.global_position})
	_finish()
