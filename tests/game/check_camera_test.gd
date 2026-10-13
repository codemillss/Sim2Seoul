extends SceneTree
## Actual camera/physics/input observations. Independent Python owns acceptance.
var output_path := ""
var capture_prefix := ""
var suite := "full"
var variant := "normal"
var fps := 60
var scene
var frames := 0
var capture_names := []
const ACTIONS := ["move_left","move_right","move_forward","move_backward","move_fast"]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--result="):output_path=arg.trim_prefix("--result=")
		elif arg.begins_with("--capture-prefix="):capture_prefix=arg.trim_prefix("--capture-prefix=")
		elif arg.begins_with("--suite="):suite=arg.trim_prefix("--suite=")
		elif arg.begins_with("--case="):variant=arg.trim_prefix("--case=")
		elif arg.begins_with("--render-fps="):fps=arg.trim_prefix("--render-fps=").to_int()
	Engine.max_fps=fps
	process_frame.connect(func():frames+=1)
	_run.call_deferred()

func _v(p: Vector3) -> Array:return [p.x,p.y,p.z]

func _keys(actions: Array) -> void:
	for a in ACTIONS:Input.action_release(a)
	for a in actions:Input.action_press(a)

func _world_keys(direction: Vector3,fast := false) -> void:
	_keys([])
	var forward: Vector3 = -scene.rig.camera.global_basis.z
	forward.y=0
	forward=forward.normalized()
	var right: Vector3 = forward.cross(Vector3.UP)
	var x: float=direction.dot(right)
	var y: float=direction.dot(forward)
	if x>0:Input.action_press("move_right",x)
	elif x<0:Input.action_press("move_left",-x)
	if y>0:Input.action_press("move_forward",y)
	elif y<0:Input.action_press("move_backward",-y)
	if fast:Input.action_press("move_fast")

func _wait(seconds: float) -> void:
	var t:=0.0
	while t<seconds-0.000001:t+=await scene.rig.camera_stepped

func _mouse(dx: float,dy: float) -> void:
	var event:=InputEventMouseMotion.new()
	event.device=42
	event.relative=Vector2(dx,dy)
	event.screen_relative=Vector2(dx,dy)
	Input.parse_input_event(event)

func _button(button: int) -> void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new()
		event.device=42
		event.button_index=button
		event.pressed=down
		Input.parse_input_event(event)

func _escape() -> void:
	for down in [true,false]:
		var event:=InputEventKey.new()
		event.physical_keycode=KEY_ESCAPE
		event.pressed=down
		Input.parse_input_event(event)
		await process_frame
		await process_frame

func _pose(point: Vector3,yaw:=0.0,pitch:=-15.0) -> void:
	_keys([])
	scene.player.global_transform=Transform3D(Basis.IDENTITY,point)
	scene.player.velocity=Vector3.ZERO
	scene.player.input_latched=false
	scene.rig.yaw=yaw
	scene.rig.pitch=deg_to_rad(pitch)
	scene.rig.requested_distance=4.5
	scene.rig.current_distance=4.5
	await _wait(0.5)
	# Discard the first injected event after capture, then permit controlled mouse motion.
	scene.rig.skip_motion=false

func _near_corners() -> Array:
	var camera: Camera3D=scene.rig.camera
	var size:=root.get_visible_rect().size
	var half_y: float=camera.near*tan(deg_to_rad(camera.fov)/2.0)
	var half_x: float=half_y*size.x/size.y
	var centre:=camera.global_position-camera.global_basis.z*camera.near
	var points:=[]
	for x in [-1,1]:
		for y in [-1,1]:points.append(centre+camera.global_basis.x*half_x*x+camera.global_basis.y*half_y*y)
	return points

func _sample(time: float) -> Dictionary:
	var player=scene.player
	var rig=scene.rig
	var camera: Camera3D=rig.camera
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=rig.arm.shape
	query.transform=Transform3D(Basis.IDENTITY,camera.global_position)
	query.collision_mask=1
	var space: PhysicsDirectSpaceState3D=scene.get_world_3d().direct_space_state
	var names:=[]
	for hit in space.intersect_shape(query,16):names.append(String(hit.collider.name))
	var near_points:=[]
	var near_hits:=[]
	for point in _near_corners():
		near_points.append(_v(point))
		var ray:=PhysicsRayQueryParameters3D.create(camera.global_position,point,1)
		var hit: Dictionary=space.intersect_ray(ray)
		if not hit.is_empty():near_hits.append(String(hit.collider.name))
	var hp:=camera.unproject_position(player.global_position+Vector3.UP*1.7)
	var fp:=camera.unproject_position(player.global_position)
	return {"t":time,"player":_v(player.global_position),"velocity":_v(player.velocity),"floor":player.is_on_floor(),
		"visible_body":player.get_node("Visual").visible,"rig":rig.snapshot(),"near_corners":near_points,
		"camera_overlap":names,"near_ray_hits":near_hits,"player_head_pixel":[hp.x,hp.y],"player_feet_pixel":[fp.x,fp.y]}

func _segment(title: String,seconds: float,direction:=Vector3.ZERO,fast:=false,orbit:=0.0) -> Dictionary:
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
		"samples":samples,"all_tick_stats":{"ticks":ticks,"max_camera_overlap_count":max_overlap,"max_near_hit_count":max_near_hits,
			"max_follow_error_m":max_follow,"max_length_excess_m":max_length_excess,"max_tick_mismatch":mismatch,
			"floor_ticks":floor_ticks,"min_distance":min_distance,"max_distance":max_distance,"min_player_y":min_y,"max_player_y":max_y,"camera_max_step_m":camera_max_step}}

func _capture(title: String) -> void:
	if capture_prefix.is_empty() or DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image()
	if picture.save_png(capture_prefix+"_"+title+".png")!=OK:push_error("P03 capture failed")
	capture_names.append({"name":title,"width":picture.get_width(),"height":picture.get_height()})

func _run() -> void:
	scene=load("res://scenes/tests/camera_test.tscn").instantiate()
	root.add_child(scene)
	match variant:
		"mask_disabled":scene.rig.arm.collision_mask=0
		"self_exclusion_removed":scene.rig.arm.collision_mask=3;scene.rig.arm.clear_excluded_objects()
		"wrong_player_camera":scene.player.movement_camera=scene.get_node("Presentation/Camera")
		"unclamped_pitch":scene.rig.pitch_min_degrees=-150;scene.rig.pitch_max_degrees=150
		"menu_capture_leak":pass
		"normal":pass
		_:push_error("Unknown P03 variant");quit(1);return
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
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if output_path.is_empty():push_error("P03 result path required");quit(1);return
	var file:=FileAccess.open(output_path,FileAccess.WRITE)
	if file==null:push_error("P03 result write failed");quit(1);return
	file.store_string(JSON.stringify(record)+"\n")
	print("P03_PROBE_DONE suite=%s case=%s cases=%d"%[suite,variant,cases.size()])
	scene.queue_free()
	quit(0)
