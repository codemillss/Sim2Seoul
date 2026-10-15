extends RefCounted
## Read actual instantiated surfaces, including float32 conversion and parent transforms.
static func inject(scene: Node, fault: String) -> void:
	var overlay: Node3D = scene.get_node("PalaceLandmarks")
	if fault == "roof_hidden":
		for node in overlay.components.values():
			if node.get_meta("feature_role") == "roof": node.visible = false; break
	elif fault == "visual_shift": overlay.components.values()[0].position.x += 2.0
	elif fault == "collision_added": overlay.add_child(StaticBody3D.new())
	elif fault == "gate_obstructed":
		var visual: MeshInstance3D = overlay.components.values()[0]
		var material: Material = visual.mesh.surface_get_material(0)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.0, 1.0, 1.0)
		var route: Array = scene.city.connection.route_xz
		var offset := Vector3((route[1][0]+route[2][0])/2.0, 1.2, (route[1][1]+route[2][1])/2.0)
		var source_arrays: Array = mesh.surface_get_arrays(0)
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		for index in source_arrays[Mesh.ARRAY_INDEX]:
			vertices.append(source_arrays[Mesh.ARRAY_VERTEX][index] + offset)
			normals.append(source_arrays[Mesh.ARRAY_NORMAL][index])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		var replacement := ArrayMesh.new()
		replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		replacement.surface_set_material(0, material)
		visual.mesh = replacement
	elif fault == "original_restored":
		for id in overlay.bundle.hidden_mesh_ids:
			if scene.city.bodies[id].collision_layer != 0: scene.city.source_nodes[id].visible = true; break
	elif fault != "normal": push_error("Unknown L02 visual fault")

static func collect(scene: Node) -> Dictionary:
	var overlay: Node3D = scene.get_node("PalaceLandmarks")
	var rows := []
	for id in overlay.components:
		var visual: MeshInstance3D = overlay.components[id]
		var vertices := []
		var normals := []
		var arrays: Array = visual.mesh.surface_get_arrays(0)
		for p in arrays[Mesh.ARRAY_VERTEX]: vertices.append_array([p.x, p.y, p.z])
		for p in arrays[Mesh.ARRAY_NORMAL]: normals.append_array([p.x, p.y, p.z])
		var material: StandardMaterial3D = visual.mesh.surface_get_material(0)
		rows.append({"id": id, "vertices": vertices, "normals": normals,
			"landmark_id": visual.get_parent().name, "feature_role": visual.get_meta("feature_role"),
			"visible": visual.is_visible_in_tree(), "identity": visual.global_transform.is_equal_approx(Transform3D.IDENTITY),
			"material_rgb": [material.albedo_color.r, material.albedo_color.g, material.albedo_color.b],
			"cull_mode": material.cull_mode, "primitive": visual.mesh.surface_get_primitive_type(0)})
	var hidden_sources := {}
	for id in overlay.bundle.hidden_mesh_ids: hidden_sources[id] = scene.city.source_nodes[id].visible
	var hidden_fragments := {}
	for id in overlay.bundle.hidden_fragment_ids: hidden_fragments[id] = scene.city.fragments[id].get_parent().visible
	var all_sources := {}
	for id in scene.city.source_nodes: all_sources[id] = scene.city.source_nodes[id].visible
	var all_fragments := {}
	for id in scene.city.fragments: all_fragments[id] = scene.city.fragments[id].get_parent().visible
	var pending: Array[Node] = [overlay]
	var collision_objects := 0
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is CollisionObject3D or node is CollisionShape3D: collision_objects += 1
		pending.append_array(node.get_children())
	return {"loaded": overlay.loaded, "visible": overlay.visible, "components": rows,
		"collision_objects": collision_objects, "hidden_sources": hidden_sources, "hidden_fragments": hidden_fragments,
		"all_source_visibility": all_sources, "all_fragment_visibility": all_fragments,
		"bundle_sha256": FileAccess.get_sha256("res://data/generated/palace_landmarks.json"),
		"scope": "Actual L02 visible surfaces; source bodies retained, new traversal/interiors not granted"}
