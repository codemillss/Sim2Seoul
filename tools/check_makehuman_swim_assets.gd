extends SceneTree
var repo_root:=ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var output:="data/reports/human_presence/20261022/appearance/makehuman_asset_probe_current.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):output=argument.trim_prefix("--report=")
	var destination:=repo_root+"/"+output
	if FileAccess.file_exists(destination):push_error("Evidence already exists; select a fresh --report path");quit(2);return
	var report:={"scope":"Actual Godot4 GLTFDocument import and CPU skin rest bounds of both original CC0 data-derived swim GLBs; not a movement or native visual acceptance.","checks":[],"variants":[]}
	for sex: String in ["male","female"]:
		var path:=repo_root+"/game/assets/vendor/makehuman_swim/swim_"+sex+".glb"
		var doc:=GLTFDocument.new();var state:=GLTFState.new();var error:=doc.append_from_file(path,state)
		_check(report,sex+"_parse",error==OK,{"error":error})
		if error!=OK:continue
		var scene:=doc.generate_scene(state);root.add_child(scene)
		await process_frame
		var skeleton: Skeleton3D
		for node: Node in scene.find_children("*","Skeleton3D",true,false):skeleton=node as Skeleton3D;break
		_check(report,sex+"_skeleton163",skeleton!=null and skeleton.get_bone_count()==163,{"count":skeleton.get_bone_count() if skeleton!=null else 0})
		if skeleton==null:scene.queue_free();continue
		var finite:=true;var order:=true;var joints:=true
		for index: int in range(skeleton.get_bone_count()):
			finite=finite and skeleton.get_bone_global_rest(index).is_finite();order=order and skeleton.get_bone_parent(index)<index
		for title: String in ["Bip01 Pelvis","Bip01 Spine","Bip01 Spine4","Bip01 Head","Bip01 L Thigh","Bip01 R Thigh","Bip01 L Calf","Bip01 R Calf","Bip01 L Foot","Bip01 R Foot","Bip01 L UpperArm","Bip01 R UpperArm","Bip01 L Forearm","Bip01 R Forearm","Bip01 L Hand","Bip01 R Hand"]:joints=joints and skeleton.find_bone(title)>=0
		_check(report,sex+"_finite_topological_semantics",finite and order and joints,{"finite":finite,"order":order,"semantics":joints})
		var bounds:=AABB();var first:=true;var surfaces:=[];var mesh_count:=0;var weights_ok:=true;var uv_ok:=true;var opaque:=true;var textured:=true;var max_rest_error:=0.;var max_weight_sum_error:=0.
		for node: Node in scene.find_children("*","MeshInstance3D",true,false):
			var mesh:=node as MeshInstance3D;mesh_count+=1
			var bm: Array[Transform3D]=[]
			for bind: int in range(mesh.skin.get_bind_count()):
				var title:=mesh.skin.get_bind_name(bind);var bone:=skeleton.find_bone(title) if not title.is_empty() else mesh.skin.get_bind_bone(bind)
				bm.append(skeleton.global_transform*skeleton.get_bone_global_rest(bone)*mesh.skin.get_bind_pose(bind))
			for surface: int in range(mesh.mesh.get_surface_count()):
				var arr:=mesh.mesh.surface_get_arrays(surface);var verts: PackedVector3Array=arr[Mesh.ARRAY_VERTEX];var bones: PackedInt32Array=arr[Mesh.ARRAY_BONES];var amounts: PackedFloat32Array=arr[Mesh.ARRAY_WEIGHTS];var uvs: PackedVector2Array=arr[Mesh.ARRAY_TEX_UV]
				uv_ok=uv_ok and uvs.size()==verts.size()
				var mat:=mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				opaque=opaque and mat!=null and mat.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED
				if "Body" in mesh.name or "Eyes" in mesh.name:textured=textured and mat!=null and mat.albedo_texture!=null
				for index: int in range(verts.size()):
					var point:=Vector3.ZERO;var sum:=0.
					for influence: int in range(4):
						var amount:=amounts[index*4+influence];sum+=amount;point+=(bm[bones[index*4+influence]]*verts[index])*amount
					max_weight_sum_error=maxf(max_weight_sum_error,absf(sum-1.));weights_ok=weights_ok and absf(sum-1.)<.0001 and point.is_finite()
					max_rest_error=maxf(max_rest_error,point.distance_to(mesh.global_transform*verts[index]))
					bounds=AABB(point,Vector3.ZERO) if first else bounds.expand(point);first=false
				surfaces.append({"mesh":mesh.name,"vertices":verts.size(),"triangles":arr[Mesh.ARRAY_INDEX].size()/3,"texture":mat.albedo_texture!=null if mat!=null else false,"opaque":mat.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED if mat!=null else false})
		_check(report,sex+"_three_surfaces",mesh_count==3,{"count":mesh_count,"surfaces":surfaces})
		_check(report,sex+"_original_uv_textures_opaque",uv_ok and opaque and textured,{"uv":uv_ok,"opaque":opaque,"skin_eye_textures":textured})
		_check(report,sex+"_rest_skin_ground_height",weights_ok and absf(bounds.position.y)<.00001 and absf(bounds.size.y-1.70)<.00001 and max_rest_error<.0001,{"bounds_position":str(bounds.position),"bounds_size":str(bounds.size),"max_rest_skin_error_m":max_rest_error,"max_imported_weight_sum_error":max_weight_sum_error,"precision_tolerance_m":.0001,"weights_normalized":weights_ok})
		report.variants.append({"sex":sex,"bone_count":skeleton.get_bone_count(),"bounds_position":str(bounds.position),"bounds_size":str(bounds.size),"surfaces":surfaces})
		scene.queue_free();await process_frame
	var failed:=0
	for check: Dictionary in report.checks:
		if not check.passed:failed+=1
	report.result={"passed":report.checks.size()-failed,"total":report.checks.size(),"failed":failed,"status":"pass" if failed==0 else "fail"}
	report["source_hashes"]={}
	for relative: String in ["tools/prepare_makehuman_swim.py","tools/check_makehuman_swim_assets.gd","game/assets/vendor/makehuman_swim/swim_male.glb","game/assets/vendor/makehuman_swim/swim_female.glb","game/assets/vendor/makehuman_swim/provenance.json"]:
		report.source_hashes[relative]=FileAccess.get_sha256(repo_root+"/"+relative)
	report["fixture"]={"entrypoint":"tools/check_makehuman_swim_assets.gd","engine":Engine.get_version_info().string,"render_scope":"headless GLTFDocument actual parsing, node generation, texture decode, CPU skin rest; no native visual or locomotion claim","precision_note":"Source float weights are renormalized. Godot import quantizes weights; observed max weight sum error 4.58e-5 and max rest skin position error 0.0733mm are checked against 0.1mm."}
	var file:=FileAccess.open(destination,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
	print("MAKEHUMAN_ASSET_PROBE ",JSON.stringify(report.result));quit(0 if failed==0 else 1)
func _check(report: Dictionary,title: String,passed: bool,evidence: Dictionary) -> void:
	report.checks.append({"name":title,"passed":passed,"evidence":evidence})
