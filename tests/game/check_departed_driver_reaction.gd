extends "res://../tests/game/check_city_action_freedom.gd"
## Real original-car stop/door walk/entry/exit creates the driver. Only player
## observer starts change; the retained driver capsule and pose owners run.
class DriverPoseSampler extends Node:
	var row: Dictionary
	var active_physics_frames:=0
	var active_render_frames:=0
	var maximum_physics_anchor_error_m:=0.
	var maximum_render_anchor_error_m:=0.
	var maximum_render_step_m:=0.
	var active_render_distance_m:=0.
	var last_render:=Vector3.ZERO
	var have_last:=false
	func _physics_process(_delta: float) -> void:
		if preload("res://scripts/actor_hit_reaction.gd").owns(row.body):
			active_physics_frames+=1
			maximum_physics_anchor_error_m=maxf(maximum_physics_anchor_error_m,row.current.origin.distance_to(row.visual.global_position))
	func _process(_delta: float) -> void:
		var expected: Transform3D=row.previous.interpolate_with(row.current,clampf(Engine.get_physics_interpolation_fraction(),0.,1.))
		maximum_render_anchor_error_m=maxf(maximum_render_anchor_error_m,row.proxy.global_position.distance_to(expected.origin))
		var at: Vector3=row.proxy.global_position
		if have_last:
			var step: float=at.distance_to(last_render);maximum_render_step_m=maxf(maximum_render_step_m,step)
			if preload("res://scripts/actor_hit_reaction.gd").owns(row.body):active_render_distance_m+=step
		last_render=at;have_last=true
		if preload("res://scripts/actor_hit_reaction.gd").owns(row.body):active_render_frames+=1
func _run() -> void:
	source_hashes=_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/private/tmp/driver-reaction-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8)
	service=scene.city_public_safety;car_service=scene.traffic_car_takeover
	_check("actual_city_and_original_takeover_ready",scene.runtime_ok and service.loaded and car_service.loaded)
	if not scene.runtime_ok:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	scene.set_free_roam(true);scene.set_pedestrians_running(false);initial_footprint=_footprint();initial_city=_city_inventory()
	await _exercise_car()
	_check("ordinary_original_car_journey_created_real_driver",not car_service.drivers.is_empty())
	if car_service.drivers.is_empty():_finish();return
	for tick: int in range(450):
		if not service.detained:break
		await _ticks(1)
	var driver: Dictionary=car_service.drivers[-1];var driver_id: int=driver.body.get_instance_id()
	var placed:=await _place_near(driver.body,.88);await _idle()
	var sampler:=DriverPoseSampler.new();sampler.row=driver;sampler.process_physics_priority=5;sampler.process_priority=999;scene.add_child(sampler);await _ticks(4)
	var before: Vector3=driver.body.global_position;var hits_before: int=service.hits
	await _tap(KEY_F);await _ticks(25)
	_check("actual_F_knuckle_contact_hits_same_spawned_driver",placed and service.hits==hits_before+1 and driver.body.get_instance_id()==driver_id,{"events":service.events.slice(-8)})
	_check("active_driver_reaction_keeps_physics_pose_endpoint_current",sampler.active_physics_frames>=4 and sampler.maximum_physics_anchor_error_m<.0001,{"active_physics_frames":sampler.active_physics_frames,"maximum_anchor_error_m":sampler.maximum_physics_anchor_error_m})
	_check("active_driver_proxy_interpolates_and_visibly_moves_without_release_pop",sampler.active_render_frames>=8 and sampler.active_render_distance_m>.03 and sampler.maximum_render_anchor_error_m<.0001 and sampler.maximum_render_step_m<.08,{"active_render_frames":sampler.active_render_frames,"render_distance_m":sampler.active_render_distance_m,"maximum_interpolation_error_m":sampler.maximum_render_anchor_error_m,"maximum_render_step_m":sampler.maximum_render_step_m,"body_distance_m":before.distance_to(driver.body.global_position)})
	_check("reaction_releases_same_driver_to_original_route_owner",not preload("res://scripts/actor_hit_reaction.gd").owns(driver.body) and driver.body.get_instance_id()==driver_id and car_service.snapshot().original_identities_retained,{"snapshot":car_service.snapshot()})
	_finish()
func _hashes() -> Dictionary:
	var hashes: Dictionary=super._hashes()
	for path: String in ["res://scripts/actor_hit_reaction.gd","res://scripts/player/human_combat_poses.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://../tests/game/check_departed_driver_reaction.gd"]:hashes[path]=FileAccess.get_sha256(path)
	return hashes
func _finish() -> void:
	if finished:return
	finished=true
	for code: int in [KEY_F,KEY_X,KEY_G,KEY_E,KEY_H,KEY_W]:_event(code,false)
	Input.action_release("move_forward");_check("runtime_source_bindings_stable",source_hashes==_hashes())
	var passed: int=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(_json({"task":"EXP33_DEPARTED_DRIVER_REACTION","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"captures":captures,"source_hashes":source_hashes,"display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"elapsed_ms":Time.get_ticks_msec()-started,"scope":"Actual production original-car stop, physical W door approach, timed driver exit/player entry, horn and driving ownership/exit. Actual F knuckle contact against that same retained spawned driver; reaction-owner physics endpoints, late render proxy interpolation and physical/render displacement observed. Test-only supported player starts and ordinary pedestrian-pause option; no driver/officer relocation, timer override, fake reaction owner or OS-input claim. Headless does not prove pixels or subjective comfort."}),"  ")+"\n");file.close();print("DEPARTED_DRIVER_REACTION_RESULT ",passed,"/",checks.size())
	if is_instance_valid(scene):
		if is_instance_valid(scene.neighborhood_life.audio):scene.neighborhood_life.audio.stop();scene.neighborhood_life.audio.stream=null
		await physics_frame;await physics_frame;scene.queue_free();await process_frame;await process_frame
	quit(0 if passed==checks.size() else 1)
