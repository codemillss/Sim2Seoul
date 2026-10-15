extends "res://test_support/check_public_walk.gd"
## W04 observes one uninterrupted session. Production W03 code stays unchanged.
var itinerary: Dictionary
var journey_active := false
var journey_stats: Dictionary
var journey_samples := []
var checkpoint_events := []
var captured_checkpoints := []
var sample_cache: Dictionary = {}
var sample_cache_tick := -1
var previous_point := Vector3.ZERO
var previous_tick := -1
var journey_time := 0.0
var journey_pose_calls := 0
var journey_recoveries := 0
var start_recoveries := 0
var last_retained_tick := -1

func _pose(point: Vector3,yaw:=0.0,pitch:=-15.0) -> void:
	if journey_active:journey_pose_calls+=1
	await super._pose(point,yaw,pitch)

func _sample(time: float) -> Dictionary:
	var tick:=Engine.get_physics_frames()
	if journey_active and sample_cache_tick==tick:
		var reused: Dictionary=sample_cache.duplicate()
		reused.t=time
		return reused
	var row: Dictionary=super._sample(time)
	row["global_physics_tick"]=tick
	if journey_active:sample_cache_tick=tick;sample_cache=row.duplicate()
	return row

func _keep_sample(row: Dictionary) -> void:
	var tick: int=row.global_physics_tick
	if tick==last_retained_tick:return
	var kept: Dictionary=row.duplicate()
	kept.t=journey_time
	journey_samples.append(kept)
	last_retained_tick=tick

func _observe(delta: float) -> void:
	var row:=_sample(0.)
	var tick: int=row.global_physics_tick
	var p: Vector3=scene.player.global_position
	journey_time+=delta
	journey_stats.ticks+=1
	journey_stats.last_physics_tick=tick
	journey_stats.max_tick_gap=maxi(journey_stats.max_tick_gap,tick-previous_tick)
	journey_stats.max_player_step_m=maxf(journey_stats.max_player_step_m,p.distance_to(previous_point))
	previous_point=p;previous_tick=tick
	journey_stats.max_player_penetration_m=maxf(journey_stats.max_player_penetration_m,row.player_penetration_m)
	journey_stats.max_camera_penetration_m=maxf(journey_stats.max_camera_penetration_m,row.camera_penetration_m)
	if row.floor and row.floor_id=="W03_support":journey_stats.floor_support_ticks+=1
	if not row.inside_movement:journey_stats.outside_movement_ticks+=1
	journey_stats.max_camera_overlap_count=maxi(journey_stats.max_camera_overlap_count,row.camera_overlap.size())
	journey_stats.max_near_hit_count=maxi(journey_stats.max_near_hit_count,row.near_ray_hits.size())
	journey_stats.max_tick_mismatch=maxi(journey_stats.max_tick_mismatch,absi(row.rig.follow_ticks-row.rig.observed_ticks))
	journey_stats.max_follow_error_m=maxf(journey_stats.max_follow_error_m,scene.rig.global_position.distance_to(p+Vector3.UP*1.3))
	journey_stats.max_length_excess_m=maxf(journey_stats.max_length_excess_m,row.rig.distance-scene.rig.arm.get_hit_length())
	journey_stats.min_distance=minf(journey_stats.min_distance,row.rig.distance)
	journey_stats.max_distance=maxf(journey_stats.max_distance,row.rig.distance)
	journey_stats.min_player_y=minf(journey_stats.min_player_y,p.y)
	journey_stats.max_player_y=maxf(journey_stats.max_player_y,p.y)
	if not row.crossing_id.is_empty():
		journey_stats.crossing_ticks[row.crossing_id]=journey_stats.crossing_ticks.get(row.crossing_id,0)+1
	if journey_stats.ticks==1 or journey_stats.ticks%6==0:_keep_sample(row)

func _checkpoint(point_index: int) -> void:
	for event in itinerary.checkpoint_events:
		if event.point_index!=point_index:continue
		var observed: Dictionary=event.duplicate(true)
		observed["point"]=_v(scene.player.global_position)
		observed["distance_m"]=Vector2(scene.player.position.x-event.xz[0],scene.player.position.z-event.xz[1]).length()
		observed["global_physics_tick"]=Engine.get_physics_frames()
		observed["journey_t"]=journey_time
		checkpoint_events.append(observed)
		if not captured_checkpoints.has(event.checkpoint_index):
			captured_checkpoints.append(event.checkpoint_index)
			await _capture("checkpoint_"+str(int(event.checkpoint_index)))

func _integrated(cases: Array) -> Dictionary:
	var start: Vector3=scene.player.global_position
	var first_tick:=Engine.get_physics_frames()+1
	previous_tick=first_tick-1;previous_point=start
	start_recoveries=scene.player.recoveries
	journey_stats={"ticks":0,"last_physics_tick":previous_tick,"max_tick_gap":0,"max_player_step_m":0.,"max_player_penetration_m":0.,"max_camera_penetration_m":0.,"floor_support_ticks":0,"outside_movement_ticks":0,"max_camera_overlap_count":0,"max_near_hit_count":0,"max_tick_mismatch":0,"max_follow_error_m":0.,"max_length_excess_m":0.,"min_distance":INF,"max_distance":0.,"min_player_y":INF,"max_player_y":-INF,"crossing_ticks":{}}
	var start_wall:=Time.get_ticks_usec();var first_frame:=frames
	var groups:=[];var movement_ticks:=0
	journey_active=true
	scene.rig.camera_stepped.connect(_observe)
	await _checkpoint(0)
	for stage in itinerary.stages:
		if suite=="short" and stage.id not in ["entrance_forward","palace_loop_prefix"]:break
		if variant=="omit_court" and stage.id in ["court_forward","court_reverse"]:continue
		if variant=="seam_teleport" and stage.id=="palace_loop_prefix":
			scene.player.global_position+=Vector3.RIGHT*2
		var before_ticks: int=journey_stats.ticks
		var group_first:=Engine.get_physics_frames()+1
		var group_wall:=Time.get_ticks_usec();var group_frame:=frames
		var group_start:=_v(scene.player.global_position)
		var names:=[];var targets:=[];var max_error:=0.
		for spec in itinerary.segment_specs:
			if spec.stage_id!=stage.id:continue
			var destination:=_point(spec.to_xz)
			var delta: Vector3=destination-scene.player.global_position;delta.y=0
			var segment_first:=Engine.get_physics_frames()+1
			var row: Dictionary=await _segment(spec.name,maxf(1./60,ceil(delta.length()/3.5*60)/60),delta.normalized(),true,8)
			row["stage_id"]=stage.id
			row["first_physics_tick"]=segment_first
			row["last_physics_tick"]=Engine.get_physics_frames()
			cases.append(row);names.append(spec.name);targets.append(spec.to_xz)
			movement_ticks+=row.ticks
			max_error=maxf(max_error,Vector2(row.end[0]-spec.to_xz[0],row.end[2]-spec.to_xz[1]).length())
			_keep_sample(_sample(0.))
			await _checkpoint(spec.to_point_index)
		var ticks: int=journey_stats.ticks-before_ticks
		groups.append({"id":stage.id,"route_id":stage.route_id,"source_indices":stage.source_indices,"legs":names,"targets_xz":targets,"start":group_start,"end":_v(scene.player.global_position),"first_physics_tick":group_first,"last_physics_tick":Engine.get_physics_frames(),"ticks":ticks,"duration_s":ticks/60.,"wall_s":(Time.get_ticks_usec()-group_wall)/1000000.,"frames":frames-group_frame,"maximum_target_error_m":max_error})
		print("W04_STAGE ",stage.id," error=",max_error," ticks=",ticks)
	_keys([])
	_keep_sample(_sample(0.))
	scene.rig.camera_stepped.disconnect(_observe)
	journey_active=false
	journey_stats["pose_calls"]=journey_pose_calls
	journey_stats["recoveries"]=scene.player.recoveries-start_recoveries
	return {"start":_v(start),"end":_v(scene.player.global_position),"first_physics_tick":first_tick,"last_physics_tick":Engine.get_physics_frames(),"ticks":journey_stats.ticks,"duration_s":journey_time,"wall_s":(Time.get_ticks_usec()-start_wall)/1000000.,"frames":frames-first_frame,"movement_ticks":movement_ticks,"checkpoint_dwell_ticks":journey_stats.ticks-movement_ticks,"stats":journey_stats,"samples":journey_samples,"groups":groups,"checkpoint_events":checkpoint_events}

func _run() -> void:
	itinerary=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/walkable_itinerary.json"))
	if itinerary.get("task")!="W04":push_error("W04 itinerary required");quit(1);return
	scene=load("res://scenes/world/public_walk.tscn").instantiate();root.add_child(scene)
	if not scene.runtime_ok:push_error("W03 production scene did not load");quit(1);return
	scene.input_router.set_script(load("res://test_support/daehanmun_probe_input.gd"));scene.input_router.isolate_movement_bindings()
	if not scene.input_router.menu_toggle_requested.is_connected(scene.toggle_menu):scene.input_router.menu_toggle_requested.connect(scene.toggle_menu)
	if variant not in ["normal","seam_teleport","omit_court"] and not _fault():push_error("Unknown W04 fault");quit(1);return
	await _wait(1)
	var shape: CapsuleShape3D=scene.player.get_node("CollisionShape").shape
	var actor:={"height":shape.height,"radius":shape.radius,"layer":scene.player.collision_layer,"mask":scene.player.collision_mask,"walk_mps":scene.player.walk_speed_mps,"run_mps":scene.player.run_speed_mps,"gravity":scene.player.gravity_mps2,"safe_margin":scene.player.safe_margin,"camera_mask":scene.rig.arm.collision_mask,"camera_probe_radius":scene.rig.arm.shape.radius,"player_camera_path_matches":scene.player.movement_camera==scene.rig.camera,"boundary_script":scene.player.get_script().resource_path}
	var warm: Dictionary=await _warmup();await _wait(1)
	var initial:={"point":_v(scene.player.global_position),"valid":scene.player.spawn_valid,"volume_guard_clear":scene.city.volume_clear(scene.player.spawn_transform.origin,1.7,.3)}
	var cases:=[]
	var journey: Dictionary=await _integrated(cases)
	await _capture("journey_end")
	var after_tick:=Engine.get_physics_frames()
	var events: Array=await _events()
	var resource: Resource=scene.city.boundary_resource
	var record:={"schema_version":1,"task":"W04","suite":suite,"fault":variant,"engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"physics_hz":Engine.physics_ticks_per_second,"render_fps":fps},"plan_sha256":FileAccess.get_sha256("res://data/generated/walkable_itinerary.json"),"w03_sha256":FileAccess.get_sha256("res://data/generated/public_walk.json"),"inventory":_inventory(),"spawn":initial,"actor":actor,"cases":cases,"journey":journey,"events_start_physics_tick":after_tick,"events_end_physics_tick":Engine.get_physics_frames(),"events":events,"rays":_rays(),"captures":capture_names,"warmup":warm,"boundary":{"contract_id":resource.contract_id,"runtime_path":resource.runtime_path,"movement_edge_margin_m":resource.movement_edge_margin_m,"road_center_exclusion_m":resource.road_center_exclusion_m,"guide_exists":scene.get_node("Presentation/BoundaryGuide") is MeshInstance3D,"guide_child_count":scene.get_node("Presentation/BoundaryGuide").get_child_count(),"guide_surface":_guide_observation()},"external_movement_events_ignored":scene.input_router.external_movement_events,"scope":"W04 automatic integrated physical journey only; human handling/OS focus, real terrain/access, M4, NPC/vehicles and V0 unverified"}
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var file:=FileAccess.open(output_path,FileAccess.WRITE)
	if file==null:push_error("W04 fresh output required");quit(1);return
	file.store_string(JSON.stringify(record)+"\n");print("W04_PROBE_DONE segments=",cases.size());scene.queue_free();quit(0)
