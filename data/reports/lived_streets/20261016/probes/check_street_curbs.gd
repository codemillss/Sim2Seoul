extends "res://../tests/game/check_jump.gd"
var curbs: Node3D
var source_hashes:={}
var begun:=""
func _initialize() -> void:
	begun=Time.get_datetime_string_from_system()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	Engine.physics_ticks_per_second=60
	create_timer(90.,true,false,true).timeout.connect(_timeout);_run.call_deferred()
func _place(point: Vector3) -> void:
	_keys([]);player.position=point+Vector3.UP*.08;player.velocity=Vector3.ZERO;player.require_neutral_input();await _ticks(10)
func _steer(point: Vector3) -> void:
	var d:=point-player.position;d.y=0
	if d.length()<.01:return
	var camera: Camera3D=fixture.get_node("Camera");camera.position=player.position+Vector3.UP*2;camera.look_at(camera.position+d.normalized(),Vector3.UP)
func _walk_to(target: Vector3,fast := true) -> Dictionary:
	var ticks:=0;var grounded:=0
	_keys(["move_forward","move_fast"] if fast else ["move_forward"])
	while Vector2(player.position.x-target.x,player.position.z-target.z).length()>.17 and ticks<120:
		_steer(target);await _ticks(1);ticks+=1
		if player.is_on_floor():grounded+=1
	_keys([])
	return {"ticks":ticks,"grounded":grounded,"reached":ticks<120}
func _ray(at: Vector3) -> Dictionary:
	var q:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*1.5,at-Vector3.UP*.2,1)
	return fixture.get_world_3d().direct_space_state.intersect_ray(q)
func _run() -> void:
	for p in ["res://scripts/street_curbs.gd","res://assets/authored/street_curbs.json","res://scripts/player/free_roam_player.gd","res://../tests/game/check_jump.gd","/private/tmp/check_street_curbs.gd"]:source_hashes[p]=FileAccess.get_sha256(p)
	_build();player.free_roam_bounds=Rect2(-450,-460,900,920);player.walk_speed_mps=8.4;player.run_speed_mps=21.
	fixture.get_node("Floor").position=Vector3(0,-.1,0);fixture.get_node("Floor").get_child(0).shape.size=Vector3(1000,.2,1000)
	var regions: Array[Rect2]=[player.free_roam_bounds];player.configure_recovery(Vector3(0,.08,0),regions)
	curbs=load("res://scripts/street_curbs.gd").new();fixture.add_child(curbs)
	_check("setup.bounded_beveled_curbs",curbs.setup(fixture.get_node("World"),player,null),{"error":curbs.load_error})
	await _ticks(3)
	_check("geometry.all_16_source_plan_segments_built_in_clear_fixture",curbs.segments.size()==16,{"bodies":curbs.bodies.size(),"segments":curbs.segments.size()})
	var max_top_error:=0.;var cuts_clear:=true
	for segment: Dictionary in curbs.segments:
		var hit:=_ray(segment.top_point);max_top_error=maxf(max_top_error,absf(hit.position.y-.12) if not hit.is_empty() else 999.)
		for point: Vector3 in segment.cut_points:
			hit=_ray(point);cuts_clear=cuts_clear and not hit.is_empty() and absf(hit.position.y)<.003
	_check("geometry.all_16_tops_physically_12cm",max_top_error<.003,{"maximum_error_m":max_top_error})
	_check("geometry.all_32_end_cuts_return_to_Y0",cuts_clear)
	var entry_clear:=true;var entry_queries:=0
	var capsule: CollisionShape3D=player.get_node("CollisionShape");var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule.shape;query.collision_mask=1;query.margin=.001
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/interiors/source_catalog.json"))
	for record: Dictionary in catalog.records:
		for entry: Dictionary in record.entry_candidates:
			for distance in [0.,3.]:
				var point:=Vector3(entry.entrance[0]+entry.outward[0]*distance,.02,entry.entrance[1]+entry.outward[1]*distance)
				query.transform=Transform3D(Basis.IDENTITY,point)*capsule.transform;entry_queries+=1
				entry_clear=entry_clear and fixture.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
	_check("protection.curbs_do_not_occupy_704_entrance_corridors",entry_clear,{"capsule_queries":entry_queries,"buildings":125,"candidates":704})
	var lane_clear:=true;var lane_queries:=0
	var traffic: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/traffic.json"))
	for route: Dictionary in traffic.routes:
		for point: Array in route.xz:
			var hit:=_ray(Vector3(point[0],0,point[1]));lane_queries+=1;lane_clear=lane_clear and not hit.is_empty() and absf(hit.position.y)<.003
	_check("protection.both_original_car_lanes_remain_Y0",lane_clear,{"queries":lane_queries})
	var before: int=player.recoveries
	for segment: Dictionary in curbs.segments:
		var id: String=segment.id;var length: float=segment.length_m
		await _place(curbs.point_on_segment(id,.5))
		var okay:=true;var ticks:=0;var ground:=0
		for index in range(1,int(ceil(length))):
			var result:=await _walk_to(curbs.point_on_segment(id,minf(index,length-.3)));okay=okay and result.reached;ticks+=result.ticks;ground+=result.grounded
		_check(id+".turbo_along_bevels_and_end",okay and player.recoveries==before and ground>=ticks*.85,{"ticks":ticks,"grounded":ground})
		var middle: float=length*.5
		await _place(curbs.point_on_segment(id,middle,-1.2))
		var across:=await _walk_to(curbs.point_on_segment(id,middle,1.2),false)
		var back:=await _walk_to(curbs.point_on_segment(id,middle,-1.2),false)
		_check(id+".walk_over_both_sides_without_vertical_snag",across.reached and back.reached and player.recoveries==before,{"outbound":across,"return":back})
	_keys([])
	var mismatch:=false
	for p in source_hashes:mismatch=mismatch or FileAccess.get_sha256(p)!=source_hashes[p]
	_check("source_hashes_unchanged_during_probe",not mismatch)
	var failed:=0
	for check in checks:
		if not check.passed:failed+=1
	var output:={"task":"street_curbs_isolated","scope":"Production controller, source-bound authored curb plan and isolated metre floor; live combined city geometry remains root validation.","started_at":begun,"finished_at":Time.get_datetime_string_from_system(),"source_hashes":source_hashes,"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"checks":checks,"check_count":checks.size(),"failed":failed,"snapshot":_json(curbs.snapshot()),"result":"PASS" if failed==0 else "FAIL"}
	var f:=FileAccess.open(report_path,FileAccess.WRITE);f.store_string(JSON.stringify(output,"  "));f.close();finished=true;print("STREET_CURBS_QA ",output.result," checks=",checks.size()," failed=",failed);quit(1 if failed else 0)
func _json(value: Variant) -> Variant:
	if value is Vector3:return _v(value)
	if value is Dictionary:
		var d:={}
		for k in value:d[str(k)]=_json(value[k])
		return d
	if value is Array:
		var a:=[]
		for x in value:a.append(_json(x))
		return a
	return value
