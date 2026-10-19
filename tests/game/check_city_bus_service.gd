extends SceneTree
## The bus is never repositioned: follow the live physical route/stop/door ride.
var scene: Node3D
var service: Node3D
var checks: Array=[]
var report_path:=""
var started:=0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	if report_path.is_empty():report_path="/tmp/sim2seoul-city-bus.json"
	for action: String in ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	started=Time.get_ticks_msec();_run.call_deferred()

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

func _check(title: String,ok: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":ok,"evidence":_json(evidence)})
	print("BUS_CHECK ",title," ",ok)
	if not ok:push_warning("BUS_CHECK_FAILED "+title)

func _ticks(count: int) -> void:
	# Never wait on a render frame between physical ticks: an overloaded render
	# may legitimately contain several ticks and otherwise skip the red interval.
	for tick: int in range(count):await physics_frame

func _tap_e() -> void:
	var press:=InputEventAction.new();press.action="interact";press.pressed=true;press.device=42;Input.parse_input_event(press);await _ticks(2)
	var release:=InputEventAction.new();release.action="interact";release.pressed=false;release.device=42;Input.parse_input_event(release);await _ticks(2)

func _pose_world(requested: Vector3) -> Dictionary:
	var safe: Dictionary=scene.interior_visit._safe_external_point(requested)
	if safe.is_empty():return {}
	scene.player.global_transform=Transform3D(Basis.IDENTITY,safe.point);scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();await _ticks(8)
	return safe

func _pose_door(local: Vector3) -> Dictionary:
	var point: Vector3=service.bus.to_global(Vector3(local.x,0,local.z));point.y=scene.terrain_surface.ground_y_world(point)+.08
	return await _pose_world(point)

func _boarding_positions() -> void:
	service.set_running(false)
	var poses: Array=[{"id":"front_very_close","local":Vector3(1.60,0,-2.95),"door":0},{"id":"front_corner_approach","local":Vector3(2.2,0,-4.65),"door":0},{"id":"front_outer_wait","local":Vector3(3.2,0,-2.7),"door":0},{"id":"middle_very_close","local":Vector3(1.60,0,.55),"door":1},{"id":"middle_outer_approach","local":Vector3(2.9,0,1.8),"door":1},{"id":"between_visible_doors","local":Vector3(2.25,0,-1.2),"door":-1}]
	for pose: Dictionary in poses:
		var bus_before: Vector3=service.bus.global_position
		var safe: Dictionary=await _pose_door(pose.local)
		var before: Dictionary=service._boarding_candidate()
		await _tap_e()
		var boarded: bool=service.riding
		_check("boarding_position."+String(pose.id),not safe.is_empty() and boarded and (int(pose.door)<0 or int(service._last_board_door)==int(pose.door)),{"safe":safe,"candidate":before,"state":service.snapshot()})
		if boarded:await _tap_e()
		await _ticks(4)
		_check("native_exit_keeps_docked_bus_on_source_route."+String(pose.id),not service.riding and not service._collision_release_pending and scene.player.is_physics_processing() and service.bus._state!="off_route" and Vector2(service.bus.global_position.x-bus_before.x,service.bus.global_position.z-bus_before.z).length()<.002 and service.bus._max_step_m<.10,{"bus":service.bus.snapshot(),"before":bus_before,"collision_release_pending":service._collision_release_pending})
		if service.riding:
			var outside: Dictionary=scene.interior_visit._safe_external_point(service.design.stops[0].wait_world)
			if not outside.is_empty():scene.player.global_position=outside.point;service.cancel_ride_for_teleport()
	var wrong_side: Dictionary=await _pose_door(Vector3(-2.2,0,-2.95));await _tap_e()
	_check("boarding_denied.opposite_side_of_bus",not wrong_side.is_empty() and not service.riding and not service.can_interact(),{"safe":wrong_side,"hint":service.prompt_text()})
	await _pose_door(Vector3(2.2,0,.55));scene.player.set_physics_process(false);scene.player.global_position.y+=1.0;await _ticks(2);await _tap_e()
	_check("boarding_denied.airborne_despite_old_floor_flag",not service.riding and not service.can_interact(),{"hint":service.prompt_text(),"point":scene.player.global_position})
	scene.player.set_physics_process(true)
	var wall:=StaticBody3D.new();wall.name="ExplicitBoardingWallFixture";wall.collision_layer=1;wall.collision_mask=6
	var wall_shape:=BoxShape3D.new();wall_shape.size=Vector3(.18,2.2,1.5);var wall_collision:=CollisionShape3D.new();wall_collision.shape=wall_shape;wall_collision.position.y=1.1;wall.add_child(wall_collision);scene.add_child(wall)
	wall.global_position=service.bus.to_global(Vector3(2.3,0,.55));wall.global_position.y=scene.terrain_surface.ground_y_world(wall.global_position)+.02;wall.global_rotation.y=service.bus.global_rotation.y
	var wall_pose: Dictionary=await _pose_door(Vector3(3.5,0,.55));await _tap_e()
	_check("boarding_denied.native_wall_between_player_and_visible_door",not wall_pose.is_empty() and not service.riding and not service.can_interact(),{"safe":wall_pose,"hint":service.prompt_text()})
	wall.queue_free();await _ticks(3)
	await _pose_world(service.design.stops[0].wait_world)
	service.set_running(true);var held_station: float=service.bus.get_station_m();await _ticks(60*15)
	_check("boarding_after_original_twelve_second_dwell_stays_available",service.bus_state=="doors_open" and service.can_interact() and absf(service.bus.get_station_m()-held_station)<.001,{"elapsed_s":service.state_elapsed,"state":service.bus_state,"hint":service.prompt_text()})

func _finish() -> void:
	var passed: int=checks.filter(func(row: Dictionary):return bool(row.passed)).size()
	var paths: Array=["res://scripts/city_bus_service.gd","res://assets/authored/bus_service.json","res://scripts/traffic/vehicle.gd","res://resources/world_geometry/world.json","res://data/generated/traffic.json","res://data/generated/terrain_surface.json"]
	var hashes: Dictionary={}
	for path: String in paths:hashes[path]=FileAccess.get_sha256(path)
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json({"passed":passed,"total":checks.size(),"checks":checks,"snapshot":service.snapshot() if is_instance_valid(service) else {},"source_hashes":hashes,"elapsed_ms":Time.get_ticks_msec()-started}),"  "));file.close()
	print("BUS_RESULT ",passed,"/",checks.size()," report=",report_path)
	quit(0 if passed==checks.size() else 1)

func _run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/sim2seoul-bus-test-settings.json";scene.exploration_physics_hz=60;root.add_child(scene)
	await _ticks(6)
	_check("production_runtime_and_current_terrain_ready",scene.runtime_ok and scene.terrain_surface.loaded)
	if not scene.runtime_ok:_finish();return
	service=scene.get("city_bus_service")
	if not is_instance_valid(service):
		service=load("res://scripts/city_bus_service.gd").new();service.name="CityBusServiceTest";scene.add_child(service)
		if not service.setup(scene):_check("bus_setup",false,{"error":service.load_error});_finish();return
	if scene.menu.visible:scene.toggle_menu()
	var network: Node3D=scene.get("street_network_detail")
	if is_instance_valid(network) and network.loaded:network.advance_signal_time(29.-network.elapsed_s)
	await _ticks(6)
	_check("one_bus_two_stops_source_full_box_and_old14_preserved",service.loaded and service.shelter_nodes.size()==2 and bool(service.route_certificate.accepted) and int(service.route_certificate.samples)>350 and bool(service.snapshot().original_vehicle_ids_unchanged),service.snapshot())
	var bus: CharacterBody3D=service.bus;var shape: CollisionShape3D=bus.get_node("CollisionShape")
	_check("bus_full_collision_and_detailed_art",shape.shape.size==Vector3(2.45,3.,9.) and bus.collision_layer==8 and bus.collision_mask==63 and service.wheels.size()==4 and service.door_panels.size()==4 and bus.has_node("Visual/DestinationLED"),{"size":shape.shape.size,"mask":bus.collision_mask})
	if is_instance_valid(network) and network.loaded:
		var signal_max_speed:=0.;var signal_max_station:=0.
		for tick: int in range(360):
			await _ticks(1);signal_max_speed=maxf(signal_max_speed,bus._speed_mps);signal_max_station=maxf(signal_max_station,bus.get_station_m())
		var actual_line: Dictionary=network.vehicle_stop_distance(String(service.design.route.source_binding.feature_id),bus.global_position,bus._segment_direction(bus._segment),30.)
		_check("actual_red_signal_braking_before_full_bus_nose_crosses_stopline",bus._speed_mps<.01 and float(actual_line.get("distance_m",0.))>=4.79 and float(actual_line.get("distance_m",100.))<=4.95 and signal_max_speed>1. and bus._blocked_reason.begins_with("signal_"),{"actual_nose_clearance_m":float(actual_line.get("distance_m",0.))-4.5,"maximum_station_m":signal_max_station,"maximum_speed_mps":signal_max_speed,"bus":bus.snapshot(),"signal":network.snapshot()})
		network.advance_signal_time(46.-network.elapsed_s)
		for tick: int in range(240):
			await _ticks(1)
			if not service._crossing_commit.is_empty():break
		var committed: bool=not service._crossing_commit.is_empty();var entry_station: float=bus.get_station_m();var minimum_committed_speed:=INF
		if committed:
			network.advance_signal_time(25.-network.elapsed_s)
			for tick: int in range(180):
				await _ticks(1);minimum_committed_speed=minf(minimum_committed_speed,bus._speed_mps)
		_check("front_committed_on_green_clears_when_signal_turns_amber_then_red",committed and bus.get_station_m()-entry_station>6. and minimum_committed_speed>.25,{"entry_station_m":entry_station,"minimum_speed_mps":minimum_committed_speed,"bus":bus.snapshot(),"events":service.events})
	var moving_pose: Dictionary=await _pose_door(Vector3(2.2,0,-2.95));await _tap_e()
	_check("boarding_denied.legal_door_side_while_bus_is_actually_moving",not moving_pose.is_empty() and bus._speed_mps>.25 and not service.riding and not service.can_interact(),{"safe":moving_pose,"bus":bus.snapshot(),"hint":service.prompt_text()})
	await _pose_world(service.design.stops[0].wait_world);await _tap_e()
	_check("first_stop_wait_request_consumes_fresh_E_without_boarding_moving_bus",service.waiting_for_bus and not service.riding,{"state":service.snapshot(),"hint":service.prompt_text()})
	var start: Vector3=bus.global_position;var previous:=start;var maximum_step:=0.;var unsupported:=0;var sampled:=0;var minimum_y:=INF;var maximum_y:=-INF;var speed_path: Array=[]
	var opening_edge_accepted:=false
	# Observe real movement until the first complete docking, not a test pose.
	for tick: int in range(2700):
		await _ticks(1)
		maximum_step=maxf(maximum_step,Vector2(bus.global_position.x-previous.x,bus.global_position.z-previous.z).length());previous=bus.global_position
		minimum_y=minf(minimum_y,bus.global_position.y);maximum_y=maxf(maximum_y,bus.global_position.y)
		if tick%30==0:
			sampled+=1
			if bus._floor_reason!="up_floor_ray" and not bus.is_on_floor():unsupported+=1
			if speed_path.size()<100:speed_path.append({"tick":tick,"s":bus.get_station_m(),"speed":bus._speed_mps,"state":bus._state,"reason":bus._blocked_reason})
		if service.bus_state=="opening_doors" and not opening_edge_accepted:
			await _tap_e();opening_edge_accepted=service._board_pending or service.riding
		if service.bus_state=="doors_open" and service.docked_stop==0:break
	await _ticks(3)
	_check("fresh_E_during_actual_door_opening_completes_once_fully_open",opening_edge_accepted and service.riding,{"state":service.snapshot()})
	if service.riding:await _tap_e()
	_check("physical_approach_brake_and_first_dock",service.bus_state=="doors_open" and service.docked_stop==0 and absf(bus.get_station_m()-65.)<.02 and bus._speed_mps<.025 and bus._state!="off_route" and bus._max_step_m<.10 and bus.global_position.distance_to(start)>20. and maximum_step<.20,{"bus":bus.snapshot(),"maximum_step_m":maximum_step,"speed_path":speed_path})
	_check("current_terrain_support_during_motion",unsupported==0 and maximum_y-minimum_y>.02,{"unsupported":unsupported,"samples":sampled,"minimum_y":minimum_y,"maximum_y":maximum_y})
	if service.docked_stop!=0:_finish();return
	var frozen: Transform3D=bus.global_transform;var clock: float=service.state_elapsed;var doors: float=service.door_fraction
	service.set_running(false);await _ticks(35)
	_check("running_switch_freezes_bus_doors_clock",bus.global_transform==frozen and service.state_elapsed==clock and service.door_fraction==doors)
	service.set_running(true)
	scene.toggle_menu();await _ticks(30)
	_check("actual_menu_freezes_bus_and_door_state",bus.global_transform==frozen and service.state_elapsed==clock and service.door_fraction==doors,{"paused":paused,"state":service.bus_state})
	scene.toggle_menu()
	var wait: Vector3=service.design.stops[0].wait_world;var safe: Dictionary=scene.interior_visit._safe_external_point(wait)
	_check("first_stop_positive_support_and_native_capsule_clear",not safe.is_empty(),{"wait":wait,"safe":safe})
	if safe.is_empty():_finish();return
	await _boarding_positions()
	scene.player.global_transform=Transform3D(Basis.IDENTITY,safe.point);scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();await _ticks(4)
	var layer: int=scene.player.collision_layer;var mask: int=scene.player.collision_mask;var shape_id: int=scene.player.get_node("CollisionShape").shape.get_instance_id()
	scene.player.require_neutral_input();Input.action_press("move_forward");await _ticks(2);await _tap_e();Input.action_release("move_forward");var boarded: bool=service.riding
	_check("actual_fresh_E_board_keeps_original_capsule_and_masks",boarded and not scene.player.is_physics_processing() and scene.player.collision_layer==layer and scene.player.collision_mask==mask and scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id,service.snapshot())
	if not boarded:_finish();return
	var blocker:=StaticBody3D.new();blocker.name="ExplicitExitCapsuleBlockingFixture";blocker.collision_layer=1;blocker.collision_mask=6
	var blocker_shape:=BoxShape3D.new();blocker_shape.size=Vector3(.95,2.2,5.0);var blocker_collision:=CollisionShape3D.new();blocker_collision.shape=blocker_shape;blocker_collision.position.y=1.1;blocker.add_child(blocker_collision);scene.add_child(blocker);blocker.global_position=service.design.stops[1].wait_world
	var saw_moving_closed:=false;var saw_exit:=false;var attachment_max:=0.;var requested_exit:=false;var blocked_verified:=false
	for tick: int in range(2700):
		await _ticks(1)
		if service.riding:
			attachment_max=maxf(attachment_max,scene.player.global_position.distance_to(bus.to_global(Vector3(.35,.72,-.6))))
			if bus._speed_mps>.5 and service.door_fraction==0.:
				saw_moving_closed=true
				if not requested_exit:await _tap_e();requested_exit=true
			if service.docked_stop==1 and service.bus_state=="doors_open" and not blocked_verified:
				await _ticks(30)
				blocked_verified=service.riding and service._safe_exit().is_empty() and not scene.player.is_physics_processing()
				_check("requested_exit_holds_when_all_native_capsule_candidates_blocked",blocked_verified,{"state":service.snapshot(),"fixture":blocker.global_position})
				blocker.queue_free();await _ticks(2)
		if not service.riding:saw_exit=true;break
	await _ticks(4)
	_check("moving_ride_closed_doors_and_supported_next_stop_exit",saw_moving_closed and saw_exit and service.docked_stop==1 and scene.player.is_physics_processing() and scene.player.collision_layer==layer and scene.player.collision_mask==mask and attachment_max<.01,{"attachment_max_m":attachment_max,"state":service.snapshot(),"player":scene.player.global_position})
	_finish()
