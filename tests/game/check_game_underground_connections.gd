extends SceneTree
## Production E/UI/controller and explicit late observer/blocker fixtures.
class HeldInput extends Node:
	var harness: SceneTree
	func _physics_process(_delta: float) -> void:
		if is_instance_valid(harness):harness._refresh_inputs()
var scene: Node3D
var helper: Node3D
var metro: Node3D
var visit: Node3D
var checks: Array[Dictionary]=[]
var captures: Array[Dictionary]=[]
var held: Dictionary={}
var report_path:="/tmp/sim2seoul-underground.json"
var started:=0
var finished:=false
var hashes: Dictionary={}
var source_nodes: Dictionary={}
var capsule_id:=0
var exterior_mask:=0
var exterior_layer:=0
var exterior_excludes: Array=[]
var outdoor_recovery: Dictionary={}
var fixtures: Array[Node3D]=[]
var _deadline: SceneTreeTimer
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	for action: String in ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	var input:=HeldInput.new();input.name="TestOnlyHeldB1Input";input.harness=self;input.process_mode=Node.PROCESS_MODE_ALWAYS;input.process_physics_priority=-200;root.add_child(input)
	started=Time.get_ticks_msec();_deadline=create_timer(540.,true,false,true);_deadline.timeout.connect(func()->void:
		if not finished:_check("bounded_timeout",false);_finish()
	);_run.call_deferred()
func _refresh_inputs() -> void:
	for action: StringName in held:Input.action_press(action)
func _hold(action: StringName,on: bool) -> void:
	if on:held[action]=true
	else:held.erase(action);Input.action_release(action)
func _ticks(count: int) -> void:
	for tick: int in range(count):await physics_frame
func _e(on: bool,device:=42) -> void:
	var event:=InputEventKey.new();event.keycode=KEY_E;event.physical_keycode=KEY_E;event.device=device;event.pressed=on;Input.parse_input_event(event)
func _tap_e(device:=42) -> void:_e(true,device);await _ticks(3);_e(false,device);await _ticks(6)
func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Rect2:return {"position":_json(value.position),"size":_json(value.size)}
	if value is AABB:return {"position":_json(value.position),"size":_json(value.size)}
	if value is Transform3D:return {"origin":_json(value.origin),"basis":[_json(value.basis.x),_json(value.basis.y),_json(value.basis.z)]}
	if value is Dictionary:
		var output: Dictionary={}
		for key: Variant in value:output[str(key)]=_json(value[key])
		return output
	if value is Array:
		var output: Array=[]
		for item: Variant in value:output.append(_json(item))
		return output
	if value is float:return value if is_finite(value) else null
	return value
func _hashes() -> Dictionary:
	var result: Dictionary={}
	for path: String in ["res://scripts/game_underground_connections.gd","res://assets/authored/game_underground_connections.json","res://scripts/game_basement_elevator_cabin.gd","res://scripts/building_interior_space.gd","res://scripts/interior_escalator.gd","res://scripts/interior_population.gd","res://scripts/interior_visit.gd","res://scripts/city_subway_service.gd","res://scripts/player/free_roam_player.gd","res://assets/authored/interiors/source_catalog.json","res://resources/world_geometry/world.json","res://../tests/game/check_game_underground_connections.gd"]:result[path]=FileAccess.get_sha256(path)
	return result
func _check(title: String,ok: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":ok,"evidence":_json(evidence)});print("UNDERGROUND_CHECK ",title," ",ok)
	if not ok:print("UNDERGROUND_FAILURE ",JSON.stringify(_json(evidence)).left(3000))
func _controls_exact() -> bool:return scene.player.collision_layer==exterior_layer and scene.player.collision_mask==exterior_mask and scene.rig._query.exclude==exterior_excludes and scene.player.get_node("CollisionShape").shape.get_instance_id()==capsule_id
func _recovery_exact() -> bool:return scene.player._outdoor_recovery==outdoor_recovery
func _capture(title: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await _ticks(3);await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();var path:=report_path.get_basename()+"_"+title+".png";var error:=image.save_png(path)
	_check("native_capture_"+title,error==OK)
	if error==OK:captures.append({"file":path,"sha256":FileAccess.get_sha256(path),"player":scene.player.global_position,"camera":scene.rig.snapshot(),"scope":"Actual production rig, E/UI signals and native controller after explicit first surface shortcut. Late blocker/menu fixtures are separately labelled. Requires actual image review, not ordinary OS proof."})
func _small_ui(title: String,panel: Control) -> void:
	if DisplayServer.get_name()=="headless":return
	var old_size: Vector2i=root.size;var old_mode: int=root.content_scale_mode;var old_scale: Vector2i=root.content_scale_size
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.size=Vector2i(640,480);await _ticks(6)
	_check("640x480_"+title+"_contained",scene.get_viewport().get_visible_rect().grow(-8.).encloses(panel.get_global_rect()),{"view":scene.get_viewport().get_visible_rect(),"panel":panel.get_global_rect()})
	await _capture("small640_"+title);root.content_scale_mode=old_mode;root.content_scale_size=old_scale;root.size=old_size;await _ticks(5)
func _walk(point: Vector3,fast:=false) -> Dictionary:
	var start: Vector3=scene.player.global_position;var samples: Array=[];var recoveries: int=scene.player.recoveries;var offset: Vector3=point-start;var speed: float=scene.player.run_speed_mps if fast else scene.player.walk_speed_mps
	var limit: int=int(ceil((Vector2(offset.x,offset.z).length()/maxf(.2,speed)+4.)*Engine.physics_ticks_per_second))
	_hold("move_forward",true);_hold("move_fast",fast)
	for tick: int in range(limit):
		offset=point-scene.player.global_position
		if Vector2(offset.x,offset.z).length()<.20:break
		scene.rig.yaw=atan2(-offset.x,-offset.z);await _ticks(1)
		if tick%10==0:samples.append(scene.player.global_position)
	_hold("move_forward",false);_hold("move_fast",false);await _ticks(5)
	return {"start":start,"point":scene.player.global_position,"target":point,"distance":scene.player.global_position.distance_to(point),"recoveries":scene.player.recoveries-recoveries,"samples":samples,"speed_mps":speed,"fast":fast}
func _walk_route(points: Array[Vector3],fast:=false) -> Dictionary:
	var legs: Array=[];var ok:=true;var recoveries: int=scene.player.recoveries
	for point: Vector3 in points:
		var leg: Dictionary=await _walk(point,fast);legs.append(leg);ok=ok and float(leg.distance)<.75 and int(leg.recoveries)==0
	return {"ok":ok,"recoveries":scene.player.recoveries-recoveries,"legs":legs}
func _fixture(point: Vector3,size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();body.name="TestOnlyB1Blocker";body.collision_layer=1;body.collision_mask=0;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;body.add_child(shape);scene.add_child(body);body.global_position=point;fixtures.append(body);return body
func _clear() -> void:
	for fixture: Node3D in fixtures:fixture.queue_free()
	fixtures.clear();await _ticks(4)
func _place(point: Vector3) -> void:
	scene.player.global_position=point;scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();await _ticks(7)
func _button(index: int) -> Button:
	for child: Node in visit.elevator_floors.get_children():
		if child is Button and int(child.get_meta("destination_index",-999))==index:return child
	return null
func _lift(target: int,capture: String="") -> Dictionary:
	var from: int=visit._current_destination();var destination: Vector3=visit.room.elevator_point(from);var local: Vector3=visit.room.to_local(scene.player.global_position);var end: Vector3=visit.room.to_local(destination);var route: Array[Vector3]=[]
	# Follow the existing marked central aisle and front cross-corridor.
	# A straight line from the rear stairs through library desks is not a route.
	if absf(local.z-end.z)>5.:
		route.append(visit.room.to_global(Vector3(0.,float(from)*visit.room.floor_height+.08,local.z)))
		route.append(visit.room.to_global(Vector3(0.,float(from)*visit.room.floor_height+.08,end.z)))
	route.append(destination);var walk: Dictionary=await _walk_route(route,true)
	await _tap_e();var opened: bool=visit.elevator_open;var labels: Array=[]
	for child: Node in visit.elevator_floors.get_children():
		if child is Button:labels.append({"text":child.text,"index":child.get_meta("destination_index",-999),"disabled":child.disabled})
	if not capture.is_empty():await _capture(capture);await _small_ui(capture,visit.elevator_panel)
	var button: Button=_button(target)
	if not opened or not is_instance_valid(button) or button.disabled:return {"ok":false,"opened":opened,"walk":walk,"target":target,"labels":labels}
	button.pressed.emit();var states: Array=[]
	for tick: int in range(30*Engine.physics_ticks_per_second):
		await _ticks(1)
		if tick%5==0:states.append({"tick":tick,"phase":visit._ride_phase,"display":visit.cabin.floor_label.text,"target":visit.selected_floor,"value":visit._current_floor_value,"point":scene.player.global_position,"doors":visit._door_fraction})
		if not visit.in_elevator:break
	await _ticks(7)
	return {"ok":bool(walk.ok) and opened and not visit.in_elevator and visit._current_destination()==target and scene.player.is_physics_processing() and not scene.player.facility_control and _controls_exact() and _recovery_exact(),"from":from,"target":target,"labels":labels,"states":states,"point":scene.player.global_position,"walk":walk,"cabin":visit.cabin.snapshot()}
func _finish() -> void:
	if finished:return
	finished=true
	for action: StringName in held:Input.action_release(action)
	held.clear()
	if not source_nodes.is_empty():
		var now: Dictionary={}
		for key: Variant in scene.city.source_nodes:now[str(key)]=scene.city.source_nodes[key].get_instance_id()
		_check("original_source_actors_capsule_and_source_geometry_preserved",now==source_nodes and _controls_exact())
	_check("all_loaded_module_and_original_input_hashes_stable",_hashes()==hashes and not hashes.values().has(""),{"loaded":hashes,"finished":_hashes()})
	var input: Node=root.get_node_or_null("TestOnlyHeldB1Input")
	if is_instance_valid(input):input.set_physics_process(false);input.harness=null;input.free()
	if is_instance_valid(_deadline):
		for connection: Dictionary in _deadline.timeout.get_connections():_deadline.timeout.disconnect(connection.callable)
		_deadline=null
	var passed: int=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot save B1 report");quit(2);return
	file.store_string(JSON.stringify(_json({"task":"authored_game_B1_connections","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"captures":captures,"helper":helper.snapshot() if is_instance_valid(helper) else {},"metro":metro.snapshot() if is_instance_valid(metro) else {},"building":visit.snapshot() if is_instance_valid(visit) else {},"source_sha256":hashes,"physics_hz":Engine.physics_ticks_per_second,"elapsed_ms":Time.get_ticks_msec()-started,"scope":"Original source identities/plates/counts and native capsule. Explicit game B1/tunnels/portals, actual production W/Shift walks and synthetic physical E devices42/0, actual elevator button signal path. First surface shortcut and late blockers/observer fixtures labelled. No real underground-network or ordinary OS input acceptance from headless."}),"  "));file.close();print("UNDERGROUND_RESULT ",passed,"/",checks.size())
	await _drain_test_audio_and_release_scene()
	quit(0 if passed==checks.size() else 1)
func _run() -> void:
	hashes=_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/b1-test-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(12)
	metro=scene.get("city_subway_service");visit=scene.interior_visit;helper=scene.get("game_underground_connections")
	if not is_instance_valid(helper):helper=load("res://scripts/game_underground_connections.gd").new();scene.add_child(helper);scene.set("game_underground_connections",helper);helper.setup(scene,metro)
	_check("production_setup_two_game_B1_connections",scene.runtime_ok and helper.loaded and metro.loaded and helper.links.size()==2,{"runtime_error":scene.exploration_error,"helper_error":helper.load_error})
	if not scene.runtime_ok or not helper.loaded:_finish();return
	for key: Variant in scene.city.source_nodes:source_nodes[str(key)]=scene.city.source_nodes[key].get_instance_id()
	capsule_id=scene.player.get_node("CollisionShape").shape.get_instance_id();exterior_mask=scene.player.collision_mask;exterior_layer=scene.player.collision_layer;exterior_excludes=scene.rig._query.exclude.duplicate()
	if scene.menu.visible:scene.toggle_menu()
	scene._visit_street_detail("subway_cityhall");await _ticks(8);await _tap_e()
	_check("physical_E_enters_station_with_exclusive_owner",metro.active and not visit.active and not metro.riding and _controls_exact())
	if not metro.active:_finish();return
	outdoor_recovery=scene.player._outdoor_recovery.duplicate(true)
	var row: Dictionary=helper.links[0];var frame: Transform3D=metro.stations[0].frame
	var route: Array[Vector3]=[frame*Vector3(float(row.corridor_center_x),3.08,34.2),row.station_door]
	var walked: Dictionary=await _walk_route(route);_check("actual_W_walk_from_station_concourse_through_two_native_openings",walked.ok and helper.can_interact(),walked)
	await _capture("station_game_connection_library")
	scene.toggle_menu();_e(true);await _ticks(3);scene.toggle_menu();await _ticks(5)
	_check("held_E_through_menu_does_not_cross_game_portal",metro.active and not visit.active and helper.transfers_to_building==0);_e(false);await _ticks(3)
	var blocked_at: Vector3=visit.room.basement_arrival_point();_fixture(blocked_at+Vector3.UP*.9,Vector3(1.4,2.,1.4));await _ticks(3);var retained: Vector3=scene.player.global_position;await _tap_e()
	_check("native_blocked_B1_arrival_preserves_station_owner_and_outdoor_recovery",metro.active and not visit.active and scene.player.global_position.distance_to(retained)<.02 and helper.blocked_transfers>0 and _controls_exact() and _recovery_exact(),helper.snapshot());await _clear()
	await _tap_e(0);await _ticks(4)
	_check("E_connects_library_B1_only_after_native_region_validation",visit.active and not metro.active and visit.room.authored_basement_count==1 and visit.room.floor_count==4 and visit._current_destination()==-1 and absf(scene.player.global_position.y-(visit.ROOM_ORIGIN.y-visit.room.floor_height))<.15 and _controls_exact() and _recovery_exact(),helper.snapshot())
	if not visit.active:_finish();return
	await _capture("library_game_B1")
	_check("B1_signs_and_host_status_use_B1_not_floor_zero","B1" in visit.status_text() and "B1" in visit.room.get_node("FloorTitle-1").text and "B1" in visit.room.get_node("ElevatorSign-1").text,{"status":visit.status_text(),"title":visit.room.get_node("FloorTitle-1").text,"elevator":visit.room.get_node("ElevatorSign-1").text})
	# A full actual B1->1F stair ascent precedes the elevator checks. The
	# existing descending route below proves both physical directions.
	var ascent: Array[Vector3]=visit.room.stair_path(-1,true);var basement_y: float=-visit.room.floor_height+.08
	var lower_approach: Array[Vector3]=[visit.room.to_global(Vector3(0.,basement_y,visit.room.depth*.5-3.5)),visit.room.to_global(Vector3(0.,basement_y,visit.room.stair_front+1.1)),ascent[0]]
	walked=await _walk_route(lower_approach,true);_check("actual_B1_walk_to_library_continuous_stair",walked.ok,walked)
	walked=await _walk_route(ascent);_check("actual_controller_ascends_B1_to_existing_1F_through_cut_slab",walked.ok and visit._current_destination()==0 and _recovery_exact(),walked)
	await _capture("library_B1_stair_arrival_1F")
	var lifted: Dictionary=await _lift(-1);_check("existing_library_1F_elevator_button_returns_authored_B1",lifted.ok,lifted)
	lifted=await _lift(0,"library_B1_elevator_picker");_check("B1_elevator_UI_button_and_native_cabin_reach_existing_library_1F",lifted.ok and lifted.labels.size()==6,lifted)
	if visit.in_elevator:_finish();return
	_check("existing_library_above_ground_programmes_people_and_facilities_retained",visit.room.floor_count==4 and visit.room.detail_kit.level_profiles.size()==4 and is_instance_valid(visit.room.population) and visit.room.detail_kit.facility_kit.facilities.size()==3,{"floor_count":visit.room.floor_count,"profiles":visit.room.detail_kit.level_profiles,"facility_count":visit.room.detail_kit.facility_kit.facilities.size(),"population":visit.room.population.snapshot()})
	var stair: Array[Vector3]=visit.room.stair_path(0,false);var approach: Array[Vector3]=[visit.room.to_global(Vector3(0.,.08,visit.room.depth*.5-3.5)),visit.room.to_global(Vector3(0.,.08,visit.room.stair_front+1.1)),stair[0]]
	walked=await _walk_route(approach,true);_check("actual_controller_crosses_library_existing_1F_to_B1_stair",walked.ok,walked)
	walked=await _walk_route(stair);_check("actual_controller_descends_original_U_stair_extension_to_B1",walked.ok and visit._current_destination()==-1 and _recovery_exact(),walked)
	await _capture("library_B1_stairs")
	var portal: Vector3=visit.room.basement_portal_point();var y: float=-visit.room.floor_height+.08
	var back: Array[Vector3]=[visit.room.to_global(Vector3(0.,y,visit.room.stair_front+1.1)),visit.room.to_global(Vector3(0.,y,visit.room.depth*.5-3.5)),portal]
	walked=await _walk_route(back,true);_check("actual_B1_walk_to_marked_station_return_door",walked.ok and helper.can_interact(),walked)
	_fixture(row.station_return+Vector3.UP*.9,Vector3(1.4,2.,1.4));await _ticks(3);retained=scene.player.global_position;await _tap_e()
	_check("blocked_station_return_preserves_building_B1_and_controls",visit.active and not metro.active and scene.player.global_position.distance_to(retained)<.02 and _controls_exact() and _recovery_exact(),helper.snapshot());await _clear();await _tap_e()
	_check("E_returns_library_B1_to_exact_station_corridor_height",metro.active and not visit.active and scene.player.global_position.distance_to(row.station_return)<.2 and _controls_exact() and _recovery_exact(),helper.snapshot())
	if not metro.active:_finish();return
	var next: Dictionary=helper.links[1];var crossing: Array[Vector3]=[frame*Vector3(float(row.corridor_center_x),3.08,34.0),frame*Vector3(float(next.corridor_center_x),3.08,34.0),next.station_door]
	walked=await _walk_route(crossing,true);_check("actual_W_walk_between_two_different_named_building_corridors",walked.ok and helper.can_interact(),walked)
	await _tap_e();await _ticks(5)
	_check("game_B1_binds_distinct_original_cityhall_plate_and_source_12_floors",visit.active and not metro.active and String(visit.current_spec.id)==String(next.building_id) and visit.room.floor_count==12 and visit.room.width>40. and visit.room.authored_basement_count==1 and visit._current_destination()==-1 and _recovery_exact(),helper.snapshot())
	if not visit.active:_finish();return
	await _capture("cityhall_game_B1")
	lifted=await _lift(11,"cityhall_B1_elevator_picker");_check("cityhall_B1_elevator_reaches_existing_12F_without_changing_source_count",lifted.ok and visit.room.floor_count==12,lifted)
	lifted=await _lift(-1);_check("existing_12F_elevator_returns_B1_with_B1_indicator_and_real_door_phases",lifted.ok and lifted.states.any(func(state: Dictionary)->bool:return "B1" in String(state.display)),lifted)
	scene._visit_street_detail("clothing");await _ticks(8)
	_check("B1_to_production_clothing_shortcut_restores_original_exterior_controls",not visit.active and not metro.active and not scene.player.interior_active and not scene.player.facility_control and scene.player.is_physics_processing() and helper.pending.is_empty() and _controls_exact())
	# Explicit late observer fixture isolates a three-frame prepare/menu race.
	scene._visit_street_detail("subway_cityhall");await _ticks(8);await _tap_e();await _place(row.station_door)
	_e(true);await _ticks(1);scene.toggle_menu();await _ticks(4);scene.toggle_menu();await _ticks(4)
	_check("menu_during_pending_publication_cancels_only_pending_and_preserves_owner",metro.active and not visit.active and helper.pending.is_empty() and _recovery_exact() and _controls_exact(),helper.snapshot());_e(false);await _ticks(3)
	await _tap_e();await _ticks(5)
	lifted=await _lift(0);_check("connected_B1_can_reach_1F_for_original_surface_door",lifted.ok,lifted)
	var surface_exit: Vector3=visit._outside_position;var exterior_view: Dictionary=visit._outside_view.duplicate(true)
	var to_exit: Array[Vector3]=[visit.room.to_global(Vector3(0.,.08,visit.room.depth*.5-1.65)),visit.room.exit_point()]
	walked=await _walk_route(to_exit,true);_check("actual_1F_walk_from_basement_lift_to_existing_source_exit",walked.ok,walked);await _tap_e()
	_check("existing_1F_E_exit_restores_source_door_camera_and_original_recovery",not visit.active and not metro.active and not scene.player.interior_active and scene.player.global_position.distance_to(surface_exit)<.25 and absf(scene.rig.yaw-float(exterior_view.yaw))<.001 and absf(scene.rig.pitch-float(exterior_view.pitch))<.001 and absf(scene.rig.requested_distance-float(exterior_view.distance))<.001 and scene.player.spawn_transform==outdoor_recovery.spawn and scene.player.fall_limit_y==float(outdoor_recovery.fall_limit) and _controls_exact(),{"player":scene.player.global_position,"source_exit":surface_exit,"view":scene.rig.snapshot(),"expected_view":exterior_view})
	await _capture("library_original_1F_source_exit")
	# Explicit late observer only for the final reset case, after the complete
	# actual station/B1/stair/lift/source-door walks above have been exercised.
	scene._visit_street_detail("subway_cityhall");await _ticks(8);await _tap_e();await _place(row.station_door);await _tap_e();await _ticks(5)
	var before_reset: bool=visit.active;scene.reset_player();await _ticks(8)
	_check("production_reset_from_connected_B1_restores_exterior_without_stale_owner",before_reset and not visit.active and not metro.active and not scene.player.interior_active and not scene.player.facility_control and scene.player.is_physics_processing() and helper.pending.is_empty() and _controls_exact())
	_finish()

func _drain_test_audio_and_release_scene() -> void:
	# The existing looping street WAV otherwise retains its AudioServer voice
	# at engine quit. Functional evidence is already saved above; stop only
	# this test scene's sound, drain two physics frames, then release the tree.
	if not is_instance_valid(scene):return
	var life: Node3D=scene.get("neighborhood_life")
	if is_instance_valid(life) and is_instance_valid(life.audio):
		life.audio.stop();life.audio.stream=null
	await physics_frame;await physics_frame
	scene.queue_free();await process_frame;await process_frame
