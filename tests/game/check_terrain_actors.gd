extends SceneTree
## EXP21 production dynamic acceptance. Bodies are never repositioned during the
## Twenty-simulated-second walk/drive observation at requested30/60Hz; only
## named later fixtures/player views move. Default60 is the stress configuration.
const ACTIONS := ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]
var requested_physics_hz: int=60
var observation_ticks: int=1200
var poll_interval_ticks: int=15
var diagnostic_interval_ticks: int=300
var report_path: String=""
var scene: Node3D
var checks: Array=[]
var captures: Array=[]
var people: Array[Dictionary]=[]
var cars: Array[Dictionary]=[]
var observations: Dictionary={}
var source_hashes: Dictionary={}
var finished: bool=false
var started_usec: int=0
var maximum_poll_usec: int=0
var total_poll_usec: int=0
var poll_count: int=0
var errors: Dictionary={"support":[],"contacts":[],"finite":[],"route":[],"car_corners":[],"car_bottom_interior":[],"freefall":[]}
var player_recoveries: int=0

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
		if argument.begins_with("--physics-hz="):
			var value: String=argument.trim_prefix("--physics-hz=")
			if not ["30","60"].has(value):push_error("check_terrain_actors requires --physics-hz=30 or60");quit(1);return
			requested_physics_hz=int(value)
	if report_path.is_empty() or not report_path.is_absolute_path():push_error("check_terrain_actors requires --report=<absolute path>");quit(1);return
	for action: String in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	observation_ticks=requested_physics_hz*20
	poll_interval_ticks=maxi(1,roundi(float(requested_physics_hz)/4.0))
	diagnostic_interval_ticks=requested_physics_hz*5
	Engine.physics_ticks_per_second=requested_physics_hz
	create_timer(900.0,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Transform3D:return {"origin":_json(value.origin),"basis":[_json(value.basis.x),_json(value.basis.y),_json(value.basis.z)]}
	if value is Rect2:return {"position":_json(value.position),"size":_json(value.size)}
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:result[str(key)]=_json(value[key])
		return result
	if value is Array or value is PackedVector3Array or value is PackedFloat64Array:
		var result: Array=[]
		for item: Variant in value:result.append(_json(item))
		return result
	if value is float:return value if is_finite(value) else null
	return value

func _check(title: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":_json(evidence)})
	if not passed:push_warning("TERRAIN_ACTORS_FAIL "+title)

func _error(kind: String,value: Dictionary) -> void:
	if errors[kind].size()<30:errors[kind].append(value)

func _ticks(count: int) -> void:
	# The camera signal follows priority-0 humans and priority-1 cars once per
	# physics tick. A render frame may contain several physics ticks on a busy PC.
	for index: int in range(count):await scene.rig.camera_stepped

func _xz_signature(points: Variant) -> String:
	var result: Array=[]
	for point: Vector3 in points:result.append([point.x,point.z])
	return JSON.stringify(result)

func _base_row(body: CharacterBody3D,kind: String) -> Dictionary:
	return {"body":body,"id":String(body.name),"kind":kind,"instance_id":body.get_instance_id(),"start":body.global_position,"previous":body.global_position,"distance_m":0.0,"maximum_excursion_m":0.0,"maximum_step_m":0.0,"minimum_y":body.global_position.y,"maximum_y":body.global_position.y,"minimum_ground_gap_m":INF,"maximum_ground_gap_m":-INF,"minimum_floor_normal_y":1.0,"floor_samples":0,"unsupported_samples":0,"minimum_vertical_velocity_mps":0.0,"state_ticks":{},"blocked_reason_ticks":{}}

func _shape_contract(shape: Shape3D) -> Dictionary:
	if shape is CapsuleShape3D:return {"class":"CapsuleShape3D","height":shape.height,"radius":shape.radius}
	if shape is BoxShape3D:return {"class":"BoxShape3D","size":shape.size}
	return {"class":shape.get_class()}

func _gather() -> void:
	for item: Array in [[scene.exploration_pedestrians,"original"],[scene.street_pedestrians,"street"],[scene.neighborhood_population.walkers,"coverage"]]:
		var module: Node3D=item[0]
		for group: Dictionary in module.groups:
			for member: Dictionary in group.members:
				var row: Dictionary=_base_row(member.body,String(member.kind));row["category"]=item[1];row["member"]=member;row["group"]=group;row["module"]=module
				row["shape_contract"]=_shape_contract(member.collider.shape);row["shape_id"]=member.collider.shape.get_instance_id();row["shape_transform"]=member.collider.transform;row["source_xz_signature"]=_xz_signature(group.points);row["source_arc"]=group.arc.duplicate()
				people.append(row)
	for body: CharacterBody3D in scene.vehicles+scene.neighborhood_population.traffic.vehicles:
		var row: Dictionary=_base_row(body,"vehicle");row["source_xz_signature"]=_xz_signature(body._points);row["source_arc"]=Array(body._arc);row["previous_station_m"]=body.get_station_m();row["previous_cycle"]=body._cycle_count;row["shape_contract"]=_shape_contract(body.body_shape.shape);row["shape_id"]=body.body_shape.shape.get_instance_id();row["shape_transform"]=body.body_shape.transform;row["minimum_body_up_dot_floor"]=1.0;row["maximum_grade"]=0.0;row["minimum_corner_gap_m"]=INF;row["maximum_corner_gap_m"]=-INF;row["interior_floor_samples"]=0;row["minimum_interior_gap_m"]=INF;row["maximum_interior_gap_m"]=-INF
		cars.append(row)

func _assert_live_layers(title: String) -> void:
	var errors: Array=[];var rows: Array=[]
	for row: Dictionary in people+cars:
		var body: CharacterBody3D=row.body
		var person: bool=row.kind!="vehicle"
		var expected_layer: int=4 if person else 8
		var expected_mask: int=47 if person else 31
		var shape: CollisionShape3D=body.get_node("CollisionShape")
		var item: Dictionary={"id":row.id,"layer":body.collision_layer,"mask":body.collision_mask,"shape_enabled":not shape.disabled}
		rows.append(item)
		if body.collision_layer!=expected_layer or body.collision_mask!=expected_mask or shape.disabled:errors.append(item)
	_check("collision.production_actor_layers_active_"+title,people.size()==30 and cars.size()==14 and errors.is_empty() and scene.player.collision_layer==2 and scene.player.collision_mask==45,{"actors":rows,"errors":errors,"expected_people_layer_mask":[4,47],"expected_vehicle_layer_mask":[8,31],"player_layer_mask":[scene.player.collision_layer,scene.player.collision_mask]})

func _floor_at(point: Vector3) -> Dictionary:
	var height: float=scene.terrain_surface.ground_y_world(point)
	if not is_finite(height):return {}
	var anchor: Vector3=Vector3(point.x,height,point.z)
	# Actor layers2/4/8 are absent from the floor mask. A bounded ray around the
	# sampled terrain cannot accidentally select a tree crown/upper hotel roof.
	return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(anchor+Vector3.UP*.65,anchor-Vector3.UP*.45,1|16|32))

func _actual_contacts(row: Dictionary) -> Array:
	var body: CharacterBody3D=row.body;var shape: CollisionShape3D=body.get_node("CollisionShape")
	var query: PhysicsShapeQueryParameters3D=PhysicsShapeQueryParameters3D.new();query.shape=shape.shape;query.transform=shape.global_transform;query.collision_mask=2|4|8;query.exclude=[body.get_rid()];query.margin=-.002
	var result: Array=[]
	for hit: Dictionary in scene.get_world_3d().direct_space_state.intersect_shape(query,8):result.append(String(hit.collider.name))
	return result

func _record_step(row: Dictionary,tick: int) -> void:
	var body: CharacterBody3D=row.body;var point: Vector3=body.global_position
	if not point.is_finite() or not body.velocity.is_finite():_error("finite",{"id":row.id,"tick":tick});return
	var step: float=Vector2(point.x-row.previous.x,point.z-row.previous.z).length()
	# A guard-authorized source-forward car recycle is a recorded lifecycle
	# event; exclude its one portal jump from continuous physical travel.
	var recycled: bool=row.kind=="vehicle" and body._cycle_count>int(row.previous_cycle)
	if not recycled:row.distance_m+=step;row.maximum_step_m=maxf(row.maximum_step_m,step)
	row.previous=point;row.maximum_excursion_m=maxf(row.maximum_excursion_m,point.distance_to(row.start));row.minimum_y=minf(row.minimum_y,point.y);row.maximum_y=maxf(row.maximum_y,point.y)
	row.minimum_vertical_velocity_mps=minf(row.minimum_vertical_velocity_mps,body.velocity.y)
	var state: String=String(body._state) if row.kind=="vehicle" else String(row.group.state)
	var reason: String=String(body._blocked_reason) if row.kind=="vehicle" else String(row.group.blocked_reason)
	row.state_ticks[state]=int(row.state_ticks.get(state,0))+1
	if not reason.is_empty():row.blocked_reason_ticks[reason]=int(row.blocked_reason_ticks.get(reason,0))+1
	var height: float=scene.terrain_surface.ground_y_world(point)
	if not is_finite(height) or point.y<height-.45 or body.velocity.y< -3.0:_error("freefall",{"id":row.id,"tick":tick,"point":point,"ground_y":height,"velocity":body.velocity})
	if row.kind=="vehicle":
		var station: float=body.get_station_m()
		if station<-.001 or station>body._length_m+.001 or (station<float(row.previous_station_m)-.002 and not recycled) or String(body._state)=="off_route" or float(body._max_route_offset_m)>.0031:_error("route",{"id":row.id,"tick":tick,"station":station,"previous_station":row.previous_station_m,"state":body._state,"recycled":recycled})
		row.previous_station_m=station;row.previous_cycle=body._cycle_count;row.maximum_grade=maxf(row.maximum_grade,float(body._terrain_grade))
	else:
		var group: Dictionary=row.group
		if float(group.station)<-.001 or float(group.station)>float(group.length)+.001 or not [-1,1].has(int(group.direction)):_error("route",{"id":row.id,"tick":tick,"station":group.station,"length":group.length,"direction":group.direction})

func _poll(row: Dictionary,tick: int) -> void:
	var body: CharacterBody3D=row.body;var floor: Dictionary=_floor_at(body.global_position);row.floor_samples+=1
	if row.kind!="vehicle":
		var local: Vector3=scene.city.to_local(body.global_position);var point: Vector2=Vector2(local.x,local.z);var closest: float=INF
		for index: int in range(1,row.group.points.size()):
			var first: Vector3=scene.city.to_local(row.group.points[index-1]);var last: Vector3=scene.city.to_local(row.group.points[index])
			closest=minf(closest,point.distance_to(Geometry2D.get_closest_point_to_segment(point,Vector2(first.x,first.z),Vector2(last.x,last.z))))
		var limit: float=absf(float(row.group.record.get("side_offset_m",0.0)))+absf(float(row.member.side))+1.25+.15
		if closest>limit:_error("route",{"id":row.id,"tick":tick,"source_polyline_distance_m":closest,"declared_side_and_passing_limit_m":limit})
	if floor.is_empty() or floor.normal.y<.72:
		row.unsupported_samples+=1;_error("support",{"id":row.id,"tick":tick,"point":body.global_position,"floor":floor.get("position"),"normal":floor.get("normal")})
	else:
		var gap: float=body.global_position.y-floor.position.y
		row.minimum_ground_gap_m=minf(row.minimum_ground_gap_m,gap);row.maximum_ground_gap_m=maxf(row.maximum_ground_gap_m,gap);row.minimum_floor_normal_y=minf(row.minimum_floor_normal_y,floor.normal.y)
		if gap<-.04 or gap>(.36 if row.kind=="vehicle" else .20):_error("support",{"id":row.id,"tick":tick,"point":body.global_position,"floor":floor.position,"gap_m":gap})
		if row.kind=="vehicle":row.minimum_body_up_dot_floor=minf(row.minimum_body_up_dot_floor,body.global_basis.y.normalized().dot(floor.normal))
	var contacts: Array=_actual_contacts(row)
	if not contacts.is_empty():_error("contacts",{"id":row.id,"tick":tick,"other":contacts})
	if row.kind!="vehicle":return
	for x: float in [-.87,.87]:
		for z: float in [-2.06,2.06]:
			var corner: Vector3=body.global_transform*Vector3(x,0.,z);var corner_floor: Dictionary=_floor_at(corner)
			if corner_floor.is_empty():_error("car_corners",{"id":row.id,"tick":tick,"corner":corner,"reason":"no_native_support"});continue
			var gap: float=corner.y-corner_floor.position.y
			row.minimum_corner_gap_m=minf(row.minimum_corner_gap_m,gap);row.maximum_corner_gap_m=maxf(row.maximum_corner_gap_m,gap)
			if gap<-.045 or gap>.4:_error("car_corners",{"id":row.id,"tick":tick,"corner":corner,"floor":corner_floor.position,"gap_m":gap})

func _poll_bottom_interior(row: Dictionary,tick: int) -> void:
	var body: CharacterBody3D=row.body
	var shape_node: CollisionShape3D=body.get_node("CollisionShape")
	var box: BoxShape3D=shape_node.shape as BoxShape3D
	if box==null:_error("car_bottom_interior",{"id":row.id,"tick":tick,"reason":"expected_actual_vehicle_box"});return
	# Read the native collider's real bottom plane. This deliberately does not
	# call the production envelope/pose code or infer its predicted clearance.
	var half_width: float=box.size.x*.5-.03;var half_length: float=box.size.z*.5-.04
	var x_count: int=maxi(1,int(ceil(half_width*2.0/.4)));var z_count: int=maxi(1,int(ceil(half_length*2.0/.4)))
	for ix: int in range(x_count+1):
		for iz: int in range(z_count+1):
			var point: Vector3=shape_node.global_transform*Vector3(lerpf(-half_width,half_width,float(ix)/x_count),-box.size.y*.5,lerpf(-half_length,half_length,float(iz)/z_count))
			var floor: Dictionary=_floor_at(point);row.interior_floor_samples+=1
			if floor.is_empty():_error("car_bottom_interior",{"id":row.id,"tick":tick,"point":point,"reason":"no_native_support"});continue
			var gap: float=point.y-floor.position.y
			row.minimum_interior_gap_m=minf(row.minimum_interior_gap_m,gap);row.maximum_interior_gap_m=maxf(row.maximum_interior_gap_m,gap)
			# Same existing corner limits: no tolerance expansion for the new
			# interior samples. A 0.4m grid is a sampled check, not a proof of all
			# continuous triangle intersections between these points/ticks.
			if gap<-.045 or gap>.4:_error("car_bottom_interior",{"id":row.id,"tick":tick,"point":point,"floor":floor.position,"gap_m":gap})

func _clean_row(row: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key: String in row:
		if key in ["body","member","module","group","source_xz_signature"]:continue
		result[key]=row[key]
	result["end"]=row.body.global_position
	if row.kind=="vehicle":result["final_controller"]=row.body.snapshot()
	else:result["final_group"]={"id":row.group.id,"station":row.group.station,"length":row.group.length,"direction":row.group.direction,"state":row.group.state,"blocked_reason":row.group.blocked_reason,"turns":row.group.turns,"passing_count":row.group.get("avoidance_count",0)}
	return result

func _motion() -> void:
	var trace: Array=[]
	for tick: int in range(observation_ticks):
		# One diagnostic tick per5 simulated seconds retains the original posed bounds even
		# on an early-empty result, independently checking actual containment.
		for row: Dictionary in cars:row.body.terrain_verify_early_bounds=tick%diagnostic_interval_ticks==0
		await _ticks(1)
		for row: Dictionary in people+cars:_record_step(row,tick)
		if tick%poll_interval_ticks==0 or tick%diagnostic_interval_ticks==0:
			var began: int=Time.get_ticks_usec()
			for row: Dictionary in people+cars:_poll(row,tick)
			if tick%diagnostic_interval_ticks==0:
				for row: Dictionary in cars:_poll_bottom_interior(row,tick)
			var cost: int=Time.get_ticks_usec()-began;maximum_poll_usec=maxi(maximum_poll_usec,cost);total_poll_usec+=cost;poll_count+=1
		if tick%requested_physics_hz==0:
			var positions: Array=[]
			for row: Dictionary in people+cars:positions.append({"id":row.id,"point":row.body.global_position,"state":String(row.body._state) if row.kind=="vehicle" else row.group.state})
			trace.append({"tick":tick,"actors":positions})
	var bound_checks: int=0;var bound_verified: int=0;var bound_empty: int=0;var bound_violations: int=0;var bound_details: Array=[]
	for row: Dictionary in cars:
		row.body.terrain_verify_early_bounds=false
		var diagnostic: Dictionary=row.body.snapshot().early_bounds
		bound_checks+=int(diagnostic.checks);bound_verified+=int(diagnostic.verified);bound_empty+=int(diagnostic.verified_empty);bound_violations+=int(diagnostic.violations)
		bound_details.append({"id":row.id,"bounds":diagnostic})
	_check("physics.early_broadphase_contains_all_original_posed_sweeps_on_diagnostic_ticks",bound_checks>=cars.size() and bound_details.all(func(row: Dictionary)->bool:return int(row.bounds.checks)>0 and int(row.bounds.verified)==int(row.bounds.checks)) and bound_verified==bound_checks and bound_empty>0 and bound_violations==0,{"checks":bound_checks,"verified":bound_verified,"verified_empty":bound_empty,"violations":bound_violations,"diagnostic_ticks":[0,diagnostic_interval_ticks,diagnostic_interval_ticks*2,diagnostic_interval_ticks*3],"cars":bound_details,"basis":"On diagnostic ticks even an early-empty query computes the complete existing half-metre posed swept-box bounds and checks actual enclosure. A violation falls back to full queries; sampled ticks do not replace the radius/terrain-height proof."})
	var moving_people: int=0;var moving_cars: int=0;var blocked: Array=[];var excessive_steps: Array=[];var preserving: Array=[];var normal_errors: Array=[]
	for row: Dictionary in people:
		if float(row.distance_m)>1.0 and float(row.maximum_excursion_m)>.4:moving_people+=1
		else:blocked.append(_clean_row(row))
		var limit: float=(1.35 if row.kind=="dog" else 1.2)/float(requested_physics_hz)+.006
		if row.maximum_step_m>limit:excessive_steps.append({"id":row.id,"actual":row.maximum_step_m,"limit":limit})
		if _xz_signature(row.group.points)!=row.source_xz_signature or row.group.arc!=row.source_arc or row.member.collider.shape.get_instance_id()!=int(row.shape_id) or _shape_contract(row.member.collider.shape)!=row.shape_contract or (row.member.collider.position!=row.shape_transform.origin or (row.kind!="dog" and row.member.collider.transform!=row.shape_transform)):preserving.append(row.id)
	for row: Dictionary in cars:
		if float(row.distance_m)>2.0 and float(row.maximum_excursion_m)>.75:moving_cars+=1
		else:blocked.append(_clean_row(row))
		if row.maximum_step_m>5.0/float(requested_physics_hz)+.006:excessive_steps.append({"id":row.id,"actual":row.maximum_step_m,"limit":5.0/float(requested_physics_hz)+.006})
		if _xz_signature(row.body._points)!=row.source_xz_signature or Array(row.body._arc)!=row.source_arc or row.body.body_shape.shape.get_instance_id()!=int(row.shape_id) or _shape_contract(row.body.body_shape.shape)!=row.shape_contract or row.body.body_shape.transform!=row.shape_transform:preserving.append(row.id)
		if row.minimum_body_up_dot_floor<.97:normal_errors.append({"id":row.id,"minimum_body_up_dot_native_floor":row.minimum_body_up_dot_floor})
	_check("motion.all_thirty_pedestrian_bodies_and_fourteen_cars_move_meaningfully",moving_people==30 and moving_cars==14,{"moving_people":moving_people,"moving_cars":moving_cars,"blocked_bodies":blocked,"thresholds":{"people_travel_m":1.0,"people_excursion_m":.4,"vehicle_travel_m":2.0,"vehicle_excursion_m":.75}})
	_check("motion.actual_per_physics_tick_steps_and_source_forward_station_are_bounded",excessive_steps.is_empty() and errors.route.is_empty(),{"excessive_steps":excessive_steps,"route_errors":errors.route})
	_check("ground.native_floor_and_whole_vehicle_corners_support_every_sample",errors.support.is_empty() and errors.car_corners.is_empty(),{"support_errors":errors.support,"corner_errors":errors.car_corners,"polls":poll_count,"poll_interval_ticks":poll_interval_ticks})
	var bottom_samples: int=0
	for row: Dictionary in cars:bottom_samples+=int(row.interior_floor_samples)
	_check("ground.native_rays_cover_all_vehicle_bottom_interiors_on_0_4m_grid",errors.car_bottom_interior.is_empty() and cars.all(func(row: Dictionary)->bool:return int(row.interior_floor_samples)>=288),{"errors":errors.car_bottom_interior,"samples":bottom_samples,"cars":cars.size(),"observation_ticks":[0,diagnostic_interval_ticks,diagnostic_interval_ticks*2,diagnostic_interval_ticks*3],"maximum_local_grid_spacing_m":.4,"limits_m":[-.045,.4],"basis":"Actual CollisionShape global transform and native floor rays, independent of production terrain envelope. Sampled interiors only, not a continuous all-times proof."})
	_check("ground.vehicle_body_up_matches_native_road_normal",normal_errors.is_empty(),{"normal_errors":normal_errors})
	_check("physics.no_actor_contact_penetration_freefall_nonfinite_or_player_recovery",errors.contacts.is_empty() and errors.freefall.is_empty() and errors.finite.is_empty() and scene.player.recoveries==player_recoveries,{"contacts":errors.contacts,"freefall":errors.freefall,"nonfinite":errors.finite,"player_recoveries_before":player_recoveries,"player_recoveries_after":scene.player.recoveries})
	_check("contracts.source_XZ_arc_lengths_capsules_and_boxes_stay_unchanged",preserving.is_empty(),{"changed_contracts":preserving})
	observations["motion"]={"ticks":observation_ticks,"physics_hz":requested_physics_hz,"simulated_seconds":20.0,"trace_1hz":trace,"people":people.map(_clean_row),"cars":cars.map(_clean_row),"production_actor_position_writes":0,"poll_cost":{"poll_count":poll_count,"maximum_usec":maximum_poll_usec,"total_usec":total_poll_usec,"meaning":"Cost of this test's periodic native sensor polling only; not game FPS or performance acceptance."}}

func _poses() -> Array:
	var result: Array=[]
	for row: Dictionary in people+cars:result.append(row.body.global_transform)
	return result

func _max_drift(before: Array) -> float:
	var result: float=0.0;var rows: Array=people+cars
	for index: int in range(rows.size()):result=maxf(result,before[index].origin.distance_to(rows[index].body.global_position))
	return result

func _toggles() -> void:
	scene.movement_switch.set_pressed(false);scene.traffic_switch.set_pressed(false);await _ticks(10)
	var before: Array=_poses();await _ticks(90)
	_check("toggles.actual_people_and_vehicle_checkboxes_freeze_all_existing_bodies",not scene.neighborhood_population.running and not scene.neighborhood_population.cars_running and _max_drift(before)<.003,{"maximum_drift_m":_max_drift(before),"people_switch":scene.movement_switch.button_pressed,"cars_switch":scene.traffic_switch.button_pressed})
	scene.movement_switch.set_pressed(true);scene.traffic_switch.set_pressed(true)
	var resumes: Array=_poses();await _ticks(120)
	var resumed_people: int=0;var resumed_cars: int=0;var rows: Array=people+cars
	for index: int in range(rows.size()):
		if resumes[index].origin.distance_to(rows[index].body.global_position)>.05:
			if rows[index].kind=="vehicle":resumed_cars+=1
			else:resumed_people+=1
	_check("toggles.same_actor_instances_resume_after_checkbox_release",resumed_people>0 and resumed_cars>0 and rows.all(func(row: Dictionary)->bool:return row.body.get_instance_id()==int(row.instance_id)),{"resumed_people":resumed_people,"resumed_cars":resumed_cars,"window_ticks":120,"blocked_states_remain_in_motion_report":true})
	scene.toggle_menu();var frozen: Array=_poses();var old_tick: int=scene.traffic.last_observation_tick;var new_tick: int=scene.neighborhood_population.traffic.manager.last_observation_tick
	for index: int in range(15):await process_frame
	_check("menu.actual_pause_freezes_all_poses_and_both_crossing_clocks",paused and frozen==_poses() and old_tick==scene.traffic.last_observation_tick and new_tick==scene.neighborhood_population.traffic.manager.last_observation_tick,{"old_tick_before":old_tick,"old_tick_after":scene.traffic.last_observation_tick,"new_tick_before":new_tick,"new_tick_after":scene.neighborhood_population.traffic.manager.last_observation_tick})
	scene.toggle_menu();await _ticks(3)
	_check("menu.resume_restarts_current_crossing_observations",not paused and scene.traffic.last_observation_tick>old_tick and scene.neighborhood_population.traffic.manager.last_observation_tick>new_tick)
	scene.movement_switch.set_pressed(false);scene.traffic_switch.set_pressed(false);await _ticks(90)

func _fixture_row(manager: Node,fixture: CharacterBody3D) -> Dictionary:
	for row: Dictionary in manager.human_rows:
		if row.id==str(fixture.get_path()):return row
	return {}

func _elevated_crossing() -> void:
	var manager: Node=scene.neighborhood_population.traffic.manager;var target: Dictionary={};var height: float=NAN
	for zone: Dictionary in manager.zones.values():
		var candidate: Vector3=scene.city.to_global(Vector3(zone.center.x,0.,zone.center.y));var ground: float=scene.terrain_surface.ground_y_world(candidate)
		if ground>2.8:target=zone;height=ground;break
	_check("crossing.real_source_crossing_exists_above_old_absolute_2_8m_limit",not target.is_empty(),{"selected":target,"ground_y":height})
	if target.is_empty():return
	var before: Array=_poses();var human_ids: Array=scene.traffic.humans.map(func(body: CharacterBody3D)->int:return body.get_instance_id())
	var fixture: CharacterBody3D=CharacterBody3D.new();fixture.name="EXP21_ExplicitElevatedCrossingHuman";fixture.collision_layer=4;fixture.collision_mask=0
	var collider: CollisionShape3D=CollisionShape3D.new();collider.name="CollisionShape";var capsule: CapsuleShape3D=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.7;collider.shape=capsule;collider.position.y=.85;fixture.add_child(collider);scene.add_child(fixture)
	fixture.global_position=scene.city.to_global(Vector3(target.center.x,height+.025,target.center.y));scene.traffic.register_human(fixture);await _ticks(3)
	var ground_row: Dictionary=_fixture_row(manager,fixture);var observed: bool=ground_row.get("crossings",[]).has(target.id)
	_check("crossing.current_native_human_above_2_8m_is_observed_at_its_ground_height",fixture.global_position.y>2.8 and observed and bool(target.human_present),{"fixture":fixture.global_position,"native_floor":_floor_at(fixture.global_position).get("position"),"human_row":ground_row,"zone":target})
	fixture.global_position.y+=8.0;await _ticks(3)
	var high_row: Dictionary=_fixture_row(manager,fixture)
	_check("crossing.same_XZ_human_far_above_the_street_does_not_occupy_ground_crossing",not high_row.get("crossings",[]).has(target.id),{"fixture":fixture.global_position,"ground_y":height,"human_row":high_row})
	scene.traffic.humans.erase(fixture);fixture.queue_free();await _ticks(3)
	var ids: Array=scene.traffic.humans.map(func(body: CharacterBody3D)->int:return body.get_instance_id())
	_check("crossing.fixture_cleanup_preserves_production_actor_poses_and_human_registry",ids==human_ids and _max_drift(before)<.003,{"maximum_actor_drift_m":_max_drift(before),"registry_before":human_ids,"registry_after":ids,"production_actor_position_writes":0,"explicit_fixture_position_writes":2})

func _capture(title: String,target: Vector3) -> void:
	if DisplayServer.get_name()=="headless":captures.append({"name":title,"captured":false,"reason":"dummy_backend_has_no_native_render"});return
	var destination: Dictionary={}
	for offset: Vector3 in [Vector3(3.,0.,3.),Vector3(-3.,0.,3.),Vector3(3.,0.,-3.),Vector3(-3.,0.,-3.),Vector3(0.,0.,5.),Vector3(5.,0.,0.)]:
		destination=scene.interior_visit._safe_external_point(target+offset)
		if destination.is_empty():continue
		var sight: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(destination.point+Vector3.UP*.9,target+Vector3.UP*.8,1|16|32)
		if scene.get_world_3d().direct_space_state.intersect_ray(sight).is_empty():break
		destination={}
	_check("view."+title+".safe_grounded_observer",not destination.is_empty(),{"target":target,"destination":destination})
	if destination.is_empty():return
	scene.player.global_transform=Transform3D(Basis.IDENTITY,destination.point);scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation()
	var direction: Vector3=target-destination.point;direction.y=0.
	scene.rig.yaw=atan2(-direction.x,-direction.z);scene.rig.pitch=deg_to_rad(-14.);scene.rig.requested_distance=4.8;scene.rig.snap_to_target_pose();await _ticks(4);await process_frame
	RenderingServer.force_draw(false,0.0)
	var target_head: Vector3=target+Vector3.UP*.8;var screen_point: Vector2=scene.rig.camera.unproject_position(target_head)
	var view_rect: Rect2=scene.get_viewport().get_visible_rect()
	_check("view."+title+".actual_target_projects_inside_native_camera",not scene.rig.camera.is_position_behind(target_head) and view_rect.has_point(screen_point),{"screen_point":screen_point,"viewport":view_rect,"target_head":target_head})
	var picture: Image=scene.get_viewport().get_texture().get_image();var path: String=report_path.trim_suffix(".json")+"_"+title+".png"
	var saved: bool=not picture.is_empty() and picture.save_png(path)==OK
	var row: Dictionary={"name":title,"captured":saved,"path":path,"width":picture.get_width(),"height":picture.get_height(),"observer":scene.player.global_position,"target":target,"camera":scene.rig.camera.global_transform,"basis":"Explicit safe observer placement after ordinary-motion acceptance; no production NPC/car placement."};captures.append(row);_check("capture."+title+".actual_native_viewport",saved,row)

func _run() -> void:
	started_usec=Time.get_ticks_usec()
	for path: String in ["res://scripts/terrain_surface.gd","res://scripts/terrain_geometry_warp.gd","res://scripts/explore_walk.gd","res://scripts/street_pedestrians.gd","res://scripts/exploration_pedestrian_avoidance.gd","res://scripts/pedestrian_corridor_avoidance.gd","res://scripts/neighborhood_population.gd","res://scripts/neighborhood_traffic.gd","res://scripts/traffic/vehicle.gd","res://scripts/traffic/traffic_manager.gd","res://scripts/neighborhood_greenery.gd","res://assets/authored/terrain_heightfield.json","res://data/generated/terrain_surface.json","res://data/generated/pedestrians.json","res://data/generated/traffic.json","res://assets/authored/neighborhood_population.json","res://../tests/game/check_terrain_actors.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_physics_hz=requested_physics_hz
	var settings_path: String=report_path+".settings.json";var settings: FileAccess=FileAccess.open(settings_path,FileAccess.WRITE);settings.store_string(JSON.stringify({"schema_version":1,"speed_id":"brisk","free_roam":true}));settings.close();scene.exploration_settings_path=settings_path;scene.quality_settings_path=settings_path+".quality.json";root.add_child(scene)
	for index: int in range(25):await physics_frame
	_check("startup.production_scene_loads_shared_terrain_and_all_dynamic_modules",scene.runtime_ok and is_instance_valid(scene.terrain_surface) and scene.terrain_surface.loaded and is_instance_valid(scene.neighborhood_population) and scene.neighborhood_population.loaded,{"runtime_ok":scene.runtime_ok,"error":scene.exploration_error,"terrain":scene.terrain_surface.snapshot() if is_instance_valid(scene.terrain_surface) else {}})
	if not scene.runtime_ok or not is_instance_valid(scene.neighborhood_population) or not scene.neighborhood_population.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	scene.set_time_profile("day");scene.set_free_roam(true);scene.set_pedestrians_running(true);scene.set_vehicles_running(true);await _ticks(6);player_recoveries=scene.player.recoveries
	_gather()
	_check("startup.exact_original_new_counts_and_requested_native_physics_hz",people.size()==30 and cars.size()==14 and scene.pedestrians.size()==2 and scene.street_pedestrians.actors.size()==8 and scene.neighborhood_population.walkers.actors.size()==20 and Engine.physics_ticks_per_second==requested_physics_hz,{"people":people.size(),"cars":cars.size(),"old_people":scene.pedestrians.size(),"old_street_actors":scene.street_pedestrians.actors.size(),"coverage_people":scene.neighborhood_population.walkers.actors.size(),"coverage_skipped":scene.neighborhood_population.walkers.skipped,"requested_physics_hz":requested_physics_hz,"actual_physics_hz":Engine.physics_ticks_per_second})
	_assert_live_layers("before_motion")
	await _motion();await _toggles();await _elevated_crossing()
	_assert_live_layers("after_fixtures")
	var highest: Dictionary=people[0]
	for row: Dictionary in people:
		if row.body.global_position.y>highest.body.global_position.y:highest=row
	await _capture("sloped_street_walkers",highest.body.global_position)
	var steepest: Dictionary=cars[0]
	for row: Dictionary in cars:
		if float(row.maximum_grade)>float(steepest.maximum_grade):steepest=row
	await _capture("source_road_vehicle_slope",steepest.body.global_position)
	var changed: Array=[]
	for path: String in source_hashes:
		if source_hashes[path]!=FileAccess.get_sha256(path):changed.append(path)
	_check("sources.frozen_during_actual_run",changed.is_empty(),{"changed":changed})
	observations["terrain"]=scene.terrain_surface.snapshot();_finish()

func _timeout() -> void:
	_check("execution.completes_within_wall_timeout",false,{"timeout_seconds":900});_finish()

func _finish() -> void:
	if finished:return
	finished=true;paused=false
	for action: String in ACTIONS:Input.action_release(action)
	var failed: int=0
	for row: Dictionary in checks:
		if not row.passed:failed+=1
	var report: Dictionary={"task":"EXP21_TERRAIN_ACTORS","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed,"actual_wall_usec":Time.get_ticks_usec()-started_usec,"requested_physics_hz":requested_physics_hz,"actual_physics_hz":Engine.physics_ticks_per_second,"observation_ticks":observation_ticks,"simulated_observation_seconds":20.0},"checks":checks,"observations":observations,"captures":captures,"scope":"Production ExploreWalk, %d actual physics ticks at requested%dHz (20 simulated seconds) and per-body movement/support/contact/source-station checks for30 pedestrian bodies and14 cars. Maximum step is the unchanged metre-per-second limit divided by requestedHz plus the existing.006m tolerance. Four5-second dense-floor/containment observations remain unchanged in simulated time. Explicit later crossing fixture and player observer starts only. Native PNGs require separate visual review. Poll timing is instrumentation cost, not FPS/performance acceptance, surveyed elevation, M4 or human-handling validation."%[observation_ticks,requested_physics_hz]}
	var file: FileAccess=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:failed+=1
	else:file.store_string(JSON.stringify(_json(report),"\t")+"\n");file.close()
	print("TERRAIN_ACTORS_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed);quit(0 if failed==0 else 1)
