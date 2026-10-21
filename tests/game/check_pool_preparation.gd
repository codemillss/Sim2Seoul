extends SceneTree
## Normal preparation uses production E and physical walks through both rooms.
## Direct water/fall placements below are explicitly labelled bypass fixtures.
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
	for path: String in ["res://scripts/pool_preparation_service.gd","res://scripts/rooftop_space.gd","res://scripts/player/free_roam_player.gd","res://scripts/exploration_rooftop_access.gd","res://scripts/shop_visit_service.gd","res://scripts/explore_walk.gd","res://scripts/interior_visit.gd","res://../tests/game/check_pool_preparation.gd","res://resources/world_geometry/world.json","res://data/generated/terrain_surface.json"]:result[path]=FileAccess.get_sha256(path)
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
	file.store_string(JSON.stringify(_json({"task":"required_pool_preparation","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"source_hashes":_hashes,"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"recorded_at":Time.get_datetime_string_from_system(true),"checks":checks,"captures":captures,"snapshot":service.snapshot() if is_instance_valid(service) else {},"elapsed_ms":Time.get_ticks_msec()-_started,"scope":"Production roof-local rooms, full retained native player capsule, physical E, held-action walking fixture priority -200, actual shower clock/menu/abort, swimsuit lock, native water guard and actual swim/Space exit. Explicit illegal-water and fall placements are fixtures; headless does not accept visual appearance. Prior EXP23 unrestricted casual-clothes pool-entry expectations are intentionally superseded."}),"  "));file.close();print("POOL_PREPARATION_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)
func _run() -> void:
	_hashes=_source_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/pool-preparation-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8)
	service=scene.get("pool_preparation_service")
	if not is_instance_valid(service):service=load("res://scripts/pool_preparation_service.gd").new();scene.pool_preparation_service=service;scene.add_child(service);service.setup(scene)
	_check("production_pool_and_clothing_hooks_loaded",scene.runtime_ok and service.loaded and scene.shop_visit_service.loaded,{"error":service.load_error})
	if not scene.runtime_ok or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	scene._visit_street_detail("hotel_pool");await _ticks(8);roof=scene.exploration_rooftop_access.ensure_rooftop(scene.exploration_rooftop_access.REPRESENTATIVE_POOL_ID)
	var points: Dictionary=roof.pool_preparation_points();var shape_id: int=scene.player.get_node("CollisionShape").shape.get_instance_id();var mask: int=scene.player.collision_mask;var before_outfit: Dictionary=scene.shop_visit_service.outfit_snapshot()
	_check("ordinary_pool_shortcut_arrives_outside_water_and_preparation_gate",scene.player.global_position.distance_to(points.arrival)<.25 and not scene.player.is_swimming() and roof._pool_gate_body.collision_layer==1,{"player":scene.player.global_position,"arrival":points.arrival})
	_check("all_created_outdoor_pools_have_native_rooms_and_gate",service.snapshot().rooms.size()>=2 and service.snapshot().rooms.all(func(row: Dictionary)->bool:return row.gate_layer==1),{"rooms":service.snapshot().rooms})
	_check("rooms_have_lockers_bench_privacy_shower_and_visible_water_nodes",roof.has_node("PoolLocker") and roof.has_node("PoolChangingBench") and roof.has_node("PoolChangingPrivacySideBody") and roof.has_node("PoolShowerColumn") and roof.has_node("PoolPreparationShowerWater"))
	await _capture("ordinary_pool_arrival")
	_check("walk_through_actual_changing_door",await _station("changing"),{"player":scene.player.global_position,"target":points.changing})
	await _capture("changing_room_lockers_and_bench")
	await _tap_e();_check("physical_E_changes_to_swimwear_only_inside_changing_room",scene.shop_visit_service.swimwear_active and service.pool_id==String(roof.spec.id) and not service.showered)
	await _capture("swimwear_in_changing_room")
	_check("swimwear_locks_I_inventory_and_outfit_equipping",not scene.shop_visit_service.open_inventory() and not scene.shop_visit_service.restore_default_outfit())
	_check("changing_room_exit_is_physically_walkable",await _leave_room("changing"))
	_check("walk_through_actual_shower_door",await _station("shower"))
	await _tap_e();await _ticks(25);var elapsed: float=service.shower_elapsed
	_check("shower_runs_visible_water_and_holds_native_player",service.showering and roof._pool_shower_water.visible and scene.player.facility_control and scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id)
	await _capture("shower_running_water")
	scene.toggle_menu();var clock: float=service.shower_elapsed
	for frame: int in range(15):await process_frame
	_check("menu_freezes_shower_progress",is_equal_approx(service.shower_elapsed,clock) and paused)
	scene.toggle_menu();await _ticks(3);await _tap_e();_check("early_E_cancellation_does_not_grant_entry",not service.showering and not service.showered and not scene.player.facility_control and not roof._pool_shower_water.visible and elapsed<service.SHOWER_SECONDS)
	await _tap_e();await _ticks(125);_check("complete_native_shower_grants_only_this_pool",service.showered and not service.showering and service.completed_showers==1 and not scene.player.facility_control and service.water_access_allowed(roof) and roof._pool_gate_body.collision_layer==0,{"snapshot":service.snapshot()})
	await _capture("prepared_swimwear_shower_room")
	_check("shower_room_exit_is_physically_walkable",await _leave_room("shower"))
	# Approach between the existing gate posts, rather than taking a diagonal
	# shortcut through the decorative left post from the centre arrival lane.
	var gate_local: Vector3=roof.frame.affine_inverse()*points.gate;var arrival_local: Vector3=roof.frame.affine_inverse()*points.arrival
	_check("authorized_gate_and_entry_steps_are_physically_walkable",await _walk_to(roof.frame*Vector3(gate_local.x,.08,arrival_local.z)) and await _walk_to(points.gate) and await _walk_to(roof.pool_rim_point()) and await _walk_to(roof.pool_steps_bottom_point()),{"player":scene.player.global_position,"gate":points.gate,"steps":roof.pool_steps_bottom_point()})
	await _ticks(12);_check("prepared_player_actually_swims_with_original_buoyancy",scene.player.is_swimming() and scene.player.water_snapshot().under_surface and service.rejected_water_entries==0,{"water":scene.player.water_snapshot()})
	await _capture("prepared_actual_swimming")
	var jumps: int=scene.player.water_snapshot().water_jump_count;scene.rig.yaw=atan2(roof.frame.basis.z.x,roof.frame.basis.z.z);scene.rig.snap_to_target_pose();_key("move_backward",true);_key("jump",true);var peak: float=scene.player.global_position.y
	for tick: int in range(45):await _ticks(1);peak=maxf(peak,scene.player.global_position.y)
	_key("jump",false);_key("move_backward",false)
	_check("fresh_Space_jumps_out_of_water_without_losing_preparation",scene.player.water_snapshot().water_jump_count==jumps+1 and peak>roof.frame.origin.y+.8 and not scene.player.is_swimming() and not scene.player.water_snapshot().under_surface and service.water_access_allowed(roof),{"peak_world_y":peak,"deck_world_y":roof.frame.origin.y,"water":scene.player.water_snapshot()})
	await _ticks(20);await _walk_to(points.arrival);_check("can_walk_back_to_changing_room_after_swimming",await _station("changing"));await _tap_e();await _ticks(3)
	_check("changing_room_E_restores_exact_previous_outfit_and_closes_gate",not scene.shop_visit_service.swimwear_active and scene.shop_visit_service.outfit_snapshot()==before_outfit and service.pool_id.is_empty() and not service.showered and roof._pool_gate_body.collision_layer==1)
	await _capture("previous_outfit_restored")
	await _leave_room("changing")
	# A labelled bypass fixture places the retained player directly in water.
	var rejects: int=service.rejected_water_entries;scene.player.global_transform=Transform3D(Basis.IDENTITY,roof.pool_float_point());scene.player.velocity=Vector3.ZERO;scene.player.reset_physics_interpolation();await _ticks(2)
	_check("direct_unprepared_water_placement_is_rejected_with_native_safe_restore",service.rejected_water_entries>rejects and not scene.player.is_swimming() and not service._safe_point(scene.player.global_position).is_empty(),{"player":scene.player.global_position,"rejects":service.rejected_water_entries})
	rejects=service.rejected_water_entries;scene.player.global_transform=Transform3D(Basis.IDENTITY,roof.pool_float_point());scene.player.velocity=Vector3(4.,5.,3.);scene.player.last_direction=Vector3.RIGHT;scene.player.reset_physics_interpolation();await _ticks(1)
	_check("rejected_positive_velocity_entry_clears_all_motion_at_supported_point",service.rejected_water_entries>rejects and scene.player.velocity.is_zero_approx() and scene.player.last_direction.is_zero_approx() and not scene.player._water_jump_locked and not service._safe_point(scene.player.global_position).is_empty(),{"velocity":scene.player.velocity,"last_direction":scene.player.last_direction})
	rejects=service.rejected_water_entries;var drop: Vector3=roof.pool_float_point();drop.y=roof.frame.origin.y+4.;scene.player.global_transform=Transform3D(Basis.IDENTITY,drop);scene.player.velocity=Vector3(0,-6.,0);scene.player.reset_physics_interpolation();await _ticks(40)
	_check("unprepared_fall_or_jump_bypass_is_rejected_before_swimming",service.rejected_water_entries>rejects and not scene.player.is_swimming() and not scene.player.facility_control,{"player":scene.player.global_position,"rejects":service.rejected_water_entries})
	await _station("changing");await _tap_e();_check("preparation_can_start_again_after_refusal",scene.shop_visit_service.swimwear_active)
	var first_session: String=service.pool_id;var second: Node3D
	for candidate: Node3D in service._roofs():
		if candidate!=roof:second=candidate;break
	if is_instance_valid(second):
		var destination: Dictionary={"roof":second,"pool_entry":second.pool_entry_point()};var accepted: bool=scene._commit_exploration_teleport(destination.pool_entry,destination);await _ticks(5)
		_check("another_roof_teleport_releases_swimwear_and_preparation",accepted and not scene.shop_visit_service.swimwear_active and service.pool_id.is_empty() and not service.water_access_allowed(second),{"previous_pool":first_session,"destination":second.spec.id})
	else:_check("another_roof_teleport_releases_swimwear_and_preparation",false)
	scene._visit_street_detail("hotel_pool");await _ticks(5);await _station("changing");await _tap_e();scene.reset_player();await _ticks(8)
	_check("successful_reset_restores_outfit_and_releases_preparation",not scene.shop_visit_service.swimwear_active and service.pool_id.is_empty() and not service.showering and not scene.player.facility_control and scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id and scene.player.collision_mask==mask)
	_check("original30_people_and14_AI_cars_preserved",scene.pedestrians.size()+scene.street_pedestrians.actors.size()+scene.neighborhood_population.walkers.actors.size()==30 and scene.vehicles.size()+scene.neighborhood_population.traffic.vehicles.size()==14)
	_finish()
