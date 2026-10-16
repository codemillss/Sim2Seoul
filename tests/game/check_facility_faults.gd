extends "res://../tests/game/check_facility_interactions.gd"
func _run() -> void:
	for path in ["res://scripts/facility_interaction.gd","res://scripts/facility_activity_visuals.gd","res://scripts/interior_visit.gd","res://scripts/player/free_roam_player.gd","res://scripts/interior_facility_kit.gd","res://assets/authored/interiors/source_catalog.json","res://../tests/game/check_building_visits.gd","res://../tests/game/check_facility_interactions.gd","res://../tests/game/check_facility_faults.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json"
	root.add_child(scene)
	if not scene.runtime_ok:_check("fault.startup",false);_finish();return
	visit=scene.interior_visit;await _ticks(25);activity=visit.facility_interaction
	original_inventory=_inventory();player_shape_before=_player_shape()
	if not await _enter(HOTEL_ID,"fault_hotel"):_finish();return
	var target:=_target("treadmill",3)
	if target.is_empty() or not await _ride_to(3,"fault_gym"):_finish();return
	if not await _walk_to_target(target,"fault_gym"):_finish();return
	_e(true);_e(false);await _ticks(5)
	_check("fault.physical_E_starts",_state().active and scene.player.facility_control)
	if not _state().active:_finish();return
	var before:=_state();var mounted: Vector3=scene.player.global_position
	var obstacle:=StaticBody3D.new();obstacle.name="ExplicitBlockedGymReturnFixture";obstacle.collision_layer=1;obstacle.collision_mask=0
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(.72,1.75,.30);collision.shape=box;obstacle.add_child(collision);scene.add_child(obstacle)
	obstacle.global_position=before.return_position+Vector3.UP*.85
	await _ticks(4);_e(true);_e(false);await _ticks(5)
	var blocked:=_state()
	_check("fault.blocked_return_retains_safe_mount_and_control",blocked.active and blocked.return_pending and scene.player.facility_control and scene.player.global_position.distance_to(mounted)<.001,{"before":before,"blocked":blocked,"mounted":mounted,"player":scene.player.global_position})
	var elapsed: float=blocked.elapsed;var work: float=blocked.workout_distance_m
	await _ticks(20)
	_check("fault.blocked_return_does_not_keep_earning_work_or_time",_state().elapsed==elapsed and _state().workout_distance_m==work)
	obstacle.queue_free();await _ticks(4)
	_e(true);_e(false);await _ticks(6)
	_check("fault.clear_return_then_E_releases_safely",not _state().active and not scene.player.facility_control and scene.player.global_position.distance_to(before.return_position)<.025 and _mesh_observation().mesh_count==0,{"state":_state(),"player":scene.player.global_position,"return":before.return_position})
	_movement();await _ticks(6)
	if not await _walk_to_target(target,"fault_external"):_finish();return
	_e(true);_e(false);await _ticks(5)
	_check("fault.second_physical_E_starts",_state().active)
	var cleanup_before: int=int(_state().external_cleanup_count)
	var destination: Vector3=visit.room.floor_spawn(3)
	var accepted: bool=scene.player.relocate_interior(destination)
	await _ticks(8)
	_check("fault.successful_external_relocation_cleans_without_teleport_back",accepted and not _state().active and not scene.player.facility_control and int(_state().external_cleanup_count)==cleanup_before+1 and scene.player.global_position.distance_to(destination)<.10 and _mesh_observation().mesh_count==0,{"accepted":accepted,"state":_state(),"requested":destination,"player":scene.player.global_position})
	_check("fault.original_collision_and_capsule_retained",_inventory()==original_inventory and _player_shape()==player_shape_before)
	visit.return_to_world_spawn();await _ticks(5)
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var failed:=0
	for check in checks:
		if not check.passed:failed+=1
	var report:={"task":"facility_faults","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"started_at_local":started_at,"finished_at_local":Time.get_datetime_string_from_system(),"source_sha256":source_hashes,"checks":checks,"summary":{"checks":checks.size(),"failed":failed},"scenario_starts":placements,"walks":walks,"final_state":_state() if is_instance_valid(activity) else {},"scope":"Independent hotel treadmill fault scenarios only. Production physical E starts both sessions and requests stop. A recorded temporary collision fixture blocks the original dismount point; the existing capsule stays at the safe mounted position, activity time and earned work freeze, then physical E retries after fixture removal and safely returns. A second live session is externally moved using the production successful relocate_interior API; the activity releases control and removes effects without teleporting back. Existing outdoor collision inventory and player capsule remain intact. This is headless fault-path verification, not all four facility activities, native rendering, a full catalog action audit, or human OS input acceptance."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(report),"\t")+"\n");file.close()
	else:failed+=1;push_error("Could not save facility faults report")
	print("FACILITY_FAULTS_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)
