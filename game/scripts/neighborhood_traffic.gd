extends Node3D
## Eight additional source-forward game vehicles. The N03 physical vehicle,
## braking, box sweeps, endpoint stop and camera-time recycle remain in use.
## Lane supports are local, vehicle-only engineering surfaces, not surveyed road.
const WORLD_PATH := "res://resources/world_geometry/world.json"
const VEHICLE_SCENE := preload("res://scenes/npc/vehicle.tscn")
const DRESSER := preload("res://scripts/exploration_traffic.gd")
const COLORS := [Color(.18,.42,.55),Color(.88,.84,.69),Color(.54,.25,.22),Color(.31,.48,.37),Color(.75,.55,.18),Color(.61,.65,.68),Color(.33,.32,.48),Color(.79,.80,.74)]
const SAMPLE_M := .50
const HALF_WIDTH_M := 1.10
const HALF_LENGTH_M := 2.30

class CoverageVehicle extends "res://scripts/traffic/exploration_vehicle.gd":
	# N03's speed-dependent lookahead contracts to exactly 1m at rest. A body
	# 1.007m beyond the box then disappears from that query and provokes a tiny
	# accelerate/brake cycle. Keep a fixed, current-physics release envelope once
	# physical braking has actually reached zero; never move the actor to stop it.
	var _obstacle_hold: bool=false
	var _release_probe_m: float=0.0
	var _obstacle_clear_s: float=0.0
	func _choose_step_budget(delta: float) -> float:
		if _obstacle_hold:
			var current: Dictionary=super._corridor_obstacle(_release_probe_m)
			_obstacle_clear_s=_obstacle_clear_s+maxf(0.0,delta) if current.is_empty() else 0.0
			if _obstacle_clear_s<.30:
				_command_speed_mps=0.0;_state="waiting_obstacle";_obstacle=current
				_blocked_reason=String(current.get("reason","obstacle_clear_hold"))
				return 0.0
			_obstacle_hold=false;_obstacle_clear_s=0.0
		var budget: float=super._choose_step_budget(delta)
		if budget<=.0000001 and not _obstacle.is_empty():
			_obstacle_hold=true;_obstacle_clear_s=0.0
			_release_probe_m=maxf(1.50,float(_obstacle.get("distance_m",0.0))+.35)
		return budget
	func snapshot() -> Dictionary:
		var result: Dictionary=super.snapshot()
		result["physical_obstacle_hold"]=_obstacle_hold;result["obstacle_release_probe_m"]=_release_probe_m;result["obstacle_clear_hold_s"]=_obstacle_clear_s
		return result

class CoverageManager extends "res://scripts/traffic/traffic_manager.gd":
	var host: Node3D
	var zones: Dictionary={}
	var grants := 0
	var yields := 0
	func setup_coverage(scene: Node3D,route_rows: Array) -> void:
		host=scene;city=scene.city;camera=scene.rig.camera;humans=scene.traffic.humans
		for route: Dictionary in route_rows:
			routes[route.id]=route
			for conflict: Dictionary in route.conflicts:
				var id: String=String(conflict.crossing_id)
				if not zones.has(id):zones[id]={"id":id,"center":Vector2(conflict.center_xz[0],conflict.center_xz[1]),"radius_m":3.80,"owner":"","queue":[],"clear_s":0.0,"human_present":true}
	func _refresh() -> void:
		var tick: int=Engine.get_physics_frames()
		if refreshed_tick==tick:return
		refreshed_tick=tick;humans=host.traffic.humans
		var continuous: bool=tick-last_observation_tick<=1
		human_rows.clear();observations_valid=observations_enabled and not humans.is_empty();human_present=false
		for zone: Dictionary in zones.values():zone.human_present=false
		for human: CharacterBody3D in humans:
			if not is_instance_valid(human) or not human.global_position.is_finite():observations_valid=false;continue
			var point: Vector3=city.to_local(human.global_position);var inside: Array=[]
			var ground_observed: bool=false;var near_ground: bool=false
			for zone: Dictionary in zones.values():
				if Vector2(point.x,point.z).distance_to(zone.center)>=float(zone.radius_m):continue
				if not ground_observed:
					var ground: Vector3=_terrain_point(human.global_position)
					near_ground=absf(human.global_position.y-ground.y)<2.8;ground_observed=true
				if near_ground:zone.human_present=true;inside.append(zone.id)
			human_rows.append({"id":str(human.get_path()),"position":[human.global_position.x,human.global_position.y,human.global_position.z],"layer":human.collision_layer,"crossings":inside})
		last_observation_tick=tick
		for zone: Dictionary in zones.values():
			if not observations_valid:zone.human_present=true
			human_present=human_present or bool(zone.human_present)
			zone.clear_s=float(zone.clear_s)+1.0/Engine.physics_ticks_per_second if continuous and observations_valid and not zone.human_present else 0.0
			var owner: String=String(zone.owner)
			if not owner.is_empty():
				for car: CharacterBody3D in vehicles:
					if car.get_route_id()!=owner:continue
					for conflict: Dictionary in routes[owner].conflicts:
						if String(conflict.crossing_id)==String(zone.id) and car.get_station_m()>float(conflict.exit_s_m)+.005:
							events.append({"type":"release","tick":tick,"route_id":owner,"crossing":zone.id});zone.owner=""
			for car: CharacterBody3D in vehicles:
				var id: String=car.get_route_id();var station: float=car.get_station_m()
				for conflict: Dictionary in routes[id].conflicts:
					if String(conflict.crossing_id)!=String(zone.id):continue
					if station>=float(conflict.stop_s_m)-.25 and station<=float(conflict.exit_s_m)+.005 and zone.owner!=id and not zone.queue.has(id):
						zone.queue.append(id);events.append({"type":"queued","tick":tick,"route_id":id,"crossing":zone.id})
			if String(zone.owner).is_empty() and not zone.queue.is_empty() and observations_valid and not zone.human_present and float(zone.clear_s)>=1.0 and _signal_allows(String(zone.queue.front()),String(zone.id)):
				zone.owner=zone.queue.pop_front();grants+=1;events.append({"type":"grant","tick":tick,"route_id":zone.owner,"crossing":zone.id,"clear_s":zone.clear_s,"human_present":false})
		while events.size()>256:events.pop_front()
	func permission(body: CharacterBody3D) -> Dictionary:
		_refresh()
		var tick: int=Engine.get_physics_frames();var fresh: bool=observations_valid and float(tick-last_observation_tick)/Engine.physics_ticks_per_second<=.1
		var conflict: Dictionary={}
		for row: Dictionary in routes[body.get_route_id()].conflicts:
			if body.get_station_m()<=float(row.exit_s_m)+.0001:conflict=row;break
		var zone: Dictionary={} if conflict.is_empty() else zones[String(conflict.crossing_id)]
		var human: bool=bool(zone.get("human_present",false))
		var signal_clear: bool=_signal_permission(body,conflict)
		var allowed: bool=fresh and signal_clear and (zone.is_empty() or (not human and String(zone.owner)==body.get_route_id()))
		var reason: String="source_forward_clear" if allowed else "human_present" if human else "fifo_or_clear_hold"
		if not signal_clear:reason="signal_red_or_amber"
		if not fresh:reason="stale_or_unknown_observation"
		if not allowed:yields+=1
		return {"fresh":fresh,"allow_crossing":allowed,"human_present":human,"occupied_by":zone.get("owner",""),"reason":reason,"crossing":zone.get("id",""),"tick":tick,"observation_tick":last_observation_tick,"observation_age_s":float(tick-last_observation_tick)/Engine.physics_ticks_per_second,"clear_s":zone.get("clear_s",0.0),"queue":zone.get("queue",[]).duplicate(),"signal_attached":is_instance_valid(signal_provider),"signal_clear":signal_clear}
	func snapshot() -> Dictionary:
		var result: Dictionary=super.snapshot();var rows: Array=[]
		for zone: Dictionary in zones.values():rows.append({"id":zone.id,"center":zone.center,"radius_m":zone.radius_m,"owner":zone.owner,"queue":zone.queue.duplicate(),"clear_s":zone.clear_s,"human_present":zone.human_present})
		result["crossings"]=rows;result["grants"]=grants;result["yield_observations"]=yields;result["events"]=events.duplicate(true)
		return result

var host: Node3D
var design: Dictionary={}
var manager: Node
var vehicles: Array[CharacterBody3D]=[]
var supports: Array[StaticBody3D]=[]
var route_audits: Array[Dictionary]=[]
var loaded := false
var load_error := ""
var running := true
var _source_meshes: Dictionary={}
var _initial_old_count := 0

func _inside_polygon(point: Vector2,coordinates: Array) -> bool:
	if coordinates.is_empty():return false
	var outer := PackedVector2Array()
	for raw: Array in coordinates[0]:outer.append(Vector2(raw[0],raw[1]))
	if not Geometry2D.is_point_in_polygon(point,outer):return false
	for index: int in range(1,coordinates.size()):
		var hole := PackedVector2Array()
		for raw: Array in coordinates[index]:hole.append(Vector2(raw[0],raw[1]))
		if Geometry2D.is_point_in_polygon(point,hole):return false
	return true

func _source_contains(point: Vector2,mesh: Dictionary) -> bool:
	for triangle: PackedVector2Array in mesh.triangles:
		if Geometry2D.is_point_in_polygon(point,triangle):return true
	return false

func _at(route: Dictionary,station: float) -> Dictionary:
	var arc := 0.0
	for index: int in range(1,route.xz.size()):
		var a := Vector3(route.xz[index-1][0],float(route.ground_y_m),route.xz[index-1][1]);var b := Vector3(route.xz[index][0],float(route.ground_y_m),route.xz[index][1]);var length: float=a.distance_to(b)
		if station<=arc+length or index==route.xz.size()-1:return {"point":a.lerp(b,clampf((station-arc)/length,0,1)),"direction":(b-a).normalized(),"segment":index-1}
		arc+=length
	return {}

func _corners(point: Vector3,direction: Vector3) -> Array[Vector3]:
	var side := Vector3(direction.z,0,-direction.x);var result: Array[Vector3]=[]
	for lateral in [-HALF_WIDTH_M,HALF_WIDTH_M]:
		for longitudinal in [-HALF_LENGTH_M,HALF_LENGTH_M]:result.append(point+side*float(lateral)+direction*float(longitudinal))
	return result

func _certify(route: Dictionary) -> Dictionary:
	var audit: Dictionary={"id":route.get("id",""),"accepted":false,"samples":0,"reason":"invalid_source_binding","support_basis":"vehicle_only_flat_engineering_lane_not_surveyed_terrain"}
	var binding: Dictionary=route.get("source_binding",{});var source: String=String(binding.get("feature_id",""))
	if binding.get("source_direction")!="source_forward" or binding.get("oneway")!="yes" or not _source_meshes.has(source) or route.get("repeat")!="guarded_oneway_stream":return audit
	var mesh: Dictionary=_source_meshes[source]
	if binding.get("source_refs",[])!=mesh.source_refs:return audit
	if route.get("road_domain",{}).get("type")!="Polygon" or route.get("xz",[]).size()<2:return audit
	var length := 0.0
	for index: int in range(1,route.xz.size()):length+=Vector2(route.xz[index][0]-route.xz[index-1][0],route.xz[index][1]-route.xz[index-1][1]).length()
	if not is_finite(length) or length<30.0 or absf(length-float(route.get("length_m",-1)))>.001:return audit
	var excluded: Array[RID]=[]
	for rid: RID in host.city.get_meta("vehicle_support_rids",[]):excluded.append(rid)
	var shape := BoxShape3D.new();shape.size=Vector3(1.8,1.48,4.2)
	for index: int in range(int(ceil(length/SAMPLE_M))+1):
		var station: float=minf(length,index*SAMPLE_M);var frame: Dictionary=_at(route,station);var point: Vector3=frame.point;var direction: Vector3=frame.direction
		for corner: Vector3 in _corners(point,direction):
			var flat := Vector2(corner.x,corner.z)
			if not Geometry2D.is_point_in_polygon(flat,host.exploration_overlay.polygon):audit.reason="outside_existing_source_extent";audit.station_m=station;return audit
			if not _inside_polygon(flat,route.road_domain.coordinates) or not _source_contains(flat,mesh):audit.reason="full_box_margin_outside_source_drive_mesh";audit.station_m=station;return audit
			if host.city._contains(flat,host.city.private_cache):audit.reason="private_source_domain";audit.station_m=station;return audit
		var query := PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=Transform3D(Basis(Vector3.UP,atan2(-direction.x,-direction.z)),host.city.to_global(point+Vector3.UP*.77));query.collision_mask=1|16;query.exclude=excluded;query.margin=0.0
		var hits: Array[Dictionary]=get_world_3d().direct_space_state.intersect_shape(query,8)
		if not hits.is_empty():audit.reason="actual_static_box_obstacle";audit.station_m=station;audit.collider=String(hits[0].collider.name);return audit
		audit.samples=int(audit.samples)+1
	# Check both exact headings at each source vertex, including the incoming
	# orientation that the physical controller retains on its arrival tick.
	for index: int in range(1,route.xz.size()-1):
		var vertex := Vector3(route.xz[index][0],float(route.ground_y_m),route.xz[index][1]);var prior := Vector3(route.xz[index-1][0],float(route.ground_y_m),route.xz[index-1][1]);var direction: Vector3=(vertex-prior).normalized()
		for corner: Vector3 in _corners(vertex,direction):
			var flat := Vector2(corner.x,corner.z)
			if not _inside_polygon(flat,route.road_domain.coordinates) or not _source_contains(flat,mesh) or host.city._contains(flat,host.city.private_cache):audit.reason="incoming_vertex_box_outside_source_domain";return audit
	for conflict: Dictionary in route.get("conflicts",[]):
		if not conflict.has("center_xz") or float(conflict.stop_s_m)<0 or float(conflict.stop_s_m)>float(conflict.enter_s_m) or float(conflict.exit_s_m)<=float(conflict.enter_s_m) or float(conflict.exit_s_m)>length:audit.reason="invalid_crossing_order";return audit
		audit["crossings"]=int(audit.get("crossings",0))+1
	audit.accepted=true
	audit.reason="source_drive_mesh_full_box_and_static_clear";audit.length_m=length;audit.source_feature_id=source;audit.source_refs=binding.source_refs;audit.maximum_sample_spacing_m=SAMPLE_M;audit.certificate_box_m=Vector3(HALF_WIDTH_M*2,1.5,HALF_LENGTH_M*2)
	return audit

func _support(route: Dictionary) -> void:
	var faces := PackedVector3Array()
	for index: int in range(1,route.xz.size()):
		var a := Vector3(route.xz[index-1][0],float(route.ground_y_m),route.xz[index-1][1]);var b := Vector3(route.xz[index][0],float(route.ground_y_m),route.xz[index][1]);var direction: Vector3=(b-a).normalized();var side := Vector3(direction.z,0,-direction.x)*HALF_WIDTH_M
		var first: Vector3=a-direction*HALF_LENGTH_M;var last: Vector3=b+direction*HALF_LENGTH_M
		faces.append_array(PackedVector3Array([first-side,last+side,first+side,first-side,last-side,last+side]))
	var body := StaticBody3D.new();body.name="CoverageLaneSupport_"+String(route.id);body.collision_layer=16;body.collision_mask=8;body.set_meta("geometry_id","EXP24_vehicle_lane_"+String(route.id));body.set_meta("source_feature_id",route.source_binding.feature_id);body.set_meta("authored_flat_support",true)
	var collision := CollisionShape3D.new();collision.name="CollisionShape";var shape := ConcavePolygonShape3D.new();shape.set_faces(faces);shape.backface_collision=true;collision.shape=shape;body.add_child(collision);add_child(body);body.global_transform=host.city.global_transform;supports.append(body)

func setup(root_scene: Node3D,population_design: Dictionary) -> bool:
	if loaded or not is_inside_tree() or not is_instance_valid(root_scene):return false
	host=root_scene;design=population_design;name="NeighborhoodTraffic";process_mode=Node.PROCESS_MODE_PAUSABLE
	_initial_old_count=host.vehicles.size()
	if not is_instance_valid(host.traffic) or not is_instance_valid(host.exploration_overlay) or population_design.get("world_sha256")!=FileAccess.get_sha256(WORLD_PATH):load_error="차량 원본/지면 계약이 다릅니다.";return false
	var world: Variant=JSON.parse_string(FileAccess.get_file_as_string(WORLD_PATH))
	if not world is Dictionary:load_error="차량 도로 원본을 읽을 수 없습니다.";return false
	for mesh: Dictionary in world.meshes:
		if mesh.get("material")!="drive":continue
		var triangles: Array[PackedVector2Array]=[];var vertices: Array=mesh.vertices
		for offset: int in range(0,vertices.size(),9):triangles.append(PackedVector2Array([Vector2(vertices[offset],vertices[offset+2]),Vector2(vertices[offset+3],vertices[offset+5]),Vector2(vertices[offset+6],vertices[offset+8])]))
		_source_meshes[String(mesh.metadata.feature_id)]={"triangles":triangles,"source_refs":mesh.metadata.source_refs}
	var route_rows: Array=population_design.get("vehicle_routes",[])
	if route_rows.size()!=4:load_error="분산 차량 경로는 네 곳이어야 합니다.";return false
	for route: Dictionary in route_rows:
		var audit: Dictionary=_certify(route);route_audits.append(audit)
		if not audit.accepted:load_error="차량 경로 검증 실패: %s · %s"%[String(route.id),String(audit.reason)];return false
	for route: Dictionary in route_rows:_support(route)
	manager=CoverageManager.new();manager.name="CoverageTrafficManager";add_child(manager);manager.setup_coverage(host,[])
	var dresser: Node=DRESSER.new();dresser.name="VehicleVisualLibrary";add_child(dresser)
	for route: Dictionary in route_rows:
		for sequence: int in range(2):
			var record: Dictionary=route.duplicate(true);record.id=String(route.id)+"_car_"+str(sequence)
			manager.routes[record.id]=record
			var body: CharacterBody3D=VEHICLE_SCENE.instantiate();body.set_script(CoverageVehicle);body.name="Vehicle_"+String(record.id);body.set_meta("geometry_id","EXP24_"+String(record.id));body.set_meta("coverage_route",String(route.id))
			body.initial_station_m=float(route.length_m)*(.22 if sequence==0 else .62);body.configure(record,manager,host.city);add_child(body);vehicles.append(body);manager.register_vehicle(body);dresser._dress(body,COLORS[(vehicles.size()-1)%COLORS.size()])
	# Configure crossing zones after per-car IDs exist; no old manager arrays move.
	manager.setup_coverage(host,manager.routes.values())
	host.rig.camera_stepped.connect(manager.after_camera_step)
	loaded=vehicles.size()==8;return loaded

func refresh_terrain() -> void:
	for body: CharacterBody3D in vehicles:body.refresh_terrain()
	if is_instance_valid(manager):
		manager.refresh_terrain()
		for zone: Dictionary in manager.zones.values():zone.clear_s=0.0;zone.human_present=true

func set_running(enabled: bool) -> void:
	running=enabled
	for body: CharacterBody3D in vehicles:body.set_running(enabled)

func actor_positions() -> Array[Vector3]:
	var result: Array[Vector3]=[]
	for body: CharacterBody3D in vehicles:result.append(body.global_position)
	return result

func coverage_viewpoints() -> Array:
	var result: Array=[]
	for route: Dictionary in design.get("vehicle_routes",[]):
		var frame: Dictionary=_at(route,float(route.length_m)*.40);var side := Vector3(frame.direction.z,0,-frame.direction.x)
		var point: Vector3=host.city.to_global(frame.point+side*7.0);var toward: Vector3=host.city.to_global(frame.point)
		if is_instance_valid(manager):point=manager._terrain_point(point);toward=manager._terrain_point(toward)
		result.append({"id":String(route.id),"point":point+Vector3.UP*.08,"toward":toward+Vector3.UP*.9,"route_id":route.id})
	return result

func snapshot() -> Dictionary:
	var rows: Array=[]
	for body: CharacterBody3D in vehicles:rows.append(body.snapshot())
	return {"loaded":loaded,"error":load_error,"running":running,"vehicle_count":vehicles.size(),"vehicles":rows,"route_certificates":route_audits.duplicate(true),"limited_vehicle_support_count":supports.size(),"manager":manager.snapshot() if is_instance_valid(manager) else {},"original_vehicle_count":_initial_old_count,"original_array_unchanged":is_instance_valid(host) and host.vehicles.size()==_initial_old_count,"source_geometry_changed":false,"old_route_arrays_changed":false,"coverage_viewpoints":coverage_viewpoints(),"scope":"Eight authored source-forward vehicles on four source-derived display road corridors; limited vehicle-only supports (height-conformed when terrain is enabled), inherited physical braking and full-box sweeps. Multi-crossing human priority/FIFO and existing camera/human/entry-guarded recycling. No real lane survey, routing/density claim, outside-source road or source-body changes."}
