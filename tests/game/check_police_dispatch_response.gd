extends "res://../tests/game/check_city_public_safety.gd"
## Assault locations use only test player starts. All officers begin at their
## real production posts and every response step uses retained native physics.
var sectors: Array=[]
func _run() -> void:
	source_hashes=_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/private/tmp/police-response-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8)
	service=scene.city_public_safety
	_check("actual_city_dispatch_loaded",scene.runtime_ok and service.loaded,{"error":scene.exploration_error,"safety_error":service.load_error})
	if not scene.runtime_ok or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	scene.set_pedestrians_running(false)
	var ids: Array=[]
	for row: Dictionary in service._adult_candidates():ids.append(row.body.get_instance_id())
	var coverage: Array=service.snapshot().district_coverage
	_check("initial_public_posts_within90m_straightline_of_original_adults",coverage.size()==28 and coverage.all(func(row: Dictionary)->bool:return row.nearest_initial_post_m<=90.),{"post_count":service.officers.size(),"coverage":coverage})
	_check("initial_posts_keep_rental_and_entrance_clearance",service.rental_clearance_snapshot().home_violations.is_empty(),service.rental_clearance_snapshot())
	var selected: Array=[]
	for row: Dictionary in scene.street_pedestrians.actors:
		if row.kind=="walker" and row.group in ["stonewall_east","museum_slope"]:selected.append(row)
	for row: Dictionary in scene.neighborhood_population.walkers.actors:
		if row.kind=="walker" and row.group=="coverage_walk_01_0":selected.append(row)
	_check("three_actual_city_sectors_selected",selected.size()==3)
	if selected.size()==3:
		var remote_placed:=await _place_near(selected[0].body,1.25)
		var remote_hits: int=service.hits;var remote_offenses: int=service.offense_count
		await _tap_f();await _ticks(24)
		_check("remote125cm_target_rejects_contact_without_dispatch",remote_placed and service.hits==remote_hits and service.offense_count==remote_offenses,{"events":service.events.slice(-4)})
	for target: Dictionary in selected:
		var placed:=await _place_near(target.body,.88)
		_check("supported_test_player_assault_start_"+target.group,placed)
		if not placed:continue
		await _ticks(24)
		# Measure dispatch movement from the actual pre-offense positions.
		# A nearby officer can already be inside6m during the victim's18-tick
		# recovery wait; starting there falsely measures its real arrival as0m.
		var initial: Dictionary={};var initial_clock: float=service._clock
		for officer: Dictionary in service.officers:initial[str(officer.body.name)]=officer.body.global_position
		var hit_before: int=service.hits;var victim_before: Vector3=target.body.global_position
		await _tap_f()
		for tick: int in range(24):
			if service.hits>hit_before:break
			await _ticks(1)
		_check("actual_knuckle_assault_dispatches_"+target.group,service.hits==hit_before+1 and service.wanted,{"combat":service.combat_snapshot(),"events":service.events.slice(-8)})
		if service.hits==hit_before:
			print("NATIVE_MISS33 ",target.group," target=",target.body.global_position," player=",scene.player.global_position," basis=",scene.player.get_node("Visual").global_basis," native=",scene.exploration_avatar.get_sandbox_strike_contact("jab_left"));continue
		await _ticks(18)
		var victim_step: float=Vector2(target.body.global_position.x-victim_before.x,target.body.global_position.z-victim_before.z).length()
		_check("bounded_physical_victim_stagger_restores_route_"+target.group,victim_step>.005 and victim_step<.36 and not preload("res://scripts/actor_hit_reaction.gd").owns(target.body),{"distance_m":victim_step,"target":str(target.body.get_path()),"events":service.events.slice(-6)})
		var origin: Vector3=scene.player.global_position;var start_clock: float=service._clock
		var trace: Array=[];var arrived:=false
		for tick: int in range(1350):
			if tick%30==0:
				var rows: Array=[]
				for officer: Dictionary in service.officers:
					if officer.state=="pursuing":rows.append({"name":str(officer.body.name),"position":officer.body.global_position,"distance_m":officer.body.global_position.distance_to(origin),"travelled_m":officer.distance_m,"pending_path":not officer.path_job.is_empty()})
				trace.append({"game_s":service._clock-start_clock,"responders":rows})
			if service._first_arrival_s>=0.:arrived=true;break
			if service.detained:break
			await _ticks(1)
		_check("officer_physically_arrives_at_stationary_assault_"+target.group,arrived and service._first_arrival_s<45.,{"arrival_s":service._first_arrival_s,"initial_posts":initial,"initial_positions_recorded_before_actual_F":true,"initial_snapshot_clock_s":initial_clock,"trace":trace,"player_movement_m":scene.player.global_position.distance_to(origin)})
		sectors.append({"sector":target.group,"arrival_s":service._first_arrival_s,"trace":trace})
		var visible_arrival:=false;var arrival_travel:=0.
		if arrived:
			for tick: int in range(300):
				var nearest:=INF;var toward:=Vector3.ZERO
				for officer: Dictionary in service.officers:
					var distance: float=officer.body.global_position.distance_to(scene.player.global_position)
					if officer.state=="pursuing" and distance<nearest:nearest=distance;toward=officer.body.global_position-scene.player.global_position
				if nearest<6.:
					visible_arrival=true
					for officer: Dictionary in service.officers:
						if officer.state=="pursuing" and officer.body.global_position.distance_to(scene.player.global_position)<6.:arrival_travel=maxf(arrival_travel,officer.body.global_position.distance_to(initial[str(officer.body.name)]))
					scene.rig.yaw=atan2(-toward.x,-toward.z);scene.rig.requested_distance=5.0;scene.rig.current_distance=5.0;scene.rig.snap_to_target_pose();break
				if service.detained:break
				await _ticks(1)
		_check("officer_physically_closes_to_visible6m_"+target.group,visible_arrival and arrival_travel>1.,{"visible_below6m":visible_arrival,"arriving_officer_displacement_m":arrival_travel,"displacement_origin":"actual pre-F officer position","initial_snapshot_clock_s":initial_clock})
		await _capture("arrival_"+target.group)
		# Continue through a real capture/release at the unrelocated assault
		# location before the next sector; no test officer positions change.
		for tick: int in range(2100):
			if not service.wanted and not service.detained:break
			await _ticks(1)
		_check("dispatch_finishes_without_stuck_ownership_"+target.group,not service.wanted and not service.detained)
	var legacy: CharacterBody3D=scene.pedestrians[0]
	var legacy_placed:=await _place_near(legacy,.88);await _ticks(24)
	var legacy_hits: int=service.hits;await _tap_f();await _ticks(20)
	scene.set_pedestrians_running(true);var legacy_start: Vector3=legacy.global_position;await _ticks(40);scene.set_pedestrians_running(false)
	_check("legacy_original_npc_hit_and_native_route_recovery",legacy_placed and service.hits==legacy_hits+1 and not preload("res://scripts/actor_hit_reaction.gd").owns(legacy) and legacy.get("_state")!="off_route" and legacy.global_position.distance_to(legacy_start)>.05,{"snapshot":legacy.snapshot(),"recovery_distance_m":legacy.global_position.distance_to(legacy_start)})
	# Actual W movement while wanted, then an elevated existing player test
	# fixture isolates the full60s timeout/catch guards without altering police.
	await _place_near(selected[0].body,.88);await _ticks(25)
	service.report_offense("검증: 실제 이동 추격",scene.player.global_position)
	var count_before: int=service.offense_count;var timer_before: float=service.chase_remaining_s
	scene.toggle_menu();await _ticks(30);_check("menu_pauses_actual60s_dispatch_clock",is_equal_approx(timer_before,service.chase_remaining_s));scene.toggle_menu();await _ticks(6)
	scene.rig.yaw+=PI;scene.rig.snap_to_target_pose()
	await _ticks(60)
	var moving_start: Vector3=scene.player.global_position;var police_start: float=service.actual_officer_distance_m
	Input.action_press("move_forward")
	await _ticks(90);Input.action_release("move_forward")
	_check("officers_continue_physical_pursuit_during_actual_w",scene.player.global_position.distance_to(moving_start)>.30 and service.actual_officer_distance_m>police_start,{"player_distance_m":scene.player.global_position.distance_to(moving_start),"police_distance_m":service.actual_officer_distance_m-police_start})
	service.report_offense("검증: 추가 신고",scene.player.global_position)
	_check("new_offense_resets_actual_chase_to60",service.offense_count==count_before+1 and is_equal_approx(service.chase_remaining_s,60.))
	var platform:=StaticBody3D.new();platform.name="TestOnlyTimeoutGroundGuardPlatform";platform.collision_layer=1;var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(4.,.2,4.);collider.shape=box;platform.add_child(collider);scene.add_child(platform);platform.global_position=scene.player.global_position+Vector3.UP*4.
	scene.player.global_position=platform.global_position+Vector3.UP*.12;scene.player.velocity=Vector3.ZERO;scene.player.reset_physics_interpolation();scene.rig.snap_to_target_pose()
	var clock_before: float=service._clock
	# A native rendered frame may contain multiple physics updates. Observe the
	# actual game clock instead of treating1790 awaited frames as59.666seconds.
	var timeout_observation_steps:=0
	while service._clock-clock_before<59.6 and timeout_observation_steps<2100:
		await _ticks(1)
		timeout_observation_steps+=1
	_check("pursuit_still_active_before60_real_game_seconds",service.wanted and service._clock-clock_before>=59.6 and service._clock-clock_before<60.,{"elapsed_game_s":service._clock-clock_before,"remaining_s":service.chase_remaining_s,"awaited_observation_steps":timeout_observation_steps,"sampling":"bounded actual game clock observation, no clock override"})
	await _ticks(35)
	_check("uncaught_officers_give_up_after60_and_return",not service.wanted and not service.detained and service._clock-clock_before>=60. and service.officers.all(func(row: Dictionary)->bool:return row.state in ["posted","returning"]),{"elapsed_game_s":service._clock-clock_before,"snapshot":service.snapshot()})
	_check("all_officer_steps_native_bounded",service.maximum_step_m<.30 and service.actual_officer_distance_m>15.,{"maximum_step_m":service.maximum_step_m,"distance_m":service.actual_officer_distance_m})
	scene.set_pedestrians_running(true)
	var route_start: Vector3=selected[0].body.global_position
	await _ticks(60)
	_check("original_victim_route_controller_resumes_physical_walking",selected[0].body.global_position.distance_to(route_start)>.05 and not preload("res://scripts/actor_hit_reaction.gd").owns(selected[0].body),{"distance_m":selected[0].body.global_position.distance_to(route_start)})
	var after: Array=[]
	for row: Dictionary in service._adult_candidates():after.append(row.body.get_instance_id())
	_check("all_original_adult_and_police_identities_retained",after==ids)
	platform.queue_free();_finish()
func _hashes() -> Dictionary:
	var result: Dictionary=super._hashes()
	for path: String in ["res://scripts/actor_hit_reaction.gd","res://scripts/street_pedestrians.gd","res://scripts/npc/pedestrian.gd","res://scripts/exploration_pedestrian_avoidance.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://scripts/player/human_combat_poses.gd","res://../tests/game/check_police_dispatch_response.gd"]:result[path]=FileAccess.get_sha256(path)
	for file: String in DirAccess.get_files_at("res://assets/original/seoul_resident"):
		if file.get_extension() in ["glb","png","json"]:result["res://assets/original/seoul_resident/"+file]=FileAccess.get_sha256("res://assets/original/seoul_resident/"+file)
	return result

func _finish() -> void:
	if finished:return
	finished=true;_check("source_inputs_stable_during_actual_run",_hashes()==source_hashes and not source_hashes.values().has(""),{"start":source_hashes,"end":_hashes()})
	var passed: int=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot write police dispatch report");quit(2);return
	file.store_string(JSON.stringify(_json({"task":"EXP33_POLICE_DISPATCH_RESPONSE","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"sectors":sectors,"captures":captures,"source_hashes":source_hashes,"snapshot":service.snapshot() if is_instance_valid(service) else {},"display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"elapsed_ms":Time.get_ticks_msec()-started,"scope":"Actual production city. Test-only supported player starts approach original stationary adults; ordinary people-pause setting is disclosed. Actual native knuckle contact starts police; all officers begin at real production posts and retain collision/physics. Three stationary assault sites, actual6m officer closure and bounded victim stagger/route restore; ordinary W pursuit, menu pause, refreshed offense and60 actual game seconds. Timeout alone uses an explicit raised test observer platform; no police/target teleport, clock override or disabled officer physics. Native images require separate pixel review; no OS input, universal route or realism claim."}),"  ")+"\n");file.close();print("POLICE_DISPATCH_RESULT ",passed,"/",checks.size())
	if is_instance_valid(scene):
		if is_instance_valid(scene.neighborhood_life.audio):scene.neighborhood_life.audio.stop();scene.neighborhood_life.audio.stream=null
		await physics_frame;await physics_frame;scene.queue_free();await process_frame;await process_frame
	quit(0 if passed==checks.size() else 1)
