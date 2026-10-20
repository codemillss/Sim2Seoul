extends SceneTree
## Production-spawn car at the newly covered Daehanmun crossing. One explicit
## signal-phase scenario start; no vehicle pose/station/route/permission writes.
var scene: Node3D
var checks: Array[Dictionary]=[]
var observations: Dictionary={}
var report_path:=""
var finished:=false
var requested_hz:=30
var started_usec:=0
const INPUTS: Array[String]=["res://scripts/traffic/vehicle.gd","res://scripts/traffic/traffic_manager.gd","res://scripts/street_network_detail.gd","res://assets/authored/road_furniture.json","res://scripts/neighborhood_traffic.gd","res://data/generated/traffic.json","res://resources/world_geometry/world.json","res://../tests/game/check_painted_signal_traffic.gd"]

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
		elif arg.begins_with("--physics-hz="):requested_hz=int(arg.trim_prefix("--physics-hz="))
	if not report_path.is_absolute_path() or FileAccess.file_exists(report_path) or requested_hz not in [30,60]:
		push_error("Use a new absolute --report=<path> [--physics-hz=30|60]");quit(1);return
	started_usec=Time.get_ticks_usec()
	create_timer(120.0,true,false,true).timeout.connect(func():_check("completion_guard",false);_finish())
	_run.call_deferred()

func _check(title: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":evidence})
	print("PAINTED_SIGNAL_CHECK ",title," ",passed)

func _ticks(count: int) -> void:
	for index: int in range(count):await physics_frame

func _run() -> void:
	var settings: String="/private/tmp/sim2seoul-painted-signals-"+str(OS.get_process_id())+".json"
	var file:=FileAccess.open(settings,FileAccess.WRITE);file.store_string(JSON.stringify({"schema_version":1,"speed_id":"brisk","free_roam":true}));file.close()
	scene=load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_physics_hz=requested_hz;scene.exploration_settings_path=settings;scene.quality_settings_path=settings+".quality.json"
	root.add_child(scene)
	if scene.menu.visible:scene.toggle_menu()
	_check("production_ready",scene.runtime_ok and scene.exploration_error.is_empty() and scene.street_network_detail.loaded,{"error":scene.exploration_error})
	if not scene.runtime_ok or not scene.exploration_error.is_empty():_finish();return
	var network: Node3D=scene.street_network_detail
	var car: CharacterBody3D
	for body: CharacterBody3D in scene.vehicles:
		if body.get_route_id()=="sejong_north":car=body;break
	if not is_instance_valid(car):_check("original_north_car_exists",false);_finish();return
	var route_signature: String=JSON.stringify(scene.traffic.routes)
	var start: float=car.get_station_m()
	# Explicit phase fixture gives the untouched spawn an approaching red.
	# Afterwards this production clock advances normally through the next green.
	network.advance_signal_time(29.0)
	await _ticks(2)
	var chosen: Dictionary=scene.traffic.painted_signal_limit(car,car._segment_direction(car._segment),30.0)
	var crossing: String=String(chosen.get("crossing_id",""))
	var fresh: bool=not crossing.is_empty() and crossing!="sejong_marked"
	_check("new_crossing_bound_to_existing_source_route",fresh,{"crossing_id":crossing,"source_route":car.get_route_id(),"initial_station_m":start,"query":chosen})
	if not fresh:_finish();return
	var stopped:=false;var stop_ticks:=0;var minimum_front_gap:=INF;var max_speed:=0.0;var max_step:=0.0;var previous: Vector3=car.global_position;var red_station:=0.0
	for tick: int in range(requested_hz*22):
		await _ticks(1)
		max_speed=maxf(max_speed,car._speed_mps)
		max_step=maxf(max_step,Vector2(car.global_position.x-previous.x,car.global_position.z-previous.z).length());previous=car.global_position
		var sample: Dictionary=car.snapshot().painted_signal
		if String(sample.get("crossing_id",""))==crossing and String(sample.get("state","")) in ["red","amber"]:
			minimum_front_gap=minf(minimum_front_gap,float(sample.distance_m)-2.1)
			if car._speed_mps<.01 and String(car._blocked_reason).begins_with("painted_signal_"):stop_ticks+=1
			else:stop_ticks=0
		if stop_ticks>=requested_hz:
			stopped=true;red_station=car.get_station_m();observations["red_stop"]=car.snapshot();break
	_check("unchanged_spawn_physically_brakes_before_new_red_stop_line",stopped and max_speed>.5 and minimum_front_gap>=.32 and max_step<=5.0/requested_hz+.007,{"initial_station_m":start,"red_station_m":red_station,"maximum_speed_mps":max_speed,"maximum_step_m":max_step,"minimum_nose_gap_m":minimum_front_gap,"actor_pose_writes":0,"car":car.snapshot()})
	var committed:=false;var rear_cleared:=false;var resumed:=false
	for tick: int in range(requested_hz*55):
		await _ticks(1)
		if car.get_station_m()>red_station+1.0 and car._speed_mps>.10:resumed=true
		for event: Dictionary in car.snapshot().painted_signal_events:
			if String(event.evidence.get("crossing_id",""))!=crossing:continue
			if event.event=="committed":committed=true
			if event.event=="rear_cleared":rear_cleared=true
		if resumed and committed and rear_cleared:break
	_check("natural_green_restarts_same_car_and_rear_clears_new_crossing",stopped and resumed and committed and rear_cleared,{"resumed":resumed,"committed":committed,"rear_cleared":rear_cleared,"car":car.snapshot(),"clock_s":network.elapsed_s,"phase_writes_after_scenario_start":0,"actor_pose_writes":0})
	_check("source_routes_and_original_conflicts_retained",JSON.stringify(scene.traffic.routes)==route_signature and car._conflicts.size()==1 and String(car._conflicts[0].crossing_id)=="sejong_marked",{"route_id":car.get_route_id(),"original_conflicts":car._conflicts})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true
	var failed:=0
	for check: Dictionary in checks:
		if not check.passed:failed+=1
	var hashes: Dictionary={}
	for path: String in INPUTS:hashes[path]=FileAccess.get_sha256(path)
	var result: Dictionary={"task":"EXP24_PAINTED_SIGNAL_TRAFFIC","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"summary":{"checks":checks.size(),"failed":failed,"physics_hz":requested_hz,"wall_usec":Time.get_ticks_usec()-started_usec},"source_sha256":hashes,"checks":checks,"observations":observations,"scope":"Production exploration original sejong_north car from unchanged spawn; one explicit starting red-phase fixture followed by normal clock advancement, physical red stop/green resume/rear clearance, no car pose/station/route/permission writes. This is engineering gameplay acceptance, not live Seoul timings or full NPC pedestrian compliance."}
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("PAINTED_SIGNAL_RESULT ",checks.size()-failed,"/",checks.size()," ",report_path)
	quit(1 if failed else 0)
