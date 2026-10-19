extends SceneTree
var scene: Node3D
var checks: Array=[]
var observations: Dictionary={}
var out := "/private/tmp/street-infra.json"

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):out=arg.trim_prefix("--report=")
	_run.call_deferred()

func clean(v: Variant) -> Variant:
	if v is Vector3:return [v.x,v.y,v.z]
	if v is Vector2:return [v.x,v.y]
	if v is Dictionary:
		var r: Dictionary={}
		for k in v:r[str(k)]=clean(v[k])
		return r
	if v is Array:
		var r: Array=[]
		for x in v:r.append(clean(x))
		return r
	return v

func check(id: String,ok: bool,data: Dictionary={}) -> void:
	checks.append({"id":id,"passed":ok,"evidence":clean(data)})
	print("INFRA_CHECK ",id," ",ok)

func ticks(n: int) -> void:
	for i in range(n):await physics_frame

func _run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_settings_path=out+".settings.json";scene.quality_settings_path=out+".quality.json"
	root.add_child(scene)
	await ticks(3)
	var module: Node3D=scene.get("street_network_detail")
	check("production_ready",scene.runtime_ok and scene.exploration_error.is_empty() and module!=null and module.loaded,{"error":scene.exploration_error})
	if module==null or not module.loaded:
		if module!=null:observations.failed_snapshot=module.snapshot()
		finish();return
	if scene.menu.visible:scene.toggle_menu()
	scene.set_vehicles_running(false);scene.set_pedestrians_running(false)
	module.set_physics_process(false)
	var snap: Dictionary=module.snapshot();observations.start=snap
	check("actual_split_paint_tin_clearance",snap.paint_mesh_count==2 and snap.paint_faces>5000 and absf(snap.paint_clearance_TIN_min_m-.052)<.001 and absf(snap.paint_clearance_TIN_max_m-.052)<.001,{"faces":snap.paint_faces,"minimum":snap.paint_clearance_TIN_min_m,"maximum":snap.paint_clearance_TIN_max_m,"projection":snap.paint_projection})
	module.elapsed_s=31.;module.advance_signal_time(0);await process_frame;await process_frame
	var glyphs: Array=[];var glyphs_ok:=true
	for row: Dictionary in module.signals:
		if row.kind!="pedestrian":continue
		var label: Label3D=row.countdown;var case: MeshInstance3D=row.head.get_node("PedestrianSignalCase")
		var text: AABB=label.transform*label.get_aabb();var box: AABB=case.mesh.get_aabb()
		var inside: bool=text.size.x>0 and text.position.x>box.position.x and text.end.x<box.end.x and text.position.y>box.position.y and text.end.y<box.end.y and label.position.z>box.end.z and label.position.z<box.end.z+.06
		var one_sided: bool=not label.double_sided and label.billboard==BaseMaterial3D.BILLBOARD_DISABLED and case.material_override.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED
		glyphs_ok=glyphs_ok and inside and one_sided;glyphs.append({"id":row.id,"inside":inside,"one_sided":one_sided,"text_aabb":str(text),"case_aabb":str(box)})
	check("real_signal_heads_and_bounded_lamps",snap.signals.size()>=8 and snap.lamps.size()>=30 and snap.new_collision_count==0 and glyphs.size()==8 and glyphs_ok,{"signals":snap.signals.size(),"lamps":snap.lamps.size(),"skipped":snap.skipped,"actual_glyphs":glyphs})
	var independent_errors: Array=[];var sampled:=0
	for mesh: MeshInstance3D in module.paint_meshes:
		var verts: PackedVector3Array=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i: int in range(0,verts.size(),3):
			var p: Vector3=mesh.to_global((verts[i]+verts[i+1]+verts[i+2])/3.0)
			var h: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*.1,p-Vector3.UP*.2,32))
			if h.is_empty() or absf(p.y-h.position.y-.052)>.001:independent_errors.append({"point":p,"hit":h.get("position",Vector3.INF)})
			sampled+=1
	check("actual_every_paint_face_native_terrain_ray",independent_errors.is_empty() and sampled==snap.paint_faces,{"samples":sampled,"errors":independent_errors.slice(0,20)})
	for row in [[0.0,"green","red"],[24.5,"amber","red"],[28.0,"red","red"],[31.0,"red","green"],[44.5,"red","red"],[46.0,"green","red"]]:
		module.elapsed_s=row[0];module.advance_signal_time(0)
		check("cycle_"+str(row[0]),module.vehicle_signal_state("sejong_marked")==row[1] and module.pedestrian_signal_state("sejong_marked")==row[2],{"vehicle":module.vehicle_signal_state("sejong_marked"),"pedestrian":module.pedestrian_signal_state("sejong_marked")})
	module.elapsed_s=31;module.advance_signal_time(0)
	var vehicle: CharacterBody3D=scene.vehicles[0];var route: Dictionary=scene.traffic.routes[vehicle.get_route_id()]
	var stop: Dictionary=route.conflicts[0]
	var point: Vector3=scene.city.to_global(Vector3(stop.stop_xz[0],0,stop.stop_xz[1]))
	var direction: Vector3=Vector3(route.xz[1][0]-route.xz[0][0],0,route.xz[1][1]-route.xz[0][1]).normalized()
	var result: Dictionary=module.vehicle_stop_distance(route.source_binding.feature_id,point-direction*10,direction,60)
	check("bus_signal_query_real_stop_line",result.required and absf(result.distance_m-12.6)<.05,result)
	module.elapsed_s=0;module.advance_signal_time(0)
	result=module.vehicle_stop_distance(route.source_binding.feature_id,point-direction*10,direction,60)
	check("bus_signal_query_releases_on_green",not result.required,result)
	for profile: String in ["day","evening","night"]:
		module.set_time_profile(profile);module.apply_quality("standard")
		var state: Dictionary=module.snapshot()
		check("actual_warm_lighting_"+profile,state.active_lights<=12 and (state.active_lights==0 if profile=="day" else state.active_lights>0),state)
	module.apply_quality("low");check("low_light_budget",module.snapshot().active_lights<=6,module.snapshot())
	module.set_physics_process(true);var before: float=module.elapsed_s
	paused=true
	for i in range(10):await process_frame
	check("menu_pause_signal_clock",module.elapsed_s==before,{"before":before,"after":module.elapsed_s})
	paused=false;await ticks(5)
	check("menu_resume_signal_clock",module.elapsed_s>before,{"before":before,"after":module.elapsed_s})
	observations.final=module.snapshot()
	finish()

func finish() -> void:
	var ok: bool=not checks.is_empty()
	for row in checks:ok=ok and row.passed
	var f:=FileAccess.open(out,FileAccess.WRITE);f.store_string(JSON.stringify(clean({"schema_version":1,"passed":ok,"headless":DisplayServer.get_name()=="headless","checks":checks,"observations":observations}),"\t"));f.close()
	quit(0 if ok else 1)
