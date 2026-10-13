extends SceneTree
## Record actual engine objects; external Python checker owns acceptance.
var variant := "normal"
var output_path := ""
var capture_prefix := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):variant = argument.trim_prefix("--case=")
		elif argument.begins_with("--result="):output_path = argument.trim_prefix("--result=")
		elif argument.begins_with("--capture-prefix="):capture_prefix = argument.trim_prefix("--capture-prefix=")
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/tests/scale_view.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	if not scene.runtime_state.get("ok",false) or not scene.scale_state.get("ok",false):
		print("E04_PROBE_ERROR "+JSON.stringify({"runtime":scene.runtime_state.get("error"),"scale":scene.scale_state.get("error")}))
		quit(1)
		return
	match variant:
		"world_scaled":scene.get_node("World").scale = Vector3(1.1,1.1,1.1)
		"world_moved":scene.get_node("World").position = Vector3(5,0,8)
		"world_rotated":scene.get_node("World").rotation_degrees.y = 15
		"world_z_flipped":scene.get_node("World").scale.z = -1
		"world_y_scaled":scene.get_node("World").scale.y = 2
		"anchors_moved":scene.get_node("Anchors").position = Vector3(5,0,0)
		"controls_scaled":scene.get_node("Controls").scale = Vector3(1.1,1.1,1.1)
		"root_moved":scene.position = Vector3(4,0,3)
		"ruler_shortened":
			var line: MeshInstance3D = scene.ruler_nodes.grid_east_10m
			var arrays: Array = line.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			vertices[1] *= 0.9
			arrays[Mesh.ARRAY_VERTEX] = vertices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays)
			line.mesh = mesh
		"cube_wrong_size":scene.cube_mesh.mesh.size = Vector3(10,5,10)
		"normal":pass
		_:push_error("Unknown E04 probe variant");quit(1);return
	scene.set_view("map")
	await process_frame
	var record := {"task":"E04","case":variant,"measurements":scene.measure(),
		"engine":Engine.get_version_info().string,"display_server":DisplayServer.get_name(),
		"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),
		"scope":"actual engine measurement, scored separately; not walking or independent survey"}
	if not capture_prefix.is_empty() and DisplayServer.get_name()!="headless":
		var captures := []
		for key in ["map","axes","oblique"]:
			scene.set_view(key)
			await create_timer(0.8).timeout
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var error := image.save_png(capture_prefix+"_"+key+".png")
			if error!=OK:push_error("Cannot save E04 image");quit(1);return
			captures.append({"view":key,"width":image.get_width(),"height":image.get_height(),
				"camera":scene.measure().camera})
		record["captures"] = captures
		scene.toggle_menu()
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(capture_prefix+"_menu.png")!=OK:quit(1);return
		record["menu_pauses_geometry"] = paused and not scene.get_node("World").can_process() and not scene.get_node("Controls").can_process()
		scene.toggle_menu()
	if not output_path.is_empty():
		var file := FileAccess.open(output_path,FileAccess.WRITE)
		if file==null:push_error("Cannot write E04 probe");quit(1);return
		file.store_string(JSON.stringify(record,"\t")+"\n")
	print("E04_PROBE "+JSON.stringify(record))
	scene.queue_free()
	quit(0)
