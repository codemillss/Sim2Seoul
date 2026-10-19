extends "res://../tests/game/check_street_scene.gd"
func _ticks(count: int) -> void:
	for index: int in range(count):await scene.rig.camera_stepped

func _run() -> void:
	Engine.max_fps=0
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();_settings_path="/private/tmp/dog-detail-"+str(OS.get_process_id())+".json"
	var f:=FileAccess.open(_settings_path,FileAccess.WRITE);f.store_string(JSON.stringify({"schema_version":1,"speed_id":"brisk","free_roam":true}));f.close();scene.exploration_settings_path=_settings_path;scene.quality_settings_path=_settings_path+".quality.json";root.add_child(scene);await _ticks(12)
	var module: Node3D=scene.street_pedestrians
	var source_hashes:={}
	for path: String in ["res://scripts/street_pedestrians.gd","res://scripts/street_dog_model.gd","res://assets/authored/street_pedestrians.json"]:source_hashes[path]=FileAccess.get_sha256(path)
	var rows:=[];var errors:=[];var maximum_step:=0.;var support_samples:=0;var phase_moves:=0;var previous:={};var stride_samples:=[];var previous_feet:={};var planted_drift_max:=0.;var planted_checks:=0;var head_pitch_range:=[0.,0.]
	for group: Dictionary in module.groups:
		if not group.record.dog:continue
		var row: Dictionary=group.members[1];previous[group.id]=row.body.global_position;group["probe_station_min"]=group.station;group["probe_station_max"]=group.station
		rows.append({"id":group.id,"start":row.body.global_position,"length":group.length,"points":group.points,"side":row.side,"start_station":group.station})
	for tick: int in range(6000):
		await _ticks(1)
		for group: Dictionary in module.groups:
			if not group.record.dog:continue
			group.probe_station_min=minf(group.probe_station_min,group.station);group.probe_station_max=maxf(group.probe_station_max,group.station)
			var row: Dictionary=group.members[1];var at: Vector3=row.body.global_position;var step:=at.distance_to(previous[group.id]);previous[group.id]=at;maximum_step=maxf(maximum_step,step)
			if step>.0001:phase_moves+=1
			if not at.is_finite() and errors.size()<12:errors.append({"tick":tick,"id":group.id,"error":"nonfinite"})
			for leg_index: int in range(row.legs.size()):
				var leg: Dictionary=row.legs[leg_index];var key:=String(group.id)+str(leg_index);var at_foot: Vector3=leg.ankle.global_position
				if previous_feet.has(key) and leg.planted and previous_feet[key].planted and step>.0001:
					planted_drift_max=maxf(planted_drift_max,at_foot.distance_to(previous_feet[key].at));planted_checks+=1
				previous_feet[key]={"at":at_foot,"planted":leg.planted}
			head_pitch_range[0]=minf(head_pitch_range[0],row.head.rotation.x);head_pitch_range[1]=maxf(head_pitch_range[1],row.head.rotation.x)
			if tick%30==0:
				support_samples+=1
				if not row.body.is_on_floor() and errors.size()<12:errors.append({"tick":tick,"id":group.id,"error":"not_on_floor"})
				if group.station<-.01 or group.station>group.length+.01:
					if errors.size()<12:errors.append({"tick":tick,"id":group.id,"error":"station_range"})
				if not module._allowed(at,.18) and errors.size()<12:errors.append({"tick":tick,"id":group.id,"error":"permission"})
				if group.leash_blocked and errors.size()<12:errors.append({"tick":tick,"id":group.id,"error":"leash_blocked"})
				if tick<600:stride_samples.append({"tick":tick,"id":group.id,"state":group.state,"phase":row.dog_model.phase,"head":row.head.rotation,"feet":row.legs.map(func(leg: Dictionary)->Dictionary:return {"planted":leg.planted,"paw":leg.paw.global_position,"anchor":leg.anchor,"joint":leg.joint.rotation})})
		if tick%1800==0:print("DOG_PATROL tick=",tick," states=",module.groups.filter(func(group: Dictionary)->bool:return group.record.dog).map(func(group: Dictionary)->Array:return [group.id,group.station,group.turns,group.state]))
		if tick>4800 and module.groups.filter(func(group: Dictionary)->bool:return group.record.dog).all(func(group: Dictionary)->bool:return group.turns>=2):break
	for entry: Dictionary in rows:
		for group: Dictionary in module.groups:
			if entry.id==group.id:entry["station_range_m"]=[group.probe_station_min,group.probe_station_max]
	var state: Dictionary=module.snapshot()
	_check("dogs.actual_full_patrol_two_endpoint_turns",module.groups.filter(func(group: Dictionary)->bool:return group.record.dog).all(func(group: Dictionary)->bool:return group.turns>=2 and group.probe_station_min<.06 and group.probe_station_max>group.length-.06),{"routes":state.routes.filter(func(group: Dictionary)->bool:return group.dog)})
	_check("dogs.two_terrain_supported_bounded_physical_patrols",errors.is_empty() and maximum_step<.04,{"maximum_step_m":maximum_step,"support_samples":support_samples,"errors":errors})
	_check("dogs.distance_driven_four_articulated_planted_and_swing_feet",state.actors.filter(func(row: Dictionary)->bool:return row.kind=="dog").all(func(row: Dictionary)->bool:return row.dog_model.planted_samples>500 and row.dog_model.swing_samples>100 and row.dog_model.maximum_planted_target_error_m<.045 and row.dog_model.paw_center_ground_gap_range_m[0]>=-.012 and row.dog_model.paw_center_ground_gap_range_m[1]<.12),{"dogs":state.actors.filter(func(row: Dictionary)->bool:return row.kind=="dog")})
	_check("dogs.sniff_and_look_pause_then_resume",state.routes.filter(func(group: Dictionary)->bool:return group.dog).all(func(group: Dictionary)->bool:return group.dog_pause_count>=2),{"routes":state.routes.filter(func(group: Dictionary)->bool:return group.dog)})
	_check("dogs.observed_world_planted_feet_and_low_sniff",planted_checks>200 and planted_drift_max<.025 and head_pitch_range[0]<-.85,{"independent_planted_frame_pairs":planted_checks,"maximum_world_paw_step_while_planted_m":planted_drift_max,"head_pitch_range_rad":head_pitch_range})
	var before:={};module.set_running(false);await _ticks(6)
	for row: Dictionary in module.actors:before[row.body.name]={"visual":row.visual.transform,"head":row.head.transform if row.kind=="dog" else null,"tail":row.tail.transform if row.kind=="dog" else null,"feet":row.legs.map(func(leg: Dictionary)->Transform3D:return leg.joint.transform) if row.kind=="dog" else []}
	var phase_before: float=module.elapsed;await _ticks(90)
	_check("dogs.movement_checkbox_still_freezes_all_visual_pose_and_clock",module.elapsed==phase_before and module.actors.all(func(row: Dictionary)->bool:return before[row.body.name].visual==row.visual.transform and (row.kind!="dog" or (before[row.body.name].head==row.head.transform and before[row.body.name].tail==row.tail.transform and before[row.body.name].feet==row.legs.map(func(leg: Dictionary)->Transform3D:return leg.joint.transform)))))
	module.set_running(true);await _ticks(120)
	var failures:=checks.filter(func(check: Dictionary)->bool:return not check.passed).size()
	var report:={"task":"street_dog_detail","result":"PASS" if failures==0 else "FAIL","summary":{"checks":checks.size(),"failed":failures},"checks":checks,"initial":rows,"snapshot":module.snapshot(),"stride_samples":stride_samples,"source_sha256":source_hashes,"scope":"Actual production scene patrol, retained collision/route/source permissions. No actor teleport after initialization. Headless does not accept visual appearance."}
	var out:=FileAccess.open(report_path,FileAccess.WRITE);out.store_string(JSON.stringify(_json(report),"  "));out.close();finished=true;print("DOG_DETAIL ",report.result," checks=",checks.size()," failed=",failures);quit(1 if failures>0 else 0)
