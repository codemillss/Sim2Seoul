extends "res://../tests/game/check_rooftop_swimming.gd"
## Native source-bound exterior structures, retained collision, safe viewpoints.
const LOTTE_ID := "osm:way:117914845:building"
const RETAIL_ID := "osm:way:233592424:building"
var exterior: Node3D
var exterior_observations: Array=[]
var facade_views: Array=[]
var capture_sequence_requested := false

func _avatar_mesh_identity() -> Array:
	var result: Array=[]
	for node: Node in _descendants(scene.player.get_node("Visual")):
		if node is MeshInstance3D and node.mesh!=null:result.append({"node":node.get_instance_id(),"mesh":node.mesh.get_instance_id()})
	return result

func _actual_avatar_projection(camera: Camera3D) -> Dictionary:
	var head_rect := Rect2();var body_rect := Rect2()
	var have_head := false;var have_body := false
	var head_parts: Array[String]=[];var mesh_count: int=0
	var all_head_corners_in_front := true
	for node: Node in _descendants(scene.player.get_node("Visual")):
		if not node is MeshInstance3D or node.mesh==null or not node.is_visible_in_tree():continue
		var part: String=String(node.get_meta("avatar_part",""))
		var is_head: bool=part in ["Head","Hair","HairBack","Nose","Eye"]
		var bounds: AABB=node.mesh.get_aabb()
		mesh_count+=1
		if is_head:head_parts.append(part)
		# Read rendered mesh transforms after the production camera/avatar
		# interpolation. This does not reuse the wayfinding placement helper.
		for corner in range(8):
			var world: Vector3=node.global_transform*bounds.get_endpoint(corner)
			if camera.is_position_behind(world):
				if is_head:all_head_corners_in_front=false
				continue
			var pixel: Vector2=camera.unproject_position(world)
			body_rect=body_rect.expand(pixel) if have_body else Rect2(pixel,Vector2.ZERO)
			have_body=true
			if is_head:
				head_rect=head_rect.expand(pixel) if have_head else Rect2(pixel,Vector2.ZERO)
				have_head=true
	return {"head_projection_rect":head_rect,"avatar_projection_rect":body_rect,"head_parts":head_parts,"visible_meshes_projected":mesh_count,"all_head_corners_in_front":all_head_corners_in_front,"head_mesh_observed":"Head" in head_parts and have_head and head_rect.has_area()}

func _facade_ray(id: String, origin: Vector3, point: Vector3) -> Dictionary:
	var ray: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(origin,point,scene.rig.arm.collision_mask,[scene.player.get_rid()])
	var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():return {"clear":true,"collision_id":"","target_surface_hit":false}
	var collider: Object=hit.get("collider")
	var collision_id: String=String(collider.get_meta("geometry_id","")) if is_instance_valid(collider) else ""
	var target_hit: bool=collision_id==id and Vector3(hit.position).distance_to(point)<.6
	return {"clear":target_hit,"collision_id":collision_id,"target_surface_hit":target_hit}

func _test_only_viewpoint_candidates(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var record: Dictionary=exterior._by_id.get(id,{})
	if record.is_empty():return result
	# The optional runtime helper proposes supported ground, not an unoccluded
	# photograph. Other source walls and greater viewing distances are explicit
	# test-only candidates; source geometry, boundaries and collisions remain.
	for face: Dictionary in record.faces:
		if float(face.width)<8.:continue
		var frame: Transform3D=face.frame
		for distance: float in [28.,42.,18.,60.,90.,125.]:
			for fraction: float in [0.,-.25,.25,-.40,.40]:
				var local_x: float=float(face.width)*fraction
				var requested: Vector3=frame*Vector3(local_x,.08,distance)
				var safe: Dictionary=visit._safe_external_point(requested)
				if safe.is_empty():continue
				var face_point: Vector3=frame*Vector3(local_x,0.,.30)
				var direction: Vector3=Vector3(face_point.x-safe.point.x,0.,face_point.z-safe.point.z).normalized()
				var eye: Vector3=safe.point+Vector3.UP*(scene.rig.pivot_height_m-sin(deg_to_rad(6.))*scene.rig.default_distance_m)-direction*cos(deg_to_rad(6.))*scene.rig.default_distance_m
				var visible_sample: Dictionary={}
				for height: float in [6.,10.,16.,26.,40.,65.]:
					if height>=float(record.source_height_m)-2.:continue
					var target: Vector3=frame*Vector3(local_x,height,.30)
					var offset: Vector3=target-eye
					var angle: float=atan2(offset.y,Vector2(offset.x,offset.z).length())
					if angle<deg_to_rad(-8.) or angle>deg_to_rad(25.):continue
					var ray: Dictionary=_facade_ray(id,eye,target)
					if bool(ray.clear):visible_sample={"sample":target,"estimated_eye":eye};break
				if visible_sample.is_empty():continue
				result.append({"id":id,"title":record.title,"point":safe.point,"toward":face_point+Vector3.UP*12.,"kind":"explicit_test_only_supported_source_facade_viewpoint_with_preliminary_LOS","distance_from_source_face_m":distance,"fraction_along_source_face":fraction,"preliminary":visible_sample})
	return result

func _set_capture_fixture_pose(destination: Dictionary) -> void:
	scene.player.global_transform=Transform3D(Basis.IDENTITY,destination.point)
	scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation()
	var direction: Vector3=destination.toward-scene.player.global_position
	scene.rig.yaw=atan2(-direction.x,-direction.z)
	scene.rig.pitch=deg_to_rad(6.);scene.rig.requested_distance=scene.rig.default_distance_m
	scene.rig.snap_to_target_pose()

func _actual_facade_target(id: String) -> Dictionary:
	var record: Dictionary=exterior._by_id.get(id,{})
	if record.is_empty():return {}
	var camera: Camera3D=scene.rig.camera
	var viewport: Rect2=scene.get_viewport().get_visible_rect()
	var usable: Rect2=Rect2(Vector2(24.,110.),viewport.size-Vector2(48.,140.))
	var candidates: Array[Dictionary]=[]
	var bounds: AABB=record.source_bounds
	# Named profiles have distinct batches. Inspect their actual uploaded
	# transforms, choosing a real facade part clear of the top/bottom UI.
	for batch: MultiMeshInstance3D in exterior.batches:
		if not String(batch.name).begins_with("Exterior_"+String(record.profile)+"_"):continue
		for index in range(batch.multimesh.instance_count):
			var transform: Transform3D=batch.global_transform*batch.multimesh.get_instance_transform(index)
			var point: Vector3=transform.origin
			if point.y<bounds.position.y+3.5 or camera.is_position_behind(point):continue
			var pixel: Vector2=camera.unproject_position(point)
			if not usable.has_point(pixel):continue
			var offset: Vector2=(pixel-viewport.size*Vector2(.5,.43))/viewport.size
			candidates.append({"point":point,"pixel":pixel,"batch":String(batch.name),"instance":index,"score":offset.length_squared(),"part_bounds":transform*batch.multimesh.mesh.get_aabb()})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return float(a.score)<float(b.score))
	var blocked_by: Dictionary={}
	for candidate: Dictionary in candidates:
		var ray: Dictionary=_facade_ray(id,camera.global_position,candidate.point)
		if not bool(ray.clear):
			blocked_by[String(ray.collision_id)]=int(blocked_by.get(String(ray.collision_id),0))+1
			continue
		candidate["physics_line_of_sight_clear"]=true
		candidate["first_collision_geometry_id"]=ray.collision_id
		candidate["target_source_surface_hit"]=ray.target_surface_hit
		candidate["projected_candidates"]=candidates.size()
		return candidate
	return {"physics_line_of_sight_clear":false,"projected_candidates":candidates.size(),"blocker_counts":blocked_by}

func _capture_exterior_view(id: String, destination: Dictionary, index: int) -> void:
	var title: String="exterior_%02d_"%index+id.replace(":","_")
	if DisplayServer.get_name()=="headless":
		deferred_checks.append({"name":"capture."+title,"reason":"Native camera/actual facade projection/PNG require a rendered viewport; headless query tests remain separate."})
		return
	var safe: Dictionary=visit._safe_external_point(destination.get("point",Vector3.INF))
	_check("capture_pose."+title+".destination_still_has_actual_clear_ground",not safe.is_empty(),{"destination":destination})
	if safe.is_empty():return
	var avatar: Node3D=scene.player.get_node("Visual")
	var avatar_id: int=avatar.get_instance_id()
	var avatar_meshes: Array=_avatar_mesh_identity()
	var collision_mask: int=scene.rig.arm.collision_mask
	var recoveries: int=scene.player.recoveries
	var observed_destination: Dictionary=destination.duplicate(true)
	observed_destination.point=safe.point
	placements.append({"name":title,"kind":"explicit_test_only_supported_exterior_viewpoint_fixture_not_a_walk","point":safe.point,"building_id":id})
	_set_capture_fixture_pose(observed_destination)
	_movement();_e(false);await _ticks(18)
	# A normal street orbit keeps the complete avatar and the lower facade in
	# frame. No fly camera, raised pivot, hidden avatar or mask change is used.
	scene.rig.snap_to_target_pose();await _ticks(18)
	var original_target: Dictionary=_actual_facade_target(id)
	var candidate_probes: Array=[]
	if not bool(original_target.get("physics_line_of_sight_clear",false)):
		for candidate: Dictionary in _test_only_viewpoint_candidates(id):
			# These are labelled synchronous view-pose probes, with no simulated
			# walking or hidden collision/visibility changes between candidates.
			_set_capture_fixture_pose(candidate)
			var probe: Dictionary=_actual_facade_target(id)
			var accepted: bool=bool(probe.get("physics_line_of_sight_clear",false)) and _camera_clear() and scene.rig.current_distance>1.5
			candidate_probes.append({"point":candidate.point,"target":probe,"accepted":accepted})
			placements.append({"name":title+"_candidate_%d"%candidate_probes.size(),"kind":"explicit_test_only_synchronous_supported_view_pose_probe_not_a_walk","point":candidate.point,"building_id":id,"accepted":accepted})
			if accepted:observed_destination=candidate;break
		_set_capture_fixture_pose(observed_destination)
		_movement();_e(false);await _ticks(36)
	await process_frame;RenderingServer.force_draw(false,0.)
	var target: Dictionary=_actual_facade_target(id)
	var camera: Camera3D=scene.rig.camera
	var visible_meshes: int=0
	for node: Node in _descendants(avatar):
		if node is MeshInstance3D and node.is_visible_in_tree():visible_meshes+=1
	var viewport: Rect2=scene.get_viewport().get_visible_rect()
	var avatar_feet: Vector3=scene.player.global_position+Vector3.UP*.1
	var avatar_head: Vector3=scene.player.global_position+Vector3.UP*1.62
	var avatar_in_frame: bool=not camera.is_position_behind(avatar_feet) and not camera.is_position_behind(avatar_head) and viewport.has_point(camera.unproject_position(avatar_feet)) and viewport.has_point(camera.unproject_position(avatar_head))
	var supported: bool=scene.player.is_on_floor() and scene.player.global_position.distance_to(observed_destination.point)<.15 and scene.player.recoveries==recoveries and not visit.active and not scene.player.interior_active
	var normal_camera: bool=camera.current and scene.get_viewport().get_camera_3d()==camera and scene.rig.arm.collision_mask==collision_mask and scene.rig.requested_distance>=scene.rig.distance_min_m and scene.rig.requested_distance<=scene.rig.distance_max_m and scene.rig.pitch>=deg_to_rad(scene.rig.pitch_min_degrees) and scene.rig.pitch<=deg_to_rad(scene.rig.pitch_max_degrees)
	var avatar_preserved: bool=avatar.get_instance_id()==avatar_id and _avatar_mesh_identity()==avatar_meshes and avatar.is_visible_in_tree() and visible_meshes>0 and avatar_in_frame
	var evidence: Dictionary={"id":id,"name":title,"title":destination.title,"runtime_proposed_viewpoint":destination.point,"runtime_proposal_actual_target_observation":original_target,"observed_fixture_viewpoint":observed_destination,"test_only_candidate_pose_probes":candidate_probes,"player":scene.player.global_position,"supported_exterior_pose":supported,"camera":camera.global_transform,"camera_state":scene.rig.snapshot(),"camera_height_above_player_feet_m":camera.global_position.y-scene.player.global_position.y,"camera_overlap_clear":_camera_clear(),"camera_collision_mask_before":collision_mask,"camera_collision_mask_after":scene.rig.arm.collision_mask,"normal_camera_controls":normal_camera,"avatar_instance_preserved":avatar.get_instance_id()==avatar_id,"avatar_mesh_identity_preserved":_avatar_mesh_identity()==avatar_meshes,"avatar_visible":avatar.is_visible_in_tree(),"visible_avatar_meshes":visible_meshes,"avatar_feet_and_head_in_viewport":avatar_in_frame,"actual_native_facade_target":target,"scope":"Supported exterior placement and any alternate source-face camera probes are labelled test fixtures. Runtime proposal LOS failure remains recorded; the runtime helper is unchanged. Physics LOS checks colliders; non-colliding foliage and visual recognition require direct PNG review. Street view shows the visible facade portion, not necessarily the full tower/crown."}
	_check("capture_pose."+title+".production_camera_avatar_and_actual_facade_are_observable",supported and normal_camera and avatar_preserved and _camera_clear() and bool(target.get("physics_line_of_sight_clear",false)) and target.has("point"),evidence)
	var projection: Dictionary=_actual_avatar_projection(camera)
	var head_rect: Rect2=projection.head_projection_rect
	var way_panel: Control=visit.wayfinding.panel as Control
	var panel_rect: Rect2=way_panel.get_global_rect()
	var panel_visible: bool=way_panel.is_visible_in_tree()
	var head_overlap: Rect2=head_rect.intersection(panel_rect) if panel_visible else Rect2()
	var body_overlap: Rect2=Rect2(projection.avatar_projection_rect).intersection(panel_rect) if panel_visible else Rect2()
	var head_clear: bool=bool(projection.head_mesh_observed) and bool(projection.all_head_corners_in_front) and viewport.encloses(head_rect) and not head_overlap.has_area()
	evidence["actual_avatar_mesh_projection"]=projection
	evidence["entrance_panel_visible"]=panel_visible;evidence["entrance_panel_global_rect"]=panel_rect
	evidence["entrance_panel_head_overlap_px2"]=head_overlap.get_area()
	evidence["entrance_panel_whole_avatar_overlap_px2"]=body_overlap.get_area()
	_check("capture_pose."+title+".entrance_panel_has_zero_overlap_with_actual_avatar_head",head_clear,{"head_projection_rect":head_rect,"avatar_projection_rect":projection.avatar_projection_rect,"projected_head_parts":projection.head_parts,"all_head_corners_in_front":projection.all_head_corners_in_front,"panel_visible":panel_visible,"panel_global_rect":panel_rect,"head_overlap_rect":head_overlap,"head_overlap_px2":head_overlap.get_area(),"whole_avatar_overlap_px2":body_overlap.get_area(),"scope":"Actual visible head/hair/face mesh bounds projected independently of runtime wayfinding; no panel, avatar or camera visibility override."})
	var picture: Image=scene.get_viewport().get_texture().get_image()
	var path: String=report_path.trim_suffix(".json")+"_"+title+".png"
	var saved: bool=not picture.is_empty() and picture.save_png(path)==OK
	evidence["captured"]=saved;evidence["path"]=path;evidence["width"]=picture.get_width();evidence["height"]=picture.get_height()
	facade_views.append(evidence);captures.append(evidence)
	_check("capture."+title+".native_png_saved",saved,evidence)

func _run() -> void:
	for path: String in ["res://scripts/building_exterior_identity.gd","res://scripts/city_facades.gd","res://assets/authored/building_exteriors.json","res://resources/world_geometry/world.json","res://scripts/entrance_wayfinding.gd","res://scripts/player/exploration_camera.gd","res://scripts/player/exploration_avatar.gd","res://scripts/player/free_roam_player.gd","res://scenes/world/explore_walk.tscn","res://../tests/game/check_building_exterior_identity.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json";root.add_child(scene)
	if not scene.runtime_ok:_check("startup",false);_finish();return
	visit=scene.interior_visit;await _ticks(25);original_inventory=_inventory()
	exterior=scene.get_node_or_null("BuildingExteriorIdentity")
	_check("startup.exterior_identity_is_wired_into_production_scene",is_instance_valid(exterior))
	if not is_instance_valid(exterior):_finish();return
	_check("startup.real_native_batches_and_design_source_match",exterior.loaded and exterior.design.world_sha256==FileAccess.get_sha256("res://resources/world_geometry/world.json") and exterior.batches.size()>0 and exterior.piece_count>1000,exterior.snapshot())
	if not exterior.loaded:_finish();return
	var source_errors: Array=[]
	for id: String in exterior.source_before:
		var source: MeshInstance3D=scene.city.source_nodes.get(id) as MeshInstance3D
		if not is_instance_valid(source) or exterior._source_state(source)!=exterior.source_before[id]:source_errors.append(id)
	_check("source.actual_nodes_mesh_faces_transforms_bounds_unchanged",source_errors.is_empty(),{"checked":exterior.source_before.size(),"changed_ids":source_errors})
	var collision_nodes: Array=[]
	for node: Node in _descendants(exterior):
		if node is CollisionObject3D or node is CollisionShape3D:collision_nodes.append(String(node.get_path()))
	_check("geometry.detail_introduces_no_collision_bodies_or_shapes",collision_nodes.is_empty(),{"collision_nodes":collision_nodes})
	var required: Dictionary={LOTTE_ID:"lotte_vertical",HOTEL_ID:"plaza_faceted","osm:way:377289798:building":"koreana_glass","osm:way:332565592:building":"sfc_grouped_piers",RETAIL_ID:"lotte_retail_stone"}
	var profiles: Dictionary={};var named_errors: Array=[]
	for record: Dictionary in exterior.records:
		profiles[String(record.profile)]=true
		if not required.has(String(record.id)):continue
		var source: MeshInstance3D=scene.city.source_nodes[String(record.id)]
		var row: Dictionary={"id":record.id,"profile":record.profile,"source_height_m":record.source_height_m,"actual_bounds":record.source_bounds,"treated_faces":record.treated_faces,"pieces":record.pieces,"ingredients":record.ingredients,"source_surface_is_generic_shader":source.material_override is ShaderMaterial,"native_part_bounds":null,"native_part_count":0,"native_parts_checked":0,"transform_evidence":"actual_native_MultiMesh_readback"}
		var bounds: AABB=record.source_bounds
		var have_bounds: bool=false;var height_violations: int=0
		var headless: bool=DisplayServer.get_name()=="headless"
		for batch: MultiMeshInstance3D in exterior.batches:
			if not String(batch.name).begins_with("Exterior_"+String(record.profile)+"_"):continue
			row.native_part_count+=batch.multimesh.instance_count
			# Godot's dummy renderer returns identity transforms. Counts remain
			# observable, but bounds require the same test with a native renderer.
			if headless:continue
			for index in range(batch.multimesh.instance_count):
				var transform: Transform3D=batch.global_transform*batch.multimesh.get_instance_transform(index)
				var actual: AABB=transform*batch.multimesh.mesh.get_aabb()
				if actual.position.y<bounds.position.y+.04 or actual.end.y>bounds.end.y-.04:height_violations+=1
				row.native_part_bounds=actual if not have_bounds else row.native_part_bounds.merge(actual)
				have_bounds=true;row.native_parts_checked+=1
		if headless:
			row.transform_evidence="DEFERRED_headless_dummy_renderer_has_no_native_transform_readback"
			deferred_checks.append({"name":"native.source_height_envelope."+String(record.id),"reason":"Headless dummy RenderingServer returns identity MultiMesh transforms; actual instance counts and structural profiles are checked, but their uploaded positions/height bounds require the same test on the GPU."})
		row["height_violations"]=height_violations
		if record.profile!=required[String(record.id)] or int(record.treated_faces)<2 or int(record.pieces)<30 or record.ingredients.size()<4 or source.material_override is ShaderMaterial or height_violations>0 or int(row.native_part_count)!=int(record.pieces) or (not headless and int(row.native_parts_checked)!=int(record.pieces)):named_errors.append(row)
		exterior_observations.append(row)
	_check("named.five_source_buildings_have_distinct_actual_structural_profiles",exterior_observations.size()==required.size() and named_errors.is_empty(),{"buildings":exterior_observations,"errors":named_errors})
	var generic: Array[String]=["glass_office","stone_office","brick_shopfront","hotel_ribbon","plaster_balcony","service_hall"]
	var missing: Array[String]=[]
	for profile: String in generic:
		if not profiles.has(profile):missing.append(profile)
	_check("background.six_structural_archetypes_are_actually_built",missing.is_empty(),{"profile_counts":exterior.profile_counts,"missing":missing,"batches":exterior.batches.size(),"native_parts":exterior.piece_count})
	var plaza_parts: int=0;var lotte_parts: int=0
	for row: Dictionary in exterior_observations:
		if row.profile=="plaza_faceted":plaza_parts=int(row.native_part_count)
		if row.profile=="lotte_vertical":lotte_parts=int(row.native_part_count)
	_check("named.plaza_faceted_surrounds_and_lotte_continuous_ribs_are_different_geometry",plaza_parts>lotte_parts and plaza_parts>500,{"plaza_native_parts":plaza_parts,"lotte_native_parts":lotte_parts})
	_check("references.photo_observation_and_authored_interpretation_separated",exterior.design.references.size()==4 and exterior.design.scope.imported_images_or_models==false and exterior.design.scope.surveyed_reconstruction==false,{"references":exterior.design.references,"scope":exterior.design.scope})
	scene.set_free_roam(true);_movement();_e(false);await _ticks(4)
	var pose: Transform3D=scene.player.global_transform
	var modes: Dictionary={"free_roam":scene.player.free_roam_enabled,"interior":scene.player.interior_active,"active":visit.active,"controls":scene.input_router.gameplay_enabled}
	var viewpoints: Array=[]
	for id: String in [LOTTE_ID,HOTEL_ID,"osm:way:377289798:building","osm:way:332565592:building",RETAIL_ID]:
		var destination: Dictionary=exterior.destination(id)
		var valid: bool=not destination.is_empty() and scene.player.exterior_contains(destination.point) and not visit._safe_external_point(destination.point).is_empty() and destination.point.y<2.
		viewpoints.append({"id":id,"valid":valid,"destination":destination})
		_check("viewpoint."+id+".uses_safe_existing_exterior_ground",valid,{"destination":destination})
	_check("viewpoint.query_never_moves_player_or_changes_visit_mode",scene.player.global_transform==pose and scene.player.free_roam_enabled==modes.free_roam and scene.player.interior_active==modes.interior and visit.active==modes.active and scene.input_router.gameplay_enabled==modes.controls,{"before":pose,"after":scene.player.global_transform,"viewpoints":viewpoints})
	var lotte: Dictionary={};var retail: Dictionary={}
	for analysis: Dictionary in exterior.design.source_extent_analysis:
		if analysis.id==LOTTE_ID:lotte=analysis
		if analysis.id==RETAIL_ID:retail=analysis
	_check("source.lotte_extents_and_partial_roam_overlap_are_explicit",not lotte.is_empty() and not retail.is_empty() and absf(float(lotte.source_height_m)-150.)<.001 and absf(float(lotte.overlap_percent)-98.19290859)<.0001 and absf(float(retail.overlap_percent)-1.99026938)<.0001 and not lotte.interior_catalog_present and not retail.interior_catalog_present,{"hotel":lotte,"department_store":retail})
	# Query nonmutation above is completed before these explicit capture-only
	# placements. Every PNG uses the production rig and the retained avatar.
	capture_sequence_requested=true
	for index in range(viewpoints.size()):
		var viewpoint: Dictionary=viewpoints[index]
		if bool(viewpoint.valid):await _capture_exterior_view(String(viewpoint.id),viewpoint.destination,index+1)
	_check("source.original_collision_inventory_preserved",_inventory()==original_inventory,{"original_bodies":original_inventory.size()})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	if capture_sequence_requested and DisplayServer.get_name()!="headless":
		var saved: int=0
		for view: Dictionary in facade_views:
			if bool(view.get("captured",false)):saved+=1
		_check("capture.five_distinct_native_exterior_images_completed",facade_views.size()==5 and saved==5,{"observed_views":facade_views.size(),"saved_images":saved})
	var failed: int=0
	for check: Dictionary in checks:
		if not check.passed:failed+=1
	var result: Dictionary={"task":"SOURCE_BOUND_BUILDING_EXTERIOR_IDENTITY","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed,"native_exterior_views":facade_views.size()},"checks":checks,"named_native_geometry":exterior_observations,"facade_views":facade_views,"captures":captures,"placements":placements,"deferred_checks":deferred_checks,"scope":"Checks the production hook, named/archetype MultiMesh geometry, source preservation, zero new collision and nonmutating supported viewpoint queries. Native GPU runs read every uploaded named-part transform and then make five labelled safe-ground fixture placements, preserving the production camera collision and original avatar, checking actual facade-part projection/physics LOS and saving five PNGs. These fixtures are not a continuous walking route. Headless dummy runs defer native transforms and images. Official photo observations, authored interpretation and direct visual acceptance remain distinct; performance and real-building access are outside this check."}
	var file: FileAccess=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(result),"\t")+"\n");file.close()
	else:failed+=1;push_error("Cannot save building exterior report")
	print("BUILDING_EXTERIOR_IDENTITY_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)
