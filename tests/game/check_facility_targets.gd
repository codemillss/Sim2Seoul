extends SceneTree
## EXP11: every source-sized facility use/approach point is checked against
## actual engine collision, support and instantiated equipment parent geometry.
var report_path := ""
var checks: Array = []
var errors: Array = []
var counts := {}
var profiles := {}
var source_hashes := {}
var target_count := 0
var point_queries := 0
var buildings := 0
var floors := 0
var equipment_queries := 0
var all_ids := {}
var repeat_specs: Array = []
var shape := CapsuleShape3D.new()
var finished := false

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	if report_path.is_empty() or not report_path.is_absolute_path():
		push_error("check_facility_targets requires --report=<absolute path>");quit(1);return
	shape.radius=.30;shape.height=1.70
	create_timer(240.,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Dictionary:
		var result := {}
		for key in value:result[str(key)]=_json(value[key])
		return result
	if value is Array:
		var result := []
		for item in value:result.append(_json(item))
		return result
	return value

func _check(title: String,passed: bool,evidence: Dictionary = {}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":evidence})
	if not passed:push_warning("FACILITY_TARGET_CHECK_FAIL "+title)

func _error(row: Dictionary,kind: String,evidence: Dictionary = {}) -> void:
	var item := {"id":String(row.get("id","")),"kind":kind}
	item.merge(evidence);errors.append(item)

func _inspect_point(room: Node3D,row: Dictionary,p: Vector3,label: String) -> void:
	var world: Vector3=room.to_global(p)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,world+Vector3.UP*.85);query.collision_mask=1;query.margin=0.
	var hits: Array=root.get_world_3d().direct_space_state.intersect_shape(query,16)
	var names := []
	for hit in hits:names.append(str(hit.collider.name))
	if not hits.is_empty():_error(row,"blocked_"+label,{"point":p,"hits":names})
	var support := root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(world+Vector3.UP*.25,world-Vector3.UP*.30,1))
	if support.is_empty() or absf((world.y-float(support.position.y))-.08)>.025:
		_error(row,"unsupported_"+label,{"point":p,"support":support.get("position",Vector3.INF)})
	point_queries+=1

func _inspect_equipment(room: Node3D,row: Dictionary) -> void:
	var title := String(row.get("data",{}).get("equipment_title",""))
	var expected: Vector3=row.anchor_point
	match String(row.kind):
		"eat":expected-=Vector3.UP*.12
		"treadmill":expected-=Vector3.UP*.08
		"weights":expected-=Vector3(0,.46,.60)
	var anchor_placement_found := false
	for placement: Dictionary in room.detail_kit.placements:
		if String(placement.title)!=title or int(placement.level)!=int(row.level) or String(placement.get("facility_id",""))!=String(row.facility_id):continue
		if (placement.position as Vector3).distance_to(expected)>.0002:continue
		anchor_placement_found=true;break
	if not anchor_placement_found:_error(row,"missing_equipment_anchor_placement",{"title":title,"expected_position":expected})
	# Headless RenderingServer returns identity for MultiMesh instance reads.
	# Inspect real accepted counter/deck/rack/enclosure bodies here; the native
	# activity test independently reads rendered food, head and effect meshes.
	var parent_title := title
	var parent_point := expected
	var parent_size := Vector3.ZERO
	match String(row.kind):
		"eat":
			parent_title="Detail_FacilityBuffetCounter"
			parent_point=Vector3(expected.x,int(row.level)*room.floor_height+.44,expected.z-1.75+int(row.data.get("food_index",-100))*1.16)
			parent_size=Vector3(1.0,.88,4.9)
		"shower":
			parent_title="Detail_FacilityShowerBack";parent_point=row.anchor_point+Vector3(0,-1.01,-.34);parent_size=Vector3(1.25,2.10,.055)
		"treadmill":parent_size=Vector3(1.0,.10,1.95)
		"weights":parent_size=Vector3(.45,.78,1.8)
	var parent_found := false
	for body: StaticBody3D in room.bodies:
		if String(body.get_meta("geometry_id","")).trim_prefix("EXP04_interior_")!=parent_title or int(body.get_meta("detail_level",-1))!=int(row.level) or String(body.get_meta("facility_id",""))!=String(row.facility_id):continue
		if room.to_local(body.global_position).distance_to(parent_point)>.0002:continue
		for child in body.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D and child.shape.size.distance_to(parent_size)<.00002 and not child.disabled and body.collision_layer==1:
				parent_found=true;break
		if parent_found:break
	equipment_queries+=1
	if not parent_found:_error(row,"missing_actual_equipment_parent",{"title":parent_title,"expected_position":parent_point,"expected_size":parent_size})

func _inspect_targets(room: Node3D) -> void:
	var list: Array=room.detail_kit.facility_kit.interactions
	var facility_links := {}
	for facility: Dictionary in room.detail_kit.facility_kit.facilities:facility_links[String(facility.id)]=int(facility.level)
	for row: Dictionary in list:
		target_count+=1
		var valid: bool=row.has_all(["id","kind","title","level","facility_id","coordinate_space","use_point","approach_point","anchor_point","data"])
		if not valid:_error(row,"schema");continue
		if row.coordinate_space!="room_local" or String(row.title).is_empty() or int(row.level)<0 or int(row.level)>=room.floor_count:_error(row,"level_title_or_coordinate_space")
		if all_ids.has(row.id):_error(row,"duplicate_global_id")
		all_ids[row.id]=true
		if not String(row.id).begins_with(String(room.spec.id)+"/"+String(row.facility_id)+"/"):_error(row,"unstable_source_facility_id_structure")
		if int(facility_links.get(String(row.facility_id),-1))!=int(row.level):_error(row,"missing_parent_facility_link")
		if String(row.kind) not in ["eat","shower","treadmill","weights"]:_error(row,"unsupported_kind");continue
		counts[row.kind]=int(counts.get(row.kind,0))+1
		var key: String=room.detail_kit.profile_id+"/"+String(row.kind)
		profiles[key]=int(profiles.get(key,0))+1
		var points_valid := true
		for field in ["use_point","approach_point","anchor_point"]:
			if not row[field] is Vector3 or not row[field].is_finite():_error(row,"invalid_"+field);points_valid=false
		if not points_valid:continue
		for field in ["use_point","approach_point"]:_inspect_point(room,row,row[field],field)
		var start: Vector3=row.approach_point;var finish: Vector3=row.use_point
		for n in range(1,8):
			# The treadmill's 10cm mounting step is checked by the activity
			# controller's raised-capsule sweep; both endpoints are checked here.
			if row.kind=="treadmill":continue
			_inspect_point(room,row,start.lerp(finish,float(n)/8.0),"segment")
		_inspect_equipment(room,row)
	if room.detail_kit.profile_id in ["hotel","office"]:
		var profile: String=room.detail_kit.profile_id
		var seen := false
		for item: Dictionary in repeat_specs:
			if String(item.profile)==profile:seen=true
		if not seen:repeat_specs.append({"profile":profile,"spec":room.spec.duplicate(true),"targets":list.duplicate(true)})

func _source_spec(record: Dictionary) -> Dictionary:
	return {"id":record.id,"title":record.title,"kind":record.kind,"width":float(record.floor.width),"depth":float(record.floor.depth),"floor_height":float(record.floor_height),"floor_count":int(record.floor_count)}

func _run() -> void:
	for path in ["res://scripts/interior_facility_kit.gd","res://scripts/interior_detail_kit.gd","res://scripts/building_interior_space.gd","res://assets/authored/interiors/source_catalog.json","res://../tests/game/check_facility_targets.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/interiors/source_catalog.json"))
	for record: Dictionary in data.records:
		var room: Node3D=load("res://scripts/building_interior_space.gd").new();root.add_child(room)
		if not room.setup(_source_spec(record),Vector3(650,-100,0)):_error(record,"setup_failed");room.free();continue
		await physics_frame;await physics_frame
		buildings+=1;floors+=room.floor_count
		if not is_equal_approx(room.width,float(record.floor.width)) or not is_equal_approx(room.depth,float(record.floor.depth)) or room.floor_count!=int(record.floor_count) or not is_equal_approx(room.floor_height,float(record.floor_height)):_error(record,"source_dimensions_changed")
		_inspect_targets(room)
		room.free();await physics_frame
	var stable := true
	for item: Dictionary in repeat_specs:
		var room: Node3D=load("res://scripts/building_interior_space.gd").new();root.add_child(room)
		stable=room.setup(item.spec,Vector3(650,-100,0)) and stable
		if room.detail_kit.facility_kit.interactions!=item.targets:stable=false
		room.free();await physics_frame
	_check("catalog.original_125_buildings_1205_floors_retained",buildings==125 and floors==1205 and errors.filter(func(e):return e.kind in ["setup_failed","source_dimensions_changed"]).is_empty(),{"buildings":buildings,"floors":floors})
	_check("targets.schema_finite_coordinates_and_floor_facility_links",errors.filter(func(e):return e.kind in ["schema","level_title_or_coordinate_space","missing_parent_facility_link","unsupported_kind"] or String(e.kind).begins_with("invalid_")).is_empty())
	_check("targets.globally_unique_source_floor_equipment_ids",all_ids.size()==target_count and errors.filter(func(e):return e.kind in ["duplicate_global_id","unstable_source_facility_id_structure"]).is_empty(),{"unique_ids":all_ids.size(),"targets":target_count})
	_check("targets.rebuilt_hotel_and_office_metadata_is_exactly_stable",stable and repeat_specs.size()==2,{"profiles":repeat_specs.map(func(item):return item.profile)})
	_check("targets.all_registered_anchors_have_actual_equipment_parents",equipment_queries==target_count and errors.filter(func(e):return e.kind in ["missing_actual_equipment_parent","missing_equipment_anchor_placement"]).is_empty(),{"actual_parent_queries":equipment_queries})
	_check("targets.capsule_clear_use_approach_and_non_treadmill_segments",point_queries==7479 and errors.filter(func(e):return String(e.kind).begins_with("blocked_")).is_empty(),{"capsule_queries":point_queries,"radius_m":shape.radius,"height_m":shape.height})
	_check("targets.every_sample_has_actual_floor_or_treadmill_support",point_queries==7479 and errors.filter(func(e):return String(e.kind).begins_with("unsupported_")).is_empty(),{"support_rays":point_queries})
	_check("targets.fixed_catalog_equipment_counts_cover_four_action_kinds",target_count==1083 and counts=={"eat":580,"shower":28,"treadmill":324,"weights":151},{"targets":target_count,"counts":counts})
	_check("targets.hotel_office_civic_residential_use_their_actual_facilities",profiles.has_all(["hotel/eat","hotel/shower","hotel/treadmill","hotel/weights","office/eat","office/treadmill","office/weights","civic/eat","residential/treadmill","residential/weights"]),{"profiles":profiles})
	_check("targets.no_unclassified_catalog_errors",errors.is_empty(),{"error_count":errors.size()})
	_finish()

func _timeout() -> void:
	_check("runtime.completed_before_timeout",false);_finish()

func _finish() -> void:
	if finished:return
	finished=true
	var failed := 0
	for check in checks:
		if not check.passed:failed+=1
	var report := {"task":"facility_targets","result":"PASS" if failed==0 else "FAIL","engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"buildings":buildings,"floors":floors,"targets":target_count,"counts":counts,"profiles":profiles,"point_queries":point_queries,"equipment_parent_queries":equipment_queries,"errors":errors,"deferred_checks":[{"name":"native.decorative_food_tray_and_shower_head_mesh_readback","reason":"Headless RenderingServer returns identity for MultiMesh readback. This report checks registered decorative anchor placements plus actual solid counter/deck/rack/enclosure parents; native activity tests cover rendered equipment and effects."}],"scope":"All 125 source-sized room layouts, with actual 0.30m-radius 1.70m-height capsule queries and floor support at use/approach plus 7 points per non-treadmill segment. Real accepted StaticBody/BoxShape counter, treadmill, weight-rack and shower-enclosure geometry is matched by facility, floor, position, size and active collision. Decorative food/head anchor placements are checked separately. Hotel and office rebuilds verify deterministic metadata. Actual E activities, raised treadmill mount/dismount, animation and GPU imagery require separate production-controller tests."}
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(report),"\t")+"\n");file.close()
	else:failed+=1;push_error("Could not save facility target audit")
	print("FACILITY_TARGETS_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed," targets=",target_count," point_queries=",point_queries)
	quit(0 if failed==0 else 1)
