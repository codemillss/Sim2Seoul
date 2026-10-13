extends SceneTree
## Actual scene measurements, never acceptance. Independent Python scores evidence.
var output_path := ""
var capture_prefix := ""
var suite := "full"
var variant := "normal"
var render_cap := 60
var scene
var frames := 0
var total_ticks := 0
const ACTIONS := ["move_left","move_right","move_forward","move_backward","move_fast"]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--result="):output_path = arg.trim_prefix("--result=")
		elif arg.begins_with("--capture-prefix="):capture_prefix = arg.trim_prefix("--capture-prefix=")
		elif arg.begins_with("--suite="):suite = arg.trim_prefix("--suite=")
		elif arg.begins_with("--case="):variant = arg.trim_prefix("--case=")
		elif arg.begins_with("--render-fps="):render_cap = arg.trim_prefix("--render-fps=").to_int()
	Engine.max_fps = render_cap
	process_frame.connect(func():frames+=1)
	_run.call_deferred()

func _v(point: Vector3) -> Array:
	return [point.x,point.y,point.z]

func _keys(actions: Array) -> void:
	for action in ACTIONS:Input.action_release(action)
	for action in actions:Input.action_press(action)

func _wait(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed<seconds-0.000001:elapsed += await scene.player.physics_stepped

func _place(point: Vector3, settle := true) -> void:
	_keys([])
	scene.player.global_transform = Transform3D(Basis.IDENTITY,point)
	scene.player.get_node("Visual").rotation = Vector3.ZERO
	scene.player.velocity = Vector3.ZERO
	scene.player.input_latched = false
	if settle:await _wait(0.8)

func _penetration() -> float:
	# Capsule-vs-box distance from vertical centre segment to AABB; no engine success flag.
	var point: Vector3 = scene.player.global_position
	var radius: float = scene.player.get_node("CollisionShape").shape.radius
	var height: float = scene.player.get_node("CollisionShape").shape.height
	var worst := 0.0
	for body in scene.get_node("Fixtures").get_children():
		var shape = body.get_node("CollisionShape").shape
		if not shape is BoxShape3D:continue
		var lo: Vector3 = body.global_position-shape.size/2
		var hi: Vector3 = body.global_position+shape.size/2
		var dx: float = max(max(lo.x-point.x,point.x-hi.x),0.0)
		var dz: float = max(max(lo.z-point.z,point.z-hi.z),0.0)
		var dy: float = max(max(lo.y-(point.y+height-radius),point.y+radius-hi.y),0.0)
		worst = max(worst,radius-sqrt(dx*dx+dy*dy+dz*dz))
	return worst

func _segment(title: String, actions: Array, seconds: float) -> Dictionary:
	var player = scene.player
	_keys(actions)
	var start: Vector3 = player.global_position
	var previous := start
	var start_wall := Time.get_ticks_usec()
	var frame_start := frames
	var count_start: int = player.recoveries
	var yaw_start: float = player.get_node("Visual").rotation.y
	var ticks := 0
	var elapsed := 0.0
	var path := 0.0
	var floor_ticks := 0
	var min_y := INF
	var max_y := -INF
	var max_vy := 0.0
	var max_drift := 0.0
	var penetration := 0.0
	var solid_contacts := 0
	var samples := []
	while elapsed<seconds-0.000001:
		elapsed += await player.physics_stepped
		ticks += 1
		total_ticks += 1
		var point: Vector3 = player.global_position
		path += Vector2(point.x-previous.x,point.z-previous.z).length()
		previous = point
		min_y = min(min_y,point.y)
		max_y = max(max_y,point.y)
		max_vy = max(max_vy,abs(player.velocity.y))
		max_drift = max(max_drift,Vector2(point.x-start.x,point.z-start.z).length())
		penetration = max(penetration,_penetration())
		if player.is_on_floor():floor_ticks+=1
		var hit_solid := false
		for index in range(player.get_slide_collision_count()):
			if player.get_slide_collision(index).get_normal().dot(Vector3.UP)<0.7:hit_solid = true
		if hit_solid:solid_contacts += 1
		if ticks==1 or ticks%6==0:
			samples.append({"t":elapsed,"p":_v(point),"floor":player.is_on_floor(),"vy":player.velocity.y,"yaw":player.get_node("Visual").rotation.y})
	var end: Vector3 = player.global_position
	var result := {"name":title,"start":_v(start),"end":_v(end),"duration_s":elapsed,
		"wall_s":(Time.get_ticks_usec()-start_wall)/1000000.0,"ticks":ticks,"frames":frames-frame_start,
		"horizontal_distance_m":Vector2(end.x-start.x,end.z-start.z).length(),"path_m":path,"floor_ticks":floor_ticks,
		"min_y":min_y,"max_y":max_y,"max_abs_vy_mps":max_vy,"max_xz_drift_m":max_drift,
		"recoveries":player.recoveries-count_start,"input":actions,"max_penetration_m":penetration,
		"solid_contact_ticks":solid_contacts,"visual_yaw_start":yaw_start,"visual_yaw_end":player.get_node("Visual").rotation.y,
		"root_yaw":player.rotation.y,"final_velocity":_v(player.velocity),"path_samples":samples}
	_keys([])
	return result

func _recovery(title: String, point: Vector3, expected_reason: String) -> Dictionary:
	await _place(Vector3(1,0.08,5))
	var player = scene.player
	player.get_node("Visual").rotation.y = 1.2
	player.velocity = Vector3(2,-3,1)
	var before: int = player.recoveries
	_keys(["move_forward","move_fast"])
	player.global_position = point
	if expected_reason=="manual_restart":scene.reset_button.pressed.emit()
	else:await player.physics_stepped
	var result := {"name":title,"reason":player.last_recovery_reason,"expected_reason":expected_reason,
		"position_before":_v(point),"position_after":_v(player.global_position),"visual_yaw_after":player.get_node("Visual").rotation.y,
		"velocity_after":_v(player.velocity),"spawn_valid":player.spawn_valid,"latched_after":player.input_latched,
		"recovery_count_delta":player.recoveries-before}
	var held := await _segment("held_after_return",["move_forward","move_fast"],1.0)
	result["held_drift_m"] = held.horizontal_distance_m
	result["floor_regained"] = player.is_on_floor()
	_keys([])
	await _wait(0.1)
	var released := await _segment("released_after_return",["move_forward"],0.5)
	result["release_then_move_m"] = released.horizontal_distance_m
	return result

func _physical_key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _run() -> void:
	scene = load("res://scenes/tests/movement_test.tscn").instantiate()
	root.add_child(scene)
	match variant:
		"speed_wrong":scene.player.walk_speed_mps = 2.0
		"gravity_zero":scene.player.gravity_mps2 = 0
		"turn_zero":scene.player.turn_speed_radians = 0
		"mask_disabled":scene.player.collision_mask = 0
		"door_blocked":scene.get_node("Fixtures/DoorLintel").position.y = 1.3
		"spawn_unsupported":scene.player.spawn_transform.origin = Vector3(-2,2,2)
		"normal":pass
		_:push_error("Unknown P02 mutation");quit(1);return
	await _wait(1.0)
	var contract: Dictionary = scene.movement_contract()
	var cases := []
	scene.set_view("distance")
	if suite in ["full","idle"]:
		await _place(Vector3(-2,0.08,2))
		cases.append(await _segment("idle",[],60.0))
	if suite in ["full","timing"]:
		for item in [["walk",["move_right"]],["run",["move_right","move_fast"]]]:
			await _place(Vector3(-18,0.08,22))
			cases.append(await _segment(item[0],item[1],10.0))
	if suite=="full":
		for item in [["diagonal_walk",["move_right","move_backward"]],["diagonal_run",["move_right","move_backward","move_fast"]]]:
			await _place(Vector3(-18,0.08,22))
			cases.append(await _segment(item[0],item[1],10.0))
		for item in [["turn_left","move_left",PI/2],["turn_right","move_right",-PI/2]]:
			await _place(Vector3(0,0.08,22))
			var result := await _segment(item[0],[item[1]],1.0)
			result["expected_yaw"] = item[2]
			result["end_direction"] = _v(scene.player.last_direction)
			cases.append(result)
		await _place(Vector3(0,0.08,22))
		scene.camera.position = Vector3(10,10,30)
		scene.camera.look_at(Vector3(0,0,30),Vector3.UP)
		var relative := await _segment("camera_relative",["move_forward"],1.0)
		relative["expected_direction"] = [-1,0,0]
		cases.append(relative)
		scene.set_view("distance")
		await _place(Vector3(-2,2,2),false)
		cases.append(await _segment("gravity_drop",[],1.0))
		for mode in ["walk","run"]:
			for angle in ["front","oblique","corner"]:
				await _place(Vector3(-5,0.08,-3.3) if angle=="corner" else Vector3(-7,0.08,-2.4))
				var actions: Array = ["move_forward"]
				if angle=="oblique":actions.append("move_right")
				if angle=="corner":actions.append("move_left")
				if mode=="run":actions.append("move_fast")
				cases.append(await _segment("wall_%s_%s"%[angle,mode],actions,3.0))
		await _place(Vector3(1,0.08,2))
		cases.append(await _segment("step_up",["move_right"],3.7))
		cases.append(await _segment("step_down",["move_left"],3.7))
		await _place(Vector3(-10,0.08,-1))
		cases.append(await _segment("slope_up",["move_right"],4.5))
		cases.append(await _segment("slope_down",["move_left"],4.5))
		var passages := []
		await _place(Vector3(0,0.08,-2))
		for index in range(10):
			var forward := await _segment("door_forward_%d"%index,["move_forward"],172.0/60.0)
			forward["direction"] = "forward"
			passages.append(forward)
			var reverse := await _segment("door_reverse_%d"%index,["move_backward"],172.0/60.0)
			reverse["direction"] = "reverse"
			passages.append(reverse)
		var forward_count := 0
		var reverse_count := 0
		for passage in passages:
			if passage.direction=="forward" and passage.start[2]>-3.5 and passage.end[2]<-4.5:forward_count+=1
			if passage.direction=="reverse" and passage.start[2]<-4.5 and passage.end[2]>-3.5:reverse_count+=1
		cases.append({"name":"door_passages","forward_passes":forward_count,"reverse_passes":reverse_count,
			"completed":forward_count+reverse_count,"passages":passages,"camera_rotation_deferred":"P03"})
		cases.append(await _recovery("fall_return",Vector3(-2,-10,2),"fall"))
		cases.append(await _recovery("outside_return",Vector3(50,0.08,2),"outside_test_area"))
		cases.append(await _recovery("manual_return",Vector3(1,0.08,5),"manual_restart"))
		await _place(Vector3(11.3,0.08,5))
		var edge := await _segment("edge_return",["move_right","move_fast"],1.0)
		edge["reason"] = scene.player.last_recovery_reason
		edge["recovery_count_delta"] = edge.recoveries
		edge["spawn_valid"] = scene.player.spawn_valid
		cases.append(edge)
		await _place(Vector3(-2,0.08,2))
		_keys(["move_forward","move_fast"])
		_physical_key(KEY_ESCAPE,true)
		await process_frame
		await process_frame
		_physical_key(KEY_ESCAPE,false)
		var pause_position: Vector3 = scene.player.global_position
		var tick_start := Engine.get_physics_frames()
		var actor_process: bool = scene.player.can_process()
		var tree_paused := paused
		var pause_velocity: Vector3 = scene.player.velocity
		await create_timer(0.25).timeout
		var pause_drift: float = scene.player.global_position.distance_to(pause_position)
		# Engine physics counter can advance while node physics is paused; actor signal is decisive.
		var actor_ticks := [0]
		var counter := func(_delta: float):actor_ticks[0]+=1
		scene.player.physics_stepped.connect(counter)
		await create_timer(0.25).timeout
		scene.player.physics_stepped.disconnect(counter)
		var engine_pause_ticks := Engine.get_physics_frames()-tick_start
		_physical_key(KEY_ESCAPE,true)
		await process_frame
		await process_frame
		_physical_key(KEY_ESCAPE,false)
		var held_menu := await _segment("held_after_menu",["move_forward","move_fast"],1.0)
		_keys([])
		await _wait(0.1)
		var resumed := await _segment("resumed_after_menu",["move_forward"],0.5)
		cases.append({"name":"menu_pause","paused":tree_paused,"actor_can_process":actor_process,
			"ticks_during_pause":actor_ticks[0],"engine_ticks_during_pause":engine_pause_ticks,
			"paused_displacement_m":pause_drift,"velocity_when_paused":_v(pause_velocity),
			"held_drift_after_close_m":held_menu.horizontal_distance_m,"release_then_move_m":resumed.horizontal_distance_m})
		await _place(Vector3(-2,0.08,2))
		_physical_key(KEY_W,true)
		await _wait(0.5)
		var w_intent: Vector2 = scene.input_router.movement_intent()
		_physical_key(KEY_W,false)
		_physical_key(KEY_SHIFT,true)
		_physical_key(KEY_RIGHT,true)
		await _wait(0.2)
		var fast_physical: bool = scene.input_router.fast_intent()
		var arrow_intent: Vector2 = scene.input_router.movement_intent()
		_physical_key(KEY_SHIFT,false)
		_physical_key(KEY_RIGHT,false)
		cases.append({"name":"physical_key_dispatch","w_intent":[w_intent.x,w_intent.y],"arrow_intent":[arrow_intent.x,arrow_intent.y],"shift_fast":fast_physical})
		_keys([])
		await _wait(0.2)
		var safe_position: Vector3 = scene.player.global_position
		scene.player.spawn_transform.origin = Vector3(-2,2,2)
		var accepted: bool = scene.player.recover("invalid_probe")
		cases.append({"name":"invalid_spawn_guard","recovery_accepted":accepted,"position_unchanged":scene.player.global_position==safe_position})
		scene.player.configure_recovery(scene.START,scene.TEST_REGIONS)
		await _wait(0.2)
	if not capture_prefix.is_empty() and DisplayServer.get_name()!="headless":
		_keys([])
		await _place(Vector3(-2,0.08,2))
		for view in ["overview","person","distance"]:
			scene.set_view(view)
			await create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			if root.get_texture().get_image().save_png(capture_prefix+"_"+view+".png")!=OK:quit(1);return
	var record := {"schema_version":1,"task":"P02","suite":suite,"case":variant,
		"engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),
			"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),
			"physics_hz":Engine.physics_ticks_per_second,"render_cap_fps":render_cap},
		"contract":contract,"cases":cases,"scope":"authored fixture, automatic input; no Seoul walking, human handling, P03 camera or M4 validation"}
	if output_path.is_empty():push_error("P02 result path required");quit(1);return
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	if file==null:push_error("P02 result write failed");quit(1);return
	file.store_string(JSON.stringify(record,"\t")+"\n")
	print("P02_PROBE_DONE suite=%s case=%s cases=%d"%[suite,variant,cases.size()])
	scene.queue_free()
	quit(0)
