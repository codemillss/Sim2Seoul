extends SceneTree
## Whole production scene. Only timers are shortened explicitly; responders
## retain normal movement, collision, source, support and return rules.
var scene: Node3D
var service: Node3D
var checks: Array=[]
var report_path:="/tmp/sim2seoul-weather-emergency.json"
var started:=0
var finished:=false
var hashes: Dictionary={}
var captures: Array=[]
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	started=Time.get_ticks_msec();Engine.max_fps=0
	create_timer(300.,true,false,true).timeout.connect(func()->void:
		if not finished:_check("bounded_timeout",false);_finish()
	)
	_run.call_deferred()
func _inputs() -> Dictionary:
	var result: Dictionary={}
	for path: String in ["res://scripts/city_weather_emergency.gd","res://scripts/fire_station_facility.gd","res://assets/authored/fire_station_service.json","res://../tests/game/check_city_weather_emergency.gd","res://scripts/explore_walk.gd","res://scripts/city_bike_service.gd","res://scripts/photo_atmosphere.gd","res://assets/authored/neighborhood_population.json","res://resources/world_geometry/world.json","res://data/generated/public_walk.json","res://data/generated/terrain_surface.json"]:result[path]=FileAccess.get_sha256(path)
	return result
func _check(title: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":evidence});print("FIRE_WEATHER_CHECK ",title," ",passed)
func _ticks(count: int) -> void:
	for i: int in range(count):await physics_frame
func _capture(title: String) -> void:
	var view: Dictionary=service.viewpoint()
	if view.is_empty():_check("observer_viewpoint_"+title,false,{"error":"No source-bound unoccupied camera viewpoint."});return
	_check("observer_viewpoint_"+title,true,{"viewpoint":service._json(view),"scope":"Same observer fixture in headless and native; never a responder placement."})
	# Explicit observer-only camera placement, never a responder placement.
	scene.player.global_position=view.point;var toward: Vector3=view.toward;var diff: Vector3=toward-view.point;scene.rig.yaw=atan2(-diff.x,-diff.z);scene.rig.pitch=deg_to_rad(float(view.get("camera_pitch_degrees",view.get("camera_pitch",-12.))));scene.rig.current_distance=float(view.get("camera_distance_m",view.get("camera_distance",5.)));scene.rig.requested_distance=scene.rig.current_distance;scene.rig.snap_to_target_pose()
	await _ticks(3)
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var path:=report_path.get_basename()+"_"+title+".png";var error:=root.get_texture().get_image().save_png(path)
	_check("native_capture_"+title,error==OK,{"file":path,"camera_fixture":"Observer player placement only; no responder teleport."})
	if error==OK:captures.append({"file":path,"sha256":FileAccess.get_sha256(path),"viewpoint":service._json(view),"actual_camera":scene.rig.snapshot()})
func _run() -> void:
	hashes=_inputs();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/fire-weather-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(5)
	service=scene.get("city_weather_emergency")
	if not is_instance_valid(service):service=load("res://scripts/city_weather_emergency.gd").new();scene.add_child(service);service.setup(scene)
	_check("whole_production_scene_and_new_service_loaded",scene.runtime_ok and service.loaded,{"exploration_error":scene.exploration_error,"service_error":service.load_error})
	if not service.loaded:_finish();return
	var original: Dictionary={"source_nodes":scene.city.source_nodes.size(),"old_people":scene.pedestrians.size(),"old_vehicles":scene.vehicles.size(),"new_people":scene.neighborhood_population.walkers.actors.size(),"new_cars":scene.neighborhood_population.traffic.vehicles.size(),"capsule":scene.player.get_node("CollisionShape").shape.get_rid().get_id()}
	_check("separate_visible_fire_station_engine_and_two_firefighters",is_instance_valid(service.station) and is_instance_valid(service.engine) and service.firefighters.size()==2,{"snapshot":service.snapshot()})
	var footprint_ok:=true
	for x: float in range(-18,19,2):
		for z: float in range(-15,16,2):
			var point: Vector3=service.station.to_global(Vector3(x,0,z));footprint_ok=footprint_ok and service._public(point,true) and not scene.city_bike_service._private_index.contains(Vector2(point.x,point.z)) and not service._ground(point).is_empty()
	_check("entire_real_scale_outskirts_campus_off_retained_private_walks_and_trees",footprint_ok and absf(service.station.global_position.x)>350. and service._walk_corridors_clear(service.station.global_position,service.station.rotation.y) and service._retained_tree_box_clear(service.station.global_position,service.station.rotation.y,Vector3(36.5,13.7,30.5)),{"footprint_m":[36.,30.],"source_ground_feature":service.provenance.source_ground_feature,"provenance":service._json(service.provenance),"whole_retained_tree_reservation":true,"bounded_game_campus_not_actual_public_land_claim":true})
	var required: Array=["RedApparatusHeader","ReceptionFrontLeftGlass","ReceptionDesk","UpperOfficeWindow","119IdentityLarge","GarageDoorSlat","FireGearLocker","CanopyWarmLED"]
	_check("recognizable_public_facility_with_real_open_reception_and_apparatus_bay",required.all(func(title: String)->bool:return title in service.facility_details.features) and float(service.facility_details.reception_open_door_width_m)>=1.2 and float(service.facility_details.garage_width_m)>=4.5 and service.facility_details.apparatus_bay_count>=2 and service.facility_details.garage_clear_height_m>=4.5 and service.facility_details.garage_clear_depth_m>=11. and is_instance_valid(service.standby_engine) and service.engine.get_child(0).shape.size.z>=8.,{"details":service.facility_details,"scope":"Component/size checks; actual native images still require independent visual review."})
	var full_capsules_clear:=true;var capsule_rows: Array=[]
	for row: Dictionary in service.firefighters:
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=row.body.get_child(0).shape;query.transform=row.body.global_transform;query.transform.origin+=Vector3.UP*.90;query.collision_mask=1|2|4|8|32;query.exclude=[row.body.get_rid()]
		var hits: Array=[]
		for hit: Dictionary in scene.get_world_3d().direct_space_state.intersect_shape(query,8):hits.append(String(hit.collider.get_path()))
		full_capsules_clear=full_capsules_clear and hits.is_empty();capsule_rows.append({"name":String(row.body.name),"contacts":hits})
	_check("complete_initial_firefighter_capsules_clear_actual_garage_and_engine",full_capsules_clear,{"capsules":capsule_rows})
	var engine_query:=PhysicsShapeQueryParameters3D.new();engine_query.shape=service.engine.get_child(0).shape;engine_query.transform=service.engine.global_transform;engine_query.transform.origin+=Vector3.UP*1.75;engine_query.collision_mask=1|2|4|8|32;engine_query.exclude=[service.engine.get_rid()];var engine_hits: Array=[]
	for hit: Dictionary in scene.get_world_3d().direct_space_state.intersect_shape(engine_query,8):engine_hits.append(String(hit.collider.get_path()))
	_check("full_initial_engine_box_clear_actual_garage_and_crew",engine_hits.is_empty(),{"contacts":engine_hits})
	var visitor:=CharacterBody3D.new();visitor.name="ExplicitEntranceCapsuleProbe";visitor.collision_layer=2;visitor.collision_mask=1|2|4|8|32
	var visitor_shape:=CollisionShape3D.new();visitor_shape.shape=scene.player.get_node("CollisionShape").shape;visitor_shape.position.y=.85;visitor.add_child(visitor_shape);scene.add_child(visitor)
	var entrance_clear:=true;var entrance_distance:=0.;var entrance_contacts: Array=[]
	var entrance_start: Vector3=service.station.to_global(Vector3(10.75,0,-28.5));visitor.global_position=service._travel_ground(entrance_start).point+Vector3.UP*.08
	for i: int in range(1,317):
		var point: Vector3=service.station.to_global(Vector3(10.75,0,-28.5+float(i)*.05));var floor: Dictionary=service._travel_ground(point)
		if floor.is_empty():entrance_clear=false;break
		point.y=floor.point.y+.08;var before: Vector3=visitor.global_position;var hit:=visitor.move_and_collide(point-before,false,.001,false);entrance_distance+=visitor.global_position.distance_to(before)
		if hit!=null:entrance_contacts.append(String(hit.get_collider().get_path()));entrance_clear=false;break
	_check("actual_human_capsule_traverses_accessible_apron_and_reception_door",entrance_clear and entrance_distance>15.,{"distance_m":entrance_distance,"contacts":entrance_contacts,"capsule":"Unmodified production player shape; actual native movement from forecourt through 1.6m open door, no responder teleport."})
	visitor.queue_free();await _ticks(2)
	scene.set_time_profile("day");await _capture("initial_daylight_119_station_front")
	var before: Dictionary=service.snapshot();scene.toggle_menu();await _ticks(15);var after: Dictionary=service.snapshot();_check("menu_pauses_both_weather_and_response_clocks",before.clock_s==after.clock_s and before.weather_clock_s==after.weather_clock_s,{"before":before,"after":after});scene.toggle_menu()
	# Explicit short-clock test configuration. Physical speeds, support,
	# collisions and incident coordinates stay unchanged.
	service.policy.clear_s=3.;service.policy.rain_s=9.;service.policy.extinguish_s=3.;service.next_fire_s=service.clock_s+4.
	var saw_rain:=false;var saw_clear_after:=false;var saw_dispatch:=false;var saw_water:=false;var saw_crew_return:=false;var saw_engine_return:=false
	for i: int in range(30*135):
		await _ticks(1)
		if i%300==0:print("FIRE_WEATHER_PROGRESS ",JSON.stringify(service.snapshot()))
		if service.weather=="rain":saw_rain=true
		if saw_rain and service.weather=="clear":saw_clear_after=true
		if service.fire_state=="dispatch":saw_dispatch=true
		if service.fire_state=="extinguishing" and not saw_water:saw_water=true;await _capture("rain_firefighters_water")
		if service.fire_state=="crew_return":saw_crew_return=true
		if service.fire_state=="engine_return":saw_engine_return=true
		if service.completed_returns>=1:break
		if service.state_clock_s>35. and service.blocked_ticks>800:break
	_check("autonomous_clear_rain_clear_cycle",saw_rain and saw_clear_after,{"weather":service.snapshot()})
	_check("actual_dispatch_arrival_water_extinguish_and_return",saw_dispatch and saw_water and saw_crew_return and saw_engine_return and service.fires_extinguished==1 and service.completed_returns==1,{"snapshot":service.snapshot(),"test_clock":{"clear_s":3.,"rain_s":9.,"extinguish_s":3.,"first_fire_after_s":4.},"physical_speeds_unchanged":true})
	_check("responders_moved_physically_without_teleport",service.engine_distance_m>30. and service.crew_distance_m>35.,{"engine_distance_m":service.engine_distance_m,"crew_distance_m":service.crew_distance_m,"blocked_ticks":service.blocked_ticks})
	var engine_home: float=Vector2(service.engine.global_position.x-service._depot.x,service.engine.global_position.z-service._depot.z).length();var crew_home:=true
	for row: Dictionary in service.firefighters:crew_home=crew_home and row.body.global_position.distance_to(row.home)<.16
	_check("engine_and_both_firefighters_return_to_station",engine_home<.16 and crew_home,{"engine_home_distance_m":engine_home,"snapshot":service.snapshot()})
	service.weather="rain";service.weather_clock_s=0.;await _ticks(4);scene.player.interior_active=true;await _ticks(3)
	_check("interior_has_no_rain_streaks_or_splashes",not service._rain.visible and service._puddles.all(func(node: Node3D)->bool:return not node.visible),{"snapshot":service.snapshot()});scene.player.interior_active=false
	for time_id: String in ["day","evening","night"]:
		scene.set_time_profile(time_id);service.weather="rain";service.weather_clock_s=0.;await _ticks(4)
		_check("rain_preserves_time_profile_"+time_id,scene.time_id==time_id and service._baseline_time==time_id and scene.photo_atmosphere.sun.light_energy>0.,{"baseline_time":service._baseline_time,"sun_energy":scene.photo_atmosphere.sun.light_energy})
	var current: Dictionary={"source_nodes":scene.city.source_nodes.size(),"old_people":scene.pedestrians.size(),"old_vehicles":scene.vehicles.size(),"new_people":scene.neighborhood_population.walkers.actors.size(),"new_cars":scene.neighborhood_population.traffic.vehicles.size(),"capsule":scene.player.get_node("CollisionShape").shape.get_rid().get_id()}
	_check("source_nodes_original_actors_and_player_capsule_preserved",original==current,{"before":original,"after":current})
	await _capture("returned_119_station");_finish()
func _finish() -> void:
	if finished:return
	finished=true;_check("source_inputs_stable_during_run",hashes==_inputs() and not hashes.values().has(""),{"start":hashes,"end":_inputs()})
	var passed: int=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify({"task":"EXP27_FIRE_WEATHER","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"snapshot":service.snapshot() if is_instance_valid(service) else {},"source_hashes":_inputs(),"captures":captures,"physics_hz":Engine.physics_ticks_per_second,"display_server":DisplayServer.get_name(),"elapsed_ms":Time.get_ticks_msec()-started,"scope":"Whole production scene. Short weather/fire timer configuration explicitly labelled; physical engine/crew positions and movement are production. No real weather, fire spread, Seoul station/operations, subjective comfort or sustained performance claim."},"  "));file.close()
	if is_instance_valid(scene):
		if is_instance_valid(scene.neighborhood_life) and is_instance_valid(scene.neighborhood_life.audio):scene.neighborhood_life.audio.stop();scene.neighborhood_life.audio.stream=null
		await physics_frame;await physics_frame;scene.queue_free();await process_frame;await process_frame
	print("FIRE_WEATHER_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)
