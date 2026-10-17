extends Node3D
## Additional dispersed source-footway patrols; old actor arrays/counts stay fixed.
## The existing physical street actor and passing controller are reused intact.
const DESIGN_PATH := "res://assets/authored/neighborhood_population.json"
const WORLD_PATH := "res://resources/world_geometry/world.json"
class CoveragePoseFinisher extends Node:
	var controller: Node3D
	func _physics_process(delta: float) -> void:controller._finish_poses(delta)
class CoverageWalkers extends "res://scripts/street_pedestrians.gd":
	var drive_grid: Dictionary={}
	const DRIVE_CELL_M: float=32.0
	var last_guard_reason: String=""
	func setup_coverage(root_scene: Node3D,design: Dictionary) -> bool:
		city=root_scene.city;player=root_scene.player;rig=root_scene.rig;_design=design;_traffic=root_scene.traffic;name="DispersedWalkers"
		process_mode=Node.PROCESS_MODE_PAUSABLE;process_physics_priority=0
		_old_people=root_scene.pedestrians.duplicate()
		if is_instance_valid(root_scene.street_pedestrians):
			for row: Dictionary in root_scene.street_pedestrians.actors:_old_people.append(row.body)
		var traffic_data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/traffic.json"))
		_traffic_routes=traffic_data.get("routes",[]).duplicate(true);_traffic_routes.append_array(design.vehicle_routes)
		for building: Dictionary in root_scene.interior_visit.catalog:
			for entry: Dictionary in building.entry_candidates:_doors.append(entry.entrance)
		var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_geometry/world.json"))
		for mesh: Dictionary in world.meshes:
			if mesh.get("metadata",{}).get("display_mode","")!="drive":continue
			var vertices: Array=mesh.vertices
			for offset: int in range(0,vertices.size(),9):
				var a: Vector2=Vector2(vertices[offset],vertices[offset+2]);var b: Vector2=Vector2(vertices[offset+3],vertices[offset+5]);var c: Vector2=Vector2(vertices[offset+6],vertices[offset+8])
				if absf((b-a).cross(c-a))<.00001:continue
				var low: Vector2=a.min(b).min(c);var high: Vector2=a.max(b).max(c);var triangle: Array[Vector2]=[a,b,c]
				for x: int in range(floori(low.x/DRIVE_CELL_M),floori(high.x/DRIVE_CELL_M)+1):
					for z: int in range(floori(low.y/DRIVE_CELL_M),floori(high.y/DRIVE_CELL_M)+1):
						var key: Vector2i=Vector2i(x,z)
						if not drive_grid.has(key):drive_grid[key]=[]
						drive_grid[key].append(triangle)
		avoidance=AVOIDANCE.new();avoidance.setup(self,_at,_ground,_allowed,_neighbors)
		for record: Dictionary in design.routes:_make_group(record)
		var finish: CoveragePoseFinisher=CoveragePoseFinisher.new();finish.controller=self;finish.process_physics_priority=3;add_child(finish)
		loaded=not actors.is_empty()
		if actors.size()!=int(design.scope.new_walkers):push_warning("NEIGHBORHOOD_WALKERS_DEGRADED "+JSON.stringify({"actual":actors.size(),"expected":design.scope.new_walkers,"skipped":skipped}))
		return loaded
	func _route(record: Dictionary) -> Dictionary:
		var points: Array[Vector3]=[]
		for point: Array in record.xz:points.append(city.to_global(Vector3(point[0],0.,point[1])))
		return {"points":points,"source":record.source_feature_id,"authored_height":false}
	func _inside_drive(point: Vector2) -> bool:
		var key: Vector2i=Vector2i(floori(point.x/DRIVE_CELL_M),floori(point.y/DRIVE_CELL_M))
		for triangle: Array in drive_grid.get(key,[]):
			var a: Vector2=triangle[0];var b: Vector2=triangle[1];var c: Vector2=triangle[2]
			var first: float=(b-a).cross(point-a);var second: float=(c-b).cross(point-b);var third: float=(a-c).cross(point-c)
			if (first>=-.0000001 and second>=-.0000001 and third>=-.0000001) or (first<=.0000001 and second<=.0000001 and third<=.0000001):return true
		return false
	func _allowed(point: Vector3,radius: float) -> bool:
		last_guard_reason=""
		for offset: Vector3 in [Vector3.ZERO,Vector3.RIGHT*radius,Vector3.LEFT*radius,Vector3.FORWARD*radius,Vector3.BACK*radius]:
			var sample: Vector3=point+offset;var local: Vector3=city.to_local(sample);var flat: Vector2=Vector2(local.x,local.z)
			if not player.free_roam_bounds.grow(-.15).has_point(Vector2(sample.x,sample.z)):last_guard_reason="outside_game_bounds";return false
			if city._contains(flat,city.private_cache):last_guard_reason="source_private_ground";return false
			for road: Array in city.road_cache:
				if city._contains(flat,road):last_guard_reason="existing_source_road_exclusion";return false
			if _inside_drive(flat):last_guard_reason="actual_source_drive_mesh";return false
		if _traffic_distance(point)<float(_design.policy.traffic_route_clearance_m)+radius:last_guard_reason="moving_vehicle_corridor";return false
		for door: Vector3 in _doors:
			if Vector2(point.x-door.x,point.z-door.z).length()<1.0+radius:last_guard_reason="source_entry_clearance";return false
		return true
	func _make_group(record: Dictionary) -> void:
		var route: Dictionary=_route(record)
		for index: int in range(1,route.points.size()):
			var first: Vector3=route.points[index-1];var last: Vector3=route.points[index]
			var count: int=maxi(1,int(ceil(first.distance_to(last)/.5)))
			for step: int in range(count+1):
				var point: Vector3=first.lerp(last,float(step)/float(count))
				if not _allowed(point,.28):skipped.append({"id":record.id,"reason":last_guard_reason,"world_point":point,"local_point":city.to_local(point),"source_feature_id":record.source_feature_id,"segment":index,"fraction":float(step)/float(count)});return
		var skipped_before: int=skipped.size()
		super._make_group(record)
		if skipped.size()>skipped_before:
			var failure: Dictionary=skipped.back();var station: float=float(failure.get("station_m",0.));var arc: float=0.;var at: Vector3=route.points[0]
			for index: int in range(1,route.points.size()):
				var a: Vector3=route.points[index-1];var b: Vector3=route.points[index];var span: float=a.distance_to(b)
				if station<=arc+span:at=a.lerp(b,clampf((station-arc)/span,0.,1.));break
				arc+=span
			var floor: Dictionary=_ground(at);failure["requested_world"]=at;failure["floor"]=floor
			if not floor.is_empty():
				var capsule: CapsuleShape3D=CapsuleShape3D.new();capsule.radius=.27;capsule.height=1.70
				var query: PhysicsShapeQueryParameters3D=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.collision_mask=1|32;query.margin=.003;query.transform=Transform3D(Basis.IDENTITY,floor.point+Vector3.UP*.86)
				var contacts: Array=[]
				for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query,8):contacts.append({"node":String(hit.collider.get_path()),"source_id":hit.collider.get_meta("geometry_id",""),"transform":hit.collider.global_transform})
				failure["capsule_static_contacts"]=contacts

	func snapshot() -> Dictionary:
		var state: Dictionary=super.snapshot();state.maximum_authored_actors=int(_design.scope.new_walkers);state.scope="Additional source-bound patrols with inherited physical passing and articulated original avatar.";return state

var loaded: bool=false
var load_error: String=""
var host: Node3D
var walkers: Node3D
var traffic: Node3D
var design: Dictionary={}
var running: bool=true
var cars_running: bool=true

func setup(root_scene: Node3D) -> bool:
	if loaded or not is_inside_tree():return false
	host=root_scene;name="NeighborhoodPopulation";process_mode=Node.PROCESS_MODE_PAUSABLE
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(DESIGN_PATH))
	if not raw is Dictionary or raw.get("schema_version")!=1 or raw.get("world_sha256")!=FileAccess.get_sha256(WORLD_PATH):load_error="거리 인구 자료와 원본 지도가 다릅니다.";return false
	design=raw
	walkers=CoverageWalkers.new();add_child(walkers)
	if not walkers.setup_coverage(host,design):
		load_error="분산 보행 경로의 바닥과 안전 공간이 부족합니다."
		push_warning("NEIGHBORHOOD_WALKERS_REJECTED "+JSON.stringify({"actual":walkers.actors.size(),"expected":design.scope.new_walkers,"skipped":walkers.skipped}))
		return false
	# The traffic helper is owned separately; keep its actors out of old arrays.
	traffic=load("res://scripts/neighborhood_traffic.gd").new();add_child(traffic)
	if not traffic.setup(host,design):
		load_error="분산 차량 경로의 바닥과 차도 여유가 부족합니다."
		push_warning("NEIGHBORHOOD_VEHICLES_REJECTED "+JSON.stringify(traffic.snapshot()))
		return false
	loaded=true
	print("NEIGHBORHOOD_POPULATION_READY walkers=",walkers.actors.size()," source_corridors=",walkers.groups.size())
	return true

func set_people_running(enabled: bool) -> void:
	running=enabled
	if is_instance_valid(walkers):walkers.set_running(enabled)

func set_vehicles_running(enabled: bool) -> void:
	cars_running=enabled
	if is_instance_valid(traffic):traffic.set_running(enabled)

func set_running(enabled: bool) -> void:set_people_running(enabled);set_vehicles_running(enabled)

func actor_positions() -> Array[Vector3]:
	var result: Array[Vector3]=[]
	if is_instance_valid(walkers):
		for row: Dictionary in walkers.actors:result.append(row.body.global_position)
	if is_instance_valid(traffic) and traffic.has_method("actor_positions"):result.append_array(traffic.actor_positions())
	return result

func coverage_viewpoints() -> Array:
	var result: Array=[]
	for row: Dictionary in design.get("coverage_viewpoints",[]):
		result.append({"id":row.id,"point":Vector3(row.point_xz[0],.08,row.point_xz[1]),"toward":Vector3(row.toward_xz[0],1.0,row.toward_xz[1])})
	return result

func snapshot() -> Dictionary:
	return {"loaded":loaded,"error":load_error,"running":running,"cars_running":cars_running,"expected_walkers":int(design.get("scope",{}).get("new_walkers",20)),"actual_walkers":walkers.actors.size() if is_instance_valid(walkers) else 0,"degraded":is_instance_valid(walkers) and walkers.actors.size()!=int(design.scope.new_walkers),"walkers":walkers.snapshot() if is_instance_valid(walkers) else {},"traffic":traffic.snapshot() if is_instance_valid(traffic) else {},"coverage_viewpoints":coverage_viewpoints(),"source_geometry_changed":false,"old_actor_counts_changed":false,"design_sha256":FileAccess.get_sha256(DESIGN_PATH),"scope":"Additional authored people on source footway fragments, with existing physical movement and local passing; no measured density, destination routing or present-day visitor claim."}
