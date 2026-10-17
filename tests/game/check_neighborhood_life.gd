extends "res://../tests/game/check_street_scene.gd"
func _run() -> void:
	for path in ["res://scripts/neighborhood_life.gd","res://scripts/building_type_identity.gd","res://scripts/explore_walk.gd","res://assets/audio/stonewall_guitar.wav","res://assets/authored/street_businesses.json"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate()
	_settings_path=report_path+".settings.json";scene.exploration_settings_path=_settings_path;scene.quality_settings_path=_settings_path+".quality.json"
	root.add_child(scene);await _ticks(12)
	_check("startup",scene.runtime_ok,{"error":scene.exploration_error})
	if not scene.runtime_ok:_finish();return
	visit=scene.interior_visit
	if scene.menu.visible:await _menu_edge()
	await _ticks(5);original_inventory=_inventory();var player_shape:=_player_shape()
	_business_geometry()
	var module: Node3D=scene.neighborhood_life
	observations.neighborhood=module.snapshot();observations.identity=scene.building_type_identity.snapshot()
	_check("life.queue_picnics_and_bilingual_signs_exist",module.queue_people.size()>=2 and module.picnics.size()>=2 and module.signs.size()>=4,module.snapshot())
	var valid:=true
	for row: Dictionary in module.placements:
		valid=valid and row.protection.clear and not String(row.support).is_empty()
	_check("life.every_placement_has_real_floor_and_clear_route_traffic_door_guards",valid,{"placements":module.placements})
	for sign_row: Dictionary in module.signs:
		for row: Dictionary in sign_row.rows:
			valid=valid and row.distance_m>0 and absf(row.direction.length()-1.0)<.001 and row.target.contains(" · ")
	_check("wayfinding.labels_use_real_horizontal_distances_and_directions",valid,{"sign_count":module.signs.size()})
	for store: Dictionary in scene.street_businesses.stores:
		if store.record.style!="restaurant":continue
		var toward: Vector3=store.node.global_position+Vector3.UP
		var safe: Dictionary=visit._safe_external_point(store.node.to_global(Vector3(0,.08,4.)))
		_check("queue.door_approach_is_still_clear",not safe.is_empty())
		if not safe.is_empty() and await _pose("restaurant_queue",safe.point):await _view("restaurant_queue",toward,5.)
	if not module.picnics.is_empty():
		var toward: Vector3=module.picnics[0].global_position
		var safe: Dictionary=visit._safe_external_point(toward+Vector3(0,.08,4.))
		if not safe.is_empty() and await _pose("day_picnic",safe.point):await _view("day_picnic",toward+Vector3.UP*.7,5.)
		scene.set_time_profile("night");await _ticks(3)
		var collision_free:=true
		for group: Node3D in module.picnics:
			for child in group.get_children():
				if child is StaticBody3D:collision_free=collision_free and child.collision_layer==0
		_check("picnic.night_hides_people_and_removes_invisible_colliders",not module._daily.visible and collision_free)
		scene.set_time_profile("day")
	var music: AudioStreamPlayer3D=module.audio
	_check("audio.original_mono_20second_loop_spatial_and_bounded",music.playing and music.stream is AudioStreamWAV and music.stream.get_length()>19.9 and music.stream.get_length()<20.1 and music.max_distance<=32 and music.stream.loop_mode==AudioStreamWAV.LOOP_FORWARD,{"length_seconds":music.stream.get_length(),"max_distance_m":music.max_distance,"stream_sha256":FileAccess.get_sha256("res://assets/audio/stonewall_guitar.wav")})
	scene.menu.find_child("BuskingMusic",true,false).button_pressed=false;_check("audio.mute_control_applies",not module.music_enabled and music.volume_db<=-70.)
	scene.menu.find_child("BuskingMusic",true,false).button_pressed=true;_check("audio.unmute_control_applies",module.music_enabled and music.volume_db> -20.)
	await _menu_edge();var time_before:=music.get_playback_position();await _ticks(30)
	_check("audio.menu_pauses_performance_playback",absf(music.get_playback_position()-time_before)<.03,{"before":time_before,"after":music.get_playback_position()})
	await _menu_edge()
	var church: Dictionary=scene.building_type_identity.destination()
	_check("identity.church_observer_supported",not church.is_empty(),church)
	if not church.is_empty() and await _pose("church",church.point):await _view("church",church.toward,7.)
	if not module.signs.is_empty():
		var sign_node: Node3D=module.signs[0].node
		var safe: Dictionary=visit._safe_external_point(sign_node.global_position+Vector3(0,.08,3.))
		if not safe.is_empty() and await _pose("wayfinding",safe.point):await _view("wayfinding",sign_node.global_position+Vector3.UP*2.3,4.)
	scene._visit_street_detail("hotel_pool");await _ticks(12)
	_check("menu.hotel_shortcut_lands_outdoors_with_visible_pool",not scene.player.interior_active and not visit.active and scene.player.is_on_floor() and scene.exploration_rooftop_access.representative_pool_destination().roof.visible)
	var pool: Dictionary=scene.exploration_rooftop_access.representative_pool_destination()
	await _ticks(8)
	_check("menu.hotel_shortcut_camera_is_clear",_camera_clear())
	var head: Vector3=scene.player.global_position+Vector3.UP*1.62
	var pixel: Vector2=scene.rig.camera.unproject_position(head)
	var head_ray: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(scene.rig.camera.global_position,head,scene.rig.arm.collision_mask,[scene.player.get_rid()]))
	var view: Dictionary={"distance_m":scene.rig.current_distance,"avatar_visible":scene.player.get_node("Visual").is_visible_in_tree(),"head_pixel":pixel,"head_in_frame":not scene.rig.camera.is_position_behind(head) and scene.get_viewport().get_visible_rect().has_point(pixel),"head_ray_clear":head_ray.is_empty(),"camera_clear":_camera_clear(),"camera":scene.rig.snapshot()}
	observations["hotel_shortcut_view"]=view
	_check("menu.hotel_shortcut_preserves_actual_third_person_avatar_and_clear_head",view.distance_m>1.8 and view.avatar_visible and view.head_in_frame and view.head_ray_clear and view.camera_clear,view)
	await _capture("hotel_pool_shortcut")
	_check("regression.original_source_collisions_and_player_shape_unchanged",original_inventory==_inventory() and player_shape==_player_shape(),{"source_count":original_inventory.size()})
	_check("shops.source_linked_convenience_expansion",scene.street_businesses.stores.size()>=10,{"count":scene.street_businesses.stores.size()})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var failed:=0
	for row: Dictionary in checks:
		if not row.passed:failed+=1
	var report: Dictionary={"task":"EXP19_neighborhood_life","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"observations":observations,"source_sha256":source_hashes,"captures":captures,"scope":"Production source scene; physical supported fixtures, route/door guards, real spatial sound playback state and pause/mute; authored people, events, shop frontage and church details. No current tenancy, real event, surveyed interior, native human-control or subjective audio-quality claim."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(_json(report),"\t")+"\n");file.close()
	scene.queue_free();await process_frame;quit(1 if failed else 0)
