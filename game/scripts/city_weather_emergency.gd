extends Node3D
## Authored weather and contained training incidents; no original source mesh,
## material, traffic actor, or pedestrian is replaced or damaged.
class ResponderBody extends CharacterBody3D:
	func _physics_process(_delta: float) -> void:pass
var host: Node3D
var loaded:=false
var load_error:=""
var policy:={"clear_s":150.0,"rain_s":65.0,"first_fire_s":180.0,"between_fires_s":210.0,"extinguish_s":14.0,"engine_mps":7.0,"crew_mps":1.8}
var clock_s:=0.0
var weather_clock_s:=0.0
var weather:="clear"
var rain_intensity:=0.0
var outdoors:=true
var fire_state:="ready"
var state_clock_s:=0.0
var next_fire_s:=180.0
var fires_started:=0
var fires_extinguished:=0
var completed_returns:=0
var water_seconds:=0.0
var engine_distance_m:=0.0
var crew_distance_m:=0.0
var blocked_ticks:=0
var last_block: Dictionary={}
var station: Node3D
var engine: CharacterBody3D
var standby_engine: CharacterBody3D
var _outbound_route: Array[Vector3]=[]
var _crew_target_points: Array[Vector3]=[]
const ENGINE_BOX:=Vector3(2.5,3.05,8.0)
const ENGINE_ENVELOPE:=Vector3(2.7,3.6,8.4)
var firefighters: Array[Dictionary]=[]
var provenance: Dictionary={}
var facility_details: Dictionary={}
var site_audit: Array[Dictionary]=[]
var _site_design: Dictionary={}
var _site_triangles: Array[PackedVector2Array]=[]
var _forecourt_polygon:=PackedVector2Array()
var _crew_homes: Array[Vector3]=[]
var _foundation_depth:=.32
var _facility_rids: Array[RID]=[]
var _native_engine_speed:=0.0
var events: Array[Dictionary]=[]
var _guard: Node3D
var _start:=Vector3.ZERO
var _arrival:=Vector3.ZERO
var _depot:=Vector3.ZERO
var _garage_exit:=Vector3.ZERO
var _engine_waypoint:=0
var _return_route: Array[Vector3]=[]
var _site:=Vector3.ZERO
var _side:=Vector3.RIGHT
var _forward:=Vector3.FORWARD
var _engine_yaw:=0.0
var _fire: Node3D
var _flames: Array[Node3D]=[]
var _smoke: Array[Node3D]=[]
var _water: Array[Node3D]=[]
var _rain: Node3D
var _rain_mesh: MultiMeshInstance3D
const RAIN_STREAK_COUNT:=100
var _puddles: Array[Node3D]=[]
var _weather_baseline: Dictionary={}
var _baseline_time:=""
var _applied_rain:=-1.0
var _wet_update_s:=0.0
var _last_engine:=Vector3.ZERO
var _visuals: Array[Dictionary]=[]

func _event(kind: String) -> void:
	if events.size()>=64:events.pop_front()
	events.append({"event":kind,"clock_s":clock_s,"state":fire_state})
	if not kind.begins_with("weather_"):print("CITY_EMERGENCY_EVENT ",kind," clock_s=",clock_s," state=",fire_state)
func _fail(message: String) -> bool:load_error=message;push_error(message);return false
func setup(scene: Node3D) -> bool:
	if loaded or not is_inside_tree():return false
	host=scene;process_mode=Node.PROCESS_MODE_PAUSABLE;process_physics_priority=1
	_guard=host.get("city_bike_service")
	if not is_instance_valid(_guard) or not _guard.loaded:return _fail("119 안전센터에 필요한 원본 보행·지면이 준비되지 않았습니다.")
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/fire_station_service.json"))
	if not raw is Dictionary or raw.get("schema_version")!=1:return _fail("소방서 외곽 부지 자료가 다릅니다.")
	_site_design=raw
	for path: String in _site_design.source_hashes:
		if FileAccess.get_sha256(path)!=String(_site_design.source_hashes[path]):return _fail("소방서 부지의 원본 출처가 다릅니다.")
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_geometry/world.json"))
	for mesh: Dictionary in world.meshes:
		if String(mesh.id)!=String(_site_design.provenance.source_ground_feature):continue
		for i: int in range(0,mesh.vertices.size(),9):_site_triangles.append(PackedVector2Array([Vector2(mesh.vertices[i],mesh.vertices[i+2]),Vector2(mesh.vertices[i+3],mesh.vertices[i+5]),Vector2(mesh.vertices[i+6],mesh.vertices[i+8])]))
	if _site_triangles.is_empty():return _fail("소방서의 지정 원본 잔디 부지가 없습니다.")
	if not _choose_corridor():print("FIRE_EDGE_SITE_REJECTED ",JSON.stringify(_json(site_audit)));return _fail("119 안전센터의 원본 공공 면·도로 공간을 확보하지 못했습니다.")
	_make_station();_make_engine();_make_crew();_make_fire();_make_rain()
	next_fire_s=float(policy.first_fire_s);loaded=true
	print("CITY_WEATHER_EMERGENCY_READY game_station=1 extra_fireengine=2 firefighters=2 source_changed=false ",JSON.stringify(_json(provenance)))
	return true

func _mat(color: Color,emissive:=false) -> StandardMaterial3D:
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.72
	if color.a<.999:mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive:mat.emission_enabled=true;mat.emission=color;mat.emission_energy_multiplier=1.5
	return mat
func _mesh(parent: Node3D,title: String,shape: Mesh,point: Vector3,mat: Material) -> MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=title;node.mesh=shape;node.position=point;node.material_override=mat;parent.add_child(node);return node
func _box(parent: Node3D,title: String,size: Vector3,point: Vector3,mat: Material) -> MeshInstance3D:
	var shape:=BoxMesh.new();shape.size=size;return _mesh(parent,title,shape,point,mat)
func _round(parent: Node3D,title: String,size: Vector3,point: Vector3,mat: Material) -> MeshInstance3D:
	var shape:=SphereMesh.new();shape.radius=.5;shape.height=1.;shape.radial_segments=10;shape.rings=5
	var node:=_mesh(parent,title,shape,point,mat);node.scale=size;return node
func _tube(parent: Node3D,title: String,a: Vector3,b: Vector3,radius: float,mat: Material) -> MeshInstance3D:
	var shape:=CylinderMesh.new();shape.top_radius=radius;shape.bottom_radius=radius;shape.height=a.distance_to(b);shape.radial_segments=8
	var node:=_mesh(parent,title,shape,(a+b)*.5,mat)
	if a.distance_to(b)>.001:node.basis=Basis(Quaternion(Vector3.UP,(b-a).normalized()))
	return node
func _label(parent: Node3D,text: String,point: Vector3,size:=.0035) -> Label3D:
	var label:=Label3D.new();label.text=text;label.position=point;label.font_size=46;label.pixel_size=size;label.modulate=Color.WHITE;label.outline_size=6;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;parent.add_child(label);return label
func _ground(at: Vector3) -> Dictionary:
	# Query retained terrain, excluding only this module's authored floor/walls.
	# The source ray/support/grade policy is identical to the shared guard.
	var y: float=host.terrain_surface.ground_y_world(at)
	if not is_finite(y):return {}
	var ray:=PhysicsRayQueryParameters3D.create(Vector3(at.x,y+1.2,at.z),Vector3(at.x,y-1.2,at.z),1|32,_facility_rids)
	var hit:=get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<cos(deg_to_rad(float(_guard.design.policy.maximum_grade_degrees))):return {}
	return {"point":Vector3(at.x,hit.position.y,at.z),"normal":hit.normal,"rid":hit.rid}
func _remember_facility_colliders(node: Node) -> void:
	if node is CollisionObject3D:_facility_rids.append(node.get_rid())
	for child: Node in node.get_children():_remember_facility_colliders(child)
func _travel_ground(at: Vector3) -> Dictionary:
	var ground:=_ground(at)
	if ground.is_empty() or not is_instance_valid(station):return ground
	var local:=station.to_local(at)
	if absf(local.x)<=18. and absf(local.z)<=15.01:
		ground.point.y=station.global_position.y
	elif local.z<=-15. and local.z>=-29. and ((local.x>=-8.5 and local.x<=-3.5) or (local.x>=9.8 and local.x<=11.7)):
		var edge: Vector3=station.to_global(Vector3(local.x,0,-29.));var far:=_ground(edge)
		if not far.is_empty():ground.point.y=lerpf(station.global_position.y,far.point.y+.025,clampf((-local.z-15.)/14.,0.,1.))
	return ground
func _on_site_grass(at: Vector3) -> bool:
	var local: Vector3=host.city.to_local(at);var flat:=Vector2(local.x,local.z)
	for triangle: PackedVector2Array in _site_triangles:
		if Geometry2D.is_point_in_polygon(flat,triangle):return true
	return false
func _public(at: Vector3,walk_only:=false) -> bool:
	var local: Vector3=host.city.to_local(at);var flat:=Vector2(local.x,local.z)
	if _guard._source_allowed(at):return _guard._walk_index.contains(flat) if walk_only else true
	# One explicitly authored, source-grounded outskirts parcel. This never
	# grants access to other grass, private plots, roofs or unsupported TIN.
	var authored_forecourt: bool=_forecourt_polygon.size()>=3 and Geometry2D.is_point_in_polygon(Vector2(at.x,at.z),_forecourt_polygon)
	if not (_on_site_grass(at) or authored_forecourt) or _guard._private_index.contains(flat) or not host.player.free_roam_bounds.grow(-1.1).has_point(Vector2(at.x,at.z)):return false
	for door: Vector3 in _guard._doors:
		if Vector2(at.x-door.x,at.z-door.z).length()<2.:return false
	return true
func _supported(at: Vector3,radius: float,walk_only:=false) -> bool:
	if not _retained_tree_clear(at,radius):return false
	for offset: Vector3 in [Vector3.ZERO,Vector3.RIGHT*radius,Vector3.LEFT*radius,Vector3.FORWARD*radius,Vector3.BACK*radius]:
		if not _public(at+offset,walk_only) or _ground(at+offset).is_empty():return false
	return true
func _retained_tree_clear(at: Vector3,radius: float) -> bool:
	# Tree colliders are distance-budgeted by their existing controller. Keep
	# their actual retained trunks reserved even before that collider wakes.
	for tree: Dictionary in host.neighborhood_greenery.trees:
		if Vector2(at.x-tree.point.x,at.z-tree.point.z).length()<radius+.17+.06:return false
	return true
func _retained_tree_box_clear(at: Vector3,yaw: float,size: Vector3) -> bool:
	var inverse:=Transform3D(Basis(Vector3.UP,yaw),at).affine_inverse()
	for tree: Dictionary in host.neighborhood_greenery.trees:
		var local: Vector3=inverse*tree.point
		if absf(local.x)<size.x*.5+.23 and absf(local.z)<size.z*.5+.23:return false
	return true
func _box_pose(at: Vector3,yaw: float,size: Vector3) -> Transform3D:
	var basis:=Basis(Vector3.UP,yaw);var high:=-INF
	for x: float in [-size.x*.5,size.x*.5]:
		for z: float in [-size.z*.5,size.z*.5]:
			var sample: Dictionary=_travel_ground(at+basis*Vector3(x,0,z))
			if sample.is_empty():return Transform3D(Basis.IDENTITY,Vector3.INF)
			high=maxf(high,sample.point.y)
	return Transform3D(basis,Vector3(at.x,high+.10,at.z))
func _static_clear(at: Vector3,yaw: float,size: Vector3,extra_mask:=0) -> bool:
	if not _retained_tree_box_clear(at,yaw,size):return false
	var pose:=_box_pose(at,yaw,size)
	if not pose.origin.is_finite():return false
	var query:=PhysicsShapeQueryParameters3D.new();var box:=BoxShape3D.new();box.size=size;query.shape=box;query.collision_mask=1|32|extra_mask;query.margin=.008;query.transform=pose;query.transform.origin+=Vector3.UP*(size.y*.5+.04)
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
func _path_safe(a: Vector3,b: Vector3,radius: float,walk_only:=false) -> bool:
	var n:=maxi(1,ceili(a.distance_to(b)/.7))
	for i: int in range(n+1):
		var at:=a.lerp(b,float(i)/n)
		if not _supported(at,radius,walk_only):return false
		if not _static_clear(at,atan2(-(b-a).x,-(b-a).z),Vector3(radius*2.,1.9,radius*2.)):return false
	return true
func _rectangle_supported(at: Vector3,yaw: float,width: float,length: float,walk_only:=false) -> bool:
	var basis:=Basis(Vector3.UP,yaw)
	for x: float in [-width*.5,0.,width*.5]:
		for z: float in [-length*.5,0.,length*.5]:
			var point:=at+basis*Vector3(x,0,z)
			if not _public(point,walk_only) or _ground(point).is_empty():return false
	return true
func _truck_path_safe(a: Vector3,b: Vector3) -> bool:
	var n:=maxi(1,ceili(a.distance_to(b)/.7));var yaw:=atan2(-(b-a).x,-(b-a).z)
	for i: int in range(n+1):
		var point:=a.lerp(b,float(i)/n)
		if not _rectangle_supported(point,yaw,ENGINE_ENVELOPE.x,ENGINE_ENVELOPE.z) or not _static_clear(point,yaw,ENGINE_ENVELOPE):return false
	return true
func _near_crossing(at: Vector3,radius: float) -> bool:
	var local: Vector3=host.city.to_local(at);var point:=Vector2(local.x,local.z)
	for crossing: Dictionary in host.street_network_detail.design.get("crossings",[]):
		for i: int in range(crossing.xz.size()-1):
			var a:=Vector2(crossing.xz[i][0],crossing.xz[i][1]);var b:=Vector2(crossing.xz[i+1][0],crossing.xz[i+1][1])
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b))<radius+float(crossing.get("width_m",4.4))*.5:return true
	return false
func _walk_corridors_clear(center: Vector3,yaw: float) -> bool:
	var inverse:=Transform3D(Basis(Vector3.UP,yaw),center).affine_inverse();var reserved:=Rect2(Vector2(-20.,-17.),Vector2(40.,34.))
	var routes: Array=host.city.public_data.routes.duplicate();routes.append_array(host.neighborhood_population.design.routes)
	var corners: Array[Vector2]=[reserved.position,Vector2(reserved.end.x,reserved.position.y),reserved.end,Vector2(reserved.position.x,reserved.end.y)]
	for route: Dictionary in routes:
		for i: int in range(route.xz.size()-1):
			var a3: Vector3=inverse*host.city.to_global(Vector3(route.xz[i][0],0,route.xz[i][1]));var b3: Vector3=inverse*host.city.to_global(Vector3(route.xz[i+1][0],0,route.xz[i+1][1]));var a:=Vector2(a3.x,a3.z);var b:=Vector2(b3.x,b3.z)
			if reserved.has_point(a) or reserved.has_point(b):return false
			for edge: int in range(4):
				if Geometry2D.segment_intersects_segment(a,b,corners[edge],corners[(edge+1)%4])!=null:return false
	return true
func _curve_route(start: Vector3,c1: Vector3,c2: Vector3,join: Vector3,arrival: Vector3,depot: Vector3) -> Array[Vector3]:
	var route: Array[Vector3]=[]
	var n:=ceili(depot.distance_to(start)/.7)
	for i: int in range(1,n+1):route.append(depot.lerp(start,float(i)/n))
	for i: int in range(1,33):route.append(start.bezier_interpolate(c1,c2,join,float(i)/32.))
	n=ceili(join.distance_to(arrival)/.7)
	for i: int in range(1,n+1):route.append(join.lerp(arrival,float(i)/n))
	return route
func _choose_corridor() -> bool:
	var source_segment: Array=_site_design.response.source_segment_xz
	var first:=Vector3(source_segment[0][0],0,source_segment[0][1]);var last:=Vector3(source_segment[1][0],0,source_segment[1][1]);var forward: Vector3=(last-first).normalized();var side:=Vector3(-forward.z,0,forward.x)
	for candidate: Array in _site_design.facility.candidate_centers_xz:
		var center: Vector3=host.city.to_global(Vector3(candidate[0],0,candidate[1]));var yaw: float=_site_design.facility.yaw_radians;var basis:=Basis(Vector3.UP,yaw);var record: Dictionary={"center":center,"source_ground_feature":_site_design.provenance.source_ground_feature,"rejection":""}
		_forecourt_polygon.clear()
		for point: Array in _site_design.facility.authored_campus_xz:_forecourt_polygon.append(Vector2(float(point[0]),float(point[1])))
		var low:=INF;var high:=-INF;var footprint_ok:=true
		for x: float in range(-18,19,2):
			for z: float in range(-15,16,2):
				var point:=center+basis*Vector3(x,0,z);var floor:=_ground(point)
				if not _public(point,true) or floor.is_empty():footprint_ok=false;continue
				low=minf(low,floor.point.y);high=maxf(high,floor.point.y)
		if not footprint_ok or not _walk_corridors_clear(center,yaw):record.rejection="bounded_campus_private_support_or_existing_walk_corridor";site_audit.append(record);continue
		if not _static_clear(center,yaw,Vector3(36.5,13.7,30.5),4|8):record.rejection="full_native_building_envelope";site_audit.append(record);continue
		var depot:=center+basis*Vector3(-6.,0,-8.);var exit:=center+basis*Vector3(-6.,0,-24.)
		var curve_start:=Vector3(_site_design.response.curve_start_xz[0],0,_site_design.response.curve_start_xz[1]);var c1:=Vector3(_site_design.response.curve_control_1_xz[0],0,_site_design.response.curve_control_1_xz[1]);var c2:=Vector3(_site_design.response.curve_control_2_xz[0],0,_site_design.response.curve_control_2_xz[1]);var join:=Vector3(_site_design.response.road_join_xz[0],0,_site_design.response.road_join_xz[1]);var arrival:=join+forward*float(_site_design.response.outbound_road_m)
		var route:=_curve_route(curve_start,c1,c2,join,arrival,depot);var route_ok:=true;var previous:=depot
		for point: Vector3 in route:
			if not _truck_path_safe(previous,point):route_ok=false;record["route_rejection_at"]=point;break
			previous=point
		if not route_ok:record.rejection="full_size_truck_curve_source_support_or_native_route";site_audit.append(record);continue
		var incident:=Vector3(_site_design.response.incident_xz[0],0,_site_design.response.incident_xz[1])
		if not _rectangle_supported(incident,0.,2.6,2.6,true) or not _static_clear(incident,0.,Vector3(2.6,3.8,2.6),4|8):record.rejection="contained_incident_whole_footprint";site_audit.append(record);continue
		var homes: Array[Vector3]=[];var targets: Array[Vector3]=[];var crew_safe:=true
		for i: int in range(2):
			var home:=Vector3(_site_design.response.crew_home_xz[i][0],0,_site_design.response.crew_home_xz[i][1]);var target:=Vector3(_site_design.response.crew_target_xz[i][0],0,_site_design.response.crew_target_xz[i][1])
			if not _path_safe(home,target,.30):crew_safe=false
			homes.append(_ground(home).point+Vector3.UP*.05 if not _ground(home).is_empty() else home);targets.append(target)
		if not crew_safe:record.rejection="two_separate_firefighter_capsule_lanes";site_audit.append(record);continue
		_start=_ground(join).point;_arrival=_ground(arrival).point;_site=_ground(incident).point;_side=side;_forward=forward;_engine_yaw=yaw;_depot=_ground(depot).point;_garage_exit=_ground(exit).point;_crew_homes=homes;_crew_target_points=targets;_foundation_depth=maxf(.32,high-low+.20)
		_outbound_route=route;_return_route=route.duplicate();_return_route.reverse();_return_route.remove_at(0);_return_route.append(_depot)
		station=Node3D.new();station.name="Game119SafetyStation";add_child(station);station.global_position=Vector3(center.x,high+.035,center.z);station.rotation.y=yaw
		record["accepted"]=true;site_audit.append(record)
		provenance={"road_route":_site_design.response.source_road_route,"road_source_binding":_site_design.response.source_feature_id,"road_start":_start,"road_arrival":_arrival,"return_route_points":_return_route.size(),"return_route_start":_return_route[0],"return_route_end":_return_route[-1],"garage_exit":_garage_exit,"station":station.global_position,"incident_site":_site,"source_ground_feature":_site_design.provenance.source_ground_feature,"source_refs":_site_design.provenance.source_refs,"bounded_authored_campus_xz":_site_design.facility.authored_campus_xz,"whole_building_footprint_on_named_source_grass":false,"whole_building_on_non_private_supported_game_campus":true,"existing_walk_corridors_clearance_m":2.,"source_support_verified":true,"source_geometry_changed":false,"real_station_location_claim":false,"game_rule":_site_design.response.return_rule}
		return true
	return false
func _make_station() -> void:
	facility_details=preload("res://scripts/fire_station_facility.gd").new().build(self,station)
	_make_station_ramp();_remember_facility_colliders(station);_make_forecourt_skin()
func _make_forecourt_skin() -> void:
	# A thin TIN-following game forecourt, only on this authored campus. Keep
	# every original sidewalk and roadway visible; this adds no collider.
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array()
	for x: float in range(-18,18,2):
		for z: float in range(-29,-15,2):
			var points: Array[Vector3]=[];var allowed:=true
			for offset: Vector2 in [Vector2(0,0),Vector2(2,0),Vector2(0,2),Vector2(2,2)]:
				var world: Vector3=station.to_global(Vector3(x+offset.x,0,z+offset.y));var flat:=Vector2(world.x,world.z);var floor:=_travel_ground(world)
				if not _public(world,true) or floor.is_empty() or _guard._road_index.contains(flat) or _guard._walk_index.contains(flat):allowed=false;break
				points.append(station.to_local(floor.point+Vector3.UP*.035))
			if not allowed:continue
			for i: int in [0,2,1,1,2,3]:vertices.append(points[i]);normals.append(Vector3.UP)
	if vertices.is_empty():return
	var mesh:=ArrayMesh.new();var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_mesh(station,"BoundedTINForecourtPaving",mesh,Vector3.ZERO,_mat(Color(.25,.29,.31)))
	facility_details["forecourt_triangles"]=vertices.size()/3
func _make_station_ramp() -> void:
	# New ramps join this authored floor to retained TIN; no source geometry is
	# raised, cut or removed. Both ramps stay within the protected game campus.
	for span: Vector2 in [Vector2(-8.5,-3.5),Vector2(9.8,11.7)]:
		var points: Array[Vector3]=[]
		for local: Vector3 in [Vector3(span.x,0,-15.01),Vector3(span.y,0,-15.01),Vector3(span.x,0,-29.),Vector3(span.y,0,-29.)]:
			if local.z==-29.:
				var floor:=_ground(station.to_global(local));local.y=floor.point.y-station.global_position.y+.025 if not floor.is_empty() else 0.
			points.append(local)
		var faces:=PackedVector3Array([points[0],points[2],points[1],points[1],points[2],points[3]]);var mesh:=ArrayMesh.new();var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=faces;arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP]);mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var visual:=_mesh(station,"AuthoredAccessibleApronRamp",mesh,Vector3.ZERO,_mat(Color(.30,.33,.33)))
		var body:=StaticBody3D.new();body.name="AuthoredGarageRampCollision";body.collision_layer=32;var collider:=CollisionShape3D.new();var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces);collider.shape=shape;body.add_child(collider);visual.add_child(body)
func _make_engine_body(title: String,depot: Vector3) -> CharacterBody3D:
	var body:=ResponderBody.new();body.name=title;body.collision_layer=8;body.collision_mask=1|2|4|8|32
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=ENGINE_BOX;shape.shape=box;shape.position.y=1.75;body.add_child(shape);add_child(body)
	body.global_transform=_box_pose(depot,_engine_yaw,ENGINE_ENVELOPE)
	var visual:=Node3D.new();visual.name="Visual";body.add_child(visual)
	var red:=_mat(Color(.76,.045,.025));var silver:=_mat(Color(.64,.68,.67));var dark:=_mat(Color(.035,.075,.10));var yellow:=_mat(Color(1.,.85,.15))
	_box(visual,"FullSizePumpChassis",Vector3(2.45,.65,7.8),Vector3(0,.95,0),dark)
	_box(visual,"PumpCabin",Vector3(2.45,2.20,2.50),Vector3(0,1.90,-2.65),red)
	_box(visual,"Windshield",Vector3(2.12,.88,.05),Vector3(0,2.40,-3.93),dark)
	_box(visual,"FrontGrille",Vector3(1.65,.42,.07),Vector3(0,1.20,-3.94),silver)
	_box(visual,"FrontBumper",Vector3(2.5,.28,.25),Vector3(0,.70,-3.92),silver)
	_box(visual,"WaterTankEquipmentBody",Vector3(2.46,2.10,5.0),Vector3(0,1.85,1.05),red)
	for side: float in [-1.,1.]:
		for z: float in [-.85,.65,2.15]:
			_box(visual,"EquipmentRollerDoor",Vector3(.055,1.40,1.35),Vector3(side*1.25,1.85,z),silver)
			for y: float in [1.3,1.65,2.,2.35]:_box(visual,"EquipmentDoorSlat",Vector3(.065,.025,1.30),Vector3(side*1.29,y,z),dark)
		_box(visual,"KoreanSafetyStripe",Vector3(.04,.18,7.1),Vector3(side*1.28,1.02,-.1),yellow)
		_box(visual,"CabSideWindow",Vector3(.05,.80,1.65),Vector3(side*1.25,2.4,-2.7),dark)
		for z: float in [-2.65,2.50]:
			var wheel:=CylinderMesh.new();wheel.top_radius=.53;wheel.bottom_radius=.53;wheel.height=.26;wheel.radial_segments=16
			var node:=_mesh(visual,"Wheel",wheel,Vector3(side*1.24,.55,z),dark);node.rotation.z=PI*.5
			var hub:=CylinderMesh.new();hub.top_radius=.24;hub.bottom_radius=.24;hub.height=.28;hub.radial_segments=12;var hub_node:=_mesh(visual,"WheelHub",hub,Vector3(side*1.25,.55,z),silver);hub_node.rotation.z=PI*.5
	for x: float in [-.82,.82]:_box(visual,"EmergencyBeacon",Vector3(.52,.22,.35),Vector3(x,3.13,-2.55),_mat(Color(1.,.08,.03),true))
	_box(visual,"RoofLadder",Vector3(.9,.16,4.6),Vector3(0,3.03,.95),silver)
	for z: float in [-1.,-.4,.2,.8,1.4,2.,2.6]:_box(visual,"LadderRung",Vector3(.85,.07,.10),Vector3(0,3.14,z),dark)
	var label:=_label(visual,"119  소방",Vector3(0,1.4,-4.08),.0035);label.billboard=BaseMaterial3D.BILLBOARD_DISABLED;label.rotation.y=PI
	_visuals.append({"body":body,"visual":visual,"previous":body.global_transform,"current":body.global_transform})
	return body
func _make_engine() -> void:
	engine=_make_engine_body("Extra119FireEngine",_depot)
	standby_engine=_make_engine_body("Standby119PumpEngine",station.to_global(Vector3(0,0,-8.)))
	_last_engine=engine.global_position
func _make_crew() -> void:
	var orange:=_mat(Color(.87,.29,.045));var dark:=_mat(Color(.10,.12,.13));var trim:=_mat(Color(.96,.92,.28));var skin:=_mat(Color(.75,.55,.40))
	for i: int in range(2):
		var body:=ResponderBody.new();body.name="Firefighter"+str(i+1);body.collision_layer=4;body.collision_mask=1|2|4|8|32
		var capsule:=CapsuleShape3D.new();capsule.radius=.25;capsule.height=1.72;var shape:=CollisionShape3D.new();shape.shape=capsule;shape.position.y=.90;body.add_child(shape);add_child(body)
		var home: Vector3=_crew_homes[i];var floor:=_ground(home);body.global_position=floor.point+Vector3.UP*.05 if not floor.is_empty() else home
		var visual:=Node3D.new();visual.name="Visual";body.add_child(visual)
		_box(visual,"FireJacket",Vector3(.45,.55,.27),Vector3(0,1.15,0),orange);_box(visual,"ReflectiveBand",Vector3(.46,.09,.28),Vector3(0,1.1,0),trim)
		_round(visual,"Face",Vector3(.25,.29,.23),Vector3(0,1.63,-.02),skin);_round(visual,"Helmet",Vector3(.37,.22,.34),Vector3(0,1.78,0),trim)
		var legs: Array[Node3D]=[]
		for side: float in [-1.,1.]:
			legs.append(_box(visual,"BootLeg",Vector3(.18,.69,.22),Vector3(side*.12,.48,0),dark))
			_box(visual,"Sleeve",Vector3(.16,.52,.20),Vector3(side*.30,1.13,-.07),orange)
		_label(visual,"소방",Vector3(0,2.1,0),.0019)
		firefighters.append({"body":body,"home":body.global_position,"legs":legs,"moving":false})
		_visuals.append({"body":body,"visual":visual,"previous":body.global_transform,"current":body.global_transform})
func _make_fire() -> void:
	_fire=Node3D.new();_fire.name="ContainedAuthoredRoadsideFire";add_child(_fire);_fire.global_position=_site
	var dark:=_mat(Color(.16,.17,.16));var orange:=_mat(Color(1.,.20,.015),true);var yellow:=_mat(Color(1.,.65,.035),true);var grey:=_mat(Color(.23,.25,.27,.52))
	for x: float in [-.4,.4]:_box(_fire,"ContainedBin",Vector3(.68,.65,.8),Vector3(x,.33,0),dark)
	for i: int in range(7):_flames.append(_round(_fire,"Flame",Vector3(.38,1.5,.38),Vector3(sin(i*2.1)*.50,.9,cos(i*2.1)*.30),orange if i%2 else yellow))
	for i: int in range(6):_smoke.append(_round(_fire,"Smoke",Vector3(.7,.7,.7),Vector3(0,2.+float(i)*.5,0),grey))
	_label(_fire,"게임 화재 · 접근 주의",Vector3(0,3.,0),.0024);_fire.visible=false
	for i: int in range(2):
		var node:=_tube(self,"WaterJet",Vector3.ZERO,Vector3.UP,.045,_mat(Color(.55,.80,.98,.74),true));node.visible=false;_water.append(node)
func _make_rain() -> void:
	_rain=Node3D.new();_rain.name="LocalOutdoorRain";add_child(_rain)
	var mat:=_mat(Color(.62,.78,.90,.44));mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var shape:=BoxMesh.new();shape.size=Vector3(.012,.72,.012);shape.material=mat
	var instances:=MultiMesh.new();instances.transform_format=MultiMesh.TRANSFORM_3D;instances.mesh=shape;instances.instance_count=RAIN_STREAK_COUNT
	_rain_mesh=MultiMeshInstance3D.new();_rain_mesh.name="BatchedRainStreaks";_rain_mesh.multimesh=instances;_rain_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;_rain.add_child(_rain_mesh)
	for i: int in range(12):
		var node:=_round(self,"WetGroundSplash",Vector3(.5,.008,.5),Vector3.ZERO,_mat(Color(.21,.30,.35,.30)));node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.visible=false;_puddles.append(node)
	_rain.visible=false

func _start_fire() -> void:
	if fire_state!="ready":return
	fire_state="dispatch";state_clock_s=0.;water_seconds=0.;_engine_waypoint=0;fires_started+=1;_fire.visible=true;_event("fire_started_dispatch")
func manual_game_demo() -> bool:
	if not loaded:return false
	weather="rain";weather_clock_s=0.;_event("rain_started_manual_game_control");_start_fire();return true
func _weather_tick(delta: float) -> void:
	weather_clock_s+=delta
	var duration: float=policy.rain_s if weather=="rain" else policy.clear_s
	if weather_clock_s>=duration:
		weather_clock_s=0.;weather="clear" if weather=="rain" else "rain";_event("weather_"+weather)
	rain_intensity=move_toward(rain_intensity,1. if weather=="rain" else 0.,delta*.35)
	var profile: String=host.get("time_id") if host.get("time_id")!=null else "day"
	var atmosphere: Node3D=host.photo_atmosphere
	if profile!=_baseline_time or _weather_baseline.is_empty():
		atmosphere.set_time_profile(profile);_baseline_time=profile
		_weather_baseline={"energy":atmosphere.sun.light_energy,"ambient":atmosphere.environment.ambient_light_energy,"fog":atmosphere.environment.fog_density,"sky":atmosphere.sky_material.sky_top_color,"horizon":atmosphere.sky_material.sky_horizon_color}
		_applied_rain=-1.
	if not is_equal_approx(_applied_rain,rain_intensity):
		# Avoid regenerating an unchanged procedural sky every physics tick.
		_applied_rain=rain_intensity
		atmosphere.sun.light_energy=float(_weather_baseline.energy)*lerpf(1.,.62,rain_intensity)
		atmosphere.environment.ambient_light_energy=float(_weather_baseline.ambient)*lerpf(1.,.87,rain_intensity)
		atmosphere.environment.fog_density=float(_weather_baseline.fog)+rain_intensity*.00035
		atmosphere.sky_material.sky_top_color=Color(_weather_baseline.sky).lerp(Color(.20,.24,.29) if profile!="night" else Color(.035,.045,.065),rain_intensity*.65)
		atmosphere.sky_material.sky_horizon_color=Color(_weather_baseline.horizon).lerp(Color(.43,.46,.49) if profile!="night" else Color(.07,.08,.10),rain_intensity*.65)
	# Weather clocks continue while visiting interiors, but rain never appears
	# in their separate cells or beneath a roof over the player's head.
	outdoors=not host.player.interior_active
	if outdoors:
		var at: Vector3=host.player.global_position;var ray:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*1.8,at+Vector3.UP*24.,1|32)
		outdoors=get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
	_rain.visible=outdoors and rain_intensity>.02
	if not outdoors:
		for puddle: Node3D in _puddles:puddle.visible=false
	_wet_update_s+=delta
	if _wet_update_s>=.45:
		_wet_update_s=0.
		for i: int in range(_puddles.size()):
			var angle:=float(i)*2.39996;var at: Vector3=host.player.global_position+Vector3(cos(angle),0,sin(angle))*(2.+float(i%4)*1.4);var ground:=_ground(at)
			_puddles[i].visible=outdoors and rain_intensity>.10 and not ground.is_empty()
			if not ground.is_empty():_puddles[i].global_position=ground.point+Vector3.UP*.025

func _move_body(body: CharacterBody3D,target: Vector3,speed: float,delta: float,truck:=false) -> bool:
	var diff:=target-body.global_position;diff.y=0.
	if diff.length()<.14:return true
	var motion:=diff.normalized()*minf(diff.length(),speed*delta)
	var proposed:=body.global_position+motion
	if not _supported(proposed,1.35 if truck else .27):blocked_ticks+=1;return false
	var floor: Dictionary=_travel_ground(proposed)
	if floor.is_empty():blocked_ticks+=1;return false
	if truck:
		var yaw:=atan2(-diff.x,-diff.z)
		# Garage arrival is a reverse manoeuvre through the same opening.
		if fire_state=="engine_return":yaw+=PI
		if not _rectangle_supported(proposed,yaw,ENGINE_ENVELOPE.x,ENGINE_ENVELOPE.z) or not _static_clear(proposed,yaw,ENGINE_BOX):blocked_ticks+=1;return false
		_engine_yaw=yaw;body.rotation.y=yaw
		var pose:=_box_pose(proposed,yaw,ENGINE_ENVELOPE)
		if not pose.origin.is_finite():return false
		proposed.y=pose.origin.y
	else:proposed.y=floor.point.y+.05
	var before:=body.global_position;var hit:=body.move_and_collide(proposed-before,false,.001,false)
	var traveled:=body.global_position.distance_to(before)
	if truck:engine_distance_m+=traveled
	else:crew_distance_m+=traveled;body.rotation.y=atan2(-diff.x,-diff.z)
	if hit!=null and traveled<.001:
		blocked_ticks+=1;last_block={"responder":String(body.name),"collider":String(hit.get_collider().get_path()),"at":body.global_position,"target":target}
	return Vector2(body.global_position.x-target.x,body.global_position.z-target.z).length()<.14
func _crew_targets(arrival:=true) -> Array[Vector3]:
	var out: Array[Vector3]=[]
	for i: int in range(2):out.append(_crew_target_points[i] if arrival else firefighters[i].home)
	return out
func _fire_tick(delta: float) -> void:
	state_clock_s+=delta
	match fire_state:
		"ready":
			if clock_s>=next_fire_s:_start_fire()
		"dispatch":
			# Crew remain visible in the station, then follow the engine on foot
			# to the contained incident. No responder is teleported into position.
			var targets: Array[Vector3]=_outbound_route
			if _move_body(engine,targets[_engine_waypoint],float(policy.engine_mps),delta,true):
				_engine_waypoint+=1
				if _engine_waypoint==targets.size():fire_state="crew_approach";state_clock_s=0.;_event("fireengine_arrived")
		"crew_approach":
			var ready:=true;var targets:=_crew_targets()
			for i: int in range(2):
				firefighters[i].moving=not _move_body(firefighters[i].body,targets[i],float(policy.crew_mps),delta);ready=ready and not firefighters[i].moving
			if ready:fire_state="extinguishing";state_clock_s=0.;_event("water_started")
		"extinguishing":
			water_seconds+=delta
			if state_clock_s>=float(policy.extinguish_s):
				_fire.visible=false;fires_extinguished+=1;fire_state="crew_return";state_clock_s=0.;_event("fire_extinguished")
		"crew_return":
			var ready:=true
			for row: Dictionary in firefighters:row.moving=not _move_body(row.body,row.home,float(policy.crew_mps),delta);ready=ready and not row.moving
			if ready:fire_state="engine_return";state_clock_s=0.;_engine_waypoint=0;_event("firefighters_returned")
		"engine_return":
			if _move_body(engine,_return_route[_engine_waypoint],float(policy.engine_mps),delta,true):
				_engine_waypoint+=1
				if _engine_waypoint==_return_route.size():fire_state="ready";state_clock_s=0.;completed_returns+=1;next_fire_s=clock_s+float(policy.between_fires_s);_event("fireengine_returned")
	for row: Dictionary in firefighters:
		for i: int in range(row.legs.size()):row.legs[i].rotation.x=sin(clock_s*8.+float(i)*PI)*.34 if row.moving else 0.
	for i: int in range(_water.size()):
		_water[i].visible=fire_state=="extinguishing"
		if _water[i].visible:
			var a: Vector3=firefighters[i].body.global_position+Vector3.UP*1.3;var b:=_site+Vector3.UP*.8;var shape: CylinderMesh=_water[i].mesh;shape.height=a.distance_to(b);_water[i].global_position=(a+b)*.5;_water[i].global_basis=Basis(Quaternion(Vector3.UP,(b-a).normalized()))

func _physics_process(delta: float) -> void:
	if not loaded or host.menu.visible:return
	for row: Dictionary in _visuals:row.visual.transform=Transform3D.IDENTITY;row.previous=row.current
	var before: Vector3=engine.global_position
	clock_s+=delta;_weather_tick(delta);_fire_tick(delta)
	_native_engine_speed=Vector2(engine.global_position.x-before.x,engine.global_position.z-before.z).length()/maxf(delta,.0001)
	for row: Dictionary in _visuals:row.current=row.body.global_transform
func _process(_delta: float) -> void:
	if not loaded or host.menu.visible:return
	var fraction:=clampf(Engine.get_physics_interpolation_fraction(),0.,1.)
	for row: Dictionary in _visuals:row.visual.global_transform=Transform3D(row.previous).interpolate_with(row.current,fraction)
	_rain.global_position=host.player.global_position
	for i: int in range(RAIN_STREAK_COUNT):
		var angle:=float(i)*2.39996;var r:=1.4+float(i%11)*.45;var point:=Vector3(cos(angle)*r,1.+fposmod(float(i)*1.71-clock_s*12.,8.),sin(angle)*r)
		_rain_mesh.multimesh.set_instance_transform(i,Transform3D(Basis(Vector3.BACK,.10),point))
	var remaining:=1.-clampf(state_clock_s/float(policy.extinguish_s),0.,1.) if fire_state=="extinguishing" else 1.
	for i: int in range(_flames.size()):_flames[i].scale=Vector3(.38,1.2+sin(clock_s*8.+i)*.35,.38)*maxf(.08,remaining)
	for i: int in range(_smoke.size()):
		var phase:=fposmod(clock_s*.7+float(i)/6.,1.);_smoke[i].position=Vector3(phase*.7,1.5+phase*3.,sin(i*2.4)*.35);_smoke[i].scale=Vector3.ONE*(.45+phase*1.1)*maxf(.2,remaining)

func viewpoint() -> Dictionary:
	if not loaded:return {}
	if fire_state=="ready":
		# Visitor standing/camera areas are to the left of the complete truck
		# exit/return sweep, and away from both office-side firefighter lanes.
		for depth: float in [24.,28.,32.,20.]:
			for lateral: float in [0.,-4.,4.,-8.,8.,12.,-12.]:
				var point: Vector3=station.to_global(Vector3(lateral,0,-depth));var view:=_observer_view(point,station.to_global(Vector3(0,6.,-14.9)),20.,0.,true)
				if not view.is_empty():return view
		return {}
	for distance: float in [6.,7.,8.,5.]:
		for direction: Vector3 in [-_side,-_forward,_side,_forward]:
			var point:=_site+direction*distance;var offset:=Vector3(-direction.z,0,direction.x)*2.5;var view:=_observer_view(point,_site+offset+Vector3.UP*1.5,5.0,-8.,false)
			if not view.is_empty():return view
	return {}
func _observer_view(point: Vector3,target: Vector3,distance: float,pitch: float,station_front_check: bool) -> Dictionary:
	var floor:=_travel_ground(point)
	if floor.is_empty() or not _supported(point,.30,true):return {}
	var foot: Vector3=floor.point+Vector3.UP*.08
	var previous:=_depot
	for route_point: Vector3 in _outbound_route:
		if Vector2(point.x,point.z).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(point.x,point.z),Vector2(previous.x,previous.z),Vector2(route_point.x,route_point.z)))<2.1:return {}
		previous=route_point
	var capsule:=PhysicsShapeQueryParameters3D.new();capsule.shape=host.player.get_node("CollisionShape").shape;capsule.transform=Transform3D(Basis.IDENTITY,foot+Vector3.UP*.85);capsule.collision_mask=1|2|4|8|32;capsule.exclude=[host.player.get_rid()]
	var space:=get_world_3d().direct_space_state
	if not space.intersect_shape(capsule,1).is_empty():return {}
	var direction:=target-foot;direction.y=0.;direction=direction.normalized()
	var pivot:=foot+Vector3.UP*float(host.rig.pivot_height_m)
	var eye:=pivot-direction*cos(deg_to_rad(pitch))*distance+Vector3.UP*(-sin(deg_to_rad(pitch)))*distance
	var camera_query:=PhysicsShapeQueryParameters3D.new();camera_query.shape=host.rig.arm.shape;camera_query.transform=Transform3D(Basis.IDENTITY,pivot);camera_query.collision_mask=1|8|32;camera_query.exclude=[host.player.get_rid()];camera_query.motion=eye-pivot
	if not space.intersect_shape(camera_query,1).is_empty() or space.cast_motion(camera_query)[0]<.99999:return {}
	if station_front_check:
		var header: Vector3=station.to_global(Vector3(-6.,5.56,-15.30));var front: Vector3=-station.global_basis.z;var truck_front: Vector3=engine.global_position+front*4.05+Vector3.UP*2.4
		var header_ray:=PhysicsRayQueryParameters3D.create(eye,header,1|8|32,[host.player.get_rid()])
		if not space.intersect_ray(header_ray).is_empty():return {}
		var truck_ray:=PhysicsRayQueryParameters3D.create(eye,truck_front,1|8|32,[host.player.get_rid()]);var hit: Dictionary=space.intersect_ray(truck_ray)
		if not hit.is_empty() and hit.collider!=engine:return {}
	else:
		var ray:=PhysicsRayQueryParameters3D.create(eye,_site+Vector3.UP*1.5,1|8|32,[host.player.get_rid()])
		if not space.intersect_ray(ray).is_empty():return {}
	return {"point":foot,"toward":target,"camera_distance":distance,"camera_pitch":pitch,"camera_distance_m":distance,"camera_pitch_degrees":pitch,"station_front_quarter_view":station_front_check,"header_and_truck_los_clear":station_front_check,"predicted_camera_eye":eye,"observer_outside_response_paths":true}
func status_text() -> String:
	var text: String="비 내리는 중" if weather=="rain" else "맑음"
	if fire_state!="ready":text+=" · 119 소방 출동 중" if fire_state!="extinguishing" else " · 소방관 진화 중"
	return text
func audio_state() -> Dictionary:
	return {"body":engine,"speed_mps":_native_engine_speed if loaded and not host.menu.visible else 0.,"engine_active":loaded and fire_state!="ready","siren_active":loaded and fire_state=="dispatch","water_active":loaded and fire_state=="extinguishing","water_point":_site+Vector3.UP*1.1}
func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Dictionary:
		var out: Dictionary={}
		for key: Variant in value:out[str(key)]=_json(value[key])
		return out
	if value is Array:
		var out: Array=[]
		for item: Variant in value:out.append(_json(item))
		return out
	return value
func snapshot() -> Dictionary:
	var crew: Array=[]
	for row: Dictionary in firefighters:crew.append({"position":row.body.global_position,"home":row.home,"moving":row.moving})
	return _json({"loaded":loaded,"error":load_error,"clock_s":clock_s,"weather":weather,"weather_clock_s":weather_clock_s,"rain_intensity":rain_intensity,"outdoors":outdoors,"visible_streaks":RAIN_STREAK_COUNT if is_instance_valid(_rain) and _rain.visible else 0,"rain_render_batches":1,"fire_state":fire_state,"fires_started":fires_started,"fires_extinguished":fires_extinguished,"completed_returns":completed_returns,"water_seconds":water_seconds,"engine_distance_m":engine_distance_m,"crew_distance_m":crew_distance_m,"blocked_ticks":blocked_ticks,"last_block":last_block,"engine_position":engine.global_position if is_instance_valid(engine) else Vector3.ZERO,"firefighters":crew,"provenance":provenance,"engine_dimensions_m":ENGINE_BOX,"standby_engine_position":standby_engine.global_position if is_instance_valid(standby_engine) else Vector3.ZERO,"facility_details":facility_details,"site_audit":site_audit,"events":events,"source_geometry_changed":false,"original_actor_counts_changed":false,"scope":"Authored weather, safety station and contained game fire; no actual Seoul firestation, weather feed, fire spread or emergency-route accuracy claim."})
