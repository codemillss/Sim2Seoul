extends "res://scripts/city_bike_service.gd"
## A separate authored parked car, derived from a retained source traffic lane.
## Shared ride ownership/capsule handoff remains in the bicycle base; all car
## envelope, road permissions, placement, seat and camera hooks are overridden.
const CAR_SIZE:=Vector3(2.20,1.65,4.50)
const TRAFFIC_PATH:="res://data/generated/traffic.json"
const WORLD_PATH:="res://resources/world_geometry/world.json"
var placement_audit: Array[Dictionary]=[]
var _drive_grid: Dictionary={}
var _car_steering_wheel: Node3D
var _driver_grips: Array[Node3D]=[]
var maximum_driver_hand_gap_m:=0.0
var source_ai_car_count_before:=0

func _design_path() -> String:return "res://assets/authored/car_service.json"
func _ride_label() -> String:return "자동차"
func _ride_status_prefix() -> String:return "DRIVABLE_CAR_READY"
func _fail(message: String) -> bool:return super._fail(message.replace("자전거","자동차"))
func setup(scene: Node3D) -> bool:
	if not is_instance_valid(scene):return false
	source_ai_car_count_before=scene.vehicles.size()+scene.neighborhood_population.traffic.vehicles.size()
	var world: Variant=JSON.parse_string(FileAccess.get_file_as_string(WORLD_PATH))
	if not world is Dictionary:return _fail("자동차 원본 도로 자료가 없습니다.")
	for mesh: Dictionary in world.meshes:
		if mesh.get("metadata",{}).get("display_mode","")!="drive":continue
		for offset: int in range(0,mesh.vertices.size(),9):
			var a:=Vector2(mesh.vertices[offset],mesh.vertices[offset+2]);var b:=Vector2(mesh.vertices[offset+3],mesh.vertices[offset+5]);var c:=Vector2(mesh.vertices[offset+6],mesh.vertices[offset+8])
			if absf((b-a).cross(c-a))<.0000001:continue
			var low:=a.min(b).min(c);var high:=a.max(b).max(c);var triangle:=PackedVector2Array([a,b,c])
			for x: int in range(floori(low.x/32.),floori(high.x/32.)+1):
				for z: int in range(floori(low.y/32.),floori(high.y/32.)+1):
					var key:=Vector2i(x,z)
					if not _drive_grid.has(key):_drive_grid[key]=[]
					_drive_grid[key].append(triangle)
	if _drive_grid.is_empty():return _fail("원본 차도 도형이 없습니다.")
	return super.setup(scene)

func _inside_drive(point: Vector2) -> bool:
	for triangle: PackedVector2Array in _drive_grid.get(Vector2i(floori(point.x/32.),floori(point.y/32.)),[]):
		var a: float=(triangle[1]-triangle[0]).cross(point-triangle[0]);var b: float=(triangle[2]-triangle[1]).cross(point-triangle[1]);var c: float=(triangle[0]-triangle[2]).cross(point-triangle[2])
		if (a>=-.000001 and b>=-.000001 and c>=-.000001) or (a<=.000001 and b<=.000001 and c<=.000001):return true
	return false
func _source_allowed(point: Vector3) -> bool:
	if not point.is_finite() or not host.player.free_roam_bounds.grow(-2.5).has_point(Vector2(point.x,point.z)):return false
	var local: Vector3=host.city.to_local(point);var flat:=Vector2(local.x,local.z)
	if _private_index.contains(flat) or not _inside_drive(flat):return false
	for door: Vector3 in _doors:
		if Vector2(door.x-point.x,door.z-point.z).length()<float(design.policy.door_clearance_m):return false
	return true
func _footprint_allowed(point: Vector3,basis: Basis) -> bool:
	# Check the complete road envelope on a dense lattice including corners,
	# edges and centre. Native box overlap/cast remains the collision predicate.
	for x: float in [-1.12,-.56,0.,.56,1.12]:
		for z: float in [-2.27,-1.70,-1.13,-.56,0.,.56,1.13,1.70,2.27]:
			var sample:=point+basis*Vector3(x,0,z)
			if not _source_allowed(sample) or _ground(sample).is_empty():return false
	return true
func _clear_box(at: Vector3,basis: Basis,exclude: Array[RID],motion:=Vector3.ZERO) -> bool:
	var query:=PhysicsShapeQueryParameters3D.new();var shape:=BoxShape3D.new();shape.size=CAR_SIZE;query.shape=shape;query.collision_mask=1|2|4|8|32;query.exclude=exclude;query.margin=.003
	query.transform=Transform3D(basis,at+basis*Vector3(0,CAR_SIZE.y*.5+.035,0))
	var space:=get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():return false
	query.motion=motion;return motion.is_zero_approx() or space.cast_motion(query)[0]>=.9999

func _lane_frame(route: Dictionary,station: float) -> Dictionary:
	var arc:=0.
	for index: int in range(1,route.xz.size()):
		var a:=Vector3(route.xz[index-1][0],0,route.xz[index-1][1]);var b:=Vector3(route.xz[index][0],0,route.xz[index][1]);var length:=a.distance_to(b)
		if station<=arc+length or index==route.xz.size()-1:
			if station<0. or station>float(route.length_m):return {}
			return {"point":host.city.to_global(a.lerp(b,clampf((station-arc)/length,0.,1.))),"direction":(b-a).normalized(),"segment":index-1}
		arc+=length
	return {}
func _make_station(record: Dictionary) -> bool:
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(TRAFFIC_PATH));var route: Dictionary={}
	if not raw is Dictionary:return false
	for candidate: Dictionary in raw.routes:
		if candidate.id==record.source_route:route=candidate;break
	if route.is_empty() or route.source_binding.feature_id!=record.source_feature_id or route.source_binding.source_refs!=record.source_refs:return false
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(WORLD_PATH));var matched_source:=false
	for mesh: Dictionary in world.meshes:
		var metadata: Dictionary=mesh.get("metadata",{})
		if metadata.get("feature_id","")==record.source_feature_id and metadata.get("display_mode","")=="drive" and metadata.get("source_refs",[])==record.source_refs:matched_source=true
	if not matched_source:return false
	var accepted: Dictionary={};var rejected: Array=[]
	for along: float in [0.,6.,-6.,12.,-12.,18.,-18.]:
		var station: float=float(record.station_m)+along;var frame:=_lane_frame(route,station)
		if frame.is_empty():continue
		var direction: Vector3=frame.direction;var side:=Vector3(direction.z,0,-direction.x);var requested: Vector3=frame.point+side*float(record.right_offset_m);var support:=_ground(requested)
		if support.is_empty():rejected.append({"station_m":station,"reason":"native_ground"});continue
		var yaw:=atan2(-direction.x,-direction.z);var basis:=_pose_basis(support.point,yaw);var excludes: Array[RID]=[host.player.get_rid(),support.rid]
		if is_instance_valid(host.terrain_surface.support):excludes.append(host.terrain_surface.support.get_rid())
		if not _footprint_allowed(support.point,basis) or not _clear_box(support.point,basis,excludes):rejected.append({"station_m":station,"reason":"road_private_door_or_native_full_box"});continue
		# Keep a clear native/source launch strip, not merely an empty parked box.
		var launch_clear:=true
		for distance: float in [2.,4.,6.]:
			var prospective: Vector3=support.point+direction*distance;var future_support:=_ground(prospective)
			if future_support.is_empty():launch_clear=false;break
			var future_basis:=_pose_basis(future_support.point,yaw)
			if not _footprint_allowed(future_support.point,future_basis) or not _clear_box(future_support.point,future_basis,excludes):launch_clear=false;break
		if not launch_clear:rejected.append({"station_m":station,"reason":"initial_forward_strip"});continue
		accepted={"point":support.point,"yaw":yaw,"station_m":station,"segment":frame.segment};break
	if accepted.is_empty():placement_audit.append({"source_route":record.source_route,"accepted":false,"rejected":rejected});return false
	var body:=BikeBody.new();body.name="PlayerCar";body.collision_layer=8;body.collision_mask=1|2|4|8|32;body.safe_margin=.001;body.floor_snap_length=.45;body.floor_max_angle=deg_to_rad(float(design.policy.maximum_grade_degrees));add_child(body)
	body.set_meta("authored_game_vehicle",true);body.set_meta("source_route",record.source_route);body.set_meta("source_feature_id",record.source_feature_id)
	var shape:=CollisionShape3D.new();shape.name="CollisionShape";var box:=BoxShape3D.new();box.size=CAR_SIZE;shape.shape=box;shape.position.y=CAR_SIZE.y*.5;body.add_child(shape)
	body.global_transform=Transform3D(_pose_basis(accepted.point,accepted.yaw),accepted.point+Vector3.UP*.025)
	var visual:=Node3D.new();visual.name="Visual";body.add_child(visual);var proxy:=PhysicsReset.new();proxy.name="RenderProxy";proxy.process_physics_priority=-100;visual.add_child(proxy)
	var row: Dictionary={"body":body,"visual":visual,"proxy":proxy,"shape":shape,"station_id":record.id,"rented":false,"yaw":accepted.yaw,"wheel_phase":0.,"distance_m":0.,"previous":body.global_transform,"current":body.global_transform,"front":null,"wheels":[],"crank":null,"pedals":[],"kickstand":null}
	_build_bike(row,proxy);bikes.append(row);stations.append({"id":record.id,"name":record.name,"point":accepted.point,"node":body,"source_route":record.source_route,"certified_footprint":true})
	placement_audit.append({"accepted":true,"source_route":record.source_route,"source_feature_id":record.source_feature_id,"source_refs":record.source_refs,"station_m":accepted.station_m,"segment":accepted.segment,"authored_right_offset_m":record.right_offset_m,"point":accepted.point,"rejected":rejected,"scope":"Separate authored game parking/launch placement on actual retained source road; not an observed parking bay or cloned AI actor."})
	return true

func _build_bike(row: Dictionary,parent: Node3D) -> void:
	var paint:=_mat(Color(.12,.43,.62),.35);var trim:=_mat(Color(.045,.065,.075));var silver:=_mat(Color(.57,.63,.65),.70);var rubber:=_mat(Color(.025,.03,.035));var glass:=_mat(Color(.20,.39,.47,.30));glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;glass.cull_mode=BaseMaterial3D.CULL_DISABLED
	_box(parent,"LowerBody",Vector3(1.80,.46,4.30),Vector3(0,.52,0),paint)
	_box(parent,"Hood",Vector3(1.76,.15,1.14),Vector3(0,.80,-1.48),paint)
	_box(parent,"Trunk",Vector3(1.76,.13,.88),Vector3(0,.80,1.63),paint)
	_box(parent,"CabinRoof",Vector3(1.47,.10,1.82),Vector3(0,1.48,.08),paint)
	var windshield:=_box(parent,"FrontWindshield",Vector3(1.40,.57,.035),Vector3(0,1.15,-.96),glass);windshield.rotation.x=deg_to_rad(25.)
	var rear_window:=_box(parent,"RearWindshield",Vector3(1.40,.53,.035),Vector3(0,1.17,1.04),glass);rear_window.rotation.x=deg_to_rad(-25.)
	for side: float in [-1.,1.]:
		_box(parent,"FrontDoor",Vector3(.045,.45,1.02),Vector3(side*.905,.79,-.45),paint)
		_box(parent,"RearDoor",Vector3(.045,.45,.89),Vector3(side*.905,.79,.55),paint)
		for z: float in [-.46,.54]:
			_box(parent,"SideGlass",Vector3(.025,.46,.85),Vector3(side*.746,1.18,z),glass)
			_box(parent,"DoorHandle",Vector3(.055,.035,.14),Vector3(side*.943,.93,z+.26),silver)
		for z: float in [-.98,.04,1.02]:_tube(parent,"WindowPillar",Vector3(side*.73,.98,z),Vector3(side*.73,1.48,z*.83),.025,paint)
		_box(parent,"MirrorStem",Vector3(.15,.025,.035),Vector3(side*.965,1.07,-.82),trim)
		_box(parent,"Mirror",Vector3(.12,.10,.20),Vector3(side*1.02,1.09,-.82),paint)
		_box(parent,"Headlight",Vector3(.50,.15,.035),Vector3(side*.56,.68,-2.17),_mat(Color(.97,.98,.82)))
		_box(parent,"TailLight",Vector3(.48,.15,.035),Vector3(side*.58,.70,2.17),_mat(Color(.75,.035,.025)))
		_box(parent,"RockerTrim",Vector3(.045,.08,3.62),Vector3(side*.915,.29,0),trim)
	_box(parent,"FrontGrille",Vector3(.90,.16,.035),Vector3(0,.49,-2.17),trim)
	_box(parent,"FrontBumper",Vector3(1.75,.10,.055),Vector3(0,.34,-2.18),silver)
	_box(parent,"RearBumper",Vector3(1.75,.10,.055),Vector3(0,.34,2.18),silver)
	for front: bool in [true,false]:
		var axle:=Node3D.new();axle.name="FrontSteeringAxle" if front else "RearAxle";axle.position.z=-1.34 if front else 1.34;parent.add_child(axle)
		if front:row.front=axle
		for side: float in [-1.,1.]:
			var wheel:=Node3D.new();wheel.name="WheelLeft" if side<0 else "WheelRight";wheel.position=Vector3(side*.865,.315,0);axle.add_child(wheel);row.wheels.append(wheel)
			for spec: Array in [[.215,.315,rubber],[.165,.205,silver]]:
				var torus:=TorusMesh.new();torus.inner_radius=spec[0];torus.outer_radius=spec[1];torus.rings=28;torus.ring_segments=8;var ring:=_mesh(wheel,"Tyre" if spec[2]==rubber else "AlloyRim",torus,spec[2]);ring.rotation.z=PI*.5
			_tube(wheel,"AxleHub",Vector3(-.075,0,0),Vector3(.075,0,0),.09,silver)
			for spoke: int in range(5):
				var angle:=TAU*spoke/5.;_tube(wheel,"RimSpoke",Vector3(side*.08,0,0),Vector3(side*.08,sin(angle)*.20,cos(angle)*.20),.013,silver)
	_box(parent,"CabinFloor",Vector3(1.64,.05,1.92),Vector3(0,.25,.08),trim)
	for x: float in [-.42,.42]:
		_box(parent,"FrontSeatCushion",Vector3(.58,.14,.60),Vector3(x,.49,-.10),_mat(Color(.15,.18,.20)))
		var back:=_box(parent,"FrontSeatBack",Vector3(.58,.67,.14),Vector3(x,.83,.22),trim);back.rotation.x=deg_to_rad(-7.)
		_box(parent,"Headrest",Vector3(.31,.24,.12),Vector3(x,1.17,.28),trim)
	_box(parent,"RearBench",Vector3(1.42,.18,.52),Vector3(0,.49,.78),trim)
	_box(parent,"Dashboard",Vector3(1.45,.19,.35),Vector3(0,.96,-.79),trim)
	_box(parent,"DashboardDisplay",Vector3(.34,.12,.025),Vector3(0,1.04,-.595),_mat(Color(.05,.38,.48)))
	var tilt:=Node3D.new();tilt.name="SteeringColumn";tilt.position=Vector3(-.42,.98,-.48);tilt.rotation.x=.90;parent.add_child(tilt)
	_car_steering_wheel=Node3D.new();_car_steering_wheel.name="SteeringWheel";tilt.add_child(_car_steering_wheel)
	var wheel_ring:=TorusMesh.new();wheel_ring.inner_radius=.145;wheel_ring.outer_radius=.17;wheel_ring.rings=24;wheel_ring.ring_segments=8;_mesh(_car_steering_wheel,"WheelRim",wheel_ring,trim)
	for side: float in [-1.,1.]:
		_tube(_car_steering_wheel,"WheelSpoke",Vector3.ZERO,Vector3(side*.155,0,0),.018,silver)
		var grip:=Node3D.new();grip.position=Vector3(side*.16,0,0);_car_steering_wheel.add_child(grip);_driver_grips.append(grip)
	var crank:=Node3D.new();crank.name="UnusedBicycleCrankAnchor";parent.add_child(crank);row.crank=crank
	var marker:=Node3D.new();marker.name="ParkedInteractionMarker";parent.add_child(marker);row.kickstand=marker
	_label(marker,"CarInteractionLabel","자동차 운전 체험\n앞좌석 문 옆에서 E",Vector3(0,2.16,0),.0028)
	var plate:=_label(parent,"GamePlate","SIM 01",Vector3(0,.53,-2.205),.0013);plate.billboard=BaseMaterial3D.BILLBOARD_DISABLED;plate.modulate=Color(.9,.95,.96)

func _other_transport_riding() -> bool:
	if host.has_method("_street_transport_riding_except"):return host._street_transport_riding_except(self)
	if host.has_method("_street_services"):
		for other: Node3D in host._street_services():
			if is_instance_valid(other) and other!=self and other.riding:return true
	return false
func _context_ready() -> bool:
	if not super._context_ready():return false
	return not (host.has_method("_shop_active") and host._shop_active())
func _door_distance() -> float:
	if bikes.is_empty():return INF
	var body: CharacterBody3D=bikes[0].body;var distance:=INF
	for side: float in [-1.,1.]:distance=minf(distance,host.player.global_position.distance_to(body.to_global(Vector3(side*1.18,0,-.38))))
	return distance
func _nearest_bike() -> int:return 0 if not bikes.is_empty() and _door_distance()<float(design.policy.interact_distance_m) else -1
func interaction_distance_m() -> float:return _door_distance() if loaded and _context_ready() else INF
func can_interact() -> bool:
	return super.can_interact() and (riding or host.player.free_roam_enabled)
func _near_station(_point: Vector3) -> String:return ""
func prompt_text() -> String:
	if not _context_ready():return ""
	if riding:return "자동차 · W 가속 / S 제동·후진\nA·D 조향 / Space 브레이크 / E 안전정차 후 내리기" if not exit_requested else "안전하게 정차하고 내릴 공간을 확인하는 중\nE · 취소하고 계속 운전"
	if _clock<_notice_until:return _notice
	if _nearest_bike()<0:return ""
	if not host.player.free_roam_enabled:return "자유 탐험 모드에서 E · 자동차 운전"
	if not _player_supported_for_mount():return "착지한 뒤 앞좌석 문 옆에서 E · 자동차 타기"
	if not _visible_bike(0):return "차 문이 보이는 열린 쪽으로 이동해 E"
	return "E · 자동차 운전석에 타기"
func _mount(index: int) -> bool:
	if not host.player.free_roam_enabled or not super._mount(index):return false
	host.rig.distance_max_m=maxf(host.rig.distance_max_m,10.);host.rig.pivot_height_m=1.25;host.rig.requested_distance=7.8;host.rig.current_distance=7.8;host.rig.yaw=bikes[index].yaw+.60;host.rig.pitch=deg_to_rad(-16.);host.rig.snap_to_target_pose()
	return true
func _safe_dismount() -> Dictionary:
	var body: CharacterBody3D=bikes[rental_index].body
	for offset: Vector3 in [Vector3(-1.85,0,-.35),Vector3(1.85,0,-.35),Vector3(-1.85,0,.95),Vector3(1.85,0,.95),Vector3(0,0,3.15),Vector3(0,0,-3.15)]:
		var safe: Dictionary=host.interior_visit._safe_external_point(body.to_global(offset))
		if not safe.is_empty():return safe
	return {}
func _attach_player(delta: float) -> void:
	if not riding:return
	var body: CharacterBody3D=bikes[rental_index].body
	host.player.global_transform=body.global_transform.translated_local(Vector3(-.42,-.20,-.10));host.player.get_node("Visual").rotation=Vector3.ZERO;host.player.velocity=Vector3.ZERO;host.player.physics_stepped.emit(delta)
func _rider_pose(measure:=true) -> void:
	if not riding:return
	var avatar: Node3D=host.exploration_avatar;avatar.position=Vector3.ZERO;avatar._upper_body.position=Vector3(0,.85,0);avatar._upper_body.rotation=Vector3(-.08,0,0)
	_car_steering_wheel.rotation.y=-steer_radians*1.8
	for side_name: String in ["Left","Right"]:
		var side: float=-1. if side_name=="Left" else 1.;var grip: Node3D=_driver_grips[0 if side<0 else 1]
		avatar._joints[side_name+"Thigh"].position.x=side*.15;avatar._leg_pose(side_name,Vector3(side*.15,.54,-.43));avatar._arm_to(side_name,avatar.to_local(grip.global_position))
		if measure:maximum_driver_hand_gap_m=maxf(maximum_driver_hand_gap_m,avatar._hands[0 if side<0 else 1].global_position.distance_to(grip.global_position))
func viewpoint() -> Dictionary:
	if not loaded or bikes.is_empty():return {}
	var body: CharacterBody3D=bikes[0].body
	for offset: Vector3 in [Vector3(-2.15,0,-.38),Vector3(2.15,0,-.38),Vector3(-2.10,0,.35),Vector3(2.10,0,.35)]:
		var safe: Dictionary=host.interior_visit._safe_external_point(body.to_global(offset))
		if safe.is_empty():continue
		var direction: Vector3=body.global_position-safe.point;direction.y=0.
		return {"point":safe.point,"toward":body.global_position+Vector3.UP*.85,"id":stations[0].id,"camera_yaw":atan2(-direction.x,-direction.z)+(.45 if offset.x>0. else -.45),"camera_pitch_degrees":-14.,"camera_distance_m":7.2}
	return {}
func interact() -> bool:return handle_interact()
func destination(kind: String="car_station") -> Dictionary:return viewpoint() if kind=="car_station" else {}
func after_external_teleport() -> void:cancel_ride_for_teleport()
func snapshot() -> Dictionary:
	var data: Dictionary=super.snapshot()
	for key: String in ["bike_count","bikes","pedal_phase","maximum_pedal_rotation","maximum_pedal_sole_height_error_m"]:data.erase(key)
	data.car_count=bikes.size();data.cars=[];data.placement_audit=placement_audit;data.maximum_driver_hand_gap_m=maximum_driver_hand_gap_m;data.car_collision_size_m=CAR_SIZE
	for row: Dictionary in bikes:data.cars.append({"position":row.body.global_position,"on_floor":row.body.is_on_floor(),"rented":row.rented,"distance_m":row.distance_m,"yaw":row.yaw,"source_allowed":_footprint_allowed(row.body.global_position,row.body.global_basis),"layer":row.body.collision_layer,"mask":row.body.collision_mask})
	data.original_ai_car_count_before=source_ai_car_count_before;data.original_ai_car_count_now=host.vehicles.size()+host.neighborhood_population.traffic.vehicles.size()
	data.scope="One separately authored parked game car on a retained source road; player controlled, full native car box and road/private/door/support checks. Original 14 AI actors/routes remain unchanged; no surveyed parking location or official traffic-operation claim."
	return data
