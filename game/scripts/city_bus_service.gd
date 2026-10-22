extends Node3D
## Three physically continuous buses on one source-road closed game loop. T01/GAME IDs and
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
	var _visual_previous:=Transform3D.IDENTITY
	var _visual_current:=Transform3D.IDENTITY
	var _visual_ready:=false
	var _visual_fraction:=1.0
	var _visual_frames:=0
	func reset_visual_history() -> void:
		var visual: Node3D=get_node("Visual");visual.transform=Transform3D.IDENTITY;visual.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
		_visual_previous=global_transform;_visual_current=global_transform;_visual_ready=true
	func _capture_visual_history() -> void:
		if not _visual_ready:reset_visual_history();return
		_visual_previous=_visual_current;_visual_current=global_transform
	func _render_visual_at(fraction: float) -> void:
		if not _visual_ready:return
		_visual_fraction=clampf(fraction,0.,1.);get_node("Visual").global_transform=_visual_previous.interpolate_with(_visual_current,_visual_fraction);_visual_frames+=1
	func presentation_snapshot() -> Dictionary:
		return {"ready":_visual_ready,"previous":_visual_previous,"current":_visual_current,"rendered":get_node("Visual").global_transform,"fraction":_visual_fraction,"render_frames":_visual_frames,"scope":"Bus-only render transform; native body/collider/route remain at current physics pose."}
	func _find_support() -> void:
		super._find_support()
		var ray:=PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*.7,global_position-Vector3.UP*.7,33,[get_rid()])
		var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit.normal.y>=cos(floor_max_angle):
			_last_support_rid=hit.rid
			if not _support_exclusions.has(_last_support_rid):_support_exclusions.append(_last_support_rid)
			_floor_reason="up_floor_ray";_floor_name=String(hit.collider.name);_floor_path=String(hit.collider.get_path())
		if is_instance_valid(service):
			for rid: RID in service._engineering_support_rids:
				if not _support_exclusions.has(rid):_support_exclusions.append(rid)
		if is_instance_valid(service) and (service._ride_bus==self or service._release_bus==self):_support_exclusions.append(service.host.player.get_rid())
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
	func _physics_process(delta: float) -> void:
		# Render offsets never enter native movement, door/world queries or the seat.
		if service.running:get_node("Visual").transform=Transform3D.IDENTITY
		service._switch_bus(self)
		# Same physical joint, no transform assignment and no recycle grant.
		if _station_m>=_length_m-POINT_EPS_M and Vector2(global_position.x-_points[0].x,global_position.z-_points[0].z).length()<=.0025:
			var before: Vector3=global_position
			_segment=0;_station_m=0.;_cycle_count+=1;_cycle_distance_m=0.;_state="driving"
			service.stop_index=0;service.docked_stop=-1;service.bus_state="approaching";service._crossing_commit.clear()
			service._event("physical_loop_joint",{"position_gap_m":before.distance_to(global_position),"cycle":_cycle_count})
		super._physics_process(delta)
	func _at_endpoint() -> bool:
		return false
	func snapshot() -> Dictionary:
		var result: Dictionary=super.snapshot();var policy: Dictionary=service.motion_policy()
		result.max_speed_limit_mps=policy.maximum_speed_mps;result.accel_mps2=policy.acceleration_mps2;result.decel_mps2=policy.braking_mps2
		result["closed_physical_loop"]=true;result["recycle_enabled"]=false
		return result
	func _advance_vertex() -> bool:
		var remaining: Vector3=_points[_segment+1]-global_position;remaining.y=0.
		if remaining.length()>.0025 or _segment==_points.size()-2:return true
		var next_segment: int=_segment+1;var yaw: float=_heading(_segment_direction(next_segment))
		var overlap: Dictionary=_sweep_obstacle(global_position,Vector3.ZERO,yaw)
		if not overlap.is_empty():_state="waiting_turn";_blocked_reason="next_segment_orientation_occupied:"+String(overlap.get("reason","unknown"));return false
		_segment=next_segment;_record_station()
		if _terrain_enabled:_apply_terrain_orientation()
		else:global_rotation.y=yaw
		return true
	func _choose_step_budget(delta: float) -> float:
		_command_speed_mps=0.;_motion_cap_m=INF;_obstacle={}
		if service.bus_state in ["opening_doors","doors_open","closing_doors"]:
			_state="bus_"+service.bus_state;return 0.
		if _state=="off_route":return 0.
		if _terrain_enabled and _terrain_orientation_blocked:
			_state="waiting_terrain_clearance";_blocked_reason="physical_orientation_clearance_blocked";return 0.
		if not _advance_vertex():return 0.
		var policy: Dictionary=service.motion_policy()
		var cap: float=float(policy.maximum_speed_mps);var brake: float=float(policy.braking_mps2)
		var target: float=service.curve_speed_limit(self,cap,brake)
		_blocked_reason="";_state="driving"
		if not bool(_permission.get("fresh",false)):
			target=0.;_state="waiting_information";_blocked_reason="stale_human_observation"
		if _floor_reason!="up_floor_ray" and not is_on_floor():target=0.;_state="waiting_support";_blocked_reason=_floor_reason
		var limit: Dictionary=service.motion_limit()
		if bool(limit.get("required",false)):
			var remaining: float=maxf(0.,float(limit.distance_m));_motion_cap_m=minf(_motion_cap_m,remaining)
			var safe_speed: float=_braking_speed(remaining,delta,brake)
			if safe_speed<target:
				target=safe_speed;_blocked_reason=String(limit.reason);_state="bus_braking" if _speed_mps>.01 else "bus_waiting"
		var lookahead: float=_speed_mps*.5+_speed_mps*_speed_mps/(2.*brake)+2.
		_obstacle=_corridor_obstacle(lookahead)
		if not _obstacle.is_empty():
			target=0.;_motion_cap_m=minf(_motion_cap_m,maxf(0.,float(_obstacle.get("distance_m",0.))-.05))
			_state="braking_obstacle" if _speed_mps>.01 else "waiting_obstacle";_blocked_reason=String(_obstacle.get("reason","unknown"))
		var change: float=(float(policy.acceleration_mps2) if target>_speed_mps else brake)*delta
		_command_speed_mps=move_toward(_speed_mps,target,change)
		return maxf(0.,minf(_command_speed_mps*delta,_motion_cap_m))

var host: Node3D
var bus: CharacterBody3D
var buses: Array[CharacterBody3D]=[]
var _records: Dictionary={}
var _ride_bus: CharacterBody3D
var _release_bus: CharacterBody3D
var _waiting_stop_index:=-1
var _source_meshes: Array[Dictionary]=[]
var _access_drive_meshes: Array[Dictionary]=[]
var boarding_access_certificates: Array[Dictionary]=[]
var _fleet_elapsed:=0.0
var _engineering_support_rids: Array[RID]=[]
const RECORD_FIELDS := ["bus_state","stop_index","docked_stop","door_fraction","state_elapsed","door_panels","wheels","passenger","_crossing_commit","_board_pending","_board_pending_s","_last_cycle"]
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
	var row: Dictionary={"type":kind,"bus_id":bus.name if is_instance_valid(bus) else "","tick":Engine.get_physics_frames(),"station_m":bus.get_station_m() if is_instance_valid(bus) else 0.}
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
	var ids: Array=design.route.footprint_support_feature_ids
	for mesh: Dictionary in world.meshes:
		if mesh.get("material")=="drive":_access_drive_meshes.append(mesh)
		if mesh.get("material")=="drive" and ids.has(mesh.get("metadata",{}).get("feature_id")):_source_meshes.append(mesh)
	if _source_meshes.size()!=ids.size():return _fail("순환 버스의 연결 원본 차도 면이 없습니다.")
	route_certificate={"accepted":false,"samples":0,"source_feature_ids":ids,"box_m":[2.45,3.0,9.0],"spacing_m":.5,"whole_box_preflight":design.preflight,"terrain_support":"EXP21 existing physical TIN; no bus-only plane"}
	for index: int in range(int(ceil(float(design.route.length_m)/.5))+1):
		var frame: Dictionary=_frame(minf(float(design.route.length_m),index*.5));var side:=Vector3(frame.direction.z,0,-frame.direction.x)
		for x: float in [-HALF_WIDTH,HALF_WIDTH]:
			for z: float in [-HALF_LENGTH,HALF_LENGTH]:
				var point: Vector3=host.city.to_local(frame.point+side*x+frame.direction*z);var found:=false
				for mesh: Dictionary in _source_meshes:
					if _source_contains(Vector2(point.x,point.z),mesh):found=true;break
				if not found:route_certificate.station_m=index*.5;return _fail("순환 차체가 원본 차도 밖에 놓입니다.")
				if not is_finite(host.terrain_surface.ground_y_world(host.city.to_global(point))):return _fail("순환 버스 경로 지면이 없습니다.")
		route_certificate.samples=int(route_certificate.samples)+1
	route_certificate.accepted=true;route_certificate.reason="source_public_drive_union_authored_closed_turns_full_box_and_native_TIN_corners"
	return true

func _store_bus() -> void:
	if not is_instance_valid(bus) or not _records.has(bus.get_instance_id()):return
	var row: Dictionary=_records[bus.get_instance_id()]
	for field: String in RECORD_FIELDS:row[field]=get(field)

func _switch_bus(body: CharacterBody3D) -> void:
	if bus==body:return
	_store_bus();bus=body
	if not _records.has(body.get_instance_id()):return
	var row: Dictionary=_records[body.get_instance_id()]
	for field: String in RECORD_FIELDS:set(field,row[field])

func active_bus() -> CharacterBody3D:
	if riding and is_instance_valid(_ride_bus):_switch_bus(_ride_bus)
	return bus

func bus_singlehead() -> CharacterBody3D:
	return buses[0] if not buses.is_empty() else null

func motion_policy() -> Dictionary:
	var policy: Dictionary={"maximum_speed_mps":design.policy.maximum_speed_mps,"acceleration_mps2":design.policy.acceleration_mps2,"braking_mps2":design.policy.braking_mps2}
	return host.transport_motion_policy("bus",policy) if host.has_method("transport_motion_policy") else policy

func curve_speed_limit(body: CharacterBody3D,cap: float,brake: float) -> float:
	var result:=cap;var lookahead: float=body._speed_mps*body._speed_mps/(2.*brake)+12.
	var radii: Array=design.route.segment_radius_m
	for index: int in range(body._segment,mini(radii.size(),body._segment+int(ceil(lookahead/.20))+3)):
		var distance: float=maxf(0.,float(body._arc[index])-body.get_station_m())
		if distance>lookahead:break
		var curve: float=sqrt(float(design.policy.lateral_acceleration_mps2)*float(radii[index]))
		result=minf(result,sqrt(curve*curve+2.*brake*distance))
	return result

func setup(root_scene: Node3D) -> bool:
	if loaded or not is_instance_valid(root_scene) or not is_inside_tree():return false
	host=root_scene;name="CityBusService";process_mode=Node.PROCESS_MODE_PAUSABLE
	if not is_instance_valid(host.get("terrain_surface")) or not host.terrain_surface.loaded:return _fail("버스는 전체 지형 연결 뒤 준비해야 합니다.")
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not raw is Dictionary or raw.get("schema_version")!=2:return _fail("버스 체험 자료 버전이 다릅니다.")
	design=raw
	for path: String in design.source_hashes:
		if FileAccess.get_sha256(path)!=String(design.source_hashes[path]):return _fail("버스의 원본/지형 자료 해시가 다릅니다: "+path)
	for old: CharacterBody3D in host.vehicles:_initial_vehicle_ids.append(old.get_instance_id())
	for old: CharacterBody3D in host.neighborhood_population.traffic.vehicles:_initial_vehicle_ids.append(old.get_instance_id())
	if not _certify_route():return false
	for row: Dictionary in design.stops:
		if not _build_stop(row):return false
	for support: StaticBody3D in host.neighborhood_population.traffic.supports:
		if support.get_meta("authored_flat_support",false):_engineering_support_rids.append(support.get_rid())
	for member: Dictionary in design.fleet:
		_store_bus();bus=VEHICLE_SCENE.instantiate();bus.set_script(PilotBus);bus.name="BlueLoopBus_"+String(member.id);bus.service=self
		bus.collision_mask=63;bus.floor_snap_length=.45;bus.set_meta("geometry_id",String(member.id)+"_authored_blue_bus")
		var collider: CollisionShape3D=bus.get_node("CollisionShape");var shape:=BoxShape3D.new();shape.size=Vector3(2.45,3.0,9.0);collider.shape=shape;collider.position.y=1.5
		bus.configure(design.route,self,host.city);add_child(bus)
		for support: StaticBody3D in host.neighborhood_population.traffic.supports:
			if support.get_meta("authored_flat_support",false):bus.add_collision_exception_with(support)
		bus.refresh_terrain()
		var station: float=float(member.initial_station_m);var frame: Dictionary=_frame(station)
		while bus._segment<bus._arc.size()-2 and float(bus._arc[bus._segment+1])<station:bus._segment+=1
		bus._station_m=station;bus.global_transform=bus._terrain_pose(frame.point,atan2(-frame.direction.x,-frame.direction.z));bus.reset_physics_interpolation()
		bus_state="approaching";stop_index=0;docked_stop=-1;door_fraction=0.;state_elapsed=0.;door_panels=[];wheels=[];_crossing_commit={};_board_pending=false;_board_pending_s=0.;_last_cycle=0
		while stop_index<design.stops.size() and float(design.stops[stop_index].station_m)<station:stop_index+=1
		_dress_bus();bus.reset_visual_history();buses.append(bus);_records[bus.get_instance_id()]={};_store_bus()
	_switch_bus(buses[0])
	process_physics_priority=2;loaded=true;_event("service_ready");_refresh_arrivals()
	print("CITY_BUS_READY route=T01 actual_closed_loop=true buses=",buses.size()," stops=",design.stops.size()," original_vehicles=",_initial_vehicle_ids.size())
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
		var signal_limit: Dictionary=network.vehicle_stop_distance(String(design.route.segment_source_ids[bus._segment]),bus.global_position,direction,maxf(30.,bus._speed_mps*bus._speed_mps/(2.*float(motion_policy().braking_mps2))+12.))
		var human_wait: bool=bool(host.traffic.human_present) and not String(signal_limit.get("crossing_id","")).is_empty()
		var state: String=String(signal_limit.get("state","uncontrolled"));var line_distance: float=float(signal_limit.get("distance_m",INF))
		if _crossing_commit.is_empty() and not human_wait and not String(signal_limit.get("crossing_id","")).is_empty():
			var available: float=line_distance-HALF_LENGTH-.35
			var brake_room: float=bus._speed_mps*bus._speed_mps/(2.*float(motion_policy().braking_mps2))+bus._speed_mps/float(Engine.physics_ticks_per_second)
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
	var board: Label3D=_label(node,"RouteDiagram",_route_board_text(row),Vector3(.454,1.54,-1.68),.00245,Color(.09,.21,.30));board.rotation.y=-PI/2.
	_box(node,"StopHeader",Vector3(.12,.38,4.6),Vector3(.60,2.35,0),blue)
	var title: Label3D=_label(node,"StopName",String(row.name)+"  "+String(row.id),Vector3(.52,2.35,.15),.0031);title.rotation.y=-PI/2.
	_box(node,"ArrivalDisplay",Vector3(.10,.38,1.8),Vector3(.50,1.95,.65),display)
	var arrival: Label3D=_label(node,"LocalArrivalDisplay","도심01  운행 준비",Vector3(.43,1.95,.65),.00275,Color(.35,1.,.61));arrival.rotation.y=-PI/2.;arrival_labels.append(arrival)
	_box(node,"StopPole",Vector3(.07,2.7,.07),Vector3(-.15,1.35,2.95),frame_mat,true)
	_box(node,"BlueStopSign",Vector3(.09,.70,.57),Vector3(-.15,2.37,2.95),blue)
	var pole: Label3D=_label(node,"StopID","BUS\n"+String(row.id),Vector3(-.21,2.38,2.95),.0023);pole.rotation.y=-PI/2.
	var anchor: Vector3=host.city.to_global(wait);anchor.y=host.terrain_surface.ground_y_world(anchor)+.08
	row["wait_world"]=anchor;row["shelter_world"]=node.global_position
	if not _build_boarding_access(row,frame):return false
	stop_certificates.append({"id":row.id,"source_walk_feature_id":row.source_walk_feature_id,"source_wait_inside":true,"terrain_y_m":node.global_position.y,"authored_id":true});shelter_nodes.append(node);return true

func _boarding_access_floor(requested: Vector3) -> Dictionary:
	# This is an authored pedestrian connector from the retained source footway,
	# not a claim that an OSM centreline is the surveyed kerb. Never cross a drive
	# mesh, private ring or building-entry reservation to reach a bus door.
	var walkers: Node3D=host.neighborhood_population.walkers
	for offset: Vector3 in [Vector3.ZERO,Vector3.RIGHT*.42,Vector3.LEFT*.42,Vector3.FORWARD*.42,Vector3.BACK*.42,Vector3(.297,0,.297),Vector3(-.297,0,.297),Vector3(.297,0,-.297),Vector3(-.297,0,-.297)]:
		var sample: Vector3=requested+offset;var local: Vector3=host.city.to_local(sample);var flat:=Vector2(local.x,local.z)
		if not host.player.free_roam_bounds.grow(-.5).has_point(Vector2(sample.x,sample.z)) or walkers._source_private_contains(flat) or walkers._source_door_near(sample,.42):return {}
		for mesh: Dictionary in _access_drive_meshes:
			if _source_contains(flat,mesh):return {}
	var ground: float=host.terrain_surface.ground_y_world(requested)
	if not is_finite(ground):return {}
	var ray:=PhysicsRayQueryParameters3D.create(Vector3(requested.x,ground+.25,requested.z),Vector3(requested.x,ground-.25,requested.z),1|32,[host.player.get_rid()])
	var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<cos(host.player.floor_max_angle) or absf(hit.position.y-ground)>.03:return {}
	var point:=Vector3(requested.x,ground+.08,requested.z);var collider: CollisionShape3D=host.player.get_node("CollisionShape")
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=collider.shape;query.transform=Transform3D(Basis.IDENTITY,point)*collider.transform;query.collision_mask=1|32;query.exclude=[host.player.get_rid()];query.margin=.003
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return {}
	return {"point":point,"normal":hit.normal}

func _access_strip(parent: Node3D,title: String,points: Array[Vector3],material: Material) -> void:
	# Ground-conforming paint only; no extra collider or raised navigation plane.
	var vertices:=PackedVector3Array()
	for index: int in [0,1,2,0,2,3]:
		var point: Vector3=points[index];point.y=host.terrain_surface.ground_y_world(point)+.066;vertices.append(point)
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var visual:=MeshInstance3D.new();visual.name=title;visual.mesh=mesh;visual.material_override=material;visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(visual)

func _build_boarding_access(row: Dictionary,frame: Dictionary) -> bool:
	var right:=Vector3(-frame.direction.z,0,frame.direction.x);var start: Vector3=row.wait_world;var access: Array[Vector3]=[];var selected_door:=-1;var supported_doors: Array[int]=[]
	for door_index: int in range(BOARD_DOOR_Z.size()):
		var target: Vector3=frame.point+right*2.65-frame.direction*float(BOARD_DOOR_Z[door_index]);var proposal: Array[Vector3]=[];var clear:=true
		var steps: int=maxi(1,int(ceil(Vector2(target.x-start.x,target.z-start.z).length()/.20)))
		for step: int in range(steps+1):
			var safe: Dictionary=_boarding_access_floor(start.lerp(target,float(step)/steps))
			if safe.is_empty():clear=false;break
			proposal.append(safe.point)
		if clear:
			supported_doors.append(door_index)
			if access.is_empty():access=proposal;selected_door=door_index
	if access.is_empty():return _fail("정류장에서 실제 버스 문까지 안전한 보행 연결이 없습니다: "+String(row.id))
	row["boarding_world"]=access.back();row["boarding_door_index"]=selected_door;row["boarding_supported_doors"]=supported_doors;row["boarding_access_world"]=access
	var parent:=Node3D.new();parent.name="BoardingAccess_"+String(row.id);add_child(parent)
	var blue:=_mat(Color(.08,.36,.60),.12);blue.cull_mode=BaseMaterial3D.CULL_DISABLED
	var pale:=_mat(Color(.79,.86,.87));pale.cull_mode=BaseMaterial3D.CULL_DISABLED
	# Short, sparse marks are confined to the pedestrian connector. They do not
	# become another vehicle lane or a false zebra crossing across traffic.
	var direction: Vector3=(access.back()-access.front()).normalized();direction.y=0.;direction=direction.normalized();var side:=Vector3(-direction.z,0,direction.x)
	for step: int in range(2,access.size()-2,8):
		var at: Vector3=access[step]
		_access_strip(parent,"PedestrianDirection",[at-side*.10-direction*.18,at+side*.10-direction*.18,at+side*.10+direction*.18,at-side*.10+direction*.18],blue)
	var boarding: Vector3=access.back();var along: Vector3=frame.direction
	for sign_value: float in [-1.,1.]:
		var edge: Vector3=boarding+right*sign_value*.38
		_access_strip(parent,"BoardingZoneEdge",[edge-right*.035-along*.50,edge+right*.035-along*.50,edge+right*.035+along*.50,edge-right*.035+along*.50],pale)
	var label:=_label(parent,"ActualDoorBoarding","승차 위치 · E\n"+("앞문" if selected_door==0 else "가운데 문"),boarding+Vector3.UP*1.45,.0030,Color(.72,.91,1.));label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	var guide:=_label(parent,"ShelterToDoor","버스 문 · %dm →"%ceili(start.distance_to(boarding)),start+Vector3.UP*1.20,.0028,Color(.82,.93,1.));guide.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	boarding_access_certificates.append({"id":row.id,"source_wait_retained":true,"boarding_world":boarding,"door_index":selected_door,"boarding_supported_doors":supported_doors,"shelter_wait_to_boarding_m":start.distance_to(boarding),"door_side_gap_m":1.07,"native_full_capsule_samples":access.size(),"sample_m":.20,"source_drive_private_and_entry_exclusion":true,"authored_public_TIN_connector":true,"source_geometry_changed":false})
	return true

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
	var front: Label3D=_label(visual,"DestinationLED","도심01  시청 · 북창 · 숭례문 순환",Vector3(0,2.75,-4.526),.0027,Color(.61,1.,.55));front.rotation.y=PI
	var rear: Label3D=_label(visual,"RearRouteLED","도심01",Vector3(0,2.65,4.50),.005,Color(.61,1.,.55))
	for side: float in [-1.,1.]:
		for z: float in [-4.25,-3.5,-2.,-.5,1.,2.5,4.2]:_box(visual,"WindowPillar",Vector3(.06,1.34,.055),Vector3(side*1.216,2.15,z),blue)
		if side<0.:_box(visual,"SilverWaistStripe",Vector3(.035,.11,8.7),Vector3(side*1.226,1.54,0),pale)
		_box(visual,"LowerSkirt",Vector3(.035,.16,8.7),Vector3(side*1.226,.43,0),dark)
		var number: Label3D=_label(visual,"SideRoute","도심01   시청 · 북창 · 숭례문 순환",Vector3(side*1.245,1.16,.55),.0037);number.rotation.y=side*PI/2.
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

func _route_board_text(current: Dictionary) -> String:
	var result: String="도심01 ↻\n"
	for row: Dictionary in design.stops:result+=("● " if row.id==current.id else "○ ")+String(row.name).trim_suffix(" 정류장").replace(" ","")+"\n"
	return result+"게임 순환 · 3대\n실제 노선 아님"

func set_running(enabled: bool) -> void:
	running=enabled
	for body: CharacterBody3D in buses:body.set_running(enabled)

func _physics_process(delta: float) -> void:
	if not loaded:return
	if is_instance_valid(_release_bus):_switch_bus(_release_bus)
	_finish_collision_release()
	if not running:return
	_fleet_elapsed+=delta;_arrival_elapsed+=delta
	for body: CharacterBody3D in buses:
		_switch_bus(body);_tick_bus(delta)
	_store_bus()
	if riding and is_instance_valid(_ride_bus):_switch_bus(_ride_bus);_attach_passenger(delta)
	if _arrival_elapsed>.5:_arrival_elapsed=0.;_refresh_arrivals()
	# Capture after priority-1 native movement and priority-2 door/seat updates.
	for body: CharacterBody3D in buses:body._capture_visual_history()

func _process(_delta: float) -> void:
	if not loaded or not running:return
	var fraction:=clampf(Engine.get_physics_interpolation_fraction(),0.,1.)
	for body: CharacterBody3D in buses:body._render_visual_at(fraction)

func _tick_bus(delta: float) -> void:
	state_elapsed+=delta
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
		if riding and _ride_bus==bus and exit_requested:_exit_ride()
		if state_elapsed>=float(design.policy.dwell_s) and not _doorway_occupied() and _headway_ready():bus_state="closing_doors";state_elapsed=0.;_event("closing_doors")
	elif bus_state=="closing_doors":
		if _doorway_occupied():bus_state="opening_doors";state_elapsed=door_fraction*float(design.policy.door_animation_s);_event("door_safety_reopen")
		else:
			door_fraction=1.-clampf(state_elapsed/float(design.policy.door_animation_s),0.,1.)
			if door_fraction<=0.:stop_index+=1;docked_stop=-1;bus_state="approaching";state_elapsed=0.;_event("departed")
	for part: Dictionary in door_panels:part.node.position=part.closed+Vector3(0,0,float(part.sign)*.48*door_fraction)
	for wheel: Node3D in wheels:wheel.rotate_x(-bus._speed_mps*delta/.43)

func _doorway_occupied() -> bool:
	if not is_instance_valid(bus):return true
	if riding and _ride_bus==bus and exit_requested:return true
	# Keep doors available while a prospective passenger is at either visible
	# door or the adjacent stop. Boarding is still a fresh, explicit E action.
	if not riding and not _boarding_candidate().is_empty():return true
	if waiting_for_bus and docked_stop==_waiting_stop_index and _at_wait(_waiting_stop_index,4.5):return true
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
	if not _context_ready() or riding or docked_stop<0 or bus_state not in ["opening_doors","doors_open","closing_doors"] or bus._speed_mps>.025:return {}
	var local: Vector3=bus.to_local(host.player.global_position)
	if local.x<BOARD_MIN_SIDE_M or local.x>BOARD_MAX_SIDE_M or absf(local.y)>.9 or not _board_grounded():return {}
	var best: Dictionary={}
	for index: int in range(BOARD_DOOR_Z.size()):
		if not design.stops[docked_stop].boarding_supported_doors.has(index):continue
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

func _at_wait(index: int,radius: float=4.) -> bool:
	if not _context_ready() or riding or index<0 or index>=design.stops.size() or not _board_grounded():return false
	var wait: Vector3=design.stops[index].wait_world
	var boarding: Vector3=design.stops[index].boarding_world
	if host.player.global_position.distance_to(boarding)<host.player.global_position.distance_to(wait):wait=boarding
	if host.player.global_position.distance_to(wait)>radius:return false
	var frame: Dictionary=_frame(float(design.stops[index].station_m));var right:=Vector3(-frame.direction.z,0,frame.direction.x)
	if (host.player.global_position-frame.point).dot(right)<1.5:return false
	for height: float in [.70,1.35]:
		var query:=PhysicsRayQueryParameters3D.create(host.player.global_position+Vector3.UP*height,wait+Vector3.UP*height,1|8,[host.player.get_rid(),bus.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():return false
	return true

func _nearest_wait() -> int:
	var best:=-1;var distance:=INF
	for index: int in range(design.stops.size()):
		if _at_wait(index):
			var d: float=minf(host.player.global_position.distance_to(design.stops[index].wait_world),host.player.global_position.distance_to(design.stops[index].boarding_world))
			if d<distance:best=index;distance=d
	return best

func _select_for_player() -> void:
	if riding and is_instance_valid(_ride_bus):_switch_bus(_ride_bus);return
	var selected: CharacterBody3D;var distance:=INF
	for body: CharacterBody3D in buses:
		_switch_bus(body)
		var candidate: Dictionary=_boarding_candidate()
		var d: float=float(candidate.distance_m) if not candidate.is_empty() else INF
		if d<distance:selected=body;distance=d
	if is_instance_valid(selected):_switch_bus(selected)
	elif not buses.is_empty():
		var nearest: CharacterBody3D=buses[0];var d:=INF
		for body: CharacterBody3D in buses:
			var gap: float=body.global_position.distance_to(host.player.global_position)
			if gap<d:nearest=body;d=gap
		_switch_bus(nearest)

func can_interact() -> bool:
	_select_for_player()
	if not _context_ready():return false
	if riding:return true
	if not _boarding_candidate().is_empty():return true
	return _nearest_wait()>=0

func interaction_distance_m() -> float:
	_select_for_player()
	if riding:return 0.0
	if not loaded or not is_instance_valid(host):return INF
	var candidate: Dictionary=_boarding_candidate()
	if not candidate.is_empty():return float(candidate.distance_m)
	var closest:=INF;var player: Vector3=host.player.global_position
	for row: Dictionary in design.stops:
		closest=minf(closest,player.distance_to(row.wait_world))
		closest=minf(closest,player.distance_to(row.boarding_world))
	if is_instance_valid(bus):
		for z: float in BOARD_DOOR_Z:
			closest=minf(closest,player.distance_to(bus.to_global(Vector3(1.58,0,z))))
	return closest

func prompt_text() -> String:
	_select_for_player()
	if not _context_ready():return ""
	if riding:
		if bus_state=="doors_open":return "E · 내리기" if not exit_requested else "안전한 하차 공간을 기다리는 중"
		return "E · 다음 정류장 하차 예약" if not exit_requested else "하차 예약됨 · 정차 후 안전하게 내립니다"
	var candidate: Dictionary=_boarding_candidate()
	if not candidate.is_empty():
		if _board_pending:return "문이 열리면 곧 승차합니다 · 잠시 기다려주세요"
		return "E · 도심01 순환버스 타기 · 앞문/가운데 문" if bus_state=="doors_open" else "E · 문을 열고 도심01 순환버스 타기"
	var wait_index: int=_nearest_wait()
	if wait_index>=0:
		if docked_stop==wait_index:
			var boarding: Vector3=design.stops[wait_index].boarding_world
			return "도심01 정차 중 · 승차 표시까지 %dm · 문 앞에서 E"%ceili(Vector2(host.player.global_position.x-boarding.x,host.player.global_position.z-boarding.z).length())
		return "E · 승차 대기 취소 · 다음 버스 %s" % _eta_text(wait_index) if waiting_for_bus and _waiting_stop_index==wait_index else "E · 도심01 승차 대기 · 다음 버스 %s" % _eta_text(wait_index)
	if is_instance_valid(bus) and host.player.global_position.distance_to(bus.global_position)<8.:
		if bus._speed_mps>.025:return "주행 중인 버스에는 탈 수 없습니다 · 정류장에서 기다려주세요"
		if docked_stop>=0:return "버스 오른쪽 앞문이나 가운데 문 앞에서 E · 승차"
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
	var requested: int=_nearest_wait()
	if requested<0:return false
	waiting_for_bus=not (waiting_for_bus and _waiting_stop_index==requested);_waiting_stop_index=requested;_event("wait_requested" if waiting_for_bus else "wait_cancelled",{"stop_id":design.stops[requested].id});return true

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
	_ride_bus=bus;riding=true;exit_requested=false;passenger.visible=true;_attach_passenger(0.);host.rig.snap_to_target_pose();_event("boarded",{"stop_id":design.stops[docked_stop].id,"door_index":_last_board_door,"capsule_layer":player.collision_layer,"capsule_mask":player.collision_mask});return true

func _attach_passenger(delta: float) -> void:
	host.player.global_transform=Transform3D(Basis.IDENTITY,bus.to_global(Vector3(.35,.72,-.6)));host.player.velocity=Vector3.ZERO
	host.player.physics_stepped.emit(delta)

func _safe_exit() -> Dictionary:
	if docked_stop<0 or bus_state!="doors_open" or bus._speed_mps>.025:return {}
	var row: Dictionary=design.stops[docked_stop];var direction: Vector3=_frame(float(row.station_m)).direction;var wait: Vector3=row.boarding_world
	for offset: float in [0.,.7,-.7,1.4,-1.4]:
		var requested: Vector3=wait+direction*offset
		if _boarding_access_floor(requested).is_empty():continue
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
	_release_bus=bus;_collision_release_pending=true;_collision_release_tick=Engine.get_physics_frames()+2
	_release_hold_controls=not external_teleport;_release_player_physics=bool(_ride_saved.player_physics)
	if external_teleport:player.set_facility_control(false)
	player.set_physics_process(_release_player_physics if external_teleport else false);player.require_neutral_input();player.reset_physics_interpolation()
	host.exploration_avatar.visible=bool(_ride_saved.avatar_visible)
	host.rig._query.exclude=_ride_saved.query_exclude;host.rig.arm.remove_excluded_object(bus.get_rid());host.rig.distance_max_m=float(_ride_saved.rig_max);host.rig.requested_distance=float(_ride_saved.rig_distance);host.rig.pitch=float(_ride_saved.rig_pitch)
	host.rig.yaw=float(_ride_saved.rig_yaw)
	riding=false;_ride_bus=null;exit_requested=false;passenger.visible=false;_ride_saved.clear();host.rig.snap_to_target_pose()

func _finish_collision_release() -> void:
	if not _collision_release_pending or riding or Engine.get_physics_frames()<_collision_release_tick:return
	var collider: CollisionShape3D=bus.get_node("CollisionShape");var query:=PhysicsShapeQueryParameters3D.new();query.shape=collider.shape;query.transform=collider.global_transform;query.collision_mask=2;query.exclude=[bus.get_rid()];query.margin=.002
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query,4):
		if hit.collider==host.player:return
	bus.remove_collision_exception_with(host.player);host.player.remove_collision_exception_with(bus)
	_collision_release_pending=false;_release_bus=null
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
	_switch_bus(_ride_bus)
	_restore_ride(true);_event("ride_cancelled_after_validated_external_teleport")

func _arrival_rows(index: int) -> Array:
	_store_bus();var rows: Array=[];var length: float=design.route.length_m
	for body: CharacterBody3D in buses:
		var row: Dictionary=_records[body.get_instance_id()];var delta_s: float=fposmod(float(design.stops[index].station_m)-body.get_station_m(),length)
		var docked: bool=int(row.docked_stop)==index
		var eta: float=0. if docked else delta_s/maxf(1.,minf(10.,float(motion_policy().maximum_speed_mps)))
		if not docked:
			for stop: Dictionary in design.stops:
				var gap: float=fposmod(float(stop.station_m)-body.get_station_m(),length)
				if gap<delta_s:eta+=float(design.policy.dwell_s)+2.*float(design.policy.door_animation_s)
			if int(row.docked_stop)>=0:eta+=maxf(0.,float(design.policy.dwell_s)-float(row.state_elapsed))
		var delay: String=""
		if String(body._blocked_reason).begins_with("signal_"):
			var network: Variant=host.get("street_network_detail")
			if is_instance_valid(network) and network.loaded:
				var phase: float=fposmod(float(network.elapsed_s),float(network.design.cycle.duration_s))
				if phase>=float(network.design.cycle.vehicle_green_end_s):eta+=float(network.design.cycle.duration_s)-phase;delay="signal"
		elif body._state in ["waiting_obstacle","blocked","waiting_turn"]:delay="traffic"
		rows.append({"delay":delay,"bus_id":body.name,"eta_s":eta,"distance_m":delta_s,"docked":docked,"state":row.bus_state,"delay_possible":true})
	rows.sort_custom(func(a: Dictionary,b: Dictionary):return float(a.eta_s)<float(b.eta_s));return rows

func _eta_text(index: int) -> String:
	var rows: Array=_arrival_rows(index)
	if rows.is_empty():return "운행 준비"
	return "정차 중" if bool(rows[0].docked) else "약 %d초" % ceili(float(rows[0].eta_s))

func _refresh_arrivals() -> void:
	for index: int in range(arrival_labels.size()):
		var rows: Array=_arrival_rows(index);var text: String="도심01 ↻ 3대 · 게임 운행\n"
		if not rows.is_empty():text+="이번 "+_eta_text(index)
		if rows.size()>1:text+="  다음 약 %d초" % ceili(float(rows[1].eta_s))
		arrival_labels[index].text=text

func viewpoint() -> Dictionary:
	if not loaded:return {}
	# Walk-restricted mode retains the original source-footway shortcut rather
	# than silently granting the wider free-exploration connector domain.
	var point: Vector3=design.stops[0].boarding_world if host.player.free_roam_enabled else design.stops[0].wait_world
	return {"point":point,"toward":_frame(float(design.stops[0].station_m)).point+Vector3.UP*1.2,"id":"T01_GAME-01"}

func snapshot() -> Dictionary:
	var original_ids: Array=[]
	if is_instance_valid(host):
		for old: CharacterBody3D in host.vehicles:original_ids.append(old.get_instance_id())
		for old: CharacterBody3D in host.neighborhood_population.traffic.vehicles:original_ids.append(old.get_instance_id())
	return {"loaded":loaded,"error":load_error,"running":running,"riding":riding,"exit_requested":exit_requested,"waiting_for_bus":waiting_for_bus,"passenger_release_pending":_collision_release_pending,"boarding_pending":_board_pending,"last_board_door_index":_last_board_door,"state":bus_state,"stop_index":stop_index,"docked_stop":docked_stop,"door_fraction":door_fraction,"state_elapsed_s":state_elapsed,"crossing_commit":_crossing_commit.duplicate(true),"bus":bus.snapshot() if is_instance_valid(bus) else {},"route_certificate":route_certificate.duplicate(true),"stop_certificates":stop_certificates.duplicate(true),"boarding_access_certificates":boarding_access_certificates.duplicate(true),"stop_count":shelter_nodes.size(),"original_vehicle_ids_unchanged":original_ids==_initial_vehicle_ids,"events":events.duplicate(true),"source_geometry_changed":false,"fleet":_fleet_snapshot(),"bus_count":buses.size(),"motion_policy":motion_policy() if loaded else {},"engineering_support_pair_exceptions":_engineering_support_rids.size(),"physical_loop_no_recycle":true,"scope":"Three source-road physical closed-loop buses; four game-authored stops. Every stop boards/alights. No endpoint recycle or position jump. ETA is an actual local-state estimate with traffic delay, not a live Seoul schedule."}

func _fleet_snapshot() -> Array:
	_store_bus();var result: Array=[]
	for body: CharacterBody3D in buses:
		var state: Dictionary=_records[body.get_instance_id()]
		result.append({"id":body.name,"state":state.bus_state,"stop_index":state.stop_index,"docked_stop":state.docked_stop,"door_fraction":state.door_fraction,"bus":body.snapshot()})
	return result

func _headway_ready() -> bool:
	var target: float=float(design.route.length_m)/maxi(1,buses.size())*.50
	for other: CharacterBody3D in buses:
		if other==bus:continue
		var gap: float=fposmod(other.get_station_m()-bus.get_station_m(),float(design.route.length_m))
		if gap<target:return false
	return true
