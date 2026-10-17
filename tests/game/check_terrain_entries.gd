extends SceneTree
## EXP21 production-scene test. Street scenario starts are explicit fixtures;
## all subsequent walking, E interactions and elevator rides use production code.
const HOTEL_IDS := ["osm:way:233593619:building","osm:way:117914845:building"]
const ACTIONS := ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]
var report_path: String = ""
var requested_physics_hz: int = 60
var scene: Node3D
var visit: Node3D
var terrain: Node3D
var checks: Array=[]
var entries: Array=[]
var placements: Array=[]
var walks: Array=[]
var rides: Array=[]
var captures: Array=[]
var pool_trials: Array=[]
var completed_pool_roundtrips: int = 0
var sources: Dictionary={}
var finished: bool = false
var completed_journeys: int = 0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
		elif arg.begins_with("--physics-hz="):
			var value: String=arg.trim_prefix("--physics-hz=")
			if value not in ["30","60"]:push_error("--physics-hz must be 30 or 60");quit(1);return
			requested_physics_hz=int(value)
	if not report_path.is_absolute_path():push_error("--report=<absolute path> required");quit(1);return
	for action: String in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	if InputMap.has_action("interact"):InputMap.erase_action("interact")
	Engine.physics_ticks_per_second=requested_physics_hz
	create_timer(480.0,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Transform3D:return {"origin":_json(value.origin),"basis":[_json(value.basis.x),_json(value.basis.y),_json(value.basis.z)]}
	if value is AABB:return {"position":_json(value.position),"size":_json(value.size)}
	if value is Rect2:return {"position":_json(value.position),"size":_json(value.size)}
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:result[str(key)]=_json(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value:result.append(_json(item))
		return result
	return value

func _check(title: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":evidence})
	if not passed:push_warning("TERRAIN_ENTRY_FAIL "+title)

func _ticks(count: int) -> void:
	for tick in range(count):await physics_frame
	await process_frame

func _release() -> void:
	for action: String in ACTIONS:Input.action_release(action)

func _e(pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new();event.physical_keycode=KEY_E;event.keycode=KEY_E;event.pressed=pressed
	Input.parse_input_event(event)

func _keys(direction: Vector3) -> void:
	_release()
	var forward: Vector3=-scene.rig.camera.global_basis.z;forward.y=0.0;forward=forward.normalized()
	var right: Vector3=forward.cross(Vector3.UP).normalized()
	var x: float=direction.dot(right);var z: float=direction.dot(forward)
	if x>0.00001:Input.action_press("move_right",x)
	elif x<-.00001:Input.action_press("move_left",-x)
	if z>0.00001:Input.action_press("move_forward",z)
	elif z<-.00001:Input.action_press("move_backward",-z)

func _clearance(point: Vector3) -> Dictionary:
	var row: Dictionary = {"requested":point,"supported":false,"capsule_clear":false,"boundary_allowed":scene.player.exterior_contains(point),"ok":false}
	if not point.is_finite() or not row.boundary_allowed:return row
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point+Vector3.UP,point-Vector3.UP,scene.player.collision_mask,[scene.player.get_rid()])
	var hit: Dictionary=space.intersect_ray(ray)
	if hit.is_empty():return row
	row["hit_y"]=hit.position.y;row["normal"]=hit.normal
	row["support_geometry"]=str(hit.collider.get_meta("geometry_id",""))
	row.supported=hit.normal.dot(Vector3.UP)>=cos(scene.player.floor_max_angle) and absf(point.y-hit.position.y-.08)<.20
	var actual: Vector3 = Vector3(point.x,hit.position.y+.08,point.z)
	var node: CollisionShape3D=scene.player.get_node("CollisionShape")
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new();query.shape=node.shape
	query.transform=Transform3D(Basis.IDENTITY,actual)*node.transform
	query.collision_mask=scene.player.collision_mask;query.exclude=[scene.player.get_rid()]
	var blockers: Array[Dictionary]=space.intersect_shape(query,8)
	row.capsule_clear=blockers.is_empty();row["point"]=actual;row["blockers"]=[]
	for blocker: Dictionary in blockers:row.blockers.append(str(blocker.collider.get_path()))
	row.ok=row.supported and row.capsule_clear
	return row

func _source_bounds(node: Node3D,shape: Shape3D) -> AABB:
	var vertices: PackedVector3Array=shape.get_faces()
	if vertices.is_empty():return AABB()
	var box: AABB = AABB(node.to_global(vertices[0]),Vector3.ZERO)
	for vertex: Vector3 in vertices:box=box.expand(node.to_global(vertex))
	return box

func _audit_catalog() -> void:
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/interiors/source_catalog.json"))
	var extra: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/interiors/supplemental_catalog.json"))
	var original: Dictionary={}
	for record: Dictionary in raw.records+extra.records:original[String(record.id)]=record
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_geometry/world.json"))
	var meshes: Dictionary={}
	for mesh: Dictionary in world.meshes:meshes[String(mesh.id)]=mesh
	var binding_errors: Array=[];var anchor_errors: Array=[];var geometry_errors: Array=[];var no_valid: Array=[];var selected_blocked: Array=[]
	var candidate_count: int = 0;var candidate_blocked: int = 0
	for spec: Dictionary in visit.catalog:
		var id: String = String(spec.id)
		var base: float=terrain.building_base_y_world(id)
		if not original.has(id) or not is_finite(base):binding_errors.append(id);continue
		if not bool(spec.get("terrain_elevation_applied",false)) or absf(float(spec.base_offset_m)-base)>.0001 or absf(float(spec.source_height)-float(original[id].source_height))>.0001 or absf(float(spec.source_roof_world_y)-base-float(spec.source_height))>.0001:binding_errors.append(id)
		var entry_ground: float=terrain.ground_y_world(spec.flat_source_entrance)
		if not is_finite(entry_ground) or absf(spec.entrance.y-spec.flat_source_entrance.y-entry_ground)>.0001 or absf(float(spec.entry_surface_adjustment_m)-entry_ground+base)>.0001 or absf(spec.door.y-spec.flat_source_door.y-base)>.0001:anchor_errors.append(id)
		var selected: Dictionary=_clearance(spec.entrance)
		if not selected.ok:selected_blocked.append(id)
		var candidate_rows: Array=[];var valid_count: int = 0
		for candidate: Dictionary in spec.entry_candidates:
			candidate_count+=1
			var candidate_ground: float=terrain.ground_y_world(candidate.flat_source_entrance)
			if not is_finite(candidate_ground) or absf(candidate.entrance.y-candidate.flat_source_entrance.y-candidate_ground)>.0001 or absf(float(candidate.entry_surface_adjustment_m)-candidate_ground+base)>.0001 or absf(candidate.door.y-candidate.flat_source_door.y-base)>.0001:anchor_errors.append(id+"/candidate")
			var row: Dictionary=_clearance(candidate.entrance)
			candidate_rows.append(row)
			if row.ok:valid_count+=1
			else:candidate_blocked+=1
		if valid_count==0:no_valid.append(id)
		var source_node: MeshInstance3D=scene.city.source_nodes.get(id)
		var visible_bounds: AABB=source_node.global_transform*source_node.get_aabb()
		var source_mesh: Dictionary=meshes.get(id,{})
		var geometry: Dictionary={"visible_source_bounds":visible_bounds}
		var expected_min: Vector3 = Vector3(INF,INF,INF);var expected_max: Vector3 = Vector3(-INF,-INF,-INF)
		for index in range(0,source_mesh.get("vertices",[]).size(),3):
			var vertex: Vector3 = Vector3(source_mesh.vertices[index],source_mesh.vertices[index+1]+base,source_mesh.vertices[index+2])
			expected_min=expected_min.min(vertex);expected_max=expected_max.max(vertex)
		var expected: AABB = AABB(expected_min,expected_max-expected_min)
		if not visible_bounds.position.is_equal_approx(expected.position) or not visible_bounds.size.is_equal_approx(expected.size):geometry_errors.append({"id":id,"kind":"source_visual","expected":expected,"observed":visible_bounds})
		var body: StaticBody3D=scene.city.bodies.get(id)
		if not is_instance_valid(body):geometry_errors.append({"id":id,"kind":"missing_source_body"})
		else:
			var node: CollisionShape3D=body.get_node("CollisionShape")
			var native: AABB=_source_bounds(node,node.shape)
			geometry["native_source_bounds"]=native
			if absf(native.position.y-expected.position.y)>.001 or absf(native.end.y-expected.end.y)>.001:geometry_errors.append({"id":id,"kind":"native_bottom_roof","expected":expected,"observed":native})
		entries.append({"id":id,"title":spec.title,"base_offset_m":base,"source_height_m":spec.source_height,"source_roof_world_y":spec.source_roof_world_y,"entry_surface_adjustment_m":spec.entry_surface_adjustment_m,"entrance_ground_y_m":spec.entrance_ground_y_m,"selected":selected,"valid_candidates":valid_count,"candidates":candidate_rows,"geometry":geometry})
	_check("catalog.exact_126_source_buildings",visit.catalog.size()==126 and original.size()==126,{"catalog":visit.catalog.size(),"source_records":original.size()})
	_check("catalog.foundation_offset_preserves_source_height_thickness",binding_errors.is_empty(),{"errors":binding_errors})
	_check("catalog.facade_doors_follow_foundations_and_entry_feet_follow_actual_pavement",anchor_errors.is_empty(),{"errors":anchor_errors})
	_check("catalog.native_source_bottom_roof_and_XZ_match_original_plus_base",geometry_errors.is_empty(),{"errors":geometry_errors})
	_check("catalog.every_building_has_native_supported_clear_entry",no_valid.is_empty(),{"missing_valid_entry":no_valid,"selected_blocked":selected_blocked,"candidate_count":candidate_count,"candidate_blocked":candidate_blocked,"scope":"All source candidates are measured; unselected blocked candidates are reported, not individually required to be clear."})
	_check("startup.terrain_rebased_exactly_once",visit.terrain_rebase_count==1 and scene.player.terrain_surface==terrain,{"rebase_count":visit.terrain_rebase_count,"player_spawn":scene.player.spawn_transform.origin})

func _place(title: String,point: Vector3) -> bool:
	_release();_e(false)
	placements.append({"name":title,"kind":"explicit_test_only_street_scenario_teleport_not_a_walk_or_ascent","point":point})
	scene.player.global_transform=Transform3D(Basis.IDENTITY,point)
	scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation()
	scene.rig.snap_to_target_pose();await _ticks(16)
	return scene.player.is_on_floor() and not scene.player.input_latched

func _walk(title: String,path: Array) -> bool:
	var recoveries: int=scene.player.recoveries;var samples: int = 0;var grounded: int = 0;var reached_all: bool = true
	for target: Vector3 in path:
		var reached: bool = false
		var start: Vector3=scene.player.global_position
		var hz: int=Engine.physics_ticks_per_second
		var budget: int = maxi(2*hz,int(ceil(Vector2(target.x-start.x,target.z-start.z).length()/scene.player.walk_speed_mps*float(hz)))*3+int(1.5*float(hz)))
		for tick in range(budget):
			var offset: Vector3=target-scene.player.global_position
			var horizontal: Vector3 = Vector3(offset.x,0.0,offset.z)
			if horizontal.length()<.18 and absf(offset.y)<.40:reached=true;break
			_keys(horizontal.normalized());await scene.player.physics_stepped;samples+=1
			if scene.player.is_on_floor():grounded+=1
			if scene.player.recoveries!=recoveries:break
		if not reached:reached_all=false;break
	_release();await _ticks(4)
	var row: Dictionary={"name":title,"completed":reached_all,"samples":samples,"grounded_samples":grounded,"recoveries":scene.player.recoveries-recoveries,"final":scene.player.global_position,"path":path,"kind":"actual_production_Input_and_move_and_slide_no_path_teleports"}
	walks.append(row)
	_check(title,reached_all and samples>2 and scene.player.recoveries==recoveries and scene.player.is_on_floor(),row)
	return reached_all

func _capture(title: String) -> void:
	if DisplayServer.get_name()=="headless":captures.append({"name":title,"captured":false,"reason":"headless_no_viewport_pixels"});return
	await process_frame;RenderingServer.force_draw(false,0.0)
	var picture: Image=scene.get_viewport().get_texture().get_image()
	var path: String = report_path.trim_suffix(".json")+"_"+title+".png"
	var saved: bool = not picture.is_empty() and picture.save_png(path)==OK
	var row: Dictionary={"name":title,"captured":saved,"path":path,"player":scene.player.global_position,"camera":scene.rig.camera.global_transform,"visit":visit.snapshot()}
	captures.append(row);_check("capture."+title,saved,row)

func _ride(title: String,index: int) -> bool:
	_e(true);_e(false);await _ticks(3)
	var picker: bool = visit.elevator_open and visit.elevator_floors.get_child_count()==visit.destination_count()
	_check(title+".fresh_E_opens_real_floor_picker",picker,{"visit":visit.snapshot()})
	if not picker:return false
	visit.elevator_floors.get_child(index).pressed.emit()
	var started: bool=visit.in_elevator and visit.selected_floor==index and not scene.player.water_snapshot().registered
	_check(title+".actual_destination_button_starts_cabin",started,visit.elevator_snapshot())
	if not started:return false
	var phases: Dictionary={};var ticks: int = 0;var fixed: bool = true;var camera: bool = true;var closed: bool = true
	var passenger: Vector3=scene.player.global_position
	var physics_start: int=Engine.get_physics_frames()
	for tick in range(60*Engine.physics_ticks_per_second):
		if not visit.in_elevator:break
		await physics_frame;ticks+=1
		if not visit.in_elevator:break
		var state: Dictionary=visit.elevator_snapshot();phases[String(state.phase)]=true
		fixed=fixed and scene.player.global_position.distance_to(passenger)<.001
		camera=camera and visit.cabin.camera.current and scene.get_viewport().get_camera_3d()==visit.cabin.camera
		if String(state.phase) in ["accelerating","cruising","decelerating"]:closed=closed and float(state.door_open_fraction)<.001
	var physics_frames: int=Engine.get_physics_frames()-physics_start
	var elapsed_seconds: float=visit._ride_elapsed
	var configured_seconds: float=visit._ride_duration
	_release();_e(false);await _ticks(12)
	var arrived: bool=not visit.in_elevator and visit.active and visit.selected_floor==index and scene.player.is_on_floor()
	var row: Dictionary={"name":title,"destination":index,"observation_samples":ticks,"physics_frames":physics_frames,"ride_elapsed_seconds":elapsed_seconds,"configured_duration_seconds":configured_seconds,"phases":phases.keys(),"fixed_passenger":fixed,"actual_cabin_camera":camera,"motion_doors_closed":closed,"arrived":arrived,"player":scene.player.global_position,"visit":visit.snapshot()}
	rides.append(row)
	_check(title+".full_phased_cabin_arrives_supported",arrived and fixed and camera and closed and physics_frames>int(2.5*float(Engine.physics_ticks_per_second)) and elapsed_seconds>=configured_seconds-.05 and phases.has("closing") and phases.has("accelerating") and phases.has("decelerating") and phases.has("opening"),row)
	return arrived


func _pool_move_to(title: String,target: Vector3) -> Dictionary:
	# Observe every real player physics step. A render frame can contain
	# several steps, so it cannot be used as a movement or wet-tick counter.
	var start: Vector3=scene.player.global_position
	var recoveries: int=scene.player.recoveries
	var before: Dictionary=scene.player.water_snapshot()
	var samples: int=0;var wet: int=0;var grounded: int=0;var peak_speed: float=0.0;var reached: bool=false
	for tick in range(25*Engine.physics_ticks_per_second):
		var offset: Vector3=Vector3(target.x-scene.player.global_position.x,0.0,target.z-scene.player.global_position.z)
		if offset.length()<.18:reached=true;break
		_keys(offset.normalized());await scene.player.physics_stepped
		samples+=1
		if scene.player.is_swimming():wet+=1
		if scene.player.is_on_floor():grounded+=1
		peak_speed=maxf(peak_speed,Vector2(scene.player.velocity.x,scene.player.velocity.z).length())
		if scene.player.recoveries!=recoveries:break
	_release();await _ticks(3)
	var row: Dictionary={"name":title,"start":start,"end":scene.player.global_position,"target":target,"reached":reached,"physics_samples":samples,"wet_samples":wet,"grounded_samples":grounded,"peak_horizontal_speed_mps":peak_speed,"horizontal_distance_m":Vector2(scene.player.global_position.x-start.x,scene.player.global_position.z-start.z).length(),"height_drop_m":start.y-scene.player.global_position.y,"recoveries":scene.player.recoveries-recoveries,"before":before,"after":scene.player.water_snapshot(),"kind":"production_Input_and_move_and_slide_no_midroof_pose_or_velocity_assignment"}
	pool_trials.append(row)
	return row

func _plaza_pool_roundtrip(roof: Node3D,title: String) -> bool:
	var region: Dictionary=roof.pool_water_region()
	var rect: Rect2=region.rect
	var entry: Vector3=roof.pool_entry_point()
	var entry_local: Vector3=roof.frame.affine_inverse()*entry
	var lift_local: Vector3=roof.frame.affine_inverse()*roof.lift_point()
	var front_z: float=rect.end.y+4.44
	var recoveries: int=scene.player.recoveries
	var registered: Dictionary=scene.player.water_snapshot()
	_check(title+".pool.active_water_frame_follows_rebased_roof",bool(registered.registered) and String(registered.id)==String(region.id) and absf(float(registered.surface_y_world)-(roof.frame.origin.y+float(region.surface_y)))<.001 and not scene.player.is_swimming(),{"registered":registered,"region":region,"roof_origin":roof.frame.origin})
	# Walk around the open front terrace and through the real gate. No
	# shortcut, teleport, velocity assignment or altered collider is used.
	if not await _walk(title+".pool.actual_lift_to_entry_walk",[roof.frame*Vector3(0.0,.08,front_z),roof.frame*Vector3(entry_local.x,.08,front_z),entry,roof.pool_rim_point()]):return false
	var descent: Dictionary=await _pool_move_to(title+".pool.walk_down_submerged_steps",roof.pool_steps_bottom_point())
	var descended: bool=bool(descent.reached) and int(descent.grounded_samples)>4 and int(descent.wet_samples)>5 and float(descent.height_drop_m)>.55 and scene.player.is_swimming() and int(descent.after.entry_count)>int(descent.before.entry_count) and int(descent.after.water_jump_count)==int(descent.before.water_jump_count) and int(descent.recoveries)==0
	_check(title+".pool.actual_steps_enter_water_without_jump_or_pose_assignment",descended,descent)
	if not descended:return false
	# Move clear of the submerged entry slope so buoyancy and actual swim
	# distance are measured independently of the supported walking section.
	var lane: Vector3=roof.frame*Vector3(rect.end.x-4.0,float(region.surface_y)-1.0,rect.get_center().y)
	var swim: Dictionary=await _pool_move_to(title+".pool.real_swim_lane",lane)
	var swam: bool=bool(swim.reached) and float(swim.horizontal_distance_m)>2.5 and int(swim.wet_samples)>=int(swim.physics_samples)-2 and float(swim.peak_horizontal_speed_mps)<=3.02 and scene.player.is_swimming() and int(swim.recoveries)==0
	_check(title+".pool.actual_rebased_water_swim_has_distance_and_speed_limit",swam,swim)
	if not swam:return false
	var direction: Vector3=-roof.frame.basis.x
	scene.rig.yaw=atan2(-direction.x,-direction.z);scene.rig.pitch=deg_to_rad(-20.0);scene.rig.requested_distance=4.0;scene.rig.snap_to_target_pose()
	await _capture(title+"_actual_swimming_rebased_pool")
	var shore: Vector3=roof.frame*Vector3(rect.end.x-.58,float(region.surface_y)-1.0,rect.get_center().y)
	var shore_trial: Dictionary=await _pool_move_to(title+".pool.swim_to_right_shore",shore)
	if not bool(shore_trial.reached):_check(title+".pool.reaches_exit_shore",false,shore_trial);return false
	var before: Dictionary=scene.player.water_snapshot()
	var start: Vector3=scene.player.global_position
	var outward: Vector3=roof.frame.basis.x
	_keys(outward);Input.action_press("jump")
	var peak: float=start.y;var outside: bool=false;var stopped: bool=false;var landed: bool=false;var physics_samples: int=0
	for tick in range(8*Engine.physics_ticks_per_second):
		await scene.player.physics_stepped;physics_samples+=1
		peak=maxf(peak,scene.player.global_position.y)
		var local: Vector3=roof.frame.affine_inverse()*scene.player.global_position
		outside=local.x>rect.end.x+.85
		if outside and not stopped:
			for action: String in ACTIONS:
				if action!="jump":Input.action_release(action)
			stopped=true
		if outside and not scene.player.is_swimming() and scene.player.is_on_floor() and absf(scene.player.global_position.y-roof.deck_height_y)<.15:landed=true;break
		if scene.player.recoveries!=recoveries:break
	var after: Dictionary=scene.player.water_snapshot()
	var row: Dictionary={"name":title+".pool.Space_exit","start":start,"end":scene.player.global_position,"peak_world_y":peak,"deck_world_y":roof.deck_height_y,"outside_water":outside,"grounded":scene.player.is_on_floor(),"physics_samples":physics_samples,"recoveries":scene.player.recoveries-recoveries,"before":before,"after":after,"kind":"single_fresh_Space_water_exit_real_ballistic_motion_and_physical_deck_landing_no_pose_or_velocity_assignment"}
	pool_trials.append(row)
	var exited: bool=landed and peak>roof.deck_height_y+.25 and int(after.water_jump_count)==int(before.water_jump_count)+1 and scene.player.recoveries==recoveries
	_check(title+".pool.fresh_Space_exits_and_lands_on_same_rebased_deck",exited,row)
	_release();await _ticks(6)
	if not exited:return false
	await _capture(title+"_actual_pool_exit_on_rebased_deck")
	var current: Vector3=roof.frame.affine_inverse()*scene.player.global_position
	if not await _walk(title+".pool.actual_deck_walk_back_to_lift",[roof.frame*Vector3(current.x,.08,front_z),roof.frame*Vector3(current.x,.08,lift_local.z-2.8),roof.lift_point()]):return false
	_check(title+".pool.roundtrip_preserves_visit_and_lift_contact",visit.active and visit.on_roof and visit._elevator_near() and not scene.player.is_swimming() and scene.player.is_on_floor() and scene.player.recoveries==recoveries,{"player":scene.player.global_position,"lift":roof.lift_point(),"water":scene.player.water_snapshot(),"visit":visit.snapshot()})
	completed_pool_roundtrips+=1
	return true

func _hotel_journey(id: String,title: String) -> bool:
	if not visit.select_building(id):_check(title+".select",false);return false
	var point: Vector3=visit.current_spec.entrance
	var outside: Dictionary=_clearance(point)
	_check(title+".selected_source_entry_has_support_and_capsule_clearance",outside.ok,outside)
	if not outside.ok:return false
	var placed: bool=await _place(title+"_street_start",outside.point)
	_check(title+".street_fixture_grounded_at_expected_elevation",placed and absf(scene.player.global_position.y-terrain.ground_y_world(scene.player.global_position))<.12,{"player":scene.player.global_position,"ground_y":terrain.ground_y_world(scene.player.global_position)})
	if not placed:return false
	await _capture(title+"_ground_entrance")
	var old_entries: int=visit.entry_count
	_e(true);_e(false);await _ticks(10)
	var entered: bool=visit.active and not visit.on_roof and visit.entry_count==old_entries+1 and String(visit.current_spec.id)==id and scene.player.interior_active and scene.player.is_on_floor()
	_check(title+".fresh_E_enters_correct_building_detached_lobby",entered,visit.snapshot())
	if not entered:return false
	var room: Node3D=visit.room
	if not await _walk(title+".actual_lobby_walk_to_lift",[room.to_global(Vector3(0.0,.08,room.depth*.5-1.65)),room.elevator_point(0)]):return false
	await _capture(title+"_lobby_lift")
	if not await _ride(title+".up_to_roof",int(visit.current_spec.floor_count)):return false
	var roof: Node3D=visit.rooftop
	var expected_roof: float=float(visit.current_spec.base_offset_m)+float(visit.current_spec.source_height)
	var water: Dictionary=roof.pool_water_region()
	_check(title+".roof_water_and_lift_follow_source_building_elevation",visit.on_roof and absf(roof.source_height_y-expected_roof)<.001 and roof.frame.origin.y>=expected_roof+.28-.001 and water.get("frame",Transform3D.IDENTITY)==roof.frame and absf(float(water.get("surface_y",0.0))-float(water.get("floor_y",0.0))-1.22)<.001,{"expected_source_roof_y":expected_roof,"roof":roof.snapshot(),"water":water})
	await _capture(title+"_rebased_roof_lift")
	# Plaza adds a continuous real pool excursion between these two rides.
	# Lotte verifies the direct landing-to-return path without a second pose.
	if id==HOTEL_IDS[0]:
		if not await _plaza_pool_roundtrip(roof,title):return false
	if not await _ride(title+".roof_to_first_floor",0):return false
	if not await _walk(title+".actual_first_floor_walk_to_exit",[room.to_global(Vector3(0.0,.08,room.depth*.5-1.65)),room.exit_point()]):return false
	var expected: Vector3=visit._outside_position
	var exits: int=visit.exit_count
	_e(true);_e(false);await _ticks(12)
	var returned: bool=not visit.active and not scene.player.interior_active and scene.player.is_on_floor() and visit.exit_count==exits+1 and scene.player.global_position.distance_to(expected)<.16 and not visit._safe_external_point(scene.player.global_position).is_empty()
	_check(title+".fresh_E_returns_to_same_supported_ground_entry",returned and String(visit.current_spec.id)==id and not scene.player.water_snapshot().registered,{"expected":expected,"actual":scene.player.global_position,"ground_y":terrain.ground_y_world(scene.player.global_position),"visit":visit.snapshot()})
	await _capture(title+"_ground_return")
	if returned:completed_journeys+=1
	return returned

func _run() -> void:
	for path: String in ["res://scripts/explore_walk.gd","res://scripts/terrain_surface.gd","res://scripts/terrain_scene_binding.gd","res://scripts/terrain_geometry_warp.gd","res://scripts/building_visit_catalog.gd","res://scripts/interior_visit.gd","res://scripts/exploration_rooftop_access.gd","res://scripts/rooftop_space.gd","res://scripts/water_effect.gd","res://scripts/player/free_roam_player.gd","res://scripts/entrance_wayfinding.gd","res://assets/authored/terrain_heightfield.json","res://data/generated/terrain_surface.json","res://assets/authored/interiors/source_catalog.json","res://assets/authored/interiors/supplemental_catalog.json","res://resources/world_geometry/world.json","res://../tests/game/check_terrain_entries.gd"]:
		sources[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_physics_hz=requested_physics_hz
	scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json"
	root.add_child(scene)
	await _ticks(25)
	_check("startup.production_terrain_scene_ready",scene.runtime_ok and scene.exploration_error.is_empty(),{"runtime_ok":scene.runtime_ok,"error":scene.exploration_error})
	if not scene.runtime_ok or not is_instance_valid(scene.terrain_surface):_finish();return
	visit=scene.interior_visit;terrain=scene.terrain_surface
	_check("startup.requested_physics_rate_applied",Engine.physics_ticks_per_second==requested_physics_hz,{"requested_hz":requested_physics_hz,"actual_hz":Engine.physics_ticks_per_second})
	_check("startup.shared_terrain_loaded",terrain.loaded and terrain.data_ready,terrain.snapshot())
	if not terrain.loaded:_finish();return
	scene.set_free_roam(true);scene.set_speed_profile("fast");scene.set_time_profile("day")
	# Entry/ride isolation: outdoor actors are verified independently by the
	#1200-tick terrain actor suite; keep every player/cabin/floor collider live.
	scene.set_pedestrians_running(false);scene.set_vehicles_running(false)
	_release();_e(false);await _ticks(5)
	_audit_catalog()
	if not await _hotel_journey(HOTEL_IDS[0],"plaza"):_finish();return
	if not await _hotel_journey(HOTEL_IDS[1],"lotte"):_finish();return
	_finish()

func _timeout() -> void:
	if not finished:_check("timeout",false);_finish()

func _finish() -> void:
	if finished:return
	finished=true;_release();_e(false);paused=false
	_check("acceptance.both_hotels_complete_real_ground_roof_ground_journeys",completed_journeys==2 and rides.size()==4 and completed_pool_roundtrips==1,{"journeys":completed_journeys,"rides":rides.size(),"actual_pool_roundtrips":completed_pool_roundtrips})
	var failed: int = 0
	for check: Dictionary in checks:
		if not check.passed:failed+=1
	var report: Dictionary={"task":"EXP21_TERRAIN_ENTRIES","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"physics_ticks_per_second":Engine.physics_ticks_per_second,"requested_physics_hz":requested_physics_hz,"source_sha256":sources,"summary":{"checks":checks.size(),"failed":failed,"catalog":entries.size(),"completed_hotel_journeys":completed_journeys,"actual_pool_roundtrips":completed_pool_roundtrips},"checks":checks,"entries":entries,"placements":placements,"walks":walks,"rides":rides,"pool_trials":pool_trials,"captures":captures,"fixtures":{"outdoor_people_running":false,"outdoor_cars_running":false,"player_cabin_and_floor_physics_enabled":true},"scope":"All126source-linked foundation/door candidates and native source building bounds are measured. Unselected blocked candidate counts are retained; at least one physical entry per source building is required. Two street scenario starts are explicit test teleports. Subsequent lobby walks, fresh physical E, actual floor-picker buttons, full phased cabin rides, roof E without another pose, and walkout use production controllers. Plaza continuously walks from the arrival lift through the gate and submerged steps, swims, uses fresh Space to exit onto the rebased deck, walks back to the same lift and descends; no intermediate rooftop pose or velocity assignment is used. Movement observation limits are expressed in seconds at the requested30or60Hz; actual elapsed ride time and actual physics frames remain independent of rendered observation samples. Screenshots are actual native viewport pixels only when rendered. No survey, real access, full external street journey, human usability, M4 or export claim."}
	var file: FileAccess = FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot save terrain entry report");quit(1);return
	file.store_string(JSON.stringify(_json(report),"\t")+"\n");file.close()
	print("TERRAIN_ENTRIES_TEST ",report.result," checks=",checks.size()," failed=",failed," journeys=",completed_journeys)
	quit(0 if failed==0 else 1)
