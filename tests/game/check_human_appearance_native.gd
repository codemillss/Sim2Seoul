extends "res://../tests/game/check_human_scale_motion.gd"
## Actual production body/controller in a daylight metre fixture. Portrait
## cameras supply close anatomical review; walking/jumping use real physics.
class WardrobeHost extends Node3D:
	var exploration_avatar: Node3D
var wardrobe_host: WardrobeHost
var wardrobe: Node3D
var clothed_preview_only:=false

func _physical_joint(title: String) -> Transform3D:
	var node:=_joint(title)
	# A native process frame may already display interpolated local joints.
	# Measure the rig's captured simulation poses rather than rendered blends.
	var index: int=rig._joint_nodes.find(node)
	return rig._physics_joint_poses[index] if index>=0 and index<rig._physics_joint_poses.size() else node.transform

func _contact_foot(side: String) -> Vector3:
	return avatar.global_transform*_physical_joint(side+"Thigh")*_physical_joint(side+"Shin")*_physical_joint(side+"Foot").origin

func _walk_view(title: String,speed: float,fast: bool) -> void:
	await _place(Vector3(-30,.08,-30));player.walk_speed_mps=speed;player.run_speed_mps=speed
	var start: Vector3=player.global_position;var rows: Array=[];var previous_feet: Dictionary={};var previous_phases: Dictionary={};var previous_run:=0.;var steady_ticks:=0;var first_steady:=-1;var stance_samples:=0;var slip_max:=0.;var max_bob:=0.;var max_roll:=0.;var max_cadence:=0.;var min_sole:=INF;var max_sole:=-INF
	_keys(["move_forward","move_fast"] if fast else ["move_forward"])
	for tick: int in range(180):
		await _full_ticks(1);var sample: Dictionary=avatar.snapshot()
		var physical_speed:=Vector2(player.velocity.x,player.velocity.z).length()
		steady_ticks=steady_ticks+1 if absf(physical_speed-speed)<speed*.02 and absf(float(sample.run_weight)-previous_run)<.001 else 0
		previous_run=float(sample.run_weight)
		if steady_ticks>=12 and first_steady<0:first_steady=tick
		max_bob=maxf(max_bob,absf(_physical_joint("UpperBody").origin.y-.85));max_roll=maxf(max_roll,absf(_physical_joint("UpperBody").basis.get_euler().z));max_cadence=maxf(max_cadence,float(sample.cadence_hz))
		var feet: Dictionary={}
		for side: String in ["Left","Right"]:
			var foot:=_contact_foot(side);feet[side]=foot;var fraction:=fposmod(float(sample.stride_phase)/TAU+(.5 if side=="Right" else 0.),1.)
			if steady_ticks>=12 and fraction>.02 and fraction<float(sample.stance_fraction)-.02 and previous_phases.has(side) and fraction>float(previous_phases[side]) and float(previous_phases[side])>.02:
				slip_max=maxf(slip_max,Vector2(foot.x-previous_feet[side].x,foot.z-previous_feet[side].z).length()*Engine.physics_ticks_per_second);stance_samples+=1
			previous_feet[side]=foot;previous_phases[side]=fraction;min_sole=minf(min_sole,foot.y-player.global_position.y-.1145);max_sole=maxf(max_sole,foot.y-player.global_position.y-.1145)
		rows.append({"tick":tick,"position":player.global_position,"velocity":player.velocity,"feet_physics":feet,"phase":sample.stride_phase,"run_weight":sample.run_weight,"steady_ticks":steady_ticks,"cadence_hz":sample.cadence_hz})
	var record:={"kind":title,"configured_speed_mps":speed,"actual_speed_mps":Vector2(player.velocity.x,player.velocity.z).length(),"actual_travel_m":player.global_position.distance_to(start),"first_settled_stride_sample_tick":first_steady,"steady_guard":"12 consecutive physics samples within2percentof configuredspeed and run_weightdelta<.001; onset is measured separately by locomotion acceptance.","stance_samples":stance_samples,"maximum_world_stance_foot_slip_mps":slip_max,"sole_range_m":[min_sole,max_sole],"maximum_torso_bob_m":max_bob,"maximum_torso_roll_radians":max_roll,"maximum_cadence_hz":max_cadence,"samples":rows}
	motion_trials.append(record)
	_check(title+".actual_controller_reaches_configured_speed_and_travels",absf(float(record.actual_speed_mps)-speed)<.015 and float(record.actual_travel_m)>speed*2.70,record)
	_check(title+".steady_stance_contacts_keep_existing_25mm_per_second_limit",stance_samples>40 and slip_max<.025 and min_sole>-.012 and max_sole<.26,record)
	_check(title+".level_upper_body_and_bounded_cadence",max_bob<.00001 and max_roll<.00001 and max_cadence<=2.21,record)
	await _portrait(title,Vector3(1.8,1.5,-3.5));_keys([]);await _full_ticks(30)

func _portrait(title: String,offset: Vector3,target_height:=.95) -> void:
	if DisplayServer.get_name()=="headless":return
	var saved_current: bool=rig.camera.current;rig.camera.current=false;review_camera.current=true
	review_camera.global_position=player.global_position+offset;review_camera.look_at(player.global_position+Vector3.UP*target_height)
	# Hidden macOS windows can stop automatic draws while simulation continues.
	# Request this GPU image explicitly rather than wait indefinitely for a draw.
	await process_frame;RenderingServer.force_draw()
	var path:=report_path.get_basename()+"_"+title+".png";var image:=root.get_texture().get_image();var code:=image.save_png(path)
	_check("native.actual_"+title+"_portrait",code==OK and not image.is_empty(),{"file":path,"camera":review_camera.global_transform,"player":player.global_position})
	if code==OK:captures.append({"file":path,"sha256":FileAccess.get_sha256(path),"camera":review_camera.global_transform,"player":player.global_position,"scope":"Independent native daylight camera of current production human, not concept art. Numeric geometry and human visual review are separate."})
	review_camera.current=false;rig.camera.current=saved_current

func _wardrobe_views() -> void:
	wardrobe_host=WardrobeHost.new();fixture.add_child(wardrobe_host);wardrobe_host.exploration_avatar=avatar
	wardrobe=load("res://scripts/shop_visit_service.gd").new();wardrobe_host.add_child(wardrobe);wardrobe.host=wardrobe_host;wardrobe.loaded=true;wardrobe.set_process(false);wardrobe.set_physics_process(false);wardrobe.set_process_input(false);wardrobe.set_process_unhandled_input(false);wardrobe._remember_clothing()
	var refs: Array=[]
	for mesh: MeshInstance3D in avatar._meshes:refs.append({"node":mesh,"mesh":mesh.mesh,"material":mesh.material_override,"visible":mesh.visible})
	var began: bool=wardrobe.begin_swimwear();await _full_ticks(2)
	_check("wardrobe.real_production_swimwear_transition",began and wardrobe.swimwear_active and wardrobe._swim_feet.size()==2)
	var swim_model: Dictionary=avatar.textured_model_snapshot()
	_check("wardrobe.actual_opaque_swim_body_keeps_original_face_and_hair",swim_model.get("swimwear_active",false) and swim_model.get("active_body_source","")=="makehuman_cc0_body_with_original_rocketbox_head" and int(swim_model.get("swim_skeleton_bone_count",0))==163 and swim_model.get("original_head_and_hair_preserved",false),swim_model)
	await _portrait("swimwear_full_body",Vector3(.9,1.20,-3.1))
	await _portrait("swimwear_neck_three_quarter",Vector3(-.65,1.45,-.8),1.38)
	await _portrait("swimwear_profile",Vector3(-3.0,1.20,.03))
	var ended: bool=wardrobe.end_swimwear();var exact:=true
	for row: Dictionary in refs:exact=exact and row.node.mesh==row.mesh and row.node.material_override==row.material and row.node.visible==row.visible
	_check("wardrobe.original_clothing_and_visibility_restore_exactly",ended and exact)
	var restored_model: Dictionary=avatar.textured_model_snapshot()
	_check("wardrobe.actual_weighted_clothed_body_restores_after_swimwear",not restored_model.get("swimwear_active",true) and restored_model.get("active_body_source","")=="rocketbox_clothed" and restored_model.get("loaded",false),restored_model)
	await _portrait("restored_clothed_full_body",Vector3(.9,1.20,-3.1))

func _jump_view() -> void:
	await _place(Vector3(-10,.08,-10));var baseline: float=player.global_position.y;var peak:=baseline;_keys(["jump"])
	for tick: int in range(105):
		await _full_ticks(1);peak=maxf(peak,player.global_position.y)
		if tick==1:_keys([])
		if tick==17:await _portrait("actual_airborne_pose",Vector3(1.4,1.2,-3.3))
	_check("jump.actual_unmodified_controller_rises_and_lands_with_finite_body",peak-baseline>2.8 and peak-baseline<3.15 and player.is_on_floor() and avatar.global_transform.is_finite(),{"actual_apex_m":peak-baseline,"avatar":avatar.snapshot()})

func _run() -> void:
	clothed_preview_only="--clothed-preview" in OS.get_cmdline_user_args()
	for path: String in ["res://scripts/player/exploration_avatar.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://scripts/player/human_activity_dimensions.gd","res://assets/vendor/microsoft_rocketbox/PROVENANCE.json","res://assets/vendor/microsoft_rocketbox/Male_Adult_04/Export/Male_Adult_04.fbx","res://assets/vendor/microsoft_rocketbox/Female_Adult_07/Export/Female_Adult_07.fbx","res://assets/vendor/makehuman_swim/provenance.json","res://assets/vendor/makehuman_swim/swim_male.glb","res://assets/vendor/makehuman_swim/swim_female.glb","res://scripts/player/human_surface_meshes.gd","res://scripts/player/free_roam_player.gd","res://scripts/player/exploration_camera.gd","res://scripts/shop_visit_service.gd","res://scripts/drivable_car_service.gd","res://../tests/game/check_human_appearance_native.gd","res://../tests/game/check_human_scale_motion.gd","res://../tests/game/check_stable_motion.gd","res://../tests/game/check_jump.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	_setup_stable();_metric_scene();await _full_ticks(15);await _place(Vector3(-8,.08,8));_model_metrics()
	var rendered: Dictionary=avatar.textured_model_snapshot() if avatar.has_method("textured_model_snapshot") else {}
	var visible_proxies:=0
	for mesh: MeshInstance3D in avatar._meshes:
		if mesh.is_visible_in_tree():visible_proxies+=1
	_check("appearance.actual_visible_textured_skinned_model_replaces_procedural_body",rendered.get("loaded",false) and rendered.get("surface_texture_uv_ready",false) and int(rendered.get("visible_mesh_count",0))>0 and int(rendered.get("skeleton_bone_count",0))>=40 and visible_proxies==0,{"model":rendered,"visible_proxies":visible_proxies})
	await _portrait("clothed_full_body",Vector3(.9,1.20,-3.1))
	await _portrait("face_front_close",Vector3(.13,1.59,-.85),1.57)
	await _portrait("face_three_quarter_close",Vector3(-.60,1.59,-.72),1.57)
	await _portrait("human_profile",Vector3(-3.0,1.20,.03))
	if clothed_preview_only:_finish();return
	await _wardrobe_views()
	await _walk_view("actual_walk_1_4mps",1.4,false)
	await _walk_view("actual_run_3_5mps",3.5,true)
	await _jump_view()
	_check("physics_original_capsule_and_no_human_mesh_collision",_capsule()==initial_capsule and avatar.find_children("*","CollisionObject3D",true,false).is_empty())
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;paused=false;_keys([]);var failed:=checks.filter(func(row: Dictionary)->bool:return not row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot write human appearance native report");quit(2);return
	file.store_string(JSON.stringify(_json({"task":"EXP29_HUMAN_APPEARANCE_NATIVE","fixture_mode":"clothed_preview_only" if clothed_preview_only else "full_appearance_motion_and_wardrobe","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"physics_hz":Engine.physics_ticks_per_second,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"measurements":measurements,"motion_trials":motion_trials,"captures":captures,"source_sha256":source_hashes,"scope":"Actual current weighted human/controller in a daylight metre fixture. Clothed-preview mode covers only four static portraits; full mode additionally observes real walk/run/jump and production swim/clothing transitions. Not OS input, a human scan, mocap, GTA asset, city navigation, performance or subjective comfort acceptance. Native pixels require separate visual review."}),"  ")+"\n");file.close();print("HUMAN_APPEARANCE_NATIVE_RESULT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)
