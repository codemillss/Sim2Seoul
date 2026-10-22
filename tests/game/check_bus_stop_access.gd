extends "res://../tests/game/check_city_bus_loop.gd"
## Only the player is placed at retained source-footway waiting anchors.
## Every connector is walked with W and boarded with a physical fresh E event.
## Bus/vehicle/NPC positions and service clocks are never test-assigned.
var captures: Array=[]
var journeys: Array=[]
var normal_traffic: Array=[]
var source_hashes: Dictionary={}
var native:=false
var finished:=false
var began_ms:=0
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	if not report_path.is_absolute_path() or FileAccess.file_exists(report_path):push_error("Use a new absolute report path");quit(2);return
	native=DisplayServer.get_name()!="headless";began_ms=Time.get_ticks_msec();source_hashes=_hashes()
	create_timer(600.,true,false,true).timeout.connect(func():_check("completion_guard",false);_finish())
	_run.call_deferred()
func _ticks(count: int) -> void:
	# Input.parse_input_event enters the ordinary buffered input path. The
	# first native frame may contain several physics steps before input and
	# process callbacks run; observe both phases before judging a fresh E.
	for tick: int in range(count):await physics_frame;await process_frame
func _source_wait_observation(label: String,posed: bool,index: int) -> Dictionary:
	var visit: Node3D=scene.interior_visit
	var target: Node3D=scene._street_interact_target()
	var request_events: Array=[]
	for row: Dictionary in service.events:
		if row.get("type","") in ["wait_requested","wait_cancelled"] and row.get("stop_id","")==service.design.stops[index].id:request_events.append(row.duplicate(true))
	return {"label":label,"posed":posed,"physics_tick":Engine.get_physics_frames(),"process_frame":Engine.get_process_frames(),"requested_stop_index":index,"request_events":request_events,"waiting_for_bus":service.waiting_for_bus,"waiting_stop_index":service._waiting_stop_index,"interact_held":Input.is_action_pressed("interact"),"e_press_pending":visit._e_press_pending,"e_was_pressed":visit._e_was_pressed,"e_requires_release":visit.e_requires_release,"menu_open":scene.menu.visible,"street_target":String(target.name) if is_instance_valid(target) else "none","player":scene.player.global_position}
func _hashes() -> Dictionary:
	var result: Dictionary={}
	for path: String in ["res://scripts/city_bus_service.gd","res://scripts/explore_walk.gd","res://assets/authored/bus_service.json","res://assets/authored/road_furniture.json","res://resources/world_geometry/world.json","res://assets/authored/neighborhood_population.json","res://scripts/player/free_roam_player.gd","res://../tests/game/check_bus_stop_access.gd","res://../tests/game/check_city_bus_loop.gd"]:result[path]=FileAccess.get_sha256(path)
	return result
func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Array:
		var result: Array=[]
		for row: Variant in value:result.append(_json(row))
		return result
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:result[str(key)]=_json(value[key])
		return result
	return value
func _capture(label: String) -> void:
	if not native:return
	await process_frame;await RenderingServer.frame_post_draw
	var path:=report_path.trim_suffix(".json")+"_"+label+".png"
	var ok: bool=scene.get_viewport().get_texture().get_image().save_png(path)==OK
	_check("native_capture_"+label,ok);captures.append({"name":label,"path":path,"saved":ok})
func _tap_key() -> void:
	var event:=InputEventKey.new();event.physical_keycode=KEY_E;event.pressed=true;event.device=42;Input.parse_input_event(event);await _ticks(2)
	event=InputEventKey.new();event.physical_keycode=KEY_E;event.pressed=false;event.device=42;Input.parse_input_event(event);await _ticks(3)
func _walk_to(point: Vector3) -> Dictionary:
	var began: Vector3=scene.player.global_position;var previous: Vector3=began;var distance:=0.;var maximum_step:=0.;var samples:=0;var reached:=false
	for tick: int in range(30*12):
		var remaining: Vector3=point-scene.player.global_position;remaining.y=0.
		if remaining.length()<.26:reached=true;break
		scene.rig.yaw=atan2(-remaining.x,-remaining.z);Input.action_press("move_forward");await _ticks(1)
		var current: Vector3=scene.player.global_position;var step:=Vector2(current.x-previous.x,current.z-previous.z).length();distance+=step;maximum_step=maxf(maximum_step,step);previous=current;samples+=1
	Input.action_release("move_forward");await _ticks(5)
	return {"reached":reached,"initial":began,"final":scene.player.global_position,"walked_m":distance,"maximum_step_m":maximum_step,"samples":samples,"remaining_m":Vector2(point.x-scene.player.global_position.x,point.z-scene.player.global_position.z).length()}
func _run() -> void:
	var settings: String="/tmp/sim2seoul-bus-access-"+str(OS.get_process_id())+".json";var file:=FileAccess.open(settings,FileAccess.WRITE);file.store_string(JSON.stringify({"schema_version":1,"speed_id":"realistic","free_roam":true}));file.close()
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=settings;scene.quality_settings_path=settings+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(6);service=scene.city_bus_service
	_check("production_scene_three_buses_four_stop_accesses",scene.runtime_ok and service.loaded and service.buses.size()==3 and service.boarding_access_certificates.size()==4,{"error":scene.exploration_error,"access":service.boarding_access_certificates})
	if not scene.runtime_ok or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	var original_ids: Array=[]
	for body: CharacterBody3D in scene.vehicles+scene.neighborhood_population.traffic.vehicles:original_ids.append(body.get_instance_id())
	_check("all_four_native_static_source_public_walk_connectors",service.boarding_access_certificates.all(func(row: Dictionary):return row.source_wait_retained and row.source_drive_private_and_entry_exclusion and row.native_full_capsule_samples>20),{"access":service.boarding_access_certificates})
	_check("fourth_stop_rejects_drive_overlap_front_door_and_uses_middle_door",int(service.design.stops[3].boarding_door_index)==1 and service.design.stops[3].boarding_supported_doors==[1])
	for index: int in range(4):
		var stop: Dictionary=service.design.stops[index];var posed: bool=await _pose(stop.wait_world);service.set_running(true)
		var wait_before: Dictionary=_source_wait_observation("before_fresh_physical_E",posed,index)
		await _tap_key()
		var wait_after: Dictionary=_source_wait_observation("original_source_wait_assertion_phase",posed,index)
		_check("source_wait_fresh_E_requests_bus_"+str(index+1),posed and service.waiting_for_bus and service._waiting_stop_index==index,{"before_E":wait_before,"after_E":wait_after,"scope":"Original wait-request condition and physical E retained. This fixture waits through both ordinary process and physics phases; no event flushing, service-state assignment or retry input."})
		var target: CharacterBody3D
		for tick: int in range(30*180):
			await _ticks(1)
			for body: CharacterBody3D in service.buses:
				service._switch_bus(body)
				if service.docked_stop==index and service.bus_state=="doors_open":target=body;break
			if is_instance_valid(target):break
		_check("actual_bus_naturally_stops_at_"+str(index+1),is_instance_valid(target))
		if not is_instance_valid(target):continue
		# Freeze only the three buses after actual docking for a repeatable walk;
		# original 14 traffic cars and original moving people remain enabled.
		service.set_running(false);service._switch_bus(target)
		var journey: Dictionary=await _walk_to(stop.boarding_world);journey["stop_id"]=stop.id;journey["bus_id"]=target.name;journey["boarding_world"]=stop.boarding_world;journey["door_index"]=stop.boarding_door_index;journeys.append(journey)
		_check("actual_W_source_wait_to_real_door_"+str(index+1),journey.reached and journey.walked_m>4.0 and journey.maximum_step_m<.45 and journey.remaining_m<.50,journey)
		await _capture("boarding_access_stop_"+str(index+1));await _tap_key()
		_check("first_fresh_physical_E_boards_actual_door_"+str(index+1),service.riding and service.active_bus()==target,{"prompt":service.prompt_text(),"player":scene.player.global_position,"boarding_candidate":service._boarding_candidate()})
		if service.riding:await _tap_key();await _ticks(5)
		_check("real_door_exit_restores_capsule_and_nearby_boarding_marker_"+str(index+1),not service.riding and scene.player.is_physics_processing() and not service._collision_release_pending and scene.player.global_position.distance_to(stop.boarding_world)<.50)
	var retained: Array=[]
	for body: CharacterBody3D in scene.vehicles+scene.neighborhood_population.traffic.vehicles:retained.append(body.get_instance_id())
	_check("original14_identities_route_geometry_and_service_counts_retained",original_ids==retained and retained.size()==14 and service.buses.size()==3 and service.design.stops.size()==4 and absf(float(service.design.route.length_m)-812.2916387858654)<.0001)
	var all_moved:=true;var bounded:=true;var guarded:=true;var cycles:=0
	for body: CharacterBody3D in scene.vehicles+scene.neighborhood_population.traffic.vehicles:
		var row: Dictionary=body.snapshot();normal_traffic.append(row);all_moved=all_moved and float(row.actual_distance_m)>1.0;bounded=bounded and float(row.max_step_m)<.30 and float(row.max_route_offset_m)<.003 and String(row.state)!="off_route";cycles+=int(row.completed_cycles)
		for recycle: Dictionary in row.recycle_history:guarded=guarded and bool(recycle.guard.allowed) and int(recycle.guard.tick)==int(recycle.tick)
	_check("all14_normal_AI_cars_actually_move_with_bounded_physical_source_route_steps",all_moved and bounded,{"normal_traffic":normal_traffic,"original_car_positions_or_clocks_assigned":false,"people_and_original_traffic_kept_enabled":true})
	_check("observed_original_endpoint_recycles_require_current_native_manager_guards",guarded and cycles>0,{"completed_cycles":cycles,"normal_traffic":normal_traffic})
	_check("current_test_sources_unchanged",source_hashes==_hashes(),{"started":source_hashes,"finished":_hashes()})
	_finish()
func _finish() -> void:
	if finished:return
	finished=true;Input.action_release("move_forward")
	var count: int=checks.filter(func(row: Dictionary):return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(_json({"task":"EXP27_BUS_STOP_ACCESS_REVIEW","passed":count,"total":checks.size(),"checks":checks,"captures":captures,"journeys":journeys,"normal_traffic":normal_traffic,"snapshot":service.snapshot() if is_instance_valid(service) else {},"source_sha256":source_hashes,"display":DisplayServer.get_name(),"wall_ms":Time.get_ticks_msec()-began_ms,"scope":"Real W walks and fresh physical-key E across all four stops; only player start poses assigned. Buses naturally dock, then are paused for repeatable walks; original14 road cars and people remain enabled. OS key events, visual review and real Seoul stop surveying are separate."}),"  "));file.close();print("BUS_ACCESS_RESULT ",count,"/",checks.size());quit(0 if count==checks.size() else 1)
