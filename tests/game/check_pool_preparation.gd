extends SceneTree
## Optional preparation uses production E and real room/step walking.
## Same-point water starts are disclosed fixtures for controlled speed comparisons.
class HeldMovement extends Node:
	var harness: SceneTree
	func _physics_process(_delta: float) -> void:harness._refresh_inputs()
var scene: Node3D
var service: Node3D
var roof: Node3D
var checks: Array=[]
var captures: Array=[]
var held: Dictionary={}
var report_path:="/tmp/sim2seoul-pool-preparation.json"
var _hashes: Dictionary={}
var _started:=0
var _finished:=false
func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	for action: String in ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	var node:=HeldMovement.new();node.harness=self;node.name="TestOnlyHeldPoolWalkingInput";node.process_physics_priority=-200;node.process_mode=Node.PROCESS_MODE_ALWAYS;root.add_child(node)
	_started=Time.get_ticks_msec();create_timer(300.,true,false,true).timeout.connect(func()->void:
		if not _finished:_check("bounded_timeout",false);_finish()
	);_run.call_deferred()
func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Color:return [value.r,value.g,value.b,value.a]
	if value is Rect2:return {"position":_json(value.position),"size":_json(value.size)}
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
func _source_hashes() -> Dictionary:
	var result: Dictionary={}
	for path: String in ["res://scripts/pool_preparation_service.gd","res://scripts/facility_interaction.gd","res://scripts/rooftop_space.gd","res://scripts/player/free_roam_player.gd","res://scripts/exploration_rooftop_access.gd","res://scripts/shop_visit_service.gd","res://scripts/explore_walk.gd","res://scripts/interior_visit.gd","res://../tests/game/check_pool_preparation.gd","res://resources/world_geometry/world.json","res://data/generated/terrain_surface.json"]:result[path]=FileAccess.get_sha256(path)
	return result
func _check(name: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":name,"passed":passed,"evidence":_json(evidence)});print("POOL_PREPARATION_CHECK ",name," ",passed)
func _ticks(count: int) -> void:
	for index: int in range(count):await scene.rig.camera_stepped
func _refresh_inputs() -> void:
	for action: String in held:Input.action_press(action)
func _key(action: String,down: bool) -> void:
	if down:held[action]=true;Input.action_press(action)
	else:held.erase(action);Input.action_release(action)
func _tap_e() -> void:
	var event:=InputEventKey.new();event.keycode=KEY_E;event.physical_keycode=KEY_E;event.device=0;event.pressed=true;Input.parse_input_event(event);await _ticks(3)
	event=InputEventKey.new();event.keycode=KEY_E;event.physical_keycode=KEY_E;event.device=0;event.pressed=false;Input.parse_input_event(event);await _ticks(4)
func _walk_to(point: Vector3) -> bool:
	await _ticks(3);_key("move_forward",true)
	for tick: int in range(500):
		var direction: Vector3=point-scene.player.global_position;direction.y=0.
		if direction.length()<.14:_key("move_forward",false);await _ticks(4);return true
		scene.rig.yaw=atan2(-direction.x,-direction.z);scene.rig.snap_to_target_pose();await _ticks(1)
	_key("move_forward",false);return false
func _station(kind: String) -> bool:
	var points: Dictionary=roof.pool_preparation_points();var local: Vector3=roof.frame.affine_inverse()*points[kind];var rectangle: Rect2=points[kind+"_rect"]
	return await _walk_to(roof.frame*Vector3(local.x,.08,rectangle.position.y-.50)) and await _walk_to(points[kind])
func _leave_room(kind: String) -> bool:
	var points: Dictionary=roof.pool_preparation_points();var local: Vector3=roof.frame.affine_inverse()*points[kind];var rectangle: Rect2=points[kind+"_rect"]
	return await _walk_to(roof.frame*Vector3(local.x,.08,rectangle.position.y-.50)) and await _walk_to(points.arrival)
func _capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await _ticks(3);await RenderingServer.frame_post_draw;var image:=root.get_texture().get_image();var path:=report_path.get_basename()+"_"+name+".png";var error:=image.save_png(path)
	_check("native_capture_"+name,error==OK)
	if error==OK:captures.append({"file":path,"sha256":FileAccess.get_sha256(path),"camera":scene.rig.snapshot(),"scope":"Actual current production camera; walking sets its heading toward the physical walking target. Image review is required."})
func _finish() -> void:
	if _finished:return
	_finished=true;var now:=_source_hashes();_check("source_inputs_stable_during_run",now==_hashes,{"loaded":_hashes,"finished":now})
	var passed:=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(_json({"task":"optional_pool_preparation_benefits","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"source_hashes":_hashes,"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"recorded_at":Time.get_datetime_string_from_system(true),"checks":checks,"captures":captures,"snapshot":service.snapshot() if is_instance_valid(service) else {},"elapsed_ms":Time.get_ticks_msec()-_started,"scope":"Production optional pool policy, retained native capsule, actual E room/shower actions and real gate/steps walking. Four same-point actual swimming input comparisons disclose player-only water observation starts. Completed shower cleanliness and90 actual game seconds, cancellation/menu pause/expiry/refresh cap, swimsuit selection and real transitions are observed. No clock/physics override; casual-clothes swimming intentionally supersedes earlier required-preparation policy. Headless does not prove visual appearance."}),"  "));file.close();print("POOL_PREPARATION_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)
func _fixture_at(point: Vector3) -> void:
	for action: String in held.keys():_key(action,false)
	scene.player.global_transform=Transform3D(Basis.IDENTITY,point);scene.player.velocity=Vector3.ZERO;scene.player.last_direction=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();scene.rig.snap_to_target_pose();await _ticks(8)
func _measure_swim(label_: String,expected_speed: float) -> void:
	# Identical central water observer starts remove wall/entry-ramp effects.
	await _fixture_at(roof.pool_float_point())
	scene.rig.yaw=atan2(roof.frame.basis.z.x,roof.frame.basis.z.z);scene.rig.snap_to_target_pose()
	var before: Vector3=scene.player.global_position;var peak:=0.;var low:=INF
	_key("move_right",true)
	for tick: int in range(20):
		await _ticks(1)
		var speed:=Vector2(scene.player.velocity.x,scene.player.velocity.z).length()
		if tick>=4:low=minf(low,speed);peak=maxf(peak,speed)
	_key("move_right",false);await _ticks(3)
	var water: Dictionary=scene.player.water_snapshot()
	_check(label_+"_actual_input_speed_and_buoyancy",scene.player.is_swimming() and absf(peak-expected_speed)<.035 and absf(low-expected_speed)<.035 and absf(float(water.swim_speed_limit_mps)-expected_speed)<.001 and Vector2(scene.player.global_position.x-before.x,scene.player.global_position.z-before.z).length()>.8,{"minimum_observed_speed_mps":low,"maximum_observed_speed_mps":peak,"expected_mps":expected_speed,"water":water,"benefits":service.snapshot(),"scope":"Actual held right input from disclosed identical player-only central-water start; body/collision/buoyancy remain production."})
	_check(label_+"_HUD_explains_actual_effects",service.prompt_text().contains("%.2fm/s"%expected_speed) and service.prompt_text().contains("청결"),{"HUD":service.prompt_text()})
	await _capture(label_+"_actual_swimming")
func _run() -> void:
	_hashes=_source_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/private/tmp/optional-pool-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8)
	service=scene.pool_preparation_service
	_check("production_optional_pool_hooks_loaded",scene.runtime_ok and is_instance_valid(service) and service.loaded,{"error":service.load_error if is_instance_valid(service) else "pool service unavailable"})
	if not scene.runtime_ok or not is_instance_valid(service) or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	scene.set_speed_profile("realistic");scene._visit_street_detail("hotel_pool");await _ticks(8);roof=scene.exploration_rooftop_access.ensure_rooftop(scene.exploration_rooftop_access.REPRESENTATIVE_POOL_ID)
	var points: Dictionary=roof.pool_preparation_points();var shape_id: int=scene.player.get_node("CollisionShape").shape.get_instance_id();var mask: int=scene.player.collision_mask;var outfit: Dictionary=scene.shop_visit_service.outfit_snapshot();var cleanliness_before: float=scene.interior_visit.facility_interaction.cleanliness
	_check("all_created_pool_entrances_open_without_clothing_or_shower",service.snapshot().rooms.size()>=2 and service.snapshot().rooms.all(func(row: Dictionary)->bool:return row.authorized and row.gate_layer==0) and not scene.shop_visit_service.swimwear_active and service.freshness_remaining_s==0.,service.snapshot())
	_check("changing_and_shower_keep_actual_rooms_and_visible_water",roof.has_node("PoolLocker") and roof.has_node("PoolChangingBench") and roof.has_node("PoolChangingPrivacySideBody") and roof.has_node("PoolShowerColumn") and roof.has_node("PoolPreparationShowerWater"))
	var gate: Vector3=roof.frame.affine_inverse()*points.gate;var arrival: Vector3=roof.frame.affine_inverse()*points.arrival
	_check("casual_clothes_physically_walk_open_gate_and_steps_into_pool",await _walk_to(roof.frame*Vector3(gate.x,.08,arrival.z)) and await _walk_to(points.gate) and await _walk_to(roof.pool_rim_point()) and await _walk_to(roof.pool_steps_bottom_point()))
	await _ticks(12);_check("unprepared_player_swims_without_restore_or_rejection",scene.player.is_swimming() and not scene.shop_visit_service.swimwear_active and service.rejected_water_entries==0,scene.player.water_snapshot())
	await _measure_swim("casual_without_shower",3.0)
	await _fixture_at(points.arrival);_check("casual_clothes_walk_into_actual_shower",await _station("shower"));await _tap_e();await _ticks(25)
	_check("shower_accepts_casual_clothes_and_gives_nothing_before_completion",service.showering and roof._pool_shower_water.visible and scene.player.facility_control and not scene.shop_visit_service.swimwear_active and service.freshness_remaining_s==0. and is_equal_approx(scene.interior_visit.facility_interaction.cleanliness,cleanliness_before))
	scene.toggle_menu();var shower_clock: float=service.shower_elapsed
	for tick: int in range(15):await process_frame
	_check("menu_pauses_real_shower_clock",is_equal_approx(service.shower_elapsed,shower_clock) and paused);scene.toggle_menu();await _ticks(3)
	await _tap_e();_check("cancelled_shower_releases_control_without_new_effect",not service.showering and not scene.player.facility_control and not roof._pool_shower_water.visible and service.freshness_remaining_s==0. and scene.interior_visit.facility_interaction.cleanliness==cleanliness_before)
	await _tap_e();await _ticks(125)
	_check("completed_shower_only_grants_capped_cleanliness_and90s_freshness",service.completed_showers==1 and not service.showering and service.showered and service.freshness_remaining_s>89. and service.freshness_remaining_s<=90. and not scene.shop_visit_service.swimwear_active and absf(scene.interior_visit.facility_interaction.cleanliness-minf(100.,cleanliness_before+20.))<.001,service.snapshot())
	_check("shower_prompt_states_freshness_duration_and_speed_bonus",service.prompt_text().contains("상쾌함") and service.prompt_text().contains("+10%"),{"HUD":service.prompt_text()})
	await _measure_swim("shower_only",3.30)
	await _fixture_at(points.arrival);_check("walk_changing_door_for_optional_swimwear",await _station("changing"));await _tap_e()
	_check("swimwear_choice_preserves_existing_freshness_and_adds15pct",scene.shop_visit_service.swimwear_active and service.freshness_remaining_s>0. and absf(service.swimming_speed_multiplier()-1.25)<.001,service.snapshot())
	await _measure_swim("shower_and_swimwear",3.75)
	await _fixture_at(points.arrival);await _station("changing");await _tap_e()
	_check("changing_back_restores_exact_outfit_but_keeps_shower_reward",not scene.shop_visit_service.swimwear_active and scene.shop_visit_service.outfit_snapshot()==outfit and service.freshness_remaining_s>0. and absf(service.swimming_speed_multiplier()-1.10)<.001,service.snapshot())
	scene.toggle_menu();var fresh_clock: float=service.freshness_remaining_s
	for tick: int in range(15):await process_frame
	_check("menu_pauses_freshness_game_clock",is_equal_approx(service.freshness_remaining_s,fresh_clock) and paused);scene.toggle_menu();await _ticks(3)
	var clock_before: float=service._clock;var remaining_before: float=service.freshness_remaining_s
	var complete_clock:=0.
	for event: Dictionary in service.events:
		if event.event=="shower_completed":complete_clock=float(event.clock_s)
	await _ticks(maxi(0,floori((remaining_before-.10)*30.)))
	_check("freshness_remains_active_until_actual90s_boundary",service.freshness_remaining_s>0. and service._clock-complete_clock<90. and absf((remaining_before-service.freshness_remaining_s)-(service._clock-clock_before))<.001,{"elapsed_since_completion_s":service._clock-complete_clock,"remaining_s":service.freshness_remaining_s})
	await _ticks(8)
	_check("freshness_expires_after_actual90_game_seconds_without_clock_override",service._clock-complete_clock>=90. and service.freshness_remaining_s==0. and not service.showered and is_equal_approx(service.swimming_speed_multiplier(),1.),{"elapsed_since_completion_s":service._clock-complete_clock,"snapshot":service.snapshot()})
	await _tap_e();_check("optional_swimwear_can_be_selected_without_shower",scene.shop_visit_service.swimwear_active and service.freshness_remaining_s==0.)
	await _measure_swim("swimwear_only",3.45)
	await _fixture_at(points.arrival);await _station("shower")
	for repeat: int in range(4):
		await _tap_e();await _ticks(125)
		_check("repeat_shower_"+str(repeat)+"_refreshes90s_and_never_stacks_speed_or_hygiene",not service.showering and service.freshness_remaining_s>89. and service.freshness_remaining_s<=90. and absf(service.swimming_speed_multiplier()-1.25)<.001 and scene.interior_visit.facility_interaction.cleanliness<=100.,service.snapshot())
	_check("repeated_completed_showers_reach_but_do_not_exceed100_cleanliness",service.completed_showers==5 and scene.interior_visit.facility_interaction.cleanliness==100. and service.last_shower_cleanliness_gain==0.,service.snapshot())
	var old_id: String=service.pool_id;var second: Node3D
	for candidate: Node3D in service._roofs():
		if candidate!=roof:second=candidate;break
	if is_instance_valid(second):
		var accepted: bool=scene._commit_exploration_teleport(second.pool_entry_point(),{"roof":second,"pool_entry":second.pool_entry_point()});await _ticks(5)
		_check("different_pool_transition_clears_timed_bonus_and_restores_outfit",accepted and service.pool_id.is_empty() and service.freshness_remaining_s==0. and not scene.shop_visit_service.swimwear_active and scene.shop_visit_service.outfit_snapshot()==outfit and service.water_access_allowed(second) and second._pool_gate_body.collision_layer==0 and not service.prompt_text().contains("샤워 완료"),{"previous_pool":old_id,"destination":second.spec.id,"snapshot":service.snapshot()})
	else:_check("different_pool_transition_clears_timed_bonus_and_restores_outfit",false)
	scene.reset_player();await _ticks(8)
	_check("ordinary_reset_keeps_original_capsule_mask_and_cleans_pool_owner",not scene.player.facility_control and not service.showering and service.pool_id.is_empty() and service.freshness_remaining_s==0. and scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id and scene.player.collision_mask==mask)
	_check("existing_cleanliness_stat_remains_after_leaving_pool",scene.interior_visit.facility_interaction.cleanliness==100.)
	_check("original30_people_and14_AI_cars_preserved",scene.pedestrians.size()+scene.street_pedestrians.actors.size()+scene.neighborhood_population.walkers.actors.size()==30 and scene.vehicles.size()+scene.neighborhood_population.traffic.vehicles.size()==14)
	_finish()
