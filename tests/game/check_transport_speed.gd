extends "res://../tests/game/check_drivable_car.gd"
## Explicit original-road starting fixtures; travel/braking use the real retained
## body/controller, held-action fixture and continuous native collision checks.
func _input_hashes() -> Dictionary:
	var result:=super._input_hashes()
	for path: String in ["res://../tests/game/check_transport_speed.gd","res://scripts/city_scooter_service.gd","res://scripts/city_helicopter_service.gd","res://assets/authored/bike_service.json","res://assets/authored/scooter_service.json","res://assets/authored/helicopter_service.json","res://resources/world_geometry/world.json","res://data/generated/public_walk.json","res://data/generated/terrain_surface.json","res://data/generated/traffic.json","res://assets/authored/neighborhood_population.json"]:result[path]=FileAccess.get_sha256(path)
	return result
func _run() -> void:
	_loaded_hashes=_input_hashes()
	for path: String in ["res://resources/world_geometry/world.json","res://data/generated/traffic.json","res://assets/authored/neighborhood_population.json"]:_source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/transport-speed-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";root.add_child(scene);await _ticks(8)
	service=scene.drivable_car_service
	_check("production_runtime_ready",scene.runtime_ok and service.loaded,{"error":scene.exploration_error})
	if not scene.runtime_ok:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	var ratios: Dictionary=preload("res://scripts/transport_motion_policy.gd").RUN_RATIOS
	var policies: Dictionary={"bike":scene.city_bike_service.design.policy,"scooter":scene.city_scooter_service.design.policy,"car":service.design.policy,"helicopter":scene.city_helicopter_service.design.policy,"bus":{"maximum_speed_mps":8.,"acceleration_mps2":1.4,"braking_mps2":2.8},"subway":{"maximum_speed_mps":12.,"acceleration_mps2":2.,"braking_mps2":2.6}}
	for profile: String in scene.SPEED_IDS:
		scene.set_speed_profile(profile)
		var measured: Dictionary={};var valid:=true
		for kind: String in policies:
			var authored: Dictionary=policies[kind].duplicate(true);var effective: Dictionary=scene.transport_motion_policy(kind,policies[kind]);var cap: float=effective.maximum_speed_mps
			valid=valid and cap>scene.player.run_speed_mps and cap>=scene.player.run_speed_mps*float(ratios[kind])-.001 and policies[kind]==authored
			measured[kind]={"cap_mps":cap,"run_mps":scene.player.run_speed_mps,"acceleration_mps2":effective.get("acceleration_mps2",effective.get("horizontal_acceleration_mps2",0.))}
		_check("all_transports_faster_than_"+profile+"_run_without_mutating_authored",valid,measured)
	scene.set_speed_profile("turbo");await _ticks(4)
	for ride: Node3D in [scene.city_bike_service,scene.city_scooter_service,scene.drivable_car_service]:
		service=ride
		var row: Dictionary=ride.bikes[0];var body: CharacterBody3D=row.body
		var a:=Vector3(95.56,0,-350.);var b:=Vector3(96.79,0,-450.);var direction: Vector3=(b-a).normalized();var yaw:=atan2(-direction.x,-direction.z)
		var support: Dictionary=ride._ground(a)
		_check(ride._motion_kind()+"_source_start_supported",not support.is_empty(),{"fixture_xz":a,"basis":"Test-only observer/vehicle start on original Sejong-daero w378453707 straight. No source/actor/collision change."})
		if support.is_empty():continue
		a.y=support.point.y+.015;var basis: Basis=ride._pose_basis(a,yaw)
		var source_safe:=true
		for step: int in range(90):
			var at:=a+direction*step;var ground: Dictionary=ride._ground(at)
			if ground.is_empty():source_safe=false;break
			at.y=ground.point.y+.015
			if not ride._footprint_allowed(at,ride._pose_basis(at,yaw)):source_safe=false;break
		_check(ride._motion_kind()+"_90m_original_source_footprint_clear",source_safe)
		if not source_safe:continue
		body.global_transform=Transform3D(basis,a);body.velocity=Vector3.ZERO;body.reset_physics_interpolation();row.yaw=yaw;row.previous=body.global_transform;row.current=row.previous;row.proxy.global_transform=row.current
		var observer: Dictionary=scene.interior_visit._safe_external_point(a+Vector3(2.8,0,0))
		if observer.is_empty():_check(ride._motion_kind()+"_observer_clear",false);continue
		scene.player.global_transform=Transform3D(Basis.IDENTITY,observer.point);scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();await _ticks(5)
		var mounted: bool=ride._mount(0)
		_check(ride._motion_kind()+"_native_full_body_fixture_mount",mounted,{"fixture_only_mount":"Detailed E eligibility/ownership covered by current separate suites. This speed fixture calls production mount after original-source placement."})
		if not mounted:continue
		await _ticks(4);var before: Vector3=body.global_position;var top:=0.;var unsupported:=0;var blocked: Dictionary={}
		_key("move_forward",true)
		for tick: int in range(60):
			await _ticks(1);top=maxf(top,ride.speed_mps)
			if not body.is_on_floor():unsupported+=1
			if not ride.blocked_reason.is_empty():blocked[ride.blocked_reason]=int(blocked.get(ride.blocked_reason,0))+1
		_key("move_forward",false)
		_check(ride._motion_kind()+"_actual_turbo_motion_exceeds_run",top>scene.player.run_speed_mps and body.global_position.distance_to(before)>30. and unsupported<5,{"top_mps":top,"run_mps":scene.player.run_speed_mps,"travel_m":body.global_position.distance_to(before),"unsupported_ticks":unsupported,"blocked":blocked,"snapshot":ride.snapshot()})
		_key("jump",true);await _ticks(ceili(float(ride.motion_policy().maximum_speed_mps)/float(ride.motion_policy().braking_mps2)*Engine.physics_ticks_per_second)+6);_key("jump",false)
		_check(ride._motion_kind()+"_turbo_brakes_and_dense_source_checks",absf(ride.speed_mps)<.02 and ride.maximum_source_sample_spacing_m<=.1801 and body.is_on_floor(),{"speed_mps":ride.speed_mps,"source_sample_max_m":ride.maximum_source_sample_spacing_m})
		await _capture(ride._motion_kind()+"_boosted_actual_ride")
		var stopped: Vector3=body.global_position;await _ticks(8)
		_check(ride._motion_kind()+"_stopped_not_teleported",body.global_position.distance_to(stopped)<.03)
		scene._visit_library_entrance();await _ticks(6)
		_check(ride._motion_kind()+"_external_transition_restores_player",not ride.riding and scene.player.is_physics_processing() and not scene.player.facility_control)
	_finish()

func _finish() -> void:
	if _finished:return
	_finished=true
	var current: Dictionary={}
	for path: String in _source_hashes:current[path]=FileAccess.get_sha256(path)
	_check("original_source_world_traffic_population_unchanged",current==_source_hashes and current.size()==3)
	_check("relevant_runtime_inputs_stable",_input_hashes()==_loaded_hashes)
	var passed:=checks.filter(func(row: Dictionary)->bool:return row.passed).size()
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(_json({"task":"EXP25_TRANSPORT_SPEED","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"captures":captures,"source_hashes":_loaded_hashes,"display":DisplayServer.get_name(),"physics_hz":Engine.physics_ticks_per_second,"elapsed_ms":Time.get_ticks_msec()-_started,"scope":"All five production speed profiles plus real turbo forward/braking on original Sejong-daero for bike/scooter/car. Explicit source-certified start/mount fixtures and test-only held input refresh, original native actors/collision retained. Helicopter and scheduled transit actual motion are separate suites. No human OS-key/subjective speed/performance acceptance from these engine checks."}),"  "));file.close();print("TRANSPORT_SPEED_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)
