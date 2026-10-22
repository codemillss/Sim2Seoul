extends SceneTree
## Full real production car-theft/arrest/custody flow. Only the player's
## initial approach to each naturally placed/moving car is a location fixture.
var scene: Node3D
var cars: Node3D
var police: Node3D
var checks: Array=[]
var captures: Array=[]
var samples: Array=[]
var input_phase_samples: Array=[]
var report_path:="/tmp/sim2seoul-stolen-car-arrest.json"
var hashes: Dictionary={}
var initial_car_ids: Array=[]
var original_officer_ids: Array=[]
var player_shape_id:=0
var player_layer:=0
var player_mask:=0
var started:=0
var finished:=false
var stolen: Array[CharacterBody3D]=[]
var region_fixture:="central"
func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
		if argument.begins_with("--region="):region_fixture=argument.trim_prefix("--region=")
	Engine.max_fps=0;started=Time.get_ticks_msec();create_timer(300.,true,false,true).timeout.connect(func()->void:
		if not finished:_check("bounded_timeout",false);_finish()
	)
	_run.call_deferred()
func _hashes() -> Dictionary:
	var result: Dictionary={}
	for path: String in ["res://scripts/traffic_car_takeover.gd","res://scripts/city_public_safety.gd","res://scripts/city_weather_emergency.gd","res://scripts/city_bike_service.gd","res://scripts/drivable_car_service.gd","res://scripts/explore_walk.gd","res://scripts/player/exploration_avatar.gd","res://scripts/traffic/vehicle.gd","res://scripts/traffic/traffic_manager.gd","res://scripts/neighborhood_traffic.gd","res://resources/world_geometry/world.json","res://assets/authored/neighborhood_population.json","res://data/generated/traffic.json","res://data/generated/terrain_surface.json","res://../tests/game/check_stolen_car_arrest.gd","res://../tests/game/check_stolen_car_arrest_euljiro.gd"]:result[path]=FileAccess.get_sha256(path)
	return result
func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:result[str(key)]=_json(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value:result.append(_json(item))
		return result
	if value is float:return value if is_finite(value) else null
	return value
func _check(name: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":name,"passed":passed,"evidence":_json(evidence)});print("STOLEN_ARREST_CHECK ",name," ",passed)
func _ticks(count: int) -> void:
	# A camera physics signal can precede buffered input dispatch on the
	# first busy native frame. Wait for ordinary physics and process phases.
	for index: int in range(count):await physics_frame;await process_frame
func _e_input_observation(label: String) -> Dictionary:
	var visit: Node3D=scene.interior_visit
	var target: Node3D=scene._street_interact_target()
	return {"label":label,"physics_tick":Engine.get_physics_frames(),"process_frame":Engine.get_process_frames(),"interact_held":Input.is_action_pressed("interact"),"e_press_pending":visit._e_press_pending,"e_was_pressed":visit._e_was_pressed,"e_requires_release":visit.e_requires_release,"menu_open":scene.menu.visible,"street_target":String(target.name) if is_instance_valid(target) else "none","player":scene.player.global_position,"player_physics":scene.player.is_physics_processing(),"facility_control":scene.player.facility_control,"car_events":cars.events.duplicate(true),"pending_car_id":cars.pending_car.get_instance_id() if is_instance_valid(cars.pending_car) else 0,"pending_elapsed_s":cars.pending_elapsed_s,"pending_actual_distance_m":cars.pending_actual_distance_m,"car_riding":cars.riding,"seized_car_count":cars.bikes.size(),"police_wanted":police.wanted,"police_offense_count":police.offense_count}
func _press_e(pressed: bool) -> void:
	var event:=InputEventKey.new();event.keycode=KEY_E;event.physical_keycode=KEY_E;event.device=42;event.pressed=pressed;Input.parse_input_event(event)
func _tap_e() -> void:
	input_phase_samples.append(_e_input_observation("before_actual_E_press"))
	_press_e(true);input_phase_samples.append(_e_input_observation("immediately_after_pressed_parse_input_event"));await _ticks(2)
	_press_e(false);input_phase_samples.append(_e_input_observation("immediately_after_released_parse_input_event"));await _ticks(3)
	input_phase_samples.append(_e_input_observation("after_actual_E_process_and_physics_phases"))
func _capture(title: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await _ticks(3);await RenderingServer.frame_post_draw
	var path:=report_path.get_basename()+"_"+title+".png";var image:=root.get_texture().get_image();var status:=image.save_png(path)
	_check("native_capture_"+title,status==OK)
	if status==OK:captures.append({"file":path,"sha256":FileAccess.get_sha256(path),"scope":"Production car/officer/player/camera and actual pursuit/custody; player initial car approach is a location fixture. No car/officer teleport or direct capture call."})
func _observer(body: CharacterBody3D) -> bool:
	# Only the player is placed, before any offense. Cars/officers are never
	# moved, their velocities/timers/AI ownership never manufactured by tests.
	for offset: Vector3 in [Vector3(-2.15,0,-.38),Vector3(2.15,0,-.38),Vector3(-2.3,0,.5),Vector3(2.3,0,.5)]:
		var safe: Dictionary=scene.interior_visit._safe_external_point(body.to_global(offset))
		if safe.is_empty():continue
		scene.player.global_position=safe.point;scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();scene.rig.yaw=body.global_rotation.y+.6;scene.rig.pitch=deg_to_rad(-15.);scene.rig.requested_distance=7.2;scene.rig.current_distance=7.2;scene.rig.snap_to_target_pose();await _ticks(3)
		if cars._nearest_car()==body and cars.can_interact():return true
	return false
func _select_car(require_moving:=true) -> CharacterBody3D:
	var ranked: Array=[]
	for body: CharacterBody3D in cars.traffic_cars:
		if stolen.has(body) or not body.is_physics_processing():continue
		# Select a declared existing source corridor. The Euljiro fixture
		# repeats the actual formerly unreachable car from dev02 after its
		# police-only public-TIN gap fix; no car/officer position is replaced.
		var prefix: String="coverage_drive_3" if region_fixture=="euljiro" else "sejong_south"
		if not String(body.get_route_id()).begins_with(prefix):continue
		var speed: float=body._speed_mps
		# A genuinely moving low-speed pass leaves physical braking room while
		# the player waits at this one initial approach (no follow-up teleport).
		if (require_moving and speed<.25) or speed>2.0:continue
		var nearest:=INF
		for row: Dictionary in police.officers:nearest=minf(nearest,body.global_position.distance_to(row.body.global_position))
		if nearest<58.:ranked.append({"body":body,"distance":nearest})
	ranked.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.distance<b.distance)
	for row: Dictionary in ranked:
		if await _observer(row.body):return row.body
	return null
func _one_theft(kind: String,exit_near_officer: bool) -> bool:
	var body: CharacterBody3D
	for attempt: int in range(150):
		body=await _select_car(kind=="investigation")
		if is_instance_valid(body):break
		await _ticks(2)
	_check(kind+"_original_source_car_has_initial_player_approach",is_instance_valid(body),{"region_fixture":region_fixture})
	if not is_instance_valid(body):return false
	var initial_speed: float=body._speed_mps;var initial_car_position: Vector3=body.global_position;var initial_officers: Array=[]
	for row: Dictionary in police.officers:initial_officers.append({"id":row.body.get_instance_id(),"point":row.body.global_position,"distance_m":row.distance_m})
	var offenses_before: int=police.offense_count;var input_phase_start: int=input_phase_samples.size();await _tap_e()
	for tick: int in range(180):
		if not is_instance_valid(cars.pending_car):break
		await _ticks(1)
	var mounted: bool=cars.riding and not is_instance_valid(cars.pending_car) and cars.rental_index>=0 and cars.bikes[cars.rental_index].body==body
	_check(kind+"_physical_E_theft_stops_and_boards_exact_original_car",mounted and (kind!="investigation" or initial_speed>.25),{"body_id":body.get_instance_id(),"route_id":body.get_route_id(),"initial_speed_mps":initial_speed,"initial_position":initial_car_position,"stopped_position":body.global_position,"stop_distance_m":cars.pending_actual_distance_m,"officers_before":initial_officers,"input_phase":input_phase_samples.slice(input_phase_start),"cars":cars.snapshot()})
	if not mounted:return false
	stolen.append(body)
	_check(kind+"_confirmed_theft_automatically_starts_actual_police_chase",police.wanted and police.offense_count==offenses_before+1 and police.chase_remaining_s>58.,police.snapshot())
	var parked_position: Vector3=body.global_position;var capture_from_inside:=false;var pressed_exit:=false;var saw_pending_exit_pair:=false;var caught_before_expiry:=false;var elapsed_ticks:=0
	for tick: int in range(1830):
		if police.detained:caught_before_expiry=true;break
		if not police.wanted:break
		if tick%15==0:
			var officers: Array=[]
			for row: Dictionary in police.officers:officers.append({"point":row.body.global_position,"distance_m":row.distance_m,"state":row.state,"path_points":row.path.size(),"path_index":row.path_index,"path_job_phase":row.path_job.get("phase",""),"catchable":police._catchable(row)})
			samples.append({"scenario":kind,"tick":tick,"game_clock_s":police._clock,"player":scene.player.global_position,"car":body.global_position,"riding":cars.riding,"wanted":police.wanted,"officers":officers})
		if exit_near_officer and not pressed_exit:
			var safe: Dictionary=cars._safe_dismount()
			if not safe.is_empty():
				for row: Dictionary in police.officers:
					var distance: float=row.body.global_position.distance_to(safe.point)
					if distance<1.7 and distance>1.05:
						pressed_exit=true;_press_e(true);samples.append({"scenario":kind,"event":"reactive_E_exit_near_approaching_officer","officer_point":row.body.global_position,"safe_exit_point":safe.point,"distance_m":distance,"physics_tick":Engine.get_physics_frames()});break
		var was_inside: bool=cars.riding;await _ticks(1);elapsed_ticks+=1
		if pressed_exit:_press_e(false)
		if cars._collision_release_pending.size()>0:saw_pending_exit_pair=true
		if police.detained:capture_from_inside=was_inside and not pressed_exit;caught_before_expiry=true;break
	_check(kind+"_actual_officer_paths_catch_before_sixty_second_expiry",caught_before_expiry and police.detained,{"elapsed_game_s":float(elapsed_ticks)/Engine.physics_ticks_per_second,"police":police.snapshot(),"cars":cars.snapshot()})
	if not police.detained:return false
	_check(kind+"_capture_uses_expected_room_and_releases_car_owner",police.custody_kind==kind and not cars.riding and scene.player.facility_control and not scene.player.is_physics_processing() and scene.player.global_position.distance_to(police._room_origin)<8.0,{"capture_from_inside":capture_from_inside,"reactive_exit_pressed":pressed_exit,"saw_pending_exit_pair":saw_pending_exit_pair})
	if not exit_near_officer:_check("first_capture_happens_from_occupied_stolen_car",capture_from_inside)
	else:_check("second_capture_overlaps_real_E_dismount_publication",pressed_exit and saw_pending_exit_pair)
	var officer_travel:=0.
	for index: int in range(police.officers.size()):officer_travel+=maxf(0.,float(police.officers[index].distance_m)-float(initial_officers[index].distance_m))
	_check(kind+"_officers_physically_approach_without_replacement_or_teleport",officer_travel>1. and police.maximum_step_m<.30,{"actual_approach_distance_m":officer_travel,"maximum_step_m":police.maximum_step_m})
	await _capture(kind+"_actual_custody")
	var controls_held:=true;var saw_published_pair_release: bool=cars._collision_release_pending.is_empty();var custody_ticks:=0
	for tick: int in range(450):
		if not police.detained:break
		controls_held=controls_held and scene.player.facility_control and not scene.player.is_physics_processing()
		await _ticks(1);custody_ticks+=1
		if cars._collision_release_pending.is_empty():saw_published_pair_release=true
	_check(kind+"_custody_keeps_player_locked_through_delayed_vehicle_pair_release",controls_held and saw_published_pair_release,{"observed_custody_ticks":custody_ticks})
	_check(kind+"_automatic_release_restores_same_supported_player_capsule",not police.detained and not cars.riding and scene.player.is_physics_processing() and not scene.player.facility_control and scene.player.get_node("CollisionShape").shape.get_instance_id()==player_shape_id and scene.player.collision_layer==player_layer and scene.player.collision_mask==player_mask and not police._supported(scene.player.global_position).is_empty(),police.snapshot())
	_check(kind+"_seized_original_car_stays_parked_after_arrest_and_release",body.global_position.distance_to(parked_position)<.04 and cars.snapshot().original_identities_retained,{"parked":parked_position,"now":body.global_position,"body_id":body.get_instance_id()})
	await _ticks(160)
	return true
func _run() -> void:
	hashes=_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/stolen-car-arrest-test-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8)
	cars=scene.get("traffic_car_takeover");police=scene.get("city_public_safety")
	_check("production_car_police_and_world_ready",scene.runtime_ok and is_instance_valid(cars) and cars.loaded and is_instance_valid(police) and police.loaded,{"error":scene.exploration_error})
	if not scene.runtime_ok or not is_instance_valid(cars) or not cars.loaded or not is_instance_valid(police) or not police.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	await _ticks(4)
	for body: CharacterBody3D in cars.traffic_cars:initial_car_ids.append(body.get_instance_id())
	for row: Dictionary in police.officers:original_officer_ids.append(row.body.get_instance_id())
	player_shape_id=scene.player.get_node("CollisionShape").shape.get_instance_id();player_layer=scene.player.collision_layer;player_mask=scene.player.collision_mask
	if not await _one_theft("investigation",false):_finish();return
	if region_fixture!="euljiro":await _one_theft("holding",true)
	var final_ids: Array=[]
	for body: CharacterBody3D in scene.vehicles:final_ids.append(body.get_instance_id())
	for body: CharacterBody3D in scene.neighborhood_population.traffic.vehicles:final_ids.append(body.get_instance_id())
	var final_officers: Array=[]
	for row: Dictionary in police.officers:final_officers.append(row.body.get_instance_id())
	_check("all14_original_cars_and_same_posted_officers_retained",final_ids==initial_car_ids and initial_car_ids.size()==14 and final_officers==original_officer_ids and cars.snapshot().original_identities_retained)
	_finish()
func _finish() -> void:
	if finished:return
	finished=true;_press_e(false)
	_check("runtime_inputs_stable_during_actual_integration",hashes==_hashes() and not hashes.values().has(""),{"start":hashes,"end":_hashes()})
	var passed:=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(_json({"task":"EXP27_STOLEN_CAR_ACTUAL_ARREST","region_fixture":region_fixture,"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"physics_hz":Engine.physics_ticks_per_second,"recorded_at":Time.get_datetime_string_from_system(),"result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"captures":captures,"source_hashes":hashes,"police":police.snapshot() if is_instance_valid(police) else {},"cars":cars.snapshot() if is_instance_valid(cars) else {},"samples":samples,"input_phase_samples":input_phase_samples,"elapsed_ms":Time.get_ticks_msec()-started,"scope":"Physical KEY_E original moving-car theft, naturally posted officers physically approach/catch, actual custody and automatic release; player-only initial car approach fixtures. No officer/car teleport, direct capture method, forged offense/timer/ownership flags or OS/native visual acceptance claim."}),"  "));file.close();print("STOLEN_ARREST_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)
