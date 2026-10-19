extends SceneTree
## Production bicycle/controller verification. Only player observer starts and
## named blocking fixtures are placed; bike motion remains move_and_slide.
var scene: Node3D
var service: Node3D
var checks: Array=[]
var report_path:="/tmp/sim2seoul-city-bikes.json"
var started:=0
var _fixtures: Array[Node3D]=[]
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	for action: String in ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	Engine.max_fps=0;started=Time.get_ticks_msec();_run.call_deferred()
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
func _check(name: String,ok: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":name,"passed":ok,"evidence":_json(evidence)});print("BIKE_CHECK ",name," ",ok)
	if not ok:push_warning("BIKE_CHECK_FAIL "+name)
func _ticks(count: int) -> void:
	for index: int in range(count):await scene.rig.camera_stepped
func _key(action: String,pressed: bool) -> void:
	var event:=InputEventAction.new();event.action=action;event.pressed=pressed;event.device=42;Input.parse_input_event(event)
func _tap_e() -> void:
	_key("interact",true);await _ticks(3);_key("interact",false);await _ticks(4)
func _fixture(at: Vector3,size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();body.name="BikeTestBlocker";body.collision_layer=1;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;body.add_child(shape);scene.add_child(body);body.global_position=at;_fixtures.append(body);return body
func _clear_fixtures() -> void:
	for body: Node3D in _fixtures:body.queue_free()
	_fixtures.clear();await _ticks(3)
func _finish() -> void:
	var passed:=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var hashes: Dictionary={}
	for path: String in ["res://scripts/city_bike_service.gd","res://assets/authored/bike_service.json","res://scripts/explore_walk.gd","res://scripts/interior_visit.gd","res://../tests/game/check_city_bike_service.gd","res://resources/world_geometry/world.json","res://data/generated/public_walk.json","res://data/generated/terrain_surface.json"]:hashes[path]=FileAccess.get_sha256(path)
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(_json({"task":"city_bikes","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"snapshot":service.snapshot() if is_instance_valid(service) else {},"physics_hz":Engine.physics_ticks_per_second,"source_hashes":hashes,"elapsed_ms":Time.get_ticks_msec()-started,"scope":"Production native terrain, retained player capsule and actors, InputEventAction E/WASD/Space, physical bike moves/collision/support, real menu and validated cancel. Test-only player placements and blockers explicitly separate. Headless does not accept rendered appearance."}),"  "));file.close();print("BIKE_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)
func _run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/city-bike-test-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=60;root.add_child(scene);await _ticks(8)
	service=scene.get("city_bike_service")
	if not is_instance_valid(service):
		service=load("res://scripts/city_bike_service.gd").new();service.name="CityBikeServiceTest";scene.add_child(service);service.setup(scene)
	_check("production_setup_two_source_bound_native_docks",scene.runtime_ok and service.loaded and service.stations.size()==2 and service.bikes.size()==2,{"runtime_error":scene.exploration_error,"bike_error":service.load_error})
	if not scene.runtime_ok or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	_check("original30_people14_vehicles_and_native_capsule_preserved",scene.pedestrians.size()+scene.street_pedestrians.actors.size()+scene.neighborhood_population.walkers.actors.size()==30 and scene.vehicles.size()+scene.neighborhood_population.traffic.vehicles.size()==14)
	var view: Dictionary=service.viewpoint();_check("supported_clear_player_rental_start",not view.is_empty(),view)
	if view.is_empty():_finish();return
	scene.player.global_transform=Transform3D(Basis.IDENTITY,view.point);scene.player.require_neutral_input();scene.player.reset_physics_interpolation();await _ticks(8)
	var body: CharacterBody3D=service.bikes[0].body;var shape_id: int=scene.player.get_node("CollisionShape").shape.get_instance_id();var layer: int=scene.player.collision_layer;var mask: int=scene.player.collision_mask
	# A real blocking wall between observer and bike must defeat E rental.
	var middle: Vector3=scene.player.global_position.lerp(body.global_position,.5);_fixture(middle+Vector3.UP*.9,Vector3(.18,2.,1.8));await _ticks(3)
	var visible_before: bool=service.can_interact();await _tap_e();_check("native_wall_blocks_through_wall_E_rental",not visible_before and not service.riding)
	await _clear_fixtures();await _ticks(4);await _tap_e()
	_check("real_E_rents_retained_capsule_visible_rider_and_bus_lock",service.riding and not scene.player.is_physics_processing() and scene.player.facility_control and scene.exploration_avatar.visible and scene.player.collision_layer==layer and scene.player.collision_mask==mask and scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id and not scene.city_bus_service.can_interact(),{"prompt":service.prompt_text(),"events":service.events})
	if not service.riding:_finish();return
	var before: Vector3=body.global_position;var maximum_speed:=0.;var unsupported:=0;var maximum_step:=0.;var previous:=before
	_key("move_forward",true)
	for tick: int in range(180):
		await _ticks(1);maximum_speed=maxf(maximum_speed,service.speed_mps);maximum_step=maxf(maximum_step,body.global_position.distance_to(previous));previous=body.global_position
		if not body.is_on_floor():unsupported+=1
	_key("move_forward",false)
	_check("W_accelerates_real_bike_and_animates_wheels_pedals_on_terrain",body.global_position.distance_to(before)>3. and maximum_speed>2. and maximum_step<.12 and unsupported<4 and service._maximum_pedal_rotation>.4,{"travel_m":body.global_position.distance_to(before),"maximum_speed_mps":maximum_speed,"maximum_step_m":maximum_step,"unsupported_ticks":unsupported,"snapshot":service.snapshot()})
	var yaw_before: float=service.bikes[0].yaw;_key("move_right",true);await _ticks(18);_key("move_right",false);_key("move_left",true);await _ticks(18);_key("move_left",false)
	_check("AD_steers_real_heading_and_front_assembly",absf(service.bikes[0].yaw-yaw_before)>.025 and absf(service.steer_radians)>.01,{"before_yaw":yaw_before,"after_yaw":service.bikes[0].yaw,"steer":service.steer_radians})
	_key("jump",true);await _ticks(90);_key("jump",false);await _ticks(4)
	_check("Space_brakes_to_full_stop_without_player_jump",absf(service.speed_mps)<.02 and body.is_on_floor() and scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id)
	var frozen: Transform3D=body.global_transform;var clock: float=service._clock;scene.toggle_menu()
	for frame: int in range(18):await process_frame
	_check("actual_menu_freezes_bike_clock_rider_and_pose",body.global_transform==frozen and service._clock==clock and paused)
	scene.toggle_menu();await _ticks(5)
	# All supported dismount candidates are deliberately blocked by real boxes.
	for offset: Vector3 in [Vector3(.95,0,.1),Vector3(-.95,0,.1),Vector3(.95,0,1.05),Vector3(-.95,0,1.05),Vector3(0,0,1.65)]:
		var at: Vector3=body.global_position+body.global_basis*offset;at.y=scene.terrain_surface.ground_y_world(at)+1.;_fixture(at,Vector3(.8,2.,.8))
	await _ticks(4);await _tap_e();await _ticks(20)
	_check("blocked_native_dismount_keeps_rider_attached_and_capsule_safe",service.riding and service.exit_requested and not scene.player.is_physics_processing() and service.blocked_reason=="dismount_blocked")
	await _tap_e();_check("blocked_dismount_request_can_cancel_to_continue",service.riding and not service.exit_requested)
	await _clear_fixtures();await _tap_e();await _ticks(12)
	_check("safe_E_dismount_restores_original_player_control_and_masks",not service.riding and scene.player.is_physics_processing() and not scene.player.facility_control and scene.player.collision_layer==layer and scene.player.collision_mask==mask and scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id)
	if service.rental_index<0:
		_check("ride_travel_left_first_dock_for_temporary_stop",false);_finish();return
	await _ticks(5);await _tap_e();_check("temporary_parked_bike_E_remounts",service.riding)
	if not service.riding:_finish();return
	var reverse_start: Vector3=body.global_position;_key("move_backward",true);await _ticks(100);_key("move_backward",false)
	_check("S_brakes_then_backs_out_at_bounded_low_speed",service.speed_mps<-.5 and absf(service.speed_mps)<=1.11 and body.global_position.distance_to(reverse_start)>.3,{"speed":service.speed_mps,"travel":body.global_position.distance_to(reverse_start)})
	_key("jump",true);await _ticks(30);_key("jump",false);await _ticks(4)
	# Commit a validated external destination first, then cancel exactly once.
	var safe: Dictionary=scene.interior_visit._safe_external_point(service.stations[0].point+Vector3(0,0,2.2))
	if safe.is_empty():safe=scene.interior_visit._safe_external_point(view.point)
	_check("external_cancel_fixture_has_positive_support",not safe.is_empty())
	if not safe.is_empty():
		scene.player.global_transform=Transform3D(Basis.IDENTITY,safe.point);service.cancel_ride_for_teleport();await _ticks(6)
		_check("validated_external_teleport_restores_and_does_not_reattach",not service.riding and scene.player.global_position.distance_to(safe.point)<.15 and scene.player.is_physics_processing() and not scene.player.facility_control and scene.player.collision_mask==mask and not scene.player.get_collision_exceptions().has(body))
	# Boundary checks on actual retained source geometry, including private rings.
	var rejected:=0
	for polygon: Array in scene.city.private_cache:
		if polygon.is_empty():continue
		var center:=Vector2.ZERO
		for point: Vector2 in polygon[0]:center+=point
		center/=maxi(1,polygon[0].size())
		if scene.city._contains(center,[polygon]) and not service._source_allowed(scene.city.to_global(Vector3(center.x,0,center.y))):rejected+=1
	_check("retained_private_source_exclusions_reject_riding_footprint",rejected>10,{"private_interiors_rejected":rejected})
	_finish()
