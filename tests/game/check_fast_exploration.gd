extends SceneTree
## Full production scene and controller. Only scenario starts are test teleports.
const ACTIONS := ["move_left","move_right","move_forward","move_backward","move_fast","jump","interact","toggle_menu"]
const PROFILES := [["rapid",5.6,14.0],["turbo",8.4,21.0]]
var report_path := ""
var settings_path := ""
var quality_path := ""
var scene
var checks: Array = []
var trials: Array = []
var placements: Array = []
var restarts: Array = []
var source_hashes := {}
var physics_seconds := 0.0
var finished := false

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path = argument.trim_prefix("--report=")
	if report_path.is_empty() or not report_path.is_absolute_path():
		push_error("check_fast_exploration requires --report=<absolute path>");quit(1);return
	settings_path = report_path+".settings.json"
	quality_path = report_path+".quality.json"
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	Engine.physics_ticks_per_second = 60
	create_timer(90.,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _check(title: String, passed: bool, evidence: Dictionary = {}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":evidence})
	if not passed:push_warning("FAST_EXPLORATION_CHECK_FAIL "+title)

func _v(point: Vector3) -> Array:return [point.x,point.y,point.z]

func _keys(actions: Array = []) -> void:
	for action in ACTIONS:Input.action_release(action)
	for action in actions:Input.action_press(action)

func _world_keys(direction: Vector3, fast := true, strength := 1.0) -> void:
	_keys()
	var forward: Vector3 = -scene.rig.camera.global_basis.z
	forward.y = 0.;forward = forward.normalized()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var sideways := direction.dot(right)*strength
	var ahead := direction.dot(forward)*strength
	if sideways>.00001:Input.action_press("move_right",sideways)
	elif sideways<-.00001:Input.action_press("move_left",-sideways)
	if ahead>.00001:Input.action_press("move_forward",ahead)
	elif ahead<-.00001:Input.action_press("move_backward",-ahead)
	if fast:Input.action_press("move_fast")

func _ticks(count: int) -> void:
	for index in range(count):
		var delta: float = await scene.rig.camera_stepped
		physics_seconds += delta

func _fresh(title: String) -> bool:
	_keys();paused = false
	if is_instance_valid(scene):
		scene.queue_free();scene = null
		await process_frame;await process_frame
	scene = load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_settings_path = settings_path
	scene.quality_settings_path = quality_path
	root.add_child(scene)
	if not scene.runtime_ok:
		_check("startup."+title,false,{"runtime_ok":scene.runtime_ok});return false
	await _ticks(20)
	restarts.append({"name":title,"state":scene.exploration_snapshot()})
	return true

func _clear_at(point: Vector3) -> bool:
	if not scene.player._inside(point):return false
	var node: CollisionShape3D = scene.player.get_node("CollisionShape")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = node.shape
	query.transform = Transform3D(Basis.IDENTITY,point)*node.transform
	query.collision_mask = scene.player.collision_mask
	query.exclude = [scene.player.get_rid()]
	return scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _supported_at(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.4,point-Vector3.UP*.4,scene.player.collision_mask,[scene.player.get_rid()])
	var hit: Dictionary = scene.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.normal.dot(Vector3.UP)>.99 and absf(hit.position.y-(point.y-.08))<.02

func _clear_path(point: Vector3, direction: Vector3, length: float) -> bool:
	for index in range(int(ceil(length/.5))+1):
		var at := point+direction*minf(length,float(index)*.5)
		if not _clear_at(at) or not _supported_at(at):return false
	return true

func _pose(title: String, point: Vector3) -> bool:
	_keys()
	var clear := _clear_at(point) and _supported_at(point)
	var fixture := {"name":title,"kind":"explicit_test_only_start_teleport","requested":_v(point),"capsule_clear":clear}
	placements.append(fixture)
	if not clear:_check("placement."+title,false,fixture);return false
	scene.player.global_transform = Transform3D(Basis.IDENTITY,point)
	scene.player.velocity = Vector3.ZERO
	scene.player.require_neutral_input();scene.player.reset_physics_interpolation()
	scene.rig.yaw = 0.;scene.rig.pitch = deg_to_rad(-15.)
	scene.rig.requested_distance = 4.5
	await _ticks(15)
	fixture["settled"] = _v(scene.player.global_position)
	fixture["on_floor"] = scene.player.is_on_floor()
	var settled: bool = scene.player.is_on_floor() and not scene.player.input_latched and scene.player.global_position.distance_to(point)<.15
	if not settled:_check("placement."+title,false,fixture)
	return settled

func _motion(title: String, direction: Vector3, seconds: float, fast := true, diagonal := false) -> Dictionary:
	var start: Vector3 = scene.player.global_position
	var prior := start
	var recoveries: int = scene.player.recoveries
	var stops: int = scene.player.boundary_stops
	var elapsed := 0.0
	var floor_ticks := 0
	var outside_ticks := 0
	var private_ticks := 0
	var count := 0
	var path := 0.0
	var max_step := 0.0
	var max_speed := 0.0
	var contacts := {}
	var positions: Array = []
	if diagonal:_keys(["move_forward","move_right","move_fast"] if fast else ["move_forward","move_right"])
	else:_world_keys(direction,fast)
	while elapsed<seconds-.000001:
		var delta: float = await scene.rig.camera_stepped
		elapsed += delta;physics_seconds += delta;count += 1
		var point: Vector3 = scene.player.global_position
		var step := Vector2(point.x-prior.x,point.z-prior.z).length()
		path += step;max_step = maxf(max_step,step)
		max_speed = maxf(max_speed,Vector2(scene.player.velocity.x,scene.player.velocity.z).length())
		if scene.player.is_on_floor():floor_ticks += 1
		if not scene.player._inside(point):outside_ticks += 1
		if not scene.player.interior_active and scene.city._contains(Vector2(point.x,point.z),scene.city.private_cache):private_ticks += 1
		for index in range(scene.player.get_slide_collision_count()):
			var body = scene.player.get_slide_collision(index).get_collider()
			if body is Node:contacts[str(body.get_meta("geometry_id",body.name))] = true
		if count==1 or count%6==0:positions.append(_v(point))
		prior = point
	_keys()
	var ending: Vector3 = scene.player.global_position
	var row := {"name":title,"start":_v(start),"end":_v(ending),"seconds":elapsed,"ticks":count,"fast":fast,"diagonal_actions":diagonal,"distance_m":Vector2(ending.x-start.x,ending.z-start.z).length(),"path_m":path,"max_step_m":max_step,"max_speed_mps":max_speed,"floor_ticks":floor_ticks,"outside_allowed_ticks":outside_ticks,"private_ticks":private_ticks,"recoveries":scene.player.recoveries-recoveries,"boundary_stops":scene.player.boundary_stops-stops,"contacts":contacts.keys(),"positions_10hz":positions}
	trials.append(row)
	return row

func _safe(row: Dictionary) -> bool:
	return row.floor_ticks==row.ticks and row.outside_allowed_ticks==0 and row.private_ticks==0 and row.recoveries==0 and row.max_step_m<=21./60.+.006

func _open_start(diagonal := false) -> Dictionary:
	var direction := Vector3(1,0,-1).normalized() if diagonal else Vector3.FORWARD
	# Existing outdoor exploration fixtures; each entire capsule route and floor
	# are queried against this live production scene before selecting a start.
	for point in [Vector3(100,.08,20),Vector3(173,.08,-48),Vector3(80,.08,-190),Vector3(100,.08,-80),Vector3(82,.08,10),Vector3(0,.08,0)]:
		if _clear_path(point,direction,21.):return {"point":point,"direction":direction}
	return {}

func _speed_case(id: String, fast: bool, speed: float, diagonal := false) -> void:
	var title := id+(".run" if fast else ".walk")+(".diagonal" if diagonal else "")
	var route := _open_start(diagonal)
	if route.is_empty():_check(title,false,{"reason":"no capsule-clear supported 21m fixture"});return
	if not scene.set_speed_profile(id):_check(title,false,{"reason":"profile rejected"});return
	if not await _pose(title,route.point):return
	var row := await _motion(title,route.direction,1.,fast,diagonal)
	var expected: float = speed*row.seconds
	_check(title,_safe(row) and absf(row.distance_m-expected)<.05 and absf(row.path_m-expected)<.05 and absf(row.max_speed_mps-speed)<.005,{"expected_distance_m":expected,"observation":row})

func _find_wall(kind: String) -> Dictionary:
	for origin in [Vector3(82,.85,10),Vector3(80,.85,-190),Vector3(173,.85,-48),Vector3(100,.85,-80),Vector3(0,.85,0)]:
		for index in range(36):
			var angle := TAU*index/36.
			var direction := Vector3(cos(angle),0,sin(angle))
			var query := PhysicsRayQueryParameters3D.create(origin,origin+direction*150.,1,[scene.player.get_rid()])
			var hit: Dictionary = scene.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty():continue
			var body: Node = hit.collider
			var identity := str(body.get_meta("geometry_id",body.name))
			if not (identity.contains(":building") if kind=="building" else identity.contains(":barrier") or identity.begins_with("W01_gate_side")):continue
			var normal: Vector3 = hit.normal
			if absf(normal.y)>.1:continue
			var point: Vector3 = hit.position+normal*3.
			point.y = .08
			if _clear_path(point,-normal,2.5):return {"id":identity,"point":point,"surface":hit.position,"normal":normal}
	return {}

func _wall_case(kind: String) -> void:
	var found := _find_wall(kind)
	if found.is_empty():_check("collision."+kind,false,{"reason":"no source wall fixture"});return
	if not await _pose("collision."+kind,found.point):return
	var row := await _motion("collision."+kind,-found.normal,.8)
	var clearance: float = (Vector3(row.end[0],row.end[1],row.end[2])-found.surface).dot(found.normal)
	# The source palace barrier and the retained W01 wall occupy the same plane;
	# the capsule can contact either while the source ray selects the other.
	var physical_contact: bool = row.contacts.has(found.id) or (kind=="barrier" and row.contacts.has("W01_palace_wall"))
	_check("collision."+kind,_safe(row) and physical_contact and row.max_speed_mps>20.99 and row.distance_m>2. and row.distance_m<3. and clearance>=.28,{"source_id":found.id,"accepted_retained_alias":"W01_palace_wall" if kind=="barrier" else "","surface":_v(found.surface),"normal":_v(found.normal),"clearance_m":clearance,"observation":row})

func _find_private_edge() -> Dictionary:
	for polygon in scene.city.private_cache:
		for ring in polygon:
			for index in range(ring.size()-1):
				var a: Vector2 = ring[index]
				var b: Vector2 = ring[index+1]
				if a.distance_to(b)<4.:continue
				var middle := (a+b)*.5
				var tangent := (b-a).normalized()
				for sign_value in [-1.,1.]:
					var outward: Vector2 = Vector2(-tangent.y,tangent.x)*sign_value
					if not scene.city._contains(middle-outward*.8,scene.city.private_cache):continue
					var point := Vector3(middle.x+outward.x*1.5,.08,middle.y+outward.y*1.5)
					var direction := Vector3(-outward.x,0,-outward.y)
					if not _clear_path(point,direction,.95):continue
					return {"point":point,"direction":direction,"edge_a":[a.x,a.y],"edge_b":[b.x,b.y],"midpoint":[middle.x,middle.y],"outward":[outward.x,outward.y]}
	return {}

func _private_case() -> void:
	var edge := _find_private_edge()
	if edge.is_empty():_check("boundary.private",false,{"reason":"no capsule-clear retained private-edge fixture"});return
	if not await _pose("boundary.private",edge.point):return
	var row := await _motion("boundary.private",edge.direction,.6)
	var ending := Vector2(row.end[0],row.end[2])
	var a := Vector2(edge.edge_a[0],edge.edge_a[1])
	var b := Vector2(edge.edge_b[0],edge.edge_b[1])
	var clearance := ending.distance_to(Geometry2D.get_closest_point_to_segment(ending,a,b))
	_check("boundary.private",_safe(row) and (row.boundary_stops>0 or row.contacts.size()>1) and row.max_speed_mps>20.99 and row.distance_m>.5 and row.distance_m<1.2 and clearance>=.399,{"source_edge":edge,"edge_clearance_m":clearance,"observation":row})

func _map_edges() -> void:
	var bounds: Rect2 = scene.player.free_roam_bounds
	var center := bounds.get_center()
	for spec in [["west",Vector3(bounds.position.x+1.,.08,center.y),Vector3.LEFT],["east",Vector3(bounds.end.x-1.,.08,center.y),Vector3.RIGHT],["north",Vector3(center.x,.08,bounds.position.y+1.),Vector3.FORWARD],["south",Vector3(center.x,.08,bounds.end.y-1.),Vector3.BACK]]:
		var point: Vector3 = spec[1]
		var tangent: Vector3 = Vector3.BACK if absf(spec[2].x)>.5 else Vector3.RIGHT
		var found := false
		for offset in [0.,25.,-25.,50.,-50.,100.,-100.]:
			if _clear_path(point+tangent*offset,spec[2],.5):point += tangent*offset;found = true;break
		if not found:_check("boundary."+spec[0],false,{"reason":"no supported edge fixture"});continue
		if not await _pose("boundary."+spec[0],point):continue
		var row := await _motion("boundary."+spec[0],spec[2],.6)
		_check("boundary."+spec[0],_safe(row) and row.boundary_stops>0 and row.distance_m>.2 and row.distance_m<.7,{"bounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"requested_distance_m":21.*row.seconds,"observation":row})

func _menu_and_reload(id: String, expected_speed: float) -> void:
	var route := _open_start()
	if route.is_empty():_check("menu."+id,false);return
	if not await _pose("menu."+id,route.point):return
	_keys(["move_forward","move_fast"])
	await _ticks(3)
	scene.toggle_menu()
	var before: Vector3 = scene.player.global_position
	var index: int = scene.SPEED_IDS.find(id)
	scene.speed_option.select(index);scene.speed_option.item_selected.emit(index)
	await create_timer(.06,true,false,true).timeout
	var saved = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	_check("menu."+id+".held_keys_paused_and_saved",paused and scene.menu.visible and not scene.input_router.gameplay_enabled and scene.player.global_position.distance_to(before)<.001 and scene.speed_id==id and saved is Dictionary and saved.size()==3 and saved.get("schema_version")==1 and saved.get("speed_id")==id and saved.get("free_roam")==true,{"before":_v(before),"after":_v(scene.player.global_position),"saved":saved,"selected_index":index})
	scene.toggle_menu();await _ticks(8)
	_check("menu."+id+".resume_requires_W_Shift_release",not paused and scene.player.input_latched and scene.player.global_position.distance_to(before)<.02,{"before":_v(before),"after":_v(scene.player.global_position)})
	_keys();await _ticks(3)
	var row := await _motion("menu."+id+".neutral_then_run",Vector3.FORWARD,.25)
	_check("menu."+id+".neutral_then_run",not scene.player.input_latched and _safe(row) and absf(row.distance_m-expected_speed*row.seconds)<.04,row)
	if not await _fresh("saved_"+id):return
	var selected: int = scene.speed_option.selected
	if not await _pose("reload."+id,route.point):return
	row = await _motion("reload."+id,Vector3.FORWARD,.25)
	_check("settings."+id+".restart_restores_actual_speed",scene.speed_id==id and not scene.exploration_settings_recovered and selected==index and scene.exploration_settings_path==settings_path and _safe(row) and absf(row.distance_m-expected_speed*row.seconds)<.04,{"snapshot":scene.exploration_snapshot(),"selected_index":selected,"observation":row})

func _library_cases() -> void:
	var visit = scene.interior_visit
	if not visit.select_building(visit.LIBRARY_ID):_check("library.entry",false);return
	if not await _pose("library.outside",visit.entrance_world_position):return
	_keys(["interact"]);await _ticks(4);_keys();await _ticks(8)
	_check("library.entry",visit.active and scene.player.interior_active and scene.player.is_on_floor(),visit.snapshot())
	if not visit.active:return
	var room = visit.room
	if await _pose("library.floor",room.floor_spawn(0)):
		var row := await _motion("library.floor_run",Vector3.FORWARD,.5)
		_check("library.floor_run",_safe(row) and absf(row.distance_m-21.*row.seconds)<.05,row)
	var wall = room.get_node("FrontWall")
	var point: Vector3 = room.to_global(Vector3(0,.08,room.depth*.5-2.))
	if await _pose("library.wall",point):
		var row := await _motion("library.wall_run",Vector3.BACK,.7)
		var clearance: float = room.global_position.z+room.depth*.5-row.end[2]
		_check("library.solid_wall_and_bounds_no_tunnel",_safe(row) and wall.collision_layer==1 and row.max_speed_mps>20.99 and row.distance_m<2. and clearance>=.299 and (row.boundary_stops>0 or row.contacts.has("EXP04_interior_FrontWall")),{"wall_id":"EXP04_interior_FrontWall","clearance_m":clearance,"observation":row})
	var path: Array = room.stair_path(0,true)
	if path.size()<6:_check("library.stairs",false,{"reason":"no production stair route"});return
	if not await _pose("library.stairs_start",path[0]):return
	var recoveries: int = scene.player.recoveries
	var start: Vector3 = scene.player.global_position
	var samples := 0
	var floor_samples := 0
	var outside := 0
	var max_speed := 0.0
	var completed := true
	var failed_target := -1
	for target_index in range(1,path.size()):
		var reached := false
		for attempt in range(120):
			var offset: Vector3 = path[target_index]-scene.player.global_position
			var flat := Vector3(offset.x,0,offset.z)
			if flat.length()<.08 and absf(offset.y)<.3:reached = true;break
			_world_keys(flat.normalized(),true,minf(1.,flat.length()/(21./60.)))
			await _ticks(1);samples += 1
			max_speed = maxf(max_speed,Vector2(scene.player.velocity.x,scene.player.velocity.z).length())
			if scene.player.is_on_floor():floor_samples += 1
			if not scene.player._inside(scene.player.global_position):outside += 1
			if scene.player.recoveries!=recoveries:break
		if not reached:completed = false;failed_target = target_index;break
	_keys();await _ticks(8)
	_check("library.turbo_real_stair_ascent",completed and samples>10 and max_speed>20.99 and outside==0 and scene.player.recoveries==recoveries and scene.player.is_on_floor() and absf(scene.player.global_position.y-room.floor_spawn(1).y)<.2,{"start":_v(start),"end":_v(scene.player.global_position),"samples":samples,"grounded_samples":floor_samples,"max_horizontal_velocity_mps":max_speed,"outside_allowed_samples":outside,"completed":completed,"failed_target":failed_target,"recoveries":scene.player.recoveries-recoveries,"input":"run held; full strength except final waypoint fractions; no midroute teleport"})

func _run() -> void:
	for path in ["res://scripts/explore_walk.gd","res://scripts/player/free_roam_player.gd","res://scripts/player/public_player.gd","res://scripts/player/palace_player.gd","res://scripts/interior_visit.gd","res://scripts/building_interior_space.gd","res://scenes/world/explore_walk.tscn","res://../tests/game/check_fast_exploration.gd"]:source_hashes[path] = FileAccess.get_sha256(path)
	for path in [settings_path,quality_path]:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	if not await _fresh("defaults"):_finish();return
	_check("startup.original_defaults_retained",scene.speed_id=="brisk" and scene.free_roam_enabled and not scene.exploration_settings_recovered,scene.exploration_snapshot())
	var labels: Array = []
	for index in range(scene.speed_option.item_count):labels.append(scene.speed_option.get_item_text(index))
	_check("menu.old_choices_and_new_choices_reachable",scene.speed_option.item_count==5 and labels[0]=="현실 속도" and labels[1]=="빠르게" and labels[2]=="아주 빠르게" and labels[3].begins_with("쾌속") and labels[4].begins_with("초고속"),{"labels":labels})
	for profile in PROFILES:
		await _speed_case(profile[0],false,profile[1])
		await _speed_case(profile[0],true,profile[2])
		await _speed_case(profile[0],true,profile[2],true)
	scene.set_speed_profile("turbo")
	await _ticks(3)
	await _wall_case("building")
	await _wall_case("barrier")
	await _private_case()
	await _map_edges()
	for profile in PROFILES:await _menu_and_reload(profile[0],profile[2])
	await _library_cases()
	_finish()

func _timeout() -> void:
	if finished:return
	_check("bounded_runtime",false,{"timeout_real_seconds":90});_finish()

func _finish() -> void:
	if finished:return
	finished = true;_keys();paused = false
	var failed := 0
	for check in checks:
		if not check.passed:failed += 1
	var result := {"schema_version":1,"task":"fast_exploration","passed":failed==0,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"trials":trials,"placements":placements,"restarts":restarts,"physics_seconds":physics_seconds,"source_sha256_at_startup":source_hashes,"engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"physics_hz":Engine.physics_ticks_per_second},"isolated_files":{"exploration_settings":settings_path,"quality_settings":quality_path},"scope":"Full production exploration scene. Actual Input.action_press and move_and_slide observations at 60Hz after explicit, capsule-clear and floor-supported scenario placements. Source-selected exterior walls, retained private polygon and four map edges; held movement during menu changes; isolated saved-setting restarts; library floor, wall and continuous stair ascent. Headless output is no GPU, native-human-input, performance, packaging or surveyed-access acceptance."}
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Could not write fast exploration report");quit(1);return
	file.store_string(JSON.stringify(result,"\t")+"\n");file.close()
	print("FAST_EXPLORATION_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed," physics_seconds=",physics_seconds)
	quit(0 if failed==0 else 1)
