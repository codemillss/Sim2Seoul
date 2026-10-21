extends SceneTree
## Production controller/KEY_E; explicit observer placements and test blockers.
## Headless synthetic physical keys do not establish ordinary OS key acceptance.
class HeldActions extends Node:
	var harness: SceneTree
	func _physics_process(_delta: float) -> void:
		if is_instance_valid(harness):harness._refresh_inputs()
var scene: Node3D
var service: Node3D
var checks: Array[Dictionary]=[]
var captures: Array[Dictionary]=[]
var held: Dictionary={}
var report_path:="/tmp/sim2seoul-subway.json"
var finished:=false
var started:=0
var source_hashes: Dictionary={}
var source_node_ids: Dictionary={}
var capsule_id:=0
var exterior_layer:=0
var exterior_mask:=0
var exterior_camera_excludes: Array=[]
var fixtures: Array[Node3D]=[]
var only_transitions:=false
var only_setup:=false
var _deadline: SceneTreeTimer
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
		if arg=="--only-transitions":only_transitions=true
		if arg=="--only-setup":only_setup=true
	for action: String in ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	var fixture:=HeldActions.new();fixture.name="TestOnlyHeldSubwayInput";fixture.harness=self;fixture.process_physics_priority=-200;fixture.process_mode=Node.PROCESS_MODE_ALWAYS;root.add_child(fixture)
	started=Time.get_ticks_msec();_deadline=create_timer(420.,true,false,true);_deadline.timeout.connect(func()->void:
		if not finished:_check("bounded_timeout",false);_finish()
	);_run.call_deferred()
func _refresh_inputs() -> void:
	for action: StringName in held:Input.action_press(action)
func _key(action: StringName,down: bool) -> void:
	if down:held[action]=true
	else:held.erase(action);Input.action_release(action)
func _e(down: bool,device:=42) -> void:
	var event:=InputEventKey.new();event.keycode=KEY_E;event.physical_keycode=KEY_E;event.device=device;event.pressed=down;Input.parse_input_event(event)
func _tap_e(device:=42) -> void:_e(true,device);await _ticks(3);_e(false,device);await _ticks(5)
func _ticks(count: int) -> void:
	for tick: int in range(count):await physics_frame
func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Transform3D:return {"origin":_json(value.origin),"basis":[_json(value.basis.x),_json(value.basis.y),_json(value.basis.z)]}
	if value is Dictionary:
		var output: Dictionary={}
		for key: Variant in value:output[str(key)]=_json(value[key])
		return output
	if value is Array:
		var output: Array=[]
		for item: Variant in value:output.append(_json(item))
		return output
	if value is float:return value if is_finite(value) else null
	return value
func _hashes() -> Dictionary:
	var result: Dictionary={}
	for path: String in ["res://scripts/city_subway_service.gd","res://assets/authored/subway_service.json","res://../tests/game/check_city_subway.gd","res://resources/world_geometry/world.json","res://scripts/player/free_roam_player.gd"]:result[path]=FileAccess.get_sha256(path)
	return result
func _check(title: String,ok: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":ok,"evidence":_json(evidence)});print("SUBWAY_CHECK ",title," ",ok)
func _place(point: Vector3) -> void:
	scene.player.global_position=point;scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();await _ticks(7)
func _fixture(point: Vector3,size: Vector3,basis:=Basis.IDENTITY) -> StaticBody3D:
	var body:=StaticBody3D.new();body.name="TestOnlySubwayBlocker";body.collision_layer=1;body.collision_mask=0;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;body.add_child(shape);scene.add_child(body);body.global_transform=Transform3D(basis,point);fixtures.append(body);return body
func _clear_fixtures() -> void:
	for body: Node3D in fixtures:body.queue_free()
	fixtures.clear();await _ticks(4)
func _capture(title: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await _ticks(3);await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();var path:=report_path.get_basename()+"_"+title+".png";var error:=image.save_png(path)
	_check("native_capture_"+title,error==OK)
	if error==OK:captures.append({"file":path,"sha256":FileAccess.get_sha256(path),"player":scene.player.global_position,"camera":scene.rig.snapshot(),"subway":service.snapshot(),"scope":"Production rig with explicit source entrance observer fixture initially; intervening station/stair walks use actual W controller. Native image review remains separate; no OS keyboard claim."})
func _walk_toward(point: Vector3,seconds: float) -> Dictionary:
	var start: Vector3=scene.player.global_position;var samples: Array=[];var recovery_start: int=scene.player.recoveries
	# Budget follows retained walking profile; initial failed run used 10s
	# for a 25m ascent at 2.24m/s and simply ran out of observation time.
	var delta: Vector3=point-start;seconds=maxf(seconds,Vector2(delta.x,delta.z).length()/maxf(.2,scene.player.walk_speed_mps)+3.)
	_key("move_forward",true)
	for tick: int in range(int(ceil(seconds*Engine.physics_ticks_per_second))):
		var offset: Vector3=point-scene.player.global_position
		if Vector2(offset.x,offset.z).length()<.28:break
		scene.rig.yaw=atan2(-offset.x,-offset.z)
		await _ticks(1)
		if tick%6==0:samples.append(scene.player.global_position)
	_key("move_forward",false);await _ticks(5)
	return {"from":start,"to":scene.player.global_position,"target":point,"distance":scene.player.global_position.distance_to(point),"recoveries":scene.player.recoveries-recovery_start,"samples":samples,"walking_profile_mps":scene.player.walk_speed_mps,"observation_budget_s":seconds}
func _wait_open(index: int,seconds:=100.) -> bool:
	for tick: int in range(int(seconds*Engine.physics_ticks_per_second)):
		if service.docked_station==index and service.train_state=="doors_open" and service.door_fraction>.98:return true
		await _ticks(1)
	return false
func _trip_to(index: int,seconds:=100.) -> Dictionary:
	var start: Vector3=service.train.global_position;var previous:=start;var travel:=0.;var greatest:=0.;var attach_error:=0.;var trace: Array=[];var arrived:=false
	for tick: int in range(int(seconds*Engine.physics_ticks_per_second)):
		await _ticks(1)
		var current: Vector3=service.train.global_position;var step: float=current.distance_to(previous);travel+=step;greatest=maxf(greatest,step);previous=current
		if service.riding:attach_error=maxf(attach_error,scene.player.global_position.distance_to(service.train.to_global(Vector3(-2.,.16,0.))))
		if tick%10==0:trace.append({"tick":tick,"state":service.train_state,"point":current,"station_m":service.station_m,"speed_mps":service.speed_mps,"blocked":service.blocked_reason})
		if service.docked_station==index and service.train_state=="doors_open":arrived=true;break
	return {"arrived":arrived,"physical_travel_m":travel,"largest_frame_step_m":greatest,"attachment_error_m":attach_error,"from":start,"to":service.train.global_position,"trace":trace,"policy":service.motion_policy()}
func _finish() -> void:
	if finished:return
	finished=true
	for action: StringName in held:Input.action_release(action)
	held.clear()
	if not source_node_ids.is_empty():
		var current: Dictionary={}
		for key: Variant in scene.city.source_nodes:current[str(key)]=scene.city.source_nodes[key].get_instance_id()
		_check("same_original_source_nodes_and_player_capsule",current==source_node_ids and scene.player.get_node("CollisionShape").shape.get_instance_id()==capsule_id)
	_check("module_and_original_inputs_stable_during_run",_hashes()==source_hashes and not source_hashes.values().has(""),{"loaded":source_hashes,"finished":_hashes()})
	if is_instance_valid(root.get_node_or_null("TestOnlyHeldSubwayInput")):
		var fixture: Node=root.get_node("TestOnlyHeldSubwayInput");fixture.set_physics_process(false);fixture.harness=null;fixture.free()
	if is_instance_valid(_deadline):
		for connection: Dictionary in _deadline.timeout.get_connections():_deadline.timeout.disconnect(connection.callable)
		_deadline=null
	var passed: int=checks.filter(func(row: Dictionary)->bool:return bool(row.passed)).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot save subway report: "+report_path);quit(2);return
	file.store_string(JSON.stringify(_json({"task":"source_linked_game_subway","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"captures":captures,"snapshot":service.snapshot() if is_instance_valid(service) else {},"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"physics_hz":Engine.physics_ticks_per_second,"recorded_at":Time.get_datetime_string_from_system(),"elapsed_ms":Time.get_ticks_msec()-started,"source_sha256":source_hashes,"scope":"Production source scene/terrain/capsule. Synthetic physical KEY_E devices 42 and 0, actual W-controller station stairs and continuously moving train. Explicit initial and second-leg observer placements and blockers labelled. Retained original entrance identities; authored underground plans and regional game timetable/route, no real full station/service accuracy. Headless is not visible-layout or ordinary OS control proof."}),"  "));file.close();print("SUBWAY_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)
func _run() -> void:
	source_hashes=_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/subway-test-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(10)
	service=scene.get("city_subway_service")
	if not is_instance_valid(service):service=load("res://scripts/city_subway_service.gd").new();scene.set("city_subway_service",service);scene.add_child(service);service.setup(scene)
	_check("production_setup_two_source_bound_game_stations",scene.runtime_ok and service.loaded and service.stations.size()==2,{"runtime_error":scene.exploration_error,"subway_error":service.load_error})
	if not scene.runtime_ok or not service.loaded:_finish();return
	for key: Variant in scene.city.source_nodes:source_node_ids[str(key)]=scene.city.source_nodes[key].get_instance_id()
	capsule_id=scene.player.get_node("CollisionShape").shape.get_instance_id();exterior_layer=scene.player.collision_layer;exterior_mask=scene.player.collision_mask;exterior_camera_excludes=scene.rig._query.exclude.duplicate()
	if scene.menu.visible:scene.toggle_menu()
	await _ticks(5)
	if only_setup:_finish();return
	if only_transitions:
		await _shortcut_regression();_finish();return
	var city: Dictionary=service.stations[0];var east: Dictionary=service.stations[1];var destination: Dictionary=service.destination("subway_cityhall");var east_destination: Dictionary=service.destination("subway_euljiro")
	_check("both_original_entrances_have_safe_supported_approaches",not destination.is_empty() and not east_destination.is_empty(),{"city":destination,"east":east_destination})
	_check("source_way_regional_segment_and_entrance_identity_scope",absf(service.route_length_m-338.33574085225547)<.001 and int(city.entrance.osm_node_id)==3404904655 and int(east.entrance.osm_node_id)==8212227135 and east.source_station==null,{"length":service.route_length_m,"scope":service.design.scope})
	if destination.is_empty() or east_destination.is_empty():_finish();return
	await _place(destination.point);service._orient(city.portal.global_transform,5.0);await _capture("cityhall_source_exit")
	_check("grounded_source_entrance_actionable",service.can_interact(),{"position":scene.player.global_position,"hint":service.prompt_text()})
	_fixture(city.anchor+city.outward*.7+Vector3.UP*1.1,Vector3(3.,2.2,.14),city.portal.global_basis);await _ticks(3)
	await _tap_e();_check("wall_blocks_through_wall_station_entry",not service.active and not service.can_interact())
	await _clear_fixtures();await _place(destination.point)
	scene.toggle_menu();_e(true);await _ticks(3);scene.toggle_menu();await _ticks(4);_check("E_held_through_menu_does_not_enter",not service.active);_e(false);await _ticks(4);await _tap_e()
	_check("physical_E_enters_only_subway_with_original_native_controller",service.active and not service.riding and scene.player.interior_active and not scene.interior_visit.active and not scene.shop_visit_service.active and not scene.player.facility_control,service.snapshot())
	if not service.active:_finish();return
	await _capture("cityhall_concourse")
	var before: Dictionary=service.snapshot();var invalid: bool=service.leave_for_teleport(Vector3(100000.,0.,100000.));_check("invalid_external_exit_preserves_station_and_control",not invalid and service.active and service.visit_station==int(before.visit_station) and scene.player.interior_active)
	var walk: Dictionary=await _walk_toward(city.gate,3.);_check("actual_controller_walk_to_ticket_gate",float(walk.distance)<.8 and int(walk.recoveries)==0,walk)
	await _tap_e(0);_check("physical_E_opens_native_card_gate",city.gate_open,{"hint":service.prompt_text()})
	walk=await _walk_toward(city.frame*Vector3(0.,.08,12.2),8.);_check("actual_controller_walks_down_continuous_stair_support",float(walk.distance)<.9 and int(walk.recoveries)==0,walk)
	walk=await _walk_toward(city.wait,5.);_check("actual_controller_reaches_tactile_platform_and_waiting_door",float(walk.distance)<.9 and int(walk.recoveries)==0,walk)
	await _capture("cityhall_platform")
	if service.docked_station!=0 or service.train_state!="doors_open":
		await _tap_e();_check("E_waiting_at_closed_or_away_train_never_boards",not service.riding and service.active and not scene.player.facility_control,service.snapshot())
	var open: bool=await _wait_open(0);_check("cyclic_train_returns_to_cityhall_open",open,service.snapshot())
	if not open:_finish();return
	_fixture(service.train.to_global(Vector3(-2.,1.0,0.)),Vector3(1.3,2.,1.3));await _ticks(3);await _tap_e()
	_check("native_blocked_cabin_refuses_board_without_changing_owner",not service.riding and service.active and scene.player.is_physics_processing() and not scene.player.facility_control)
	await _clear_fixtures()
	await _tap_e();_check("physical_E_boards_train_same_capsule_and_other_transport_mutex",service.riding and scene.player.facility_control and not scene.player.is_physics_processing() and scene.player.get_node("CollisionShape").shape.get_instance_id()==capsule_id and not scene.city_bike_service.can_interact() and not scene.city_scooter_service.can_interact() and not scene.city_bus_service.can_interact() and not scene.drivable_car_service.can_interact() and not scene.city_helicopter_service.can_interact(),service.snapshot())
	if not service.riding:_finish();return
	await _capture("train_cabin")
	var paused_point: Vector3=service.train.global_position;var paused_clock: float=service.state_elapsed;scene.toggle_menu();await _ticks(15);_check("menu_pauses_train_clock_and_native_motion",service.train.global_position.distance_to(paused_point)<.0001 and service.state_elapsed==paused_clock);scene.toggle_menu();await _ticks(2)
	var trip: Dictionary=await _trip_to(1);_check("source_curved_track_continuous_native_train_move_to_east",trip.arrived and float(trip.physical_travel_m)>330. and float(trip.largest_frame_step_m)<3. and float(trip.attachment_error_m)<.02,trip)
	if not trip.arrived:_finish();return
	await _tap_e(0);await _ticks(6);_check("E_disembarks_other_station_restores_walk_and_native_collision",not service.riding and service.active and service.visit_station==1 and scene.player.is_physics_processing() and not scene.player.facility_control and not service._release_pending,service.snapshot())
	await _capture("euljiro_platform")
	walk=await _walk_toward(east.frame*Vector3(0.,3.08,28.5),10.);_check("actual_controller_walks_other_station_stairs_up",float(walk.distance)<.9 and int(walk.recoveries)==0,walk)
	walk=await _walk_toward(east.exit,3.);_check("actual_controller_reaches_original_east_surface_exit",float(walk.distance)<.9 and int(walk.recoveries)==0,walk)
	await _tap_e();_check("E_exits_to_original_euljiro_1_1_source_entrance",not service.active and not scene.player.interior_active and scene.player.global_position.distance_to(east_destination.point)<2.0 and scene.player.is_physics_processing(),{"player":scene.player.global_position,"exit":east_destination.point})
	await _capture("euljiro_source_exit")
	if service.active:_finish();return
	await _tap_e(0);_check("same_east_entrance_reusable_for_return_visit",service.active and service.visit_station==1)
	if not service.active:_finish();return
	# Return-leg observer fixture shortens repeated walking; first leg above
	# already covers actual upper/lower controller walks and native gate E.
	east.gate_open=true;service._update_doors();await _place(east.wait)
	open=await _wait_open(1);_check("two_terminal_train_available_for_return_leg",open)
	if not open:_finish();return
	await _tap_e();_check("physical_E_boards_return_train",service.riding)
	if not service.riding:_finish();return
	trip=await _trip_to(0);_check("continuous_return_leg_cityhall_and_repeating_service",trip.arrived and float(trip.physical_travel_m)>330. and float(trip.largest_frame_step_m)<3. and service.completed_legs>=2,trip)
	var passenger: Vector3=scene.player.global_position;invalid=service.leave_for_teleport(Vector3(100000.,0.,100000.));_check("blocked_teleport_preserves_rider_train_and_controls",not invalid and service.active and service.riding and scene.player.facility_control and scene.player.global_position.distance_to(passenger)<.01)
	scene.reset_player();await _ticks(8);var returned: bool=not service.active;_check("validated_reset_restores_world_player_camera_and_control",returned and not service.active and not service.riding and not scene.player.interior_active and not scene.player.facility_control and scene.player.is_physics_processing() and not service._release_pending and scene.player.get_node("CollisionShape").shape.get_instance_id()==capsule_id and _exterior_controls_exact(),service.snapshot())
	await _shortcut_regression()
	_finish()

func _exterior_controls_exact() -> bool:
	return scene.player.collision_layer==exterior_layer and scene.player.collision_mask==exterior_mask and scene.rig._query.exclude==exterior_camera_excludes
func _controls() -> Dictionary:
	return {"layer":scene.player.collision_layer,"mask":scene.player.collision_mask,"expected_layer":exterior_layer,"expected_mask":exterior_mask,"camera_excludes_exact":scene.rig._query.exclude==exterior_camera_excludes,"physics":scene.player.is_physics_processing(),"facility":scene.player.facility_control,"interior_active":scene.player.interior_active}
func _shortcut_regression() -> void:
	# Real production menu handlers, not direct service leave shortcuts.
	scene._visit_street_detail("subway_euljiro");await _ticks(8)
	_check("production_subway_euljiro_shortcut_reaches_source_entrance",not service.active and scene.player.global_position.distance_to(service.destination("subway_euljiro").get("point",Vector3.INF))<1. and _exterior_controls_exact(),_controls())
	await _tap_e();_check("production_east_shortcut_E_enters_station",service.active and service.visit_station==1)
	if not service.active:return
	var clothing: Dictionary=scene.shop_visit_service.destination("clothing")
	if not clothing.is_empty():
		_fixture(clothing.point+Vector3.UP*1.0,Vector3(12.,3.,12.));await _ticks(4)
		var retained: Vector3=scene.player.global_position;scene._visit_street_detail("clothing");await _ticks(5)
		_check("blocked_production_clothing_shortcut_preserves_metro_owner",service.active and scene.player.interior_active and not scene.shop_visit_service.active and scene.player.global_position.distance_to(retained)<.02 and scene.player.is_physics_processing() and not scene.player.facility_control and _exterior_controls_exact(),_controls())
		await _clear_fixtures()
	scene._visit_street_detail("clothing");await _ticks(8)
	_check("walking_metro_to_clothing_shortcut_restores_exact_exterior_controls",not service.active and not scene.player.interior_active and not scene.player.facility_control and scene.player.is_physics_processing() and _exterior_controls_exact(),_controls())
	await _tap_e();_check("clothing_shop_reusable_after_subway_visit",scene.shop_visit_service.active and scene.shop_visit_service.current_shop_id=="citywear_game_clothing",{"shop_id":scene.shop_visit_service.current_shop_id})
	scene._visit_street_detail("subway_cityhall");await _ticks(8);await _tap_e()
	_check("shop_to_subway_production_transition_transfers_owner_once",service.active and service.visit_station==0 and not scene.shop_visit_service.active and not scene.shop_visit_service.ui_open and not scene.player.facility_control and scene.player.is_physics_processing() and _exterior_controls_exact(),_controls())
	if not service.active:return
	var roof: Dictionary=scene.exploration_rooftop_access.representative_pool_destination();scene._visit_street_detail("hotel_pool");await _ticks(8)
	_check("walking_metro_to_pool_shortcut_preserves_authored_roof_height_and_mask",not service.active and not service.riding and not roof.is_empty() and absf(scene.player.global_position.y-roof.get("pool_entry",Vector3.INF).y)<.25 and not scene.player.interior_active and service._supported(scene.player.global_position) and not scene.player.facility_control and scene.player.is_physics_processing() and _exterior_controls_exact(),_controls().merged({"player":scene.player.global_position,"roof_entry":roof.get("pool_entry",Vector3.INF)}))
	scene._visit_street_detail("subway_euljiro");await _ticks(8)
	_check("pool_to_subway_shortcut_clears_pool_owner_and_restores_native_player",not service.active and not scene.player.interior_active and not scene.shop_visit_service.swimwear_active and scene.player.is_physics_processing() and not scene.player.facility_control and _exterior_controls_exact(),_controls())
	await _tap_e();if not service.active:return
	# Fixture observer only for final rider->shortcut restoration regression.
	var station: Dictionary=service.stations[1];station.gate_open=true;service._update_doors();await _place(station.wait)
	var ready: bool=await _wait_open(1)
	if not ready:_check("rider_shortcut_fixture_train_available",false,service.snapshot());return
	await _tap_e();_check("rider_shortcut_fixture_boarded",service.riding)
	if not service.riding:return
	scene._visit_street_detail("clothing");await _ticks(8)
	_check("riding_metro_to_clothing_shortcut_restores_exact_exterior_controls",not service.active and not service.riding and not service._release_pending and not scene.player.interior_active and not scene.player.facility_control and scene.player.is_physics_processing() and _exterior_controls_exact(),_controls())

	scene._visit_street_detail("subway_cityhall");await _ticks(8);await _tap_e()
	var reset_entered: bool=service.active;scene.reset_player();await _ticks(8)
	_check("production_reset_handler_leaves_walking_subway_and_restores_controls",reset_entered and not service.active and not service.riding and not scene.player.interior_active and not scene.player.facility_control and scene.player.is_physics_processing() and _exterior_controls_exact(),_controls())
