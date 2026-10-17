extends RefCounted
## EXP21 independent source-XZ/native floor/native tree-instance acceptance.
## Headless physical evidence is reported separately; dummy instance transforms
## never produce a native-rendering PASS.
const TREE_COUNT: int=369
const WORLD_PATH: String="res://resources/world_geometry/world.json"
const DESIGN_PATH: String="res://assets/authored/neighborhood_greenery.json"
var _errors: Array=[]

func _bad(reason: String,evidence: Dictionary={}) -> void:
	if _errors.size()<40:_errors.append({"reason":reason,"evidence":evidence})

func _floor(scene: Node3D,point: Vector3,exclude: Array[RID]) -> Dictionary:
	var y: float=scene.terrain_surface.ground_y_world(point)
	if not is_finite(y):return {}
	var at: Vector3=Vector3(point.x,y,point.z)
	return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*.65,at-Vector3.UP*.45,1|32,exclude))

func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node]=[]
	for child: Node in node.get_children():result.append(child);result.append_array(_descendants(child))
	return result

func _city_tree_batches(scene: Node3D) -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D]=[]
	for node: Node in _descendants(scene.city):
		if not node is MultiMeshInstance3D:continue
		var title: String=String(node.name).to_lower()
		var role: String=String(node.get_meta("kind",node.get_meta("role",""))).to_lower()
		if title.contains("tree") or title.contains("trunk") or title.contains("bark") or role in ["tree","tree_trunk","vegetation_tree"]:result.append(node as MultiMeshInstance3D)
	return result

func inspect(scene: Node3D) -> Dictionary:
	_errors.clear()
	var evidence: Dictionary={"display":DisplayServer.get_name(),"physical_passed":false,"native_status":"NOT_RUN","native_passed":false,"source_sha256":{DESIGN_PATH:FileAccess.get_sha256(DESIGN_PATH),WORLD_PATH:FileAccess.get_sha256(WORLD_PATH)},"scope":"All369 retained additional trees: sourceXZ, native ground and physical trunk frames. Native bark/crown positions are read only on a real rendering backend. Existing city tree-named MultiMeshes, if present, receive a separate current-position ground readback; no botanical/survey/full-viewport claim."}
	if not is_instance_valid(scene) or not is_instance_valid(scene.get("terrain_surface")) or not scene.terrain_surface.loaded or not is_instance_valid(scene.get("neighborhood_greenery")) or not scene.neighborhood_greenery.loaded:
		_bad("missing_loaded_terrain_or_greenery");evidence["errors"]=_errors.duplicate(true);return {"passed":false,"evidence":evidence}
	var module: Node3D=scene.neighborhood_greenery
	var source: Variant=JSON.parse_string(FileAccess.get_file_as_string(DESIGN_PATH))
	if not source is Dictionary:_bad("missing_authored_tree_source");evidence["errors"]=_errors.duplicate(true);return {"passed":false,"evidence":evidence}
	var source_by_id: Dictionary={}
	for record: Dictionary in source.trees:source_by_id[String(record.id)]=record
	var excluded: Array[RID]=[scene.player.get_rid()]
	for row: Dictionary in module.trees:excluded.append(row.body.get_rid())
	var expected_groups: Dictionary={};var physical_rows: Array=[];var active: int=0;var source_count: int=0;var fill_count: int=0
	var minimum_native_ground: float=INF;var maximum_native_ground: float=-INF;var seen: Dictionary={}
	if module.trees.size()!=TREE_COUNT:_bad("retained_tree_count",{"actual":module.trees.size(),"expected":TREE_COUNT})
	for row: Dictionary in module.trees:
		var id: String=String(row.record.id)
		if seen.has(id) or not source_by_id.has(id):_bad("missing_or_duplicate_source_tree",{"id":id});continue
		seen[id]=true
		var record: Dictionary=source_by_id[id]
		var source_point: Vector3=scene.city.to_global(Vector3(record.xz[0],0.,record.xz[1]))
		var floor: Dictionary=_floor(scene,source_point,excluded)
		if floor.is_empty() or floor.normal.y<.72:_bad("tree_has_no_native_ground",{"id":id,"source_point":source_point});continue
		var expected: Vector3=Vector3(source_point.x,floor.position.y+.02,source_point.z)
		var body: StaticBody3D=row.body;var collision: CollisionShape3D=row.shape
		var shape: CylinderShape3D=collision.shape as CylinderShape3D
		var actual: Vector3=body.global_position
		if actual.distance_to(expected)>.003 or (row.point as Vector3).distance_to(expected)>.003:_bad("tree_body_or_cached_point_not_on_sourceXZ_native_floor",{"id":id,"expected":expected,"actual_body":actual,"cached_point":row.point})
		if shape==null or absf(shape.radius-.17)>.00001 or absf(shape.height-3.1)>.00001:_bad("trunk_shape_contract",{"id":id})
		else:
			var bottom: Vector3=collision.global_transform*Vector3(0.,-shape.height*.5,0.)
			if bottom.distance_to(expected)>.003 or collision.global_basis.y.normalized().dot(Vector3.UP)<.99999:_bad("trunk_actual_bottom_frame",{"id":id,"expected":expected,"actual_bottom":bottom})
		if row.active:active+=1
		if body.collision_layer!=(1 if row.active else 0) or collision.disabled==bool(row.active):_bad("trunk_active_collision_state",{"id":id,"active":row.active,"layer":body.collision_layer,"disabled":collision.disabled})
		minimum_native_ground=minf(minimum_native_ground,floor.position.y);maximum_native_ground=maxf(maximum_native_ground,floor.position.y)
		if record.basis=="source_natural_tree_node":source_count+=1
		elif record.basis=="authored_source_footway_edge_fill":fill_count+=1
		else:_bad("unlabelled_tree_provenance",{"id":id})
		var cell: String=str(floori(source_point.x/100.))+"_"+str(floori(source_point.z/100.))
		if not expected_groups.has(cell):expected_groups[cell]=[]
		expected_groups[cell].append({"id":id,"base":expected,"record":record})
		physical_rows.append({"id":id,"source_xz":record.xz,"expected_base":expected,"actual_body":actual,"native_floor":floor.position,"native_normal":floor.normal,"active":row.active})
	if active>128:_bad("trunk_collision_budget",{"actual":active,"limit":128})
	var physical_errors: Array=_errors.duplicate(true)
	evidence["physical_passed"]=physical_errors.is_empty();evidence["physical_errors"]=physical_errors;evidence["physical_rows"]=physical_rows;evidence["tree_count"]=module.trees.size();evidence["source_count"]=source_count;evidence["fill_count"]=fill_count;evidence["active_trunks"]=active;evidence["native_ground_y_range_m"]=[minimum_native_ground,maximum_native_ground]
	var city_batches: Array[MultiMeshInstance3D]=_city_tree_batches(scene)
	evidence["original_city_tree_named_batches"]=city_batches.size()
	if DisplayServer.get_name()=="headless":
		evidence["native_status"]="DEFERRED";evidence["native_deferred_reason"]="Dummy RenderingServer returns identity/unavailable instance transforms; native bark/crown and city-tree instance readback is intentionally not treated as PASS. Physical bodies/sourceXZ/native physics floors were inspected separately."
		evidence["errors"]=_errors.duplicate(true);return {"passed":false,"evidence":evidence}
	var bark_count: int=0;var crown_count: int=0;var grate_count: int=0;var bark_cells: Dictionary={};var crown_cells: Dictionary={};var maximum_native_matrix_error: float=0.0;var minimum_crown_bottom_relative_m: float=INF;var native_batches: Array=[]
	for batch: MultiMeshInstance3D in module.batches:
		var title: String=String(batch.name);var kind: String=title.get_slice("_",title.get_slice_count("_")-1)
		var cell: String=title.trim_prefix("StreetTrees_").trim_suffix("_"+kind)
		if not expected_groups.has(cell):_bad("unexpected_tree_batch_cell",{"batch":title});continue
		var expected: Array=expected_groups[cell];var multi: MultiMesh=batch.multimesh
		if multi==null or multi.transform_format!=MultiMesh.TRANSFORM_3D or multi.mesh==null:_bad("missing_native_tree_multimesh",{"batch":title});continue
		if kind=="grate":grate_count+=multi.instance_count;continue
		if not ["bark","leaf"].has(kind):_bad("unknown_tree_batch_kind",{"batch":title});continue
		var per_tree: int=1 if kind=="bark" else 3
		if multi.instance_count!=expected.size()*per_tree:_bad("native_instance_count",{"batch":title,"actual":multi.instance_count,"expected":expected.size()*per_tree});continue
		if kind=="bark":bark_cells[cell]=true;bark_count+=multi.instance_count
		else:crown_cells[cell]=true;crown_count+=multi.instance_count
		var bounds: AABB=multi.mesh.get_aabb()
		for index: int in range(multi.instance_count):
			var row: Dictionary=expected[index if per_tree==1 else floori(float(index)/3.0)]
			var actual_transform: Transform3D=batch.global_transform*multi.get_instance_transform(index)
			if not actual_transform.basis.is_finite() or not actual_transform.origin.is_finite():_bad("nonfinite_native_tree_matrix",{"batch":title,"index":index});continue
			if kind=="bark":
				var bottom: Vector3=actual_transform*Vector3(0.,bounds.position.y,0.)
				var delta: float=bottom.distance_to(row.base);maximum_native_matrix_error=maxf(maximum_native_matrix_error,delta)
				if delta>.004 or actual_transform.basis.y.normalized().dot(Vector3.UP)<.99999:_bad("native_bark_matrix_not_at_source_tree_ground",{"id":row.id,"batch":title,"index":index,"expected_bottom":row.base,"actual_bottom":bottom})
			else:
				var crown: int=index%3
				var spread: Vector3=Vector3(1.55,1.40,1.50) if crown==0 else Vector3(1.15,1.30,1.1)
				var height: float=float(row.record.height_m)
				var offset: Vector3=Vector3(0.,height-1.40,0.) if crown==0 else Vector3(-.75 if crown==1 else .80,height-2.0,.18 if crown==1 else -.20)
				offset.y=maxf(offset.y,2.65+spread.y)
				var expected_origin: Vector3=row.base+offset;var delta: float=actual_transform.origin.distance_to(expected_origin)
				maximum_native_matrix_error=maxf(maximum_native_matrix_error,delta)
				var actual_bounds: AABB=actual_transform*bounds;var relative_bottom: float=actual_bounds.position.y-row.base.y
				minimum_crown_bottom_relative_m=minf(minimum_crown_bottom_relative_m,relative_bottom)
				if delta>.004 or actual_transform.basis.get_scale().distance_to(spread)>.0001 or relative_bottom<2.64:_bad("native_crown_matrix_or_head_clearance",{"id":row.id,"batch":title,"index":index,"expected_origin":expected_origin,"actual_origin":actual_transform.origin,"bottom_above_tree_base_m":relative_bottom})
		native_batches.append({"node":String(batch.get_path()),"kind":kind,"instances":multi.instance_count,"world_transform":batch.global_transform})
	if bark_count!=TREE_COUNT or crown_count!=TREE_COUNT*3 or grate_count!=TREE_COUNT*4 or bark_cells.size()!=expected_groups.size() or crown_cells.size()!=expected_groups.size():_bad("native_tree_coverage_incomplete",{"bark":bark_count,"crowns":crown_count,"grates":grate_count,"expected_cells":expected_groups.size(),"bark_cells":bark_cells.size(),"crown_cells":crown_cells.size()})
	var original_rows: Array=[]
	for batch: MultiMeshInstance3D in city_batches:
		var multi: MultiMesh=batch.multimesh
		if multi==null or multi.mesh==null:_bad("original_city_tree_missing_mesh",{"node":String(batch.get_path())});continue
		var name: String=String(batch.name).to_lower()
		var crown: bool=name.contains("crown") or name.contains("leaf") or multi.mesh is SphereMesh
		var minimum_gap: float=INF;var maximum_gap: float=-INF
		for index: int in range(multi.instance_count):
			var pose: Transform3D=batch.global_transform*multi.get_instance_transform(index);var bounds: AABB=multi.mesh.get_aabb()
			var bottom: Vector3=pose*Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
			var floor: Dictionary=_floor(scene,bottom,excluded)
			if floor.is_empty():_bad("original_city_tree_no_native_floor",{"node":String(batch.get_path()),"index":index});continue
			var gap: float=bottom.y-floor.position.y;minimum_gap=minf(minimum_gap,gap);maximum_gap=maxf(maximum_gap,gap)
			if (not crown and (gap<-.03 or gap>.20)) or (crown and gap<2.6):_bad("original_city_tree_native_ground_height",{"node":String(batch.get_path()),"index":index,"crown":crown,"gap_m":gap})
		original_rows.append({"node":String(batch.get_path()),"instances":multi.instance_count,"kind":"crown" if crown else "trunk","native_ground_gap_range_m":[minimum_gap,maximum_gap],"scope":"Actual native instance currentXZ and floor readback; independent original sourceXZ list unavailable for this optional legacy batch."})
	evidence["native_status"]="PASS" if _errors.is_empty() else "FAIL";evidence["native_passed"]=_errors.is_empty();evidence["native_bark_instances"]=bark_count;evidence["native_crown_instances"]=crown_count;evidence["native_grate_count_only"]=grate_count;evidence["maximum_native_matrix_error_m"]=maximum_native_matrix_error;evidence["minimum_native_crown_bottom_above_tree_base_m"]=minimum_crown_bottom_relative_m;evidence["native_batches"]=native_batches;evidence["original_city_tree_readback"]=original_rows;evidence["errors"]=_errors.duplicate(true)
	return {"passed":bool(evidence.physical_passed) and bool(evidence.native_passed),"evidence":evidence}
