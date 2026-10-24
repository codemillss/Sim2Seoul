extends "res://../tests/game/check_textured_human_rig.gd"
## Actual indexed material ownership of the authored strapless swim body.
## Independent of the generator's SDF and garment clipping implementation.
## This guards textile patches on exposed arms, not anatomical realism.
var material_cases: Array=[]
const ARM_WEIGHT_THRESHOLD:=.60
const MAX_CLOTH_ARM_AREA_M2:=.000001

func _source_vertices(surface: Node3D,row: Dictionary) -> PackedVector3Array:
	var frame: Transform3D=surface.avatar.global_transform.affine_inverse()*row.skeleton.global_transform
	var matrices: Array[Transform3D]=[]
	for binding: int in range(row.bind_bones.size()):matrices.append(frame*row.skeleton.get_bone_global_rest(row.bind_bones[binding])*row.mesh.skin.get_bind_pose(binding))
	var result:=PackedVector3Array();result.resize(row.vertices.size())
	for index: int in row.referenced:
		for slot: int in range(4):
			var weight: float=row.weights[index*4+slot]
			if weight>0.:result[index]+=(matrices[row.bones[index*4+slot]]*row.vertices[index])*weight
	return result

func _distance_to_segment(point: Vector3,a: Vector3,b: Vector3) -> float:
	var axis:=b-a;var fraction:=clampf((point-a).dot(axis)/axis.length_squared(),0.,1.)
	return point.distance_to(a+axis*fraction)

func _arm_materials(surface: Node3D,helper: Node3D,side: String) -> Dictionary:
	var skeleton: Skeleton3D=helper.skeleton;var frame: Transform3D=surface.avatar.global_transform.affine_inverse()*skeleton.global_transform
	var upper: Vector3=frame*skeleton.get_bone_global_rest(helper._find(side+"UpperArm")).origin
	var elbow: Vector3=frame*skeleton.get_bone_global_rest(helper._find(side+"Forearm")).origin
	var wrist: Vector3=frame*skeleton.get_bone_global_rest(helper._find(side+"Hand")).origin
	var arm_triangles:=0;var arm_area:=0.;var cloth_triangles:=0;var cloth_area:=0.;var examples: Array=[];var finite:=true;var roles: Dictionary={}
	for row: Dictionary in surface._surfaces:
		if row.skeleton!=skeleton:continue
		var name_: String=String(row.mesh.mesh.surface_get_material(int(row.surface)).resource_name)
		var textile: bool="swimwear" in name_.to_lower() or "trousers" in name_.to_lower()
		var points:=_source_vertices(surface,row);var influences:=PackedFloat32Array();influences.resize(points.size());var bindings: Dictionary={}
		for binding: int in range(row.bind_bones.size()):
			var title:=String(skeleton.get_bone_name(row.bind_bones[binding]))
			if title in (["Bip01 L UpperArm","Bip01 L Forearm","Bip01 L Hand"] if side=="Left" else ["Bip01 R UpperArm","Bip01 R Forearm","Bip01 R Hand"]):bindings[binding]=true
		for index: int in row.referenced:
			for slot: int in range(4):
				if bindings.has(row.bones[index*4+slot]):influences[index]+=row.weights[index*4+slot]
		var indices: PackedInt32Array=row.mesh.mesh.surface_get_arrays(int(row.surface))[Mesh.ARRAY_INDEX]
		var material_arm_triangles:=0
		for at: int in range(0,indices.size(),3):
			var a:=indices[at];var b:=indices[at+1];var c:=indices[at+2];var center: Vector3=(points[a]+points[b]+points[c])/3.
			var influence: float=(influences[a]+influences[b]+influences[c])/3.
			if influence<=ARM_WEIGHT_THRESHOLD or center.y<1.05 or center.y>upper.y+.035:continue
			# Bone proximity rejects torso triangles with a small shoulder blend;
			# no generator torso/arm distance field or garment rectangle is read.
			var bone_distance: float=minf(_distance_to_segment(center,upper,elbow),_distance_to_segment(center,elbow,wrist))
			if bone_distance>.115:continue
			var area: float=(points[b]-points[a]).cross(points[c]-points[a]).length()*.5
			finite=finite and points[a].is_finite() and points[b].is_finite() and points[c].is_finite() and is_finite(area)
			arm_triangles+=1;material_arm_triangles+=1;arm_area+=area
			if textile:
				cloth_triangles+=1;cloth_area+=area
				if examples.size()<8:examples.append({"surface_index":int(row.surface),"material_name":name_,"vertex_indices":[a,b,c],"source_points":[points[a],points[b],points[c]],"mean_arm_influence":influence,"bone_distance_m":bone_distance,"area_m2":area})
		if material_arm_triangles>0:roles[name_]=material_arm_triangles
	return {"side":side,"actual_all_material_arm_triangles":arm_triangles,"actual_all_material_arm_area_m2":arm_area,"actual_textile_arm_triangles":cloth_triangles,"actual_textile_arm_area_m2":cloth_area,"finite":finite,"materials":roles,"examples":examples,"criterion":{"minimum_mean_arm_weight":ARM_WEIGHT_THRESHOLD,"source_height_band_m":[1.05,upper.y+.035],"max_distance_to_actual_arm_bones_m":.115,"maximum_textile_arm_area_m2":MAX_CLOTH_ARM_AREA_M2},"scope":"Actual referenced source-rest indexed triangles and native bind weights across ALL skin+textile surfaces. Arm shaft classification is bone proximity plus independent mean arm influence; no production SDF/notch/garment rectangle is reused. This detects material assignment, not missing geometry or mesh-volume collapse."}

func _run() -> void:
	for path: String in ["res://scripts/player/exploration_avatar.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://../tools/authored_character/build_seoul_resident.py","res://../tests/game/check_swim_arm_skin.gd","res://assets/original/seoul_resident/AUTHORED_MANIFEST.json"]:source_hashes[path]=FileAccess.get_sha256(path)
	var variants:=0
	for id: String in ["SeoulResident_M01","SeoulResident_F01"]:
		var player:=CharacterBody3D.new();player.set_meta("human_model_id",id);var visual:=Node3D.new();visual.name="Visual";player.add_child(visual);var original:=MeshInstance3D.new();original.name="Body";original.mesh=CapsuleMesh.new();visual.add_child(original);root.add_child(player)
		var avatar: Node3D=load("res://scripts/player/exploration_avatar.gd").new();visual.add_child(avatar);_check(id+".production_avatar_setup",avatar.setup(player));avatar.set_physics_process(false)
		for profile: String in ["standard","soft","athletic"]:
			var label_: String=id+"_"+profile+"_swim";_check(label_+".profile_ready",avatar.set_authored_model(id,profile));var surface: Node3D=avatar._textured_surface
			surface.set_swimwear(true);avatar._rest_pose();var helper: Node3D=surface.active_native_rig();helper.sync_pose();var snapshot: Dictionary=surface.snapshot();variants+=1
			var expected: String="res://assets/original/seoul_resident/seoul_resident_"+("f01" if id=="SeoulResident_F01" else "m01")+("" if profile=="standard" else "_"+profile)+"_swim.glb"
			source_hashes[expected]=FileAccess.get_sha256(expected)
			_check(label_+".actual_active_native_asset_truthful",snapshot.active_glb_path==expected and snapshot.active_glb_sha256==source_hashes[expected] and snapshot.body_profile==profile and snapshot.swimwear_active and snapshot.skeleton_bone_count==52,snapshot)
			var actual_materials: Array=[]
			for row: Dictionary in surface._surfaces:
				if row.skeleton==helper.skeleton:actual_materials.append(String(row.mesh.mesh.surface_get_material(int(row.surface)).resource_name))
			_check(label_+".actual_skin_and_textile_surfaces_present",actual_materials.has("Resident_Jacket_or_Swimwear") and actual_materials.has("Resident_Authored_Skin"),{"actual_material_names":actual_materials})
			for side: String in ["Left","Right"]:
				var observation:=_arm_materials(surface,helper,side)
				_check(label_+"."+side+".all_material_arm_geometry_observed",observation.finite and observation.actual_all_material_arm_triangles>100 and observation.actual_all_material_arm_area_m2>.005,observation)
				_check(label_+"."+side+".exposed_arm_not_assigned_to_swim_textile",observation.actual_textile_arm_area_m2<=MAX_CLOTH_ARM_AREA_M2,observation)
				material_cases.append({"name":label_,"asset":expected,"asset_sha256":source_hashes[expected],"observation":observation})
			surface.set_swimwear(false)
		player.queue_free();await process_frame
	_check("all_six_gender_profile_swim_variants_exercised",variants==6,{"actual_variants":variants})
	var same:=true
	for path: String in source_hashes:same=same and FileAccess.get_sha256(path)==source_hashes[path]
	_check("actual_assets_and_fixture_sources_unchanged",same)
	var failed:=checks.filter(func(row: Dictionary)->bool:return not row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(_json({"task":"EXP34_SWIM_ARM_MATERIAL_OWNERSHIP","result":"PASS" if failed==0 else "FAIL","summary":{"checks":checks.size(),"failed":failed,"variants":variants,"arm_observations":material_cases.size()},"checks":checks,"material_cases":material_cases,"source_sha256":source_hashes,"scope":"Production six gender/profile native swim bodies. Actual indexed material membership, native source-rest bone proximity and bind weights across all skin+textile surfaces. Independent guard for a strapless swimsuit incorrectly coloring exposed inner arms; not a mesh-hole or anatomical-realism certificate."}),"  ")+"\n");file.close();print("SWIM_ARM_SKIN_RESULT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)
