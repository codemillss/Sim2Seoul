extends Node3D
## Microsoft Rocketbox render surface, with original weighted anatomy and UVs.
## Existing articulated markers remain invisible game-contact/wardrobe proxies.
const RIG := preload("res://scripts/player/textured_human_rig.gd")
const VENDOR := "res://assets/vendor/microsoft_rocketbox/"
const REST_HEIGHT_M := 1.70
static var _weighted_mesh_cache: Dictionary={}
static var _palette_mesh_cache: Dictionary={}
static var _texture_means_cache: Dictionary={}
var loaded:=false
var load_error:=""
var avatar: Node3D
var model_id:=""
var imported_root: Node3D
var skeleton: Skeleton3D
var rig: Node3D
var visible_meshes: Array[MeshInstance3D]=[]
var _body_material: StandardMaterial3D
var _hand_material: StandardMaterial3D
var _palette_signature:=""
var _palette_gain_linear:=1.
var _garment_texture_means: Dictionary={}
var _head_material: StandardMaterial3D
var _surfaces: Array[Dictionary]=[]
var _base_colors: Dictionary={}
var _actual_bounds:=AABB()
var _bounds_tick:=-1
var _texture_uv_ready:=false
var _normalization_scale:=1.
var _active_body_source:="rocketbox_clothed"
var _swimwear_active:=false
var _swim_root: Node3D
var _swim_skeleton: Skeleton3D
var _swim_rig: Node3D
var _swim_meshes: Array[MeshInstance3D]=[]
var _swim_head_cut: Dictionary={}
var _swim_head_join: Dictionary={}

func setup(source_avatar: Node3D,selected_model: String) -> bool:
	if loaded or not is_instance_valid(source_avatar):return false
	avatar=source_avatar;model_id=selected_model;name="TexturedHumanSurface";process_priority=110;process_mode=Node.PROCESS_MODE_PAUSABLE
	var path:=VENDOR+model_id+"/Export/"+model_id+".fbx";var packed: PackedScene=load(path)
	if packed==null:return _fail("missing_imported_human_"+model_id)
	imported_root=packed.instantiate();imported_root.name="OriginalWeightedHuman";add_child(imported_root)
	for node: Node in imported_root.find_children("*","Skeleton3D",true,false):skeleton=node as Skeleton3D;break
	if skeleton==null:return _fail("missing_weighted_skeleton")
	for node: Node in imported_root.find_children("*","MeshInstance3D",true,false):
		if node.mesh!=null:visible_meshes.append(node as MeshInstance3D)
	if visible_meshes.is_empty():return _fail("missing_visible_human_mesh")
	# These two selected upstream FBXs contain one high-detail mesh each. A
	# generic guard still prevents duplicated simultaneous LODs if replaced.
	if visible_meshes.size()>1:
		var chosen: MeshInstance3D=visible_meshes[0]
		for mesh: MeshInstance3D in visible_meshes:
			if "hipoly" in String(mesh.name).to_lower():chosen=mesh;break
		for mesh: MeshInstance3D in visible_meshes:mesh.visible=mesh==chosen
		visible_meshes=[chosen]
	_build_surface_cache()
	var rest:=_skin_bounds();if rest.size.y<1.:return _fail("invalid_source_skin_bounds")
	_normalization_scale=REST_HEIGHT_M/rest.size.y;imported_root.scale=Vector3.ONE*_normalization_scale
	# Artist rig faces +Z; game contacts and controller face -Z. Skin bind
	# matrices already convert mesh Z-up data to skeleton Y-up, so no X rotation.
	imported_root.rotation.y=PI;imported_root.position.y=-rest.position.y*_normalization_scale
	_set_materials();_build_surface_cache()
	for key: String in ["jacket","trousers","skin"]:_base_colors[key]=avatar._materials[key].albedo_color
	rig=RIG.new();avatar.add_child(rig)
	if not rig.setup(avatar,imported_root,skeleton):return _fail("rig_"+String(rig.load_error))
	loaded=true;sync_clothing();refresh_bounds();return true

func _fail(reason: String) -> bool:
	load_error=reason;loaded=false
	if is_instance_valid(imported_root):imported_root.visible=false
	push_error("TEXTURED_HUMAN "+reason);return false

func _build_surface_cache() -> void:
	_surfaces.clear()
	for mesh: MeshInstance3D in visible_meshes:
		_cache_mesh_surfaces(mesh,skeleton,_swimwear_active)
	if _swimwear_active:
		for mesh: MeshInstance3D in _swim_meshes:
			if mesh.visible:_cache_mesh_surfaces(mesh,_swim_skeleton,false)

func _cache_mesh_surfaces(mesh: MeshInstance3D,owner_skeleton: Skeleton3D,head_only: bool) -> void:
	var bind_bones: PackedInt32Array=[]
	for index: int in range(mesh.skin.get_bind_count()):
		var bone_name:=mesh.skin.get_bind_name(index);bind_bones.append(owner_skeleton.find_bone(bone_name) if not bone_name.is_empty() else mesh.skin.get_bind_bone(index))
	for index: int in range(mesh.mesh.get_surface_count()):
		if head_only and index not in [1,2]:continue
		var arrays: Array=mesh.mesh.surface_get_arrays(index);var used: Dictionary={}
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for vertex: int in indices:used[vertex]=true
		var referenced:=PackedInt32Array(used.keys())
		_surfaces.append({"mesh":mesh,"skeleton":owner_skeleton,"surface":index,"vertices":arrays[Mesh.ARRAY_VERTEX],"referenced":referenced,"bones":arrays[Mesh.ARRAY_BONES],"weights":arrays[Mesh.ARRAY_WEIGHTS],"bind_bones":bind_bones,"uv_count":arrays[Mesh.ARRAY_TEX_UV].size() if arrays[Mesh.ARRAY_TEX_UV]!=null else 0})

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

func _weighted_colours(mesh: MeshInstance3D) -> ArrayMesh:
	if _weighted_mesh_cache.has(model_id):return _weighted_mesh_cache[model_id]
	var result:=ArrayMesh.new();var bind_bones: PackedInt32Array=[]
	for index: int in range(mesh.skin.get_bind_count()):
		var title:=mesh.skin.get_bind_name(index);bind_bones.append(skeleton.find_bone(title) if not title.is_empty() else mesh.skin.get_bind_bone(index))
	var matrices:=_skin_matrices(mesh,bind_bones)
	var pelvis:=skeleton.find_bone("Bip01 Pelvis");var pelvis_y: float=(avatar.global_transform.affine_inverse()*skeleton.global_transform*skeleton.get_bone_global_rest(pelvis).origin).y
	var hand_arrays: Array=[]
	for surface: int in range(mesh.mesh.get_surface_count()):
		var arrays: Array=mesh.mesh.surface_get_arrays(surface)
		if surface==0:
			var colours:=PackedColorArray();var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES];var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
			for index: int in range(vertices.size()):
				var best:=0.;var title:="";var point:=Vector3.ZERO
				for influence: int in range(4):
					var amount: float=weights[index*4+influence];var bind: int=bones[index*4+influence]
					if amount>0.:point+=(matrices[bind]*vertices[index])*amount
					if amount>best:best=amount;title=skeleton.get_bone_name(bind_bones[bind])
				var hand: bool="Hand" in title or "Finger" in title
				var lower: bool="Thigh" in title or "Calf" in title or "Foot" in title or "Toe" in title or ("Pelvis" in title and point.y<pelvis_y+.08)
				colours.append(Color(0,0,1) if hand else (Color(0,1,0) if lower else Color(1,0,0)))
			arrays[Mesh.ARRAY_COLOR]=colours
			# Keep real skin on its own original triangles so a white coat's
			# HDR fabric gain cannot quantize or recolour the hands. Geometry,
			# UVs, skin weights and original topology are unchanged.
			hand_arrays=arrays.duplicate();var hand_indices:=PackedInt32Array();var cloth_indices:=PackedInt32Array()
			var original_indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			for triangle: int in range(0,original_indices.size(),3):
				var points:=PackedInt32Array([original_indices[triangle],original_indices[triangle+1],original_indices[triangle+2]])
				if colours[points[0]].b>.5 or colours[points[1]].b>.5 or colours[points[2]].b>.5:hand_indices.append_array(points)
				else:cloth_indices.append_array(points)
			arrays[Mesh.ARRAY_INDEX]=cloth_indices;hand_arrays[Mesh.ARRAY_INDEX]=hand_indices
			var skin_colours:=PackedColorArray();skin_colours.resize(vertices.size());skin_colours.fill(Color.WHITE);hand_arrays[Mesh.ARRAY_COLOR]=skin_colours
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);result.surface_set_name(surface,mesh.mesh.surface_get_name(surface))
		# Retain a real base material while an instance override is changed or
		# torn down; a null base causes dummy/native instance-uniform queries to
		# inspect an invalid material during scene cleanup.
		var original_material: Material=mesh.mesh.surface_get_material(surface)
		result.surface_set_material(surface,original_material if original_material!=null else StandardMaterial3D.new())
	if not hand_arrays.is_empty():
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,hand_arrays);result.surface_set_name(3,"OriginalWeightedSkinHands");result.surface_set_material(3,mesh.mesh.surface_get_material(0))
	_weighted_mesh_cache[model_id]=result;return result

func _texture_means(mesh: ArrayMesh) -> Dictionary:
	if _texture_means_cache.has(model_id):return _texture_means_cache[model_id]
	var image:=_body_material.albedo_texture.get_image()
	if image.is_compressed():image.decompress()
	var arrays: Array=mesh.surface_get_arrays(0);var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV];var mask: PackedColorArray=arrays[Mesh.ARRAY_COLOR];var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var sums: Array[Color]=[Color(0,0,0,0),Color(0,0,0,0)];var areas: Array[float]=[0.,0.]
	# Area-weighted UV-centroid sampling measures fabric actually used by
	# the source mesh, excluding empty atlas space and the preserved hands.
	for triangle: int in range(0,indices.size(),3):
		var a: int=indices[triangle];var b: int=indices[triangle+1];var c: int=indices[triangle+2]
		var area: float=(vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).length()*.5
		var midpoint: Vector2=(uv[a]+uv[b]+uv[c])/3.
		var pixel:=image.get_pixel(clampi(int(fposmod(midpoint.x,1.)*image.get_width()),0,image.get_width()-1),clampi(int(fposmod(midpoint.y,1.)*image.get_height()),0,image.get_height()-1)).srgb_to_linear()
		var lower: bool=(mask[a].g+mask[b].g+mask[c].g)>1.5;var region:=1 if lower else 0
		sums[region]+=pixel*area;areas[region]+=area
	var result:={"jacket_linear":sums[0]/maxf(areas[0],.000001),"pants_linear":sums[1]/maxf(areas[1],.000001),"method":"original_rendered_fabric_area_weighted_uv_centroid_linear_rgb"}
	_texture_means_cache[model_id]=result;return result

func _set_materials() -> void:
	var prefix:="m006" if model_id=="Male_Adult_04" else "f007";var folder:=VENDOR+model_id+"/textures/"
	_body_material=StandardMaterial3D.new();_body_material.albedo_texture=load(folder+prefix+"_body_color.png");_body_material.normal_enabled=true;_body_material.normal_texture=load(folder+prefix+"_body_normal.png");_body_material.normal_scale=.55;_body_material.roughness=.82;_body_material.metallic_specular=.25;_body_material.vertex_color_use_as_albedo=true;_body_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;_body_material.alpha_scissor_threshold=.50
	_hand_material=_body_material.duplicate();_hand_material.vertex_color_use_as_albedo=false
	_head_material=StandardMaterial3D.new();_head_material.albedo_texture=load(folder+prefix+"_head_color.png");_head_material.normal_enabled=true;_head_material.normal_texture=load(folder+prefix+"_head_normal.png");_head_material.normal_scale=.45;_head_material.roughness=.62;_head_material.metallic_specular=.25
	var hair:=StandardMaterial3D.new();hair.albedo_texture=load(folder+prefix+"_opacity_color.png");hair.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;hair.alpha_scissor_threshold=.40;hair.cull_mode=BaseMaterial3D.CULL_DISABLED;hair.roughness=.76;hair.metallic_specular=.15
	for mesh: MeshInstance3D in visible_meshes:
		mesh.mesh=_weighted_colours(mesh);_garment_texture_means=_texture_means(mesh.mesh);mesh.set_surface_override_material(0,_body_material);mesh.set_surface_override_material(1,_head_material);mesh.set_surface_override_material(2,hair);mesh.set_surface_override_material(3,_hand_material)
	_texture_uv_ready=_head_material.albedo_texture!=null and hair.albedo_texture!=null and _body_material.albedo_texture!=null
	for surface: Dictionary in _surfaces:_texture_uv_ready=_texture_uv_ready and surface.uv_count==surface.vertices.size() and surface.uv_count>0

func _ratio(value: Color,reference: Color) -> Color:
	if value.is_equal_approx(reference):return Color.WHITE
	return Color(clampf(value.r/maxf(reference.r,.1),.20,2.0),clampf(value.g/maxf(reference.g,.1),.20,2.0),clampf(value.b/maxf(reference.b,.1),.20,2.0))

func _fabric_gain(value: Color,reference: Color,texture_mean: Color) -> Color:
	# Default attire keeps every original texture value. A selected garment
	# colour instead targets the actual fabric's measured mean reflectance.
	if value.is_equal_approx(reference):return Color.WHITE
	var linear:=value.srgb_to_linear()
	return Color(linear.r/maxf(texture_mean.r,.0001),linear.g/maxf(texture_mean.g,.0001),linear.b/maxf(texture_mean.b,.0001))

func sync_clothing() -> void:
	if not loaded:return
	var torso: MeshInstance3D=avatar.find_child("Torso",true,false)
	var jacket: Color=torso.material_override.albedo_color if torso!=null and torso.material_override is StandardMaterial3D else avatar._materials.jacket.albedo_color
	var pants: Color=avatar._materials.trousers.albedo_color;var skin: Color=avatar._materials.skin.albedo_color
	var skin_gain:=_ratio(skin,_base_colors.skin)
	_apply_palette(_fabric_gain(jacket,_base_colors.jacket,_garment_texture_means.jacket_linear),_fabric_gain(pants,_base_colors.trousers,_garment_texture_means.pants_linear),skin_gain,false)
	_head_material.albedo_color=skin_gain;_hand_material.albedo_color=Color(skin_gain.r,skin_gain.g,skin_gain.b,0. if _swimwear_active else 1.)

func _apply_palette(jacket: Color,pants: Color,skin: Color,hide_hands: bool) -> void:
	var signature:=model_id+str(jacket)+str(pants)+str(skin)+str(hide_hands)+str(_swimwear_active)
	if signature==_palette_signature:return
	_palette_signature=signature
	_palette_gain_linear=maxf(1.,maxf(maxf(jacket.r,maxf(jacket.g,jacket.b)),maxf(pants.r,maxf(pants.g,pants.b))))
	# BaseMaterial's source_color uniform receives sRGB; the vertex gains
	# remain linear and in0..1, avoiding the mesh RGBA8 channel clamp.
	_body_material.albedo_color=Color(_palette_gain_linear,_palette_gain_linear,_palette_gain_linear).linear_to_srgb()
	var result: ArrayMesh
	if _palette_mesh_cache.has(signature):result=_palette_mesh_cache[signature]
	else:
		var source: ArrayMesh=_weighted_mesh_cache[model_id];result=ArrayMesh.new()
		for index: int in range(source.get_surface_count()):
			var arrays: Array=source.surface_get_arrays(index)
			if index==0:
				var mask: PackedColorArray=arrays[Mesh.ARRAY_COLOR];var colours:=PackedColorArray()
				for part: Color in mask:
					var value:=(jacket*part.r+pants*part.g+skin*part.b)/_palette_gain_linear
					value.a=0. if _swimwear_active or (hide_hands and part.b>.65) else 1.;colours.append(value)
				arrays[Mesh.ARRAY_COLOR]=colours
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);result.surface_set_name(index,source.surface_get_name(index));result.surface_set_material(index,source.surface_get_material(index))
		_palette_mesh_cache[signature]=result
	for mesh: MeshInstance3D in visible_meshes:mesh.mesh=result

func _process(_delta: float) -> void:
	if loaded:
		sync_clothing();_sync_swim_head_join()

func _sync_swim_head_join() -> void:
	# Both native rigs finish at priority100. Their different leg lengths can
	# give different supported pelvis heights while walking. Retain the real
	# Rocketbox head/hair and translate its whole Neck subtree to the active
	# body's Head at priority110. Local neck/head lengths and rotations stay
	# intact. Measuring current engine poses makes repeated calls idempotent;
	# next frame's primary rig restores the baseline before this final fit.
	if not _swimwear_active or not is_instance_valid(_swim_skeleton) or not is_instance_valid(skeleton):return
	var neck:=skeleton.find_bone("Bip01 Neck");var head:=skeleton.find_bone("Bip01 Head");var body_neck:=_swim_skeleton.find_bone("neck01");var body_head:=_swim_skeleton.find_bone("Bip01 Head")
	if mini(mini(neck,head),mini(body_neck,body_head))<0:return
	var desired: Vector3=_swim_skeleton.global_transform*_swim_skeleton.get_bone_global_pose(body_head).origin
	var original: Vector3=skeleton.global_transform*skeleton.get_bone_global_pose(head).origin
	var shift:=desired-original
	# Preserve the exact neutral original poses: sub-micrometre import float
	# differences do not warrant changing any original bone transform.
	if shift.length()>.000001:
		var pose:=skeleton.get_bone_global_pose(neck);pose.origin+=skeleton.global_basis.inverse()*shift
		var parent:=skeleton.get_bone_parent(neck)
		skeleton.set_bone_pose(neck,pose if parent<0 else skeleton.get_bone_global_pose(parent).affine_inverse()*pose)
	var final_head: Vector3=skeleton.global_transform*skeleton.get_bone_global_pose(head).origin
	var final_neck: Vector3=skeleton.global_transform*skeleton.get_bone_global_pose(neck).origin
	var target_neck: Vector3=_swim_skeleton.global_transform*_swim_skeleton.get_bone_global_pose(body_neck).origin
	_swim_head_join={"active":true,"method":"render_only_rigid_original_neck_subtree_translation_to_swim_head","world_translation_m":shift,"head_error_m":final_head.distance_to(desired),"neck_error_m":final_neck.distance_to(target_neck),"native_neck_head_lengths_preserved":true,"process_priority":process_priority,"physics_camera_source_markers_modified":false}


func set_swimwear(enabled: bool) -> void:
	if enabled==_swimwear_active:return
	if enabled and not is_instance_valid(_swim_root):
		if not _prepare_swim_body():push_error("TEXTURED_HUMAN missing_swim_body");return
	_swimwear_active=enabled
	if is_instance_valid(_swim_root):_swim_root.visible=enabled
	if is_instance_valid(_swim_rig):_swim_rig.set_process(enabled)
	_active_body_source="makehuman_cc0_body_with_original_rocketbox_head" if enabled else "rocketbox_clothed"
	_palette_signature="";sync_clothing()
	if enabled:
		rig.sync_pose();_swim_rig.sync_pose();_sync_swim_head_join()
	else:
		rig.sync_pose();_swim_head_join={}
	_build_surface_cache();refresh_bounds()

func _head_boundary_vertex(data: Dictionary,a: int,b: int,t: float) -> int:
	if t<=.0000001:return a
	if t>=.9999999:return b
	var key:=str(mini(a,b))+":"+str(maxi(a,b))
	if data.edge_vertices.has(key):return int(data.edge_vertices[key])
	var vertices: PackedVector3Array=data.vertices;var normals: PackedVector3Array=data.normals;var uv: PackedVector2Array=data.uv
	var bones: PackedInt32Array=data.bones;var weights: PackedFloat32Array=data.weights
	var result:=vertices.size();vertices.append(vertices[a].lerp(vertices[b],t));normals.append(normals[a].lerp(normals[b],t).normalized());uv.append(uv[a].lerp(uv[b],t))
	var mixed: Dictionary={}
	for influence: int in range(4):
		var first: int=bones[a*4+influence];var second: int=bones[b*4+influence]
		mixed[first]=float(mixed.get(first,0.))+weights[a*4+influence]*(1.-t)
		mixed[second]=float(mixed.get(second,0.))+weights[b*4+influence]*t
	var ordered: Array=mixed.keys()
	ordered.sort_custom(func(first: int,second: int)->bool:return float(mixed[first])>float(mixed[second]) if not is_equal_approx(float(mixed[first]),float(mixed[second])) else first<second)
	var total:=0.
	for influence: int in range(mini(4,ordered.size())):total+=float(mixed[ordered[influence]])
	for influence: int in range(4):
		bones.append(int(ordered[influence]) if influence<ordered.size() else 0);weights.append(float(mixed[ordered[influence]])/maxf(total,.000001) if influence<ordered.size() else 0.)
	data.vertices=vertices;data.normals=normals;data.uv=uv;data.bones=bones;data.weights=weights
	if data.tangents!=null and data.tangents.size()>0:
		var tangents: PackedFloat32Array=data.tangents;var direction:=Vector3(tangents[a*4],tangents[a*4+1],tangents[a*4+2]).lerp(Vector3(tangents[b*4],tangents[b*4+1],tangents[b*4+2]),t).normalized()
		tangents.append_array(PackedFloat32Array([direction.x,direction.y,direction.z,tangents[a*4+3] if t<.5 else tangents[b*4+3]]));data.tangents=tangents
	if data.colors!=null and data.colors.size()>0:
		var colors: PackedColorArray=data.colors;colors.append(colors[a].lerp(colors[b],t));data.colors=colors
	data.edge_vertices[key]=result;return result

func _prepare_swim_body() -> bool:
	var sex:="male" if model_id=="Male_Adult_04" else "female";var path:="res://assets/vendor/makehuman_swim/swim_"+sex+".glb";var packed: PackedScene=load(path)
	if packed==null:return false
	# Keep the same person's original textured head and hair. Only the
	# separately licensed full-body surface below the neck changes with clothes.
	_swim_root=packed.instantiate();_swim_root.name="CC0TexturedSwimBody";add_child(_swim_root);_swim_root.rotation.y=PI
	for node: Node in _swim_root.find_children("*","Skeleton3D",true,false):_swim_skeleton=node as Skeleton3D;break
	if _swim_skeleton==null:return false
	for node: Node in _swim_root.find_children("*","MeshInstance3D",true,false):
		var mesh:=node as MeshInstance3D
		if "Eyes" in String(mesh.name):mesh.visible=false;continue
		if String(mesh.name)=="TexturedBody":
			var cut:=ArrayMesh.new()
			var head_index:=_swim_skeleton.find_bone("Bip01 Head");var head_binds: Array[bool]=[]
			if head_index<0:return false
			for bind_index: int in range(mesh.skin.get_bind_count()):
				var bind_name:=mesh.skin.get_bind_name(bind_index);var bone_index:=_swim_skeleton.find_bone(bind_name) if not bind_name.is_empty() else mesh.skin.get_bind_bone(bind_index)
				var head_branch:=false
				while bone_index>=0:
					if bone_index==head_index:head_branch=true;break
					bone_index=_swim_skeleton.get_bone_parent(bone_index)
				head_binds.append(head_branch)
			var removed:=0;var retained:=0;var clipped:=0;var boundary_vertices:=0
			for surface: int in range(mesh.mesh.get_surface_count()):
				var arrays: Array=mesh.mesh.surface_get_arrays(surface);var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var old_indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX];var indices:=PackedInt32Array()
				var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES];var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS];var head_scores:=PackedFloat32Array()
				var data:={"vertices":vertices,"normals":arrays[Mesh.ARRAY_NORMAL],"uv":arrays[Mesh.ARRAY_TEX_UV],"bones":bones,"weights":weights,"tangents":arrays[Mesh.ARRAY_TANGENT],"colors":arrays[Mesh.ARRAY_COLOR],"edge_vertices":{}}
				for vertex: int in range(vertices.size()):
					var score:=0.
					for influence: int in range(4):
						if head_binds[bones[vertex*4+influence]]:score+=weights[vertex*4+influence]
					head_scores.append(score)
				for triangle: int in range(0,old_indices.size(),3):
					var a: int=old_indices[triangle];var b: int=old_indices[triangle+1];var c: int=old_indices[triangle+2]
					# Interpolate the weight contour instead of rejecting complete
					# crossing triangles, which leaves small saw-tooth neck flaps.
					var triangle_vertices:=PackedInt32Array([a,b,c]);var polygon:=PackedInt32Array()
					for edge: int in range(3):
						var first: int=triangle_vertices[edge];var second: int=triangle_vertices[(edge+1)%3]
						var first_in: bool=head_scores[first]<=.50;var second_in: bool=head_scores[second]<=.50
						if first_in:polygon.append(first)
						if first_in!=second_in:polygon.append(_head_boundary_vertex(data,first,second,(.50-head_scores[first])/(head_scores[second]-head_scores[first])))
					var unique:=PackedInt32Array()
					for vertex: int in polygon:
						if unique.is_empty() or unique[-1]!=vertex:unique.append(vertex)
					if unique.size()>1 and unique[0]==unique[-1]:unique.remove_at(unique.size()-1)
					polygon=unique
					if polygon.size()<3:removed+=1;continue
					if polygon.size()!=3 or polygon!=triangle_vertices:clipped+=1
					for corner: int in range(1,polygon.size()-1):
						var points: PackedVector3Array=data.vertices
						if (points[polygon[corner]]-points[polygon[0]]).cross(points[polygon[corner+1]]-points[polygon[0]]).length_squared()<.00000000000001:continue
						indices.append_array(PackedInt32Array([polygon[0],polygon[corner],polygon[corner+1]]));retained+=1
				boundary_vertices+=data.edge_vertices.size()
				arrays[Mesh.ARRAY_VERTEX]=data.vertices;arrays[Mesh.ARRAY_NORMAL]=data.normals;arrays[Mesh.ARRAY_TEX_UV]=data.uv;arrays[Mesh.ARRAY_BONES]=data.bones;arrays[Mesh.ARRAY_WEIGHTS]=data.weights;arrays[Mesh.ARRAY_TANGENT]=data.tangents;arrays[Mesh.ARRAY_COLOR]=data.colors
				arrays[Mesh.ARRAY_INDEX]=indices;cut.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);var material: StandardMaterial3D=mesh.mesh.surface_get_material(surface).duplicate()
				# Match the original actor's exposed neck/hand tone approximately;
				# the face and hair themselves remain the exact Rocketbox textures.
				material.albedo_color=Color(.73,.65,.60) if sex=="male" else Color(.95,.88,.84);material.roughness=.62;cut.surface_set_material(surface,material)
			mesh.mesh=cut
			_swim_head_cut={"method":"head_descendant_weight_isocontour_with_shared_edge_interpolation","removed_triangles":removed,"retained_triangles":retained,"partially_clipped_source_triangles":clipped,"interpolated_boundary_vertices":boundary_vertices,"head_weight_threshold":.50,"whole_triangle_mean_rejection":false,"height_plane_used":false,"shoulder_clavicle_arm_topology_preserved":true,"interpolated_fields":["position","uv","normal","native_skin_weights"]}
		_swim_meshes.append(mesh)
	_swim_rig=RIG.new();avatar.add_child(_swim_rig)
	if not _swim_rig.setup(avatar,_swim_root,_swim_skeleton,skeleton):return false
	return true

func snapshot(refresh_actual_bounds:=false) -> Dictionary:
	if loaded and refresh_actual_bounds:refresh_bounds()
	var active_rig: Node3D=_swim_rig if _swimwear_active else rig
	var rig_data: Dictionary=active_rig.snapshot() if is_instance_valid(active_rig) and active_rig.has_method("snapshot") else {}
	return {"loaded":loaded,"error":load_error,"model_id":model_id,"visible_mesh_count":(visible_meshes+_swim_meshes).filter(func(mesh: MeshInstance3D)->bool:return mesh.is_visible_in_tree()).size(),"skeleton_bone_count":skeleton.get_bone_count() if is_instance_valid(skeleton) else 0,"actual_visible_bounds_m":_actual_bounds,"actual_height_m":_actual_bounds.size.y,"normalized_rest_height_m":REST_HEIGHT_M,"bounds_sampled_at_physics_tick":_bounds_tick,"surface_texture_uv_ready":_texture_uv_ready,"rig_contact_metrics":rig_data,"normalization_scale":_normalization_scale,"clothing_palette":{"body_gain_linear":_palette_gain_linear,"texture_means":_garment_texture_means,"hands_use_separate_original_skin_material":true},"swimwear_active":_swimwear_active,"active_body_source":_active_body_source,"swim_skeleton_bone_count":_swim_skeleton.get_bone_count() if is_instance_valid(_swim_skeleton) and _swimwear_active else 0,"original_head_and_hair_preserved":true,"swim_head_cut":_swim_head_cut,"swim_head_join":_swim_head_join,"legacy_geometry_rendered":false,"supplier":"Microsoft Rocketbox MIT head/clothes; MakeHuman CC0 body when swimming","scope":"Original textured weighted human. Bounds use CPU skinning of referenced, rendered vertices in avatar-local metres; hidden body/head replacements are excluded. No obsolete procedural geometry is rendered."}
