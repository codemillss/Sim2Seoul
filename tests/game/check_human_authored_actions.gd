extends "res://../tests/game/check_stable_motion.gd"
## Authored punch/flinch must retain upper-body ownership during real Input gait.
## Compare actual imported bones with corrected source directions, not gait curves.
signal authored_late_observed
var human: Node3D
var skeleton: Skeleton3D
var action_rows: Array=[]
var action_results: Array=[]
var active_action:=""

func _basis_error(actual: Basis,expected: Basis) -> float:
	return maxf(actual.x.normalized().distance_to(expected.x.normalized()),maxf(actual.y.normalized().distance_to(expected.y.normalized()),actual.z.normalized().distance_to(expected.z.normalized())))

func _observe_physics(_delta: float) -> void:pass

func _observe_render(_delta: float) -> void:
	if not active_action.is_empty() and is_instance_valid(skeleton) and float(avatar._sandbox_remaining_s)>.08:
		var upper: Transform3D=human._source_pose(human._source_node("UpperBody"))
		var delta: Basis=(upper.basis*human._source_reference.UpperBody.basis.inverse()).orthonormalized()
		var arm_error:=0.;var finite:=true
		for semantic: String in ["LeftUpperArm","LeftForearm","LeftHand","RightUpperArm","RightForearm","RightHand"]:
			# Hand rotation follows the authored forearm because its game proxy
			# is a grip position; the native correction retains the wrist rest.
			var source: String=semantic.replace("Hand","Forearm")
			var expected: Basis=human._source_pose(human._source_node(source)).basis*human._corrections[semantic]
			var actual: Transform3D=skeleton.get_bone_global_pose(human._find(semantic))
			arm_error=maxf(arm_error,_basis_error(actual.basis,expected));finite=finite and actual.is_finite()
		var top: int=human._find("Spine2")
		var chest_error:=_basis_error(skeleton.get_bone_global_pose(top).basis,delta*human._rest_global[top].basis)
		var palm: Vector3=_anchor().global_transform.affine_inverse()*skeleton.global_transform*(skeleton.get_bone_global_pose(human._find("RightHand"))*Vector3(human._hand_contacts.Right))
		var snap: Dictionary=human.snapshot()
		action_rows.append({"remaining_s":avatar._sandbox_remaining_s,"source_torso_pitch_radians":upper.basis.get_euler().x,"maximum_source_native_arm_axis_error":arm_error,"source_native_chest_axis_error":chest_error,"right_palm_avatar_m":palm,"native_finite":finite and palm.is_finite(),"ground_gait":snap.ground_gait_common_pelvis,"contact_mode":snap.contact_mode,"foot_contact_error_m":snap.maximum_contact_error_m,"speed_mps":Vector2(player.velocity.x,player.velocity.z).length()})
	authored_late_observed.emit()

func _wait_late(count: int) -> void:
	for index in range(count):await authored_late_observed

func _action_case(kind: String) -> void:
	await _place(Vector3(0,.08,0));player.walk_speed_mps=1.4
	_keys(["move_forward"]);await _wait_late(180)
	action_rows=[];active_action=kind;avatar.play_sandbox_action(kind,1.2)
	await _wait_late(132);active_action=""
	var arm_error:=0.;var chest_error:=0.;var contact_error:=0.;var finite:=true;var supported:=true;var minimum_speed:=INF
	var palm_min:=INF;var palm_max:=-INF;var pitch_min:=INF;var pitch_max:=-INF
	for row: Dictionary in action_rows:
		arm_error=maxf(arm_error,row.maximum_source_native_arm_axis_error);chest_error=maxf(chest_error,row.source_native_chest_axis_error)
		contact_error=maxf(contact_error,row.foot_contact_error_m);finite=finite and row.native_finite;supported=supported and row.ground_gait and not row.contact_mode
		minimum_speed=minf(minimum_speed,row.speed_mps);palm_min=minf(palm_min,-row.right_palm_avatar_m.z);palm_max=maxf(palm_max,-row.right_palm_avatar_m.z)
		pitch_min=minf(pitch_min,row.source_torso_pitch_radians);pitch_max=maxf(pitch_max,row.source_torso_pitch_radians)
	var result:={"action":kind,"samples":action_rows.size(),"maximum_source_native_arm_axis_error":arm_error,"maximum_source_native_chest_axis_error":chest_error,"maximum_foot_contact_error_m":contact_error,"native_finite":finite,"ground_gait_without_equipment_contact":supported,"minimum_speed_mps":minimum_speed,"right_palm_forward_range_m":[palm_min,palm_max],"source_pitch_range_radians":[pitch_min,pitch_max],"trace":action_rows}
	action_results.append(result)
	_check(kind+".active_Input_walk_and_ground_support_remain",action_rows.size()>100 and supported and minimum_speed>1.3 and contact_error<.01,result)
	_check(kind+".actual_native_arms_keep_authored_source_directions",arm_error<.0001,{"maximum_unit_axis_error":arm_error,"tolerance":.0001})
	_check(kind+".actual_native_chest_keeps_authored_source_orientation",chest_error<.0001,{"maximum_unit_axis_error":chest_error,"tolerance":.0001})
	_check(kind+".actual_native_bones_and_palm_remain_finite",finite)
	if kind=="punch":_check("punch.actual_palm_has_forward_travel",palm_max-palm_min>.08,{"actual_forward_range_m":[palm_min,palm_max],"predeclared_minimum_excursion_m":.08})
	else:_check("flinch.source_and_native_chest_recoil_is_exercised",pitch_max-pitch_min>.08,{"source_pitch_range_radians":[pitch_min,pitch_max],"predeclared_minimum_excursion_radians":.08})
	_keys([]);await _wait_late(90)

func _run() -> void:
	for path: String in ["res://project.godot","res://scripts/input_router.gd","res://scenes/player/camera_rig.tscn","res://scripts/player/camera_rig.gd","res://scripts/player/free_roam_player.gd","res://scripts/player/exploration_avatar.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://scripts/player/exploration_camera.gd","res://scripts/player/human_gait_support.gd","res://assets/vendor/microsoft_rocketbox/Male_Adult_04/Export/Male_Adult_04.fbx","res://assets/vendor/microsoft_rocketbox/PROVENANCE.json","res://../tests/game/check_jump.gd","res://../tests/game/check_stable_motion.gd","res://../tests/game/check_human_authored_actions.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	_setup_stable();await _wait_late(20)
	human=avatar._textured_surface.rig;skeleton=avatar._textured_surface.skeleton
	await _action_case("punch");await _action_case("flinch")
	var stable:=true
	for path: String in source_hashes:stable=stable and source_hashes[path]==FileAccess.get_sha256(path)
	_check("source_bindings_remain_unchanged",stable)
	_check("original_collision_capsule_preserved",_capsule()==initial_capsule)
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;active_action="";_keys([])
	var failed: int=checks.filter(func(row: Dictionary)->bool:return not row.passed).size()
	var result:={"task":"HUMAN_AUTHORED_ACTION_OWNERSHIP","result":"PASS" if failed==0 else "FAIL","summary":{"checks":checks.size(),"failed":failed},"display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"physics_hz":Engine.physics_ticks_per_second,"source_sha256":source_hashes,"checks":checks,"cases":action_results,"scope":"Actual production Input.action_press walk plus production play_sandbox_action punch/flinch in isolated metre fixture. Late-priority actual imported bone orientations are compared with authored source marker directions and native rest corrections; real palm travel and retained foot support are observed. No gait curve is copied into the oracle. Headless fixed-fps simulation is not native pixels, OS-input police gameplay, performance or subjective realism acceptance."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot write authored action ownership report");quit(2);return
	file.store_string(JSON.stringify(_json(result),"  ")+"\n");file.close()
	print("HUMAN_AUTHORED_ACTION_RESULT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)
