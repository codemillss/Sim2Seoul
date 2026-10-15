extends SceneTree
## Import the unmodified CC0 asset through Godot's real glTF importer.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2: args[pair[0]] = pair[1]
	var source: String = args["--source"]
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	var started := Time.get_ticks_usec()
	var error := document.append_from_file(source, state, 64)
	if error != OK: push_error("Native glTF import failed: " + str(error)); quit(1); return
	var imported := document.generate_scene(state)
	if imported == null: push_error("Native glTF scene missing"); quit(1); return
	root.add_child(imported)
	var surfaces := []
	var pending: Array[Node] = [imported]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if not node is MeshInstance3D: continue
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices := []
			var normals := []
			var uv := []
			var colors := []
			var material: StandardMaterial3D = node.mesh.surface_get_material(surface)
			var palette: Image = material.albedo_texture.get_image()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for index in indices:
				var point: Vector3 = node.global_transform * arrays[Mesh.ARRAY_VERTEX][index]
				var normal: Vector3 = (node.global_basis * arrays[Mesh.ARRAY_NORMAL][index]).normalized()
				var texcoord: Vector2 = arrays[Mesh.ARRAY_TEX_UV][index]
				var color := palette.get_pixel(clampi(int(texcoord.x * palette.get_width()), 0, palette.get_width()-1), clampi(int(texcoord.y * palette.get_height()), 0, palette.get_height()-1))
				vertices.append_array([point.x, point.y, point.z])
				normals.append_array([normal.x, normal.y, normal.z])
				uv.append_array([texcoord.x, texcoord.y])
				colors.append_array([color.r, color.g, color.b])
			surfaces.append({"name": node.name, "vertices": vertices, "normals": normals, "uv": uv, "sampled_rgb": colors,
				"source_vertex_count": arrays[Mesh.ARRAY_VERTEX].size(), "indices": indices.size(), "material": material.resource_name,
				"texture_size": [palette.get_width(), palette.get_height()]})
	var result := {"task": "L03", "source_sha256": FileAccess.get_sha256(source), "engine": Engine.get_version_info().string,
		"actual_native_import": true, "elapsed_import_and_extract_usec": Time.get_ticks_usec()-started, "surfaces": surfaces,
		"scope": "Native importer and texture sampling; source units are not surveyed metres; no collision generated"}
	var file := FileAccess.open(args["--output"], FileAccess.WRITE)
	file.store_string(JSON.stringify(result) + "\n")
	print("L03_NATIVE_IMPORT_OK surfaces=", surfaces.size())
	imported.queue_free()
	quit(0)
