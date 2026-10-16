extends "res://../tests/game/check_jump.gd"
var hill: Node3D
var source_hashes := {}
var started_at := ""
var samples := []
func _place_hill(station: float) -> void:
	_keys([]);player.position=hill.point_at_station(station)+Vector3.UP*.08;player.velocity=Vector3.ZERO;player.require_neutral_input()
	await _ticks(15)
	_check("placement.floor_"+str(station),player.is_on_floor(),{"position":_v(player.position)})
func _steer(target: Vector3) -> void:
	var direction:=target-player.position;direction.y=0.
	if direction.length()<.01:return
	var camera: Camera3D=fixture.get_node("Camera");camera.position=player.position+Vector3.UP*2.;camera.look_at(camera.position+direction.normalized(),Vector3.UP)
func _follow(title: String,reverse: bool,fast: bool) -> void:
	var start:=89. if reverse else 1.
	await _place_hill(start)
	var before: int=player.recoveries;var floor_ticks:=0;var ticks:=0;var max_lateral:=0.;var count:=0
	var stations:=range(88,0,-1) if reverse else range(2,90)
	_keys(["move_forward","move_fast"] if fast else ["move_forward"])
	for s in stations:
		var target: Vector3=hill.point_at_station(float(s));var guard:=0
		while Vector2(player.position.x-target.x,player.position.z-target.z).length()>.45 and guard<180:
			_steer(target);await _ticks(1);guard+=1;ticks+=1
			if player.is_on_floor():floor_ticks+=1
			if ticks%12==0:samples.append({"trial":title,"station":s,"position":_v(player.position),"floor":player.is_on_floor(),"velocity":_v(player.velocity)})
		if guard>=180:break
		count+=1
	_keys([]);await _ticks(10)
	_check(title,count==88 and player.recoveries==before and floor_ticks>=ticks*.9,{"reached_waypoints":count,"physics_ticks":ticks,"grounded_ticks":floor_ticks,"recovery_delta":player.recoveries-before,"end":_v(player.position)})
func _run() -> void:
	started_at=Time.get_datetime_string_from_system()
	for path in ["res://scripts/museum_approach.gd","res://assets/authored/museum_approach.json","res://scripts/player/free_roam_player.gd","res://resources/world_geometry/world.json","res://../tests/game/check_jump.gd","/private/tmp/check_museum_authored.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	_build();player.free_roam_bounds=Rect2(-400,-100,250,300);player.walk_speed_mps=8.4;player.run_speed_mps=21.
	var floor_body: StaticBody3D=fixture.get_node("Floor");floor_body.position=Vector3(-230,-.1,35);floor_body.get_child(0).shape.size=Vector3(220,.2,220)
	var regions: Array[Rect2]=[Rect2(-400,-100,250,300)];player.configure_recovery(Vector3(-245,.08,-10),regions)
	hill=load("res://scripts/museum_approach.gd").new();fixture.add_child(hill)
	_check("module.setup",hill.setup(fixture.get_node("World"),player,null),{"error":hill.load_error})
	await _ticks(4)
	var max_error:=0.;var misses:=0;var occupied:=0
	for s in range(91):
		var at: Vector3=hill.point_at_station(s)
		var query:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*4.,at-Vector3.UP*.5,1)
		var hit: Dictionary=fixture.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():misses+=1
		else:max_error=maxf(max_error,absf(hit.position.y-at.y))
	_check("geometry.source_centreline_supported_at_all_91_stations",misses==0 and max_error<.015,{"misses":misses,"maximum_error_m":max_error})
	var q:=PhysicsShapeQueryParameters3D.new();q.shape=SphereShape3D.new();q.shape.radius=.1;q.collision_mask=1;q.transform=Transform3D(Basis.IDENTITY,hill.point_at_station(42)-Vector3.UP*1.)
	_check("geometry.closed_ground_blocks_the_volume_below_crest",not fixture.get_world_3d().direct_space_state.intersect_shape(q,1).is_empty())
	await _follow("walk_up_and_down_8_4_mps",false,false)
	await _follow("run_up_and_down_21_mps",false,true)
	await _follow("reverse_run_21_mps",true,true)
	await _place_hill(42.)
	var terrace: Vector3=hill.snapshot().anchors[4].foot_point
	var before: int=player.recoveries;var terrace_ticks:=0;var terrace_floor:=0
	_keys(["move_forward"])
	while Vector2(player.position.x-terrace.x,player.position.z-terrace.z).length()>.3 and terrace_ticks<180:
		_steer(terrace);await _ticks(1);terrace_ticks+=1
		if player.is_on_floor():terrace_floor+=1
	_keys([]);await _ticks(5)
	_check("terrace.level_walk_connection",terrace_ticks<180 and terrace_floor>=terrace_ticks*.9 and absf(player.position.y-3.)<.02 and player.recoveries==before,{"ticks":terrace_ticks,"grounded_ticks":terrace_floor,"position":_v(player.position)})
	var path_target: Vector3=hill.point_at_station(42.)
	var return_ticks:=0;var return_floor:=0
	_keys(["move_forward"])
	while Vector2(player.position.x-path_target.x,player.position.z-path_target.z).length()>.3 and return_ticks<180:
		_steer(path_target);await _ticks(1);return_ticks+=1
		if player.is_on_floor():return_floor+=1
	_keys([]);await _ticks(5)
	_check("terrace.level_return_to_path",return_ticks<180 and return_floor>=return_ticks*.9 and absf(player.position.y-3.)<.02 and player.recoveries==before,{"ticks":return_ticks,"grounded_ticks":return_floor,"position":_v(player.position)})
	await _place_hill(42.);var boosts:=0;var peak: float=player.position.y
	for index in range(6):
		_keys(["jump"]);await _ticks(1)
		if player.velocity.y>7.:boosts+=1
		_keys([]);await _ticks(7);peak=maxf(peak,player.position.y)
	_check("jump.six_fresh_presses_from_hill",boosts==6 and peak>8. and player.recoveries==before,{"boosts":boosts,"peak_y":peak,"recovery_delta":player.recoveries-before})
	_keys([]);await _ticks(160)
	_check("jump.lands_back_on_crest",player.is_on_floor() and absf(player.position.y-3.)<.02,{"position":_v(player.position)})
	var after_hashes:={}
	for path in source_hashes:after_hashes[path]=FileAccess.get_sha256(path)
	_check("sources_unchanged_during_execution",after_hashes==source_hashes,{"after_hashes":after_hashes})
	var report:={"started_at":started_at,"finished_at":Time.get_datetime_string_from_system(),"task":"museum_authored_hill_isolated","source_hashes":source_hashes,"scope":"production controller on isolated metre floor and authored hill; combined source city remains separate root QA","engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"snapshot":_json(hill.snapshot()),"checks":checks,"samples":samples}
	var failed:=0
	for check in checks:
		if not check.passed:failed+=1
	report["failed"]=failed;report["result"]="PASS" if failed==0 else "FAIL";report["check_count"]=checks.size()
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close();finished=true
	print("MUSEUM_AUTHORED_QA ",report.result," checks=",checks.size()," failed=",failed);quit(1 if failed else 0)
func _json(value: Variant) -> Variant:
	if value is Vector3:return _v(value)
	if value is Vector2:return [value.x,value.y]
	if value is Transform3D:return {"origin":_v(value.origin),"basis":[_v(value.basis.x),_v(value.basis.y),_v(value.basis.z)]}
	if value is Dictionary:
		var d:={}
		for key in value:d[str(key)]=_json(value[key])
		return d
	if value is Array:
		var a:=[]
		for item in value:a.append(_json(item))
		return a
	return value
