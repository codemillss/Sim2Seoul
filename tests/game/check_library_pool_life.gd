extends "res://../tests/game/check_pool_preparation.gd"
## Focused actual-city desk/bar E integration. Explicit scenario starts are
## labelled; approach walks, interactions, ownership and menus are production.
var observations: Array=[]

func _source_hashes() -> Dictionary:
	var result:=super._source_hashes()
	for path: String in ["res://scripts/interior_facility_kit.gd","res://scripts/interior_detail_kit.gd","res://scripts/facility_interaction.gd","res://scripts/facility_activity_visuals.gd","res://scripts/player/exploration_avatar.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://../tests/game/check_library_pool_life.gd"]:result[path]=FileAccess.get_sha256(path)
	return result

func _scenario(point: Vector3,label_: String) -> void:
	observations.append({"scenario_start":label_,"point":point,"test_only_placement":true})
	scene.player.global_position=point;scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();await _ticks(8)

func _study() -> void:
	scene._visit_library_entrance();await _ticks(8);await _tap_e()
	var visit: Node3D=scene.interior_visit;var activity: Node3D=visit.facility_interaction
	_check("library_menu_and_fresh_E_enter_actual_source_library",visit.active and String(visit.current_spec.id)=="osm:relation:10757525:building")
	if not visit.active:return
	var target: Dictionary={}
	for row: Dictionary in activity.snapshot().targets:
		if row.kind=="study" and int(row.level)==0:target=row;break
	_check("library_has_floor0_usable_study_desk_with_knee_space",not target.is_empty(),{"target":target})
	if target.is_empty():return
	var shape_id: int=scene.player.get_node("CollisionShape").shape.get_instance_id();var mask: int=scene.player.collision_mask
	await _scenario(visit.room.to_global(target.approach_point),"library_study_approach")
	_check("study_chair_actual_native_capsule_and_exit_corridor_clear",activity._capsule_clear(visit.room.to_global(target.use_point)) and activity._walk_segment_clear(visit.room.to_global(target.use_point),visit.room.to_global(target.approach_point)))
	await _tap_e();await _ticks(8)
	_check("fresh_E_sits_actual_human_and_takes_single_facility_control",activity.is_using() and activity.snapshot().kind=="study" and scene.player.facility_control and scene.exploration_avatar.snapshot().activity_kind=="study",activity.snapshot())
	if not activity.is_using():return
	var actor: Node3D=scene.exploration_avatar;var model: Dictionary=actor.textured_model_snapshot(true);var actual: AABB=actor.global_transform*model.actual_visible_bounds_m;var floor_y: float=visit.room.to_global(Vector3(0,0,0)).y
	var skel: Skeleton3D=actor._textured_surface.skeleton;var pelvis: Vector3=skel.global_transform*skel.get_bone_global_pose(skel.find_bone("Bip01 Pelvis")).origin
	observations.append({"study_actual_skin_world_bounds":{"position":actual.position,"size":actual.size},"floor_y_m":floor_y,"actual_sole_floor_gap_m":actual.position.y-floor_y,"actual_pelvis_world_m":pelvis,"seat_top_world_m":visit.room.to_global(target.data.seat_center+Vector3.UP*.52),"rig":model.rig_contact_metrics})
	_check("study_actual_skinned_shoe_soles_rest_near_floor",absf(actual.position.y-floor_y)<.025,{"sole_floor_gap_m":actual.position.y-floor_y,"world_bounds":str(actual)})
	_check("study_actual_head_is_seated_below_standing_height",actual.end.y-floor_y<1.50 and actual.end.y-floor_y>1.05,{"top_above_floor_m":actual.end.y-floor_y})
	scene.rig.yaw=deg_to_rad(125.);scene.rig.pitch=deg_to_rad(-12.);scene.rig.requested_distance=3.8;scene.rig.snap_to_target_pose()
	await _capture("library_seated_study")
	var locked: Vector3=scene.player.global_position;_key("move_forward",true);_key("jump",true);await _ticks(8)
	_check("study_W_and_Space_do_not_move_locked_capsule",scene.player.global_position.distance_to(locked)<.001)
	_key("move_forward",false);_key("jump",false);await _ticks(3)
	scene.toggle_menu();var clock: float=activity.snapshot().elapsed
	for index: int in range(12):await process_frame
	_check("study_menu_freezes_time_and_keeps_control",is_equal_approx(float(activity.snapshot().elapsed),clock) and scene.player.facility_control)
	scene.toggle_menu();await _ticks(4);await _tap_e();await _ticks(3)
	_check("fresh_E_stands_in_clear_aisle_and_restores_control",not activity.is_using() and not scene.player.facility_control and scene.player.global_position.distance_to(visit.room.to_global(target.approach_point))<.16 and scene.exploration_avatar.snapshot().activity_kind=="",activity.snapshot())
	_check("study_retains_native_capsule_and_collision_mask",scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id and scene.player.collision_mask==mask)
	_check("study_elapsed_record_is_real_and_completed_once",activity.study_seconds>.5 and activity.completed_counts.study==1 and activity.started_counts.study==1,activity.snapshot())
	await _capture("library_stood_up")

func _bar() -> void:
	scene._visit_street_detail("hotel_pool");await _ticks(8);roof=scene.exploration_rooftop_access.ensure_rooftop(scene.exploration_rooftop_access.REPRESENTATIVE_POOL_ID)
	service=scene.pool_preparation_service
	var lounge: Dictionary=roof.pool_lounge_snapshot()
	_check("evening_shortcut_arrives_at_guarded_pool_with_four_lights",scene.time_id=="evening" and lounge.active_lights==4 and not scene.player.is_swimming() and roof._pool_gate_body.collision_layer==1,{"lounge":lounge,"position":scene.player.global_position})
	_check("pool_has_actual_textured_bartender_and_nonalcohol_menu",lounge.bartender_textured and lounge.bar.nonalcoholic and lounge.bar.drinks.size()==3,lounge)
	var view: Vector3=roof.pool_float_point()-scene.player.global_position;scene.rig.yaw=atan2(-view.x,-view.z);scene.rig.pitch=deg_to_rad(-22.);scene.rig.requested_distance=7.5;scene.rig.snap_to_target_pose()
	await _capture("pool_evening_lights")
	var bar: Dictionary=roof.pool_bar();var chosen: Dictionary=bar.drink_options[1];var credit_before: int=scene.shop_visit_service.balance;await _scenario(chosen.use_point+roof.frame.basis.x*.55,"bar_approach")
	_check("bar_customer_point_is_actual_capsule_safe",not service._safe_point(chosen.use_point).is_empty())
	_check("physical_walk_reaches_bar_customer_side",await _walk_to(chosen.use_point))
	await _tap_e();await _ticks(3)
	_check("fresh_E_orders_visible_cup_without_preparation_bypass",roof.pool_bar().stage=="preparing" and roof._bar_cup.visible and not service.showered and not scene.player.facility_control and not scene.shop_visit_service.swimwear_active,roof.pool_bar())
	scene.toggle_menu();var progress: float=roof.pool_bar().elapsed_s
	for index: int in range(12):await process_frame
	_check("menu_freezes_bartender_order",is_equal_approx(float(roof.pool_bar().elapsed_s),progress))
	scene.toggle_menu();await _ticks(55)
	_check("bartender_finishes_actual_visible_cup_at_counter",roof.pool_bar().stage=="ready" and roof._bar_cup.visible,roof.pool_bar())
	await _capture("pool_bartender_ready_drink")
	await _tap_e();await _ticks(3)
	_check("fresh_E_collects_one_free_nonalcohol_drink",roof.pool_bar().served==1 and roof.pool_bar().stage=="idle" and not roof._bar_cup.visible and roof.pool_bar().drink=="보리차" and scene.shop_visit_service.balance==credit_before,roof.pool_bar())
	scene.set_time_profile("day");await _ticks(3);_check("day_profile_turns_all_pool_light_emission_off",roof.pool_lounge_snapshot().active_lights==0 and roof._glow_materials.all(func(m: StandardMaterial3D)->bool:return m.emission_energy_multiplier==0.))
	scene.set_time_profile("evening");await _ticks(3)
	_check("pool_original_changing_shower_gate_and_water_region_retained",roof.pool_preparation_points().has_all(["changing","shower","gate"]) and roof.pool_water_region().rect.get_area()>=72. and roof._pool_gate_body.collision_layer==1 and not service.water_access_allowed(roof))
	observations.append({"pool_lounge":roof.pool_lounge_snapshot(),"preparation":service.snapshot()})

func _run() -> void:
	_hashes=_source_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/library-pool-life-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8)
	service=scene.pool_preparation_service
	_check("actual_exploration_runtime_loaded",scene.runtime_ok)
	if not scene.runtime_ok:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	scene.set_speed_profile("realistic")
	await _study();await _bar();_finish()

func _finish() -> void:
	if _finished:return
	_finished=true
	_check("source_inputs_stable_during_run",_hashes==_source_hashes())
	var passed:=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(_json({"task":"LIBRARY_AND_POOL_LIFE","result":"PASS" if passed==checks.size() else "FAIL","summary":{"checks":checks.size(),"failed":checks.size()-passed},"source_sha256":_hashes,"checks":checks,"observations":observations,"captures":captures,"elapsed_ms":Time.get_ticks_msec()-_started,"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"scope":"Actual source-positioned city scene and native capsule. Library/bar scenario starts are explicit test placements; short approach walks and fresh physical E use production dispatcher. Study menu/input/exit, actual CPU skin height, pool evening lights/free nonalcohol order and unchanged preparation guards are checked. Full existing swim/Space-exit regression is separate; native image review and OS input/performance are separate."}),"  ")+"\n");file.close();print("LIBRARY_POOL_LIFE_RESULT ",passed,"/",checks.size());_teardown.call_deferred(0 if passed==checks.size() else 1)

func _teardown(exit_code: int) -> void:
	# Let the awaited scenario frames unwind before releasing textured models.
	if is_instance_valid(scene):scene.queue_free()
	await process_frame
	await process_frame
	quit(exit_code)
