extends SceneTree
## Physical F edges and original adult targets, source-native officer paths,
## sixty actual simulation seconds, pausable custody and restored control.
var scene: Node3D
var service: Node3D
var checks: Array=[]
var captures: Array=[]
var report_path := "/tmp/sim2seoul-public-safety.json"
var started := 0
var finished := false
var source_hashes: Dictionary={}
var original_people: Array=[]
var original_dogs: Array=[]
var original_cars: Array=[]
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	Engine.max_fps=0;started=Time.get_ticks_msec();create_timer(480.,true,false,true).timeout.connect(func()->void:if not finished:_check("bounded_timeout",false);_finish())
	_run.call_deferred()
func _hashes() -> Dictionary:
	var result: Dictionary={}
	for path: String in ["res://scripts/city_police_headquarters.gd","res://assets/authored/police_headquarters.json","res://scripts/city_police_facility.gd","res://assets/authored/police_facility.json","res://scripts/city_police_patrol.gd","res://assets/authored/police_patrol.json","res://scripts/city_public_safety.gd","res://scripts/city_bike_service.gd","res://scripts/drivable_car_service.gd","res://scripts/traffic_car_takeover.gd","res://scripts/player/exploration_avatar.gd","res://scripts/explore_walk.gd","res://resources/world_geometry/world.json","res://assets/authored/bike_service.json","res://assets/authored/scooter_service.json","res://assets/authored/neighborhood_population.json","res://data/generated/public_walk.json","res://data/generated/terrain_surface.json","res://../tests/game/check_city_public_safety.gd"]:result[path]=FileAccess.get_sha256(path)
	return result
func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:result[str(key)]=_json(value[key])
		return result
	if value is Array or value is PackedVector3Array:
		var result: Array=[]
		for item: Variant in value:result.append(_json(item))
		return result
	if value is float:return value if is_finite(value) else null
	return value
func _check(title: String,ok: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":ok,"evidence":_json(evidence)});print("PUBLIC_SAFETY_CHECK ",title," ",ok)
func _ticks(count: int) -> void:
	for index: int in range(count):await physics_frame;await process_frame
func _f_event(pressed: bool,echo:=false) -> void:
	var event:=InputEventKey.new();event.keycode=KEY_F;event.physical_keycode=KEY_F;event.pressed=pressed;event.echo=echo;Input.parse_input_event(event)
func _tap_f(device:=0) -> void:
	var event:=InputEventKey.new();event.keycode=KEY_F;event.physical_keycode=KEY_F;event.device=device;event.pressed=true;Input.parse_input_event(event);await _ticks(2)
	event=InputEventKey.new();event.keycode=KEY_F;event.physical_keycode=KEY_F;event.device=device;event.pressed=false;Input.parse_input_event(event);await _ticks(2)
func _capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await _ticks(3);await RenderingServer.frame_post_draw;var image:=root.get_texture().get_image();var path:=report_path.get_basename()+"_"+name+".png";var error:=image.save_png(path)
	_check("capture_"+name,error==OK,{"path":path,"size":[image.get_width(),image.get_height()]})
	if error==OK:captures.append({"path":path,"sha256":FileAccess.get_sha256(path),"scope":"Actual production camera; test-only player starts disclosed."})
func _place_near(body: CharacterBody3D,range_m:=1.25) -> bool:
	for index: int in range(16):
		var angle:=float(index)*TAU/16.;var point:=body.global_position+Vector3(sin(angle),0,cos(angle))*range_m
		var floor: Dictionary=service._supported(point,true)
		if floor.is_empty():continue
		if not scene.free_roam_enabled and not scene.city.movement_contains(Vector2(floor.point.x,floor.point.z)):continue
		scene.player.set_facility_control(false);scene.player.set_physics_process(true);scene.player.global_position=floor.point;scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();var toward: Vector3=body.global_position-floor.point;toward.y=0.;scene.player.get_node("Visual").rotation.y=atan2(-toward.x,-toward.z);scene.rig.yaw=scene.player.get_node("Visual").rotation.y+.3;scene.rig.pitch=deg_to_rad(-15.);scene.rig.requested_distance=4.5;scene.rig.current_distance=4.5;scene.rig.snap_to_target_pose();await _ticks(4);return true
	return false
func _run() -> void:
	source_hashes=_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/city-public-safety-test-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8)
	service=scene.get("city_public_safety")
	if not is_instance_valid(service):service=load("res://scripts/city_public_safety.gd").new();scene.add_child(service);service.setup(scene)
	_check("production_service_loaded_with_supported_uniformed_native_officers",scene.runtime_ok and service.loaded and service.officers.size()>=2,{"scene_error":scene.exploration_error,"service_error":service.load_error,"snapshot":service.snapshot()})
	if not scene.runtime_ok or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	_check("posted_officers_have_native_floor_contact_and_idle_gait",service.officers.all(func(row: Dictionary)->bool:return row.body.is_on_floor() and row.avatar.state=="idle"),service.snapshot())
	var rental_clearance: Dictionary=service.rental_clearance_snapshot();_check("all16_rental_dock_fixtures_boarding_and8m_departures_clear_of_police_homes",rental_clearance.reserved_docks==16 and rental_clearance.home_violations.is_empty() and rental_clearance.posted_violations.is_empty(),rental_clearance)
	scene.set_pedestrians_running(false);scene.set_vehicles_running(false)
	for body: CharacterBody3D in scene.pedestrians:original_people.append(body.get_instance_id())
	for controller: Node in [scene.street_pedestrians,scene.neighborhood_population.walkers]:
		for row: Dictionary in controller.actors:
			if row.kind=="walker":original_people.append(row.body.get_instance_id())
			else:original_dogs.append(row.body.get_instance_id())
	for body: CharacterBody3D in scene.vehicles:original_cars.append(body.get_instance_id())
	for body: CharacterBody3D in scene.neighborhood_population.traffic.vehicles:original_cars.append(body.get_instance_id())
	var target: Dictionary={}
	for row: Dictionary in scene.street_pedestrians.actors:
		if row.kind=="walker" and await _place_near(row.body):target=row;break
	_check("player_only_supported_approach_to_existing_adult",not target.is_empty())
	if target.is_empty():_finish();return
	await _capture("adult_before_punch")
	var before_hits: int=service.hits;await _tap_f();_check("physical_f_hits_existing_adult_and_starts_sixty_seconds",service.hits==before_hits+1 and service.wanted and service.chase_remaining_s>59.,{"snapshot":service.snapshot()})
	var punch_weight: float=scene.exploration_avatar._sandbox_remaining_s;_check("visible_non_graphic_punch_animation_without_camera_shake",punch_weight>0.,{"action":scene.exploration_avatar._sandbox_action,"remaining_s":punch_weight})
	var start_count: int=service.offense_count;service.punch();_check("punch_cooldown_blocks_repeat_offense",service.offense_count==start_count)
	await _capture("police_response")
	# The same first report reaches its actual first catch; no test changes the
	# offense count, wanted state, timers, police transforms or NPC identities.
	var initial_placed:=await _place_near(service.officers[0].body,1.15)
	for index: int in range(180):
		if service.detained:break
		await _ticks(1)
	_check("actual_first_offense_nearby_ground_capture_enters_investigation",initial_placed and service.detained and service.custody_kind=="investigation",service.snapshot())
	if service.detained:
		await _capture("authored_investigation")
		var custody_before: float=service.detention_remaining_s;scene.toggle_menu();await _ticks(30);_check("real_menu_pauses_detention_timer",is_equal_approx(custody_before,service.detention_remaining_s));scene.toggle_menu()
		var wrong_shortcut_before: Vector3=scene.player.global_position;scene._visit_street_detail("bike_station");_check("detention_blocks_menu_teleport_shortcut",scene.player.global_position.distance_to(wrong_shortcut_before)<.05)
		await _ticks(270);_check("investigation_automatically_releases_to_supported_world_and_restores_control",not service.detained and scene.player.is_physics_processing() and not scene.player.facility_control and not service._supported(scene.player.global_position).is_empty(),service.snapshot())
	await _ticks(165)
	# Root preserves a press+release delivered between consecutive physics
	# steps. Use an empty-facing ground start to test edges without new harm.
	var attempted_before: float=service._next_punch_s
	_f_event(true);_f_event(false);await _ticks(3)
	_check("physical_f_short_press_release_between_ticks_is_preserved",service._next_punch_s>attempted_before)
	await _ticks(24);attempted_before=service._next_punch_s
	_f_event(true);await _ticks(3);var held_once: float=service._next_punch_s;_f_event(true,true);await _ticks(30)
	_check("physical_f_hold_and_echo_do_not_repeat",held_once>attempted_before and is_equal_approx(held_once,service._next_punch_s));_f_event(false)
	scene.toggle_menu();attempted_before=service._next_punch_s;_f_event(true);await _ticks(3);scene.toggle_menu();_f_event(true,true);await _ticks(24)
	_check("menu_held_f_does_not_trigger_on_resume_until_released",is_equal_approx(attempted_before,service._next_punch_s));_f_event(false)
	# A raised observer platform explicitly tests that elevated players cannot
	# be arrested from original street terrain or through a static blocker.
	var platform:=StaticBody3D.new();platform.name="TestOnlyRaisedPlayerObserverPlatform";platform.collision_layer=1;var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(4.,.2,4.);collider.shape=box;platform.add_child(collider);scene.add_child(platform);platform.global_position=scene.player.global_position+Vector3.UP*4.
	scene.player.global_position=platform.global_position+Vector3.UP*.12;scene.player.velocity=Vector3.ZERO;scene.player.set_physics_process(false);scene.player.reset_physics_interpolation();scene.rig.snap_to_target_pose();await _ticks(3)
	service.report_offense("test escape report",scene.player.global_position)
	var no_air_catch:=true
	for row: Dictionary in service.officers:no_air_catch=no_air_catch and not service._catchable(row)
	_check("no_arrest_for_elevated_player",no_air_catch)
	var remaining_before: float=service.chase_remaining_s;scene.toggle_menu();await _ticks(30);_check("real_menu_pauses_wanted_timer",is_equal_approx(remaining_before,service.chase_remaining_s));scene.toggle_menu()
	var dog_candidates: Array=[]
	for row: Dictionary in service._adult_candidates():dog_candidates.append(row.body.get_instance_id())
	_check("dogs_excluded_from_punch_targets",original_dogs.size()==2 and not dog_candidates.has(original_dogs[0]) and not dog_candidates.has(original_dogs[1]))
	var clock_before: float=service._clock;await _ticks(1830)
	_check("actual_sixty_simulation_seconds_escape_and_return_state",not service.wanted and not service.detained and service._clock-clock_before>=60. and service.events.any(func(row: Dictionary)->bool:return row.event=="escaped_after_sixty_seconds"),{"elapsed_game_s":service._clock-clock_before,"officers":service.snapshot().officers,"events":service.events})
	_check("officers_moved_with_bounded_native_steps",service.actual_officer_distance_m>1. and service.maximum_step_m<.30,{"actual_distance_m":service.actual_officer_distance_m,"maximum_step_m":service.maximum_step_m})
	platform.queue_free();scene.player.set_physics_process(true)
	scene.set_free_roam(false);var selected_mode_before: bool=scene.free_roam_enabled
	var placed:=await _place_near(service.officers[0].body,1.15)
	if placed:
		var wall:=StaticBody3D.new();wall.name="TestOnlyOfficerLOSBlocker";wall.collision_layer=1;var shape:=CollisionShape3D.new();var wall_box:=BoxShape3D.new();wall_box.size=Vector3(2.,2.4,.08);shape.shape=wall_box;wall.add_child(shape);scene.add_child(wall)
		var toward: Vector3=service.officers[0].body.global_position-scene.player.global_position;toward.y=0.;wall.global_transform=Transform3D(Basis(Vector3.UP,atan2(-toward.x,-toward.z)),(service.officers[0].body.global_position+scene.player.global_position)*.5+Vector3.UP*1.2)
		await _ticks(2);_check("native_wall_blocks_nearby_officer_arrest",not service._catchable(service.officers[0]));wall.queue_free();await _ticks(3)
	_check("supported_player_only_officer_catch_approach",placed)
	if placed:
		service.report_offense("test repeated assault report",scene.player.global_position);await _ticks(5);_check("repeated_offense_uses_visible_holding_room",service.detained and service.custody_kind=="holding",service.snapshot())
		if service.detained:
			await _capture("authored_holding")
			var cell_before: Vector3=scene.player.global_position;scene.free_roam_switch.set_pressed(not scene.free_roam_switch.button_pressed);await _ticks(3)
			_check("detention_settings_checkbox_cannot_recover_out_of_room",service.detained and scene.player.global_position.distance_to(cell_before)<.05)
			await _ticks(390)
		_check("custody_restores_selected_public_walk_mode",scene.free_roam_enabled==selected_mode_before and scene.player.free_roam_enabled==selected_mode_before,{"before":selected_mode_before,"host":scene.free_roam_enabled,"player":scene.player.free_roam_enabled})
		_check("holding_automatically_releases_with_no_stuck_controls",not service.detained and service.releases>=2 and scene.player.is_physics_processing() and not scene.player.facility_control,service.snapshot())
	_check("officer_render_anchors_interpolate_without_moving_capsules",service.render_frames>0 and service.maximum_render_anchor_error_m<.0001,{"render_frames":service.render_frames,"maximum_anchor_error_m":service.maximum_render_anchor_error_m,"maximum_path_chunk_ms":service.maximum_path_plan_ms,"maximum_path_job_cpu_ms":service.maximum_path_job_cpu_ms,"configured_budget_ms_per_officer":1.5})
	var people_now: Array=[];var dogs_now: Array=[];var cars_now: Array=[]
	for body: CharacterBody3D in scene.pedestrians:people_now.append(body.get_instance_id())
	for controller: Node in [scene.street_pedestrians,scene.neighborhood_population.walkers]:
		for row: Dictionary in controller.actors:
			if row.kind=="walker":people_now.append(row.body.get_instance_id())
			else:dogs_now.append(row.body.get_instance_id())
	for body: CharacterBody3D in scene.vehicles:cars_now.append(body.get_instance_id())
	for body: CharacterBody3D in scene.neighborhood_population.traffic.vehicles:cars_now.append(body.get_instance_id())
	_check("original_28_adult_2_dog_14_car_identities_retained",people_now==original_people and dogs_now==original_dogs and cars_now==original_cars and original_people.size()==28 and original_dogs.size()==2 and original_cars.size()==14)
	_finish()
func _finish() -> void:
	if finished:return
	finished=true;_check("source_inputs_stable_during_actual_run",_hashes()==source_hashes and not source_hashes.values().has(""),{"start":source_hashes,"end":_hashes()})
	var passed: int=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot write public safety report");quit(2);return
	file.store_string(JSON.stringify(_json({"task":"EXP27_PUBLIC_SAFETY","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"captures":captures,"source_hashes":source_hashes,"snapshot":service.snapshot() if is_instance_valid(service) else {},"elapsed_ms":Time.get_ticks_msec()-started,"scope":"Production scene, physical F, original adult identities, test-only player starts and raised platform; sixty actual game seconds, menu pause and custody restoration. Headless does not prove appearance or user comfort."}),"  "));file.close();print("PUBLIC_SAFETY_RESULT ",passed,"/",checks.size())
	if is_instance_valid(scene):
		if is_instance_valid(scene.neighborhood_life.audio):scene.neighborhood_life.audio.stop();scene.neighborhood_life.audio.stream=null
		await physics_frame;await physics_frame;scene.queue_free();await process_frame;await process_frame
	quit(0 if passed==checks.size() else 1)
