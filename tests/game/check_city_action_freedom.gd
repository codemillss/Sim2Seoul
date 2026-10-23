extends "res://../tests/game/check_city_public_safety.gd"
## Physical key edges in the ordinary world. Player-only supported observer
## starts and named LOS blockers are fixtures; original actors stay in place.
signal late_observed
class LateObservation extends Node:
	var harness: SceneTree
	func _process(_delta: float) -> void:harness.late_observed.emit()
var observations: Array=[]
var initial_footprint: Dictionary={}
var initial_city: Dictionary={}
var car_service: Node3D

func _initialize() -> void:
	super._initialize()
	var late:=LateObservation.new();late.name="TestOnlyAfterNativeRigObservation";late.harness=self;late.process_priority=1000;late.process_mode=Node.PROCESS_MODE_ALWAYS;root.add_child(late)

func _ticks(count: int) -> void:
	# SceneTree.process_frame emits before native skin priorities100/110. Read
	# after their actual solved poses, as the existing authored-action fixture.
	for tick: int in range(count):await physics_frame;await late_observed

func _hashes() -> Dictionary:
	var result:=super._hashes()
	for path: String in ["res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://scripts/traffic/vehicle.gd","res://../tests/game/check_city_action_freedom.gd"]:result[path]=FileAccess.get_sha256(path)
	return result

func _event(code: int,down: bool,echo:=false) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down;event.echo=echo;event.device=42;Input.parse_input_event(event)

func _tap(code: int) -> void:
	_event(code,true);await _ticks(2);_event(code,false)

func _count(kind: String) -> int:
	return service.events.filter(func(row: Dictionary)->bool:return row.event==kind).size()

func _combat() -> Dictionary:
	return service.combat_snapshot()

func _idle() -> void:
	for tick: int in range(60):
		if String(_combat().get("phase",""))=="idle":return
		await _ticks(1)

func _footprint() -> Dictionary:
	var shape: CollisionShape3D=scene.player.get_node("CollisionShape")
	return {"player":scene.player.get_instance_id(),"shape":shape.shape.get_instance_id(),"radius":shape.shape.radius,"height":shape.shape.height,"transform":shape.transform,"layer":scene.player.collision_layer,"mask":scene.player.collision_mask}

func _city_inventory() -> Dictionary:
	var result: Dictionary={}
	for key: String in scene.city.source_nodes:
		var node: Node3D=scene.city.source_nodes[key];result[key]={"instance":node.get_instance_id(),"transform":node.global_transform}
	return result

func _pose() -> Dictionary:
	var human: Node3D=scene.exploration_avatar._textured_surface.rig
	var skeleton: Skeleton3D=scene.exploration_avatar._textured_surface.skeleton
	var points: Dictionary={};var finite:=true;var error:=0.
	for semantic: String in ["LeftUpperArm","LeftForearm","LeftHand","RightUpperArm","RightForearm","RightHand"]:
		var bone: Transform3D=skeleton.get_bone_global_pose(human._find(semantic));finite=finite and bone.is_finite()
		var source: String=semantic.replace("Hand","Forearm")
		var expected: Basis=human._source_pose(human._source_node(source)).basis*human._corrections[semantic]
		error=maxf(error,maxf(bone.basis.x.normalized().distance_to(expected.x.normalized()),maxf(bone.basis.y.normalized().distance_to(expected.y.normalized()),bone.basis.z.normalized().distance_to(expected.z.normalized()))))
		if semantic.ends_with("Hand"):points[semantic]=scene.player.get_node("Visual").global_transform.affine_inverse()*(skeleton.global_transform*bone.origin)
	return {"points":points,"finite":finite,"source_axis_error":error,"combat":_combat()}

func _capture_now(title: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image();var path:=report_path.get_basename()+"_"+title+".png";var status:=picture.save_png(path)
	_check("native_"+title,status==OK)
	if status==OK:captures.append({"file":path,"sha256":FileAccess.get_sha256(path),"combat":_combat(),"car_stage":car_service.get("pending_stage") if is_instance_valid(car_service) else "","scope":"Actual ordinary camera and rendered imported human. Supported player-only observer starts; all source actors and collision remain production objects. Pixel review required separately."})

func _exercise_action(code: int,expected: String) -> void:
	var before:=_count("melee_started");var hits_before: int=service.hits
	# The down/up pair arrives between physics ticks, proving queued short taps.
	_event(code,true);_event(code,false);await _ticks(1)
	var starting:=_combat();var samples: Array=[];var finite:=true;var error:=0.;var minimum_left:=Vector3(INF,INF,INF);var maximum_left:=Vector3(-INF,-INF,-INF);var minimum_right:=minimum_left;var maximum_right:=maximum_left;var phases: Array=[];var captured:=false
	_check(expected+".short_physical_edge_starts_windup_without_immediate_hit",_count("melee_started")==before+1 and starting.get("action","")==expected and starting.get("phase","")=="windup" and service.hits==hits_before,{"combat":starting})
	for tick: int in range(30):
		await _ticks(1)
		var state:=_combat();var phase:=String(state.get("phase",""))
		if phase=="idle":break
		if not phases.has(phase):phases.append(phase)
		var pose:=_pose();finite=finite and pose.finite;error=maxf(error,pose.source_axis_error)
		minimum_left=minimum_left.min(pose.points.LeftHand);maximum_left=maximum_left.max(pose.points.LeftHand);minimum_right=minimum_right.min(pose.points.RightHand);maximum_right=maximum_right.max(pose.points.RightHand)
		if samples.size()<5 and (tick%3)==0:samples.append({"tick":tick,"phase":phase,"left":pose.points.LeftHand,"right":pose.points.RightHand})
		if not captured and tick==4:await _capture_now(expected+"_intermediate");captured=true
		if tick==6:_event(KEY_F,true);_event(KEY_F,false)
	var left_range:=maximum_left.distance_to(minimum_left);var right_range:=maximum_right.distance_to(minimum_right)
	var row:={"action":expected,"left_hand_excursion_m":left_range,"right_hand_excursion_m":right_range,"maximum_source_native_axis_error":error,"phases":phases,"samples":samples,"native_finite":finite};observations.append(row)
	_check(expected+".actual_imported_arms_follow_authored_pose_and_move",finite and error<.001 and maxf(left_range,right_range)>.07,row)
	_check(expected+".fresh_recovery_press_does_not_queue_an_extra_action",_combat().get("phase","")=="idle" and _count("melee_started")==before+1,{"combat":_combat(),"phases":phases})

func _car_observer(body: CharacterBody3D,farther:=false) -> bool:
	var offsets: Array=[Vector3(-2.7,0,-.38),Vector3(2.7,0,-.38),Vector3(-2.8,0,.6),Vector3(2.8,0,.6)] if farther else [Vector3(-2.15,0,-.38),Vector3(2.15,0,-.38),Vector3(-2.3,0,.6),Vector3(2.3,0,.6)]
	for offset: Vector3 in offsets:
		var safe: Dictionary=scene.interior_visit._safe_external_point(body.to_global(offset))
		if safe.is_empty():continue
		scene.player.global_position=safe.point;scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();scene.rig.snap_to_target_pose();await _ticks(3)
		if car_service._nearest_car()==body and car_service.can_interact() and scene._street_interact_target()==car_service:return true
	return false

func _walk_to_door(body: CharacterBody3D) -> Dictionary:
	var before: Vector3=scene.player.global_position;var start_distance: float=car_service._door_distance_for(body)
	_event(KEY_W,true)
	for tick: int in range(100):
		if not is_instance_valid(car_service.pending_car) or car_service.pending_stage!="approach" or car_service._door_distance_for(body)<=1.02:break
		var left: Vector3=body.to_global(Vector3(-1.2,0,-.38));var right: Vector3=body.to_global(Vector3(1.2,0,-.38));var door: Vector3=left if scene.player.global_position.distance_to(left)<scene.player.global_position.distance_to(right) else right
		var toward: Vector3=door-scene.player.global_position;toward.y=0.;scene.rig.yaw=atan2(-toward.x,-toward.z);scene.rig.snap_to_target_pose();Input.action_press("move_forward");await _ticks(1)
	_event(KEY_W,false);Input.action_release("move_forward");await _ticks(2)
	return {"start_door_distance_m":start_distance,"end_door_distance_m":car_service._door_distance_for(body),"actual_player_travel_m":scene.player.global_position.distance_to(before),"scope":"Physical W press plus maintained action input; ordinary retained capsule/camera-relative controller, no observer reposition during the actual door approach."}

func _exercise_car() -> void:
	var car: CharacterBody3D
	for attempt: int in range(70):
		for body: CharacterBody3D in car_service.traffic_cars:
			if body.is_physics_processing() and float(body._speed_mps)>1.2 and await _car_observer(body):car=body;break
		if is_instance_valid(car):break
		await _ticks(2)
	_check("staged_car_has_actual_original_moving_candidate",is_instance_valid(car))
	if not is_instance_valid(car):return
	var car_id:=car.get_instance_id();var shape_id: int=car.get_node("CollisionShape").shape.get_instance_id();var offenses: int=service.offense_count
	await _tap(KEY_E);var pending_onfoot: bool=car_service.pending_car==car and scene.player.is_physics_processing() and not scene.player.facility_control
	_check("physical_E_requests_braking_and_keeps_player_on_foot",pending_onfoot,{"stage":car_service.pending_stage})
	await _tap(KEY_E);await _ticks(3)
	_check("fresh_E_cancels_takeover_without_offense_or_replacement",not car_service.riding and not is_instance_valid(car_service.pending_car) and service.offense_count==offenses and car.get_instance_id()==car_id)
	var approached:=await _car_observer(car,true);await _tap(KEY_E)
	var stages: Array=[];var onfoot:=false;var saw_driver:=false;var captured_exit:=false;var captured_entry:=false;var door_walk: Dictionary={}
	var actions_before:=_count("melee_started");_event(KEY_F,true);_event(KEY_X,true);_event(KEY_G,true);_event(KEY_H,true)
	for tick: int in range(220):
		if not is_instance_valid(car_service.pending_car):break
		var stage: String=car_service.pending_stage
		if stage=="approach" and car_service._door_distance_for(car)>1.1 and door_walk.is_empty():door_walk=await _walk_to_door(car)
		if not stages.has(stage):stages.append(stage)
		onfoot=onfoot or (stage=="driver_exit" and scene.player.is_physics_processing() and not scene.player.facility_control)
		saw_driver=saw_driver or not car_service.drivers.is_empty()
		if stage=="driver_exit" and not captured_exit:await _capture_now("original_car_driver_exit");captured_exit=true
		if stage=="player_enter" and not captured_entry:await _capture_now("original_car_player_entry");captured_entry=true
		await _ticks(1)
	for code: int in [KEY_F,KEY_X,KEY_G,KEY_H]:_event(code,false)
	var mounted: bool=car_service.riding and not is_instance_valid(car_service.pending_car) and car_service.rental_index>=0
	_check("actual_stop_driver_exit_and_player_entry_precede_same_car_mount",approached and mounted and stages.has("driver_exit") and stages.has("player_enter") and onfoot and saw_driver,{"stages":stages,"snapshot":car_service.snapshot()})
	_check("physical_W_near_door_uses_original_player_capsule",not door_walk.is_empty() and door_walk.actual_player_travel_m>.05 and door_walk.end_door_distance_m<=1.1,{"door_walk":door_walk})
	_check("pending_takeover_rejects_attack_guard_and_horn",_count("melee_started")==actions_before and not _combat().get("guarding",true) and car_service.snapshot().horn_count==0)
	_check("staged_takeover_preserves_original_car_body_and_shape",car.get_instance_id()==car_id and car.get_node("CollisionShape").shape.get_instance_id()==shape_id and car_service.snapshot().original_identities_retained)
	if mounted:
		var horns: int=car_service.snapshot().horn_count;_event(KEY_H,true);await _ticks(3);_event(KEY_H,true,true);await _ticks(25)
		_check("physical_driving_H_horns_once_with_hold_echo_suppressed",car_service.snapshot().horn_count==horns+1,{"snapshot":car_service.snapshot()});_event(KEY_H,false)
		actions_before=_count("melee_started");await _tap(KEY_F);await _tap(KEY_X);_event(KEY_G,true);await _ticks(3)
		_check("adopted_driving_rejects_melee_and_guard",_count("melee_started")==actions_before and not _combat().get("guarding",true));_event(KEY_G,false)
		await _tap(KEY_E);await _ticks(35)
		_check("original_car_exit_restores_original_player_capsule",not car_service.riding and scene.player.is_physics_processing() and not scene.player.facility_control and _footprint()==initial_footprint)

func _run() -> void:
	source_hashes=_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/city-action-freedom-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8)
	service=scene.city_public_safety;car_service=scene.traffic_car_takeover
	_check("ordinary_production_services_ready",scene.runtime_ok and service.loaded and car_service.loaded,{"error":scene.exploration_error})
	if not scene.runtime_ok:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	scene.set_free_roam(true);scene.set_pedestrians_running(false)
	initial_footprint=_footprint();initial_city=_city_inventory()
	for body: CharacterBody3D in scene.pedestrians:original_people.append(body.get_instance_id())
	for controller: Node in [scene.street_pedestrians,scene.neighborhood_population.walkers]:
		for row: Dictionary in controller.actors:
			if row.kind=="walker":original_people.append(row.body.get_instance_id())
			else:original_dogs.append(row.body.get_instance_id())
	for body: CharacterBody3D in car_service.traffic_cars:original_cars.append(body.get_instance_id())
	var target: Dictionary={}
	for row: Dictionary in scene.street_pedestrians.actors:
		if row.kind=="walker" and await _place_near(row.body):target=row;break
	_check("source_supported_player_only_adult_observer",not target.is_empty())
	if target.is_empty():_finish();return
	# Face away for all motion/input-only tests; no extra offenses or actor edits.
	scene.player.get_node("Visual").rotation.y+=PI;await _ticks(4)
	await _exercise_action(KEY_F,"jab_left");await _exercise_action(KEY_F,"cross_right");await _exercise_action(KEY_F,"hook_left");await _exercise_action(KEY_X,"shove")
	await _ticks(30);var count:=_count("melee_started");_event(KEY_F,true);await _ticks(2);_event(KEY_F,true,true);_event(KEY_F,true);await _ticks(35)
	_check("physical_hold_echo_and_duplicate_down_cannot_repeat_combo",_count("melee_started")==count+1);_event(KEY_F,false)
	await _idle();_event(KEY_G,true);await _ticks(4)
	var guard:=_combat();count=_count("melee_started");await _tap(KEY_F);await _tap(KEY_X);await _ticks(5)
	_check("held_G_guard_is_visible_and_rejects_attack_edges",guard.get("guarding",false) and _combat().get("guarding",false) and _count("melee_started")==count,{"combat":_combat()});await _capture_now("held_guard")
	var guard_pose:=_pose();_check("held_G_actual_native_arms_follow_authored_guard",guard_pose.finite and guard_pose.source_axis_error<.001,{"pose":guard_pose})
	_event(KEY_G,false);await _ticks(3);_check("physical_G_release_clears_guard",not _combat().get("guarding",true))
	scene.toggle_menu();count=_count("melee_started");_event(KEY_F,true);_event(KEY_G,true);await _ticks(3);scene.toggle_menu();_event(KEY_F,true,true);_event(KEY_G,true,true);await _ticks(24)
	_check("menu_held_attack_guard_cannot_activate_after_resume",_count("melee_started")==count and not _combat().get("guarding",true));_event(KEY_F,false);_event(KEY_G,false)
	# A real static wall lies only between the supported original adult and
	# player. Re-evaluation occurs after windup, while the wall stays present.
	var near:=await _place_near(target.body);var wall:=StaticBody3D.new();wall.name="TestOnlyActionContactLOSBlocker";wall.collision_layer=1;var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2.,2.3,.08);collision.shape=box;wall.add_child(collision);scene.add_child(wall)
	var toward: Vector3=target.body.global_position-scene.player.global_position;toward.y=0.;wall.global_transform=Transform3D(Basis(Vector3.UP,atan2(-toward.x,-toward.z)),scene.player.global_position.lerp(target.body.global_position,.5)+Vector3.UP*1.15);await _ticks(2)
	var hits_before: int=service.hits;await _tap(KEY_F);await _idle()
	_check("actual_contact_rechecks_native_wall_and_does_not_hit",near and service.hits==hits_before,{"combat":_combat(),"events":service.events.slice(maxi(0,service.events.size()-4))});wall.queue_free();await _ticks(3)
	var target_ids: Array=[]
	for row: Dictionary in service._adult_candidates():target_ids.append(row.body.get_instance_id())
	_check("all_original_dogs_remain_outside_adult_contact_targets",original_dogs.size()==2 and not target_ids.has(original_dogs[0]) and not target_ids.has(original_dogs[1]))
	# Confirm delayed real contact and existing wanted integration last, then
	# let the actual police catch prove custody key gating and automatic release.
	near=await _place_near(target.body);hits_before=service.hits;await _tap(KEY_X)
	_check("physical_shove_does_not_hit_during_windup",near and service.hits==hits_before)
	await _idle();_check("physical_shove_contacts_original_adult_and_reports_police",service.hits==hits_before+1 and service.wanted,{"events":service.events.slice(maxi(0,service.events.size()-5))})
	var officer_near:=await _place_near(service.officers[0].body,1.15)
	for tick: int in range(120):
		if service.detained:break
		await _ticks(1)
	_check("actual_police_capture_enters_reversible_custody",officer_near and service.detained)
	if service.detained:
		count=_count("melee_started");_event(KEY_F,true);_event(KEY_X,true);_event(KEY_G,true);await _ticks(4)
		_check("custody_blocks_melee_and_guard",_count("melee_started")==count and not _combat().get("guarding",true))
		_event(KEY_F,false);_event(KEY_X,false);_event(KEY_G,false)
		await _ticks(400);_check("custody_release_restores_original_capsule_and_control",not service.detained and _footprint()==initial_footprint and scene.player.is_physics_processing() and not scene.player.facility_control)
	await _exercise_car()
	_check("all_source_building_footprints_and_original_actor_ids_retained",_city_inventory()==initial_city and car_service.snapshot().original_identities_retained and car_service.traffic_cars.size()==original_cars.size(),{"original_adults":original_people.size(),"original_dogs":original_dogs.size(),"original_cars":original_cars.size()})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true
	for code: int in [KEY_F,KEY_X,KEY_G,KEY_E,KEY_H,KEY_W]:_event(code,false)
	Input.action_release("move_forward")
	_check("runtime_source_bindings_stable",source_hashes==_hashes())
	var passed:=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(_json({"task":"EXP32_CITY_ACTION_FREEDOM","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"observations":observations,"captures":captures,"source_hashes":source_hashes,"display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"elapsed_ms":Time.get_ticks_msec()-started,"scope":"Production ordinary scene; physical keycode F/X/G/E/H edges device42, short taps/hold/echo/menu/custody, actual imported native bone directions and hand travel, delayed actual adult contact and police, original moving-car stop/driver exit/player entry and horn/ride ownership. Test-only supported player observer starts, original pedestrian pause option and named static LOS blocker are disclosed. No source actor transform replacement, no real OS input/performance or subjective realism claim."}),"  ")+"\n");file.close();print("CITY_ACTION_FREEDOM_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)
