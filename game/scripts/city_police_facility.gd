extends Node3D
## The retained Sejong-ro police-box footprint gains a source-sized authored
## civic frontage and lobby. The original building mesh/collider stays intact.
const DESIGN := "res://assets/authored/police_facility.json"
var host: Node3D
var safety: Node3D
var loaded:=false
var load_error:=""
var active:=false
var phase:="outside"
var design: Dictionary={}
var entry_point:=Vector3.ZERO
var entry_door:=Vector3.ZERO
var outward:=Vector3.FORWARD
var facade: Node3D
var lobby: Node3D
var lobby_origin:=Vector3(4850,120,4800)
var lobby_exit:=Vector3.ZERO
var entry_count:=0
var exit_count:=0
var patrol_car: CharacterBody3D
var _saved: Dictionary={}
var _timer:=0.
var _door_panels: Array[Node3D]=[]
var _source_door_rest: Array[Vector3]=[]
var _materials: Dictionary={}
var _notice:=""
var events: Array=[]

func setup(scene: Node3D,controller: Node3D) -> bool:
	host=scene;safety=controller;process_mode=Node.PROCESS_MODE_PAUSABLE;process_physics_priority=1
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(DESIGN))
	if not raw is Dictionary or raw.source_world_sha256!=FileAccess.get_sha256(raw.source_world_path):load_error="파출소 원본 건물 자료가 다릅니다.";return false
	design=raw
	if not host.city.source_nodes.has(design.source_building_id):load_error="세종로파출소 원본 건물이 없습니다.";return false
	_materials={"stone":_mat(Color(.78,.80,.77)),"white":_mat(Color(.93,.95,.94)),"blue":_mat(Color(.025,.18,.46)),"cyan":_mat(Color(.03,.47,.78)),"metal":_mat(Color(.35,.42,.45)),"glass":_mat(Color(.10,.25,.34)),"black":_mat(Color(.05,.07,.09)),"wood":_mat(Color(.45,.31,.20)),"paper":_mat(Color(.94,.91,.80)),"gold":_mat(Color(.92,.71,.24))}
	outward=Vector3(design.facade.outward_xz[0],0,design.facade.outward_xz[1]);var along:=Vector3(design.facade.along_xz[0],0,design.facade.along_xz[1]);var center:=Vector3(design.facade.center_xz[0],0,design.facade.center_xz[1]);var base: float=host.terrain_surface.building_base_y_world(design.source_building_id)
	if not is_finite(base):load_error="파출소 기초 높이가 없습니다.";return false
	facade=Node3D.new();facade.name="SejongPoliceSourceFacade";add_child(facade);facade.global_transform=Transform3D(Basis(along,Vector3.UP,outward),center+Vector3.UP*base)
	var desired:=center+outward*2.25;var safe: Dictionary=host.interior_visit._safe_external_point(desired)
	if safe.is_empty():load_error="파출소 정문 앞 실제 보행 공간이 비어 있지 않습니다.";return false
	entry_point=safe.point;entry_door=center+outward*.25+Vector3.UP*(base+1.2)
	_build_frontage(base);_build_lobby();loaded=true;print("POLICE_FACILITY_READY source=",design.source_building_id," lobby_m2=",design.lobby.area_m2," source_geometry_changed=false")
	return true
func _mat(color: Color) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.72;return material
func _box(parent: Node3D,title: String,size: Vector3,point: Vector3,material: Material,solid:=false) -> MeshInstance3D:
	var mesh:=BoxMesh.new();mesh.size=size;var node:=MeshInstance3D.new();node.name=title;node.mesh=mesh;node.position=point;node.material_override=material;parent.add_child(node)
	if solid:
		var body:=StaticBody3D.new();body.name=title+"Collision";body.collision_layer=32;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;body.add_child(shape);parent.add_child(body);body.position=point
	return node
func _label(parent: Node3D,title: String,text: String,at: Vector3,pixel:=.0035,color:=Color.WHITE,billboard:=false) -> Label3D:
	var node:=Label3D.new();node.name=title;node.text=text;node.font_size=42;node.pixel_size=pixel;node.position=at;node.modulate=color;node.outline_size=3;node.billboard=BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED;parent.add_child(node);return node
func _build_frontage(base: float) -> void:
	var ring: Array=design.source_ring_xz
	for index: int in range(ring.size()):
		var a:=Vector3(ring[index][0],0,ring[index][1]);var b:=Vector3(ring[(index+1)%ring.size()][0],0,ring[(index+1)%ring.size()][1]);var along: Vector3=(a-b).normalized();var out:=Vector3(-along.z,0,along.x);var edge:=Node3D.new();edge.name="SourceCivicElevation"+str(index);add_child(edge);edge.global_transform=Transform3D(Basis(along,Vector3.UP,out),(a+b)*.5+Vector3.UP*base)
		var width: float=a.distance_to(b)
		_box(edge,"LimestoneCladding",Vector3(width-.02,8.9,.035),Vector3(0,4.47,.035),_materials.stone)
		_box(edge,"GranitePlinth",Vector3(width,.42,.075),Vector3(0,.24,.075),_materials.metal)
		_box(edge,"PoliceBlueRoofCornice",Vector3(width+.035,.22,.10),Vector3(0,8.57,.09),_materials.blue)
		_box(edge,"FloorStringCourse",Vector3(width,.12,.095),Vector3(0,4.35,.09),_materials.white)
		if index==1:continue
		var count:=maxi(1,floori(width/2.2))
		for column: int in range(count):
			var x: float=-width*.5+(float(column)+.5)*width/float(count)
			for y: float in [2.0,6.35]:
				var w:=minf(1.55,width/float(count)-.28);_box(edge,"WindowMetalReveal",Vector3(w+.12,1.95,.095),Vector3(x,y,.10),_materials.metal);_box(edge,"CivicWindowGlass",Vector3(w,1.80,.04),Vector3(x,y,.165),_materials.glass);_box(edge,"WindowMullion",Vector3(.045,1.80,.03),Vector3(x,y,.195),_materials.white)
	var width: float=design.facade.edge_length_m
	_box(facade,"PublicInstitutionBlueBand",Vector3(width-.3,1.18,.18),Vector3(0,3.28,.16),_materials.blue)
	_label(facade,"KoreanInstitutionName","세종로파출소",Vector3(0,3.53,.27),.007)
	_label(facade,"EnglishInstitutionName","SEJONG-RO POLICE BOX",Vector3(0,3.02,.27),.0027,Color(.85,.94,1.))
	_box(facade,"EntryCanopy",Vector3(3.65,.16,1.40),Vector3(0,2.67,.62),_materials.white)
	_box(facade,"CanopyBlueFascia",Vector3(3.7,.22,.14),Vector3(0,2.6,1.34),_materials.blue)
	_label(facade,"ClearEntryLabel","민원실 · 출입구",Vector3(0,2.58,1.43),.003)
	for side: float in [-1.,1.]:
		_box(facade,"DoorJamb",Vector3(.09,2.45,.14),Vector3(side*1.10,1.28,.20),_materials.metal)
		var panel:=Node3D.new();panel.name="AutomaticPoliceDoor";panel.position=Vector3(side*.52,1.23,.26);facade.add_child(panel);_box(panel,"DoorGlass",Vector3(1.03,2.30,.055),Vector3.ZERO,_materials.glass);_box(panel,"DoorRail",Vector3(1.03,.075,.07),Vector3(0,.35,.03),_materials.white);_box(panel,"DoorHandle",Vector3(.045,.48,.06),Vector3(-side*.36,-.02,.075),_materials.metal);_door_panels.append(panel);_source_door_rest.append(panel.position)
	_box(facade,"NoticeBoardCase",Vector3(1.40,1.65,.09),Vector3(-3.25,1.45,.15),_materials.metal);_box(facade,"NoticeBoard",Vector3(1.27,1.5,.03),Vector3(-3.25,1.45,.22),_materials.paper);_label(facade,"KoreanPublicNotice","민원 안내\n분실물 · 생활안전\n안내데스크로 오세요",Vector3(-3.25,1.45,.25),.0017,Color(.08,.16,.22))
	_box(facade,"112Plaque",Vector3(1.25,1.25,.09),Vector3(3.3,1.45,.16),_materials.blue);_label(facade,"Police112","경찰\n112",Vector3(3.3,1.45,.23),.0048)
	_label(facade,"AuthoredInteriorNotice","원본 건물 위치 · 게임용 외형·실내",Vector3(0,.34,.27),.0019,Color(.14,.22,.29))
	# Physical source floor is retained; only projected forecourt lines are new.
	for x: float in [-1.5,1.5]:
		var point: Vector3=facade.to_global(Vector3(x,0,2.2));var floor: float=host.terrain_surface.ground_y_world(point)
		if is_finite(floor):_box(self,"EntryBlueGroundGuide",Vector3(.10,.014,2.0),Vector3(point.x,floor+.023,point.z),_materials.blue)
	var camera:=Node3D.new();camera.name="EntranceCCTV";facade.add_child(camera);camera.position=Vector3(2.2,2.6,.5);_box(camera,"CameraHousing",Vector3(.18,.16,.36),Vector3.ZERO,_materials.white);_box(camera,"CameraLens",Vector3(.10,.10,.02),Vector3(0,0,.19),_materials.black)
	_build_flag()
func _build_flag() -> void:
	var flag:=Node3D.new();flag.name="KoreanPublicInstitutionFlag";facade.add_child(flag);flag.position=Vector3(-4.15,4.7,.5)
	_box(flag,"FlagPole",Vector3(.055,3.7,.055),Vector3(0,0,0),_materials.metal)
	_box(flag,"KoreanFlagCloth",Vector3(1.35,.90,.025),Vector3(.68,1.15,0),_materials.white)
	# A small Taegeuk-inspired national-colour mark plus trigrams, rather than
	# imported official insignia or an asset claiming present-day appearance.
	for spec: Array in [[Color(.78,.06,.14),.14],[Color(.04,.22,.62),-.14]]:
		var circle:=SphereMesh.new();circle.radius=.25;circle.height=.48;circle.radial_segments=20;var node:=MeshInstance3D.new();node.mesh=circle;node.material_override=_mat(spec[0]);node.scale=Vector3(.75,.65,.05);node.position=Vector3(.68,1.15+float(spec[1])*.6,.035);flag.add_child(node)
	for x: float in [.20,1.15]:
		for y: float in [.87,1.43]:
			for stripe: int in range(3):_box(flag,"FlagTrigram",Vector3(.20,.024,.02),Vector3(x,y+stripe*.045-.045,.04),_materials.black)
func _build_lobby() -> void:
	lobby=Node3D.new();lobby.name="SourceSizedAuthoredPoliceLobby";add_child(lobby);lobby.global_position=lobby_origin;lobby.visible=false
	var w: float=design.lobby.width_m;var d: float=design.lobby.depth_m
	_box(lobby,"LobbyFloor",Vector3(w,.22,d),Vector3(0,-.11,0),_materials.stone,true)
	_box(lobby,"LobbyBackWall",Vector3(w,3.35,.15),Vector3(0,1.675,-d*.5),_materials.white,true)
	for side: float in [-1.,1.]:_box(lobby,"LobbySideWall",Vector3(.15,3.35,d),Vector3(side*w*.5,1.675,0),_materials.white,true)
	_box(lobby,"LobbyFrontWall",Vector3(w,3.35,.12),Vector3(0,1.675,d*.5),_materials.glass,true)
	for side: float in [-1.,1.]:
		_box(lobby,"LobbyFrontPier",Vector3(.15,3.35,.18),Vector3(side*1.1,1.675,d*.5-.1),_materials.metal)
	_label(lobby,"InteriorDoorIdentity","자동문 · 출구",Vector3(0,2.45,d*.5-.12),.0025,Color(.85,.94,1.),true)
	_box(lobby,"LobbyCeiling",Vector3(w,.12,d),Vector3(0,3.4,0),_materials.white,true)
	_box(lobby,"ReceptionCounter",Vector3(w-2.2,1.05,.72),Vector3(0,.525,-d*.5+1.2),_materials.wood,true)
	_box(lobby,"ReceptionBlueFront",Vector3(w-2.25,.48,.035),Vector3(0,.67,-d*.5+1.58),_materials.blue)
	_label(lobby,"ReceptionDeskIdentity","경찰 민원 안내",Vector3(0,1.30,-d*.5+1.62),.0045,Color(.05,.20,.39),true)
	_label(lobby,"ReceptionPublicBoard","세종로파출소\n생활안전 · 분실물 · 순찰 안내",Vector3(0,2.35,-d*.5+.10),.005,Color(.06,.22,.45))
	_box(lobby,"CounterMonitor",Vector3(.53,.33,.055),Vector3(-.8,1.30,-d*.5+1.04),_materials.black)
	_box(lobby,"CounterBrochures",Vector3(.35,.045,.27),Vector3(.9,1.08,-d*.5+1.2),_materials.paper)
	for side: float in [-1.,1.]:
		for seat: int in range(2):
			_box(lobby,"WaitingChair",Vector3(.55,.46,.57),Vector3(side*(w*.5-.66),.23,float(seat)*.8-.35),_materials.blue,true)
			_box(lobby,"WaitingChairBack",Vector3(.08,.55,.55),Vector3(side*(w*.5-.9),.7,float(seat)*.8-.35),_materials.blue)
		_label(lobby,"PublicInformation", "민원 대기석\n쾌적한 이용을 위해 차례를 지켜주세요" if side<0 else "생활안전 안내\n이곳의 평면과 운영은 게임용 구성입니다",Vector3(side*(w*.5-.11),2.15,0),.0023,Color(.09,.20,.29),true)
	_box(lobby,"StaffOnlyDoor",Vector3(.9,2.25,.055),Vector3(w*.5-1.,1.125,-d*.5+.12),_materials.metal)
	_label(lobby,"StaffOnlyLabel","직원전용",Vector3(w*.5-1.,1.75,-d*.5+.18),.0024)
	var officer:=Node3D.new();officer.name="ReceptionOfficerVisual";lobby.add_child(officer);officer.position=Vector3(.1,0,-d*.5+.55);_box(officer,"UniformTorso",Vector3(.42,.55,.28),Vector3(0,1.05,0),_materials.blue);var head:=SphereMesh.new();head.radius=.13;head.height=.29;var head_node:=MeshInstance3D.new();head_node.mesh=head;head_node.position=Vector3(0,1.48,0);head_node.material_override=_mat(Color(.74,.56,.41));officer.add_child(head_node);_box(officer,"PoliceCap",Vector3(.29,.08,.28),Vector3(0,1.62,0),_materials.blue)
	lobby_exit=lobby_origin+Vector3(0,.025,d*.5-.7);_label(lobby,"LobbyExit","출구 · E",Vector3(0,2.2,d*.5-.18),.004,Color(.04,.25,.32),true)
	var light:=OmniLight3D.new();light.position=Vector3(0,2.8,0);light.omni_range=12.;light.light_energy=1.6;lobby.add_child(light)
func _external_clear(point: Vector3) -> bool:
	if not point.is_finite():return false
	var shape: CollisionShape3D=host.player.get_node("CollisionShape");var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape.shape;query.transform=Transform3D(Basis.IDENTITY,point)*shape.transform;query.collision_mask=1|4|8|32;query.exclude=[host.player.get_rid()];query.margin=.002
	var space:=get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():return false
	var floor:=space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.2,point-Vector3.UP*.35,1|32,[host.player.get_rid()]))
	return not floor.is_empty() and floor.normal.y>.7 and absf(point.y-floor.position.y)<.14
func can_interact() -> bool:
	if not loaded or safety.detained or host.menu.visible:return false
	if active:return phase=="inside" and host.player.global_position.distance_to(lobby_exit)<2.0
	return not safety.wanted and not host.player.interior_active and not host.player.facility_control and host.player.is_physics_processing() and not host._street_transport_riding() and host.player.global_position.distance_to(entry_point)<2.6 and host.player.is_on_floor() and _external_clear(host.player.global_position+Vector3.UP*.025)
func interaction_distance_m() -> float:return host.player.global_position.distance_to(lobby_exit if active else entry_point) if can_interact() else INF
func handle_interact() -> bool:
	if not can_interact():return false
	if active:phase="leaving";_timer=0.;host.player.set_facility_control(true);return true
	_saved={"yaw":host.rig.yaw,"pitch":host.rig.pitch,"distance":host.rig.requested_distance,"current":host.rig.current_distance,"pivot":host.rig.pivot_height_m,"outside":host.player.global_position,"world_spawn":host.player.spawn_transform.origin};active=true;phase="opening";_timer=0.;host.player.set_facility_control(true);events.append({"event":"door_opening"});return true
func _enter_lobby() -> bool:
	var w: float=design.lobby.width_m;var d: float=design.lobby.depth_m;var bounds:=AABB(lobby_origin+Vector3(-w*.5+.15,-.1,-d*.5+.15),Vector3(w-.3,3.45,d-.3))
	if not host.player.begin_interior(lobby_exit-Vector3(0,0,1.4),bounds):active=false;phase="outside";host.player.set_facility_control(false);return false
	lobby.visible=true;phase="inside";entry_count+=1;host.rig.yaw=0.;host.rig.pitch=deg_to_rad(-13.);host.rig.requested_distance=3.4;host.rig.current_distance=3.4;host.rig.pivot_height_m=1.0;host.rig.snap_to_target_pose();events.append({"event":"source_sized_lobby_entered"});return true
func leave_for_teleport(point: Vector3) -> bool:
	if not active or not _external_clear(point):return false
	if host.player.interior_active:
		if not host.player.end_interior(point):
			# A custody room is deliberately outside the ordinary exterior
			# domain. The host has already validated its complete native
			# capsule/floor and marks this same-tick internal transfer only.
			# Restore the lobby recovery owner through a separately validated
			# outdoor anchor before moving to that validated custody point.
			var custody_transfer: bool=host.get("_sandbox_custody_transfer")==true and point.distance_to(safety._room_origin)<8.
			if not custody_transfer:return false
			var anchor: Dictionary=host.interior_visit._safe_external_point(_saved.get("outside",entry_point))
			if anchor.is_empty() or not _external_clear(anchor.point) or not host.player.end_interior(anchor.point):return false
			host.player.global_transform=Transform3D(Basis.IDENTITY,point);host.player.require_neutral_input();host.player.reset_physics_interpolation()
	else:host.player.global_transform=Transform3D(Basis.IDENTITY,point);host.player.set_facility_control(false);host.player.require_neutral_input();host.player.reset_physics_interpolation()
	active=false;phase="outside";_timer=0.;lobby.visible=false;exit_count+=1
	if not _saved.is_empty():host.rig.yaw=_saved.yaw;host.rig.pitch=_saved.pitch;host.rig.requested_distance=_saved.distance;host.rig.current_distance=_saved.current;host.rig.pivot_height_m=_saved.pivot;_saved.clear()
	host.rig.snap_to_target_pose();events.append({"event":"validated_lobby_exit","point":point});return true
func return_to_world_spawn() -> bool:
	var safe: Dictionary=host.interior_visit._safe_external_point(_saved.get("world_spawn",entry_point))
	if safe.is_empty():safe=host.interior_visit._safe_external_point(entry_point)
	return not safe.is_empty() and leave_for_teleport(safe.point)
func prompt_text() -> String:
	if active:return "E · 파출소 로비에서 나가기" if can_interact() else "세종로파출소 민원실 · 출구로 이동하세요"
	return "E · 세종로파출소 민원실 들어가기" if can_interact() else ""
func status_text() -> String:return "세종로파출소 · 민원 안내 / 대기석\n"+prompt_text() if active else prompt_text()
func viewpoint() -> Dictionary:
	for offset: Vector3 in [outward*5.,outward*4.+facade.global_basis.x*2.5,outward*4.-facade.global_basis.x*2.5]:
		var safe: Dictionary=host.interior_visit._safe_external_point(entry_point+offset)
		if not safe.is_empty() and safety._rental_reservation_conflicts(safe.point).is_empty():return {"point":safe.point,"toward":facade.global_position+Vector3.UP*2.6,"camera_distance":6.,"camera_pitch":deg_to_rad(-10.),"scope":"Actual retained Sejong-ro police-box building location; authored civic facade and lobby."}
	return {}
func _physics_process(delta: float) -> void:
	if not loaded or host.menu.visible:return
	if phase in ["opening","leaving"]:
		_timer+=delta
		if _timer>=.65:
			if phase=="opening":_enter_lobby()
			else:
				var safe: Dictionary=host.interior_visit._safe_external_point(entry_point)
				if not safe.is_empty():leave_for_teleport(safe.point)
	var fraction:=clampf(_timer/.6,0.,1.) if phase=="opening" else (1. if active else 0.)
	for index: int in range(_door_panels.size()):_door_panels[index].position=_source_door_rest[index]+Vector3((-1. if index==0 else 1.)*fraction*.92,0,0)
func snapshot() -> Dictionary:
	return {"loaded":loaded,"error":load_error,"active":active,"phase":phase,"source_building_id":design.get("source_building_id",""),"official_address":design.get("official_address",""),"entry_point":entry_point,"entry_door":entry_door,"lobby_m2":design.get("lobby",{}).get("area_m2",0.),"lobby_outside_source_m2":design.get("lobby",{}).get("outside_source_m2",-1.),"entry_count":entry_count,"exit_count":exit_count,"events":events,"scope":"Actual retained source building location with official institution/address identity; facade, public lobby52m², bay and access are authored gameplay representations, not measured current facade/plan/parking."}
