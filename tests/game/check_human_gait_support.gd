extends "res://../tests/game/check_textured_human_rig.gd"
## Independent native sole geometry and periodic-curve checks. These do not
## replace actual moving skin, stance-lock or native rear-view acceptance.
const SUPPORT := preload("res://scripts/player/human_gait_support.gd")
func _run() -> void:
	for path: String in ["res://scripts/player/human_gait_support.gd","res://scripts/player/exploration_avatar.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://../tests/game/check_human_gait_support.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	for run_weight: float in [0.,1.]:
		var duty:=lerpf(.60,.40,run_weight);var label_:="run" if run_weight>0. else "walk"
		var joins: Array[float]=[0.,duty*.18,duty*.65,duty,duty+(1.-duty)*.35,duty+(1.-duty)*.65,1.]
		var maximum_value_jump:=0.;var maximum_derivative_jump:=0.;var epsilon:=.00001
		for phase: float in joins:
			var a:=SUPPORT.angle((phase-epsilon)*TAU,duty,run_weight)
			var b:=SUPPORT.angle(phase*TAU,duty,run_weight)
			var c:=SUPPORT.angle((phase+epsilon)*TAU,duty,run_weight)
			maximum_value_jump=maxf(maximum_value_jump,absf(c-a))
			maximum_derivative_jump=maxf(maximum_derivative_jump,absf((c-b)/epsilon-(b-a)/epsilon))
		_check(label_+".periodic_roll_C1_at_all_contact_and_swing_joins",maximum_value_jump<.0001 and maximum_derivative_jump<.02,{"maximum_value_jump_radians":maximum_value_jump,"maximum_one_sided_derivative_jump_radians_per_cycle":maximum_derivative_jump,"finite_difference_step_cycle":epsilon,"joins":joins})
		_check(label_+".heel_strike_toe_up_flat_midstance_and_toe_off_heel_up",SUPPORT.angle(0.,duty,run_weight)>0. and absf(SUPPORT.angle(duty*.4*TAU,duty,run_weight))<.000001 and SUPPORT.angle(duty*.95*TAU,duty,run_weight)<0.)
		var bounded:=true;var idle:=true
		for sample: int in range(241):
			var phase:=float(sample)/240.*TAU
			var actual:=SUPPORT.angle(phase,duty,run_weight)
			bounded=bounded and actual<=SUPPORT.HEEL_STRIKE_RADIANS+.000001 and actual>=-SUPPORT.TOE_OFF_RADIANS-.000001
			idle=idle and SUPPORT.angle(phase,duty,run_weight,0.)==0.
		_check(label_+".dense_roll_bounded_10deg_heel_25deg_toe_and_idle_exactly_neutral",bounded and idle,{"sample_count":241})
	for id: String in ["Male_Adult_04","Female_Adult_07"]:
		var player:=CharacterBody3D.new();player.set_meta("pose_proxy_only",true)
		var visual:=Node3D.new();visual.name="Visual";player.add_child(visual)
		var original:=MeshInstance3D.new();original.name="Body";original.mesh=CapsuleMesh.new();original.material_override=StandardMaterial3D.new();visual.add_child(original);root.add_child(player)
		var avatar: Node3D=load("res://scripts/player/exploration_avatar.gd").new();visual.add_child(avatar)
		_check(id+".actual_production_weighted_human_setup",avatar.setup(player));avatar.set_physics_process(false)
		var path:=asset_root+id+"/Export/"+id+".fbx";source_hashes[path]=FileAccess.get_sha256(path)
		var model: Node3D=(load(path) as PackedScene).instantiate();avatar.add_child(model)
		var skeleton:=model.find_child("Skeleton3D",true,false) as Skeleton3D
		for animation: Node in model.find_children("*","AnimationPlayer",true,false):animation.stop();animation.active=false
		var bounds:=_skin_bounds(skeleton,model);var factor:=1.70/bounds.size.y
		model.scale=Vector3.ONE*factor;model.rotation.y=PI;model.position.y=-bounds.position.y*factor
		var rig: Node3D=load("res://scripts/player/textured_human_rig.gd").new();avatar.add_child(rig)
		_check(id+".actual_original_weighted_rig_setup",rig.setup(avatar,model,skeleton))
		var poses: Array[Transform3D]=[]
		for index: int in range(skeleton.get_bone_count()):poses.append(skeleton.get_bone_pose(index))
		var calibration:=SUPPORT.calibrate(rig)
		_check(id+".indexed_original_weighted_sole_pivots_found",bool(calibration.valid),calibration)
		if not bool(calibration.valid):player.free();continue
		var rest: Array=rig.get("_rest_global");var frame:=avatar.global_transform.affine_inverse()*skeleton.global_transform
		for side: String in ["Left","Right"]:
			var contact: Dictionary=calibration.feet[side];var foot: int=rig.call("_find",side+"Foot");var foot_rest: Transform3D=rest[foot]
			var ankle: Vector3=foot_rest.origin;var basis: Basis=foot_rest.basis
			var maximum_pivot_error:=0.;var ankle_only_error:=0.;var forward_lifted:=false;var rear_lifted:=false;var samples: Array=[]
			for degrees: float in [-25.,-10.,0.,5.,10.]:
				var angle_radians:=deg_to_rad(degrees);var result:=SUPPORT.corrected_goal(ankle,basis,contact,angle_radians)
				var q: Vector3=contact.heel_local if degrees>=0. else contact.toe_local
				var neutral_pivot:=ankle+basis*q
				var actual_pivot: Vector3=result.goal+result.basis*q
				var error: float=(frame*actual_pivot).distance_to(frame*neutral_pivot)
				maximum_pivot_error=maxf(maximum_pivot_error,error)
				var rolled_only:=ankle+Basis((basis*Vector3(contact.roll_axis_local)).normalized(),angle_radians)*basis*q
				ankle_only_error=maxf(ankle_only_error,(frame*rolled_only).distance_to(frame*neutral_pivot))
				if degrees>9.:
					var original_toe: Vector3=frame*(ankle+basis*Vector3(contact.toe_local))
					var actual_toe: Vector3=frame*(result.goal+result.basis*Vector3(contact.toe_local))
					forward_lifted=actual_toe.y>original_toe.y+.02
				if degrees< -24.:
					var original_heel: Vector3=frame*(ankle+basis*Vector3(contact.heel_local))
					var actual_heel: Vector3=frame*(result.goal+result.basis*Vector3(contact.heel_local))
					rear_lifted=actual_heel.y>original_heel.y+.06
				samples.append({"roll_degrees":degrees,"ankle_target_skeleton":result.goal,"basis_skeleton":Transform3D(result.basis,Vector3.ZERO),"actual_contact_avatar_m":frame*actual_pivot,"neutral_contact_avatar_m":frame*neutral_pivot,"contact_error_m":error})
			_check(id+"."+side+".corrected_ankle_keeps_actual_native_sole_pivot_fixed_under_roll",maximum_pivot_error<.000001,{"maximum_actual_pivot_error_m":maximum_pivot_error,"counterexample_ankle_only_roll_moves_contact_m":ankle_only_error,"samples":samples})
			_check(id+"."+side+".heel_strike_lifts_toe_and_toe_off_lifts_heel",forward_lifted and rear_lifted,{"toe_lift_over_20mm_at_10deg":forward_lifted,"heel_lift_over_60mm_at_25deg":rear_lifted})
		var unmodified:=true
		for index: int in range(skeleton.get_bone_count()):unmodified=unmodified and poses[index]==skeleton.get_bone_pose(index)
		_check(id+".calibration_and_pure_pose_geometry_do_not_modify_any_native_bone",unmodified,{"native_bones":skeleton.get_bone_count()})
		cases.append({"name":id,"calibration":calibration});player.free();await process_frame
	var failed:=checks.filter(func(row: Dictionary)->bool:return not row.passed).size()
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(_json({"task":"EXP30_HUMAN_GAIT_SUPPORT_GEOMETRY","result":"PASS" if failed==0 else "FAIL","summary":{"checks":checks.size(),"failed":failed},"checks":checks,"cases":cases,"source_sha256":source_hashes,"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"scope":"Pure periodic C1 roll curve and native rest-weighted sole geometry. Pivot preservation is checked independently from returned goal/basis and measured rest heel/toe patches. This fixture does not exercise production integration, moving blended skin, controller, render interpolation, native images, sustained performance or subjective naturalness."}),"  ")+"\n");file.close()
	print("HUMAN_GAIT_SUPPORT_RESULT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)
