extends "res://../tests/game/check_street_scene.gd"
func _run() -> void:
	for path in ["res://scripts/street_curbs.gd","res://assets/authored/street_curbs.json","res://scripts/explore_walk.gd","res://scripts/street_life.gd","res://scripts/museum_approach.gd","res://../tests/game/check_street_scene.gd","/private/tmp/check_street_curbs_city.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();_settings_path="/private/tmp/street-curbs-city-"+str(OS.get_process_id())+".json"
	var initial:=FileAccess.open(_settings_path,FileAccess.WRITE);initial.store_string(JSON.stringify({"schema_version":1,"speed_id":"brisk","free_roam":true}));initial.close()
	scene.exploration_settings_path=_settings_path;scene.quality_settings_path=_settings_path+".quality.json";root.add_child(scene);await _ticks(12)
	_check("startup.actual_production_EXP14_city_ready",scene.runtime_ok,{"error":scene.exploration_error})
	if not scene.runtime_ok:quit(1);return
	if scene.menu.visible:scene.toggle_menu();await _ticks(3)
	var before:=_inventory();var curbs: Node3D=load("res://scripts/street_curbs.gd").new();scene.add_child(curbs)
	_check("setup.actual_city_with_existing_props",curbs.setup(scene.city,scene.player,scene.rig),{"error":curbs.load_error})
	await _ticks(3)
	_check("source.all_original_city_body_shapes_and_transforms_retained",_inventory()==before,{"source_body_inventory_count":before.size()})
	var baseline: Dictionary=curbs.snapshot();var max_error:=0.;var clear:=true;var queries:=0
	for segment: Dictionary in curbs.segments:
		var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(segment.top_point+Vector3.UP,segment.top_point-Vector3.UP*.3,1|32))
		max_error=maxf(max_error,absf(hit.position.y-.12) if not hit.is_empty() else 999.)
		clear=clear and _supported_clear(segment.foot_point);queries+=1
	_check("geometry.actual_city_tops_and_player_capsules_clear",queries>0 and clear and max_error<.003,{"tops_queried":queries,"maximum_top_error_m":max_error})
	var library_point: Vector3=scene.photo_civic_detail.entrance_world_position;library_point.y=.08
	_check("protection.custom_photo_library_entrance_still_supported_clear",_supported_clear(library_point),{"point":library_point})
	if not curbs.segments.is_empty():
		var target: Dictionary=curbs.segments[0];var id: String=target.id;var at: Vector3=target.top_point;curbs.free();await _ticks(2)
		var blocker:=_blocker("ExplicitExistingParkedProp",at)
		curbs=load("res://scripts/street_curbs.gd").new();scene.add_child(curbs)
		var ready: bool=curbs.setup(scene.city,scene.player,scene.rig);var rejected:=false
		for row: Dictionary in curbs.skipped:
			if row.id==id:rejected=true
		_check("preflight.rejects_a_new_physical_prop_before_same_frame_build",ready and rejected,{"blocked_segment":id,"skipped":curbs.skipped})
		blocker.free()
	_check("source.original_city_inventory_unchanged_after_rebuild",_inventory()==before)
	var changed:=false
	for path in source_hashes:changed=changed or FileAccess.get_sha256(path)!=source_hashes[path]
	_check("sources_unchanged_during_actual_city_probe",not changed)
	var failed:=0
	for row: Dictionary in checks:
		if not row.passed:failed+=1
	var report:={"task":"street_curbs_actual_city","scope":"Current production EXP14 city with new curbs manually added only in this isolated process; no production scene integration/GPU.","started_at":started_at,"finished_at":Time.get_datetime_string_from_system(),"source_hashes":source_hashes,"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"baseline":_json(baseline),"checks":checks,"check_count":checks.size(),"failed":failed,"result":"PASS" if failed==0 else "FAIL"}
	var f:=FileAccess.open(report_path,FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close();finished=true;print("CURBS_ACTUAL_CITY ",report.result," checks=",checks.size()," failed=",failed);quit(1 if failed else 0)
