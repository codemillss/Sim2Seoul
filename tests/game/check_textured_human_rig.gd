extends SceneTree
## Actual imported skin and production avatar pose functions in an isolated
## component fixture. This does not stand in for native city/wardrobe review.
var report_path:=""
var asset_root:="res://assets/vendor/microsoft_rocketbox/"
var checks: Array=[]
var cases: Array=[]
var source_hashes: Dictionary={}
var include_swim:=false
var expected_bones:=81

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
		if argument.begins_with("--asset-root="):asset_root=argument.trim_prefix("--asset-root=")
		if argument=="--include-swim":include_swim=true
	if not report_path.is_absolute_path():push_error("An absolute report path is required");quit(2);return
	_run.call_deferred()

func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is AABB:return {"position":_json(value.position),"size":_json(value.size)}
	if value is Transform3D:return {"origin":_json(value.origin),"basis":[_json(value.basis.x),_json(value.basis.y),_json(value.basis.z)]}
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
	if not passed:push_warning("TEXTURED_HUMAN_RIG_FAIL "+label_)

func _skin_bounds(skeleton: Skeleton3D,model: Node3D) -> AABB:
	var bounds:=AABB();var ready:=false
	for node: Node in model.find_children("*","MeshInstance3D",true,false):
		var mesh:=node as MeshInstance3D
		if not mesh.visible or mesh.skin==null:continue
		var skin_matrices: Array[Transform3D]=[]
		for index: int in range(mesh.skin.get_bind_count()):
			var title:=mesh.skin.get_bind_name(index);var bone:=skeleton.find_bone(title) if not title.is_empty() else mesh.skin.get_bind_bone(index)
			skin_matrices.append(skeleton.global_transform*skeleton.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(index))
		for surface: int in range(mesh.mesh.get_surface_count()):
			var arrays:=mesh.mesh.surface_get_arrays(surface);var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES];var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
			var influences: int=bones.size()/vertices.size()
			for index: int in range(vertices.size()):
				var point:=Vector3.ZERO
				for slot: int in range(influences):
					var weight:=weights[index*influences+slot]
					if weight>0.:point+=(skin_matrices[bones[index*influences+slot]]*vertices[index])*weight
				bounds=AABB(point,Vector3.ZERO) if not ready else bounds.expand(point);ready=true
	return bounds

func _sample(label_: String,avatar: Node3D,helper: Node3D,skeleton: Skeleton3D,model: Node3D) -> void:
	var saved: Dictionary={}
	for key: String in avatar._joints:saved[key]=avatar._joints[key].transform
	var synced: bool=helper.sync_pose();var snapshot: Dictionary=helper.snapshot();var unchanged:=true
	for key: String in saved:unchanged=unchanged and avatar._joints[key].transform==saved[key]
	var actual_errors:={};var maximum:=0.
	for key: String in helper._goals:
		var row: Dictionary=helper._goals[key];var actual: Vector3=skeleton.global_transform*(skeleton.get_bone_global_pose(row.index)*row.contact);var target: Vector3=skeleton.global_transform*row.target;var error:=actual.distance_to(target)
		actual_errors[key]=error
		if row.required:maximum=maxf(maximum,error)
	var bounds:=_skin_bounds(skeleton,model)
	_check(label_+".finite_all_imported_bone_poses",synced and snapshot.finite_bone_poses and skeleton.get_bone_count()==expected_bones,snapshot)
	_check(label_+".actual_engine_hand_and_foot_contacts",maximum<.010,{"actual_engine_errors_m":actual_errors,"maximum_error_m":maximum,"component":snapshot})
	_check(label_+".retarget_does_not_modify_source_pose_markers",unchanged)
	_check(label_+".actual_deformed_skin_bounds_finite",bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.y>.6 and bounds.size.y<2.1,{"actual_cpu_skinned_bounds":bounds})
	var maximum_length_error:=0.
	for side: String in ["Left","Right"]:
		for segment: Array in [["UpperArm","Forearm"],["Forearm","Hand"]]:
			var a: int=helper._find(side+segment[0]);var b: int=helper._find(side+segment[1])
			var current_a: Vector3=skeleton.global_transform*skeleton.get_bone_global_pose(a).origin;var current_b: Vector3=skeleton.global_transform*skeleton.get_bone_global_pose(b).origin
			var rest_a: Vector3=skeleton.global_transform*helper._rest_global[a].origin;var rest_b: Vector3=skeleton.global_transform*helper._rest_global[b].origin
			maximum_length_error=maxf(maximum_length_error,absf(current_a.distance_to(current_b)-rest_a.distance_to(rest_b)))
	_check(label_+".real_arm_lengths_are_not_stretched_to_old_markers",maximum_length_error<.00001,{"maximum_segment_length_error_m":maximum_length_error})
	_check(label_+".contact_lean_bounded_and_ordinary_gait_has_no_extra_lean",float(snapshot.contact_lean_degrees)<=25.001 and (snapshot.contact_mode or float(snapshot.contact_lean_degrees)==0.),{"degrees":snapshot.contact_lean_degrees,"contact_mode":snapshot.contact_mode})
	cases.append({"name":label_,"rig":snapshot,"actual_engine_contact_errors_m":actual_errors,"actual_cpu_skinned_bounds":bounds})

func _run() -> void:
	for path: String in ["res://scripts/player/exploration_avatar.gd","res://scripts/player/human_surface_meshes.gd","res://scripts/player/human_activity_dimensions.gd","res://scripts/player/textured_human_rig.gd","res://../tests/game/check_textured_human_rig.gd"]:
		if FileAccess.file_exists(path):source_hashes[path]=FileAccess.get_sha256(path)
	var models: Array=[{"id":"Male_Adult_04","path":asset_root+"Male_Adult_04/Export/Male_Adult_04.fbx","bones":81},{"id":"Female_Adult_07","path":asset_root+"Female_Adult_07/Export/Female_Adult_07.fbx","bones":81}]
	if include_swim:
		models.append({"id":"swim_male","path":"res://assets/vendor/makehuman_swim/swim_male.glb","bones":163})
		models.append({"id":"swim_female","path":"res://assets/vendor/makehuman_swim/swim_female.glb","bones":163})
	for specification: Dictionary in models:
		var id: String=specification.id;expected_bones=int(specification.bones)
		var player:=CharacterBody3D.new();player.set_meta("pose_proxy_only",true);var visual:=Node3D.new();visual.name="Visual";player.add_child(visual);var original:=MeshInstance3D.new();original.name="Body";original.mesh=CapsuleMesh.new();visual.add_child(original);root.add_child(player)
		var avatar: Node3D=load("res://scripts/player/exploration_avatar.gd").new();visual.add_child(avatar);_check(id+".production_avatar_markers_ready",avatar.setup(player));avatar.set_physics_process(false)
		var model_path: String=specification.path;source_hashes[model_path]=FileAccess.get_sha256(model_path)
		var model: Node3D
		if model_path.ends_with(".glb"):
			var document:=GLTFDocument.new();var imported_state:=GLTFState.new();var result:=document.append_from_file(ProjectSettings.globalize_path(model_path),imported_state)
			if result==OK:model=document.generate_scene(imported_state)
		else:
			var packed:=load(model_path) as PackedScene
			if packed!=null:model=packed.instantiate() as Node3D
		if model==null:_check(id+".actual_imported_model_loaded",false);player.free();continue
		model.name="AvatarVisual";avatar.add_child(model)
		var skeleton:=model.find_child("Skeleton3D",true,false) as Skeleton3D
		for animation: Node in model.find_children("*","AnimationPlayer",true,false):animation.stop();animation.active=false
		var initial:=_skin_bounds(skeleton,model);var scale_factor:=1.70/initial.size.y;model.scale=Vector3.ONE*scale_factor;model.rotation.y=PI;model.position.y=-initial.position.y*scale_factor
		var helper:=load("res://scripts/player/textured_human_rig.gd").new() as Node3D;avatar.add_child(helper)
		_check(id+".retarget_setup",helper.setup(avatar,model,skeleton),helper.snapshot())
		if not helper.loaded:player.free();continue
		_sample(id+"_neutral",avatar,helper,skeleton,model)
		var neutral:=_skin_bounds(skeleton,model)
		_check(id+".visible_neutral_height_stays_1_70m",absf(neutral.size.y-1.7)<.025 and absf(neutral.position.y)<.025,{"actual_cpu_skinned_bounds":neutral})
		for phase: float in [0.,.25,.5,.75]:
			avatar._rest_pose();var feet:={}
			for side: String in ["Left","Right"]:
				var cycle:=phase*TAU+(PI if side=="Right" else 0.)
				feet[side]=avatar._gait_foot(-1. if side=="Left" else 1.,cycle,.32,.14)
			avatar._supported_hips(feet)
			for side: String in ["Left","Right"]:avatar._leg_pose(side,feet[side])
			_sample(id+"_gait_"+str(phase),avatar,helper,skeleton,model)
		for kind: String in ["eat","weights","cycle","rowing"]:
			for elapsed: float in [0.,.3,.6,.9,1.2,1.8,2.4]:
				avatar.set_activity(kind,elapsed);_sample(id+"_"+kind+"_"+str(elapsed),avatar,helper,skeleton,model)
		avatar.set_activity("",0.);player.free();await process_frame
	var failed:=checks.filter(func(row: Dictionary)->bool:return not row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(_json({"task":"EXP29_TEXTURED_HUMAN_RETARGET","result":"PASS" if failed==0 else "FAIL","summary":{"checks":checks.size(),"failed":failed},"checks":checks,"cases":cases,"source_sha256":source_hashes,"display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"scope":"Actual Microsoft Rocketbox FBX/Skin with production avatar marker/IK/activity functions, original source transforms checked before/after sync, actual Godot bone-global hand/foot contacts and CPU-skinned bounds. Component-pose fixtures only; not city physics, wardrobe, OS input, visual quality or runtime performance acceptance."}),"  ")+"\n");file.close();print("TEXTURED_HUMAN_RIG_RESULT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)
