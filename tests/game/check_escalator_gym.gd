extends "res://../tests/game/check_facility_interactions.gd"
## EXP16: existing production input/controller and real conveyor collision.
## Starts are explicit scenario fixtures; no body position writes during rides.
const COMPLETION_GUARD_SECONDS := 600.0
var escalator_observations: Array=[]
var _test_start_wall_usec: int=0
var _test_start_process_frames: int=0
var _test_start_physics_frames: int=0

func _initialize() -> void:
	# This longer combined suite retains every functional threshold. The timer
	# only bounds completion; its elapsed seconds are not an FPS/performance gate.
	started_at=Time.get_datetime_string_from_system()
	_test_start_wall_usec=Time.get_ticks_usec()
	_test_start_process_frames=Engine.get_process_frames()
	_test_start_physics_frames=Engine.get_physics_frames()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	if report_path.is_empty() or not report_path.is_absolute_path():
		push_error("check_escalator_gym requires --report=<absolute path>");quit(1);return
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	if InputMap.has_action("interact"):InputMap.erase_action("interact")
	Engine.physics_ticks_per_second=60
	create_timer(COMPLETION_GUARD_SECONDS,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _actual_roles(kind: String,observation: Dictionary) -> bool:
	if kind not in ["cycle","rowing"]:return super._actual_roles(kind,observation)
	var required: Array=["cycle_crank","cycle_pedal","cycle_flywheel_motion"] if kind=="cycle" else ["rowing_sliding_seat","rowing_handle","rowing_cable"]
	for role in required:
		if int(observation.roles.get(role,0))==0:return false
	return observation.visible_mesh_count>0 and observation.solid_count==0

func _capsule_at(point: Vector3) -> bool:
	var shape_node: CollisionShape3D=scene.player.get_node("CollisionShape")
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape_node.shape
	query.transform=Transform3D(Basis.IDENTITY,point)*shape_node.transform
	query.collision_mask=scene.player.collision_mask;query.exclude=[scene.player.get_rid()]
	return scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _supported_at(point: Vector3) -> Dictionary:
	return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.13,point-Vector3.UP*.45,1,[scene.player.get_rid()]))

func _escalator_geometry() -> void:
	var module: Node3D=visit.room.escalator
	var snapshot: Dictionary=module.snapshot();var errors:=[];var samples:=0
	for lane in range(2):
		for index in range(25):
			var t:=float(index)/24.0
			var point: Vector3=visit.room.to_global(Vector3(module.lane_x(lane),float(module.rise)*t+.08,lerpf(float(module.lower_z),float(module.upper_z),t)))
			var hit:=_supported_at(point);samples+=1
			if not _capsule_at(point) or hit.is_empty() or hit.normal.y<.7:errors.append({"lane":lane,"t":t,"point":point,"hit":hit.get("position",Vector3.INF)})
		for top in [false,true]:
			var landing: Vector3=module.endpoint(lane,top)
			if not _capsule_at(landing) or _supported_at(landing).is_empty():errors.append({"lane":lane,"top":top,"landing":landing})
	_check("escalator.actual_continuous_capsule_and_supported_landings",samples==50 and errors.is_empty(),{"samples":samples,"errors":errors,"module":snapshot})
	var opening: Rect2=module.opening
	var mid: Vector3=visit.room.to_global(Vector3(module.lane_x(0),float(module.rise)+.05,opening.get_center().y))
	var ray:=PhysicsRayQueryParameters3D.create(mid,mid-Vector3.UP*.25,1,[scene.player.get_rid()])
	_check("escalator.upper_slab_is_physically_open",scene.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),{"ray_from":mid,"ray_to":mid-Vector3.UP*.25})
	_check("escalator.two_actual_opposed_conveyor_bodies",module.supports.size()==2 and module.supports[0].constant_linear_velocity.y>0 and module.supports[1].constant_linear_velocity.y<0 and module.supports[0].collision_layer==1 and module.supports[1].collision_layer==1,{"snapshot":snapshot})

func _escalator_ride(lane: int) -> void:
	var module: Node3D=visit.room.escalator
	var ascending:=lane==0;var title:="up" if ascending else "down"
	var start: Vector3=module.endpoint(lane,not ascending)
	if not await _pose("escalator_"+title+"_landing",start):return
	if DisplayServer.get_name()!="headless":
		scene.rig.yaw=-.32 if ascending else PI+.25;scene.rig.pitch=deg_to_rad(-13.0);scene.rig.requested_distance=5.0;scene.rig.snap_to_target_pose()
		await _ticks(5);await _capture("commercial_escalator_"+title+"_landing")
	var initial_recoveries: int=scene.player.recoveries
	var boarded:=false
	for index in range(300):
		var local: Vector3=visit.room.to_local(scene.player.global_position)
		if (ascending and local.z<float(module.lower_z)-.32) or (not ascending and local.z>float(module.upper_z)+.32):boarded=true;break
		_world_keys(Vector3(0,0,-.30 if ascending else .30));await scene.player.physics_stepped
	_movement();await _ticks(3)
	_check("escalator."+title+".walks_onto_actual_ramp",boarded and scene.player.recoveries==initial_recoveries,{"start":start,"boarded_position":scene.player.global_position})
	if not boarded:return
	var before: Vector3=scene.player.global_position;var visuals_before: Transform3D=module.steps[0].tread.transform;var clock_before: float=module.elapsed
	scene.toggle_menu();await _ticks(24)
	_check("escalator."+title+".menu_freezes_body_steps_and_clock",paused and scene.player.global_position==before and module.steps[0].tread.transform==visuals_before and module.elapsed==clock_before,{"before":before,"after":scene.player.global_position,"time_before":clock_before,"time_after":module.elapsed})
	scene.toggle_menu();await _ticks(3)
	var trace:=[];var reached:=false;var max_step:=0.0;var prior: Vector3=scene.player.global_position
	for index in range(1800):
		await scene.player.physics_stepped
		var now: Vector3=scene.player.global_position
		max_step=maxf(max_step,now.distance_to(prior));prior=now
		var local: Vector3=visit.room.to_local(now)
		if index%60==0:trace.append({"tick":index,"position":now,"grounded":scene.player.is_on_floor()})
		if (ascending and local.y>float(module.rise)-.12 and local.z<float(module.upper_z)+.08) or (not ascending and local.y<.14 and local.z>float(module.lower_z)-.08):reached=true;break
		if scene.player.recoveries!=initial_recoveries:break
	var end: Vector3=scene.player.global_position
	var evidence:={"direction":title,"start":before,"end":end,"trace":trace,"maximum_body_step_m":max_step,"recoveries_before":initial_recoveries,"recoveries_after":scene.player.recoveries,"input_during_carry":"all movement actions released","capsule_after":_player_shape()}
	escalator_observations.append(evidence)
	_check("escalator."+title+".neutral_passenger_is_physically_carried_between_floors",reached and absf(end.y-before.y)>float(module.rise)*.8 and max_step<.12 and scene.player.recoveries==initial_recoveries,evidence)
	# Walk from the conveyor onto a known supported apron using production input.
	var destination: Vector3=module.endpoint(lane,ascending)
	for index in range(240):
		var offset: Vector3=destination-scene.player.global_position;offset.y=0
		if offset.length()<.12:break
		_world_keys(offset.normalized()*.65);await scene.player.physics_stepped
	_movement();await _ticks(8)
	_check("escalator."+title+".safe_floor_dismount_releases_carrier",scene.player.is_on_floor() and absf(scene.player.global_position.y-destination.y)<.15 and Vector2(scene.player.global_position.x-destination.x,scene.player.global_position.z-destination.z).length()<.30 and _capsule_at(scene.player.global_position+Vector3.UP*.006),{"destination":destination,"actual":scene.player.global_position,"current_floor":visit.snapshot().current_floor})

func _new_station(target: Dictionary) -> void:
	var kind:=String(target.kind);var title:="new_"+kind
	if not await _begin(target,title):return
	var before:=_state();var original: Vector3=scene.player.global_position
	await _observe_animation(kind,title)
	await _held_control_check(title)
	await _pause_action(title)
	var avatar_before: Dictionary=scene.exploration_avatar.snapshot()
	await _ticks(110)
	var avatar_after: Dictionary=scene.exploration_avatar.snapshot();var after:=_state()
	var stats: bool=float(after.cycling_distance_m)>float(before.cycling_distance_m) and int(after.cycling_revolutions)>int(before.cycling_revolutions) if kind=="cycle" else float(after.rowing_distance_m)>float(before.rowing_distance_m) and int(after.rowing_strokes)>int(before.rowing_strokes)
	_check("gym."+kind+".seated_joints_move_and_distinct_work_accumulates",stats and avatar_after.activity_kind==kind and avatar_before.joint_transforms!=avatar_after.joint_transforms and scene.player.global_position.distance_to(original)<.001,{"before":before,"after":after,"avatar_before":avatar_before,"avatar_after":avatar_after})
	await _capture_activity(title+"_in_use",target)
	await _capture_activity(title+"_small",target,true)
	# A real blocker at the saved standing marker must prevent a dismount.
	var return_point: Vector3=after.return_position
	# The body began exactly at its clear use marker in this fixture. Move the
	# original return marker fixture by starting from the approach in a new test
	# below; never block the live seated capsule itself.
	await _cancel_by_E(title)
	_check("gym."+kind+".safe_dismount_preserves_stats_and_original_capsule",_player_shape()==player_shape_before and not scene.player.facility_control and _state().cycling_distance_m>=after.cycling_distance_m and _state().rowing_strokes>=after.rowing_strokes,{"state":_state(),"return_point":return_point})

func _blocked_station_exit(target: Dictionary) -> void:
	# Enter from 0.7m behind the seat, making a distinct return position. The
	# normal short floor corridor is validated before production E mounts it.
	var point: Vector3=visit.room.to_global(target.approach_point)
	if not await _pose("cycle_distinct_return_marker",point):return
	_e(true);_e(false);await _ticks(5)
	_check("gym.cycle.approach_E_mounts_validated_short_clear_segment",_state().active and _state().kind=="cycle" and scene.player.global_position.distance_to(point)>.5,{"state":_state()})
	if not _state().active:return
	await _ticks(45)
	var blocker:=StaticBody3D.new();blocker.name="ExplicitGymDismountBlocker";blocker.collision_layer=1;blocker.collision_mask=0
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(.40,1.7,.30);collision.shape=box;blocker.add_child(collision);scene.add_child(blocker);blocker.global_position=point+Vector3.UP*.85
	await _ticks(3);_e(true);_e(false);await _ticks(6)
	var blocked:=_state();await _ticks(15)
	_check("gym.cycle.blocked_return_retains_safe_seat_and_freezes_work",blocked.active and blocked.return_pending and _state().elapsed==blocked.elapsed and _state().cycling_distance_m==blocked.cycling_distance_m and scene.player.global_position.distance_to(blocked.use_position)<.001,{"blocked":blocked,"after_wait":_state()})
	blocker.queue_free();await _ticks(4);_e(true);_e(false);await _ticks(8)
	_check("gym.cycle.fresh_E_retries_clear_return_and_restores_control",not _state().active and not scene.player.facility_control and scene.player.global_position.distance_to(point)<.10,{"state":_state(),"original_return":point,"actual":scene.player.global_position})

func _run() -> void:
	for path in ["res://scripts/interior_escalator.gd","res://scripts/building_interior_space.gd","res://scripts/interior_visit.gd","res://scripts/interior_facility_kit.gd","res://scripts/facility_interaction.gd","res://scripts/facility_activity_visuals.gd","res://scripts/player/exploration_avatar.gd","res://../tests/game/check_escalator_gym.gd","res://../tests/game/check_facility_interactions.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json";root.add_child(scene)
	if not scene.runtime_ok:_check("startup",false);_finish();return
	visit=scene.interior_visit;await _ticks(25);activity=visit.facility_interaction
	original_inventory=_inventory();player_shape_before=_player_shape()
	if await _enter(OFFICE_ID,"commercial_escalator"):
		_check("escalator.identifiable_single_large_commercial_building",is_instance_valid(visit.room.escalator) and visit.current_spec.title=="서울파이낸스센터",{"id":visit.current_spec.id,"width":visit.room.width,"depth":visit.room.depth,"floor_count":visit.room.floor_count})
		if is_instance_valid(visit.room.escalator):
			_escalator_geometry();await _escalator_ride(0);await _escalator_ride(1)
		visit.return_to_world_spawn();await _ticks(8)
	if await _enter(HOTEL_ID,"gym_variety"):
		_check("gym.original_hotel_has_no_unrequested_escalator",not is_instance_valid(visit.room.escalator))
		var cycle:=_target("cycle",3);var rowing:=_target("rowing",3);var treadmill:=_target("treadmill",3);var weights:=_target("weights",3)
		_check("gym.two_new_and_two_retained_actual_targets",not cycle.is_empty() and not rowing.is_empty() and not treadmill.is_empty() and not weights.is_empty(),{"cycle":cycle,"rowing":rowing,"treadmill":treadmill,"weights":weights})
		if await _ride_to(3,"gym_variety"):
			if not cycle.is_empty():await _new_station(cycle);await _blocked_station_exit(cycle)
			if not rowing.is_empty():await _new_station(rowing)
			if not treadmill.is_empty():await _exercise(treadmill)
			if not weights.is_empty():await _exercise(weights)
		visit.return_to_world_spawn();await _ticks(8)
	_check("regression.source_collision_capsule_and_cleanup",_inventory()==original_inventory and _player_shape()==player_shape_before and not scene.player.facility_control and not _state().active and not scene.player.interior_active,{"body_count":original_inventory.size(),"capsule":_player_shape(),"state":_state()})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var failed:=0
	for check in checks:
		if not check.passed:failed+=1
	var report:={"task":"escalator_gym","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"checks":checks,"summary":{"checks":checks.size(),"failed":failed},"completion_guard":{"timer_seconds":COMPLETION_GUARD_SECONDS,"wall_elapsed_seconds":float(Time.get_ticks_usec()-_test_start_wall_usec)/1000000.0,"process_frames":Engine.get_process_frames()-_test_start_process_frames,"physics_frames":Engine.get_physics_frames()-_test_start_physics_frames,"scope":"Completion guard only; timer/wall/frame observations do not establish an FPS or performance acceptance criterion."},"scenario_starts":placements,"walks":walks,"escalator_observations":escalator_observations,"activity_observations":activity_observations,"captures":captures,"capture_progress":capture_progress,"capture_stage_trace":capture_stage_trace,"deferred_checks":deferred_checks,"scope":"One authored SFC 1F↔2F physical conveyor pair and representative hotel4F gym. Recorded test starts, actual production movement and E, no body writes during carry. Geometry/ramp support, neutral passenger ascent/descent, pause, landing/dismount, new station distinct meshes and seated joint motion, per-kind progress, blocked return/retry, original treadmill/dumbbell regression and unchanged capsule/exterior inventory. Native screenshots only when renderer is available. The completion guard is separate from functional thresholds; neither timeout nor PASS is an FPS/performance acceptance. Not a surveyed real building layout, all-room action audit or human feel acceptance."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(report),"\t")+"\n");file.close()
	else:failed+=1
	print("ESCALATOR_GYM_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)
