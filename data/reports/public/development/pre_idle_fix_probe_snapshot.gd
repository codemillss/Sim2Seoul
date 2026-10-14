extends "res://test_support/check_palace_walk.gd"
## Actual W03 runtime/input observations; an independent Python checker owns acceptance.
func _sample(time: float) -> Dictionary:
	var row: Dictionary=super._sample(time)
	row["contact_ids"]=row.contact_ids.filter(func(id):return id!="W03_support")
	row["inside_movement"]=scene.city.movement_contains(Vector2(scene.player.global_position.x,scene.player.global_position.z))
	row["crossing_id"]=scene.city.crossing_at(Vector2(scene.player.position.x,scene.player.position.z))
	row["boundary_reason"]=scene.player.last_boundary_reason
	return row

func _segment(title: String,seconds: float,direction:=Vector3.ZERO,fast:=false,orbit:=0.0) -> Dictionary:
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
	while t<seconds-0.000001:
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
		if ticks==1 or ticks%6==0 or t>=seconds-0.000001:samples.append(sample)
	_keys([])
	return {"name":title,"duration_s":t,"wall_s":(Time.get_ticks_usec()-wall)/1000000.0,"ticks":ticks,"frames":frames-first_frame,
		"start":_v(start),"end":_v(scene.player.global_position),"recoveries":scene.player.recoveries-recovered,
		"samples":samples,"W03_stats":stats,"boundary_stops":scene.player.boundary_stops-boundary_before,"pipelines":{"before":pipelines_before,"after":_pipelines()},"all_tick_stats":{"ticks":ticks,"max_camera_overlap_count":max_overlap,"max_near_hit_count":max_near_hits,
			"max_follow_error_m":max_follow,"max_length_excess_m":max_length_excess,"max_tick_mismatch":mismatch,
			"floor_ticks":floor_ticks,"min_distance":min_distance,"max_distance":max_distance,"min_player_y":min_y,"max_player_y":max_y,"camera_max_step_m":camera_max_step}}

func _rays() -> Array:
	var c: Dictionary=scene.city.connection
	var p:=_point(c.route_xz[1])
	var q:=_point(c.route_xz[2])
	var u:=Vector3(c.direction_xz[0],0,c.direction_xz[1])
	var n:=Vector3(c.normal_xz[0],0,c.normal_xz[1])
	var specs:=[["gate_center",p-u*2,q+u*2,false],["lintel",p-u*2,q+u*2,false],["wall_left",p-u*2+n*6,p+u*2+n*6,true],["wall_right",p-u*2-n*6,p+u*2-n*6,true],["off_support",_point(c.route_xz[0])+n*6,_point(c.route_xz[0])+n*6,false]]
	var result:=[]
	for s in specs:
		var from: Vector3=s[1]
		var to: Vector3=s[2]
		from.y=3.5 if s[0]=="lintel" else 1.0
		to.y=from.y
		var exclude: Array[RID]=[]
		if s[3]:
			for b in scene.city.bodies.values():exclude.append(b.get_rid())
			for id in scene.city.fragments:
				if id!="W01_palace_wall":exclude.append(scene.city.fragments[id].get_rid())
		if s[0]=="off_support":to.y=-1.0
		var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1,exclude))
		result.append({"name":s[0],"from":_v(from),"to":_v(to),"hit":not hit.is_empty(),"id":"" if hit.is_empty() else hit.collider.get_meta("geometry_id",""),"position":[] if hit.is_empty() else _v(hit.position),"isolated_wall":s[3]})
	var excluded: Array[RID]=[]
	for id in scene.city.bodies:
		if id!="temporary_support":excluded.append(scene.city.bodies[id].get_rid())
	for id in scene.city.fragments:
		if id not in ["W03_support","W02_support","W01_support"]:excluded.append(scene.city.fragments[id].get_rid())
	for spec in [["city_floor",[130.,-140.]],["plaza_floor",[190.,-100.]],["plaza_hole",[155.4,-56.73]],["private_floor",[-131.61,-249.65]],["road_off_crossing",[80.,-180.]]]:
		var from:=_point(spec[1]);from.y=1
		var to:=from-Vector3.UP*2
		var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1,excluded))
		result.append({"name":spec[0],"from":_v(from),"to":_v(to),"hit":not hit.is_empty(),"id":"" if hit.is_empty() else hit.collider.get_meta("geometry_id",""),"position":[] if hit.is_empty() else _v(hit.position)})
	for spec in [["preserved_retaining_wall",Vector3(-110,1,-60),Vector3(-115,1,-60)],["library_closed",Vector3(150,1,-110),Vector3(150,1,-140)]]:
		var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(spec[1],spec[2],1))
		result.append({"name":spec[0],"from":_v(spec[1]),"to":_v(spec[2]),"hit":not hit.is_empty(),"id":"" if hit.is_empty() else hit.collider.get_meta("geometry_id",""),"position":[] if hit.is_empty() else _v(hit.position)})
	return result

func _route(route: Dictionary,sense: String,cases: Array) -> Dictionary:
	var points: Array=route.xz.duplicate(true)
	if sense=="reverse":points.reverse()
	await _pose(_point(points[0]),scene.starting_yaw)
	var legs:=[]
	var targets:=[]
	var sum_time:=0.0
	var sum_wall:=0.0
	var sum_frames:=0
	var max_error:=0.0
	for i in range(points.size()-1):
		var destination:=_point(points[i+1])
		var delta: Vector3=destination-scene.player.global_position;delta.y=0
		var name: String="%s_%s_%d"%[route.id,sense,i]
		# Short source bends still take a real physics tick; clock is assessed over the whole route.
		var row: Dictionary=await _segment(name,maxf(1.0/60,ceil(delta.length()/3.5*60)/60),delta.normalized(),true,8)
		cases.append(row);legs.append(name);targets.append(points[i+1])
		sum_time+=row.duration_s;sum_wall+=row.wall_s;sum_frames+=row.frames
		max_error=maxf(max_error,Vector2(row.end[0]-points[i+1][0],row.end[2]-points[i+1][1]).length())
	print("W03_ROUTE ",route.id," ",sense," endpoint_error=",max_error)
	await _capture(route.id+"_"+sense)
	return {"route":route.id,"direction":sense,"legs":legs,"targets_xz":targets,"duration_s":sum_time,"wall_s":sum_wall,"frames":sum_frames,"maximum_target_error_m":max_error,"teleports_within_group":0}

func _warmup() -> Dictionary:
	var before:=_pipelines();var started:=Time.get_ticks_usec();var poses:=0
	for c in scene.city.public_data.checkpoints:
		for offset in [0.,PI]:
			await _pose(_point(c.xz),scene.starting_yaw+offset)
			if DisplayServer.get_name()!="headless":
				await process_frame
				RenderingServer.force_draw()
			poses+=1
	await _pose(_point(scene.city.connection.route_xz[0]),scene.starting_yaw);await _wait(1)
	return {"poses":poses,"wall_s":(Time.get_ticks_usec()-started)/1000000.,"pipelines_before":before,"pipelines_after":_pipelines(),"scope":"16 checkpoint camera poses plus neutral settle; cold startup excluded"}

func _fault() -> bool:
	match variant:
		"normal":pass
		"support_disabled":scene.city.fragments.W03_support.collision_layer=0;scene.city.fragments.W03_support.collision_mask=0
		"preserved_wall_removed":scene.city.bodies["osm:way:381755262:barrier"].collision_layer=0;scene.city.bodies["osm:way:381755262:barrier"].collision_mask=0
		"player_mask_zero":scene.player.collision_mask=0
		"camera_mask_zero":scene.rig.arm.collision_mask=0
		"global_support_reenabled":scene.city.bodies.temporary_support.collision_layer=1;scene.city.bodies.temporary_support.collision_mask=14
		"boundary_guard_disabled":
			var spawn: Transform3D=scene.player.spawn_transform
			scene.player.set_script(load("res://test_support/public_unbounded_player.gd"))
			scene.player.connection_world=scene.city;scene.player.router=scene.input_router
			scene.player.movement_camera=scene.rig.camera;scene.player.visual=scene.player.get_node("Visual")
			var regions: Array[Rect2]=[];scene.player.configure_recovery(spawn.origin,regions)
		_:return false
	return true

func _events() -> Array:
	var events: Array=await super._events()
	await _pose(_point(scene.city.connection.route_xz[0]),scene.starting_yaw)
	var prior: int=scene.player.recoveries
	var p:=Vector3(-131.61,.08,-249.65)
	var classified: String=scene.city.boundary_reason(Vector2(p.x,p.z))
	var inside: bool=scene.player._inside(p)
	var old: Transform3D=scene.player.spawn_transform;scene.player.spawn_transform=Transform3D(Basis.IDENTITY,p)
	var rejected: bool=not scene.player._valid_spawn();scene.player.spawn_transform=old
	scene.player.global_position=p
	await _wait(.5)
	events.append({"name":"private_return","classified":classified,"inside_before":inside,"spawn_rejected":rejected,"recoveries":scene.player.recoveries-prior,"reason":scene.player.last_recovery_reason,"point":_v(scene.player.global_position),"floor":scene.player.is_on_floor()})
	return events

func _run() -> void:
	scene=load("res://scenes/world/public_walk.tscn").instantiate();root.add_child(scene)
	if not scene.runtime_ok:push_error("W03 did not load");quit(1);return
	scene.input_router.set_script(load("res://test_support/daehanmun_probe_input.gd"));scene.input_router.isolate_movement_bindings()
	if not scene.input_router.menu_toggle_requested.is_connected(scene.toggle_menu):scene.input_router.menu_toggle_requested.connect(scene.toggle_menu)
	if not _fault():push_error("Unknown W03 fault");quit(1);return
	await _wait(1)
	var c: Dictionary=scene.city.connection
	var initial:={"point":_v(scene.player.global_position),"valid":scene.player.spawn_valid,"volume_guard_clear":scene.city.volume_clear(scene.player.spawn_transform.origin,1.7,.3)}
	var shape: CapsuleShape3D=scene.player.get_node("CollisionShape").shape
	var actor:={"height":shape.height,"radius":shape.radius,"layer":scene.player.collision_layer,"mask":scene.player.collision_mask,"walk_mps":scene.player.walk_speed_mps,"run_mps":scene.player.run_speed_mps,"gravity":scene.player.gravity_mps2,"safe_margin":scene.player.safe_margin,"camera_mask":scene.rig.arm.collision_mask,"camera_probe_radius":scene.rig.arm.shape.radius,"player_camera_path_matches":scene.player.movement_camera==scene.rig.camera,"boundary_script":scene.player.get_script().resource_path}
	var warmup: Dictionary=await _warmup();await _capture("outside_spawn");await _wait(1)
	var cases:=[];cases.append(await _segment("idle",60 if suite=="full" else 2))
	var a:=Vector3(68.33789955,.08,-80.9554167);var b:=Vector3(68.73469962,.08,-38.24007347)
	for fast in [false,true]:
		await _pose(a,scene.starting_yaw)
		cases.append(await _segment("speed_run" if fast else "speed_walk",10,(b-a).normalized(),fast))
	var groups:=[]
	if suite=="full":
		for id in scene.city.public_data.public_routes:
			var r: Dictionary=scene.city.public_data.routes.filter(func(v):return v.id==id)[0]
			for sense in ["forward","reverse"]:groups.append(await _route(r,sense,cases))
		for index in [1,5,6,7]:
			await _pose(_point(scene.city.public_data.checkpoints[index].xz),scene.starting_yaw)
			await _capture("checkpoint_"+str(index))
	else:
		var crossing: Array=scene.city.public_data.source_sections[3].runtime_xz
		for sense in ["forward","reverse"]:groups.append(await _route({"id":"sejong_marked","xz":crossing,"length_m":32.509519},sense,cases))
	var u:=Vector3(c.direction_xz[0],0,c.direction_xz[1]);var p:=_point(c.route_xz[1])-u*2;var q:=_point(c.route_xz[2])+u*2
	for forward in [true,false]:
		await _pose(p if forward else q,scene.starting_yaw if forward else scene.starting_yaw+PI)
		cases.append(await _segment("gate_forward" if forward else "gate_reverse",ceil((c.passage_length_m+4)/1.4*60)/60,u if forward else -u,false,45 if forward else -45))
		await _capture("gate_inside" if forward else "gate_outside")
	var neck: Array=scene.city.public_data.area_links[1].runtime_xz.slice(0,6)
	for sense in ["forward","reverse"]:groups.append(await _route({"id":"neck","xz":neck,"length_m":0.},sense,cases))
	var boundaries:=[]
	for spec in [["boundary_road",a,Vector3.RIGHT],["boundary_crossing",Vector3(80.54,.08,-194.625),Vector3.FORWARD],["boundary_unfinished",Vector3(-247.452,.08,-35.952),Vector3(-1,0,-1).normalized()],["boundary_plaza_hole",Vector3(190,.08,-100),Vector3(-1,0,1).normalized()]]:
		await _pose(spec[1],scene.starting_yaw)
		var row: Dictionary=await _segment(spec[0],4,spec[2],true)
		cases.append(row);boundaries.append(spec[0]);await _capture(spec[0])
	var events: Array=await _events()
	var resource: Resource=scene.city.boundary_resource
	var record:={"schema_version":1,"task":"W03","suite":suite,"fault":variant,"engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"physics_hz":Engine.physics_ticks_per_second,"render_fps":fps},"plan_sha256":FileAccess.get_sha256("res://data/generated/public_walk.json"),"inventory":_inventory(),"spawn":initial,"actor":actor,"cases":cases,"route_groups":groups,"boundary_cases":boundaries,"events":events,"rays":_rays(),"captures":capture_names,"warmup":warmup,"boundary":{"contract_id":resource.contract_id,"runtime_path":resource.runtime_path,"movement_edge_margin_m":resource.movement_edge_margin_m,"road_center_exclusion_m":resource.road_center_exclusion_m,"guide_exists":scene.get_node("Presentation/BoundaryGuide") is MeshInstance3D,"guide_child_count":scene.get_node("Presentation/BoundaryGuide").get_child_count()},"external_movement_events_ignored":scene.input_router.external_movement_events,"scope":"Automatic W03 source public routes on engineering support; full W0, actual terrain/access, human/M4 and vehicles untested"}
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var file:=FileAccess.open(output_path,FileAccess.WRITE)
	if file==null:push_error("W03 result required");quit(1);return
	file.store_string(JSON.stringify(record)+"\n");print("W03_PROBE_DONE cases=",cases.size());scene.queue_free();quit(0)
