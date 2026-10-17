extends "res://../tests/game/check_street_scene.gd"
var terrain: Node3D
var full_journey := false
var traces: Array=[]
var performance_rows: Array=[]
var _began_ms := 0
var physics_hz: int=60

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
		if argument=="--full-journey":full_journey=true
		if argument.begins_with("--physics-hz="):physics_hz=int(argument.trim_prefix("--physics-hz="))
	if report_path.is_empty() or not report_path.is_absolute_path():quit(1);return
	if physics_hz not in [30,60]:quit(1);return
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	Engine.physics_ticks_per_second=physics_hz;Engine.max_fps=0
	create_timer(1800.,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _ground(point: Vector3) -> Dictionary:
	var y: float=terrain.ground_y_world(point)
	if not is_finite(y):return {}
	return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(point.x,y+.7,point.z),Vector3(point.x,y-.7,point.z),1|32,[scene.player.get_rid()]))

func _sample_surface() -> void:
	var errors: Array=[];var count:=0;var max_gap:=0.;var heights: Array=[]
	for x in range(-480,481,40):
		for z in range(-480,481,40):
			var point:=Vector3(x,0,z);var data: Dictionary=terrain.sample_ground_world(point)
			if not data.get("ok",false):errors.append({"point":point,"reason":"missing_query"});continue
			var native: Dictionary=_ground(point);count+=1;heights.append(data.height_m)
			if native.is_empty():errors.append({"point":point,"reason":"missing_native_support"});continue
			var gap: float=absf(native.position.y-data.height_m);max_gap=maxf(max_gap,gap)
			# Existing source curbs are12cm high; they are documented overlays.
			if gap>.155:errors.append({"point":point,"query":data.point,"native":native.position,"id":native.collider.get_meta("geometry_id","")})
	_check("terrain.whole_region_queries_match_native_support",count>=600 and errors.is_empty(),{"samples":count,"maximum_gap_m":max_gap,"errors":errors})
	heights.sort()
	_check("terrain.region_has_source_conditioned_height_difference",float(heights.back())-float(heights[0])>12.,{"relative_range_m":[heights[0],heights.back()],"datum":terrain.field.datum})
	_check("terrain.outside_and_nonfinite_rejected",not terrain.sample_ground_world(Vector3(900,0,0)).ok and not terrain.sample_ground_world(Vector3(NAN,0,0)).ok and is_nan(terrain.ground_y_world(Vector3(900,0,0))))
	_check("terrain.old_invented_hill_removed",scene.museum_approach.bodies.is_empty() and scene.museum_approach.get_meta("source_interpolated_terrain",false),{"source_path_retained":scene.museum_approach._line.size()})
	_check("terrain.terrain_and_all_building_binding_ready",terrain.loaded and terrain.foundation_by_source.size()==635 and visit.terrain_rebase_count==1,terrain.snapshot())
	var projection_errors: Array=[];var native_deferred: int=0
	for record: Dictionary in scene.terrain_binding.records:
		if record.get("ok",false):continue
		if DisplayServer.get_name()=="headless" and record.get("kind")=="multimesh" and record.get("reason")=="native_instance_buffer_unavailable":native_deferred+=1
		else:projection_errors.append(record)
	_check("terrain.every_static_projection_succeeded_or_dummy_native_readback_explicitly_deferred",projection_errors.is_empty(),{"errors":projection_errors,"headless_multimesh_readback_deferred":native_deferred,"records":scene.terrain_binding.records.size()})
	var bird_errors: Array=[]
	for bird: Dictionary in scene.street_life.birds:
		var original: Vector3=bird.flat_source_anchor
		var expected: Vector3=original+Vector3.UP*terrain.ground_y_world(original)
		var body: Node3D=bird.actor.get_node("BirdBody")
		if bird.anchor.distance_to(expected)>.0001 or body.position.distance_to(Vector3(0.,.15,0.))>.0001 or bird.head.position.distance_to(Vector3(0.,.26,-.13))>.0001 or bird.wings[0].position.distance_to(Vector3(-.09,.15,.03))>.0001 or bird.wings[1].position.distance_to(Vector3(.09,.15,.03))>.0001:bird_errors.append({"node":bird.actor.name,"anchor":bird.anchor,"expected":expected,"body_local":body.position})
	_check("terrain.bird_roots_rebased_once_and_animated_local_geometry_preserved",not scene.street_life.birds.is_empty() and bird_errors.is_empty(),{"birds":scene.street_life.birds.size(),"errors":bird_errors})
	observations["binding"]=scene.terrain_binding.snapshot()

func _public_geometry() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/public_walk.json"))
	var rows: Array=[];var failures: Array=[]
	for route: Dictionary in data.routes:
		var samples:=0;var slope:=0.;var max_gap:=0.;var minimum:=INF;var maximum:=-INF
		for index in range(1,route.xz.size()):
			var a:=Vector3(route.xz[index-1][0],0,route.xz[index-1][1]);var b:=Vector3(route.xz[index][0],0,route.xz[index][1])
			var steps:=maxi(1,ceili(a.distance_to(b)))
			for tick in range(steps+1):
				var point: Vector3=a.lerp(b,float(tick)/steps);var h: float=terrain.ground_y_world(point);var floor: Dictionary=_ground(point);samples+=1
				minimum=minf(minimum,h);maximum=maxf(maximum,h)
				if floor.is_empty():failures.append({"route":route.id,"point":point,"reason":"no_floor"});continue
				max_gap=maxf(max_gap,absf(floor.position.y-h));slope=maxf(slope,rad_to_deg(acos(clampf(floor.normal.y,-1.,1.))))
				if floor.normal.y<.71 or absf(floor.position.y-h)>.16:failures.append({"route":route.id,"point":point,"floor":floor.position,"normal":floor.normal,"query_y":h})
		rows.append({"route":route.id,"samples":samples,"maximum_slope_degrees":slope,"native_gap_m":max_gap,"relative_height_range_m":[minimum,maximum]})
	_check("public.all_source_route_ground_sections_supported",failures.is_empty(),{"routes":rows,"failures":failures})

func _walk_targets(title: String,points: Array,run_fast: bool) -> bool:
	var recovery: int=scene.player.recoveries;var count:=0;var grounded:=0;var max_step:=0.;var min_y:=INF;var max_y:=-INF;var camera_hits:=0;var success:=true;var failed_index:=-1;var stalled:=0
	var start: Vector3=scene.player.global_position
	for index in range(points.size()):
		var target: Vector3=points[index];var gap_start: float=Vector2(target.x-scene.player.global_position.x,target.z-scene.player.global_position.z).length()
		var speed: float=scene.player.run_speed_mps if run_fast else scene.player.walk_speed_mps
		var budget:=maxi(100,ceili(gap_start/speed*60)*3+120);var reached:=false
		for tick in range(budget):
			var delta: Vector3=target-scene.player.global_position;delta.y=0.
			if delta.length()<.24:reached=true;break
			_world_keys(delta.normalized()*minf(1.,delta.length()/maxf(.35,speed/float(physics_hz))))
			if run_fast:Input.action_press("move_fast")
			var before: Vector3=scene.player.global_position
			await scene.player.physics_stepped
			var at: Vector3=scene.player.global_position;var moved: float=at.distance_to(before)
			count+=1;max_step=maxf(max_step,moved);min_y=minf(min_y,at.y);max_y=maxf(max_y,at.y)
			if scene.player.is_on_floor():grounded+=1
			if moved<.0001:stalled+=1
			else:stalled=0
			if count%30==0:
				var query:=PhysicsShapeQueryParameters3D.new();query.shape=scene.rig.arm.shape;query.transform=Transform3D(Basis.IDENTITY,scene.rig.camera.global_position);query.collision_mask=scene.rig.arm.collision_mask;query.exclude=[scene.player.get_rid()];query.margin=0.
				camera_hits+=scene.get_world_3d().direct_space_state.intersect_shape(query,1).size()
				traces.append({"walk":title,"tick":Engine.get_physics_frames(),"point":at,"floor":scene.player.is_on_floor(),"camera_distance":scene.rig.current_distance})
			if scene.player.recoveries!=recovery or stalled>180:break
		if not reached:success=false;failed_index=index;break
		if index%50==0:print("EXP21_WALK_PROGRESS ",title," reached=",index+1,"/",points.size()," at=",scene.player.global_position)
	_movement();await _ticks(10)
	var result: Dictionary={"title":title,"points":points.size(),"reached":success,"failed_index":failed_index,"ticks":count,"grounded_ticks":grounded,"maximum_step_m":max_step,"height_range_m":[min_y,max_y],"camera_overlap_samples":camera_hits,"recoveries":scene.player.recoveries-recovery,"start":start,"end":scene.player.global_position,"scenario_pose_calls_during_walk":0,"kind":"Production Input action movement, no mid-walk pose assignment"}
	result["physics_hz"]=physics_hz
	walks.append(_json(result));_check("walk."+title,success and count>10 and scene.player.recoveries==recovery and max_step<.45*60.0/physics_hz and camera_hits==0,result)
	return success

func _geometry_fixture_layers(node: Node, saved: Array) -> void:
	if node is CharacterBody3D and node!=scene.player:
		saved.append({"body":node,"layer":node.collision_layer,"path":String(node.get_path())})
		node.collision_layer=0
	for child: Node in node.get_children():_geometry_fixture_layers(child,saved)

func _journey() -> void:
	scene.set_pedestrians_running(false);scene.set_vehicles_running(false)
	# This is a static terrain/source-itinerary fixture. A paused original NPC
	# stands on its closed route; making it immovable would test a fixture
	# obstacle. Live actors retain all production layers in their own suite.
	var saved_layers: Array=[]
	_geometry_fixture_layers(scene,saved_layers)
	observations["geometry_walk_fixture"]={"purpose":"Isolate static ground/building/camera integration from paused dynamic actors", "temporarily_layerless_bodies":saved_layers.size(),"player_mask_unchanged":scene.player.collision_mask,"in_walk_pose_assignments":0,"live_actor_suite":"check_terrain_actors.gd"}
	_check("walk_fixture.all_44_dynamic_bodies_isolated_only_for_static_route",saved_layers.size()==44)
	scene.set_speed_profile("turbo")
	var itinerary: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/walkable_itinerary.json"))
	var points: Array=[]
	var source: Array=itinerary.points_xz if full_journey else itinerary.stages[0].xz
	for xz: Array in source:points.append(Vector3(xz[0],terrain.ground_y_world(Vector3(xz[0],0,xz[1]))+.08,xz[1]))
	if await _pose("source_itinerary_start",points[0]):await _walk_targets("source_3_3km_continuous" if full_journey else "daehanmun_forward",points.slice(1),true)
	if not full_journey:
		var backward: Array=points.duplicate();backward.reverse();await _walk_targets("daehanmun_backward",backward.slice(1),true)
	await _capture_native("daehanmun_source_grade")
	var museum: Array=[]
	for station in range(0,91,3):museum.append(scene.museum_approach.point_at_station(station)+Vector3.UP*.08)
	if await _pose("museum_source_path_start",museum[0]):
		await _walk_targets("museum_uphill_source_profile",museum.slice(1),true)
		await _capture_native("museum_source_high_ground")
		museum.reverse();await _walk_targets("museum_downhill_source_profile",museum.slice(1),true)
	var restored: int=0
	for item: Dictionary in saved_layers:
		item.body.collision_layer=item.layer
		if item.body.collision_layer==item.layer:restored+=1
	_check("walk_fixture.all_original_actor_layers_restored",restored==44,{"restored":restored,"positions_assigned":0})
	scene.set_pedestrians_running(true);scene.set_vehicles_running(true)

func _jump_and_gravity() -> void:
	var point: Vector3=scene.player.spawn_transform.origin
	if not await _pose("elevated_jump_start",point):return
	var initial: int=scene.player.recoveries;var peak: float=0.;var camera_hits: int=0
	for press in range(3):
		Input.action_press("jump");await _ticks(1);Input.action_release("jump")
		for tick in range(roundi(26.0*physics_hz/60.0)):
			await scene.player.physics_stepped
			peak=maxf(peak,scene._height_above_terrain(scene.player.global_position))
	await _capture_native("source_ground_repeated_jump")
	for tick in range(200):
		await scene.player.physics_stepped
		peak=maxf(peak,scene._height_above_terrain(scene.player.global_position))
		if scene.player.is_on_floor():break
	_check("jump.three_fresh_presses_and_gravity_land_on_same_elevated_ground",peak>6. and scene.player.is_on_floor() and scene.player.recoveries==initial and absf(scene.player.global_position.y-terrain.ground_y_world(scene.player.global_position))<.16,{"peak_relative_ground_m":peak,"landed":scene.player.global_position,"recoveries":scene.player.recoveries-initial,"input":"Three fresh jump actions; no pose during flight"})

func _recovery_and_modes() -> void:
	var before: int=scene.player.recoveries
	scene.player.global_position=Vector3(scene.player.global_position.x,-50,scene.player.global_position.z);await _ticks(10)
	_check("recovery.fall_returns_to_elevated_source_spawn",scene.player.recoveries==before+1 and scene.player.spawn_valid and absf(scene.player.global_position.y-terrain.ground_y_world(scene.player.global_position))<.15,{"point":scene.player.global_position,"spawn":scene.player.spawn_transform,"reason":scene.player.last_recovery_reason})
	scene.set_free_roam(false);await _ticks(5)
	_check("mode.bounded_walk_excludes_only_open_terrain_bit",not scene.player.free_roam_enabled and (scene.player.collision_mask&32)==0 and terrain.support.collision_layer==32 and scene.player.spawn_valid)
	scene.set_free_roam(true);await _ticks(5)
	_check("mode.open_terrain_restores_without_height_jump",scene.player.free_roam_enabled and (scene.player.collision_mask&32)!=0 and scene.player.is_on_floor())
	var elevated:=Vector3(-400,terrain.ground_y_world(Vector3(-400,0,-400)),-400)
	_check("hud.elevated_ground_is_not_roof",absf(scene._height_above_terrain(elevated))<.0001 and scene._height_above_terrain(elevated+Vector3.UP*10)>9.99,{"ground":elevated})

func _capture_native(title: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;RenderingServer.force_draw();await process_frame
	var path:=report_path.get_basename()+"_"+title+".png"
	var result: int=root.get_texture().get_image().save_png(path)
	captures.append({"name":title,"captured":result==OK,"path":path,"camera":_json(scene.rig.camera.global_transform),"player":_json(scene.player.global_position)})

func _run() -> void:
	_began_ms=Time.get_ticks_msec();started_at=Time.get_datetime_string_from_system()
	for path in ["res://scripts/terrain_surface.gd","res://scripts/terrain_scene_binding.gd","res://scripts/terrain_geometry_warp.gd","res://scripts/explore_walk.gd","res://scripts/player/free_roam_player.gd","res://assets/authored/terrain_heightfield.json","res://data/generated/terrain_surface.json","res://resources/world_geometry/world.json","res://../tests/game/check_terrain_integration.gd","res://../tests/game/terrain_greenery_checks.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	for path in ["res://scripts/source_polygon_index.gd","res://scripts/street_pedestrians.gd","res://scripts/neighborhood_population.gd","res://scripts/traffic/vehicle.gd","res://../tests/game/source_polygon_index_checks.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();_settings_path="/private/tmp/exp21-integration-"+str(OS.get_process_id())+".json"
	scene.exploration_physics_hz=physics_hz
	scene.exploration_settings_path=_settings_path;scene.quality_settings_path=_settings_path+".quality.json";root.add_child(scene);await _ticks(12)
	_check("startup.terrain_production_loaded",scene.runtime_ok,{"error":scene.exploration_error})
	if not scene.runtime_ok:_finish();return
	terrain=scene.terrain_surface;visit=scene.interior_visit
	if scene.menu.visible:await _menu_edge()
	scene.set_time_profile("day")
	_sample_surface();_public_geometry()
	var guards: Dictionary=load("res://../tests/game/source_polygon_index_checks.gd").new().inspect(scene)
	_check("guards.spatial_index_matches_original_static_protection_and_entry_rules",guards.passed,guards.evidence)
	var greenery: Dictionary=load("res://../tests/game/terrain_greenery_checks.gd").new().inspect(scene)
	_check("greenery.all_tree_source_positions_and_actual_native_floor_support",greenery.evidence.get("physical_passed",false),greenery.evidence)
	if DisplayServer.get_name()!="headless":_check("greenery.all_native_multimesh_instances_match_elevated_tree_positions",greenery.passed,greenery.evidence)
	else:observations["greenery_native_readback"]={"status":"DEFERRED","reason":"Dummy rendering cannot verify actual native MultiMesh transforms"}
	await _journey();await _jump_and_gravity();await _recovery_and_modes()
	await _capture_native("terrain_recovery_ground")
	for tick in range(120):
		var start:=Time.get_ticks_usec();await process_frame
		performance_rows.append({"frame_us":Time.get_ticks_usec()-start,"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"video_memory":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();paused=false
	var changed: Array=[]
	for path: String in source_hashes:
		if FileAccess.get_sha256(path)!=source_hashes[path]:changed.append(path)
	_check("sources.frozen_during_execution",changed.is_empty(),{"changed":changed})
	var failed:=0
	for check: Dictionary in checks:
		if not check.passed:failed+=1
	var report: Dictionary={"task":"EXP21","result":"PASS" if failed==0 else "FAIL","summary":{"checks":checks.size(),"failed":failed},"display":DisplayServer.get_name(),"started_at":started_at,"elapsed_wall_s":(Time.get_ticks_msec()-_began_ms)/1000.,"checks":checks,"observations":observations,"walks":walks,"traces":traces,"placements":placements,"captures":captures,"source_sha256":source_hashes,"performance_samples":performance_rows,"scope":"New EXP21 native physical/query/source-route integration. Explicit test setup placements and fall injection; production input thereafter. M1 local observation only; no surveyed DEM accuracy, human acceptance, M4, export or long-running performance claim."}
	report["physics_hz"]=Engine.physics_ticks_per_second
	var output:=FileAccess.open(report_path,FileAccess.WRITE);output.store_string(JSON.stringify(_json(report),"  ")+"\n");output.close()
	print("EXP21_INTEGRATION ",report.result," checks=",checks.size()," failed=",failed);quit(0 if failed==0 else 1)
