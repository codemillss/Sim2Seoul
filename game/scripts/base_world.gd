extends Node3D
## Display geometry only. Source coordinates and permissions are never changed here.
var loaded_geometry_count := 0
var triangle_count := 0
var source_nodes := {}

func populate(world: Dictionary) -> void:
	for role in ["Ground","Buildings","Routes","Barriers"]:
		for child in get_node(role).get_children():
			child.free()
	loaded_geometry_count = 0
	triangle_count = 0
	source_nodes.clear()
	var materials := {}
	for key in world.display.palette:
		var rgb: Array = world.display.palette[key]
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(rgb[0],rgb[1],rgb[2])
		material.roughness = 0.92
		material.cull_mode = BaseMaterial3D.CULL_BACK
		materials[key] = material
	for entry in world.meshes:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		for i in range(0,entry.vertices.size(),3):
			vertices.append(Vector3(entry.vertices[i],entry.vertices[i+1],entry.vertices[i+2]))
			normals.append(Vector3(entry.normals[i],entry.normals[i+1],entry.normals[i+2]))
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(0,materials[entry.material])
		var node := MeshInstance3D.new()
		node.name = entry.id.replace(":","_")
		node.mesh = mesh
		node.set_meta("source",entry.metadata)
		node.set_meta("geometry_id",entry.id)
		get_node(entry.role).add_child(node)
		source_nodes[entry.id] = node
		loaded_geometry_count += 1
		triangle_count += vertices.size()/3
