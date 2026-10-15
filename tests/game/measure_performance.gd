extends SceneTree
## R01 native render sampling only. The moving camera is not a walking test.
const MONITORS := ["TIME_PROCESS", "TIME_PHYSICS_PROCESS", "MEMORY_STATIC", "OBJECT_COUNT", "RENDER_TOTAL_DRAW_CALLS_IN_FRAME", "RENDER_TOTAL_OBJECTS_IN_FRAME", "RENDER_VIDEO_MEM_USED", "RENDER_TEXTURE_MEM_USED", "RENDER_BUFFER_MEM_USED"]
var profile := "A"
var output_path := ""
var capture_path := ""
var duration_s := 600.
var warmup_s := 30.
var scene
var bench_camera: Camera3D
var plan: Dictionary
var monitor_ids := {}
var frame_buffer := []
var frame_file: FileAccess
var frame_count := 0
var maximum_buffer_rows := 0
var second_rows := []
var boot_us := 0
var spawn_us := 0
var ready_us := 0
var first_frame_us := 0
var warmup_us := 0
var measure_us := 0
var previous_us := 0
var next_second := 0.
var measuring := false
var finishing := false
var camera_clock_s := 0.
var initial_resolution := {}
var start_physics_tick := 0
var end_physics_tick := 0
var initial_conditions := {}
var warmup_actual_s := 0.
var first_frame_reported := false
var source_pose_index := 0
var source_tick := 0
var source_clock_s := 0.
var render_texture: Texture2D

func _initialize() -> void:
	boot_us=Time.get_ticks_usec()
	print("R01_PID=",OS.get_process_id())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="):profile=arg.trim_prefix("--profile=")
		elif arg.begins_with("--result="):output_path=arg.trim_prefix("--result=")
		elif arg.begins_with("--capture="):capture_path=arg.trim_prefix("--capture=")
		elif arg.begins_with("--duration="):duration_s=arg.trim_prefix("--duration=").to_float()
		elif arg.begins_with("--warmup="):warmup_s=arg.trim_prefix("--warmup=").to_float()
	Engine.max_fps=0;Engine.physics_ticks_per_second=60
	OS.low_processor_usage_mode=false
	render_texture=root.get_texture()
	var constants:=ClassDB.class_get_integer_constant_list("Performance")
	for name in MONITORS:
		if constants.has(name):monitor_ids[name]=ClassDB.class_get_integer_constant("Performance",name)
	RenderingServer.frame_post_draw.connect(_rendered)
	_start.call_deferred()

func _v(point: Vector3) -> Array:return [point.x,point.y,point.z]
func _vec(values: Array) -> Vector3:return Vector3(values[0],values[1],values[2])

func _monitor(name: String):
	if not monitor_ids.has(name) or (name=="MEMORY_STATIC" and not OS.is_debug_build()):return null
	var value:=Performance.get_monitor(monitor_ids[name])
	return value if is_finite(value) else null

func _camera_at(seconds: float) -> void:
	camera_clock_s=seconds
	var phase:=fposmod(seconds,float(plan.period_s))/float(plan.period_s)
	var target_s:=phase*float(plan.source_duration_s)
	# Previous retained safe source pose only: never interpolate a chord through walls.
	var low:=0;var high: int=plan.poses.size()
	while low<high:
		var middle: int=(low+high)/2
		if float(plan.poses[middle][0])<=target_s:low=middle+1
		else:high=middle
	source_pose_index=maxi(0,low-1)
	var pose: Array=plan.poses[source_pose_index]
	source_clock_s=pose[0];source_tick=int(pose[1])
	var basis: Array=pose[3]
	bench_camera.global_transform=Transform3D(Basis(_vec(basis[0]),_vec(basis[1]),_vec(basis[2])),_vec(pose[2]))
	bench_camera.fov=pose[4];bench_camera.near=pose[5]

func _after_player_step(_delta: float) -> void:
	if finishing or not is_instance_valid(bench_camera):return
	var now:=Time.get_ticks_usec()
	if measuring:
		_camera_at(0. if measure_us==0 else (now-measure_us)/1000000.)
	elif warmup_us>0:
		_camera_at((now-warmup_us)/1000000.*float(plan.period_s)/warmup_s)
	else:_camera_at(0.)

func _actors() -> Dictionary:
	var people:=[];var cars:=[]
	var people_root: Node=scene.get_node_or_null("Actors/Pedestrians")
	var car_root: Node=scene.get_node_or_null("Actors/Vehicles")
	if people_root!=null:
		for body in people_root.get_children():
			var s: Dictionary=body.call("snapshot")
			people.append({"instance_id":body.get_instance_id(),"route_id":s.route_id,"position":s.position,"station_m":s.station_m,"route_length_m":s.route_length_m,"state":s.state,"running":s.running,"completed_cycles":s.completed_cycles,"end_events":s.end_events,"actual_distance_m":s.actual_distance_m,"physics_steps":s.physics_steps})
	if car_root!=null:
		for body in car_root.get_children():
			var s: Dictionary=body.call("snapshot")
			cars.append({"instance_id":body.get_instance_id(),"route_id":s.route_id,"position":s.position,"station_m":s.station_m,"route_length_m":s.route_length_m,"state":s.state,"running":s.running,"cycle_count":s.cycle_count,"end_events":s.end_events,"actual_distance_m":s.actual_distance_m,"physics_steps":s.physics_steps})
	return {"pedestrians":people,"vehicles":cars,"pedestrian_count":people.size(),"vehicle_count":cars.size()}

func _light_row(seconds: float) -> Dictionary:
	var basis:=bench_camera.global_basis
	return {"t_s":seconds,"physics_tick":Engine.get_physics_frames(),"camera_clock_s":camera_clock_s,
		"camera_loop_phase":fposmod(camera_clock_s,float(plan.period_s))/float(plan.period_s),"source_pose_index":source_pose_index,"source_tick":source_tick,"source_t_s":source_clock_s,
		"camera_position":_v(bench_camera.global_position),"camera_basis_columns":[_v(basis.x),_v(basis.y),_v(basis.z)],
		"camera_fov":bench_camera.fov,"camera_near":bench_camera.near,"camera_far":bench_camera.far,
		"camera_current":root.get_camera_3d()==bench_camera,"window_size":[root.size.x,root.size.y],
		"window_focused":DisplayServer.window_is_focused(),
		"viewport_visible_size":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],
		"player_position":_v(scene.player.global_position),"player_recoveries":scene.player.recoveries,
		"tree_paused":paused,"actors":_actors()}

func _conditions() -> Dictionary:
	var sun: DirectionalLight3D=scene.get_node_or_null("Presentation/Sun") as DirectionalLight3D
	var light=null
	if sun!=null:
		light={"shadow_enabled":sun.shadow_enabled,"shadow_max_distance_m":sun.directional_shadow_max_distance,"light_energy":sun.light_energy}
	var screen:={"index":root.current_screen,"size_pixels":null,"scale":null,"reported_dpi":null}
	if DisplayServer.has_method("screen_get_size"):
		var size: Vector2i=DisplayServer.screen_get_size(root.current_screen)
		screen.size_pixels=[size.x,size.y]
	if DisplayServer.has_method("screen_get_scale"):screen.scale=DisplayServer.screen_get_scale(root.current_screen)
	if DisplayServer.has_method("screen_get_dpi"):screen.reported_dpi=DisplayServer.screen_get_dpi(root.current_screen)
	return {"camera_far_m":bench_camera.far,"sun":light,"scaling_3d_scale":root.scaling_3d_scale,"msaa_3d":root.msaa_3d,"screen":screen}

func _resolution() -> Dictionary:
	# Readback is outside the timed interval. A requested window size is not proof.
	var picture:=root.get_texture().get_image()
	var row:={"width":picture.get_width(),"height":picture.get_height(),"source":"ViewportTexture.get_image","scaling_3d_scale":root.scaling_3d_scale}
	if not capture_path.is_empty() and initial_resolution.is_empty():
		row["png_save_error"]=picture.save_png(capture_path)
	return row

func _start() -> void:
	if DisplayServer.get_name()=="headless" or profile not in ["A","B"] or duration_s<=0 or warmup_s<=0:
		push_error("R01 requires native rendering, A/B profile and positive timing");quit(1);return
	plan=JSON.parse_string(FileAccess.get_file_as_string("res://test_support/benchmark_camera.json"))
	if not plan is Dictionary or plan.get("poses",[]).size()<8 or plan.get("period_s")!=300. or plan.get("stage_sample_counts",{}).size()!=11:
		push_error("R01 complete eleven-stage N04 camera trace required");quit(1);return
	spawn_us=Time.get_ticks_usec()
	var path:="res://scenes/world/city_landmarks.tscn" if profile=="A" else "res://scenes/world/traffic_walk.tscn"
	scene=load(path).instantiate();root.add_child(scene)
	if not scene.runtime_ok:push_error("R01 production scene did not load");quit(1);return
	scene.input_router.gameplay_enabled=false
	scene.input_router.set_process_input(false);scene.input_router.set_process_unhandled_input(false)
	scene.rig.set_capture(false)
	for action in ["move_left","move_right","move_forward","move_backward","move_fast"]:Input.action_release(action)
	scene.get_node("Interface").visible=false
	bench_camera=Camera3D.new();bench_camera.name="R01BenchmarkCamera"
	bench_camera.fov=scene.rig.camera.fov;bench_camera.near=scene.rig.camera.near;bench_camera.far=scene.rig.camera.far
	scene.add_child(bench_camera);_camera_at(0.);bench_camera.make_current()
	if profile=="B":scene.traffic.camera=bench_camera
	scene.player.physics_stepped.connect(_after_player_step)
	ready_us=Time.get_ticks_usec()
	while first_frame_us==0:await process_frame
	# Main-window project overrides are applied after SceneTree._initialize.
	# Apply the requested native size after that initialization, then render it.
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size=Vector2i.ZERO;root.content_scale_factor=1.
	root.size=Vector2i(1920,1080);root.scaling_3d_scale=1.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await RenderingServer.frame_post_draw
	# Readback occurs outside the rendering callback itself.
	await process_frame
	initial_resolution=_resolution()
	initial_conditions=_conditions()
	if initial_resolution.width!=1920 or initial_resolution.height!=1080:
		push_error("R01 actual rendered image is not 1920x1080");quit(1);return
	print("R01_READY profile=",profile," scene_spawn_to_first_frame_s=",(first_frame_us-spawn_us)/1000000.," actual_render=1920x1080")
	frame_file=FileAccess.open(output_path+".frames.jsonl",FileAccess.WRITE)
	if frame_file==null:push_error("R01 raw frame stream could not be saved");quit(1);return
	warmup_us=Time.get_ticks_usec()
	while (Time.get_ticks_usec()-warmup_us)/1000000.<warmup_s:await process_frame
	warmup_actual_s=(Time.get_ticks_usec()-warmup_us)/1000000.
	measuring=true

func _rendered() -> void:
	if ready_us==0 or finishing:return
	var now:=Time.get_ticks_usec()
	if not first_frame_reported:
		first_frame_us=now;first_frame_reported=true;print("R01_FIRST_FRAME profile=",profile)
	if not measuring:return
	if measure_us==0:
		measure_us=now;previous_us=now;start_physics_tick=Engine.get_physics_frames()
		_camera_at(0.);second_rows.append(_light_row(0.));next_second=1.
		print("R01_MEASURE_START profile=",profile)
		return
	var elapsed: float=(now-measure_us)/1000000.
	var row: Array=[elapsed,(now-previous_us)/1000.]
	for name in MONITORS:row.append(_monitor(name))
	row.append(Engine.get_physics_frames());row.append(render_texture.get_width());row.append(render_texture.get_height())
	row.append(root.scaling_3d_scale)
	row.append(camera_clock_s);row.append(source_pose_index);row.append(source_tick)
	frame_buffer.append(row);frame_count+=1;previous_us=now
	maximum_buffer_rows=maxi(maximum_buffer_rows,frame_buffer.size())
	if elapsed>=next_second:
		second_rows.append(_light_row(elapsed));next_second=floor(elapsed)+1.
		_flush_frames()
		if int(floor(elapsed))%60==0:print("R01_PROGRESS profile=",profile," elapsed_s=",elapsed," frames=",frame_count)
	if elapsed>=duration_s:
		end_physics_tick=Engine.get_physics_frames()
		if second_rows[-1].t_s<elapsed:second_rows.append(_light_row(elapsed))
		measuring=false;finishing=true;_finish.call_deferred()

func _flush_frames() -> void:
	if frame_buffer.is_empty():return
	frame_file.store_string(JSON.stringify(frame_buffer)+"\n")
	frame_buffer.clear()

func _finish() -> void:
	var elapsed: float=(previous_us-measure_us)/1000000.
	_flush_frames();frame_file.close()
	var profile_methods:={}
	for name in ["set_frame_profiling_enabled","get_frame_profile","get_frame_profile_frame"]:profile_methods[name]=RenderingServer.has_method(name)
	var record:={"schema_version":1,"task":"R01","profile":profile,"duration_requested_s":duration_s,"duration_actual_s":elapsed,
		"warmup_requested_s":warmup_s,"warmup_actual_s":warmup_actual_s,"window_s":300.,"pid":OS.get_process_id(),
		"engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"debug_build":OS.is_debug_build(),"physics_hz":Engine.physics_ticks_per_second,"max_fps":Engine.max_fps,"vsync_mode":DisplayServer.window_get_vsync_mode()},
		"startup":{"engine_initialize_ticks_us":boot_us,"scene_spawn_ticks_us":spawn_us,"scene_ready_ticks_us":ready_us,"first_actual_frame_ticks_us":first_frame_us,"engine_initialize_to_first_frame_s":(first_frame_us-boot_us)/1000000.,"scene_spawn_to_first_frame_s":(first_frame_us-spawn_us)/1000000.,"scene_ready_s":(ready_us-spawn_us)/1000000.},
		"resolution_proof":{"before":initial_resolution,"after":_resolution()},"render_conditions":{"before":initial_conditions,"after":_conditions()},"first_physics_tick":start_physics_tick,"last_physics_tick":end_physics_tick,
		"camera_plan_sha256":FileAccess.get_sha256("res://test_support/benchmark_camera.json"),"public_sha256":FileAccess.get_sha256("res://data/generated/public_walk.json"),
		"camera_source":{"record_sha256":plan.source_record_sha256,"source_duration_s":plan.source_duration_s,"compression_factor":plan.source_duration_s/300.,"stage_sample_counts":plan.stage_sample_counts,"source_leg_count":plan.source_leg_count,"mode":"Previous retained source pose; no interpolated geometry chords."},
		"frame_columns":["t_end_s","monotonic_frame_ms"]+MONITORS+["physics_tick","viewport_texture_width","viewport_texture_height","scaling_3d_scale","camera_clock_s","source_pose_index","source_tick"],"frame_count":frame_count,"second_observations":second_rows,
		"frame_storage":{"during_measurement":"JSONL array batches once per second; full per-frame arrays assembled after measurement by Python","maximum_buffer_rows":maximum_buffer_rows,"batch_file_sha256":FileAccess.get_sha256(output_path+".frames.jsonl"),"overhead_scope":"One render signal callback, nine monitor reads per frame, 1Hz light actor observations and buffered serialization; no per-frame geometry queries."},
		"monitor_units":{"TIME_PROCESS":"seconds; engine monitor can lag up to 1 second","TIME_PHYSICS_PROCESS":"seconds; engine monitor can lag up to 1 second","MEMORY_STATIC":"bytes; engine tracked static memory, debug build only, not process RSS","OBJECT_COUNT":"objects","RENDER_TOTAL_DRAW_CALLS_IN_FRAME":"draw calls","RENDER_TOTAL_OBJECTS_IN_FRAME":"rendered objects","RENDER_VIDEO_MEM_USED":"bytes; driver-reported video allocation, not GPU frame time","RENDER_TEXTURE_MEM_USED":"bytes","RENDER_BUFFER_MEM_USED":"bytes"},
		"monitor_availability":monitor_ids,"gpu_time_ms":null,"render_frame_profile":{"available_methods":profile_methods,"sampled":false,"reason":"These names are internal C++ API in the verified upstream 4.6 source, not documented GDScript methods. No unverified invocation or nested-area sum."},
		"setup":{"input_disabled":not scene.input_router.gameplay_enabled,"interface_hidden":not scene.get_node("Interface").visible,"source_spawn":scene.city.public_data.spawn,"camera_is_independent":bench_camera!=scene.rig.camera,"traffic_camera_redirected":scene.traffic.camera==bench_camera if profile=="B" else false,"warmup_camera_loop_s":warmup_s,"measurement_camera_loop_s":300.},
		"scope":"Uncapped native rendering benchmark replaying retained N04 camera poses from all eleven W04 stages in a time-compressed 300 second loop. Player remains at spawn; actors continue independently, so this is not a physical walking, camera collision, traffic safety, exported-package or M4 test. No heavy geometry observers; monitor values can lag up to one second and static memory is unavailable in release builds."}
	var file:=FileAccess.open(output_path,FileAccess.WRITE)
	if file==null:push_error("R01 result could not be saved");quit(1);return
	file.store_string(JSON.stringify(record)+"\n")
	print("R01_DONE profile=",profile," frames=",frame_count," elapsed_s=",elapsed)
	scene.queue_free();quit(0)
