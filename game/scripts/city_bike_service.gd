extends Node3D
## Two authored rental bicycles. The bike body alone owns riding movement;
## player capsule, actor controllers and source geometry are retained.
const DATA_PATH := "res://assets/authored/bike_service.json"
const BOX_SIZE := Vector3(.70,1.90,1.90)
class BikeBody extends CharacterBody3D:
	func _physics_process(_delta: float) -> void:pass
class PoseFinish extends Node:
	var service: Node3D
	func _physics_process(_delta: float) -> void:service._rider_pose()
class PhysicsReset extends Node3D:
	func _physics_process(_delta: float) -> void:transform=Transform3D.IDENTITY
var host: Node3D
var loaded:=false
var load_error:=""
var riding:=false
var exit_requested:=false
var bikes: Array[Dictionary]=[]
var stations: Array[Dictionary]=[]
var design: Dictionary={}
var events: Array[Dictionary]=[]
var rental_index:=-1
var speed_mps:=0.0
var steer_radians:=0.0
var actual_distance_m:=0.0
var maximum_step_m:=0.0
var blocked_reason:=""
var _saved: Dictionary={}
var _collision_release_pending: Array[Dictionary]=[]
var _clock:=0.0
var _pedal_phase:=0.0
var _steer_assembly: Node3D
var _notice:=""
var _notice_until:=0.0
var _floor_rids: Array[RID]=[]
var _doors: Array[Vector3]=[]
var _reverse_hold_s:=0.0
var _maximum_pedal_rotation:=0.0
var maximum_hand_gap_m:=0.0
var maximum_pedal_sole_height_error_m:=0.0
var _minimum_support_normal_y:=1.0
var _grounded_ticks:=0
var _private_index: RefCounted
var _road_index: RefCounted
var _walk_index: RefCounted

func _design_path() -> String:return DATA_PATH
func _ride_label() -> String:return "따릉이"
func _ride_status_prefix() -> String:return "CITY_BIKES_READY"
func _event(kind: String,evidence: Dictionary={}) -> void:
	if events.size()>=80:events.pop_front()
	events.append({"event":kind,"clock_s":_clock,"evidence":evidence})
func _fail(message: String) -> bool:load_error=message;push_error(message);return false
func setup(scene: Node3D) -> bool:
	if loaded or not is_instance_valid(scene) or not is_inside_tree():return false
	host=scene;process_mode=Node.PROCESS_MODE_PAUSABLE;process_physics_priority=0
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(_design_path()))
	if not raw is Dictionary or raw.get("schema_version")!=1:return _fail("자전거 자료 형식이 다릅니다.")
	design=raw
	for path: String in design.source_hashes:
		if FileAccess.get_sha256(path)!=String(design.source_hashes[path]):return _fail("자전거와 원본 거리 자료가 다릅니다.")
	if not is_instance_valid(host.get("terrain_surface")) or not host.terrain_surface.loaded:return _fail("자전거 지면이 준비되지 않았습니다.")
	var index_script:=preload("res://scripts/source_polygon_index.gd")
	_private_index=index_script.new();_private_index.setup(host.city.private_cache,Callable(host.city,"_contains"))
	_walk_index=index_script.new();_walk_index.setup(host.city.movement_cache,Callable(host.city,"_contains"))
	var road_parts: Array=[]
	for parts: Array in host.city.road_cache:road_parts.append_array(parts)
	_road_index=index_script.new();_road_index.setup(road_parts,Callable(host.city,"_contains"))
	for record: Dictionary in host.interior_visit.catalog:
		for entry: Dictionary in record.entry_candidates:_doors.append(entry.entrance)
	for record: Dictionary in design.stations:
		if not _make_station(record):return _fail("자전거 대여소의 안전한 원본 보행 공간을 확보하지 못했습니다: "+String(record.id))
	var finish:=PoseFinish.new();finish.service=self;finish.process_physics_priority=2;add_child(finish)
	loaded=true;print(_ride_status_prefix()," bikes=",bikes.size()," docks=",stations.size()," authored=true source_geometry_changed=false");return true

func _mat(color: Color,metallic:=0.0) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.65;material.metallic=metallic;return material
func _mesh(parent: Node3D,title: String,mesh: Mesh,material: Material,at:=Vector3.ZERO) -> MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=title;node.mesh=mesh;node.material_override=material;node.position=at;parent.add_child(node);return node
func _box(parent: Node3D,title: String,size: Vector3,at: Vector3,material: Material) -> MeshInstance3D:
	var mesh:=BoxMesh.new();mesh.size=size;return _mesh(parent,title,mesh,material,at)
func _tube(parent: Node3D,title: String,a: Vector3,b: Vector3,radius: float,material: Material) -> MeshInstance3D:
	var mesh:=CylinderMesh.new();mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=a.distance_to(b);mesh.radial_segments=10
	var node:=_mesh(parent,title,mesh,material,(a+b)*.5);node.basis=Basis(Quaternion(Vector3.UP,(b-a).normalized()));return node
func _label(parent: Node3D,title: String,text: String,at: Vector3,size:=.0025) -> Label3D:
	var node:=Label3D.new();node.name=title;node.text=text;node.font_size=42;node.pixel_size=size;node.position=at;node.modulate=Color(.08,.25,.10);node.outline_size=3;node.billboard=BaseMaterial3D.BILLBOARD_ENABLED;parent.add_child(node);return node
func _ground(at: Vector3,height:=1.0) -> Dictionary:
	var y: float=host.terrain_surface.ground_y_world(at)
	if not is_finite(y):return {}
	var ray:=PhysicsRayQueryParameters3D.create(Vector3(at.x,y+height,at.z),Vector3(at.x,y-height,at.z),1|32)
	var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<cos(deg_to_rad(float(design.policy.maximum_grade_degrees))):return {}
	return {"point":Vector3(at.x,hit.position.y,at.z),"normal":hit.normal,"rid":hit.rid}
func _source_allowed(point: Vector3) -> bool:
	if not point.is_finite() or not host.player.free_roam_bounds.grow(-1.1).has_point(Vector2(point.x,point.z)):return false
	var local: Vector3=host.city.to_local(point);var flat:=Vector2(local.x,local.z)
	if _private_index.contains(flat):return false
	if not host.player.free_roam_enabled and not _walk_index.contains(flat):return false
	if not (_walk_index.contains(flat) or _road_index.contains(flat)):return false
	for door: Vector3 in _doors:
		if Vector2(door.x-point.x,door.z-point.z).length()<float(design.policy.door_clearance_m):return false
	return true
func _footprint_allowed(point: Vector3,basis: Basis) -> bool:
	for offset: Vector3 in [Vector3.ZERO,Vector3(-.36,0,-.96),Vector3(.36,0,-.96),Vector3(-.36,0,.96),Vector3(.36,0,.96)]:
		var sample:=point+basis*offset
		if not _source_allowed(sample) or _ground(sample).is_empty():return false
	return true
func _pose_basis(at: Vector3,yaw: float) -> Basis:
	var sample:=_ground(at)
	if sample.is_empty():return Basis(Vector3.UP,yaw)
	var normal: Vector3=sample.normal;var forward: Vector3=-Basis(Vector3.UP,yaw).z;forward=(forward-normal*forward.dot(normal)).normalized()
	return Basis(forward.cross(normal).normalized(),normal,-forward).orthonormalized()
func _clear_box(at: Vector3,basis: Basis,exclude: Array[RID],motion:=Vector3.ZERO) -> bool:
	var query:=PhysicsShapeQueryParameters3D.new();var shape:=BoxShape3D.new();shape.size=BOX_SIZE;query.shape=shape;query.collision_mask=1|2|4|8|32;query.exclude=exclude;query.margin=.003
	query.transform=Transform3D(basis,at+basis*Vector3(0,.98,0));query.motion=Vector3.ZERO
	var space:=get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():return false
	query.motion=motion;return motion.is_zero_approx() or space.cast_motion(query)[0]>=.9999
func _station_sign_clear(at: Vector3,yaw: float) -> bool:
	# The existing bicycle box is below the raised sign. Reserve its complete
	# upper envelope separately so a clear bike cannot put the sign in a wall,
	# roof or overhanging static fixture. The actual station uses yaw only.
	var query:=PhysicsShapeQueryParameters3D.new();var box:=BoxShape3D.new();box.size=Vector3(1.52,1.94,.14);query.shape=box;query.collision_mask=1|32;query.margin=.005
	var basis:=Basis(Vector3.UP,yaw);query.transform=Transform3D(basis,at+basis*Vector3(-.9,2.45,.75))
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
func _make_station(record: Dictionary) -> bool:
	var route: Dictionary={}
	for item: Dictionary in host.city.public_data.routes:
		if item.id==record.source_route:route=item;break
	if route.is_empty():return false
	var a: Array=route.xz[record.source_segment[0]];var b: Array=route.xz[record.source_segment[1]]
	var start: Vector3=host.city.to_global(Vector3(a[0],0,a[1]));var end: Vector3=host.city.to_global(Vector3(b[0],0,b[1]));var direction: Vector3=end-start;direction.y=0.;direction=direction.normalized();var side:=Vector3(direction.z,0,-direction.x)
	var desired: Vector3=start.lerp(end,float(record.fraction))+side*float(record.side_offset_m);var yaw:=atan2(-direction.x,-direction.z);var support: Dictionary={};var accepted:=false
	for shift: float in [0.,1.5,-1.5,3.,-3.,4.5,-4.5]:
		var candidate: Vector3=desired+direction*shift;support=_ground(candidate)
		if support.is_empty():continue
		var basis:=_pose_basis(support.point,yaw)
		var fixture_clear:=true
		for local: Vector3 in [Vector3(-1.65,0,.75),Vector3(-.9,0,.75),Vector3(-.55,0,.55),Vector3(.55,0,.55)]:
			var point: Vector3=support.point+basis*local;var source: Vector3=host.city.to_local(point)
			if not _source_allowed(point) or not _walk_index.contains(Vector2(source.x,source.z)) or _ground(point).is_empty():fixture_clear=false
		if fixture_clear and _footprint_allowed(support.point,basis) and _station_sign_clear(support.point,yaw) and _clear_box(support.point+Vector3.UP*.035,basis,[host.player.get_rid(),support.rid]):desired=support.point;accepted=true;break
	if not accepted:return false
	var station:=Node3D.new();station.name=String(record.id);add_child(station);station.global_position=desired;station.global_rotation.y=yaw
	var green:=_mat(Color(.23,.63,.12));var steel:=_mat(Color(.58,.62,.62),.45)
	for x: float in [-.55,.55]:
		_tube(station,"RackUpright",Vector3(x,.02,.55),Vector3(x,.60,.55),.028,steel)
	_tube(station,"RackHoop",Vector3(-.55,.60,.55),Vector3(.55,.60,.55),.028,steel)
	_box(station,"DockGreenPlate",Vector3(1.20,.025,.35),Vector3(0,.025,.65),green)
	# Support the board at its left edge so the rear face's text and pictogram
	# are readable too; a central through-post used to cover their letters.
	_tube(station,"StationPost",Vector3(-1.60,0,.75),Vector3(-1.60,2.55,.75),.045,steel)
	_tube(station,"PictogramMount",Vector3(-.9,2.55,.75),Vector3(-.9,2.73,.75),.035,steel)
	var panel:=Node3D.new();panel.name="FixedStationSign";panel.position=Vector3(-.9,2.3,.75);station.add_child(panel)
	_box(panel,"StationHeader",Vector3(1.5,.52,.06),Vector3.ZERO,green)
	_box(panel,"StationInformation",Vector3(1.5,.42,.06),Vector3(0,-.55,0),_mat(Color(.91,.94,.87)))
	# Physical board and both text faces share the same fixed frame.
	for front: bool in [true,false]:
		var face: float=1. if front else -1.
		var title:=_label(panel,"StationTitleFront" if front else "StationTitleBack",_ride_label()+" 대여소\nBICYCLE · 게임 체험",Vector3(0,0,face*.045),.0027)
		title.modulate=Color(.98,1.,.96);title.outline_modulate=Color(.10,.30,.06);title.billboard=BaseMaterial3D.BILLBOARD_DISABLED;title.rotation.y=0. if front else PI
		var help:=_label(panel,"StationHelpFront" if front else "StationHelpBack","E · 빌리기 / 반납\n"+String(record.name),Vector3(0,-.55,face*.045),.0024)
		help.billboard=BaseMaterial3D.BILLBOARD_DISABLED;help.rotation.y=0. if front else PI
	# A normal-sized, fixed bicycle pictogram makes the dock readable before
	# its Korean text is close enough to read. These are sign graphics, not
	# reserve bicycle models or additional rentable inventory.
	var icon:=Node3D.new();icon.name="StationBicyclePictogram";icon.position=Vector3(-.9,3.05,.75);station.add_child(icon)
	_box(icon,"IconBackground",Vector3(.96,.68,.06),Vector3.ZERO,green)
	var ink:=_mat(Color(.98,1.,.96))
	for face: float in [-1.,1.]:
		for x: float in [-.25,.25]:
			var ring:=TorusMesh.new();ring.inner_radius=.122;ring.outer_radius=.140;ring.rings=20;ring.ring_segments=6
			var wheel:=_mesh(icon,"SignWheel",ring,ink,Vector3(x,-.10,face*.044));wheel.rotation.x=PI*.5
		for line: Array in [[Vector2(-.25,-.10),Vector2(-.10,.15)],[Vector2(-.10,.15),Vector2(.05,-.10)],[Vector2(.05,-.10),Vector2(-.25,-.10)],[Vector2(-.10,.15),Vector2(.18,.15)],[Vector2(.18,.15),Vector2(.25,-.10)],[Vector2(.18,.15),Vector2(.18,.24)],[Vector2(.18,.24),Vector2(.31,.24)],[Vector2(-.17,.19),Vector2(-.02,.19)]]:
			_tube(icon,"SignFrame",Vector3(line[0].x,line[0].y,face*.045),Vector3(line[1].x,line[1].y,face*.045),.014,ink)
	var body:=BikeBody.new();body.name="RentalBike"+str(bikes.size()+1);body.collision_layer=4;body.collision_mask=1|2|4|8|32;body.safe_margin=.001;body.floor_snap_length=.35;body.floor_max_angle=deg_to_rad(float(design.policy.maximum_grade_degrees));add_child(body)
	var shape:=CollisionShape3D.new();shape.name="CollisionShape";var box:=BoxShape3D.new();box.size=BOX_SIZE;shape.shape=box;shape.position.y=.95;body.add_child(shape)
	body.global_transform=Transform3D(_pose_basis(desired,yaw),desired+Vector3.UP*.025)
	var visual:=Node3D.new();visual.name="Visual";body.add_child(visual);var proxy:=PhysicsReset.new();proxy.name="RenderProxy";proxy.process_physics_priority=-100;visual.add_child(proxy)
	var row: Dictionary={"body":body,"visual":visual,"proxy":proxy,"shape":shape,"station_id":record.id,"rented":false,"yaw":yaw,"wheel_phase":0.,"distance_m":0.,"previous":body.global_transform,"current":body.global_transform,"front":null,"wheels":[],"crank":null,"pedals":[],"kickstand":null}
	_build_bike(row,proxy);bikes.append(row);stations.append({"id":record.id,"name":record.name,"point":desired,"node":station,"source_route":record.source_route,"panel":panel,"pictogram":icon,"certified_footprint":true})
	return true

func _build_bike(row: Dictionary,parent: Node3D) -> void:
	var white:=_mat(Color(.91,.93,.88));var green:=_mat(Color(.26,.66,.12));var dark:=_mat(Color(.06,.075,.07));var silver:=_mat(Color(.57,.63,.62),.6);var red:=_mat(Color(.67,.025,.015));var amber:=_mat(Color(1.,.61,.12))
	for front: bool in [false,true]:
		var assembly:=Node3D.new();assembly.name="Steering" if front else "RearWheelAssembly";assembly.position=Vector3(0,0,-.58 if front else .58);parent.add_child(assembly)
		if front:row.front=assembly
		var wheel:=Node3D.new();wheel.name="FrontWheel" if front else "RearWheel";wheel.position.y=.35;assembly.add_child(wheel)
		for spec: Array in [[.322,.357,dark],[.283,.304,green],[.270,.277,silver]]:
			var torus:=TorusMesh.new();torus.inner_radius=spec[0];torus.outer_radius=spec[1];torus.rings=32;torus.ring_segments=8;var ring:=_mesh(wheel,"Tyre" if spec[2]==dark else "Rim",torus,spec[2]);ring.rotation.z=PI*.5
		for index: int in range(12):
			var angle:=TAU*index/12.;_tube(wheel,"Spoke",Vector3(.018,0,0),Vector3(0,sin(angle)*.277,cos(angle)*.277),.0045,silver)
		_tube(wheel,"Axle",Vector3(-.09,0,0),Vector3(.09,0,0),.034,silver)
		_box(wheel,"WheelReflector",Vector3(.025,.06,.11),Vector3(0,0,.22),amber);row.wheels.append(wheel)
		for side: float in [-1.,1.]:_tube(assembly,"Fork" if front else "RearStay",Vector3(side*.075,.35,0),Vector3(side*.075,.85,.11 if front else -.34),.025,white)
		# A continuous authored mudguard follows the upper half of the wheel.
		for index: int in range(10):
			var a:=PI*index/10.;var b:=PI*(index+1)/10.;_tube(assembly,"Mudguard",Vector3(0,.35+sin(a)*.376,cos(a)*.376),Vector3(0,.35+sin(b)*.376,cos(b)*.376),.023,green)
	var crank_at:=Vector3(0,.40,.10);var seat_at:=Vector3(0,.88,.16);var neck_at:=Vector3(0,.91,-.48)
	_tube(parent,"LowStepThrough",Vector3(0,.58,-.43),crank_at,.048,white)
	_tube(parent,"FrameDownTube",crank_at,seat_at,.047,white)
	_tube(parent,"FrameBrace",Vector3(0,.60,.14),Vector3(0,.75,-.45),.035,white)
	_tube(parent,"SeatPost",seat_at,Vector3(0,.94,.16),.027,silver)
	_box(parent,"Saddle",Vector3(.23,.07,.28),Vector3(0,.94,.16),dark)
	_box(parent,"ChainCase",Vector3(.06,.15,.59),Vector3(.09,.40,.34),green)
	_box(parent,"RearQRLock",Vector3(.19,.16,.12),Vector3(0,.76,.51),green)
	_box(parent,"RearLamp",Vector3(.09,.065,.035),Vector3(0,.75,.72),red)
	var steer: Node3D=row.front
	_tube(steer,"HandleStem",Vector3(0,.80,.09),Vector3(0,1.20,.36),.027,silver)
	_tube(steer,"HandleBar",Vector3(-.28,1.20,.36),Vector3(.28,1.20,.36),.021,silver)
	for side: float in [-1.,1.]:
		_tube(steer,"BlackGrip",Vector3(side*.19,1.20,.36),Vector3(side*.30,1.20,.36),.031,dark)
		_tube(steer,"BrakeLever",Vector3(side*.23,1.18,.33),Vector3(side*.27,1.17,.255),.012,silver)
	_box(steer,"BasketBottom",Vector3(.39,.026,.28),Vector3(0,.96,-.21),dark)
	for x: float in [-.195,.195]:
		for z: float in [-.35,-.07]:_tube(steer,"BasketUpright",Vector3(x,.97,z),Vector3(x,1.23,z),.013,dark)
	for y: float in [1.00,1.08,1.16,1.23]:
		for z: float in [-.35,-.07]:_tube(steer,"BasketMesh",Vector3(-.195,y,z),Vector3(.195,y,z),.006,dark)
		for x: float in [-.195,.195]:_tube(steer,"BasketMesh",Vector3(x,y,-.35),Vector3(x,y,-.07),.006,dark)
	_box(steer,"BasketLogo",Vector3(.27,.15,.015),Vector3(0,1.11,-.365),green)
	_label(steer,"BikeName",_ride_label(),Vector3(0,1.11,-.38),.0016)
	_box(steer,"FrontLamp",Vector3(.08,.06,.045),Vector3(0,.88,-.10),white)
	var crank:=Node3D.new();crank.name="PedalCrank";crank.position=crank_at;parent.add_child(crank);row.crank=crank
	for side: float in [-1.,1.]:
		_tube(crank,"CrankArm",Vector3(side*.11,0,0),Vector3(side*.17,0,side*.155),.014,silver)
		var pedal:=_box(crank,"Pedal",Vector3(.15,.035,.08),Vector3(side*.20,0,side*.155),dark);row.pedals.append(pedal)
	row.kickstand=_tube(parent,"Kickstand",Vector3(.07,.40,.28),Vector3(.28,.025,.40),.012,dark)

func _context_ready() -> bool:
	if not loaded or not host.runtime_ok or get_tree().paused or host.menu.visible:return false
	if host.player.interior_active or host.interior_visit.active:return false
	return not _other_transport_riding()
func _other_transport_riding() -> bool:
	for property: String in ["city_bus_service","city_bike_service","city_scooter_service"]:
		var other: Node3D=host.get(property)
		if is_instance_valid(other) and other!=self and other.riding:return true
	return false
func _nearest_bike() -> int:
	if rental_index>=0:return rental_index if host.player.global_position.distance_to(bikes[rental_index].body.global_position)<float(design.policy.interact_distance_m) else -1
	var best:=-1;var visible_best:=-1;var distance:=float(design.policy.interact_distance_m);var visible_distance:=distance
	for index: int in range(bikes.size()):
		var value: float=Vector2(host.player.global_position.x-bikes[index].body.global_position.x,host.player.global_position.z-bikes[index].body.global_position.z).length()
		if bikes[index].rented:continue
		if value<distance:best=index;distance=value
		if value<visible_distance and _visible_bike(index):visible_best=index;visible_distance=value
	return visible_best if visible_best>=0 else best
func interaction_distance_m() -> float:
	if not loaded or not _context_ready():return INF
	var index:=_nearest_bike()
	if index<0:return INF
	var delta: Vector3=host.player.global_position-bikes[index].body.global_position
	return Vector2(delta.x,delta.z).length()
func _player_supported_for_mount() -> bool:
	# A shortcut or a newly published contact can precede is_on_floor's next
	# move_and_slide result. Check current native feet support as well, while
	# a rising/falling airborne capsule remains ineligible.
	if absf(host.player.velocity.y)>.3:return false
	var support:=_ground(host.player.global_position,.4)
	return not support.is_empty() and absf(host.player.global_position.y-support.point.y)<.13
func _near_station(point: Vector3) -> String:
	for station: Dictionary in stations:
		if Vector2(point.x-station.point.x,point.z-station.point.z).length()<=float(design.policy.return_radius_m):return station.id
	return ""
func _visible_bike(index: int) -> bool:
	if index<0:return false
	var body: CharacterBody3D=bikes[index].body
	var horizontal:=Vector2(host.player.global_position.x-body.global_position.x,host.player.global_position.z-body.global_position.z).length()
	if absf(host.player.global_position.y-body.global_position.y)>maxf(.4,horizontal*tan(deg_to_rad(float(design.policy.maximum_grade_degrees)))+.15):return false
	var excludes: Array[RID]=[host.player.get_rid(),body.get_rid()]
	# A passing registered pedestrian or dog may briefly cross both sight
	# rays, but should not make the E target disappear. Recast through only
	# those known actor RIDs: walls, cars and other parked mobility bodies
	# still block sight, and _mount's full box still rejects occupied space.
	for person: CharacterBody3D in host.traffic.humans:
		if is_instance_valid(person) and not person is BikeBody:excludes.append(person.get_rid())
	for height: float in [.65,1.20]:
		var ray:=PhysicsRayQueryParameters3D.create(host.player.global_position+Vector3.UP*height,body.global_position+Vector3.UP*height,1|4|8|32,excludes)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():return false
	return true
func can_interact() -> bool:
	if not _context_ready():return false
	if riding:return true
	return not host.player.facility_control and host.player.is_physics_processing() and _player_supported_for_mount() and _visible_bike(_nearest_bike())
func prompt_text() -> String:
	if not _context_ready():return ""
	if riding:return _ride_label()+" · W 가속 / S 제동·뒤로\nA·D 방향 / Space 제동 / E "+("반납" if not _near_station(bikes[rental_index].body.global_position).is_empty() else "내리기") if not exit_requested else "내릴 자리를 확인하는 중\nE · 취소하고 다시 이동"
	if _clock<_notice_until:return _notice
	var index:=_nearest_bike()
	if index<0:return ""
	if not _visible_bike(index):return _ride_label()+" 옆의 열린 공간으로 이동해 E"
	if not _player_supported_for_mount():return "착지한 뒤 E · "+_ride_label()+" 이용"
	return "E · "+_ride_label()+" 반납" if bikes[index].rented and not _near_station(bikes[index].body.global_position).is_empty() else ("E · "+_ride_label()+" 다시 타기" if bikes[index].rented else "E · "+_ride_label()+" 빌려 타기 · 게임 체험")
func handle_interact() -> bool:
	if not can_interact():return false
	if riding:exit_requested=not exit_requested;_event("dismount_requested" if exit_requested else "dismount_cancelled");return true
	var index:=_nearest_bike()
	if bikes[index].rented and not _near_station(bikes[index].body.global_position).is_empty():
		bikes[index].rented=false;bikes[index].station_id=_near_station(bikes[index].body.global_position);rental_index=-1;_notice=_ride_label()+" 반납 완료";_notice_until=_clock+3.;_event("returned",{"station_id":bikes[index].station_id});return true
	if not _mount(index):
		_notice=_ride_label()+" 주변이 막혀 있습니다. 사람이 지나가거나 공간이 비면 E를 다시 눌러주세요." if blocked_reason=="mount_space_blocked" else _ride_label()+"가 길 위에 안전하게 서 있어야 탈 수 있습니다."
		_notice_until=_clock+3.;_event("mount_rejected",{"reason":blocked_reason,"bike_index":index})
	# This E belonged to the visible nearby vehicle, including a failed safe
	# mount. Do not pass the same press through to a building entrance.
	return true
func _mount(index: int) -> bool:
	if index<0 or not _context_ready():return false
	var row: Dictionary=bikes[index];var body: CharacterBody3D=row.body;var support:=_ground(body.global_position)
	if support.is_empty():blocked_reason="mount_support_missing";return false
	if not _footprint_allowed(body.global_position,body.global_basis):blocked_reason="mount_source_boundary";return false
	var excludes: Array[RID]=[body.get_rid(),host.player.get_rid(),support.rid]
	if is_instance_valid(host.terrain_surface.support):excludes.append(host.terrain_surface.support.get_rid())
	if not _clear_box(body.global_position,body.global_basis,excludes):blocked_reason="mount_space_blocked";return false
	var player: CharacterBody3D=host.player
	_saved={"physics":player.is_physics_processing(),"mask":player.collision_mask,"layer":player.collision_layer,"visual":player.get_node("Visual").transform,"avatar_visible":host.exploration_avatar.visible,"left_hip":host.exploration_avatar._joints.LeftThigh.position,"right_hip":host.exploration_avatar._joints.RightThigh.position,"rig_distance":host.rig.requested_distance,"rig_current":host.rig.current_distance,"rig_max":host.rig.distance_max_m,"rig_yaw":host.rig.yaw,"rig_pitch":host.rig.pitch,"rig_pivot":host.rig.pivot_height_m,"query_exclude":host.rig._query.exclude.duplicate()}
	player.set_facility_control(true);player.set_physics_process(false);player.velocity=Vector3.ZERO
	body.add_collision_exception_with(player);player.add_collision_exception_with(body)
	var exclude: Array[RID]=host.rig._query.exclude.duplicate();exclude.append(body.get_rid());host.rig._query.exclude=exclude;host.rig.arm.add_excluded_object(body.get_rid())
	rental_index=index;row.rented=true;row.kickstand.visible=false;riding=true;exit_requested=false;speed_mps=0.;steer_radians=0.;_reverse_hold_s=0.;blocked_reason="";_notice="";_notice_until=0.;host.exploration_avatar.visible=true
	# The former dead-rear view put the narrow frame and both wheels directly
	# behind the rider. Start at a three-quarter angle; mouse orbit stays free.
	host.rig.distance_max_m=maxf(host.rig.distance_max_m,6.5);host.rig.pivot_height_m=.8;host.rig.requested_distance=4.6;host.rig.current_distance=4.6;host.rig.yaw=row.yaw+.60;host.rig.pitch=deg_to_rad(-18.)
	_attach_player(0.);_rider_pose(false);host.rig.snap_to_target_pose();_event("rented_and_mounted",{"bike":body.name});return true
func _safe_dismount() -> Dictionary:
	var row: Dictionary=bikes[rental_index];var body: CharacterBody3D=row.body
	for offset: Vector3 in [Vector3(.95,0,.1),Vector3(-.95,0,.1),Vector3(.95,0,1.05),Vector3(-.95,0,1.05),Vector3(0,0,1.65)]:
		var requested: Vector3=body.global_position+body.global_basis*offset
		var safe: Dictionary=host.interior_visit._safe_external_point(requested)
		if not safe.is_empty():return safe
	return {}
func _finish_collision_release() -> void:
	for index: int in range(_collision_release_pending.size()-1,-1,-1):
		var pending: Dictionary=_collision_release_pending[index];var body: CharacterBody3D=pending.body
		if Engine.get_physics_frames()<int(pending.release_tick):continue
		if riding and rental_index>=0 and bikes[rental_index].body==body:
			_collision_release_pending.remove_at(index);continue
		var shape: CollisionShape3D=body.get_node("CollisionShape")
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape.shape;query.transform=shape.global_transform;query.collision_mask=host.player.collision_layer;query.exclude=[body.get_rid()]
		var outside:=true
		for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query,8):
			if hit.collider==host.player:outside=false
		if not outside:continue
		body.remove_collision_exception_with(host.player);host.player.remove_collision_exception_with(body)
		if pending.hold_control and not riding and not _other_transport_riding():
			host.player.set_facility_control(false);host.player.set_physics_process(bool(pending.player_physics));host.player.require_neutral_input()
		_collision_release_pending.remove_at(index);_event("published_exit_pair_released")
func _restore_player(delay_control:=false) -> void:
	var body: CharacterBody3D=bikes[rental_index].body;var player: CharacterBody3D=host.player
	bikes[rental_index].kickstand.visible=true
	# Position publication reaches the physics server after this controller.
	# Retain the mutual pair until a later native query sees the capsule outside.
	_collision_release_pending.append({"body":body,"release_tick":Engine.get_physics_frames()+2,"hold_control":delay_control,"player_physics":bool(_saved.physics)})
	player.collision_layer=int(_saved.layer);player.collision_mask=int(_saved.mask);player.get_node("Visual").transform=_saved.visual
	if not delay_control:player.set_facility_control(false);player.set_physics_process(bool(_saved.physics))
	player.require_neutral_input();player.reset_physics_interpolation();host.exploration_avatar.visible=bool(_saved.avatar_visible);host.exploration_avatar._joints.LeftThigh.position=_saved.left_hip;host.exploration_avatar._joints.RightThigh.position=_saved.right_hip;host.exploration_avatar._rest_pose()
	host.rig._query.exclude=_saved.query_exclude;host.rig.arm.remove_excluded_object(body.get_rid());host.rig.distance_max_m=_saved.rig_max;host.rig.pivot_height_m=_saved.rig_pivot;host.rig.requested_distance=_saved.rig_distance;host.rig.current_distance=minf(host.rig.current_distance,host.rig.requested_distance);host.rig.yaw=_saved.rig_yaw;host.rig.pitch=_saved.rig_pitch
	riding=false;exit_requested=false;speed_mps=0.;_saved.clear();host.rig.snap_to_target_pose()
func _try_dismount() -> bool:
	if absf(speed_mps)>float(design.policy.dismount_speed_mps):return false
	var safe:=_safe_dismount()
	if safe.is_empty():blocked_reason="dismount_blocked";return false
	var row: Dictionary=bikes[rental_index];host.player.global_transform=Transform3D(Basis.IDENTITY,safe.point);_restore_player(true);_event("dismounted",{"point":safe.point})
	var station_id:=_near_station(row.body.global_position)
	if not station_id.is_empty():row.rented=false;row.station_id=station_id;rental_index=-1;_event("returned",{"station_id":station_id});_notice=_ride_label()+" 반납 완료";_notice_until=_clock+3.
	return true
func cancel_ride_for_teleport() -> void:
	if not riding:return
	var row: Dictionary=bikes[rental_index];_restore_player();row.rented=false;rental_index=-1;_event("ride_cancelled_after_validated_external_teleport")
func _attach_player(delta: float) -> void:
	if not riding:return
	var body: CharacterBody3D=bikes[rental_index].body
	host.player.global_transform=body.global_transform.translated_local(Vector3(0,.13,.10));host.player.get_node("Visual").rotation=Vector3.ZERO;host.player.velocity=Vector3.ZERO;host.player.physics_stepped.emit(delta)
func _rider_pose(measure:=true) -> void:
	if not riding:return
	var avatar: Node3D=host.exploration_avatar;avatar.position=Vector3.ZERO;avatar._upper_body.position=Vector3(0,.85,0);avatar._upper_body.rotation=Vector3(-.12,0,0)
	var row: Dictionary=bikes[rental_index]
	for side_name: String in ["Left","Right"]:
		var side: float=-1. if side_name=="Left" else 1.
		var foot:=Vector3(side*.16,.40-.13+.132-side*sin(_pedal_phase)*.155,side*cos(_pedal_phase)*.155+.06)
		avatar._joints[side_name+"Thigh"].position.x=side*.16
		avatar._leg_pose(side_name,foot)
		var grip: Vector3=row.front.to_global(Vector3(side*.265,1.20,.36))
		avatar._arm_to(side_name,avatar.to_local(grip))
		if measure:
			maximum_hand_gap_m=maxf(maximum_hand_gap_m,avatar._hands[0 if side<0 else 1].global_position.distance_to(grip))
			var sole: Vector3=avatar._joints[side_name+"Foot"].to_global(Vector3(0,-.1145,-.06))
			var pedal: Vector3=row.crank.to_global(Vector3(side*.20,0,side*.155))+bikes[rental_index].body.global_basis.y*.0175
			maximum_pedal_sole_height_error_m=maxf(maximum_pedal_sole_height_error_m,absf((sole-pedal).dot(bikes[rental_index].body.global_basis.y)))
func _physics_process(delta: float) -> void:
	if not loaded or delta<=0.:return
	_finish_collision_release()
	_clock+=delta
	for index: int in range(bikes.size()):
		var row: Dictionary=bikes[index];var body: CharacterBody3D=row.body;row.previous=row.current
		if not riding or index!=rental_index:
			body.velocity=Vector3(0,-.12 if body.is_on_floor() else maxf(body.velocity.y-9.8*delta,-8.),0);body.move_and_slide();row.current=body.global_transform;continue
		var intent: Vector2=host.input_router.movement_intent();var hand_brake:=Input.is_action_pressed("jump") or exit_requested
		if host.player.input_latched:
			if intent.is_zero_approx() and not Input.is_action_pressed("jump"):host.player.input_latched=false
			intent=Vector2.ZERO;hand_brake=true
		_reverse_hold_s=_reverse_hold_s+delta if intent.y>.1 and speed_mps<=.02 and not hand_brake else 0.
		var target_speed:=0.
		if not hand_brake:
			if intent.y<-.1:target_speed=float(design.policy.maximum_speed_mps)
			elif intent.y>.1 and _reverse_hold_s>=.55:target_speed=-1.1
		var braking: bool=hand_brake or (intent.y>.1 and speed_mps>0.) or (intent.y<-.1 and speed_mps<0.)
		var rate:=float(design.policy.braking_mps2) if braking else (float(design.policy.acceleration_mps2) if not is_zero_approx(target_speed) else float(design.policy.coast_deceleration_mps2))
		speed_mps=move_toward(speed_mps,target_speed,rate*delta)
		steer_radians=move_toward(steer_radians,-intent.x*deg_to_rad(float(design.policy.maximum_steer_degrees)),delta*1.8)
		var yaw: float=row.yaw+clampf(speed_mps/float(design.policy.wheelbase_m)*tan(steer_radians),-1.5,1.5)*delta
		var before:=body.global_position;var flat_basis:=Basis(Vector3.UP,yaw);var motion: Vector3=-flat_basis.z*speed_mps*delta;var support:=_ground(before)
		var basis:=_pose_basis(before+motion,yaw);var excludes: Array[RID]=[body.get_rid(),host.player.get_rid()]
		if not support.is_empty():excludes.append(support.rid)
		if is_instance_valid(host.terrain_surface.support):excludes.append(host.terrain_surface.support.get_rid())
		if not _footprint_allowed(before+motion,basis):blocked_reason="source_boundary_or_support";speed_mps=0.;motion=Vector3.ZERO
		elif not _clear_box(before,basis,excludes,motion):blocked_reason="physical_sweep";speed_mps=0.;motion=Vector3.ZERO
		else:blocked_reason="";body.global_basis=basis;row.yaw=yaw
		body.velocity.x=motion.x/delta;body.velocity.z=motion.z/delta;body.velocity.y=-.12 if body.is_on_floor() else maxf(body.velocity.y-9.8*delta,-8.);body.move_and_slide()
		var actual:=Vector2(body.global_position.x-before.x,body.global_position.z-before.z).length();actual_distance_m+=actual;row.distance_m+=actual;maximum_step_m=maxf(maximum_step_m,actual)
		if actual<absf(speed_mps)*delta*.35:speed_mps=0.
		if body.is_on_floor():_grounded_ticks+=1;_minimum_support_normal_y=minf(_minimum_support_normal_y,body.get_floor_normal().y)
		row.wheel_phase=fmod(row.wheel_phase+actual*signf(speed_mps)/float(design.policy.wheel_radius_m),TAU);_pedal_phase=fmod(_pedal_phase+actual*signf(speed_mps)/.92,TAU);_maximum_pedal_rotation=maxf(_maximum_pedal_rotation,_pedal_phase)
		for wheel: Node3D in row.wheels:wheel.rotation.x=row.wheel_phase
		row.crank.rotation.x=_pedal_phase
		for pedal: Node3D in row.pedals:pedal.rotation.x=-_pedal_phase
		row.front.rotation.y=steer_radians;row.current=body.global_transform;_attach_player(delta)
		if exit_requested and absf(speed_mps)<=float(design.policy.dismount_speed_mps):_try_dismount()
func _process(_delta: float) -> void:
	if not loaded:return
	var fraction:=clampf(Engine.get_physics_interpolation_fraction(),0.,1.)
	for row: Dictionary in bikes:row.proxy.global_transform=row.previous.interpolate_with(row.current,fraction)
func viewpoint() -> Dictionary:
	if stations.is_empty():return {}
	var row: Dictionary=bikes[0];var body: CharacterBody3D=row.body
	for offset: Vector3 in [Vector3(1.90,0,.1),Vector3(-1.90,0,.1),Vector3(1.65,0,.75),Vector3(-1.65,0,.75)]:
		var safe: Dictionary=host.interior_visit._safe_external_point(body.global_position+body.global_basis*offset)
		if safe.is_empty() or safe.point.distance_to(body.global_position)>float(design.policy.interact_distance_m):continue
		var direction: Vector3=body.global_position-safe.point;direction.y=0.
		# Keep the real bike beside the observer's silhouette, with its wheels
		# separated on screen, rather than centring it behind the avatar.
		var camera_yaw:=atan2(-direction.x,-direction.z)+(.65 if offset.x>0. else -.65)
		return {"point":safe.point,"toward":body.global_position+Vector3.UP*.7,"id":stations[0].id,"camera_yaw":camera_yaw,"camera_pitch_degrees":-18.,"camera_distance_m":4.2}
	return {}
func snapshot() -> Dictionary:
	var rows: Array=[]
	for row: Dictionary in bikes:rows.append({"name":row.body.name,"position":row.body.global_position,"on_floor":row.body.is_on_floor(),"mask":row.body.collision_mask,"layer":row.body.collision_layer,"rented":row.rented,"station_id":row.station_id,"kickstand_visible":row.kickstand.visible,"distance_m":row.distance_m,"wheel_phase":row.wheel_phase,"source_allowed":_footprint_allowed(row.body.global_position,row.body.global_basis)})
	return {"loaded":loaded,"error":load_error,"riding":riding,"rental_index":rental_index,"pending_pair_release_count":_collision_release_pending.size(),"exit_requested":exit_requested,"speed_mps":speed_mps,"steer_radians":steer_radians,"actual_distance_m":actual_distance_m,"maximum_step_m":maximum_step_m,"maximum_hand_gap_m":maximum_hand_gap_m,"maximum_pedal_sole_height_error_m":maximum_pedal_sole_height_error_m,"minimum_support_normal_y":_minimum_support_normal_y,"grounded_ticks":_grounded_ticks,"pedal_phase":_pedal_phase,"maximum_pedal_rotation":_maximum_pedal_rotation,"blocked_reason":blocked_reason,"bike_count":bikes.size(),"dock_count":stations.size(),"bikes":rows,"events":events.duplicate(true),"source_geometry_changed":false,"scope":"Authored physical game bicycle rental; no real station inventory, account, payment or legal cycling-access claim."}
