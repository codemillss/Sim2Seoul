extends "res://../tests/game/check_textured_human_rig.gd"
## Real wardrobe wrapper: retained Rocketbox head plus MakeHuman body. Numeric
## neck/shoulder continuity supplements, and never replaces, native image review.

func _run() -> void:
	for path: String in ["res://scripts/player/exploration_avatar.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://scripts/player/human_activity_dimensions.gd","res://assets/vendor/makehuman_swim/swim_male.glb","res://assets/vendor/makehuman_swim/swim_female.glb","res://assets/vendor/microsoft_rocketbox/Male_Adult_04/Export/Male_Adult_04.fbx","res://assets/vendor/microsoft_rocketbox/Female_Adult_07/Export/Female_Adult_07.fbx","res://../tests/game/check_textured_human_rig.gd","res://../tests/game/check_hybrid_neck_fit.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	for id: String in ["Male_Adult_04","Female_Adult_07"]:
		var player:=CharacterBody3D.new();player.set_meta("human_model_id",id)
		var visual:=Node3D.new();visual.name="Visual";player.add_child(visual);var original:=MeshInstance3D.new();original.name="Body";original.mesh=CapsuleMesh.new();visual.add_child(original);root.add_child(player)
		var avatar: Node3D=load("res://scripts/player/exploration_avatar.gd").new();visual.add_child(avatar)
		_check(id+".normal_weighted_avatar_setup",avatar.setup(player))
		avatar.set_physics_process(false)
		var surface: Node3D=avatar._textured_surface
		if not is_instance_valid(surface) or not surface.loaded:player.free();continue
		var original_poses: Array[Transform3D]=[]
		for bone: int in range(surface.skeleton.get_bone_count()):original_poses.append(surface.skeleton.get_bone_pose(bone))
		surface.set_swimwear(true)
		var body_rig: Node3D=surface._swim_rig
		_check(id+".real_swim_wrapper_uses_original_head_reference",is_instance_valid(body_rig) and body_rig.loaded and body_rig.reference_skeleton==surface.skeleton,surface.snapshot(true))
		if not is_instance_valid(body_rig) or not body_rig.loaded:player.free();continue
		body_rig.sync_pose();var fit: Dictionary=body_rig.snapshot().upper_body_reference_fit
		_check(id+".neck_base_and_head_joint_match_retained_original_heights",fit.get("enabled",false) and absf(float(fit.get("neck_base_height_error_m",INF)))<.005 and absf(float(fit.get("head_joint_height_error_m",INF)))<.005,fit)
		_check(id+".both_actual_shoulders_match_original_head_stature",absf(float(fit.shoulder_height_errors_m.Left))<.005 and absf(float(fit.shoulder_height_errors_m.Right))<.005,fit)
		_check(id+".actual_neck_and_head_xyz_join_original_head",float(fit.get("neck_base_error_m",INF))<.005 and float(fit.get("head_joint_error_m",INF))<.005,fit)
		_check(id+".both_actual_shoulder_xyz_centers_match_original",float(fit.shoulder_center_errors_m.Left)<.005 and float(fit.shoulder_center_errors_m.Right)<.005,fit)
		_check(id+".visible_neck_has_original_adult_vertical_span",float(fit.neck_vertical_span_m)>.045 and float(fit.neck_vertical_span_m)<.085,fit)
		var previous:=-INF;var ordered:=true;var neck_positions: Array=[]
		for title: String in ["neck01","neck02","neck03","Bip01 Head"]:
			var bone: int=surface._swim_skeleton.find_bone(title);var at: Vector3=surface._swim_skeleton.global_transform*surface._swim_skeleton.get_bone_global_pose(bone).origin
			ordered=ordered and at.y>previous;previous=at.y;neck_positions.append({"bone":title,"point":at})
		_check(id+".neck_chain_is_continuous_and_ordered_to_original_head",ordered,{"chain":neck_positions})
		var source_unchanged:=true
		for bone: int in range(original_poses.size()):source_unchanged=source_unchanged and surface.skeleton.get_bone_pose(bone)==original_poses[bone]
		_check(id+".original_head_skeleton_not_moved_to_hide_join",source_unchanged)
		var arms_fixed:=true
		for side: String in ["Left","Right"]:
			for segment: Array in [["UpperArm","Forearm"],["Forearm","Hand"]]:
				var a: int=body_rig._find(side+segment[0]);var b: int=body_rig._find(side+segment[1])
				var actual_a: Vector3=surface._swim_skeleton.get_bone_global_pose(a).origin;var actual_b: Vector3=surface._swim_skeleton.get_bone_global_pose(b).origin
				var old_a: Vector3=body_rig._rest_global[a].origin;var old_b: Vector3=body_rig._rest_global[b].origin
				arms_fixed=arms_fixed and absf(actual_a.distance_to(actual_b)-old_a.distance_to(old_b))<.00001
		_check(id+".original_actual_arm_segment_lengths_preserved",arms_fixed)
		var lower_fixed:=true
		for semantic: String in ["Pelvis","LeftThigh","LeftShin","LeftFoot","RightThigh","RightShin","RightFoot"]:
			var bone: int=body_rig._find(semantic);lower_fixed=lower_fixed and body_rig._rest_global[bone]==body_rig._fitted_rest_global[bone]
		for side: String in ["Left","Right"]:
			for segment: Array in [["Thigh","Shin"],["Shin","Foot"]]:
				var a: int=body_rig._find(side+segment[0]);var b: int=body_rig._find(side+segment[1])
				var actual_a: Vector3=surface._swim_skeleton.get_bone_global_pose(a).origin;var actual_b: Vector3=surface._swim_skeleton.get_bone_global_pose(b).origin
				lower_fixed=lower_fixed and absf(actual_a.distance_to(actual_b)-body_rig._rest_global[a].origin.distance_to(body_rig._rest_global[b].origin))<.00001
		for bone: int in range(surface._swim_skeleton.get_bone_count()):lower_fixed=lower_fixed and surface._swim_skeleton.get_bone_rest(bone)==body_rig._rest[bone] and surface._swim_skeleton.get_bone_global_pose(bone).is_finite()
		_check(id+".height_fit_preserves_hips_legs_lengths_and_import_rests",lower_fixed)
		var current: Dictionary=surface.snapshot(true);var bounds: AABB=current.actual_visible_bounds_m
		_check(id+".actual_hybrid_top_stays_1_70m_instead_of_raising_head",absf(bounds.end.y-1.70)<.008 and bounds.size.y>1.68 and bounds.size.y<1.72,{"actual_visible_bounds":bounds,"fit":fit})
		cases.append({"model":id,"fit":fit,"actual_hybrid_bounds":bounds,"neck_chain":neck_positions,"body_rig":body_rig.snapshot()})
		surface.set_swimwear(false);_check(id+".restoring_original_clothing_keeps_unchanged_head",not surface._swimwear_active and not surface._swim_root.visible)
		player.free();await process_frame
	var bindings_same:=true
	for path: String in source_hashes:bindings_same=bindings_same and FileAccess.get_sha256(path)==source_hashes[path]
	_check("all_hybrid_fit_input_sources_unchanged",bindings_same)
	var failed:=checks.filter(func(row: Dictionary)->bool:return not row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(_json({"task":"EXP29_HYBRID_NECK_FIT","result":"PASS" if failed==0 else "FAIL","summary":{"checks":checks.size(),"failed":failed},"checks":checks,"cases":cases,"source_sha256":source_hashes,"display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"scope":"Actual wardrobe wrapper combining original Rocketbox head with MakeHuman swim body. Native XYZ neck/head/shoulder joins, ordered neck chain, limb lengths, original skeleton immutability and referenced rendered CPU skin bounds; numeric join checks supplement separate three-quarter/profile/full-body visual review and do not certify subjective realism."}),"  ")+"\n");file.close();print("HYBRID_NECK_FIT_RESULT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)
