extends "res://../tests/game/check_textured_human_rig.gd"
## Diagnostic coverage of two independently proportioned, simultaneously
## posed skins. Production source is read-only; no fit is applied here.

func _record(id: String,mode: String,phase: float,surface: Node3D) -> void:
	var primary: Node3D=surface.rig;var body: Node3D=surface._swim_rig
	primary.sync_pose();body.sync_pose();surface._process(0.)
	var original: Skeleton3D=surface.skeleton;var swim: Skeleton3D=surface._swim_skeleton
	var neck: Vector3=original.global_transform*original.get_bone_global_pose(body._reference_index("Neck")).origin
	var head: Vector3=original.global_transform*original.get_bone_global_pose(body._reference_index("Head")).origin
	var body_neck: Vector3=swim.global_transform*swim.get_bone_global_pose(swim.find_bone("neck01")).origin
	var body_head: Vector3=swim.global_transform*swim.get_bone_global_pose(body._find("Head")).origin
	var neck_offset:=body_neck-neck;var head_offset:=body_head-head
	var primary_drop: Vector3=original.global_basis*primary._last_hip_delta;var body_drop: Vector3=swim.global_basis*body._last_hip_delta
	var label_:=id+"_"+mode+"_"+str(phase)
	_check(label_+".actual_neck_xyz_join_under_5mm",neck_offset.length()<.005,{"offset_m":neck_offset,"distance_m":neck_offset.length()})
	_check(label_+".actual_head_xyz_join_under_5mm",head_offset.length()<.005,{"offset_m":head_offset,"distance_m":head_offset.length()})
	cases.append({"model":id,"mode":mode,"phase":phase,"original_neck_world_m":neck,"body_neck_world_m":body_neck,"neck_offset_m":neck_offset,"neck_error_m":neck_offset.length(),"original_head_joint_world_m":head,"body_head_joint_world_m":body_head,"head_offset_m":head_offset,"head_error_m":head_offset.length(),"primary_pelvis_displacement_world_m":primary_drop,"body_pelvis_displacement_world_m":body_drop,"coupler":surface.snapshot().swim_head_join,"original_rig_contact_maximum_m":primary.snapshot().maximum_contact_error_m,"swim_rig_contact_maximum_m":body.snapshot().maximum_contact_error_m})

func _run() -> void:
	for path: String in ["res://scripts/player/exploration_avatar.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://../tests/game/check_hybrid_neck_fit.gd","res://../tests/game/check_hybrid_gait_join.gd","res://assets/vendor/makehuman_swim/swim_male.glb","res://assets/vendor/makehuman_swim/swim_female.glb","res://assets/vendor/microsoft_rocketbox/Male_Adult_04/Export/Male_Adult_04.fbx","res://assets/vendor/microsoft_rocketbox/Female_Adult_07/Export/Female_Adult_07.fbx"]:source_hashes[path]=FileAccess.get_sha256(path)
	for id: String in ["Male_Adult_04","Female_Adult_07"]:
		var player:=CharacterBody3D.new();player.set_meta("human_model_id",id);var visual:=Node3D.new();visual.name="Visual";player.add_child(visual);var original:=MeshInstance3D.new();original.name="Body";original.mesh=CapsuleMesh.new();visual.add_child(original);root.add_child(player)
		var avatar: Node3D=load("res://scripts/player/exploration_avatar.gd").new();visual.add_child(avatar);_check(id+".actual_avatar_setup",avatar.setup(player));avatar.set_physics_process(false)
		var surface: Node3D=avatar._textured_surface;surface.set_swimwear(true)
		if not is_instance_valid(surface._swim_rig):_check(id+".actual_swim_rig_loaded",false);player.free();continue
		avatar._rest_pose();_record(id,"neutral",0.,surface)
		for mode: String in ["walk","run"]:
			for phase: float in [0.,.125,.25,.375,.5,.625,.75,.875]:
				avatar._rest_pose();avatar.state=mode;avatar.walk_weight=1.;avatar._run_weight=1. if mode=="run" else 0.;avatar.stride_phase=phase*TAU;avatar._stance_fraction=.4 if mode=="run" else .6
				var reach: float=(avatar.RUN_CYCLE_DISTANCE_M if mode=="run" else avatar.WALK_CYCLE_DISTANCE_M)*avatar._stance_fraction*.5;var lift:=.21 if mode=="run" else .075;var feet:={}
				for side: String in ["Left","Right"]:feet[side]=avatar._walking_foot(side,phase*TAU+(PI if side=="Right" else 0.),reach,lift)
				avatar._supported_hips(feet);avatar._pose_pelvis_gait(feet)
				for side: String in ["Left","Right"]:avatar._feet[side]=feet[side];avatar._leg_pose(side,feet[side])
				_record(id,mode,phase,surface)
		player.free();await process_frame
	var bindings:=true
	for path: String in source_hashes:bindings=bindings and FileAccess.get_sha256(path)==source_hashes[path]
	_check("production_and_test_sources_unchanged",bindings)
	var failed:=checks.filter(func(row: Dictionary)->bool:return not row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(_json({"task":"EXP29_HYBRID_GAIT_JOIN_DIAGNOSTIC","result":"PASS" if failed==0 else "FAIL","summary":{"checks":checks.size(),"failed":failed},"checks":checks,"cases":cases,"source_sha256":source_hashes,"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"scope":"Actual production dual-rig wardrobe wrapper. Original rig sync first, MakeHuman body rig second, neutral plus eight walking/eight running phases for each sex. Engine neck/head global positions, not proxy nodes or neutral-only fit. Read-only production diagnostic; no rendering, FPS, camera or real-time city acceptance."}),"  ")+"\n");file.close();print("HYBRID_GAIT_JOIN_RESULT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)
