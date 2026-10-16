extends SceneTree
## Integrated latest-city physics/GPU probe; every camera/player placement is test-only.
## --report=/absolute/result.json --automatic-probe; PNGs use result_<view>.png.
const ACTIONS := ["move_left","move_right","move_forward","move_backward","move_fast","jump","interact","toggle_menu"]
const CITY_HALL := "osm:way:198561926:building"
const LIBRARY := "osm:relation:10757525:building"
var report_path := ""
var scene
var checks: Array = []
var trials: Array = []
var captures: Array = []
var placements: Array = []
var finished := false
var physics_seconds := 0.0
var physics_ticks := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	if report_path.is_empty() or not report_path.is_absolute_path():
		push_error("check_seoul_detail requires --report=<absolute path>")
		quit(1)
		return
	# Do not touch the user's saved settings or physical keys. Pre-register jump
	# without an event so the scene cannot add a physical Space event in this probe.
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action)
		Input.action_release(action)
	Engine.physics_ticks_per_second=60
	create_timer(90.0,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _check(title: String, passed: bool, evidence: Dictionary = {}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":evidence})
	if not passed:push_warning("SEOUL_DETAIL_CHECK_FAIL "+title)

func _v(point: Vector3) -> Array:return [point.x,point.y,point.z]

func _keys(actions: Array) -> void:
	for action in ACTIONS:Input.action_release(action)
	for action in actions:Input.action_press(action)

func _tick() -> void:
	var delta: float=await scene.player.physics_stepped
	physics_seconds+=delta
	physics_ticks+=1

func _ticks(count: int) -> void:
	for index in range(count):await _tick()

func _clear_at(point: Vector3) -> bool:
	if not scene.player._inside(point):return false
	var query:=PhysicsShapeQueryParameters3D.new()
	var collision: CollisionShape3D=scene.player.get_node("CollisionShape")
	query.shape=collision.shape
	query.transform=Transform3D(Basis.IDENTITY,point)*collision.transform
	query.collision_mask=scene.player.collision_mask
	query.exclude=[scene.player.get_rid()]
	return scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _pose(title: String, point: Vector3) -> bool:
	_keys([])
	var clear:=_clear_at(point)
	placements.append({"name":title,"kind":"explicit_test_only_teleport","position":_v(point),"capsule_clear":clear})
	_check("placement."+title,clear,placements[-1])
	if not clear:return false
	scene.player.global_transform=Transform3D(Basis.IDENTITY,point)
	scene.player.velocity=Vector3.ZERO
	scene.player.require_neutral_input()
	scene.rig.reset_orientation()
	await _ticks(20)
	_check("placement."+title+".grounded",scene.player.is_on_floor() and not scene.player.input_latched,{"position":_v(scene.player.global_position)})
	return true

func _vehicle_states() -> Dictionary:
	var result:={}
	for body in scene.vehicles:result[body.get_route_id()]=body.snapshot().duplicate(true)
	return result

func _physics_inventory() -> void:
	var source_active:=0
	var fragment_active:=0
	var bad_shapes:=[]
	for id in scene.city.bodies:
		var body: StaticBody3D=scene.city.bodies[id]
		if body.collision_layer!=0:source_active+=1
		var collision: CollisionShape3D=body.get_node("CollisionShape")
		if collision.disabled or not collision.shape is ConcavePolygonShape3D or not collision.shape.backface_collision:bad_shapes.append(id)
	for body in scene.city.fragments.values():
		if body.collision_layer!=0:fragment_active+=1
	var evidence:={"source_count":scene.city.bodies.size(),"active_source":source_active,"fragment_count":scene.city.fragments.size(),"active_fragments":fragment_active,"road_supports":scene.road_supports.size(),"bad_shapes":bad_shapes,"player_layer":scene.player.collision_layer,"player_mask":scene.player.collision_mask,"camera_mask":scene.rig.arm.collision_mask}
	_check("physics.source_collision_preserved",scene.city.bodies.size()==685 and source_active==682 and fragment_active==5 and bad_shapes.is_empty(),evidence)
	_check("physics.exploration_support_isolated",scene.road_supports.size()==2 and scene.exploration_overlay.support.collision_layer==32 and scene.exploration_overlay.support.collision_mask==2 and scene.player.collision_layer==2 and scene.player.collision_mask==45 and scene.rig.arm.collision_mask==33,evidence)
	for body in scene.vehicles:
		_check("physics.vehicle_mask."+body.get_route_id(),body.collision_layer==8 and body.collision_mask==31,{"layer":body.collision_layer,"mask":body.collision_mask})

func _appearance_checks() -> void:
	var identity=scene.seoul_identity
	_check("appearance.loaded",identity.loaded and identity.load_error.is_empty(),{"error":identity.load_error})
	_check("appearance.inventory",identity.wall_count==3 and identity.landmark_count==9 and identity.detail_mesh_count==6 and identity.ornament_count==267 and identity.material_count==18,{"walls":identity.wall_count,"landmarks":identity.landmark_count,"detail_meshes":identity.detail_mesh_count,"ornaments":identity.ornament_count,"materials":identity.material_count})
	var removed:=0
	var retained:=0
	var changed:=0
	for row in identity.overlap_report.values():
		removed+=int(row.removed_triangles)
		retained+=int(row.retained_triangles)
		changed+=int(row.bodies_changed)
	_check("appearance.coincident_wall_faces_removed",identity.overlap_report.size()==2 and removed>0 and retained>0 and changed==0,{"removed_triangles":removed,"retained_triangles":retained,"bodies_changed":changed,"reports":identity.overlap_report})
	var roof_surfaces:=0
	var missing_undersides:=[]
	for landmark in scene.landmark_visuals.bundle.landmarks:
		for component in landmark.components:
			if component.material not in ["tile","tile_edge"]:continue
			roof_surfaces+=1
			var visual: MeshInstance3D=scene.landmark_visuals.components[component.id]
			var material: Material=visual.material_override
			if not material is ShaderMaterial or not material.shader.code.contains("cull_disabled"):missing_undersides.append(component.id)
	_check("appearance.roof_undersides_rendered",roof_surfaces>0 and missing_undersides.is_empty(),{"roof_surfaces":roof_surfaces,"missing_double_sided_shader":missing_undersides})
	_check("names.source_mapping",scene.building_names.named_count==149 and scene.building_names.identify(CITY_HALL)=="서울특별시청" and scene.building_names.identify(LIBRARY)=="서울도서관" and scene.building_names.identify("W01_gate_side_0")=="대한문",{"named_count":scene.building_names.named_count,"city_hall":scene.building_names.identify(CITY_HALL),"library":scene.building_names.identify(LIBRARY),"gate":scene.building_names.identify("W01_gate_side_0")})

func _jump_case() -> void:
	if not await _pose("clear_road_jump",Vector3(82,0.08,10)):return
	var start: Vector3=scene.player.global_position
	var recovered: int=scene.player.recoveries
	var peak:=start.y
	var ascents:=0
	var previous_up:=false
	var outside:=0
	_keys(["jump"])
	for index in range(130):
		await _tick()
		peak=maxf(peak,scene.player.global_position.y)
		var going_up: bool=scene.player.velocity.y>0.01
		if going_up and not previous_up:ascents+=1
		previous_up=going_up
		if not scene.player._inside(scene.player.global_position):outside+=1
	_keys([])
	var row:={"name":"actual_city_held_jump","start":_v(start),"end":_v(scene.player.global_position),"apex_rise_m":peak-start.y,"ascending_episodes":ascents,"ending_grounded":scene.player.is_on_floor(),"outside_ticks":outside,"recoveries":scene.player.recoveries-recovered}
	trials.append(row)
	_check("jump.actual_city_3m",absf(peak-start.y-3.0)<0.12,row)
	_check("jump.actual_city_landing_and_no_hold_repeat",ascents==1 and scene.player.is_on_floor() and outside==0 and scene.player.recoveries==recovered,row)

func _orbit_case() -> void:
	var before: int=scene.player.recoveries
	var samples:=[]
	var overlap_count:=0
	var invalid_count:=0
	var below_floor:=0
	for index in range(12):
		scene.rig.yaw=TAU*float(index)/12.0
		scene.rig.pitch=deg_to_rad(-18.0)
		await _ticks(6)
		# Observe after the rig's physics solve rather than the player's earlier signal.
		await scene.rig.camera_stepped
		var camera: Camera3D=scene.rig.camera
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=scene.rig.arm.shape
		query.transform=Transform3D(Basis.IDENTITY,camera.global_position)
		query.collision_mask=scene.rig.arm.collision_mask
		query.exclude=[scene.player.get_rid()]
		var hits: Array=scene.get_world_3d().direct_space_state.intersect_shape(query,8)
		overlap_count+=hits.size()
		if not camera.global_transform.is_finite():invalid_count+=1
		if camera.global_position.y<0.15:below_floor+=1
		samples.append({"yaw":scene.rig.yaw,"camera":_v(camera.global_position),"distance":scene.rig.current_distance,"overlap_count":hits.size(),"far":camera.far})
	trials.append({"name":"actual_city_12_yaw_orbit","samples":samples})
	_check("camera.12_yaw_finite_and_clear",overlap_count==0 and invalid_count==0 and below_floor==0,{"overlaps":overlap_count,"invalid":invalid_count,"below_floor":below_floor,"samples":samples})
	_check("camera.orbit_player_stays_safe",scene.player.is_on_floor() and scene.player._inside(scene.player.global_position) and scene.player.recoveries==before,{"player":_v(scene.player.global_position),"recoveries_delta":scene.player.recoveries-before})
	_check("camera.single_owner_and_rendering",scene.rig.camera.top_level and scene.rig.rendered_frames>0 and scene.rig.snapshot().transform_owner=="exploration_camera",scene.rig.snapshot())

func _quality_cases() -> void:
	for id in ["low","standard"]:
		var ok: bool=scene.apply_quality(id)
		await _ticks(6)
		_check("quality."+id+".city_view_distance",ok and scene.quality_id==id and scene.rig.camera.far>=1400.0,{"quality":scene.quality_id,"far":scene.rig.camera.far,"near":scene.rig.camera.near})

func _name_ray_case() -> void:
	# Elevated test eye over the plaza sees the modern City Hall above the library.
	# Keep the live player safely on the road; the test camera is explicitly placed.
	scene.rig.set_physics_process(false)
	scene.rig.set_process(false)
	var camera: Camera3D=scene.rig.camera
	camera.global_position=Vector3(155,18,-65)
	camera.look_at(Vector3(205,32,-175),Vector3.UP)
	placements.append({"name":"name_ray_city_hall","kind":"explicit_test_only_camera","position":_v(camera.global_position),"target":[205,32,-175]})
	await _ticks(18)
	var query:=PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*220.0,1,[scene.player.get_rid()])
	var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(query)
	var id: String="" if hit.is_empty() else String(hit.collider.get_meta("geometry_id",""))
	_check("names.actual_camera_ray_city_hall",id==CITY_HALL and scene.building_names.current_id==CITY_HALL and scene.building_names.current_name=="서울특별시청",{"ray_id":id,"ray_name":scene.building_names.identify(id),"current_id":scene.building_names.current_id,"current_name":scene.building_names.current_name})
	scene.rig.set_physics_process(true)
	scene.rig.set_process(true)
	scene.rig.reset_orientation()
	await _ticks(6)

func _traffic_checks(initial: Dictionary) -> void:
	# The jumping player is on the west side of the carriageway, away from both
	# six-car source polylines. Allow the real stream to continue, with no car edits.
	await _ticks(180)
	var moving:=_vehicle_states()
	var ids:=moving.keys()
	_check("traffic.six_distinct_routes",scene.exploration_traffic.vehicle_count==6 and scene.vehicles.size()==6 and ids.size()==6,{"route_ids":ids,"extra_vehicles":scene.exploration_traffic.extra_vehicles.size()})
	for id in ids:
		var distance: float=float(moving[id].actual_distance_m)-float(initial.get(id,{}).get("actual_distance_m",0.0))
		_check("traffic.actual_motion."+id,initial.has(id) and distance>0.1 and moving[id].on_floor and moving[id].max_route_offset_m<=0.0031,{"distance_delta_m":distance,"initial":initial.get(id,{}),"moving":moving[id]})
	scene.set_vehicles_running(false)
	var stopped:=_vehicle_states()
	await _ticks(18)
	var paused_states:=_vehicle_states()
	for id in ids:
		_check("traffic.pause."+id,paused_states[id].running==false and absf(float(paused_states[id].actual_distance_m)-float(stopped[id].actual_distance_m))<0.00001,{"before":stopped[id],"after":paused_states[id]})
	scene.set_vehicles_running(true)
	await _ticks(75)
	var resumed:=_vehicle_states()
	var resumed_motion:=0
	for id in ids:
		if float(resumed[id].actual_distance_m)-float(paused_states[id].actual_distance_m)>0.05:resumed_motion+=1
		_check("traffic.resume_enabled."+id,resumed[id].running,{"distance_delta_m":float(resumed[id].actual_distance_m)-float(paused_states[id].actual_distance_m),"state":resumed[id].state,"blocked_reason":resumed[id].blocked_reason})
	_check("traffic.resumed_stream_moves",resumed_motion>0,{"moving_after_resume":resumed_motion,"total":ids.size()})
	trials.append({"name":"six_car_motion_pause_resume","initial":initial,"moving":moving,"paused":paused_states,"resumed":resumed})

func _wall_view() -> Dictionary:
	var wall: MeshInstance3D=scene.city.fragments.W01_palace_wall.get_parent()
	var arrays: Array=wall.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var goal:=Vector2(52,-30)
	var best:=INF
	var point:=Vector3(52,0,-30)
	var outward:=Vector3.RIGHT
	for index in range(0,vertices.size(),3):
		if absf(normals[index].y)>0.1:continue
		for edge in range(3):
			var a: Vector3=wall.to_global(vertices[index+edge])
			var b: Vector3=wall.to_global(vertices[index+(edge+1)%3])
			var av:=Vector2(a.x,a.z)
			var bv:=Vector2(b.x,b.z)
			if av.distance_squared_to(bv)<0.01:continue
			var close:=Geometry2D.get_closest_point_to_segment(goal,av,bv)
			var distance:=goal.distance_squared_to(close)
			if distance>=best:continue
			best=distance
			point=Vector3(close.x,0,close.y)
			outward=wall.global_basis*normals[index]
			if outward.dot(Vector3(82,0,-30)-point)<0:outward*=-1
	return {"eye":point+outward*5.0+Vector3.UP*2.4,"target":point+Vector3.UP*0.95}

func _capture(title: String, eye: Vector3, target: Vector3) -> void:
	var camera: Camera3D=scene.rig.camera
	camera.global_position=eye
	camera.look_at(target,Vector3.UP)
	placements.append({"name":title,"kind":"explicit_test_only_camera","position":_v(eye),"target":_v(target)})
	if DisplayServer.get_name()=="headless":
		captures.append({"name":title,"captured":false,"reason":"headless_has_no_rendered_viewport"})
		return
	# Let the 10Hz name display observe this new test-camera pose before capture.
	await _ticks(18)
	for index in range(3):await process_frame
	await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image()
	var path:=report_path.get_basename()+"_"+title+".png"
	var ok: bool=picture.save_png(path)==OK
	captures.append({"name":title,"captured":ok,"path":path,"width":picture.get_width(),"height":picture.get_height(),"eye":_v(eye),"target":_v(target)})
	_check("capture."+title,ok and picture.get_width()>0 and picture.get_height()>0,captures[-1])

func _run() -> void:
	for path in [report_path+".settings.json",report_path+".quality.json"]:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_settings_path=report_path+".settings.json"
	scene.quality_settings_path=report_path+".quality.json"
	root.add_child(scene)
	_check("startup.latest_city_runtime",scene.runtime_ok,{"exploration_error":scene.exploration_error,"traffic_error":scene.traffic_error,"quality_error":scene.quality_error})
	if not scene.runtime_ok:_finish();return
	scene.automatic_probe=true
	scene.rig.automatic_probe=true
	_check("startup.jump_action_registered",InputMap.has_action("jump") and InputMap.action_get_events("jump").is_empty(),{"action_exists":InputMap.has_action("jump"),"physical_events_in_probe":InputMap.action_get_events("jump").size()})
	await _ticks(12)
	_appearance_checks()
	_physics_inventory()
	var initial:=_vehicle_states()
	await _jump_case()
	await _orbit_case()
	await _quality_cases()
	await _name_ray_case()
	await _traffic_checks(initial)
	_keys([])
	scene.rig.set_capture(false)
	scene.rig.set_physics_process(false)
	scene.rig.set_process(false)
	await _capture("gate_front",Vector3(65,4,16),Vector3(26,4,8))
	var wall:=_wall_view()
	await _capture("stone_wall_close",wall.eye,wall.target)
	await _capture("city_hall_library",Vector3(155,7,-65),Vector3(190,20,-170))
	await _capture("gate_roof_underside",Vector3(35,5.2,10),Vector3(28,6.8,8))
	_finish()

func _timeout() -> void:
	if finished:return
	_check("bounded_runtime",false,{"timeout_real_seconds":90,"physics_seconds":physics_seconds})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true
	_keys([])
	paused=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var failures:=0
	for check in checks:
		if not check.passed:failures+=1
	var result:={"schema_version":1,"task":"SEOUL_DETAIL","passed":failures==0,"failed_checks":failures,"checks":checks,"trials":trials,"captures":captures,"placements":placements,"physics_seconds":physics_seconds,"physics_ticks":physics_ticks,"engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"physics_hz":Engine.physics_ticks_per_second},"scope":"Latest actual city scene with isolated physical inputs/settings, one explicit road teleport, Input.action_press jump, twelve fixed-yaw physics observations, source/fragment collision inventory, actual naming ray, six live car distances and pause/resume, plus explicit test-camera viewport captures. No continuous full-route, natural human-input, survey-accuracy, long-run performance or packaging acceptance."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:
		push_error("Cannot write Seoul detail report: "+report_path)
		quit(1)
		return
	file.store_string(JSON.stringify(result)+"\n")
	file.close()
	print("SEOUL_DETAIL_TEST ","PASS" if failures==0 else "FAIL"," checks=",checks.size()," failed=",failures," physics_seconds=",physics_seconds)
	quit(0 if failures==0 else 1)
