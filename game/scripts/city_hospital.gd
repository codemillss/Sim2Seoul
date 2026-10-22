extends Node3D
## Fictional, metre-sized hospital on one explicitly reserved outer parcel.
## The lobby and emergency reception occupy the same world as the street.
const DESIGN_PATH := "res://assets/authored/city_hospital.json"
class StaffMember extends CharacterBody3D:
	func _physics_process(delta: float) -> void:
		velocity=Vector3(0,-9.8*delta,0);move_and_slide()
var host: Node3D
var loaded:=false
var load_error:=""
var design: Dictionary={}
var building: Node3D
var floor_y:=0.
var terrain_range:=Vector2.ZERO
var door_groups: Array[Dictionary]=[]
var staff: Array[CharacterBody3D]=[]
var site_samples: Array=[]
var events: Array=[]
var _materials: Dictionary={}
var _native_bodies: Array[StaticBody3D]=[]

func _fail(message: String) -> bool:
	load_error=message;push_error(message);return false
func _mat(name_: String,color: Color,emissive:=false) -> Material:
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.72
	if emissive:material.emission_enabled=true;material.emission=color;material.emission_energy_multiplier=1.2
	_materials[name_]=material;return material
func _box(parent: Node3D,title: String,size: Vector3,at: Vector3,material: Material,solid:=false) -> MeshInstance3D:
	var node:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;node.mesh=mesh;node.name=title;node.position=at;node.material_override=material;parent.add_child(node)
	if solid:
		var body:=StaticBody3D.new();body.name=title+"Collision";body.collision_layer=32;body.collision_mask=14;node.add_child(body);var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape;body.add_child(collision);_native_bodies.append(body)
	return node
func _text(parent: Node3D,title: String,text: String,at: Vector3,pixel:=.004,east:=false,color:=Color.WHITE) -> Label3D:
	var label:=Label3D.new();label.name=title;label.text=text;label.font_size=40;label.pixel_size=pixel;label.outline_size=3;label.modulate=color;label.position=at
	if east:label.rotation.y=PI*.5
	parent.add_child(label);return label
func _floor_hit(at: Vector3) -> Dictionary:
	var y: float=host.terrain_surface.ground_y_world(at)
	if not is_finite(y):return {}
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x,y+.5,at.z),Vector3(at.x,y-.5,at.z),1|32))
func setup(scene: Node3D) -> bool:
	host=scene;process_mode=Node.PROCESS_MODE_PAUSABLE
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(DESIGN_PATH))
	if not raw is Dictionary or raw.get("source_world_sha256")!=FileAccess.get_sha256("res://resources/world_geometry/world.json"):return _fail("병원 배치 자료와 원본 도시가 다릅니다.")
	# This authored model has fixed furniture, window and approach geometry.
	# Refuse edited metadata that would describe a differently sized building.
	for key: String in ["width_x_m","depth_z_m","height_m","floor_count","ground_floor_height_m","upper_floor_height_m","door_width_m","door_height_m"]:
		var expected: Dictionary={"width_x_m":48.,"depth_z_m":34.,"height_m":44.,"floor_count":12.,"ground_floor_height_m":4.4,"upper_floor_height_m":3.6,"door_width_m":2.4,"door_height_m":2.4}
		if not (raw.get(key) is float or raw.get(key) is int) or not is_equal_approx(float(raw[key]),float(expected[key])):return _fail("병원 설계 치수와 실제 모델이 달라졌습니다: "+key)
	if raw.get("center_xz_m")!=[265.,375.] or raw.get("footprint_xz_m")!=[[241.,358.],[289.,358.],[289.,392.],[241.,392.]] or raw.get("entry_outward_xz")!=[1.,0.] or raw.get("source_parcel_id")!="osm:way:1216911414:land_area":return _fail("병원 실제 모델과 부지 설계가 다릅니다.")
	design=raw
	var minimum:=INF;var maximum:=-INF
	for x: int in range(241,290,2):
		for z: int in range(358,393,2):
			var at:=Vector3(x,0,z);var local: Vector3=host.city.to_local(at);var flat:=Vector2(local.x,local.z)
			if not host.player.free_roam_bounds.grow(-.5).has_point(Vector2(at.x,at.z)) or not Geometry2D.is_point_in_polygon(Vector2(at.x,at.z),host.player.free_roam_polygon) or host.city_bike_service._private_index.contains(flat):return _fail("병원 부지에 사유지나 경계 밖 위치가 있습니다.")
			var hit:=_floor_hit(at)
			if hit.is_empty():return _fail("병원 부지의 실제 지형 지지가 없습니다.")
			minimum=minf(minimum,hit.position.y);maximum=maxf(maximum,hit.position.y);site_samples.append({"xz":[x,z],"native_y_m":hit.position.y})
	terrain_range=Vector2(minimum,maximum);floor_y=maximum+.035
	var shape:=BoxShape3D.new();shape.size=Vector3(48,44,34);var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,Vector3(265,floor_y+22.04,375));query.collision_mask=1|4|8|32;query.margin=.002
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return _fail("대형 병원 전체 공간이 기존 구조와 겹칩니다.")
	building=Node3D.new();building.name="MetreSizedCityHospital";add_child(building);building.global_position=Vector3(265,floor_y,375)
	_mat("stone",Color(.78,.80,.78));_mat("white",Color(.93,.94,.90));_mat("glass",Color(.10,.27,.33));_mat("metal",Color(.36,.43,.46));_mat("teal",Color(.025,.40,.40));_mat("red",Color(.76,.055,.07));_mat("wood",Color(.54,.40,.27));_mat("paper",Color(.95,.94,.85));_mat("dark",Color(.06,.10,.13));_mat("led",Color(.91,.98,.94),true)
	_build_shell();_build_lobby();_build_approach();loaded=true
	print("CITY_HOSPITAL_READY footprint=48x34m height=44m floors=12 public_ground_floor=true original_geometry_changed=false")
	return true
func _build_shell() -> void:
	var depth: float=floor_y-terrain_range.x+.30
	_box(building,"FullSizeFoundation",Vector3(48,depth,34),Vector3(0,-depth*.5,0),_materials.stone,true)
	_box(building,"PublicLobbyFloor",Vector3(48,.12,34),Vector3(0,-.06,0),_materials.stone,true)
	# Upper storeys retain real floor pitch. Their solid envelope is separate
	# from the walkable public ground floor, rather than a scaled small lobby.
	_box(building,"UpperHospitalEnvelope",Vector3(48,39.6,34),Vector3(0,24.2,0),_materials.white,true)
	for x: float in [-23.9]:_box(building,"RearServiceWall",Vector3(.20,4.4,34),Vector3(x,2.2,0),_materials.white,true)
	for z: float in [-16.9,16.9]:_box(building,"LobbySideWall",Vector3(48,4.4,.20),Vector3(0,2.2,z),_materials.stone,true)
	# Two independent 2.4m openings: main reception and emergency reception.
	for span: Vector2 in [Vector2(-17,-11.2),Vector2(-8.8,-1.2),Vector2(1.2,17)]:
		_box(building,"StreetLevelGlass",Vector3(.12,4.2,span.y-span.x),Vector3(23.94,2.1,(span.x+span.y)*.5),_materials.glass,true)
	for z: float in [0.,-10.]:_build_door(z)
	for floor_: int in range(1,12):
		var y:=4.4+(floor_-1)*3.6
		_box(building,"HospitalFloorBand",Vector3(48.12,.18,34.12),Vector3(0,y+.10,0),_materials.stone)
		for east: float in [-1.,1.]:
			for column: int in range(11):
				var z: float=-15.0+float(column)*3.
				_box(building,"WardWindowReveal",Vector3(.10,2.45,2.5),Vector3(east*24.05,y+1.95,z),_materials.metal)
				_box(building,"WardWindowGlass",Vector3(.055,2.26,2.30),Vector3(east*24.12,y+1.95,z),_materials.glass)
				_box(building,"WardWindowMullion",Vector3(.065,2.28,.055),Vector3(east*24.16,y+1.95,z),_materials.white)
		for side: float in [-1.,1.]:
			for column: int in range(15):
				_box(building,"NorthSouthWardWindow",Vector3(2.3,2.25,.07),Vector3(-21.+column*3.,y+1.95,side*17.07),_materials.glass)
	_box(building,"RoofParapet",Vector3(48.2,.85,34.2),Vector3(0,44.10,0),_materials.stone)
	for z: float in [-9.,9.]:
		_box(building,"RoofAirHandlingPlant",Vector3(8,2.1,4.5),Vector3(-10,45.55,z),_materials.metal)
		for vent: int in range(5):_box(building,"HVACLouvres",Vector3(.14,1.45,4.6),Vector3(-13.2+vent*1.6,45.6,z),_materials.dark)
	_box(building,"HospitalNameBand",Vector3(.18,2.2,29),Vector3(24.2,42.3,0),_materials.teal)
	_text(building,"HospitalKoreanIdentity","서울시티 종합병원",Vector3(24.35,42.5,0),.018,true)
	_text(building,"HospitalEnglishIdentity","CITY GENERAL HOSPITAL",Vector3(24.35,41.65,0),.007,true)
	for z: float in [0.,-10.]:
		_box(building,"EntranceCanopy",Vector3(4.,.22,7.4),Vector3(25.4,3.75,z),_materials.white,true)
		_box(building,"CanopyFascia",Vector3(.14,.65,7.4),Vector3(27.43,3.64,z),_materials.red if z<0 else _materials.teal)
		_text(building,"EntranceIdentity","응급실  EMERGENCY" if z<0 else "정문 · 접수 / 원무",Vector3(27.53,3.66,z),.009,true)
	_box(building,"EmergencyCrossVertical",Vector3(.15,1.8,.50),Vector3(24.25,7.6,-10),_materials.red)
	_box(building,"EmergencyCrossHorizontal",Vector3(.15,.50,1.8),Vector3(24.26,7.6,-10),_materials.red)
func _build_door(z: float) -> void:
	var panels: Array[Node3D]=[];var rests: Array[Vector3]=[]
	for side: float in [-1.,1.]:
		var panel:=_box(building,"HospitalAutomaticDoor",Vector3(.12,2.4,1.18),Vector3(24.03,1.2,z+side*.60),_materials.glass,true);panels.append(panel);rests.append(panel.position)
		_box(panel,"DoorSafetyStripe",Vector3(.04,.055,1.15),Vector3(.09,.18,0),_materials.white)
	_box(building,"DoorHeader",Vector3(.20,.25,2.60),Vector3(24.03,2.52,z),_materials.metal,true)
	door_groups.append({"z":z,"point":Vector3(289,floor_y,375+z),"panels":panels,"rests":rests,"target":0.,"fraction":0.})
func _chair(x: float,z: float) -> void:
	_box(building,"HospitalWaitingSeat",Vector3(.56,.12,.55),Vector3(x,.45,z),_materials.teal,true)
	_box(building,"WaitingSeatBack",Vector3(.56,.55,.08),Vector3(x,.76,z+.27),_materials.teal)
	for dx: float in [-.20,.20]:_box(building,"SeatSteelLeg",Vector3(.035,.43,.035),Vector3(x+dx,.215,z),_materials.metal)
func _build_lobby() -> void:
	_box(building,"ReceptionCounter",Vector3(1.2,1.04,8.),Vector3(12,.52,4.5),_materials.wood,true)
	_box(building,"CounterWorktop",Vector3(1.36,.06,8.2),Vector3(12,1.07,4.5),_materials.white)
	_text(building,"ReceptionIdentity","원무 · 접수 · 수납",Vector3(12.74,2.25,4.5),.006,true,Color(.05,.30,.31))
	for z: float in [2.,5.,7.5]:
		_box(building,"ReceptionMonitor",Vector3(.055,.40,.60),Vector3(12.2,1.35,z),_materials.dark)
		_box(building,"NumberTicketDispenser",Vector3(.30,1.1,.35),Vector3(16,.55,z),_materials.white,true)
	for x: float in [3.,4.,5.,6.,7.,8.]:
		for z: float in [2.,5.5,9.]:_chair(x,z)
	_box(building,"EmergencyPrivacyWall",Vector3(32,3.2,.12),Vector3(-7,1.6,-6.0),_materials.white,true)
	_box(building,"TriageNurseCounter",Vector3(1.2,1.02,5.),Vector3(11,.51,-10.),_materials.teal,true)
	_text(building,"EmergencyTriageIdentity","응급 접수 · 간호 안내",Vector3(11.72,2.1,-10),.005,true,Color(.03,.30,.31))
	for z: float in [-12.,-9.]:
		_box(building,"EmergencyTrolley",Vector3(2.05,.12,.75),Vector3(3.,.71,z),_materials.metal,true)
		_box(building,"HospitalMattress",Vector3(1.95,.12,.70),Vector3(3.,.83,z),_materials.white)
		_box(building,"TrolleyPillow",Vector3(.40,.10,.62),Vector3(2.3,.94,z),_materials.paper)
		for x: float in [2.3,3.7]:_box(building,"TrolleyWheel",Vector3(.15,.18,.70),Vector3(x,.28,z),_materials.dark)
	_box(building,"WayfindingDirectory",Vector3(.14,2.6,4.0),Vector3(19.,1.35,11.8),_materials.teal,true)
	_text(building,"HospitalFloorDirectory","1F 원무 · 접수 · 응급실\n외래 · 병동 → 직원 안내\n화장실 · 편의시설 ←",Vector3(19.12,1.55,11.8),.003,true)
	_box(building,"StaffAccessDoor",Vector3(.12,2.30,1.2),Vector3(-23.72,1.15,7.),_materials.metal)
	_text(building,"ClinicalAreaIdentity","진료 · 병동 구역\n직원 전용",Vector3(-23.6,1.8,7.),.0035,true,Color(.05,.28,.29))
	for z: float in [-10.,4.5]:_staff_person(Vector3(10.8,0,z),z<0)
	for x: float in [-14.,0.,14.]:
		for z: float in [-10.,4.,12.]:
			_box(building,"LobbyLEDPanel",Vector3(1.2,.05,1.2),Vector3(x,4.32,z),_materials.led)
	for at: Vector3 in [Vector3(10,3.6,4),Vector3(10,3.6,-10),Vector3(-8,3.6,4)]:
		var light:=OmniLight3D.new();light.position=at;light.light_energy=1.4;light.omni_range=20.;light.shadow_enabled=false;building.add_child(light)
func _staff_person(at: Vector3,nurse: bool) -> void:
	var body:=StaffMember.new();body.name="EmergencyNurse" if nurse else "HospitalReceptionist";body.collision_layer=4;body.collision_mask=1|2|4|8|32;building.add_child(body);body.position=at
	var collider:=CollisionShape3D.new();collider.name="CollisionShape";var shape:=CapsuleShape3D.new();shape.height=1.7;shape.radius=.27;collider.shape=shape;collider.position.y=.85;body.add_child(collider)
	var visual:=Node3D.new();visual.name="Visual";body.add_child(visual);var placeholder:=MeshInstance3D.new();placeholder.name="Body";placeholder.mesh=CapsuleMesh.new();visual.add_child(placeholder)
	var avatar:=preload("res://scripts/player/exploration_avatar.gd").new();visual.add_child(avatar);avatar.setup(body)
	avatar._materials.jacket.albedo_color=Color(.64,.85,.84) if nurse else Color(.93,.94,.89);avatar._materials.trousers.albedo_color=Color(.16,.34,.38);visual.rotation.y=-PI*.5;staff.append(body)
func _build_approach() -> void:
	# Bounded ramps join real support; each segment follows the existing ground
	# plus a smoothly diminishing authored rise. Original terrain stays intact.
	for z: float in [0.,-10.]:
		for i: int in range(24):
			var a:=Vector3(289.+float(i)*.5,0,375.+z);var b:=a+Vector3(.5,0,0)
			var ya: float=host.terrain_surface.ground_y_world(a);var yb: float=host.terrain_surface.ground_y_world(b)
			if not is_finite(ya) or not is_finite(yb):continue
			ya=lerpf(floor_y,ya,clampf(float(i)/24.,0.,1.));yb=lerpf(floor_y,yb,clampf(float(i+1)/24.,0.,1.))
			var verts:=PackedVector3Array([Vector3(a.x,ya,a.z-1.5),Vector3(b.x,yb,b.z-1.5),Vector3(a.x,ya,a.z+1.5),Vector3(a.x,ya,a.z+1.5),Vector3(b.x,yb,b.z-1.5),Vector3(b.x,yb,b.z+1.5)])
			var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=verts;var normals:=PackedVector3Array()
			for unused: Vector3 in verts:normals.append(Vector3.UP)
			arrays[Mesh.ARRAY_NORMAL]=normals;var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=_materials.stone;node.name="HospitalEntryRamp";add_child(node)
			var body:=StaticBody3D.new();body.collision_layer=32;body.collision_mask=14;var collision:=CollisionShape3D.new();var shape:=ConcavePolygonShape3D.new();shape.set_faces(verts);shape.backface_collision=true;collision.shape=shape;body.add_child(collision);add_child(body);_native_bodies.append(body)
func _target() -> int:
	if not loaded or host.menu.visible or host._sandbox_detained() or host._police_facility_active() or host.player.interior_active or host.player.facility_control or host._street_transport_riding() or not host.player.is_on_floor():return -1
	var selected:=-1;var distance:=2.8
	for index: int in range(door_groups.size()):
		var point: Vector3=door_groups[index].point;var delta: Vector3=host.player.global_position-point
		if absf(delta.y)<.35 and Vector2(delta.x,delta.z).length()<distance:distance=Vector2(delta.x,delta.z).length();selected=index
	return selected
func can_interact() -> bool:return _target()>=0
func interaction_distance_m() -> float:
	var index:=_target();return host.player.global_position.distance_to(door_groups[index].point) if index>=0 else INF
func handle_interact() -> bool:
	var index:=_target()
	if index<0:return false
	door_groups[index].target=0. if float(door_groups[index].target)>.5 else 1.;events.append({"event":"physical_door_requested","door":index,"target":door_groups[index].target});return true
func prompt_text() -> String:
	var index:=_target()
	return ("E · 응급실 자동문 " if float(door_groups[index].z)<-.5 else "E · 병원 정문 자동문 ")+("닫기" if float(door_groups[index].target)>.5 else "열기") if index>=0 else ""
func _physics_process(delta: float) -> void:
	if not loaded or host.menu.visible:return
	for row: Dictionary in door_groups:
		# Closing while a real person occupies the aperture waits rather than
		# pushing that person through a solid wall. Opening is always permitted.
		if float(row.target)<.5:
			var q:=PhysicsShapeQueryParameters3D.new();var s:=BoxShape3D.new();s.size=Vector3(.9,2.4,2.6);q.shape=s;q.transform=Transform3D(Basis.IDENTITY,row.point+Vector3.UP*1.2);q.collision_mask=2|4
			if not get_world_3d().direct_space_state.intersect_shape(q,1).is_empty():continue
		row.fraction=move_toward(float(row.fraction),float(row.target),delta/1.0)
		for index: int in range(row.panels.size()):row.panels[index].position=row.rests[index]+Vector3(0,0,(-1. if index==0 else 1.)*float(row.fraction)*1.26)
func viewpoint() -> Dictionary:
	for x: float in [299.,301.,296.]:
		var safe: Dictionary=host.interior_visit._safe_external_point(Vector3(x,0,375))
		if not safe.is_empty():return {"point":safe.point,"toward":Vector3(289,floor_y+2.0,375),"camera_distance_m":8.,"camera_pitch_degrees":-10.,"scope":"Fictional large hospital, public ground-floor lobby and emergency reception; twelve-storey exterior."}
	return {}
func snapshot() -> Dictionary:
	var doors: Array=[]
	for row: Dictionary in door_groups:doors.append({"point":row.point,"fraction":row.fraction,"target":row.target})
	return {"loaded":loaded,"error":load_error,"design":design,"floor_y_m":floor_y,"terrain_range_m":terrain_range,"native_site_samples":site_samples.size(),"doors":doors,"staff":staff.size(),"events":events,"physical_bodies":_native_bodies.size(),"same_world_lobby":true,"original_geometry_changed":false,"real_hospital_claim":false}
