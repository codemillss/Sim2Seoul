extends "res://test_support/check_walkable_milestone.gd"
## L04 observation cameras and local diagnostics never enter the production game.
var review_plan: Dictionary
var reference_spec: Dictionary
var inspected := []
var masks := []

func _target(id: String) -> Vector3:
	for item in reference_spec.landmarks:
		if item.id != id: continue
		var box: Array = item.spatial_binding.bbox_xz_m
		var height := float(item.spatial_binding.height_m) if item.spatial_binding.height_m != null else 0.0
		return Vector3((box[0]+box[2])*.5, height*.45, (box[1]+box[3])*.5)
	return Vector3.ZERO

func _actor() -> Dictionary:
	var shape: CapsuleShape3D = scene.player.get_node("CollisionShape").shape
	return {"height":shape.height,"radius":shape.radius,"layer":scene.player.collision_layer,"mask":scene.player.collision_mask,
		"walk_mps":scene.player.walk_speed_mps,"run_mps":scene.player.run_speed_mps,"gravity":scene.player.gravity_mps2,
		"safe_margin":scene.player.safe_margin,"camera_mask":scene.rig.arm.collision_mask,"camera_probe_radius":scene.rig.arm.shape.radius,
		"player_camera_path_matches":scene.player.movement_camera==scene.rig.camera,"boundary_script":scene.player.get_script().resource_path}

func _mask(name: String, target: String) -> void:
	if capture_prefix.is_empty() or DisplayServer.get_name()=="headless": return
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color.WHITE
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	var targets := {}
	var overlay: Node3D = scene.landmark_visuals if scene.landmark_visuals.TARGETS.has(target) else scene.city_visuals
	for node in overlay.components.values():
		if node.get_parent().name==target: targets[node] = true
	var saved := {}
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is MeshInstance3D:
			saved[node] = node.material_override
			node.material_override = white if targets.has(node) else black
	var environment: Environment = scene.get_world_3d().environment
	var temporary := Environment.new()
	temporary.background_mode = Environment.BG_COLOR
	temporary.background_color = Color.BLACK
	scene.get_world_3d().environment = temporary
	var ui: CanvasLayer = scene.get_node("Interface")
	var was_visible := ui.visible
	ui.visible = false
	await _capture(name + "_mask")
	# Pixel data is independently decoded from the saved PNG by the driver.
	masks.append({"capture":name+"_mask","target":target,"white_target_only":true,
		"camera_position":_v(scene.get_viewport().get_camera_3d().global_position)})
	ui.visible = was_visible
	scene.get_world_3d().environment = environment
	for node in saved: node.material_override = saved[node]

func _views() -> void:
	for node in scene.get_node("Presentation").get_children():
		if node is Label3D: node.visible = false
	for node in scene.get_node("Interface").get_children():
		if node is PanelContainer: node.visible = false
	var eye := Camera3D.new()
	eye.fov = scene.rig.camera.fov
	scene.add_child(eye)
	for view in review_plan.views:
		var point := _point(view.xz)
		var target := _target(view.target)
		var delta := target-(point+Vector3.UP*1.3)
		var yaw := atan2(-delta.x,-delta.z)
		var pitch := clampf(rad_to_deg(atan2(delta.y,Vector2(delta.x,delta.z).length())),-55,15)
		await _pose(point,yaw,pitch)
		scene.rig.camera.make_current()
		var location: Dictionary = _sample(0.0)
		var body_visible: bool = scene.player.get_node("Visual").visible
		for authored in [false,true]:
			scene.landmark_visuals.show_authored(authored)
			scene.city_visuals.show_authored(authored)
			await _capture(view.id+ ("_after" if authored else "_before"))
		# Bind projection metadata to the rendered third-person frame, rather
		# than a later frame after the inspection camera has become current.
		location = _sample(0.0)
		await _mask(view.id+"_third",view.target)
		var eye_player := _v(scene.player.global_position)
		eye.global_position = scene.player.global_position+Vector3.UP*1.6
		eye.look_at(target)
		eye.make_current()
		scene.player.get_node("Visual").visible = false
		await _capture(view.id+"_eye")
		await _mask(view.id+"_eye",view.target)
		inspected.append({"id":view.id,"target":view.target,"basis":view.basis,"xz":view.xz,
			"location":location,"third_camera":location.rig,"eye_position":_v(eye.global_position),"eye_player":eye_player,
			"eye_target":_v(target),"eye_height_m":1.6,"eye_fov":eye.fov,
			"player_visible_in_third":body_visible,"labels_hidden":true})
		scene.player.get_node("Visual").visible = body_visible
		scene.rig.camera.make_current()
	eye.queue_free()

func _run() -> void:
	review_plan = JSON.parse_string(FileAccess.get_file_as_string("res://test_support/landmark_review_plan.json"))
	reference_spec = JSON.parse_string(FileAccess.get_file_as_string("res://test_support/landmark_spec.json"))
	scene = load("res://scenes/world/city_landmarks.tscn").instantiate()
	root.add_child(scene)
	if not scene.runtime_ok: push_error("L04 production scene failed"); quit(1); return
	scene.input_router.set_script(load("res://test_support/daehanmun_probe_input.gd"))
	scene.input_router.isolate_movement_bindings()
	if variant=="camera_mask": scene.rig.arm.collision_mask=0
	elif variant!="normal": push_error("Unknown L04 fault"); quit(1); return
	await _wait(1)
	var before := _inventory()
	var actor := _actor()
	await _views()
	var cases := []
	var previous_group := ""
	for requested in review_plan.cases:
		var row: Dictionary
		if requested.purpose=="orbit":
			var cp: Array = scene.city.public_data.checkpoints[requested.checkpoint_index].xz
			await _pose(_point(cp),0,-15)
			await _wait(1)
			row = await _segment(requested.name,requested.seconds,Vector3.ZERO,false,TAU/.0025/requested.seconds)
		else:
			if requested.group!=previous_group:
				await _pose(_point(requested.from_xz),scene.starting_yaw,-15)
				await _wait(1)
				previous_group = requested.group
			var destination := _point(requested.expected_end_xz)
			var delta: Vector3 = destination-scene.player.global_position
			delta.y=0
			row = await _segment(requested.name,maxf(1.0/60,ceil(delta.length()/3.5*60)/60),delta.normalized(),true,8)
			row["expected_end_xz"] = requested.expected_end_xz
		row["purpose"] = requested.purpose
		cases.append(row)
		print("L04_CASE ",requested.name," ticks=",row.ticks)
	var city_observed: Dictionary = load("res://test_support/city_visual_observation.gd").collect(scene)
	var palace_observed: Dictionary = load("res://test_support/palace_visual_observation.gd").collect(scene)
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version":1,"task":"L04","fault":variant,"engine":{"version":Engine.get_version_info().string,
		"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"physics_hz":Engine.physics_ticks_per_second,"render_fps":fps},
		"plan_sha256":FileAccess.get_sha256("res://test_support/landmark_review_plan.json"),"actor":actor,
		"inventory_before":before,"inventory_after":_inventory(),"views":inspected,"masks":masks,"cases":cases,
		"city_visuals":city_observed,"palace_visuals":palace_observed,"captures":capture_names,
		"scope":"Local orbit/gate/plaza diagnostics; placements occur between groups. Full W04 journey is reused only with exact source hashes. Eye camera is inspection only; no new walking/interior permission"})+"\n")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	scene.queue_free()
	quit(0)
