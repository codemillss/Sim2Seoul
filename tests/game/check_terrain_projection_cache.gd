extends SceneTree
## Same production geometry is fingerprinted on cold and warm independent runs.
## MultiMesh readback and ordinary actors are outside this exact cache test.
var report_path: String=""
var scene: Node3D
var source_hashes: Dictionary={}
var rows: Array[Dictionary]=[]
var errors: Array[Dictionary]=[]
var started_usec: int=0
var finished: bool=false

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	if not report_path.is_absolute_path():push_error("--report=<absolute path> required");quit(1);return
	for action: String in ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	create_timer(1800.0,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _sha(value: Variant) -> String:
	var context: HashingContext=HashingContext.new()
	if context.start(HashingContext.HASH_SHA256)!=OK:return ""
	if context.update(var_to_bytes(value))!=OK:return ""
	return context.finish().hex_encode()

func _points_valid(points: PackedVector3Array,minimum: int) -> bool:
	if points.size()<minimum:return false
	for point: Vector3 in points:
		if not point.is_finite():return false
	return true

func _geometry(node: Node3D) -> Dictionary:
	var payload: Array=[];var valid: bool=node.global_transform.is_finite();var count: int=0;var surfaces: int=0;var kind: String=""
	if node is MeshInstance3D and (node as MeshInstance3D).mesh!=null:
		var mesh: Mesh=(node as MeshInstance3D).mesh;kind=mesh.get_class();surfaces=mesh.get_surface_count();valid=valid and surfaces>0
		for index: int in range(surfaces):
			var arrays: Array=mesh.surface_get_arrays(index)
			if arrays.size()!=Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:valid=false;continue
			var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];valid=valid and _points_valid(points,3);count+=points.size()
			var primitive: int=(mesh as ArrayMesh).surface_get_primitive_type(index) if mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
			payload.append([primitive,arrays])
	elif node is CollisionShape3D and (node as CollisionShape3D).shape!=null:
		var shape: Shape3D=(node as CollisionShape3D).shape;kind=shape.get_class();payload=[shape.margin,shape.custom_solver_bias]
		if shape is ConcavePolygonShape3D:
			var points: PackedVector3Array=(shape as ConcavePolygonShape3D).get_faces();count=points.size();valid=valid and _points_valid(points,3) and count%3==0;payload.append(points);payload.append((shape as ConcavePolygonShape3D).backface_collision)
		elif shape is ConvexPolygonShape3D:
			var points: PackedVector3Array=(shape as ConvexPolygonShape3D).points;count=points.size();valid=valid and _points_valid(points,4);payload.append(points)
		elif shape is BoxShape3D:
			var size: Vector3=(shape as BoxShape3D).size;valid=valid and size.is_finite() and minf(size.x,minf(size.y,size.z))>0.;payload.append(size)
		elif shape is CapsuleShape3D:payload.append([(shape as CapsuleShape3D).radius,(shape as CapsuleShape3D).height])
		elif shape is CylinderShape3D:payload.append([(shape as CylinderShape3D).radius,(shape as CylinderShape3D).height])
		elif shape is SphereShape3D:payload.append((shape as SphereShape3D).radius)
		else:valid=false
	else:valid=false
	return {"valid":valid,"type":kind,"surfaces":surfaces,"points":count,"sha256":_sha([node.get_class(),node.global_transform,kind,payload])}

func _run() -> void:
	started_usec=Time.get_ticks_usec()
	for path: String in ["res://scripts/terrain_surface.gd","res://scripts/terrain_geometry_warp.gd","res://scripts/terrain_scene_binding.gd","res://assets/authored/terrain_heightfield.json","res://data/generated/terrain_surface.json","res://resources/world_geometry/world.json","res://../tests/game/check_terrain_projection_cache.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate()
	var settings: String="/private/tmp/exp21-cache-"+str(OS.get_process_id())+".json"
	scene.exploration_settings_path=settings;scene.quality_settings_path=settings+".quality";root.add_child(scene)
	if not scene.runtime_ok:errors.append({"reason":"production_startup_failed","error":scene.exploration_error});_finish();return
	scene.set_pedestrians_running(false);scene.set_vehicles_running(false)
	for tick: int in range(2):await physics_frame
	var records: Array=scene.terrain_binding.records
	var skipped: int=0;var hits: int=0;var misses: int=0;var writes: int=0;var seen: Dictionary={}
	for record: Dictionary in records:
		if record.get("kind","")=="multimesh":skipped+=1;continue
		var path: String=String(record.get("node",""));var node: Node3D=root.get_node_or_null(NodePath(path)) as Node3D
		if node==null:errors.append({"path":path,"reason":"recorded_node_missing"});continue
		var geometry: Dictionary=_geometry(node);var cache: Dictionary=record.get("cache",{});var key: String=String(cache.get("key",""))
		if not cache.is_empty() and key.length()!=64:errors.append({"path":path,"reason":"cache_dependency_key_invalid"})
		if key.length()==64:
			if bool(cache.get("hit",false)):hits+=1
			else:misses+=1
			if bool(cache.get("written",false)):writes+=1
		if not geometry.valid or geometry.sha256.length()!=64 or not bool(record.get("ok",false)):errors.append({"path":path,"reason":"invalid_projected_geometry","kind":geometry.type})
		if seen.has(path):errors.append({"path":path,"reason":"duplicate_binding_record"})
		seen[path]=true;rows.append({"path":path,"type":geometry.type,"geometry_sha256":geometry.sha256,"points":geometry.points,"surfaces":geometry.surfaces,"cache_key":key,"cache_hit":bool(cache.get("hit",false))})
	rows.sort_custom(func(first: Dictionary,second: Dictionary) -> bool:return String(first.path)<String(second.path))
	if hits+misses==0:errors.append({"reason":"no_cacheable_geometry_observed"})
	var aggregate: Array=[]
	for row: Dictionary in rows:aggregate.append([row.path,row.type,row.geometry_sha256])
	var constants: Dictionary=scene.terrain_binding.warp.get_script().get_script_constant_map()
	_finish({"aggregate_geometry_sha256":_sha(aggregate),"fingerprinted_nodes":rows.size(),"binding_records":records.size(),"multimesh_skipped":skipped,"cacheable_nodes":hits+misses,"cache_hits":hits,"cache_misses":misses,"cache_writes":writes,"cache_schema":constants.get("CACHE_SCHEMA",""),"runtime_mesh_sha256":scene.terrain_surface.runtime_mesh_sha256})

func _finish(observation: Dictionary={}) -> void:
	if finished:return
	finished=true
	for path: String in source_hashes:
		if FileAccess.get_sha256(path)!=source_hashes[path]:errors.append({"path":path,"reason":"source_changed_during_test"})
	if rows.is_empty():errors.append({"reason":"no_geometry_fingerprinted"})
	var report: Dictionary={"task":"EXP21_CACHE_GEOMETRY","result":"PASS" if errors.is_empty() else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"elapsed_wall_s":(Time.get_ticks_usec()-started_usec)/1000000.0,"observations":observation,"geometry":rows,"errors":errors,"source_sha256":source_hashes,"scope":"Separate cold and warm production startups; exact transforms and complete mesh arrays/shape geometry fingerprint. No materials, resources IDs, MultiMesh, ordinary actors, performance or gameplay equivalence claim."}
	var file: FileAccess=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot write cache fingerprint report");quit(1);return
	file.store_string(JSON.stringify(report,"  ")+"\n");file.close();print("EXP21_CACHE_GEOMETRY ",report.result," nodes=",rows.size());quit(0 if errors.is_empty() else 1)

func _timeout() -> void:
	errors.append({"reason":"timeout"});_finish()
