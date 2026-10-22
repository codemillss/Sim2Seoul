extends "res://../tests/game/check_mobility_distribution.gd"
## Actual F/Q/E dispatch in the entire city. Only supported player observer
## starts are fixtures; no original vehicle or actor transform is replaced.
var scooter: Node3D
var _q_original_docks:=0
var _personal_id:=0

func _ticks(count: int) -> void:
	# SceneTree frames still advance while the ordinary menu pauses the rig.
	for tick: int in range(count):await physics_frame;await process_frame

func _region_start(index: int) -> Dictionary:
	var body: CharacterBody3D=scooter.bikes[index].body
	for offset: Vector3 in [Vector3(1.9,0,.1),Vector3(-1.9,0,.1),Vector3(0,0,2.2),Vector3(0,0,-2.2)]:
		var safe: Dictionary=scene.interior_visit._safe_external_point(body.to_global(offset))
		if safe.is_empty():continue
		scene.player.global_transform=Transform3D(Basis.IDENTITY,safe.point);scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();await _ticks(5)
		return {"point":scene.player.global_position,"source_station":index,"scope":"Supported player-only neighborhood starting fixture, without requiring a different rental E target before Q releases the previous rental."}
	return {}

func _hashes() -> Dictionary:
	var out:=super._hashes()
	for path: String in ["res://scripts/city_public_safety.gd","res://scripts/city_weather_emergency.gd","res://scripts/traffic_car_takeover.gd","res://scripts/drivable_car_service.gd","res://../tests/game/check_city_sandbox_controls.gd"]:out[path]=FileAccess.get_sha256(path)
	return out

func _q(down: bool,echo:=false) -> void:
	var event:=InputEventKey.new();event.keycode=KEY_Q;event.physical_keycode=KEY_Q;event.pressed=down;event.echo=echo;event.device=42;Input.parse_input_event(event)

func _tap_q() -> void:
	_q(true);_q(false);await _ticks(5)

func _record_frame(title: String) -> void:
	if DisplayServer.get_name()=="headless":return
	# Camera-only inspection orbits keep every native collision enabled.
	# Record the real solved distance rather than silently accepting a shot
	# pressed against the old dock/parked vehicle after the nearby Q call.
	var base_yaw: float=scene.rig.yaw;var best_yaw:=base_yaw;var best_distance:=-1.;var trials: Array=[]
	for offset: float in [0.,PI*.5,PI,-PI*.5,.8,-.8]:
		scene.rig.yaw=base_yaw+offset;scene.rig.current_distance=4.8;scene.rig.requested_distance=4.8;scene.rig.snap_to_target_pose();await _ticks(6)
		var view: Dictionary=scene.rig.snapshot();trials.append(view)
		if float(view.distance)>best_distance:best_distance=float(view.distance);best_yaw=scene.rig.yaw
	scene.rig.yaw=best_yaw;scene.rig.current_distance=4.8;scene.rig.snap_to_target_pose();await _ticks(15);await RenderingServer.frame_post_draw
	_check("native_called_scooter_regular_camera_has_clear_orbit",best_distance>=2.5,{"trials":trials,"chosen":scene.rig.snapshot(),"scope":"Only ordinary camera yaw/zoom input-equivalent fixtures; source/player/vehicle positions and collision are unchanged."})
	var path:=report_path.get_basename()+"_"+title+".png";var picture:=root.get_texture().get_image();var code:=picture.save_png(path)
	_check("native_"+title,code==OK,{"file":path})
	if code==OK:captures.append({"file":path,"sha256":FileAccess.get_sha256(path),"camera":scene.rig.snapshot(),"scope":"Actual regular third-person camera; source-supported player observer and camera orbit fixtures only, physical Q/E plus maintained engine W/Space. No camera collision bypass."})

func _near_personal() -> bool:
	var body: CharacterBody3D=scooter.bikes[scooter.summoned_index].body
	for offset: Vector3 in [Vector3(1.3,0,.1),Vector3(-1.3,0,.1),Vector3(0,0,-1.8),Vector3(0,0,1.8),Vector3(1.8,0,.4),Vector3(-1.8,0,.4)]:
		var safe: Dictionary=scene.interior_visit._safe_external_point(body.to_global(offset))
		if safe.is_empty():continue
		scene.player.global_transform=Transform3D(Basis.IDENTITY,safe.point);scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();await _ticks(5)
		if scooter.can_interact() and scooter._nearest_bike()==scooter.summoned_index and scene._street_interact_target()==scooter:return true
	return false

func _actual_ride_outside_dock() -> Dictionary:
	var body: CharacterBody3D=scooter.bikes[scooter.rental_index].body;var before: Vector3=body.global_position;var travelled:=0.;var supported:=true
	_key("move_forward",true)
	for tick: int in range(150):
		await _ticks(1);travelled=body.global_position.distance_to(before);supported=supported and body.is_on_floor()
		if travelled>=2.7:break
	_key("move_forward",false);_key("jump",true);await _ticks(45);_key("jump",false);await _ticks(2)
	var stopped_speed: float=scooter.speed_mps;await _tap_e();await _ticks(5)
	return {"travel_m":body.global_position.distance_to(before),"supported":supported,"stopped_speed_mps":stopped_speed,"riding":scooter.riding,"outside_dock":scooter._near_station(body.global_position).is_empty(),"rental_index":scooter.rental_index,"body_id":body.get_instance_id()}

func _run() -> void:
	_loaded_hashes=_hashes()
	var settings:="/tmp/sim2seoul-sandbox-controls-"+str(OS.get_process_id())+".json";var file:=FileAccess.open(settings,FileAccess.WRITE);file.store_string(JSON.stringify({"schema_version":1,"speed_id":"realistic","free_roam":true}));file.close()
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=settings;scene.quality_settings_path=settings+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8)
	scooter=scene.city_scooter_service
	_check("ordinary_city_all_sandbox_services_ready",scene.runtime_ok and scooter.loaded and scene.city_public_safety.loaded and scene.city_weather_emergency.loaded and scene.traffic_car_takeover.loaded,{"error":scene.exploration_error})
	if not scene.runtime_ok:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	_initial_inventory=_inventory();_initial_capsule=_capsule();_initial_actors=_actors();_initial_tin=hash(scene.terrain_surface.faces);_q_original_docks=scooter.stations.size()
	# Start with an ordinary dock rental, actually ride beyond every return
	# radius, and park. This reproduces the retained rental_index regression.
	var start:=await _place_observer(scooter,1)
	_check("supported_existing_dock_observer",not start.is_empty())
	if start.is_empty():_finish();return
	scene.rig.yaw=float(scooter.bikes[1].yaw);await _tap_e()
	_check("physical_E_rents_original_dock_scooter",scooter.riding and scooter.rental_index==1)
	if not scooter.riding:_finish();return
	var old_body: CharacterBody3D=scooter.bikes[1].body;var trip:=await _actual_ride_outside_dock()
	_check("actual_W_Space_E_parks_original_scooter_outside_dock",not trip.riding and trip.outside_dock and trip.travel_m>3. and trip.supported and absf(trip.stopped_speed_mps)<.02,trip)
	var count_before: int=scooter.summon_count;await _tap_q()
	_check("short_physical_Q_edge_creates_one_personal_scooter",scooter.summon_count==count_before+1 and scooter.summoned_index>=0 and scooter.bikes.size()==_q_original_docks+1,{"snapshot":scooter.snapshot()})
	if scooter.summoned_index<0:_finish();return
	_personal_id=scooter.bikes[scooter.summoned_index].body.get_instance_id()
	_check("previous_parked_rental_released_without_moving_or_deleting_body",scooter.rental_index==-1 and not scooter.bikes[1].rented and scooter.bikes[1].body==old_body and scooter.bikes[1].body.get_instance_id()==int(trip.body_id))
	var personal_start:=await _near_personal();_check("new_personal_scooter_is_ordinary_nearest_E_target",personal_start)
	if not personal_start:_finish();return
	await _tap_e();_check("physical_E_mounts_called_scooter_after_old_rental",scooter.riding and scooter.bikes[scooter.rental_index].body.get_instance_id()==_personal_id)
	await _record_frame("called_scooter_mounted")
	var rejected_before: int=scooter.summon_count;await _tap_q();_check("Q_while_riding_does_not_spawn_or_move_inventory",scooter.summon_count==rejected_before and scooter.riding)
	_key("jump",true);await _ticks(20);_key("jump",false);await _tap_e();await _ticks(5)
	_check("E_safe_personal_exit_restores_original_capsule",not scooter.riding and _capsule()==_initial_capsule and scene.player.is_physics_processing() and not scene.player.facility_control)
	# Repeat calls from distant original neighborhoods while keeping the same
	# single real personal body, leaving the eight dock bodies untouched.
	var region_positions: Array=[]
	for index: int in [0,6,3]:
		var entry:=await _region_start(index)
		if entry.is_empty():_check("source_region_"+str(index)+"_observer",false);continue
		scene.rig.yaw=float(scooter.bikes[index].yaw);var previous_count: int=scooter.summon_count;await _tap_q()
		var body: CharacterBody3D=scooter.bikes[scooter.summoned_index].body;region_positions.append(body.global_position)
		_check("Q_region_"+str(index)+"_reuses_same_source_supported_real_body",scooter.summon_count==previous_count+1 and body.get_instance_id()==_personal_id and scooter.bikes.size()==_q_original_docks+1 and scooter._footprint_allowed(body.global_position,body.global_basis) and scooter._visible_bike(scooter.summoned_index),{"point":body.global_position,"original_dock_index":index,"station_count":scooter.stations.size()})
	var stable_count: int=scooter.summon_count
	_q(true);await _ticks(4);var once: int=scooter.summon_count
	_q(true,true);_q(true,false);await _ticks(25);_q(false)
	_check("held_and_echo_Q_cannot_repeat_calls",once<=stable_count+1 and scooter.summon_count==once)
	scene.toggle_menu();var menu_count: int=scooter.summon_count;_q(true);await _ticks(4);scene.toggle_menu();_q(true);await _ticks(4)
	_check("menu_held_Q_does_not_fire_after_resume",scooter.summon_count==menu_count)
	_q(false);await _ticks(2)
	var air_count: int=scooter.summon_count;_key("jump",true);await _ticks(4);_key("jump",false);await _tap_q()
	_check("airborne_Q_rejects_new_inventory",scooter.summon_count==air_count,{"player_velocity":scene.player.velocity,"notice":scooter.summon_notice()})
	await _ticks(45)
	_check("original_source_nodes_actors_TIN_and_dock_inventory_retained",_inventory()==_initial_inventory and _actors()==_initial_actors and hash(scene.terrain_surface.faces)==_initial_tin and scooter.stations.size()==_q_original_docks and scooter.design.stations.size()==8)
	_finish()

func _finish() -> void:
	if finished:return
	finished=true
	for action: String in _held_actions:Input.action_release(action)
	_held_actions.clear();_q(false);_e(false)
	var hashes:=_hashes();_check("all_runtime_inputs_stable",hashes==_loaded_hashes)
	var passed:=checks.filter(func(row: Dictionary)->bool:return row.passed).size()
	var out:=FileAccess.open(report_path,FileAccess.WRITE);out.store_string(JSON.stringify(_json({"task":"EXP27_sandbox_Q_controls","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"captures":captures,"source_hashes":hashes,"snapshot":scooter.snapshot() if is_instance_valid(scooter) else {},"observer_starts":observer_starts,"scope":"Actual physical KEY_Q/KEY_E edges and maintained engine W/Space in entire production scene. Supported player observer positions only; no vehicle/NPC transform fixtures. Separate OS/subjective/performance acceptance required."}),"  "));out.close();print("SANDBOX_CONTROLS_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)
