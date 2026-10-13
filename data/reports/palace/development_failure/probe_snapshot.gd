extends "res://test_support/check_daehanmun_walk.gd"
## Actual W02 runtime/input observations; an independent Python checker owns acceptance.
func _sample(time: float) -> Dictionary:
	var row: Dictionary=super._sample(time)
	row["contact_ids"]=row.contact_ids.filter(func(id):return id!="W02_support")
	row["inside_movement"]=scene.city.movement_contains(Vector2(scene.player.global_position.x,scene.player.global_position.z))
	return row

func _segment(title: String,seconds: float,direction:=Vector3.ZERO,fast:=false,orbit:=0.0) -> Dictionary:
	var pipelines_before := _pipelines()
	var boundary_before: int=scene.player.boundary_stops
	var stats:={"ticks":0,"max_player_penetration_m":0.0,"max_camera_penetration_m":0.0,"floor_support_ticks":0,"outside_movement_ticks":0,"first_outside_point":[],"solid_contact_ticks":0,"contact_ids":[]}
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
		stats.max_player_penetration_m=maxf(stats.max_player_penetration_m,sample.player_penetration_m)
		stats.max_camera_penetration_m=maxf(stats.max_camera_penetration_m,sample.camera_penetration_m)
		if sample.floor and sample.floor_id=="W02_support":stats.floor_support_ticks+=1
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
		"samples":samples,"W02_stats":stats,"boundary_stops":scene.player.boundary_stops-boundary_before,"pipelines":{"before":pipelines_before,"after":_pipelines()},"all_tick_stats":{"ticks":ticks,"max_camera_overlap_count":max_overlap,"max_near_hit_count":max_near_hits,
			"max_follow_error_m":max_follow,"max_length_excess_m":max_length_excess,"max_tick_mismatch":mismatch,
			"floor_ticks":floor_ticks,"min_distance":min_distance,"max_distance":max_distance,"min_player_y":min_y,"max_player_y":max_y,"camera_max_step_m":camera_max_step}}

func _inventory() -> Dictionary:
	var inventory: Dictionary=super._inventory()
	for row in inventory.fragments:row["visible"]=scene.city.fragments[row.id].get_parent().visible
	var pending: Array[Node]=[scene.city]
	var created:=0
	var active:=0
	while not pending.is_empty():
		var node: Node=pending.pop_back()
		if node is StaticBody3D:
			created+=1
			if node.collision_layer!=0:active+=1
		pending.append_array(node.get_children())
	inventory["created_body_count"]=created
	inventory["active_body_count"]=active
	return inventory

func _warmup() -> Dictionary:
	var before:=_pipelines()
	var started:=Time.get_ticks_usec()
	var poses:=0
	for c in scene.city.palace.checkpoints:
		for offset in [-PI/2,0.0,PI/2]:
			await _pose(_point(c.xz),scene.starting_yaw+offset)
			if DisplayServer.get_name()!="headless":
				await process_frame
				RenderingServer.force_draw()
			poses+=1
	await _pose(_point(scene.city.connection.route_xz[0]),scene.starting_yaw)
	await _wait(1)
	return {"poses":poses,"wall_s":(Time.get_ticks_usec()-started)/1000000.0,"pipelines_before":before,"pipelines_after":_pipelines(),"scope":"15 checkpoint camera poses and neutral settle; cold startup excluded"}

func _rays() -> Array:
	var result: Array=super._rays()
	var supports: Array[RID]=[]
	for id in scene.city.bodies:
		if id!="temporary_support":supports.append(scene.city.bodies[id].get_rid())
	for id in scene.city.fragments:
		if id not in ["W02_support","W01_support"]:supports.append(scene.city.fragments[id].get_rid())
	for spec in [["court_hole",[-125.0,-60.0]],["lawn",[-11.31,-46.07]],["seokjojeon_stairs",[-174.46,-126.0]],["court_floor",[-130.0,-40.0]],["loop_floor",[-201.81,-32.65]]]:
		var p:=_point(spec[1]);p.y=1
		var q:=p-Vector3.UP*2
		var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p,q,1,supports))
		result.append({"name":spec[0],"from":_v(p),"to":_v(q),"hit":not hit.is_empty(),"id":"" if hit.is_empty() else hit.collider.get_meta("geometry_id",""),"position":[] if hit.is_empty() else _v(hit.position)})
	for spec in [["preserved_retaining_wall",Vector3(-110,1,-60),Vector3(-115,1,-60)],["preserved_jungwhamun",Vector3(-140,1,-5),Vector3(-140,1,-35)]]:
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
	print("W02_ROUTE ",route.id," ",sense," endpoint_error=",max_error)
	await _capture(route.id+"_"+sense)
	return {"route":route.id,"direction":sense,"legs":legs,"targets_xz":targets,"duration_s":sum_time,"wall_s":sum_wall,"frames":sum_frames,"maximum_target_error_m":max_error,"teleports_within_group":0}

func _fault() -> bool:
	match variant:
		"normal":pass
		"support_disabled":scene.city.fragments.W02_support.collision_layer=0;scene.city.fragments.W02_support.collision_mask=0
		"preserved_wall_removed":scene.city.bodies["osm:way:381755262:barrier"].collision_layer=0;scene.city.bodies["osm:way:381755262:barrier"].collision_mask=0
		"player_mask_zero":scene.player.collision_mask=0
		"camera_mask_zero":scene.rig.arm.collision_mask=0
		"global_support_reenabled":scene.city.bodies.temporary_support.collision_layer=1;scene.city.bodies.temporary_support.collision_mask=14
		"courtyard_hole_filled":
			var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=14;body.set_meta("geometry_id","W02_fault_hole_floor")
			var shape:=BoxShape3D.new();shape.size=Vector3(2,.2,2)
			var collider:=CollisionShape3D.new();collider.shape=shape;body.add_child(collider)
			scene.city.add_child(body);body.position=Vector3(-125,-.1,-60)
		_:return false
	return true

func _run() -> void:
	scene=load("res://scenes/world/palace_walk.tscn").instantiate();root.add_child(scene)
	if not scene.runtime_ok:push_error("W02 did not load");quit(1);return
	scene.input_router.set_script(load("res://test_support/daehanmun_probe_input.gd"))
	scene.input_router.isolate_movement_bindings()
	if not scene.input_router.menu_toggle_requested.is_connected(scene.toggle_menu):scene.input_router.menu_toggle_requested.connect(scene.toggle_menu)
	if not _fault():push_error("Unknown W02 fault");quit(1);return
	await _wait(1)
	var initial:={"point":_v(scene.player.global_position),"valid":scene.player.spawn_valid,"volume_guard_clear":scene.city.volume_clear(scene.player.spawn_transform.origin,1.7,.3)}
	var c: Dictionary=scene.city.connection
	var shape: CapsuleShape3D=scene.player.get_node("CollisionShape").shape
	var actor:={"height":shape.height,"radius":shape.radius,"layer":scene.player.collision_layer,"mask":scene.player.collision_mask,"walk_mps":scene.player.walk_speed_mps,"run_mps":scene.player.run_speed_mps,"gravity":scene.player.gravity_mps2,"safe_margin":scene.player.safe_margin,"camera_mask":scene.rig.arm.collision_mask,"camera_probe_radius":scene.rig.arm.shape.radius,"player_camera_path_matches":scene.player.movement_camera==scene.rig.camera}
	var warmup: Dictionary=await _warmup()
	await _capture("outside_spawn");await _wait(1)
	var cases:=[]
	if suite=="diagnostic":
		await _pose(Vector3(-143.173110961914,.08,-4.63182830810547),scene.starting_yaw)
		var target:=Vector3(-127.074800790811,.08,-.784708085469902)
		var d: Vector3=target-scene.player.global_position;d.y=0
		cases.append(await _segment("edge_diagnostic",ceil(d.length()/3.5*60)/60,d.normalized(),true,8))
		var diagnostic_file:=FileAccess.open(output_path,FileAccess.WRITE);diagnostic_file.store_string(JSON.stringify({"cases":cases,"reason":scene.player.last_recovery_reason})+"\n");scene.queue_free();quit(0);return
	cases.append(await _segment("idle",60 if suite=="full" else 2))
	var a:=Vector3(-201.8102688131039,.08,-32.6473801927641)
	var b:=Vector3(-199.4948170396965,.08,-92.06735245604068)
	for fast in [false,true]:
		await _pose(a,scene.starting_yaw)
		cases.append(await _segment("speed_run" if fast else "speed_walk",10,(b-a).normalized(),fast))
	var groups:=[]
	if suite=="full":
		for route in scene.city.palace.routes:
			for sense in ["forward","reverse"]:groups.append(await _route(route,sense,cases))
		for checkpoint in scene.city.palace.checkpoints:
			await _pose(_point(checkpoint.xz),scene.starting_yaw)
			await _capture("checkpoint_"+str(scene.city.palace.checkpoints.find(checkpoint)))
	var u:=Vector3(c.direction_xz[0],0,c.direction_xz[1])
	var p:=_point(c.route_xz[1])-u*2
	var q:=_point(c.route_xz[2])+u*2
	for forward in [true,false]:
		await _pose(p if forward else q,scene.starting_yaw if forward else scene.starting_yaw+PI)
		cases.append(await _segment("gate_forward" if forward else "gate_reverse",ceil((c.passage_length_m+4)/1.4*60)/60,u if forward else -u,false,45 if forward else -45))
		await _capture("gate_inside" if forward else "gate_outside")
	var boundary_cases:=[]
	for spec in [["boundary_footway",(a+b)/2,Vector3.RIGHT],["boundary_lawn",_point(scene.city.palace.routes[1].xz[2]),Vector3(-.339,0,.376).normalized()],["boundary_court_hole",Vector3(-130,.08,-40),Vector3.FORWARD],["boundary_seok_stairs",_point(scene.city.palace.checkpoints[3].xz),Vector3.FORWARD]]:
		await _pose(spec[1],scene.starting_yaw)
		var row: Dictionary=await _segment(spec[0],4,spec[2],true)
		cases.append(row);boundary_cases.append(spec[0])
		await _capture(spec[0])
	var events: Array=await _events()
	var record:={"schema_version":1,"task":"W02","suite":suite,"fault":variant,"engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"physics_hz":Engine.physics_ticks_per_second,"render_fps":fps},"plan_sha256":FileAccess.get_sha256("res://data/generated/palace_walk.json"),"inventory":_inventory(),"spawn":initial,"actor":actor,"cases":cases,"route_groups":groups,"boundary_cases":boundary_cases,"events":events,"rays":_rays(),"captures":capture_names,"warmup":warmup,"external_movement_events_ignored":scene.input_router.external_movement_events,"scope":"Automatic local flat palace support; no human handling, real terrain/access, M4 or W0/V0 acceptance"}
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var file:=FileAccess.open(output_path,FileAccess.WRITE)
	if file==null:push_error("W02 result path required");quit(1);return
	file.store_string(JSON.stringify(record)+"\n")
	print("W02_PROBE_DONE cases=",cases.size());scene.queue_free();quit(0)
