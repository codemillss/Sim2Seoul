extends "res://../tests/game/check_stable_motion.gd"
## Native hand contacts during the facility-owned entry/exit animation branch.
## This isolated metre fixture does not prove full-world car routing or OS play.
signal late_observed
var human: Node3D
var skeleton: Skeleton3D
var active_vehicle_action := ""
var case_rows: Array=[]
var action_results: Array=[]

func _observe_physics(_delta: float) -> void:pass

func _observe_render(_delta: float) -> void:
	if not active_vehicle_action.is_empty() and is_instance_valid(skeleton):
		var snap: Dictionary=human.snapshot()
		var palms: Dictionary={};var hand_contact_error:=0.
		for side: String in ["Left","Right"]:
			var pose: Transform3D=skeleton.get_bone_global_pose(human._find(side+"Hand"))
			palms[side]=_anchor().global_transform.affine_inverse()*skeleton.global_transform*(pose*Vector3(human._hand_contacts[side]))
			hand_contact_error=maxf(hand_contact_error,float(snap.contacts[side+"Hand"].error_m))
		case_rows.append({"action":avatar._sandbox_action,"remaining_s":avatar._sandbox_remaining_s,"native_finite":snap.finite_bone_poses,"contact_mode":snap.contact_mode,"maximum_hand_contact_error_m":hand_contact_error,"palms_avatar_m":palms,"root":player.global_position,"camera_origin":rig.camera.global_position,"camera_basis":rig.camera.global_basis})
	late_observed.emit()

func _wait_late(count: int) -> void:
	for index in range(count):await late_observed

func _vehicle_case(kind: String,duration: float) -> void:
	await _place(Vector3(0,.08,0));_keys([]);await _wait_late(30)
	player.set_facility_control(true);await _wait_late(30)
	var original_root: Vector3=player.global_position
	var original_camera: Transform3D=rig.camera.global_transform
	var baseline: Dictionary=human.snapshot()
	var baseline_hand_error:=maxf(float(baseline.contacts.LeftHand.error_m),float(baseline.contacts.RightHand.error_m))
	active_vehicle_action=kind;case_rows=[];avatar.play_sandbox_action(kind,duration)
	await _wait_late(ceili((duration+.22)*120.));active_vehicle_action=""
	var contact_max:=0.;var finite:=true;var all_contact:=true;var root_drift:=0.;var camera_drift:=0.;var camera_turn:=0.;var samples:=0
	var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF)
	for row: Dictionary in case_rows:
		finite=finite and row.native_finite;all_contact=all_contact and row.contact_mode
		contact_max=maxf(contact_max,row.maximum_hand_contact_error_m)
		root_drift=maxf(root_drift,Vector3(row.root).distance_to(original_root))
		camera_drift=maxf(camera_drift,Vector3(row.camera_origin).distance_to(original_camera.origin))
		for axis: int in range(3):camera_turn=maxf(camera_turn,original_camera.basis[axis].distance_to(Basis(row.camera_basis)[axis]))
		if row.remaining_s>0.:
			samples+=1;var palm: Vector3=row.palms_avatar_m.Left
			low=low.min(palm);high=high.max(palm)
	var evidence:={"kind":kind,"duration_s":duration,"sample_count":samples,"baseline_native_hand_contact_error_m":baseline_hand_error,"maximum_native_hand_contact_error_m":contact_max,"left_palm_excursion_m":high-low,"maximum_root_drift_m":root_drift,"maximum_camera_drift_m":camera_drift,"maximum_camera_unit_axis_error":camera_turn,"trace":case_rows}
	action_results.append(evidence)
	_check(kind+".facility_owned_native_hand_contacts_remain",samples>50 and all_contact and contact_max<=baseline_hand_error+.001,evidence)
	_check(kind+".actual_native_left_hand_reaches_and_recovers",high.z-low.z>.04 and high.y-low.y>.02,{"actual_palm_range_m":high-low,"minimum_z_m":.04,"minimum_y_m":.02})
	_check(kind+".native_bones_finite_without_body_or_camera_impulse",finite and root_drift<.0001 and camera_drift<.0001 and camera_turn<.0001,{"finite":finite,"root_drift_m":root_drift,"camera_drift_m":camera_drift,"camera_unit_axis_error":camera_turn})
	_check(kind+".timed_action_finishes",avatar._sandbox_remaining_s<=0.,{"remaining_s":avatar._sandbox_remaining_s})
	player.set_facility_control(false);await _wait_late(30)

func _run() -> void:
	for path: String in ["res://scripts/city_public_safety.gd","res://scripts/explore_walk.gd","res://scripts/traffic_car_takeover.gd","res://scripts/player/exploration_avatar.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://scripts/player/free_roam_player.gd","res://scripts/player/exploration_camera.gd","res://../tests/game/check_jump.gd","res://../tests/game/check_stable_motion.gd","res://../tests/game/check_vehicle_transition_pose.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	_setup_stable();await _wait_late(20)
	human=avatar._textured_surface.rig;skeleton=avatar._textured_surface.skeleton
	await _vehicle_case("vehicle_enter",.78);await _vehicle_case("vehicle_exit",.65)
	avatar.play_sandbox_action("punch",.4);await _wait_late(6)
	avatar.cancel_sandbox_action("jab_left")
	_check("matching_cancel_preserves_a_different_current_action",avatar._sandbox_action=="punch" and avatar._sandbox_remaining_s>0.)
	avatar.cancel_sandbox_action("punch");player.set_facility_control(true);await _wait_late(120)
	player.set_facility_control(false);await _wait_late(60)
	_check("cancelled_melee_does_not_resume_after_facility_release",avatar._sandbox_action.is_empty() and avatar._sandbox_remaining_s<=0.)
	avatar.play_sandbox_action("cross_right",.48);avatar.play_sandbox_action("vehicle_enter",.78);avatar.cancel_sandbox_action("cross_right")
	_check("old_melee_cancel_preserves_new_vehicle_owner",avatar._sandbox_action=="vehicle_enter" and avatar._sandbox_remaining_s>.7)
	avatar.cancel_sandbox_action("vehicle_enter");avatar.set_sandbox_guarding(true);await _wait_late(30)
	avatar.cancel_sandbox_action("guard");player.set_facility_control(true);await _wait_late(30)
	player.set_facility_control(false);await _wait_late(30)
	_check("forced_guard_owner_loss_cannot_resume_held_pose",not avatar._sandbox_guarding and avatar._sandbox_guard_weight==0. and avatar._sandbox_action.is_empty())
	var stable:=true
	for path: String in source_hashes:stable=stable and source_hashes[path]==FileAccess.get_sha256(path)
	_check("source_bindings_remain_unchanged",stable)
	_check("original_collision_capsule_preserved",_capsule()==initial_capsule)
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_keys([])
	var failed: int=checks.filter(func(row: Dictionary)->bool:return not row.passed).size()
	var result:={"task":"VEHICLE_TRANSITION_POSE","result":"PASS" if failed==0 else "FAIL","summary":{"checks":checks.size(),"failed":failed},"display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"physics_hz":Engine.physics_ticks_per_second,"source_sha256":source_hashes,"checks":checks,"cases":action_results,"scope":"Actual production avatar facility-control branch and imported native hand/arm contacts for vehicle entry/exit in isolated metre fixture; unchanged retained root/camera/capsule. No real-world car path, visual or OS-input claim."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot write vehicle transition pose report");quit(2);return
	file.store_string(JSON.stringify(_json(result),"  ")+"\n");file.close()
	print("VEHICLE_TRANSITION_POSE_RESULT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)
