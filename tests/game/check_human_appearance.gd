extends SceneTree
## Retained invisible pose/wardrobe compatibility markers, not the new rendered
## human's appearance acceptance. Weighted skin and native pixels are separate.
class FixtureHost extends Node3D:
	var exploration_avatar: Node3D
class FixtureActor extends CharacterBody3D:
	var facility_control:=false
var report_path:=""
var checks: Array=[]
var measurements: Dictionary={}
var avatar: Node3D
var actor: CharacterBody3D
var host: FixtureHost
var source_hashes: Dictionary={}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	if report_path.is_empty() or not report_path.is_absolute_path():quit(2);return
	_run.call_deferred()

func _check(name_: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":name_,"passed":passed,"evidence":evidence})
	if not passed:push_warning("APPEARANCE_FAIL "+name_)

func _v(point: Vector3) -> Array:return [point.x,point.y,point.z]
func _bounds() -> AABB:
	var bounds:=AABB();var initialized:=false
	for node: MeshInstance3D in avatar._meshes:
		var box: AABB=node.global_transform*node.get_aabb();bounds=box if not initialized else bounds.merge(box);initialized=true
	return bounds

func _run() -> void:
	for path: String in ["res://scripts/player/exploration_avatar.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://scripts/player/human_activity_dimensions.gd","res://assets/vendor/microsoft_rocketbox/PROVENANCE.json","res://assets/vendor/microsoft_rocketbox/Male_Adult_04/Export/Male_Adult_04.fbx","res://assets/vendor/microsoft_rocketbox/Female_Adult_07/Export/Female_Adult_07.fbx","res://assets/vendor/makehuman_swim/provenance.json","res://assets/vendor/makehuman_swim/swim_male.glb","res://assets/vendor/makehuman_swim/swim_female.glb","res://scripts/player/human_surface_meshes.gd","res://scripts/shop_visit_service.gd","res://../tests/game/check_human_appearance.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	host=FixtureHost.new();root.add_child(host);actor=FixtureActor.new();host.add_child(actor);var visual:=Node3D.new();visual.name="Visual";actor.add_child(visual)
	var original:=MeshInstance3D.new();original.name="Body";visual.add_child(original)
	avatar=load("res://scripts/player/exploration_avatar.gd").new();visual.add_child(avatar);host.exploration_avatar=avatar
	_check("production_avatar_setup",avatar.setup(actor));avatar.set_physics_process(false)
	var bounds:=_bounds();var head: MeshInstance3D=avatar.find_child("Head",true,false);var head_box: AABB=head.global_transform*head.get_aabb()
	measurements={"minimum_m":_v(bounds.position),"maximum_m":_v(bounds.end),"size_m":_v(bounds.size),"head_size_m":_v(head_box.size),"mesh_count":avatar._meshes.size(),"eye_height_m":avatar.snapshot().eye_height_m}
	var extremes: Array=[]
	for mesh: MeshInstance3D in avatar._meshes:
		var box: AABB=mesh.global_transform*mesh.get_aabb()
		if box.end.x>.303 or box.position.x<-.303:extremes.append({"part":String(mesh.name),"min":_v(box.position),"max":_v(box.end)})
	measurements["width_extremes"]=extremes
	_check("adult_1_70m_shoes_to_hair_and_ground_clearance",absf(bounds.end.y-1.70)<.005 and bounds.position.y>=-.004 and bounds.position.y<.015,measurements)
	_check("head_retains_23cm_and_adult_proportion",absf(head_box.size.y-.23)<.001 and bounds.size.y/head_box.size.y>7.2 and bounds.size.y/head_box.size.y<7.6,measurements)
	_check("adult_body_fits_original_width_and_depth",bounds.size.x<.61 and bounds.size.z<.47,measurements)
	var surfaces:=0;var primitives:=0;var bad_normals:=0;var vertices:=0;var faces:=0;var inverted:=0
	for node: MeshInstance3D in avatar._meshes:
		if not node.mesh is ArrayMesh:primitives+=1;continue
		surfaces+=1
		var arrays:=node.mesh.surface_get_arrays(0);var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL];var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		vertices+=points.size();faces+=indices.size()/3
		for normal: Vector3 in normals:
			if not normal.is_finite() or absf(normal.length()-1.)>.001:bad_normals+=1
		for i: int in range(0,indices.size(),3):
			var a:=indices[i];var b:=indices[i+1];var c:=indices[i+2];var cross_: Vector3=(points[b]-points[a]).cross(points[c]-points[a])
			if cross_.length()>.00000001 and cross_.dot(normals[a]+normals[b]+normals[c])>0.:inverted+=1
	measurements["custom_surfaces"]={"mesh_instances":surfaces,"remaining_detail_primitives":primitives,"instanced_vertices":vertices,"instanced_triangles":faces,"invalid_normals":bad_normals,"clockwise_winding_mismatches":inverted}
	_check("connected_anatomy_clothes_and_shoes_use_smooth_custom_meshes",surfaces>=23 and head.mesh is ArrayMesh and avatar.find_child("Torso",true,false).mesh is ArrayMesh and avatar.find_child("LeftShoe",true,false).mesh is ArrayMesh,measurements.custom_surfaces)
	_check("custom_surfaces_have_finite_unit_normals_and_godot_front_faces",bad_normals==0 and inverted==0,measurements.custom_surfaces)
	_check("face_has_jaw_eyes_lids_brows_lips_nose_ears_and_hair",["EyeLid","EyeSclera","EyeIris","EyeBrow","UpperLip","LowerLip","Nose","Ear","Hair"].all(func(title: String)->bool:return head.find_child(title,true,false)!=null))
	var materials: Dictionary=avatar._materials
	_check("skin_fabric_hair_and_eyes_have_different_surface_response",materials.skin.roughness<materials.jacket.roughness and materials.eye.roughness<materials.skin.roughness and materials.jacket.roughness_texture!=null and materials.hair.roughness!=materials.skin.roughness)
	_check("no_new_physics_geometry_or_movement_owner",avatar.find_children("*","CollisionObject3D",true,false).is_empty() and not original.visible)
	var second: Node3D=load("res://scripts/player/exploration_avatar.gd").new();var second_actor:=FixtureActor.new();host.add_child(second_actor);var second_visual:=Node3D.new();second_visual.name="Visual";second_actor.add_child(second_visual);var old2:=MeshInstance3D.new();old2.name="Body";second_visual.add_child(old2);second_visual.add_child(second);second.setup(second_actor);second.set_physics_process(false)
	_check("npc_mesh_resources_are_shared_but_skin_and_uniform_materials_are_independent",second.find_child("Head",true,false).mesh==head.mesh and second._materials.skin!=materials.skin and second._materials.jacket!=materials.jacket)
	var shop: Node3D=load("res://scripts/shop_visit_service.gd").new();host.add_child(shop);shop.host=host;shop.loaded=true;shop.set_process(false);shop.set_physics_process(false);shop.set_process_input(false);shop.set_process_unhandled_input(false);shop._remember_clothing()
	var clothes:=0;var all_saved:=true
	for node: MeshInstance3D in avatar._meshes:
		if node.material_override in [materials.jacket,materials.jacket_trim,materials.shirt] and not String(node.get_meta("avatar_part","")).ends_with("ShoeLaces"):clothes+=1;all_saved=all_saved and shop._original_clothing.has(node.get_instance_id())
	_check("every_new_collar_placket_cuff_and_fitted_clothing_surface_is_in_existing_shop_contract",clothes>0 and all_saved and shop._original_clothing.has(avatar.find_child("Torso",true,false).get_instance_id()) and shop._original_clothing.has(avatar.find_child("Shirt",true,false).get_instance_id()),{"clothing_surfaces":clothes,"remembered_surfaces":shop._original_clothing.size()})
	var references: Array=[]
	for node: MeshInstance3D in avatar._meshes:references.append({"node":node,"mesh":node.mesh,"material":node.material_override,"visible":node.visible})
	var began: bool=shop.begin_swimwear();var swim_valid:=true;var hidden:=0;var skin_count:=0
	for node: MeshInstance3D in avatar._meshes:
		var part: String=node.get_meta("avatar_part","")
		if part in ["Shirt","JacketFront","JacketHem","LeftShoe","RightShoe","LeftShoeSole","RightShoeSole","LeftShoeLaces","RightShoeLaces"]:swim_valid=swim_valid and not node.visible;hidden+=1
		elif part in ["Torso","LeftSleeve","RightSleeve","LeftLowerSleeve","RightLowerSleeve","LeftLowerLeg","RightLowerLeg"]:swim_valid=swim_valid and node.material_override.albedo_color.is_equal_approx(materials.skin.albedo_color);skin_count+=1
	_check("existing_swimwear_transition_hides_all_garment_details_and_recolors_body",began and swim_valid and hidden>0 and skin_count==7 and shop._swim_feet.size()==2,{"hidden":hidden,"skin_surfaces":skin_count})
	var bare_torso: MeshInstance3D=avatar.find_child("Torso",true,false);var bare_bounds: AABB=bare_torso.global_transform*bare_torso.get_aabb()
	_check("swim_bare_torso_meets_waist_and_uses_skin_surface_instead_of_jacket_fabric",bare_bounds.position.y>1.0 and bare_bounds.position.y<1.02 and bare_torso.material_override.roughness_texture==materials.skin.roughness_texture and is_equal_approx(bare_torso.material_override.roughness,materials.skin.roughness),{"torso_bottom_m":bare_bounds.position.y,"skin_roughness":bare_torso.material_override.roughness})
	var ended: bool=shop.end_swimwear();var restored:=true
	for row: Dictionary in references:restored=restored and row.node.mesh==row.mesh and row.node.material_override==row.material and row.node.visible==row.visible
	_check("swimwear_restores_exact_meshes_materials_and_visibility",ended and restored and shop._swim_feet.is_empty() and avatar._swim_mesh_defaults.is_empty())
	var max_error:=0.;var invalid_pose:=false
	for activity: String in ["eat","weights","treadmill","cycle","rowing","shower"]:
		for time_: float in [0.,.25,.5,1.,1.75]:
			avatar.set_activity(activity,time_)
			for node: MeshInstance3D in avatar._meshes:invalid_pose=invalid_pose or not node.global_transform.is_finite()
			if activity=="weights":
				var curl:=(1.-cos(time_*TAU/2.))* .5
				for index: int in range(2):
					var side: String="Left" if index==0 else "Right";var hand: MeshInstance3D=avatar._hands[index];var actual: Vector3=avatar._joints[side+"UpperArm"].transform*avatar._joints[side+"Forearm"].transform*hand.position;var target:=Vector3((-.43 if index==0 else .43),.92+curl*.44,-.12-curl*.14);max_error=maxf(max_error,actual.distance_to(target))
	_check("all_existing_activity_poses_remain_finite_and_hands_keep_equipment_contacts",not invalid_pose and max_error<.025,{"maximum_dumbbell_contact_error_m":max_error})
	avatar.set_activity("",0.);_check("rest_pose_preserves_level_head_anchor_and_zero_roll",avatar._upper_body.position==Vector3(0,.85,0) and avatar._upper_body.rotation==Vector3.ZERO)
	var failed:=checks.filter(func(row: Dictionary)->bool:return not row.passed).size()
	var report:={"task":"EXP29_RETAINED_POSE_WARDROBE_COMPATIBILITY","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"measurements":measurements,"source_sha256":source_hashes,"scope":"Retained invisible pose/wardrobe markers and existing shop/swim/activity component APIs only. These procedural meshes were rejected as visible art and are not the current appearance acceptance. Actual weighted human geometry, native visual judgment and city navigation have separate evidence."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n");file.close();print("HUMAN_APPEARANCE_RESULT ",checks.size()-failed,"/",checks.size());host.free();quit(0 if failed==0 else 1)
