extends SceneTree
## Actual production car controller with explicitly named player/blocker fixtures.
## Continuous WASD/Space is synthetic; E is a physical key press/release event.
class HeldMovementFixture extends Node:
	var harness: SceneTree
	func _physics_process(_delta: float) -> void:harness.call("_refresh_held_actions")
var scene: Node3D
var service: Node3D
var checks: Array=[]
var captures: Array=[]
var report_path:="/tmp/sim2seoul-drivable-car-initial.json"
var _held_actions: Dictionary={}
var _fixtures: Array[Node3D]=[]
var _source_hashes: Dictionary={}
var _loaded_hashes: Dictionary={}
var _finished:=false
var _started:=0
var _exit_watch_ticks:=0
var _previous_position:=Vector3.INF
var _was_riding:=false
var maximum_post_exit_idle_step_m:=0.0
func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	for action: String in ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	var fixture:=HeldMovementFixture.new();fixture.name="TestOnlyHeldMovementFixture";fixture.harness=self;fixture.process_physics_priority=-200;fixture.process_mode=Node.PROCESS_MODE_ALWAYS;root.add_child(fixture)
	Engine.max_fps=0;_started=Time.get_ticks_msec();create_timer(240.,true,false,true).timeout.connect(func()->void:
		if not _finished:_check("bounded_test_timeout",false);_finish()
	);_run.call_deferred()
func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Transform3D:return {"origin":_json(value.origin),"basis":[_json(value.basis.x),_json(value.basis.y),_json(value.basis.z)]}
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
func _input_hashes() -> Dictionary:
	var hashes: Dictionary={}
	for path: String in ["res://scripts/drivable_car_service.gd","res://scripts/city_bike_service.gd","res://assets/authored/car_service.json","res://scripts/transport_motion_policy.gd","res://scripts/explore_walk.gd","res://scripts/interior_visit.gd","res://../tests/game/check_drivable_car.gd"]:hashes[path]=FileAccess.get_sha256(path)
	return hashes
func _check(name: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":name,"passed":passed,"evidence":_json(evidence)});print("CAR_CHECK ",name," ",passed)
	if not passed:push_warning("CAR_CHECK_FAIL "+name)
func _ticks(count: int) -> void:
	for index: int in range(count):
		await scene.rig.camera_stepped
		if is_instance_valid(service) and service.loaded and not service.bikes.is_empty():
			var position: Vector3=service.bikes[0].body.global_position
			if _was_riding and not service.riding:_exit_watch_ticks=6
			elif _exit_watch_ticks>0:
				if _previous_position.is_finite():maximum_post_exit_idle_step_m=maxf(maximum_post_exit_idle_step_m,Vector2(position.x-_previous_position.x,position.z-_previous_position.z).length())
				_exit_watch_ticks-=1
			_previous_position=position;_was_riding=service.riding
func _key(action: String,pressed: bool) -> void:
	if pressed:_held_actions[action]=true
	else:_held_actions.erase(action);Input.action_release(action)
	var event:=InputEventAction.new();event.action=action;event.device=42;event.pressed=pressed;Input.parse_input_event(event)
func _refresh_held_actions() -> void:
	# Test-only held movement is refreshed before the production controller.
	# Native focus-loss protections and physical E edge/release are unchanged.
	for action: String in _held_actions:Input.action_press(action)
func _tap_e(device:=0) -> void:
	var press:=InputEventKey.new();press.keycode=KEY_E;press.physical_keycode=KEY_E;press.device=device;press.pressed=true;Input.parse_input_event(press);await _ticks(3)
	var release:=InputEventKey.new();release.keycode=KEY_E;release.physical_keycode=KEY_E;release.device=device;release.pressed=false;Input.parse_input_event(release);await _ticks(4)
func _fixture(at: Vector3,size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();body.name="CarTestNamedBlockingFixture";body.collision_layer=1;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;body.add_child(shape);scene.add_child(body);body.global_position=at;_fixtures.append(body);return body
func _clear_fixtures() -> void:
	for body: Node3D in _fixtures:body.queue_free()
	_fixtures.clear();await _ticks(3)
func _capture(title: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await _ticks(3);await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();var path:=report_path.get_basename()+"_"+title+".png";var error:=image.save_png(path)
	_check("native_capture_"+title,error==OK,{"file":path,"size":[image.get_width(),image.get_height()]})
	if error==OK:captures.append({"file":path,"sha256":FileAccess.get_sha256(path),"camera":scene.rig.snapshot(),"production_camera_preserved":true,"scope":"No test camera override. Image review is still required for car body, doors, wheels, cabin seats, driver posture and rendering."})
func _finish() -> void:
	if _finished:return
	_finished=true
	var sources_now: Dictionary={}
	for path: String in _source_hashes:sources_now[path]=FileAccess.get_sha256(path)
	_check("actual_world_traffic_and_actor_source_files_unchanged",sources_now==_source_hashes,{"before":_source_hashes,"after":sources_now})
	var hashes:=_input_hashes();_check("runtime_inputs_stable_during_test",hashes==_loaded_hashes,{"loaded":_loaded_hashes,"finished":hashes})
	var passed:=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Could not write car report: "+report_path);quit(2);return
	file.store_string(JSON.stringify(_json({"task":"drivable_car","source_hashes":_loaded_hashes,"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"recorded_at":Time.get_datetime_string_from_system(),"result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"captures":captures,"snapshot":service.snapshot() if is_instance_valid(service) and service.loaded else {},"physics_hz":Engine.physics_ticks_per_second,"elapsed_ms":Time.get_ticks_msec()-_started,"maximum_post_exit_idle_step_m":maximum_post_exit_idle_step_m,"scope":"One original authored player car on an actual retained source road, original AI actors retained, native full-car physics and player capsule. Physical KEY_E input events devices 0 and 42; test-only held movement refreshed at physics priority -200. Player observer placements and named blockers are fixtures. Headless does not accept rendered appearance or human OS key hold."}),"  "));file.close();print("CAR_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)
func _run() -> void:
	_loaded_hashes=_input_hashes()
	for path: String in ["res://resources/world_geometry/world.json","res://data/generated/traffic.json","res://assets/authored/neighborhood_population.json"]:_source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/drivable-car-test-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8)
	service=scene.get("drivable_car_service")
	if not is_instance_valid(service):
		service=load("res://scripts/drivable_car_service.gd").new();service.name="DrivableCarServiceTest";scene.drivable_car_service=service;scene.add_child(service);service.setup(scene)
	_check("production_setup_one_source_bound_full_body_car",scene.runtime_ok and service.loaded and service.bikes.size()==1,{"runtime_error":scene.exploration_error,"car_error":service.load_error,"placement":service.placement_audit})
	if not scene.runtime_ok or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	await _ticks(4)
	_check("original14_AI_cars_and30_people_retained",scene.vehicles.size()+scene.neighborhood_population.traffic.vehicles.size()==14 and scene.pedestrians.size()+scene.street_pedestrians.actors.size()+scene.neighborhood_population.walkers.actors.size()==30)
	var body: CharacterBody3D=service.bikes[0].body;var row: Dictionary=service.bikes[0];var collision: CollisionShape3D=row.shape
	_check("native_car_envelope_covers_body_mirrors_and_length",collision.shape is BoxShape3D and collision.shape.size==service.CAR_SIZE and body.collision_layer==8 and body.collision_mask==47,{"shape_size":collision.shape.size,"layer":body.collision_layer,"mask":body.collision_mask})
	_check("original_authored_sedan_has_four_wheels_doors_cabin_and_seats",row.wheels.size()==4 and row.proxy.has_node("FrontDoor") and row.proxy.has_node("CabinRoof") and row.proxy.has_node("SteeringColumn/SteeringWheel") and row.proxy.has_node("FrontSeatCushion") and row.proxy.has_node("RearBench"))
	var view: Dictionary=service.destination("car_station");_check("supported_car_door_shortcut_exists",not view.is_empty(),view)
	if view.is_empty():_finish();return
	# Exercise the actual menu shortcut, preserving its production camera and
	# its validation/owner cleanup rather than positioning the player directly.
	scene._visit_street_detail("car_station");await _ticks(8)
	_check("shortcut_matches_prompt_and_native_E_eligibility",scene.player.global_position.distance_to(view.point)<.25 and service.can_interact() and "E" in service.prompt_text(),{"expected":view.point,"player":scene.player.global_position,"door_distance":service.interaction_distance_m(),"visible":service._visible_bike(0),"support":service._player_supported_for_mount(),"prompt":service.prompt_text(),"camera":scene.rig.snapshot()})
	await _capture("production_shortcut")
	var shape_id: int=scene.player.get_node("CollisionShape").shape.get_instance_id();var layer: int=scene.player.collision_layer;var mask: int=scene.player.collision_mask;var pivot: float=scene.rig.pivot_height_m;var distance: float=scene.rig.requested_distance
	var middle: Vector3=scene.player.global_position.lerp(body.global_position,.5);_fixture(middle+Vector3.UP*.95,Vector3(.20,2.,2.));await _ticks(3);var can_behind_wall: bool=service.can_interact();await _tap_e()
	_check("native_wall_prevents_through_wall_driver_entry",not can_behind_wall and not service.riding)
	await _clear_fixtures();await _tap_e()
	_check("physical_E_mount_keeps_native_capsule_and_locks_other_transports",service.riding and not scene.player.is_physics_processing() and scene.player.facility_control and scene.exploration_avatar.visible and scene.player.collision_layer==layer and scene.player.collision_mask==mask and scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id and not scene.city_bike_service.can_interact() and not scene.city_scooter_service.can_interact() and not scene.city_bus_service.can_interact(),{"events":service.events,"prompt":service.prompt_text()})
	if not service.riding:_finish();return
	await _capture("production_mount")
	var before: Vector3=body.global_position;var maximum_speed:=0.;var unsupported:=0;var intent_ticks:=0;var blocked_ticks: Dictionary={}
	_key("move_forward",true)
	for tick: int in range(60):
		await _ticks(1);maximum_speed=maxf(maximum_speed,service.speed_mps)
		if not body.is_on_floor():unsupported+=1
		if scene.input_router.movement_intent().y<-.1:intent_ticks+=1
		if not service.blocked_reason.is_empty():blocked_ticks[service.blocked_reason]=int(blocked_ticks.get(service.blocked_reason,0))+1
	_key("move_forward",false)
	_check("W_accelerates_actual_full_car_on_native_terrain",body.global_position.distance_to(before)>1. and maximum_speed>2. and unsupported<4 and intent_ticks==60 and service.maximum_step_m<=float(service.motion_policy().maximum_speed_mps)/Engine.physics_ticks_per_second+.025,{"travel_m":body.global_position.distance_to(before),"maximum_speed_mps":maximum_speed,"unsupported_ticks":unsupported,"intent_ticks":intent_ticks,"blocked_ticks":blocked_ticks,"maximum_step_m":service.maximum_step_m})
	# Profiles can reach cruise before this check. Derive the bounded stop
	# allowance from the actual speed and production brake rate (45 ticks
	# at 30Hz is shorter than 14m/s / 9.1m/s²), then allow three input ticks.
	var brake_start_speed:=absf(service.speed_mps);var brake_rate: float=service.motion_policy().braking_mps2
	var brake_ticks:=ceili(brake_start_speed/brake_rate*Engine.physics_ticks_per_second)+3
	_key("jump",true);await _ticks(brake_ticks);_key("jump",false)
	_check("Space_stops_car_without_player_jump",absf(service.speed_mps)<.02 and body.is_on_floor() and not scene.player.is_physics_processing(),{"start_speed_mps":brake_start_speed,"braking_mps2":brake_rate,"physics_hz":Engine.physics_ticks_per_second,"allowed_ticks":brake_ticks,"remaining_speed_mps":service.speed_mps,"on_floor":body.is_on_floor()})
	var reverse_start: Vector3=body.global_position;var reverse_minimum:=0.;var reverse_maximum:=0.;_key("move_backward",true)
	for tick: int in range(105):await _ticks(1);reverse_minimum=minf(reverse_minimum,service.speed_mps);reverse_maximum=maxf(reverse_maximum,absf(service.speed_mps))
	_key("move_backward",false)
	_check("S_brakes_then_reverses_at_bounded_low_speed",reverse_minimum<-.5 and reverse_maximum<=1.11 and body.global_position.distance_to(reverse_start)>.3,{"minimum_speed_mps":reverse_minimum,"maximum_absolute_speed_mps":reverse_maximum,"travel_m":body.global_position.distance_to(reverse_start),"blocked_reason":service.blocked_reason})
	_key("jump",true);await _ticks(30);_key("jump",false)
	_key("move_forward",true);await _ticks(35);_key("move_forward",false);var yaw_before: float=row.yaw;_key("move_right",true);await _ticks(8);_key("move_right",false);var yaw_right: float=row.yaw;_key("move_left",true);await _ticks(13);_key("move_left",false)
	_check("AD_changes_car_yaw_front_axle_and_steering_wheel",absf(yaw_right-yaw_before)>.005 and absf(service.steer_radians)>.01 and absf(service._car_steering_wheel.rotation.y)>.01,{"yaw_before":yaw_before,"yaw_right":yaw_right,"yaw_after":row.yaw,"steer":service.steer_radians})
	_key("jump",true);await _ticks(45);_key("jump",false)
	_check("driver_hands_hold_actual_steering_wheel_grips",service.maximum_driver_hand_gap_m<.04,{"maximum_driver_hand_gap_m":service.maximum_driver_hand_gap_m})
	var obstacle_at: Vector3=body.global_position-body.global_basis.z*3.;obstacle_at.y=scene.terrain_surface.ground_y_world(obstacle_at)+1.;_fixture(obstacle_at,Vector3(4.,2.,.5));await _ticks(3);var obstacle_before: Vector3=body.global_position
	_key("move_forward",true);await _ticks(60);_key("move_forward",false)
	_check("native_full_car_sweep_stops_at_actual_wall",body.global_position.distance_to(obstacle_before)<.60 and service.blocked_reason=="physical_sweep",{"travel_m":body.global_position.distance_to(obstacle_before),"reason":service.blocked_reason})
	await _clear_fixtures();_key("jump",true);await _ticks(30);_key("jump",false)
	var frozen: Transform3D=body.global_transform;var clock: float=service._clock;scene.toggle_menu()
	for frame: int in range(18):await process_frame
	_check("actual_menu_pauses_car_clock_and_pose",paused and body.global_transform==frozen and service._clock==clock)
	scene.toggle_menu();await _ticks(5)
	for offset: Vector3 in [Vector3(-1.85,0,-.35),Vector3(1.85,0,-.35),Vector3(-1.85,0,.95),Vector3(1.85,0,.95),Vector3(0,0,3.15),Vector3(0,0,-3.15)]:
		var at: Vector3=body.to_global(offset);at.y=scene.terrain_surface.ground_y_world(at)+1.;_fixture(at,Vector3(.9,2.,.9))
	await _ticks(4);await _tap_e();await _ticks(15)
	_check("occupied_native_exit_candidates_keep_driver_safely_seated",service.riding and service.exit_requested and not scene.player.is_physics_processing() and service.blocked_reason=="dismount_blocked")
	await _tap_e();_check("blocked_exit_can_cancel_without_losing_control",service.riding and not service.exit_requested)
	await _clear_fixtures();await _tap_e();await _ticks(12)
	_check("safe_E_exit_restores_capsule_camera_and_walking",not service.riding and scene.player.is_physics_processing() and not scene.player.facility_control and scene.player.collision_mask==mask and scene.player.collision_layer==layer and scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id and is_equal_approx(scene.rig.pivot_height_m,pivot) and is_equal_approx(scene.rig.requested_distance,distance) and service._collision_release_pending.is_empty(),{"riding":service.riding,"pending":service._collision_release_pending.size(),"camera":scene.rig.snapshot()})
	await _capture("production_exited")
	await _tap_e(42);_check("physical_E_device42_remounts_same_parked_car",service.riding and service.rental_index==0)
	if service.riding:
		var safe: Dictionary=scene.interior_visit._safe_external_point(view.point)
		_check("external_cancel_has_validated_supported_destination",not safe.is_empty())
		if not safe.is_empty():
			scene.player.global_transform=Transform3D(Basis.IDENTITY,safe.point);service.after_external_teleport();await _ticks(8)
			_check("validated_external_teleport_restores_and_does_not_reattach",not service.riding and scene.player.global_position.distance_to(safe.point)<.15 and scene.player.is_physics_processing() and not scene.player.facility_control and not scene.player.get_collision_exceptions().has(body))
	_check("native_pair_publication_does_not_kick_parked_car",maximum_post_exit_idle_step_m<.002 and service._collision_release_pending.is_empty(),{"maximum_post_exit_idle_step_m":maximum_post_exit_idle_step_m})
	var plaza: Vector3=scene.city.to_global(Vector3(0,0,0));var nonfinite:=Vector3(INF,0,0)
	_check("road_only_permission_rejects_plaza_nonfinite_and_outside",not service._source_allowed(plaza) and not service._source_allowed(nonfinite) and not service._source_allowed(Vector3(9999,0,9999)),{"plaza":plaza})
	var private_checked:=0;var private_rejected:=0
	for polygon: Array in scene.city.private_cache:
		if polygon.is_empty():continue
		var center:=Vector2.ZERO
		for point: Vector2 in polygon[0]:center+=point
		center/=maxi(1,polygon[0].size())
		if scene.city._contains(center,[polygon]):
			private_checked+=1
			if not service._source_allowed(scene.city.to_global(Vector3(center.x,0,center.y))):private_rejected+=1
	_check("actual_private_building_rings_remain_forbidden",private_checked>0 and private_checked==private_rejected,{"checked":private_checked,"rejected":private_rejected})
	_check("original_AI_cars_and_source_route_bindings_retained_after_drive",service.source_ai_car_count_before==14 and scene.vehicles.size()+scene.neighborhood_population.traffic.vehicles.size()==14 and service.placement_audit[0].source_feature_id=="osm:way:1084408283:highway_line")
	_finish()
