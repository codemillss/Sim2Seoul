extends "res://../tests/game/check_street_scene.gd"
## Full production scene, bounded observations, real controller and UI signals.
var _began_ms := 0
var _curb_rows: Array = []

func _check(title: String,passed: bool,evidence: Dictionary = {}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":_json(evidence)})
	if not passed:push_warning("LIVED_STREETS_CHECK_FAIL "+title)

func _ray(point: Vector3) -> Dictionary:
	return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.65,point-Vector3.UP*.65,1|32,[scene.player.get_rid()]))

func _curb_geometry() -> void:
	var module: Node3D=scene.street_curbs
	var state: Dictionary=module.snapshot()
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/street_curbs.json"))
	var top_error := 0.;var cut_error := 0.;var side_error := 0.;var closed := 0;var shape_error := 0;var length := 0.;var failures := []
	var rids: Array[RID]=[]
	for body: StaticBody3D in module.bodies:
		rids.append(body.get_rid())
		for child in body.get_children():
			if not child is CollisionShape3D:continue
			if not child.shape is ConvexPolygonShape3D:shape_error+=1;continue
			var above := false;var below := false
			for point: Vector3 in child.shape.points:
				above=above or point.y>=-.00001;below=below or point.y<-.1
			if above and below and child.shape.points.size()>=6:closed+=1
			else:shape_error+=1
	for row: Dictionary in module.segments:
		var actual_length := 0.
		for index in range(1,row.source_xz.size()):
			var a: Array=row.source_xz[index-1];var b: Array=row.source_xz[index]
			actual_length+=Vector2(b[0]-a[0],b[1]-a[1]).length()
		length+=actual_length
		var top: Dictionary=_ray(row.top_point)
		top_error=maxf(top_error,absf(top.position.y-.12) if not top.is_empty() else 999.)
		if top.is_empty() or not rids.has(top.get("rid")):failures.append(row.id)
		for point: Vector3 in row.cut_points:
			var hit := _ray(point);cut_error=maxf(cut_error,absf(hit.position.y) if not hit.is_empty() else 999.)
		for lateral in [-.425,.425]:
			var point: Vector3=module.point_on_segment(row.id,row.length_m*.5,lateral)
			var hit := _ray(point);side_error=maxf(side_error,absf(hit.position.y-.06) if not hit.is_empty() else 999.)
		_curb_rows.append({"id":row.id,"length_m":actual_length,"top":row.top_point,"cuts":row.cut_points,"source_drive_features":row.source_drive_features})
	var mesh_vertices := 0;var mesh_top := -INF
	for child in module.get_children():
		if child is MeshInstance3D:
			for surface in range(child.mesh.get_surface_count()):
				for point: Vector3 in child.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:mesh_vertices+=1;mesh_top=maxf(mesh_top,point.y)
	_check("curbs.actual_16_owned_closed_bodies_exceed_150_source_metres",module.segments.size()==16 and module.bodies.size()==16 and length>150. and absf(length-state.built_length_m)<.002 and closed>1500 and shape_error==0,{"length_m":length,"bodies":module.bodies.size(),"closed_convex_shapes":closed,"shape_errors":shape_error,"skipped":module.skipped})
	_check("curbs.actual_mesh_and_ray_tops_12cm_sides_6cm_ends_flat",top_error<.003 and cut_error<.003 and side_error<.004 and absf(mesh_top-.12)<.0001 and mesh_vertices>3000 and failures.is_empty(),{"top_error_m":top_error,"side_error_m":side_error,"end_error_m":cut_error,"mesh_top_y_m":mesh_top,"actual_mesh_vertices":mesh_vertices,"wrong_top_bodies":failures})
	var candidate_count := 0;var query_count := 0;var blocked := []
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/interiors/source_catalog.json"))
	var capsule: CollisionShape3D=scene.player.get_node("CollisionShape")
	var query := PhysicsShapeQueryParameters3D.new();query.shape=capsule.shape;query.collision_mask=1;query.margin=.001
	for record: Dictionary in catalog.records:
		for entry: Dictionary in record.entry_candidates:
			candidate_count+=1
			var outward:=Vector3(entry.outward[0],0,entry.outward[1]);var along:=Vector3(outward.z,0,-outward.x)
			var half_width:=maxf(1.2,float(entry.door_width)*.5)+.3
			for distance in [0.,1.,2.,3.,4.,5.]:
				for lateral in [-half_width,0.,half_width]:
					var point: Vector3=scene.city.to_global(Vector3(entry.entrance[0],.02,entry.entrance[1])+outward*distance+along*lateral)
					query.transform=Transform3D(Basis.IDENTITY,point)*capsule.transform;query_count+=1
					for hit: Dictionary in scene.get_world_3d().direct_space_state.intersect_shape(query,32):
						if rids.has(hit.rid) and blocked.size()<8:blocked.append({"id":record.id,"candidate":candidate_count,"distance":distance,"lateral":lateral})
	var flat_cuts := [];var flat_ok := true
	for crossing: Dictionary in raw.named_flat_cuts:
		var okay := true
		for coordinate: Array in crossing.source_xz:
			var point: Vector3=scene.city.to_global(Vector3(coordinate[0],0,coordinate[1]));var hit:=_ray(point)
			okay=okay and not hit.is_empty() and absf(hit.position.y)<.003
		flat_ok=flat_ok and okay;flat_cuts.append({"id":crossing.id,"flat":okay,"actual_support_queries":crossing.source_xz.size()})
	_check("curbs.all_704_source_entrance_corridors_have_no_new_curb_capsule_contacts",catalog.records.size()==125 and candidate_count==704 and query_count==12672 and blocked.is_empty(),{"buildings":catalog.records.size(),"candidates":candidate_count,"actual_capsule_queries":query_count,"blocked_examples":blocked,"sampling":"every candidate: outward 0..5m at 1m, centre and both full protected half-width edges; contacts filtered to actual new curb RIDs"})
	_check("curbs.three_actual_marked_crossing_centres_remain_flat",flat_ok and flat_cuts.size()==3,{"crossings":flat_cuts})
	observations["curbs"]={"segments":_curb_rows,"height_m":state.height_m,"width_m":state.width_m,"end_fade_m":state.end_fade_length_m,"authored_not_surveyed":not state.physical_terrain_verified,"protected_source_plan":state.protection}

func _cross_curbs() -> void:
	var selected := []
	for row: Dictionary in scene.street_curbs.segments:
		if row.length_m<8.:continue
		var a: Vector3=scene.street_curbs.point_on_segment(row.id,row.length_m*.5,-1.15)+Vector3.UP*.08
		var b: Vector3=scene.street_curbs.point_on_segment(row.id,row.length_m*.5,1.15)+Vector3.UP*.08
		if _supported_clear(a) and _supported_clear(b):selected.append({"row":row,"a":a,"b":b})
		if selected.size()==2:break
	_check("curbs.two_representative_crossings_have_clear_actual_capsule_starts",selected.size()==2)
	for index in range(selected.size()):
		var record: Dictionary=selected[index];var fast: bool=index==1
		scene.set_speed_profile("turbo" if fast else "brisk")
		for reverse in [false,true]:
			var a: Vector3=record.b if reverse else record.a;var b: Vector3=record.a if reverse else record.b
			var title: String=String(record.row.id)+("_turbo" if fast else "_walk")+("_back" if reverse else "_out")
			if not await _pose(title,a):continue
			var recoveries: int=scene.player.recoveries;var ticks := 0;var grounded := 0;var max_y: float=scene.player.global_position.y;var max_step := 0.;var max_speed := 0.
			var before: Vector3=scene.player.global_position
			for tick in range(200):
				var direction: Vector3=b-scene.player.global_position;direction.y=0.
				if direction.length()<.075:break
				var speed: float=scene.player.run_speed_mps if fast else scene.player.walk_speed_mps
				_world_keys(direction.normalized()*minf(1.,direction.length()/(speed/60.)))
				if fast:Input.action_press("move_fast")
				await _ticks(1);ticks+=1
				var at: Vector3=scene.player.global_position
				if scene.player.is_on_floor():grounded+=1
				max_y=maxf(max_y,at.y);max_step=maxf(max_step,at.distance_to(before));max_speed=maxf(max_speed,Vector2(scene.player.velocity.x,scene.player.velocity.z).length());before=at
			_movement();await _ticks(4)
			var reached: bool=Vector2(scene.player.global_position.x-b.x,scene.player.global_position.z-b.z).length()<.1
			var result:={"id":title,"ticks":ticks,"grounded":grounded,"start":a,"end":scene.player.global_position,"target":b,"maximum_foot_y_m":max_y,"maximum_step_m":max_step,"maximum_horizontal_speed_mps":max_speed,"recoveries_delta":scene.player.recoveries-recoveries,"reached":reached}
			walks.append(_json(result))
			_check("controller."+title+".physically_crosses_both_bevels",reached and ticks>3 and grounded>=ticks*.85 and max_y>.105 and max_y<.20 and max_step<.37 and scene.player.recoveries==recoveries and (max_speed>20. if fast else max_speed>2.),result)
		if index==0:await _view("curb_crossing",record.row.top_point+Vector3.UP*.2,4.5)
	scene.set_speed_profile("brisk")

func _actor_poses() -> Array:
	var result := []
	for row: Dictionary in scene.street_pedestrians.actors:
		var item:={"body":row.body.global_transform,"visual":row.visual.transform,"proxy":row.proxy.transform}
		if row.kind=="walker":
			item["clock"]=row.avatar.clock;item["joints"]={}
			for name: String in ["LeftThigh","RightThigh","LeftUpperArm","RightUpperArm"]:item.joints[name]=row.avatar._joints[name].transform
		else:
			item["legs"]=[]
			for leg: Dictionary in row.legs:item.legs.append(leg.joint.transform)
			item["tail"]=row.tail.transform
		result.append(item)
	for group: Dictionary in scene.street_pedestrians.groups:
		if group.record.dog:result.append({"leash":group.leash.transform,"visible":group.leash.visible})
	return result

func _actor_motion() -> void:
	var module: Node3D=scene.street_pedestrians
	var state: Dictionary=module.snapshot();var humans := 0;var dogs := 0;var registered := 0;var construction_errors := []
	for row: Dictionary in module.actors:
		if scene.traffic.humans.has(row.body):registered+=1
		if row.kind=="walker":
			humans+=1
			if not row.collider.shape is CapsuleShape3D or row.avatar._meshes.size()<20:construction_errors.append(row.body.name)
		else:
			dogs+=1
			if not row.collider.shape is BoxShape3D or row.legs.size()!=4:construction_errors.append(row.body.name)
	_check("population.six_articulated_walkers_two_four_leg_dogs_and_two_legacy_people",humans==6 and dogs==2 and scene.pedestrians.size()==2 and construction_errors.is_empty() and module.skipped.is_empty(),{"humans":humans,"dogs":dogs,"legacy_people":scene.pedestrians.size(),"errors":construction_errors})
	_check("population.all_eight_real_character_bodies_registered_with_existing_traffic",registered==8 and module.actors.all(func(row: Dictionary)->bool:return row.body.collision_layer==4 and row.body.collision_mask==47),{"registered":registered,"traffic_humans":scene.traffic.humans.size()})
	var starts := {};var ranges := {};var y_ranges := {};var limb_ranges := {};var support_errors := [];var overlaps := [];var maximum_leash := 0.;var maximum_leash_mid_error := 0.;var paws_min := INF;var paws_max := -INF
	for row: Dictionary in module.actors:
		var id: String=row.body.name;starts[id]=row.body.global_position;ranges[id]=0.;y_ranges[id]=[row.body.global_position.y,row.body.global_position.y];limb_ranges[id]={}
	for tick in range(360):
		await _ticks(1)
		for row: Dictionary in module.actors:
			var id: String=row.body.name;var at: Vector3=row.body.global_position
			ranges[id]=maxf(ranges[id],at.distance_to(starts[id]));y_ranges[id][0]=minf(y_ranges[id][0],at.y);y_ranges[id][1]=maxf(y_ranges[id][1],at.y)
			var joints: Array=[row.avatar._joints.LeftThigh,row.avatar._joints.RightThigh,row.avatar._joints.LeftUpperArm,row.avatar._joints.RightUpperArm] if row.kind=="walker" else row.legs.map(func(leg: Dictionary)->Node3D:return leg.joint)
			for index in range(joints.size()):
				var angle: float=joints[index].rotation.x
				if not limb_ranges[id].has(index):limb_ranges[id][index]=[angle,angle]
				else:limb_ranges[id][index][0]=minf(limb_ranges[id][index][0],angle);limb_ranges[id][index][1]=maxf(limb_ranges[id][index][1],angle)
			if tick%12!=0:continue
			var hit:=_ray(at)
			if hit.is_empty() or not row.body.is_on_floor() or absf(at.y-hit.position.y)>.045:
				if support_errors.size()<8:support_errors.append({"id":id,"tick":tick,"at":at,"ground":hit.get("position"),"on_floor":row.body.is_on_floor()})
			var query:=PhysicsShapeQueryParameters3D.new();query.shape=row.collider.shape;query.transform=row.collider.global_transform;query.collision_mask=2|4|8;query.margin=-.001;query.exclude=[row.body.get_rid()]
			for contact: Dictionary in scene.get_world_3d().direct_space_state.intersect_shape(query,8):
				if overlaps.size()<8:overlaps.append({"id":id,"other":String(contact.collider.name),"tick":tick})
			if row.kind=="dog":
				for leg: Dictionary in row.legs:
					var paw_hit:=_ray(leg.paw.global_position)
					if not paw_hit.is_empty():var gap: float=leg.paw.global_position.y-paw_hit.position.y;paws_min=minf(paws_min,gap);paws_max=maxf(paws_max,gap)
		if tick%12==0:
			for group: Dictionary in module.groups:
				if not group.record.dog:continue
				var owner: Dictionary=group.members[0];var dog: Dictionary=group.members[1]
				var local_dog: Vector3=owner.visual.to_local(dog.body.global_position)
				var hand: Vector3=owner.avatar._hands[1 if local_dog.x>0. else 0].global_position
				var collar: Vector3=dog.collar.global_position+Vector3.UP*.015
				maximum_leash=maxf(maximum_leash,group.leash.global_basis.y.length())
				maximum_leash_mid_error=maxf(maximum_leash_mid_error,group.leash.global_position.distance_to((hand+collar)*.5))
	var moving := 0;var animated := 0;var slope_rise := 0.;var motion_rows := []
	for id: String in ranges:
		if ranges[id]>.5:moving+=1
		var moved_joints := 0;var excursions := []
		for joint: int in limb_ranges[id]:
			var excursion: float=limb_ranges[id][joint][1]-limb_ranges[id][joint][0];excursions.append(excursion)
			if excursion>.12:moved_joints+=1
		# A dog keeper deliberately holds one arm toward the actual leash grip.
		if moved_joints>=(3 if id.ends_with("dog_walker") else 4):animated+=1
		if id=="museum_slope_walker":slope_rise=y_ranges[id][1]-y_ranges[id][0]
		motion_rows.append({"id":id,"observed_displacement_m":ranges[id],"foot_y_range_m":y_ranges[id],"actual_joint_excursions_rad":excursions})
	state=module.snapshot()
	_check("population.real_physics_moves_all_eight_with_animated_limbs",moving==8 and animated==8,{"moving":moving,"animated":animated,"observation_seconds":6.})
	_check("population.actual_floor_support_including_sloped_walker_without_overlaps",support_errors.is_empty() and overlaps.is_empty() and slope_rise>.15,{"support_errors":support_errors,"overlap_examples":overlaps,"slope_actual_rise_m":slope_rise})
	_check("dogs.four_paws_animate_near_floor_and_actual_leashes_follow_hands",paws_min>=-.012 and paws_max<.11 and maximum_leash>.45 and maximum_leash<=1.4 and maximum_leash_mid_error<.035,{"paw_center_gap_range_m":[paws_min,paws_max],"maximum_actual_leash_length_m":maximum_leash,"maximum_hand_collar_midpoint_error_m":maximum_leash_mid_error})
	_check("population.modest_dispersion_and_bounded_step_traffic_separation",state.maximum_observed_actors_within_10m<=4 and state.maximum_step_m<.04 and state.routes.all(func(row: Dictionary)->bool:return row.minimum_traffic_route_distance_m>=3.5),{"maximum_eight_actor_density_within_10m":state.maximum_observed_actors_within_10m,"maximum_actual_step_m":state.maximum_step_m,"route_traffic_clearance_m":state.routes.map(func(row: Dictionary)->float:return row.minimum_traffic_route_distance_m)})
	observations["actor_motion"]={"samples":360,"actors":motion_rows,"initial_counts":{"walker":humans,"dog":dogs},"traffic_registered":registered}

func _pause_and_toggle() -> void:
	await _menu_edge();var opened: bool=scene.menu.visible and paused
	var poses := _actor_poses();var elapsed: float=scene.street_pedestrians.elapsed
	for frame in range(12):await process_frame
	_check("menu.real_toggle_freezes_actor_bodies_joints_leashes_and_clock",opened and _actor_poses()==poses and scene.street_pedestrians.elapsed==elapsed)
	await _menu_edge();await _ticks(4)
	scene.movement_switch.set_pressed_no_signal(false);scene.movement_switch.toggled.emit(false);await _ticks(36)
	var positions := [];var old_positions := []
	for row: Dictionary in scene.street_pedestrians.actors:positions.append(row.body.global_position)
	for body: CharacterBody3D in scene.pedestrians:old_positions.append(body.global_position)
	elapsed=scene.street_pedestrians.elapsed;await _ticks(24)
	var stopped: bool=not scene.street_pedestrians.running and not scene.pedestrians_running
	for index in range(positions.size()):stopped=stopped and scene.street_pedestrians.actors[index].body.global_position.distance_to(positions[index])<.002
	for index in range(old_positions.size()):stopped=stopped and scene.pedestrians[index].global_position.distance_to(old_positions[index])<.002
	_check("menu.legacy_pedestrian_checkbox_pauses_all_ten_actual_people_and_dogs",stopped and scene.street_pedestrians.elapsed==elapsed,{"checkbox_text":scene.movement_switch.text,"new_bodies":positions.size(),"legacy_bodies":old_positions.size()})
	scene.movement_switch.set_pressed_no_signal(true);scene.movement_switch.toggled.emit(true);await _ticks(90)
	var resumed := 0;var old_resumed := 0;var resume_rows := []
	for index in range(positions.size()):
		var actor: CharacterBody3D=scene.street_pedestrians.actors[index].body
		var moved: float=actor.global_position.distance_to(positions[index])
		if moved>.1:resumed+=1
		var contacts := []
		for contact in range(actor.get_slide_collision_count()):
			var hit: KinematicCollision3D=actor.get_slide_collision(contact)
			contacts.append({"collider":String(hit.get_collider().name),"normal":hit.get_normal()})
		resume_rows.append({"id":actor.name,"displacement_m":moved,"start":positions[index],"end":actor.global_position,"velocity":actor.velocity,"slide_contacts":contacts})
	for index in range(old_positions.size()):
		if scene.pedestrians[index].global_position.distance_to(old_positions[index])>.1:old_resumed+=1
	_check("menu.legacy_checkbox_resumes_new_population_and_original_walkers",scene.street_pedestrians.running and scene.pedestrians_running and resumed==8 and old_resumed>0,{"new_resumed":resumed,"legacy_resumed":old_resumed,"observed_bodies":resume_rows,"routes":scene.street_pedestrians.snapshot().routes.map(func(row: Dictionary)->Dictionary:return {"id":row.id,"state":row.state,"reason":row.blocked_reason})})

func _player_clearance() -> void:
	var module: Node3D=scene.street_pedestrians;var group: Dictionary={}
	for candidate: Dictionary in module.groups:
		if candidate.id=="stonewall_west":group=candidate
	if group.is_empty():_check("population.player_stop_fixture_available",false);return
	var direction: Vector3=module._tangent(group,group.station)*float(group.direction)
	var ground: Dictionary=module._ground(module._at(group,group.station+float(group.direction)*1.05))
	if ground.is_empty():_check("population.player_stop_fixture_supported",false);return
	if not await _pose("actual_player_ahead_of_walker",ground.point+Vector3.UP*.055):return
	var body: CharacterBody3D=group.members[0].body;var before: Vector3=body.global_position
	await _ticks(24)
	var drift: float=body.global_position.distance_to(before);var minimum_distance: float=body.global_position.distance_to(scene.player.global_position)
	_check("population.actual_player_blocks_approach_without_body_overlap",group.state=="waiting" and group.blocked_reason in ["neighbor_clearance","swept_body"] and drift<.025 and minimum_distance>.70,{"state":group.state,"reason":group.blocked_reason,"stopped_displacement_m":drift,"player_center_distance_m":minimum_distance})
	var side:=Vector3(direction.z,0,-direction.x)
	var start: Vector3=scene.player.global_position;var target:=Vector3(INF,INF,INF)
	for offset: Vector3 in [side*2.,-side*2.,direction*2.]:
		var candidate: Vector3=start+offset+Vector3.UP*.08
		if not _supported_clear(candidate):continue
		var capsule: CollisionShape3D=scene.player.get_node("CollisionShape")
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule.shape;query.transform=Transform3D(Basis.IDENTITY,start+Vector3.UP*.025)*capsule.transform;query.motion=offset;query.collision_mask=1|32;query.exclude=[scene.player.get_rid()]
		var fractions: PackedFloat32Array=scene.get_world_3d().direct_space_state.cast_motion(query)
		if not fractions.is_empty() and fractions[0]>.999:target=start+offset;break
	var reached := false
	for tick in range(90 if target.is_finite() else 0):
		var toward: Vector3=target-scene.player.global_position;toward.y=0.
		if toward.length()<.1:reached=true;break
		_world_keys(toward.normalized()*minf(1.,toward.length()/(scene.player.walk_speed_mps/60.)));await _ticks(1)
	_movement();await _ticks(30)
	_check("population.walking_player_away_releases_actual_waiting_walker",reached and body.global_position.distance_to(before)>.25 and group.state=="walking",{"player_walk_reached":reached,"player_start":start,"player_end":scene.player.global_position,"target":target,"walker_displacement_after_release_m":body.global_position.distance_to(before),"state":group.state})

func _view(title: String,toward: Vector3,distance := 4.5) -> void:
	var direction: Vector3=toward-scene.player.global_position;direction.y=0.
	scene.rig.yaw=atan2(-direction.x,-direction.z);scene.rig.pitch=deg_to_rad(-23. if title.begins_with("curb_") else -10.);scene.rig.requested_distance=distance;scene.rig.snap_to_target_pose()
	await _ticks(5)
	_check("view."+title+".normal_camera_is_clear",scene.get_viewport().get_camera_3d()==scene.rig.camera and _camera_clear(),{"distance_m":scene.rig.camera.global_position.distance_to(scene.rig.global_position),"player":scene.player.global_position})
	if DisplayServer.get_name()=="headless":captures.append({"name":title,"captured":false,"reason":"headless"});return
	await process_frame;RenderingServer.force_draw(false,0.);await RenderingServer.frame_post_draw
	var picture: Image=scene.get_viewport().get_texture().get_image();var path:=report_path.trim_suffix(".json")+"_"+title+".png"
	var saved: bool=not picture.is_empty() and picture.save_png(path)==OK
	captures.append({"name":title,"captured":saved,"path":path,"width":picture.get_width(),"height":picture.get_height(),"player":scene.player.global_position,"camera":scene.rig.camera.global_transform,"time_id":scene.time_id,"normal_avatar_visible":scene.player.get_node("Visual").is_visible_in_tree()});_check("capture."+title,saved)

func _observer(title: String,toward: Vector3,offsets: Array,look_offset:=Vector3.ZERO,distance:=4.5) -> void:
	for offset: Vector3 in offsets:
		var at:=toward+offset;var hit:=_ray(at)
		if hit.is_empty():continue
		at.y=hit.position.y+.08
		if _supported_clear(at):
			if await _pose(title+"_observer",at):await _view(title,toward+Vector3.UP*.8+look_offset,distance)
			return
	_check("view."+title+".safe_observer_exists",false,{"toward":toward})

func _views() -> void:
	var curb: Dictionary=scene.street_curbs.segments[5]
	await _observer("curb_wide",curb.top_point,[Vector3(2.0,0,1.7),Vector3(-2.0,0,1.7),Vector3(0,0,2.5)],Vector3(.6,0,0),2.8)
	for id in ["stonewall_dog","plaza_dog","museum_slope"]:
		for group: Dictionary in scene.street_pedestrians.groups:
			if group.id!=id:continue
			var body: CharacterBody3D=group.members[0].body
			var side: Vector3=body.get_node("Visual").global_basis.x
			var toward: Vector3=body.global_position
			if group.record.dog:toward=toward.lerp(group.members[1].body.global_position,.5)
			await _observer(id,toward,[Vector3(0,0,3.5),Vector3(0,0,-3.5),side*3.5,-side*3.5],side*.9)
			if id=="stonewall_dog":
				scene.set_time_profile("evening");await _ticks(8)
				await _view("evening_street",toward+Vector3.UP*.8+side*.9,4.5);scene.set_time_profile("day")

func _run() -> void:
	_began_ms=Time.get_ticks_msec()
	for path in ["res://scripts/explore_walk.gd","res://scripts/street_curbs.gd","res://scripts/street_pedestrians.gd","res://scripts/street_businesses.gd","res://scripts/street_life.gd","res://scripts/museum_approach.gd","res://scripts/photo_atmosphere.gd","res://scripts/player/free_roam_player.gd","res://scripts/player/exploration_avatar.gd","res://scripts/player/exploration_camera.gd","res://assets/authored/street_curbs.json","res://assets/authored/street_pedestrians.json","res://assets/authored/street_businesses.json","res://assets/authored/street_life.json","res://assets/authored/museum_approach.json","res://../tests/game/check_lived_streets.gd","res://../tests/game/check_street_scene.gd","res://../tests/game/check_building_visits.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();_settings_path="/private/tmp/sim2seoul-lived-streets-"+str(OS.get_process_id())+".json"
	var initial:=FileAccess.open(_settings_path,FileAccess.WRITE);initial.store_string(JSON.stringify({"schema_version":1,"speed_id":"brisk","free_roam":true}));initial.close()
	scene.exploration_settings_path=_settings_path;scene.quality_settings_path=_settings_path+".quality.json";root.add_child(scene);await _ticks(12)
	_check("startup.production_city_and_both_new_modules_loaded",scene.runtime_ok and is_instance_valid(scene.street_curbs) and scene.street_curbs.loaded and is_instance_valid(scene.street_pedestrians) and scene.street_pedestrians.loaded,{"error":scene.exploration_error})
	if not scene.runtime_ok:_finish();return
	visit=scene.interior_visit
	if scene.menu.visible:await _menu_edge()
	await _ticks(4);original_inventory=_inventory();var shape:=_player_shape()
	_check("regression.original_city_inventory_and_EXP14_features_loaded",original_inventory.size()==692 and scene.street_businesses.loaded and scene.street_businesses.stores.size()==4 and scene.street_life.loaded and scene.street_life.birds.size()==6 and scene.street_life.lamps.size()==10 and scene.museum_approach.loaded,{"source_bodies":original_inventory.size(),"stores":scene.street_businesses.stores.size(),"birds":scene.street_life.birds.size(),"lamps":scene.street_life.lamps.size()})
	_curb_geometry()
	await _actor_motion();await _pause_and_toggle();await _player_clearance()
	await _cross_curbs();await _views()
	if await _enter(LIBRARY_ID,"regression_library"):await _leave("regression_library")
	_check("regression.all_source_shapes_capsule_and_outdoor_controller_retained",_inventory()==original_inventory and _player_shape()==shape and not scene.player.interior_active,{"source_body_count":original_inventory.size()})
	var changed := []
	for path: String in source_hashes:
		if FileAccess.get_sha256(path)!=source_hashes[path]:changed.append(path)
	_check("regression.all_source_hashes_frozen_during_probe",changed.is_empty(),{"changed":changed})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var failed := 0
	for row: Dictionary in checks:
		if not row.passed:failed+=1
	var evidence:={"task":"lived_streets","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"started_at_local":started_at,"finished_at_local":Time.get_datetime_string_from_system(),"wall_elapsed_seconds":(Time.get_ticks_msec()-_began_ms)/1000.,"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"observations":observations,"scenario_starts":placements,"walks":walks,"captures":captures,"scope":"Actual production exploration scene with owned curb terrain and eight extra CharacterBody3D actors. Source entrances sampled by actual capsule contacts against new curb RIDs; every top/end and both bevels independently ray-tested. Four real Input controller crossings, actual motion/joints/paws/leashes/support and dynamic actor contacts, real menu pause and legacy checkbox signals, physical E library entry/exit. Explicit scenario starts only; no actor teleport or per-step player teleport. Native images require actual frame_post_draw on the regular third-person camera; headless makes no rendered-image acceptance. Curbs, population and hill heights are bounded game-authored detail, not surveyed pavement, crowd realism or human OS-input/performance acceptance."}
	var output:=FileAccess.open(report_path,FileAccess.WRITE)
	if output!=null:output.store_string(JSON.stringify(_json(evidence),"\t")+"\n");output.close()
	else:failed+=1;push_error("Could not save lived streets report")
	print("LIVED_STREETS_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)
