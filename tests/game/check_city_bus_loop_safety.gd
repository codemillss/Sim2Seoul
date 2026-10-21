extends "res://../tests/game/check_city_bus_loop.gd"
func _run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/sim2seoul-loop-safety-settings.json";scene.exploration_physics_hz=60;root.add_child(scene);await _ticks(6);service=scene.city_bus_service
	_check("production_fleet_ready",scene.runtime_ok and service.loaded and service.buses.size()==3 and service.design.stops.size()==4)
	if not scene.runtime_ok or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	var outside:=0;var samples:=0;var first_outside: Dictionary={}
	var probe: CharacterBody3D=service.buses[0]
	for sample: int in range(int(ceil(float(service.design.route.length_m)/.5))+1):
		var frame: Dictionary=service._frame(minf(float(service.design.route.length_m),sample*.5));var pose: Transform3D=probe._terrain_pose(frame.point,atan2(-frame.direction.x,-frame.direction.z))
		for x: float in [-1.225,1.225]:
			for y: float in [0.,3.]:
				for z: float in [-4.5,4.5]:
					var corner: Vector3=scene.city.to_local(pose*Vector3(x,y,z));var inside:=false
					for mesh: Dictionary in service._source_meshes:
						if service._source_contains(Vector2(corner.x,corner.z),mesh):inside=true;break
					if not inside:
						outside+=1
						if first_outside.is_empty():first_outside={"station_m":sample*.5,"corner":corner}
		samples+=1
	_check("TIN_fitted_bus_all_eight_corners_project_inside_public_source_drive",outside==0,{"samples":samples,"outside_corners":outside,"first_outside":first_outside})
	var target: CharacterBody3D=service.buses[2]
	await _ticks(60);var moving: Vector3=target.to_global(Vector3(2.8,0,.55));moving.y=scene.terrain_surface.ground_y_world(moving)+.08
	var moving_pose: bool=await _pose(moving);var speed: float=target._speed_mps;await _tap()
	_check("moving_bus_rejects_actual_door_side_E",moving_pose and speed>.5 and not service.riding,{"speed_mps":speed})
	await _pose(service.design.stops[0].wait_world)
	for tick: int in range(60*60):
		await _ticks(1);service._switch_bus(target)
		if service.bus_state=="doors_open":break
	_check("natural_actual_dock",service.bus_state=="doors_open")
	if service.bus_state!="doors_open":_finish();return
	service.set_running(false);var layer: int=scene.player.collision_layer;var mask: int=scene.player.collision_mask;var shape_id: int=scene.player.get_node("CollisionShape").shape.get_instance_id()
	var count:=0;var release_ok:=true;var shift:=0.;var yaw_rows: Array=[]
	for local: Vector3 in [Vector3(1.6,0,-2.95),Vector3(2.8,0,-3.5),Vector3(1.6,0,.55),Vector3(3.2,0,1.4)]:
		service._switch_bus(target);var before: Vector3=target.global_position;var p: Vector3=target.to_global(local);p.y=scene.terrain_surface.ground_y_world(p)+.08
		var posed: bool=await _pose(p);var prior_yaw: float=target.global_rotation.y+.73;scene.rig.yaw=prior_yaw;scene.rig.snap_to_target_pose();await _tap()
		if posed and service.riding and service.active_bus()==target:count+=1
		if service.riding:await _tap()
		await _ticks(5);release_ok=release_ok and not service._collision_release_pending and scene.player.is_physics_processing() and not scene.player.facility_control and scene.player.collision_layer==layer and scene.player.collision_mask==mask and scene.player.get_node("CollisionShape").shape.get_instance_id()==shape_id and is_equal_approx(scene.rig.yaw,prior_yaw)
		yaw_rows.append({"before_boarding_yaw":prior_yaw,"after_exit_yaw":scene.rig.yaw,"bus_yaw":target.global_rotation.y})
		shift=maxf(shift,Vector2(target.global_position.x-before.x,target.global_position.z-before.z).length())
	_check("four_legal_door_positions_fresh_E_select_the_same_nearest_bus",count==4,{"count":count,"bus":target.name})
	_check("all_four_native_exits_restore_original_capsule_masks_prior_orbit_yaw_and_no_bus_jitter",release_ok and shift<.002,{"maximum_shift_m":shift,"yaw_restoration":yaw_rows})
	service._switch_bus(target);var p: Vector3=target.to_global(Vector3(-2.2,0,-2.95));p.y=scene.terrain_surface.ground_y_world(p)+.08;await _pose(p);await _tap();_check("opposite_road_side_denied",not service.riding and not service.can_interact())
	p=target.to_global(Vector3(2.2,0,.55));p.y=scene.terrain_surface.ground_y_world(p)+.08;await _pose(p);scene.player.set_physics_process(false);scene.player.global_position.y+=1.;await _ticks(2);await _tap();_check("airborne_old_floor_flag_denied",not service.riding and not service.can_interact());scene.player.set_physics_process(true)
	var wall:=StaticBody3D.new();wall.name="BusDoorWallSafetyFixture";wall.collision_layer=1;wall.collision_mask=6;var box:=BoxShape3D.new();box.size=Vector3(.18,2.2,1.8);var collider:=CollisionShape3D.new();collider.shape=box;collider.position.y=1.1;wall.add_child(collider);scene.add_child(wall);wall.global_position=target.to_global(Vector3(2.4,0,.55));wall.global_position.y=scene.terrain_surface.ground_y_world(wall.global_position)+.02;wall.global_rotation.y=target.global_rotation.y
	p=target.to_global(Vector3(3.5,0,.55));p.y=scene.terrain_surface.ground_y_world(p)+.08;var wall_pose: bool=await _pose(p);await _tap();_check("native_wall_blocks_boarding_LOS",wall_pose and not service.riding and not service.can_interact());wall.queue_free();await _ticks(3)
	p=target.to_global(Vector3(1.6,0,.55));p.y=scene.terrain_surface.ground_y_world(p)+.08;await _pose(p);service.set_running(true);var held: float=target.get_station_m();await _ticks(60*15);service._switch_bus(target)
	_check("actual_door_presence_holds_after_twelve_second_dwell",service.bus_state=="doors_open" and service.can_interact() and absf(target.get_station_m()-held)<.002,{"elapsed":service.state_elapsed})
	Input.action_press("move_forward");await _ticks(2);await _tap();Input.action_release("move_forward");_check("fresh_E_boards_while_walk_input_held",service.riding and service.active_bus()==target)
	if not service.riding:_finish();return
	service.set_running(false);var blocker:=StaticBody3D.new();blocker.name="BusExitFullCapsuleFixture";blocker.collision_layer=1;blocker.collision_mask=6;box=BoxShape3D.new();box.size=Vector3(1.4,2.5,8.0);collider=CollisionShape3D.new();collider.shape=box;collider.position.y=1.25;blocker.add_child(collider);scene.add_child(blocker);blocker.global_position=service.design.stops[service.docked_stop].wait_world;blocker.global_rotation.y=target.global_rotation.y;await _ticks(2);await _tap()
	_check("full_capsule_blocked_exit_retains_rider_and_reservation",service.riding and service.exit_requested and service._safe_exit().is_empty() and not scene.player.is_physics_processing())
	blocker.queue_free();await _ticks(2);service.set_running(true);await _ticks(6);service.set_running(false)
	_check("requested_exit_completes_only_after_native_space_clears",not service.riding and not service._collision_release_pending and scene.player.is_physics_processing() and not scene.player.facility_control)
	service._switch_bus(target);p=target.to_global(Vector3(1.6,0,.55));p.y=scene.terrain_surface.ground_y_world(p)+.08;await _pose(p);await _tap()
	var bad: bool=scene._commit_exploration_teleport(Vector3.INF)
	_check("rejected_external_target_keeps_bus_ownership",not bad and service.riding and not scene.player.is_physics_processing())
	var safe: Dictionary=scene.interior_visit._safe_external_point(service.design.stops[0].wait_world);var committed:=false
	if not safe.is_empty():committed=scene._commit_exploration_teleport(safe.point)
	await _ticks(5)
	_check("validated_external_teleport_restores_control_and_delayed_collision_pair",committed and not service.riding and not service._collision_release_pending and scene.player.is_physics_processing() and not scene.player.facility_control and scene.player.collision_layer==layer and scene.player.collision_mask==mask)
	var frozen: Array=[]
	for body: CharacterBody3D in service.buses:frozen.append(body.global_transform)
	var clocks: Array=service._fleet_snapshot().map(func(row: Dictionary):return row.state)
	await _ticks(30);var stopped:=true
	for i: int in range(service.buses.size()):stopped=stopped and service.buses[i].global_transform==frozen[i]
	_check("vehicle_checkbox_pauses_all_three_bodies",stopped)
	service.set_running(true);scene.toggle_menu();await _ticks(30);stopped=true
	for i: int in range(service.buses.size()):stopped=stopped and service.buses[i].global_transform==frozen[i]
	_check("menu_pauses_all_three_bodies",stopped);scene.toggle_menu()
	_check("original14_still_present",service.snapshot().original_vehicle_ids_unchanged)
	_finish()
