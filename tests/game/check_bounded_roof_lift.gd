extends "res://../tests/game/check_large_outdoor_pool.gd"
## Free-roam OFF must retain a working bounded roof/lift/water transaction.
## Turning it ON while on that roof must release the exterior restriction.

func _request_from_landing(index: int, title: String) -> bool:
	_movement();_e(false);await _ticks(4)
	var point: Vector3=roof.lift_point() if visit.on_roof else visit.room.elevator_point(0)
	if not await _pose(title+"_supported_lift_start",point):return false
	_e(true);_e(false);await _ticks(4)
	var accepted: bool=visit.request_floor(index)
	_check(title+".request_accepted",accepted,{"requested_floor":index,"free_roam":scene.player.free_roam_enabled,"interior_active":scene.player.interior_active,"elevator":visit.elevator_snapshot()})
	if not accepted:return false
	var water_cleared: bool=not scene.player.water_snapshot().registered
	_check(title+".boarding_clears_water",water_cleared,scene.player.water_snapshot())
	var completed: bool=await _wait_elevator_end(2400)
	_movement();_e(false);await _ticks(12)
	_check(title+".arrives_and_finishes_cabin_instead_of_blocked_loop",completed and not visit.in_elevator and visit.selected_floor==index and scene.player.is_on_floor() and String(visit.elevator_snapshot().phase)=="idle",{"selected_floor":visit.selected_floor,"on_roof":visit.on_roof,"interior_active":scene.player.interior_active,"player":scene.player.global_position,"elevator":visit.elevator_snapshot()})
	return completed and not visit.in_elevator and visit.selected_floor==index

func _run() -> void:
	for path: String in ["res://scripts/rooftop_space.gd","res://scripts/exploration_rooftop_access.gd","res://scripts/player/free_roam_player.gd","res://scripts/interior_visit.gd","res://scripts/explore_walk.gd","res://../tests/game/check_bounded_roof_lift.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json";root.add_child(scene)
	if not scene.runtime_ok:_check("startup",false);_finish();return
	visit=scene.interior_visit;await _ticks(25);original_inventory=_inventory()
	scene.set_free_roam(true);scene.set_speed_profile("brisk");_movement();await _ticks(4)
	if not await _enter(HOTEL_ID,"bounded_pool_hotel"):_finish();return
	roof=visit.rooftop
	var roof_index: int=int(visit.current_spec.floor_count)
	# Change the setting through the production scene API while inside. Its
	# public walking boundary cannot contain this high source roof in Y.
	scene.set_free_roam(false);_movement();await _ticks(4)
	_check("bounded_roof.walking_boundary_really_disabled_free_roam",not scene.free_roam_enabled and not scene.player.free_roam_enabled and scene.player.interior_active)
	if not await _request_from_landing(roof_index,"bounded_roof.first_ascent"):_finish();return
	_check("bounded_roof.arrival_retains_valid_roof_region_and_water",visit.on_roof and scene.player.interior_active and scene.player.interior_ceiling_unbounded and scene.player.interior_frame.is_equal_approx(roof.frame) and scene.player.water_snapshot().registered and not scene.player.free_roam_enabled,{"water":scene.player.water_snapshot(),"player":scene.player.global_position,"roof_frame":roof.frame,"interior_frame":scene.player.interior_frame})
	_observe_raised_basin()
	if await _jump_into_pool():
		await _swim_to("bounded_roof.actual_swim_to_pool_center",roof.pool_float_point())
		_movement();await _ticks(90)
		_check("bounded_roof.real_buoyancy_stays_inside_bounded_roof",scene.player.is_swimming() and scene.player.interior_active and scene.player.water_snapshot().registered and not scene.player.free_roam_enabled,scene.player.water_snapshot())
		await _exit_water()
	if not await _request_from_landing(0,"bounded_roof.descent_with_free_roam_still_off"):_finish();return
	_check("bounded_roof.indoor_arrival_keeps_mode_and_dry_state",not visit.on_roof and scene.player.interior_active and not scene.player.free_roam_enabled and not scene.player.water_snapshot().registered,{"player":scene.player.global_position,"elevator":visit.elevator_snapshot(),"water":scene.player.water_snapshot()})
	if not await _request_from_landing(roof_index,"bounded_roof.second_ascent"):_finish();return
	var before: Transform3D=scene.player.global_transform
	var recoveries: int=scene.player.recoveries
	scene.set_free_roam(true);_movement();await _ticks(6)
	_check("bounded_roof.enabling_free_roam_releases_region_preserving_pose",visit.active and visit.on_roof and not scene.player.interior_active and scene.player.free_roam_enabled and scene.player.global_position.distance_to(before.origin)<.05 and scene.player.recoveries==recoveries,{"before":before,"after":scene.player.global_transform,"recoveries":scene.player.recoveries-recoveries,"water":scene.player.water_snapshot()})
	_check("bounded_roof.enabling_free_roam_registers_outdoor_pool_water",scene.player.water_snapshot().registered and not scene.player.interior_active and String(scene.player.water_snapshot().id)==String(roof.pool_water_region().id),scene.player.water_snapshot())
	var released_pose: Transform3D=scene.player.global_transform
	var released_recoveries: int=scene.player.recoveries
	scene.set_free_roam(false);_movement();await _ticks(4)
	_check("bounded_roof.exterior_roof_OFF_is_rejected_with_pose_and_ON_switch_preserved",scene.free_roam_enabled and scene.player.free_roam_enabled and scene.free_roam_switch.button_pressed and not scene.player.interior_active and scene.player.global_position.distance_to(released_pose.origin)<.05 and scene.player.recoveries==released_recoveries and not scene.exploration_notice.text.is_empty(),{"before":released_pose,"after":scene.player.global_transform,"free_roam":scene.free_roam_enabled,"player_free_roam":scene.player.free_roam_enabled,"switch_pressed":scene.free_roam_switch.button_pressed,"notice":scene.exploration_notice.text,"recoveries":scene.player.recoveries-released_recoveries,"water":scene.player.water_snapshot()})
	if not await _request_from_landing(0,"bounded_roof.outdoor_roof_reboards_and_returns"):_finish();return
	_check("bounded_roof.outdoor_return_to_indoor_is_valid_and_dry",scene.player.interior_active and not visit.on_roof and not scene.player.water_snapshot().registered)
	await _leave("bounded_pool_hotel")
	_check("bounded_roof.street_restores_original_world",not visit.active and not scene.player.interior_active and _inventory()==original_inventory,{"original_source_bodies":original_inventory.size()})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var failed: int=0
	for check: Dictionary in checks:
		if not check.passed:failed+=1
	var result: Dictionary={"task":"BOUNDED_ROOF_LIFT_WATER_AND_MODE_TRANSITION","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"basin":basin_observation,"trials":swim_trials,"walks":walks,"placements":placements,"captures":captures,"deferred_checks":deferred_checks,"scope":"The same real-source hotel roof is reached twice by the production elevator with free roaming disabled. Its bounded roof, real pool entry/swim/Space exit and return lift are observed. Free roaming is then enabled on the second roof arrival, with pose-preserving outdoor release, outdoor water registration and a final lift return. Fixtures are explicitly labelled. Not human usability/performance/export acceptance."}
	var file: FileAccess=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(result),"\t")+"\n");file.close()
	else:failed+=1;push_error("Cannot save bounded rooftop report")
	print("BOUNDED_ROOF_LIFT_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)
