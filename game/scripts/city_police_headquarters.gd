extends "res://scripts/city_police_facility.gd"
## A separately labelled fictional civic campus with realistic metre dimensions.
## The full ground-floor lobby shares the retained outdoor world: no teleport,
## hidden room owner, input freeze or invented real Seoul police location.
const CAMPUS_DESIGN:="res://assets/authored/police_headquarters.json"
var foundation_y:=0.
var door_phase:="closed"
var door_fraction:=0.
var door_openings:=0
var door_safety_holds:=0
var native_certificate: Dictionary={}
var parked_car: StaticBody3D
var _doors: Array[AnimatableBody3D]=[]
var _door_rest: Array[Vector3]=[]
var _dwell:=0.
var _inside_ticks:=0
var _ramp_length:=7.
func setup(scene: Node3D,controller: Node3D) -> bool:
	host=scene;safety=controller;name="GamePoliceHeadquarters";process_mode=Node.PROCESS_MODE_PAUSABLE;process_physics_priority=1
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(CAMPUS_DESIGN))
	if not raw is Dictionary:load_error="게임 경찰청사 자료가 없습니다.";return false
	design=raw
	for path: String in design.source_inputs:
		if FileAccess.get_sha256(("res://web_source/" if OS.has_feature("web") else "res://../")+path)!=design.source_inputs[path]:load_error="게임 경찰청사 원본 부지 자료가 바뀌었습니다.";return false
	_materials={"stone":_mat(Color(.76,.78,.76)),"white":_mat(Color(.91,.93,.92)),"blue":_mat(Color(.025,.16,.39)),"cyan":_mat(Color(.05,.42,.66)),"metal":_mat(Color(.31,.37,.40)),"glass":_mat(Color(.09,.24,.32)),"black":_mat(Color(.04,.06,.08)),"wood":_mat(Color(.43,.30,.18)),"paper":_mat(Color(.95,.93,.87)),"gold":_mat(Color(.87,.69,.26))}
	if not _preflight_site():return false
	facade=Node3D.new();facade.name="FictionalFullScalePoliceCampus";add_child(facade);facade.global_position=Vector3(design.center_xz[0],foundation_y,design.center_xz[1]);outward=Vector3.BACK
	_build_campus();_build_same_world_lobby();_build_ramp();_build_parked_car();entry_door=facade.to_global(Vector3(0,1.3,11.));entry_point=facade.to_global(Vector3(0,.08,12.5));loaded=true
	print("GAME_POLICE_HEADQUARTERS_READY metres=30x22x15.6 floors=4 direct_world_lobby=true source_changed=false");return true
func _preflight_site() -> bool:
	var min_y:=INF;var max_y:=-INF;var count:=0;var source_private:=0;var source_missing:=0
	for x: float in range(-20,21,2):
		for z: float in range(-15,16,2):
			var point:=Vector3(design.center_xz[0]+x,0,design.center_xz[1]+z);var floor: Dictionary=host.drivable_car_service._ground(point)
			if floor.is_empty():source_missing+=1;continue
			var local: Vector3=host.city.to_local(point)
			if host.city_bike_service._private_index.contains(Vector2(local.x,local.z)):source_private+=1
			if not host.player.exterior_contains(floor.point):source_private+=1
			min_y=minf(min_y,floor.point.y);max_y=maxf(max_y,floor.point.y);count+=1
	var ramp_samples:=0
	for x: float in [-2.,-1.,0.,1.,2.]:
		for step: int in range(15):
			var point:=Vector3(design.center_xz[0]+x,0,design.center_xz[1]+11.+float(step)*.5);var floor: Dictionary=host.drivable_car_service._ground(point)
			if floor.is_empty():source_missing+=1;continue
			var local: Vector3=host.city.to_local(point)
			if host.city_bike_service._private_index.contains(Vector2(local.x,local.z)) or not host.player.exterior_contains(floor.point):source_private+=1
			ramp_samples+=1
	foundation_y=max_y+.07
	var query:=PhysicsShapeQueryParameters3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(30,15.6,22);query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,Vector3(design.center_xz[0],foundation_y+7.8,design.center_xz[1]));query.collision_mask=1|2|4|8|32;query.exclude=[host.player.get_rid(),host.terrain_surface.support.get_rid()]
	var contacts: Array=[]
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query,16):contacts.append(String(hit.collider.get_path()))
	native_certificate={"native_supported_samples":count,"ramp_supported_samples":ramp_samples,"missing_support":source_missing,"private_or_bounds_samples":source_private,"ground_range_m":max_y-min_y,"foundation_top_y":foundation_y,"full_building_native_contacts":contacts,"scope":"Original full native support/private/bounds grid, source obstacles and4m tree exclusion; foundation adds geometry without flattening or deleting retained TIN."}
	if source_missing>0 or source_private>0 or not contacts.is_empty() or max_y-min_y>1.:load_error="게임 경찰청사 부지의 원본 지면/경계/빈 공간 검증이 실패했습니다.";return false
	return true
func _build_campus() -> void:
	var w: float=design.width_m;var d: float=design.depth_m;var h: float=design.height_m
	# Complete foundation and ground slab; only this new bounded campus gains
	# collision. No original collision or permission index is altered.
	_box(facade,"RaisedNativeFoundation",Vector3(w,.95,d),Vector3(0,-.475,0),_materials.stone,true)
	_box(facade,"GroundPublicLobbyFloor",Vector3(w,.16,d),Vector3(0,-.08,0),_materials.stone,true)
	for side: float in [-1.,1.]:_box(facade,"CivicSideElevation",Vector3(.25,h,d),Vector3(side*(w*.5-.125),h*.5,0),_materials.stone,true)
	_box(facade,"CivicRearElevation",Vector3(w,h,.25),Vector3(0,h*.5,-d*.5+.125),_materials.stone,true)
	for side: float in [-1.,1.]:_box(facade,"GroundEntrancePier",Vector3((w-3.4)*.5,3.9,.25),Vector3(side*(w+3.4)*.25,1.95,d*.5-.125),_materials.white,true)
	_box(facade,"UpperCivicFrontElevation",Vector3(w,h-3.9,.25),Vector3(0,3.9+(h-3.9)*.5,d*.5-.125),_materials.stone,true)
	for level: int in range(1,5):
		var y: float=level*3.9
		_box(facade,"StructuralFloorSlab",Vector3(w,.18,d),Vector3(0,y,0),_materials.white,true)
		_box(facade,"FacadeFloorBand",Vector3(w+.06,.18,.18),Vector3(0,y-.10,d*.5+.04),_materials.blue)
		if level>=4:continue
		for column: int in range(9):
			var x: float=(column-4)*3.05
			_box(facade,"OfficeWindowFrame",Vector3(2.35,1.72,.12),Vector3(x,y+1.75,d*.5+.08),_materials.metal);_box(facade,"OfficeWindowGlazing",Vector3(2.15,1.52,.035),Vector3(x,y+1.75,d*.5+.155),_materials.glass);_box(facade,"WindowMullion",Vector3(.055,1.52,.04),Vector3(x,y+1.75,d*.5+.18),_materials.white)
		for side: float in [-1.,1.]:
			for column: int in range(6):
				_box(facade,"SideOfficeWindow",Vector3(.10,1.72,2.2),Vector3(side*(w*.5+.05),y+1.75,(column-2.5)*3.2),_materials.glass)
	_box(facade,"PoliceBlueCrown",Vector3(w+.25,.55,d+.25),Vector3(0,h+.30,0),_materials.blue)
	_box(facade,"EntranceCanopy",Vector3(9.,.20,2.4),Vector3(0,3.25,d*.5+1.08),_materials.white)
	_box(facade,"EntranceBlueFascia",Vector3(9.1,.45,.16),Vector3(0,3.08,d*.5+2.23),_materials.blue)
	_label(facade,"PublicEntryName","민원실 · 출입구",Vector3(0,3.10,d*.5+2.33),.0048)
	_box(facade,"MainInstitutionBand",Vector3(18.,1.10,.20),Vector3(0,h-1.35,d*.5+.17),_materials.blue)
	_label(facade,"MainPoliceIdentity","서울 생활안전 경찰청사",Vector3(0,h-1.20,d*.5+.29),.007)
	_label(facade,"FictionalInstitutionDisclosure","게임용 가상 경찰청사 · 실제 기관 위치 아님",Vector3(0,h-1.61,d*.5+.29),.0029,Color(.85,.95,1.))
	_label(facade,"FourFloorScaleIdentity","4F 수사 · 3F 생활안전 · 2F 직원업무 · 1F 민원실",Vector3(0,4.65,d*.5+.28),.0032,Color(.07,.18,.32))
	_box(facade,"Institution112Plaque",Vector3(1.35,1.8,.15),Vector3(5.,1.5,d*.5+.12),_materials.blue);_label(facade,"Institution112","경찰\n112",Vector3(5.,1.5,d*.5+.22),.004)
	_label(facade,"PhysicalScaleNotice","30m × 22m · 4층 / 게임용 설계",Vector3(-7.,1.2,d*.5+.22),.0025,Color(.12,.22,.30))
	for side: float in [-1.,1.]:
		var panel:=AnimatableBody3D.new();panel.name="NativeAutomaticPoliceDoor";panel.collision_layer=32;panel.collision_mask=0;panel.sync_to_physics=false;facade.add_child(panel);panel.position=Vector3(side*.79,1.3,d*.5-.02)
		var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(1.59,2.60,.12);shape.shape=box;panel.add_child(shape)
		_box(panel,"BlueGlassSlidingDoor",box.size,Vector3.ZERO,_materials.glass);_box(panel,"DoorGrip",Vector3(.05,.55,.07),Vector3(-side*.55,0,.10),_materials.metal);_label(panel,"DoorSafetyStripe","자동문",Vector3(0,.25,.10),.0024,Color.WHITE)
		_doors.append(panel);_door_rest.append(panel.position)
	for x: float in [-12.5,-9.3,-6.1,6.1,9.3,12.5]:
		_box(facade,"GroundPublicWindowFrame",Vector3(2.45,2.10,.13),Vector3(x,1.65,d*.5+.08),_materials.metal)
		_box(facade,"GroundPublicWindow",Vector3(2.25,1.90,.04),Vector3(x,1.65,d*.5+.17),_materials.glass)
		_box(facade,"GroundWindowMullion",Vector3(.055,1.9,.035),Vector3(x,1.65,d*.5+.20),_materials.white)
	_box(facade,"EntranceUpperTransom",Vector3(3.4,1.3,.15),Vector3(0,3.25,d*.5-.02),_materials.glass,true)
func _build_same_world_lobby() -> void:
	var paper: Material=_materials.paper
	for line: int in range(-7,8):_box(facade,"PolishedFloorTileJoint",Vector3(.014,.006,21.5),Vector3(line*1.9,.006,0),_materials.white)
	for line: int in range(-5,6):_box(facade,"PolishedFloorTileJoint",Vector3(29.5,.006,.014),Vector3(0,.006,line*1.9),_materials.white)
	_box(facade,"PublicServiceCounter",Vector3(10.,1.05,.90),Vector3(-4.,.525,-6.7),_materials.wood,true);_box(facade,"CounterPoliceBlueFront",Vector3(9.95,.50,.045),Vector3(-4.,.68,-6.22),_materials.blue)
	for index: int in range(3):
		var x: float=-7.5+float(index)*3.3
		_box(facade,"PublicCounterMonitor",Vector3(.65,.40,.08),Vector3(x,1.32,-6.9),_materials.black);_box(facade,"PublicCounterPaper",Vector3(.40,.035,.30),Vector3(x+.6,1.08,-6.65),paper)
		_label(facade,"PublicCounterService",["① 종합민원","② 분실물 신고","③ 생활안전 안내"][index],Vector3(x,2.45,-7.05),.0036,Color(.05,.20,.36),true)
	for row: int in range(2):
		for seat: int in range(4):
			var point:=Vector3(-9.+float(seat)*1.0,.23,1.0+float(row)*2.0)
			_box(facade,"CivilWaitingChair",Vector3(.60,.46,.60),point,_materials.blue,true);_box(facade,"CivilWaitingChairBack",Vector3(.60,.55,.08),point+Vector3(0,.45,.29),_materials.blue)
	_label(facade,"PublicQueueInstruction","민원 대기석 · 차례를 기다려 주세요",Vector3(-7.5,2.0,4.),.0035,Color(.06,.18,.28),true)
	_box(facade,"InformationKiosk",Vector3(.70,1.30,.45),Vector3(6.8,.65,3.0),_materials.metal,true);_box(facade,"KioskDisplay",Vector3(.60,.50,.03),Vector3(6.8,1.2,3.24),_materials.black);_label(facade,"KioskInstruction","방문 안내\n민원 · 분실물 · 생활안전",Vector3(6.8,2.05,3.25),.0026,Color(.07,.2,.30),true)
	_box(facade,"ConsultationPartition",Vector3(.10,2.9,6.5),Vector3(5.,1.45,-6.9),_materials.glass,true);_box(facade,"ConsultationBack",Vector3(9.,2.9,.10),Vector3(9.5,1.45,-10.1),_materials.white,true)
	_label(facade,"ConsultationIdentity","상담실 · 직원 안내 후 이용",Vector3(10.,2.4,-3.65),.003,Color(.07,.2,.30),true)
	_box(facade,"ConsultationDesk",Vector3(2.4,.78,1.1),Vector3(9.5,.39,-6.7),_materials.wood,true)
	_box(facade,"StaffAccessDoor",Vector3(1.4,2.5,.10),Vector3(-11.,1.25,-10.7),_materials.metal,true);_label(facade,"StaffAccessNotice","2~4층 직원 전용\n민원인은 안내데스크를 이용하세요",Vector3(-11.,2.1,-10.59),.0025,Color.WHITE,true)
	_label(facade,"InsidePublicIdentity","서울 생활안전 경찰청사 · 민원실",Vector3(-3.,3.15,-9.9),.005,Color(.03,.16,.35),true)
	_label(facade,"SameWorldExit","출구 · 자동문 E",Vector3(0,2.75,10.65),.004,Color(.85,.95,1.),true)
	for x: float in [-8.,8.]:
		var light:=OmniLight3D.new();light.position=Vector3(x,3.3,0);light.omni_range=18.;light.light_energy=1.8;facade.add_child(light)
	var officer:=Node3D.new();officer.name="CivilServiceOfficerVisual";facade.add_child(officer);officer.position=Vector3(-4.,0,-7.6)
	_box(officer,"ProperHumanUniformTorso",Vector3(.42,.52,.25),Vector3(0,1.12,0),_materials.blue)
	_box(officer,"ProperHumanTrousers",Vector3(.36,.32,.24),Vector3(0,.75,0),_materials.blue)
	for side: float in [-1.,1.]:_box(officer,"ProperHumanLeg",Vector3(.15,.61,.16),Vector3(side*.105,.355,0),_materials.blue);_box(officer,"OfficerShoe",Vector3(.17,.10,.28),Vector3(side*.105,.05,.035),_materials.black)
	var head:=SphereMesh.new();head.radius=.115;head.height=.25;var node:=MeshInstance3D.new();node.mesh=head;node.position=Vector3(0,1.54,0);node.material_override=_mat(Color(.74,.56,.42));officer.add_child(node);_box(officer,"PoliceUniformCap",Vector3(.25,.075,.25),Vector3(0,1.70,0),_materials.blue)
func _build_ramp() -> void:
	var front:=facade.to_global(Vector3(0,0,11.));var end:=Vector3(front.x,0,front.z+_ramp_length);var floor: Dictionary=host.drivable_car_service._ground(end)
	if floor.is_empty():return
	var end_y: float=floor.point.y+.01;var rise:=foundation_y-end_y;var slope:=atan2(rise,_ramp_length);var length:=sqrt(rise*rise+_ramp_length*_ramp_length)
	var ramp:=Node3D.new();ramp.name="NativeAccessiblePoliceEntryRamp";add_child(ramp);ramp.global_position=(front+Vector3(end.x,end_y,end.z))*.5;ramp.rotation.x=slope
	_box(ramp,"SupportedEntryRamp",Vector3(4.,.16,length+.12),Vector3(0,-.08,0),_materials.stone,true)
	for side: float in [-1.,1.]:
		_box(ramp,"RampHandrail",Vector3(.05,.05,length),Vector3(side*1.95,.90,0),_materials.metal)
		for z: float in [-length*.4,0.,length*.4]:_box(ramp,"RampRailPost",Vector3(.05,.9,.05),Vector3(side*1.95,.45,z),_materials.metal)
	native_certificate.ramp_rise_m=rise;native_certificate.ramp_length_m=_ramp_length;native_certificate.ramp_gradient=rise/_ramp_length
	_label(self,"PoliceCampusGroundWayfinding","경찰청사 민원실 ↑\nE 자동문 · 게임용 가상 시설",Vector3(end.x,end_y+1.4,end.z+.8),.004,Color(.05,.19,.37),true)
func _build_parked_car() -> void:
	var point:=Vector3(design.parked_car_xz[0],0,design.parked_car_xz[1]);var ground: Dictionary=host.drivable_car_service._ground(point)
	if ground.is_empty():return
	parked_car=StaticBody3D.new();parked_car.name="HeadquartersParkedPoliceCar";parked_car.collision_layer=8;var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2.2,1.65,4.5);collider.shape=box;collider.position.y=.825;parked_car.add_child(collider);add_child(parked_car);parked_car.global_transform=Transform3D(host.drivable_car_service._pose_basis(ground.point,0.),ground.point+Vector3.UP*.035)
	var visual:=Node3D.new();parked_car.add_child(visual);var dresser:=preload("res://scripts/drivable_car_service.gd").new();var row: Dictionary={"wheels":[],"pedals":[]};dresser._build_bike(row,visual);dresser.free()
	for child: Node in visual.get_children():
		if child is MeshInstance3D and (String(child.name).begins_with("FrontDoor") or String(child.name).begins_with("RearDoor") or String(child.name) in ["LowerBody","Trunk","CabinRoof","Hood"]):child.material_override=_materials.white
	for side: float in [-1.,1.]:
		_box(visual,"PoliceBlueStripe",Vector3(.05,.2,3.5),Vector3(side*.94,.58,0),_materials.blue);var sign:=_label(visual,"ParkedPoliceIdentity","경찰 · POLICE112",Vector3(side*.97,.94,-.2),.002);sign.rotation.y=side*PI*.5
	_box(visual,"ParkedCarBeaconBlue",Vector3(.55,.12,.28),Vector3(.35,1.65,0),_materials.cyan);_box(visual,"ParkedCarBeaconRed",Vector3(.55,.12,.28),Vector3(-.35,1.65,0),_mat(Color(.9,.05,.05)))
func contains_player() -> bool:
	if not loaded:return false
	var at: Vector3=facade.to_local(host.player.global_position)
	return absf(at.x)<14.7 and absf(at.z)<10.7 and at.y>-.15 and at.y<3.8
func can_interact() -> bool:
	if not loaded or safety.detained or host.menu.visible or host.player.interior_active or host.player.facility_control or host._street_transport_riding():return false
	return host.player.is_on_floor() and host.player.global_position.distance_to(facade.to_global(Vector3(0,.03,11.)))<3.6
func interaction_distance_m() -> float:return host.player.global_position.distance_to(facade.to_global(Vector3(0,.03,11.))) if can_interact() else INF
func handle_interact() -> bool:
	if not can_interact():return false
	door_phase="opening";_dwell=0.;door_openings+=1;return true
func _door_blocked() -> bool:
	var at: Vector3=facade.to_local(host.player.global_position)
	if absf(at.x)<2.5 and absf(at.z-11.)<1.4 and at.y>-.3 and at.y<2.8:return true
	var query:=PhysicsShapeQueryParameters3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(3.7,2.7,.8);query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,facade.to_global(Vector3(0,1.35,11.)));query.collision_mask=2|4|8
	return not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
func _physics_process(delta: float) -> void:
	if not loaded or host.menu.visible:return
	if contains_player():_inside_ticks+=1
	if door_phase=="opening":
		door_fraction=minf(1.,door_fraction+delta/.65)
		if door_fraction>=1.:door_phase="open";_dwell=0.
	elif door_phase=="open":
		_dwell+=delta
		if _dwell>6. and not _door_blocked():door_phase="closing"
	elif door_phase=="closing":
		if _door_blocked():door_safety_holds+=1;door_phase="opening"
		else:
			door_fraction=maxf(0.,door_fraction-delta/.65)
			if door_fraction<=0.:door_phase="closed"
	var fraction: float=smoothstep(0.,1.,door_fraction)
	for index: int in range(_doors.size()):_doors[index].position=_door_rest[index]+Vector3((-1. if index==0 else 1.)*fraction*1.65,0,0)
func prompt_text() -> String:return "E · 경찰청사 자동문 열기" if can_interact() else ""
func status_text() -> String:return "게임용 경찰청사 · 1층 민원실\n민원 안내 · 분실물 · 생활안전 / 출구 자동문 E" if contains_player() else prompt_text()
func viewpoint() -> Dictionary:
	for point: Vector3 in [Vector3(-120,0,-398),Vector3(-126,0,-400),Vector3(-113,0,-400)]:
		var safe: Dictionary=host.interior_visit._safe_external_point(point)
		if not safe.is_empty():return {"point":safe.point,"toward":facade.global_position+Vector3(0,6.,0),"camera_distance":8.,"camera_pitch":deg_to_rad(-10.),"scope":"New fictional30×22m4F campus on audited retained native ground; no actual Seoul police headquarters claim."}
	return {}
func snapshot() -> Dictionary:
	return {"loaded":loaded,"error":load_error,"active":false,"kind":"same_world_fictional_full_scale_police_campus","center_xz":design.get("center_xz",[]),"metres":[30,22,15.6],"floors":4,"public_floor_m2":660,"door_phase":door_phase,"door_fraction":door_fraction,"door_openings":door_openings,"safety_holds":door_safety_holds,"inside_ticks":_inside_ticks,"player_inside":contains_player(),"certificate":native_certificate,"source_geometry_changed":false,"scope":design.get("scope","")}
