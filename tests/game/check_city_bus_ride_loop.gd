extends "res://../tests/game/check_city_bus_loop.gd"
class EndpointCameraHold extends Node:
	var host: Node3D
	var point: Vector3
	var toward: Vector3
	func _physics_process(delta: float) -> void:
		host.rig.camera.global_transform=Transform3D(Basis.IDENTITY,point).looking_at(toward,Vector3.UP)
		host.rig.camera_stepped.emit(delta)
var endpoint_cars: Array[CharacterBody3D]=[]

func _run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/sim2seoul-bus-ride-loop-settings.json";scene.exploration_physics_hz=60;root.add_child(scene);await _ticks(6);service=scene.get("city_bus_service")
	_check("production_three_bus_loop_ready",scene.runtime_ok and service.loaded and service.buses.size()==3)
	if not scene.runtime_ok or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	var target: CharacterBody3D=service.buses[2]
	for tick: int in range(60*60):
		await _ticks(1);service._switch_bus(target)
		if service.bus_state=="doors_open":break
	_check("natural_dock_without_test_bus_reposition",service.bus_state=="doors_open",{"bus":target.snapshot()})
	service.set_running(false);service._switch_bus(target)
	var point: Vector3=target.to_global(Vector3(1.6,0,.55));point.y=scene.terrain_surface.ground_y_world(point)+.08
	var posed: bool=await _pose(point);await _tap()
	_check("fresh_E_selects_third_bus_and_sole_rider",posed and service.riding and service.active_bus()==target,{"state":service.snapshot()})
	if not service.riding:_finish();return
	# Hold the actual original camera/frustum on both unchanged endpoint cars.
	# The normal manager still receives camera_stepped and runs its original guard.
	for car: CharacterBody3D in scene.neighborhood_population.traffic.vehicles:
		if String(car.get_meta("coverage_route",""))=="coverage_drive_1":endpoint_cars.append(car)
	scene.rig.set_physics_process(false);scene.rig.set_process(false)
	var camera_hold:=EndpointCameraHold.new();camera_hold.host=scene;camera_hold.process_physics_priority=3;scene.add_child(camera_hold)
	var endpoint: Vector3=endpoint_cars[0]._points[-1];camera_hold.point=endpoint+Vector3(2,8,35);camera_hold.toward=endpoint+Vector3.UP*.75
	var start_cycle: int=target._cycle_count;var start_station: float=target.get_station_m();var start_distance: float=target._distance_m;var last: Vector3=target.global_position;var max_step:=0.;var attachment_error:=0.;var actual_closed:=true;var seen_stops: Dictionary={};var complete:=false;var offroute:=false
	service.set_running(true)
	for tick: int in range(60*330):
		await _ticks(1)
		service.active_bus();max_step=maxf(max_step,Vector2(target.global_position.x-last.x,target.global_position.z-last.z).length());last=target.global_position
		attachment_error=maxf(attachment_error,scene.player.global_position.distance_to(target.to_global(Vector3(.35,.72,-.6))))
		if target._speed_mps>.5:actual_closed=actual_closed and service.door_fraction<.001
		if service.docked_stop>=0:seen_stops[str(service.docked_stop)]=true
		if target._state=="off_route":offroute=true;break
		if tick%600==0:print("RIDE_PROGRESS tick=",tick," station=",target.get_station_m()," cycle=",target._cycle_count," state=",target._state," reason=",target._blocked_reason)
		if target._cycle_count>start_cycle and target.get_station_m()>=start_station+.02:complete=true;break
	_check("occupied_bus_physically_completes_entire_loop_with_camera",complete and not offroute and target._distance_m-start_distance>=float(service.design.route.length_m)-.02,{"bus":target.snapshot(),"start_station":start_station,"actual_distance":target._distance_m-start_distance,"seen_stops":seen_stops.keys()})
	var guard_rows: Array=[];var held:=0
	for car: CharacterBody3D in endpoint_cars:
		var guard: Dictionary=scene.neighborhood_population.traffic.manager.recycle_guard(car);guard_rows.append({"car":car.snapshot(),"guard":guard})
		if not bool(guard.end_outside) and not bool(guard.allowed) and car._speed_mps<.01 and car._length_m-car.get_station_m()<16.:held+=1
	_check("both_original_endpoint_cars_remain_visible_and_guarded_while_bus_loops",held==2,{"cars":guard_rows})
	_check("occupied_motion_has_closed_doors_and_no_position_jump",actual_closed and max_step<.80 and attachment_error<.02,{"max_step_m":max_step,"attachment_error_m":attachment_error})
	# Request exit only with a fresh E while actually moving; preserve the requested destination when blocked.
	var request:=false
	for tick: int in range(60*120):
		await _ticks(1);service.active_bus()
		if service.riding and target._speed_mps>.5 and not request:await _tap();request=service.exit_requested
		if not service.riding:break
	await _ticks(5)
	_check("fresh_E_request_alights_next_safe_actual_stop",request and not service.riding and not service._collision_release_pending and scene.player.is_physics_processing() and not scene.player.facility_control,{"player":scene.player.global_position,"snapshot":service.snapshot()})
	_check("original14_vehicles_and_source_unchanged",service.snapshot().original_vehicle_ids_unchanged and not service.snapshot().source_geometry_changed)
	_finish()
