extends "res://../tests/game/check_human_gait_continuity.gd"
## Independent actual native upper-body observations. No authored curve is
## copied into the oracle; numeric design checks do not approve visual realism.
var upper_rows: Array=[]
var upper_results: Array=[]
var transition_results: Array=[]
var upper_recording:=false
const SEMANTICS := ["Pelvis","Spine","Spine1","Spine2","Neck","Head","LeftClavicle","RightClavicle","LeftUpperArm","RightUpperArm","LeftForearm","RightForearm","LeftHand","RightHand","LeftThigh","RightThigh","LeftFoot","RightFoot"]

func _observe_render(delta: float) -> void:
	if (sampling or upper_recording) and is_instance_valid(skeleton):
		var marker: Node3D=_anchor();var inv:=marker.global_transform.affine_inverse()
		var positions:={};var rotations:={};var local_origin_errors:={};var finite:=true
		for semantic: String in SEMANTICS:
			var index: int=human._find(semantic)
			if index<0:continue
			var pose: Transform3D=inv*skeleton.global_transform*skeleton.get_bone_global_pose(index)
			positions[semantic]=pose.origin;rotations[semantic]=pose.basis.get_rotation_quaternion()
			var rest: Transform3D=skeleton.get_bone_rest(index)
			local_origin_errors[semantic]=skeleton.get_bone_pose(index).origin.distance_to(rest.origin)*skeleton.global_basis.get_scale().abs().x
			finite=finite and pose.is_finite()
		var elbows:={};var palms:={};var lengths:={}
		for side: String in ["Left","Right"]:
			var shoulder: Vector3=positions[side+"UpperArm"];var elbow: Vector3=positions[side+"Forearm"];var wrist: Vector3=positions[side+"Hand"]
			elbows[side]=rad_to_deg(PI-(shoulder-elbow).angle_to(wrist-elbow))
			var hand: int=human._find(side+"Hand")
			palms[side]=inv*skeleton.global_transform*(skeleton.get_bone_global_pose(hand)*Vector3(human._hand_contacts[side]))
			for pair: Array in [["UpperArm","Forearm"],["Forearm","Hand"]]:
				var a: int=human._find(side+pair[0]);var b: int=human._find(side+pair[1])
				var rest_length: float=(skeleton.global_basis*(human._rest_global[b].origin-human._rest_global[a].origin)).length()
				lengths[side+pair[0]]=absf(Vector3(positions[side+pair[0]]).distance_to(positions[side+pair[1]])-rest_length)
		var shoulder_axis: Vector3=positions.RightUpperArm-positions.LeftUpperArm
		var hip_axis: Vector3=positions.RightThigh-positions.LeftThigh
		upper_rows.append({"dt":delta,"frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"render_fraction":Engine.get_physics_interpolation_fraction(),"positions":positions,"rotations":rotations,"palms":palms,"elbow_flex_degrees":elbows,"arm_length_error_m":lengths,"local_origin_errors_m":local_origin_errors,"shoulder_yaw_radians":atan2(shoulder_axis.z,shoulder_axis.x),"hip_yaw_radians":atan2(hip_axis.z,hip_axis.x),"finite":finite,"speed_mps":Vector2(player.velocity.x,player.velocity.z).length(),"walk_weight":avatar.walk_weight,"run_weight":avatar._run_weight,"state":avatar.state})
	super._observe_render(delta)

func _corr(a: Array[float],b: Array[float]) -> float:
	if a.size()!=b.size() or a.size()<3:return 0.
	var ma:=0.;var mb:=0.
	for value: float in a:ma+=value
	for value: float in b:mb+=value
	ma/=a.size();mb/=b.size()
	var cov:=0.;var va:=0.;var vb:=0.
	for index: int in range(a.size()):
		var da:=a[index]-ma;var db:=b[index]-mb;cov+=da*db;va+=da*da;vb+=db*db
	return cov/sqrt(va*vb) if va*vb>.0000000001 else 0.

func _upper_metrics() -> Dictionary:
	var shoulder_yaw: Array[float]=[];var hip_yaw: Array[float]=[];var torso_hip: Array[float]=[]
	var palms:={"Left":[],"Right":[]};var feet:={"Left":[],"Right":[]};var elbow:={"Left":[],"Right":[]};var swing_y:={"Left":[],"Right":[]}
	var max_length:=0.;var max_origin:=0.;var max_head_origin:=0.;var finite:=true;var max_wrist_speed:=0.;var max_arm_angular_speed:=0.;var max_torso_angular_speed:=0.;var max_wrist_frame:=0.
	for index: int in range(upper_rows.size()):
		var row: Dictionary=upper_rows[index]
		shoulder_yaw.append(row.shoulder_yaw_radians);hip_yaw.append(row.hip_yaw_radians);torso_hip.append(angle_difference(row.hip_yaw_radians,row.shoulder_yaw_radians));finite=finite and row.finite
		for value: float in row.arm_length_error_m.values():max_length=maxf(max_length,value)
		for key: String in row.local_origin_errors_m:
			if key in ["Neck","Head"]:max_head_origin=maxf(max_head_origin,row.local_origin_errors_m[key])
			elif key in ["LeftClavicle","RightClavicle","LeftUpperArm","RightUpperArm"]:max_origin=maxf(max_origin,row.local_origin_errors_m[key])
		for side: String in ["Left","Right"]:
			palms[side].append(-float(row.palms[side].z));feet[side].append(-float(row.positions[side+"Foot"].z));elbow[side].append(float(row.elbow_flex_degrees[side]));swing_y[side].append(float(row.palms[side].y))
		if index==0:continue
		var previous: Dictionary=upper_rows[index-1];var dt: float=row.dt
		if dt<=0.:continue
		for side: String in ["Left","Right"]:
			var wrist: float=Vector3(row.palms[side]).distance_to(previous.palms[side]);max_wrist_frame=maxf(max_wrist_frame,wrist);max_wrist_speed=maxf(max_wrist_speed,wrist/dt)
			for semantic: String in [side+"UpperArm",side+"Forearm",side+"Hand"]:max_arm_angular_speed=maxf(max_arm_angular_speed,Quaternion(row.rotations[semantic]).angle_to(previous.rotations[semantic])/dt)
		for semantic: String in ["Spine1","Spine2"]:
			if row.rotations.has(semantic):max_torso_angular_speed=maxf(max_torso_angular_speed,Quaternion(row.rotations[semantic]).angle_to(previous.rotations[semantic])/dt)
	var forward_ranges:={};var elbow_ranges:={};var palm_y_ranges:={};var same_side_correlations:={}
	for side: String in ["Left","Right"]:
		var p: Array[float]=[];var e: Array[float]=[];var y: Array[float]=[];var f: Array[float]=[]
		for value: float in palms[side]:p.append(value)
		for value: float in elbow[side]:e.append(value)
		for value: float in swing_y[side]:y.append(value)
		for value: float in feet[side]:f.append(value)
		forward_ranges[side]=_range(p);elbow_ranges[side]=_range(e);palm_y_ranges[side]=_range(y);same_side_correlations[side]=_corr(p,f)
	var left: Array[float]=[];var right: Array[float]=[]
	for value: float in palms.Left:left.append(value)
	for value: float in palms.Right:right.append(value)
	return {"samples":upper_rows.size(),"finite":finite,"palm_forward_ranges_m":forward_ranges,"palm_vertical_ranges_m":palm_y_ranges,"elbow_flex_degrees":elbow_ranges,"shoulder_yaw_range_radians":_range(shoulder_yaw),"hip_yaw_range_radians":_range(hip_yaw),"shoulder_minus_hip_yaw_range_radians":_range(torso_hip),"shoulder_hip_yaw_correlation":_corr(shoulder_yaw,hip_yaw),"left_right_palm_correlation":_corr(left,right),"same_side_palm_foot_forward_correlation":same_side_correlations,"maximum_original_arm_length_error_m":max_length,"maximum_shoulder_clavicle_local_translation_error_m":max_origin,"maximum_neck_head_local_translation_error_m":max_head_origin,"maximum_palm_speed_mps":max_wrist_speed,"maximum_arm_angular_speed_radians_s":max_arm_angular_speed,"maximum_torso_angular_speed_radians_s":max_torso_angular_speed,"maximum_one_render_palm_change_m":max_wrist_frame}

func _analyse(mode: String,speed: float) -> void:
	super._analyse(mode,speed)
	# Lower-body acceptance is preserved, but do not duplicate its large trace.
	gait_results[-1].erase("trace")
	var row:=_upper_metrics();row["mode"]=mode;row["configured_speed_mps"]=speed
	var forward_min:=.12 if mode=="walk" else .20
	var elbow_low:=5. if mode=="walk" else 45.;var elbow_high:=105. if mode=="walk" else 130.
	_check(mode+".actual_upper_native_bones_and_palms_finite",row.finite and int(row.samples)>=SAMPLE_TICKS-2)
	_check(mode+".actual_native_arm_lengths_and_shoulder_connections_preserved",float(row.maximum_original_arm_length_error_m)<.00002 and float(row.maximum_shoulder_clavicle_local_translation_error_m)<.00002,row)
	_check(mode+".neck_and_head_keep_anatomical_local_connections",float(row.maximum_neck_head_local_translation_error_m)<.0005,{"maximum_local_translation_error_m":row.maximum_neck_head_local_translation_error_m})
	_check(mode+".shoulders_and_chest_have_small_nonzero_turn",float(row.shoulder_yaw_range_radians.excursion)>deg_to_rad(2.) and float(row.shoulder_yaw_range_radians.excursion)<deg_to_rad(25.) and float(row.shoulder_minus_hip_yaw_range_radians.excursion)>deg_to_rad(2.),row)
	_check(mode+".actual_left_right_arms_counter_swing",float(row.left_right_palm_correlation)<-.5,row)
	_check(mode+".actual_same_side_arm_and_leg_are_in_opposite_phase",float(row.same_side_palm_foot_forward_correlation.Left)<-.20 and float(row.same_side_palm_foot_forward_correlation.Right)<-.20,row)
	for side: String in ["Left","Right"]:
		_check(mode+"."+side+"_actual_palm_travels_forward_and_back",float(row.palm_forward_ranges_m[side].excursion)>forward_min,{"actual_range_m":row.palm_forward_ranges_m[side],"predeclared_minimum_m":forward_min})
		_check(mode+"."+side+"_elbow_is_bent_and_changes_through_stride",float(row.elbow_flex_degrees[side].minimum)>=elbow_low and float(row.elbow_flex_degrees[side].maximum)<=elbow_high and float(row.elbow_flex_degrees[side].excursion)>3.,{"actual_flexion_degrees":row.elbow_flex_degrees[side],"predeclared_range_degrees":[elbow_low,elbow_high],"minimum_variation_degrees":3.})
	_check(mode+".actual_palms_and_arm_rotations_have_no_one_frame_flip",float(row.maximum_palm_speed_mps)<(5. if mode=="walk" else 8.) and float(row.maximum_arm_angular_speed_radians_s)<(12. if mode=="walk" else 18.) and float(row.maximum_torso_angular_speed_radians_s)<4.,row)
	var trace: Array=[]
	for index: int in range(0,upper_rows.size(),4):
		var sample: Dictionary=upper_rows[index].duplicate(true);sample.erase("rotations");trace.append(sample)
	row["every_fourth_actual_render_trace"]=trace;upper_results.append(row)

func _trial(mode: String,speed: float) -> void:
	upper_rows=[];await super._trial(mode,speed)

func _transition(mode: String,speed: float) -> void:
	await _place(Vector3(0,.08,0));player.walk_speed_mps=speed;player.run_speed_mps=speed
	upper_rows=[];upper_recording=true;_keys(["move_forward","move_fast"] if mode=="run" else ["move_forward"]);await _wait_steps(120);upper_recording=false
	var start:=_upper_metrics();start["mode"]=mode;start["phase"]="start";transition_results.append(start)
	upper_rows=[];upper_recording=true;_keys([]);await _wait_steps(180);upper_recording=false
	var stop:=_upper_metrics();stop["mode"]=mode;stop["phase"]="stop";transition_results.append(stop)
	_check(mode+".actual_start_stop_palms_and_bones_are_finite",start.finite and stop.finite and int(start.samples)>100 and int(stop.samples)>150)
	_check(mode+".actual_start_stop_has_no_wrist_or_torso_flip",float(start.maximum_arm_angular_speed_radians_s)<20. and float(stop.maximum_arm_angular_speed_radians_s)<20. and float(start.maximum_torso_angular_speed_radians_s)<5. and float(stop.maximum_torso_angular_speed_radians_s)<5.,{"start":start,"stop":stop})
	_check(mode+".released_input_returns_to_actual_idle",Vector2(player.velocity.x,player.velocity.z).length()<.01 and avatar.walk_weight<.001,{"velocity":player.velocity,"walk_weight":avatar.walk_weight})

func _run() -> void:
	for file: String in DirAccess.get_files_at("res://scripts/player/"):
		if file.ends_with(".gd"):var path:="res://scripts/player/"+file;source_hashes[path]=FileAccess.get_sha256(path)
	for path: String in ["res://../tests/game/check_human_upper_gait.gd","res://../tests/game/check_human_gait_continuity.gd","res://../tests/game/check_stable_motion.gd","res://../tests/game/check_jump.gd","res://assets/original/seoul_resident/seoul_resident_m01_street.glb","res://assets/original/seoul_resident/seoul_resident_f01_street.glb"]:source_hashes[path]=FileAccess.get_sha256(path)
	_setup_stable();await _wait_steps(20);await _place(Vector3(0,.08,0))
	surface=avatar._textured_surface;human=surface.rig;skeleton=surface.skeleton
	_prepare_skin_patches();await _trial("walk",1.4);await _trial("run",3.5)
	await _transition("walk",1.4);await _transition("run",3.5)
	var same:=true
	for path: String in source_hashes:same=same and FileAccess.get_sha256(path)==source_hashes[path]
	_check("source_bindings_unchanged",same)
	_check("original_capsule_and_physics_roots_preserved",_capsule()==initial_capsule and avatar.find_children("*","CollisionObject3D",true,false).is_empty())
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;sampling=false;upper_recording=false;_keys([])
	var failed:=checks.filter(func(row: Dictionary)->bool:return not row.passed).size()
	var report:={"task":"EXP31_ACTUAL_UPPER_BODY_GAIT","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"model_id":surface.model_id if is_instance_valid(surface) else "","physics_hz":Engine.physics_ticks_per_second,"requested_render_cap_hz":OBSERVATION_HZ,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"lower_body_trials":gait_results,"upper_body_trials":upper_results,"start_stop_trials":transition_results,"source_sha256":source_hashes,"scope":"Actual production Input-driven controller and native weighted-human skeleton. Upper-body sample points/arm lengths/elbow flex/shoulder and hip axes are independently observed in displayed actor frame; no production gait curve is reused as the oracle. Inherited actual CPU skin sole/lower-body checks retained. Requested120renderframes at recorded30/120physics, not sustainedFPS. Four-second steady walk/run plus actual start/stop. Numeric project-design limits do not establish mocap quality, native pixel naturalness, OS input or subjective comfort."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot write upper gait report");quit(2);return
	file.store_string(JSON.stringify(_json(report),"  ")+"\n");file.close();print("HUMAN_UPPER_GAIT_RESULT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)
