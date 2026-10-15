extends "res://test_support/check_vehicles.gd"
## One continuous N04 session. Warmup and post-journey fault events are explicit.
var guidance: RefCounted
var extra_specs: Dictionary={}
var motion_active:=false
var motion_first:=0
var motion_start_usec:=0
var motion_first_frame:=0
var motion_start: Dictionary={}
var motion_stats: Dictionary={}
var motion_samples:=[]
var motion_last_retained: int=-1
var previous_cars:=[]
var previous_people:=[]
var previous_player:=Vector3.ZERO
var motion_pose_calls:=0
var exercise_phase:="journey"
var exercise_rows:=[]
var suppress_yield:=false
var run_error:=""
var clear_watch:=""
var observed_clear_tick:=-1
var observed_clear_player: Dictionary={}

func _pose(point: Vector3,yaw:=0.,pitch:=-15.) -> void:
	if motion_active:motion_pose_calls+=1
	await super._pose(point,yaw,pitch)

func _sample(time: float) -> Dictionary:
	var row: Dictionary=super._sample(time)
	if is_instance_valid(guidance):row["guidance"]=guidance.snapshot()
	return row

func _floor_id(body: CharacterBody3D,mask: int) -> String:
	var p:=body.global_position
	var hit: Dictionary=body.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*.3,p-Vector3.UP*.3,mask,[body.get_rid()]))
	return "" if hit.is_empty() else hit.collider.get_meta("geometry_id","")

func _without_history(rows: Array) -> Array:
	for row in rows:
		row.erase("endpoint_history");row.erase("recycle_history")
	return rows

func _motion_state() -> Dictionary:
	return {"vehicles":_without_history(_vehicle_rows()),"npcs":_without_history(_npc_rows()),"player":_player_row()}

func _begin_motion() -> void:
	motion_first=Engine.get_physics_frames()+1;motion_start_usec=Time.get_ticks_usec();motion_first_frame=frames
	motion_start=_motion_state();previous_cars=motion_start.vehicles.duplicate(true);previous_people=motion_start.npcs.duplicate(true);previous_player=scene.player.global_position
	motion_stats={"ticks":0,"vehicle_min_count":2,"vehicle_max_count":2,"npc_min_count":2,"npc_max_count":2,"vehicle_floor_ticks":0,"npc_floor_ticks":0,"player_floor_ticks":0,"player_outside_ticks":0,"max_vehicle_step_m":0.,"max_npc_step_m":0.,"max_player_step_m":0.,"max_vehicle_y_m":0.,"max_npc_y_m":0.,"max_vehicle_speed_mps":0.,"max_npc_speed_mps":0.,"max_npc_source_penetration_m":0.,"max_player_penetration_m":0.,"max_camera_penetration_m":0.,"vehicle_human_contacts":0,"pose_calls":0,"recoveries":0}
	motion_stats.merge({"max_camera_overlap_count":0,"max_near_hit_count":0,"max_tick_mismatch":0,"max_follow_error_m":0.,"max_length_excess_m":0.})
	motion_active=true
	scene.rig.camera_stepped.connect(_observe_motion)

func _retain_motion() -> void:
	var tick:=Engine.get_physics_frames()
	if tick==motion_last_retained or tick<motion_first:return
	var t: float=(tick-motion_first+1)/60.
	motion_samples.append({"tick":tick,"t":t,"vehicles":_without_history(_vehicle_rows()),"npcs":_without_history(_npc_rows()),"player":_player_row(),"traffic":scene.traffic.snapshot(),"walk":_sample(t),"phase":exercise_phase})
	motion_last_retained=tick

func _observe_motion(_delta: float) -> void:
	var row:=_sample(0.)
	motion_stats.ticks+=1
	motion_stats.vehicle_min_count=mini(motion_stats.vehicle_min_count,scene.vehicles.size());motion_stats.vehicle_max_count=maxi(motion_stats.vehicle_max_count,scene.vehicles.size())
	motion_stats.npc_min_count=mini(motion_stats.npc_min_count,scene.pedestrians.size());motion_stats.npc_max_count=maxi(motion_stats.npc_max_count,scene.pedestrians.size())
	for i in range(scene.vehicles.size()):
		var body: CharacterBody3D=scene.vehicles[i]
		var p:=body.global_position
		var cycle: int=body.get("_cycle_count")
		if cycle==previous_cars[i].cycle_count:motion_stats.max_vehicle_step_m=maxf(motion_stats.max_vehicle_step_m,Vector2(p.x-previous_cars[i].position[0],p.z-previous_cars[i].position[2]).length())
		previous_cars[i]={"position":_v(p),"cycle_count":cycle}
		if body.is_on_floor() and _floor_id(body,17) in ["W03_support","N03_support_sejong_south","N03_support_sejong_north"]:motion_stats.vehicle_floor_ticks+=1
		motion_stats.max_vehicle_y_m=maxf(motion_stats.max_vehicle_y_m,absf(p.y))
		motion_stats.max_vehicle_speed_mps=maxf(motion_stats.max_vehicle_speed_mps,Vector2(body.velocity.x,body.velocity.z).length())
		for j in range(body.get_slide_collision_count()):
			var hit: KinematicCollision3D=body.get_slide_collision(j)
			if int(hit.get_collider().collision_layer)&6:motion_stats.vehicle_human_contacts+=1
	for i in range(scene.pedestrians.size()):
		var body: CharacterBody3D=scene.pedestrians[i]
		var p:=body.global_position
		motion_stats.max_npc_step_m=maxf(motion_stats.max_npc_step_m,Vector2(p.x-previous_people[i].position[0],p.z-previous_people[i].position[2]).length());previous_people[i]={"position":_v(p)}
		if body.is_on_floor() and _floor_id(body,1)=="W03_support":motion_stats.npc_floor_ticks+=1
		motion_stats.max_npc_y_m=maxf(motion_stats.max_npc_y_m,absf(p.y))
		motion_stats.max_npc_speed_mps=maxf(motion_stats.max_npc_speed_mps,Vector2(body.velocity.x,body.velocity.z).length())
		motion_stats.max_npc_source_penetration_m=maxf(motion_stats.max_npc_source_penetration_m,scene.city.volume_penetration(p,1.7,.3))
	var p: Vector3=scene.player.global_position
	motion_stats.max_player_step_m=maxf(motion_stats.max_player_step_m,p.distance_to(previous_player));previous_player=p
	if row.floor and row.floor_id=="W03_support":motion_stats.player_floor_ticks+=1
	if not row.inside_movement:motion_stats.player_outside_ticks+=1
	motion_stats.max_player_penetration_m=maxf(motion_stats.max_player_penetration_m,row.player_penetration_m);motion_stats.max_camera_penetration_m=maxf(motion_stats.max_camera_penetration_m,row.camera_penetration_m)
	motion_stats.max_camera_overlap_count=maxi(motion_stats.max_camera_overlap_count,row.camera_overlap.size());motion_stats.max_near_hit_count=maxi(motion_stats.max_near_hit_count,row.near_ray_hits.size())
	motion_stats.max_tick_mismatch=maxi(motion_stats.max_tick_mismatch,absi(row.rig.follow_ticks-row.rig.observed_ticks))
	motion_stats.max_follow_error_m=maxf(motion_stats.max_follow_error_m,scene.rig.global_position.distance_to(p+Vector3.UP*1.3));motion_stats.max_length_excess_m=maxf(motion_stats.max_length_excess_m,row.rig.distance-scene.rig.arm.get_hit_length())
	if (clear_watch=="cross" and not scene.traffic.human_present) or (clear_watch=="npc" and scene.player.global_position.distance_to(scene.pedestrians[0].global_position)>1.05):
		observed_clear_tick=Engine.get_physics_frames();observed_clear_player=_player_row();clear_watch=""
	if motion_stats.ticks==1 or motion_stats.ticks%6==0:_retain_motion()

func _finish_motion() -> Dictionary:
	_retain_motion();scene.rig.camera_stepped.disconnect(_observe_motion);motion_active=false
	motion_stats.pose_calls=motion_pose_calls;motion_stats.recoveries=scene.player.recoveries-motion_start.player.recoveries
	return {"first_tick":motion_first,"last_tick":Engine.get_physics_frames(),"ticks":motion_stats.ticks,"duration_s":motion_stats.ticks/60.,"wall_s":(Time.get_ticks_usec()-motion_start_usec)/1000000.,"frames":frames-motion_first_frame,"start":motion_start,"end":_motion_state(),"stats":motion_stats,"samples":motion_samples}

func _look_west() -> void:
	var angle:=wrapf(PI/2-scene.rig.yaw,-PI,PI)
	_mouse(-angle/.0025,0.);Input.flush_buffered_events()
	await _wait(2./60)

func _seek(name: String,target: Vector3,allow_yield:=true) -> Dictionary:
	var start: Vector3=scene.player.global_position
	extra_specs[name]={"from_xz":[start.x,start.z],"to_xz":[target.x,target.z]}
	suppress_yield=not allow_yield
	var row: Dictionary=await _segment(name,start.distance_to(target)/3.5,Vector3.ZERO,true,0.)
	suppress_yield=false
	return row

func _source_walk(route_id: String,from_index: int,to_index: int,label: String) -> void:
	var route: Array=scene.city.public_data.routes.filter(func(r):return r.id==route_id)[0].xz
	var step:=1 if to_index>from_index else -1
	for i in range(from_index+step,to_index+step,step):
		await _seek(label+"_"+str(i),_point(route[i]))
		if not run_error.is_empty():return

func _crossing_exercises() -> void:
	await _source_walk("city_plaza",3,22,"approach_cross")
	var south: CharacterBody3D=scene.vehicles[0]
	var city_route: Array=scene.city.public_data.routes[3].xz
	var west_safe:=_point(city_route[22]).lerp(_point(city_route[23]),.8)
	for attempt in range(3):
		var safe:=22 if attempt%2==0 else 29
		var occupied:=25 if attempt%2==0 else 27
		var clear:=29 if attempt%2==0 else 22
		exercise_phase="cross_"+str(attempt)
		if attempt%2==0:await _seek("portal_safe_"+str(attempt),west_safe)
		await _look_west()
		var start_tick:=Engine.get_physics_frames()
		var before: Dictionary=south.snapshot()
		for j in range(9000):
			if south.snapshot().cycle_count>before.cycle_count:break
			await _wait(1./60)
		await _source_walk("city_plaza",safe,occupied,"occupy_"+str(attempt))
		for j in range(900):
			if south.snapshot().speed_mps<=.001 and south.get_station_m()<source_routes.sejong_south.conflicts[0].enter_s_m:break
			await _wait(1./60)
		var hold_tick:=Engine.get_physics_frames()
		await _wait(.8)
		var stopped: Dictionary=south.snapshot();var player_occupied:=_player_row()
		observed_clear_tick=-1;observed_clear_player={};clear_watch="cross"
		await _source_walk("city_plaza",occupied,clear,"clear_"+str(attempt))
		var clear_tick:=observed_clear_tick;var player_clear:=observed_clear_player
		for j in range(1200):
			if south.get_station_m()>source_routes.sejong_south.conflicts[0].exit_s_m+1. and south.snapshot().speed_mps>.1:break
			await _wait(1./60)
		var released: Dictionary=south.snapshot()
		exercise_rows.append({"kind":"crossing","index":attempt,"start_tick":start_tick,"hold_tick":hold_tick,"clear_tick":clear_tick,"end_tick":Engine.get_physics_frames(),"source_index":occupied,"car_before":before,"car_stopped":stopped,"car_released":released,"player_occupied":player_occupied,"player_clear":player_clear})
		print("N04_CROSS ",attempt," stop=",stopped.station_m," release=",released.station_m)
	await _source_walk("city_plaza",29,3,"return_cross")

func _npc_block_exercises() -> void:
	await _source_walk("entrance",0,3,"approach_palace")
	await _source_walk("palace_loop",0,5,"approach_npc")
	var npc: CharacterBody3D=scene.pedestrians[0]
	for attempt in range(3):
		exercise_phase="npc_block_"+str(attempt)
		var start_tick:=Engine.get_physics_frames()
		var before: Dictionary=npc.snapshot()
		for j in range(9000):
			var row: Dictionary=npc.snapshot()
			if row.state in ["waiting","endpoint_wait"] and row.station_m<2. and row.blocked_reason=="body:"+String(scene.player.name):break
			await _wait(1./60)
		await _wait(.8)
		var stopped: Dictionary=npc.snapshot();var occupied:=_player_row();var hold_tick:=Engine.get_physics_frames()
		observed_clear_tick=-1;observed_clear_player={};clear_watch="npc"
		await _source_walk("palace_loop",5,4,"clear_npc_"+str(attempt))
		var clear_tick:=observed_clear_tick;var clear:=observed_clear_player
		for j in range(600):
			if npc.snapshot().actual_distance_m>stopped.actual_distance_m+1.:break
			await _wait(1./60)
		exercise_rows.append({"kind":"npc_block","index":attempt,"start_tick":start_tick,"hold_tick":hold_tick,"clear_tick":clear_tick,"end_tick":Engine.get_physics_frames(),"npc_before":before,"npc_stopped":stopped,"npc_released":npc.snapshot(),"player_occupied":occupied,"player_clear":clear})
		print("N04_NPC_BLOCK ",attempt," stop=",stopped.state," reason=",stopped.blocked_reason)
		if attempt<2:await _source_walk("palace_loop",4,5,"return_npc_"+str(attempt))
	await _source_walk("palace_loop",4,0,"return_palace")
	await _source_walk("entrance",3,0,"return_spawn")

func _segment(title: String,seconds: float,direction:=Vector3.ZERO,fast:=false,orbit:=0.0) -> Dictionary:
	var selected: Dictionary=extra_specs.get(title,{})
	if selected.is_empty():
		for spec in itinerary.segment_specs:
			if spec.name==title:selected=spec;break
	var destination:=Vector3(selected.to_xz[0],scene.player.position.y,selected.to_xz[1])
	guidance.set_leg(title,Vector3(selected.from_xz[0],0,selected.from_xz[1]),destination)
	var pipelines_before := _pipelines()
	var boundary_before: int=scene.player.boundary_stops
	var stats:={"ticks":0,"max_player_penetration_m":0.0,"max_camera_penetration_m":0.0,"floor_support_ticks":0,"outside_movement_ticks":0,"first_outside_point":[],"solid_contact_ticks":0,"contact_ids":[],"crossing_ticks":{},"boundary_reasons":{}}
	var t:=0.0
	var ticks:=0
	var start: Vector3=scene.player.global_position
	var recovered: int=scene.player.recoveries
	var wall:=Time.get_ticks_usec()
	var first_frame:=frames
	var samples:=[]
	var max_overlap:=0
	var max_near_hits:=0
	var max_follow:=0.0
	var max_length_excess:=0.0
	var mismatch:=0
	var floor_ticks:=0
	var min_distance:=INF
	var max_distance:=0.0
	var min_y:=INF
	var max_y:=-INF
	var camera_max_step:=0.0
	var previous: Vector3=scene.rig.camera.global_position
	while ticks==0 or (Vector2(scene.player.position.x-destination.x,scene.player.position.z-destination.z).length()>.06 and t<seconds+90. and run_error.is_empty()):
		direction=scene.player.global_position.direction_to(destination) if suppress_yield else guidance.next_direction(scene.player,scene.pedestrians,scene.city)
		direction.y=0.
		if direction.length_squared()>0:_world_keys(direction,fast)
		else:_keys([])
		if orbit!=0:
			_mouse(orbit/60.0,0)
			Input.flush_buffered_events()
		t+=await scene.rig.camera_stepped
		ticks+=1
		var sample:=_sample(t)
		stats.ticks+=1
		if not sample.crossing_id.is_empty():stats.crossing_ticks[sample.crossing_id]=stats.crossing_ticks.get(sample.crossing_id,0)+1
		if not sample.boundary_reason.is_empty():stats.boundary_reasons[sample.boundary_reason]=stats.boundary_reasons.get(sample.boundary_reason,0)+1
		stats.max_player_penetration_m=maxf(stats.max_player_penetration_m,sample.player_penetration_m)
		stats.max_camera_penetration_m=maxf(stats.max_camera_penetration_m,sample.camera_penetration_m)
		if sample.floor and sample.floor_id=="W03_support":stats.floor_support_ticks+=1
		if not sample.inside_movement:
			stats.outside_movement_ticks+=1
			if stats.first_outside_point.is_empty():stats.first_outside_point=sample.player
		if not sample.contact_ids.is_empty():stats.solid_contact_ticks+=1
		for id in sample.contact_ids:
			if not stats.contact_ids.has(id):stats.contact_ids.append(id)
		max_overlap=max(max_overlap,sample.camera_overlap.size())
		max_near_hits=max(max_near_hits,sample.near_ray_hits.size())
		var target: Vector3=scene.player.global_position+Vector3.UP*scene.rig.pivot_height_m
		max_follow=max(max_follow,scene.rig.global_position.distance_to(target))
		max_length_excess=max(max_length_excess,scene.rig.current_distance-scene.rig.arm.get_hit_length())
		mismatch=max(mismatch,abs(scene.rig.follow_ticks-scene.rig.observed_ticks))
		min_distance=min(min_distance,scene.rig.current_distance)
		max_distance=max(max_distance,scene.rig.current_distance)
		min_y=min(min_y,scene.player.global_position.y)
		max_y=max(max_y,scene.player.global_position.y)
		if scene.player.is_on_floor():floor_ticks+=1
		camera_max_step=max(camera_max_step,scene.rig.camera.global_position.distance_to(previous))
		previous=scene.rig.camera.global_position
		if ticks==1 or ticks%6==0:samples.append(sample)
	_keys([])
	if samples.is_empty() or samples[-1].global_physics_tick!=Engine.get_physics_frames():samples.append(_sample(t))
	_retain_motion()
	var target_error:=Vector2(scene.player.position.x-destination.x,scene.player.position.z-destination.z).length()
	if target_error>.065 and run_error.is_empty():run_error="source leg timeout: "+title
	return {"target_xz":selected.to_xz,"target_error_m":target_error,"yield_events":guidance.events.filter(func(event):return event.source_leg==title),"name":title,"duration_s":t,"wall_s":(Time.get_ticks_usec()-wall)/1000000.0,"ticks":ticks,"frames":frames-first_frame,
		"start":_v(start),"end":_v(scene.player.global_position),"recoveries":scene.player.recoveries-recovered,
		"samples":samples,"W03_stats":stats,"boundary_stops":scene.player.boundary_stops-boundary_before,"pipelines":{"before":pipelines_before,"after":_pipelines()},"all_tick_stats":{"ticks":ticks,"max_camera_overlap_count":max_overlap,"max_near_hit_count":max_near_hits,
			"max_follow_error_m":max_follow,"max_length_excess_m":max_length_excess,"max_tick_mismatch":mismatch,
			"floor_ticks":floor_ticks,"min_distance":min_distance,"max_distance":max_distance,"min_player_y":min_y,"max_player_y":max_y,"camera_max_step_m":camera_max_step}}


func _run() -> void:
	itinerary=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/walkable_itinerary.json"))
	if not await _fresh_scene():push_error("N04 traffic scene rejected");quit(1);return
	guidance=load("res://test_support/urban_motion_guidance.gd").new()
	var initial_inventory:=_inventory();var supports:=[];var descriptors:=[];var npc_descriptors:=[]
	for body in scene.road_supports:supports.append(_body_row(body.get_meta("geometry_id"),body))
	for body in scene.vehicles:descriptors.append({"id":body.get_route_id(),"size":_v(body.get_node("CollisionShape").shape.size),"layer":body.collision_layer,"mask":body.collision_mask,"priority":body.process_physics_priority,"safe_margin":body.safe_margin})
	for body in scene.pedestrians:npc_descriptors.append({"id":body.snapshot().route_id,"height":body.get_node("CollisionShape").shape.height,"radius":body.get_node("CollisionShape").shape.radius,"layer":body.collision_layer,"mask":body.collision_mask,"safe_margin":body.safe_margin})
	await _warmup();await _wait(1.)
	var initial:={"point":_v(scene.player.global_position),"valid":scene.player.spawn_valid,"volume_guard_clear":scene.city.volume_clear(scene.player.spawn_transform.origin,1.7,.3)}
	var shape: CapsuleShape3D=scene.player.get_node("CollisionShape").shape
	var actor:={"height":shape.height,"radius":shape.radius,"layer":scene.player.collision_layer,"mask":scene.player.collision_mask,"walk_mps":scene.player.walk_speed_mps,"run_mps":scene.player.run_speed_mps,"gravity":scene.player.gravity_mps2,"safe_margin":scene.player.safe_margin,"camera_mask":scene.rig.arm.collision_mask,"camera_probe_radius":scene.rig.arm.shape.radius,"player_camera_path_matches":scene.player.movement_camera==scene.rig.camera,"boundary_script":scene.player.get_script().resource_path}
	var cases:=[]
	_begin_motion()
	var journey: Dictionary=await _integrated(cases)
	var walk_yields: Array=guidance.events.duplicate(true)
	if suite=="full" and run_error.is_empty():
		await _crossing_exercises()
		if run_error.is_empty():await _npc_block_exercises()
	var timeline:=_finish_motion()
	var final_vehicles:=_vehicle_rows();var final_npcs:=_npc_rows();var events: Array=scene.traffic.events.duplicate(true)
	var resource: Resource=scene.city.boundary_resource
	var after_tick:=Engine.get_physics_frames();var post_events: Array=await _events()
	# The full camera/physics trace is retained once in timeline.samples, including
	# every source leg endpoint. Avoid three redundant copies in shared evidence.
	journey.erase("samples")
	for row in cases:row.erase("samples")
	var walk:={"schema_version":1,"task":"W04","suite":suite,"fault":variant,"engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"physics_hz":60,"render_fps":fps},"plan_sha256":FileAccess.get_sha256("res://data/generated/walkable_itinerary.json"),"w03_sha256":FileAccess.get_sha256("res://data/generated/public_walk.json"),"inventory":initial_inventory,"spawn":initial,"actor":actor,"cases":cases,"journey":journey,"yield_events":walk_yields,"extra_specs":extra_specs,"events_start_physics_tick":after_tick,"events_end_physics_tick":Engine.get_physics_frames(),"events":post_events,"rays":_rays(),"boundary":{"contract_id":resource.contract_id,"runtime_path":resource.runtime_path,"movement_edge_margin_m":resource.movement_edge_margin_m,"road_center_exclusion_m":resource.road_center_exclusion_m,"guide_exists":true,"guide_child_count":0,"guide_surface":_guide_observation()}}
	var record:={"schema_version":1,"task":"N04","suite":suite,"fault":variant,"error":run_error,"engine":walk.engine,"bundle_sha256":FileAccess.get_sha256("res://data/generated/traffic.json"),"plan_sha256":walk.plan_sha256,"initial_inventory":initial_inventory,"final_inventory":_inventory(),"descriptors":descriptors,"npc_descriptors":npc_descriptors,"support_descriptors":supports,"walk":walk,"timeline":timeline,"final_vehicles":final_vehicles,"final_npcs":final_npcs,"traffic_events":events,"exercises":exercise_rows,"city_visuals":load("res://test_support/city_visual_observation.gd").collect(scene),"palace_visuals":load("res://test_support/palace_visual_observation.gd").collect(scene),"captures":capture_names,"scope":"One continuous ordinary-input journey and natural encounter exercises; no actor reset, fixtures or player placement during timeline. Warmup and post-timeline recovery injections explicit. No human/M4/field/performance acceptance."}
	record["observation_layout"]="N04-single-global-trace-v1"
	FileAccess.open(output_path,FileAccess.WRITE).store_string(JSON.stringify(record)+"\n");print("N04_DONE ticks=",timeline.ticks," error=",run_error)
	scene.queue_free();quit(0)
