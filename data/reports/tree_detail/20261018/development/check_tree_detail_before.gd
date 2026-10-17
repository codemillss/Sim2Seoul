extends "res://../tests/game/check_street_scene.gd"
## Before/after visual-tree probe. Only explicit player scenario starts move;
## all actors, camera obstruction and short Input walks retain production code.
const TREE_DESIGN := "res://assets/authored/neighborhood_greenery.json"
const TREE_WORLD := "res://resources/world_geometry/world.json"
const EXPECTED_TREES := 369
var phase: String=""
var fixture_path: String=""
var fixture: Dictionary={}
var greenery: Node3D
var terrain: Node3D
var tree_by_id: Dictionary={}
var tree_bases: Dictionary={}
var native_tree_bounds: Dictionary={}
var _tree_rids: Array[RID]=[]
var _began_usec: int=0

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
		elif argument.begins_with("--fixture="):fixture_path=argument.trim_prefix("--fixture=")
		elif argument.begins_with("--phase="):phase=argument.trim_prefix("--phase=")
	if phase not in ["before","after"] or not report_path.is_absolute_path() or not fixture_path.is_absolute_path():
		push_error("check_tree_detail requires --phase=before|after --report=<absolute> --fixture=<absolute>");quit(1);return
	if FileAccess.file_exists(report_path) or (phase=="before" and FileAccess.file_exists(fixture_path)):
		push_error("Refusing to overwrite a tree-detail report or before fixture");quit(1);return
	if phase=="after":
		var saved: Variant=JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
		if not saved is Dictionary or saved.get("schema_version")!=1 or not saved.get("views") is Array:
			push_error("A saved before fixture is required");quit(1);return
		fixture=saved
	for action: String in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	if InputMap.has_action("interact"):InputMap.erase_action("interact")
	Engine.physics_ticks_per_second=30;Engine.max_fps=60
	create_timer(600.,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _check(title: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":_json(evidence)})
	if not passed:push_warning("TREE_DETAIL_FAIL "+title)

func _ticks(count: int) -> void:
	for index: int in range(count):await scene.rig.camera_stepped

func _vec(value: Array) -> Vector3:return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _floor(point: Vector3) -> Dictionary:
	var y: float=terrain.ground_y_world(point)
	if not is_finite(y):return {}
	var excludes: Array[RID]=_tree_rids.duplicate();excludes.append(scene.player.get_rid())
	return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(point.x,y+.65,point.z),Vector3(point.x,y-.45,point.z),1|32,excludes))

func _safe_point(point: Vector3) -> Vector3:
	var floor: Dictionary=_floor(point)
	if floor.is_empty() or floor.normal.y<.8:return Vector3.INF
	var at: Vector3=Vector3(point.x,floor.position.y+.08,point.z)
	if not scene.player.exterior_contains(at):return Vector3.INF
	var node: CollisionShape3D=scene.player.get_node("CollisionShape")
	var query: PhysicsShapeQueryParameters3D=PhysicsShapeQueryParameters3D.new();query.shape=node.shape;query.transform=Transform3D(Basis.IDENTITY,at)*node.transform;query.collision_mask=scene.player.collision_mask;query.exclude=[scene.player.get_rid()]
	if not scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return Vector3.INF
	return at

func _physical_trees() -> void:
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(TREE_DESIGN))
	var originals: Dictionary={}
	for record: Dictionary in source.trees:originals[String(record.id)]=record
	var errors: Array=[];var rows: Array=[];var active: int=0
	for row: Dictionary in greenery.trees:_tree_rids.append(row.body.get_rid())
	for row: Dictionary in greenery.trees:
		var id: String=String(row.record.id)
		if tree_by_id.has(id) or not originals.has(id):errors.append({"id":id,"reason":"source_id"});continue
		tree_by_id[id]=row
		var record: Dictionary=originals[id]
		var source_point: Vector3=scene.city.to_global(Vector3(record.xz[0],0.,record.xz[1]))
		var floor: Dictionary=_floor(source_point)
		if floor.is_empty():errors.append({"id":id,"reason":"native_floor"});continue
		var base: Vector3=Vector3(source_point.x,floor.position.y+.02,source_point.z);tree_bases[id]=base
		var shape: CylinderShape3D=row.shape.shape as CylinderShape3D
		var valid_shape: bool=shape!=null and absf(shape.radius-.17)<.00001 and absf(shape.height-3.1)<.00001
		var bottom: Vector3=row.shape.global_transform*Vector3(0.,-1.55,0.)
		if not valid_shape or (row.point as Vector3).distance_to(base)>.003 or row.body.global_position.distance_to(base)>.003 or bottom.distance_to(base)>.003 or row.shape.global_basis.y.normalized().dot(Vector3.UP)<.99999:errors.append({"id":id,"reason":"source_XZ_native_floor_or_trunk_contract","base":base,"body":row.body.global_position,"bottom":bottom})
		if row.active:active+=1
		if row.body.collision_layer!=(1 if row.active else 0) or row.body.collision_mask!=0 or row.shape.disabled==bool(row.active):errors.append({"id":id,"reason":"active_layer_mask_shape"})
		if record.basis not in ["source_natural_tree_node","authored_source_footway_edge_fill"]:errors.append({"id":id,"reason":"provenance"})
		rows.append({"id":id,"base":base,"source_xz":record.xz,"radius_m":shape.radius if shape!=null else -1.,"height_m":shape.height if shape!=null else -1.,"active":row.active})
	_check("trees.all_369_source_points_native_floors_and_original_trunk_contract",greenery.trees.size()==EXPECTED_TREES and tree_bases.size()==EXPECTED_TREES and active<=128 and errors.is_empty(),{"count":greenery.trees.size(),"active":active,"budget":128,"errors":errors})
	observations["physical_trees"]={"rows":rows,"errors":errors,"active":active}
	if phase=="after":
		var changed: Array=[]
		for id: String in fixture.get("tree_bases",{}):
			if not tree_bases.has(id) or tree_bases[id].distance_to(_vec(fixture.tree_bases[id]))>.003:changed.append(id)
		_check("trees.before_after_all_source_ground_frames_identical",fixture.get("tree_bases",{}).size()==EXPECTED_TREES and changed.is_empty(),{"changed":changed})

func _native_trees() -> void:
	if DisplayServer.get_name()=="headless":
		observations["native_trees"]={"status":"DEFERRED","reason":"Dummy MultiMesh readback does not verify visible tree geometry."};return
	var groups: Dictionary={}
	for row: Dictionary in greenery.trees:
		var base: Vector3=tree_bases.get(String(row.record.id),row.point)
		var cell: String=str(floori(base.x/100.))+"_"+str(floori(base.z/100.))
		if not groups.has(cell):groups[cell]=[]
		groups[cell].append(String(row.record.id))
	var errors: Array=[];var counts: Dictionary={"bark":0,"leaf":0,"detail":0,"grate":0};var seen: Dictionary={};var bases: Dictionary={};var crown_min: Dictionary={};var batch_rows: Array=[];var geometry_vertices: int=0
	for batch: MultiMeshInstance3D in greenery.batches:
		var name: String=String(batch.name);var kind: String=name.get_slice("_",name.get_slice_count("_")-1)
		if not counts.has(kind):errors.append({"node":name,"reason":"unknown_kind"});continue
		var multi: MultiMesh=batch.multimesh
		if multi==null or multi.mesh==null or multi.transform_format!=MultiMesh.TRANSFORM_3D:errors.append({"node":name,"reason":"native_mesh"});continue
		counts[kind]+=multi.instance_count
		for surface_index: int in range(multi.mesh.get_surface_count()):
			var arrays: Array=multi.mesh.surface_get_arrays(surface_index)
			if arrays.size()>Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX]!=null:geometry_vertices+=arrays[Mesh.ARRAY_VERTEX].size()
		var ids: Array=[]
		if phase=="after":ids=Array(batch.get_meta("tree_ids",[]))
		else:
			var cell: String=name.trim_prefix("StreetTrees_").trim_suffix("_"+kind)
			var source_ids: Array=groups.get(cell,[])
			var per_tree: int=3 if kind=="leaf" else (4 if kind=="grate" else 1)
			for index: int in range(multi.instance_count):
				var source_index: int=floori(float(index)/per_tree)
				ids.append(source_ids[source_index] if source_index<source_ids.size() else "")
		if kind=="grate":
			batch_rows.append({"node":name,"kind":kind,"instances":multi.instance_count});continue
		if ids.size()!=multi.instance_count:errors.append({"node":name,"reason":"tree_ids_count","ids":ids.size(),"instances":multi.instance_count});continue
		var mesh_bounds: AABB=multi.mesh.get_aabb()
		for index: int in range(multi.instance_count):
			var id: String=String(ids[index])
			if not tree_bases.has(id):errors.append({"node":name,"index":index,"reason":"unknown_source_tree_id"});continue
			var pose: Transform3D=batch.global_transform*multi.get_instance_transform(index)
			if not pose.origin.is_finite() or not pose.basis.is_finite():errors.append({"id":id,"reason":"nonfinite_native_matrix"});continue
			var base: Vector3=tree_bases[id];var bounds: AABB=pose*mesh_bounds
			if not native_tree_bounds.has(id):native_tree_bounds[id]=bounds
			else:
				var previous_bounds: AABB=native_tree_bounds[id];native_tree_bounds[id]=previous_bounds.merge(bounds)
			var key: String=id+"/"+kind
			seen[key]=int(seen.get(key,0))+1
			if phase=="after":
				if pose.origin.distance_to(base)>.004 or pose.basis.y.normalized().dot(Vector3.UP)<.99999 or pose.basis.determinant()<=0.:errors.append({"id":id,"kind":kind,"reason":"native_instance_source_ground_frame","origin":pose.origin,"base":base})
				if bases.has(id) and not pose.is_equal_approx(bases[id]):errors.append({"id":id,"kind":kind,"reason":"bark_leaf_detail_frames_differ"})
				bases[id]=pose
			if kind=="bark":
				var bottom: Vector3=pose*Vector3(0.,mesh_bounds.position.y,0.)
				if bottom.distance_to(base)>.004:errors.append({"id":id,"reason":"native_bark_bottom","bottom":bottom,"base":base})
			elif kind=="leaf":crown_min[id]=minf(float(crown_min.get(id,INF)),bounds.position.y-base.y)
		batch_rows.append({"node":name,"kind":kind,"instances":multi.instance_count,"mesh_bounds":mesh_bounds,"visibility_range_end_m":batch.visibility_range_end})
	var size_rows: Array=[]
	for id: String in native_tree_bounds:
		var bounds: AABB=native_tree_bounds[id];var base: Vector3=tree_bases[id]
		var height: float=bounds.end.y-base.y;var width: float=maxf(bounds.size.x,bounds.size.z);var crown_bottom: float=float(crown_min.get(id,-INF))
		if crown_bottom<2.65-.01:errors.append({"id":id,"reason":"native_canopy_head_clearance","clearance_m":crown_bottom})
		if phase=="after":
			# Rotating a shared mesh AABB also rotates its empty corners. This
			# deliberately conservative world-AABB width is not crown diameter.
			if height<9.0-.01 or height>12.5+.01 or width<4.5-.01 or width>11.0+.01:errors.append({"id":id,"reason":"native_visual_size","height_m":height,"world_AABB_width_m":width})
			for kind: String in ["bark","leaf","detail"]:
				if int(seen.get(id+"/"+kind,0))!=1:errors.append({"id":id,"kind":kind,"reason":"expected_one_instance_per_tree"})
		size_rows.append({"id":id,"native_world_bounds":bounds,"height_above_ground_m":height,"world_AABB_width_m":width,"canopy_bottom_above_ground_m":crown_bottom})
	var expected_leaves: int=EXPECTED_TREES*(3 if phase=="before" else 1)
	var expected_detail: int=0 if phase=="before" else EXPECTED_TREES
	_check("trees.native_readback_every_source_tree_and_visible_size_clearance",native_tree_bounds.size()==EXPECTED_TREES and counts.bark==EXPECTED_TREES and counts.leaf==expected_leaves and counts.detail==expected_detail and counts.grate==EXPECTED_TREES*4 and errors.is_empty(),{"counts":counts,"errors":errors,"tree_bounds":size_rows,"shared_geometry_vertices_counted":geometry_vertices})
	observations["native_trees"]={"status":"PASS" if errors.is_empty() else "FAIL","counts":counts,"tree_bounds":size_rows,"batches":batch_rows,"errors":errors,"after_height_limits_m":[9.,12.5],"after_conservative_world_AABB_width_limits_m":[4.5,11.],"basis":"Native mesh AABBs and native instance matrices; size/ground/headroom constraints are independent of row.visual_height_m, visual_width_scale and visual_yaw. Rotated mesh AABB width includes empty corners and is not crown diameter."}

func _project_pose(point: Vector3,eye: Vector3,basis: Basis) -> Dictionary:
	var local: Vector3=basis.transposed()*(point-eye)
	var clip: Vector4=scene.rig.camera.get_camera_projection()*Vector4(local.x,local.y,local.z,1.)
	if clip.w<=0.:return {"on_screen":false,"screen":Vector2.INF}
	var size: Vector2=scene.get_viewport().get_visible_rect().size
	var screen: Vector2=Vector2((clip.x/clip.w+1.)*.5*size.x,(1.-clip.y/clip.w)*.5*size.y)
	return {"on_screen":scene.get_viewport().get_visible_rect().has_point(screen),"screen":screen}

func _make_view(id: String,title: String,radius: float,zoom: float,pitch_degrees: float,target_height: float) -> Dictionary:
	var base: Vector3=tree_bases[id]
	for index: int in range(24):
		var angle: float=TAU*float(index)/24.;var offset: Vector3=Vector3(cos(angle),0.,sin(angle))*radius
		var at: Vector3=_safe_point(base+offset)
		if not at.is_finite():continue
		var direction: Vector3=base-at;direction.y=0.
		for yaw_offset_degrees: float in [18.,-18.]:
			# Offset the ordinary orbit so the trunk is not hidden immediately
			# behind the avatar. The resulting eye still receives the full native
			# camera sweep/LOS checks; the production camera is never bypassed.
			var yaw: float=atan2(-direction.x,-direction.z)+deg_to_rad(yaw_offset_degrees)
			var pitch: float=deg_to_rad(clampf(pitch_degrees,scene.rig.pitch_min_degrees,minf(15.,scene.rig.pitch_max_degrees)))
			var basis: Basis=Basis.from_euler(Vector3(pitch,yaw,0.))
			var pivot: Vector3=at+Vector3.UP*scene.rig.pivot_height_m;var eye: Vector3=pivot+basis.z*zoom
			var avatar: Dictionary=_project_pose(at+Vector3.UP*1.7,eye,basis);var trunk: Dictionary=_project_pose(base+Vector3.UP*1.7,eye,basis)
			var target: Dictionary=_project_pose(base+Vector3.UP*target_height,eye,basis)
			var separation: float=absf(avatar.screen.x-trunk.screen.x)
			if not avatar.on_screen or not trunk.on_screen or not target.on_screen or separation<maxf(32.,scene.get_viewport().get_visible_rect().size.x*.045):continue
			# The shared wide fixture must also fit the planned maximum crown,
			# so an old short tree cannot select a view that crops the new tree.
			if title=="daehanmun_tree_row" and not _project_pose(base+Vector3.UP*12.5,eye,basis).on_screen:continue
			var query: PhysicsShapeQueryParameters3D=PhysicsShapeQueryParameters3D.new();query.shape=scene.rig.arm.shape;query.transform=Transform3D(Basis.IDENTITY,pivot);query.motion=eye-pivot;query.collision_mask=scene.rig.arm.collision_mask;query.exclude=[scene.player.get_rid()]
			if not scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty() or scene.get_world_3d().direct_space_state.cast_motion(query)[0]<.99999:continue
			var los: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye,base+Vector3.UP*target_height,1|32,_tree_rids))
			if not los.is_empty():continue
			return {"id":title,"tree_id":id,"player_point":_v(at),"yaw":yaw,"pitch":pitch,"requested_distance":zoom,"target_height_m":target_height,"yaw_offset_degrees":yaw_offset_degrees,"minimum_trunk_avatar_horizontal_separation_px":maxf(32.,scene.get_viewport().get_visible_rect().size.x*.045)}
	return {}

func _segment_clear(a: Vector3,b: Vector3) -> bool:
	var count: int=maxi(1,ceili(Vector2(b.x-a.x,b.z-a.z).length()/.25))
	for index: int in range(count+1):
		if not _safe_point(a.lerp(b,float(index)/count)).is_finite():return false
	return true

func _build_fixture() -> bool:
	var ids: Array=tree_bases.keys();ids.sort_custom(func(a: String,b: String)->bool:return Vector2(tree_bases[a].x,tree_bases[a].z).length_squared()<Vector2(tree_bases[b].x,tree_bases[b].z).length_squared())
	var views: Array=[];var selected_id: String=""
	for raw_id: Variant in ids.slice(0,30):
		var id: String=String(raw_id);var wide: Dictionary=_make_view(id,"daehanmun_tree_row",14.,4.5,8.,5.)
		var close: Dictionary=_make_view(id,"near_trunk_and_branches",2.2,4.5,0.,1.7)
		var canopy: Dictionary=_make_view(id,"under_canopy",6.,3.5,15.,5.)
		if wide.is_empty() or close.is_empty() or canopy.is_empty():continue
		views=[wide,close,canopy];selected_id=id;break
	if selected_id.is_empty():return false
	var entry: Dictionary={};var best: float=INF
	for spec: Dictionary in visit.catalog:
		var candidate: Vector3=spec.entrance+spec.outward*2.2
		var at: Vector3=_safe_point(candidate)
		if not at.is_finite() or not _segment_clear(at,spec.entrance):continue
		for raw_id: Variant in ids:
			var id: String=String(raw_id);var gap: float=Vector2(tree_bases[id].x-spec.entrance.x,tree_bases[id].z-spec.entrance.z).length()
			var score: float=gap+Vector2(spec.entrance.x,spec.entrance.z).length()*.03
			if gap>15. or gap<1.85 or score>=best:continue
			var view: Dictionary=_make_view(id,"entrance_side_tree",8.,4.5,8.,4.)
			if view.is_empty():continue
			best=score;entry={"building_id":spec.id,"tree_id":id,"start":_v(at),"entrance":_v(spec.entrance),"outward":_v(spec.outward),"view":view}
	if not entry.is_empty():views.append(entry.view)
	var contact: Dictionary={}
	for raw_id: Variant in ids.slice(0,30):
		var id: String=String(raw_id);var base: Vector3=tree_bases[id]
		for index: int in range(24):
			var angle: float=TAU*index/24.;var radial: Vector3=Vector3(cos(angle),0.,sin(angle));var side: Vector3=Vector3(-radial.z,0.,radial.x)
			var at: Vector3=_safe_point(base+radial*1.6);var end: Vector3=_safe_point(base-radial*1.6)
			var a: Vector3=_safe_point(base+radial*1.6+side*1.3);var b: Vector3=_safe_point(base-radial*1.6+side*1.3)
			if not at.is_finite() or not end.is_finite() or not a.is_finite() or not b.is_finite():continue
			if not _segment_clear(at,a) or not _segment_clear(a,b) or not _segment_clear(b,end):continue
			contact={"tree_id":id,"start":_v(at),"radial":_v(radial),"side_path":[_v(a),_v(b),_v(end)]};break
		if not contact.is_empty():break
	fixture={"schema_version":1,"created_at_local":Time.get_datetime_string_from_system(),"before_report":report_path,"source_sha256":{TREE_DESIGN:FileAccess.get_sha256(TREE_DESIGN),TREE_WORLD:FileAccess.get_sha256(TREE_WORLD)},"physics_hz":30,"time_id":"day","quality_id":"standard","viewport_size":[root.size.x,root.size.y],"views":views,"contact":contact,"entry":entry,"tree_bases":_json(tree_bases),"scope":"Explicit player scenario starts and normal production third-person orientation. Source trees, NPCs and vehicles are never placed or disabled. Actor poses are live and are not a before/after image identity claim."}
	var output: FileAccess=FileAccess.open(fixture_path,FileAccess.WRITE)
	if output==null:return false
	output.store_string(JSON.stringify(_json(fixture),"\t")+"\n");output.close()
	return views.size()==4 and not contact.is_empty() and not entry.is_empty()

func _pose(title: String,point: Vector3) -> bool:
	_movement();_e(false)
	placements.append({"name":title,"kind":"explicit_player_only_scenario_start","point":_v(point)})
	scene.player.global_transform=Transform3D(Basis.IDENTITY,point);scene.player.require_neutral_input();scene.player.reset_physics_interpolation();scene.rig.reset_orientation();scene.rig.snap_to_target_pose()
	await _ticks(18)
	var grounded: bool=scene.player.is_on_floor() and not scene.player.input_latched and Vector2(scene.player.global_position.x-point.x,scene.player.global_position.z-point.z).length()<.08
	_check("placement."+title+".grounded_without_horizontal_displacement",grounded,{"requested":point,"actual":scene.player.global_position})
	return grounded

func _screen_point(point: Vector3) -> Dictionary:
	var camera: Camera3D=scene.rig.camera;var screen: Vector2=camera.unproject_position(point)
	return {"world":point,"screen":screen,"behind":camera.is_position_behind(point),"on_screen":not camera.is_position_behind(point) and scene.get_viewport().get_visible_rect().has_point(screen)}

func _capture_fixture(view: Dictionary) -> void:
	var id: String=String(view.id)
	if not await _pose(id,_vec(view.player_point)):return
	scene.rig.yaw=float(view.yaw);scene.rig.pitch=float(view.pitch);scene.rig.requested_distance=float(view.requested_distance);scene.rig.current_distance=float(view.requested_distance);scene.rig.snap_to_target_pose();await _ticks(8)
	var target: Vector3=tree_bases[String(view.tree_id)]+Vector3.UP*float(view.target_height_m)
	var head: Dictionary=_screen_point(scene.player.global_position+Vector3.UP*1.7);var tree_target: Dictionary=_screen_point(target)
	var trunk: Dictionary=_screen_point(tree_bases[String(view.tree_id)]+Vector3.UP*1.7)
	var separation: float=absf(head.screen.x-trunk.screen.x)
	var view_row: Dictionary={"fixture":view,"actual_player":scene.player.global_position,"camera":scene.rig.camera.global_transform,"requested_distance":scene.rig.requested_distance,"resolved_distance":scene.rig.current_distance,"player_head":head,"tree_target":tree_target,"trunk_at_head_height":trunk,"trunk_avatar_horizontal_separation_px":separation,"camera_mask":scene.rig.arm.collision_mask,"avatar_visible":scene.player.get_node("Visual").is_visible_in_tree()}
	var wide_top_on_screen: bool=true
	if native_tree_bounds.has(String(view.tree_id)):
		var bounds: AABB=native_tree_bounds[String(view.tree_id)];view_row["tree_top"]=_screen_point(Vector3(tree_bases[String(view.tree_id)].x,bounds.end.y,tree_bases[String(view.tree_id)].z))
		if id=="daehanmun_tree_row":wide_top_on_screen=bool(view_row.tree_top.on_screen)
	_check("view."+id+".normal_production_camera_and_avatar",scene.get_viewport().get_camera_3d()==scene.rig.camera and _camera_clear() and scene.rig.arm.collision_mask==33 and head.on_screen and trunk.on_screen and tree_target.on_screen and view_row.avatar_visible and separation>=float(view.get("minimum_trunk_avatar_horizontal_separation_px",32.)) and wide_top_on_screen and scene.rig.pitch<=deg_to_rad(15.)+.00001,view_row)
	var frames: Array=[];var process_usec: Array=[];var physics_usec: Array=[];var draw_calls: Array=[];var objects: Array=[];var primitives: Array=[];var prior: int=Time.get_ticks_usec();var physics_start: int=Engine.get_physics_frames();var recoveries: int=scene.player.recoveries
	for index: int in range(120):
		await process_frame
		var now: int=Time.get_ticks_usec();frames.append(now-prior);prior=now
		process_usec.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000000.);physics_usec.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000000.)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME));objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME));primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var all_cars: Array=scene.vehicles+scene.neighborhood_population.traffic.vehicles
	var live: Dictionary={"people_running":scene.pedestrians_running and scene.neighborhood_population.running,"vehicles_running":all_cars.all(func(body: CharacterBody3D)->bool:return body._running),"people_bodies":scene.pedestrians.size()+scene.street_pedestrians.actors.size()+scene.neighborhood_population.walkers.actors.size(),"vehicle_bodies":all_cars.size()}
	_check("observation."+id+".live_30Hz_day_actors_and_supported_player",Engine.physics_ticks_per_second==30 and scene.time_id=="day" and scene.quality_id=="standard" and not scene.menu.visible and live.people_running and live.vehicles_running and live.people_bodies==30 and live.vehicle_bodies==14 and scene.player.is_on_floor() and scene.player.recoveries==recoveries,{"live":live,"physics_frames_elapsed":Engine.get_physics_frames()-physics_start,"recoveries":scene.player.recoveries-recoveries})
	for values: Array in [frames,process_usec,physics_usec,draw_calls,objects,primitives]:values.sort()
	view_row["120_process_frame_observation"]={"frames":120,"frame_interval_usec_median":frames[60],"frame_interval_usec_p95":frames[114],"frame_interval_usec_max":frames.back(),"process_monitor_usec_median":process_usec[60],"physics_monitor_usec_median":physics_usec[60],"draw_calls_median":draw_calls[60],"rendered_objects_median":objects[60],"rendered_primitives_median":primitives[60],"actual_physics_frames":Engine.get_physics_frames()-physics_start,"scope":"Short same-fixture native observation with 60fps render cap; not a sustained performance or GPU-only timing claim."}
	if DisplayServer.get_name()=="headless":view_row["captured"]=false;view_row["native_status"]="DEFERRED"
	else:
		await process_frame;RenderingServer.force_draw(false,0.);await RenderingServer.frame_post_draw
		var picture: Image=scene.get_viewport().get_texture().get_image();var path: String=report_path.get_basename()+"_"+id+".png"
		var saved: bool=not picture.is_empty() and picture.save_png(path)==OK
		view_row["captured"]=saved;view_row["path"]=path;view_row["width"]=picture.get_width();view_row["height"]=picture.get_height()
		_check("capture."+id+".native_viewport",saved)
	captures.append(_json(view_row))

func _walk_short(title: String,points: Array) -> bool:
	var recovery: int=scene.player.recoveries;var samples: int=0;var floor_samples: int=0;var max_step: float=0.;var reached_all: bool=true;var start: Vector3=scene.player.global_position
	for target: Vector3 in points:
		var reached: bool=false
		for tick: int in range(240):
			var delta: Vector3=target-scene.player.global_position;delta.y=0.
			if delta.length()<.14:reached=true;break
			_world_keys(delta.normalized()*minf(.65,delta.length()/.4))
			var previous: Vector3=scene.player.global_position;await scene.rig.camera_stepped
			max_step=maxf(max_step,Vector2(scene.player.global_position.x-previous.x,scene.player.global_position.z-previous.z).length());samples+=1
			if scene.player.is_on_floor():floor_samples+=1
			if scene.player.recoveries!=recovery:break
		if not reached:reached_all=false;break
	_movement();await _ticks(3)
	var row: Dictionary={"title":title,"reached":reached_all,"samples":samples,"grounded_samples":floor_samples,"maximum_step_m":max_step,"start":start,"end":scene.player.global_position,"recoveries":scene.player.recoveries-recovery,"mid_walk_pose_assignments":0,"production_Input_actions":true}
	walks.append(_json(row));_check("walk."+title,reached_all and samples>=8 and floor_samples>=samples-2 and max_step<=scene.player.walk_speed_mps/30.+.006 and scene.player.recoveries==recovery,row)
	return reached_all

func _physical_interactions() -> void:
	var contact: Dictionary=fixture.get("contact",{})
	if contact.is_empty():_check("contact.fixture_available",false);return
	var row: Dictionary=tree_by_id[String(contact.tree_id)];var base: Vector3=tree_bases[String(contact.tree_id)]
	if await _pose("trunk_contact",_vec(contact.start)):
		await _ticks(18)
		var start: Vector3=scene.player.global_position;var radial: Vector3=_vec(contact.radial);var recovery: int=scene.player.recoveries;var touched: bool=false;var minimum: float=INF;var contacts: Array=[]
		for tick: int in range(90):
			_world_keys(-radial*.5);await scene.rig.camera_stepped
			minimum=minf(minimum,Vector2(scene.player.global_position.x-base.x,scene.player.global_position.z-base.z).length())
			for index: int in range(scene.player.get_slide_collision_count()):
				var hit: KinematicCollision3D=scene.player.get_slide_collision(index)
				if hit.get_collider()==row.body:touched=true
				if contacts.size()<8 and hit.get_collider()==row.body:contacts.append({"tick":tick,"normal":hit.get_normal(),"point":hit.get_position(),"geometry_id":String(hit.get_collider().get_meta("geometry_id",""))})
		_movement();await _ticks(3)
		var capsule: CapsuleShape3D=scene.player.get_node("CollisionShape").shape
		var same_side: float=(scene.player.global_position-base).dot(radial)
		_check("contact.production_Input_hits_real_trunk_without_crossing_or_recovery",touched and row.active and row.body.collision_layer==1 and not row.shape.disabled and minimum>=capsule.radius+.17-.02 and same_side>0. and start.distance_to(scene.player.global_position)>.25 and scene.player.recoveries==recovery,{"tree_id":contact.tree_id,"native_slide_contacts":contacts,"minimum_center_distance_m":minimum,"same_side_projection_m":same_side,"player_capsule_radius_m":capsule.radius,"actual_trunk_radius_m":row.shape.shape.radius,"recoveries":scene.player.recoveries-recovery})
		var side_points: Array=[]
		for raw: Array in contact.side_path:side_points.append(_vec(raw))
		await _walk_short("walk_beside_same_tree",side_points)
	var entry: Dictionary=fixture.get("entry",{})
	if entry.is_empty():_check("entry.fixture_available",false);return
	var selected: bool=visit.select_building(String(entry.building_id))
	_check("entry.nearby_source_building_selection",selected,{"building_id":entry.building_id})
	if not selected:return
	if await _pose("nearby_tree_entrance",_vec(entry.start)):
		if await _walk_short("nearby_tree_to_source_entrance",[_vec(entry.entrance)]):
			_movement();_e(false);await _ticks(4)
			var count: int=visit.entry_count;_e(true);_e(false);await _ticks(12)
			_check("entry.nearby_tree_does_not_block_real_E_entry",visit.active and visit.entry_count==count+1 and scene.player.interior_active,{"building_id":entry.building_id,"actual_building_id":visit.current_spec.get("id",""),"entries_before":count,"entries_after":visit.entry_count,"active":visit.active,"player":scene.player.global_position})

func _run() -> void:
	_began_usec=Time.get_ticks_usec();started_at=Time.get_datetime_string_from_system()
	for path: String in [TREE_DESIGN,TREE_WORLD,"res://scripts/neighborhood_greenery.gd","res://scripts/explore_walk.gd","res://scripts/player/exploration_camera.gd","res://scripts/player/free_roam_player.gd","res://scripts/terrain_surface.gd","res://data/generated/terrain_surface.json","res://../tests/game/check_tree_detail.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	_settings_path="/private/tmp/tree-detail-"+phase+"-"+str(OS.get_process_id())+".json"
	var settings: FileAccess=FileAccess.open(_settings_path,FileAccess.WRITE);settings.store_string(JSON.stringify({"schema_version":1,"speed_id":"brisk","free_roam":true}));settings.close()
	var quality: FileAccess=FileAccess.open(_settings_path+".quality.json",FileAccess.WRITE);quality.store_string(JSON.stringify({"schema_version":1,"preset_id":"standard"}));quality.close()
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_physics_hz=30;scene.exploration_settings_path=_settings_path;scene.quality_settings_path=_settings_path+".quality.json";root.add_child(scene)
	for index: int in range(25):await physics_frame
	_check("startup.production_30Hz_terrain_greenery_loaded",scene.runtime_ok and is_instance_valid(scene.terrain_surface) and scene.terrain_surface.loaded and is_instance_valid(scene.neighborhood_greenery) and scene.neighborhood_greenery.loaded and Engine.physics_ticks_per_second==30,{"runtime_ok":scene.runtime_ok,"error":scene.exploration_error})
	if not scene.runtime_ok:_finish();return
	terrain=scene.terrain_surface;greenery=scene.neighborhood_greenery;visit=scene.interior_visit
	if scene.menu.visible:scene.toggle_menu()
	scene.set_time_profile("day");scene.set_free_roam(true);scene.set_speed_profile("brisk");scene.apply_quality("standard");scene.set_pedestrians_running(true);scene.set_vehicles_running(true);await _ticks(6)
	_physical_trees();_native_trees()
	if phase=="before":_check("fixture.four_fixed_views_contact_and_entry_saved",_build_fixture(),{"path":fixture_path,"views":fixture.get("views",[]).size()})
	else:
		var changed: Array=[]
		for path: String in fixture.source_sha256:
			if fixture.source_sha256[path]!=FileAccess.get_sha256(path):changed.append(path)
		_check("sources.before_after_world_and_authored_tree_positions_unchanged",changed.is_empty(),{"changed":changed,"before_sources":fixture.source_sha256})
		var size: Array=fixture.get("viewport_size",[root.size.x,root.size.y]);root.size=Vector2i(int(size[0]),int(size[1]));await _ticks(3)
	for view: Dictionary in fixture.get("views",[]):await _capture_fixture(view)
	await _physical_interactions()
	var changed: Array=[]
	for path: String in source_hashes:
		if source_hashes[path]!=FileAccess.get_sha256(path):changed.append(path)
	_check("sources.frozen_during_actual_tree_detail_probe",changed.is_empty(),{"changed":changed})
	_finish()

func _timeout() -> void:
	_check("execution.finishes_within_600_second_wall_limit",false);_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var failed: int=0
	for row: Dictionary in checks:
		if not row.passed:failed+=1
	var report: Dictionary={"task":"TREE_DETAIL","phase":phase,"result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"started_at_local":started_at,"actual_wall_usec":Time.get_ticks_usec()-_began_usec,"source_sha256":source_hashes,"fixture_path":fixture_path,"fixture_sha256":FileAccess.get_sha256(fixture_path) if FileAccess.file_exists(fixture_path) else "","summary":{"checks":checks.size(),"failed":failed,"native_rendering_verified":DisplayServer.get_name()!="headless"},"checks":checks,"observations":observations,"scenario_starts":placements,"walks":walks,"captures":captures,"scope":"Before/after shared explicit player/camera fixtures in production ExploreWalk at30Hz, day/standard quality, all30 pedestrian bodies and14cars enabled. All369 source points/native ground/trunk contracts; after native shared mesh bounds and per-ID transforms, four normal third-person screenshots with120 process-frame observations, real Input trunk contact/side walk/nearby E entry. NPC/car poses, collision layers and source trees are never assigned by this test. Headless native rendering is explicitly deferred. This is a narrow tree visual/physical regression, not a sustained FPS, botanical/survey, complete live-actor itinerary or human-handling claim."}
	var output: FileAccess=FileAccess.open(report_path,FileAccess.WRITE)
	if output==null:push_error("Could not save tree detail report");quit(1);return
	output.store_string(JSON.stringify(_json(report),"\t")+"\n");output.close()
	print("TREE_DETAIL_TEST ",phase," ",report.result," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)
