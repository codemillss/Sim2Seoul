extends SceneTree
## Actual engine measurements; Python owns acceptance. Defaults to 60 real seconds.
var output_path := ""
var capture_prefix := ""
var variant := "normal"
var duration := 60.0
var scene

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--result="):output_path = arg.trim_prefix("--result=")
		elif arg.begins_with("--capture-prefix="):capture_prefix = arg.trim_prefix("--capture-prefix=")
		elif arg.begins_with("--case="):variant = arg.trim_prefix("--case=")
		elif arg.begins_with("--seconds="):duration = arg.trim_prefix("--seconds=").to_float()
	_run.call_deferred()

func _run() -> void:
	if not is_finite(duration) or duration<=0:quit(1);return
	scene = load("res://scenes/tests/player_fixture.tscn").instantiate()
	root.add_child(scene)
	match variant:
		"player_scaled":scene.player.scale = Vector3(1.1,1.1,1.1)
		"collision_height":scene.player.get_node("CollisionShape").shape.height = 2.0
		"visual_offset":scene.player.get_node("Visual").position.y = 0.15
		"mask_disabled":scene.player.collision_mask = 0
		"collider_disabled":scene.player.get_node("CollisionShape").disabled = true
		"floor_disabled":scene.get_node("Fixtures/Floor/CollisionShape").disabled = true
		"spawn_below_floor":scene.player.position.y = -0.5
		"door_blocked":scene.get_node("Fixtures/DoorLintel").position.y = 1.3
		"step_height_wrong":scene.get_node("Fixtures/Step015").position.y += 0.1
		"normal":pass
		_:push_error("Unknown P01 variant");quit(1);return
	# Capture initial placement before the settling interval.
	var initial_position: Vector3 = scene.player.global_position
	var initial_velocity: Vector3 = scene.player.velocity
	await process_frame
	var settle_seconds := 0.0
	while settle_seconds<1.0-0.000001:
		settle_seconds += await scene.player.physics_stepped
	var start_time := Time.get_ticks_usec()
	var seconds := 0.0
	var ticks := 0
	var on_floor_ticks := 0
	var min_y := INF
	var max_y := -INF
	var max_vertical_speed := 0.0
	var max_horizontal_drift := 0.0
	var first: Vector3 = scene.player.global_position
	var samples := []
	while seconds<duration-0.000001:
		seconds += await scene.player.physics_stepped
		ticks += 1
		var p: Vector3 = scene.player.global_position
		min_y = min(min_y,p.y)
		max_y = max(max_y,p.y)
		max_vertical_speed = max(max_vertical_speed,abs(scene.player.velocity.y))
		max_horizontal_drift = max(max_horizontal_drift,Vector2(p.x-first.x,p.z-first.z).length())
		if scene.player.is_on_floor():on_floor_ticks += 1
		if ticks==1 or ticks%60==0:
			samples.append({"physics_seconds":seconds,"position":[p.x,p.y,p.z],"velocity_y":scene.player.velocity.y,"floor":scene.player.is_on_floor()})
	var elapsed := (Time.get_ticks_usec()-start_time)/1000000.0
	scene.set_view("overview")
	var record := {"task":"P01","case":variant,"engine":Engine.get_version_info().string,
		"display_server":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"driver":RenderingServer.get_current_rendering_driver_name(),"physics_ticks_per_second":Engine.physics_ticks_per_second,
		"initial_position":[initial_position.x,initial_position.y,initial_position.z],
		"initial_velocity":[initial_velocity.x,initial_velocity.y,initial_velocity.z],
		"settle_seconds":settle_seconds,"observation":{"requested_seconds":duration,"physics_seconds":seconds,
			"wall_seconds":elapsed,"ticks":ticks,"on_floor_ticks":on_floor_ticks,"min_y":min_y,"max_y":max_y,
			"max_vertical_speed_mps":max_vertical_speed,"max_horizontal_drift_m":max_horizontal_drift,"samples_1hz":samples},
		"measurements":scene.measure(),"scope":"synthetic P01 idle support only, not locomotion/door passage/step traversal/Seoul collision"}
	if not capture_prefix.is_empty() and DisplayServer.get_name()!="headless":
		var captures := []
		for view in ["overview","person","door"]:
			scene.set_view(view)
			await create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			if image.save_png(capture_prefix+"_"+view+".png")!=OK:push_error("P01 capture write failed");quit(1);return
			captures.append({"view":view,"width":image.get_width(),"height":image.get_height(),"camera":scene.measure().camera})
		record["captures"] = captures
		scene.toggle_menu()
		var paused_position: Vector3 = scene.player.global_position
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		record["menu"] = {"tree_paused":paused,"player_can_process":scene.player.can_process(),"player_position_unchanged":scene.player.global_position==paused_position}
		if root.get_texture().get_image().save_png(capture_prefix+"_menu.png")!=OK:quit(1);return
		scene.toggle_menu()
	if output_path.is_empty():push_error("P01 result path required");quit(1);return
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	if file==null:push_error("P01 result write failed");quit(1);return
	file.store_string(JSON.stringify(record,"\t")+"\n")
	print("P01_PROBE_DONE case=%s ticks=%s physics_seconds=%.3f wall_seconds=%.3f" % [variant,ticks,seconds,elapsed])
	scene.queue_free()
	quit(0)
