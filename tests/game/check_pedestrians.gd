extends "res://test_support/check_walkable_milestone.gd"
## N02 independent observations; setup moves only the player between named cases.
var npc_cases := []
var route_map := {}
var target_actor: CharacterBody3D

func _npc_sample(actor: CharacterBody3D) -> Dictionary:
	var row: Dictionary=actor.snapshot()
	var p: Vector3=actor.global_position
	row["floor_id"]=""
	var ray:=PhysicsRayQueryParameters3D.create(p+Vector3.UP*.3,p-Vector3.UP*.3,1,[actor.get_rid()])
	var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():row.floor_id=hit.collider.get_meta("geometry_id","")
	row["inside_movement"]=scene.city.movement_contains(Vector2(p.x,p.z))
	row["penetration_m"]=scene.city.volume_penetration(p,1.7,.3)
	var line: Array=route_map[row.route_id].xz
	var closest:=INF
	for i in range(line.size()-1):
		var a:=Vector2(line[i][0],line[i][1])
		var b:=Vector2(line[i+1][0],line[i+1][1])
		closest=minf(closest,Vector2(p.x,p.z).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(p.x,p.z),a,b)))
	row["observed_route_error_m"]=closest
	return row

func _npc_rows() -> Array:
	var rows:=[]
	for actor in scene.pedestrians:rows.append(_npc_sample(actor))
	return rows

func _player_row() -> Dictionary:
	return {"position":_v(scene.player.global_position),"velocity":_v(scene.player.velocity),"recoveries":scene.player.recoveries,
		"floor":scene.player.is_on_floor(),"inside_movement":scene.city.movement_contains(Vector2(scene.player.position.x,scene.player.position.z)),
		"penetration_m":scene.city.volume_penetration(scene.player.global_position,1.7,.3),"camera_mask":scene.rig.arm.collision_mask}

func _case(title: String,seconds: float,walk:=Vector3.ZERO) -> Dictionary:
	var start_rows:=_npc_rows()
	var start_player:=_player_row()
	var first:=Engine.get_physics_frames()+1
	var started:=Time.get_ticks_usec()
	var start_frames:=frames
	var tick:=0
	var samples:=[]
	var stats:={"min_npc_count":2,"max_npc_count":2,"floor_ticks":0,"outside_ticks":0,"max_step_m":0.,"max_route_error_m":0.,"max_source_penetration_m":0.,
		"min_player_distance_m":INF,"min_y":INF,"max_y":-INF,"max_yaw_step_rad":0.,"max_horizontal_velocity_mps":0.,"over_nominal_ticks":0,"contact_examples":[]}
	var previous: Array=start_rows
	var target_ticks:=int(round(seconds*60))
	while tick<target_ticks:
		if walk.length_squared()>0:_world_keys(walk,false)
		else:_keys([])
		await scene.rig.camera_stepped
		tick+=1
		var rows:=_npc_rows()
		stats.min_npc_count=mini(stats.min_npc_count,scene.pedestrian_root.get_child_count())
		stats.max_npc_count=maxi(stats.max_npc_count,scene.pedestrian_root.get_child_count())
		for i in range(rows.size()):
			var row: Dictionary=rows[i]
			var p:=Vector3(row.position[0],row.position[1],row.position[2])
			stats.max_horizontal_velocity_mps=maxf(stats.max_horizontal_velocity_mps,Vector2(row.velocity[0],row.velocity[2]).length())
			if row.on_floor and row.floor_id=="W03_support":stats.floor_ticks+=1
			if not row.inside_movement:stats.outside_ticks+=1
			var step:=Vector2(p.x,p.z).distance_to(Vector2(previous[i].position[0],previous[i].position[2]))
			stats.max_step_m=maxf(stats.max_step_m,step)
			if step>.0202:
				stats.over_nominal_ticks+=1
				if stats.contact_examples.size()<8:
					var contacts:=[]
					var body: CharacterBody3D=scene.pedestrians[i]
					for j in range(body.get_slide_collision_count()):
						var collision:=body.get_slide_collision(j)
						contacts.append({"body":collision.get_collider().get_meta("geometry_id",""),"normal":_v(collision.get_normal()),"depth_m":collision.get_depth()})
					stats.contact_examples.append({"route_id":row.route_id,"step_m":step,"contacts":contacts})
			stats.max_route_error_m=maxf(stats.max_route_error_m,row.observed_route_error_m)
			stats.max_source_penetration_m=maxf(stats.max_source_penetration_m,row.penetration_m)
			stats.min_player_distance_m=minf(stats.min_player_distance_m,Vector2(p.x-scene.player.position.x,p.z-scene.player.position.z).length())
			stats.min_y=minf(stats.min_y,p.y);stats.max_y=maxf(stats.max_y,p.y)
			stats.max_yaw_step_rad=maxf(stats.max_yaw_step_rad,absf(wrapf(row.visual_yaw_rad-previous[i].visual_yaw_rad,-PI,PI)))
		previous=rows
		if tick==1 or tick%6==0 or tick==target_ticks:
			samples.append({"tick":Engine.get_physics_frames(),"t":tick/60.,"player":_player_row(),"npcs":rows})
	_keys([])
	var record:={"name":title,"ticks":tick,"duration_s":tick/60.,"wall_s":(Time.get_ticks_usec()-started)/1000000.,"frames":frames-start_frames,
		"first_tick":first,"last_tick":Engine.get_physics_frames(),"start":start_rows,"end":_npc_rows(),"player_start":start_player,"player_end":_player_row(),
		"stats":stats,"samples":samples,"target_route_id":"plaza_front"}
	npc_cases.append(record)
	print("N02_CASE ",title," ticks=",tick," ends=",record.end.map(func(v):return v.end_events)," states=",record.end.map(func(v):return v.state))
	return record

func _at(actor: CharacterBody3D,station: float) -> Vector3:
	var r: Dictionary=route_map[actor.snapshot().route_id]
	var left:=clampf(station,0,float(r.length_m))
	for i in range(r.xz.size()-1):
		var a:=Vector3(r.xz[i][0],.08,r.xz[i][1])
		var b:=Vector3(r.xz[i+1][0],.08,r.xz[i+1][1])
		var length:=a.distance_to(b)
		if left<=length:return a.lerp(b,left/length)
		left-=length
	return _point(r.xz[-1])

func _tangent(actor: CharacterBody3D) -> Vector3:
	var snap: Dictionary=actor.snapshot()
	var d: Vector3=_at(actor,snap.station_m+snap.direction*.1)-_at(actor,snap.station_m-snap.direction*.1)
	return d.normalized()

func _middle() -> void:
	await _pose(_point(scene.city.public_data.routes[0].xz[0]),scene.starting_yaw)
	for i in range(2400):
		var row: Dictionary=target_actor.snapshot()
		if row.state=="walking" and row.station_m>13 and row.station_m<row.route_length_m-13:return
		await _wait(1./60)
	push_error("N02 target never reached middle")

func _stand_ahead() -> void:
	await _middle()
	var row: Dictionary=target_actor.snapshot()
	var point:=_at(target_actor,row.station_m+row.direction*1.5)
	var d:=_tangent(target_actor)
	await _pose(point,atan2(d.x,d.z))

func _inspect(actor: CharacterBody3D,title: String) -> void:
	scene.set_pedestrians_running(false)
	var row: Dictionary=actor.snapshot()
	var p:=_at(actor,row.station_m+(5. if row.station_m<6. else -5.))
	var delta: Vector3=actor.global_position-p
	await _pose(p,atan2(-delta.x,-delta.z))
	await _capture(title)
	scene.set_pedestrians_running(true)

func _run() -> void:
	scene=load("res://scenes/world/pedestrian_walk.tscn").instantiate();root.add_child(scene)
	if not scene.runtime_ok:
		var rejected:={"task":"N02","rejected":true,"reason":scene.pedestrian_error,"npc_count":scene.pedestrian_root.get_child_count()}
		FileAccess.open(output_path,FileAccess.WRITE).store_string(JSON.stringify(rejected)+"\n")
		scene.queue_free();quit(0);return
	scene.input_router.set_script(load("res://test_support/daehanmun_probe_input.gd"));scene.input_router.isolate_movement_bindings()
	for route in scene.pedestrian_bundle.routes:route_map[route.id]=route
	target_actor=scene.pedestrians[1]
	var initial_npcs:=_npc_rows()
	if variant=="npc_mask":target_actor.collision_mask=0
	await _wait(1.)
	var before:=_inventory()
	var descriptors:=[]
	for actor in scene.pedestrians:
		var capsule: CapsuleShape3D=actor.get_node("CollisionShape").shape
		descriptors.append({"id":actor.snapshot().route_id,"height":capsule.height,"radius":capsule.radius,"layer":actor.collision_layer,"mask":actor.collision_mask,"safe_margin":actor.safe_margin,"process_mode":actor.process_mode})
	var player_shape: CapsuleShape3D=scene.player.get_node("CollisionShape").shape
	var player_descriptor:={"height":player_shape.height,"radius":player_shape.radius,"layer":scene.player.collision_layer,"mask":scene.player.collision_mask,"camera_mask":scene.rig.arm.collision_mask}
	await _case("free_cycles",280. if suite=="full" else 12.)
	scene.movement_switch.button_pressed=false
	await _case("manual_stop",2.)
	scene.movement_switch.button_pressed=true
	await _case("manual_resume",3.)
	await _stand_ahead()
	await _case("brief_block",.8)
	await _case("clear_and_resume",4.,Vector3.BACK)
	await _stand_ahead()
	await _case("persistent_block",5.)
	await _middle()
	target_actor.set_running(false)
	var snap: Dictionary=target_actor.snapshot()
	var direction:=_tangent(target_actor)
	await _pose(_at(target_actor,snap.station_m-snap.direction*1.5),atan2(-direction.x,-direction.z))
	await _case("player_push",4.,direction)
	target_actor.set_running(true)
	await _case("backoff",2.,-direction)
	await _case("escape",6.,direction)
	_keys([])
	var menu_before:=_npc_rows()
	await _escape()
	var opened:=paused
	var tree_paused: bool=scene.get_tree().paused
	var menu_hold_before:=_npc_rows()
	var menu_player_before:=_player_row()
	var menu_time:=Time.get_ticks_usec()
	await create_timer(.5).timeout
	var menu_after:=_npc_rows()
	var menu_wall:=(Time.get_ticks_usec()-menu_time)/1000000.
	var menu_player_after:=_player_row()
	await _capture("menu")
	await _escape()
	var menu_event:={"opened":opened,"closed":not paused,"tree_paused":tree_paused,"wall_s":menu_wall,"before":menu_before,"hold_before":menu_hold_before,"after":menu_after,"player_before":menu_player_before,"player_after":menu_player_after}
	var count_before: int=scene.pedestrians.size()
	var duplicate: bool=scene.spawn_pedestrians()
	var spawn_event:={"attempt_return":duplicate,"before":count_before,"after":scene.pedestrian_root.get_child_count()}
	await _inspect(scene.pedestrians[0],"palace_walker")
	await _inspect(scene.pedestrians[1],"plaza_walker")
	var record:={"schema_version":1,"task":"N02","suite":suite,"fault":variant,"engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"physics_hz":Engine.physics_ticks_per_second,"render_fps":fps},
		"bundle_sha256":FileAccess.get_sha256("res://data/generated/pedestrians.json"),"initial_npcs":initial_npcs,"static_inventory":before,"static_inventory_after":_inventory(),"descriptors":descriptors,"player_descriptor":player_descriptor,
		"cases":npc_cases,"menu_event":menu_event,"spawn_event":spawn_event,"captures":capture_names,
		"city_visuals":load("res://test_support/city_visual_observation.gd").collect(scene),"palace_visuals":load("res://test_support/palace_visual_observation.gd").collect(scene),
		"scope":"NPC autonomous within cases; player placements between setups. Actual source geometry retained; no vehicle/human/M4/performance acceptance"}
	FileAccess.open(output_path,FileAccess.WRITE).store_string(JSON.stringify(record)+"\n")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	scene.queue_free();quit(0)
