extends Node3D
## Project-authored weighted residents. No imported vendor body/face is loaded.
## The source generator defines every mesh, UV, texture, bone and skin weight.
const RIG := preload("res://scripts/player/textured_human_rig.gd")
const HUMAN_MATERIALS := preload("res://scripts/player/human_skin_materials.gd")
const ORIGINAL := "res://assets/original/seoul_resident/"
const REST_HEIGHT_M := 1.70
const BODY_PROFILES := ["standard","soft","athletic"]
var loaded:=false
var load_error:=""
var avatar: Node3D
var model_id:=""
var body_profile:="standard"
var requested_model_alias:=""
var _street_asset_path:=""
var _street_asset_sha256:=""
var _swim_asset_path:=""
var _swim_asset_sha256:=""
var _normalized_rest_bounds:=AABB()
var imported_root: Node3D
var skeleton: Skeleton3D
var rig: Node3D
var visible_meshes: Array[MeshInstance3D]=[]
var _body_material: StandardMaterial3D
var _hand_material: StandardMaterial3D
var _head_material: StandardMaterial3D
var _pants_material: StandardMaterial3D
var _surfaces: Array[Dictionary]=[]
var _base_colors: Dictionary={}
var _actual_bounds:=AABB()
var _bounds_tick:=-1
var _texture_uv_ready:=false
var _normalization_scale:=1.
var _active_body_source:="sim2seoul_authored_resident_street"
var _swimwear_active:=false
var _swim_root: Node3D
var _swim_skeleton: Skeleton3D
var _swim_rig: Node3D
var _swim_meshes: Array[MeshInstance3D]=[]
var _palette_signature:=""
var _palette_gain_linear:=1.
var _garment_texture_means: Dictionary={"method":"authored_base_material_colors_texture_means_not_measured","texture_means_measured":false}
var _street_material_colors: Dictionary={}
var _swim_material_colors: Dictionary={}
var _swim_head_cut: Dictionary={}
var _swim_head_join: Dictionary={}
var _custom_colors: Dictionary={}
var _custom_preview_clothes:=false
var _source_meshes: Dictionary={}
var _hair_vertex_masks: Dictionary={}
var _vertex_custom_signature:=""

func setup(source_avatar: Node3D,selected_model: String,selected_profile: String="standard") -> bool:
	if loaded or not is_instance_valid(source_avatar):return false
	if selected_profile not in BODY_PROFILES:return false
	avatar=source_avatar;requested_model_alias=selected_model
	model_id="SeoulResident_F01" if selected_model in ["Female_Adult_07","SeoulResident_F01"] else "SeoulResident_M01"
	body_profile=selected_profile
	name="AuthoredHumanSurface";process_priority=110;process_mode=Node.PROCESS_MODE_PAUSABLE
	_street_asset_path=authored_asset_path("street");_swim_asset_path=authored_asset_path("swim")
	var packed: PackedScene=load(_street_asset_path)
	if packed==null:return _fail("missing_authored_resident_"+model_id+"_"+body_profile)
	_street_asset_sha256=FileAccess.get_sha256(_street_asset_path)
	imported_root=packed.instantiate();imported_root.name="Sim2SeoulAuthoredResident";add_child(imported_root)
	for node: Node in imported_root.find_children("*","Skeleton3D",true,false):skeleton=node as Skeleton3D;break
	if skeleton==null:return _fail("missing_authored_skeleton")
	for node: Node in imported_root.find_children("*","MeshInstance3D",true,false):
		if node.mesh!=null:visible_meshes.append(node as MeshInstance3D)
	if visible_meshes.is_empty():return _fail("missing_authored_surface")
	_build_surface_cache()
	var rest:=_skin_bounds()
	if rest.size.y<1.:return _fail("invalid_authored_body_bounds")
	_normalization_scale=REST_HEIGHT_M/rest.size.y
	imported_root.scale=Vector3.ONE*_normalization_scale;imported_root.rotation.y=PI
	imported_root.position.y=-rest.position.y*_normalization_scale
	_normalized_rest_bounds=imported_root.transform*rest
	_prepare_materials(visible_meshes,_street_material_colors)
	for key: String in ["jacket","trousers","skin"]:_base_colors[key]=avatar._materials[key].albedo_color
	_set_material_handles();_build_surface_cache()
	rig=RIG.new();avatar.add_child(rig)
	if not rig.setup(avatar,imported_root,skeleton):return _fail("rig_"+String(rig.load_error))
	loaded=true;sync_clothing();refresh_bounds();return true

func authored_asset_path(clothing: String) -> String:
	if clothing not in ["street","swim"]:return ""
	var file:="seoul_resident_f01" if model_id=="SeoulResident_F01" else "seoul_resident_m01"
	if body_profile!="standard":file+="_"+body_profile
	return ORIGINAL+file+"_"+clothing+".glb"

func active_native_rig() -> Node3D:
	return _swim_rig if _swimwear_active else rig

func _fail(reason: String) -> bool:
	load_error=reason;loaded=false
	if is_instance_valid(imported_root):imported_root.visible=false
	push_error("AUTHORED_HUMAN "+reason);return false

func _prepare_materials(meshes: Array[MeshInstance3D],colors: Dictionary) -> void:
	for mesh: MeshInstance3D in meshes:
		_source_meshes[mesh.get_instance_id()]=mesh.mesh
		for index: int in range(mesh.mesh.get_surface_count()):
			var base: Material=mesh.mesh.surface_get_material(index)
			var material: StandardMaterial3D=base.duplicate() as StandardMaterial3D
			if material==null:material=StandardMaterial3D.new()
			material.vertex_color_use_as_albedo=true
			var arrays: Array=mesh.mesh.surface_get_arrays(index)
			var count: int=arrays[Mesh.ARRAY_VERTEX].size()
			var tangent_ready: bool=arrays[Mesh.ARRAY_NORMAL]!=null and arrays[Mesh.ARRAY_NORMAL].size()==count and arrays[Mesh.ARRAY_TEX_UV]!=null and arrays[Mesh.ARRAY_TEX_UV].size()==count and arrays[Mesh.ARRAY_TANGENT]!=null and arrays[Mesh.ARRAY_TANGENT].size()==count*4
			HUMAN_MATERIALS.apply_to(material,_material_role(mesh,index),tangent_ready)
			mesh.set_surface_override_material(index,material)
			colors[str(mesh.get_instance_id())+":"+str(index)]=material.albedo_color

func _material_role(mesh: MeshInstance3D,index: int) -> String:
	var title:=String(mesh.mesh.surface_get_material(index).resource_name).to_lower()
	if "original_eye" in title:return "eye"
	if "jacket" in title or "swimwear" in title:return "jacket"
	if "trousers" in title:return "pants"
	if "hands" in title:return "hands"
	if "skin" in title:return "skin"
	if "hair" in title:return "hair"
	if "sneakers" in title:return "shoes"
	return "detail"

func set_customization(colors: Dictionary,preview_clothes:=false) -> bool:
	# Presentation only. Preserve original resources, vertices, indices, native
	# skin weights and rest bones. Only per-instance colour arrays/materials vary.
	var accepted: Dictionary={}
	for key: String in colors:
		if key not in ["skin","hair","jacket","pants","shoes"] or not colors[key] is Color:return false
		var color: Color=colors[key]
		if not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b) or color.r<0. or color.r>1. or color.g<0. or color.g>1. or color.b<0. or color.b>1.:return false
		accepted[key]=Color(color.r,color.g,color.b)
	_custom_colors=accepted;_custom_preview_clothes=preview_clothes;_palette_signature=""
	sync_clothing();return true

func _hair_mask(source: ArrayMesh,surface: int) -> PackedByteArray:
	var key:=str(source.get_instance_id())+":"+str(surface)
	if _hair_vertex_masks.has(key):return _hair_vertex_masks[key]
	var arrays:=source.surface_get_arrays(surface);var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var parent:=PackedInt32Array();parent.resize(vertices.size())
	for index: int in range(parent.size()):parent[index]=index
	for triangle: int in range(0,indices.size(),3):
		var root_a:=_component_root(parent,indices[triangle])
		for corner: int in [1,2]:
			var root_b:=_component_root(parent,indices[triangle+corner]);parent[root_b]=root_a
	var maximum_y: Dictionary={}
	for index: int in range(vertices.size()):
		var root_index:=_component_root(parent,index);maximum_y[root_index]=maxf(float(maximum_y.get(root_index,-INF)),vertices[index].y)
	var mask:=PackedByteArray();mask.resize(vertices.size())
	for index: int in range(vertices.size()):mask[index]=1 if float(maximum_y[_component_root(parent,index)])>1.59 else 0
	_hair_vertex_masks[key]=mask;return mask

func _component_root(parent: PackedInt32Array,index: int) -> int:
	var cursor:=index
	while parent[cursor]!=cursor:cursor=parent[cursor]
	return cursor

func _sync_custom_vertex_colors() -> void:
	var signature:=str(_custom_colors.get("skin","default"))+str(_custom_colors.get("hair","default"))+str(_source_meshes.size())
	if signature==_vertex_custom_signature:return
	_vertex_custom_signature=signature
	var skin_reference:=Color(.77,.56,.44) if model_id=="SeoulResident_F01" else Color(.69,.48,.36)
	var linear_reference:=skin_reference.srgb_to_linear();var skin_target: Color=_custom_colors.get("skin",skin_reference)
	var linear_target:=skin_target.srgb_to_linear();var gain:=Color(linear_target.r/linear_reference.r,linear_target.g/linear_reference.g,linear_target.b/linear_reference.b)
	for meshes: Array in [visible_meshes,_swim_meshes]:
		for mesh: MeshInstance3D in meshes:
			var source: ArrayMesh=_source_meshes[mesh.get_instance_id()]
			if not _custom_colors.has("skin") and not _custom_colors.has("hair"):mesh.mesh=source;continue
			var result:=ArrayMesh.new()
			for index: int in range(source.get_surface_count()):
				var arrays:=source.surface_get_arrays(index);var role:=_material_role(mesh,index)
				if (role in ["skin","hands"] and _custom_colors.has("skin")) or (role=="hair" and _custom_colors.has("hair")):
					var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR];colors=colors.duplicate()
					if role in ["skin","hands"]:
						for vertex: int in range(colors.size()):colors[vertex]=colors[vertex]*gain
					else:
						var mask:=_hair_mask(source,index);var target: Color=Color(_custom_colors.hair).srgb_to_linear()
						for vertex: int in range(colors.size()):
							if mask[vertex]==1:
								var shade:=clampf(colors[vertex].r/.00048,.65,1.35);colors[vertex]=Color(target.r*shade,target.g*shade,target.b*shade,1.)
					arrays[Mesh.ARRAY_COLOR]=colors
				result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);result.surface_set_name(index,source.surface_get_name(index));result.surface_set_material(index,source.surface_get_material(index))
			mesh.mesh=result
	_build_surface_cache()

func _set_material_handles() -> void:
	for mesh: MeshInstance3D in visible_meshes:
		for index: int in range(mesh.mesh.get_surface_count()):
			var material:=mesh.get_surface_override_material(index) as StandardMaterial3D
			match _material_role(mesh,index):
				"jacket":_body_material=material
				"skin":_head_material=material
				"hands":_hand_material=material
				"pants":_pants_material=material
	_garment_texture_means={"method":"authored_base_material_colors_texture_means_not_measured","texture_means_measured":false,"jacket_material_srgb":_body_material.albedo_color if _body_material!=null else Color.WHITE,"pants_material_srgb":_pants_material.albedo_color if _pants_material!=null else Color.WHITE}

func _build_surface_cache() -> void:
	_surfaces.clear();_texture_uv_ready=true
	for mesh: MeshInstance3D in visible_meshes:
		if not _swimwear_active:_cache_mesh_surfaces(mesh,skeleton)
	if _swimwear_active:
		for mesh: MeshInstance3D in _swim_meshes:_cache_mesh_surfaces(mesh,_swim_skeleton)

func _cache_mesh_surfaces(mesh: MeshInstance3D,owner_skeleton: Skeleton3D) -> void:
	var bind_bones: PackedInt32Array=[]
	for index: int in range(mesh.skin.get_bind_count()):
		var title:=mesh.skin.get_bind_name(index)
		bind_bones.append(owner_skeleton.find_bone(title) if not title.is_empty() else mesh.skin.get_bind_bone(index))
	for index: int in range(mesh.mesh.get_surface_count()):
		var arrays: Array=mesh.mesh.surface_get_arrays(index);var used: Dictionary={}
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for vertex: int in range(arrays[Mesh.ARRAY_VERTEX].size()):used[vertex]=true
		else:
			for vertex: int in indices:used[vertex]=true
		var uv_count: int=arrays[Mesh.ARRAY_TEX_UV].size() if arrays[Mesh.ARRAY_TEX_UV]!=null else 0
		var material:=mesh.get_surface_override_material(index) as StandardMaterial3D
		_texture_uv_ready=_texture_uv_ready and uv_count==arrays[Mesh.ARRAY_VERTEX].size() and uv_count>0 and material!=null and material.albedo_texture!=null
		_surfaces.append({"mesh":mesh,"skeleton":owner_skeleton,"surface":index,"vertices":arrays[Mesh.ARRAY_VERTEX],"referenced":PackedInt32Array(used.keys()),"bones":arrays[Mesh.ARRAY_BONES],"weights":arrays[Mesh.ARRAY_WEIGHTS],"bind_bones":bind_bones,"uv_count":uv_count})

func _skin_matrices(mesh: MeshInstance3D,bind_bones: PackedInt32Array,owner_skeleton: Skeleton3D=null) -> Array[Transform3D]:
	var matrices: Array[Transform3D]=[]
	var skel: Skeleton3D=owner_skeleton if owner_skeleton!=null else skeleton
	var frame:=avatar.global_transform.affine_inverse()*skel.global_transform
	for index: int in range(mesh.skin.get_bind_count()):matrices.append(frame*skel.get_bone_global_pose(bind_bones[index])*mesh.skin.get_bind_pose(index))
	return matrices

func _skin_bounds() -> AABB:
	var bounds:=AABB();var first:=true;var matrices: Array[Transform3D]=[];var last_mesh: MeshInstance3D
	for surface: Dictionary in _surfaces:
		if surface.mesh!=last_mesh:matrices=_skin_matrices(surface.mesh,surface.bind_bones,surface.skeleton);last_mesh=surface.mesh
		var vertices: PackedVector3Array=surface.vertices;var bones: PackedInt32Array=surface.bones;var weights: PackedFloat32Array=surface.weights
		for index: int in surface.referenced:
			var point:=Vector3.ZERO
			for influence: int in range(4):
				var amount: float=weights[index*4+influence]
				if amount>0.:point+=(matrices[bones[index*4+influence]]*vertices[index])*amount
			bounds=AABB(point,Vector3.ZERO) if first else bounds.expand(point);first=false
	return bounds

func refresh_bounds() -> AABB:
	_actual_bounds=_skin_bounds();_bounds_tick=Engine.get_physics_frames();return _actual_bounds

func _ratio(value: Color,reference: Color) -> Color:
	if value.is_equal_approx(reference):return Color.WHITE
	return Color(clampf(value.r/maxf(reference.r,.1),.2,2.),clampf(value.g/maxf(reference.g,.1),.2,2.),clampf(value.b/maxf(reference.b,.1),.2,2.))

func sync_clothing() -> void:
	if not loaded:return
	_sync_custom_vertex_colors()
	var torso: MeshInstance3D=avatar.find_child("Torso",true,false)
	var jacket: Color=torso.material_override.albedo_color if torso!=null and torso.material_override is StandardMaterial3D else avatar._materials.jacket.albedo_color
	var pants: Color=avatar._materials.trousers.albedo_color
	var skin_gain:=_ratio(avatar._materials.skin.albedo_color,_base_colors.skin)
	var signature:=str(jacket)+str(pants)+str(skin_gain)+str(_swimwear_active)+str(_custom_colors)+str(_custom_preview_clothes)
	if signature==_palette_signature:return
	_palette_signature=signature
	for meshes: Array in [visible_meshes,_swim_meshes]:
		for mesh: MeshInstance3D in meshes:
			var original: Dictionary=_street_material_colors if mesh in visible_meshes else _swim_material_colors
			for index: int in range(mesh.mesh.get_surface_count()):
				var material:=mesh.get_surface_override_material(index) as StandardMaterial3D
				var base: Color=original[str(mesh.get_instance_id())+":"+str(index)]
				var role:=_material_role(mesh,index)
				if role in ["skin","hands"]:material.albedo_color=base*skin_gain
				elif role=="jacket" and mesh in visible_meshes:
					var shop_owned: bool=torso!=null and torso.material_override!=avatar._materials.jacket
					if _custom_preview_clothes:material.albedo_color=_custom_colors.get("jacket",base)
					else:material.albedo_color=_custom_colors.jacket if _custom_colors.has("jacket") and not shop_owned else (base if jacket.is_equal_approx(_base_colors.jacket) else jacket)
				elif role=="pants" and mesh in visible_meshes:
					material.albedo_color=_custom_colors.pants if _custom_colors.has("pants") else (base if pants.is_equal_approx(_base_colors.trousers) else pants)
				elif role=="shoes":material.albedo_color=_custom_colors.get("shoes",base)

func _process(_delta: float) -> void:
	if loaded:sync_clothing()

func set_swimwear(enabled: bool) -> void:
	if enabled==_swimwear_active:return
	if enabled and not is_instance_valid(_swim_root):
		if not _prepare_swim_body():push_error("AUTHORED_HUMAN missing_own_swimwear");return
	_swimwear_active=enabled;imported_root.visible=not enabled
	if is_instance_valid(_swim_root):_swim_root.visible=enabled
	rig.set_process(not enabled)
	if is_instance_valid(_swim_rig):_swim_rig.set_process(enabled)
	_active_body_source="sim2seoul_authored_resident_swimwear" if enabled else "sim2seoul_authored_resident_street"
	_palette_signature="";sync_clothing()
	if enabled:_swim_rig.sync_pose()
	else:rig.sync_pose()
	_build_surface_cache();refresh_bounds()

func _prepare_swim_body() -> bool:
	var packed: PackedScene=load(_swim_asset_path)
	if packed==null:return false
	_swim_asset_sha256=FileAccess.get_sha256(_swim_asset_path)
	_swim_root=packed.instantiate();_swim_root.name="Sim2SeoulAuthoredSwimwear";add_child(_swim_root)
	# Exactly the same authored rest anatomy and bind matrices as streetwear.
	# Preserve scale and origin across clothing, not a separate body fit.
	_swim_root.transform=imported_root.transform
	for node: Node in _swim_root.find_children("*","Skeleton3D",true,false):_swim_skeleton=node as Skeleton3D;break
	if _swim_skeleton==null:return false
	for node: Node in _swim_root.find_children("*","MeshInstance3D",true,false):
		if node.mesh!=null:_swim_meshes.append(node as MeshInstance3D)
	if _swim_meshes.is_empty():return false
	_prepare_materials(_swim_meshes,_swim_material_colors)
	_swim_rig=RIG.new();avatar.add_child(_swim_rig)
	if not _swim_rig.setup(avatar,_swim_root,_swim_skeleton):return false
	_swim_head_join={"active":false,"method":"single_project_authored_head_and_body","two_supplier_fit":false,"same_authored_rest_anatomy":true,"physics_camera_source_markers_modified":false}
	return true

func snapshot(refresh_actual_bounds:=false) -> Dictionary:
	if loaded and refresh_actual_bounds:refresh_bounds()
	var active_rig: Node3D=_swim_rig if _swimwear_active else rig
	var active_skeleton: Skeleton3D=_swim_skeleton if _swimwear_active else skeleton
	var rig_data: Dictionary=active_rig.snapshot() if is_instance_valid(active_rig) and active_rig.has_method("snapshot") else {}
	return {"loaded":loaded,"error":load_error,"model_id":model_id,"body_profile":body_profile,"active_glb_path":_swim_asset_path if _swimwear_active else _street_asset_path,"active_glb_sha256":_swim_asset_sha256 if _swimwear_active else _street_asset_sha256,"street_glb_path":_street_asset_path,"swim_glb_path":_swim_asset_path,"normalized_rest_bounds_m":_normalized_rest_bounds,"requested_compatibility_alias":requested_model_alias,"visible_mesh_count":(visible_meshes+_swim_meshes).filter(func(mesh: MeshInstance3D)->bool:return mesh.is_visible_in_tree()).size(),"skeleton_bone_count":active_skeleton.get_bone_count() if is_instance_valid(active_skeleton) else 0,"actual_visible_bounds_m":_actual_bounds,"actual_height_m":_actual_bounds.size.y,"normalized_rest_height_m":REST_HEIGHT_M,"bounds_sampled_at_physics_tick":_bounds_tick,"surface_texture_uv_ready":_texture_uv_ready,"rig_contact_metrics":rig_data,"normalization_scale":_normalization_scale,"clothing_palette":{"body_gain_linear":1.,"texture_means":_garment_texture_means,"hands_use_separate_original_skin_material":true},"swimwear_active":_swimwear_active,"active_body_source":_active_body_source,"swim_skeleton_bone_count":_swim_skeleton.get_bone_count() if is_instance_valid(_swim_skeleton) and _swimwear_active else 0,"original_head_and_hair_preserved":true,"swim_head_cut":{},"swim_head_join":_swim_head_join if _swimwear_active else {},"legacy_geometry_rendered":false,"supplier":"Sim2Seoul project-authored anatomical profiles, facial sculpt, clothing, procedural textures, skeleton and skin weights","authored_generator":"tools/authored_character/build_seoul_resident.py","vendor_geometry_loaded":false,"scope":"Own weighted human, authored directly from numerical profiles. Bounds CPU-skin the actual referenced displayed vertices. Original vendor bodies, faces, textures and animations are not loaded."}
