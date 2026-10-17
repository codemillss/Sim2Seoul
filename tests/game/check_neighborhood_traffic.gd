extends "res://../tests/game/check_facility_interactions.gd"
## Production traffic is never repositioned by this test. The player and two
## labelled temporary obstacle fixtures are the only scenario placements.
var coverage: Node3D
var traffic_observations: Dictionary={}
var _settings_path: String=""
var _route_hash: String=""
var _old_vehicle_ids: Array=[]
var _started_ms: int=0

func _check(title: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":_json(evidence)})
	if not passed:push_warning("NEIGHBORHOOD_TRAFFIC_CHECK_FAIL "+title)

func _car(route_id: String,sequence: int) -> CharacterBody3D:
	for body: CharacterBody3D in coverage.vehicles:
		if body.get_route_id()==route_id+"_car_"+str(sequence):return body
	return null

func _route(id: String) -> Dictionary:
	for row: Dictionary in coverage.design.vehicle_routes:
		if String(row.id)==id:return row
	return {}

func _frame(body: CharacterBody3D,ahead: float) -> Dictionary:
	var route: Dictionary=coverage.manager.routes[body.get_route_id()]
	var local: Dictionary=coverage._at(route,clampf(body.get_station_m()+ahead,0,float(route.length_m)))
	return {"point":scene.city.to_global(local.point),"direction":scene.city.global_basis*local.direction}

func _contacts(body: CharacterBody3D) -> Array:
	var shape: CollisionShape3D=body.get_node("CollisionShape");var query: PhysicsShapeQueryParameters3D=PhysicsShapeQueryParameters3D.new();query.shape=shape.shape;query.transform=shape.global_transform;query.collision_mask=2|4|8;query.exclude=[body.get_rid()];query.margin=-.002
	var result: Array=[]
	for hit: Dictionary in scene.get_world_3d().direct_space_state.intersect_shape(query,8):result.append(String(hit.collider.name))
	return result

func _view_toward(point: Vector3) -> void:
	var direction: Vector3=point-scene.player.global_position;direction.y=0
	scene.rig.yaw=atan2(-direction.x,-direction.z);scene.rig.pitch=deg_to_rad(-10);scene.rig.requested_distance=4.0;scene.rig.snap_to_target_pose()

func _startup_geometry() -> void:
	var state: Dictionary=coverage.snapshot();var accepted: int=0;var sample_count: int=0;var styles: int=0;var support_errors: Array=[];var footprint_errors: Array=[]
	for certificate: Dictionary in state.route_certificates:
		if certificate.accepted:accepted+=1
		sample_count+=int(certificate.samples)
	for support: StaticBody3D in coverage.supports:
		if support.collision_layer!=16 or support.collision_mask!=8 or not support.get_meta("authored_flat_support",false):support_errors.append(support.name)
	for body: CharacterBody3D in coverage.vehicles:
		if body.has_node("Visual/SedanBody") and body.has_node("Visual/Headlight"):styles+=1
		var box: BoxShape3D=body.get_node("CollisionShape").shape
		if box.size!=Vector3(1.8,1.5,4.2) or body.collision_layer!=8 or body.collision_mask!=31:footprint_errors.append(body.name)
		for x in [-.87,.87]:
			for z in [-2.06,2.06]:
				var corner: Vector3=body.global_position+body.global_basis*Vector3(x,0,z)
				var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(corner+Vector3.UP*.15,corner-Vector3.UP*.15,1|16,[body.get_rid()]))
				if hit.is_empty() or hit.normal.y<.95 or absf(hit.position.y-body.global_position.y)>.03:footprint_errors.append({"body":body.name,"corner":corner,"floor":hit.get("position",Vector3.INF)})
	_check("startup.eight_physical_sedans_on_four_certified_source_forward_corridors",coverage.loaded and state.vehicle_count==8 and accepted==4 and sample_count>1900 and styles==8 and footprint_errors.is_empty(),{"state":state,"physical_footprint_errors":footprint_errors,"sedan_models":styles})
	_check("support.four_limited_vehicle_only_lanes_leave_player_and_source_bodies_unchanged",coverage.supports.size()==4 and support_errors.is_empty() and scene.vehicles.size()==6 and scene.traffic.vehicles.size()==6 and scene.traffic_bundle.routes.size()==2,{"supports":support_errors,"old_vehicle_count":scene.vehicles.size(),"old_manager_count":scene.traffic.vehicles.size(),"old_routes":scene.traffic_bundle.routes.size()})
	_check("crossings.multiple_zone_source_conflicts_are_retained",coverage.manager.zones.size()==3 and _route("coverage_drive_1").conflicts.size()==2 and _route("coverage_drive_2").conflicts.size()==1,coverage.manager.snapshot())

func _ordinary_motion() -> void:
	var previous: Array[Vector3]=coverage.actor_positions();var travelled: Array=[];var max_step: float=0.0;var contacts: Array=[];var groundless: int=0
	for _body in coverage.vehicles:travelled.append(0.0)
	for tick: int in range(360):
		await _ticks(1)
		for index: int in range(coverage.vehicles.size()):
			var body: CharacterBody3D=coverage.vehicles[index];var difference: Vector3=body.global_position-previous[index];difference.y=0;var step: float=difference.length();previous[index]=body.global_position
			travelled[index]=float(travelled[index])+step;max_step=maxf(max_step,step)
			if not body.is_on_floor() or body.snapshot().floor_reason!="up_floor_ray":groundless+=1
			if tick%12==0:
				var hits: Array=_contacts(body)
				if not hits.is_empty() and contacts.size()<8:contacts.append({"tick":tick,"body":body.name,"hits":hits})
	var all_moved: bool=true
	for distance: float in travelled:all_moved=all_moved and distance>8.0
	var evidence: Dictionary={"actual_distances_m":travelled,"maximum_physical_step_m":max_step,"groundless_observations":groundless,"actor_overlaps":contacts,"position_writes_during_drive":0,"state":coverage.snapshot()};traffic_observations["ordinary_motion"]=evidence
	_check("motion.all_eight_physically_drive_with_bounded_steps_support_and_no_actor_overlap",all_moved and max_step<=5.0/60.0+.003 and groundless==0 and contacts.is_empty(),evidence)

func _menus() -> void:
	scene.traffic_switch.set_pressed(false);await _ticks(3);var before: Array[Vector3]=coverage.actor_positions();await _ticks(55)
	_check("checkbox.actual_vehicle_control_stops_original_six_and_new_eight",not coverage.running and before==coverage.actor_positions() and scene.vehicles.all(func(body):return not body.snapshot().running),{"new_state":coverage.snapshot(),"old_states":scene.vehicles.map(func(body):return body.snapshot().state)})
	scene.traffic_switch.set_pressed(true);await _ticks(60)
	var frozen: Array=[]
	for body: CharacterBody3D in coverage.vehicles:frozen.append(body.global_transform)
	var manager_tick: int=coverage.manager.last_observation_tick
	scene.toggle_menu();await _ticks(25);var same: bool=true
	for index: int in range(frozen.size()):same=same and frozen[index]==coverage.vehicles[index].global_transform
	_check("pause.menu_exactly_freezes_all_vehicle_poses_and_crossing_observation_clock",paused and same and manager_tick==coverage.manager.last_observation_tick,{"manager_tick_before":manager_tick,"manager_tick_after":coverage.manager.last_observation_tick})
	scene.toggle_menu();await _ticks(3)

func _obstacle_fixture(title: String,point: Vector3,direction: Vector3) -> CharacterBody3D:
	var body: CharacterBody3D=CharacterBody3D.new();body.name=title;body.collision_layer=8;body.collision_mask=31
	var collider: CollisionShape3D=CollisionShape3D.new();collider.name="CollisionShape";var shape: BoxShape3D=BoxShape3D.new();shape.size=Vector3(1.8,1.5,4.2);collider.shape=shape;collider.position.y=.75;body.add_child(collider);scene.add_child(body);body.global_position=point;body.global_rotation.y=atan2(-direction.x,-direction.z)
	return body

func _obstacle_yield(human: bool) -> void:
	var body: CharacterBody3D=_car("coverage_drive_2",0);var frame: Dictionary=_frame(body,17.0);var fixture: CharacterBody3D
	var title: String="human_priority" if human else "following_gap"
	if human:
		if not await _pose("stationary_player_in_coverage_lane",frame.point+Vector3.UP*.08):return
	else:fixture=_obstacle_fixture("ExplicitStationaryLeadCar",frame.point,frame.direction);await _ticks(2)
	var start: Vector3=body.global_position;var minimum: float=INF;var stopped: int=0;var approach_stopped: int=0;var hold_entry_tick: int=-1;var hold_losses: int=0;var overlap: Array=[];var actual_reason: String="";var final_hold: Vector3=Vector3.INF;var final_drift: float=0.0;var path: Array=[]
	# Keep the original bounded approach allowance. A fixed last-60 slice can
	# include legitimate final braking; the settled window starts at the first
	# actual zero-speed hold, and never restarts if that hold is subsequently lost.
	for tick: int in range(360):
		await _ticks(1)
		var separation: float=Vector2(body.global_position.x-frame.point.x,body.global_position.z-frame.point.z).length();minimum=minf(minimum,separation)
		var state: Dictionary=body.snapshot()
		if state.speed_mps<.005:approach_stopped+=1
		if String(state.blocked_reason).contains(String(scene.player.name)) or String(state.blocked_reason).contains("ExplicitStationaryLeadCar"):actual_reason=String(state.blocked_reason)
		if tick%10==0 and not _contacts(body).is_empty():overlap.append(_contacts(body))
		if tick%6==0:path.append({"phase":"bounded_approach","tick":tick,"position":body.global_position,"speed_mps":state.speed_mps,"reason":state.blocked_reason,"obstacle":state.obstacle,"physical_obstacle_hold":state.get("physical_obstacle_hold",false),"release_probe_m":state.get("obstacle_release_probe_m",0.0)})
		if state.get("physical_obstacle_hold",false) and float(state.speed_mps)<.001:
			hold_entry_tick=tick+1;final_hold=body.global_position;break
	if hold_entry_tick>0:
		for tick: int in range(60):
			await _ticks(1)
			var state: Dictionary=body.snapshot();var separation: float=Vector2(body.global_position.x-frame.point.x,body.global_position.z-frame.point.z).length();minimum=minf(minimum,separation)
			if float(state.speed_mps)<.005:stopped+=1
			if not state.get("physical_obstacle_hold",false) or float(state.speed_mps)>=.001:hold_losses+=1
			final_drift=maxf(final_drift,body.global_position.distance_to(final_hold))
			var hits: Array=_contacts(body)
			if not hits.is_empty():overlap.append({"phase":"settled_hold","tick":tick,"contacts":hits})
			path.append({"phase":"settled_hold","tick":tick,"position":body.global_position,"speed_mps":state.speed_mps,"reason":state.blocked_reason,"obstacle":state.obstacle,"physical_obstacle_hold":state.get("physical_obstacle_hold",false),"release_probe_m":state.get("obstacle_release_probe_m",0.0)})
	var evidence: Dictionary={"start":start,"end":body.global_position,"obstacle_point":frame.point,"actual_obstacle_reason":actual_reason,"minimum_center_distance_m":minimum,"stopped_ticks":stopped,"approach_stopped_ticks":approach_stopped,"approach_limit_ticks":360,"first_physical_hold_tick":hold_entry_tick,"settled_window_ticks":60 if hold_entry_tick>0 else 0,"hold_loss_ticks":hold_losses,"contacts":overlap,"state":body.snapshot(),"fixture_is_explicit_stationary_car":not human,"production_vehicle_position_writes":0,"settled_60_tick_drift_m":final_drift,"physical_observation_path":path};traffic_observations[title]=evidence
	_check(title+".actual_full_box_sweep_brakes_before_stationary_obstacle_without_overlap",hold_entry_tick>0 and stopped>40 and minimum>(2.42 if human else 4.22) and overlap.is_empty() and not actual_reason.is_empty(),evidence)
	_check(title+".stationary_obstacle_hold_has_no_repeated_acceleration_or_position_creep",hold_entry_tick>0 and hold_losses==0 and final_drift<.001 and body.snapshot().speed_mps<.001 and body.snapshot().get("physical_obstacle_hold",false),evidence)
	if human:
		_view_toward(body.global_position);await _ticks(3);await _capture("coverage_vehicle_yields_to_player")
		await _pose("player_clears_coverage_lane",scene.city.to_global(Vector3(-5,.08,100)))
	else:fixture.queue_free();await _ticks(3)
	var resume: Vector3=body.global_position;await _ticks(140)
	_check(title+".same_physical_car_resumes_after_obstacle_clears",body.global_position.distance_to(resume)>2.0,{"start":resume,"end":body.global_position,"state":body.snapshot()})

func _crossing_priority() -> void:
	var body: CharacterBody3D=_car("coverage_drive_1",0);var route: Dictionary=_route("coverage_drive_1");var conflict: Dictionary=route.conflicts[1]
	var point: Vector3=scene.city.to_global(Vector3(conflict.center_xz[0],.08,conflict.center_xz[1]))
	var before_station: float=body.get_station_m()
	_check("crossing.scenario_starts_before_second_source_conflict_without_vehicle_reposition",before_station<float(conflict.stop_s_m)-2.0,{"station_m":before_station,"source_stop_m":conflict.stop_s_m})
	if before_station>=float(conflict.stop_s_m)-2.0:return
	if not await _pose("player_occupies_second_source_crossing",point):return
	var observed: bool=false;var contacts: Array=[];var path: Array=[]
	for tick: int in range(1200):
		await _ticks(1);var state: Dictionary=body.snapshot()
		if tick%30==0:path.append({"tick":tick,"station_m":body.get_station_m(),"speed_mps":state.speed_mps,"permission":state.permission})
		if not _contacts(body).is_empty():contacts.append(_contacts(body))
		if String(state.permission.get("crossing",""))==String(conflict.crossing_id) and state.permission.get("human_present",false) and absf(body.get_station_m()-float(conflict.stop_s_m))<.03 and state.speed_mps<.005:observed=true;break
	var stopped: float=body.get_station_m();await _ticks(65)
	_check("crossing.second_zone_human_has_priority_and_car_waits_at_actual_source_stop",observed and absf(body.get_station_m()-stopped)<.002 and body.get_station_m()<=float(conflict.stop_s_m)+.005 and contacts.is_empty(),{"state":body.snapshot(),"source_conflict":conflict,"path":path,"contacts":contacts})
	_view_toward(body.global_position);await _ticks(3);await _capture("coverage_second_crossing_wait")
	await _pose("second_crossing_player_leaves",scene.city.to_global(Vector3(-5,.08,100)))
	var passed: bool=false;var crossing_speed: float=0.0
	for _tick: int in range(900):
		await _ticks(1)
		if body.get_station_m()>=float(conflict.enter_s_m) and body.get_station_m()<=float(conflict.exit_s_m):crossing_speed=maxf(crossing_speed,float(body.snapshot().speed_mps))
		if body.get_station_m()>float(conflict.exit_s_m)+.1:passed=true;break
	_check("crossing.current_human_clear_hold_and_FIFO_grant_allow_safe_physical_pass",passed and crossing_speed<=2.0+.005 and coverage.manager.grants>0,{"crossing_max_speed_mps":crossing_speed,"state":body.snapshot(),"manager":coverage.manager.snapshot()})

func _endpoint_guards() -> void:
	var body: CharacterBody3D=_car("coverage_drive_0",1);var route: Dictionary=_route("coverage_drive_0");var end: Dictionary=coverage._at(route,float(route.length_m));var side: Vector3=Vector3(end.direction.z,0,-end.direction.x)
	for car: CharacterBody3D in coverage.vehicles:car.set_running(car==body)
	if not await _pose("endpoint_nearby_observer",scene.city.to_global(end.point+side*5.0+Vector3.UP*.08)):return
	_view_toward(scene.city.to_global(end.point));var start_cycle: int=body.snapshot().cycle_count;var reached: bool=false
	for _tick: int in range(2600):
		await _ticks(1)
		if body.can_recycle():reached=true;break
	var stopped_at: Vector3=body.global_position;await _ticks(25)
	var near_guard: Dictionary=coverage.manager.recycle_guard(body)
	_check("endpoint.source_forward_car_reaches_real_endpoint_and_waits_for_nearby_human",reached and body.global_position.distance_to(stopped_at)<.001 and body.snapshot().cycle_count==start_cycle and not near_guard.allowed and near_guard.minimum_human_surface_distance_m<30.0,{"guard":near_guard,"state":body.snapshot(),"production_vehicle_position_writes":0})
	var start_frame: Dictionary=coverage._at(route,0.0);var fixture: CharacterBody3D=_obstacle_fixture("ExplicitEntryOccupancyCar",scene.city.to_global(start_frame.point),start_frame.direction);await _ticks(2)
	await _pose("endpoint_far_observer_looking_away",scene.city.to_global(Vector3(-5,.08,100)))
	scene.rig.yaw=PI;scene.rig.pitch=deg_to_rad(-10);scene.rig.snap_to_target_pose();await _ticks(12)
	var blocked: Dictionary=coverage.manager.recycle_guard(body)
	_check("recycle.occupied_start_box_blocks_reentry_even_when_portals_are_outside",not blocked.allowed and not blocked.entry_clear and blocked.minimum_human_surface_distance_m>=30.0 and body.snapshot().cycle_count==start_cycle,{"guard":blocked,"state":body.snapshot()})
	fixture.queue_free();await _ticks(3);var recycled: bool=false
	for _tick: int in range(60):
		await _ticks(1)
		if body.snapshot().cycle_count>start_cycle:recycled=true;break
	var state: Dictionary=body.snapshot();var history: Array=state.recycle_history;var actual: Dictionary={} if history.is_empty() else history[-1].guard
	_check("recycle.current_camera_human_entry_guard_reuses_source_forward_start_without_overlap",recycled and actual.get("allowed",false) and actual.get("start_outside",false) and actual.get("end_outside",false) and actual.get("entry_clear",false) and float(actual.get("minimum_human_surface_distance_m",0))>=30.0 and body.get_station_m()<1.0 and _contacts(body).is_empty(),{"state":state,"actual_guard":actual})
	coverage.set_running(true)

func _run() -> void:
	_started_ms=Time.get_ticks_msec()
	for path in ["res://scripts/neighborhood_traffic.gd","res://scripts/neighborhood_population.gd","res://scripts/traffic/vehicle.gd","res://scripts/traffic/exploration_vehicle.gd","res://scripts/traffic/traffic_manager.gd","res://assets/authored/neighborhood_population.json","res://../tests/game/check_neighborhood_traffic.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();_settings_path=report_path+".settings.json"
	var settings: FileAccess=FileAccess.open(_settings_path,FileAccess.WRITE);settings.store_string(JSON.stringify({"schema_version":1,"speed_id":"brisk","free_roam":true}));settings.close();scene.exploration_settings_path=_settings_path;scene.quality_settings_path=_settings_path+".quality.json";root.add_child(scene);await _ticks(25)
	var population: Node3D=scene.get("neighborhood_population")
	coverage=population.traffic if is_instance_valid(population) else null
	_check("startup.production_population_and_coverage_traffic_load",scene.runtime_ok and is_instance_valid(coverage) and coverage.loaded,{"runtime_ok":scene.runtime_ok,"error":scene.exploration_error,"traffic_error":coverage.load_error if is_instance_valid(coverage) else "missing"})
	if not scene.runtime_ok or not is_instance_valid(coverage) or not coverage.loaded:_finish();return
	visit=scene.interior_visit;original_inventory=_inventory();player_shape_before=_player_shape();_route_hash=JSON.stringify(scene.traffic_bundle.routes)
	for body: CharacterBody3D in scene.vehicles:_old_vehicle_ids.append(body.get_instance_id())
	scene.set_pedestrians_running(false);_startup_geometry();await _ordinary_motion();await _menus()
	# The second source crossing must be reached by its original moving car.
	# Run it before the two obstacle scenarios so its station stays upstream.
	await _crossing_priority();await _obstacle_yield(true);await _obstacle_yield(false);await _endpoint_guards()
	var ids: Array=[]
	for body: CharacterBody3D in scene.vehicles:ids.append(body.get_instance_id())
	_check("regression.original_source_inventory_player_capsule_six_cars_and_old_routes_remain",_inventory()==original_inventory and _player_shape()==player_shape_before and ids==_old_vehicle_ids and JSON.stringify(scene.traffic_bundle.routes)==_route_hash,{"source_body_count":original_inventory.size(),"old_vehicle_count":ids.size(),"new_vehicle_count":coverage.vehicles.size(),"player_shape":_player_shape()})
	var changed: Array=[]
	for path: String in source_hashes:
		if source_hashes[path]!=FileAccess.get_sha256(path):changed.append(path)
	_check("sources.frozen_during_run",changed.is_empty(),{"changed":changed})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;paused=false;_movement();_e(false)
	var failed: int=0
	for row: Dictionary in checks:
		if not row.passed:failed+=1
	var report: Dictionary={"task":"NEIGHBORHOOD_TRAFFIC","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed,"actual_wall_ms":Time.get_ticks_msec()-_started_ms},"checks":checks,"observations":traffic_observations,"scenario_starts":placements,"captures":captures,"scope":"Actual additional eight production vehicles on four source-derived corridors. No production-vehicle position writes during motion. Physical player/lead-car yield, real source-crossing stop and clear-hold/FIFO pass, source-forward endpoint and camera/human/entry guarded recycle. Source/player/old-six preservation and actual checkbox/menu pause. Two labelled stationary car fixtures only. No traffic density, physical terrain survey, human usability or engine FPS/performance acceptance."}
	var file: FileAccess=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(report),"\t")+"\n");file.close()
	else:failed+=1
	print("NEIGHBORHOOD_TRAFFIC_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed);quit(0 if failed==0 else 1)
