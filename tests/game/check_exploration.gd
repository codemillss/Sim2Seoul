extends SceneTree
## Targeted actual-input checks. Every scenario placement is an explicit test fixture.
const ACTIONS := ["move_left","move_right","move_forward","move_backward","move_fast","jump","interact"]
var report_path := ""
var settings_path := ""
var quality_path := ""
var scene
var checks: Array = []
var trials: Array = []
var placements: Array = []
var restarts: Array = []
var finished := false
var physics_seconds := 0.0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	if report_path.is_empty() or not report_path.is_absolute_path():
		push_error("check_exploration requires --report=<absolute path>")
		print("EXPLORATION_TEST FAIL missing_report_path");quit(1);return
	settings_path=report_path+".settings.json"
	quality_path=report_path+".quality.json"
	# Isolate only this test process from physical keys; production bindings stay intact.
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action)
		Input.action_release(action)
	Engine.physics_ticks_per_second=60
	create_timer(90.,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _check(name: String, passed: bool, evidence: Dictionary = {}) -> void:
	checks.append({"name":name,"passed":passed,"evidence":evidence})
	if not passed:push_warning("EXPLORATION_CHECK_FAIL "+name)

func _v(point: Vector3) -> Array:return [point.x,point.y,point.z]

func _keys(actions: Array) -> void:
	for action in ACTIONS:Input.action_release(action)
	for action in actions:Input.action_press(action)

func _world_keys(direction: Vector3, fast: bool) -> void:
	_keys([])
	var forward: Vector3=-scene.rig.camera.global_basis.z
	forward.y=0.;forward=forward.normalized()
	var right: Vector3=forward.cross(Vector3.UP).normalized()
	var sideways: float=direction.dot(right)
	var ahead: float=direction.dot(forward)
	if sideways>0.00001:Input.action_press("move_right",sideways)
	elif sideways< -0.00001:Input.action_press("move_left",-sideways)
	if ahead>0.00001:Input.action_press("move_forward",ahead)
	elif ahead< -0.00001:Input.action_press("move_backward",-ahead)
	if fast:Input.action_press("move_fast")

func _ticks(count: int) -> void:
	for index in range(count):
		var delta: float=await scene.rig.camera_stepped
		physics_seconds+=delta

func _fresh(label: String) -> bool:
	_keys([]);paused=false
	if is_instance_valid(scene):
		scene.queue_free();scene=null
		await process_frame
		await process_frame
	scene=load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_settings_path=settings_path
	scene.quality_settings_path=quality_path
	root.add_child(scene)
	if not scene.runtime_ok:
		_check("startup."+label,false,{"runtime_ok":scene.runtime_ok})
		return false
	await _ticks(20)
	restarts.append({"name":label,"state":scene.exploration_snapshot()})
	return true

func _clear_at(point: Vector3) -> bool:
	if not scene.player._inside(point):return false
	var query:=PhysicsShapeQueryParameters3D.new()
	var shape_node: CollisionShape3D=scene.player.get_node("CollisionShape")
	query.shape=shape_node.shape
	query.transform=Transform3D(Basis.IDENTITY,point)*shape_node.transform
	query.collision_mask=scene.player.collision_mask
	query.exclude=[scene.player.get_rid()]
	return scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _pose(name: String, requested: Vector3, allow_nearby := false) -> bool:
	_keys([])
	var point:=requested
	var clear:=_clear_at(point)
	if not clear and allow_nearby:
		for offset in [Vector3(.5,0,0),Vector3(-.5,0,0),Vector3(0,0,.5),Vector3(0,0,-.5),Vector3(1,0,0),Vector3(-1,0,0)]:
			if _clear_at(requested+offset):point=requested+offset;clear=true;break
	placements.append({"name":name,"kind":"test_only_teleport_before_trial","requested":_v(requested),"placed":_v(point),"clear":clear})
	if not clear:
		_check("placement."+name,false,placements[-1]);return false
	scene.player.global_transform=Transform3D(Basis.IDENTITY,point)
	scene.player.velocity=Vector3.ZERO
	scene.player.require_neutral_input()
	scene.rig.yaw=0.;scene.rig.pitch=deg_to_rad(-15.)
	scene.rig.requested_distance=4.5
	await _ticks(15)
	_check("placement."+name+".settled",scene.player.is_on_floor() and scene.player.global_position.distance_to(point)<.15,{"position":_v(scene.player.global_position),"floor":scene.player.is_on_floor()})
	return true

func _motion(name: String, direction: Vector3, seconds: float, fast: bool, diagonal_actions := false) -> Dictionary:
	var start: Vector3=scene.player.global_position
	var prior: Vector3=start
	var recoveries: int=scene.player.recoveries
	var floor_ticks:=0
	var outside_ticks:=0
	var outside_old_ticks:=0
	var max_step:=0.
	var path:=0.
	var max_speed:=0.
	var elapsed:=0.
	var tick_count:=0
	var contacts: Dictionary={}
	var positions: Array=[]
	var bounds: Rect2=scene.player.free_roam_bounds
	if diagonal_actions:
		_keys(["move_forward","move_right","move_fast"] if fast else ["move_forward","move_right"])
	else:_world_keys(direction,fast)
	while elapsed<seconds-0.000001:
		var delta: float=await scene.rig.camera_stepped
		elapsed+=delta;physics_seconds+=delta;tick_count+=1
		var point: Vector3=scene.player.global_position
		var step: float=Vector2(point.x-prior.x,point.z-prior.z).length()
		path+=step;max_step=maxf(max_step,step)
		max_speed=maxf(max_speed,Vector2(scene.player.velocity.x,scene.player.velocity.z).length())
		if scene.player.is_on_floor():floor_ticks+=1
		if not bounds.has_point(Vector2(point.x,point.z)):outside_ticks+=1
		if not scene.city.movement_contains(Vector2(point.x,point.z)):outside_old_ticks+=1
		for index in range(scene.player.get_slide_collision_count()):
			var body=scene.player.get_slide_collision(index).get_collider()
			if body is Node:contacts[str(body.get_meta("geometry_id",body.name))]=true
		if tick_count==1 or tick_count%6==0:positions.append(_v(point))
		prior=point
	_keys([])
	var ending: Vector3=scene.player.global_position
	var row:={"name":name,"seconds":elapsed,"ticks":tick_count,"start":_v(start),"end":_v(ending),"direction":_v(direction),"fast":fast,"diagonal_actions":diagonal_actions,"distance_m":Vector2(ending.x-start.x,ending.z-start.z).length(),"path_m":path,"max_step_m":max_step,"max_speed_mps":max_speed,"floor_ticks":floor_ticks,"outside_bounds_ticks":outside_ticks,"outside_original_walk_ticks":outside_old_ticks,"recoveries":scene.player.recoveries-recoveries,"contacts":contacts.keys(),"positions_10hz":positions}
	trials.append(row)
	return row

func _motion_safe(row: Dictionary) -> bool:
	return row.floor_ticks==row.ticks and row.outside_bounds_ticks==0 and row.recoveries==0

func _speed_case(id: String, fast: bool, expected_speed: float, diagonal := false) -> void:
	scene.set_speed_profile(id)
	var name: String="speed_"+id+("_run" if fast else "_walk")+("_diagonal" if diagonal else "")
	if not await _pose(name,Vector3(82,.08,10)):return
	var direction: Vector3=Vector3(1,0,-1).normalized() if diagonal else Vector3.FORWARD
	var row: Dictionary=await _motion(name,direction,1.5,fast,diagonal)
	var expected: float=expected_speed*row.seconds
	_check(name,_motion_safe(row) and absf(row.distance_m-expected)<.05 and absf(row.path_m-expected)<.05 and row.max_speed_mps<=expected_speed+.005,{"expected_distance_m":expected,"observation":row})

func _actor_state() -> Array:
	var rows: Array=[]
	for body in scene.pedestrians+scene.vehicles:
		rows.append({"name":str(body.name),"id":body.get_instance_id(),"position":_v(body.global_position),"mask":body.collision_mask,"layer":body.collision_layer,"state":body.snapshot()})
	return rows

func _find_obstacle(kind: String) -> Dictionary:
	var space: PhysicsDirectSpaceState3D=scene.get_world_3d().direct_space_state
	for origin in [Vector3(82,.85,10),Vector3(80,.85,-190),Vector3(173,.85,-48),Vector3(100,.85,-80),Vector3(0,.85,0)]:
		for index in range(24):
			var angle: float=TAU*index/24.
			var direction:=Vector3(cos(angle),0,sin(angle))
			var query:=PhysicsRayQueryParameters3D.create(origin,origin+direction*150.,1,[scene.player.get_rid()])
			var hit: Dictionary=space.intersect_ray(query)
			if hit.is_empty():continue
			var body: Node=hit.collider
			var identity: String=str(body.get_meta("geometry_id",body.name))
			if not (identity.contains(":building") if kind=="building" else identity.contains(":barrier") or identity.begins_with("W01_gate_side")):continue
			var normal: Vector3=hit.normal
			if absf(normal.y)>.1:continue
			var point: Vector3=hit.position+normal*1.0
			point.y=.08
			if not _clear_at(point):continue
			return {"id":identity,"point":point,"surface":hit.position,"normal":normal}
	return {}

func _obstacle_case(kind: String) -> void:
	var found:=_find_obstacle(kind)
	_check("obstacle."+kind+".source_found",not found.is_empty())
	if found.is_empty():return
	if not await _pose("push_"+kind,found.point):return
	var row: Dictionary=await _motion("push_"+kind,-found.normal,.7,true)
	var ending:=Vector3(row.end[0],row.end[1],row.end[2])
	var clearance: float=(ending-found.surface).dot(found.normal)
	_check("obstacle."+kind+".physical_stop",_motion_safe(row) and row.contacts.has(found.id) and clearance>=.28 and row.distance_m<1.,{"source_id":found.id,"surface":_v(found.surface),"normal":_v(found.normal),"clearance_m":clearance,"observation":row})

func _edge_cases() -> void:
	var bounds: Rect2=scene.player.free_roam_bounds
	var center: Vector2=bounds.get_center()
	var edges: Array=[
		["west",Vector3(bounds.position.x+1.,.08,center.y),Vector3.LEFT],
		["east",Vector3(bounds.end.x-1.,.08,center.y),Vector3.RIGHT],
		["north",Vector3(center.x,.08,bounds.position.y+1.),Vector3.FORWARD],
		["south",Vector3(center.x,.08,bounds.end.y-1.),Vector3.BACK],
	]
	for spec in edges:
		if not await _pose("edge_"+spec[0],spec[1],true):continue
		var row: Dictionary=await _motion("edge_"+spec[0],spec[2],.7,true)
		_check("bounds."+spec[0]+".cannot_exit",_motion_safe(row) and row.distance_m<2.,{"bounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"blocked_before_requested_distance":row.distance_m<row.seconds*7.-.5,"observation":row})

func _save_text() -> String:
	return FileAccess.get_file_as_string(settings_path) if FileAccess.file_exists(settings_path) else ""

func _ui_cases() -> void:
	if not await _pose("menu_outside_original",Vector3(82,.08,10)):return
	var point: Vector3=scene.player.global_position
	var tick_before: int=scene.player.recoveries
	scene.toggle_menu()
	for viewport_size in [Vector2i(1152,720),Vector2i(960,600)]:
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_size=Vector2i.ZERO
		root.size=viewport_size
		for frame in range(4):await process_frame
		scene._layout_v0()
		await process_frame
		var rect: Rect2=scene.menu.get_global_rect()
		var view: Vector2=root.get_visible_rect().size
		_check("menu.fits_"+str(viewport_size.x)+"x"+str(viewport_size.y),rect.position.x>=0 and rect.position.y>=0 and rect.end.x<=view.x+.1 and rect.end.y<=view.y+.1 and scene.exploration_menu_scroll.follow_focus,{"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"viewport":[view.x,view.y],"scroll_follow_focus":scene.exploration_menu_scroll.follow_focus})
	_keys(["move_forward","move_fast"])
	await create_timer(.15,true,false,true).timeout
	_check("menu.paused_input",paused and scene.menu.visible and not scene.input_router.gameplay_enabled and scene.player.global_position.distance_to(point)<.001,{"before":_v(point),"after":_v(scene.player.global_position)})
	scene.speed_option.select(0);scene.speed_option.item_selected.emit(0)
	_check("ui.real_speed_signal",scene.speed_id=="realistic" and scene.player.walk_speed_mps==1.4 and scene.player.run_speed_mps==3.5,{"saved":_save_text()})
	scene.speed_option.select(2);scene.speed_option.item_selected.emit(2)
	scene.free_roam_switch.set_pressed_no_signal(false);scene.free_roam_switch.toggled.emit(false)
	var saved=JSON.parse_string(_save_text())
	_check("ui.free_roam_off_recovers_and_saves",not scene.free_roam_enabled and not scene.player.free_roam_enabled and scene.city.movement_contains(Vector2(scene.player.global_position.x,scene.player.global_position.z)) and scene.player.recoveries==tick_before+1 and scene.player.last_recovery_reason=="free_roam_disabled" and saved is Dictionary and saved.size()==3 and saved.get("schema_version")==1 and saved.get("speed_id")=="fast" and saved.get("free_roam")==false,{"saved":saved,"position":_v(scene.player.global_position),"recovery_delta":scene.player.recoveries-tick_before})
	scene.toggle_menu()
	var recovered: Vector3=scene.player.global_position
	await _ticks(8)
	_check("menu.resume_requires_neutral",not paused and not scene.menu.visible and scene.player.input_latched and scene.player.global_position.distance_to(recovered)<.1,{"start":_v(recovered),"end":_v(scene.player.global_position)})
	_keys([]);await _ticks(3)
	_check("menu.neutral_release",not scene.player.input_latched)

func _run() -> void:
	for path in [settings_path,quality_path]:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	if not await _fresh("fresh_defaults"):_finish();return
	_check("defaults.brisk_and_free",scene.speed_id=="brisk" and scene.free_roam_enabled and scene.player.free_roam_enabled and scene.player.walk_speed_mps==2.24 and scene.player.run_speed_mps==5.6,scene.exploration_snapshot())
	_check("support.player_and_camera_masks",(scene.player.collision_mask&32)!=0 and (scene.rig.arm.collision_mask&32)!=0,{"player_mask":scene.player.collision_mask,"camera_mask":scene.rig.arm.collision_mask})
	var actors_before:=_actor_state()
	await _speed_case("brisk",false,2.24)
	await _speed_case("brisk",true,5.6)
	await _speed_case("fast",true,7.)
	await _speed_case("fast",true,7.,true)
	for point in [Vector3(82,.08,10),Vector3(80,.08,-190),Vector3(173,.08,-48)]:
		var name: String="expanded_area_"+str(int(point.x))+"_"+str(int(point.z))
		if not await _pose(name,point,true):continue
		var row: Dictionary=await _motion(name,Vector3.FORWARD,1.5,true)
		_check(name,_motion_safe(row) and row.outside_original_walk_ticks>0 and row.distance_m>.2,row)
	await _edge_cases()
	await _obstacle_case("building")
	await _obstacle_case("barrier")
	await _ticks(240)
	var actors_after:=_actor_state()
	_check("actors.inventory_and_support_isolation",scene.pedestrians.size()==2 and scene.vehicles.size()==6 and actors_after.size()==8 and actors_before.size()==8 and actors_after.all(func(row):return (int(row.mask)&32)==0),{"before":actors_before,"after":actors_after})
	for ending in actors_after:
		var initial: Dictionary={}
		for row in actors_before:
			if row.id==ending.id:initial=row;break
		var distance: float=float(ending.state.get("actual_distance_m",0.))-float(initial.get("state",{}).get("actual_distance_m",0.))
		_check("actors."+ending.name+".actual_motion",not initial.is_empty() and distance>.1 and ending.state.get("on_floor",false),{"actual_distance_delta_m":distance,"start":initial,"end":ending})
	await _ui_cases()
	if not await _fresh("saved_settings"):_finish();return
	_check("settings.restore_saved_fast_strict",scene.speed_id=="fast" and not scene.free_roam_enabled and scene.player.walk_speed_mps==2.8 and scene.player.run_speed_mps==7. and not scene.exploration_settings_recovered,scene.exploration_snapshot())
	var file:=FileAccess.open(settings_path,FileAccess.WRITE)
	if file==null:
		_check("settings.corrupt_fixture_written",false);_finish();return
	file.store_string("{broken JSON\n");file.close()
	if not await _fresh("malformed_settings"):_finish();return
	_check("settings.malformed_json_recovers_defaults",scene.speed_id=="brisk" and scene.free_roam_enabled and scene.exploration_settings_recovered,scene.exploration_snapshot())
	file=FileAccess.open(settings_path,FileAccess.WRITE)
	if file==null:
		_check("settings.invalid_types_fixture_written",false);_finish();return
	file.store_string("{\"schema_version\":1,\"speed_id\":false,\"free_roam\":\"yes\"}\n");file.close()
	if not await _fresh("invalid_types_settings"):_finish();return
	_check("settings.invalid_types_recover_defaults",scene.speed_id=="brisk" and scene.free_roam_enabled and scene.exploration_settings_recovered and scene.player.walk_speed_mps==2.24 and scene.player.run_speed_mps==5.6,scene.exploration_snapshot())
	_check("speed.reject_unknown",not scene.set_speed_profile("unsupported") and scene.speed_id=="brisk")
	_finish()

func _timeout() -> void:
	if finished:return
	_check("bounded_runtime",false,{"timeout_real_seconds":90})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_keys([]);paused=false
	var failures:=0
	for check in checks:
		if not check.passed:failures+=1
	var result:={"schema_version":1,"task":"EXPLORATION","passed":failures==0,"failed_checks":failures,"checks":checks,"physics_seconds":physics_seconds,"trials":trials,"placements":placements,"restarts":restarts,"engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"physics_hz":Engine.physics_ticks_per_second},"scope":"Targeted real Input.action_press and move_and_slide trials after explicit test-only placements. Per-tick player floor/bounds/recovery observations, source-ray-selected obstacle contacts, actor masks/motion, UI pause/signals and settings restarts. No continuous full-route, native human-input, packaging or performance acceptance."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:
		push_error("Cannot write exploration report: "+report_path)
		print("EXPLORATION_TEST FAIL report_write");quit(1);return
	file.store_string(JSON.stringify(result)+"\n");file.close()
	print("EXPLORATION_TEST ","PASS" if failures==0 else "FAIL"," checks=",checks.size()," failed=",failures," physics_seconds=",physics_seconds)
	quit(0 if failures==0 else 1)
