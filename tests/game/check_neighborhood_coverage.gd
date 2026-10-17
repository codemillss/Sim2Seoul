extends "res://../tests/game/check_lived_streets.gd"
## Production scene: new coverage, physical support, native trees and real toggles.
var greenery: Node3D
var population: Node3D

func _check(title: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":_json(evidence)})
	if not passed:push_warning("NEIGHBORHOOD_COVERAGE_FAIL "+title)

func _floor_at(point: Vector3,excludes: Array[RID]=[]) -> Dictionary:
	return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.5,point-Vector3.UP*.5,1|32,excludes))

func _road_guard_regression() -> void:
	var module: Node3D=population.walkers
	# This exact observed source-footway position is 25.5009m from the source
	# drive mesh (independent Shapely union and float32 triangle audit). Large
	# compound-ring classification previously rejected its entire patrol.
	var off_road: Vector2=Vector2(-407.0767,-305.2527)
	var route: Dictionary=population.design.vehicle_routes[0]
	var road_centre: Vector2=Vector2(route.xz[0][0],route.xz[0][1])
	_check("road_guard.rejects_observed_false_positive_and_still_protects_source_road_centre",not module._inside_drive(off_road) and module._inside_drive(road_centre),{"known_off_road_source_footway_point":off_road,"independent_source_drive_distance_m":25.5009,"positive_source_road_point":road_centre,"positive_source_feature":route.source_binding.feature_id,"basis":"Actual native source drive triangles; the positive point is inside the source-certified vehicle route."})

func _trees() -> void:
	var state: Dictionary=greenery.snapshot();var errors: Array=[];var source: int=0;var fill: int=0;var active: int=0
	var native_counts: Dictionary={"bark":0,"leaf":0,"grate":0};var minimum_canopy: float=INF;var rendered_nodes: int=0;var readback_samples: Array=[]
	for row: Dictionary in greenery.trees:
		var body: StaticBody3D=row.body;var shape: CollisionShape3D=row.shape;var local: Vector3=scene.city.to_local(row.point)
		var original: Vector2=Vector2(row.record.xz[0],row.record.xz[1]);var floor: Dictionary=_floor_at(row.point,[body.get_rid(),scene.player.get_rid()])
		if Vector2(local.x,local.z).distance_to(original)>.001 or floor.is_empty() or absf(row.point.y-floor.position.y-.02)>.003 or floor.normal.y<.8:errors.append({"id":row.record.id,"reason":"source_position_or_current_floor","point":row.point,"floor":floor.get("position")})
		if not shape.shape is CylinderShape3D or absf(shape.shape.radius-.17)>.0001 or shape.shape.height<3.:errors.append({"id":row.record.id,"reason":"trunk_shape"})
		if row.active:
			active+=1
			if body.collision_layer!=1 or shape.disabled:errors.append({"id":row.record.id,"reason":"active_collision"})
		elif body.collision_layer!=0 or not shape.disabled:errors.append({"id":row.record.id,"reason":"distant_collision"})
		if row.record.basis=="source_natural_tree_node":source+=1
		elif row.record.basis=="authored_source_footway_edge_fill":fill+=1
		else:errors.append({"id":row.record.id,"reason":"unlabelled_provenance"})
	for batch: MultiMeshInstance3D in greenery.batches:
		rendered_nodes+=1
		var kind: String=String(batch.name).get_slice("_",String(batch.name).get_slice_count("_")-1)
		if not native_counts.has(kind):errors.append({"batch":String(batch.name)});continue
		native_counts[kind]+=batch.multimesh.instance_count
		if batch.visibility_range_end>240. or batch.visibility_range_end<150.:errors.append({"batch":String(batch.name),"reason":"unbounded_visual_distance"})
		if kind=="leaf":
			var mesh_bounds: AABB=batch.multimesh.mesh.get_aabb()
			if readback_samples.size()<3 and batch.multimesh.instance_count>0:readback_samples.append({"batch":String(batch.name),"batch_transform":batch.global_transform,"mesh_bounds":mesh_bounds,"first_instance_transform":batch.multimesh.get_instance_transform(0)})
			for index: int in range(batch.multimesh.instance_count):
				var actual: AABB=batch.multimesh.get_instance_transform(index)*mesh_bounds
				var ground: float=INF
				for row: Dictionary in greenery.trees:
					if Vector2(row.point.x-(batch.position.x+actual.get_center().x),row.point.z-(batch.position.z+actual.get_center().z)).length()<3.:ground=minf(ground,row.point.y)
				if is_finite(ground):minimum_canopy=minf(minimum_canopy,batch.position.y+actual.position.y-ground)
	_check("trees.all_retained_source_points_have_real_floor_and_labelled_fill",source>=150 and fill>=30 and errors.is_empty(),{"source_trees":source,"authored_fill":fill,"errors":errors,"runtime_skipped":state.skipped,"source_rejections":state.source_rejections})
	_check("trees.actual_native_mesh_instance_counts_match_every_tree_in_bounded_batches",native_counts.bark==greenery.trees.size() and native_counts.leaf==greenery.trees.size()*3 and native_counts.grate==greenery.trees.size()*4 and rendered_nodes<=240,{"instance_counts":native_counts,"native_nodes":rendered_nodes})
	var crown_evidence: Dictionary={"verified":DisplayServer.get_name()!="headless","display":DisplayServer.get_name(),"rendering_method":RenderingServer.get_current_rendering_method(),"minimum_native_readback_canopy_bottom_m":minimum_canopy,"readback_samples":readback_samples}
	if DisplayServer.get_name()=="headless":crown_evidence["deferred_reason"]="The dummy rendering backend returns identity MultiMesh instance transforms; actual native crown clearance requires the GPU run. Instance counts and actual trunk bodies are checked here."
	else:_check("trees.GPU_native_crowns_start_above_pedestrian_heads",minimum_canopy>=2.60,crown_evidence)
	observations["native_crown_readback"]=crown_evidence
	_check("trees.current_nearby_trunk_collisions_fit128_body_budget",active==int(state.active_collisions) and active<=128,{"active":active,"nearby_candidates":state.nearby_collision_candidates,"budget":state.collision_budget})
	observations["greenery"]=state

func _entrances_and_public_routes() -> void:
	# Deliberately test all retained trunk shapes, including currently distant ones.
	# The independent capsule distance test uses the actual body and shape frame.
	var blocked: Array=[];var candidate_count: int=0;var sample_count: int=0
	for spec: Dictionary in visit.catalog:
		for entry: Dictionary in spec.entry_candidates:
			candidate_count+=1
			var outward: Vector3=entry.outward;var along: Vector3=Vector3(outward.z,0,-outward.x)
			var half_width: float=maxf(1.2,float(entry.door_width)*.5)+.3
			for distance: float in [0.,1.,2.,3.,4.,5.]:
				for lateral: float in [-half_width,0.,half_width]:
					var point: Vector3=entry.entrance+outward*distance+along*lateral;sample_count+=1
					for row: Dictionary in greenery.trees:
						if Vector2(point.x-row.body.global_position.x,point.z-row.body.global_position.z).length()<.35+float(row.shape.shape.radius) and blocked.size()<12:blocked.append({"building":spec.id,"tree":row.record.id,"distance":distance,"lateral":lateral})
	var public: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/public_walk.json"));var path_samples: int=0
	for route: Dictionary in public.routes:
		for index: int in range(1,route.xz.size()):
			var first: Vector2=Vector2(route.xz[index-1][0],route.xz[index-1][1]);var last: Vector2=Vector2(route.xz[index][0],route.xz[index][1])
			var steps: int=maxi(1,int(ceil(first.distance_to(last)/.5)))
			for step: int in range(steps+1):
				var point: Vector2=first.lerp(last,float(step)/float(steps));path_samples+=1
				for row: Dictionary in greenery.trees:
					var actual: Vector3=scene.city.to_local(row.body.global_position)
					if point.distance_to(Vector2(actual.x,actual.z))<.35+row.shape.shape.radius and blocked.size()<12:blocked.append({"route":route.id,"tree":row.record.id})
	_check("trees.all_source_entrance_approaches_and_public_route_capsules_remain_clear",visit.catalog.size()>=125 and candidate_count>=704 and sample_count>=12672 and blocked.is_empty(),{"buildings":visit.catalog.size(),"entrances":candidate_count,"entry_capsule_positions":sample_count,"public_route_positions":path_samples,"contacts":blocked,"basis":"Independent XZ distance to actual radius-.17m trunk cylinders, conservatively ignoring tree height; includes every distant disabled trunk."})

func _walkers() -> void:
	var module: Node3D=population.walkers;var sectors: Dictionary={};var source_ids: Dictionary={};var registered: int=0;var starts: Dictionary={};var previous: Dictionary={};var distances: Dictionary={};var excursions: Dictionary={};var joint_minmax: Dictionary={}
	for group: Dictionary in module.groups:sectors[group.record.coverage_sector]=true;source_ids[group.source]=true
	for row: Dictionary in module.actors:
		var key: String=String(row.body.name);starts[key]=row.body.global_position;previous[key]=row.body.global_position;distances[key]=0.;excursions[key]=0.;joint_minmax[key]=[INF,-INF]
		if scene.traffic.humans.has(row.body):registered+=1
	_check("people.twenty_original_articulated_bodies_cover_ten_new_source_corridors",module.actors.size()==20 and sectors.size()==10 and source_ids.size()>=8 and registered==20 and module.skipped.is_empty(),{"actors":module.actors.size(),"sectors":sectors.keys(),"source_features":source_ids.keys(),"registered_with_vehicle_human_guard":registered,"skipped":module.skipped})
	var floor_errors: Array=[];var overlap_errors: Array=[];var road_errors: Array=[];var maximum_step: float=0.;var trace: Array=[]
	for tick: int in range(1200):
		await _ticks(1)
		for row: Dictionary in module.actors:
			var key: String=String(row.body.name);var at: Vector3=row.body.global_position
			var step: float=Vector2(at.x-previous[key].x,at.z-previous[key].z).length();distances[key]+=step;maximum_step=maxf(maximum_step,step);previous[key]=at;excursions[key]=maxf(excursions[key],at.distance_to(starts[key]))
			var angle: float=row.avatar._joints.LeftThigh.rotation.x;joint_minmax[key][0]=minf(joint_minmax[key][0],angle);joint_minmax[key][1]=maxf(joint_minmax[key][1],angle)
			if tick%15!=0:continue
			var support: Dictionary=_floor_support(row)
			if not support.supported and floor_errors.size()<12:floor_errors.append({"id":key,"tick":tick,"support":support})
			var local: Vector3=scene.city.to_local(at)
			if module._inside_drive(Vector2(local.x,local.z)) and road_errors.size()<12:road_errors.append({"id":key,"tick":tick,"position":at})
			var query: PhysicsShapeQueryParameters3D=PhysicsShapeQueryParameters3D.new();query.shape=row.collider.shape;query.transform=row.collider.global_transform;query.collision_mask=2|4|8;query.margin=-.002;query.exclude=[row.body.get_rid()]
			for hit: Dictionary in scene.get_world_3d().direct_space_state.intersect_shape(query,8):
				if overlap_errors.size()<12:overlap_errors.append({"id":key,"other":String(hit.collider.name),"tick":tick})
		if tick%60==0:trace.append({"tick":tick,"people":module.snapshot().actors})
	var moved: int=0;var animated: int=0;var avoided: int=0
	for key: String in distances:
		if distances[key]>2. and excursions[key]>.5:moved+=1
		if joint_minmax[key][1]-joint_minmax[key][0]>.12:animated+=1
	for group: Dictionary in module.groups:
		if int(group.get("avoidance_count",0))>0:avoided+=1
	_check("people.every_new_walker_moves_with_actual_step_budget_and_animated_original_limbs",moved==20 and animated==20 and maximum_step<1.05/60.+.003,{"moving":moved,"animated":animated,"maximum_step_m":maximum_step,"actual_distance_m":distances,"maximum_excursion_m":excursions})
	_check("people.actual_twenty_second_walks_keep_floor_without_road_or_actor_penetration",floor_errors.is_empty() and overlap_errors.is_empty() and road_errors.is_empty(),{"floor_errors":floor_errors,"actor_contacts":overlap_errors,"road_errors":road_errors,"ticks":1200})
	_check("people.opposing_walkers_use_existing_local_passing_instead_of_stopping_whole_corridor",avoided>=2,{"groups_with_real_avoidance":avoided,"groups":module.snapshot().routes})
	observations["walking"]={"trace_1hz":trace,"snapshot":module.snapshot()}

func _toggles() -> void:
	var starts: Array=[]
	for row: Dictionary in population.walkers.actors:starts.append(row.body.global_position)
	scene.movement_switch.set_pressed(false);await _ticks(90)
	var maximum: float=0.
	for index: int in range(starts.size()):maximum=maxf(maximum,starts[index].distance_to(population.walkers.actors[index].body.global_position))
	_check("checkbox.production_people_switch_stops_all_twenty_added_actors",not population.running and not population.walkers.running and maximum<.002,{"maximum_drift_m":maximum})
	scene.movement_switch.set_pressed(true);await _ticks(60)
	var frozen: Array=[]
	await _menu_edge()
	for row: Dictionary in population.walkers.actors:frozen.append(row.body.global_transform)
	var elapsed: float=population.walkers.elapsed
	for index: int in range(12):await process_frame
	var same: bool=true
	for index: int in range(frozen.size()):same=same and population.walkers.actors[index].body.global_transform==frozen[index]
	_check("menu.production_pause_freezes_added_population_without_recreation",paused and same and population.walkers.elapsed==elapsed)
	await _menu_edge();await _ticks(15)
	_check("menu.resume_continues_existing_actor_instances",population.walkers.elapsed>elapsed and population.walkers.actors.size()==frozen.size())

func _coverage_views() -> void:
	var selected: Array=[]
	for sector: int in [0,2,4,6,8]:
		for group: Dictionary in population.walkers.groups:
			if int(group.record.coverage_sector)!=sector:continue
			var at: Vector3=group.members[0].body.global_position;var tangent: Vector3=population.walkers._tangent(group,group.station);var side: Vector3=Vector3(tangent.z,0,-tangent.x)
			await _observer("coverage_sector_"+str(sector),at,[side*3.+tangent*2.,-side*3.+tangent*2.,tangent*4.,-tangent*4.],Vector3.ZERO,4.8)
			selected.append({"sector":sector,"actor":at,"source":group.source});break
	_check("coverage.five_observed_views_span_the_existing_neighborhood",selected.size()==5,{"selected":selected,"all_viewpoints":population.coverage_viewpoints()})

func _run() -> void:
	_began_ms=Time.get_ticks_msec()
	for path: String in ["res://scripts/neighborhood_greenery.gd","res://scripts/neighborhood_population.gd","res://scripts/neighborhood_traffic.gd","res://scripts/street_pedestrians.gd","res://scripts/pedestrian_corridor_avoidance.gd","res://scripts/explore_walk.gd","res://assets/authored/neighborhood_greenery.json","res://assets/authored/neighborhood_population.json","res://resources/world_geometry/world.json","res://../tests/game/check_neighborhood_coverage.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();_settings_path="/private/tmp/sim2seoul-neighborhood-coverage-"+str(OS.get_process_id())+".json"
	var preferences: FileAccess=FileAccess.open(_settings_path,FileAccess.WRITE);preferences.store_string(JSON.stringify({"schema_version":1,"speed_id":"brisk","free_roam":false}));preferences.close()
	scene.exploration_settings_path=_settings_path;scene.quality_settings_path=_settings_path+".quality.json";root.add_child(scene);await _ticks(18)
	greenery=scene.get_node_or_null("NeighborhoodGreenery");population=scene.get_node_or_null("NeighborhoodPopulation")
	_check("startup.free_roam_OFF_still_prepares_supported_trees_walkers_and_cars",scene.runtime_ok and is_instance_valid(greenery) and greenery.loaded and is_instance_valid(population) and population.loaded,{"error":scene.exploration_error,"population":population.snapshot() if is_instance_valid(population) else {}})
	if not scene.runtime_ok or not is_instance_valid(population) or not population.loaded:_finish();return
	visit=scene.interior_visit;original_inventory=_inventory();var capsule: Dictionary=_player_shape()
	if scene.menu.visible:await _menu_edge()
	var unsupported: Array=[]
	for row: Dictionary in population.walkers.actors:
		if not _floor_support(row).supported:unsupported.append(String(row.body.name))
	_check("startup.free_roam_OFF_keeps_actual_population_floor_support_and_player_boundary",not scene.free_roam_enabled and unsupported.is_empty() and not scene.player.free_roam_enabled and (scene.player.collision_mask & 32)==0,{"unsupported":unsupported,"player_mask":scene.player.collision_mask})
	scene.set_free_roam(true);scene.set_time_profile("day");await _ticks(6)
	_road_guard_regression();_trees();_entrances_and_public_routes();await _walkers();await _toggles();await _coverage_views()
	_check("regression.original_actor_arrays_source_bodies_and_capsule_are_preserved",scene.pedestrians.size()==2 and scene.vehicles.size()==6 and scene.street_pedestrians.actors.size()==8 and _inventory()==original_inventory and _player_shape().shape==capsule.shape,{"old_people":scene.pedestrians.size(),"old_cars":scene.vehicles.size(),"old_street_actors":scene.street_pedestrians.actors.size(),"original_bodies":original_inventory.size()})
	var changed: Array=[]
	for path: String in source_hashes:
		if FileAccess.get_sha256(path)!=source_hashes[path]:changed.append(path)
	_check("regression.checked_sources_stayed_frozen",changed.is_empty(),{"changed":changed})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var failed: int=0
	for row: Dictionary in checks:
		if not row.passed:failed+=1
	var evidence: Dictionary={"task":"neighborhood_coverage","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"started_at_local":started_at,"finished_at_local":Time.get_datetime_string_from_system(),"wall_elapsed_seconds":(Time.get_ticks_msec()-_began_ms)/1000.,"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"observations":observations,"scenario_starts":placements,"captures":captures,"scope":"Production scene, source-point trees and labelled source-footway edge fill in bounded native batches. Actual cylinder radii and native crown transforms, every catalog entrance approach and old public route, current ground rays, 20 articulated walkers on 10 dispersed source corridors, 1200 real physics ticks with support/contact/road/step checks, existing local passing, actual people checkbox and menu pause. Only player scenario starts are placed; actors are never teleported. Five regular-camera coverage captures require a GPU. Source tree dates, tree species, visitor density and surveyed pavement/elevation remain unverified; a 20-second bounded probe is not long-duration performance acceptance."}
	var output: FileAccess=FileAccess.open(report_path,FileAccess.WRITE)
	if output!=null:output.store_string(JSON.stringify(_json(evidence),"\t")+"\n");output.close()
	else:failed+=1;push_error("Could not save neighborhood coverage report")
	print("NEIGHBORHOOD_COVERAGE_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)
