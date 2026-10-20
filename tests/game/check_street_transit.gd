extends "res://../tests/game/check_street_scene.gd"
## Actual production street acceptance. Only player scenario starts and labelled
## fault/boarding fixtures write poses/state; the braking car is never moved.
var requested_hz := 30
var network: Node3D
var transit: Node3D
var original_capsule: Dictionary={}
var original_routes := ""
var original_tin := 0
var original_tin_transform := Transform3D.IDENTITY
var began_usec := 0
var native := false
var settings_base := ""
const INPUTS := ["res://scripts/explore_walk.gd","res://scripts/interior_visit.gd","res://scripts/street_network_detail.gd","res://assets/authored/road_furniture.json","res://scripts/city_bus_service.gd","res://assets/authored/bus_service.json","res://scripts/city_bike_service.gd","res://assets/authored/bike_service.json","res://../tests/game/check_city_bike_service.gd","res://scripts/street_pedestrians.gd","res://scripts/street_dog_model.gd","res://assets/authored/street_pedestrians.json","res://scripts/traffic/traffic_manager.gd","res://scripts/neighborhood_traffic.gd","res://scripts/traffic/vehicle.gd","res://resources/world_geometry/world.json","res://data/generated/public_walk.json","res://data/generated/traffic.json","res://assets/authored/terrain_heightfield.json","res://data/generated/terrain_surface.json","res://../tools/prepare_road_furniture.py","res://../tests/game/check_street_transit.gd"]

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
		elif arg.begins_with("--physics-hz="):requested_hz=int(arg.trim_prefix("--physics-hz="))
	if not report_path.is_absolute_path() or requested_hz not in [30,60]:push_error("Use --report=<absolute> [--physics-hz=30|60]");quit(1);return
	if FileAccess.file_exists(report_path):push_error("Refusing to overwrite existing street-transit evidence");quit(1);return
	for action: String in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	if InputMap.has_action("interact"):InputMap.erase_action("interact")
	native=DisplayServer.get_name()!="headless";began_usec=Time.get_ticks_usec()
	create_timer(420.,true,false,true).timeout.connect(func():_check("completion_guard",false);_finish())
	_run.call_deferred()

func _check(title: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":_json(evidence)})
	print("STREET_TRANSIT_CHECK ",title," ",passed)
	if not passed:push_warning("STREET_TRANSIT_FAIL "+title)

func _ticks(count: int) -> void:
	for index: int in range(count):await physics_frame

func _seconds(seconds: float) -> void:await _ticks(ceili(seconds*requested_hz))

func _route_signature() -> String:
	var values: Dictionary={}
	for manager: Node in [scene.traffic,scene.neighborhood_population.traffic.manager]:
		for id: String in manager.routes:values[id]=manager.routes[id].xz
	for group: Dictionary in scene.street_pedestrians.groups:
		var xz: Array=[]
		for p: Vector3 in group.points:xz.append([p.x,p.z])
		values[String(group.id)]=xz
	return JSON.stringify(values)

func _hashes() -> Dictionary:
	var result: Dictionary={}
	for path: String in INPUTS:result[path]=FileAccess.get_sha256(path)
	for path: String in ["res://scripts/city_scooter_service.gd","res://assets/authored/scooter_service.json","res://../tests/game/check_city_scooter_service.gd","res://../tests/game/check_bike_entry_reliability.gd"]:result[path]=FileAccess.get_sha256(path)
	return result

func _menu(open: bool) -> void:
	if scene.menu.visible!=open:scene.toggle_menu()
	for i: int in range(2):await process_frame

func _button(label: String) -> Button:
	for node: Node in _desc(scene.get_node("Interface")):
		if node is Button and node.text==label:return node
	return null

func _shortcut(label: String) -> bool:
	await _menu(true)
	var button: Button=_button(label)
	if button==null:_check("shortcut_exists_"+label,false);await _menu(false);return false
	button.pressed.emit();await _ticks(6)
	return not paused and not scene.menu.visible

func _tap_e() -> void:
	_e(true);await _ticks(2);_e(false);await _ticks(3)

func _clock(value: float) -> void:
	network.elapsed_s=value;network.advance_signal_time(0.0)

func _run() -> void:
	source_hashes=_hashes()
	settings_base="/private/tmp/sim2seoul-street-transit-"+str(OS.get_process_id())+".json"
	var initial:=FileAccess.open(settings_base,FileAccess.WRITE);initial.store_string(JSON.stringify({"schema_version":1,"speed_id":"brisk","free_roam":true}));initial.close()
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_physics_hz=requested_hz;scene.exploration_settings_path=settings_base;scene.quality_settings_path=settings_base+".quality.json"
	root.add_child(scene)
	# Freeze movement synchronously after setup, before any actor physics tick.
	scene.set_vehicles_running(false)
	await _ticks(3)
	_check("production_all_new_modules_and_committed_terrain",scene.runtime_ok and scene.exploration_error.is_empty() and scene.terrain_surface.loaded and scene.street_network_detail.loaded and scene.city_bus_service.loaded and scene.city_bike_service.loaded and scene.city_scooter_service.loaded and scene.street_pedestrians.loaded,{"error":scene.exploration_error,"physics_hz":Engine.physics_ticks_per_second})
	if not scene.runtime_ok or not scene.exploration_error.is_empty():_finish();return
	visit=scene.interior_visit;network=scene.street_network_detail;transit=scene.city_bus_service
	original_inventory=_inventory();original_capsule=_player_shape();original_routes=_route_signature();original_tin=hash(scene.terrain_surface.faces);original_tin_transform=scene.terrain_surface.support.global_transform
	_check("original_source_inventory_692_and_fourteen_cars",original_inventory.size()==692 and scene.vehicles.size()+scene.neighborhood_population.traffic.vehicles.size()==14,{"source_records":original_inventory.size(),"original_cars":scene.vehicles.size()+scene.neighborhood_population.traffic.vehicles.size()})
	_actual_paint_sections()
	network.set_physics_process(false);_clock(29.0)
	await _menu(false);scene.set_vehicles_running(true)
	# Keep the independent bus pilot at its original spawn during the car test,
	# so native capture cannot miss its first12-second boarding dwell.
	transit.set_running(false)
	await _original_car_signal_journey()
	transit.set_running(true)
	if native:await _native_bus_journey()
	else:observations["native_bus_journey"]={"status":"DEFERRED","reason":"The separate bus suite covers actual fresh-E ride; this fast headless suite does not duplicate it."}
	network.set_physics_process(true)
	await _pedestrian_two_way_checks()
	await _dog_shortcut_checks()
	await _street_views_and_lighting()
	await _small_menu()
	var bike_shortcut: bool=await _shortcut("자전거 대여소로 이동")
	_check("bike_module_and_actual_station_shortcut_ready",scene.city_bike_service.loaded and bike_shortcut and scene.player.is_on_floor(),{"player":scene.player.global_position})
	await _transaction_regressions()
	_check("source_inventory_capsule_XZ_TIN_retained",_inventory()==original_inventory and _player_shape()==original_capsule and _route_signature()==original_routes and hash(scene.terrain_surface.faces)==original_tin and scene.terrain_surface.support.global_transform==original_tin_transform,{"source_records":original_inventory.size(),"capsule":_player_shape(),"tin_faces":scene.terrain_surface.faces.size()/3,"production_actor_repositions":0,"player_scenario_starts":placements.size()})
	_check("isolated_settings_and_source_hashes_unchanged",scene.exploration_settings_path==settings_base and settings_base.begins_with("/private/tmp/") and _hashes()==source_hashes,{"settings_path":settings_base})
	_finish()

func _route_x_at_z(points: Array,z: float) -> float:
	for i: int in range(1,points.size()):
		var a: Array=points[i-1];var b: Array=points[i]
		if z<minf(a[1],b[1]) or z>maxf(a[1],b[1]) or absf(float(b[1])-float(a[1]))<.00001:continue
		return lerpf(a[0],b[0],(z-float(a[1]))/(float(b[1])-float(a[1])))
	return NAN

func _paint_section(mesh: MeshInstance3D,z: float) -> Array:
	var intervals: Array=[];var vertices: PackedVector3Array=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i: int in range(0,vertices.size(),3):
		var xs: Array[float]=[]
		for edge: int in range(3):
			var a: Vector3=vertices[i+edge];var b: Vector3=vertices[i+(edge+1)%3]
			if z<minf(a.z,b.z)-.00001 or z>maxf(a.z,b.z)+.00001:continue
			if absf(b.z-a.z)<.000001:
				if absf(z-a.z)<.00001:xs.append(a.x);xs.append(b.x)
			else:xs.append(lerpf(a.x,b.x,clampf((z-a.z)/(b.z-a.z),0,1)))
		if xs.size()<2:continue
		xs.sort()
		if xs.back()<50 or xs.front()>112:continue
		intervals.append(Vector2(maxf(50,xs.front()),minf(112,xs.back())))
	intervals.sort_custom(func(a: Vector2,b: Vector2)->bool:return a.x<b.x)
	var merged: Array=[]
	for interval: Vector2 in intervals:
		if merged.is_empty() or interval.x>(merged.back() as Vector2).y+.001:merged.append(interval)
		else:merged[-1]=Vector2((merged.back() as Vector2).x,maxf((merged.back() as Vector2).y,interval.y))
	return merged

func _actual_paint_sections() -> void:
	var white: MeshInstance3D;var yellow: MeshInstance3D
	for visual: MeshInstance3D in network.paint_meshes:
		if String(visual.name).ends_with("white"):white=visual
		elif String(visual.name).ends_with("yellow"):yellow=visual
	var rows: Array=[];var errors: Array=[]
	for z: float in [-160.,-130.,-100.,-70.,-40.]:
		var south: float=_route_x_at_z(scene.traffic.routes.sejong_south.xz,z);var north: float=_route_x_at_z(scene.traffic.routes.sejong_north.xz,z);var bus_x: float=_route_x_at_z(transit.design.route.xz,z)
		var whites: Array=_paint_section(white,z);var yellows: Array=_paint_section(yellow,z)
		var good: bool=yellows.size()==2 and not whites.is_empty()
		for interval: Vector2 in whites:
			for body: Vector2 in [Vector2(south-.90,south+.90),Vector2(north-.90,north+.90),Vector2(bus_x-1.225,bus_x+1.225)]:
				if minf(interval.y,body.y)-maxf(interval.x,body.x)>.001:good=false
		for interval: Vector2 in yellows:
			if interval.x<=south+.9 or interval.y>=north-.9 or interval.y-interval.x>.18:good=false
		if not good:errors.append(z)
		rows.append({"z_m":z,"actual_white_intervals_x_m":whites,"actual_yellow_intervals_x_m":yellows,"original_south_center_x_m":south,"original_north_center_x_m":north,"bus_center_x_m":bus_x,"passed":good})
	_check("actual_projected_paint_has_one_double_median_and_clear_car_bus_lanes",errors.is_empty(),{"sections":rows,"errors_z_m":errors,"basis":"Read actual post-TIN mesh triangle cross-sections, not authored anchor counts. Five source-road witnesses include the previously failingz=-100m."})
	observations["actual_paint_sections"]=rows

func _pedestrian_two_way_checks() -> void:
	var rows: Array=[];var errors: Array=[]
	_clock(31.0);await process_frame;await process_frame
	for row: Dictionary in network.signals:
		if row.kind!="pedestrian":continue
		var from: Vector3=row.opposite_bank_approach+Vector3.UP*1.35
		var target: Vector3=row.head.global_position+row.head.global_basis.z*.13
		var view: Vector3=from-target;view.y=0
		var front: Vector3=row.head.global_basis.z;front.y=0
		var facing: float=front.normalized().dot(view.normalized())
		var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,target,1|32,[scene.player.get_rid()]))
		var safe: Dictionary=scene._exploration_destination(row.opposite_bank_approach)
		var label: Label3D=row.countdown;var case: MeshInstance3D=row.head.get_node("PedestrianSignalCase")
		var text_bounds: AABB=label.transform*label.get_aabb();var case_bounds: AABB=case.mesh.get_aabb()
		var contained: bool=text_bounds.size.x>0 and text_bounds.position.x>case_bounds.position.x and text_bounds.end.x<case_bounds.end.x and text_bounds.position.y>case_bounds.position.y and text_bounds.end.y<case_bounds.end.y and label.position.z>case_bounds.end.z and label.position.z<case_bounds.end.z+.06
		var one_sided: bool=not label.double_sided and label.billboard==BaseMaterial3D.BILLBOARD_DISABLED and case.material_override.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED
		var ok: bool=facing>.95 and hit.is_empty() and not safe.is_empty() and contained and one_sided
		if not ok:errors.append(row.id)
		rows.append({"id":row.id,"bank":row.bank,"crossing_id":row.crossing_id,"head":target,"opposite_approach":from,"front_dot_to_opposite_bank":facing,"static_LOS_clear":hit.is_empty(),"supported_standing_point":not safe.is_empty(),"countdown_single_sided":one_sided,"countdown_inside_opaque_case":contained,"countdown_bounds":text_bounds,"case_bounds":case_bounds,"obstacle":String(hit.collider.name) if not hit.is_empty() else ""})
	var expected: int=network.design.pedestrian_signals.size()
	for crossing: Dictionary in network.design.crossings:
		var banks: Array=[]
		for row: Dictionary in rows:
			if row.crossing_id==crossing.id:banks.append(int(row.bank))
		banks.sort()
		if banks!=[0,1]:errors.append({"crossing_id":crossing.id,"banks":banks})
	_check("pedestrian_heads_face_both_opposite_approaches_with_native_LOS",rows.size()==expected and expected>=8 and errors.is_empty(),{"expected_heads":expected,"heads":rows,"errors":errors})
	observations["pedestrian_two_way"]=rows
	if not native:return
	_clock(31.0)
	for row: Dictionary in network.signals:
		if row.kind!="pedestrian" or row.crossing_id!="sejong_marked":continue
		var side:=Vector3(-row.front_direction.z,0,row.front_direction.x)
		for sign: float in [1.,-1.]:
			var safe: Dictionary=scene._exploration_destination(row.opposite_bank_approach+side*sign*2.)
			if safe.is_empty():continue
			await _pose("crossing_bank_"+str(1-int(row.bank))+"_lateral_"+str(sign*2.),safe.point)
			await _aim_normal_view(row.head.global_position,4.0)
			if _far_signal_view(row.head).clear:break
		await _normal_view("crossing_far_head_from_bank_"+str(1-int(row.bank)),row.head.global_position,4.0,row.head)
	_clock(0.0)

func _original_car_signal_journey() -> void:
	var car: CharacterBody3D=scene.vehicles[0];var route: Dictionary=scene.traffic.routes[car.get_route_id()];var conflict: Dictionary=route.conflicts[0]
	var start: float=car.get_station_m();var maximum_speed:=0.0;var maximum_station:=start;var maximum_step:=0.0;var previous: Vector3=car.global_position;var stopped:=false;var wait_ticks:=0
	for tick: int in range(requested_hz*18):
		await _ticks(1);maximum_speed=maxf(maximum_speed,car._speed_mps);maximum_station=maxf(maximum_station,car.get_station_m());maximum_step=maxf(maximum_step,Vector2(car.global_position.x-previous.x,car.global_position.z-previous.z).length());previous=car.global_position
		if car._speed_mps<.01 and absf(car.get_station_m()-float(conflict.stop_s_m))<.025:wait_ticks+=1
		else:wait_ticks=0
		if wait_ticks>=requested_hz:stopped=true;break
	_check("original_car_from_spawn_physically_brakes_at_red",car.get_route_id()=="sejong_south" and start<.005 and stopped and maximum_speed>1.0 and maximum_station<=float(conflict.stop_s_m)+.005 and maximum_step<=5.0/requested_hz+.007,{"start_station_m":start,"stop_station_m":car.get_station_m(),"stop_limit_m":conflict.stop_s_m,"maximum_speed_mps":maximum_speed,"maximum_step_m":maximum_step,"reason":car._blocked_reason,"permission":car._permission,"actor_position_writes":0})
	var red_station: float=car.get_station_m();_clock(0.0);var crossed:=false;var resume_ticks:=0
	for tick: int in range(requested_hz*48):
		await _ticks(1);resume_ticks+=1
		if car.get_station_m()>float(conflict.exit_s_m)+1.0:crossed=true;break
	_check("same_original_car_green_resumes_and_clears_crossing",crossed and car.get_station_m()>red_station+10.0 and car._speed_mps>.1,{"red_station_m":red_station,"after_station_m":car.get_station_m(),"enter_s_m":conflict.enter_s_m,"exit_s_m":conflict.exit_s_m,"elapsed_s":float(resume_ticks)/requested_hz,"reason":car._blocked_reason,"permission":car._permission,"actor_position_writes":0})
	observations["signals"]={"car_id":car.get_route_id(),"red_observed":stopped,"green_crossed":crossed,"source_conflict":conflict,"vehicle_head_count":network.signals.filter(func(row: Dictionary)->bool:return row.kind=="vehicle").size(),"pedestrian_head_count":network.signals.filter(func(row: Dictionary)->bool:return row.kind=="pedestrian").size()}

func _native_bus_journey() -> void:
	var arrived: bool=await _shortcut("버스 정류장으로 이동")
	_check("native_bus_stop_shortcut_has_supported_observer",arrived and scene.player.is_on_floor(),{"point":scene.player.global_position})
	var first:=false
	for tick: int in range(requested_hz*55):
		await _ticks(1)
		if transit.docked_stop==0 and transit.bus_state=="doors_open":first=true;break
		if transit.stop_index>0:break
	_check("native_bus_natural_first_dock_without_reposition",first,{"station_m":transit.bus.get_station_m(),"state":transit.bus_state,"stop_index":transit.stop_index})
	if not first:return
	await _normal_view("bus_stop_open_doors",transit.bus.global_position+Vector3.UP*1.3,4.5)
	await _tap_e();_check("native_root_fresh_E_boards_bus",transit.riding and not scene.player.is_physics_processing(),{"state":transit.bus_state,"capsule":_player_shape()})
	if not transit.riding:return
	var moving:=false;var requested:=false;var exited:=false;var max_attachment:=0.0
	for tick: int in range(requested_hz*55):
		await _ticks(1)
		if transit.riding:max_attachment=maxf(max_attachment,scene.player.global_position.distance_to(transit.bus.to_global(Vector3(.35,.72,-.6))))
		if transit.riding and transit.bus._speed_mps>.5 and transit.door_fraction==0.0:
			moving=true
			if not requested:
				await _capture_frame("bus_moving_ride",true);await _tap_e();requested=true
		if requested and not transit.riding:exited=true;break
	# Production exit publishes the supported player pose before restoring the
	# native collision pair and controls two physics frames later. Observe that
	# bounded handoff and the stationary dock after it, without writing state.
	var restored_after_ticks: int=-1;var pending_pairs: int=2;var maximum_bus_shift:=0.0
	var exit_bus_point: Vector3=transit.bus.global_position
	if exited:
		for tick: int in range(12):
			await _ticks(1)
			maximum_bus_shift=maxf(maximum_bus_shift,transit.bus.global_position.distance_to(exit_bus_point))
			pending_pairs=int(transit.bus.get_collision_exceptions().has(scene.player))+int(scene.player.get_collision_exceptions().has(transit.bus))
			if restored_after_ticks<0 and scene.player.is_physics_processing() and not scene.player.facility_control and not transit._collision_release_pending and pending_pairs==0:restored_after_ticks=tick+1
	var supported_exit: bool=exited and scene.player.is_on_floor() and not scene._exploration_destination(scene.player.global_position).is_empty()
	var restored: bool=restored_after_ticks>0 and scene.player.is_physics_processing() and not scene.player.facility_control and not transit._collision_release_pending and pending_pairs==0
	_check("native_bus_moves_closed_then_requested_supported_exit",moving and exited and transit.docked_stop==1 and restored and supported_exit and maximum_bus_shift<.02 and max_attachment<.02,{"moving":moving,"requested":requested,"exited":exited,"attachment_max_m":max_attachment,"state":transit.bus_state,"player":scene.player.global_position,"control_restored_after_ticks":restored_after_ticks,"release_pending":transit._collision_release_pending,"native_exception_pairs_remaining":pending_pairs,"supported_exit":supported_exit,"post_exit_observation_ticks":12 if exited else 0,"post_exit_bus_max_shift_m":maximum_bus_shift})
	if exited:await _normal_view("bus_safe_exit",transit.bus.global_position+Vector3.UP,4.5)

func _dog_poses() -> Array:
	var result: Array=[]
	for group: Dictionary in scene.street_pedestrians.groups:
		if group.record.dog:
			for row: Dictionary in group.members:result.append(row.body.global_transform)
	return result

func _dog_shortcut_checks() -> void:
	var before: Dictionary=scene._dog_walk_viewpoint()
	var success: bool=await _shortcut("반려견 산책 구간으로 이동")
	var selected: Dictionary={}
	for group: Dictionary in scene.street_pedestrians.groups:
		if group.id==before.get("group_id",""):selected=group;break
	_check("dog_production_shortcut_selects_existing_keeper_and_dog",success and not selected.is_empty() and selected.members.size()==2,{"destination":before,"player":scene.player.global_position})
	if selected.is_empty():return
	var subjects: Array=[selected.members[0].body.global_position+Vector3.UP,selected.members[1].body.global_position+Vector3.UP*.4]
	var visibility: Array=[];var clear:=true
	for subject: Vector3 in subjects:
		var excludes: Array[RID]=[scene.player.get_rid()]
		var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(scene.rig.camera.global_position,subject,1|32,excludes))
		var projected: Vector2=scene.rig.camera.unproject_position(subject)
		var on_screen: bool=not scene.rig.camera.is_position_behind(subject) and scene.get_viewport().get_visible_rect().has_point(projected)
		clear=clear and hit.is_empty() and on_screen
		visibility.append({"point":subject,"screen":projected,"on_screen":on_screen,"static_clear":hit.is_empty(),"obstacle":String(hit.collider.name) if not hit.is_empty() else ""})
	_check("dog_keeper_and_dog_in_normal_camera_clear_LOS_visible_player",clear and _camera_clear() and scene.player.get_node("Visual").visible and scene.rig.current_distance>1.8,{"subjects":visibility,"camera_distance_m":scene.rig.current_distance,"avatar_visible":scene.player.get_node("Visual").visible})
	await _capture_frame("dog_keeper_close",false)
	await _menu(true);var frozen: Array=_dog_poses();var clock: float=scene.street_pedestrians.elapsed;var signal_clock: float=network.elapsed_s
	for i: int in range(12):await process_frame
	_check("menu_pauses_actual_dog_poses_and_clocks",_dog_poses()==frozen and scene.street_pedestrians.elapsed==clock and network.elapsed_s==signal_clock,{"dog_elapsed_s":clock,"signal_elapsed_s":signal_clock})
	await _menu(false);await _seconds(.3)
	_check("menu_resume_restarts_dog_and_signal_clocks",scene.street_pedestrians.elapsed>clock and network.elapsed_s!=signal_clock)
	scene.movement_switch.set_pressed_no_signal(false);scene.movement_switch.toggled.emit(false);await _ticks(2);frozen=_dog_poses();clock=scene.street_pedestrians.elapsed
	await _seconds(.6)
	_check("actual_pedestrian_checkbox_freezes_keeper_and_dog",not scene.street_pedestrians.running and _dog_poses()==frozen and scene.street_pedestrians.elapsed==clock)
	scene.movement_switch.set_pressed_no_signal(true);scene.movement_switch.toggled.emit(true);await _seconds(.3)
	_check("actual_pedestrian_checkbox_resumes_same_dog_groups",scene.street_pedestrians.running and scene.street_pedestrians.elapsed>clock)

func _aim_normal_view(toward: Vector3,distance: float) -> void:
	var direction: Vector3=toward-scene.player.global_position;direction.y=0
	scene.rig.yaw=atan2(-direction.x,-direction.z);scene.rig.pitch=deg_to_rad(-12.);scene.rig.requested_distance=distance;scene.rig.snap_to_target_pose();await _ticks(5)

func _far_signal_view(head: Node3D) -> Dictionary:
	var eye: Vector3=scene.rig.camera.global_position;var target: Vector3=head.to_global(Vector3(.18,-.16,.128))
	var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye,target,1|32,[scene.player.get_rid()]))
	var blockers: Array=[]
	for row: Dictionary in network.signals:
		if row.head==head:continue
		var title: String="PedestrianSignalCase" if row.kind=="pedestrian" else "HorizontalSignalCase"
		var case: MeshInstance3D=row.head.get_node(title)
		if case.mesh.get_aabb().intersects_segment(case.to_local(eye),case.to_local(target))!=null:blockers.append(row.id)
	return {"clear":hit.is_empty() and blockers.is_empty(),"camera_eye":eye,"far_face_target":target,"static_obstacle":String(hit.collider.name) if not hit.is_empty() else "","intervening_rendered_signal_cases":blockers}

func _normal_view(title: String,toward: Vector3,distance: float,far_signal: Node3D=null) -> void:
	await _aim_normal_view(toward,distance)
	var evidence: Dictionary={"distance_m":scene.rig.current_distance,"player":scene.player.global_position};var signal_clear:=true
	if far_signal!=null:
		var sight: Dictionary=_far_signal_view(far_signal);signal_clear=sight.clear;evidence.merge(sight)
	_check("view_"+title+"_normal_camera_and_visible_player",_camera_clear() and scene.rig.current_distance>1.8 and scene.player.get_node("Visual").visible and signal_clear,evidence)
	await _capture_frame(title,false)

func _capture_frame(title: String,ride: bool) -> void:
	if not native:captures.append({"name":title,"captured":false,"reason":"headless_has_no_pixels"});return
	await process_frame;RenderingServer.force_draw(false,0);await RenderingServer.frame_post_draw
	var picture: Image=scene.get_viewport().get_texture().get_image();var path: String=report_path.trim_suffix(".json")+"_"+title+".png"
	var saved: bool=not picture.is_empty() and picture.save_png(path)==OK
	var row: Dictionary={"name":title,"captured":saved,"path":path,"width":picture.get_width(),"height":picture.get_height(),"player":scene.player.global_position,"camera":scene.rig.camera.global_transform,"camera_distance_m":scene.rig.current_distance,"player_visual_visible":scene.player.get_node("Visual").visible,"seated_passenger_model":ride and transit.riding and transit.passenger.visible,"time_id":scene.time_id,"basis":"Actual frame_post_draw viewport and ordinary production camera; explicit player observer/shortcut only"}
	captures.append(row);_check("capture_"+title,saved,row)

func _street_views_and_lighting() -> void:
	var reached: bool=await _shortcut("신호등·횡단보도로 이동")
	_check("crossing_shortcut_commits_supported_destination",reached and scene.player.is_on_floor(),{"point":scene.player.global_position})
	if reached:
		await _normal_view("crossing_wide",scene.city.to_global(Vector3(84,0,-193)),4.5)
		_clock(31.0);await _normal_view("crossing_pedestrian_green",scene.city.to_global(Vector3(82,0,-195)),4.0)
	var previous_time: String=scene.time_id;var previous_quality: String=scene.quality_id
	for id: String in ["evening","night"]:
		await _menu(true);var index: int=["day","evening","night"].find(id);scene.time_option.select(index);scene.time_option.item_selected.emit(index)
		await _menu(false)
		var lamp_shortcut: bool=await _shortcut("가로등 거리로 이동");await _seconds(.4)
		var snap: Dictionary=network.snapshot();var nearest: Dictionary={};var distance_to_lamp:=INF
		for lamp: Dictionary in network.lamps:
			if lamp.light.visible and lamp.point.distance_to(scene.player.global_position)<distance_to_lamp:nearest=lamp;distance_to_lamp=lamp.point.distance_to(scene.player.global_position)
		var lit_ground: Vector3=scene.player.global_position
		if not nearest.is_empty():lit_ground=nearest.light.global_position;lit_ground.y=scene.terrain_surface.ground_y_world(lit_ground)+.08
		_check("menu_time_"+id+"_actual_warm_lights_bounded",lamp_shortcut and scene.time_id==id and snap.time_id==id and snap.active_lights>0 and snap.active_lights<=12 and not nearest.is_empty(),{"active":snap.active_lights,"budget":snap.light_budget,"time_id":snap.time_id,"actual_lamp_shortcut":lamp_shortcut,"nearest_active_lamp":nearest.get("id",""),"spot_energy":nearest.light.light_energy if not nearest.is_empty() else 0.,"spot_ground_target":lit_ground,"player":scene.player.global_position})
		await _normal_view("warm_lamp_street_"+id,lit_ground,4.5)
		scene.apply_quality("low");snap=network.snapshot();_check("quality_low_warm_light_budget_"+id,snap.active_lights<=6 and snap.light_budget==6,{"active":snap.active_lights,"budget":snap.light_budget});scene.apply_quality(previous_quality)
	scene.set_time_profile(previous_time);scene.apply_quality(previous_quality);_clock(0.0)
	_check("time_quality_restored",scene.time_id==previous_time and scene.quality_id==previous_quality)

func _small_menu() -> void:
	await _menu(true);var old: Vector2i=root.size;root.size=Vector2i(640,480)
	for i: int in range(5):await process_frame
	scene._layout_v0();for i: int in range(3):await process_frame
	var view: Rect2=scene.get_viewport().get_visible_rect();var rect: Rect2=scene.exploration_menu_scroll.get_global_rect()
	_check("small_640_menu_scroll_within_viewport",view.grow(1).encloses(rect) and scene.exploration_menu_scroll.get_v_scroll_bar().max_value>rect.size.y,{"viewport":view,"scroll_rect":rect,"content_height":scene.exploration_menu_content.size.y,"max_scroll":scene.exploration_menu_scroll.get_v_scroll_bar().max_value})
	await _capture_frame("small_menu_640",false);root.size=old;for i: int in range(3):await process_frame
	await _menu(false)

func _transaction_state() -> Dictionary:
	return {"player":scene.player.global_transform,"free_roam":scene.free_roam_enabled,"player_free_roam":scene.player.free_roam_enabled,"mask":scene.player.collision_mask,"riding":transit.riding,"player_physics":scene.player.is_physics_processing(),"facility":scene.player.facility_control,"camera_excludes":scene.rig._query.exclude.duplicate()}

func _transaction_regressions() -> void:
	scene.set_vehicles_running(false)
	# Explicit lifecycle fixture only: the natural bus journey is separately
	# observed above/on the bus suite. Do not relocate any vehicle or claim this
	# direct boarding state establishes a real first-stop arrival.
	placements.append({"name":"transactional_menu_direct_boarding_state","kind":"explicit_test_only_bus_state_fixture_no_bus_pose_write","bus_station_m":transit.bus.get_station_m()})
	await _pose("transactional_player_source_start",visit._world_spawn)
	scene.set_free_roam(false);transit.bus_state="doors_open";transit.docked_stop=0;transit.door_fraction=1.0;transit.bus._speed_mps=0.0
	var fixture_boarded:=false;var candidates:=0
	for door_z: float in [-2.95,.55]:
		var requested: Vector3=transit.bus.to_global(Vector3(2.4,0,door_z));requested.y=scene.terrain_surface.ground_y_world(requested)+.08
		var safe: Dictionary=scene._exploration_destination(requested)
		if safe.is_empty():continue
		# Synchronous player-only fixture: mode staysOFF and no tick advances on
		# the road before production boarding suspends the original capsule.
		placements.append({"name":"transactional_player_at_actual_bus_door","kind":"explicit_player_only_fixture_no_bus_pose_write","point":safe.point,"door_z":door_z})
		scene.player.global_transform=Transform3D(Basis.IDENTITY,safe.point);scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();candidates+=1
		if transit._board():fixture_boarded=true;break
	_check("transaction_fixture_boarded_with_free_roam_OFF",fixture_boarded and transit.riding and not scene.free_roam_enabled and not scene.player.free_roam_enabled,{"native_supported_door_candidates":candidates})
	if not fixture_boarded:scene.set_free_roam(true);return
	var before: Dictionary=_transaction_state()
	var rejected: Dictionary=scene._exploration_destination(Vector3(INF,INF,INF))
	_check("failed_prospective_destination_preserves_ride_and_mode",rejected.is_empty() and _transaction_state()==before)
	var pool: Dictionary=scene.exploration_rooftop_access.representative_pool_destination()
	if pool.is_empty():_check("transaction_pool_exists",false);return
	var blocker: StaticBody3D=_blocker("ExplicitPoolEntryBlockingFixture",pool.pool_entry)
	await _ticks(2);before=_transaction_state();scene._visit_street_detail("hotel_pool")
	_check("blocked_pool_shortcut_keeps_riding_and_free_roam_OFF",_transaction_state()==before,{"state":_transaction_state(),"target":pool.pool_entry,"notice":scene.exploration_notice.text})
	blocker.queue_free();await _ticks(2);scene._visit_street_detail("hotel_pool");await _ticks(4)
	_check("validated_pool_commit_restores_control_and_enables_free_roam",not transit.riding and scene.free_roam_enabled and scene.player.free_roam_enabled and scene.player.is_physics_processing() and not scene.player.facility_control and scene.player.global_position.distance_to(pool.pool_entry)<.20,{"player":scene.player.global_position,"target":pool.pool_entry,"capsule":_player_shape()})
	scene.rig.requested_distance=13.0;await _menu(true);scene._visit_library_entrance();await _ticks(6)
	_check("library_shortcut_overrides_saved_far_camera",not scene.menu.visible and not paused and scene.player.global_position.distance_to(visit.entrance_world_position)<.20 and scene.rig.camera.global_position.distance_to(scene.player.global_position)<7.0,{"requested_distance_m":scene.rig.requested_distance,"actual_distance_m":scene.rig.camera.global_position.distance_to(scene.player.global_position)})
	scene.set_vehicles_running(true)

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var failed:=0
	for row: Dictionary in checks:
		if not bool(row.passed):failed+=1
	var report: Dictionary={"task":"EXP23_STREET_TRANSIT","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed,"requested_physics_hz":requested_hz,"actual_physics_hz":Engine.physics_ticks_per_second,"wall_usec":Time.get_ticks_usec()-began_usec},"checks":checks,"observations":observations,"scenario_starts":placements,"captures":captures,"scope":"Production exploration: original car spawn-to-red-stop and green-crossing journey with no car pose writes; original inventory/capsule/XZ/TIN, real menu/dog shortcut/clock/checkbox checks and labelled player/fault/direct-boarding fixtures for transactional shortcut regression. Native mode additionally observes natural bus arrival/fresh-E ride/exit and captures actual frame_post_draw pixels with the normal third-person camera. Headless creates no native appearance or performance acceptance; game-authored timings/places are not real schedules or measured infrastructure."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot save street-transit report");quit(1);return
	file.store_string(JSON.stringify(_json(report),"\t"));file.close()
	print("STREET_TRANSIT_RESULT ",checks.size()-failed,"/",checks.size()," report=",report_path);quit(0 if failed==0 else 1)
