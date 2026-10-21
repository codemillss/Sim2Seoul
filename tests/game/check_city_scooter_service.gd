extends SceneTree
## Production scooter/controller verification. Only player observer starts and
## named blocking fixtures are placed; scooter motion remains move_and_slide.
class HeldMovementFixture extends Node:
	var harness: SceneTree
	func _physics_process(_delta: float) -> void:harness.call("_refresh_held_actions")
var scene: Node3D
var service: Node3D
var checks: Array=[]
var report_path:="/tmp/sim2seoul-city-scooters.json"
var started:=0
var _fixtures: Array[Node3D]=[]
var captures: Array=[]
var finished:=false
var maximum_post_exit_idle_step_m:=0.0
var _previous_scooter_position:=Vector3.INF
var _was_riding:=false
var _exit_watch_ticks:=0
var _loaded_hashes: Dictionary={}
var _held_actions: Dictionary={}
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	for action: String in ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	var held_fixture:=HeldMovementFixture.new();held_fixture.name="TestOnlyHeldMovementFixture";held_fixture.harness=self;held_fixture.process_physics_priority=-200;held_fixture.process_mode=Node.PROCESS_MODE_ALWAYS;root.add_child(held_fixture)
	Engine.max_fps=0;started=Time.get_ticks_msec();create_timer(420.,true,false,true).timeout.connect(func()->void:
		if not finished:_check("bounded_test_timeout",false);_finish()
	);_run.call_deferred()
func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Transform3D:return {"origin":_json(value.origin),"basis":[_json(value.basis.x),_json(value.basis.y),_json(value.basis.z)]}
	if value is Dictionary:
		var out: Dictionary={}
		for key: Variant in value:out[str(key)]=_json(value[key])
		return out
	if value is Array:
		var out: Array=[]
		for item: Variant in value:out.append(_json(item))
		return out
	if value is float:return value if is_finite(value) else null
	return value
func _input_hashes() -> Dictionary:
	var result: Dictionary={}
	for path: String in ["res://scripts/city_scooter_service.gd","res://scripts/city_bike_service.gd","res://assets/authored/scooter_service.json","res://assets/authored/bike_service.json","res://scripts/transport_motion_policy.gd","res://scripts/explore_walk.gd","res://scripts/interior_visit.gd","res://scripts/city_bus_service.gd","res://scripts/street_network_detail.gd","res://assets/authored/road_furniture.json","res://../tests/game/check_city_scooter_service.gd","res://resources/world_geometry/world.json","res://data/generated/public_walk.json","res://data/generated/terrain_surface.json"]:
		result[path]=FileAccess.get_sha256(path)
	return result
func _check(name: String,ok: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":name,"passed":ok,"evidence":_json(evidence)});print("SCOOTER_CHECK ",name," ",ok)
	if not ok:push_warning("SCOOTER_CHECK_FAIL "+name)
func _ticks(count: int) -> void:
	for index: int in range(count):
		await scene.rig.camera_stepped
		if is_instance_valid(service) and service.loaded and not service.bikes.is_empty():
			var at: Vector3=service.bikes[0].body.global_position
			if _was_riding and not service.riding:_exit_watch_ticks=6
			elif _exit_watch_ticks>0:
				if _previous_scooter_position.is_finite():maximum_post_exit_idle_step_m=maxf(maximum_post_exit_idle_step_m,Vector2(at.x-_previous_scooter_position.x,at.z-_previous_scooter_position.z).length())
				_exit_watch_ticks-=1
			_previous_scooter_position=at;_was_riding=service.riding
func _key(action: String,pressed: bool) -> void:
	if action in ["move_left","move_right","move_forward","move_backward","move_fast","jump"]:
		if pressed:_held_actions[action]=true
		else:_held_actions.erase(action);Input.action_release(action)
	var event:=InputEventAction.new();event.action=action;event.pressed=pressed;event.device=42;Input.parse_input_event(event)
func _refresh_held_actions() -> void:
	# A native focus notification may clear Godot's injected action state.
	# Maintain only this test's explicit held movement/brake fixture; leave
	# production focus handling and real physical E edge/release events intact.
	for action: String in _held_actions:Input.action_press(action)
func _tap_e(device:=0) -> void:
	var event:=InputEventKey.new();event.keycode=KEY_E;event.physical_keycode=KEY_E;event.device=device;event.pressed=true;Input.parse_input_event(event)
	await _ticks(3);event=InputEventKey.new();event.keycode=KEY_E;event.physical_keycode=KEY_E;event.device=device;event.pressed=false;Input.parse_input_event(event);await _ticks(4)
func _fixture(at: Vector3,size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();body.name="ScooterTestBlocker";body.collision_layer=1;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;body.add_child(shape);scene.add_child(body);body.global_position=at;_fixtures.append(body);return body
func _clear_fixtures() -> void:
	for body: Node3D in _fixtures:body.queue_free()
	_fixtures.clear();await _ticks(3)
func _capture(title: String,rider:=false,preserve_camera:=false) -> void:
	if DisplayServer.get_name()=="headless":return
	var body: CharacterBody3D=service.bikes[0].body
	if not preserve_camera:
		if rider:scene.rig.yaw=service.bikes[0].yaw+.55
		else:
			var toward: Vector3=body.global_position-body.global_basis.z*.9;var direction: Vector3=toward-scene.player.global_position;direction.y=0.;scene.rig.yaw=atan2(-direction.x,-direction.z)
		scene.rig.pitch=deg_to_rad(-13.);scene.rig.requested_distance=4.7;scene.rig.current_distance=4.7;scene.rig.snap_to_target_pose()
	await _ticks(3);await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();var path:=report_path.get_basename()+"_"+title+".png";var error:=image.save_png(path)
	_check("native_capture_"+title,error==OK,{"file":path,"size":[image.get_width(),image.get_height()]})
	var projection: Dictionary={}
	if preserve_camera:
		var camera: Camera3D=scene.rig.camera;var viewport:=camera.get_viewport().get_visible_rect();var rows: Array=[];var clear:=true
		for wheel: Node3D in service.bikes[0].wheels:
			var center: Vector2=camera.unproject_position(wheel.global_position);var inside: bool=not camera.is_position_behind(wheel.global_position) and viewport.grow(-12.).has_point(center);var behind_hud:=false
			for control: Control in [scene.status.get_parent(),scene.interior_visit.prompt]:
				if control.is_visible_in_tree() and control.get_global_rect().has_point(center):behind_hud=true
			clear=clear and inside and not behind_hud;rows.append({"wheel":wheel.name,"center":center,"inside_viewport_margin":inside,"behind_hud":behind_hud})
		projection={"wheels":rows,"viewport_size":viewport.size,"scope":"Wheel center projection and two existing HUD rectangles only; image review must still assess visible tyres/deck, silhouettes, text and rendering."}
		_check("native_"+title+"_both_wheel_centers_in_view_and_clear_of_HUD",clear and rows.size()==2,projection)
	if error==OK:captures.append({"file":path,"sha256":FileAccess.get_sha256(path),"camera":scene.rig.snapshot(),"production_camera_preserved":preserve_camera,"wheel_projection":projection,"rider":scene.exploration_avatar.snapshot(),"scope":"Production shortcut/mount camera without test overrides." if preserve_camera else "Diagnostic camera override, not ordinary camera acceptance. All saved images require model/human review."})

func _finish() -> void:
	if finished:return
	finished=true
	var hashes:=_input_hashes();_check("source_inputs_stable_during_actual_runtime",not _loaded_hashes.values().has("") and hashes==_loaded_hashes,{"loaded":_loaded_hashes,"finished":hashes})
	var passed:=checks.filter(func(row: Dictionary)->bool:return row.passed).size()
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Could not write scooter evidence: "+report_path);quit(2);return
	file.store_string(JSON.stringify(_json({"task":"city_scooters","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"captures":captures,"snapshot":service.snapshot() if is_instance_valid(service) else {},"maximum_post_exit_idle_step_m":maximum_post_exit_idle_step_m,"physics_hz":Engine.physics_ticks_per_second,"source_hashes":hashes,"elapsed_ms":Time.get_ticks_msec()-started,"scope":"Production native terrain, retained player capsule and actors, Physical KEY_E devices 0 and 42, InputEventAction WASD/Space, physical scooter moves/collision/support, real menu and validated cancel. Test-only player placements and blockers explicitly separate. Headless does not accept rendered appearance."}),"  "));file.close();print("SCOOTER_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)
func _run() -> void:
	_loaded_hashes=_input_hashes()
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/city-scooter-test-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8)
	service=scene.get("city_scooter_service")
	if not is_instance_valid(service):
		service=load("res://scripts/city_scooter_service.gd").new();service.name="CityScooterServiceTest";scene.add_child(service);service.setup(scene)
	_check("production_setup_two_source_bound_native_docks",scene.runtime_ok and service.loaded and service.stations.size()==2 and service.bikes.size()==2,{"runtime_error":scene.exploration_error,"scooter_error":service.load_error})
	if not scene.runtime_ok or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	_check("original30_people14_vehicles_and_native_capsule_preserved",scene.pedestrians.size()+scene.street_pedestrians.actors.size()+scene.neighborhood_population.walkers.actors.size()==30 and scene.vehicles.size()+scene.neighborhood_population.traffic.vehicles.size()==14)
	var view: Dictionary=service.viewpoint();_check("supported_clear_player_rental_start",not view.is_empty(),view)
	var nearest_bike:=INF
	for scooter_row: Dictionary in service.bikes:
		for bike_row: Dictionary in scene.city_bike_service.bikes:nearest_bike=minf(nearest_bike,scooter_row.body.global_position.distance_to(bike_row.body.global_position))
	_check("both_scooter_docks_do_not_overlap_parked_bicycles",nearest_bike>3.,{"nearest_bike_m":nearest_bike})
	var departure_offset: Vector3=scene.city_bike_service.bikes[0].body.to_local(service.bikes[0].body.global_position)
	_check("scooter_dock_leaves_bicycle_departure_corridor_open",absf(departure_offset.x)>1.5,{"scooter_in_bicycle_departure_frame":departure_offset,"minimum_lateral_clearance_m":1.5})
	_check("scooter_deck_small_wheels_stem_display_and_no_saddle",service.bikes[0].proxy.has_node("BatteryDeck") and service.bikes[0].proxy.has_node("Steering/SpeedDisplayHousing") and not service.bikes[0].proxy.has_node("Saddle"))
	if view.is_empty():_finish();return
	scene._visit_street_detail("scooter_station");await _ticks(8)
	_check("production_menu_shortcut_uses_supported_scooter_viewpoint",scene.player.global_position.distance_to(view.point)<.25 and service.can_interact(),{"expected":view.point,"actual":scene.player.global_position,"camera":scene.rig.snapshot(),"context":service._context_ready(),"nearest_index":service._nearest_bike(),"supported":service._player_supported_for_mount(),"visible":service._visible_bike(0),"player_velocity":scene.player.velocity,"facility_control":scene.player.facility_control,"player_physics":scene.player.is_physics_processing(),"hint":service.prompt_text()})
	await _capture("production_shortcut",false,true)
	await _capture("station_full_scooter")
	var body: CharacterBody3D=service.bikes[0].body;var shape_id: int=scene.player.get_node("CollisionShape").shape.get_instance_id();var layer: int=scene.player.collision_layer;var mask: int=scene.player.collision_mask
	# A real blocking wall between observer and scooter must defeat E rental.
	var middle: Vector3=scene.player.global_position.lerp(body.global_position,.5);_fixture(middle+Vector3.UP*.9,Vector3(.18,2.,1.8));await _ticks(3)
	var visible_before: bool=service.can_interact();await _tap_e();_check("native_wall_blocks_through_wall_E_rental",not visible_before and not service.riding)
	await _clear_fixtures();await _ticks(4);await _tap_e()
	_check("real_E_rents_retained_capsule_visible_rider_and_bus_lock",service.riding and not scene.player.is_physics_processing() and scene.player.facility_control and scene.exploration_avatar.visible and scene.player.collision_layer==layer and scene.player.collision_mask==mask and scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id and not scene.city_bus_service.can_interact() and not scene.city_bike_service.can_interact(),{"prompt":service.prompt_text(),"events":service.events})
	if not service.riding:_finish();return
	_check("mounted_kickstand_retracted",not service.bikes[0].kickstand.visible)
	await _capture("production_mount",true,true)
	var before: Vector3=body.global_position;var maximum_speed:=0.;var unsupported:=0;var maximum_step:=0.;var previous:=before;var forward_intent_ticks:=0;var forward_action_ticks:=0;var blocked_ticks: Dictionary={};var slide_ticks:=0
	_key("move_forward",true)
	for tick: int in range(90):
		await _ticks(1);maximum_speed=maxf(maximum_speed,service.speed_mps);maximum_step=maxf(maximum_step,body.global_position.distance_to(previous));previous=body.global_position
		if not body.is_on_floor():unsupported+=1
		if scene.input_router.movement_intent().y<-.1:forward_intent_ticks+=1
		if Input.is_action_pressed("move_forward"):forward_action_ticks+=1
		if not service.blocked_reason.is_empty():blocked_ticks[service.blocked_reason]=int(blocked_ticks.get(service.blocked_reason,0))+1
		if body.get_slide_collision_count()>1:slide_ticks+=1
	_key("move_forward",false)
	_check("W_accelerates_real_scooter_and_animates_wheels_on_terrain",body.global_position.distance_to(before)>3. and maximum_speed>2. and maximum_step<=float(service.motion_policy().maximum_speed_mps)/Engine.physics_ticks_per_second+.025 and unsupported<4 and service.bikes[0].wheel_phase>.4 and forward_action_ticks==90 and forward_intent_ticks==90,{"travel_m":body.global_position.distance_to(before),"maximum_speed_mps":maximum_speed,"maximum_step_m":maximum_step,"unsupported_ticks":unsupported,"forward_intent_ticks":forward_intent_ticks,"forward_action_ticks":forward_action_ticks,"blocked_ticks":blocked_ticks,"multiple_collision_ticks":slide_ticks,"held_input_fixture":"Test-only Node at physics priority -200 refreshes held movement/brake state with Input.action_press before the production controller; native focus handling unchanged. This is synthetic sustained movement, not a human OS key-hold acceptance. KEY_E retains actual physical press/release events.","snapshot":service.snapshot()})
	await _capture("riding_posture",true)
	# A complete physical out-and-back returns the rented bicycle through E.
	_key("jump",true);await _ticks(90);_key("jump",false)
	var reverse_start: Vector3=body.global_position;var reverse_minimum:=0.;var reverse_maximum:=0.;_key("move_backward",true)
	for tick: int in range(1000):
		await _ticks(1)
		reverse_minimum=minf(reverse_minimum,service.speed_mps);reverse_maximum=maxf(reverse_maximum,absf(service.speed_mps))
		if Vector2(body.global_position.x-service.stations[0].point.x,body.global_position.z-service.stations[0].point.z).length()<1.9:break
	_key("move_backward",false)
	_check("S_brakes_then_backs_out_at_bounded_low_speed",reverse_minimum<-.5 and reverse_maximum<=1.11 and body.global_position.distance_to(reverse_start)>.3,{"minimum_reverse_speed":reverse_minimum,"maximum_absolute_speed":reverse_maximum,"travel":body.global_position.distance_to(reverse_start),"scope":"Measured during the physical straight return to the dock, before steering and crowded terminal tests. Actor occupancy still brakes the production body."})
	_key("jump",true);await _ticks(35);_key("jump",false);await _tap_e();await _ticks(10)
	_check("physical_round_trip_E_dismount_returns_to_authored_dock",not service.riding and service.rental_index<0 and service.events.any(func(event: Dictionary)->bool:return event.event=="returned"),{"events":service.events,"scooter_position":body.global_position,"dock":service.stations[0].point})
	_check("returned_kickstand_deployed",service.bikes[0].kickstand.visible)
	await _capture("returned_after_dismount")
	await _ticks(4);await _tap_e(42)
	if not service.riding:_check("returned_scooter_can_rent_again",false);_finish();return
	_key("move_forward",true);await _ticks(90);_key("move_forward",false)
	var yaw_before: float=service.bikes[0].yaw;_key("move_right",true);await _ticks(9);_key("move_right",false);_key("move_left",true);await _ticks(9);_key("move_left",false)
	_check("AD_steers_real_heading_and_front_assembly",absf(service.bikes[0].yaw-yaw_before)>.025 and absf(service.steer_radians)>.01,{"before_yaw":yaw_before,"after_yaw":service.bikes[0].yaw,"steer":service.steer_radians})
	_key("jump",true);await _ticks(90);_key("jump",false);await _ticks(4)
	_check("standing_rider_hands_hold_grips_and_both_soles_stay_on_deck",service.maximum_hand_gap_m<.035 and service.maximum_deck_sole_height_error_m<.012 and service.maximum_deck_footprint_error_m<.002,{"maximum_hand_gap_m":service.maximum_hand_gap_m,"maximum_sole_deck_height_error_m":service.maximum_deck_sole_height_error_m,"maximum_sole_outside_deck_m":service.maximum_deck_footprint_error_m})
	_check("Space_brakes_to_full_stop_without_player_jump",absf(service.speed_mps)<.02 and body.is_on_floor() and scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id)
	var obstacle_at: Vector3=body.global_position-body.global_basis.z*1.5;obstacle_at.y=scene.terrain_surface.ground_y_world(obstacle_at)+1.;_fixture(obstacle_at,Vector3(.8,2.,.8));await _ticks(3)
	var obstacle_before: Vector3=body.global_position;_key("move_forward",true);await _ticks(100);_key("move_forward",false)
	_check("full_box_native_wall_sweep_prevents_riding_through_obstacle",body.global_position.distance_to(obstacle_before)<.4 and service.blocked_reason=="physical_sweep",{"distance":body.global_position.distance_to(obstacle_before),"reason":service.blocked_reason})
	await _clear_fixtures()
	var frozen: Transform3D=body.global_transform;var clock: float=service._clock;scene.toggle_menu()
	for frame: int in range(18):await process_frame
	_check("actual_menu_freezes_scooter_clock_rider_and_pose",body.global_transform==frozen and service._clock==clock and paused)
	scene.toggle_menu();await _ticks(5)
	# All supported dismount candidates are deliberately blocked by real boxes.
	for offset: Vector3 in [Vector3(.95,0,.1),Vector3(-.95,0,.1),Vector3(.95,0,1.05),Vector3(-.95,0,1.05),Vector3(0,0,1.65)]:
		var at: Vector3=body.global_position+body.global_basis*offset;at.y=scene.terrain_surface.ground_y_world(at)+1.;_fixture(at,Vector3(.8,2.,.8))
	await _ticks(4);await _tap_e();await _ticks(20)
	_check("blocked_native_dismount_keeps_rider_attached_and_capsule_safe",service.riding and service.exit_requested and not scene.player.is_physics_processing() and service.blocked_reason=="dismount_blocked")
	await _tap_e();_check("blocked_dismount_request_can_cancel_to_continue",service.riding and not service.exit_requested)
	await _clear_fixtures();await _tap_e();await _ticks(12)
	_check("safe_E_dismount_restores_original_player_control_and_masks",not service.riding and scene.player.is_physics_processing() and not scene.player.facility_control and scene.player.collision_layer==layer and scene.player.collision_mask==mask and scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id)
	if service.rental_index<0:
		_check("ride_travel_left_first_dock_for_temporary_stop",false);_finish();return
	await _ticks(5);await _tap_e();_check("temporary_parked_scooter_E_remounts",service.riding)
	if not service.riding:_finish();return
	# Reverse capability was measured on the straight physical return above.
	# At this later terminal point, a real pedestrian can occupy the departure
	# box; stopping for that person must not fail an empty-space speed test.
	_key("jump",true);await _ticks(30);_key("jump",false);await _ticks(4)
	# Commit a validated external destination first, then cancel exactly once.
	var safe: Dictionary=scene.interior_visit._safe_external_point(service.stations[0].point+Vector3(0,0,2.2))
	if safe.is_empty():safe=scene.interior_visit._safe_external_point(view.point)
	_check("external_cancel_fixture_has_positive_support",not safe.is_empty())
	if not safe.is_empty():
		scene.player.global_transform=Transform3D(Basis.IDENTITY,safe.point);service.cancel_ride_for_teleport();await _ticks(6)
		_check("validated_external_teleport_restores_and_does_not_reattach",not service.riding and scene.player.global_position.distance_to(safe.point)<.15 and scene.player.is_physics_processing() and not scene.player.facility_control and scene.player.collision_mask==mask and not scene.player.get_collision_exceptions().has(body))
	_check("native_published_exit_and_cancel_do_not_kick_parked_scooter",maximum_post_exit_idle_step_m<.002 and service._collision_release_pending.is_empty(),{"maximum_post_exit_idle_step_m":maximum_post_exit_idle_step_m,"pending_release_count":service._collision_release_pending.size()})
	# Both authored docks must accept the actual keyboard E, not only the
	# first shortcut. Only the pedestrian fixture is repositioned here.
	var second: CharacterBody3D=service.bikes[1].body;var second_start:=false
	for offset: Vector3 in [Vector3(1.9,0,.1),Vector3(-1.9,0,.1),Vector3(0,0,1.9),Vector3(0,0,-1.9)]:
		var start: Dictionary=scene.interior_visit._safe_external_point(second.global_position+second.global_basis*offset)
		if start.is_empty():continue
		scene.player.global_transform=Transform3D(Basis.IDENTITY,start.point);scene.player.require_neutral_input();scene.player.reset_physics_interpolation();await _ticks(6)
		if service._nearest_bike()==1 and service.can_interact():second_start=true;break
	if second_start:await _tap_e(42)
	_check("second_stonewall_dock_physical_E_device42_rents_correct_scooter",second_start and service.riding and service.rental_index==1,{"rental_index":service.rental_index,"prompt":service.prompt_text()})
	if service.riding:
		await _tap_e();await _ticks(12)
	_check("second_dock_E_returns_and_restores_native_control",not service.riding and service.rental_index<0 and scene.player.is_physics_processing() and not scene.player.facility_control and service._collision_release_pending.is_empty())
	# Boundary checks on actual retained source geometry, including private rings.
	var rejected:=0;var candidates:=0
	for polygon: Array in scene.city.private_cache:
		if polygon.is_empty():continue
		var center:=Vector2.ZERO
		for point: Vector2 in polygon[0]:center+=point
		center/=maxi(1,polygon[0].size())
		if scene.city._contains(center,[polygon]):
			candidates+=1
			if not service._source_allowed(scene.city.to_global(Vector3(center.x,0,center.y))):rejected+=1
	_check("retained_private_source_exclusions_reject_riding_footprint",candidates>=1 and rejected==candidates,{"valid_private_interiors":candidates,"private_interiors_rejected":rejected})
	_finish()
