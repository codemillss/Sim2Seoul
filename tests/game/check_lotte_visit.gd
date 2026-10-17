extends "res://../tests/game/check_rooftop_swimming.gd"
## Only Lotte is supplemental; the 125-building source catalog stays intact.
const LOTTE_ID := "osm:way:117914845:building"
const RETAIL_ID := "osm:way:233592424:building"
var source_validation: Dictionary={}

func _extent_contract() -> void:
	var overlay: Node3D=scene.exploration_overlay
	var polygon: PackedVector2Array=scene.player.free_roam_polygon
	var errors: Array=[]
	var centre:=Vector2.ZERO
	for point: Vector2 in polygon:centre+=point
	centre/=float(polygon.size())
	for index in range(polygon.size()):
		var a: Vector2=polygon[index];var b: Vector2=polygon[(index+1)%polygon.size()]
		var middle: Vector2=(a+b)*.5
		var inward: Vector2=(centre-middle).normalized()
		var near: Vector2=middle+inward*.20
		var safe: Vector2=middle+inward*.65
		var outside: Vector2=middle-inward*.65
		if scene.player.exterior_contains(Vector3(near.x,.08,near.y)) or not scene.player.exterior_contains(Vector3(safe.x,.08,safe.y)) or scene.player.exterior_contains(Vector3(outside.x,.08,outside.y)):errors.append({"edge":index,"near":near,"safe":safe,"outside":outside})
	_check("extent.actual_projected_four_corner_polygon_and_capsule_edge_margin",polygon.size()==4 and polygon==overlay.polygon and errors.is_empty() and overlay.extent.coordinate_contract_sha256==FileAccess.get_sha256("res://../config/region.json"),{"polygon":Array(polygon),"bounds":overlay.bounds,"edge_errors":errors,"scope":overlay.extent.scope})
	var old_errors: Array=[]
	for x: float in [-449.6,0.,449.6]:
		for z: float in [-459.6,0.,459.6]:
			var point:=Vector2(x,z)
			if not Geometry2D.is_point_in_polygon(point,polygon):old_errors.append(point)
	_check("extent.previous_rectangle_play_space_remains_inside_new_polygon",old_errors.is_empty(),{"invalid_old_points":old_errors})
	# Layer32 support stays available to independent NPCs/scenery in both
	# modes; only the player's mask bit controls its use in historical W03.
	var before_mask: int=scene.player.collision_mask
	var origin:=Vector3(440.,.08,430.)
	overlay.set_enabled(false)
	var npc_hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin+Vector3.UP,origin-Vector3.UP,32))
	var player_hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin+Vector3.UP,origin-Vector3.UP,scene.player.collision_mask,[scene.player.get_rid()]))
	_check("support.OFF_keeps_actual_NPC_floor_and_excludes_it_from_player_queries",overlay.support.collision_layer==32 and npc_hit.get("collider")==overlay.support and player_hit.get("collider")!=overlay.support and (scene.player.collision_mask&32)==0 and (scene.player.collision_mask&~32)==(before_mask&~32),{"npc_support":str(npc_hit.get("collider")),"player_support":str(player_hit.get("collider")),"mask_before":before_mask,"mask_after":scene.player.collision_mask,"support_layer":overlay.support.collision_layer})
	overlay.set_enabled(true)
	_check("support.ON_restores_player_floor_bit_without_changing_other_bits",scene.player.collision_mask==before_mask and overlay.support.collision_layer==32)

func _ride_to(index: int,title: String) -> bool:
	_movement();_e(false);await _ticks(4)
	var current: int=visit._current_destination()
	if not await _pose(title+"_explicit_supported_landing_fixture",visit.landing_point(current)):return false
	_e(true);_e(false);await _ticks(5)
	_check(title+".fresh_E_opens_real_floor_picker",visit.elevator_open and visit.selected_floor==current,{"from_floor":current,"destinations":visit.destination_count()})
	if not visit.elevator_open:return false
	visit.elevator_floors.get_child(index).pressed.emit()
	var started: bool=visit.in_elevator and visit.selected_floor==index
	_check(title+".actual_destination_button_starts_cabin",started,{"elevator":visit.elevator_snapshot()})
	if not started:return false
	var cabin_observed: bool=visit.cabin.visible and visit.cabin.camera.current and scene.get_viewport().get_camera_3d()==visit.cabin.camera
	var finished_ride: bool=await _wait_elevator_end(2400)
	_movement();_e(false);await _ticks(12)
	_check(title+".real_cabin_finishes_on_selected_supported_floor",cabin_observed and finished_ride and not visit.in_elevator and visit.selected_floor==index and scene.player.is_on_floor() and String(visit.elevator_snapshot().phase)=="idle",{"player":scene.player.global_position,"elevator":visit.elevator_snapshot()})
	return finished_ride and not visit.in_elevator and visit.selected_floor==index

func _run() -> void:
	for path: String in ["res://scripts/building_visit_catalog.gd","res://scripts/exploration_overlay.gd","res://scripts/player/free_roam_player.gd","res://scripts/rooftop_space.gd","res://assets/authored/exploration_extent.json","res://assets/authored/interiors/source_catalog.json","res://assets/authored/interiors/supplemental_catalog.json","res://resources/world_geometry/world.json","res://../tools/prepare_lotte_visit.py","res://../tests/game/check_lotte_visit.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json";root.add_child(scene)
	if not scene.runtime_ok:_check("startup",false);_finish();return
	visit=scene.interior_visit;await _ticks(25);original_inventory=_inventory()
	scene.set_free_roam(true);scene.set_speed_profile("brisk");_movement();_e(false);await _ticks(4)
	var base: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/interiors/source_catalog.json"))
	var aux: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/interiors/supplemental_catalog.json"))
	source_validation=aux.validation
	var lots: int=0;var retail: int=0;var floors: int=0;var lotte: Dictionary={}
	for spec: Dictionary in visit.catalog:
		floors+=int(spec.floor_count)
		if spec.id==LOTTE_ID:lots+=1;lotte=spec
		if spec.id==RETAIL_ID:retail+=1
	_check("catalog.base_125_unchanged_plus_exactly_one_Lotte_126_and_1242_floors",base.records.size()==125 and FileAccess.get_sha256("res://assets/authored/interiors/source_catalog.json")==aux.base_catalog_sha256 and aux.records.size()==1 and visit.catalog.size()==126 and floors==1242 and lots==1 and retail==0,{"base_records":base.records.size(),"supplemental_records":aux.records.size(),"merged_records":visit.catalog.size(),"merged_floors":floors,"lotte_records":lots,"retail_records":retail})
	if lotte.is_empty():_finish();return
	_check("source.generator_exact_footprint_floor_private_and_door_validations_pass",source_validation.result=="PASS" and float(source_validation.hotel_source_bbox_outside_m2)==0. and float(source_validation.hotel_capsule_inset_bbox_outside_m2)==0. and float(source_validation.source_private_overlap_m2)==0. and float(source_validation.floor_outside_actual_source_m2)==0. and int(source_validation.source_door_candidates)>0,source_validation)
	_extent_contract()
	var vertex_errors: Array=[];var floor_errors: Array=[]
	for part: Array in lotte.source_rings:
		for ring: Array in part:
			for coordinate: Array in ring:
				var point:=Vector3(float(coordinate[0]),.08,float(coordinate[1]))
				if not scene.player.exterior_contains(point):vertex_errors.append(point)
	for u: float in [-.5,-.25,0.,.25,.5]:
		for v: float in [-.5,-.25,0.,.25,.5]:
			var world: Vector3=Vector3(lotte.rectangle_center.x,0.,lotte.rectangle_center.y)+lotte.rectangle_along*float(lotte.width)*u+lotte.rectangle_outward*float(lotte.depth)*v
			if not _source_contains(Vector2(world.x,world.z),lotte):floor_errors.append(world)
	_check("source.full_Lotte_footprint_fits_real_source_polygon_and_floor_stays_inscribed",vertex_errors.is_empty() and floor_errors.is_empty() and float(lotte.rectangle_outside_source_m2)==0. and float(lotte.width)>=12. and float(lotte.depth)>=16.,{"footprint_errors":vertex_errors,"floor_errors":floor_errors,"width":lotte.width,"depth":lotte.depth,"source_rings":lotte.source_rings})
	_check("source.height_levels_and_reference_are_actual_retained_source",float(lotte.source_height)==150. and int(lotte.source_levels)==37 and int(lotte.floor_count)==37 and absf(float(lotte.floor_height)*37.-150.)<.00001 and lotte.floors_basis=="osm_building_levels" and "w/117914845" in lotte.source_reference_ids and lotte.catalog_origin=="supplemental_lotte_source_bbox",{"source_height":lotte.source_height,"source_levels":lotte.source_levels,"floor_height":lotte.floor_height,"reference_ids":lotte.source_reference_ids,"basis":lotte.floors_basis})
	if not await _enter(LOTTE_ID,"lotte_source_door"):_finish();return
	_check("interior.actual_source_door_E_enters_37_floor_hotel_profile",visit.active and scene.player.interior_active and visit.room.floor_count==37 and visit.room.detail_kit.profile_id=="hotel" and String(visit.current_spec.id)==LOTTE_ID,{"room_profile":visit.room.detail_kit.profile_id,"visit":visit.snapshot()})
	if not await _ride_to(1,"lotte_second_floor"):_finish();return
	_check("interior.second_floor_has_hotel_buffet_programme",String(visit.room.detail_kit.level_profiles[1].profile_id)=="hotel_buffet",{"programme":visit.room.detail_kit.level_profiles[1]})
	if not await _ride_to(37,"lotte_roof"):_finish();return
	roof=visit.rooftop
	_check("roof.actual_37_floor_ride_reaches_same_source_roof_with_outdoor_pool",visit.on_roof and roof.profile_id=="outdoor_pool" and String(roof.spec.id)==LOTTE_ID and roof.source_height_y==150. and scene.player.is_on_floor() and scene.player.water_snapshot().registered,{"roof":roof.snapshot(),"player":scene.player.global_position,"water":scene.player.water_snapshot()})
	var helper: Node3D=scene.get_node("ExplorationRooftopAccess")
	var hotels: Array=[];var errors: Array=[]
	for spec: Dictionary in visit.catalog:
		var title: String=String(spec.title)
		if not title.contains("호텔") and not title.to_lower().contains("hotel"):continue
		var hotel_roof: Node3D=helper.ensure_rooftop(String(spec.id))
		if not is_instance_valid(hotel_roof):errors.append(spec.id);continue
		var water: Dictionary=hotel_roof.pool_water_region();var rect: Rect2=water.get("rect",Rect2())
		if hotel_roof.profile_id!="outdoor_pool" or rect.size.x<6. or rect.size.y<6. or maxf(rect.size.x,rect.size.y)<12.:errors.append(spec.id)
		hotels.append({"id":spec.id,"title":spec.title,"pool_rect":rect})
	_check("roof.Lotte_is_eighth_real_source_hotel_pool",hotels.size()==8 and errors.is_empty(),{"hotels":hotels,"errors":errors})
	if not await _ride_to(0,"lotte_return_to_lobby"):_finish();return
	await _leave("lotte_source_door")
	_check("source.original_city_collision_and_base_catalog_are_preserved",_inventory()==original_inventory and FileAccess.get_sha256("res://assets/authored/interiors/source_catalog.json")==aux.base_catalog_sha256 and FileAccess.get_sha256("res://resources/world_geometry/world.json")==aux.world_sha256,{"source_bodies":original_inventory.size()})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var failed: int=0
	for check: Dictionary in checks:
		if not check.passed:failed+=1
	var result: Dictionary={"task":"LOTTE_SOURCE_BBOX_SUPPLEMENTAL_VISIT","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"placements":placements,"generator_source_validation":source_validation,"scope":"The EXP04 125-building base remains byte-identical. A checksum-linked one-building supplemental catalog adds the retained Lotte Hotel source, 150m/37 source levels, source-inscribed game floor and clear source-perimeter candidate doors. Projected region-bbox polygon/capsule margins, independent NPC support versus player OFF mask, actual fresh E entry and floor-picker cabin trips to 2F/roof/1F are observed. Pool is an authored amenity, not a factual venue. Explicit supported landing placements are test fixtures; not continuous navigation, human usability or performance acceptance."}
	var file: FileAccess=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(result),"\t")+"\n");file.close()
	else:failed+=1;push_error("Cannot save Lotte source visit report")
	print("LOTTE_VISIT_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)
