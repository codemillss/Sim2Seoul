extends SceneTree
## Short isolated observations; not a frame-rate acceptance or human-use test.
var scene: Node3D
var report_path: String=""
var rows: Array=[]
func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	if not report_path.is_absolute_path():quit(1);return
	Engine.max_fps=60;Engine.physics_ticks_per_second=60
	_run.call_deferred()
func _run() -> void:
	var source_sha: String=FileAccess.get_sha256("res://scripts/traffic/vehicle.gd")
	var source_hashes: Dictionary={}
	for path: String in ["res://scripts/source_polygon_index.gd","res://scripts/street_pedestrians.gd","res://scripts/neighborhood_population.gd","res://../tests/game/profile_terrain_runtime.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate()
	var settings: String="/private/tmp/exp21-profile-"+str(OS.get_process_id())+".json"
	scene.exploration_settings_path=settings;scene.quality_settings_path=settings+".quality";root.add_child(scene)
	for tick: int in range(12):await physics_frame
	if not scene.runtime_ok:push_error("Production terrain startup failed");quit(1);return
	if scene.menu.visible:scene.toggle_menu()
	for phase: Array in [["none",false,false],["people",true,false],["cars",false,true],["all",true,true]]:
		scene.set_pedestrians_running(bool(phase[1]));scene.set_vehicles_running(bool(phase[2]))
		for tick: int in range(10):await physics_frame
		var samples: Array=[]
		for index: int in range(45):
			var began: int=Time.get_ticks_usec();var physics_before: int=Engine.get_physics_frames();await process_frame
			samples.append({"frame_us":Time.get_ticks_usec()-began,"physics_ticks":Engine.get_physics_frames()-physics_before,"last_physics_us":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000000.0,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
		var counters: Array=[]
		for car: CharacterBody3D in scene.vehicles+scene.neighborhood_population.traffic.vehicles:counters.append({"id":car.name,"queries":car._terrain_query_counts.duplicate(true)})
		rows.append({"phase":phase[0],"samples":samples,"last_tick_vehicle_queries":counters})
	var changed: bool=source_sha!=FileAccess.get_sha256("res://scripts/traffic/vehicle.gd")
	for path: String in source_hashes:
		if source_hashes[path]!=FileAccess.get_sha256(path):changed=true
	var report: Dictionary={"task":"EXP21_SHORT_LOAD_OBSERVATION","result":"FAIL" if changed else "OBSERVED","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"vehicle_source_sha256":source_sha,"samples":rows,"scope":"One production startup and45processframes per isolated actor-toggle phase. Native monitor values and actual physics ticks recorded; no timed route, long-run FPS acceptance, GPU-equivalent headless claim, human handling, M4 or export."}
	report["source_sha256"]=source_hashes
	report["physics_hz"]=Engine.physics_ticks_per_second
	var file: FileAccess=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n");file.close();print("EXP21_LOAD ",report.result);quit(1 if changed else 0)
