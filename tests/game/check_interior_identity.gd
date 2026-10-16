extends SceneTree
## Structural physics runs for every source floor; GPU observations are separate.
## Scenario starts are explicit test-only teleports. Entry uses the real E binding.
const LIBRARY_ID := "osm:relation:10757525:building"
const CITYHALL_ID := "osm:way:198561926:building"
const OFFICE_ID := "osm:way:332565592:building"
const HOTEL_ID := "osm:way:233593619:building"
const GALLERY_ID := "osm:way:1217684974:building"
const ACTIONS := ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]
const ROOM_SCRIPT := "res://scripts/building_interior_space.gd"
var report_path := ""
var catalog_evidence_path := ""
var scene
var visit
var checks: Array = []
var observations: Array = []
var captures: Array = []
var placements: Array = []
var walks: Array = []
var source_hashes := {}
var deferred_checks: Array = []
var catalog_summary := {}
var original_inventory := {}
var finished := false
var standing_shape := CapsuleShape3D.new()
var representative_observations := {}
var special_observations := {}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path = argument.trim_prefix("--report=")
		if argument.begins_with("--catalog-evidence="):catalog_evidence_path = argument.trim_prefix("--catalog-evidence=")
	if report_path.is_empty() or not report_path.is_absolute_path():
		push_error("check_interior_identity requires --report=<absolute path>");quit(1);return
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	if InputMap.has_action("interact"):InputMap.erase_action("interact")
	standing_shape.radius = .30;standing_shape.height = 1.70
	Engine.physics_ticks_per_second = 60
	create_timer(360.,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2 or value is Vector2i:return [value.x,value.y]
	if value is AABB:return {"position":_json(value.position),"size":_json(value.size)}
	if value is Transform3D:return {"origin":_json(value.origin),"basis":[_json(value.basis.x),_json(value.basis.y),_json(value.basis.z)]}
	if value is Dictionary:
		var result := {}
		for key in value:result[str(key)] = _json(value[key])
		return result
	if value is Array:
		var result := []
		for item in value:result.append(_json(item))
		return result
	return value

func _check(title: String, passed: bool, evidence: Dictionary = {}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":_json(evidence)})
	if not passed:push_warning("INTERIOR_IDENTITY_FAIL "+title)

func _ticks(count: int) -> void:
	for index in range(count):await physics_frame
	await process_frame

func _keys(actions: Array = []) -> void:
	for action in ACTIONS:Input.action_release(action)
	for action in actions:Input.action_press(action)

func _e(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E;event.keycode = KEY_E;event.pressed = pressed
	Input.parse_input_event(event)

func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child);result.append_array(_descendants(child))
	return result

func _inventory() -> Dictionary:
	var result := {}
	for collection in [scene.city.bodies,scene.city.fragments]:
		for id in collection:
			var body: StaticBody3D = collection[id]
			var node: CollisionShape3D = body.get_node("CollisionShape")
			var shape: Shape3D = node.shape
			result[id] = {"node":body.get_instance_id(),"layer":body.collision_layer,"mask":body.collision_mask,"transform":str(body.transform),"shape":shape.get_instance_id(),"shape_transform":str(node.transform),"disabled":node.disabled,"faces":hash(shape.get_faces()) if shape is ConcavePolygonShape3D else 0}
	return result

func _source_spec(record: Dictionary) -> Dictionary:
	return {"id":record.id,"title":record.title,"kind":record.kind,"width":float(record.floor.width),"depth":float(record.floor.depth),"floor_height":float(record.floor_height),"floor_count":int(record.floor_count),"height_basis":record.height_basis,"floors_basis":record.floors_basis}

func _level(room: Node3D, local_y: float) -> int:
	return clampi(int(floor((local_y+.025)/room.floor_height)),0,room.floor_count-1)

func _physical_observation(room: Node3D) -> Dictionary:
	var level_solids := {};var labels := [];var batches := [];var solid_count := 0;var detail_count := 0
	for level in range(room.floor_count):level_solids[str(level)] = []
	for child in _descendants(room):
		if child is StaticBody3D:
			solid_count += 1
			# Godot auto-renames equal sibling names; the per-body geometry ID
			# retains its semantic family while shapes/poses come from the engine.
			var geometry_title := String(child.get_meta("geometry_id","")).trim_prefix("EXP04_interior_")
			if geometry_title.begins_with("Detail_"):
				detail_count += 1
				var collision: CollisionShape3D
				for part in child.get_children():
					if part is CollisionShape3D:collision = part;break
				var row := {"name":geometry_title,"engine_node_name":String(child.name),"position":room.to_local(child.global_position),"shape":collision.shape.get_class() if collision!=null else "missing","shape_size":collision.shape.size if collision!=null and collision.shape is BoxShape3D else Vector3.ZERO}
				level_solids[str(_level(room,room.to_local(child.global_position).y))].append(row)
		elif child is Label3D:
			labels.append({"name":String(child.name),"is_detail_label":child.has_meta("detail_level"),"text":child.text,"position":room.to_local(child.global_position),"level":_level(room,room.to_local(child.global_position).y),"font_size":child.font_size,"pixel_size":child.pixel_size,"depth_test":not child.no_depth_test})
		elif child is MultiMeshInstance3D:
			batches.append({"name":String(child.name),"instances":child.multimesh.instance_count,"material":str(child.material_override.albedo_color) if child.material_override is StandardMaterial3D else "other"})
	return {"source_id":room.spec.id,"title":room.spec.title,"width":room.width,"depth":room.depth,"floor_height":room.floor_height,"floor_count":room.floor_count,"solid_count":solid_count,"detail_solid_count":detail_count,"level_solids":level_solids,"labels":labels,"batches":batches,"people_count":room.people.size()}

func _feature_count(observation: Dictionary, prefix: String, level := -1) -> int:
	var count := 0
	for key in observation.level_solids:
		if level>=0 and int(key)!=level:continue
		for row in observation.level_solids[key]:
			if String(row.name).begins_with("Detail_"+prefix):count += 1
	return count

func _label_count(observation: Dictionary, prefix: String, level := -1) -> int:
	var count := 0
	for row: Dictionary in observation.labels:
		if String(row.name).begins_with("Detail_"+prefix) and (level<0 or int(row.level)==level):count += 1
	return count

func _programme_level(room: Node3D, programme: String) -> int:
	for row: Dictionary in room.interior_snapshot().level_profiles:
		if String(row.profile_id)==programme:return int(row.level)
	return -1

func _capsule_failures(room: Node3D, point: Vector3) -> Array:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = standing_shape;query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*.85)
	query.collision_mask = 1;query.margin = 0.
	var result := []
	for hit in root.get_world_3d().direct_space_state.intersect_shape(query,16):
		result.append({"body":String(hit.collider.name),"instance":hit.collider_id})
	return result

func _catalog_physics() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/interiors/source_catalog.json"))
	var errors := [];var buildings := 0;var floors := 0;var capsule_queries := 0;var floor_queries := 0;var total_detail_solids := 0;var profiles := {};var people_bad := [];var representative_ids := [LIBRARY_ID,CITYHALL_ID,OFFICE_ID,HOTEL_ID,GALLERY_ID]
	var native := DisplayServer.get_name()!="headless"
	for record: Dictionary in data.records:
		if native and record.id not in representative_ids:continue
		var room: Node3D = load(ROOM_SCRIPT).new();root.add_child(room)
		if not room.setup(_source_spec(record),Vector3(650,-100,0)):
			errors.append({"id":record.id,"kind":"setup_failed"});room.free();continue
		await _ticks(2)
		buildings += 1;floors += room.floor_count
		if not is_equal_approx(room.width,float(record.floor.width)) or not is_equal_approx(room.depth,float(record.floor.depth)) or room.floor_count!=int(record.floor_count) or not is_equal_approx(room.floor_height,float(record.floor_height)):
			errors.append({"id":record.id,"kind":"source_dimensions_changed"})
		if room.people.size()!=4:people_bad.append(record.id)
		if not room.has_method("interior_snapshot"):
			errors.append({"id":record.id,"kind":"missing_identity_API"});room.free();continue
		var identity: Dictionary = room.interior_snapshot()
		profiles[str(identity.get("profile_id",""))] = int(profiles.get(str(identity.get("profile_id","")),0))+1
		if String(identity.get("profile_id","")).is_empty() or identity.get("level_profiles",[]).size()!=room.floor_count:
			errors.append({"id":record.id,"kind":"invalid_identity_schema"})
		for body: StaticBody3D in room.bodies:
			if body.has_meta("detail_level"):total_detail_solids += 1
		for level in range(room.floor_count):
			var y: float = float(level)*room.floor_height+.08
			var targets := [{"kind":"spawn","point":room.floor_spawn(level)},{"kind":"elevator","point":room.elevator_point(level)}]
			for x in [-.55,.55]:
				for index in range(9):targets.append({"kind":"central_corridor","point":room.to_global(Vector3(x,y,lerpf(-room.depth*.5+1.2,room.depth*.5-1.2,float(index)/8.)))})
			for x in [room.stair_left+room.stair_width*.5,room.stair_left+room.stair_width*1.5+.25]:
				targets.append({"kind":"stair_approach","point":room.to_global(Vector3(x,y,room.stair_front+.9))})
			for x in [-room.width*.5+2.2,-room.width*.25,0.,room.width*.25,room.width*.5-1.2]:
				targets.append({"kind":"front_cross_corridor","point":room.to_global(Vector3(x,y,room.depth*.5-1.65))})
			if level==0:targets.append({"kind":"exit","point":room.exit_point()})
			for target in targets:
				capsule_queries += 1
				var hits := _capsule_failures(room,target.point)
				if not hits.is_empty():errors.append({"id":record.id,"level":level,"kind":target.kind,"point":target.point,"hits":hits})
			for point: Vector3 in [room.floor_spawn(level),room.elevator_point(level)]:
				floor_queries += 1
				var hit := root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP,point-Vector3.UP,1))
				if hit.is_empty() or absf(hit.position.y-point.y+.08)>.02:
					errors.append({"id":record.id,"level":level,"kind":"missing_support_floor","point":point})
		if record.id in representative_ids:
			var observation := _physical_observation(room)
			observation.identity = identity.duplicate(true)
			observation.identity.erase("placements")
			representative_observations[record.id] = observation
			await _verify_gpu_geometry(room,identity)
		if not native and String(identity.profile_id) in ["chapel","residential","bank"] and not special_observations.has(identity.profile_id):
			var observation := _physical_observation(room)
			observation.identity = identity.duplicate(true);observation.identity.erase("placements")
			special_observations[identity.profile_id] = observation
		room.free()
		if buildings%25==0:print("INTERIOR_CATALOG_PROGRESS buildings=",buildings," floors=",floors)
	catalog_summary = {"scope":"five_native_representatives" if native else "all_125_source_buildings","buildings":buildings,"floors":floors,"capsule_queries":capsule_queries,"support_rays":floor_queries,"detail_solid_bodies":total_detail_solids,"profile_counts":profiles,"errors":errors,"people_bad_ids":people_bad}
	_check("catalog.source_dimensions_"+("five_native_representatives" if native else "all_125_buildings"),buildings==(5 if native else 125) and floors==(68 if native else 1205) and errors.filter(func(e):return e.kind=="source_dimensions_changed" or e.kind=="setup_failed").is_empty(),catalog_summary)
	_check("catalog.all_floor_spawns_lifts_stair_approaches_and_corridors_capsule_clear",errors.is_empty(),{"buildings":buildings,"floors":floors,"capsule_queries":capsule_queries,"support_rays":floor_queries,"errors":errors})
	_check("catalog.identity_profiles_and_four_people_for_every_room",profiles.size()>=4 and not profiles.has("") and people_bad.is_empty(),{"profiles":profiles,"people_bad_ids":people_bad})
	if not native:
		var expected := {"bank":3,"chapel":3,"civic":6,"gallery":5,"hotel":9,"library":1,"office":97,"residential":1}
		_check("catalog.eight_profile_mapping_counts_for_fixed_source",profiles==expected,{"observed":profiles,"expected":expected})
	if native:
		var linked: Variant = JSON.parse_string(FileAccess.get_file_as_string(catalog_evidence_path)) if FileAccess.file_exists(catalog_evidence_path) else null
		var linked_ok: bool = linked is Dictionary and linked.get("result")=="PASS" and linked.get("display")=="headless" and linked.get("catalog_physics",{}).get("buildings")==125 and linked.get("catalog_physics",{}).get("floors")==1205
		if linked_ok:
			for path in source_hashes:
				if linked.get("source_sha256",{}).get(path)!=source_hashes[path]:linked_ok = false
		_check("catalog.full_125_headless_evidence_matches_current_sources",linked_ok,{"path":catalog_evidence_path,"expected_buildings":125,"expected_floors":1205})
		deferred_checks.append({"name":"native.full_125_catalog_not_repeated","reason":"Full catalog physics and special-profile solids were performed headlessly; native execution inspects five representative profiles and uses hash-matched linked evidence","headless_report":catalog_evidence_path,"matching_sources_confirmed":linked_ok})

func _transform_key(transform: Transform3D) -> String:
	# Identity multiplication can turn IEEE -0.0 into +0.0 (90-degree Z-axis
	# rotations expose this). Integer buckets normalise that spelling only;
	# the actual position and all scaled axes are compared below as numbers.
	var fields: Array[String] = []
	for value in [transform.origin.x,transform.origin.y,transform.origin.z,transform.basis.x.x,transform.basis.x.y,transform.basis.x.z,transform.basis.y.x,transform.basis.y.y,transform.basis.y.z,transform.basis.z.x,transform.basis.z.y,transform.basis.z.z]:fields.append(str(roundi(value*1000.)))
	return ",".join(fields)

func _transform_delta(expected: Transform3D, actual: Transform3D) -> Dictionary:
	var axes := [expected.basis.x-actual.basis.x,expected.basis.y-actual.basis.y,expected.basis.z-actual.basis.z]
	var maximum := 0.
	for axis: Vector3 in axes:maximum = maxf(maximum,maxf(absf(axis.x),maxf(absf(axis.y),absf(axis.z))))
	return {"position_m":expected.origin.distance_to(actual.origin),"scaled_axis_component_m":maximum}

func _placement_mesh_matches(kind: String, mesh_class: String) -> bool:
	return mesh_class==String({"box":"BoxMesh","cylinder":"CylinderMesh","pot":"CylinderMesh","shade":"CylinderMesh","foliage":"SphereMesh"}.get(kind,"unsupported"))

func _verify_gpu_geometry(room: Node3D, identity: Dictionary) -> void:
	if DisplayServer.get_name()=="headless":
		deferred_checks.append({"name":"gpu.multimesh_transforms."+String(room.spec.id),"reason":"Godot headless dummy renderer cannot read back uploaded MultiMesh transforms"});return
	await process_frame;RenderingServer.force_draw(false,0.)
	var visible := {};var total := 0
	for child in _descendants(room):
		if child is MultiMeshInstance3D:
			for index in range(child.multimesh.instance_count):
				var actual: Transform3D = child.transform*child.multimesh.get_instance_transform(index)
				var key := _transform_key(actual)
				if not visible.has(key):visible[key] = []
				visible[key].append({"transform":actual,"mesh":child.multimesh.mesh.get_class()});total += 1
	var observed := 0;var missing := [];var max_position_error := 0.;var max_axis_error := 0.;var rotated_samples := [];var dumbbell_samples := []
	for row: Dictionary in identity.get("placements",[]):
		var basis: Basis = row.get("basis",Basis.IDENTITY)
		var transform := Transform3D(basis*Basis.from_scale(row.size),row.position)
		var matched := false;var nearest := {}
		for actual: Dictionary in visible.get(_transform_key(transform),[]):
			var delta := _transform_delta(transform,actual.transform)
			nearest = {"actual":actual.transform,"mesh":actual.mesh,"delta":delta}
			if delta.position_m>.0002 or delta.scaled_axis_component_m>.00002 or not _placement_mesh_matches(String(row.get("mesh_kind","box")),actual.mesh):continue
			matched = true;observed += 1
			max_position_error = maxf(max_position_error,delta.position_m);max_axis_error = maxf(max_axis_error,delta.scaled_axis_component_m)
			if not basis.is_equal_approx(Basis.IDENTITY) and rotated_samples.size()<3:rotated_samples.append({"title":row.title,"expected":transform,"actual":actual.transform,"delta":delta})
			if String(row.title)=="Detail_FacilityDumbbellWeight" and dumbbell_samples.size()<2:dumbbell_samples.append({"title":row.title,"expected":transform,"actual":actual.transform,"delta":delta,"expected_size":row.size,"actual_axis_lengths":Vector3(actual.transform.basis.x.length(),actual.transform.basis.y.length(),actual.transform.basis.z.length())})
			break
		if not matched and missing.size()<12:missing.append({"title":row.title,"expected":transform,"position":row.position,"size":row.size,"nearest_same_bucket":nearest})
	_check("gpu.detail_placements_have_actual_multimesh_geometry."+String(room.spec.id),observed>0 and missing.is_empty(),{"uploaded_instances":total,"expected_detail_instances":identity.get("placements",[]).size(),"observed":observed,"comparison":"normalised lookup then actual position + all three scaled orientation axes + primitive mesh class","position_tolerance_m":.0002,"scaled_axis_component_tolerance_m":.00002,"max_position_error_m":max_position_error,"max_scaled_axis_error_m":max_axis_error,"rotated_samples":rotated_samples,"dumbbell_axis_samples":dumbbell_samples,"missing_first_12":missing})

func _identity_differences() -> void:
	for id in [LIBRARY_ID,CITYHALL_ID,OFFICE_ID,HOTEL_ID,GALLERY_ID]:
		_check("identity.representative_exists."+id,representative_observations.has(id))
	if representative_observations.size()!=5:return
	var library: Dictionary = representative_observations[LIBRARY_ID]
	var civic: Dictionary = representative_observations[CITYHALL_ID]
	var office: Dictionary = representative_observations[OFFICE_ID]
	var hotel: Dictionary = representative_observations[HOTEL_ID]
	var gallery: Dictionary = representative_observations[GALLERY_ID]
	_check("identity.library_real_shelves_return_and_reading_furniture",_feature_count(library,"LibraryShelf")>0 and _feature_count(library,"ReturnMachine",0)>0 and _feature_count(library,"ReadingDesk",1)>0,{"library_shelves":_feature_count(library,"LibraryShelf"),"lobby_return_machine":_feature_count(library,"ReturnMachine",0),"upper_reading_desks":_feature_count(library,"ReadingDesk",1)})
	_check("identity.civic_reception_service_and_waiting_geometry",_feature_count(civic,"CivicReception",0)>0 and _feature_count(civic,"CivicServiceCounter")>0 and _feature_count(civic,"QueueSeat",0)>0 and _feature_count(civic,"QueueTicket",0)>0,{"lobby_reception":_feature_count(civic,"CivicReception",0),"service_counters":_feature_count(civic,"CivicServiceCounter"),"lobby_queue_seats":_feature_count(civic,"QueueSeat",0),"lobby_queue_tickets":_feature_count(civic,"QueueTicket",0)})
	_check("identity.office_reception_and_work_floors",_feature_count(office,"OfficeReception",0)>0 and _feature_count(office,"OfficeDesk")>0,{"reception":_feature_count(office,"OfficeReception",0),"office_desks":_feature_count(office,"OfficeDesk")})
	_check("identity.hotel_lounge_and_guest_rooms",_feature_count(hotel,"HotelReception",0)>0 and _feature_count(hotel,"LoungeSofa",0)>0 and _label_count(hotel,"GuestRoomNumber",2)>0 and _feature_count(hotel,"Bed",2)>0,{"reception":_feature_count(hotel,"HotelReception",0),"lounge_sofas":_feature_count(hotel,"LoungeSofa",0),"third_floor_guest_door_labels":_label_count(hotel,"GuestRoomNumber",2),"third_floor_beds":_feature_count(hotel,"Bed",2),"door_visuals":"verified separately through native GPU MultiMesh readback"})
	_check("identity.source_civic_art_center_maps_to_real_gallery_geometry",_feature_count(gallery,"GalleryReception",0)>0 and _feature_count(gallery,"ArtworkPanel",0)>0 and _feature_count(gallery,"GalleryDisplay")>0 and gallery.identity.profile_id=="gallery",{"source_id":gallery.source_id,"profile":gallery.identity.profile_id,"lobby_reception":_feature_count(gallery,"GalleryReception",0),"lobby_art_panels":_feature_count(gallery,"ArtworkPanel",0),"display_cases":_feature_count(gallery,"GalleryDisplay")})
	var profile_ids := {};var floor_variants := {};var hangul_by_profile := {}
	for id in representative_observations:
		var row: Dictionary = representative_observations[id]
		profile_ids[String(row.identity.profile_id)] = true
		var geometry_per_level := []
		for level in range(mini(3,row.floor_count)):
			var features := []
			for solid: Dictionary in row.level_solids[str(level)]:
				# Compare real shape sizes and horizontal placement, excluding level IDs
				# in node names so renamed copies cannot count as floor diversity.
				features.append("%s|%.3f,%.3f|%s"%[solid.shape,solid.position.x,solid.position.z,str(solid.shape_size)])
			features.sort();geometry_per_level.append(features)
		floor_variants[row.identity.profile_id] = geometry_per_level.size()>=2 and geometry_per_level[0]!=geometry_per_level[1]
		var hangul := []
		for label in row.labels:
			if not label.is_detail_label:continue
			for index in range(String(label.text).length()):
				var code: int = String(label.text).unicode_at(index)
				if code>=0xAC00 and code<=0xD7A3:hangul.append(label.text);break
		hangul_by_profile[row.identity.profile_id] = hangul
	_check("identity.five_profiles_have_distinct_physical_furniture_families",profile_ids.size()==5,{"profile_ids":profile_ids.keys()})
	_check("identity.lobby_and_upper_floors_have_different_real_solids",not floor_variants.values().has(false),floor_variants)
	var hangul_ok := true
	for rows in hangul_by_profile.values():
		if rows.size()<5:hangul_ok = false
	_check("identity.korean_wayfinding_and_local_details_present_in_actual_labels",hangul_ok,hangul_by_profile)
	for observation in representative_observations.values():observations.append(observation)
	if DisplayServer.get_name()=="headless":
		for sample in [{"id":"chapel","family":"ChapelPew"},{"id":"residential","family":"ResidentialMailWall"},{"id":"bank","family":"BankServiceCounter"}]:
			var actual: Dictionary = special_observations.get(sample.id,{})
			var count := _feature_count(actual,sample.family,0) if not actual.is_empty() else 0
			_check("identity.special_profile_has_actual_shape."+sample.id,count>0,{"source_id":actual.get("source_id",""),"title":actual.get("title",""),"family":sample.family,"actual_solid_count":count})
			if not actual.is_empty():observations.append(actual)

func _pose(title: String, point: Vector3) -> bool:
	_keys();_e(false)
	placements.append({"name":title,"kind":"explicit_test_only_scenario_start","point":point})
	scene.player.global_transform = Transform3D(Basis.IDENTITY,point)
	scene.player.require_neutral_input();scene.player.reset_physics_interpolation()
	scene.rig.reset_orientation();scene.rig.snap_to_target_pose()
	await _ticks(16)
	var good: bool = scene.player.is_on_floor() and not scene.player.input_latched
	_check("placement."+title+".grounded",good,{"requested":point,"actual":scene.player.global_position})
	return good

func _enter(id: String, title: String) -> bool:
	_keys();_e(false);await _ticks(3)
	var selected: bool = visit.select_building(id)
	_check(title+".source_selected",selected,{"id":id})
	if not selected:return false
	if not await _pose(title+"_outside",visit.entrance_world_position):return false
	var entries: int = visit.entry_count
	_e(true);_e(false);await _ticks(9)
	var entered: bool = visit.active and visit.entry_count==entries+1
	_check(title+".physical_E_enters_detailed_room",entered,visit.snapshot())
	return entered

func _leave(title: String) -> void:
	if not visit.active:return
	if not await _pose(title+"_exit",visit.room.exit_point()):return
	var exits: int = visit.exit_count
	_e(true);_e(false);await _ticks(9)
	_check(title+".physical_E_safe_exit",not visit.active and visit.exit_count==exits+1 and not visit._safe_external_point(scene.player.global_position).is_empty(),visit.snapshot())

func _detail_body(prefix: String, level: int) -> StaticBody3D:
	for body: StaticBody3D in visit.room.bodies:
		var title := String(body.get_meta("geometry_id","")).trim_prefix("EXP04_interior_")
		if title=="Detail_"+prefix and int(body.get_meta("detail_level",-1))==level:return body
	return null

func _capture_feature(title: String, level: int, family: String, close := false) -> void:
	var body := _detail_body(family,level)
	_check("capture_target."+title+".actual_body_exists",is_instance_valid(body),{"family":family,"level":level})
	if not is_instance_valid(body):return
	var local: Vector3 = visit.room.to_local(body.global_position)
	# These are explicit scenario starts. The normal camera solver remains the
	# sole pose owner, using zoom values available in the normal game menu.
	var stand := Vector3(0.,0.,minf(visit.room.depth*.5-3.5,local.z+3.5))
	if close:stand = Vector3(local.x+2.3,0.,local.z+1.8)
	var target: Vector3 = body.global_position+Vector3.UP*.70
	await _capture(title,level,0.,stand,2.0 if close else 4.,target)

func _capture(title: String, level: int, yaw_degrees := -8., local_point := Vector3.INF, zoom := 4., aim_world := Vector3.INF, preserve_walk_endpoint := false) -> void:
	var at: Vector3 = visit.room.floor_spawn(level) if not local_point.is_finite() else visit.room.to_global(local_point+Vector3.UP*(level*visit.room.floor_height+.08))
	if preserve_walk_endpoint:
		_keys();_e(false);await _ticks(2)
		var retained: bool = scene.player.is_on_floor() and scene.player.global_position.distance_to(at)<.2 and not scene.player.input_latched
		_check("capture_pose."+title+".retains_actual_walk_endpoint",retained,{"walk_endpoint":scene.player.global_position,"requested_camera_stance":at,"position_writes":0})
		if not retained:return
	elif not await _pose(title+"_view",at):return
	scene.rig.yaw = deg_to_rad(yaw_degrees);scene.rig.pitch = deg_to_rad(-8.);scene.rig.requested_distance = zoom
	var framed_target := aim_world
	if aim_world.is_finite():
		var pivot: Vector3 = scene.player.global_position+Vector3.UP*scene.rig.pivot_height_m
		var horizontal := Vector3(aim_world.x-pivot.x,0.,aim_world.z-pivot.z)
		# Put the inspected furniture beside the third-person avatar, retaining
		# both in the wide view rather than aiming its centre behind the capsule.
		if not horizontal.is_zero_approx():framed_target -= horizontal.normalized().cross(Vector3.UP)*minf(1.75,horizontal.length()*(.45 if zoom<3.0 else .23))
		var direction: Vector3 = framed_target-pivot
		scene.rig.yaw = atan2(-direction.x,-direction.z)
		scene.rig.pitch = clampf(atan2(direction.y,Vector2(direction.x,direction.z).length()),deg_to_rad(scene.rig.pitch_min_degrees),deg_to_rad(scene.rig.pitch_max_degrees))
	scene.rig.snap_to_target_pose();await _ticks(8)
	var query := PhysicsShapeQueryParameters3D.new();query.shape=scene.rig.arm.shape
	query.transform=Transform3D(Basis.IDENTITY,scene.rig.camera.global_position);query.collision_mask=scene.rig.arm.collision_mask;query.exclude=[scene.player.get_rid()]
	var overlaps: Array = scene.get_world_3d().direct_space_state.intersect_shape(query,1)
	var target_in_view := true;var projected := Vector2.ZERO
	if aim_world.is_finite():
		target_in_view = not scene.rig.camera.is_position_behind(aim_world)
		if target_in_view:
			projected = scene.rig.camera.unproject_position(aim_world)
			target_in_view = Rect2(Vector2(16,115),scene.get_viewport().get_visible_rect().size-Vector2(32,145)).has_point(projected)
	var allowed_zoom: bool = zoom>=scene.rig.distance_min_m and zoom<=scene.rig.distance_max_m
	var evidence := {"name":title,"level":level,"profile":visit.room.interior_snapshot().profile_id,"player":scene.player.global_position,"camera":scene.rig.camera.global_transform,"state":visit.snapshot(),"requested_zoom_m":zoom,"normal_UI_zoom_range":allowed_zoom,"preserved_actual_walk_endpoint":preserve_walk_endpoint,"avatar_visible":scene.player.get_node("Visual").visible,"actual_furniture_target":aim_world if aim_world.is_finite() else null,"framed_look_at_point":framed_target if framed_target.is_finite() else null,"target_pixel":projected,"target_clear_of_top_UI":target_in_view,"camera_overlap_count":overlaps.size()}
	_check("capture_pose."+title+".camera_clear_and_actual_target_on_screen",overlaps.is_empty() and target_in_view and allowed_zoom,evidence)
	if DisplayServer.get_name()=="headless":
		evidence.captured = false;evidence.reason = "headless_has_no_rendered_viewport";captures.append(evidence);return
	await process_frame;RenderingServer.force_draw(false,0.)
	var picture: Image = scene.get_viewport().get_texture().get_image()
	var path := report_path.trim_suffix(".json")+"_"+title+".png"
	var saved: bool = not picture.is_empty() and picture.save_png(path)==OK
	evidence.captured = saved;evidence.path = path;evidence.width = picture.get_width();evidence.height = picture.get_height()
	captures.append(evidence);_check("capture."+title,saved,evidence)

func _people_motion() -> void:
	var people: Array = visit.room.people
	var before := []
	for person in people:before.append(person.global_position)
	await _ticks(60)
	var moved := 0
	for index in range(people.size()):
		if people[index].global_position.distance_to(before[index])>.15:moved += 1
	_check("people.four_real_walkers_still_animate",people.size()==4 and moved==4,{"count":people.size(),"moved":moved})
	before.clear()
	for person in people:before.append(person.global_position)
	scene.toggle_menu();await _ticks(12)
	var max_motion := 0.
	for index in range(people.size()):max_motion = maxf(max_motion,people[index].global_position.distance_to(before[index]))
	_check("people.pause_still_freezes_walkers",paused and max_motion<.001,{"max_motion_m":max_motion})
	scene.toggle_menu();_keys();_e(false);await _ticks(5)

func _elevator() -> bool:
	if not await _pose("library_lift_call",visit.room.elevator_point(0)):return false
	_e(true);_e(false);await _ticks(4)
	_check("elevator.physical_E_opens_existing_floor_selector",visit.elevator_open and visit.elevator_panel.visible and visit.elevator_floors.get_child_count()==visit.destination_count() and visit.destination_count()==visit.room.floor_count+1)
	var accepted: bool = visit.request_floor(1)
	_check("elevator.first_to_second_floor_request_accepted",accepted and visit.in_elevator)
	if not accepted:return false
	for index in range(1800):
		await _ticks(1)
		if not visit.in_elevator:break
	await _ticks(2)
	var arrived: bool = not visit.in_elevator and visit.selected_floor==1 and scene.player.is_on_floor() and absf(scene.player.global_position.y-visit.room.floor_spawn(1).y)<.2
	_check("elevator.actual_controller_ride_arrives_second_floor",arrived,{"state":visit.snapshot(),"player":scene.player.global_position})
	return arrived

func _world_keys(direction: Vector3) -> void:
	_keys()
	var forward: Vector3 = -scene.rig.camera.global_basis.z
	forward.y = 0.;forward = forward.normalized()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var sideways: float = direction.dot(right);var ahead: float = direction.dot(forward)
	if sideways>.00001:Input.action_press("move_right",sideways)
	elif sideways<-.00001:Input.action_press("move_left",-sideways)
	if ahead>.00001:Input.action_press("move_forward",ahead)
	elif ahead<-.00001:Input.action_press("move_backward",-ahead)

func _stairs() -> void:
	var path: Array = visit.room.stair_path(1,false)
	if path.is_empty():_check("stairs.valid_second_floor_down_path",false);return
	if not await _pose("library_stair_top",path[0]):return
	var before_recoveries: int = scene.player.recoveries
	var samples := 0;var failed_target := -1
	for target_index in range(1,path.size()):
		var target: Vector3 = path[target_index]
		var reached := false
		for index in range(900):
			var offset: Vector3 = target-scene.player.global_position
			var horizontal := Vector3(offset.x,0.,offset.z)
			if horizontal.length()<.18 and absf(offset.y)<.4:reached = true;break
			_world_keys(horizontal.normalized());await scene.player.physics_stepped;samples += 1
			if scene.player.recoveries!=before_recoveries:break
		if not reached:failed_target = target_index;break
	_keys();await _ticks(6)
	var row := {"kind":"real_controller_Input_action_movement_without_per_step_teleports","waypoints":path.size(),"samples":samples,"failed_target":failed_target,"recoveries_before":before_recoveries,"recoveries_after":scene.player.recoveries,"end":scene.player.global_position,"grounded":scene.player.is_on_floor()}
	walks.append(row)
	_check("stairs.detailed_library_real_walk_down_without_recovery",failed_target<0 and samples>10 and scene.player.recoveries==before_recoveries and scene.player.is_on_floor() and absf(scene.player.global_position.y-visit.room.floor_spawn(0).y)<.25,row)

func _functional() -> void:
	scene = load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_settings_path = report_path+".settings.json";scene.quality_settings_path = report_path+".quality.json"
	root.add_child(scene)
	if not scene.runtime_ok:_check("startup.production_exploration",false);return
	visit = scene.interior_visit;await _ticks(25)
	original_inventory = _inventory()
	_check("startup.production_exploration_and_source_catalog",visit.loaded and visit.catalog.size()==125)
	if await _enter(LIBRARY_ID,"library"):
		await _capture("library_lobby",0)
		await _people_motion()
		if await _elevator():
			await _capture("library_reading_floor",1)
			await _capture_feature("library_books_and_reading_lamps_close",1,"ReadingDesk",true)
		await _stairs();await _leave("library")
	for sample in [{"id":CITYHALL_ID,"name":"cityhall","upper":false},{"id":OFFICE_ID,"name":"office","upper":true},{"id":HOTEL_ID,"name":"hotel","upper":false},{"id":GALLERY_ID,"name":"gallery","upper":false}]:
		if visit.active:break
		if await _enter(sample.id,sample.name):
			if sample.name=="cityhall":await _capture_feature("cityhall_citizen_lobby",0,"CivicReception")
			elif sample.name=="office":await _capture_feature("office_lobby",0,"OfficeReception")
			elif sample.name=="hotel":await _capture_feature("hotel_lobby",0,"HotelReception")
			elif sample.name=="gallery":await _capture_feature("gallery_lobby",0,"GalleryReception")
			if sample.upper:
				var work_level := _programme_level(visit.room,"office_work")
				_check("office.has_work_floor_programme",work_level>=1,{"level":work_level})
				if work_level>=1:await _capture_feature(sample.name+"_work_floor",work_level,"OfficeDesk")
			if sample.name=="hotel":await _capture_feature("hotel_guest_floor",2,"Bed")
			await _leave(sample.name)
	_check("exterior.original_692_collision_bodies_and_shapes_unchanged",original_inventory.size()==692 and _inventory()==original_inventory,{"original_body_count":original_inventory.size()})

func _run() -> void:
	for path in [ROOM_SCRIPT,"res://scripts/interior_detail_kit.gd","res://scripts/interior_surface.gdshader","res://scripts/interior_visit.gd","res://scripts/building_visit_catalog.gd","res://assets/authored/interiors/source_catalog.json","res://scripts/player/free_roam_player.gd","res://../tests/game/check_interior_identity.gd"]:
		if FileAccess.file_exists(path):source_hashes[path] = FileAccess.get_sha256(path)
	await _catalog_physics();_identity_differences()
	await _functional();_finish()

func _timeout() -> void:
	if finished:return
	_check("timeout",false);_finish()

func _finish() -> void:
	if finished:return
	finished = true;_keys();_e(false);paused = false
	var failed := 0
	for check in checks:
		if not check.passed:failed += 1
	var report := {"task":"interior_identity","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"checks":checks,"summary":{"checks":checks.size(),"failed":failed},"catalog_physics":catalog_summary,"representative_observations":observations,"scenario_starts":placements,"walks":walks,"captures":captures,"deferred_checks":deferred_checks,"scope":"All source floor dimensions and capsule standing/support queries are engine observations. Representative identity checks inspect actual StaticBody shapes and Label3D contents. GPU MultiMesh readback and saved viewport captures run only with a native renderer; headless dummy results defer them. Scenario starts are explicit test-only teleports; physical E, elevator ride, people animation/pause, and stair descent use production controllers. Authored profiles are game reconstructions, not surveyed interiors, public-access permissions, native-human-input acceptance, a full catalog walk-through, or a performance/export test."}
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(report),"\t")+"\n");file.close()
	else:failed += 1;push_error("Could not save interior identity report")
	print("INTERIOR_IDENTITY_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)
