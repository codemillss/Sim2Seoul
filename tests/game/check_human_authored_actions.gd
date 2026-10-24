extends "res://../tests/game/check_stable_motion.gd"
## Authored punch/flinch must retain upper-body ownership during real Input gait.
## Observe native anatomy, floor support, camera continuity and knuckle travel.
## Authored combat is anatomical IK; it must not be compared to old proxy FK.
signal authored_late_observed
var human: Node3D
var skeleton: Skeleton3D
var action_rows: Array=[]
var action_results: Array=[]
var active_action:=""
var previous_palm:=Vector3.ZERO
var palm_ready:=false

func _basis_error(actual: Basis,expected: Basis) -> float:
	return maxf(actual.x.normalized().distance_to(expected.x.normalized()),maxf(actual.y.normalized().distance_to(expected.y.normalized()),actual.z.normalized().distance_to(expected.z.normalized())))

func _observe_physics(_delta: float) -> void:pass

func _observe_render(delta_s: float) -> void:
	if not active_action.is_empty() and is_instance_valid(skeleton) and float(avatar._sandbox_remaining_s)>.08:
		var upper: Transform3D=human._source_pose(human._source_node("UpperBody"))
		var delta: Basis=(upper.basis*human._source_reference.UpperBody.basis.inverse()).orthonormalized()
		var length_error:=0.;var finite:=true;var minimum_sole:=INF
		for side: String in ["Left","Right"]:
			for pair: Array in [["UpperArm","Forearm"],["Forearm","Hand"],["Thigh","Shin"],["Shin","Foot"]]:
				var a: int=human._find(side+pair[0]);var b: int=human._find(side+pair[1])
				var actual_a: Transform3D=skeleton.get_bone_global_pose(a);var actual_b: Transform3D=skeleton.get_bone_global_pose(b)
				var expected_length: float=human._rest_global[a].origin.distance_to(human._rest_global[b].origin)
				length_error=maxf(length_error,absf(actual_a.origin.distance_to(actual_b.origin)-expected_length));finite=finite and actual_a.is_finite() and actual_b.is_finite()
			var foot: int=human._find(side+"Foot");var contact: Dictionary=human._sole_contacts.feet[side]
			for key: String in ["heel_local","toe_local"]:
				var point: Vector3=skeleton.global_transform*(skeleton.get_bone_global_pose(foot)*Vector3(contact[key]));minimum_sole=minf(minimum_sole,point.y)
		var neck: int=human._find("Neck");var neck_error: float=skeleton.get_bone_pose(neck).origin.distance_to(human._rest[neck].origin)
		var top: int=human._find("Spine2")
		var chest_error:=_basis_error(skeleton.get_bone_global_pose(top).basis,delta*human._rest_global[top].basis)
		var knuckle: Dictionary=human.combat_contact_world("Right")
		var palm: Vector3=_anchor().global_transform.affine_inverse()*Vector3(knuckle.point)
		var palm_speed:=palm.distance_to(previous_palm)/maxf(.00001,delta_s) if palm_ready else 0.;previous_palm=palm;palm_ready=true
		var offset: Vector3=Vector3.UP*rig.pivot_height_m+rig.global_basis.z*rig.current_distance
		var camera_error: float=(rig.camera.global_position-_anchor().global_position-offset).length()
		var snap: Dictionary=human.snapshot()
		action_rows.append({"remaining_s":avatar._sandbox_remaining_s,"source_torso_pitch_radians":upper.basis.get_euler().x,"maximum_native_segment_length_error_m":length_error,"source_native_chest_axis_error":chest_error,"right_knuckle_avatar_m":palm,"knuckle_speed_body_relative_mps":palm_speed,"native_neck_local_translation_error_m":neck_error,"lowest_native_heel_toe_world_y_m":minimum_sole,"camera_body_relative_error_m":camera_error,"native_finite":finite and palm.is_finite(),"ground_gait":snap.ground_gait_common_pelvis,"contact_mode":snap.contact_mode,"foot_contact_error_m":snap.maximum_contact_error_m,"speed_mps":Vector2(player.velocity.x,player.velocity.z).length()})
	authored_late_observed.emit()

func _wait_late(count: int) -> void:
	for index in range(count):await authored_late_observed

func _action_case(kind: String) -> void:
	await _place(Vector3(0,.08,0));player.walk_speed_mps=1.4
	_keys(["move_forward"]);await _wait_late(180)
	action_rows=[];palm_ready=false;active_action=kind;avatar.play_sandbox_action(kind,1.2)
	await _wait_late(132);active_action=""
	var length_error:=0.;var chest_error:=0.;var contact_error:=0.;var neck_error:=0.;var camera_error:=0.;var sole_error:=0.;var palm_speed:=0.;var finite:=true;var supported:=true;var minimum_speed:=INF
	var palm_min:=INF;var palm_max:=-INF;var pitch_min:=INF;var pitch_max:=-INF
	for row: Dictionary in action_rows:
		length_error=maxf(length_error,row.maximum_native_segment_length_error_m);chest_error=maxf(chest_error,row.source_native_chest_axis_error)
		neck_error=maxf(neck_error,row.native_neck_local_translation_error_m);camera_error=maxf(camera_error,row.camera_body_relative_error_m);sole_error=maxf(sole_error,absf(row.lowest_native_heel_toe_world_y_m));palm_speed=maxf(palm_speed,row.knuckle_speed_body_relative_mps)
		contact_error=maxf(contact_error,row.foot_contact_error_m);finite=finite and row.native_finite;supported=supported and row.ground_gait and not row.contact_mode
		minimum_speed=minf(minimum_speed,row.speed_mps);palm_min=minf(palm_min,-row.right_knuckle_avatar_m.z);palm_max=maxf(palm_max,-row.right_knuckle_avatar_m.z)
		pitch_min=minf(pitch_min,row.source_torso_pitch_radians);pitch_max=maxf(pitch_max,row.source_torso_pitch_radians)
	var result:={"action":kind,"samples":action_rows.size(),"maximum_native_segment_length_error_m":length_error,"maximum_source_native_chest_axis_error":chest_error,"maximum_foot_contact_error_m":contact_error,"maximum_neck_translation_error_m":neck_error,"maximum_camera_relative_error_m":camera_error,"maximum_lowest_heel_toe_floor_error_m":sole_error,"maximum_body_relative_knuckle_speed_mps":palm_speed,"native_finite":finite,"ground_gait_without_equipment_contact":supported,"minimum_speed_mps":minimum_speed,"right_knuckle_forward_range_m":[palm_min,palm_max],"source_pitch_range_radians":[pitch_min,pitch_max],"trace":action_rows}
	action_results.append(result)
	_check(kind+".active_Input_walk_and_ground_support_remain",action_rows.size()>100 and supported and minimum_speed>1.3 and contact_error<.01,result)
	_check(kind+".actual_native_arm_and_leg_segments_keep_anatomical_lengths",length_error<.00002,{"maximum_segment_error_m":length_error,"tolerance_m":.00002})
	_check(kind+".actual_native_neck_stays_connected",neck_error<.0005,{"maximum_local_translation_error_m":neck_error,"tolerance_m":.0005})
	_check(kind+".actual_gait_sole_landmarks_remain_on_floor",sole_error<.035,{"maximum_lowest_native_heel_toe_floor_error_m":sole_error,"tolerance_m":.035})
	_check(kind+".actual_camera_has_no_combat_shake",camera_error<.002,{"maximum_camera_body_relative_error_m":camera_error,"tolerance_m":.002})
	_check(kind+".actual_knuckle_motion_has_no_render_teleport",palm_speed<15.,{"maximum_body_relative_knuckle_speed_mps":palm_speed,"limit_mps":15.})
	_check(kind+".actual_native_chest_keeps_authored_source_orientation",chest_error<.0001,{"maximum_unit_axis_error":chest_error,"tolerance":.0001})
	_check(kind+".actual_native_bones_and_palm_remain_finite",finite)
	if kind=="punch":_check("punch.actual_native_knuckle_has_forward_travel",palm_max-palm_min>.25,{"actual_forward_range_m":[palm_min,palm_max],"predeclared_minimum_excursion_m":.25})
	else:_check("flinch.source_and_native_chest_recoil_is_exercised",pitch_max-pitch_min>.08,{"source_pitch_range_radians":[pitch_min,pitch_max],"predeclared_minimum_excursion_radians":.08})
	avatar.cancel_sandbox_action();_keys([]);await _wait_late(90)
	_check(kind+".stop_returns_to_idle_without_cached_attack",avatar.state=="idle" and avatar._sandbox_authored_pose.is_empty() and not avatar.has_meta("render_sandbox_pose") and avatar._sandbox_action.is_empty())

func _run() -> void:
	for path: String in ["res://project.godot","res://scripts/input_router.gd","res://scenes/player/camera_rig.tscn","res://scripts/player/camera_rig.gd","res://scripts/player/free_roam_player.gd","res://scripts/player/exploration_avatar.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://scripts/player/exploration_camera.gd","res://scripts/player/human_gait_support.gd","res://scripts/player/human_combat_poses.gd","res://assets/original/seoul_resident/seoul_resident_m01_street.glb","res://assets/original/seoul_resident/seoul_resident_f01_street.glb","res://assets/original/seoul_resident/AUTHORED_MANIFEST.json","res://../tests/game/check_jump.gd","res://../tests/game/check_stable_motion.gd","res://../tests/game/check_human_authored_actions.gd"]:
		if FileAccess.file_exists(path):source_hashes[path]=FileAccess.get_sha256(path)
	_setup_stable();await _wait_late(20)
	human=avatar._textured_surface.rig;skeleton=avatar._textured_surface.skeleton
	await _action_case("punch");await _action_case("flinch")
	avatar.play_sandbox_action("jab_left",.48);await _wait_late(8);avatar.cancel_sandbox_action();player.set_physics_process(false);await _wait_late(8)
	_check("transport_takeover_clears_earlier_attack_owner",avatar._sandbox_authored_pose.is_empty() and not avatar.has_meta("render_sandbox_pose"))
	avatar.play_sandbox_action("vehicle_enter",.4);avatar.cancel_sandbox_action("jab_left");await _wait_late(8)
	_check("stale_melee_cancel_cannot_erase_newer_vehicle_pose",avatar._sandbox_action=="vehicle_enter" and avatar._sandbox_remaining_s>0.)
	avatar.cancel_sandbox_action();player.set_physics_process(true);await _wait_late(100)
	var finger: int=human._find("RightFinger11")
	_check("resume_releases_actual_finger_and_render_attack_pose",avatar._sandbox_authored_pose.is_empty() and not avatar.has_meta("render_sandbox_pose") and skeleton.get_bone_pose_rotation(finger).get_angle()<.001)
	var stable:=true
	for path: String in source_hashes:stable=stable and source_hashes[path]==FileAccess.get_sha256(path)
	_check("source_bindings_remain_unchanged",stable)
	_check("original_collision_capsule_preserved",_capsule()==initial_capsule)
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;active_action="";_keys([])
	var failed: int=checks.filter(func(row: Dictionary)->bool:return not row.passed).size()
	var result:={"task":"HUMAN_AUTHORED_ACTION_OWNERSHIP","result":"PASS" if failed==0 else "FAIL","summary":{"checks":checks.size(),"failed":failed},"display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"physics_hz":Engine.physics_ticks_per_second,"source_sha256":source_hashes,"checks":checks,"cases":action_results,"scope":"Actual production Input.action_press walk1.4m/s plus production authored punch/flinch in isolated metre fixture. Late actual native arm/leg lengths, neck translation, sole floor landmarks, camera/body offset and knuckle continuity/forward travel are independently observed. Moving attacks retain walking foot contacts. Explicit transport ownership handoff fixture verifies cancellation and actual finger release. No gait or authored IK curve is copied into the oracle. Headless fixed-fps simulation is not native pixels, OS-input police gameplay, performance or subjective realism acceptance."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot write authored action ownership report");quit(2);return
	file.store_string(JSON.stringify(_json(result),"  ")+"\n");file.close()
	print("HUMAN_AUTHORED_ACTION_RESULT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)
