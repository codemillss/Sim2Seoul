extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _vector(p: Vector3) -> Array:return [p.x,p.y,p.z]
func _run() -> void:
	var output:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--result="):output=arg.trim_prefix("--result=")
	var scene=load("res://scenes/tests/collision_test.tscn").instantiate()
	root.add_child(scene)
	if not scene.runtime_state.ok:push_error(scene.runtime_state.error);quit(1);return
	for i in range(35):await physics_frame
	scene.toggle_menu()
	# Invoke the actual connected menu button signals, not only set_mode directly.
	var buttons=scene.menu.get_child(0)
	buttons.get_children().filter(func(b):return b is Button and b.text=="서울 충돌 배치 보기")[0].pressed.emit()
	await physics_frame
	await process_frame
	var city:={"mode":scene.mode,"paused":paused,"mouse_mode":Input.mouse_mode,"input_enabled":scene.input_router.gameplay_enabled,"rig_input":scene.rig.input_enabled,"player_physics":scene.player.is_physics_processing(),"city_layers":scene.city.bodies.values().all(func(b):return b.collision_layer==1 and b.collision_mask==14),"fixture_layers":scene.get_node("Fixtures").get_children().all(func(b):return b.collision_layer==0 and b.collision_mask==0)}
	var m: Dictionary=scene.runtime_state.world.meshes.filter(func(x):return x.id=="temporary_support")[0]
	var p:=Vector3.ZERO
	for j in range(0,9,3):p+=Vector3(m.vertices[j],m.vertices[j+1],m.vertices[j+2])/3.0
	var excluded: Array[RID]=[scene.player.get_rid()]
	for id in scene.city.bodies:
		if id!="temporary_support":excluded.append(scene.city.bodies[id].get_rid())
	var ray:=PhysicsRayQueryParameters3D.create(p+Vector3.UP,p-Vector3.UP,1,excluded)
	var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(ray)
	var ground:={"from":_vector(p+Vector3.UP),"to":_vector(p-Vector3.UP),"hit":not hit.is_empty(),"id":hit.collider.get_meta("geometry_id","") if not hit.is_empty() else "","position":_vector(hit.position) if not hit.is_empty() else [],"normal":_vector(hit.normal) if not hit.is_empty() else [],"scope":"Selected engineering support-plane ray, no physical terrain/permission/spawn acceptance"}
	scene.toggle_menu()
	buttons.get_children().filter(func(b):return b is Button and b.text=="시험장으로 돌아가기")[0].pressed.emit()
	for i in range(35):await physics_frame
	var fixture:={"mode":scene.mode,"paused":paused,"mouse_mode":Input.mouse_mode,"input_enabled":scene.input_router.gameplay_enabled,"rig_input":scene.rig.input_enabled,"player_physics":scene.player.is_physics_processing(),"floor":scene.player.is_on_floor(),"position":_vector(scene.player.global_position),"spawn_valid":scene.player.spawn_valid,"camera_active":scene.rig.camera.current,"city_layers":scene.city.bodies.values().all(func(b):return b.collision_layer==0 and b.collision_mask==0),"fixture_layers":scene.get_node("Fixtures").get_children().all(func(b):return b.collision_layer==1 and b.collision_mask==14)}
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:push_error("P04 mode output missing");quit(1);return
	file.store_string(JSON.stringify({"task":"P04","city_button":city,"fixture_button":fixture,"city_ground":ground,"display":DisplayServer.get_name(),"scope":"Automatic actual menu-button signals and fixture recovery; headless mouse mode is intent only"})+"\n")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	scene.queue_free()
	quit()
