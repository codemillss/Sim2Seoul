extends "res://test_support/check_walkable_milestone.gd"
## Inspection images do not create player spawns or traversal permissions.
func _run() -> void:
	scene = load("res://scenes/world/city_landmarks.tscn").instantiate()
	root.add_child(scene)
	if not scene.runtime_ok: push_error("L03 scene did not load"); quit(1); return
	scene.rig.set_capture(false)
	await _wait(1)
	load("res://test_support/city_visual_observation.gd").inject(scene, variant)
	var city_observed: Dictionary = load("res://test_support/city_visual_observation.gd").collect(scene)
	var palace_observed: Dictionary = load("res://test_support/palace_visual_observation.gd").collect(scene)
	var spec = JSON.parse_string(FileAccess.get_file_as_string("res://test_support/landmark_spec.json"))
	for node in scene.get_node("Presentation").get_children():
		if node is Label3D: node.visible = false
	# Keep the map attribution; remove the large movement help panel in reviews.
	for node in scene.get_node("Interface").get_children():
		if node is PanelContainer: node.visible = false
	var review := Camera3D.new()
	review.fov = 52.0
	scene.add_child(review)
	var views := []
	for item in spec.landmarks:
		if item.phase != "L03": continue
		var binding: Dictionary = item.spatial_binding
		var box: Array = binding.bbox_xz_m
		var height := float(binding.height_m) if binding.height_m != null else 0.0
		var centre := Vector3((box[0]+box[2])/2.0, binding.current_bottom_y_m, (box[1]+box[3])/2.0)
		var size := maxf(box[2]-box[0], box[3]-box[1])
		var target := centre + Vector3.UP * height * 0.42
		var eye := centre + Vector3(size*.30, height*.60+size*.40, size*1.24)
		if item.id == "sfc": eye = centre + Vector3(size*1.5,height*1.30,size*2.10)
		review.global_position = eye
		review.look_at(target)
		review.make_current()
		for authored in [false, true]:
			scene.city_visuals.show_authored(authored)
			await _capture(item.id + ("_after" if authored else "_before"))
		if item.id == "sfc" and not capture_prefix.is_empty():
			# Load the real original with its original texture at the documented fit.
			var state := GLTFState.new()
			var document := GLTFDocument.new()
			if document.append_from_file("res://assets/vendor/kenney_city_kit_commercial/building-skyscraper-a.glb", state, 64) != OK:
				push_error("L03 comparison import failed"); quit(1); return
			var original := document.generate_scene(state)
			scene.add_child(original)
			var reuse: Dictionary = scene.city_visuals.bundle.reuse
			var fit: Dictionary = reuse.transform
			var scale: Array = fit.scale_xyz
			var u := Vector3(fit.u_axis_xz[0],0,fit.u_axis_xz[1])
			var v := Vector3(fit.v_axis_xz[0],0,fit.v_axis_xz[1])
			var bounds: Array = reuse.source_bounds
			var translation := Vector3(fit.origin_xz_m[0],fit.bottom_y_m-bounds[1][0]*scale[1],fit.origin_xz_m[1])
			translation += u*(fit.local_center_uv[0]-(bounds[0][0]+bounds[0][1])*.5*scale[0])
			translation += v*(fit.local_center_uv[1]-(bounds[2][0]+bounds[2][1])*.5*scale[2])
			original.transform = Transform3D(Basis(u*scale[0],Vector3.UP*scale[1],v*scale[2]),translation)
			for component in scene.city_visuals.components.values():
				if component.get_parent().name == "sfc": component.visible = false
			await _capture("sfc_native_fit_original_texture")
			# Full-height isolated inspection complements the context comparison.
			scene.city.visible = false
			scene.landmark_visuals.visible = false
			for component in scene.city_visuals.components.values(): component.visible = false
			await _capture("sfc_isolated_native")
			original.queue_free()
			await process_frame
			for component in scene.city_visuals.components.values():
				component.visible = component.get_parent().name == "sfc"
			await _capture("sfc_isolated_modified")
			scene.city.visible = true
			scene.landmark_visuals.visible = true
			for component in scene.city_visuals.components.values(): component.visible = true
		views.append({"id":item.id,"camera":_v(eye),"target":_v(target),"fov":review.fov,"labels_hidden":true})
	scene.city_visuals.show_authored(true)
	review.global_position = Vector3(-120,88,22)
	review.look_at(Vector3(100,13,-112))
	review.make_current()
	await _capture("palace_city_combined")
	views.append({"id":"palace_city_combined","camera":_v(review.global_position),"target":[100,13,-112],"labels_hidden":true})
	scene.rig.camera.make_current()
	await _pose(_point(scene.city.connection.route_xz[0]), scene.starting_yaw)
	await _capture("gate_third_person")
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"task":"L03","visuals":city_observed,"l02_visuals":palace_observed,
		"views":views,"captures":capture_names,"engine":{"version":Engine.get_version_info().string,
		"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"driver":RenderingServer.get_current_rendering_driver_name()}})+"\n")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("L03_VIEWS_DONE count=",views.size())
	scene.queue_free()
	quit(0)
