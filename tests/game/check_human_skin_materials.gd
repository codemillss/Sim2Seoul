extends SceneTree
## Focused material/resource contract, not an anatomy or performance benchmark.
const PBR := preload("res://scripts/player/human_skin_materials.gd")
var checks: Array=[]
var report_path:="/private/tmp/sim2seoul-human-materials.json"
var source_hashes: Dictionary={}
var material_rows: Array=[]

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	_run.call_deferred()

func _check(title: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":evidence});print("HUMAN_MATERIAL ",title," ",passed)

func _hashes() -> Dictionary:
	var value: Dictionary={}
	for path: String in ["res://scripts/player/human_skin_materials.gd","res://scripts/player/textured_human_surface.gd","res://scripts/player/exploration_avatar.gd","res://../tests/game/check_human_skin_materials.gd"]:value[path]=FileAccess.get_sha256(path)
	for filename: String in DirAccess.get_files_at("res://assets/original/seoul_resident"):
		if filename.get_extension() in ["glb","json"]:value["res://assets/original/seoul_resident/"+filename]=FileAccess.get_sha256("res://assets/original/seoul_resident/"+filename)
	return value

func _run() -> void:
	source_hashes=_hashes()
	var properties: Array=[]
	for row: Dictionary in ClassDB.class_get_property_list("BaseMaterial3D",false):properties.append(str(row.name))
	var required: Array=["roughness","roughness_texture","roughness_texture_channel","metallic_specular","normal_enabled","normal_texture","normal_scale","subsurf_scatter_enabled","subsurf_scatter_strength","subsurf_scatter_skin_mode","subsurf_scatter_transmittance_enabled","clearcoat_enabled"]
	_check("installed_ClassDB_supports_used_material_properties",required.all(func(key: String)->bool:return key in properties),{"engine":Engine.get_version_info().string,"required":required,"rendering_method":RenderingServer.get_current_rendering_method()})
	var base:=StandardMaterial3D.new();base.albedo_color=Color(.7,.5,.3);base.roughness=.73;base.cull_mode=BaseMaterial3D.CULL_DISABLED;base.transparency=BaseMaterial3D.TRANSPARENCY_DISABLED
	var skin: StandardMaterial3D=base.duplicate();var other: StandardMaterial3D=base.duplicate();PBR.apply_to(skin,"skin",true);PBR.apply_to(other,"skin",true)
	var hair: StandardMaterial3D=base.duplicate();PBR.apply_to(hair,"hair",true)
	var cloth: StandardMaterial3D=base.duplicate();PBR.apply_to(cloth,"jacket",true)
	var eye: StandardMaterial3D=base.duplicate();PBR.apply_to(eye,"eye",true)
	var no_tangent: StandardMaterial3D=base.duplicate();PBR.apply_to(no_tangent,"skin",false)
	_check("helper_preserves_source_albedo_cull_and_opaque_policy",[skin,other,hair,cloth,eye,no_tangent].all(func(material: StandardMaterial3D)->bool:return material.albedo_color==base.albedo_color and material.cull_mode==base.cull_mode and material.transparency==base.transparency) and is_equal_approx(base.roughness,.73))
	_check("per_instance_materials_share_only_readonly_maps",skin!=other and skin.normal_texture==other.normal_texture and skin.roughness_texture==other.roughness_texture and skin.normal_texture!=hair.normal_texture)
	_check("normal_requires_actual_tangent_frame",not no_tangent.normal_enabled and no_tangent.normal_texture==null and skin.normal_enabled and skin.normal_texture!=null)
	_check("eye_hair_cloth_skin_have_distinct_bounded_response",eye.roughness<.3 and eye.metallic_specular<.5 and not eye.normal_enabled and not eye.subsurf_scatter_enabled and hair.roughness>.9 and cloth.roughness>.9 and skin.roughness>.7 and skin.subsurf_scatter_strength<=.0351 and not skin.subsurf_scatter_transmittance_enabled and not skin.clearcoat_enabled)
	for id: String in ["SeoulResident_M01","SeoulResident_F01"]:
		var player:=CharacterBody3D.new();player.set_meta("human_model_id",id)
		var visual:=Node3D.new();visual.name="Visual";player.add_child(visual)
		var body:=MeshInstance3D.new();body.name="Body";body.mesh=CapsuleMesh.new();visual.add_child(body);root.add_child(player)
		var avatar: Node3D=load("res://scripts/player/exploration_avatar.gd").new();visual.add_child(avatar)
		var ready: bool=avatar.setup(player);avatar.set_physics_process(false)
		_check(id+".actual_production_surface_loaded",ready)
		if ready:
			var surface: Node3D=avatar._textured_surface
			for outfit: String in ["street","swim"]:
				surface.set_swimwear(outfit=="swim")
				var meshes: Array=surface._swim_meshes if outfit=="swim" else surface.visible_meshes
				var valid:=not meshes.is_empty();var eyes:=0;var skins:=0
				for mesh: MeshInstance3D in meshes:
					for index: int in range(mesh.mesh.get_surface_count()):
						var source: StandardMaterial3D=surface._source_meshes[mesh.get_instance_id()].surface_get_material(index)
						var material: StandardMaterial3D=mesh.get_surface_override_material(index);var role: String=surface._material_role(mesh,index)
						var arrays: Array=mesh.mesh.surface_get_arrays(index);var vertices: int=arrays[Mesh.ARRAY_VERTEX].size()
						valid=valid and material!=source and material.cull_mode==source.cull_mode and material.transparency==source.transparency and material.vertex_color_use_as_albedo and int(material.get_meta("human_material_version",0))==PBR.VERSION
						if role=="eye":eyes+=1;valid=valid and is_equal_approx(material.roughness,.22) and not material.normal_enabled
						if role in ["skin","hands"]:skins+=1;valid=valid and material.normal_enabled and arrays[Mesh.ARRAY_TANGENT].size()==vertices*4 and material.normal_texture==skin.normal_texture and material.subsurf_scatter_strength<=.0351
						material_rows.append({"model":id,"outfit":outfit,"name":source.resource_name,"role":role,"roughness":material.roughness,"specular":material.metallic_specular,"normal_enabled":material.normal_enabled,"normal_scale":material.normal_scale,"sss_strength":material.subsurf_scatter_strength,"tangents":arrays[Mesh.ARRAY_TANGENT].size(),"vertices":vertices,"cull_mode":material.cull_mode,"transparency":material.transparency})
				_check(id+"."+outfit+".production_hook_keeps_opaque_tangent_skin_and_separate_eye",valid and eyes==1 and skins>=2,{"eye_surfaces":eyes,"skin_and_hand_surfaces":skins})
			var first_mesh: MeshInstance3D=surface.visible_meshes[0]
			var eye_colors: PackedColorArray=PackedColorArray();var hair_colors: PackedColorArray=PackedColorArray();var eye_index:=-1;var hair_index:=-1
			for index: int in range(first_mesh.mesh.get_surface_count()):
				if surface._material_role(first_mesh,index)=="eye":eye_index=index;eye_colors=first_mesh.mesh.surface_get_arrays(index)[Mesh.ARRAY_COLOR]
				if surface._material_role(first_mesh,index)=="hair":hair_index=index;hair_colors=first_mesh.mesh.surface_get_arrays(index)[Mesh.ARRAY_COLOR]
			surface.set_swimwear(false);surface.set_customization({"skin":Color("c59370"),"hair":Color("a6a9af")},true)
			_check(id+".palette_changes_preserve_actual_eye_surface",eye_index>=0 and hair_index>=0 and first_mesh.mesh.surface_get_arrays(eye_index)[Mesh.ARRAY_COLOR]==eye_colors and first_mesh.mesh.surface_get_arrays(hair_index)[Mesh.ARRAY_COLOR]!=hair_colors)
		root.remove_child(player);player.queue_free();await process_frame
	var cache: Dictionary=PBR.cache_snapshot()
	_check("shared_microtexture_cache_is_bounded",cache.shared_map_pairs==3 and cache.shared_texture_count==6 and cache.image_bytes_with_mips<300000,cache)
	_check("source_inputs_stable_during_material_probe",_hashes()==source_hashes and not source_hashes.values().has(""))
	var passed: int=checks.filter(func(row: Dictionary)->bool:return row.passed).size()
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"task":"human_skin_materials","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"material_rows":material_rows,"cache":cache,"source_sha256":source_hashes,"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"scope":"Installed ClassDB, real StandardMaterial3D resources, shared generated maps, and two standard authored production avatar instances in street/swim presentation. No physics or anatomy quality claim. Native front/face pixel review is separate; no performance/FPS claim."},"  "));file.close()
	print("HUMAN_MATERIAL_RESULT ",passed,"/",checks.size());await process_frame;quit(0 if passed==checks.size() else 1)
