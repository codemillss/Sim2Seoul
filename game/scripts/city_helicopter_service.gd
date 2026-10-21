extends Node3D
## One authored, bounded arcade flight experience. No source support, building,
## road, actor controller or player collision shape is modified.
const DATA_PATH := "res://assets/authored/helicopter_service.json"
const ASCEND := &"helicopter_ascend"
const DESCEND := &"helicopter_descend"
class AircraftBody extends CharacterBody3D:
	func _physics_process(_delta: float) -> void:pass
class RenderReset extends Node3D:
	func _physics_process(_delta: float) -> void:transform=Transform3D.IDENTITY
var host: Node3D
var loaded:=false
var load_error:=""
var riding:=false
var body: CharacterBody3D
var design: Dictionary={}
var helipad: Dictionary={}
var site_audit: Array[Dictionary]=[]
var events: Array[Dictionary]=[]
var speed_mps:=0.0
var vertical_speed_mps:=0.0
var rotor_fraction:=0.0
var rotor_phase:=0.0
var tail_phase:=0.0
var actual_distance_m:=0.0
var maximum_step_m:=0.0
var blocked_reason:=""
var exit_requested:=false
var return_pending:=false
var _clock:=0.0
var _return_elapsed:=0.0
var _saved: Dictionary={}
var _release: Dictionary={}
var _notice:=""
var _notice_until:=0.0
var _shapes: Array[CollisionShape3D]=[]
var _proxy: Node3D
var _main_rotor: Node3D
var _tail_rotor: Node3D
var _passenger: Node3D
var _previous:=Transform3D.IDENTITY
var _current:=Transform3D.IDENTITY
var _private_index: RefCounted
var _walk_index: RefCounted
var _source_triangles: Array[PackedVector2Array]=[]
var _water_triangles: Array[PackedVector2Array]=[]
var _terrain_rid: RID
var _doors: Array[Vector3]=[]
var _yaw:=0.0
var _neutral_required:=false

func _event(kind: String,evidence: Dictionary={}) -> void:
	if events.size()>=120:events.pop_front()
	events.append({"event":kind,"clock_s":_clock,"evidence":evidence})
func _fail(message: String) -> bool:load_error=message;push_error(message);return false
func setup(scene: Node3D) -> bool:
	if loaded or not is_instance_valid(scene) or not is_inside_tree():return false
	host=scene;process_mode=Node.PROCESS_MODE_PAUSABLE;process_physics_priority=0
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not raw is Dictionary or raw.get("schema_version")!=1:return _fail("헬리콥터 체험 자료가 다릅니다.")
	design=raw
	for path: String in design.source_hashes:
		if FileAccess.get_sha256(path)!=String(design.source_hashes[path]):return _fail("헬리콥터와 원본 거리 자료가 다릅니다.")
	if not is_instance_valid(host.get("terrain_surface")) or not host.terrain_surface.loaded:return _fail("비행 체험 지면이 준비되지 않았습니다.")
	_terrain_rid=host.terrain_surface.support.get_rid()
	var index_script:=preload("res://scripts/source_polygon_index.gd")
	_private_index=index_script.new();_private_index.setup(host.city.private_cache,Callable(host.city,"_contains"))
	_walk_index=index_script.new();_walk_index.setup(host.city.movement_cache,Callable(host.city,"_contains"))
	for record: Dictionary in host.interior_visit.catalog:
		for entry: Dictionary in record.entry_candidates:_doors.append(entry.entrance)
	var world: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_geometry/world.json"))
	if not world is Dictionary:return _fail("비행장 원본 부지를 확인하지 못했습니다.")
	for mesh: Dictionary in world.meshes:
		var source_grass: bool=mesh.id==design.helipad.source_ground_feature
		var source_water: bool=mesh.get("material","")=="water"
		if not source_grass and not source_water:continue
		var vertices: Array=mesh.vertices
		for i: int in range(0,vertices.size(),9):
			var triangle:=PackedVector2Array([Vector2(vertices[i],vertices[i+2]),Vector2(vertices[i+3],vertices[i+5]),Vector2(vertices[i+6],vertices[i+8])])
			if source_grass:_source_triangles.append(triangle)
			if source_water:_water_triangles.append(triangle)
	if _source_triangles.is_empty():return _fail("서울광장 원본 부지가 없습니다.")
	_make_aircraft()
	var site:=_choose_site()
	if site.is_empty():body.queue_free();return _fail("원본 서울광장에서 충분히 넓고 평탄한 게임 착륙 부지를 확보하지 못했습니다.")
	body.global_transform=Transform3D(Basis(Vector3.UP,site.yaw),site.point);_yaw=site.yaw
	self.set("helipad",site.duplicate(true))
	_previous=body.global_transform;_current=_previous;_proxy.global_transform=_current
	_build_pad(site)
	_bind_key(ASCEND,KEY_SPACE);_bind_key(DESCEND,KEY_CTRL)
	loaded=true;print("CITY_HELICOPTER_READY aircraft=1 source_ground=",design.helipad.source_ground_feature," source_geometry_changed=false arcade_flight=true");return true

func _bind_key(action: StringName,keycode: Key) -> void:
	if not InputMap.has_action(action):InputMap.add_action(action)
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode==keycode and event.device==-1:return
	var key:=InputEventKey.new();key.device=-1;key.physical_keycode=keycode;InputMap.action_add_event(action,key)
func _mat(color: Color,metallic:=0.0) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.55;material.metallic=metallic;return material
func _mesh(parent: Node3D,title: String,mesh: Mesh,material: Material,at:=Vector3.ZERO) -> MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=title;node.mesh=mesh;node.material_override=material;node.position=at;parent.add_child(node);return node
func _box(parent: Node3D,title: String,size: Vector3,at: Vector3,material: Material) -> MeshInstance3D:
	var mesh:=BoxMesh.new();mesh.size=size;return _mesh(parent,title,mesh,material,at)
func _tube(parent: Node3D,title: String,a: Vector3,b: Vector3,radius: float,material: Material) -> MeshInstance3D:
	var mesh:=CylinderMesh.new();mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=a.distance_to(b);mesh.radial_segments=12
	var node:=_mesh(parent,title,mesh,material,(a+b)*.5);node.basis=Basis(Quaternion(Vector3.UP,(b-a).normalized()));return node
func _label(parent: Node3D,title: String,text: String,at: Vector3,size:=.003) -> Label3D:
	var label:=Label3D.new();label.name=title;label.text=text;label.position=at;label.pixel_size=size;label.font_size=42;label.modulate=Color(.97,.99,1.);label.outline_modulate=Color(.06,.16,.23);label.outline_size=5;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;parent.add_child(label);return label
func _collision_box(title: String,size: Vector3,at: Vector3) -> void:
	var shape:=BoxShape3D.new();shape.size=size;var node:=CollisionShape3D.new();node.name=title;node.shape=shape;node.position=at;body.add_child(node);_shapes.append(node)
func _make_aircraft() -> void:
	body=AircraftBody.new();body.name="GameHelicopter";body.collision_layer=4;body.collision_mask=1|2|4|8|32;body.safe_margin=.002;body.floor_stop_on_slope=true;body.floor_snap_length=.12;body.floor_max_angle=deg_to_rad(float(design.policy.maximum_landing_grade_degrees));add_child(body)
	_collision_box("CabinCollision",Vector3(2.1,1.75,3.4),Vector3(0,1.35,-.4))
	_collision_box("EngineMastCollision",Vector3(1.15,.85,2.),Vector3(0,2.55,.10))
	_collision_box("TailBoomCollision",Vector3(.5,.55,3.6),Vector3(0,1.5,2.55))
	_collision_box("TailplaneCollision",Vector3(1.76,.13,.51),Vector3(0,1.43,3.75))
	_collision_box("TailFinCollision",Vector3(.20,1.50,.90),Vector3(0,1.95,4.40))
	_collision_box("TailRotorCollision",Vector3(.3,1.5,1.5),Vector3(-.33,1.7,4.45))
	for side: float in [-1.,1.]:_collision_box("SkidCollision",Vector3(.18,.32,3.85),Vector3(side*1.1,.20,-.31))
	var disc:=CylinderShape3D.new();disc.radius=4.05;disc.height=.16;var rotor_shape:=CollisionShape3D.new();rotor_shape.name="FullRotorDiscCollision";rotor_shape.shape=disc;rotor_shape.position.y=2.95;body.add_child(rotor_shape);_shapes.append(rotor_shape)
	_proxy=RenderReset.new();_proxy.name="AircraftRenderProxy";_proxy.process_physics_priority=-100;_proxy.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF;body.add_child(_proxy)
	var orange:=_mat(Color(.88,.23,.075));var cream:=_mat(Color(.90,.94,.93));var dark:=_mat(Color(.055,.075,.085));var silver:=_mat(Color(.55,.62,.65),.65);var blue:=_mat(Color(.10,.28,.38));var red:=_mat(Color(.82,.035,.025))
	var fuselage:=SphereMesh.new();fuselage.radius=1.;fuselage.height=2.;fuselage.radial_segments=24;fuselage.rings=12
	var cabin:=_mesh(_proxy,"RoundedCabin",fuselage,cream,Vector3(0,1.38,-.4));cabin.scale=Vector3(1.02,.83,1.64)
	_box(_proxy,"CabinLowerOrangeBand",Vector3(1.95,.36,2.35),Vector3(0,.95,-.55),orange)
	_box(_proxy,"FrontWindshield",Vector3(1.60,.73,.11),Vector3(0,1.64,-1.88),blue)
	_box(_proxy,"WindshieldDivider",Vector3(.055,.78,.14),Vector3(0,1.66,-1.95),cream)
	for side: float in [-1.,1.]:
		_box(_proxy,"SideCockpitWindow",Vector3(.10,.70,.90),Vector3(side*.99,1.66,-1.05),blue)
		_box(_proxy,"DoorFrame",Vector3(.07,.82,.07),Vector3(side*1.025,1.55,-.35),dark)
		_box(_proxy,"DoorHandle",Vector3(.08,.045,.22),Vector3(side*1.075,1.15,-.36),silver)
		_tube(_proxy,"LandingSkid",Vector3(side*1.1,.12,-1.90),Vector3(side*1.1,.12,1.50),.075,silver)
		_tube(_proxy,"SkidFrontCurve",Vector3(side*1.1,.12,-1.90),Vector3(side*1.1,.28,-2.12),.075,silver)
		for z: float in [-1.,.7]:_tube(_proxy,"SkidStrut",Vector3(side*.65,.8,z),Vector3(side*1.1,.15,z),.055,dark)
	_tube(_proxy,"TailBoom",Vector3(0,1.48,.8),Vector3(0,1.65,4.55),.20,orange)
	_box(_proxy,"TailFin",Vector3(.09,1.30,.80),Vector3(0,1.91,4.40),cream)
	_box(_proxy,"Tailplane",Vector3(1.70,.07,.45),Vector3(0,1.43,3.75),orange)
	_box(_proxy,"EngineCowling",Vector3(1.1,.5,1.45),Vector3(0,2.16,.05),orange)
	for x: float in [-.30,.30]:_tube(_proxy,"Exhaust",Vector3(x,2.20,.65),Vector3(x,2.20,1.0),.105,dark)
	_tube(_proxy,"RotorMast",Vector3(0,2.35,0),Vector3(0,2.95,0),.10,silver)
	_main_rotor=Node3D.new();_main_rotor.name="MainRotor";_main_rotor.position.y=2.95;_proxy.add_child(_main_rotor)
	_box(_main_rotor,"RotorBladeEastWest",Vector3(8.,.065,.22),Vector3.ZERO,dark)
	_box(_main_rotor,"RotorBladeNorthSouth",Vector3(.22,.065,8.),Vector3.ZERO,dark)
	for end: float in [-1.,1.]:
		_box(_main_rotor,"MainRotorTip",Vector3(.35,.07,.24),Vector3(end*3.80,0,0),cream)
		_box(_main_rotor,"MainRotorTip",Vector3(.24,.07,.35),Vector3(0,0,end*3.80),cream)
	_tail_rotor=Node3D.new();_tail_rotor.name="TailRotor";_tail_rotor.position=Vector3(-.33,1.70,4.45);_proxy.add_child(_tail_rotor)
	_box(_tail_rotor,"TailRotorBlade",Vector3(.07,1.40,.12),Vector3.ZERO,dark);_box(_tail_rotor,"TailRotorBlade",Vector3(.07,.12,1.40),Vector3.ZERO,dark)
	_box(_proxy,"TailBeacon",Vector3(.13,.12,.13),Vector3(0,2.63,4.40),red)
	_label(_proxy,"AircraftName","SEOUL · 게임 비행",Vector3(.02,1.02,1.08),.0023)
	_passenger=Node3D.new();_passenger.name="SeatedPassenger";_proxy.add_child(_passenger);_passenger.visible=false
	_box(_passenger,"PilotTorso",Vector3(.34,.48,.26),Vector3(.4,1.32,-.84),dark)
	var head:=SphereMesh.new();head.radius=.15;head.height=.30;_mesh(_passenger,"PilotHead",head,_mat(Color(.70,.52,.35)),Vector3(.4,1.73,-.88))

func _terrain_point(at: Vector3) -> Dictionary:
	var y: float=host.terrain_surface.ground_y_world(at)
	if not is_finite(y):return {}
	var hit:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x,y+.75,at.z),Vector3(at.x,y-.75,at.z),1|32))
	if hit.is_empty() or hit.normal.y<cos(deg_to_rad(float(design.policy.maximum_landing_grade_degrees))):return {}
	return {"point":Vector3(at.x,hit.position.y,at.z),"normal":hit.normal,"rid":hit.rid}
func _on_source_grass(at: Vector3) -> bool:
	var local: Vector3=host.city.to_local(at);var point:=Vector2(local.x,local.z)
	for triangle: PackedVector2Array in _source_triangles:
		if Geometry2D.is_point_in_polygon(point,triangle):return true
	return false
func _public_ground(at: Vector3) -> bool:
	var local: Vector3=host.city.to_local(at);var point:=Vector2(local.x,local.z)
	if _private_index.contains(point) or not _flight_bounds_valid(at):return false
	for triangle: PackedVector2Array in _water_triangles:
		if Geometry2D.is_point_in_polygon(point,triangle):return false
	for door: Vector3 in _doors:
		if Vector2(door.x-at.x,door.z-at.z).length()<float(design.policy.door_clearance_m):return false
	return true
func _flight_bounds_valid(at: Vector3) -> bool:
	if not at.is_finite():return false
	var point:=Vector2(at.x,at.z);var radius:=float(design.policy.protected_radius_m)
	if not host.player.free_roam_bounds.grow(-radius).has_point(point):return false
	var polygon: PackedVector2Array=host.player.free_roam_polygon
	if polygon.size()<3:return true
	if not Geometry2D.is_point_in_polygon(point,polygon):return false
	for i: int in range(polygon.size()):
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()]))<radius:return false
	return true
func _volume_clear(at: Vector3,yaw: float,exclude_player:=true) -> bool:
	var exclude: Array[RID]=[body.get_rid(),_terrain_rid]
	if exclude_player:exclude.append(host.player.get_rid())
	for collider: CollisionShape3D in _shapes:
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=collider.shape;query.transform=Transform3D(Basis(Vector3.UP,yaw),at)*collider.transform;query.collision_mask=1|2|4|8|32;query.exclude=exclude;query.margin=.003
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return false
	return true
func _choose_site() -> Dictionary:
	var route: Dictionary={}
	for item: Dictionary in host.city.public_data.routes:
		if item.id==design.helipad.source_route:route=item;break
	if route.is_empty():return {}
	var ai: Array=route.xz[design.helipad.source_segment[0]];var bi: Array=route.xz[design.helipad.source_segment[1]]
	var a: Vector3=host.city.to_global(Vector3(ai[0],0,ai[1]));var b: Vector3=host.city.to_global(Vector3(bi[0],0,bi[1]));var forward: Vector3=(b-a).normalized();forward.y=0.;forward=forward.normalized();var side:=Vector3(forward.z,0,-forward.x);var yaw:=atan2(-forward.x,-forward.z)
	for fraction: float in design.helipad.candidate_fractions:
		for offset: float in design.helipad.candidate_side_offsets_m:
			var desired:=a.lerp(b,fraction)+side*offset;var reason:="";var minimum:=INF;var maximum:=-INF
			for radius: float in [0.,2.7,5.4]:
				for step: int in range(16 if radius>0. else 1):
					var angle:=TAU*step/16.;var at:=desired+Vector3(cos(angle),0,sin(angle))*radius
					if not _on_source_grass(at) or not _public_ground(at):reason="outside_original_public_grass_or_bounds";break
					var sample:=_terrain_point(at)
					if sample.is_empty():reason="native_support_or_grade";break
					minimum=minf(minimum,sample.point.y);maximum=maxf(maximum,sample.point.y)
				if not reason.is_empty():break
			if reason.is_empty() and maximum-minimum>.55:reason="ground_height_spread"
			var base:=_terrain_point(desired)
			if reason.is_empty() and not base.is_empty():
				desired.y=base.point.y+.12
				if not _volume_clear(desired,yaw):reason="aircraft_full_native_envelope_occupied"
			site_audit.append({"fraction":fraction,"side_offset_m":offset,"point":desired,"accepted":reason.is_empty(),"reason":reason,"sample_height_range_m":[minimum,maximum]})
			if reason.is_empty():return {"id":design.helipad.id,"name":design.helipad.name,"point":desired,"yaw":yaw,"source_ground_feature":design.helipad.source_ground_feature,"source_route":design.helipad.source_route,"source_segment":design.helipad.source_segment,"fraction":fraction,"side_offset_m":offset,"native_envelope_clear":true,"native_existing_terrain":true}
	return {}
func _marking_strip(parent: Node3D,points: Array[Vector3],width: float,material: Material) -> void:
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array()
	for i: int in range(points.size()-1):
		var a:=points[i];var b:=points[i+1];var direction:=b-a;direction.y=0.;var side:=Vector3(direction.z,0,-direction.x).normalized()*width*.5
		var quad: Array[Vector3]=[a-side,a+side,b+side,b-side]
		for j: int in range(4):quad[j].y=host.terrain_surface.ground_y_world(quad[j])+.021
		for j: int in [0,1,2,0,2,3]:vertices.append(quad[j]);normals.append(Vector3.UP)
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);_mesh(parent,"TerrainConformingPaint",mesh,material)
func _build_pad(site: Dictionary) -> void:
	var pad:=Node3D.new();pad.name="HelipadMarkingsOnExistingTerrain";add_child(pad);var white:=_mat(Color(.96,.98,.94));white.cull_mode=BaseMaterial3D.CULL_DISABLED
	var points: Array[Vector3]=[]
	for step: int in range(65):
		var angle:=TAU*step/64.;points.append(site.point+Vector3(cos(angle),0,sin(angle))*float(design.policy.pad_radius_m))
	_marking_strip(pad,points,.18,white)
	var basis:=Basis(Vector3.UP,site.yaw)
	for x: float in [-.90,.90]:_marking_strip(pad,[site.point+basis*Vector3(x,0,-1.40),site.point+basis*Vector3(x,0,1.40)],.28,white)
	_marking_strip(pad,[site.point+basis*Vector3(-.90,0,0),site.point+basis*Vector3(.90,0,0)],.28,white)
	_label(pad,"GameHelipadWayfinding","헬리콥터 · 게임 착륙장\n기체 옆에서 E 탑승",site.point+Vector3.UP*4.6,.004)

func _other_riding() -> bool:
	if host.has_method("_street_transport_riding_except"):return host._street_transport_riding_except(self)
	for name: String in ["city_bike_service","city_scooter_service","city_bus_service","drivable_car_service"]:
		var service: Variant=host.get(name)
		if is_instance_valid(service) and service!=self and service.get("riding")==true:return true
	return false
func _context_ready() -> bool:
	if not loaded or not host.runtime_ok or get_tree().paused or host.menu.visible or host.player.interior_active or host.interior_visit.active:return false
	if host.has_method("_shop_active") and host._shop_active():return false
	return not _other_riding()
func _landed() -> bool:
	if not is_instance_valid(body) or absf(vertical_speed_mps)>.35 or absf(speed_mps)>.4:return false
	var minimum:=INF;var maximum:=-INF
	for x: float in [-1.1,1.1]:
		for z: float in [-1.3,1.2]:
			var at: Vector3=body.to_global(Vector3(x,0,z));var support:=_terrain_point(at)
			if support.is_empty() or not _public_ground(at):return false
			var gap: float=at.y-support.point.y
			if gap<-.08 or gap>.32:return false
			minimum=minf(minimum,support.point.y);maximum=maxf(maximum,support.point.y)
	return maximum-minimum<.36
func _player_grounded() -> bool:
	if absf(host.player.velocity.y)>.3:return false
	var support:=_terrain_point(host.player.global_position)
	return not support.is_empty() and absf(host.player.global_position.y-support.point.y)<.15
func _entry_visible() -> bool:
	var exclude: Array[RID]=[host.player.get_rid(),body.get_rid()]
	for human: CharacterBody3D in host.traffic.humans:
		if is_instance_valid(human):exclude.append(human.get_rid())
	var ray:=PhysicsRayQueryParameters3D.create(host.player.global_position+Vector3.UP,body.to_global(Vector3(0,1.2,-.6)),1|4|8|32,exclude)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
func interaction_distance_m() -> float:
	if not _context_ready():return INF
	if riding:return 0.
	var delta: Vector3=host.player.global_position-body.global_position
	return Vector2(delta.x,delta.z).length() if Vector2(delta.x,delta.z).length()<=float(design.policy.interact_distance_m) else INF
func can_interact() -> bool:
	if not _context_ready():return false
	if riding:return true
	return not return_pending and _release.is_empty() and not host.player.facility_control and host.player.is_physics_processing() and _landed() and _player_grounded() and is_finite(interaction_distance_m()) and _entry_visible()
func prompt_text() -> String:
	if not _context_ready():return ""
	if _clock<_notice_until:return _notice
	if riding:
		if exit_requested:return "로터를 멈추고 안전한 하차 공간을 확인하는 중\nE · 하차 취소"
		if rotor_fraction<.90:return "헬리콥터 · 로터 준비 %d%%\nSpace 이륙 · W/S 전후 · A/D 회전 · Ctrl 하강"%roundi(rotor_fraction*100.)
		return "헬리콥터 · W/S 전후 · A/D 회전 · Space 상승 · Ctrl 하강\n"+("착륙 완료 · E 로터 정지 후 내리기" if _landed() else "비행 중 · 평탄한 공공 지면에 착륙한 뒤 E 하차")
	if is_finite(interaction_distance_m()):return "E · 헬리콥터 탑승 · 게임 비행 체험" if can_interact() else "기체 옆의 평탄한 지면에 서서 E · 헬리콥터 체험"
	return ""
func _notice_message(text: String) -> void:_notice=text;_notice_until=_clock+3.
func handle_interact() -> bool:
	if not _context_ready():return false
	if riding:
		if exit_requested:exit_requested=false;_neutral_required=true;_event("exit_cancelled");return true
		if not _landed():_notice_message("공중에서는 내릴 수 없습니다. Ctrl로 평탄한 공공 지면에 착륙한 뒤 E를 눌러주세요.");_event("airborne_exit_rejected");return true
		exit_requested=true;_event("landed_exit_requested");return true
	if not can_interact():return false
	if not _volume_clear(body.global_position,_yaw):_notice_message("헬리콥터 주변에 사람이나 물체가 있습니다. 공간이 비면 E를 다시 눌러주세요.");_event("boarding_occupied_rejected");return true
	var player: CharacterBody3D=host.player
	# The cockpit proxy keeps the purchased outfit's actual torso colour.
	for mesh: MeshInstance3D in host.exploration_avatar._meshes:
		if String(mesh.get_meta("avatar_part",""))=="Torso":
			_passenger.get_node("PilotTorso").material_override=mesh.material_override
			break
	_saved={"physics":player.is_physics_processing(),"layer":player.collision_layer,"mask":player.collision_mask,"visual":player.get_node("Visual").transform,"avatar_visible":host.exploration_avatar.visible,"rig_pivot":host.rig.pivot_height_m,"rig_distance":host.rig.requested_distance,"rig_current":host.rig.current_distance,"rig_max":host.rig.distance_max_m,"rig_yaw":host.rig.yaw,"rig_pitch":host.rig.pitch,"query_exclude":host.rig._query.exclude.duplicate()}
	player.set_facility_control(true);player.set_physics_process(false);player.velocity=Vector3.ZERO;body.add_collision_exception_with(player);player.add_collision_exception_with(body)
	var exclude: Array[RID]=host.rig._query.exclude.duplicate();exclude.append(body.get_rid());host.rig._query.exclude=exclude;host.rig.arm.add_excluded_object(body.get_rid())
	host.exploration_avatar.visible=false;_passenger.visible=true;riding=true;exit_requested=false;_neutral_required=true;_notice="";_notice_until=0.;speed_mps=0.;vertical_speed_mps=0.
	host.rig.distance_max_m=maxf(host.rig.distance_max_m,18.);host.rig.pivot_height_m=1.4;host.rig.requested_distance=12.;host.rig.current_distance=12.;host.rig.yaw=_yaw+.45;host.rig.pitch=deg_to_rad(-20.)
	_attach_player(0.);host.rig.snap_to_target_pose();_event("boarded");return true
func interact() -> bool:return handle_interact()
func _attach_player(delta: float) -> void:
	if not riding:return
	host.player.global_transform=body.global_transform.translated_local(Vector3(.40,.90,-.70));host.player.velocity=Vector3.ZERO;host.player.physics_stepped.emit(delta)
func _safe_exit() -> Dictionary:
	for offset: Vector3 in [Vector3(2.3,0,-.6),Vector3(-2.3,0,-.6),Vector3(2.6,0,.7),Vector3(-2.6,0,.7)]:
		var at:=body.to_global(offset)
		if not _public_ground(at):continue
		var safe: Dictionary=host.interior_visit._safe_external_point(at)
		if not safe.is_empty() and _player_exit_supported(safe.point):return safe
	return {}
func _player_exit_supported(at: Vector3) -> bool:
	var support:=_terrain_point(at)
	return not support.is_empty() and absf(at.y-support.point.y)<.2
func _restore_player(delayed: bool) -> void:
	var player: CharacterBody3D=host.player
	_release={"tick":Engine.get_physics_frames()+2,"hold":delayed,"physics":bool(_saved.physics)}
	player.collision_layer=int(_saved.layer);player.collision_mask=int(_saved.mask);player.get_node("Visual").transform=_saved.visual
	if not delayed:player.set_facility_control(false);player.set_physics_process(bool(_saved.physics))
	player.require_neutral_input();player.reset_physics_interpolation();host.exploration_avatar.visible=bool(_saved.avatar_visible);_passenger.visible=false
	host.rig._query.exclude=_saved.query_exclude;host.rig.arm.remove_excluded_object(body.get_rid());host.rig.pivot_height_m=_saved.rig_pivot;host.rig.distance_max_m=_saved.rig_max;host.rig.requested_distance=_saved.rig_distance;host.rig.current_distance=minf(host.rig.current_distance,host.rig.requested_distance);host.rig.yaw=_saved.rig_yaw;host.rig.pitch=_saved.rig_pitch
	riding=false;exit_requested=false;speed_mps=0.;vertical_speed_mps=0.;_saved.clear();host.rig.snap_to_target_pose()
func _finish_release() -> void:
	if _release.is_empty() or riding or Engine.get_physics_frames()<int(_release.tick):return
	for collider: CollisionShape3D in _shapes:
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=collider.shape;query.transform=collider.global_transform;query.collision_mask=host.player.collision_layer;query.exclude=[body.get_rid()]
		for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query,4):
			if hit.collider==host.player:return
	body.remove_collision_exception_with(host.player);host.player.remove_collision_exception_with(body)
	if _release.hold and not _other_riding():host.player.set_facility_control(false);host.player.set_physics_process(bool(_release.physics));host.player.require_neutral_input()
	_release.clear();_event("native_capsule_restored")
func _try_exit() -> void:
	if not _landed() or rotor_fraction>.01:return
	var safe:=_safe_exit()
	if safe.is_empty():blocked_reason="dismount_blocked";return
	host.player.global_transform=Transform3D(Basis.IDENTITY,safe.point);_restore_player(true);_event("disembarked",{"point":safe.point});_notice_message("헬리콥터에서 내렸습니다.")
func cancel_ride_for_teleport() -> void:
	if not riding:return
	_restore_player(false);return_pending=true;_return_elapsed=.5;_event("external_teleport_restored_player")
func after_external_teleport() -> void:cancel_ride_for_teleport()
func cancel_after_teleport() -> void:cancel_ride_for_teleport()
func _try_return_home() -> void:
	if not return_pending or not _volume_clear(helipad.point,helipad.yaw):return
	body.global_transform=Transform3D(Basis(Vector3.UP,helipad.yaw),helipad.point);body.velocity=Vector3.ZERO;body.reset_physics_interpolation();_yaw=helipad.yaw;_previous=body.global_transform;_current=_previous;_proxy.global_transform=_current;return_pending=false;rotor_fraction=0.;_event("game_aircraft_returned_to_clear_home_pad")
func _motion_fraction(motion: Vector3) -> float:
	var fraction:=1.;var exclude: Array[RID]=[body.get_rid(),host.player.get_rid(),_terrain_rid]
	for collider: CollisionShape3D in _shapes:
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=collider.shape;query.transform=collider.global_transform;query.motion=motion;query.collision_mask=1|2|4|8|32;query.exclude=exclude;query.margin=.003
		fraction=minf(fraction,get_world_3d().direct_space_state.cast_motion(query)[0])
	return fraction
func _physics_process(delta: float) -> void:
	if not loaded or delta<=0.:return
	_finish_release();_clock+=delta;_previous=_current
	_return_elapsed+=delta
	if return_pending and _return_elapsed>=.5:_return_elapsed=0.;_try_return_home()
	var target_rotor:=1. if riding and not exit_requested or return_pending else 0.
	rotor_fraction=move_toward(rotor_fraction,target_rotor,delta/float(design.policy.rotor_spinup_seconds if target_rotor>rotor_fraction else design.policy.rotor_spindown_seconds))
	rotor_phase=fmod(rotor_phase+rotor_fraction*35.*delta,TAU);tail_phase=fmod(tail_phase+rotor_fraction*52.*delta,TAU);_main_rotor.rotation.y=rotor_phase;_tail_rotor.rotation.x=tail_phase
	if not riding:
		body.velocity=Vector3.ZERO if return_pending else Vector3(0,-.12 if body.is_on_floor() else maxf(body.velocity.y-9.8*delta,-5.),0)
		if not return_pending:body.move_and_slide()
		_current=body.global_transform;return
	var intent: Vector2=host.input_router.movement_intent();var ascend:=Input.is_action_pressed(ASCEND);var descend:=Input.is_action_pressed(DESCEND)
	if _neutral_required or host.player.input_latched:
		if intent.is_zero_approx() and not ascend and not descend:_neutral_required=false;host.player.input_latched=false
		intent=Vector2.ZERO;ascend=false;descend=false
	var enabled:=rotor_fraction>.90 and not exit_requested
	var requested_yaw:=_yaw-intent.x*float(design.policy.yaw_radians_per_second)*delta if enabled else _yaw
	if _volume_clear(body.global_position,requested_yaw):_yaw=requested_yaw;body.global_rotation.y=_yaw
	else:blocked_reason="rotation_occupied"
	var target_speed:=0.
	if enabled:target_speed=-intent.y*float(design.policy.maximum_forward_mps if intent.y<0. else design.policy.maximum_reverse_mps)
	var rate:=float(design.policy.horizontal_acceleration_mps2 if not is_zero_approx(target_speed) else design.policy.horizontal_braking_mps2)
	speed_mps=move_toward(speed_mps,target_speed,rate*delta)
	var target_vertical:=float(design.policy.ascent_mps) if ascend and not descend and enabled else (-float(design.policy.descent_mps) if descend and not ascend and enabled else 0.)
	var ground_y: float=host.terrain_surface.ground_y_world(body.global_position)
	if target_vertical<0. and body.global_position.y-ground_y<.6:target_vertical=-.6
	if exit_requested:target_vertical=-.12
	vertical_speed_mps=move_toward(vertical_speed_mps,target_vertical,float(design.policy.vertical_acceleration_mps2)*delta)
	var motion: Vector3=(-body.global_basis.z*speed_mps+Vector3.UP*vertical_speed_mps)*delta
	var next:=body.global_position+motion;var ceiling: float=host.terrain_surface.ground_y_world(next)+float(design.policy.maximum_altitude_above_terrain_m)
	if next.y>ceiling:
		# At the ceiling, flying from a hill towards lower terrain would also
		# exceed the AGL limit. Stop that horizontal entry instead of teleporting
		# vertically or silently flying above the configured height.
		if body.global_position.y>ceiling+.001:motion.x=0.;motion.z=0.;speed_mps=0.
		motion.y=minf(motion.y,maxf(0.,ceiling-body.global_position.y));vertical_speed_mps=0.;blocked_reason="maximum_altitude"
	if not _flight_bounds_valid(next):motion.x=0.;motion.z=0.;speed_mps=0.;blocked_reason="flight_boundary"
	var fraction:=_motion_fraction(motion)
	if fraction<.9999:motion*=maxf(0.,fraction-.002);speed_mps=0.;vertical_speed_mps=0.;blocked_reason="native_aircraft_sweep"
	elif blocked_reason not in ["maximum_altitude","flight_boundary","rotation_occupied"]:blocked_reason=""
	var before:=body.global_position;body.velocity=motion/delta;body.move_and_slide()
	if body.is_on_floor() and body.velocity.y<=.01:vertical_speed_mps=0.
	if body.get_slide_collision_count()>0 and motion.length()>.01:blocked_reason="native_aircraft_contact"
	var actual:=body.global_position.distance_to(before);actual_distance_m+=actual;maximum_step_m=maxf(maximum_step_m,actual)
	_current=body.global_transform;_attach_player(delta)
	if exit_requested:_try_exit()
func _process(_delta: float) -> void:
	if not loaded:return
	_proxy.global_transform=_previous.interpolate_with(_current,clampf(Engine.get_physics_interpolation_fraction(),0.,1.))
func destination(_kind: String="helipad") -> Dictionary:
	if not loaded:return {}
	# A successful shortcut releases its pilot and returns the aircraft home.
	# Its observer and camera must therefore agree on that future home pose,
	# including when the current aircraft is far away or awaiting pad clearance.
	var observe_home: bool=riding or return_pending or not _landed()
	var reference: Vector3=helipad.point if observe_home else body.global_position
	var reference_basis:=Basis(Vector3.UP,helipad.yaw) if observe_home else body.global_basis
	for offset: Vector3 in [Vector3(2.6,0,-.7),Vector3(-2.6,0,-.7),Vector3(2.8,0,.5),Vector3(-2.8,0,.5)]:
		var requested: Vector3=reference+reference_basis*offset
		var safe: Dictionary=host.interior_visit._safe_external_point(requested)
		if safe.is_empty() or not _public_ground(safe.point):continue
		var direction: Vector3=reference-safe.point;direction.y=0.
		return {"id":helipad.id,"point":safe.point,"toward":reference+Vector3.UP,"camera_yaw":atan2(-direction.x,-direction.z)+.50,"camera_pitch_degrees":-15.,"camera_distance_m":9.,"observing_home":observe_home}
	return {}
func viewpoint() -> Dictionary:return destination()
func snapshot() -> Dictionary:
	return {"loaded":loaded,"error":load_error,"riding":riding,"landed":_landed() if loaded else false,"position":body.global_position if is_instance_valid(body) else Vector3.ZERO,"velocity":body.velocity if is_instance_valid(body) else Vector3.ZERO,"speed_mps":speed_mps,"vertical_speed_mps":vertical_speed_mps,"rotor_fraction":rotor_fraction,"rotor_phase":rotor_phase,"tail_phase":tail_phase,"actual_distance_m":actual_distance_m,"maximum_step_m":maximum_step_m,"blocked_reason":blocked_reason,"exit_requested":exit_requested,"return_pending":return_pending,"capsule_release_pending":not _release.is_empty(),"helipad":helipad,"site_audit":site_audit,"events":events.duplicate(true),"source_geometry_changed":false,"scope":"One authored arcade helicopter and game marking on source Seoul Plaza terrain. Full main-rotor collision, native movement, bounded altitude/region and ground-only safe exit. No real helipad, flight permission or engineering flight-dynamics claim."}
