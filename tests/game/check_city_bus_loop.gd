extends SceneTree
var scene: Node3D
var service: Node3D
var checks: Array=[]
var report_path:="/tmp/city-bus-loop.json"
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	_run.call_deferred()
func _ticks(count: int) -> void:
	for index: int in range(count):await physics_frame
func _check(name: String,ok: bool,data: Dictionary={}) -> void:
	checks.append({"name":name,"passed":ok,"evidence":data});print("LOOP_CHECK ",name," ",ok)
func _finish() -> void:
	var n: int=checks.filter(func(r: Dictionary):return bool(r.passed)).size()
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":n,"total":checks.size(),"checks":checks,"snapshot":service.snapshot() if is_instance_valid(service) else {},"script_sha256":FileAccess.get_sha256("res://scripts/city_bus_service.gd"),"data_sha256":FileAccess.get_sha256("res://assets/authored/bus_service.json")},"  "));file.close();print("LOOP_RESULT ",n,"/",checks.size());quit(0 if n==checks.size() else 1)
func _tap() -> void:
	var e:=InputEventAction.new();e.action="interact";e.pressed=true;e.device=42;Input.parse_input_event(e);await _ticks(2);e=InputEventAction.new();e.action="interact";e.pressed=false;e.device=42;Input.parse_input_event(e);await _ticks(2)
func _pose(point: Vector3) -> bool:
	var safe: Dictionary=scene.interior_visit._safe_external_point(point)
	if safe.is_empty():return false
	scene.player.global_transform=Transform3D(Basis.IDENTITY,safe.point);scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();await _ticks(5);return true
func _run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/sim2seoul-loop-settings.json";scene.exploration_physics_hz=60;root.add_child(scene);await _ticks(6)
	service=scene.get("city_bus_service");_check("production_ready",scene.runtime_ok and is_instance_valid(service) and service.loaded,{"error":service.load_error if is_instance_valid(service) else "missing"})
	if not scene.runtime_ok or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	_check("three_buses_four_boardable_source_walk_stops",service.buses.size()==3 and service.design.stops.size()>=4 and service.route_certificate.accepted and service.snapshot().original_vehicle_ids_unchanged,{"certificate":service.route_certificate,"stops":service.stop_certificates})
	var old_ids: Array=[]
	for body: CharacterBody3D in service.buses:old_ids.append(body.get_instance_id())
	var before: Array=[];var max_step:=0.;var unsupported:=0;var offroute:=false;var cycles:=0;var dock_events:=0;var distinct: Dictionary={};var first_dock: CharacterBody3D
	for body: CharacterBody3D in service.buses:before.append(body.global_position)
	for tick: int in range(60*240):
		await _ticks(1)
		for index: int in range(service.buses.size()):
			var body: CharacterBody3D=service.buses[index];var p: Vector3=before[index];max_step=maxf(max_step,Vector2(body.global_position.x-p.x,body.global_position.z-p.z).length());before[index]=body.global_position
			if body._state=="off_route":offroute=true
			if tick%60==0 and body._floor_reason!="up_floor_ray" and not body.is_on_floor():unsupported+=1
		service._store_bus()
		for body: CharacterBody3D in service.buses:
			var row: Dictionary=service._records[body.get_instance_id()].duplicate();row["id"]=String(body.name)
			if row.bus_state=="doors_open":
				distinct[String(row.id)+"_"+str(row.docked_stop)]=true

		cycles=0
		for body: CharacterBody3D in service.buses:cycles+=body._cycle_count
		if tick%600==0:print("LOOP_PROGRESS tick=",tick," stations=",service.buses.map(func(b: CharacterBody3D):return [b.get_station_m(),b._speed_mps,b._state,b._blocked_reason]))
		if offroute:break
		if cycles>=3 and distinct.size()>=8:break
	_check("three_actual_physical_loop_completions_no_jump",cycles>=3 and not offroute and max_step<.80,{"cycles":cycles,"max_step_m":max_step,"fleet":service._fleet_snapshot()})
	_check("multiple_actual_stop_calls_on_all_buses",distinct.size()>=8,{"distinct_bus_stop_calls":distinct.keys()})
	_check("native_terrain_support_preserved",unsupported==0,{"unsupported":unsupported,"fleet":service._fleet_snapshot()})
	if offroute:_finish();return
	# Actual next dock, then several door approaches and a real fresh-E ownership transfer.
	var target: CharacterBody3D
	for tick: int in range(60*120):
		await _ticks(1)
		for body: CharacterBody3D in service.buses:
			service._switch_bus(body)
			if service.bus_state=="doors_open":target=body;break
		if is_instance_valid(target):break
	if not is_instance_valid(target):_check("live_dock_for_E",false);_finish();return
	service.set_running(false);service._switch_bus(target)
	var legal:=0;var max_exit_shift:=0.;var all_release:=true
	for local: Vector3 in [Vector3(1.6,0,-2.95),Vector3(2.8,0,-3.5),Vector3(1.6,0,.55),Vector3(3.2,0,1.4)]:
		var station: Vector3=target.global_position;var point: Vector3=target.to_global(local);point.y=scene.terrain_surface.ground_y_world(point)+.08
		var posed: bool=await _pose(point);await _tap()
		if posed and service.riding and service.active_bus()==target:legal+=1
		if service.riding:await _tap()
		await _ticks(5);max_exit_shift=maxf(max_exit_shift,Vector2(target.global_position.x-station.x,target.global_position.z-station.z).length());all_release=all_release and not service._collision_release_pending and scene.player.is_physics_processing()
	_check("fresh_E_multiple_doors_choose_correct_bus_single_rider",legal==4,{"boarded_positions":legal,"target":target.name})
	_check("native_exit_restores_capsule_without_pushing_any_bus",all_release and max_exit_shift<.002,{"max_exit_shift_m":max_exit_shift,"pending":service._collision_release_pending})
	service._switch_bus(target);var p: Vector3=target.to_global(Vector3(-2.2,0,-2.95));p.y=scene.terrain_surface.ground_y_world(p)+.08;await _pose(p);await _tap();_check("deny_opposite_side",not service.riding)
	var frozen: Array=[]
	for body: CharacterBody3D in service.buses:frozen.append(body.global_transform)
	service.set_running(true);scene.toggle_menu();await _ticks(30);var still:=true
	for i: int in range(service.buses.size()):still=still and service.buses[i].global_transform==frozen[i]
	_check("menu_freezes_all_three_actual_bodies",still);scene.toggle_menu()
	_finish()
