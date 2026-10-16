extends "res://../tests/game/check_interior_identity.gd"
## EXP10: independent facility geometry, circulation and production-controller checks.
## This inherits the full source-sized floor/portal regression, not facility counters.
var facility_errors: Array = []
var facility_counts := {}
var facility_profiles := {}
var facility_samples := {}
var facility_rooms := {}
var facility_capsules := 0
var facility_support_rays := 0
var facility_geometry_count := 0
var facility_sign_count := 0
var facility_gpu: Array = []
var facility_walks: Array = []
const EQUIPMENT := {"buffet":["FacilityBuffetCounter"],"kitchen":["FacilityKitchenCounter"],"fitness":["FacilityTreadmill"],"strength":["FacilityWeightBench","FacilityDumbbellRack"],"spa":["FacilityShowerPartition","FacilityBathSide"],"spa_lockers":["FacilityLockerBank"],"banquet":["FacilityDiningTable"],"business_lounge":["FacilityBusinessDesk"],"classroom":["FacilityLectureDesk"],"laundry":["FacilityWasher"],"community_table":["FacilityDiningTable"],"residents_table":["FacilityDiningTable"],"workshop":["FacilityStudioTable"],"children_reading":["FacilityChildTable"],"media_reading":["FacilityMediaDesk"],"library_study":["FacilityStudyTable"],"staff_lounge":["LoungeSofa"],"art_lounge":["LoungeSofa"]}

func _has_hangul(value: String) -> bool:
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if code>=0xAC00 and code<=0xD7A3:return true
	return false

func _facility_error(room: Node3D, row: Dictionary, kind: String, evidence: Dictionary = {}) -> void:
	var item := {"id":room.spec.id,"facility":row.get("id",""),"type":row.get("type",""),"level":row.get("level",-1),"kind":kind}
	item.merge(evidence);facility_errors.append(item)

func _solid_record(room: Node3D, body: StaticBody3D) -> Dictionary:
	var shape_node: CollisionShape3D
	for child in body.get_children():
		if child is CollisionShape3D:shape_node = child;break
	var shape: Shape3D = shape_node.shape if shape_node!=null else null
	return {"name":String(body.get_meta("geometry_id","")).trim_prefix("EXP04_interior_"),"engine_name":String(body.name),"facility_id":String(body.get_meta("facility_id","")),"level":int(body.get_meta("detail_level",-1)),"position":room.to_local(body.global_position),"basis":body.basis,"shape":shape.get_class() if shape!=null else "missing","size":shape.size if shape is BoxShape3D else Vector3.ZERO,"collision_layer":body.collision_layer,"disabled":shape_node.disabled if shape_node!=null else true}

func _belongs(row: Dictionary, point: Vector3, facility_id: String) -> bool:
	if not facility_id.is_empty():return facility_id==String(row.id)
	return (row.bounds as AABB).grow(.025).has_point(point)

func _glyph_bounds(label: Label3D) -> AABB:
	var bounds := label.get_aabb()
	if bounds.size.length_squared()>.000001:return bounds
	var mesh := label.generate_triangle_mesh()
	if mesh==null:return bounds
	var faces := mesh.get_faces()
	if faces.is_empty():return bounds
	bounds = AABB(faces[0],Vector3.ZERO)
	for point in faces:bounds = bounds.expand(point)
	return bounds

func _facility_signs(room: Node3D, row: Dictionary, labels: Array) -> Array:
	var result := []
	for label: Label3D in labels:
		if int(label.get_meta("detail_level",-1))!=int(row.level):continue
		var belongs: bool = String(label.get_meta("facility_id",""))==String(row.id)
		# Semantic metadata survives Godot's automatic equal-sibling renaming.
		if not belongs:belongs = String(label.name).begins_with(String(row.sign_prefix)) and String(row.title) in label.text
		if not belongs:continue
		var bounds := _glyph_bounds(label)
		var at: Vector3 = room.to_local(label.global_position)
		result.append({"name":String(label.name),"text":label.text,"position":at,"font_size":label.font_size,"pixel_size":label.pixel_size,"glyph_bounds":bounds,"color":label.modulate,"depth_test":not label.no_depth_test,"visible":label.visible})
	return result

func _facility_point(room: Node3D, row: Dictionary, point: Vector3, kind: String) -> void:
	facility_capsules += 1
	# Call the parent directly: this is a real physics query, without recursion.
	var world := room.to_global(point)
	var hits := super._capsule_failures(room,world)
	if not hits.is_empty():_facility_error(room,row,"blocked_"+kind,{"point":point,"hits":hits})
	facility_support_rays += 1
	var support := root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(world+Vector3.UP*.50,world-Vector3.UP*.50,1))
	if support.is_empty() or absf(support.position.y-world.y+.08)>.035:
		_facility_error(room,row,"unsupported_"+kind,{"point":point,"support":support.get("position",Vector3.INF)})

func _walk_route(row: Dictionary) -> Array:
	var route: Array = row.walk_points.duplicate()
	if row.has("shower_point") and route.size()>=3:
		# Enter the shower through its open front, then return to the existing
		# aisle before continuing into the shallow bath. Never cross the glass.
		var shower: Vector3 = row.shower_point
		var approach := shower+Vector3(0,0,1.15)
		route.insert(3,approach);route.insert(4,shower)
		route.insert(5,approach);route.insert(6,route[2])
	return route

func _inspect_facilities(room: Node3D) -> void:
	var identity: Dictionary = room.interior_snapshot()
	var facilities: Array = identity.get("facilities",[])
	var profile := String(identity.get("profile_id",""))
	var bodies := [];var labels := []
	for child in _descendants(room):
		if child is StaticBody3D and child.has_meta("detail_level"):bodies.append(_solid_record(room,child))
		elif child is Label3D:labels.append(child)
	facility_profiles[profile] = int(facility_profiles.get(profile,0))+facilities.size()
	for row: Dictionary in facilities:
		var valid: bool = row.has_all(["id","type","programme","level","title","entry_point","walk_points","coordinate_space","bounds","geometry_prefix","sign_prefix"])
		valid = valid and row.get("coordinate_space")=="room_local" and int(row.get("level",-1))>=0 and int(row.get("level",-1))<room.floor_count and row.get("entry_point") is Vector3 and row.get("bounds") is AABB
		if not valid:_facility_error(room,row,"invalid_facility_schema");continue
		var type := String(row.type)
		facility_counts[type] = int(facility_counts.get(type,0))+1
		var actual := []
		for body: Dictionary in bodies:
			if int(body.level)==int(row.level) and String(body.name).begins_with("Detail_") and _belongs(row,body.position,body.facility_id):actual.append(body)
		facility_geometry_count += actual.size()
		if actual.is_empty():_facility_error(room,row,"no_actual_solid_geometry",{"prefix":row.geometry_prefix})
		var signatures := [];var equipment_found := []
		for body: Dictionary in actual:
			if body.shape=="missing" or int(body.collision_layer)!=1 or bool(body.disabled):_facility_error(room,row,"invalid_actual_shape",body)
			if not String(body.name).begins_with("Detail_FacilityZone"):
				signatures.append("%s|%s"%[body.shape,str(body.size)])
			for family in EQUIPMENT.get(type,[]):
				if String(body.name)=="Detail_"+String(family) and not equipment_found.has(family):equipment_found.append(family)
		signatures.sort()
		if not EQUIPMENT.has(type) or equipment_found.size()!=EQUIPMENT.get(type,[]).size():_facility_error(room,row,"missing_distinctive_actual_equipment",{"expected":EQUIPMENT.get(type,[]),"found":equipment_found})
		var actual_signs := _facility_signs(room,row,labels)
		facility_sign_count += actual_signs.size()
		if actual_signs.is_empty():_facility_error(room,row,"missing_actual_facility_sign")
		var main_signs := 0
		for sign_row: Dictionary in actual_signs:
			var glyph: AABB = sign_row.glyph_bounds
			if String(row.title) in String(sign_row.text):main_signs += 1
			var text_valid: bool = _has_hangul(sign_row.text)
			var dimensions_valid: bool = glyph.size.x>.1 and glyph.size.y>.08 and glyph.size.x<=8.0 and glyph.size.y<=2.2
			var visible_height: float = float(sign_row.position.y)-float(row.level)*room.floor_height
			if not text_valid or not dimensions_valid or int(sign_row.font_size)<18 or float(sign_row.pixel_size)<.004 or not bool(sign_row.depth_test) or visible_height<.45 or visible_height>room.floor_height-.1:
				_facility_error(room,row,"sign_readability_geometry",sign_row)
		if main_signs==0:_facility_error(room,row,"missing_facility_title_in_actual_sign")
		if String(identity.level_profiles[int(row.level)].profile_id)!=String(row.programme):_facility_error(room,row,"programme_disagrees_with_floor")
		var path: Array = [row.entry_point];path.append_array(_walk_route(row))
		if path.size()<2:_facility_error(room,row,"no_facility_walk_route")
		for index in range(path.size()):
			if not path[index] is Vector3 or not path[index].is_finite():_facility_error(room,row,"invalid_walk_point");continue
			_facility_point(room,row,path[index],"entry" if index==0 else "walk_point")
			if index==0:continue
			var steps := maxi(1,int(ceil(path[index-1].distance_to(path[index])/.45)))
			for step in range(1,steps):_facility_point(room,row,path[index-1].lerp(path[index],float(step)/float(steps)),"walk_segment")
		if row.has("shower_point"):_facility_point(room,row,row.shower_point,"shower_entrance")
		if row.has("bath_point"):_facility_point(room,row,row.bath_point,"bath_entrance")
		var sample_key := profile+"/"+type
		if not facility_samples.has(sample_key):
			facility_samples[sample_key] = {"source_id":room.spec.id,"source_title":room.spec.title,"profile":profile,"manifest":row,"actual_solids":actual,"actual_signs":actual_signs,"physical_signature":signatures}
		if String(room.spec.id) in [LIBRARY_ID,CITYHALL_ID,OFFICE_ID,HOTEL_ID,GALLERY_ID]:
			if not facility_rooms.has(room.spec.id):facility_rooms[room.spec.id] = []
			facility_rooms[room.spec.id].append(row.duplicate(true))

func _capsule_failures(room: Node3D, point: Vector3) -> Array:
	var key := room.get_instance_id()
	if not facility_rooms.has(key):
		facility_rooms[key] = true
		_inspect_facilities(room)
	return super._capsule_failures(room,point)

func _facility_catalog_result() -> void:
	_check("facilities.all_catalog_facility_shapes_signs_and_routes_observed",facility_errors.is_empty() and facility_geometry_count>0 and facility_sign_count>0,{"facility_counts":facility_counts,"by_profile":facility_profiles,"actual_solid_count":facility_geometry_count,"actual_sign_count":facility_sign_count,"capsule_queries":facility_capsules,"support_rays":facility_support_rays,"error_count":facility_errors.size(),"error_rows_reference":"facilities.errors"})
	var native := DisplayServer.get_name()!="headless"
	var expected_profiles := ["library","civic","office","hotel","gallery"] if native else ["library","civic","office","hotel","gallery","bank","chapel","residential"]
	var missing := []
	for profile in expected_profiles:
		if int(facility_profiles.get(profile,0))==0:missing.append(profile)
	_check("facilities.actual_facilities_cover_source_profiles",missing.is_empty(),{"expected":expected_profiles,"observed":facility_profiles,"missing":missing})
	var hotel_levels := {};var hotel_shapes := {};var other_shapes := {}
	for sample: Dictionary in facility_samples.values():
		var signature: String = str(sample.physical_signature)
		if sample.profile=="hotel":hotel_levels[int(sample.manifest.level)] = true;hotel_shapes[signature] = true
		elif sample.profile in ["library","civic","office","gallery"]:
			if not other_shapes.has(sample.profile):other_shapes[sample.profile] = {}
			other_shapes[sample.profile][signature] = true
	_check("facilities.hotel_has_three_distinct_real_facility_floors",hotel_levels.size()>=3 and hotel_shapes.size()>=3,{"levels":hotel_levels.keys(),"actual_shape_variants":hotel_shapes.size()})
	var unique_other := {}
	for profile in other_shapes:
		for signature in other_shapes[profile]:unique_other[signature] = true
	_check("facilities.four_other_profiles_have_distinct_actual_fitouts",other_shapes.size()==4 and unique_other.size()>=4,{"profiles":other_shapes.keys(),"distinct_actual_shape_signatures":unique_other.size()})

func _material_observation(material: Material) -> Dictionary:
	if material is StandardMaterial3D:return {"class":material.get_class(),"color":str(material.albedo_color),"roughness":material.roughness,"metallic":material.metallic,"transparency":material.transparency}
	if material is ShaderMaterial:return {"class":material.get_class(),"color":str(material.get_shader_parameter("base_color")),"shader":material.shader.resource_path}
	return {"class":material.get_class() if material!=null else "missing"}

func _verify_gpu_geometry(room: Node3D, identity: Dictionary) -> void:
	await super._verify_gpu_geometry(room,identity)
	if DisplayServer.get_name()=="headless":return
	var actual := {}
	for child in _descendants(room):
		if not child is MultiMeshInstance3D:continue
		for index in range(child.multimesh.instance_count):
			var transform: Transform3D = child.transform*child.multimesh.get_instance_transform(index)
			var key := _transform_key(transform)
			actual[key] = {"transform":transform,"mesh":child.multimesh.mesh.get_class(),"material":_material_observation(child.material_override),"bounds":transform*child.multimesh.mesh.get_aabb(),"color":child.material_override.albedo_color if child.material_override is StandardMaterial3D else Color.TRANSPARENT}
	var per_type := {};var missing := [];var sign_errors := [];var sign_boards := 0
	for facility: Dictionary in identity.get("facilities",[]):
		if not per_type.has(facility.type):per_type[facility.type] = {"count":0,"meshes":{},"materials":{}}
		for row: Dictionary in identity.get("placements",[]):
			if int(row.level)!=int(facility.level) or not _belongs(facility,row.position,String(row.get("facility_id",""))):continue
			var expected := Transform3D(row.get("basis",Basis.IDENTITY)*Basis.from_scale(row.size),row.position)
			var key := _transform_key(expected)
			if not actual.has(key):missing.append({"facility":facility.id,"title":row.title});continue
			var observed: Dictionary = actual[key]
			var delta := _transform_delta(expected,observed.transform)
			if delta.position_m>.0002 or delta.scaled_axis_component_m>.00002 or not _placement_mesh_matches(String(row.get("mesh_kind","box")),observed.mesh):missing.append({"facility":facility.id,"title":row.title,"expected":expected,"actual":observed.transform,"delta":delta});continue
			per_type[facility.type].count += 1
			per_type[facility.type].meshes[observed.mesh] = true
			per_type[facility.type].materials[str(observed.material)] = true
		for row: Dictionary in identity.get("placements",[]):
			if String(row.title)!="Detail_FacilitySignBoard" or String(row.get("facility_id",""))!=String(facility.id):continue
			var key := _transform_key(Transform3D(row.get("basis",Basis.IDENTITY)*Basis.from_scale(row.size),row.position))
			if not actual.has(key):continue
			var board: AABB = actual[key].bounds
			for label in _descendants(room):
				if not label is Label3D or String(label.get_meta("facility_id",""))!=String(facility.id) or not String(facility.title) in label.text:continue
				var glyph: AABB = label.transform*_glyph_bounds(label)
				var ink: Color = actual[key].color
				var contrast: float = (maxf(label.modulate.get_luminance(),ink.get_luminance())+.05)/(minf(label.modulate.get_luminance(),ink.get_luminance())+.05)
				var fits: bool = glyph.position.x>=board.position.x+.015 and glyph.end.x<=board.end.x-.015 and glyph.position.y>=board.position.y+.005 and glyph.end.y<=board.end.y-.005
				sign_boards += 1
				if not fits or contrast<3.0:sign_errors.append({"facility":facility.id,"glyph_bounds":glyph,"actual_board_bounds":board,"contrast_ratio":contrast})
	var valid := not per_type.is_empty() and missing.is_empty()
	for row: Dictionary in per_type.values():
		if int(row.count)<3 or row.materials.size()<2:valid = false
	valid = valid and sign_boards>0 and sign_errors.is_empty()
	var evidence := {"source_id":room.spec.id,"types":per_type,"missing":missing,"actual_sign_boards":sign_boards,"glyph_fit_or_contrast_errors":sign_errors}
	facility_gpu.append(evidence)
	_check("gpu.facility_actual_meshes_and_materials."+String(room.spec.id),valid,{"source_id":room.spec.id,"types":per_type.keys(),"missing_count":missing.size(),"observation_reference":"gpu_facility_observations"})

func _facility_for_type(type: String) -> Dictionary:
	for row: Dictionary in visit.room.interior_snapshot().get("facilities",[]):
		if String(row.type)==type:return row
	return {}

func _ride_to_facility(level: int, title: String) -> bool:
	var current: int = int(visit.snapshot().current_floor)
	if current==level:return true
	if not await _pose("facility_lift_call_"+title,visit.room.elevator_point(current)):return false
	_e(true);_e(false);await _ticks(4)
	var picker: bool = visit.elevator_open
	var accepted: bool = picker and visit.request_floor(level)
	_check("lift.facility_destination_accepted."+title,accepted,{"physical_E_picker":picker,"from":current,"target":level})
	if not accepted:return false
	for index in range(2400):
		await _ticks(1)
		if not visit.in_elevator:break
	await _ticks(3)
	var arrived: bool = not visit.in_elevator and visit.selected_floor==level and scene.player.is_on_floor() and scene.rig.camera.current and scene.player.is_physics_processing()
	_check("lift.facility_arrival_safe_camera_restored."+title,arrived,{"state":visit.snapshot(),"player":scene.player.global_position})
	return arrived

func _walk_facility(row: Dictionary) -> void:
	if not await _pose("facility_"+String(row.id)+"_entry",visit.room.to_global(row.entry_point)):return
	var before_recoveries: int = scene.player.recoveries
	var samples := 0;var failed_target := -1;var minimum_clearance := INF
	var route := _walk_route(row)
	for index in range(route.size()):
		var target: Vector3 = visit.room.to_global(route[index])
		var reached := false
		for step in range(720):
			var offset: Vector3 = target-scene.player.global_position
			var horizontal := Vector3(offset.x,0.,offset.z)
			minimum_clearance = minf(minimum_clearance,horizontal.length())
			if horizontal.length()<.16 and absf(offset.y)<.25:reached = true;break
			_world_keys(horizontal.normalized());await scene.player.physics_stepped;samples += 1
			if scene.player.recoveries!=before_recoveries:break
		if not reached:failed_target = index;break
	_keys();await _ticks(6)
	var evidence := {"source_id":visit.current_spec.get("id",""),"facility":row.id,"type":row.type,"level":row.level,"waypoints":route.size(),"local_route":route,"samples":samples,"failed_target":failed_target,"end":scene.player.global_position,"grounded":scene.player.is_on_floor(),"recoveries_before":before_recoveries,"recoveries_after":scene.player.recoveries,"method":"production Input actions, no per-step position writes"}
	facility_walks.append(evidence)
	_check("walk.facility_actual_controller."+String(row.id),samples>5 and failed_target<0 and scene.player.is_on_floor() and scene.player.recoveries==before_recoveries,evidence)

func _capture_facility(row: Dictionary) -> void:
	var body: StaticBody3D
	for candidate: StaticBody3D in visit.room.bodies:
		var title := String(candidate.get_meta("geometry_id","")).trim_prefix("EXP04_interior_")
		if int(candidate.get_meta("detail_level",-1))==int(row.level) and title=="Detail_"+String(EQUIPMENT.get(String(row.type),[""])[0]) and _belongs(row,visit.room.to_local(candidate.global_position),String(candidate.get_meta("facility_id",""))):
			body = candidate;break
	if body==null:_check("capture.facility_actual_target."+String(row.id),false);return
	var at: Vector3 = row.entry_point
	at.y = 0.
	var target: Vector3 = body.global_position+Vector3.UP*.55
	await _capture("facility_"+String(visit.room.interior_snapshot().profile_id)+"_"+String(row.type)+"_"+str(row.level),int(row.level),0.,at,4.,target)

func _capture_hotel_detail(row: Dictionary) -> void:
	if String(visit.room.interior_snapshot().profile_id)!="hotel" or String(row.type) not in ["buffet","spa"]:return
	var family := "FacilityBuffetCounter" if row.type=="buffet" else "FacilityShowerPartition"
	var body := _detail_body(family,int(row.level))
	_check("capture_detail."+String(row.type)+".actual_equipment_target",is_instance_valid(body),{"family":family,"level":row.level})
	if not is_instance_valid(body):return
	if row.type=="buffet":
		var stance: Vector3 = visit.room.to_local(body.global_position)
		stance.x -= 1.35;stance.z += 1.0;stance.y = 0.
		await _capture("facility_hotel_buffet_trays_close",int(row.level),0.,stance,2.,body.global_position+Vector3.UP*.56)
	else:
		var stance: Vector3 = visit.room.to_local(scene.player.global_position)
		stance.y = 0.
		await _capture("facility_hotel_spa_shower_bath_close",int(row.level),0.,stance,2.,body.global_position+Vector3.UP*.05,true)

func _facility_functional() -> void:
	scene = load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_settings_path = report_path+".settings.json";scene.quality_settings_path = report_path+".quality.json"
	root.add_child(scene)
	if not scene.runtime_ok:_check("startup.production_exploration",false);return
	visit = scene.interior_visit;await _ticks(25)
	original_inventory = _inventory()
	_check("startup.production_exploration_and_source_catalog",visit.loaded and visit.catalog.size()==125)
	for id in [HOTEL_ID,LIBRARY_ID,CITYHALL_ID,OFFICE_ID,GALLERY_ID]:
		if not await _enter(id,"facility_building_"+str(id).replace(":","_")):continue
		var choices: Array = visit.room.interior_snapshot().get("facilities",[])
		var selected := []
		for row: Dictionary in choices:
			if id==HOTEL_ID:
				var duplicate_type := false
				for previous: Dictionary in selected:
					if previous.type==row.type:duplicate_type = true
				if not duplicate_type:selected.append(row)
			elif selected.is_empty():selected.append(row)
		for row: Dictionary in selected:
			if not await _ride_to_facility(int(row.level),String(visit.room.interior_snapshot().profile_id)+"_"+str(row.level)):continue
			await _walk_facility(row)
			await _capture_hotel_detail(row)
			await _capture_facility(row)
		await _leave("facility_"+String(visit.room.interior_snapshot().profile_id))
	_check("exterior.original_692_collision_bodies_and_shapes_unchanged",original_inventory.size()==692 and _inventory()==original_inventory,{"original_body_count":original_inventory.size()})

func _run() -> void:
	for path in [ROOM_SCRIPT,"res://scripts/interior_detail_kit.gd","res://scripts/interior_facility_kit.gd","res://scripts/interior_surface.gdshader","res://scripts/interior_visit.gd","res://scripts/building_visit_catalog.gd","res://assets/authored/interiors/source_catalog.json","res://scripts/player/free_roam_player.gd","res://../tests/game/check_interior_identity.gd","res://../tests/game/check_interior_facilities.gd"]:
		if FileAccess.file_exists(path):source_hashes[path] = FileAccess.get_sha256(path)
	await _catalog_physics();_identity_differences();_facility_catalog_result()
	await _facility_functional();_finish()

func _finish() -> void:
	if finished:return
	finished = true;_keys();_e(false);paused = false
	var failed := 0
	for check in checks:
		if not check.passed:failed += 1
	var report := {"task":"interior_facilities","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"checks":checks,"summary":{"checks":checks.size(),"failed":failed},"catalog_physics":catalog_summary,"facilities":{"counts":facility_counts,"profiles":facility_profiles,"capsule_queries":facility_capsules,"support_rays":facility_support_rays,"actual_solids":facility_geometry_count,"actual_signs":facility_sign_count,"errors":facility_errors,"samples":facility_samples},"representative_observations":observations,"gpu_facility_observations":facility_gpu,"scenario_starts":placements,"walks":facility_walks,"captures":captures,"deferred_checks":deferred_checks,"scope":"Original 125 source floor plates, 1,205 floors and four people per room are preserved and observed through inherited physics checks. New facility bodies, engine shapes, Korean Label3D glyph bounds and complete declared entry/walk segments are independently observed. Representative portals use physical E and facility walking uses production Input actions after explicit scenario starts. Native rendering is required for actual MultiMesh/material readback and screenshots; hash-linked headless evidence covers the full catalog. These are authored game facilities, not surveyed hotel/building layouts, access permissions, usable food/showers/baths/gym equipment, or a long-running performance test."}
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(report),"\t")+"\n");file.close()
	else:failed += 1;push_error("Could not save interior facilities report")
	print("INTERIOR_FACILITIES_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)
