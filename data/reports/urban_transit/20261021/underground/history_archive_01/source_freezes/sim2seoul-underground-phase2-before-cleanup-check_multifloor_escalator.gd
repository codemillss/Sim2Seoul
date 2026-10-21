extends "res://../tests/game/check_escalator_gym.gd"
## Actual SFC production controller carries 1F→4F→1F. The first landing is an
## explicit scenario start; all subsequent landings and transfers are walked.
var transfer_observations: Array=[]
var original_floor_count := 0

func _check(title: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":_json(evidence)})
	print("MULTIFLOOR_CHECK ","PASS " if passed else "FAIL ",title)

func _initialize() -> void:
	started_at=Time.get_datetime_string_from_system()
	_test_start_wall_usec=Time.get_ticks_usec()
	_test_start_process_frames=Engine.get_process_frames()
	_test_start_physics_frames=Engine.get_physics_frames()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	if report_path.is_empty() or not report_path.is_absolute_path():
		push_error("check_multifloor_escalator requires --report=<absolute path>");quit(1);return
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	if InputMap.has_action("interact"):InputMap.erase_action("interact")
	Engine.physics_ticks_per_second=60
	create_timer(COMPLETION_GUARD_SECONDS,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _geometry_all_pairs() -> void:
	var module: Node3D=visit.room.escalator
	var errors:=[];var samples:=0;var landings:=0
	for lower_level in range(module.pair_count):
		for lane in range(2):
			for index in range(25):
				var t:=float(index)/24.0
				var point: Vector3=visit.room.to_global(Vector3(module.lane_x(lane),(float(lower_level)+t)*float(module.rise)+.08,lerpf(float(module.lower_z),float(module.upper_z),t)))
				var hit:=_supported_at(point);samples+=1
				if not _capsule_at(point) or hit.is_empty() or hit.normal.y<.7:errors.append({"lower_level":lower_level,"lane":lane,"t":t,"point":point,"hit":hit.get("position",Vector3.INF)})
			for top in [false,true]:
				var landing: Vector3=module.endpoint(lane,top,1.05,lower_level);landings+=1
				if not _capsule_at(landing) or _supported_at(landing).is_empty():errors.append({"lower_level":lower_level,"lane":lane,"top":top,"landing":landing})
	_check("multifloor.all_six_native_supports_and_twelve_landings_clear_original_capsule",samples==150 and landings==12 and errors.is_empty(),{"samples":samples,"landings":landings,"errors":errors,"module":module.snapshot()})
	var openings:=[];var valid:=true
	for level in range(1,4):
		var hole: Rect2=module.opening_for_level(level)
		var mid: Vector3=visit.room.to_global(Vector3(module.lane_x(0),float(level)*float(module.rise)+.05,hole.get_center().y))
		var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(mid,mid-Vector3.UP*.25,1,[scene.player.get_rid()]))
		openings.append({"level":level,"hole":hole,"ray_from":mid,"hit":hit.get("position",Vector3.INF)})
		if hole.size.length_squared()<1.0 or not hit.is_empty():valid=false
	_check("multifloor.2F_3F_4F_actual_slab_openings",valid,{"openings":openings})
	var opposed: bool=module.supports.size()==6
	for pair in range(module.pair_count):
		var up: StaticBody3D=module.supports[pair*2];var down: StaticBody3D=module.supports[pair*2+1]
		if up.constant_linear_velocity.y<=0 or down.constant_linear_velocity.y>=0 or up.collision_layer!=1 or down.collision_layer!=1 or up.constant_linear_velocity!=-down.constant_linear_velocity:opposed=false
	_check("multifloor.three_independent_opposed_native_conveyor_pairs",opposed,{"module":module.snapshot()})
	var sign_texts:=[]
	for node in visit.room.get_children():
		if node is Label3D and node.has_meta("escalator_lower_level"):sign_texts.append(node.text)
	_check("multifloor.each_connected_pair_has_floor_number_direction_signs",sign_texts.size()==12 and "2층 → 3층  ↑" in sign_texts and "3층 → 4층  ↑" in sign_texts and "4층 → 3층  ↓" in sign_texts,{"sign_texts":sign_texts})
	var reservations:=[];var reservations_valid:=true
	for level in range(4):
		var zone: AABB=module.reservation_for_level(level);reservations.append({"level":level,"zone":zone})
		if absf(zone.position.y-(float(level)*float(module.rise)-.2))>.001 or zone.size.x<module.opening.size.x+1.5:reservations_valid=false
	_check("multifloor.floor_local_reservations_and_backwards_pair0_endpoint",reservations_valid and module.endpoint(0,false)==module.endpoint(0,false,1.05,0) and module.opening_for_level(0)==Rect2() and module.opening_for_level(4)==Rect2(),{"reservations":reservations})

func _ride_pair(lane: int,lower_level: int,place_start := false) -> bool:
	var module: Node3D=visit.room.escalator
	var ascending:=lane==0;var title:="%dF_%dF_%s"%[lower_level+1,lower_level+2,"up" if ascending else "down"]
	var start: Vector3=module.endpoint(lane,not ascending,1.05,lower_level)
	if place_start:
		if not await _pose("escalator_"+title+"_initial_landing",start):return false
	else:
		_check("multifloor."+title+".continuous_previous_walk_reaches_boarding_apron",scene.player.is_on_floor() and scene.player.global_position.distance_to(start)<.35,{"requested":start,"actual":scene.player.global_position})
	var initial_recoveries: int=scene.player.recoveries
	var boarded:=false
	for index in range(300):
		var local: Vector3=visit.room.to_local(scene.player.global_position)
		if (ascending and local.z<float(module.lower_z)-.32) or (not ascending and local.z>float(module.upper_z)+.32):boarded=true;break
		_world_keys(Vector3(0,0,-.30 if ascending else .30));await scene.player.physics_stepped
	_movement();await _ticks(3)
	_check("multifloor."+title+".walks_onto_native_ramp",boarded and scene.player.recoveries==initial_recoveries,{"start":start,"actual":scene.player.global_position})
	if not boarded:return false
	var tread_index: int=lower_level*int(module.steps.size()/module.pair_count)
	var rail_index: int=lower_level*int(module.rail_markers.size()/module.pair_count)
	var before: Vector3=scene.player.global_position;var tread_before: Transform3D=module.steps[tread_index].tread.transform
	var rail_before: Transform3D=module.rail_markers[rail_index].mesh.transform;var clock_before: float=module.elapsed
	scene.toggle_menu();await _ticks(20)
	_check("multifloor."+title+".menu_freezes_body_treads_handrails_and_clock",paused and scene.player.global_position==before and module.steps[tread_index].tread.transform==tread_before and module.rail_markers[rail_index].mesh.transform==rail_before and module.elapsed==clock_before,{"before":before,"after":scene.player.global_position,"clock_before":clock_before,"clock_after":module.elapsed})
	scene.toggle_menu();await _ticks(3)
	var trace:=[];var reached:=false;var max_step:=0.0;var prior: Vector3=scene.player.global_position
	var base:=float(lower_level)*float(module.rise)
	for index in range(1800):
		await scene.player.physics_stepped
		var now: Vector3=scene.player.global_position;max_step=maxf(max_step,now.distance_to(prior));prior=now
		var local: Vector3=visit.room.to_local(now)
		if index%60==0:trace.append({"tick":index,"position":now,"grounded":scene.player.is_on_floor(),"floor":visit.snapshot().current_floor})
		if (ascending and local.y>base+float(module.rise)-.12 and local.z<float(module.upper_z)+.08) or (not ascending and local.y<base+.14 and local.z>float(module.lower_z)-.08):reached=true;break
		if scene.player.recoveries!=initial_recoveries:break
	var end: Vector3=scene.player.global_position
	var evidence:={"lower_level":lower_level,"direction":"up" if ascending else "down","start":before,"end":end,"trace":trace,"maximum_body_step_m":max_step,"recoveries_before":initial_recoveries,"recoveries_after":scene.player.recoveries,"input_during_carry":"all movement actions released","capsule_after":_player_shape()}
	escalator_observations.append(evidence)
	_check("multifloor."+title+".neutral_original_player_is_carried_to_other_storey",reached and absf(end.y-before.y)>float(module.rise)*.8 and max_step<.12 and scene.player.recoveries==initial_recoveries,evidence)
	if not reached:return false
	var destination: Vector3=module.endpoint(lane,ascending,1.05,lower_level)
	for index in range(240):
		var offset: Vector3=destination-scene.player.global_position;offset.y=0
		if offset.length()<.12:break
		_world_keys(offset.normalized()*.65);await scene.player.physics_stepped
	_movement();await _ticks(8)
	var landed: bool=scene.player.is_on_floor() and absf(scene.player.global_position.y-destination.y)<.15 and Vector2(scene.player.global_position.x-destination.x,scene.player.global_position.z-destination.z).length()<.30 and _capsule_at(scene.player.global_position+Vector3.UP*.006)
	_check("multifloor."+title+".walks_off_to_clear_supported_apron",landed,{"destination":destination,"actual":scene.player.global_position,"current_floor":visit.snapshot().current_floor})
	return landed

func _transfer(level: int,ascending: bool) -> bool:
	var module: Node3D=visit.room.escalator;var lane:=0 if ascending else 1
	var side_x: float=module.opening.position.x-.72 if ascending else module.opening.end.x+.72
	var start_z: float=module.upper_z-1.05 if ascending else module.lower_z+1.05
	var end_z: float=module.lower_z+1.05 if ascending else module.upper_z-1.05
	var y:=float(level)*float(module.rise)+.08
	var path: Array[Vector3]=[visit.room.to_global(Vector3(side_x,y,start_z)),visit.room.to_global(Vector3(side_x,y,end_z)),visit.room.to_global(Vector3(module.lane_x(lane),y,end_z))]
	var start: Vector3=scene.player.global_position
	var passed:=await _walk_path("multifloor.%dF.walk_around_opening_to_next_%s_pair"%[level+1,"up" if ascending else "down"],path)
	transfer_observations.append({"level":level,"ascending":ascending,"start":start,"end":scene.player.global_position,"path":path,"passed":passed})
	return passed

func _run() -> void:
	for path in ["res://scripts/interior_escalator.gd","res://scripts/building_interior_space.gd","res://scripts/interior_visit.gd","res://scripts/player/free_roam_player.gd","res://../tests/game/check_multifloor_escalator.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json";root.add_child(scene)
	if not scene.runtime_ok:_check("startup",false);_finish();return
	visit=scene.interior_visit;await _ticks(25);activity=visit.facility_interaction
	original_inventory=_inventory();player_shape_before=_player_shape()
	if await _enter(OFFICE_ID,"multifloor_escalator"):
		original_floor_count=visit.room.floor_count
		_check("multifloor.original_SFC_plate_and_28_storeys_with_three_pairs",is_instance_valid(visit.room.escalator) and visit.room.floor_count==28 and visit.room.escalator.pair_count==3 and visit.room.escalator.connecting_levels==[0,1,2,3],{"spec":visit.current_spec,"floor_count":visit.room.floor_count})
		if is_instance_valid(visit.room.escalator):
			_geometry_all_pairs()
			var complete:=true
			for lower_level in range(3):
				if not await _ride_pair(0,lower_level,lower_level==0):complete=false;break
				if lower_level<2 and not await _transfer(lower_level+1,true):complete=false;break
			if complete:
				var down_top: Vector3=visit.room.escalator.endpoint(1,true,1.05,2)
				complete=await _walk_path("multifloor.4F.walk_between_up_and_down_aprons",[down_top])
			if complete:
				for lower_level in range(2,-1,-1):
					if not await _ride_pair(1,lower_level):complete=false;break
					if lower_level>0 and not await _transfer(lower_level,false):complete=false;break
			_check("multifloor.production_controller_completes_1F_to_4F_to_1F_without_midroute_teleports",complete and escalator_observations.size()==6 and transfer_observations.size()==4 and visit.room.floor_index_at(scene.player.global_position)==0,{"rides":escalator_observations.size(),"transfers":transfer_observations.size(),"position":scene.player.global_position,"scenario_starts":placements})
			# The original independent U-stair network must retain its solid support.
			var stair_errors:=[];var stair_samples:=0
			for level in range(3):
				for point: Vector3 in visit.room.stair_path(level,true):
					stair_samples+=1
					if not _capsule_at(point) or _supported_at(point).is_empty():stair_errors.append({"level":level,"point":point})
			_check("multifloor.original_U_stairs_have_unchanged_walkable_support_and_headroom",stair_samples>50 and stair_errors.is_empty(),{"samples":stair_samples,"errors":stair_errors})
		visit.return_to_world_spawn();await _ticks(8)
	_check("regression.source_geometry_original_capsule_and_cleanup",_inventory()==original_inventory and _player_shape()==player_shape_before and not scene.player.facility_control and not scene.player.interior_active and scene.player.is_physics_processing(),{"source_body_count":original_inventory.size(),"capsule":_player_shape()})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var end_hashes: Dictionary={};var changed_sources: Array=[]
	for path: String in source_hashes:
		end_hashes[path]=FileAccess.get_sha256(path)
		if end_hashes[path]!=source_hashes[path]:changed_sources.append(path)
	_check("regression.loaded_sources_match_end_of_run",changed_sources.is_empty(),{"changed_sources":changed_sources,"source_sha256_at_finish":end_hashes})
	var failed:=0
	for check in checks:
		if not check.passed:failed+=1
	var report:={"task":"multifloor_escalator","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"source_sha256_at_finish":end_hashes,"checks":checks,"summary":{"checks":checks.size(),"failed":failed},"completion_guard":{"seconds":COMPLETION_GUARD_SECONDS,"wall_elapsed_seconds":float(Time.get_ticks_usec()-_test_start_wall_usec)/1000000.0,"physics_frames":Engine.get_physics_frames()-_test_start_physics_frames},"scenario_starts":placements,"walks":walks,"escalator_observations":escalator_observations,"transfers":transfer_observations,"scope":"Original source-sized 28-storey SFC: authored 1F↔2F, 2F↔3F, 3F↔4F pairs. Original production capsule, source collision inventory, actual smooth conveyor supports and moving visual treads/handrails; one initial landing fixture, production controller walk/neutral physical carry completes all six legs with intermediate floor transfers. Menu pause and existing U-stair geometry retained. Synthetic Input.action_press and parsed production E events; not human OS input, surveyed real interior, rendered visual acceptance or performance acceptance."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(report),"\t")+"\n");file.close()
	else:failed+=1
	print("MULTIFLOOR_ESCALATOR_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)
