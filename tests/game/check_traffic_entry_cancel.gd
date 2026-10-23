extends "res://../tests/game/check_traffic_car_takeover.gd"
## Focused transaction rollback at the new timed entry ownership boundary.
## Reuses source-supported player observer fixtures and physical E, never moves
## an original car. Real W approach is separately covered by action-freedom QA.
func _hashes() -> Dictionary:
	var result: Dictionary=super._hashes();result["res://../tests/game/check_traffic_entry_cancel.gd"]=FileAccess.get_sha256("res://../tests/game/check_traffic_entry_cancel.gd");return result
func _reach_entry() -> CharacterBody3D:
	var car:=await _moving_observer(1.2)
	if not is_instance_valid(car):return null
	await _tap_e()
	for tick: int in range(240):
		if not is_instance_valid(service.pending_car):return null
		if service.pending_stage=="player_enter":return car
		if service.pending_stage=="approach" and service._door_distance_for(car)>1.1:await _observer(car)
		elif service._door_distance_for(car)>2.3:await _observer(car)
		await _ticks(1)
	return null
func _run() -> void:
	hashes=_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/traffic-entry-cancel-test-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8)
	service=scene.get("traffic_car_takeover");_check("production_original_car_service_ready",scene.runtime_ok and is_instance_valid(service) and service.loaded)
	if not scene.runtime_ok or not is_instance_valid(service) or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	scene.player.free_roam_enabled=true;await _ticks(4)
	var shape_id: int=scene.player.get_node("CollisionShape").shape.get_instance_id();var original_mask: int=scene.player.collision_mask;var original_layer: int=scene.player.collision_layer
	var car:=await _reach_entry()
	_check("physical_E_reaches_timed_player_entry_before_adoption",is_instance_valid(car) and service.pending_stage=="player_enter" and service.bikes.is_empty(),{"snapshot":service.snapshot()})
	if not is_instance_valid(car):_finish();return
	_check("entry_owns_controls_but_retains_capsule_physics_and_AI_reservation",service._entry_owned_control and scene.player.facility_control and scene.player.is_physics_processing() and car._manager.vehicles.has(car) and not car.is_physics_processing() and service.drivers.size()==1 and scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id)
	var elapsed: float=service.pending_elapsed_s;var stage_elapsed: float=service.pending_stage_elapsed_s;var position: Vector3=scene.player.global_position;scene.toggle_menu()
	for tick: int in range(6):await process_frame
	_check("menu_pauses_timed_entry_and_provisional_driver",is_equal_approx(service.pending_elapsed_s,elapsed) and is_equal_approx(service.pending_stage_elapsed_s,stage_elapsed) and scene.player.global_position.distance_to(position)<.0001)
	scene.toggle_menu();await _tap_e();await _ticks(6)
	_check("fresh_E_rolls_back_entry_and_releases_only_owned_control",not service.riding and not is_instance_valid(service.pending_car) and service.pending_stage.is_empty() and not service._entry_owned_control and not scene.player.facility_control and scene.player.is_physics_processing())
	_check("entry_cancel_restores_same_AI_and_removes_provisional_driver",car.is_physics_processing() and car._running and car._manager.vehicles.has(car) and service.drivers.is_empty() and service.bikes.is_empty(),{"snapshot":service.snapshot()})
	_check("entry_cancel_preserves_original_player_masks_and_shape",scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id and scene.player.collision_mask==original_mask and scene.player.collision_layer==original_layer)
	_check("cancelled_entry_does_not_report_theft_or_leave_gesture",scene.city_public_safety.offense_count==0 and not scene.city_public_safety.wanted and scene.exploration_avatar._sandbox_action!="vehicle_enter")
	car=await _reach_entry()
	_check("second_actual_original_car_entry_is_reachable",is_instance_valid(car) and service.pending_stage=="player_enter")
	if not is_instance_valid(car):_finish();return
	scene.toggle_menu();scene._visit_street_detail("bike_station");await _ticks(8)
	_check("validated_shortcut_cancels_entry_and_keeps_new_external_position",not scene.menu.visible and not service.riding and not is_instance_valid(service.pending_car) and not scene.player.facility_control and scene.player.is_physics_processing() and service.drivers.is_empty() and service.bikes.is_empty())
	_check("validated_external_cancel_restores_original_AI_without_theft",car.is_physics_processing() and car._running and car._manager.vehicles.has(car) and scene.city_public_safety.offense_count==0 and scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id)
	_check("all_original_car_body_model_route_shapes_retained",service.snapshot().original_identities_retained and service.snapshot().original_ai_car_count==14 and service.snapshot().spawned_replacement_cars==0)
	_finish()
func _finish() -> void:
	if _finished:return
	_finished=true;held.clear();_check("runtime_inputs_unchanged_during_test",hashes==_hashes(),{"loaded":hashes,"finished":_hashes()})
	var passed:=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(_json({"task":"EXP32_traffic_entry_cancel","recorded_at":Time.get_datetime_string_from_system(),"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"physics_hz":Engine.physics_ticks_per_second,"source_hashes":hashes,"result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"captures":captures,"snapshot":service.snapshot() if is_instance_valid(service) else {},"elapsed_ms":Time.get_ticks_msec()-_started,"scope":"Physical E and actual original moving cars; original AI/model/shape/route not moved or replaced. Player observer placement after braking is a source-supported test fixture. E cancellation, menu pause and real menu shortcut cancellation are exercised during player_enter before adoption; no artificially set custody state or fake offense. Actual W door approach and full police pursuit are separate integration suites."}),"  "));file.close();print("ENTRY_CANCEL_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)
