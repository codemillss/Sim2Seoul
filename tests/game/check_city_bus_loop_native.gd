extends "res://../tests/game/check_city_bus_loop.gd"
## Root executes this with a real rendering window. Never repositions a bus.
## Only the production shortcut and an explicitly labelled safe player-door
## fixture change player location. The fourth camera is an inspection fixture.
var requested_hz:=30
var captures: Array=[]
var observations: Dictionary={}
var began_ms:=0
var finished:=false
var native:=false
func _initialize() -> void:
	report_path="/tmp/sim2seoul-city-bus-loop-native.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
		elif arg.begins_with("--physics-hz="):requested_hz=int(arg.trim_prefix("--physics-hz="))
	if FileAccess.file_exists(report_path):push_error("Refusing to overwrite native bus evidence");quit(1);return
	if requested_hz not in [30,60] or not report_path.is_absolute_path():push_error("Use --report=<absolute> --physics-hz=30|60");quit(1);return
	native=DisplayServer.get_name()!="headless";began_ms=Time.get_ticks_msec()
	create_timer(120.,true,false,true).timeout.connect(func():_check("native_two_minute_completion_guard",false);_finish())
	_run.call_deferred()
func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Transform3D:return {"origin":_json(value.origin),"basis":[_json(value.basis.x),_json(value.basis.y),_json(value.basis.z)]}
	if value is Array:
		var values: Array=[]
		for child: Variant in value:values.append(_json(child))
		return values
	if value is Dictionary:
		var values: Dictionary={}
		for key: Variant in value:values[str(key)]=_json(value[key])
		return values
	if value is float:return value if is_finite(value) else null
	return value
func _button(node: Node,label: String) -> Button:
	if node is Button and node.text==label:return node
	for child: Node in node.get_children():
		var found: Button=_button(child,label)
		if found!=null:return found
	return null
func _capture(title: String,basis: String) -> void:
	if not native:captures.append({"name":title,"captured":false,"reason":"headless_has_no_native_pixels"});return
	await process_frame;RenderingServer.force_draw(false,0);await RenderingServer.frame_post_draw
	var picture: Image=scene.get_viewport().get_texture().get_image();var path: String=report_path.trim_suffix(".json")+"_"+title+".png";var saved: bool=not picture.is_empty() and picture.save_png(path)==OK
	var current: Camera3D=scene.get_viewport().get_camera_3d()
	captures.append({"name":title,"captured":saved,"path":path,"width":picture.get_width(),"height":picture.get_height(),"basis":basis,"player":scene.player.global_position,"camera":current.global_transform,"fleet":service._fleet_snapshot(),"arrivals":service.arrival_labels.map(func(label: Label3D):return label.text)})
	_check("native_capture_"+title,saved)
func _fleet_observation() -> void:
	var centre:=Vector3.ZERO
	for body: CharacterBody3D in service.buses:centre+=body.global_position
	centre/=service.buses.size()
	var camera:=Camera3D.new();camera.name="ExplicitNativeFleetObservationFixture";camera.fov=62.;camera.far=1400.;scene.add_child(camera);camera.global_position=Vector3(centre.x,centre.y+430.,230.);camera.look_at(Vector3(centre.x,centre.y,230.),Vector3.FORWARD);camera.make_current()
	var rows: Array=[]
	for body: CharacterBody3D in service.buses:
		var roof: Vector3=body.to_global(Vector3(0,3.12,0));var ray:=PhysicsRayQueryParameters3D.create(camera.global_position,roof,1,[body.get_rid()]);var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(ray)
		rows.append({"bus_id":body.name,"in_actual_camera_frustum":camera.is_position_in_frustum(roof),"roof_ray_clear":hit.is_empty(),"occluder":String(hit.collider.name) if not hit.is_empty() else "","position":body.global_position})
	observations["fleet_aerial_fixture"]={"rows":rows,"production_vehicle_positions_changed":false,"basis":"Test-only aerial Camera3D; original player/transport camera is restored immediately after capture."}
	await _capture("04_three_bus_observation","Explicit test-only aerial observation Camera3D; all three live physical buses retain their production positions; not a player-accessible camera claim")
	scene.rig.camera.make_current();camera.queue_free()
func _finish() -> void:
	if finished:return
	finished=true
	var passed: int=checks.filter(func(row: Dictionary):return bool(row.passed)).size();var hashes: Dictionary={}
	for path: String in ["res://scripts/city_bus_service.gd","res://assets/authored/bus_service.json","res://scripts/explore_walk.gd","res://assets/authored/road_furniture.json","res://../tests/game/check_city_bus_loop_native.gd"]:hashes[path]=FileAccess.get_sha256(path)
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json({"task":"EXP25_BUS_NATIVE_SHORT_JOURNEY","passed":passed,"total":checks.size(),"checks":checks,"captures":captures,"observations":observations,"display":DisplayServer.get_name(),"physics_hz":Engine.physics_ticks_per_second,"wall_ms":Time.get_ticks_msec()-began_ms,"source_sha256":hashes,"snapshot":service.snapshot() if is_instance_valid(service) else {},"scope":"Production menu shortcut, fresh-E wait/board/reserved exit, live source-road bus motion. Safe player door pose is labelled fixture. Bus transforms are never test-assigned. Native captures are actual viewport pixels; aerial inspection frame is explicitly a fixture. Long812m occupied/endpoint-camera stress remains a separate acceptance artifact."}),"  "));file.close()
	print("BUS_NATIVE_RESULT ",passed,"/",checks.size()," report=",report_path);quit(0 if passed==checks.size() else 1)
func _run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/sim2seoul-bus-native-"+str(OS.get_process_id())+".json";scene.exploration_physics_hz=requested_hz;root.add_child(scene);await _ticks(5);service=scene.city_bus_service
	_check("native_production_three_bus_four_stop_ready",native and scene.runtime_ok and service.loaded and service.buses.size()==3 and service.design.stops.size()==4,{"native":native,"runtime":scene.runtime_ok})
	if not scene.runtime_ok or not service.loaded:_finish();return
	if not scene.menu.visible:scene.toggle_menu()
	await process_frame
	var button: Button=_button(scene.get_node("Interface"),"버스 정류장으로 이동")
	_check("actual_menu_bus_stop_shortcut_exists",button!=null)
	if button==null:_finish();return
	button.pressed.emit();await _ticks(7)
	var view: Dictionary=service.viewpoint();var safe: Dictionary=scene.interior_visit._safe_external_point(scene.player.global_position)
	_check("production_shortcut_supported_at_source_walk_wait",not scene.menu.visible and not paused and not safe.is_empty() and scene.player.global_position.distance_to(view.point)<.35)
	await _tap();_check("fresh_E_wait_request_without_automatic_boarding",service.waiting_for_bus and not service.riding)
	var target: CharacterBody3D
	for tick: int in range(requested_hz*65):
		await _ticks(1)
		for body: CharacterBody3D in service.buses:
			service._switch_bus(body)
			if service.docked_stop==0 and service.bus_state=="doors_open":target=body;break
		if is_instance_valid(target):break
	_check("natural_first_stop_arrival_without_bus_pose_fixture",is_instance_valid(target),{"fleet":service._fleet_snapshot(),"arrivals":service.arrival_labels.map(func(label: Label3D):return label.text)})
	if not is_instance_valid(target):_finish();return
	observations["arrival"]={"bus_id":target.name,"fleet":service._fleet_snapshot(),"arrival_display":service.arrival_labels[0].text,"ordinary_player_camera":scene.rig.camera.global_transform}
	await _capture("01_stop_arrival","Ordinary production third-person camera after real menu shortcut; live bus naturally stopped and arrival screen updated")
	# Explicit fixture: move only the supported player to a real visible door.
	service._switch_bus(target);var door: Vector3=target.to_global(Vector3(1.6,0,.55));door.y=scene.terrain_surface.ground_y_world(door)+.08
	var posed: bool=await _pose(door);scene.rig.yaw=target.global_rotation.y+.73;scene.rig.snap_to_target_pose();var camera_saved: Dictionary={"distance":scene.rig.requested_distance,"maximum":scene.rig.distance_max_m,"pitch":scene.rig.pitch,"yaw":scene.rig.yaw}
	observations["boarding_fixture"]={"kind":"supported_player_door_approach_only","player":scene.player.global_position,"bus_id":target.name,"bus_pose_changed":false,"camera_before":camera_saved}
	await _tap();_check("fresh_E_boards_nearest_naturally_docked_bus",posed and service.riding and service.active_bus()==target and not scene.player.is_physics_processing())
	if not service.riding:_finish();return
	var before: Vector3=target.global_position;var start_stop: int=service.docked_stop;var moving:=false;var requested:=false
	for tick: int in range(requested_hz*50):
		await _ticks(1);service.active_bus()
		if target._speed_mps>1. and target.global_position.distance_to(before)>2.:
			moving=service.door_fraction<.001
			await _capture("02_actual_seated_ride","Ordinary production passenger camera during actual closed-door physical movement; seated player capsule/attachment retained")
			await _tap();requested=service.exit_requested;break
	_check("actual_closed_door_motion_and_fresh_E_next_stop_reservation",moving and requested,{"bus":target.snapshot(),"start_stop":start_stop})
	for tick: int in range(requested_hz*45):
		await _ticks(1)
		if not service.riding:break
	await _ticks(6);service._switch_bus(target)
	var restored: bool=not service.riding and not service._collision_release_pending and scene.player.is_physics_processing() and not scene.player.facility_control and is_equal_approx(scene.rig.requested_distance,float(camera_saved.distance)) and is_equal_approx(scene.rig.distance_max_m,float(camera_saved.maximum)) and is_equal_approx(scene.rig.pitch,float(camera_saved.pitch)) and is_equal_approx(scene.rig.yaw,float(camera_saved.yaw))
	var exit_safe: Dictionary=scene.interior_visit._safe_external_point(scene.player.global_position)
	_check("next_actual_stop_native_supported_exit_and_camera_restoration",restored and service.docked_stop!=start_stop and not exit_safe.is_empty(),{"current_stop":service.docked_stop,"camera_before":camera_saved,"camera_after":{"distance":scene.rig.requested_distance,"maximum":scene.rig.distance_max_m,"pitch":scene.rig.pitch,"yaw":scene.rig.yaw},"exit_safe":exit_safe})
	await _capture("03_supported_next_stop_exit","Ordinary production third-person camera after requested native capsule-safe exit; avatar/control and camera distance/pitch restored")
	await _fleet_observation()
	_check("original14_preserved_after_native_short_trip",service.snapshot().original_vehicle_ids_unchanged)
	_finish()
