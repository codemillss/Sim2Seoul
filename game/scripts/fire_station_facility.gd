extends RefCounted
## Metre-authored fictional 36 x 30m civic facility; not a real station survey.
## Local -Z is the street front. Three 4.8 x 4.5 x 12m apparatus bays.
var _service: Node3D
var _root: Node3D
var components: Array[String]=[]
func _mat(color: Color,emissive:=false) -> StandardMaterial3D:return _service._mat(color,emissive)
func _box(title: String,size: Vector3,point: Vector3,mat: Material,solid:=false) -> MeshInstance3D:
	var mesh: MeshInstance3D=_service._box(_root,title,size,point,mat);components.append(title)
	if solid:
		var body:=StaticBody3D.new();body.name=title+"Collision";body.collision_layer=32;body.collision_mask=2|4|8;var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collider.shape=shape;body.add_child(collider);mesh.add_child(body)
	return mesh
func _text(title: String,text: String,point: Vector3,pixel:=.0045,color:=Color.WHITE) -> void:
	var label: Label3D=_service._label(_root,text,point,pixel);label.name=title;label.modulate=color;label.font_size=48;label.outline_size=3;label.billboard=BaseMaterial3D.BILLBOARD_DISABLED;label.rotation.y=PI;components.append(title)
func _brick() -> ShaderMaterial:
	var shader:=Shader.new();shader.code="""shader_type spatial;
varying vec3 world_point;
void vertex(){world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float row=world_point.y/0.23;
 vec2 p=vec2((world_point.x+world_point.z)/0.49+mod(floor(row),2.0)*0.5,row);
 vec2 cell=fract(p);float mortar=step(0.045,cell.x)*step(0.075,cell.y);
 float variation=fract(sin(dot(floor(p),vec2(12.9898,78.233)))*43758.5453);
 vec3 brick=mix(vec3(0.29,0.10,0.065),vec3(0.48,0.22,0.14),variation);
 ALBEDO=mix(vec3(0.40,0.35,0.30),brick,mortar);ROUGHNESS=0.87;
}"""
	var mat:=ShaderMaterial.new();mat.shader=shader;return mat
func _line(title: String,a: Vector3,b: Vector3,width: float,mat: Material) -> void:
	var node:=_box(title,Vector3(width,.014,a.distance_to(b)),(a+b)*.5,mat);node.rotation.y=atan2((b-a).x,(b-a).z)
func build(service: Node3D,parent: Node3D) -> Dictionary:
	_service=service;_root=parent
	var brick:=_brick();var pale:=_mat(Color(.78,.80,.78));var stone:=_mat(Color(.31,.36,.38));var red:=_mat(Color(.68,.045,.025));var dark:=_mat(Color(.035,.075,.095));var metal:=_mat(Color(.38,.43,.44));var yellow:=_mat(Color(.98,.78,.08));var warm:=_mat(Color(1.,.81,.53),true)
	var glass:=_mat(Color(.17,.35,.42,.52));glass.roughness=.12;glass.metallic=.16
	var depth: float=_service._foundation_depth
	_box("FoundationPlinth",Vector3(36.,depth,30.),Vector3(0,-depth*.5,0),stone,true)
	_box("RearBrickWall",Vector3(36.,11.8,.26),Vector3(0,5.9,14.87),brick,true)
	for x: float in [-17.86,17.86]:_box("SideBrickWall",Vector3(.28,11.8,30.),Vector3(x,5.9,0),brick,true)
	for y: float in [4.8,8.4]:_box("StructuralFloor",Vector3(35.6,.22,29.6),Vector3(0,y,0),pale,true)
	_box("RoofParapet",Vector3(36.4,.35,30.4),Vector3(0,11.95,0),pale,true)
	_box("RoofDarkCap",Vector3(36.5,.10,30.5),Vector3(0,12.18,0),metal)
	_box("ReceptionPartition",Vector3(.22,4.5,29.5),Vector3(3.3,2.25,0),pale,true)
	_box("ApparatusRearPartition",Vector3(21.,4.5,.20),Vector3(-7.2,2.25,-2.1),pale,true)
	for bay: float in [-12.,-6.,0.]:
		for side: float in [-1.,1.]:_box("RedBayPillar",Vector3(.36,4.5,.55),Vector3(bay+side*2.62,2.25,-14.9),red,true)
		_box("RedApparatusHeader",Vector3(5.6,.48,.58),Vector3(bay,4.58,-14.9),red,true)
		_box("RaisedSectionalDoor",Vector3(4.8,.23,.85),Vector3(bay,4.45,-14.35),metal)
		for i: int in range(7):_box("GarageDoorSlat",Vector3(4.75,.035,.86),Vector3(bay,4.32+float(i)*.03,-14.36),dark)
		_text("BayNumber",str(int((bay+12.)/6.)+1)+"  출동차고",Vector3(bay,4.63,-15.24),.0034)
		for x: float in [-2.35,2.35]:_line("ApparatusBayGuide",Vector3(bay+x,.02,-14.5),Vector3(bay+x,.02,-2.5),.08,yellow)
		for z: float in [-14.6,-13.3]:_line("ExitKeepClearStripe",Vector3(bay-2.1,.025,z),Vector3(bay+2.1,.025,z+.6),.11,yellow)
		for x: float in [-1.5,0.,1.5]:
			_box("FireGearLocker",Vector3(.8,2.15,.55),Vector3(bay+x,1.075,-2.65),metal,true)
			_box("LockerDoorInset",Vector3(.69,1.95,.04),Vector3(bay+x,1.12,-2.96),red)
	_box("Main119Header",Vector3(35.4,.90,.40),Vector3(0,5.52,-15.03),red)
	_text("Apparatus119Header","119  게임 서울서부소방서",Vector3(-3.,5.56,-15.27),.0125)
	_text("GameFacilityDisclosure","현재 지도 외곽에 배치한 가상 공공청사",Vector3(-3.,6.3,-15.23),.0038,Color(.96,.93,.80))
	# Glazed human-scale entrance: 1.6m clear width and 2.4m clear height.
	for x: float in [3.5,9.915,11.585,17.7]:_box("ReceptionMullion",Vector3(.07,4.2,.16),Vector3(x,2.1,-15.),metal,true)
	_box("ReceptionFrontLeftGlass",Vector3(6.45,3.35,.08),Vector3(6.725,1.825,-14.92),glass,true)
	_box("ReceptionFrontRightGlass",Vector3(6.15,3.35,.08),Vector3(14.625,1.825,-14.92),glass,true)
	_box("DoorLintel",Vector3(1.60,1.50,.16),Vector3(10.75,3.22,-15.),metal,true)
	_box("ReceptionCanopy",Vector3(14.6,.22,2.),Vector3(10.6,4.1,-15.85),red,true)
	_box("CanopyWarmLED",Vector3(13.8,.04,.07),Vector3(10.6,3.96,-16.7),warm)
	_text("ReceptionEntrance","민원 안내 · 안전교육   출입구",Vector3(10.7,4.48,-16.92),.0041)
	_text("ReceptionWelcome","안내 · 접수",Vector3(10.75,2.05,-11.8),.0040,Color(.1,.23,.28))
	_box("ReceptionDesk",Vector3(4.,1.0,.85),Vector3(10.8,.5,-11.4),pale,true)
	_box("ReceptionDeskTop",Vector3(4.2,.07,.95),Vector3(10.8,1.04,-11.4),stone)
	_box("DeskMonitor",Vector3(.55,.37,.06),Vector3(11.3,1.27,-11.4),dark)
	for x: float in [5.,5.8,6.6,7.4]:
		_box("VisitorSeat",Vector3(.55,.12,.56),Vector3(x,.45,-8.5),red)
		_box("VisitorSeatBack",Vector3(.55,.65,.09),Vector3(x,.78,-8.2),red)
		for dx: float in [-.19,.19]:_box("VisitorChairLeg",Vector3(.04,.4,.04),Vector3(x+dx,.20,-8.5),metal)
	_box("BrochureRack",Vector3(.65,1.45,.3),Vector3(16.5,.725,-13.),metal)
	for y: float in [.5,.85,1.2]:_box("SafetyLeaflet",Vector3(.48,.24,.035),Vector3(16.5,y,-13.17),_mat(Color(.96,.65,.15)))
	# 3.6m upper storeys have actual regular window rhythm and floor bands.
	for y: float in [6.9,10.5]:
		_box("UpperFloorFascia",Vector3(36.,3.2,.20),Vector3(0,y,-14.9),brick,true)
		for x: float in [-15.,-11.,-7.,-3.,1.,5.,9.,13.,16.]:
			_box("UpperOfficeWindowFrame",Vector3(2.6,1.8,.15),Vector3(x,y,-15.07),pale)
			_box("UpperOfficeWindowInset",Vector3(2.4,1.6,.06),Vector3(x,y,-15.17),dark)
			_box("UpperOfficeWindow",Vector3(2.35,1.55,.035),Vector3(x,y,-15.22),glass)
			_box("OfficeWindowMullion",Vector3(.07,1.6,.08),Vector3(x,y,-15.27),metal)
		for z: float in [-11.,-5.,1.,7.,12.]:
			for side: float in [-1.,1.]:_box("SideWindowGlass",Vector3(.06,1.65,3.),Vector3(side*18.04,y,z),dark)
	_box("119IdentityPylon",Vector3(3.3,5.7,.35),Vector3(15.3,8.5,-15.25),red)
	_text("119IdentityLarge","119",Vector3(15.3,9.7,-15.48),.015)
	_text("SafetyCenterIdentity","소방서",Vector3(15.3,7.8,-15.49),.0063)
	for x: float in [-8.,5.,12.]:
		_box("RoofHVAC",Vector3(3.4,1.25,2.4),Vector3(x,12.9,7.),metal)
		for dx: float in [-1.,0.,1.]:_box("HVACVent",Vector3(.16,.05,1.9),Vector3(x+dx,13.55,7.),dark)
	for point: Vector3 in [Vector3(-12.,3.9,-8.),Vector3(-6.,3.9,-8.),Vector3(0.,3.9,-8.),Vector3(10.8,3.6,-11.),Vector3(-7.,5.6,-16.),Vector3(10.8,4.5,-16.8)]:
		_box("CeilingLight",Vector3(1.5,.06,.3),point,warm)
		var light:=OmniLight3D.new();light.name="FacilityWarmLight";light.position=point;light.omni_range=7.;light.light_color=Color(1.,.85,.67);light.light_energy=.75;light.shadow_enabled=false;_root.add_child(light)
	return {"width_m":36.,"depth_m":30.,"height_m":12.,"floor_count":3,"storey_heights_m":[4.8,3.6,3.6],"apparatus_bay_count":3,"garage_width_m":4.8,"garage_clear_height_m":4.5,"garage_clear_depth_m":12.,"forecourt_depth_m":15.,"reception_open_door_width_m":1.6,"reception_open_door_height_m":2.47,"features":components,"real_station_identity_claim":false,"original_source_geometry_changed":false}
