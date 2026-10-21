extends "res://../tests/game/check_drivable_car.gd"
## The full production scene, native travel and unmodified render callbacks.
## Source-certified starting placements are explicit fixtures, not travel proof.
class RenderObserver extends Node:
	var harness: SceneTree
	func _physics_process(_delta: float) -> void:harness._observe_physics()
	func _process(_delta: float) -> void:harness._observe_render()
var observations: Array=[]
var observer: RenderObserver
var observed_body: Node3D
var observed_visual: Node3D
var visual_is_parent_anchor:=false
var measuring:=false
var previous_body:=Transform3D.IDENTITY
var current_body:=Transform3D.IDENTITY
var previous_avatar:=Transform3D.IDENTITY
var current_avatar:=Transform3D.IDENTITY
var samples: Array=[]
var fraction_bins: Dictionary={}
var maximum_avatar_error:=0.0
var maximum_vehicle_error:=0.0
var maximum_camera_error:=0.0
var maximum_physics_step:=0.0
var measured_distance:=0.0
var visible_avatar:=true
var measure_name:=""
var snap_start:=0
var initial_controls: Dictionary={}
var initial_capsule:=0
var source_actor_ids: Dictionary={}

func _initialize() -> void:
	super._initialize();Engine.max_fps=120
	observer=RenderObserver.new();observer.name="TestOnlyAfterProductionRenderObserver";observer.harness=self;observer.process_physics_priority=4;observer.process_priority=1000;root.add_child(observer)

func _ticks(count: int) -> void:
	for index: int in range(count):await physics_frame

func _input_hashes() -> Dictionary:
	var result:=super._input_hashes()
	for path: String in ["res://scripts/player/exploration_camera.gd","res://scripts/player/camera_rig.gd","res://scripts/city_subway_service.gd","res://scripts/city_scooter_service.gd","res://scripts/city_helicopter_service.gd","res://scripts/city_helicopter_rope.gd","res://scripts/city_bus_service.gd","res://scripts/traffic/vehicle.gd","res://../tests/game/check_transport_camera_stability.gd"]:result[path]=FileAccess.get_sha256(path)
	return result

func _observe_physics() -> void:
	if not measuring:return
	previous_body=current_body;current_body=observed_body.global_transform
	previous_avatar=current_avatar;current_avatar=scene.exploration_avatar.global_transform
	var step: float=previous_body.origin.distance_to(current_body.origin)
	maximum_physics_step=maxf(maximum_physics_step,step);measured_distance+=step

func _observe_render() -> void:
	if not measuring or not scene.rig._pose_ready:return
	var fraction: float=scene.rig._render_fraction
	var expected_body: Transform3D=previous_body.interpolate_with(current_body,fraction)
	var actual_body: Transform3D=observed_visual.global_transform
	if visual_is_parent_anchor:actual_body=actual_body*observed_visual.transform.affine_inverse()
	var vehicle_error: float=actual_body.origin.distance_to(expected_body.origin)
	var avatar_error: float=scene.rig._avatar_proxy.global_position.distance_to(previous_avatar.interpolate_with(current_avatar,fraction).origin)
	var camera_error: float=scene.rig.camera.global_position.distance_to(scene.rig._render_pose(fraction).origin)
	# Motion-only samples expose the sawtooth: at a fixed physical position
	# every interpolation policy would trivially pass.
	if previous_body.origin.distance_to(current_body.origin)>.002:
		fraction_bins[int(floor(fraction*4.))]=true
		maximum_vehicle_error=maxf(maximum_vehicle_error,vehicle_error);maximum_avatar_error=maxf(maximum_avatar_error,avatar_error);maximum_camera_error=maxf(maximum_camera_error,camera_error)
		if samples.size()<24:samples.append({"fraction":fraction,"vehicle_error_m":vehicle_error,"avatar_error_m":avatar_error,"camera_error_m":camera_error,"physics_step_m":previous_body.origin.distance_to(current_body.origin),"actual_body":actual_body.origin,"actual_avatar":scene.rig._avatar_proxy.global_position})

func _start_measure(label: String,body: Node3D,visual: Node3D,parent_anchor:=false,avatar_is_visible:=true) -> void:
	measure_name=label;observed_body=body;observed_visual=visual;visual_is_parent_anchor=parent_anchor;visible_avatar=avatar_is_visible
	previous_body=body.global_transform;current_body=previous_body;previous_avatar=scene.exploration_avatar.global_transform;current_avatar=previous_avatar
	samples.clear();fraction_bins.clear();maximum_avatar_error=0.;maximum_vehicle_error=0.;maximum_camera_error=0.;maximum_physics_step=0.;measured_distance=0.;snap_start=scene.rig.transition_snaps;measuring=true

func _end_measure() -> Dictionary:
	measuring=false
	var row: Dictionary={"transport":measure_name,"moving_render_samples_first24":samples.duplicate(true),"distinct_fraction_quartiles":fraction_bins.keys(),"maximum_avatar_render_error_m":maximum_avatar_error,"maximum_vehicle_render_error_m":maximum_vehicle_error,"maximum_camera_publication_error_m":maximum_camera_error,"maximum_native_physics_step_m":maximum_physics_step,"actual_native_travel_m":measured_distance,"transition_snap_delta":scene.rig.transition_snaps-snap_start,"avatar_visible":visible_avatar,"scope":"Observer runs after real production render callbacks; physics at 30Hz, render capped at 120Hz. No manual render fraction or body write during the measured interval."}
	observations.append(row)
	_check(measure_name+"_moving_frames_cover_multiple_render_fractions",fraction_bins.size()>=3 and measured_distance>1.0,row)
	_check(measure_name+"_vehicle_and_camera_publish_same_clock",maximum_vehicle_error<.005 and maximum_camera_error<.005,row)
	if visible_avatar:_check(measure_name+"_visible_rider_shares_camera_and_vehicle_clock",maximum_avatar_error<.005,row)
	_check(measure_name+"_continuous_native_travel_does_not_snap_camera",int(row.transition_snap_delta)==0,row)
	return row

func _controls_exact() -> bool:
	return scene.player.collision_layer==initial_controls.layer and scene.player.collision_mask==initial_controls.mask and scene.rig._query.exclude==initial_controls.exclude and scene.player.get_node("CollisionShape").shape.get_instance_id()==initial_capsule and scene.player.is_physics_processing() and not scene.player.facility_control

func _source_road_ride(ride: Node3D) -> void:
	service=ride
	var kind: String=ride._motion_kind();var row: Dictionary=ride.bikes[0];var body: CharacterBody3D=row.body
	var a:=Vector3(95.56,0.,-350.);var direction:=Vector3(1.23,0.,-100.).normalized();var yaw:=atan2(-direction.x,-direction.z);var support: Dictionary=ride._ground(a)
	_check(kind+"_source_start_has_native_support",not support.is_empty(),{"fixture":"Only initial bike/player position on original Sejong-daero w378453707; native actors and source meshes remain."})
	if support.is_empty():return
	a.y=support.point.y+.015;body.global_transform=Transform3D(ride._pose_basis(a,yaw),a);body.velocity=Vector3.ZERO;body.reset_physics_interpolation();row.yaw=yaw;row.previous=body.global_transform;row.current=row.previous;row.proxy.global_transform=row.current
	var outside: Dictionary=scene.interior_visit._safe_external_point(a+Vector3(2.8,0.,0.))
	if outside.is_empty():_check(kind+"_fixture_observer_safe",false);return
	scene.player.global_transform=Transform3D(Basis.IDENTITY,outside.point);scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();await _ticks(5)
	var mounted: bool=ride._mount(0);_check(kind+"_production_mount_retains_native_capsule",mounted and scene.player.get_node("CollisionShape").shape.get_instance_id()==initial_capsule)
	if not mounted:return
	await _ticks(5);_key("move_forward",true);await _ticks(10)
	_start_measure(kind,body,row.proxy);await _ticks(45);_end_measure();_key("move_forward",false)
	_key("jump",true);await _ticks(45);_key("jump",false);await _ticks(3)
	var frozen: Transform3D=row.proxy.global_transform;var camera: Transform3D=scene.rig.camera.global_transform
	scene.toggle_menu();await create_timer(.15,true,false,true).timeout
	_check(kind+"_menu_freezes_rendered_vehicle_and_eye",row.proxy.global_transform==frozen and scene.rig.camera.global_transform==camera)
	scene.toggle_menu();await _ticks(4)
	# Actual E dismount, not an external teleport, verifies attachment release.
	await _tap_e(0);await _ticks(7)
	_check(kind+"_E_alights_and_restores_capsule_camera_controls",not ride.riding and _controls_exact(),{"pending":ride._collision_release_pending.size()})
	if ride.riding:scene._visit_library_entrance();await _ticks(6)

func _metro_ride() -> void:
	var metro: Node3D=scene.city_subway_service
	scene._visit_street_detail("subway_cityhall");await _ticks(8);await _tap_e(0)
	_check("subway_physical_E_enters_original_source_entrance",metro.active and not metro.riding)
	if not metro.active:return
	# Platform start shortens previously covered 25m stair walking. The train
	# completes its own native schedule; no train/clock/route fixture is used.
	metro.stations[0].gate_open=true;metro._update_doors();scene.player.global_position=metro.stations[0].wait;scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();await _ticks(6)
	for index in range(3000):
		if metro.docked_station==0 and metro.train_state=="doors_open" and metro.door_fraction>.99:break
		await _ticks(1)
	await _tap_e(0);_check("subway_physical_E_boards_native_train",metro.riding)
	if not metro.riding:return
	for index in range(1800):
		if metro.train_state=="moving" and metro.speed_mps>3.:break
		await _ticks(1)
	var floor_mesh: Node3D=metro.train.find_child("CabinFloor",true,false)
	_start_measure("subway",metro.train,floor_mesh,true);await _ticks(60);_end_measure()
	var before: Transform3D=floor_mesh.global_transform;var camera: Transform3D=scene.rig.camera.global_transform;var clock: float=metro.state_elapsed
	scene.toggle_menu();await create_timer(.15,true,false,true).timeout
	_check("subway_menu_freezes_rendered_train_eye_and_clock",floor_mesh.global_transform==before and scene.rig.camera.global_transform==camera and metro.state_elapsed==clock)
	scene.toggle_menu();await _ticks(4)
	for index in range(3000):
		if metro.train_state=="doors_open" and metro.docked_station==1:break
		await _ticks(1)
	await _tap_e(0);await _ticks(7)
	_check("subway_actual_other_station_alight_restores_controller",metro.active and not metro.riding and metro.visit_station==1 and not metro._release_pending and _controls_exact())
	scene._visit_library_entrance();await _ticks(7);_check("subway_validated_shortcut_restores_exterior",not metro.active and not scene.player.interior_active and _controls_exact())

func _high_speed_helicopter() -> void:
	var heli: Node3D=scene.city_helicopter_service
	scene._visit_street_detail("helipad");await _ticks(8);await _tap_e(0);await _ticks(62)
	_check("helicopter_physical_E_boards_for_high_speed_camera_regression",heli.riding)
	if not heli.riding:return
	# One explicit clear-air starting fixture avoids a 150m roof climb in a
	# camera regression. All measured travel uses the unchanged native flight.
	var fixture: Dictionary=_clear_flight_start(heli)
	_check("helicopter_fixture_full_envelope_has_180m_inside_original_flight_bounds",not fixture.is_empty(),fixture)
	if fixture.is_empty():scene._visit_library_entrance();await _ticks(6);return
	heli._yaw=fixture.yaw;heli.body.global_transform=Transform3D(Basis(Vector3.UP,float(fixture.yaw)),fixture.point);heli.body.velocity=Vector3.ZERO;heli.speed_mps=0.;heli.vertical_speed_mps=0.;heli._previous=heli.body.global_transform;heli._current=heli._previous;heli._proxy.global_transform=heli._current;heli._attach_player(0.);scene.rig.yaw=float(fixture.yaw)+.45;scene.rig.snap_to_target_pose();await _ticks(4)
	_key("move_forward",true);await _ticks(48)
	_start_measure("helicopter_high_speed",heli.body,heli._proxy,false,false);await _ticks(18);var row:=_end_measure();_key("move_forward",false)
	_check("helicopter_legit_native_step_exceeds_old_2m_teleport_threshold",float(row.maximum_native_physics_step_m)>2.0,{"step_m":row.maximum_native_physics_step_m,"fixture":fixture,"native_speed_policy":heli.motion_policy(),"blocked_reason":heli.blocked_reason})
	scene._visit_library_entrance();await _ticks(8);_check("helicopter_external_transition_restores_exact_controls",not heli.riding and _controls_exact())

func _clear_flight_start(heli: Node3D) -> Dictionary:
	var bounds: Rect2=scene.player.free_roam_bounds.grow(-16.)
	for x in range(int(bounds.position.x)+10,int(bounds.end.x)-10,40):
		for z in range(int(bounds.position.y)+10,int(bounds.end.y)-10,40):
			for direction: Vector3 in [Vector3.FORWARD,Vector3.BACK,Vector3.RIGHT,Vector3.LEFT]:
				var start:=Vector3(float(x),165.,float(z));var yaw:=atan2(-direction.x,-direction.z);var safe:=true
				for step in range(19):
					var point: Vector3=start+direction*float(step)*10.
					var ground: float=scene.terrain_surface.ground_y_world(point)
					if not heli._flight_bounds_valid(point) or not is_finite(ground) or point.y>ground+float(heli.design.policy.maximum_altitude_above_terrain_m)-1. or not heli._volume_clear(point,yaw):safe=false;break
				if safe:return {"point":start,"yaw":yaw,"direction":direction,"sample_spacing_m":10.,"certified_straight_length_m":180.,"scope":"Single labelled clear-air initial fixture within original flight polygon and native full envelope. Actual measured flight controller unchanged."}
	return {}

func _bus_ride() -> void:
	var buses: Node3D=scene.city_bus_service;var body: CharacterBody3D=buses.buses[2]
	for tick in range(1800):
		buses._switch_bus(body)
		if buses.bus_state=="doors_open":break
		await _ticks(1)
	_check("bus_natural_scheduled_dock_available_without_bus_pose_fixture",buses.bus_state=="doors_open")
	if buses.bus_state!="doors_open":return
	buses.set_running(false)
	var door: Vector3=body.to_global(Vector3(1.6,0.,.55));door.y=scene.terrain_surface.ground_y_world(door)+.08
	var safe: Dictionary=scene.interior_visit._safe_external_point(door)
	if safe.is_empty():_check("bus_native_supported_door_fixture",false);buses.set_running(true);return
	scene.player.global_transform=Transform3D(Basis.IDENTITY,safe.point);scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();await _ticks(6);await _tap_e(0)
	_check("bus_physical_E_boards_visible_passenger",buses.riding and buses.active_bus()==body and body.get_node("Visual/SeatedPassenger").visible)
	if not buses.riding:buses.set_running(true);return
	buses.set_running(true)
	for tick in range(1800):
		if body._speed_mps>1.:break
		await _ticks(1)
	_start_measure("bus",body,body.get_node("Visual"),false,false);await _ticks(45);_end_measure()
	scene._visit_library_entrance();await _ticks(8);_check("bus_external_transition_restores_exact_controls",not buses.riding and _controls_exact())

func _run() -> void:
	_loaded_hashes=_input_hashes()
	for path: String in ["res://resources/world_geometry/world.json","res://data/generated/traffic.json","res://assets/authored/neighborhood_population.json"]:_source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8)
	_check("production_scene_ready",scene.runtime_ok,{"error":scene.exploration_error})
	if not scene.runtime_ok:_finish();return
	for key: Variant in scene.city.source_nodes:source_actor_ids[str(key)]=scene.city.source_nodes[key].get_instance_id()
	if scene.menu.visible:scene.toggle_menu()
	initial_controls={"layer":scene.player.collision_layer,"mask":scene.player.collision_mask,"exclude":scene.rig._query.exclude.duplicate()};initial_capsule=scene.player.get_node("CollisionShape").shape.get_instance_id()
	scene.set_speed_profile("turbo");await _ticks(4)
	# Preserve the train's initial open CityHall dock through the unrelated
	# road checks using the real vehicles checkbox API, without clock writes.
	scene.city_subway_service.set_running(false)
	for ride: Node3D in [scene.city_bike_service,scene.city_scooter_service,scene.drivable_car_service]:await _source_road_ride(ride)
	scene.city_subway_service.set_running(true)
	await _metro_ride();await _high_speed_helicopter();await _bus_ride()
	_finish()

func _finish() -> void:
	if _finished:return
	_finished=true;measuring=false
	for action: String in _held_actions:Input.action_release(action)
	_held_actions.clear()
	var now: Dictionary={}
	if is_instance_valid(scene):
		for key: Variant in scene.city.source_nodes:now[str(key)]=scene.city.source_nodes[key].get_instance_id()
	_check("original_native_source_actors_and_capsule_unchanged",now==source_actor_ids and (not is_instance_valid(scene) or scene.player.get_node("CollisionShape").shape.get_instance_id()==initial_capsule))
	_check("inputs_stable_during_run",_input_hashes()==_loaded_hashes,{"loaded":_loaded_hashes,"finished":_input_hashes()})
	var passed: int=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(_json({"task":"transport_camera_render_stability","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"observations":observations,"source_hashes":_loaded_hashes,"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"physics_hz":Engine.physics_ticks_per_second,"render_max_fps":Engine.max_fps,"elapsed_ms":Time.get_ticks_msec()-_started,"scope":"Full production scene and actual native bike/scooter/car/train/high-speed helicopter motion. Explicit initial road/platform/air fixtures. Samples after actual render callbacks at multiple Engine interpolation fractions. Not ordinary OS input or subjective native visual acceptance; root performs native review."}),"  "));file.close();print("TRANSPORT_CAMERA_RESULT ",passed,"/",checks.size())
	if is_instance_valid(scene):
		if is_instance_valid(scene.neighborhood_life.audio):scene.neighborhood_life.audio.stop();scene.neighborhood_life.audio.stream=null
		await physics_frame;await physics_frame;scene.queue_free();await process_frame;await process_frame
	quit(0 if passed==checks.size() else 1)
