extends SceneTree
## Production14 original cars. Only player observation poses and held movement
## are fixtures; no AI vehicle/source route/model is moved or substituted.
## EXP32 additionally observer-places the player beside the actual stopped door
## before staged entry. Physical on-foot approach itself belongs to the new
## check_city_action_freedom suite, not this controller-isolation fixture.
class HeldInput extends Node:
	var harness: SceneTree
	func _physics_process(_delta: float) -> void:harness._hold()
var scene: Node3D
var service: Node3D
var checks: Array=[]
var captures: Array=[]
var report_path:="/tmp/sim2seoul-traffic-takeover.json"
var held: Dictionary={}
var hashes: Dictionary={}
var initial_ids: Array=[]
var _finished:=false
var _started:=0
var _police_controller_unit_fixture: Dictionary={}
func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	for action: String in ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	var input:=HeldInput.new();input.harness=self;input.process_physics_priority=-200;input.process_mode=Node.PROCESS_MODE_ALWAYS;root.add_child(input)
	_started=Time.get_ticks_msec();Engine.max_fps=0
	create_timer(300.,true,false,true).timeout.connect(func()->void:
		if not _finished:_check("bounded_test_timeout",false);_finish()
	)
	_run.call_deferred()
func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:result[str(key)]=_json(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value:result.append(_json(item))
		return result
	if value is float:return value if is_finite(value) else null
	return value
func _hashes() -> Dictionary:
	var result: Dictionary={}
	for path: String in ["res://scripts/player/exploration_avatar.gd","res://scripts/player/textured_human_surface.gd","res://scripts/player/textured_human_rig.gd","res://scripts/traffic_car_takeover.gd","res://scripts/drivable_car_service.gd","res://scripts/city_bike_service.gd","res://scripts/explore_walk.gd","res://scripts/city_public_safety.gd","res://scripts/city_weather_emergency.gd","res://scripts/traffic/vehicle.gd","res://scripts/traffic/traffic_manager.gd","res://scripts/neighborhood_traffic.gd","res://assets/authored/car_service.json","res://assets/authored/neighborhood_population.json","res://resources/world_geometry/world.json","res://data/generated/traffic.json","res://../tests/game/check_traffic_car_takeover.gd"]:result[path]=FileAccess.get_sha256(path)
	return result
func _check(name: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":name,"passed":passed,"evidence":_json(evidence)});print("TAKEOVER_CHECK ",name," ",passed)
func _ticks(count: int) -> void:
	for index: int in range(count):await scene.rig.camera_stepped
func _hold() -> void:
	for action: String in held:Input.action_press(action)
func _key(action: String,pressed: bool) -> void:
	if pressed:held[action]=true
	else:held.erase(action);Input.action_release(action)
func _tap_e() -> void:
	var press:=InputEventKey.new();press.keycode=KEY_E;press.physical_keycode=KEY_E;press.device=42;press.pressed=true;Input.parse_input_event(press);await _ticks(2)
	var release:=InputEventKey.new();release.keycode=KEY_E;release.physical_keycode=KEY_E;release.device=42;release.pressed=false;Input.parse_input_event(release);await _ticks(3)
func _observer(body: CharacterBody3D) -> bool:
	for offset: Vector3 in [Vector3(-2.15,0,-.38),Vector3(2.15,0,-.38),Vector3(-2.30,0,.60),Vector3(2.30,0,.60)]:
		var safe: Dictionary=scene.interior_visit._safe_external_point(body.to_global(offset))
		if safe.is_empty():continue
		scene.player.global_position=safe.point;scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();scene.rig.snap_to_target_pose();await _ticks(3)
		if service._nearest_car()==body and service.can_interact():return true
	return false
func _moving_observer(minimum_speed_mps:=2.5) -> CharacterBody3D:
	for attempt: int in range(150):
		for body: CharacterBody3D in service.traffic_cars:
			if not body.is_physics_processing() or float(body._speed_mps)<minimum_speed_mps:continue
			# Observer/wall fixtures can legitimately make an AI car brake. Its
			# speed must still qualify after publication, immediately before E.
			if await _observer(body) and float(body._speed_mps)>=minimum_speed_mps:
				var stop_room: float=float(body._speed_mps)*float(body._speed_mps)/6.0+1.0
				if float(body._length_m)-float(body._station_m)>stop_room+1.0 and body._corridor_obstacle(stop_room).is_empty():return body
		await _ticks(2)
	return null
func _capture(title: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await _ticks(3);await RenderingServer.frame_post_draw
	var path:=report_path.get_basename()+"_"+title+".png";var image:=root.get_texture().get_image();var status:=image.save_png(path)
	_check("native_capture_"+title,status==OK)
	if status==OK:captures.append({"file":path,"sha256":FileAccess.get_sha256(path),"production_camera_preserved":true,"scope":"Player observer placement is a test fixture; car body/model and camera are production objects. Pixel review remains separate."})
func _finish() -> void:
	if _finished:return
	_finished=true;held.clear()
	if not _police_controller_unit_fixture.is_empty() and is_instance_valid(scene.get("city_public_safety")):
		scene.city_public_safety.set_physics_process(bool(_police_controller_unit_fixture.original_physics_processing))
	_check("runtime_inputs_unchanged_during_test",hashes==_hashes(),{"loaded":hashes,"finished":_hashes()})
	var passed:=checks.filter(func(row: Dictionary)->bool:return row.passed).size()
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(_json({"task":"EXP27_traffic_car_takeover","recorded_at":Time.get_datetime_string_from_system(),"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"physics_hz":Engine.physics_ticks_per_second,"source_hashes":hashes,"result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"captures":captures,"snapshot":service.snapshot() if is_instance_valid(service) else {},"police_controller_unit_fixture":_police_controller_unit_fixture,"elapsed_ms":Time.get_ticks_msec()-_started,"scope":"Production original AI actors; original body/model/shape and traffic route identities. Physical KEY_E events device42, test-only held movement and source-supported player observer poses, including close door re-positioning after physical braking for EXP32 staged entry. Actual on-foot door approach belongs to check_city_action_freedom separately. After actual theft-report/wanted integration is proven, ONLY police physics is paused for remaining car-controller/all14 E checks, then restored on finish; complete live pursuit/capture/release is separately checked by check_stolen_car_arrest and its Euljiro variant. No car teleport, AI body/model replacement, real OS key, sustained-performance or human-comfort claim."}),"  "));file.close()
	print("TAKEOVER_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)
func _run() -> void:
	hashes=_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/traffic-takeover-test-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8)
	service=scene.get("traffic_car_takeover")
	_check("production_setup14_original_actors_no_new_car",scene.runtime_ok and is_instance_valid(service) and service.loaded,{"runtime_error":scene.exploration_error})
	if not scene.runtime_ok or not is_instance_valid(service) or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	scene.player.free_roam_enabled=true;await _ticks(4)
	for body: CharacterBody3D in service.traffic_cars:initial_ids.append(body.get_instance_id())
	_check("original_body_model_shape_route_identity_and_no_replacement",service.snapshot().original_identities_retained and service.snapshot().spawned_replacement_cars==0 and initial_ids.size()==14)
	var moving:=await _moving_observer(1.2)
	_check("moving_actual_original_car_can_be_approached",is_instance_valid(moving))
	if not is_instance_valid(moving):_finish();return
	var initial_offenses: int=scene.city_public_safety.offense_count
	var wall:=StaticBody3D.new();wall.name="TakeoverNamedLineOfSightBlocker";wall.collision_layer=1
	var wall_collision:=CollisionShape3D.new();var wall_box:=BoxShape3D.new();wall_box.size=Vector3(.20,2.2,2.0);wall_collision.shape=wall_box;wall.add_child(wall_collision);scene.add_child(wall);wall.global_position=scene.player.global_position.lerp(moving.global_position,.5)+Vector3.UP*.95;await _ticks(2)
	_check("native_wall_blocks_original_car_door_sight",not service._visible_car(moving))
	wall.queue_free();await _ticks(3);moving=await _moving_observer()
	_check("pending_fixture_revalidates_current_actual_car_speed",is_instance_valid(moving),{"minimum_request_speed_mps":2.5})
	if not is_instance_valid(moving):_finish();return
	await _tap_e()
	_check("pending_stop_does_not_seat_player_or_allow_other_transport",is_instance_valid(service.pending_car) and service.riding and scene.player.is_physics_processing() and not scene.player.facility_control and not scene.city_scooter_service.can_interact())
	_check("pending_car_cannot_be_recycled_by_AI_manager",not moving.can_recycle() and not moving._running and moving._manager.vehicles.has(moving))
	var pending_clock: float=service.pending_elapsed_s;var pending_position: Vector3=moving.global_position;scene.toggle_menu()
	for frame: int in range(4):await process_frame
	_check("menu_pauses_pending_braking_without_moving_car",is_equal_approx(service.pending_elapsed_s,pending_clock) and moving.global_position.distance_to(pending_position)<.0001)
	scene.toggle_menu();await _ticks(2);await _tap_e()
	_check("fresh_E_cancels_pending_and_resumes_only_original_AI",not service.riding and not is_instance_valid(service.pending_car) and moving.is_physics_processing() and moving._manager.vehicles.has(moving) and scene.player.is_physics_processing() and not scene.player.facility_control)
	_check("pending_or_cancelled_request_is_not_confirmed_vehicle_theft",scene.city_public_safety.offense_count==initial_offenses and not scene.city_public_safety.wanted)
	# A second genuine pending request exercises the actual menu setting,
	# rather than changing a private controller flag in the test.
	moving=await _moving_observer()
	_check("traffic_setting_regression_has_actual_pending_candidate",is_instance_valid(moving))
	if not is_instance_valid(moving):_finish();return
	await _tap_e();scene.toggle_menu();scene.traffic_switch.set_pressed(false)
	for frame: int in range(3):await process_frame
	var disabled_position: Vector3=moving.global_position
	scene._visit_street_detail("bike_station")
	var shortcut_cancelled: bool=not scene.menu.visible and not service.riding
	if scene.menu.visible:scene.toggle_menu()
	await _ticks(12)
	_check("menu_traffic_OFF_then_validated_shortcut_cancel_keeps_original_AI_paused",shortcut_cancelled and not service.riding and not is_instance_valid(service.pending_car) and moving.is_physics_processing() and not moving._running and not scene.traffic_switch.button_pressed and moving.global_position.distance_to(disabled_position)<.005 and scene.city_public_safety.offense_count==initial_offenses,{"events":service.events,"before":disabled_position,"after":moving.global_position,"shortcut_cancelled":shortcut_cancelled})
	scene.traffic_switch.set_pressed(true);await _ticks(3)
	_check("actual_traffic_checkbox_ON_restores_unseized_AI_running",scene.traffic_switch.button_pressed and moving.is_physics_processing() and moving._running)
	moving=await _moving_observer()
	_check("moving_mount_revalidates_actual_speed_after_cancel_fixtures",is_instance_valid(moving),{"minimum_request_speed_mps":2.5})
	if not is_instance_valid(moving):_finish();return
	var other_positions: Dictionary={}
	for body: CharacterBody3D in service.traffic_cars:
		if body!=moving:other_positions[body.get_instance_id()]=body.global_position
	var original_shape_id: int=scene.player.get_node("CollisionShape").shape.get_instance_id();var initial_mask: int=scene.player.collision_mask;var initial_layer: int=scene.player.collision_layer
	await _tap_e()
	_check("physical_E_requests_only_actual_nearby_car_braking",service.riding and (service.pending_car==moving or not service.bikes.is_empty() and service.bikes[0].body==moving),{"snapshot":service.snapshot()})
	var saw_braking: bool=service.pending_initial_speed_mps>1.;var saw_onfoot_pending:=false;var maximum_braking_step:=0.;var previous: Vector3=moving.global_position
	for tick: int in range(180):
		if not is_instance_valid(service.pending_car):break
		saw_onfoot_pending=saw_onfoot_pending or scene.player.is_physics_processing()
		if service._door_distance_for(moving)>2.3 or service.pending_stage=="approach" and service._door_distance_for(moving)>1.10:await _observer(moving)
		await _ticks(1);maximum_braking_step=maxf(maximum_braking_step,Vector2(moving.global_position.x-previous.x,moving.global_position.z-previous.z).length());previous=moving.global_position
	_check("moving_original_car_physically_decelerates_before_seat_handoff",saw_braking and saw_onfoot_pending and service.pending_actual_distance_m>.05 and maximum_braking_step<.20,{"initial_speed_mps":service.pending_initial_speed_mps,"actual_stop_distance_m":service.pending_actual_distance_m,"maximum_step_m":maximum_braking_step,"snapshot":service.snapshot()})
	_check("confirmed_takeover_locks_capsule_and_other_transports",service.riding and not is_instance_valid(service.pending_car) and not scene.player.is_physics_processing() and scene.player.facility_control and not scene.city_bike_service.can_interact() and not scene.city_scooter_service.can_interact())
	if not service.riding or is_instance_valid(service.pending_car):_finish();return
	var theft_reported:=false
	for event: Dictionary in scene.city_public_safety.events:
		if event.event=="offense_reported" and event.evidence.get("reason","")=="vehicle_theft":theft_reported=true
	_check("confirmed_original_car_theft_triggers_real_game_police_pursuit",theft_reported and scene.city_public_safety.offense_count==initial_offenses+1 and scene.city_public_safety.wanted and scene.city_public_safety.chase_remaining_s>58. and scene.city_public_safety.chase_remaining_s<=60.,{"public_safety":scene.city_public_safety.snapshot()})
	# The remaining assertions isolate transport control across every original
	# actor. A successful newly reachable police arrest must not be misreported
	# as a broken E controller. Full LIVE approach/capture/custody/release is
	# exercised independently by the two stolen-car/arrest integration suites.
	_police_controller_unit_fixture={"name":"TestOnlyPolicePhysicsIsolationForCarControllerChecks","starts_after":"actual vehicle_theft report and wanted-state assertion","original_physics_processing":scene.city_public_safety.is_physics_processing(),"offense_reporting_retained":true,"police_actors_not_relocated_or_replaced":true,"restored_on_finish":true,"separate_live_integration_suites":["check_stolen_car_arrest.gd","check_stolen_car_arrest_euljiro.gd"]}
	scene.city_public_safety.set_physics_process(false)
	var manager: Node=moving._manager;var route_id: String=moving.get_route_id();var free: bool=not manager.vehicles.has(moving) and not manager.queue.has(route_id) and String(manager.zone_owner)!=route_id
	var zones: Variant=manager.get("zones")
	if zones is Dictionary:
		for zone: Dictionary in zones.values():free=free and not zone.queue.has(route_id) and String(zone.owner)!=route_id
	_check("only_seized_car_releases_AI_and_FIFO_ownership",free and not moving.is_physics_processing() and manager.routes.has(route_id))
	var other_moved:=0
	for body: CharacterBody3D in service.traffic_cars:
		if body!=moving and body.is_physics_processing() and body.global_position.distance_to(other_positions[body.get_instance_id()])>.05:other_moved+=1
	_check("other_original_AI_continues_during_takeover",other_moved>0,{"other_cars_moved":other_moved})
	await _capture("original_model_driver")
	await _ticks(4);var start: Vector3=moving.global_position;_key("move_forward",true);await _ticks(40);_key("move_forward",false)
	_check("W_drives_same_original_body_with_native_car_controls",moving.global_position.distance_to(start)>.15 and service.actual_distance_m>.15,{"travel_m":moving.global_position.distance_to(start),"snapshot":service.snapshot()})
	_key("jump",true);await _ticks(70);_key("jump",false)
	_check("Space_brakes_original_car_on_supported_road",absf(service.speed_mps)<.03 and moving.is_on_floor())
	await _tap_e();await _ticks(10)
	_check("E_dismount_restores_original_capsule_and_releases_collision_pair",not service.riding and not scene.player.facility_control and scene.player.is_physics_processing() and scene.player.collision_mask==initial_mask and scene.player.collision_layer==initial_layer and scene.player.get_node("CollisionShape").shape.get_instance_id()==original_shape_id and service._collision_release_pending.is_empty())
	if service.riding:_finish();return
	var parked: Vector3=moving.global_position;await _ticks(15)
	_check("seized_car_stays_parked_and_original_identity_retained",moving.global_position.distance_to(parked)<.03 and service.snapshot().original_identities_retained)
	var observer:=await _observer(moving);await _tap_e();await _ticks(3)
	_check("parked_same_car_is_driveable_again",observer and service.riding and service.bikes[service.rental_index].body==moving)
	_check("parked_seized_car_reentry_does_not_repeat_theft",scene.city_public_safety.offense_count==initial_offenses+1)
	service.cancel_ride_for_teleport();scene.player.global_position=scene.interior_visit._safe_external_point(moving.to_global(Vector3(-2.3,0,0))).get("point",scene.player.global_position);await _ticks(6)
	_check("validated_external_cancel_restores_player_and_parks_car",not service.riding and not scene.player.facility_control and scene.player.is_physics_processing())
	# Check every untouched source actor can expose a physical E interaction at
	# its current supported location. No vehicle is relocated to make this pass.
	var eligible:=0;var eligibility: Array=[]
	for body: CharacterBody3D in service.traffic_cars:
		if await _observer(body):eligible+=1;eligibility.append({"route_id":body.get_route_id(),"eligible":true,"position":body.global_position})
		else:eligibility.append({"route_id":body.get_route_id(),"eligible":false,"position":body.global_position})
	_check("all14_original_cars_have_supported_E_approaches",eligible==14,{"eligible":eligible,"cars":eligibility})
	for body: CharacterBody3D in service.traffic_cars:
		if body==moving:continue
		var approached:=await _observer(body)
		if approached:await _tap_e()
		for tick: int in range(240):
			if not is_instance_valid(service.pending_car):break
			if service._door_distance_for(body)>2.3 or service.pending_stage=="approach" and service._door_distance_for(body)>1.10:await _observer(body)
			await _ticks(1)
		var mounted: bool=service.riding and not is_instance_valid(service.pending_car) and service.rental_index>=0 and service.bikes[service.rental_index].body==body
		_check("physical_E_seizes_original_"+String(body.get_route_id()),approached and mounted,{"body_id":body.get_instance_id(),"snapshot":service.snapshot()})
		if mounted:
			await _tap_e();await _ticks(12)
			_check("E_exits_original_"+String(body.get_route_id()),not service.riding and scene.player.is_physics_processing() and not scene.player.facility_control)
		if service.riding:
			service.cancel_ride_for_teleport();await _observer(body);await _ticks(8)
	var current_ids: Array=[]
	for body: CharacterBody3D in scene.vehicles:current_ids.append(body.get_instance_id())
	for body: CharacterBody3D in scene.neighborhood_population.traffic.vehicles:current_ids.append(body.get_instance_id())
	_check("all14_original_host_actor_arrays_and_source_identities_preserved",current_ids==initial_ids and service.snapshot().original_identities_retained)
	_finish()
