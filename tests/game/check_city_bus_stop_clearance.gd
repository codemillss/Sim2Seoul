extends "res://../tests/game/check_city_bus_loop.gd"
## Runs with native physics in headless or normal rendering. Only queries/poses the
## player; no bus, source road, crossing, shelter or original actor is repositioned.
var shelter_rids: Array[RID]=[]
func _collect_shelters(node: Node) -> void:
	if node is StaticBody3D:shelter_rids.append(node.get_rid())
	for child: Node in node.get_children():_collect_shelters(child)
func _new_prop_hits(query: PhysicsShapeQueryParameters3D) -> Array:
	var result: Array=[]
	for hit: Dictionary in scene.get_world_3d().direct_space_state.intersect_shape(query,512):
		if hit.rid in shelter_rids:result.append(String(hit.collider.get_path()))
	return result
func _run() -> void:
	if FileAccess.file_exists(report_path):push_error("Refusing to overwrite clearance evidence");quit(2);return
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/sim2seoul-stop-clearance-settings.json";scene.exploration_physics_hz=60;root.add_child(scene);await _ticks(6);service=scene.city_bus_service
	_check("production_ready",scene.runtime_ok and service.loaded)
	if not scene.runtime_ok or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	service.set_running(false)
	for shelter: Node3D in service.shelter_nodes:_collect_shelters(shelter)
	var cert: Dictionary=service.design.preflight.stop_clearance;var accepted: bool=cert.crossing_source_count==19 and cert.crossing_game_count==7;var min_cross:=INF
	for row: Dictionary in cert.stop_certificates:
		accepted=accepted and row.accepted and row.full_shelter_source_path_distance_m>=.5 and row.full_shelter_source_solid_distance_m>=.4 and row.full_shelter_private_overlap_m2==0.
		for part: Dictionary in row.nearest_crossing.values():min_cross=minf(min_cross,float(part.distance_m));accepted=accepted and float(part.distance_m)>=3.
	_check("all_four_full_bus_wait_visual_shelter_planar_crossing_sourcewalk_solid_private_certificate",accepted,{"minimum_crossing_distance_m":min_cross,"certificate":cert})
	var crossings: Array=[];var features: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../data/processed/features.json"))
	for row: Dictionary in features.features:
		var tags: Dictionary=row.get("source_tags",{})
		if row.geometry.type=="LineString" and (tags.get("footway")=="crossing" or tags.has("crossing")):crossings.append({"id":row.feature_id,"xz":row.geometry.coordinates,"width_m":4.4})
	var roads: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/road_furniture.json"))
	for row: Dictionary in roads.crossings:crossings.append(row)
	var blocked: Array=[];var segments:=0;var skipped:=0
	for crossing: Dictionary in crossings:
		var path: Array=crossing.xz
		for i: int in range(path.size()-1):
			var a: Vector3=scene.city.to_global(Vector3(path[i][0],0,path[i][1]));var b: Vector3=scene.city.to_global(Vector3(path[i+1][0],0,path[i+1][1]));var middle: Vector3=(a+b)*.5;var ground: float=scene.terrain_surface.ground_y_world(middle)
			if not is_finite(ground):skipped+=1;continue
			var box:=BoxShape3D.new();box.size=Vector3(float(crossing.get("width_m",4.4))+6.,6.,a.distance_to(b)+6.)
			var query:=PhysicsShapeQueryParameters3D.new();query.shape=box;query.transform=Transform3D(Basis(Vector3.UP,atan2(-(b-a).x,-(b-a).z)),Vector3(middle.x,ground+2.,middle.z));query.collision_mask=1;query.margin=.002
			var hits: Array=_new_prop_hits(query)
			if not hits.is_empty():blocked.append({"crossing_id":crossing.id,"segment":i,"new_shelter_colliders":hits})
			segments+=1
	_check("actual_all_shelter_colliders_clear_source_and_game_crossing_bands_plus_3m",blocked.is_empty() and segments>0,{"crossing_count":crossings.size(),"native_segments":segments,"outside_TIN_segments_skipped":skipped,"blocked":blocked,"scope":"Native full-box exclusion against all new stop collider RIDs; source traffic/building and actual walking acceptance are checked separately."})
	var supported:=true;var support_rows: Array=[];var wait_rows: Array=[];var camera_ok:=true;var los_ok:=true;var full_wait_safe:=true
	for i: int in range(service.design.stops.size()):
		var stop: Dictionary=service.design.stops[i];var node: Node3D=service.shelter_nodes[i];var samples:=0;var spread_min:=INF;var spread_max:=-INF
		for x: float in [-.775,0.,.775]:
			for z: float in [-2.5,0.,3.235]:
				var p: Vector3=node.to_global(Vector3(x,0,z));var sample: Dictionary=scene.terrain_surface.sample_ground_world(p);supported=supported and sample.ok
				if sample.ok:
					spread_min=minf(spread_min,sample.height_m);spread_max=maxf(spread_max,sample.height_m)
					var ray:=PhysicsRayQueryParameters3D.create(Vector3(p.x,sample.height_m+.15,p.z),Vector3(p.x,sample.height_m-.15,p.z),32)
					var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(ray);supported=supported and not hit.is_empty() and absf(hit.position.y-sample.height_m)<.003;samples+=1
		var safe: Dictionary=scene.interior_visit._safe_external_point(stop.wait_world);full_wait_safe=full_wait_safe and not safe.is_empty()
		var posed: bool=await _pose(stop.wait_world);full_wait_safe=full_wait_safe and posed
		var minimum_camera:=INF
		if posed:
			var actual_camera: Camera3D=scene.get_viewport().get_camera_3d()
			for orbit: int in range(8):
				scene.rig.yaw=float(orbit)*TAU/8.;scene.rig.snap_to_target_pose();await _ticks(3)
				var distance: float=scene.rig.current_distance;minimum_camera=minf(minimum_camera,distance)
			camera_ok=camera_ok and minimum_camera>=2.2
		var frame: Dictionary=service._frame(float(stop.station_m));var probe: CharacterBody3D=service.buses[0];var pose: Transform3D=probe._terrain_pose(frame.point,atan2(-frame.direction.x,-frame.direction.z));var exclude: Array[RID]=[scene.player.get_rid()]
		for body: CharacterBody3D in service.buses:exclude.append(body.get_rid())
		var door_rows: Array=[]
		for z: float in [-2.95,.55]:
			var door: Vector3=pose*Vector3(1.6,0,z);door.y=scene.terrain_surface.ground_y_world(door)+.08;var door_safe: Dictionary=scene.interior_visit._safe_external_point(door);var query:=PhysicsRayQueryParameters3D.create(stop.wait_world+Vector3.UP*1.1,door+Vector3.UP*1.1,1|16,exclude);var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(query);var clear: bool=not door_safe.is_empty() and hit.is_empty();los_ok=los_ok and clear;door_rows.append({"door_z":z,"safe_capsule":not door_safe.is_empty(),"clear_LOS":hit.is_empty(),"hit":String(hit.collider.get_path()) if not hit.is_empty() else ""})
		support_rows.append({"id":stop.id,"sample_count":samples,"TIN_height_range_m":spread_max-spread_min});wait_rows.append({"id":stop.id,"wait_safe":not safe.is_empty(),"native_player_pose":posed,"minimum_eight_orbit_camera_distance_m":minimum_camera,"doors":door_rows})
	_check("all_four_full_shelters_nine_actual_TIN_ray_supported_samples",supported,{"stops":support_rows})
	_check("all_four_waits_native_full_capsule_safe",full_wait_safe,{"stops":wait_rows})
	_check("all_four_waits_eight_orbit_camera_remains_third_person",camera_ok,{"minimum_distance_m":2.2,"stops":wait_rows})
	_check("all_four_wait_to_both_real_door_approaches_native_capsule_and_LOS",los_ok,{"stops":wait_rows})
	_check("original14_and_route_geometry_preserved",service.snapshot().original_vehicle_ids_unchanged and absf(float(service.design.route.length_m)-812.2916387858654)<.0001)
	_finish()
