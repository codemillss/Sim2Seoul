extends SceneTree
## Compare every generated scalar against the actual ArrayMesh vertex handed to Godot.
var checks: Array[Dictionary] = []
var capture_prefix := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			capture_prefix = argument.trim_prefix("--capture-prefix=")
	_run.call_deferred()

func _check(name: String, passed: bool, detail = null) -> void:
	checks.append({"name":name,"passed":passed,"detail":detail})

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	_check("runtime_loaded",scene.runtime_state.get("ok",false))
	if not scene.runtime_state.get("ok",false):
		quit(1)
		return
	var world: Dictionary = scene.runtime_state.world
	var actual_world = scene.get_node("World")
	_check("all_meshes_loaded",actual_world.loaded_geometry_count==world.counts.meshes)
	var max_error := 0.0
	var vertex_count := 0
	var triangles := 0
	var transforms_ok: bool = actual_world.transform==Transform3D.IDENTITY
	var backfaces_ok := true
	var normals_ok := true
	for entry in world.meshes:
		var node: MeshInstance3D = actual_world.source_nodes[entry.id]
		transforms_ok = transforms_ok and node.global_transform==Transform3D.IDENTITY
		var arrays := node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		backfaces_ok = backfaces_ok and node.mesh.surface_get_material(0).cull_mode==BaseMaterial3D.CULL_BACK
		vertex_count += vertices.size()
		triangles += vertices.size()/3
		for i in range(vertices.size()):
			for axis in range(3):
				max_error = max(max_error,abs(float(vertices[i][axis])-float(entry.vertices[i*3+axis])))
		for i in range(0,vertices.size(),3):
			var front := -(vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).normalized()
			normals_ok = normals_ok and front.dot(normals[i])>0.9999
	_check("identity_world_transforms",transforms_ok)
	_check("source_to_engine_max_scalar_error_below_0_0002m",max_error<=0.0002,max_error)
	_check("triangle_count_matches",triangles==world.counts.triangles,triangles)
	_check("explicit_normals_match_engine_clockwise_faces",normals_ok)
	_check("backface_culling_enabled",backfaces_ok)
	_check("no_collision_or_player_added",scene.find_children("*","CollisionObject3D",true,false).is_empty() and scene.get_node("Actors/PlayerSlot").get_child_count()==0)
	_check("scope_boundary_spawn_permissions_pending",world.scope.playable_boundary==null and world.scope.spawn==null and not world.scope.walkability_verified)
	for key in ["overview","top","palace"]:
		scene._set_view(key)
		await process_frame
		_check("view_"+key,scene.selected_view==key and scene.get_node("Presentation/OverviewCamera").projection==Camera3D.PROJECTION_ORTHOGONAL)
		if not capture_prefix.is_empty() and DisplayServer.get_name()!="headless":
			await create_timer(0.8).timeout
			await RenderingServer.frame_post_draw
			var result := root.get_texture().get_image().save_png(capture_prefix+"_"+key+".png")
			_check("capture_"+key,result==OK)
	if not capture_prefix.is_empty() and DisplayServer.get_name()!="headless":
		scene.set_menu_open(true)
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png(capture_prefix+"_menu.png")
		_check("capture_menu",result==OK and scene.menu_panel.visible and not scene.view_bar.visible)
		scene.set_menu_open(false)
	var failed := checks.filter(func(item): return not item.passed)
	var record := {"task":"E03","checks":checks,"passed":checks.size()-failed.size(),"failed":failed.size(),
		"vertices":vertex_count,"engine":Engine.get_version_info().string,"display_server":DisplayServer.get_name(),
		"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),
		"max_source_to_engine_scalar_error_m":max_error,"scope":"geometry transmission and display, not independent survey/scale scene/walk/performance"}
	if not capture_prefix.is_empty():
		var file := FileAccess.open(capture_prefix+".json",FileAccess.WRITE)
		file.store_string(JSON.stringify(record,"\t")+"\n")
	print("E03_WORLD_TEST_RESULT "+JSON.stringify(record))
	scene.queue_free()
	quit(0 if failed.is_empty() else 1)
