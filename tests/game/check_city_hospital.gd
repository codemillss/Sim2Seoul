extends SceneTree
## Full production, retained metric geometry, actual input and native doors.
## Starting observers are player-only fixtures; other actors are not moved.
var scene: Node3D
var hospital: Node3D
var checks: Array=[]
var captures: Array=[]
var measurements: Dictionary={}
var hashes: Dictionary={}
var report_path:="/tmp/sim2seoul-hospital.json"
var done:=false
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	Engine.max_fps=0;create_timer(180.,true,false,true).timeout.connect(func()->void:if not done:_check("bounded_wall_timeout",false);_finish())
	run.call_deferred()
func _hashes() -> Dictionary:
	var out: Dictionary={}
	for path: String in ["res://scripts/explore_walk.gd","res://scripts/city_hospital.gd","res://scripts/city_metric_overlay.gd","res://scripts/civic_facility_guidance.gd","res://assets/authored/city_hospital.json","res://assets/authored/city_metric_reference.json","res://scripts/player/free_roam_player.gd","res://scripts/player/exploration_avatar.gd","res://resources/world_geometry/world.json","res://data/generated/terrain_surface.json","res://../tests/game/check_city_hospital.gd"]:out[path]=FileAccess.get_sha256(path)
	return out
func _json(v: Variant) -> Variant:
	if v is Vector3:return [v.x,v.y,v.z]
	if v is Vector2:return [v.x,v.y]
	if v is Dictionary:
		var out: Dictionary={}
		for key: Variant in v:out[str(key)]=_json(v[key])
		return out
	if v is Array:
		var out: Array=[]
		for item: Variant in v:out.append(_json(item))
		return out
	if v is float:return v if is_finite(v) else null
	return v
func _check(title: String,ok: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":ok,"evidence":_json(evidence)});print("HOSPITAL_CHECK ",title," ",ok)
func _ticks(count: int) -> void:
	for i: int in range(count):await physics_frame;await process_frame
func _key(key: Key,pressed: bool) -> void:
	var event:=InputEventKey.new();event.keycode=key;event.physical_keycode=key;event.pressed=pressed;Input.parse_input_event(event)
func _tap_e() -> void:_key(KEY_E,true);await _ticks(2);_key(KEY_E,false);await _ticks(2)
func _capture(title: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await _ticks(4);await RenderingServer.frame_post_draw;var path:=report_path.get_basename()+"_"+title+".png";var result:=root.get_texture().get_image().save_png(path)
	_check("native_capture_"+title,result==OK,{"path":path})
	if result==OK:captures.append({"path":path,"sha256":FileAccess.get_sha256(path)})
func _place(point: Vector3,toward: Vector3) -> bool:
	var safe: Dictionary=scene.interior_visit._safe_external_point(point)
	if safe.is_empty() or not scene._commit_exploration_teleport(safe.point):return false
	var direction: Vector3=toward-safe.point;direction.y=0.;scene.rig.yaw=atan2(-direction.x,-direction.z);scene.player.visual.rotation.y=scene.rig.yaw;scene.rig.pitch=deg_to_rad(-12.);scene.rig.requested_distance=4.8;scene.rig.current_distance=4.8;scene.rig.snap_to_target_pose();await _ticks(6);return true
func _metric_runtime() -> void:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_geometry/world.json"));var max_error:=0.;var bad_scale: Array=[];var count:=0;var hidden:=0;var examples: Array=[]
	for entry: Dictionary in world.meshes:
		if entry.role!="Buildings":continue
		var node: MeshInstance3D=scene.city.source_nodes[entry.id];var rendered: AABB=node.global_transform*node.get_aabb();var minimum:=Vector2(INF,INF);var maximum:=Vector2(-INF,-INF)
		for i: int in range(0,entry.vertices.size(),3):minimum=minimum.min(Vector2(entry.vertices[i],entry.vertices[i+2]));maximum=maximum.max(Vector2(entry.vertices[i],entry.vertices[i+2]))
		var error:=maxf(maxf(absf(rendered.position.x-minimum.x),absf(rendered.position.z-minimum.y)),maxf(absf(rendered.end.x-maximum.x),absf(rendered.end.z-maximum.y)))
		max_error=maxf(max_error,error);count+=1
		if not node.global_basis.get_scale().is_equal_approx(Vector3.ONE):bad_scale.append(entry.id)
		if not node.is_visible_in_tree():hidden+=1
		if examples.size()<10:examples.append({"id":entry.id,"world_width_x_m":rendered.size.x,"world_depth_z_m":rendered.size.z,"xz_error_m":error,"visible":node.is_visible_in_tree()})
	measurements={"original_buildings_measured":count,"maximum_xz_extent_error_m":max_error,"nonunit_runtime_transforms":bad_scale,"hidden_originals_with_separate_replacement_visuals":hidden,"examples":examples,"scope":"All original runtime building bounds and transforms, not independent survey accuracy or an assumption that hidden originals prove final landmark visibility."}
	_check("all635_runtime_original_building_width_depth_positions_match_retained_source",count==635 and max_error<.001 and bad_scale.is_empty(),measurements)
	var reference: Dictionary=scene.city_metric_overlay.data;var counts: Dictionary={}
	for row: Dictionary in reference.buildings:counts[row.height_basis]=counts.get(row.height_basis,0)+1
	_check("height_estimates_are_explicit_and_not_promoted_to_surveyed_dimensions",counts.get("temporary_purpose_default")==479 and counts.get("source_tag")==98,{"height_basis_counts":counts})
func run() -> void:
	hashes=_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/hospital-test-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8)
	_check("whole_production_scene_and_hospital_load",scene.runtime_ok and is_instance_valid(scene.city_hospital) and scene.city_hospital.loaded,{"error":scene.exploration_error,"weather_error":scene.city_weather_emergency.load_error})
	if not scene.runtime_ok or not is_instance_valid(scene.city_hospital) or not scene.city_hospital.loaded:_finish();return
	hospital=scene.city_hospital
	if scene.menu.visible:scene.toggle_menu()
	scene.set_speed_profile("realistic");scene.set_time_profile("day");_metric_runtime()
	_check("hospital_large_metres_and_twelve_floor_pitch_are_consistent",hospital.design.width_x_m==48 and hospital.design.depth_z_m==34 and hospital.design.height_m==44 and hospital.design.floor_count==12 and is_equal_approx(hospital.design.ground_floor_height_m+11.*hospital.design.upper_floor_height_m,44.),hospital.snapshot())
	_check("hospital_full_native_site_and_source_parcel_obstacle_audit",hospital.site_samples.size()==450 and hospital.design.original_geometry_conflicts.is_empty() and hospital.design.source_parcel_id=="osm:way:1216911414:land_area",hospital.snapshot())
	_check("public_ground_floor_has_distinct_reception_emergency_beds_and_adult_staff",hospital.staff.size()==2 and is_instance_valid(hospital.building.find_child("ReceptionCounter",true,false)) and is_instance_valid(hospital.building.find_child("TriageNurseCounter",true,false)) and is_instance_valid(hospital.building.find_child("EmergencyTrolley",true,false)) and not scene.player.interior_active,hospital.snapshot())
	var menu_found:=false
	for child: Node in scene.exploration_menu_content.get_children():
		if child is Button and child.text=="외곽 종합병원 정문으로 이동":menu_found=true;break
	_check("hospital_has_a_reachable_normal_menu_shortcut",menu_found)
	scene._visit_city_life("hospital");await _ticks(6);_check("normal_shortcut_keeps_retained_player_on_native_supported_exterior",scene.player.is_on_floor() and scene.player.global_position.distance_to(Vector3(299,hospital.floor_y,375))<5. and not scene.player.facility_control and not scene.player.interior_active,{"point":scene.player.global_position});await _capture("normal_hospital_approach")
	_check("new_hospital_identity_and_actual_entrance_replace_unrelated_source_badge",scene.civic_facility_guidance.current.get("title")=="서울시티 종합병원" and "서울시티 종합병원" in scene.building_names.caption.text and not scene.interior_visit.wayfinding.panel.visible,scene.civic_facility_guidance.snapshot())
	var placed:=await _place(Vector3(291,0,375),Vector3(285,hospital.floor_y,375));_check("main_entrance_player_fixture_is_supported_and_targets_physical_hospital_door",placed and scene._street_interact_target()==hospital and "정문" in hospital.prompt_text(),{"position":scene.player.global_position,"prompt":hospital.prompt_text()})
	_key(KEY_W,true);await _ticks(95);_key(KEY_W,false);await _ticks(8)
	_check("closed_full_height_native_door_really_blocks_walking_capsule",scene.player.global_position.x>289.25 and hospital.door_groups[0].fraction<.01,{"position":scene.player.global_position,"doors":hospital.snapshot().doors})
	await _tap_e();await _ticks(34);_check("physical_e_opens_same_visible_native_sliding_doors",hospital.door_groups[0].fraction>.99 and not scene.player.facility_control and not scene.player.interior_active,hospital.snapshot())
	_key(KEY_W,true);await _ticks(140);_key(KEY_W,false);await _ticks(10)
	_check("actual_w_walks_from_street_into_full_size_lobby_without_teleport",scene.player.global_position.x<285. and scene.player.global_position.x>279. and scene.player.is_on_floor() and not scene.player.interior_active and not scene.player.facility_control,{"position":scene.player.global_position,"expected_floor_y":hospital.floor_y});await _capture("real_hospital_lobby")
	# Return through the same physical aperture using the real controller.
	_key(KEY_S,true);await _ticks(155);_key(KEY_S,false);await _ticks(10)
	_check("actual_s_walks_back_out_of_hospital_and_keeps_ordinary_controls",scene.player.global_position.x>289.4 and scene.player.is_on_floor() and scene.player.is_physics_processing(),{"position":scene.player.global_position})
	await _tap_e();await _ticks(12);var fraction: float=hospital.door_groups[0].fraction;scene.toggle_menu();await _ticks(30);_check("menu_pauses_real_hospital_door_motion",is_equal_approx(fraction,hospital.door_groups[0].fraction));scene.toggle_menu();await _ticks(35)
	var er_placed:=await _place(Vector3(291,0,365),Vector3(285,hospital.floor_y,365));await _tap_e();await _ticks(35);_key(KEY_W,true);await _ticks(115);_key(KEY_W,false);await _ticks(8)
	_check("separate_emergency_entry_opens_and_really_walks_to_triage",er_placed and hospital.door_groups[1].fraction>.99 and scene.player.global_position.x<287. and scene.player.global_position.z>363. and scene.player.global_position.z<367.,{"position":scene.player.global_position,"doors":hospital.snapshot().doors});await _capture("real_emergency_reception")
	scene._visit_city_life("library");await _ticks(5);var switch_: CheckButton=scene.find_child("MetreComparison",true,false);switch_.set_pressed_no_signal(true);scene.city_metric_overlay.set_enabled(true);await _ticks(6)
	_check("one_metre_comparison_displays_actual_nearby_footprints_without_moving_them",scene.city_metric_overlay.enabled and not scene.city_metric_overlay.selected.is_empty() and scene.city_metric_overlay.lines.mesh!=null,scene.city_metric_overlay.snapshot());await _capture("source_width_depth_and_gap_comparison");scene.city_metric_overlay.set_enabled(false)
	if DisplayServer.get_name()!="headless":
		# This separate, explicitly labelled observer fits the entire tall
		# exterior. Normal player-camera entry views above stay separate.
		var camera:=Camera3D.new();camera.name="TestOnlyFullHospitalExteriorObserver";scene.add_child(camera);camera.global_position=Vector3(329,hospital.floor_y+32.,417);camera.fov=58.;camera.look_at(Vector3(265,hospital.floor_y+21.,375));camera.make_current()
		var interface: CanvasLayer=scene.get_node("Interface");var sandbox: CanvasLayer=scene.get_node("CitySandboxHUD");var old_ui: bool=interface.visible;var old_sandbox: bool=sandbox.visible;interface.visible=false;sandbox.visible=false
		await _capture("independent_full_height_hospital_exterior");interface.visible=old_ui;sandbox.visible=old_sandbox;scene.rig.camera.make_current();camera.queue_free()
	_check("current_input_hashes_remained_stable_during_acceptance",hashes==_hashes())
	_finish()
func _finish() -> void:
	if done:return
	done=true
	for key: Key in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_E]:_key(key,false)
	var passed:=0
	for row: Dictionary in checks:
		if row.passed:passed+=1
	var out:={"schema_version":1,"task":"EXP28_HOSPITAL_AND_RUNTIME_SCALE","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"captures":captures,"measurements":measurements,"source_hashes":hashes,"scope":"Actual full game and engine-input W/S/E with original controller, native physical doors, source footprint dimensions and current hospital. Native image review and OS keyboard are separate. Upper hospital floors are a realistic exterior envelope and not playable clinical floors."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(out),"\t")+"\n");file.close()
	print("HOSPITAL_RESULT ",out.result," ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)
