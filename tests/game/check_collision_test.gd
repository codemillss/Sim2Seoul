extends "res://test_support/check_camera_test.gd"
var fault:= "normal"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fault="):fault=arg.trim_prefix("--fault=")
	super._initialize()

func _run() -> void:
	scene=load("res://scenes/tests/collision_test.tscn").instantiate()
	root.add_child(scene)
	match variant:
		"mask_disabled":scene.rig.arm.collision_mask=0
		"self_exclusion_removed":scene.rig.arm.collision_mask=3;scene.rig.arm.clear_excluded_objects()
		"wrong_player_camera":scene.player.movement_camera=scene.get_node("Presentation/Camera")
		"unclamped_pitch":scene.rig.pitch_min_degrees=-150;scene.rig.pitch_max_degrees=150
		"menu_capture_leak":pass
		"normal":pass
		_:push_error("Unknown P03 variant");quit(1);return
	if not scene.runtime_state.ok:
		push_error(scene.runtime_state.error);quit(1);return
	_apply_fixture_fault()
	await _wait(1)
	var rig=scene.rig
	var player=scene.player
	var contract: Dictionary=scene.movement_contract()
	contract.merge({"pivot_height":rig.pivot_height_m,"sensitivity":rig.sensitivity_radians_per_pixel,
		"pitch_min":deg_to_rad(rig.pitch_min_degrees),"pitch_max":deg_to_rad(rig.pitch_max_degrees),
		"min_distance":rig.distance_min_m,"max_distance":rig.distance_max_m,"default_distance":rig.default_distance_m,
		"expansion_mps":rig.expansion_mps,"mask":rig.arm.collision_mask,"probe_radius":rig.arm.shape.radius,
		"margin":rig.arm.margin,"near":rig.camera.near,"fov":rig.camera.fov,"player_priority":player.process_physics_priority,
		"arm_priority":rig.arm.process_physics_priority,"rig_priority":rig.process_physics_priority,
		"player_camera_path_matches":player.movement_camera==rig.camera},true)
	contract["camera_fixed"]=false
	var fixtures:=[]
	for body in scene.get_node("Fixtures").get_children():
		var shape=body.get_node("CollisionShape").shape
		if shape is BoxShape3D:fixtures.append({"name":String(body.name),"lo":_v(body.global_position-shape.size/2),"hi":_v(body.global_position+shape.size/2)})
	var cases:=[]
	await _pose(Vector3(0,0.08,22))
	cases.append(await _segment("open_idle",60 if suite=="full" else 2))
	await _capture("open")
	for fast in [false,true]:
		await _pose(Vector3(-18,0.08,22))
		cases.append(await _segment("follow_run" if fast else "follow_walk",10,Vector3.RIGHT,fast))
	await _pose(Vector3(-7,0.08,-2),PI)
	cases.append(await _segment("wall_still",3))
	await _capture("wall")
	await _pose(Vector3(-7,0.08,-2),PI)
	cases.append(await _segment("wall_orbit",3,Vector3.ZERO,false,220))
	await _pose(Vector3(-8,0.08,-3.3),PI)
	cases.append(await _segment("corner_orbit",3,Vector3.ZERO,false,220))
	await _capture("corner")
	await _pose(Vector3(0,0.08,-3.3),PI,-55)
	cases.append(await _segment("lintel_orbit",3,Vector3.ZERO,false,35))
	await _capture("lintel")
	await _pose(Vector3(0,0.08,22))
	rig.current_distance=0.3
	rig.camera.position.z=0.3
	cases.append(await _segment("clear_expansion",2))
	await _pose(Vector3(1,0.08,2))
	cases.append(await _segment("step_camera",3.7,Vector3.RIGHT))
	await _pose(Vector3(-10,0.08,-1))
	cases.append(await _segment("slope_camera",4.5,Vector3.RIGHT))
	await _pose(Vector3(0,0.08,-2),PI)
	for index in range(10):
		cases.append(await _segment("door_forward_%d"%index,172.0/60.0,Vector3.FORWARD,false,28))
		cases.append(await _segment("door_reverse_%d"%index,172.0/60.0,Vector3.BACK,false,-28))
	await _capture("door")
	await _pose(Vector3(0,0.08,22))
	rig.set_capture(true)
	var yaw_start: float=rig.yaw
	var pitch_start: float=rig.pitch
	_mouse(300,300)
	await _wait(0.1)
	var yaw_discard: float=rig.yaw
	var pitch_discard: float=rig.pitch
	_mouse(120,40)
	await _wait(0.1)
	cases.append({"name":"mouse_orbit","start_yaw":yaw_start,"start_pitch":pitch_start,"end_yaw":rig.yaw,"end_pitch":rig.pitch,
		"dx":120,"dy":40,"discarded_first":true,"yaw_after_discard":yaw_discard,"pitch_after_discard":pitch_discard})
	_mouse(0,100000)
	await _wait(0.1)
	var low: float=rig.pitch
	_mouse(0,-100000)
	await _wait(0.1)
	var high: float=rig.pitch
	for index in range(30):_button(MOUSE_BUTTON_WHEEL_UP)
	await _wait(0.1)
	var zoom_near: float=rig.requested_distance
	for index in range(30):_button(MOUSE_BUTTON_WHEEL_DOWN)
	await _wait(0.1)
	cases.append({"name":"clamps","pitch_low":low,"pitch_high":high,"zoom_near":zoom_near,"zoom_far":rig.requested_distance})
	await _pose(Vector3(0,0.08,22))
	rig.arm.collision_mask=3 if variant!="mask_disabled" else 0
	await _wait(0.2)
	var exclusion_registered: bool=rig.arm.remove_excluded_object(player.get_rid())
	if exclusion_registered:rig.arm.add_excluded_object(player.get_rid())
	cases.append({"name":"self_exclusion","excluded_registered":exclusion_registered,"mask_used":rig.arm.collision_mask,"length_with_exclusion":rig.arm.get_hit_length(),"requested_distance":rig.requested_distance})
	rig.arm.collision_mask=1 if variant not in ["mask_disabled","self_exclusion_removed"] else rig.arm.collision_mask
	_keys(["move_forward","move_fast"])
	await _escape()
	if variant=="menu_capture_leak":rig.set_capture(true)
	var before: Vector3=player.global_position
	var before_yaw: float=rig.yaw
	var before_pitch: float=rig.pitch
	var actor_ticks:=[0]
	var rig_ticks:=[0]
	var actor_counter:=func(_dt: float):actor_ticks[0]+=1
	var rig_counter:=func(_dt: float):rig_ticks[0]+=1
	player.physics_stepped.connect(actor_counter)
	rig.camera_stepped.connect(rig_counter)
	var mouse_open: int=Input.mouse_mode
	var capture_open: bool=rig.input_enabled
	_mouse(200,80)
	await create_timer(0.25).timeout
	await _capture("menu")
	var pause_record:={"name":"menu_input","paused":paused,"actor_ticks":actor_ticks[0],"rig_ticks":rig_ticks[0],"mouse_open":mouse_open,
		"capture_open":capture_open,"paused_drift":player.global_position.distance_to(before),"paused_yaw_drift":abs(rig.yaw-before_yaw),"paused_pitch_drift":abs(rig.pitch-before_pitch)}
	player.physics_stepped.disconnect(actor_counter)
	rig.camera_stepped.disconnect(rig_counter)
	await _escape()
	pause_record["mouse_closed"]=Input.mouse_mode
	pause_record["capture_closed"]=rig.input_enabled
	var yaw_before: float=rig.yaw
	_mouse(300,100)
	await _wait(0.1)
	pause_record["recapture_first_ignored"]=is_equal_approx(rig.yaw,yaw_before)
	await _wait(0.5)
	pause_record["held_drift"]=player.global_position.distance_to(before)
	_keys([])
	await _wait(0.1)
	var release_pos: Vector3=player.global_position
	_keys(["move_forward"])
	await _wait(0.5)
	pause_record["release_move_m"]=Vector2(player.global_position.x-release_pos.x,player.global_position.z-release_pos.z).length()
	_keys([])
	cases.append(pause_record)
	scene.automatic_probe=false
	scene.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	scene.automatic_probe=true
	var focus_record:={"name":"focus_loss","paused":paused,"mouse_mode":Input.mouse_mode}
	scene.focus_changed(true)
	focus_record["stays_paused_on_focus_return"]=paused
	cases.append(focus_record)
	scene.toggle_menu()
	player.global_position=Vector3(-2,-10,2)
	await rig.camera_stepped
	cases.append({"name":"fall_camera_return","reason":player.last_recovery_reason,"position":_v(player.global_position),
		"yaw":rig.yaw,"pitch":rig.pitch,"distance_requested":rig.requested_distance,"latched":player.input_latched})
	await _wait(0.2)
	var max_corner:=0.0
	for point in _near_corners():max_corner=max(max_corner,point.distance_to(rig.camera.global_position))
	cases.append({"name":"eye_clearance","max_near_corner_radius":max_corner})
	var record:={"schema_version":1,"task":"P03","suite":suite,"case":variant,"engine":{"version":Engine.get_version_info().string,
		"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),
		"physics_hz":Engine.physics_ticks_per_second,"render_cap_fps":fps},"contract":contract,"fixtures":fixtures,"cases":cases,"captures":capture_names,
		"scope":"synthetic camera fixture, automatic injected events; no human handling, city/Daehanmun or M4 validation"}
	var fixture_extra:=await _fixture_extra()
	var matrix:=await _matrix()
	var city_result:=await _city()
	record={"schema_version":1,"task":"P04","fault":fault,"engine":record.engine,"camera_fixture":record,"fixture_extra":fixture_extra,"matrix":matrix,"city":city_result,"rules":scene.city.rules,"source_world_sha256":scene.city.plan.world_sha256,"source_collision_sha256":FileAccess.get_sha256("res://resources/collision/generated.json"),"captures":capture_names,"scope":"Synthetic movement/camera and static city collision inspection/probes only; no permission, terrain, route/Daehanmun or M4 acceptance"}
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if output_path.is_empty():push_error("P03 result path required");quit(1);return
	var file:=FileAccess.open(output_path,FileAccess.WRITE)
	if file==null:push_error("P03 result write failed");quit(1);return
	file.store_string(JSON.stringify(record)+"\n")
	print("P04_PROBE_DONE suite=%s case=%s cases=%d"%[suite,variant,cases.size()])
	scene.queue_free()
	quit(0)

func _apply_fixture_fault() -> void:
	if fault=="player_mask_zero":scene.player.collision_mask=0
	elif fault=="fixture_wall_disabled":scene.get_node("Fixtures/Wall/CollisionShape").disabled=true
	elif fault=="camera_all_layers":scene.rig.arm.collision_mask=15

func _fixture_extra() -> Array:
	var extra:=[]
	for config in [["wall_walk",Vector3(-7,0.08,-2.0),Vector3.FORWARD,false],["wall_run",Vector3(-7,0.08,-2.0),Vector3.FORWARD,true],["wall_oblique_walk",Vector3(-6.5,0.08,-2.0),Vector3(-.3,0,-1).normalized(),false],["wall_oblique_run",Vector3(-6.5,0.08,-2.0),Vector3(-.3,0,-1).normalized(),true],["wall_corner_walk",Vector3(-8,0.08,-2),Vector3(-.4,0,-1).normalized(),false],["wall_corner_run",Vector3(-8,0.08,-2),Vector3(-.4,0,-1).normalized(),true],["building_walk",Vector3(8,0.08,3.5),Vector3.BACK,false],["building_run",Vector3(8,0.08,3.5),Vector3.BACK,true]]:
		await _pose(config[1])
		extra.append(await _segment(config[0],2,config[2],config[3]))
	await _capture("fixture_building")
	return extra

func _proxy(title: String,role: String,position: Vector3) -> CharacterBody3D:
	var body:=CharacterBody3D.new()
	body.name=title
	body.collision_layer=int(scene.city.rules.body_roles[role].layer)
	body.collision_mask=int(scene.city.rules.body_roles[role].mask)
	body.position=position
	scene.add_child(body)
	var cs:=CollisionShape3D.new()
	cs.name="CollisionShape"
	var sphere:=SphereShape3D.new()
	sphere.radius=.3
	cs.shape=sphere
	body.add_child(cs)
	return body

func _matrix() -> Dictionary:
	var rows:=[]
	var camera_rows:=[]
	for target_role in ["static_world","player","pedestrian","vehicle"]:
		var target:=_proxy("MatrixTarget",target_role,Vector3(-18,8,40))
		await physics_frame
		await process_frame
		for moving_role in ["player","pedestrian","vehicle"]:
			var mover:=_proxy("MatrixMover",moving_role,Vector3(-20,8,40))
			await physics_frame
			await process_frame
			var collision:=KinematicCollision3D.new()
			var motion:=Vector3(4,0,0)
			var hit:=mover.test_move(mover.global_transform,motion,collision)
			rows.append({"moving_role":moving_role,"target_role":target_role,"moving_layer":mover.collision_layer,"moving_mask":mover.collision_mask,"target_layer":target.collision_layer,"target_mask":target.collision_mask,"motion":_v(motion),"hit":hit,"collider":String(collision.get_collider().name) if hit else ""})
			mover.free()
		var query:=PhysicsRayQueryParameters3D.create(Vector3(-20,8,40),Vector3(-16,8,40),scene.rig.arm.collision_mask)
		var h: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(query)
		camera_rows.append({"target_role":target_role,"mask":scene.rig.arm.collision_mask,"hit":not h.is_empty(),"collider":String(h.collider.name) if not h.is_empty() else ""})
		target.free()
	return {"pairs":rows,"camera":camera_rows,"player_layer":scene.player.collision_layer,"player_mask":scene.player.collision_mask,"fixture_masks":scene.get_node("Fixtures").get_children().map(func(b):return {"name":String(b.name),"layer":b.collision_layer,"mask":b.collision_mask}),"scope":"Role-tagged kinematic sphere proxies; NPC/vehicle route/controllers are not implemented"}

func _identity(t: Transform3D) -> Array:
	return [_v(t.origin),_v(t.basis.x),_v(t.basis.y),_v(t.basis.z)]

func _packed_hash(values: PackedVector3Array) -> String:
	var hashing:=HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(values.to_byte_array())
	return hashing.finish().hex_encode()

func _city_ray(spec: Dictionary) -> Dictionary:
	var target: StaticBody3D=scene.city.bodies[spec.mesh_id]
	var excluded: Array[RID]=[]
	for body in scene.city.bodies.values():
		if body!=target:excluded.append(body.get_rid())
	excluded.append(scene.player.get_rid())
	var a:=Vector3(spec.from[0],spec.from[1],spec.from[2])
	var b:=Vector3(spec.to[0],spec.to[1],spec.to[2])
	var query:=PhysicsRayQueryParameters3D.create(a,b,1,excluded)
	query.hit_back_faces=true
	var result: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(query)
	return {"spec":spec,"hit":not result.is_empty(),"collider_id":result.collider.get_meta("geometry_id","") if not result.is_empty() else "","position":_v(result.position) if not result.is_empty() else [],"normal":_v(result.normal) if not result.is_empty() else [],"scope":"Actual selected city collider ray; other colliders excluded to isolate source surface/holes"}

func _apply_city_fault() -> void:
	var city=scene.city
	var id: String=city.plan.capsule_moves[0].mesh_id
	var body: StaticBody3D=city.bodies[id]
	match fault:
		"city_layer_wrong":body.collision_layer=4
		"city_shape_disabled":body.get_node("CollisionShape").disabled=true
		"city_shape_missing":body.get_node("CollisionShape").free()
		"city_transform_shift":body.position.x=1
		"city_faces_shift":
			var cs: CollisionShape3D=body.get_node("CollisionShape")
			var faces: PackedVector3Array=cs.shape.get_faces()
			faces[0].x+=1
			cs.shape.set_faces(faces)
		"display_collision_added":
			var skipped: String=city.plan.excluded[0].mesh_id
			var extra:=StaticBody3D.new()
			extra.name="UnexpectedCollision"
			extra.collision_layer=1
			city.source_nodes[skipped].add_child(extra)
			var cs:=CollisionShape3D.new()
			cs.shape=BoxShape3D.new()
			extra.add_child(cs)
		"hole_blocked":
			var spec: Dictionary=city.plan.hole_probes[0]
			var parent: StaticBody3D=city.bodies[spec.mesh_id]
			var cs:=CollisionShape3D.new()
			cs.name="HolePatch"
			var box:=BoxShape3D.new()
			box.size=Vector3(1,.1,1)
			cs.shape=box
			cs.position=Vector3(spec.from[0],spec.from[1]-.5,spec.from[2])
			parent.add_child(cs)

func _city() -> Dictionary:
	_keys([])
	scene.set_mode("city")
	_apply_city_fault()
	await physics_frame
	await process_frame
	var city=scene.city
	var inventory:=[]
	for m in scene.runtime_state.world.meshes:
		var node: MeshInstance3D=city.source_nodes[m.id]
		var item:={"mesh_id":m.id,"role":m.role,"source_permission":node.get_meta("source").runtime_permission,"mesh_transform":_identity(node.global_transform),"body_count":node.get_child_count(),"bodies":[]}
		for body in node.get_children():
			var shapes:=[]
			for cs in body.get_children():
				if cs is CollisionShape3D:
					var face_count:=0
					var digest:=""
					var backface:=false
					if cs.shape is ConcavePolygonShape3D:
						face_count=cs.shape.get_faces().size()
						digest=_packed_hash(cs.shape.get_faces())
						backface=cs.shape.backface_collision
					shapes.append({"type":cs.shape.get_class(),"disabled":cs.disabled,"transform":_identity(cs.global_transform),"face_count":face_count,"faces_float32_sha256":digest,"backface_collision":backface})
			item.bodies.append({"type":body.get_class(),"layer":body.collision_layer,"mask":body.collision_mask,"transform":_identity(body.global_transform),"has_scope":body.has_meta("collision_scope"),"permission":body.get_meta("collision_scope",{}).get("runtime_permission",null),"shapes":shapes})
		inventory.append(item)
	var surface_results:=[]
	for spec in city.plan.surface_probes:surface_results.append(_city_ray(spec))
	var hole_results:=[]
	for spec in city.plan.hole_probes:hole_results.append(_city_ray(spec))
	var capsule_results:=[]
	for spec in city.plan.capsule_moves:
		var mover:=CharacterBody3D.new()
		mover.collision_layer=2
		mover.collision_mask=13
		mover.position=Vector3(spec.start[0],spec.start[1],spec.start[2])
		scene.add_child(mover)
		var cs:=CollisionShape3D.new()
		var capsule:=CapsuleShape3D.new()
		capsule.height=1.7
		capsule.radius=.3
		cs.shape=capsule
		cs.position.y=.85
		mover.add_child(cs)
		for other in city.bodies:
			if other!=spec.mesh_id:mover.add_collision_exception_with(city.bodies[other])
		mover.add_collision_exception_with(scene.player)
		await physics_frame
		await process_frame
		var start: Vector3=mover.global_position
		var motion:=Vector3(spec.motion[0],spec.motion[1],spec.motion[2])
		var collision: KinematicCollision3D=mover.move_and_collide(motion)
		capsule_results.append({"spec":spec,"start":_v(start),"end":_v(mover.global_position),"hit":collision!=null,"collider_id":collision.get_collider().get_meta("geometry_id","") if collision!=null else "","travel":_v(collision.get_travel()) if collision!=null else _v(motion),"remainder":_v(collision.get_remainder()) if collision!=null else [0,0,0],"height":capsule.height,"radius":capsule.radius,"mask":mover.collision_mask,"scope":"Actual external-to-internal kinematic capsule movement against selected city shell; other colliders excluded"})
		mover.free()
	await _capture("city_overview")
	scene.set_mode("city_palace")
	await _capture("city_palace")
	return {"runtime_ok":city.collision_ok,"counts":city.plan.counts,"inventory":inventory,"surface_probes":surface_results,"hole_probes":hole_results,"capsule_moves":capsule_results,"gates_pending":city.plan.gates_pending,"scope":city.plan.scope,"active_mode":scene.mode,"fixture_inactive":scene.get_node("Fixtures").get_children().all(func(b):return b.collision_layer==0 and b.collision_mask==0),"player_physics_inactive":not scene.player.is_physics_processing(),"camera_input_disabled":not scene.rig.input_enabled}

func _player_penetration() -> float:
	var point: Vector3=scene.player.global_position
	var worst:=0.0
	for body in scene.get_node("Fixtures").get_children():
		var shape=body.get_node("CollisionShape").shape
		if not shape is BoxShape3D:continue
		var lo: Vector3=body.global_position-shape.size/2
		var hi: Vector3=body.global_position+shape.size/2
		var dx: float=maxf(maxf(lo.x-point.x,point.x-hi.x),0)
		var dz: float=maxf(maxf(lo.z-point.z,point.z-hi.z),0)
		var dy: float=maxf(maxf(lo.y-(point.y+1.4),point.y+.3-hi.y),0)
		worst=maxf(worst,.3-sqrt(dx*dx+dy*dy+dz*dz))
	return worst

func _sample(time: float) -> Dictionary:
	var result: Dictionary=super._sample(time)
	result["player_box_penetration_m"]=_player_penetration()
	return result

func _segment(title: String,seconds: float,direction:=Vector3.ZERO,fast:=false,orbit:=0.0) -> Dictionary:
	var stats:={"ticks":0,"max_box_penetration_m":0.0,"solid_contact_ticks":0}
	var counter:=func(_delta: float):
		stats.ticks+=1
		stats.max_box_penetration_m=maxf(stats.max_box_penetration_m,_player_penetration())
		var contact:=false
		for i in range(scene.player.get_slide_collision_count()):
			if scene.player.get_slide_collision(i).get_normal().dot(Vector3.UP)<.7:contact=true
		if contact:stats.solid_contact_ticks+=1
	scene.rig.camera_stepped.connect(counter)
	var result: Dictionary=await super._segment(title,seconds,direction,fast,orbit)
	scene.rig.camera_stepped.disconnect(counter)
	result["player_all_tick_stats"]=stats
	return result
