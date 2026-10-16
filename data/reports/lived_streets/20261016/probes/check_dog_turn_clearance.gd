extends "res://../tests/game/check_street_scene.gd"
func _run() -> void:
	var before_hash:=FileAccess.get_sha256("res://scripts/street_pedestrians.gd")
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();_settings_path="/private/tmp/dog-turn-clear-"+str(OS.get_process_id())+".json"
	var f:=FileAccess.open(_settings_path,FileAccess.WRITE);f.store_string(JSON.stringify({"schema_version":1,"speed_id":"brisk","free_roam":true}));f.close();scene.exploration_settings_path=_settings_path;scene.quality_settings_path=_settings_path+".quality.json";root.add_child(scene);await _ticks(12)
	var errors:=[];var queries:=0
	var module: Node3D=scene.street_pedestrians
	for group: Dictionary in module.groups:
		if not group.record.dog:continue
		var row: Dictionary=group.members[1]
		for station in [0.,.5,1.,float(group.length)-1.,float(group.length)-.5,float(group.length)]:
			var support: Dictionary=module._ground(module._at(group,station,row.side));var point: Vector3=support.point
			for angle_index in range(16):
				var yaw:=TAU*float(angle_index)/16.;var q:=PhysicsShapeQueryParameters3D.new();q.shape=row.collider.shape;q.collision_mask=1|32;q.margin=.001;q.transform=Transform3D(Basis(Vector3.UP,yaw),point+Vector3.UP*.24)
				queries+=1;var hits: Array=scene.get_world_3d().direct_space_state.intersect_shape(q,1)
				if not hits.is_empty():errors.append({"group":group.id,"station":station,"angle":yaw,"other":String(hits[0].collider.name)})
	var report:={"task":"dog_turn_clearance_independent","result":"PASS" if errors.is_empty() else "FAIL","queries":queries,"source_sha256":before_hash,"source_unchanged":before_hash==FileAccess.get_sha256("res://scripts/street_pedestrians.gd"),"errors":errors,"scope":"Actual source scene, both dog endpoint regions, all16yawangles; static box collision clearance only, no GPU or actor motion substitution."}
	var out:=FileAccess.open(report_path,FileAccess.WRITE);out.store_string(JSON.stringify(report,"  "));out.close();finished=true;print("DOG_TURN_CLEARANCE ",report.result," queries=",queries," failures=",errors.size());quit(1 if not errors.is_empty() else 0)
