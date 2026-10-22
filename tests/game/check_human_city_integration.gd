extends "res://../tests/game/check_mobility_distribution.gd"
## Entire ordinary city: original two N02 actor identities and native capsules
## stay intact while their exploration-only visuals become articulated adults.
var people: Array=[]
var observations: Array=[]
func _ticks(count: int) -> void:
	for tick in range(count):await physics_frame;await process_frame
func _hashes() -> Dictionary:
	var result:=super._hashes()
	for path: String in ["res://scripts/exploration_pedestrian_avoidance.gd","res://scripts/street_pedestrians.gd","res://scripts/city_public_safety.gd","res://scripts/city_weather_emergency.gd","res://../tests/game/check_human_city_integration.gd"]:result[path]=FileAccess.get_sha256(path)
	return result
func _body_capsule(body: CharacterBody3D) -> Dictionary:
	var node:=body.get_node("CollisionShape") as CollisionShape3D
	return {"body_id":body.get_instance_id(),"shape_node":node.get_instance_id(),"shape":node.shape.get_instance_id(),"height":node.shape.height,"radius":node.shape.radius,"transform":node.transform,"layer":body.collision_layer,"mask":body.collision_mask,"disabled":node.disabled}
func _measure(row: Dictionary) -> Dictionary:
	var avatar: Node3D=row.avatar;var bounds:=AABB();var ready:=false
	# Query after the reset/capture physics phases; local mesh dimensions are
	# measured relative to the actor, independently of its source-ground Y.
	for mesh: MeshInstance3D in avatar._meshes:
		var box: AABB=mesh.global_transform*mesh.get_aabb();bounds=box if not ready else bounds.merge(box);ready=true
	return {"body":row.body.get_instance_id(),"avatar":avatar.get_instance_id(),"position":row.body.global_position,"capsule":_body_capsule(row.body),"state":avatar.state,"cadence_hz":avatar.cadence_hz,"visual_bounds_height_m":bounds.size.y,"head_height_m":avatar.HEAD_HEIGHT_M,"on_floor":row.body.is_on_floor(),"phase":avatar.stride_phase,"proxy":row.proxy.get_instance_id()}
func _run() -> void:
	_loaded_hashes=_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/human-city-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(12)
	_check("whole_production_city_ready",scene.runtime_ok,{"error":scene.exploration_error})
	if not scene.runtime_ok:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	_initial_inventory=_inventory();_initial_capsule=_capsule();_initial_actors=_actors();_initial_tin=hash(scene.terrain_surface.faces)
	var adapter: Node3D=scene.exploration_pedestrians
	_check("same_two_source_N02_bodies_have_exploration_only_adult_meshes",adapter.human_visuals.size()==2 and scene.pedestrians.size()==2 and adapter.human_visuals.all(func(row: Dictionary)->bool:return row.body in scene.pedestrians and not row.body.get_node("Visual/Body").visible and not row.body.get_node("Visual/Front").visible),adapter.snapshot())
	for row: Dictionary in adapter.human_visuals:people.append({"body":row.body,"start":row.body.global_position,"capsule":_body_capsule(row.body),"phase":row.avatar.stride_phase,"moving_samples":0,"gait_samples":0,"supported_samples":0,"last":row.body.global_position,"max_y":-INF,"min_y":INF})
	for tick in range(240):
		await _ticks(1)
		for index in range(people.size()):
			var row: Dictionary=adapter.human_visuals[index];var record: Dictionary=people[index];var step: float=row.body.global_position.distance_to(record.last);record.last=row.body.global_position
			if step>.002:record.moving_samples+=1
			if row.avatar.state=="walk" and row.avatar.cadence_hz>.1:record.gait_samples+=1
			if row.body.is_on_floor():record.supported_samples+=1
			if tick%30==0:observations.append(_measure(row))
	for index in range(people.size()):
		var record: Dictionary=people[index];var row: Dictionary=adapter.human_visuals[index]
		_check("original_actor_"+str(index)+"_actual_physical_route_walk_drives_visible_gait",record.moving_samples>30 and record.gait_samples>30 and record.supported_samples>220 and row.avatar.state!="transport",{"moving_samples":record.moving_samples,"gait_samples":record.gait_samples,"supported_samples":record.supported_samples,"end":_measure(row),"start":record.start})
		_check("original_actor_"+str(index)+"_capsule_identity_route_and_collision_retained",_body_capsule(row.body)==record.capsule and row.body.has_meta("exploration_avoidance_adapter") and row.body._route_id==adapter.groups[index].id.trim_prefix("legacy_"),{"before":record.capsule,"after":_body_capsule(row.body),"route_id":row.body._route_id})
	scene.set_pedestrians_running(false);await _ticks(35)
	_check("old_two_source_walkers_rest_instead_of_cycling_while_paused",adapter.human_visuals.all(func(row: Dictionary)->bool:return row.avatar.state=="idle" and row.avatar.cadence_hz==0. and row.body.velocity.length()<.15),{"actors":adapter.human_visuals.map(func(row: Dictionary)->Dictionary:return _measure(row))})
	_check("all_original_28_adults_2_dogs_14_AI_cars_and1233_source_nodes_retained",_actors()==_initial_actors and _actors().size()==44 and _inventory()==_initial_inventory and _initial_inventory.size()==1233 and _capsule()==_initial_capsule and hash(scene.terrain_surface.faces)==_initial_tin,{"actor_count":_actors().size(),"source_nodes":_initial_inventory.size()})
	_check("component_source_hashes_remain_unchanged_during_run",_hashes()==_loaded_hashes)
	_finish()
func _finish() -> void:
	if finished:return
	finished=true;var failed:=checks.filter(func(row: Dictionary)->bool:return not row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(_json({"task":"EXP28_HUMAN_CITY_INTEGRATION","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"observations":observations,"source_hashes":_loaded_hashes,"scope":"Whole ordinary city, physical original N02 actors/capsules/routes retained and observed; no actor placement or motion injection. Engine headless observation, not native appearance, OS input, all-human photorealism or world-scale survey acceptance."}),"  ")+"\n");file.close();print("HUMAN_CITY_INTEGRATION_RESULT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)
