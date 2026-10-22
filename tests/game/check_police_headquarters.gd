extends SceneTree
## Actual same-world W walking and E native doors, no facility teleport.
var scene: Node3D
var campus: Node3D
var checks: Array=[]
var captures: Array=[]
var report_path:="/tmp/sim2seoul-police-headquarters.json"
var hashes: Dictionary={}
var finished:=false
var trajectory: Array=[]
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	create_timer(240.,true,false,true).timeout.connect(func()->void:if not finished:_check("bounded_timeout",false);_finish());run.call_deferred()
func _hashes() -> Dictionary:
	var out: Dictionary={}
	for path: String in ["res://scripts/city_public_safety.gd","res://scripts/city_police_headquarters.gd","res://assets/authored/police_headquarters.json","res://scripts/city_police_facility.gd","res://scripts/explore_walk.gd","res://scripts/player/free_roam_player.gd","res://resources/world_geometry/world.json","res://../tests/game/check_police_headquarters.gd"]:out[path]=FileAccess.get_sha256(path)
	return out
func _json(v: Variant) -> Variant:
	if v is Vector3:return [v.x,v.y,v.z]
	if v is Dictionary:
		var out: Dictionary={}
		for k: Variant in v:out[str(k)]=_json(v[k])
		return out
	if v is Array:
		var out: Array=[]
		for row: Variant in v:out.append(_json(row))
		return out
	return v
func _check(title: String,ok: bool,evidence: Dictionary={}) -> void:checks.append({"name":title,"passed":ok,"evidence":_json(evidence)});print("POLICE_HEADQUARTERS_CHECK ",title," ",ok)
func _ticks(count: int) -> void:
	for index: int in range(count):await physics_frame;await process_frame
func _key(key: Key,pressed: bool) -> void:
	var event:=InputEventKey.new();event.keycode=key;event.physical_keycode=key;event.pressed=pressed;Input.parse_input_event(event)
func _tap_e() -> void:_key(KEY_E,true);await _ticks(2);_key(KEY_E,false);await _ticks(2)
func _capture(title: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await _ticks(3);await RenderingServer.frame_post_draw;var path:=report_path.get_basename()+"_"+title+".png";var result:=root.get_texture().get_image().save_png(path);_check("native_capture_"+title,result==OK,{"path":path});if result==OK:captures.append({"path":path,"sha256":FileAccess.get_sha256(path)})
func run() -> void:
	hashes=_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/police-headquarters-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8);campus=scene.city_public_safety.police_headquarters
	_check("separate_full_scale_campus_loads_with_original_small_substation",scene.runtime_ok and campus.loaded and scene.city_public_safety.police_facility.loaded,{"error":scene.exploration_error,"campus":campus.snapshot()})
	if not scene.runtime_ok or not campus.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	_check("realistic_game_dimensions_and_original_site_certificates",campus.design.width_m==30. and campus.design.depth_m==22. and campus.design.floors==4 and campus.design.height_m==15.6 and campus.native_certificate.native_supported_samples==336 and campus.native_certificate.private_or_bounds_samples==0 and campus.native_certificate.full_building_native_contacts.is_empty(),campus.snapshot())
	_check("same_world_ground_lobby_and_explicit_fictional_identity",campus.facade.get_node("FictionalInstitutionDisclosure").text.contains("가상") and is_instance_valid(campus.facade.get_node("PublicServiceCounter")) and is_instance_valid(campus.facade.get_node("CivilWaitingChair")) and not campus.active and campus.native_certificate.ramp_gradient<1./12.,campus.snapshot())
	var door_query:=PhysicsShapeQueryParameters3D.new();var door_shape:=CapsuleShape3D.new();door_shape.radius=.3;door_shape.height=1.7;door_query.shape=door_shape;door_query.collision_mask=32;door_query.transform=Transform3D(Basis.IDENTITY,campus.facade.to_global(Vector3(0,.9,11.)));var door_hits: Array=[]
	for hit: Dictionary in root.get_world_3d().direct_space_state.intersect_shape(door_query,8):door_hits.append(String(hit.collider.get_path()))
	var door_poses: Array=[]
	for door: AnimatableBody3D in campus._doors:door_poses.append({"global":door.global_transform.origin,"native":PhysicsServer3D.body_get_state(door.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM).origin,"layer":door.collision_layer,"shapes":door.get_child_count()})
	_check("closed_native_door_occupies_actual_world_entrance",not door_hits.is_empty(),{"contacts":door_hits,"poses":door_poses,"player_mask":scene.player.collision_mask})
	var safe: Dictionary=scene.interior_visit._safe_external_point(Vector3(-120,0,-401.3));var placed: bool=not safe.is_empty() and scene._commit_exploration_teleport(safe.point)
	_check("only_player_observer_start_on_original_native_ground",placed,{"safe":safe})
	if not placed:_finish();return
	scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();scene.rig.yaw=0.;scene.rig.pitch=deg_to_rad(-12.);scene.rig.requested_distance=7.5;scene.rig.current_distance=7.5;scene.rig.snap_to_target_pose();await _ticks(4);await _capture("full_scale_frontage")
	var start: Vector3=scene.player.global_position;_key(KEY_W,true)
	for index: int in range(150):
		await _ticks(1)
		if index%10==0:trajectory.append({"phase":"closed_door_approach","point":scene.player.global_position,"on_floor":scene.player.is_on_floor()})
	_key(KEY_W,false);await _ticks(4)
	_check("actual_w_walk_climbs_source_supported_ramp_and_closed_door_blocks",scene.player.global_position.z<-407.8 and scene.player.global_position.z>-409.1 and scene.player.global_position.distance_to(start)>5. and not campus.contains_player() and scene.player.is_on_floor(),{"start":start,"end":scene.player.global_position,"door":campus.snapshot()})
	_check("fresh_e_dispatch_resolves_large_campus_door",campus.can_interact() and scene._street_interact_target()==scene.city_public_safety,{"prompt":scene.street_interaction_hint()});await _tap_e();_check("physical_e_slides_real_native_collision_doors",campus.door_phase=="opening" and campus.door_fraction>0. and not scene.player.facility_control)
	var fraction: float=campus.door_fraction;scene.toggle_menu();await _ticks(30);_check("menu_pauses_native_door_transition",is_equal_approx(fraction,campus.door_fraction));scene.toggle_menu();await _ticks(24)
	var door_stall:=0;_key(KEY_W,true)
	for index: int in range(110):
		await _ticks(1)
		if index%10==0:trajectory.append({"phase":"same_world_enter","point":scene.player.global_position,"on_floor":scene.player.is_on_floor()})
		if campus.contains_player() and campus.facade.to_local(scene.player.global_position).z<4.:break
		if scene.player.velocity.length()<.05:door_stall+=1
	_key(KEY_W,false);await _ticks(4)
	_check("actual_w_walks_into_furnished_lobby_without_teleport_or_new_owner",campus.contains_player() and not scene.player.interior_active and not scene.player.facility_control and not campus.active and campus.facade.to_local(scene.player.global_position).z<6. and scene.player.is_on_floor(),{"point":scene.player.global_position,"campus":campus.snapshot(),"stalled_ticks":door_stall});await _capture("walkable_public_lobby")
	var inside: Vector3=scene.player.global_position;_key(KEY_D,true);await _ticks(14);_key(KEY_D,false);await _ticks(4);_check("same_world_lobby_supports_free_public_walking",campus.contains_player() and scene.player.global_position.distance_to(inside)>.6 and scene.player.is_on_floor(),{"distance":scene.player.global_position.distance_to(inside)})
	# Walk back toward the door from this actual interior position. No player
	# placement, officer relocation or native door force-state is used here.
	_key(KEY_A,true);await _ticks(14);_key(KEY_A,false);await _ticks(4);_key(KEY_S,true)
	for index: int in range(100):
		await _ticks(1)
		if campus.can_interact():break
	_key(KEY_S,false);await _ticks(4);await _tap_e();await _ticks(24);_key(KEY_S,true)
	for index: int in range(150):
		await _ticks(1)
		if scene.player.global_position.z>-401.4:break
	_key(KEY_S,false);await _ticks(4)
	_check("actual_s_exit_walks_down_ramp_to_original_street_without_stuck_controls",scene.player.global_position.z>-403. and not campus.contains_player() and not scene.player.interior_active and not scene.player.facility_control and scene.player.is_on_floor(),{"point":scene.player.global_position,"campus":campus.snapshot()})
	var departure: Dictionary=scene.city_public_safety.rental_clearance_snapshot();_check("four_original_officers_and_all16_rental_reservations_retained",scene.city_public_safety.officers.size()==4 and departure.home_violations.is_empty() and departure.posted_violations.is_empty())
	_check("menu_viewpoint_can_find_retained_native_exterior",not campus.viewpoint().is_empty(),campus.viewpoint());_finish()
func _finish() -> void:
	if finished:return
	finished=true;_check("source_inputs_stable_during_actual_run",hashes==_hashes() and not hashes.values().has(""),{"start":hashes,"end":_hashes()});var passed: int=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(_json({"task":"EXP28_FULL_SCALE_POLICE_HEADQUARTERS","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"captures":captures,"trajectory":trajectory,"source_hashes":hashes,"snapshot":campus.snapshot() if is_instance_valid(campus) else {},"scope":"Actual productionW/S/A/D walking andphysicalE native doors/ramp. Only one disclosed player-only start; no campus entry/exit teleport, door-state injection or original actor changes. Fictional campus, realisticgame dimensions, no current measuredSeoul police headquarters claim. Headless does not verify appearance."}),"  "));file.close();print("POLICE_HEADQUARTERS_RESULT ",passed,"/",checks.size())
	if is_instance_valid(scene):
		if is_instance_valid(scene.neighborhood_life.audio):scene.neighborhood_life.audio.stop();scene.neighborhood_life.audio.stream=null
		scene.queue_free();await process_frame;await process_frame
	quit(0 if passed==checks.size() else 1)
