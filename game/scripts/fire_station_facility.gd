extends RefCounted
## A fictional 12 x 8 metre municipal-looking game facility. Local -Z is
## the street front; the left apparatus bay and right reception stay distinct.
## No real fire service badge, actual station identity or original model edit.
var _service: Node3D
var _root: Node3D
var components: Array[String]=[]
func _mat(color: Color,emissive:=false) -> StandardMaterial3D:return _service._mat(color,emissive)
func _box(title: String,size: Vector3,point: Vector3,mat: Material,solid:=false) -> MeshInstance3D:
	var mesh: MeshInstance3D=_service._box(_root,title,size,point,mat);components.append(title)
	if solid:
		var body:=StaticBody3D.new();body.name=title+"Collision";body.collision_layer=32;body.collision_mask=2|4|8;var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collider.shape=shape;body.add_child(collider);mesh.add_child(body)
	return mesh
func _text(title: String,text: String,point: Vector3,pixel:=.0035,color:=Color.WHITE) -> void:
	var label: Label3D=_service._label(_root,text,point,pixel);label.name=title;label.modulate=color;label.font_size=48;label.outline_size=4;components.append(title)
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
func _paint_line(title: String,a: Vector3,b: Vector3,width: float,mat: Material) -> void:
	var span:=a.distance_to(b);var node:=_box(title,Vector3(width,.012,span),(a+b)*.5,mat);node.rotation.y=atan2((b-a).x,(b-a).z)
func build(service: Node3D,parent: Node3D) -> Dictionary:
	_service=service;_root=parent
	var brick:=_brick();var pale:=_mat(Color(.80,.80,.75));var stone:=_mat(Color(.39,.43,.44));var red:=_mat(Color(.68,.055,.035));var dark:=_mat(Color(.055,.085,.10));var metal:=_mat(Color(.38,.43,.44));var white:=_mat(Color(.94,.95,.89));var yellow:=_mat(Color(.98,.78,.08));var warm:=_mat(Color(1.,.79,.48),true)
	var glass:=_mat(Color(.19,.38,.43,.36));glass.roughness=.13;glass.metallic=.12
	# Foundation and structural masonry have complete collision. The open bay
	# is 5.6m wide, 4m high and 7.6m deep rather than a solid decorative cube.
	var foundation_depth: float=_service._foundation_depth
	_box("FoundationPlinth",Vector3(12.,foundation_depth,8.),Vector3(0,-foundation_depth*.5,0),stone,true)
	_box("RearBrickWall",Vector3(12.,5.8,.22),Vector3(0,2.9,3.9),brick,true)
	_box("WestBrickWall",Vector3(.24,5.8,8.),Vector3(-5.88,2.9,0),brick,true)
	_box("EastBrickWall",Vector3(.24,5.8,8.),Vector3(5.88,2.9,0),brick,true)
	_box("ReceptionPartition",Vector3(.20,3.1,7.6),Vector3(.65,1.55,.1),pale,true)
	_box("FlatRoofParapet",Vector3(12.3,.30,8.35),Vector3(0,5.95,0),pale,true)
	_box("RoofDarkCap",Vector3(12.4,.10,8.45),Vector3(0,6.15,0),metal)
	_box("UpperFloorFascia",Vector3(12.,1.5,.22),Vector3(0,5.10,-3.91),brick,true)
	for x: float in [-5.62,.50]:_box("RedBayPillar",Vector3(.36,4.15,.46),Vector3(x,2.075,-3.93),red,true)
	_box("RedApparatusHeader",Vector3(6.5,.70,.52),Vector3(-2.55,4.28,-3.93),red,true)
	_box("RaisedSectionalDoor",Vector3(5.60,.25,.58),Vector3(-2.55,3.85,-3.55),metal)
	for i: int in range(7):_box("GarageDoorSlat",Vector3(5.55,.035,.60),Vector3(-2.55,3.73+float(i)*.031,-3.57),dark)
	_text("Apparatus119Header","119  게임안전센터",Vector3(-2.55,4.30,-4.235),.0050)
	_text("GameFacilityDisclosure","가상 소방서 · 현장 위치 재현 아님",Vector3(0,6.73,0),.0025,Color(.98,.94,.80))
	# A glazed reception has a human-sized open front entrance and visible
	# furnishings. The central 1.25m opening remains a real capsule passage.
	_box("ReceptionFrontLeftGlass",Vector3(1.70,2.70,.08),Vector3(1.60,1.50,-3.94),glass,true)
	_box("ReceptionFrontRightGlass",Vector3(1.65,2.70,.08),Vector3(5.02,1.50,-3.94),glass,true)
	for x: float in [.78,2.43,4.19,5.82]:_box("ReceptionMullion",Vector3(.07,3.1,.14),Vector3(x,1.55,-4.),metal,true)
	_box("DoorLintel",Vector3(1.76,.19,.16),Vector3(3.31,2.98,-4.),metal,true)
	_box("ReceptionCanopy",Vector3(5.20,.20,1.35),Vector3(3.30,3.23,-4.45),red,true)
	_box("CanopyWarmLED",Vector3(4.60,.035,.055),Vector3(3.30,3.10,-4.88),warm)
	_text("ReceptionEntrance","민원 · 안전교육  출입구",Vector3(3.30,3.65,-4.45),.0027)
	_text("ReceptionWelcome","안내 · 접수",Vector3(3.35,1.85,-1.75),.0027,Color(.16,.25,.28))
	_box("ReceptionDesk",Vector3(2.50,1.0,.68),Vector3(3.30,.50,-1.85),pale,true)
	_box("ReceptionDeskTop",Vector3(2.70,.07,.80),Vector3(3.30,1.04,-1.85),stone)
	_box("DeskMonitor",Vector3(.48,.35,.055),Vector3(3.45,1.28,-1.77),dark)
	for x: float in [1.5,2.2,2.9]:
		_box("VisitorSeat",Vector3(.52,.12,.55),Vector3(x,.45,.55),red)
		_box("VisitorSeatBack",Vector3(.52,.64,.09),Vector3(x,.77,.80),red)
		for dx: float in [-.19,.19]:_box("VisitorChairLeg",Vector3(.04,.40,.04),Vector3(x+dx,.20,.55),metal)
	_box("BrochureRack",Vector3(.60,1.30,.25),Vector3(5.35,.65,-2.9),metal)
	for y: float in [.50,.82,1.12]:_box("SafetyLeaflet",Vector3(.45,.21,.035),Vector3(5.35,y,-3.045),_mat(Color(.94,.68,.18)))
	# Upper office windows, projecting frames and roof equipment break the
	# roof/side silhouette. The upper storey is an exterior office impression.
	for x: float in [-4.7,-2.8,-.9,1.25,3.25,5.15]:
		_box("UpperOfficeWindowFrame",Vector3(1.60,1.05,.14),Vector3(x,5.0,-4.08),pale)
		_box("UpperOfficeWindow",Vector3(1.42,.90,.055),Vector3(x,5.0,-4.18),glass)
		_box("OfficeWindowMullion",Vector3(.055,.92,.08),Vector3(x,5.0,-4.23),metal)
	for z: float in [-2.3,.1,2.4]:
		_box("SideWindowFrame",Vector3(.13,1.15,1.70),Vector3(6.02,4.70,z),pale)
		_box("SideWindowGlass",Vector3(.06,.98,1.52),Vector3(6.10,4.70,z),glass)
	_box("RoofHVAC",Vector3(1.7,.80,1.45),Vector3(3.7,6.55,1.6),metal)
	for x: float in [3.23,3.68,4.13]:_box("HVACVent",Vector3(.10,.04,1.1),Vector3(x,6.98,1.6),dark)
	_box("119IdentityPylon",Vector3(.90,2.60,.35),Vector3(5.15,5.0,-4.20),red)
	_text("119IdentityLarge","119",Vector3(5.15,5.35,-4.42),.0062)
	_text("SafetyCenterIdentity","소방",Vector3(5.15,4.54,-4.43),.0032)
	# Apparatus bay details are set back from the actual truck footprint.
	for x: float in [-4.8,-3.8,-2.8,-1.8]:
		_box("FireGearLocker",Vector3(.75,2.15,.55),Vector3(x,1.075,3.45),metal,true)
		_box("LockerDoorInset",Vector3(.63,1.90,.045),Vector3(x,1.12,3.145),red)
	_box("WallHoseReel",Vector3(.12,.95,.95),Vector3(-5.60,1.4,.8),yellow)
	_text("BayNumber","01  출동차고",Vector3(-2.55,3.30,3.35),.0032)
	for x: float in [-5.2,.1]:
		_box("BayReflectivePost",Vector3(.20,1.10,.20),Vector3(x,.55,-4.65),yellow,true)
		for y: float in [.25,.65]:_box("BollardBlackBand",Vector3(.215,.15,.215),Vector3(x,y,-4.65),dark)
	for x: float in [-5.05,.0]:_paint_line("ApparatusBayGuide",Vector3(x,.018,-3.5),Vector3(x,.018,3.),.08,yellow)
	for x: float in [-5.2,-4.,-2.8,-1.6,-.4]:
		var stripe:=_box("ExitKeepClearStripe",Vector3(.13,.014,1.1),Vector3(x,.022,-4.45),yellow);stripe.rotation.y=-.5
	_text("KeepClearEntrance","출동차량 진출입 · 주정차 금지",Vector3(-2.55,.16,-5.4),.0021,Color(1.,.85,.24))
	# Bounded local lighting: four unshadowed fixtures, no shared sunlight edit.
	for point: Vector3 in [Vector3(-2.5,3.35,-1.0),Vector3(3.3,2.8,-1.2),Vector3(-2.5,4.4,-4.8),Vector3(3.3,3.4,-4.8)]:
		_box("CeilingLight",Vector3(.95,.05,.22),point,warm)
		var light:=OmniLight3D.new();light.name="FacilityWarmLight";light.position=point;light.omni_range=5.0;light.light_color=Color(1.,.84,.64);light.light_energy=.65;light.shadow_enabled=false;_root.add_child(light)
	return {"width_m":12.0,"depth_m":8.0,"height_m":6.2,"garage_width_m":5.6,"garage_clear_height_m":3.6,"reception_open_door_width_m":1.69,"features":components,"real_station_identity_claim":false,"original_source_geometry_changed":false}
