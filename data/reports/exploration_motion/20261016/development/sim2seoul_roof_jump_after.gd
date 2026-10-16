extends "res://../tests/game/check_rooftops.gd"
var flights: Array=[]
func _run() -> void:
	source_hashes={"player":FileAccess.get_sha256("res://scripts/player/free_roam_player.gd"),"roof":FileAccess.get_sha256("res://scripts/rooftop_space.gd")}
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json";root.add_child(scene)
	visit=scene.interior_visit;await _ticks(25)
	var passed := true
	for id: String in IDS:
		if not visit.select_building(id):passed=false;continue
		await _pose(visit.entrance_world_position);_e(true);_e(false);await _ticks(12)
		if not visit.active or not await _ride_to(int(visit.current_spec.floor_count),"real_roof_ride"):passed=false;continue
		var roof: Node3D=visit.rooftop
		var recoveries: int=scene.player.recoveries
		var start: Vector3=scene.player.global_position
		var edges := []
		var accepted := 0
		var peak := start.y
		for index in range(6):
			_keys();await _ticks(2)
			var vy: float=scene.player.velocity.y
			Input.action_press("jump");await _ticks(1)
			if scene.player.velocity.y>7.4:accepted+=1
			edges.append({"edge":index+1,"before_vy":vy,"position":scene.player.global_position,"after_vy":scene.player.velocity.y,"air_remaining":scene.player.air_jumps_remaining(),"air_count":scene.player.air_jump_count(),"recoveries":scene.player.recoveries-recoveries})
			await _ticks(20);peak=maxf(peak,scene.player.global_position.y)
		_keys();await _ticks(320)
		var row := {"id":id,"profile":roof.profile_id,"start":start,"edges":edges,"peak_above_deck_m":peak-roof.deck_height_y,"recoveries":scene.player.recoveries-recoveries,"grounded_after":scene.player.is_on_floor(),"unlimited_api":scene.player.air_jumps_remaining()==-1 and scene.player.has_unlimited_air_jumps(),"no_position_or_velocity_injection":true}
		flights.append(row)
		if accepted!=6 or peak-roof.deck_height_y<=10.0 or scene.player.recoveries!=recoveries or not scene.player.is_on_floor():passed=false
		visit.return_to_world_spawn();await _ticks(10)
	var report:={"task":"roof_jump_after_actual_lifts","result":"PASS" if passed else "FAIL","source_sha256":source_hashes,"display":DisplayServer.get_name(),"flights":flights,"scope":"Three actual production E entries and roof lift arrivals. Six fresh jump action edges per roof use unchanged production physics with no per-step pose, velocity or private jump-count writes. Starts only use explicit outdoor entrance scenario positions. All roofs must rise beyond10m and land without recovery."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(_json(report),"\t"));file.close();print(JSON.stringify(_json(report)));quit(0 if passed else 1)
