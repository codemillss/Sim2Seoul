extends "res://../tests/game/check_city_hospital.gd"
## Whole-city human presence. Physical keyboard events, actual native walking,
## adult visuals and normal menu controls; only initial player poses are fixtures.
var city_motion: Array=[]
var before_actors: Dictionary={}
var before_capsule: Dictionary={}
var temp_settings_sha:=""
var user_settings_sha:=""
func _hashes() -> Dictionary:
	var out:=super._hashes()
	for path: String in ["res://scripts/player/exploration_camera.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://scripts/player/human_activity_dimensions.gd","res://assets/vendor/microsoft_rocketbox/PROVENANCE.json","res://assets/vendor/microsoft_rocketbox/Male_Adult_04/Export/Male_Adult_04.fbx","res://assets/vendor/microsoft_rocketbox/Female_Adult_07/Export/Female_Adult_07.fbx","res://assets/vendor/makehuman_swim/provenance.json","res://assets/vendor/makehuman_swim/swim_male.glb","res://assets/vendor/makehuman_swim/swim_female.glb","res://scripts/player/human_surface_meshes.gd","res://scripts/street_pedestrians.gd","res://scripts/exploration_pedestrian_avoidance.gd","res://scripts/shop_visit_service.gd","res://../tests/game/check_human_presence_city.gd"]:out[path]=FileAccess.get_sha256(path)
	return out
func _originals() -> Dictionary:
	var people: Array=[];var cars: Array=[];var source: Array=[]
	for person: Node in scene.pedestrians:people.append(person.get_instance_id())
	for car: Node in scene.vehicles:cars.append(car.get_instance_id())
	for id: String in scene.city.source_nodes:source.append(id)
	people.sort();cars.sort();source.sort();return {"people":people,"cars":cars,"source":source,"terrain":hash(scene.terrain_surface.faces)}
func _capsule_state() -> Dictionary:
	var collision: CollisionShape3D=scene.player.get_node("CollisionShape")
	return {"body":scene.player.get_instance_id(),"shape":collision.shape.get_instance_id(),"height":collision.shape.height,"radius":collision.shape.radius,"transform":str(collision.transform),"layer":scene.player.collision_layer,"mask":scene.player.collision_mask}
func _tap_v() -> void:_key(KEY_V,true);await _ticks(2);_key(KEY_V,false);await _ticks(2)
func _actual_motion(key: Key,ticks: int,label_: String) -> void:
	_key(key,true)
	for tick: int in range(ticks):
		await _ticks(1)
		if tick%4==0:city_motion.append({"phase":label_,"position":scene.player.global_position,"velocity":scene.player.velocity,"yaw":scene.player.visual.rotation.y,"motion":scene.player.locomotion_snapshot(),"avatar":scene.exploration_avatar.snapshot(),"camera":scene.rig.snapshot()})
	_key(key,false);await _ticks(12)
func run() -> void:
	hashes=_hashes();user_settings_sha=FileAccess.get_sha256("user://sim2seoul_exploration.json")
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/human-presence-city-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30
	var prefs:=FileAccess.open(scene.exploration_settings_path,FileAccess.WRITE);prefs.store_string(JSON.stringify({"schema_version":1,"speed_id":"turbo","free_roam":true})+"\n");prefs.close();temp_settings_sha=FileAccess.get_sha256(scene.exploration_settings_path)
	root.add_child(scene);await _ticks(10);hospital=scene.city_hospital
	_check("whole_city_uses_current_human_camera_motion_and_all_facilities",scene.runtime_ok and hospital.loaded and scene.city_public_safety.loaded and scene.city_weather_emergency.loaded,{"error":scene.exploration_error})
	if not scene.runtime_ok:_finish();return
	before_actors=_originals();before_capsule=_capsule_state()
	_check("saved_turbo_still_loads_and_all_five_profiles_remain",scene.speed_id=="turbo" and scene.SPEED_IDS.size()==5 and scene.player.run_speed_mps==21.)
	if not scene.menu.visible:scene.toggle_menu()
	var preview: Button=scene.find_child("NaturalWalkPreview",true,false);var reset_button: Button=scene.find_child("HumanEyeView",true,false)
	_check("normal_menu_exposes_natural_walk_and_human_eye_actions",preview!=null and reset_button!=null)
	preview.pressed.emit();await _ticks(6)
	_check("real_menu_preview_changes_session_to_realistic_without_overwriting_saved_turbo",not scene.menu.visible and scene.speed_id=="realistic" and scene.player.walk_speed_mps==1.4 and scene.player.run_speed_mps==3.5 and FileAccess.get_sha256(scene.exploration_settings_path)==temp_settings_sha,{"speed":scene.speed_id})
	_check("preview_leaves_original_user_preferences_untouched",FileAccess.get_sha256("user://sim2seoul_exploration.json")==user_settings_sha)
	# A session-only preview must survive unrelated normal UI saves. Exercise
	# both actual free-roam toggles and then a deliberate different speed choice.
	scene.toggle_menu();scene.free_roam_switch.button_pressed=false;await _ticks(3)
	var saved_without_free_roam: Variant=JSON.parse_string(FileAccess.get_file_as_string(scene.exploration_settings_path))
	_check("preview_then_free_roam_off_saves_original_turbo_and_keeps_realistic_session",saved_without_free_roam is Dictionary and saved_without_free_roam.get("speed_id")=="turbo" and saved_without_free_roam.get("free_roam")==false and scene.speed_id=="realistic" and not scene.free_roam_enabled,{"saved":saved_without_free_roam,"runtime_speed":scene.speed_id})
	scene.free_roam_switch.button_pressed=true;await _ticks(3)
	var saved_with_free_roam: Variant=JSON.parse_string(FileAccess.get_file_as_string(scene.exploration_settings_path))
	_check("preview_then_free_roam_on_still_saves_original_turbo",saved_with_free_roam is Dictionary and saved_with_free_roam.get("speed_id")=="turbo" and saved_with_free_roam.get("free_roam")==true and scene.speed_id=="realistic" and scene.free_roam_enabled,{"saved":saved_with_free_roam,"runtime_speed":scene.speed_id})
	var fast_index: int=scene.SPEED_IDS.find("fast");scene.speed_option.select(fast_index);scene.speed_option.item_selected.emit(fast_index);await _ticks(3)
	var explicit_speed: Variant=JSON.parse_string(FileAccess.get_file_as_string(scene.exploration_settings_path))
	_check("explicit_menu_speed_selection_replaces_saved_preference_after_preview",explicit_speed is Dictionary and explicit_speed.get("speed_id")=="fast" and scene.speed_id=="fast" and scene.player.run_speed_mps==7.,{"saved":explicit_speed,"runtime_speed":scene.speed_id})
	preview.pressed.emit();await _ticks(3)
	var after_second_preview: Variant=JSON.parse_string(FileAccess.get_file_as_string(scene.exploration_settings_path))
	_check("second_preview_keeps_latest_explicit_speed_and_returns_runtime_to_realistic",not scene.menu.visible and after_second_preview is Dictionary and after_second_preview.get("speed_id")=="fast" and scene.speed_id=="realistic" and scene.player.walk_speed_mps==1.4 and scene.player.run_speed_mps==3.5,{"saved":after_second_preview,"runtime_speed":scene.speed_id})
	_check("default_camera_is_third_person_with_metred_adult_eye_reference",absf(scene.rig.snapshot().human_eye_reference_m-1.6143558)<.001 and scene.rig.requested_distance>3. and scene.rig.current_distance>1.8,{"camera":scene.rig.snapshot()})
	var adults: Array=scene.find_children("ExplorationAvatar","Node3D",true,false);var detailed:=0;var bad: Array=[];var model_rows: Array=[]
	for adult: Node3D in adults:
		var model: Dictionary=adult.textured_model_snapshot() if adult.has_method("textured_model_snapshot") else {}
		var legacy_visible:=0
		for mesh: MeshInstance3D in adult._meshes:
			if mesh.is_visible_in_tree():legacy_visible+=1
		if model.get("loaded",false) and int(model.get("visible_mesh_count",0))>0 and int(model.get("skeleton_bone_count",0))>=40 and model.get("surface_texture_uv_ready",false) and legacy_visible==0:detailed+=1
		else:bad.append(String(adult.get_path()))
		model_rows.append({"path":String(adult.get_path()),"visible_textured_model":model,"legacy_visible_mesh_count":legacy_visible})
	_check("actual_textured_skinned_humans_replace_visible_proxies_for_player_and_city_characters",detailed>=29 and bad.is_empty(),{"adults":adults.size(),"detailed":detailed,"missing":bad,"models":model_rows})
	scene.set_time_profile("day");scene._visit_city_life("hospital");await _ticks(5);await _tap_v()
	_check("physical_v_resets_view_after_real_destination_without_teleporting_player",absf(scene.rig.pivot_height_m-1.2)<.001 and absf(scene.rig.pitch-deg_to_rad(-7.))<.001 and absf(scene.rig.requested_distance-3.4)<.001,{"point":scene.player.global_position,"camera":scene.rig.snapshot()});await _capture("street_human_eye_height")
	var posed:=await _place(Vector3(291,0,375),Vector3(283,hospital.floor_y,375));await _tap_v();_check("native_supported_main_door_fixture_targets_hospital",posed and scene._street_interact_target()==hospital)
	await _tap_e();await _ticks(35);_check("physical_e_opens_native_door_with_new_character",hospital.door_groups[0].fraction>.99)
	_key(KEY_W,true)
	for tick: int in range(180):
		await _ticks(1)
		if tick%6==0:city_motion.append({"phase":"lobby_entry","point":scene.player.global_position,"velocity":scene.player.velocity,"camera":scene.rig.snapshot()})
		if scene.player.global_position.x<285.7:break
	_key(KEY_W,false);await _ticks(12)
	_check("natural_w_walk_enters_same_world_hospital_at_human_height",scene.player.global_position.x<286. and scene.player.is_on_floor() and not scene.player.facility_control and not scene.player.interior_active,{"point":scene.player.global_position,"camera":scene.rig.snapshot()});await _capture("lobby_human_height_and_staff")
	await _actual_motion(KEY_D,45,"turn_90");var from_: Vector3=scene.player.global_position;await _actual_motion(KEY_A,70,"reverse_180")
	_check("natural_turn_and_reverse_walk_inside_actual_lobby_without_native_fall",scene.player.is_on_floor() and scene.player.global_position.distance_to(from_)>.5 and scene.player.global_position.x>242. and scene.player.global_position.x<288.5 and not scene.player.facility_control,{"point":scene.player.global_position,"camera":scene.rig.snapshot()});await _capture("actual_turned_character")
	var stable: Vector3=scene.player.global_position;scene.toggle_menu();_key(KEY_V,true);await _ticks(4);_key(KEY_V,false);await _ticks(4)
	_check("paused_menu_and_v_cannot_move_player_or_resume_world",scene.menu.visible and scene.player.global_position.is_equal_approx(stable));scene.toggle_menu();await _ticks(3)
	# On-foot V changes presentation, preserving exact current velocity/position.
	_key(KEY_W,true);await _ticks(24);var point_before: Vector3=scene.player.global_position;var velocity_before: Vector3=scene.player.velocity;var shape_before:=_capsule_state();_key(KEY_V,true)
	_check("physical_v_while_walking_preserves_physics_momentum_and_capsule",scene.player.global_position==point_before and scene.player.velocity==velocity_before and _capsule_state()==shape_before)
	await _ticks(2);_key(KEY_V,false);_key(KEY_W,false);await _ticks(12)
	scene._visit_city_life("car_station");await _ticks(8);var car: Node3D=scene.drivable_car_service
	_check("existing_car_shortcut_is_still_safe_and_interactable",car.can_interact())
	await _tap_e();await _ticks(10)
	_check("existing_car_owns_camera_after_real_e_mount",car.riding and scene.player.facility_control and scene.rig.pivot_height_m!=1.2,{"camera":scene.rig.snapshot()})
	var ride_pivot: float=scene.rig.pivot_height_m;var ride_distance: float=scene.rig.requested_distance;await _tap_v()
	_check("v_during_ride_preserves_exact_vehicle_camera_owner",car.riding and is_equal_approx(scene.rig.pivot_height_m,ride_pivot) and is_equal_approx(scene.rig.requested_distance,ride_distance))
	await _tap_e();await _ticks(18);_check("physical_e_dismount_restores_existing_onfoot_control",not car.riding and not scene.player.facility_control and scene.player.is_physics_processing())
	_check("all_original_actor_ids_source_nodes_terrain_and_capsule_are_retained",_originals()==before_actors and _capsule_state()==before_capsule,{"source_count":before_actors.source.size(),"old_people":before_actors.people.size(),"old_cars":before_actors.cars.size()})
	_finish()
func _finish() -> void:
	if done:return
	done=true;paused=false
	for key: Key in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_V,KEY_E]:_key(key,false)
	_check("current_sources_and_saved_user_settings_unchanged",hashes==_hashes() and FileAccess.get_sha256("user://sim2seoul_exploration.json")==user_settings_sha)
	var failed:=checks.filter(func(c: Dictionary)->bool:return not c.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(_json({"task":"EXP29_HUMAN_PRESENCE_CITY","result":"PASS" if failed==0 else "FAIL","checks":checks,"captures":captures,"source_hashes":hashes,"city_motion":city_motion,"scope":"Actual entire production city, engine physical keys E/V/W/A/D and normal menu signals. Only supported initial player observer fixtures; no NPC/vehicle/source/body placement or door-state forging. Native pixels and OS keyboard are separately reviewed; not a GTA asset, scanned human or performance claim."}),"  ")+"\n");file.close();print("HUMAN_PRESENCE_CITY_RESULT ",checks.size()-failed,"/",checks.size())
	if is_instance_valid(scene):
		if is_instance_valid(scene.neighborhood_life.audio):scene.neighborhood_life.audio.stop();scene.neighborhood_life.audio.stream=null
		scene.queue_free();await process_frame;await process_frame
	quit(0 if failed==0 else 1)
