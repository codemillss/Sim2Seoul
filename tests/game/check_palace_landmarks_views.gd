extends "res://test_support/check_walkable_milestone.gd"
## Fixed inspection cameras are visual reviews, not additional playable/spawn locations.
func _run() -> void:
	scene = load("res://scenes/world/palace_landmarks.tscn").instantiate()
	root.add_child(scene)
	if not scene.runtime_ok: push_error("L02 scene did not load"); quit(1); return
	scene.rig.set_capture(false)
	await _wait(1)
	load("res://test_support/palace_visual_observation.gd").inject(scene, variant)
	var observed: Dictionary = load("res://test_support/palace_visual_observation.gd").collect(scene)
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://test_support/landmark_spec.json"))
	# Labels cannot substitute for recognizable silhouettes in comparison images.
	for node in scene.get_node("Presentation").get_children():
		if node is Label3D: node.visible = false
	var review := Camera3D.new()
	review.name = "FixedLandmarkInspectionCamera"
	review.fov = 52.0
	scene.add_child(review)
	var views := []
	for item in spec.landmarks:
		if item.phase != "L02": continue
		var b: Dictionary = item.spatial_binding
		var box: Array = b.bbox_xz_m
		var height: float = b.height_m
		var centre := Vector3((box[0]+box[2])/2.0, b.current_bottom_y_m, (box[1]+box[3])/2.0)
		var size := maxf(box[2]-box[0], box[3]-box[1])
		var target := centre + Vector3.UP * height * 0.43
		var eye := centre + Vector3(size*0.32, height+size*0.38, size*1.18)
		if item.id == "daehanmun":
			var dir: Array = scene.city.connection.direction_xz
			eye = centre - Vector3(dir[0], 0, dir[1])*size*1.6 + Vector3.UP*height*0.9
			# Small across-passage offset reveals depth without hiding the opening.
			eye += Vector3(-dir[1], 0, dir[0])*size*0.25
		review.global_position = eye
		review.look_at(target)
		review.make_current()
		for authored in [false, true]:
			scene.landmark_visuals.show_authored(authored)
			await _capture(item.id + ("_after" if authored else "_before"))
		views.append({"id": item.id, "camera": _v(eye), "target": _v(target), "fov": review.fov,
			"mode": "fixed_visual_inspection_not_player_spawn", "labels_hidden": true})
	scene.landmark_visuals.show_authored(true)
	scene.rig.camera.make_current()
	await _pose(_point(scene.city.connection.route_xz[0]), scene.starting_yaw)
	await _capture("gate_third_person")
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version": 1, "task": "L02", "views": views,
		"visuals": observed, "captures": capture_names,
		"engine": {"version": Engine.get_version_info().string, "display": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name()},
		"scope": "Fixed before/after visual inspection; no new walkability or human recognition acceptance"}) + "\n")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("L02_VIEWS_DONE count=", views.size())
	scene.queue_free()
	quit(0)
