extends "res://../tests/game/check_street_transit.gd"
## EXP25: actual display readback, source preservation and controller crossings.
var road_inputs: Array[String]=["res://scripts/street_network_detail.gd","res://scripts/street_curbs.gd","res://assets/authored/road_furniture.json","res://assets/authored/street_curbs.json","res://resources/world_geometry/world.json","res://data/generated/public_walk.json","res://data/generated/traffic.json","res://assets/authored/neighborhood_population.json","res://scripts/terrain_geometry_warp.gd","res://scripts/terrain_scene_binding.gd","res://../tools/prepare_road_furniture.py","res://../tests/game/check_road_surface_detail.gd"]
var road_started:=0
var geometry_only:=false

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
		elif arg=="--geometry-only":geometry_only=true
	if not report_path.is_absolute_path() or FileAccess.file_exists(report_path):push_error("Use new absolute --report path");quit(1);return
	for action: String in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	native=DisplayServer.get_name()!="headless";road_started=Time.get_ticks_usec()
	create_timer(420.,true,false,true).timeout.connect(func():_check("completion_guard",false);_finish())
	_run.call_deferred()

func _hashes() -> Dictionary:
	var values: Dictionary={}
	for path: String in road_inputs:values[path]=FileAccess.get_sha256(path)
	for path: String in ["res://../tests/game/check_street_transit.gd","res://../tests/game/check_street_scene.gd","res://../tests/game/check_building_visits.gd"]:values[path]=FileAccess.get_sha256(path)
	return values

func _run() -> void:
	source_hashes=_hashes();settings_base="/private/tmp/exp25-road-"+str(OS.get_process_id())+".json"
	var settings:=FileAccess.open(settings_base,FileAccess.WRITE);settings.store_string(JSON.stringify({"schema_version":1,"speed_id":"realistic","free_roam":true}));settings.close()
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=settings_base;scene.quality_settings_path=settings_base+".quality.json";scene.exploration_physics_hz=30
	root.add_child(scene);scene.set_vehicles_running(false);scene.set_pedestrians_running(false);await _ticks(3)
	var road_ready: bool=scene.terrain_surface.loaded and is_instance_valid(scene.street_network_detail) and scene.street_network_detail.loaded
	_check("production_road_and_committed_TIN_ready",road_ready and (geometry_only or scene.runtime_ok and scene.exploration_error.is_empty()),{"error":scene.exploration_error,"geometry_only":geometry_only,"whole_host_runtime_ok":scene.runtime_ok})
	if not road_ready or (not geometry_only and (not scene.runtime_ok or not scene.exploration_error.is_empty())):_finish();return
	network=scene.street_network_detail;transit=scene.city_bus_service;visit=scene.interior_visit
	if not geometry_only:await _menu(false)
	original_inventory=_inventory();original_capsule=_player_shape();original_routes=_route_signature();original_tin=hash(scene.terrain_surface.faces)
	_check("original_692_source_records_and_14_cars",original_inventory.size()==692 and scene.vehicles.size()+scene.neighborhood_population.traffic.vehicles.size()==14,{"source_records":original_inventory.size(),"original_cars":scene.vehicles.size()+scene.neighborhood_population.traffic.vehicles.size()})
	_walk_display_readback();_curb_opening_rays();_paint_terrain_rays();_signal_faces()
	if geometry_only:
		_check("frozen_road_inputs_match",_hashes()==source_hashes);_finish();return
	network.set_physics_process(false);_clock(29.0);scene.set_vehicles_running(true);transit.set_running(false)
	await _original_car_signal_journey();scene.set_vehicles_running(false)
	network.set_physics_process(true);await _natural_cycle()
	network.set_physics_process(false);_clock(31.0)
	await _crossing_controller_walks()
	_check("source_nodes_capsule_routes_TIN_retained",_inventory()==original_inventory and _player_shape()==original_capsule and _route_signature()==original_routes and hash(scene.terrain_surface.faces)==original_tin,{"original_world_sha256":FileAccess.get_sha256("res://resources/world_geometry/world.json"),"source_records":original_inventory.size(),"TIN_faces":scene.terrain_surface.faces.size()/3})
	_check("frozen_road_inputs_match",_hashes()==source_hashes)
	_finish()

func _walk_display_readback() -> void:
	var errors: Array=[];var terrain_errors: Array=[];var witnesses:=0;var samples:=0
	for row: Dictionary in network.design.surface_masks:
		var visual: MeshInstance3D=scene.city.source_nodes.get(row.node_id)
		if not is_instance_valid(visual):errors.append(row.node_id);continue
		var world: Vector3=scene.city.to_global(Vector3(row.occlusion_witness_xz[0],0,row.occlusion_witness_xz[1]));var witness:=Vector2(world.x,world.z)
		var covered:=false
		if visual.visible:
			var vertices: PackedVector3Array=visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for index: int in range(0,vertices.size(),3):
				var a: Vector3=visual.to_global(vertices[index]);var b: Vector3=visual.to_global(vertices[index+1]);var c: Vector3=visual.to_global(vertices[index+2])
				if witness.x>=minf(a.x,minf(b.x,c.x)) and witness.x<=maxf(a.x,maxf(b.x,c.x)) and witness.y>=minf(a.z,minf(b.z,c.z)) and witness.y<=maxf(a.z,maxf(b.z,c.z)):
					if Geometry2D.is_point_in_polygon(witness,PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])):covered=true
				if index%600==0:
					var centre: Vector3=(a+b+c)/3.;var floor_y: float=scene.terrain_surface.ground_y_world(centre);samples+=1
					if absf(centre.y-floor_y-float(row.source_y_m))>.001:terrain_errors.append(row.node_id)
		if covered:errors.append(row.node_id)
		witnesses+=1
	var unchanged:=true
	for row: Dictionary in network.surface_mask_audit:unchanged=unchanged and row.same_source_node and row.same_children
	_check("actual_104_walk_render_overlaps_removed_preserving_source_nodes",witnesses==104 and errors.is_empty() and unchanged,{"witnesses":witnesses,"covering_walk_nodes":errors,"original_valid_drive_overlap_m2":network.design.preflight.walk_drive_render_overlap_before_m2,"source_nodes_and_children_unchanged":unchanged})
	_check("replacement_walk_meshes_projected_once",samples>100 and terrain_errors.is_empty(),{"native_mesh_samples":samples,"wrong_height_nodes":terrain_errors})

func _curb_opening_rays() -> void:
	var rows: Array=[];var errors: Array=[]
	for row: Dictionary in network.design.curb_crossing_masks:
		var point: Vector3=scene.city.to_global(Vector3(row.native_witness_xz[0],0,row.native_witness_xz[1]));point.y=scene.terrain_surface.ground_y_world(point)
		var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.5,point-Vector3.UP*.3,1|32,[scene.player.get_rid()]))
		var ok: bool=not hit.is_empty() and not hit.collider.get_meta("authored_game_curb",false)
		if not ok:errors.append(row.curb_id)
		rows.append({"curb_id":row.curb_id,"crossing_id":row.crossing_id,"native_ray_point":point,"hit":String(hit.collider.name) if not hit.is_empty() else "none","original_overlap_m2":row.original_overlap_m2,"passed":ok})
	_check("native_curb_crossing_opening_keeps_ground_support",rows.size()==1 and errors.is_empty(),{"openings":rows,"errors":errors})

func _paint_terrain_rays() -> void:
	var errors:=0;var samples:=0
	for mesh: MeshInstance3D in network.paint_meshes:
		var vertices: PackedVector3Array=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for index: int in range(0,vertices.size(),3):
			var point: Vector3=mesh.to_global((vertices[index]+vertices[index+1]+vertices[index+2])/3.)
			var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.1,point-Vector3.UP*.2,32))
			if hit.is_empty() or absf(point.y-hit.position.y-.052)>.001:errors+=1
			samples+=1
	_check("every_actual_paint_face_matches_native_TIN",samples>5000 and errors==0,{"samples":samples,"errors":errors,"white_and_yellow_batches":network.paint_meshes.size()})
	var sections: Array=[]
	var yellow: MeshInstance3D
	for visual: MeshInstance3D in network.paint_meshes:
		if String(visual.name).ends_with("yellow"):yellow=visual
	for z: float in [-450.,-350.,-280.,-160.,-100.,-50.]:sections.append({"z":z,"actual_yellow_intervals":_paint_section(yellow,z)})
	# Independent southern source cross-sections. Other named roads can cross
	# the same latitude, so inspect the local Sejong corridor window only.
	for pair: Vector2 in [Vector2(150.,51.23),Vector2(200.,35.32),Vector2(250.,19.45),Vector2(350.,-11.55),Vector2(400.,-28.12),Vector2(450.,-45.04),Vector2(470.,-53.73)]:
		var matches: Array=[]
		for interval: Vector2 in _section_in_window(yellow,pair.x,pair.y-1.,pair.y+1.):
			if absf((interval.x+interval.y)*.5-pair.y)<1.:matches.append(interval)
		var expected:=2
		for ring: Array in network.design.get("loop_turn_paint_openings",{}).get("mask_rings_xz",[]):
			var polygon:=PackedVector2Array()
			for xy: Array in ring:polygon.append(Vector2(xy[0],xy[1]))
			if Geometry2D.is_point_in_polygon(Vector2(pair.y,pair.x),polygon):expected=0
		sections.append({"z":pair.x,"corridor_x":pair.y,"expected_count":expected,"actual_yellow_intervals":matches})
	var continuous:=true
	for row: Dictionary in sections:continuous=continuous and row.actual_yellow_intervals.size()==int(row.get("expected_count",2))
	_check("one_continuous_double_yellow_basis_between_junctions",continuous,{"native_mesh_sections":sections,"source_map_unchanged":true})

func _signal_faces() -> void:
	var errors: Array=[];var vehicles:=0;var pedestrians:=0
	for row: Dictionary in network.signals:
		var target: Vector3=row.controller_stop_point if row.kind=="vehicle" else row.opposite_bank_approach
		var toward: Vector3=target-row.head.global_position;toward.y=0
		var front: Vector3=row.head.global_basis.z;front.y=0
		var facing: float=front.normalized().dot(toward.normalized())
		var label: Label3D=row.countdown
		if facing<.85 or label.double_sided or label.billboard!=BaseMaterial3D.BILLBOARD_DISABLED:errors.append(row.id)
		if row.kind=="vehicle":vehicles+=1
		else:pedestrians+=1
	_check("both_direction_vehicle_and_pedestrian_fronts_are_physical_single_sided",errors.is_empty() and vehicles==15 and pedestrians==14,{"vehicle_heads":vehicles,"pedestrian_heads":pedestrians,"wrong_fronts":errors})

func _natural_cycle() -> void:
	var phases: Array=[];var bad:=0;var began: float=network.elapsed_s;var observed:=0.
	for tick: int in range(30*47):
		await _ticks(1);observed+=1./30.
		var state: Dictionary=network.signal_phase_snapshot("sejong_marked");var signature: String=String(state.vehicle)+"/"+String(state.pedestrian)
		if not phases.has(signature):phases.append(signature)
		if state.vehicle!="red" and state.pedestrian=="green":bad+=1
	_check("natural_full_cycle_green_amber_protected_pedestrian_and_clearance",bad==0 and phases.size()==4 and observed>float(network.design.cycle.duration_s),{"phases":phases,"conflicting_ticks":bad,"elapsed_simulation_s":observed,"initial_clock_s":began,"final_clock_s":network.elapsed_s,"manual_clock_writes_during_observation":0,"timing_basis":"game_authored_not_real_schedules"})
	await _menu(true);var stopped: float=network.elapsed_s
	for index: int in range(10):await process_frame
	_check("menu_pauses_natural_signal_clock",network.elapsed_s==stopped)
	await _menu(false)

func _crossing_controller_walks() -> void:
	for crossing: Dictionary in network.design.crossings:
		var banks: Array=[]
		for row: Dictionary in network.signals:
			if row.kind=="pedestrian" and row.crossing_id==crossing.id:banks.append(row)
		if banks.size()!=2:_check("crossing_has_two_banks_"+String(crossing.id),false);continue
		var safe: Dictionary=scene._exploration_destination(banks[0].approach_point)
		if safe.is_empty():_check("crossing_supported_start_"+String(crossing.id),false);continue
		await _pose("crossing_"+String(crossing.id)+"_player_start",safe.point)
		var source: Array=crossing.xz.duplicate(true)
		if Vector2(source[0][0]-scene.player.global_position.x,source[0][1]-scene.player.global_position.z).length()>Vector2(source[-1][0]-scene.player.global_position.x,source[-1][1]-scene.player.global_position.z).length():source.reverse()
		var path: Array=[]
		for xz: Array in source:
			var point: Vector3=scene.city.to_global(Vector3(xz[0],0,xz[1]));point.y=scene.terrain_surface.ground_y_world(point)+.08;path.append(point)
		path.append(banks[1].approach_point)
		await _walk_path("native_controller_crossing_"+String(crossing.id),path)
		if native:await _normal_view("crossing_"+String(crossing.id),banks[0].head.global_position,4.5)

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var failed:=0
	for row: Dictionary in checks:
		if not row.passed:failed+=1
	var data: Dictionary={"task":"EXP25_ROAD_SURFACES","result":"PASS" if failed==0 else "FAIL","geometry_only":geometry_only,"display":DisplayServer.get_name(),"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed,"physics_hz":Engine.physics_ticks_per_second,"wall_usec":Time.get_ticks_usec()-road_started},"checks":checks,"walks":walks,"scenario_starts":placements,"captures":captures,"scope":"Actual source-node render mesh readback and native terrain/curb rays. Without --geometry-only, also one natural authored signal cycle, original-car red/green journey and seven real-controller crossings. Only explicit player starts; original actor routes/positions are not rewritten. Native pixels need separate visual review; no real Seoul lane/signal survey claim."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(_json(data),"\t"));file.close()
	print("EXP25_ROAD_RESULT ",checks.size()-failed,"/",checks.size()," report=",report_path);quit(0 if failed==0 else 1)

func _section_in_window(mesh: MeshInstance3D,z: float,x_min: float,x_max: float) -> Array:
	# Unlike inherited EXP23 helper's fixed northern 50..112m crop, this
	# inspects the actual southern source corridor too.
	var intervals: Array=[];var vertices: PackedVector3Array=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i: int in range(0,vertices.size(),3):
		var xs: Array[float]=[]
		for edge: int in range(3):
			var a: Vector3=mesh.to_global(vertices[i+edge]);var b: Vector3=mesh.to_global(vertices[i+(edge+1)%3])
			if z<minf(a.z,b.z)-.00001 or z>maxf(a.z,b.z)+.00001:continue
			if absf(b.z-a.z)<.000001:
				if absf(z-a.z)<.00001:xs.append(a.x);xs.append(b.x)
			else:xs.append(lerpf(a.x,b.x,clampf((z-a.z)/(b.z-a.z),0.,1.)))
		if xs.size()<2:continue
		xs.sort()
		if xs.back()<x_min or xs.front()>x_max:continue
		intervals.append(Vector2(maxf(x_min,xs.front()),minf(x_max,xs.back())))
	intervals.sort_custom(func(a: Vector2,b: Vector2)->bool:return a.x<b.x)
	var merged: Array=[]
	for interval: Vector2 in intervals:
		# Post-TIN float32 triangles can split one stripe by 1.282 mm at z=450.
		# Merge up to 2 mm only; the authored paired-stripe gap is 170 mm.
		if merged.is_empty() or interval.x>(merged.back() as Vector2).y+.002:merged.append(interval)
		else:merged[-1]=Vector2((merged.back() as Vector2).x,maxf((merged.back() as Vector2).y,interval.y))
	return merged
