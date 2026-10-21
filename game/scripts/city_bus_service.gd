extends Node3D
## A source-road, terrain-grounded two-stop game pilot. T01/GAME IDs and
## arrival predictions belong to this simulation, never a live Seoul service.
const DATA_PATH := "res://assets/authored/bus_service.json"
const VEHICLE_SCENE := preload("res://scenes/npc/vehicle.tscn")
const HALF_WIDTH := 1.225
const HALF_LENGTH := 4.5
const BOARD_DOOR_Z := [-2.95,.55]
const BOARD_MIN_SIDE_M := 1.43
const BOARD_MAX_SIDE_M := 3.95
const BOARD_ALONG_M := 1.95

class PilotBus extends "res://scripts/traffic/vehicle.gd":
	var service: Node3D
	func _find_support() -> void:
		super._find_support()
		if _floor_reason!="up_floor_ray":
			var ray:=PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*.7,global_position-Vector3.UP*.7,49,[get_rid()])
			var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(ray)
			if not hit.is_empty() and hit.normal.y>=cos(floor_max_angle):
				_last_support_rid=hit.rid
				if not _support_exclusions.has(_last_support_rid):_support_exclusions.append(_last_support_rid)
				_floor_reason="up_floor_ray";_floor_name=String(hit.collider.name);_floor_path=String(hit.collider.get_path())
		if is_instance_valid(service) and (service.riding or service._collision_release_pending):_support_exclusions.append(service.host.player.get_rid())
		# W03 and the EXP21 TIN overlap as ground. The first ray may choose W03;
		# include the other explicitly known ground RID in obstacle-only queries.
		# Native move_and_slide still retains BOTH ground collision layers.
		var surface: Node=_terrain_node if is_instance_valid(_terrain_node) else _terrain_service()
		if is_instance_valid(surface) and is_instance_valid(surface.support):
			var ground_rid: RID=surface.support.get_rid()
			if not _support_exclusions.has(ground_rid):_support_exclusions.append(ground_rid)
	func _terrain_clearance_height(at: Vector3,pose_basis: Basis) -> float:
		var height: float=_terrain_height(at)
		if not is_finite(height) or pose_basis.y.y<=.0001:return NAN
		var surface: Node=_terrain_node if is_instance_valid(_terrain_node) else _terrain_service()
		if surface==null:return NAN
		var polygon:=PackedVector2Array();var low:=Vector2.INF;var high:=-Vector2.INF
		for offset: Vector3 in [Vector3(-1.225,0,-4.5),Vector3(1.225,0,-4.5),Vector3(1.225,0,4.5),Vector3(-1.225,0,4.5)]:
			var corner: Vector3=at+pose_basis*offset;var flat:=Vector2(corner.x,corner.z)
			polygon.append(flat);low=low.min(flat);high=high.max(flat)
		for triangle: Dictionary in surface.triangles_at_xz_rect(Rect2(low,high-low).grow(.00001)):
			var tri:=PackedVector2Array([Vector2(triangle.a.x,triangle.a.z),Vector2(triangle.b.x,triangle.b.z),Vector2(triangle.c.x,triangle.c.z)])
			for cut: PackedVector2Array in Geometry2D.intersect_polygons(polygon,tri):
				for point: Vector2 in cut:
					var ground: float=_terrain_triangle_height(triangle,point)
					var bottom: float=-(pose_basis.y.x*(point.x-at.x)+pose_basis.y.z*(point.y-at.z))/pose_basis.y.y
					if is_finite(ground):height=maxf(height,ground-bottom)
		return height+TERRAIN_CLEARANCE_M
	func _terrain_pose(at: Vector3,yaw: float) -> Transform3D:
		_reset_terrain_queries()
		var key:=Vector3(at.x,at.z,yaw)
		if _terrain_pose_cache.has(key):return _terrain_pose_cache[key]
		var centre: float=_terrain_height(at)
		if not is_finite(centre):return Transform3D(Basis(Vector3.UP,yaw),at)
		var flat:=Basis(Vector3.UP,yaw);var heights: Array[float]=[]
		for x: float in [-1.225,1.225]:
			for z: float in [-4.5,4.5]:
				var height: float=_terrain_height(at+flat*Vector3(x,0,z));heights.append(height if is_finite(height) else centre)
		var side: float=((heights[2]+heights[3])-(heights[0]+heights[1]))/4.9
		var back: float=((heights[1]+heights[3])-(heights[0]+heights[2]))/18.
		var normal: Vector3=(Vector3.UP-flat.x*side-flat.z*back).normalized()
		var forward: Vector3=-flat.z;forward=(forward-normal*forward.dot(normal)).normalized()
		var fitted:=Basis(forward.cross(normal).normalized(),normal,-forward).orthonormalized()
		var feet:=Vector3(at.x,centre,at.z);feet.y=_terrain_clearance_height(feet,fitted)
		var result:=Transform3D(fitted,feet);_terrain_pose_cache[key]=result;return result
	func _choose_step_budget(delta: float) -> float:
		if service.bus_state in ["opening_doors","doors_open","closing_doors"]:
			_command_speed_mps=0.;_state="bus_"+service.bus_state;return 0.
		var budget: float=super._choose_step_budget(delta)
		var limit: Dictionary=service.motion_limit()
		if bool(limit.get("required",false)):
			var remaining: float=maxf(0.,float(limit.distance_m))
			_motion_cap_m=minf(_motion_cap_m,remaining)
			_command_speed_mps=minf(_command_speed_mps,_braking_speed(remaining,delta,2.0))
			budget=minf(budget,minf(remaining,_command_speed_mps*delta))
			if remaining<18.:
				_state="bus_braking" if _speed_mps>.01 else "bus_waiting"
				_blocked_reason=String(limit.reason)
		return budget

class BusRecycleGuard extends "res://scripts/traffic/traffic_manager.gd":
	var source_manager: Node
	func _refresh() -> void:
		source_manager._refresh();humans=source_manager.humans;observations_valid=source_manager.observations_valid;last_observation_tick=source_manager.last_observation_tick;human_rows=source_manager.human_rows
	func _corners(route: Dictionary,ending: bool) -> Array[Vector3]:
		var points: Array=route.xz;var a: Array=points[-2] if ending else points[0];var b: Array=points[-1] if ending else points[1]
		var direction:=Vector3(b[0]-a[0],0,b[1]-a[1]).normalized();var raw: Array=points[-1] if ending else points[0]
		var pose: Transform3D=vehicles[0]._terrain_pose(city.to_global(Vector3(raw[0],0,raw[1])),atan2(-direction.x,-direction.z));var result: Array[Vector3]=[]
		for x: float in [-1.53,1.53]:
			for y: float in [0.,3.24]:
				for z: float in [-4.55,4.55]:result.append(pose*Vector3(x,y,z))
		return result
	func recycle_guard(body: CharacterBody3D) -> Dictionary:
		var result: Dictionary=super.recycle_guard(body)
		var route: Dictionary=routes[body.get_route_id()];var raw: Array=route.xz[0];var next: Array=route.xz[1]
		var direction:=Vector3(next[0]-raw[0],0,next[1]-raw[1]).normalized()
		var pose: Transform3D=body._terrain_pose(city.to_global(Vector3(raw[0],0,raw[1])),atan2(-direction.x,-direction.z))
		var collider: CollisionShape3D=body.get_node("CollisionShape");var query:=PhysicsShapeQueryParameters3D.new();query.shape=collider.shape;query.transform=pose*collider.transform;query.collision_mask=14;query.exclude=[body.get_rid()];query.margin=.08
		var clear: bool=body.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
		result["full_bus_entry_clear"]=clear;result["full_bus_view_corners"]=true
		result.allowed=bool(result.allowed) and clear and float(result.minimum_human_surface_distance_m)>=32.0
		return result

var host: Node3D
var bus: CharacterBody3D
var design: Dictionary={}
var loaded:=false
var load_error:=""
var running:=true
var riding:=false
var exit_requested:=false
var bus_state:="approaching"
var stop_index:=0
var docked_stop:=-1
var door_fraction:=0.0
var state_elapsed:=0.0
var events: Array=[]
var route_certificate: Dictionary={}
var stop_certificates: Array=[]
var shelter_nodes: Array[Node3D]=[]
var door_panels: Array[Dictionary]=[]
var arrival_labels: Array[Label3D]=[]
var wheels: Array[Node3D]=[]
var passenger: Node3D
var _ride_saved: Dictionary={}
var _arrival_elapsed:=0.0
var _last_cycle:=-1
var _initial_vehicle_ids: Array=[]
var _source_mesh: Dictionary={}
var _recycle_manager: Node
var _crossing_commit: Dictionary={}
var waiting_for_bus:=false
var _board_pending:=false
var _board_pending_s:=0.0
var _last_board_door:=-1
var _collision_release_pending:=false
var _collision_release_tick:=0
var _release_hold_controls:=false
var _release_player_physics:=true

func _fail(message: String) -> bool:
	load_error=message;push_error(message);return false

func _event(kind: String,extra: Dictionary={}) -> void:
	var row: Dictionary={"type":kind,"tick":Engine.get_physics_frames(),"station_m":bus.get_station_m() if is_instance_valid(bus) else 0.}
	row.merge(extra);events.append(row)
	while events.size()>128:events.pop_front()

func _mat(color: Color,emission: float=0.0) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.55
	if emission>0.:material.emission_enabled=true;material.emission=color;material.emission_energy_multiplier=emission
	return material

func _box(parent: Node3D,title: String,size: Vector3,point: Vector3,material: Material,solid: bool=false) -> MeshInstance3D:
	var mesh:=BoxMesh.new();mesh.size=size;mesh.material=material
	var node:=MeshInstance3D.new();node.name=title;node.mesh=mesh;node.position=point;parent.add_child(node)
	if solid:
		var body:=StaticBody3D.new();body.name=title+"Collision";body.collision_layer=1;body.collision_mask=6
		body.set_meta("authored_game_placement",true);var shape:=BoxShape3D.new();shape.size=size
		var collider:=CollisionShape3D.new();collider.shape=shape;body.add_child(collider);node.add_child(body)
	return node

func _label(parent: Node3D,title: String,text: String,point: Vector3,pixels: float=.0038,color: Color=Color.WHITE) -> Label3D:
	var label:=Label3D.new();label.name=title;label.text=text;label.position=point;label.font_size=34;label.pixel_size=pixels;label.modulate=color;label.outline_size=3;label.outline_modulate=Color(.015,.025,.035);parent.add_child(label);return label

func _frame(station: float) -> Dictionary:
	var arc:=0.0;var points: Array=design.route.xz
	for index: int in range(1,points.size()):
		var a:=Vector3(points[index-1][0],0,points[index-1][1]);var b:=Vector3(points[index][0],0,points[index][1]);var span: float=a.distance_to(b)
		if station<=arc+span or index==points.size()-1:
			var point: Vector3=host.city.to_global(a.lerp(b,clampf((station-arc)/span,0.,1.)))
			point.y=host.terrain_surface.ground_y_world(point)
			return {"point":point,"direction":host.city.global_basis*(b-a).normalized()}
		arc+=span
	return {}

func _source_contains(point: Vector2,mesh: Dictionary) -> bool:
	var values: Array=mesh.get("vertices",[])
	for index: int in range(0,values.size(),9):
		var triangle:=PackedVector2Array([Vector2(values[index],values[index+2]),Vector2(values[index+3],values[index+5]),Vector2(values[index+6],values[index+8])])
		if Geometry2D.is_point_in_polygon(point,triangle):return true
	return false

func _certify_route() -> bool:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_geometry/world.json"))
	for mesh: Dictionary in world.meshes:
		if mesh.get("material")=="drive" and mesh.get("metadata",{}).get("feature_id")==design.route.source_binding.feature_id:_source_mesh=mesh;break
	if _source_mesh.is_empty():return _fail("버스의 원본 차도 면을 찾지 못했습니다.")
	route_certificate={"accepted":false,"samples":0,"source_feature_id":design.route.source_binding.feature_id,"source_refs":_source_mesh.metadata.source_refs,"box_m":[2.45,3.0,9.0],"spacing_m":.5,"terrain_support":"EXP21 existing physical TIN; no bus-only plane"}
	for index: int in range(int(ceil(float(design.route.length_m)/.5))+1):
		var frame: Dictionary=_frame(minf(float(design.route.length_m),index*.5));var side:=Vector3(frame.direction.z,0,-frame.direction.x)
		for x: float in [-HALF_WIDTH,HALF_WIDTH]:
			for z: float in [-HALF_LENGTH,HALF_LENGTH]:
				var point: Vector3=host.city.to_local(frame.point+side*x+frame.direction*z)
				if not _source_contains(Vector2(point.x,point.z),_source_mesh):route_certificate.reason="full_bus_outside_source_road";route_certificate.station_m=index*.5;return _fail("버스 전체 폭과 길이가 원본 차도 밖에 놓입니다.")
				if not is_finite(host.terrain_surface.ground_y_world(host.city.to_global(point))):return _fail("버스 경로 지면이 없습니다.")
		route_certificate.samples=int(route_certificate.samples)+1
	route_certificate.accepted=true;route_certificate.reason="all_bus_corners_inside_source_drive_triangles"
	return true

func setup(root_scene: Node3D) -> bool:
	if loaded or not is_instance_valid(root_scene) or not is_inside_tree():return false
	host=root_scene;name="CityBusService";process_mode=Node.PROCESS_MODE_PAUSABLE
	if not is_instance_valid(host.get("terrain_surface")) or not host.terrain_surface.loaded:return _fail("버스는 전체 지형 연결 뒤 준비해야 합니다.")
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not raw is Dictionary or raw.get("schema_version")!=1:return _fail("버스 체험 자료 버전이 다릅니다.")
	design=raw
	for path: String in design.source_hashes:
		if FileAccess.get_sha256(path)!=String(design.source_hashes[path]):return _fail("버스의 원본/지형 자료 해시가 다릅니다: "+path)
	for old: CharacterBody3D in host.vehicles:_initial_vehicle_ids.append(old.get_instance_id())
	for old: CharacterBody3D in host.neighborhood_population.traffic.vehicles:_initial_vehicle_ids.append(old.get_instance_id())
	if not _certify_route():return false
	for row: Dictionary in design.stops:
		if not _build_stop(row):return false
	bus=VEHICLE_SCENE.instantiate();bus.set_script(PilotBus);bus.name="BluePilotBus_T01";bus.service=self
	bus.collision_mask=63;bus.floor_snap_length=.45;bus.set_meta("geometry_id","T01_authored_blue_bus")
	var collider: CollisionShape3D=bus.get_node("CollisionShape");var shape:=BoxShape3D.new();shape.size=Vector3(2.45,3.0,9.0);collider.shape=shape;collider.position.y=1.5
	bus.configure(design.route,self,host.city);add_child(bus);bus.refresh_terrain();_dress_bus()
	_recycle_manager=BusRecycleGuard.new();_recycle_manager.name="BusOriginalCameraHumanGuard";_recycle_manager.source_manager=host.traffic;_recycle_manager.city=host.city;_recycle_manager.camera=host.rig.camera;_recycle_manager.routes={String(design.route.id):design.route};_recycle_manager.vehicles.append(bus);add_child(_recycle_manager)
	process_physics_priority=2;loaded=true;_event("service_ready");_refresh_arrivals()
	print("CITY_BUS_READY route=T01 stops=2 source_road_certified=true original_vehicles=",_initial_vehicle_ids.size())
	return true

func permission(_vehicle: CharacterBody3D) -> Dictionary:
	host.traffic._refresh()
	var fresh: bool=host.traffic.observations_valid and Engine.get_physics_frames()-host.traffic.last_observation_tick<=1
	return {"fresh":fresh,"allow_crossing":fresh,"human_present":host.traffic.human_present,"reason":"pilot_full_box_observation_and_source_signal" if fresh else "stale_or_unknown_human_observation","tick":Engine.get_physics_frames()}

func motion_limit() -> Dictionary:
	var result: Dictionary={"required":false}
	if stop_index<design.stops.size():
		result={"required":true,"distance_m":maxf(0.,float(design.stops[stop_index].station_m)-bus.get_station_m()),"reason":"scheduled_stop_"+String(design.stops[stop_index].id)}
	var network: Variant=host.get("street_network_detail")
	if is_instance_valid(network) and network.has_method("vehicle_stop_distance"):
		if not _crossing_commit.is_empty() and bus.get_station_m()>=float(_crossing_commit.clear_station_m):
			_event("crossing_rear_cleared",_crossing_commit);_crossing_commit.clear()
		var direction: Vector3=bus._segment_direction(bus._segment)
		var signal_limit: Dictionary=network.vehicle_stop_distance(String(design.route.source_binding.feature_id),bus.global_position,direction,30.)
		var human_wait: bool=bool(host.traffic.human_present) and not String(signal_limit.get("crossing_id","")).is_empty()
		var state: String=String(signal_limit.get("state","uncontrolled"));var line_distance: float=float(signal_limit.get("distance_m",INF))
		if _crossing_commit.is_empty() and not human_wait and not String(signal_limit.get("crossing_id","")).is_empty():
			var available: float=line_distance-HALF_LENGTH-.35
			var brake_room: float=bus._speed_mps*bus._speed_mps/4.+bus._speed_mps/float(Engine.physics_ticks_per_second)
			var green_entry: bool=state=="green" and line_distance<=HALF_LENGTH+.05 and bus._speed_mps>.10
			var amber_committed: bool=state=="amber" and bus._speed_mps>.5 and available<brake_room
			if green_entry or amber_committed:
				# The bus pilot and the source road have different arc origins.
				# Convert the observed stop/clearance distance to this bus's own
				# station; a source-road exit_s_m cannot describe its rear clearance.
				var clearance: float=maxf(0.0,float(signal_limit.get("clearance_from_stop_m",10.0)))
				_crossing_commit={"crossing_id":signal_limit.crossing_id,"entry_phase":state,"clear_station_m":bus.get_station_m()+line_distance+clearance+HALF_LENGTH+.50,"reason":"green_front_entry" if green_entry else "amber_insufficient_physical_brake_room"};_event("crossing_committed",_crossing_commit)
		var committed: bool=not _crossing_commit.is_empty() and String(_crossing_commit.crossing_id)==String(signal_limit.get("crossing_id",""))
		if (bool(signal_limit.get("required",false)) or human_wait) and not committed:
			var distance: float=maxf(0.,float(signal_limit.get("distance_m",0.))-HALF_LENGTH-.35)
			if not bool(result.get("required",false)) or distance<float(result.distance_m):result={"required":true,"distance_m":distance,"reason":"human_crossing_priority" if human_wait else "signal_"+String(signal_limit.get("state","stop"))}
	return result

func _build_stop(row: Dictionary) -> bool:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_geometry/world.json"));var walk: Dictionary={}
	for mesh: Dictionary in world.meshes:
		if mesh.get("material")=="walk" and mesh.get("metadata",{}).get("feature_id")==row.source_walk_feature_id:walk=mesh;break
	if walk.is_empty():return _fail("정류장의 원본 보행 면이 없습니다.")
	var point:=Vector3(row.shelter_xz[0],0,row.shelter_xz[1]);var wait:=Vector3(row.wait_xz[0],0,row.wait_xz[1]);var frame: Dictionary=_frame(float(row.station_m))
	if not _source_contains(Vector2(wait.x,wait.z),walk):return _fail("정류장 대기 위치가 원본 보행 면 밖입니다.")
	var node:=Node3D.new();node.name="Shelter_"+String(row.id);add_child(node);node.global_position=host.city.to_global(point);node.global_position.y=host.terrain_surface.ground_y_world(node.global_position);node.global_rotation.y=atan2(-frame.direction.x,-frame.direction.z)
	var frame_mat:=_mat(Color(.16,.20,.23));var roof:=_mat(Color(.29,.34,.36));var glass:=_mat(Color(.30,.49,.54));var wood:=_mat(Color(.43,.30,.18));var blue:=_mat(Color(.05,.26,.62));var display:=_mat(Color(.01,.025,.03));var white:=_mat(Color(.86,.91,.92))
	glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;glass.albedo_color.a=.32;glass.roughness=.22
	_box(node,"ShelterRoof",Vector3(1.55,.16,5.0),Vector3(0,2.62,0),roof)
	for z: float in [-2.2,2.2]:
		_box(node,"ShelterColumn",Vector3(.10,2.55,.10),Vector3(.6,1.275,z),frame_mat,true)
	_box(node,"ShelterRearGlazing",Vector3(.045,1.90,4.25),Vector3(.66,1.40,0),glass,true)
	for z: float in [-1.3,0.,1.3]:_box(node,"GlassMullion",Vector3(.07,2.0,.045),Vector3(.62,1.45,z),frame_mat)
	_box(node,"BenchSeat",Vector3(.48,.10,2.65),Vector3(.22,.48,.15),wood,true)
	_box(node,"BenchBack",Vector3(.07,.39,2.65),Vector3(.47,.75,.15),wood,true)
	for z: float in [-.9,1.2]:_box(node,"BenchLeg",Vector3(.10,.43,.12),Vector3(.25,.215,z),frame_mat,true)
	_box(node,"RouteBoard",Vector3(.07,1.34,.76),Vector3(.51,1.50,-1.68),white)
	var board: Label3D=_label(node,"RouteDiagram","도심01\n덕수궁 돌담\n     ↓\n시청 앞 하차\n\n게임 체험 노선",Vector3(.454,1.54,-1.68),.00245,Color(.09,.21,.30));board.rotation.y=-PI/2.
	_box(node,"StopHeader",Vector3(.12,.38,4.6),Vector3(.60,2.35,0),blue)
	var title: Label3D=_label(node,"StopName",String(row.name)+"  "+String(row.id),Vector3(.52,2.35,.15),.0031);title.rotation.y=-PI/2.
	_box(node,"ArrivalDisplay",Vector3(.10,.38,1.8),Vector3(.50,1.95,.65),display)
	var arrival: Label3D=_label(node,"LocalArrivalDisplay","도심01  운행 준비",Vector3(.43,1.95,.65),.00275,Color(.35,1.,.61));arrival.rotation.y=-PI/2.;arrival_labels.append(arrival)
	_box(node,"StopPole",Vector3(.07,2.7,.07),Vector3(-.15,1.35,2.95),frame_mat,true)
	_box(node,"BlueStopSign",Vector3(.09,.70,.57),Vector3(-.15,2.37,2.95),blue)
	var pole: Label3D=_label(node,"StopID","BUS\n"+String(row.id),Vector3(-.21,2.38,2.95),.0023);pole.rotation.y=-PI/2.
	var anchor: Vector3=host.city.to_global(wait);anchor.y=host.terrain_surface.ground_y_world(anchor)+.08
	row["wait_world"]=anchor;row["shelter_world"]=node.global_position
	stop_certificates.append({"id":row.id,"source_walk_feature_id":row.source_walk_feature_id,"source_wait_inside":true,"terrain_y_m":node.global_position.y,"authored_id":true});shelter_nodes.append(node);return true

func _dress_bus() -> void:
	var visual: Node3D=bus.get_node("Visual")
	for child: Node3D in visual.get_children():child.visible=false
	var blue:=_mat(Color(.035,.25,.65));var pale:=_mat(Color(.83,.88,.90));var glass:=_mat(Color(.075,.15,.20));var dark:=_mat(Color(.035,.045,.052));var steel:=_mat(Color(.54,.60,.64));var white:=_mat(Color(.94,.97,1.),.5);var amber:=_mat(Color(.98,.57,.07),.7);var red:=_mat(Color(.75,.045,.025),.5)
	glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;glass.albedo_color.a=.76;glass.roughness=.20
	_box(visual,"LowFloorBlueBody",Vector3(2.42,.18,8.94),Vector3(0,.39,0),blue)
	_box(visual,"LeftBodyPanel",Vector3(.09,1.06,8.94),Vector3(-1.165,1.01,0),blue)
	for span: Vector2 in [Vector2(-4.47,-3.55),Vector2(-2.35,-.05),Vector2(1.15,4.47)]:
		_box(visual,"RightBodyBetweenDoors",Vector3(.09,1.06,span.y-span.x),Vector3(1.165,1.01,(span.x+span.y)*.5),blue)
	_box(visual,"FrontBlueNose",Vector3(2.42,1.12,.12),Vector3(0,1.02,-4.40),blue)
	_box(visual,"RearBluePanel",Vector3(2.42,1.12,.12),Vector3(0,1.02,4.40),blue)
	_box(visual,"WhiteRoof",Vector3(2.43,.20,8.94),Vector3(0,2.92,0),pale)
	_box(visual,"RoofAirConditioner",Vector3(1.5,.20,2.3),Vector3(0,3.12,.4),pale)
	_box(visual,"WindowBelt",Vector3(.055,1.33,8.80),Vector3(-1.19,2.15,0),glass)
	for span: Vector2 in [Vector2(-4.40,-3.55),Vector2(-2.35,-.05),Vector2(1.15,4.40)]:
		_box(visual,"RightWindowsBetweenDoors",Vector3(.055,1.33,span.y-span.x),Vector3(1.19,2.15,(span.x+span.y)*.5),glass)
	_box(visual,"RearWindow",Vector3(2.2,1.33,.045),Vector3(0,2.15,4.43),glass)
	_box(visual,"InteriorFloor",Vector3(2.20,.09,8.65),Vector3(0,.52,0),_mat(Color(.27,.30,.31)))
	var seat_mat:=_mat(Color(.15,.32,.53));var pole_mat:=_mat(Color(.91,.76,.17))
	for side: float in [-1.,1.]:
		for z: float in [-1.7,-.5,1.8,3.0]:
			_box(visual,"PassengerSeat",Vector3(.46,.10,.48),Vector3(side*.77,.94,z),seat_mat)
			_box(visual,"PassengerSeatBack",Vector3(.46,.55,.08),Vector3(side*.77,1.24,z+.22),seat_mat)
	for z: float in [-1.9,1.6]:_box(visual,"YellowHandrail",Vector3(.045,2.14,.045),Vector3(.43,1.65,z),pole_mat)
	_box(visual,"DriverConsole",Vector3(.85,.42,.50),Vector3(-.57,1.20,-3.86),dark)
	_box(visual,"FrontWindshield",Vector3(2.20,1.12,.045),Vector3(0,2.12,-4.445),glass)
	_box(visual,"FrontHeader",Vector3(2.35,.40,.07),Vector3(0,2.74,-4.48),dark)
	var front: Label3D=_label(visual,"DestinationLED","도심01  덕수궁 · 시청",Vector3(0,2.75,-4.526),.0038,Color(.61,1.,.55));front.rotation.y=PI
	var rear: Label3D=_label(visual,"RearRouteLED","도심01",Vector3(0,2.65,4.50),.005,Color(.61,1.,.55))
	for side: float in [-1.,1.]:
		for z: float in [-4.25,-3.5,-2.,-.5,1.,2.5,4.2]:_box(visual,"WindowPillar",Vector3(.06,1.34,.055),Vector3(side*1.216,2.15,z),blue)
		if side<0.:_box(visual,"SilverWaistStripe",Vector3(.035,.11,8.7),Vector3(side*1.226,1.54,0),pale)
		_box(visual,"LowerSkirt",Vector3(.035,.16,8.7),Vector3(side*1.226,.43,0),dark)
		var number: Label3D=_label(visual,"SideRoute","도심01   덕수궁 · 시청",Vector3(side*1.245,1.16,.55),.0037);number.rotation.y=side*PI/2.
		_box(visual,"WingMirrorArm",Vector3(.30,.045,.05),Vector3(side*1.34,2.42,-3.9),dark)
		_box(visual,"WingMirror",Vector3(.13,.36,.20),Vector3(side*1.49,2.28,-3.92),dark)
		for z: float in [-2.68,2.62]:
			var wheel:=Node3D.new();wheel.name="RotatingWheel";wheel.position=Vector3(side*1.22,.43,z);visual.add_child(wheel);wheels.append(wheel)
			var mesh:=CylinderMesh.new();mesh.top_radius=.43;mesh.bottom_radius=.43;mesh.height=.22;mesh.radial_segments=20;mesh.material=dark
			var tire:=MeshInstance3D.new();tire.mesh=mesh;tire.rotation.z=PI/2.;wheel.add_child(tire)
			var hub:=CylinderMesh.new();hub.top_radius=.23;hub.bottom_radius=.23;hub.height=.235;hub.radial_segments=14;hub.material=steel
			var hubnode:=MeshInstance3D.new();hubnode.mesh=hub;hubnode.rotation.z=PI/2.;wheel.add_child(hubnode)
		for z: float in [-3.9,-.6,3.9]:_box(visual,"SideMarker",Vector3(.03,.075,.15),Vector3(side*1.25,.72,z),amber)
		_box(visual,"Headlamp",Vector3(.52,.19,.055),Vector3(side*.72,.85,-4.49),white)
		_box(visual,"RearLamp",Vector3(.24,.55,.05),Vector3(side*.91,.96,4.49),red)
	_box(visual,"FrontBumper",Vector3(2.42,.16,.15),Vector3(0,.45,-4.46),dark)
	_box(visual,"RearBumper",Vector3(2.42,.16,.15),Vector3(0,.45,4.46),dark)
	_box(visual,"FrontNumberPlate",Vector3(.44,.13,.035),Vector3(0,.68,-4.55),amber)
	for z: float in [-2.95,.55]:
		for part: float in [-1.,1.]:
			var panel:=Node3D.new();panel.name="SlidingDoor";panel.position=Vector3(1.246,1.76,z+part*.30);visual.add_child(panel)
			_box(panel,"DoorGlass",Vector3(.035,1.87,.56),Vector3.ZERO,glass)
			_box(panel,"DoorFrame",Vector3(.05,.075,.58),Vector3(0,-.89,0),pale)
			_box(panel,"DoorEdge",Vector3(.05,1.87,.035),Vector3(0,0,-part*.25),steel)
			door_panels.append({"node":panel,"closed":panel.position,"sign":part})
	_box(visual,"RearVent",Vector3(.035,.45,1.2),Vector3(-1.245,.97,3.2),dark)
	for z: float in [2.75,2.95,3.15,3.35,3.55]:_box(visual,"VentSlat",Vector3(.04,.025,.03),Vector3(-1.27,.97,z),steel)
	passenger=Node3D.new();passenger.name="SeatedPassenger";passenger.position=Vector3(.4,1.23,-.6);visual.add_child(passenger);passenger.visible=false
	_box(passenger,"PassengerTorso",Vector3(.40,.50,.26),Vector3(0,.18,0),_mat(Color(.42,.59,.47)))
	var head:=SphereMesh.new();head.radius=.15;head.height=.30;head.radial_segments=12;head.rings=8;head.material=_mat(Color(.72,.52,.37));var headnode:=MeshInstance3D.new();headnode.mesh=head;headnode.position.y=.60;passenger.add_child(headnode)

func set_running(enabled: bool) -> void:
	running=enabled
	if is_instance_valid(bus):bus.set_running(enabled)

func _physics_process(delta: float) -> void:
	if not loaded:return
	_finish_collision_release()
	if not running:return
	state_elapsed+=delta;_arrival_elapsed+=delta
	if _last_cycle!=bus._cycle_count:
		_last_cycle=bus._cycle_count
		if _last_cycle>0:stop_index=0;docked_stop=-1;bus_state="approaching";state_elapsed=0.;_crossing_commit.clear();_event("guarded_service_repeat")
	if waiting_for_bus and not _at_first_wait(6.0):waiting_for_bus=false;_event("wait_request_left_stop")
	if _board_pending:
		_board_pending_s+=delta
		if _board_pending_s>2.0 or not _context_ready() or _boarding_candidate().is_empty():_board_pending=false
	if bus_state=="approaching" and stop_index<design.stops.size():
		if absf(bus.get_station_m()-float(design.stops[stop_index].station_m))<.015 and bus._speed_mps<.025:
			docked_stop=stop_index;bus_state="opening_doors";state_elapsed=0.;_event("docked",{"stop_id":design.stops[stop_index].id,"speed_mps":bus._speed_mps})
	elif bus_state=="opening_doors":
		door_fraction=clampf(state_elapsed/float(design.policy.door_animation_s),0.,1.)
		if door_fraction>=1.:bus_state="doors_open";state_elapsed=0.;_event("doors_open",{"stop_id":design.stops[docked_stop].id})
	elif bus_state=="doors_open":
		if _board_pending and not riding:
			_board_pending=false
			if not _boarding_candidate().is_empty():_board()
		if riding and exit_requested:_exit_ride()
		if state_elapsed>=float(design.policy.dwell_s) and not _doorway_occupied() and not (riding and docked_stop==design.stops.size()-1):bus_state="closing_doors";state_elapsed=0.;_event("closing_doors")
	elif bus_state=="closing_doors":
		if _doorway_occupied():bus_state="opening_doors";state_elapsed=door_fraction*float(design.policy.door_animation_s);_event("door_safety_reopen")
		else:
			door_fraction=1.-clampf(state_elapsed/float(design.policy.door_animation_s),0.,1.)
			if door_fraction<=0.:stop_index+=1;docked_stop=-1;bus_state="approaching";state_elapsed=0.;_event("departed")
	for part: Dictionary in door_panels:part.node.position=part.closed+Vector3(0,0,float(part.sign)*.48*door_fraction)
	for wheel: Node3D in wheels:wheel.rotate_x(-bus._speed_mps*delta/.43)
	if riding:_attach_passenger(delta)
	if _arrival_elapsed>.5:_arrival_elapsed=0.;_refresh_arrivals()
	# The inherited controller's recycle grant remains camera/human/entry bound.
	if not riding and bus.can_recycle():
		var guard: Dictionary=_recycle_manager.recycle_guard(bus)
		bus.try_recycle(guard)

func _doorway_occupied() -> bool:
	if not is_instance_valid(bus):return true
	# Keep doors available while a prospective passenger is at either visible
	# door or the adjacent stop. Boarding is still a fresh, explicit E action.
	if not riding and not _boarding_candidate().is_empty():return true
	if waiting_for_bus and docked_stop==0 and _at_first_wait(4.5):return true
	for human: CharacterBody3D in host.traffic.humans:
		if human==host.player and riding:continue
		if not is_instance_valid(human):continue
		for z: float in BOARD_DOOR_Z:
			var doorway: Vector3=bus.to_global(Vector3(1.35,.5,z))
			if absf(human.global_position.y-doorway.y)<2.0 and Vector2(human.global_position.x-doorway.x,human.global_position.z-doorway.z).length()<.85:return true
	return false

func _context_ready() -> bool:
	if not loaded or not is_instance_valid(host) or not host.runtime_ok:return false
	if host.get_tree().paused:return false
	if is_instance_valid(host.get("menu")) and host.menu.visible:return false
	if _collision_release_pending and not riding:return false
	if host.has_method("_street_transport_riding_except"):
		if host._street_transport_riding_except(self):return false
	else:
		for key: String in ["city_bike_service","city_scooter_service"]:
			var mobility: Variant=host.get(key)
			if is_instance_valid(mobility) and mobility.get("riding")==true:return false
	if not riding and host.player.facility_control:return false
	return not host.player.interior_active and not host.interior_visit.active

func _board_grounded() -> bool:
	# A menu shortcut leaves a small safe gap above the floor. Do not require an
	# old CharacterBody floor flag when current native support is already clear.
	if absf(host.player.velocity.y)>2.0:return false
	var feet: Vector3=host.player.global_position
	var ray:=PhysicsRayQueryParameters3D.create(feet+Vector3.UP*.12,feet-Vector3.UP*.24,1|16|32,[host.player.get_rid(),bus.get_rid()])
	var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<cos(host.player.floor_max_angle):return false
	var gap: float=feet.y-hit.position.y
	return gap>=-.025 and gap<=.20

func _boarding_candidate() -> Dictionary:
	if not _context_ready() or riding or docked_stop!=0 or bus_state not in ["opening_doors","doors_open","closing_doors"] or bus._speed_mps>.025:return {}
	var local: Vector3=bus.to_local(host.player.global_position)
	if local.x<BOARD_MIN_SIDE_M or local.x>BOARD_MAX_SIDE_M or absf(local.y)>.9 or not _board_grounded():return {}
	var best: Dictionary={}
	for index: int in range(BOARD_DOOR_Z.size()):
		var z: float=BOARD_DOOR_Z[index]
		if absf(local.z-z)>BOARD_ALONG_M:continue
		var doorway: Vector3=bus.to_global(Vector3(1.58,0,z));var clear:=true
		for height: float in [.70,1.35]:
			var target: Vector3=bus.to_global(Vector3(1.58,height,z))
			var query:=PhysicsRayQueryParameters3D.create(host.player.global_position+Vector3.UP*height,target,1|8,[host.player.get_rid(),bus.get_rid()])
			if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():clear=false;break
		if not clear:continue
		var distance: float=Vector2(local.x-1.58,local.z-z).length()
		if best.is_empty() or distance<float(best.distance_m):best={"door_index":index,"door_world":doorway,"distance_m":distance,"local_feet":local}
	return best

func _at_first_wait(radius: float=4.0) -> bool:
	if not _context_ready() or riding or design.stops.is_empty() or not _board_grounded():return false
	var wait: Vector3=design.stops[0].wait_world
	if host.player.global_position.distance_to(wait)>radius:return false
	var frame: Dictionary=_frame(float(design.stops[0].station_m));var right:=Vector3(-frame.direction.z,0,frame.direction.x)
	var side: float=(host.player.global_position-frame.point).dot(right)
	if side<1.5 or side>5.5:return false
	for height: float in [.70,1.35]:
		var query:=PhysicsRayQueryParameters3D.create(host.player.global_position+Vector3.UP*height,wait+Vector3.UP*height,1|8,[host.player.get_rid(),bus.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():return false
	return true

func can_interact() -> bool:
	if not _context_ready():return false
	if riding:return true
	if not _boarding_candidate().is_empty():return true
	return stop_index==0 and docked_stop<0 and _at_first_wait()

func interaction_distance_m() -> float:
	if riding:return 0.0
	if not loaded or not is_instance_valid(host):return INF
	var candidate: Dictionary=_boarding_candidate()
	if not candidate.is_empty():return float(candidate.distance_m)
	var closest:=INF;var player: Vector3=host.player.global_position
	for row: Dictionary in design.stops:
		closest=minf(closest,player.distance_to(row.wait_world))
	if is_instance_valid(bus):
		for z: float in BOARD_DOOR_Z:
			closest=minf(closest,player.distance_to(bus.to_global(Vector3(1.58,0,z))))
	return closest

func prompt_text() -> String:
	if not _context_ready():return ""
	if riding:
		if bus_state=="doors_open":return "E · 내리기" if not exit_requested else "안전한 하차 공간을 기다리는 중"
		return "E · 다음 정류장 하차 예약" if not exit_requested else "하차 예약됨 · 정차 후 안전하게 내립니다"
	var candidate: Dictionary=_boarding_candidate()
	if not candidate.is_empty():
		if _board_pending:return "문이 열리면 곧 승차합니다 · 잠시 기다려주세요"
		return "E · 도심01 버스 타기 · 앞문과 가운데 문 모두 이용" if bus_state=="doors_open" else "E · 문을 열고 도심01 버스 타기"
	if stop_index==0 and docked_stop<0 and _at_first_wait():return "E · 도심01 승차 대기 취소" if waiting_for_bus else "E · 도심01 승차 대기 · 도착하면 문 앞에서 E"
	for row: Dictionary in design.stops:
		if host.player.global_position.distance_to(row.wait_world)<4.0:
			if row.id==design.stops[-1].id:return "도심01 · 하차 전용 정류장 · 승차는 덕수궁 돌담에서"
			if stop_index>0:return "이번 버스는 출발했습니다 · 승차는 다음 운행 때 가능합니다"
			if not _board_grounded():return "바닥에 착지한 뒤 E · 도심01 버스 이용"
			if docked_stop==0:return "버스 오른쪽 앞문이나 가운데 문으로 다가가 E · 승차"
			return "도심01 · 버스 도착을 기다려주세요"
	if host.player.global_position.distance_to(bus.global_position)<8.0:
		if bus._state=="endpoint_wait" or stop_index>=design.stops.size():return "이번 운행을 마친 버스입니다 · 승차는 덕수궁 돌담 정류장에서"
		if bus._speed_mps>.025:return "주행 중인 버스에는 탈 수 없습니다 · 정류장에서 기다려주세요"
		if docked_stop==design.stops.size()-1:return "하차 전용 정류장입니다 · 승차는 덕수궁 돌담 정류장에서"
		if docked_stop==0:return "버스 오른쪽 앞문이나 가운데 문 앞에서 E · 승차"
	return ""

func handle_interact() -> bool:
	if not can_interact():return false
	if riding:
		exit_requested=true;_event("exit_requested")
		if bus_state=="doors_open":_exit_ride()
		return true
	var candidate: Dictionary=_boarding_candidate()
	if not candidate.is_empty():
		if bus_state=="doors_open":return _board()
		_board_pending=true;_board_pending_s=0.;waiting_for_bus=true
		if bus_state=="closing_doors":bus_state="opening_doors";state_elapsed=door_fraction*float(design.policy.door_animation_s)
		_event("boarding_door_edge_accepted",{"door_index":candidate.door_index});return true
	waiting_for_bus=not waiting_for_bus;_event("wait_requested" if waiting_for_bus else "wait_cancelled");return true

func _board() -> bool:
	if bus_state!="doors_open" or bus._speed_mps>.025:return false
	var candidate: Dictionary=_boarding_candidate()
	if candidate.is_empty():return false
	_last_board_door=int(candidate.door_index);waiting_for_bus=false;_board_pending=false
	state_elapsed=minf(state_elapsed,maxf(0.,float(design.policy.dwell_s)-3.0))
	var player: CharacterBody3D=host.player
	_ride_saved={"player_physics":player.is_physics_processing(),"player_layer":player.collision_layer,"player_mask":player.collision_mask,"avatar_visible":host.exploration_avatar.visible,"rig_distance":host.rig.requested_distance,"rig_max":host.rig.distance_max_m,"rig_yaw":host.rig.yaw,"rig_pitch":host.rig.pitch,"query_exclude":host.rig._query.exclude.duplicate()}
	player.set_facility_control(true);player.set_physics_process(false);player.velocity=Vector3.ZERO
	bus.add_collision_exception_with(player);player.add_collision_exception_with(bus)
	# Retain the native capsule/masks and omit only the bus from the ride camera.
	var exclude: Array[RID]=host.rig._query.exclude.duplicate();exclude.append(bus.get_rid());host.rig._query.exclude=exclude;host.rig.arm.add_excluded_object(bus.get_rid())
	host.exploration_avatar.visible=false;host.rig.distance_max_m=14.;host.rig.requested_distance=10.;host.rig.yaw=bus.global_rotation.y;host.rig.pitch=deg_to_rad(-12.)
	riding=true;exit_requested=false;passenger.visible=true;_attach_passenger(0.);host.rig.snap_to_target_pose();_event("boarded",{"stop_id":design.stops[docked_stop].id,"door_index":_last_board_door,"capsule_layer":player.collision_layer,"capsule_mask":player.collision_mask});return true

func _attach_passenger(delta: float) -> void:
	host.player.global_transform=Transform3D(Basis.IDENTITY,bus.to_global(Vector3(.35,.72,-.6)));host.player.velocity=Vector3.ZERO
	host.player.physics_stepped.emit(delta)

func _safe_exit() -> Dictionary:
	if docked_stop<0 or bus_state!="doors_open" or bus._speed_mps>.025:return {}
	var row: Dictionary=design.stops[docked_stop];var direction: Vector3=_frame(float(row.station_m)).direction;var wait: Vector3=row.wait_world
	for offset: float in [0.,.7,-.7,1.4,-1.4]:
		var requested: Vector3=wait+direction*offset
		var safe: Dictionary=host.interior_visit._safe_external_point(requested)
		if not safe.is_empty():return safe
	return {}

func _restore_ride(external_teleport: bool=false) -> void:
	var player: CharacterBody3D=host.player
	player.collision_layer=int(_ride_saved.player_layer);player.collision_mask=int(_ride_saved.player_mask)
	# CharacterBody transforms assigned in an earlier-priority callback are not
	# necessarily visible to this tick's native motion queries yet. Retain the
	# bus/player exception until physics actually observes the outside capsule.
	# Otherwise the bus's tiny terrain-clearance move can depenetrate sideways
	# from the old seated capsule and permanently leave its source route.
	_collision_release_pending=true;_collision_release_tick=Engine.get_physics_frames()+2
	_release_hold_controls=not external_teleport;_release_player_physics=bool(_ride_saved.player_physics)
	if external_teleport:player.set_facility_control(false)
	player.set_physics_process(_release_player_physics if external_teleport else false);player.require_neutral_input();player.reset_physics_interpolation()
	host.exploration_avatar.visible=bool(_ride_saved.avatar_visible)
	host.rig._query.exclude=_ride_saved.query_exclude;host.rig.arm.remove_excluded_object(bus.get_rid());host.rig.distance_max_m=float(_ride_saved.rig_max);host.rig.requested_distance=float(_ride_saved.rig_distance);host.rig.pitch=float(_ride_saved.rig_pitch)
	riding=false;exit_requested=false;passenger.visible=false;_ride_saved.clear();host.rig.snap_to_target_pose()

func _finish_collision_release() -> void:
	if not _collision_release_pending or riding or Engine.get_physics_frames()<_collision_release_tick:return
	var collider: CollisionShape3D=bus.get_node("CollisionShape");var query:=PhysicsShapeQueryParameters3D.new();query.shape=collider.shape;query.transform=collider.global_transform;query.collision_mask=2;query.exclude=[bus.get_rid()];query.margin=.002
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query,4):
		if hit.collider==host.player:return
	bus.remove_collision_exception_with(host.player);host.player.remove_collision_exception_with(bus)
	_collision_release_pending=false
	if _release_hold_controls:
		host.player.set_facility_control(false);host.player.set_physics_process(_release_player_physics);host.player.require_neutral_input();host.player.reset_physics_interpolation()
	_release_hold_controls=false;_event("passenger_native_collision_restored")

func _exit_ride() -> bool:
	if not riding:return true
	var safe: Dictionary=_safe_exit()
	if safe.is_empty():_event("exit_blocked_capsule_or_support");return false
	host.player.global_transform=Transform3D(Basis.IDENTITY,safe.point);host.player.velocity=Vector3.ZERO;_restore_ride();_event("disembarked",{"stop_id":design.stops[docked_stop].id,"point":safe.point});return true

func cancel_ride_for_teleport() -> void:
	# Caller has already validated AND applied its destination; never choose an
	# unsupported nearby point merely because a menu command was attempted.
	if not riding:return
	_restore_ride(true);_event("ride_cancelled_after_validated_external_teleport")

func _refresh_arrivals() -> void:
	for index: int in range(arrival_labels.size()):
		var text: String="도심01  이번 운행 통과"
		if docked_stop==index:text="도심01  정차 중 · 문 열림" if door_fraction>.95 else "도심01  정차 · 문 작동 중"
		elif stop_index<=index:
			var remaining: float=maxf(0.,float(design.stops[index].station_m)-bus.get_station_m())
			text="도심01  약 %d초 · 게임 운행" % ceili(remaining/4.+maxi(0,index-stop_index)*8.)
		arrival_labels[index].text=text

func viewpoint() -> Dictionary:
	if not loaded:return {}
	return {"point":design.stops[0].wait_world,"toward":_frame(float(design.stops[0].station_m)).point+Vector3.UP*1.2,"id":"T01_GAME-01"}

func snapshot() -> Dictionary:
	var original_ids: Array=[]
	if is_instance_valid(host):
		for old: CharacterBody3D in host.vehicles:original_ids.append(old.get_instance_id())
		for old: CharacterBody3D in host.neighborhood_population.traffic.vehicles:original_ids.append(old.get_instance_id())
	return {"loaded":loaded,"error":load_error,"running":running,"riding":riding,"exit_requested":exit_requested,"waiting_for_bus":waiting_for_bus,"passenger_release_pending":_collision_release_pending,"boarding_pending":_board_pending,"last_board_door_index":_last_board_door,"state":bus_state,"stop_index":stop_index,"docked_stop":docked_stop,"door_fraction":door_fraction,"state_elapsed_s":state_elapsed,"crossing_commit":_crossing_commit.duplicate(true),"bus":bus.snapshot() if is_instance_valid(bus) else {},"route_certificate":route_certificate.duplicate(true),"stop_certificates":stop_certificates.duplicate(true),"stop_count":shelter_nodes.size(),"original_vehicle_ids_unchanged":original_ids==_initial_vehicle_ids,"events":events.duplicate(true),"source_geometry_changed":false,"scope":"One authored blue bus, two source-walk shelters, actual inherited physical drive/brake/full-box sweeps, EXP21 terrain and signal stops. E seated ride; final exit needs positive native support/full capsule clearance. T01/GAME IDs and arrival estimates are game-authored, never real schedules."}
