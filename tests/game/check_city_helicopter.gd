extends SceneTree
## Ordinary E and production aircraft physics. Explicit test-only observer,
## near-ceiling and near-boundary placements and blockers are labelled below.
class HeldInput extends Node:
	var harness: SceneTree
	func _physics_process(_delta: float) -> void:harness._refresh_inputs()
var scene: Node3D
var service: Node3D
var checks: Array[Dictionary]=[]
var captures: Array[Dictionary]=[]
var held: Dictionary={}
var report_path:="/tmp/sim2seoul-helicopter.json"
var finished:=false
var started:=0
var maximum_idle_step_m:=0.0
var _loaded_hashes: Dictionary={}
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	for action: String in ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	var fixture:=HeldInput.new();fixture.name="TestOnlyHeldFlightInput";fixture.harness=self;fixture.process_physics_priority=-200;fixture.process_mode=Node.PROCESS_MODE_ALWAYS;root.add_child(fixture)
	started=Time.get_ticks_msec();create_timer(480.,true,false,true).timeout.connect(func()->void:
		if not finished:_check("bounded_timeout",false);_finish()
	);_run.call_deferred()
func _refresh_inputs() -> void:
	for action: StringName in held:Input.action_press(action)
func _key(action: StringName,down: bool) -> void:
	if down:held[action]=true
	else:held.erase(action);Input.action_release(action)
func _e(down: bool) -> void:
	var event:=InputEventKey.new();event.keycode=KEY_E;event.physical_keycode=KEY_E;event.device=0;event.pressed=down;Input.parse_input_event(event)
func _tap_e() -> void:_e(true);await _ticks(3);_e(false);await _ticks(5)
func _ticks(count: int) -> void:
	for tick: int in range(count):await scene.rig.camera_stepped
func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Transform3D:return {"origin":_json(value.origin),"basis":[_json(value.basis.x),_json(value.basis.y),_json(value.basis.z)]}
	if value is Dictionary:
		var out: Dictionary={}
		for key: Variant in value:out[str(key)]=_json(value[key])
		return out
	if value is Array:
		var out: Array=[]
		for item: Variant in value:out.append(_json(item))
		return out
	if value is float:return value if is_finite(value) else null
	return value
func _hashes() -> Dictionary:
	var result: Dictionary={}
	for path: String in ["res://scripts/city_helicopter_service.gd","res://assets/authored/helicopter_service.json","res://../tests/game/check_city_helicopter.gd","res://scripts/explore_walk.gd","res://scripts/interior_visit.gd","res://resources/world_geometry/world.json","res://data/generated/public_walk.json","res://data/generated/terrain_surface.json"]:result[path]=FileAccess.get_sha256(path)
	return result
func _check(title: String,ok: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":ok,"evidence":_json(evidence)});print("HELICOPTER_CHECK ",title," ",ok)
func _capture(title: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();var path:=report_path.get_basename()+"_"+title+".png";var error:=image.save_png(path)
	_check("native_capture_"+title,error==OK)
	if error==OK:captures.append({"file":path,"sha256":FileAccess.get_sha256(path),"camera":scene.rig.snapshot(),"aircraft":service.snapshot(),"scope":"Actual production destination or flight camera, no diagnostic camera override. Image opening/review is still required."})
func _fixture(at: Vector3,size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();body.name="TestOnlyFlightBlocker";body.collision_layer=1;var node:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;node.shape=box;body.add_child(node);scene.add_child(body);body.global_position=at;return body
func _place_observer() -> bool:
	var view: Dictionary=service.viewpoint()
	if view.is_empty():return false
	scene._commit_exploration_teleport(view.point);scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation()
	scene.rig.yaw=view.camera_yaw;scene.rig.pitch=deg_to_rad(view.camera_pitch_degrees);scene.rig.requested_distance=view.camera_distance_m;scene.rig.current_distance=view.camera_distance_m;scene.rig.snap_to_target_pose();return true
func _finish() -> void:
	if finished:return
	finished=true
	var hashes:=_hashes();_check("source_inputs_stable_during_runtime",hashes==_loaded_hashes,{"loaded":_loaded_hashes,"finished":hashes})
	var passed:=checks.filter(func(row: Dictionary)->bool:return row.passed).size()
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Could not write helicopter report");quit(2);return
	file.store_string(JSON.stringify(_json({"task":"authored_city_helicopter","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"captures":captures,"snapshot":service.snapshot() if is_instance_valid(service) else {},"source_hashes":hashes,"physics_hz":Engine.physics_ticks_per_second,"elapsed_ms":Time.get_ticks_msec()-started,"scope":"Native aircraft shapes including full rotor, existing source terrain, physical KEY_E and labelled held movement fixture. Actual takeoff, movement, rotation, same-ground return, landing and walking restoration. Near-ceiling/boundary aircraft placements and static blockers are test fixtures, not ordinary travel. No actual aviation accuracy/permission, sustained performance or subjective/native appearance acceptance from headless."}),"  "));file.close();print("HELICOPTER_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)
func _run() -> void:
	_loaded_hashes=_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/helicopter-test-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";root.add_child(scene);await _ticks(8)
	service=scene.get("city_helicopter_service")
	if not is_instance_valid(service):service=load("res://scripts/city_helicopter_service.gd").new();service.name="CityHelicopterServiceTest";scene.set("city_helicopter_service",service);scene.add_child(service);service.setup(scene)
	_check("production_setup_original_source_grass_and_native_terrain",scene.runtime_ok and service.loaded,{"error":service.load_error,"site_audit":service.site_audit})
	if not scene.runtime_ok or not service.loaded:_finish();return
	_check("source_actors_and_native_player_shape_preserved",scene.pedestrians.size()+scene.street_pedestrians.actors.size()+scene.neighborhood_population.walkers.actors.size()==30 and scene.vehicles.size()+scene.neighborhood_population.traffic.vehicles.size()==14)
	_check("full_rotor_has_native_cylinder_not_cabin_only_collision",service.body.get_node("FullRotorDiscCollision").shape is CylinderShape3D and service.body.get_node("FullRotorDiscCollision").shape.radius>=4.0)
	if scene.menu.visible:scene.toggle_menu()
	_check("supported_ordinary_observer_destination",_place_observer())
	await _ticks(8);_check("landed_aircraft_accepts_E_target",service._landed() and service.can_interact(),{"snapshot":service.snapshot(),"player":scene.player.global_position})
	await _capture("helipad_before_boarding")
	var shape_id: int=scene.player.get_node("CollisionShape").shape.get_instance_id();var layer: int=scene.player.collision_layer;var mask: int=scene.player.collision_mask;var rig_pivot: float=scene.rig.pivot_height_m;var rig_max: float=scene.rig.distance_max_m
	scene.toggle_menu();_e(true)
	for frame: int in range(3):await process_frame
	scene.toggle_menu();await _ticks(5);_check("E_held_through_menu_never_boards",not service.riding);_e(false);await _tap_e()
	_check("physical_E_boards_once_and_retains_capsule_with_other_transport_mutex",service.riding and not scene.player.is_physics_processing() and scene.player.facility_control and scene.player.collision_layer==layer and scene.player.collision_mask==mask and scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id and not scene.city_bike_service.can_interact() and not scene.city_scooter_service.can_interact() and not scene.city_bus_service.can_interact(),{"events":service.events})
	if not service.riding:_finish();return
	await _ticks(65);_check("rotor_spins_up_before_flight",service.rotor_fraction>.99 and service.rotor_phase!=0.)
	var home: Vector3=service.body.global_position
	_key(service.ASCEND,true);await _ticks(65);_key(service.ASCEND,false);await _ticks(16)
	_check("Space_takes_off_physically_above_2m",service.body.global_position.y-home.y>2. and not service._landed(),{"rise_m":service.body.global_position.y-home.y,"snapshot":service.snapshot()})
	await _capture("airborne")
	await _tap_e();_check("airborne_E_is_consumed_with_reason_and_never_ejects",service.riding and not service.exit_requested and service.events.any(func(row: Dictionary)->bool:return row.event=="airborne_exit_rejected") and service.prompt_text().contains("공중"))
	var held_menu_before: Vector3=service.body.global_position;scene.toggle_menu();_key("move_forward",true)
	for frame: int in range(4):await process_frame
	scene.toggle_menu();await _ticks(8)
	_check("held_movement_after_menu_requires_release_before_flying",service.body.global_position.distance_to(held_menu_before)<.02 and scene.player.input_latched)
	_key("move_forward",false);await _ticks(3)
	var before: Vector3=service.body.global_position;_key("move_forward",true);await _ticks(60);_key("move_forward",false);await _ticks(42)
	_check("W_moves_actual_aircraft_and_attached_player",Vector2(service.body.global_position.x-before.x,service.body.global_position.z-before.z).length()>2. and scene.player.global_position.distance_to(service.body.to_global(Vector3(.40,.90,-.70)))<.02,{"travel_m":service.body.global_position.distance_to(before),"maximum_step_m":service.maximum_step_m})
	var yaw_before: float=service._yaw;_key("move_left",true);await _ticks(20);_key("move_left",false)
	_check("A_rotates_aircraft_with_native_rotor_envelope",absf(service._yaw-yaw_before)>.2)
	_key("move_right",true);await _ticks(20);_key("move_right",false);await _ticks(3)
	_key("move_backward",true)
	for tick: int in range(300):
		await _ticks(1)
		if Vector2(service.body.global_position.x-home.x,service.body.global_position.z-home.z).length()<2.7:break
	_key("move_backward",false);await _ticks(40)
	_check("physical_reverse_returns_over_same_helipad",Vector2(service.body.global_position.x-home.x,service.body.global_position.z-home.z).length()<1.5,{"position":service.body.global_position,"home":home})
	_key(service.DESCEND,true)
	for tick: int in range(300):
		await _ticks(1)
		if service._landed():break
	_key(service.DESCEND,false);await _ticks(10)
	_check("Ctrl_lands_on_original_ground_with_all_skid_support",service._landed() and service.body.is_on_floor(),{"snapshot":service.snapshot()})
	await _capture("landed")
	await _tap_e();await _ticks(55)
	_check("landed_E_stops_rotor_and_restores_walking_capsule_camera",not service.riding and service.rotor_fraction<.01 and service._release.is_empty() and scene.player.is_physics_processing() and not scene.player.facility_control and scene.player.collision_layer==layer and scene.player.collision_mask==mask and scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id and is_equal_approx(scene.rig.pivot_height_m,rig_pivot) and is_equal_approx(scene.rig.distance_max_m,rig_max),{"snapshot":service.snapshot()})
	var walk_before: Vector3=scene.player.global_position;await _ticks(4);_key("move_forward",true);await _ticks(10);_key("move_forward",false);await _ticks(3)
	_check("walking_input_moves_player_after_helicopter_exit",scene.player.global_position.distance_to(walk_before)>.3)
	_place_observer();await _ticks(5);await _tap_e();await _ticks(65);_key(service.ASCEND,true);await _ticks(55);_key(service.ASCEND,false);await _ticks(15)
	_check("same_aircraft_can_be_boarded_and_flown_again",service.riding and not service._landed())
	# This beam intersects only the full main-rotor height, beyond the cabin.
	var obstacle:=_fixture(service.body.to_global(Vector3(0,2.95,-4.4)),Vector3(.25,.6,.25));await _ticks(3)
	before=service.body.global_position;_key("move_forward",true);await _ticks(45);_key("move_forward",false);await _ticks(10)
	_check("rotor_tip_beam_blocks_native_forward_motion_before_cabin",service.body.global_position.distance_to(before)<.55 and service.blocked_reason in ["native_aircraft_sweep","native_aircraft_contact","rotation_occupied"],{"travel_m":service.body.global_position.distance_to(before),"reason":service.blocked_reason})
	obstacle.queue_free();await _ticks(3)
	# These narrow beams touch only a horizontal tailplane tip or the high
	# vertical fin, outside the old cabin/boom/rotor collider envelopes.
	var tail_tip:=_fixture(service.body.to_global(Vector3(.80,1.43,3.75)),Vector3(.12,.16,.20));await _ticks(3)
	_check("horizontal_tailplane_tip_has_native_collision",not service._volume_clear(service.body.global_position,service._yaw),{"fixture_local_center":[.80,1.43,3.75]})
	tail_tip.queue_free();await _ticks(3)
	var fin:=_fixture(service.body.to_global(Vector3(0,2.53,4.40)),Vector3(.13,.12,.20));await _ticks(3)
	_check("high_vertical_tail_fin_has_native_collision",not service._volume_clear(service.body.global_position,service._yaw),{"fixture_local_center":[0,2.53,4.40]})
	fin.queue_free();await _ticks(3)
	# Explicit fixture places the aircraft near the configured ceiling. It is
	# separate from the ordinary physical takeoff/return/landing above.
	var ground_y: float=scene.terrain_surface.ground_y_world(service.body.global_position);service.body.global_position.y=ground_y+119.6;service.vertical_speed_mps=0.;service.speed_mps=0.;service.body.velocity=Vector3.ZERO
	_key(service.ASCEND,true);await _ticks(45);_key(service.ASCEND,false);await _ticks(10)
	_check("near_ceiling_fixture_cannot_exceed_configured_altitude",service.body.global_position.y-ground_y<=120.02 and service.body.global_position.y-ground_y>=119.9,{"altitude_m":service.body.global_position.y-ground_y,"fixture":"Aircraft starts 0.4m below configured ceiling; controller performs the actual final rise and stops."})
	var lower_direction:=Vector3.FORWARD;var lower_ground:=INF
	for direction: Vector3 in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT]:
		var height: float=scene.terrain_surface.ground_y_world(service.body.global_position+direction*2.)
		if height<lower_ground:lower_ground=height;lower_direction=direction
	service._yaw=atan2(-lower_direction.x,-lower_direction.z);service.body.global_rotation.y=service._yaw;service.speed_mps=0.
	var maximum_agl:=0.;_key("move_forward",true)
	for tick: int in range(25):
		await _ticks(1);maximum_agl=maxf(maximum_agl,service.body.global_position.y-scene.terrain_surface.ground_y_world(service.body.global_position))
	_key("move_forward",false);await _ticks(3)
	_check("ceiling_guard_also_rejects_horizontal_entry_over_lower_terrain",maximum_agl<=120.02,{"maximum_altitude_above_terrain_m":maximum_agl,"lower_direction":lower_direction})
	var valid: Vector3=service.helipad.point;var invalid:=Vector3(scene.player.free_roam_bounds.end.x+20.,valid.y,valid.z)
	for step: int in range(30):
		var middle: Vector3=valid.lerp(invalid,.5)
		if service._flight_bounds_valid(middle):valid=middle
		else:invalid=middle
	valid.y=scene.terrain_surface.ground_y_world(valid)+110.;service.body.global_transform=Transform3D(Basis(Vector3.UP,-PI*.5),valid);service._yaw=-PI*.5;service.speed_mps=0.;service.vertical_speed_mps=0.;service.body.velocity=Vector3.ZERO
	before=service.body.global_position;_key("move_forward",true);await _ticks(45);_key("move_forward",false);await _ticks(5)
	_check("near_boundary_fixture_stops_entire_rotor_before_leaving_region",service._flight_bounds_valid(service.body.global_position) and service.body.global_position.distance_to(before)<.25 and service.blocked_reason=="flight_boundary",{"distance_m":service.body.global_position.distance_to(before),"position":service.body.global_position,"fixture":"Bisection picks a protected-radius boundary start; actual W input attempts to leave."})
	scene.toggle_menu();var frozen: Transform3D=service.body.global_transform;var clock: float=service._clock;var rotor_phase: float=service.rotor_phase
	for frame: int in range(12):await process_frame
	_check("menu_freezes_aircraft_rotor_and_flight_clock",service.body.global_transform==frozen and service._clock==clock and service.rotor_phase==rotor_phase)
	scene._visit_street_detail("helipad");await _ticks(25)
	var to_home: Vector3=service.helipad.point-scene.player.global_position;to_home.y=0.
	var expected_yaw:=atan2(-to_home.x,-to_home.z)+.5
	_check("airborne_helipad_shortcut_observer_and_camera_face_recovered_home",not service.riding and not service.return_pending and service._landed() and absf(wrapf(scene.rig.yaw-expected_yaw,-PI,PI))<.05 and scene.player.global_position.distance_to(service.helipad.point)<3.8,{"actual_yaw":scene.rig.yaw,"expected_yaw":expected_yaw,"player":scene.player.global_position,"home":service.helipad.point})
	await _tap_e();await _ticks(65);_key(service.ASCEND,true);await _ticks(45);_key(service.ASCEND,false);await _ticks(15);scene.toggle_menu();scene._visit_library_entrance();await _ticks(25)
	_check("airborne_library_shortcut_restores_player_and_recovers_clear_pad",not service.riding and not service.return_pending and service.rotor_fraction<.01 and scene.player.is_physics_processing() and not scene.player.facility_control and service._landed() and service._release.is_empty(),{"snapshot":service.snapshot()})
	_place_observer();await _ticks(5);await _tap_e();await _ticks(65);_key(service.ASCEND,true);await _ticks(55);_key(service.ASCEND,false);await _ticks(15)
	var occupied:=_fixture(service.helipad.point+Vector3.UP,Vector3(.5,2.,.5));await _ticks(3)
	scene.toggle_menu();scene._visit_library_entrance();await _ticks(25)
	_check("occupied_home_pad_defers_recovery_without_crash_or_player_reattach",not service.riding and service.return_pending and service.rotor_fraction>.9 and scene.player.is_physics_processing() and not scene.player.facility_control,{"snapshot":service.snapshot()})
	occupied.queue_free();await _ticks(30)
	_check("clear_home_pad_finishes_safe_recovery_and_allows_rental_again",not service.return_pending and service.rotor_fraction<.01 and service._landed() and service._release.is_empty())
	_place_observer();await _ticks(6);_check("recovered_aircraft_remains_available",service.can_interact())
	_finish()
