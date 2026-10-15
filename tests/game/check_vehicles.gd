extends "res://test_support/check_pedestrians.gd"
## N03 source-bound physical cases. Scene resets and human fixtures are explicit.
var vehicle_cases:=[]
var sessions:=[]
var source_routes: Dictionary={}
var scene_index:=0
var fixtures: Array[CharacterBody3D]=[]

func _player_row() -> Dictionary:
	var row:=super._player_row()
	var contacts:=[]
	for i in range(scene.player.get_slide_collision_count()):
		var hit: KinematicCollision3D=scene.player.get_slide_collision(i)
		contacts.append({"id":hit.get_collider().get_meta("geometry_id",""),"layer":hit.get_collider().collision_layer})
	row["contacts"]=contacts
	return row

func _vehicle_rows() -> Array:
	var rows:=[]
	for v in scene.vehicles:
		var row: Dictionary=v.snapshot()
		var p: Vector3=v.global_position
		var floor_hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*.3,p-Vector3.UP*.3,17,[v.get_rid()]))
		row["floor_id"]="" if floor_hit.is_empty() else floor_hit.collider.get_meta("geometry_id","")
		row["yaw_rad"]=v.rotation.y
		var contacts:=[]
		for j in range(v.get_slide_collision_count()):
			var hit: KinematicCollision3D=v.get_slide_collision(j)
			contacts.append({"id":hit.get_collider().get_meta("geometry_id",""),"layer":hit.get_collider().collision_layer,"normal":_v(hit.get_normal())})
		row["contacts"]=contacts
		rows.append(row)
	return rows

func _fresh_scene() -> bool:
	if is_instance_valid(scene):
		sessions.append({"index":scene_index,"events":scene.traffic.events.duplicate(true),"inventory_after":_inventory()})
		scene.queue_free();scene=null
	await process_frame
	await process_frame
	scene_index+=1
	scene=load("res://scenes/world/traffic_walk.tscn").instantiate();root.add_child(scene)
	if not scene.runtime_ok:return false
	scene.input_router.set_script(load("res://test_support/daehanmun_probe_input.gd"));scene.input_router.isolate_movement_bindings()
	for route in scene.pedestrian_bundle.routes:route_map[route.id]=route
	for route in scene.traffic_bundle.routes:source_routes[route.id]=route
	fixtures.clear()
	await _wait(.5)
	return true

func _car_at(id: String,station: float) -> Vector3:
	var r: Dictionary=source_routes[id]
	var remaining:=clampf(station,0,r.length_m)
	for i in range(r.xz.size()-1):
		var a:=Vector3(r.xz[i][0],0,r.xz[i][1]);var b:=Vector3(r.xz[i+1][0],0,r.xz[i+1][1])
		var distance:=a.distance_to(b)
		if remaining<=distance:return a.lerp(b,remaining/distance)
		remaining-=distance
	return _point(r.xz[-1])-Vector3.UP*.08

func _place_player(p: Vector3,yaw: float) -> void:
	_keys([]);scene.player.global_position=p;scene.player.velocity=Vector3.ZERO;scene.player.input_latched=false
	scene.rig.yaw=yaw;scene.rig.pitch=deg_to_rad(-15);scene.rig.requested_distance=4.5;scene.rig.current_distance=4.5;scene.rig.arm.spring_length=4.5

func _far_player(facing_portals: bool) -> void:
	if facing_portals:
		var spawn: Array=scene.city.public_data.spawn
		var visible_position:=Vector3(spawn[0],scene.player.position.y,spawn[2])
		var direction:=_car_at("sejong_north",0)-visible_position
		_place_player(visible_position,atan2(-direction.x,-direction.z))
		return
	var route: Array=scene.city.public_data.routes[1].xz
	var far: Array=route[0]
	for p in route:
		if p[0]<far[0]:far=p
	var position:=Vector3(far[0],scene.player.position.y,far[1])
	_place_player(position,PI/2)

func _case_cars(title: String,seconds: float,walk:=Vector3.ZERO) -> Dictionary:
	var before:=_vehicle_rows();var first:=Engine.get_physics_frames()+1;var started:=Time.get_ticks_usec();var f0:=frames
	var rows:=[];var previous: Array=before
	var stats:={"floor_ticks":0,"max_step_m":0.,"max_y_m":0.,"max_speed_mps":0.,"max_command_mps":0.,"min_count":2,"max_count":2,"human_contacts":0,"recycles":0}
	var count:=int(round(seconds*60))
	for tick in range(1,count+1):
		if walk.length_squared()>0:_world_keys(walk,false)
		else:_keys([])
		await scene.rig.camera_stepped
		var current:=_vehicle_rows()
		stats.min_count=mini(stats.min_count,scene.vehicles.size());stats.max_count=maxi(stats.max_count,scene.vehicles.size())
		for i in range(current.size()):
			var v: Dictionary=current[i]
			if v.on_floor and v.floor_id in ["W03_support","N03_support_sejong_south","N03_support_sejong_north"]:stats.floor_ticks+=1
			var recycled: bool=v.cycle_count!=previous[i].cycle_count
			if recycled:stats.recycles+=1
			else:stats.max_step_m=maxf(stats.max_step_m,Vector2(v.position[0]-previous[i].position[0],v.position[2]-previous[i].position[2]).length())
			stats.max_y_m=maxf(stats.max_y_m,absf(v.position[1]))
			stats.max_speed_mps=maxf(stats.max_speed_mps,v.speed_mps)
			stats.max_command_mps=maxf(stats.max_command_mps,v.command_speed_mps)
			for hit in v.contacts:
				if int(hit.layer)&6:stats.human_contacts+=1
		previous=current
		if tick==1 or tick%6==0 or tick==count:
			rows.append({"tick":Engine.get_physics_frames(),"t":tick/60.,"vehicles":current,"traffic":scene.traffic.snapshot(),"player":_player_row(),"npcs":_npc_rows()})
	_keys([])
	var record:={"name":title,"session":scene_index,"ticks":count,"duration_s":seconds,"first_tick":first,"last_tick":Engine.get_physics_frames(),"wall_s":(Time.get_ticks_usec()-started)/1000000.,"frames":frames-f0,
		"start":before,"end":_vehicle_rows(),"stats":stats,"samples":rows}
	vehicle_cases.append(record)
	print("N03_CASE ",title," states=",record.end.map(func(v):return v.state)," stations=",record.end.map(func(v):return v.station_m)," cycles=",record.end.map(func(v):return v.cycle_count))
	return record

func _fixture(point: Vector3,layer: int,box: bool=false) -> CharacterBody3D:
	var body:=CharacterBody3D.new();body.name="ContactFixture";body.collision_layer=layer;body.collision_mask=31 if box else 15
	body.set_meta("geometry_id","N03_test_fixture")
	var collision:=CollisionShape3D.new()
	if box:
		var shape:=BoxShape3D.new();shape.size=Vector3(1.8,1.5,4.2);collision.shape=shape;collision.position.y=.75
	else:
		var shape:=CapsuleShape3D.new();shape.radius=.3;shape.height=1.7;collision.shape=shape;collision.position.y=.85
	body.add_child(collision);root.add_child(body);body.position=point;fixtures.append(body)
	if not box:scene.traffic.register_human(body)
	return body

func _remove_fixture(body: CharacterBody3D) -> void:
	scene.traffic.humans.erase(body);fixtures.erase(body);body.free()

func _run() -> void:
	if not await _fresh_scene():
		FileAccess.open(output_path,FileAccess.WRITE).store_string(JSON.stringify({"task":"N03","rejected":true,"reason":scene.traffic_error,"vehicle_count":scene.vehicles.size(),"support_count":scene.road_supports.size()})+"\n");quit(0);return
	var initial_inventory:=_inventory()
	var descriptors:=[]
	var support_descriptors:=[]
	for body in scene.road_supports:
		support_descriptors.append(_body_row(body.get_meta("geometry_id"),body))
	for body in scene.vehicles:
		descriptors.append({"id":body.get_route_id(),"size":_v(body.get_node("CollisionShape").shape.size),"layer":body.collision_layer,"mask":body.collision_mask,"priority":body.process_physics_priority,"safe_margin":body.safe_margin})
	if variant=="vehicle_mask":scene.vehicles[0].collision_mask=15
	_far_player(false);await _wait(.5)
	await _case_cars("free_cycles",150. if suite=="full" else 12.)
	if suite=="full":
		await _fresh_scene()
		_place_player(Vector3(80.5415013,scene.player.position.y,-194.6255234),PI/2)
		await _case_cars("occupied_queue",55.)
		_far_player(false)
		await _case_cars("clear_short",.8)
		await _case_cars("release_fifo",16.)
		await _fresh_scene();_far_player(false)
		scene.traffic.observations_enabled=false
		await _case_cars("stale_hold",3.)
		scene.traffic.observations_enabled=true
		await _case_cars("fresh_resume",6.)
		await _fresh_scene();_far_player(false)
		var target: CharacterBody3D=scene.vehicles[0]
		for i in range(1200):
			if target.get_station_m()>=source_routes.sejong_south.conflicts[0].enter_s_m+.1:break
			await _wait(1./60)
		var before_human: Dictionary=target.snapshot()
		_place_player(Vector3(80.5415013,scene.player.position.y,-194.6255234),PI/2)
		var late:=await _case_cars("late_human",3.)
		late["injection"]={"vehicle_before":before_human,"human_position":_v(scene.player.position)}
		_far_player(false);await _case_cars("late_clear",7.)
		await _fresh_scene();_far_player(false)
		var npc:=_fixture(_car_at("sejong_south",50.),4)
		await _case_cars("npc_obstacle",22.)
		_remove_fixture(npc);await _case_cars("npc_clear",7.)
		await _fresh_scene();_far_player(false)
		target=scene.vehicles[0]
		var middle: float=(source_routes.sejong_south.conflicts[0].enter_s_m+source_routes.sejong_south.conflicts[0].exit_s_m)*.5
		for i in range(1500):
			if target.get_station_m()>=middle:break
			await _wait(1./60)
		target.set_running(false)
		var west:=Vector3(66.1017243,scene.player.position.y,-195.0030993)
		var approach: Vector3=target.global_position-west;approach.y=0;approach=approach.normalized()
		_place_player(west,atan2(-approach.x,-approach.z))
		await _case_cars("player_push",12.,approach)
		await _case_cars("player_backoff",3.,-approach)
		target.set_running(true)
		await _case_cars("player_exit",10.,-approach)
		await _fresh_scene();_far_player(true)
		await _case_cars("visible_guard",70.)
		var near:=_fixture(_car_at("sejong_north",0)+Vector3.RIGHT*8.,4)
		_far_player(false);await _case_cars("near_human_guard",2.)
		_remove_fixture(near)
		var entry:=_fixture(_car_at("sejong_north",0),8,true)
		await _case_cars("entry_guard",2.)
		_remove_fixture(entry);await _case_cars("recycle_release",3.)
	scene.traffic_switch.button_pressed=false
	_place_player(Vector3(95.984174,scene.player.position.y,-196.502149),PI/2)
	await _case_cars("manual_stop",2.)
	_far_player(false)
	scene.traffic_switch.button_pressed=true
	await _case_cars("manual_resume",3.)
	# Separate review pose after all timed cases; never evidence of a walking journey.
	var review_position:=Vector3(66.1017243,scene.player.position.y,-195.0030993)
	var review_direction: Vector3=scene.vehicles[0].global_position-review_position
	_place_player(review_position,atan2(-review_direction.x,-review_direction.z))
	await _wait(.5)
	var review:={"player":_player_row(),"vehicles":_vehicle_rows(),"camera_position":_v(scene.rig.camera.global_position),"scope":"explicit post-case review pose"}
	var held_before:=_vehicle_rows();await _escape();var tree_paused: bool=scene.get_tree().paused
	var hold:=_vehicle_rows();var t:=Time.get_ticks_usec();await create_timer(.5).timeout
	var held_after:=_vehicle_rows();await _capture("menu");await _escape()
	var menu:={"tree_paused":tree_paused,"closed":not paused,"wall_s":(Time.get_ticks_usec()-t)/1000000.,"before":held_before,"hold":hold,"after":held_after}
	var duplicate: bool=scene.spawn_traffic()
	await _capture("traffic")
	sessions.append({"index":scene_index,"events":scene.traffic.events.duplicate(true),"inventory_after":_inventory()})
	var record:={"schema_version":1,"task":"N03","suite":suite,"fault":variant,"engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"physics_hz":Engine.physics_ticks_per_second,"render_fps":fps},
		"bundle_sha256":FileAccess.get_sha256("res://data/generated/traffic.json"),"descriptors":descriptors,"support_descriptors":support_descriptors,"initial_inventory":initial_inventory,"cases":vehicle_cases,"sessions":sessions,"menu":menu,"duplicate_spawn_return":duplicate,"captures":capture_names,
		"city_visuals":load("res://test_support/city_visual_observation.gd").collect(scene),"palace_visuals":load("res://test_support/palace_visual_observation.gd").collect(scene),
		"review":review,"scope":"Scene resets between independent scenarios; player injections and stationary capsule/entry-box fixtures explicit. No human handling/M4/performance/N04 acceptance."}
	FileAccess.open(output_path,FileAccess.WRITE).store_string(JSON.stringify(record)+"\n")
	scene.queue_free();quit(0)
