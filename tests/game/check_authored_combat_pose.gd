extends SceneTree
## Full-cycle original combat component inspection. Uses production posing and
## actual native bone globals; captures are visual evidence, not a quality score.
var report_path:=""
var checks: Array=[]
var captures: Array=[]
var samples: Array=[]
var actor: CharacterBody3D
var avatar: Node3D
var camera: Camera3D
var body_profile:="standard"
var female_model:=false
var swim_body:=false

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
		if argument.begins_with("--body-profile="):body_profile=argument.trim_prefix("--body-profile=")
		if argument=="--female-model":female_model=true
		if argument=="--swim-body":swim_body=true
	if not report_path.is_absolute_path():quit(2);return
	_run.call_deferred()

func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Basis:return [_json(value.x),_json(value.y),_json(value.z)]
	if value is Dictionary:
		var result:={}
		for key: Variant in value:result[str(key)]=_json(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value:result.append(_json(item))
		return result
	return value

func _check(label_: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":label_,"passed":passed,"evidence":_json(evidence)})
	if not passed:push_warning("AUTHORED_COMBAT_FAIL "+label_)

func _bone(semantic: String) -> Vector3:
	var rig: Node3D=avatar._textured_surface.active_native_rig()
	return rig.skeleton.global_transform*rig.skeleton.get_bone_global_pose(rig._find(semantic)).origin

func _pose(kind: String,phase: float) -> void:
	avatar._rest_pose();avatar._sandbox_action=kind;avatar._sandbox_duration_s=avatar.sandbox_action_duration(kind)
	avatar._sandbox_remaining_s=avatar._sandbox_duration_s*(1.-phase);avatar._sandbox_guarding=false
	avatar._sandbox_pose(0.)
	avatar._textured_surface.active_native_rig().sync_pose()
	await process_frame;await process_frame

func _capture(label_: String,point: Vector3,look_at_: Vector3) -> void:
	if DisplayServer.get_name()=="headless":return
	camera.global_position=point;camera.look_at(look_at_);await process_frame;await RenderingServer.frame_post_draw
	var path:=report_path.get_basename()+"_"+label_+".png";var code:=root.get_texture().get_image().save_png(path)
	_check("native_"+label_,code==OK)
	if code==OK:captures.append({"file":path,"sha256":FileAccess.get_sha256(path),"camera":camera.global_position,"scope":"Actual production skin and bone poses in an isolated, lit component scene. Camera framing only; not world collision or OS input."})

func _render_ownership() -> void:
	# Exercise the production presentation owner's snapshot/publication and
	# restore methods. This component test does not replace city camera sweeps.
	var presenter: Node3D=load("res://scripts/player/exploration_camera.gd").new()
	presenter._avatar_root=avatar
	for joint: Node3D in avatar._joints.values():presenter._joint_nodes.append(joint)
	presenter._joint_nodes.append(avatar._pelvis)
	var contact: float=avatar.sandbox_contact_phase("cross_right")
	await _pose("cross_right",contact*.65);presenter._capture_joint_poses(true)
	await _pose("cross_right",contact);presenter._capture_joint_poses(false)
	var physical_pelvis: Transform3D=avatar._pelvis.transform
	presenter._publish_joint_poses(.5)
	var rendered: Dictionary=avatar.get_meta("render_sandbox_pose",{})
	_check("render_phase_interpolates_combat_between_physical_ticks",not rendered.is_empty() and absf(float(rendered.get("phase",0.))-contact*.825)<.00001,{"phase":rendered.get("phase",-1.),"physical_previous":contact*.65,"physical_current":contact})
	_check("render_keeps_combat_hip_drop_instead_of_gait_wave",avatar._pelvis.position.y<.96,{"rendered_pelvis_y":avatar._pelvis.position.y})
	presenter._restore_physics_joints()
	_check("physics_restore_removes_render_combat_metadata",not avatar.has_meta("render_sandbox_pose") and avatar._pelvis.transform==physical_pelvis)
	avatar.cancel_sandbox_action();presenter._publish_joint_poses(.5)
	_check("cancel_does_not_resurrect_cached_render_attack",not avatar.has_meta("render_sandbox_pose"))
	avatar.set_sandbox_guarding(true);avatar._sandbox_pose(.1);presenter._capture_joint_poses(false);presenter._publish_joint_poses(1.)
	_check("held_guard_has_explicit_render_owner",avatar.has_meta("render_sandbox_pose"))
	presenter._facility_mode=true;presenter._publish_joint_poses(1.)
	_check("facility_takeover_discards_render_guard_owner",not avatar.has_meta("render_sandbox_pose"))
	avatar.set_sandbox_guarding(false);avatar.cancel_sandbox_action();presenter._restore_physics_joints();presenter.free()

func _run() -> void:
	root.size=Vector2i(960,840)
	var world:=Node3D.new();root.add_child(world)
	var env:=WorldEnvironment.new();var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.15,.17,.20);environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color(.75,.80,.90);environment.ambient_light_energy=.65;environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC;env.environment=environment;world.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-40,-30,0);light.light_energy=1.8;world.add_child(light)
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(6,6);ground.mesh=plane;var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.24,.27,.30);ground.material_override=mat;world.add_child(ground)
	actor=CharacterBody3D.new();var visual:=Node3D.new();visual.name="Visual";actor.add_child(visual);var original:=MeshInstance3D.new();original.name="Body";original.mesh=CapsuleMesh.new();visual.add_child(original);world.add_child(actor)
	actor.set_meta("human_model_id","SeoulResident_F01" if female_model else "SeoulResident_M01");actor.set_meta("human_body_profile",body_profile)
	avatar=load("res://scripts/player/exploration_avatar.gd").new();visual.add_child(avatar)
	_check("production_avatar_and_skin_loaded",avatar.setup(actor),avatar.textured_model_snapshot(false))
	avatar.set_physics_process(false)
	if avatar._textured_surface==null:quit(1);return
	avatar._textured_surface.set_swimwear(swim_body)
	var profile: Dictionary=avatar.textured_model_snapshot(false)
	_check("actual_requested_gender_profile_and_wardrobe_loaded",profile.model_id==("SeoulResident_F01" if female_model else "SeoulResident_M01") and profile.body_profile==body_profile and profile.swimwear_active==swim_body and not String(profile.active_glb_sha256).is_empty(),profile)
	camera=Camera3D.new();camera.fov=37.;world.add_child(camera);camera.current=true
	var rig: Node3D=avatar._textured_surface.active_native_rig()
	var neutral_lengths:={}
	for side: String in ["Left","Right"]:
		neutral_lengths[side]=[_bone(side+"UpperArm").distance_to(_bone(side+"Forearm")),_bone(side+"Forearm").distance_to(_bone(side+"Hand"))]
	for kind: String in ["jab_left","cross_right","hook_left","shove"]:
		var duration: float=avatar.sandbox_action_duration(kind);var contact: float=avatar.sandbox_contact_phase(kind)
		var phases: Array[float]=[0.,.075,.15,contact,.43,.60,.78,.96]
		var maximum_length_error:=0.;var maximum_position_error:=0.;var finite:=true
		for index: int in range(phases.size()):
			var phase: float=phases[index];await _pose(kind,phase)
			var point: Dictionary=avatar.get_sandbox_strike_contact(kind)
			for side: String in ["Left","Right"]:
				maximum_length_error=maxf(maximum_length_error,absf(_bone(side+"UpperArm").distance_to(_bone(side+"Forearm"))-float(neutral_lengths[side][0])))
				maximum_length_error=maxf(maximum_length_error,absf(_bone(side+"Forearm").distance_to(_bone(side+"Hand"))-float(neutral_lengths[side][1])))
			finite=finite and rig.snapshot().finite_bone_poses
			samples.append({"kind":kind,"phase":phase,"point":point,"pelvis":_bone("Pelvis"),"left_wrist":_bone("LeftHand"),"right_wrist":_bone("RightHand"),"left_elbow":_bone("LeftForearm"),"right_elbow":_bone("RightForearm"),"root":actor.global_position,"rig":rig.snapshot()})
			await _capture(kind+"_front_"+str(index),Vector3(1.45,1.42,-3.50),Vector3(0,.94,-.10))
			await _capture(kind+"_side_"+str(index),Vector3(-3.7,1.42,-.7),Vector3(0,.94,-.10))
			await _capture(kind+"_back_"+str(index),Vector3(-1.45,1.42,3.50),Vector3(0,.94,-.10))
		_check(kind+"_all_phases_native_bones_finite",finite)
		_check(kind+"_native_arms_never_stretch",maximum_length_error<.00002,{"maximum_segment_error_m":maximum_length_error})
		_check(kind+"_visual_weight_shift_never_moves_capsule",actor.global_position==Vector3.ZERO)
		await _pose(kind,contact);var strike: Dictionary=avatar.get_sandbox_strike_contact(kind)
		await _capture(kind+"_contact_hands",Vector3(.72,1.62,-1.35),Vector3(0.,1.42,-.40))
		_check(kind+"_actual_native_contact_reaches_forward",strike.valid and Vector3(strike.point).z<-.39 and Vector3(strike.point).y>1.15 and Vector3(strike.point).y<1.65,{"contact":strike})
		if kind!="shove":
			var side: String=strike.side;var finger: int=rig._find(side+"Finger11")
			_check(kind+"_actual_original_finger_bone_is_closed",finger>=0 and rig.skeleton.get_bone_pose_rotation(finger).get_angle()>.8,{"finger_index":finger,"rotation":rig.skeleton.get_bone_pose_rotation(finger).get_euler() if finger>=0 else Vector3.ZERO})
			var hand: int=rig._find(side+"Hand");var thumb_base: int=rig._find(side+"Finger0");var thumb_end: int=rig._find(side+"Finger02")
			var actual_hand: Transform3D=rig.skeleton.get_bone_global_pose(hand)
			var base_in_hand: Vector3=actual_hand.affine_inverse()*rig.skeleton.get_bone_global_pose(thumb_base).origin
			var end_in_hand: Vector3=actual_hand.affine_inverse()*rig.skeleton.get_bone_global_pose(thumb_end).origin
			_check(kind+"_thumb_opposes_across_palm_instead_of_hanging_outward",absf(end_in_hand.x)<absf(base_in_hand.x)*.85 and end_in_hand.z>.005 and end_in_hand.y>-.10,{"thumb_base_hand_local":base_in_hand,"thumb_distal_hand_local":end_in_hand,"scope":"Native articulated thumb landmark test; exposed skin still requires closeup visual review."})
	avatar.cancel_sandbox_action();avatar._rest_pose();rig.sync_pose()
	_check("cancel_removes_combat_pose_owner",avatar._sandbox_authored_pose.is_empty() and avatar._sandbox_action.is_empty())
	await _render_ownership()
	var hashes:={}
	for path: String in ["res://scripts/player/exploration_avatar.gd","res://scripts/player/exploration_camera.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/human_combat_poses.gd","res://scripts/player/textured_human_surface.gd","res://../tests/game/check_authored_combat_pose.gd"]:hashes[path]=FileAccess.get_sha256(path)
	var failed:=checks.filter(func(row: Dictionary)->bool:return not row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(_json({"task":"EXP34_original_authored_profile_combat_pose","body_profile":body_profile,"female_model_requested":female_model,"swim_body_requested":swim_body,"active_native_body":avatar.textured_model_snapshot(false),"result":"PASS" if failed==0 else "FAIL","passed":checks.size()-failed,"total":checks.size(),"checks":checks,"samples":samples,"captures":captures,"source_sha256":hashes,"scope":"Actual native production skeleton and original pose functions. Finite anatomy/unchanged capsule/contact reach checks plus full cycle front and side pixels; subjective visual review remains separate."}),"  ")+"\n");file.close()
	print("AUTHORED_COMBAT_POSE_RESULT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)
