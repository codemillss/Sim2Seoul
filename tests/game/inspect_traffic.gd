extends "res://test_support/check_vehicles.gd"
## Paused close review of the actual N03 scene, separate from timed motion tests.

func _screen_bounds(points: Array[Vector3]) -> Rect2:
	var camera: Camera3D=scene.rig.camera
	var bounds:=Rect2(camera.unproject_position(points[0]),Vector2.ZERO)
	for point: Vector3 in points:bounds=bounds.expand(camera.unproject_position(point))
	return bounds

func _car_bounds(car: CharacterBody3D) -> Rect2:
	var corners: Array[Vector3]=[]
	for x: float in [-.9,.9]:
		for y: float in [0.,1.5]:
			for z: float in [-2.1,2.1]:corners.append(car.global_transform*Vector3(x,y,z))
	return _screen_bounds(corners)

func _player_bounds() -> Rect2:
	var points: Array[Vector3]=[]
	var right: Vector3=scene.rig.camera.global_basis.x*.3
	for y: float in [0.,1.7]:
		points.append(scene.player.global_position+Vector3.UP*y-right)
		points.append(scene.player.global_position+Vector3.UP*y+right)
	return _screen_bounds(points)

func _run() -> void:
	root.size=Vector2i(1152,720)
	if not await _fresh_scene():push_error("N03 inspection scene rejected");quit(1);return
	_far_player(false)
	var south: CharacterBody3D=scene.vehicles[0]
	var setup_ticks:=0
	while south.get_station_m()<25.2 and setup_ticks<1800:
		await scene.rig.camera_stepped
		setup_ticks+=1
	if south.get_station_m()<25.2:push_error("N03 close review did not reach source station 25.2m");quit(1);return
	scene.set_vehicles_running(false)
	scene.set_pedestrians_running(false)
	var arrived: Dictionary=south.snapshot()
	var west:=Vector3(66.1017243,scene.player.global_position.y,-195.0030993)
	var direction: Vector3=south.global_position-west
	var yaw:=atan2(-direction.x,-direction.z)
	await _pose(west,yaw,-12.)
	var orbit_degrees:=0.
	if _car_bounds(south).intersects(_player_bounds()):
		orbit_degrees=30.
		await _pose(west,yaw+deg_to_rad(orbit_degrees),-12.)
	await _capture("closeup_car")
	var descriptors:=[]
	for car in scene.vehicles:
		descriptors.append({"id":car.get_route_id(),"size":_v(car.get_node("CollisionShape").shape.size),"layer":car.collision_layer,"mask":car.collision_mask,"priority":car.process_physics_priority,"safe_margin":car.safe_margin})
	var bounds:=_car_bounds(south)
	var record:={"schema_version":1,"task":"N03",
		"scope":"Paused close review of the actual traffic scene after ordinary source-route movement; player reposition/orbit is inspection setup, not timed motion or performance evidence.",
		"bundle_sha256":FileAccess.get_sha256("res://data/generated/traffic.json"),
		"engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name()},
		"captures":capture_names,"descriptors":descriptors,"vehicles":_vehicle_rows(),
		"player":_player_row(),"camera":scene.rig.snapshot(),
		"review":{"setup_physics_ticks":setup_ticks,"arrived_before_pose":arrived,"orbit_degrees":orbit_degrees,
			"tick":Engine.get_physics_frames(),"car_screen_rect":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],
			"car_behind_camera":scene.rig.camera.is_position_behind(south.global_position+Vector3.UP*.75),
			"car_center_screen":[scene.rig.camera.unproject_position(south.global_position+Vector3.UP*.75).x,scene.rig.camera.unproject_position(south.global_position+Vector3.UP*.75).y]}}
	FileAccess.open(output_path,FileAccess.WRITE).store_string(JSON.stringify(record)+"\n")
	scene.queue_free();quit(0)
