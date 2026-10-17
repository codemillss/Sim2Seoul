extends Node3D
## Small authored storefronts fitted to retained source building edges.
## This presentation layer never changes an exterior body or offers a new portal.
const CATALOG_PATH := "res://assets/authored/street_businesses.json"
const WORLD_PATH := "res://resources/world_geometry/world.json"
var loaded := false
var load_error := ""
var records: Array[Dictionary] = []
var stores: Array[Dictionary] = []
var placements: Array[Dictionary] = []
var labels: Array[Label3D] = []
var _materials: Dictionary = {}
var _batches: Dictionary = {}
var _world: Node3D
var _player: CharacterBody3D
var _rig: Node3D
var _store: Node3D
var _business_id := ""
var _round_count := 0
var _batch_count := 0

func setup(world: Node3D,player: CharacterBody3D,rig: Node3D) -> bool:
	if loaded or not is_instance_valid(world) or not is_instance_valid(player) or not is_instance_valid(rig):return false
	_world=world;_player=player;_rig=rig;name="StreetBusinesses";process_mode=Node.PROCESS_MODE_PAUSABLE
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not raw is Dictionary or int(raw.get("schema_version",0))!=1 or not raw.get("records") is Array:return _fail("거리 상점 자료 형식이 다릅니다.")
	if String(raw.get("world_sha256",""))!=FileAccess.get_sha256(WORLD_PATH):return _fail("거리 상점과 도시 원본이 다릅니다.")
	_make_materials()
	for row: Dictionary in raw.records:
		if not row.has_all(["id","title","style","source_feature_id","facade_center_xz","outward_xz","facade_width_m","source_edge_xz"]):return _fail("상점의 외벽 배치 자료가 부족합니다.")
		var source: Node3D=world.source_nodes.get(String(row.source_feature_id))
		if not is_instance_valid(source):return _fail("상점을 붙일 원본 건물이 없습니다.")
		var outward := Vector3(float(row.outward_xz[0]),0,float(row.outward_xz[1])).normalized()
		if not outward.is_finite() or outward.length_squared()<.99:return _fail("상점 외벽 방향이 다릅니다.")
		_store=Node3D.new();_store.name=String(row.id);add_child(_store)
		_store.global_transform=world.global_transform*Transform3D(Basis(Vector3.UP.cross(outward),Vector3.UP,outward),Vector3(float(row.facade_center_xz[0]),0,float(row.facade_center_xz[1]))+outward*.045)
		_store.set_meta("business_id",row.id);_store.set_meta("source_feature_id",row.source_feature_id)
		_business_id=String(row.id);_batches={}
		var width := float(row.facade_width_m)
		if row.style=="restaurant":_restaurant(width)
		else:_convenience(width,String(row.style),String(row.title))
		_flush()
		records.append(row.duplicate(true));stores.append({"record":row.duplicate(true),"node":_store})
	loaded=not stores.is_empty()
	print("STREET_BUSINESSES_READY count=",stores.size()," source_edges=true new_entries=0")
	return loaded

func _fail(message: String) -> bool:load_error=message;return false

func _make_materials() -> void:
	var colors := {"frame":Color(.14,.18,.19),"metal":Color(.62,.66,.65),"glass_back":Color(.08,.15,.17),"glass":Color(.32,.58,.61,.20),"white":Color(.94,.94,.86),"paper":Color(.88,.86,.73),"oak":Color(.43,.29,.17),"red":Color(.50,.10,.075),"awning":Color(.31,.16,.11),"rice":Color(.93,.89,.70),"kimchi":Color(.66,.20,.08),"green":Color(.26,.44,.17),"blue":Color(.06,.28,.54),"gs_cyan":Color(.07,.64,.77),"gs_navy":Color(.07,.20,.38),"cu_purple":Color(.40,.18,.58),"cu_lime":Color(.64,.80,.16),"emart_navy":Color(.12,.20,.38),"emart_yellow":Color(.98,.77,.07),"seven_green":Color(.04,.39,.26),"seven_red":Color(.77,.12,.12),"seven_orange":Color(.95,.40,.10),"yellow":Color(.91,.65,.13)}
	for key: String in colors:
		var material := StandardMaterial3D.new();material.albedo_color=colors[key];material.roughness=.72
		if key=="glass":material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.roughness=.15;material.cull_mode=BaseMaterial3D.CULL_DISABLED
		if key in ["white","gs_cyan","cu_lime","emart_yellow"]:material.emission_enabled=true;material.emission=colors[key];material.emission_energy_multiplier=.16
		_materials[key]=material

func _box(role: String,size: Vector3,point: Vector3,material: String,basis := Basis.IDENTITY) -> void:
	if not _batches.has(material):_batches[material]=[]
	_batches[material].append(Transform3D(basis*Basis.from_scale(size),point))
	placements.append({"business_id":_business_id,"role":role,"size_m":size,"local_position":point,"material":material})

func _round(role: String,size: Vector3,point: Vector3,material: String) -> void:
	var mesh := CylinderMesh.new();mesh.top_radius=.5;mesh.bottom_radius=.5;mesh.height=1.;mesh.radial_segments=12
	var node := MeshInstance3D.new();node.name=role;node.mesh=mesh;node.scale=size;node.position=point;node.material_override=_materials[material]
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.set_meta("business_id",_business_id);node.set_meta("storefront_role",role)
	_store.add_child(node);_round_count+=1
	placements.append({"business_id":_business_id,"role":role,"size_m":size,"local_position":point,"material":material})

func _label(role: String,text: String,point: Vector3,width: float,color := Color(.97,.96,.87),size := 42) -> Label3D:
	var node := Label3D.new();node.name=role;node.text=text;node.position=point;node.font_size=size;node.pixel_size=.005
	node.modulate=color;node.outline_size=3;node.outline_modulate=Color(.08,.10,.11);node.no_depth_test=false
	node.set_meta("business_id",_business_id);node.set_meta("storefront_role",role)
	_store.add_child(node)
	var bounds := node.get_aabb()
	if bounds.size.x>width:node.pixel_size*=width/bounds.size.x
	labels.append(node);return node

func _frame(center: Vector3,width: float,height: float) -> void:
	_box("WindowRecess",Vector3(width,height,.035),center,"glass_back")
	for side in [-1.0,1.0]:
		_box("WindowUpright",Vector3(.055,height+.06,.14),center+Vector3(side*width*.5,0,.08),"metal")
		_box("WindowRail",Vector3(width+.055,.055,.14),center+Vector3(0,side*height*.5,.08),"metal")
	_box("WindowGlass",Vector3(width-.035,height-.035,.012),center+Vector3(0,0,.31),"glass")

func _door(x: float) -> void:
	_frame(Vector3(x,1.10,.035),1.08,2.08)
	_box("DoorDivider",Vector3(.03,2.0,.04),Vector3(x,1.10,.23),"metal")
	_box("DoorPushRail",Vector3(.72,.035,.04),Vector3(x,1.08,.37),"metal")
	_box("DoorThreshold",Vector3(1.13,.035,.32),Vector3(x,.025,.16),"frame")

func _restaurant(width: float) -> void:
	_box("RestaurantFascia",Vector3(width,.52,.15),Vector3(0,2.48,.10),"red")
	_label("RestaurantName","진주회관",Vector3(0,2.49,.20),minf(4.8,width-.3),Color(.98,.95,.82),64)
	_label("RestaurantSubline","콩국수 · 김치볶음밥",Vector3(0,2.09,.27),3.6,Color(.97,.93,.78),25)
	_box("RestaurantAwning",Vector3(width+.08,.06,.88),Vector3(0,2.23,.51),"awning",Basis(Vector3.RIGHT,.10))
	for index in range(int(width/.38)):
		_box("AwningTrim",Vector3(.045,.11,.065),Vector3(-width*.5+.19+index*.38,2.12,.94),"paper")
	_door(0.0)
	for side in [-1.0,1.0]:
		var x: float=side*width*.275
		_frame(Vector3(x,1.28,.035),width*.30,1.46)
		_box("RestaurantSill",Vector3(width*.31,.075,.35),Vector3(x,.53,.18),"oak")
		_box("DiningWindowTable",Vector3(width*.26,.06,.30),Vector3(x,.83,.17),"oak")
		for dish in [-.38,.38]:
			_round("NoodleBowl",Vector3(.28,.12,.28),Vector3(x+dish,.925,.15),"white")
			_round("SoybeanSoup",Vector3(.24,.018,.24),Vector3(x+dish,.991,.15),"rice")
			for line in range(4):_box("NoodleStrand",Vector3(.14,.009,.009),Vector3(x+dish,1.004,.10+line*.035),"white")
			_box("KimchiDish",Vector3(.15,.035,.13),Vector3(x+dish+.23,.89,.17),"kimchi")
			for chopstick in [0.,.035]:_box("TableChopsticks",Vector3(.012,.012,.24),Vector3(x+dish-.22+chopstick,.88,.15),"oak")
		_box("WindowCurtain",Vector3(width*.30,.18,.04),Vector3(x,1.95,.29),"paper")
	var board_x := width*.5-.28
	_box("KoreanMenuBoard",Vector3(.52,1.12,.065),Vector3(board_x,1.18,.12),"paper")
	_label("KoreanMenu","콩국수\n김치\n볶음밥",Vector3(board_x,1.18,.17),.46,Color(.26,.14,.10),21)

func _convenience(width: float,style: String,title: String) -> void:
	var main := {"gs25":"gs_navy","cu":"cu_purple","emart24":"emart_navy","seven_eleven":"seven_green"}.get(style,"blue") as String
	var accent := {"gs25":"gs_cyan","cu":"cu_lime","emart24":"emart_yellow","seven_eleven":"seven_orange"}.get(style,"yellow") as String
	_box("ConvenienceFascia",Vector3(width,.52,.16),Vector3(0,2.49,.12),main)
	_box("ConvenienceAccent",Vector3(width,.075,.18),Vector3(0,2.20,.13),accent)
	var name_text: String={"cu":"CU","emart24":"emart24","gs25":"GS25","seven_eleven":"7-ELEVEN"}.get(style,"편의점")
	_label("ConvenienceName",name_text,Vector3(-width*.26,2.50,.22),width*.40,Color(.98,.99,.94),56)
	_label("ConvenienceCategories","도시락 · 음료 · 간식",Vector3(width*.19,2.54,.22),width*.42,Color(.98,.99,.94),24)
	_label("EnglishConvenience","CONVENIENCE STORE",Vector3(width*.19,2.34,.225),width*.42,Color(.98,.99,.94),18)
	if style=="seven_eleven":
		for stripe in range(3):_box("SevenElevenColourStripe",Vector3(width,.035,.018),Vector3(0,2.72-stripe*.038,.218),["seven_orange","seven_green","seven_red"][stripe])
	_door(-width*.31)
	var left := -width*.21
	var right := width*.44
	var center := (left+right)*.5
	_frame(Vector3(center,1.30,.035),right-left,1.63)
	_box("DisplayShelfBase",Vector3(right-left-.12,.09,.30),Vector3(center,.52,.17),"white")
	for shelf in range(3):
		var y := .71+float(shelf)*.36
		_box("DisplayShelf",Vector3(right-left-.12,.045,.28),Vector3(center,y,.17),"white")
		for item in range(10):
			var x := lerpf(left+.19,right-.19,float(item)/9.0)
			var material := ["red","blue","green","yellow","paper"][(item+shelf)%5] as String
			if shelf==0:
				_box("LunchBox",Vector3(.24,.09,.18),Vector3(x,y+.075,.17),material)
				_box("LunchBoxLid",Vector3(.23,.014,.17),Vector3(x,y+.128,.17),"white")
			elif shelf==1:
				_round("DrinkCan",Vector3(.085,.19,.085),Vector3(x,y+.12,.17),material)
				_round("CanCap",Vector3(.087,.012,.087),Vector3(x,y+.22,.17),"metal")
			else:_box("SnackPacket",Vector3(.14,.22,.10),Vector3(x,y+.13,.17),material,Basis(Vector3.FORWARD,(float(item%3)-1.0)*.08))
	_box("FridgeFrame",Vector3(.43,1.50,.12),Vector3(right-.28,1.31,.13),accent)
	for level in range(4):_box("FridgeShelf",Vector3(.35,.025,.18),Vector3(right-.28,.78+level*.28,.24),"white")
	_label("WindowMenu","도시락\n삼각김밥",Vector3(left+.54,1.82,.37),.91,Color(.98,.96,.79),23)
	_label("ShopSourceName",title,Vector3(0,.30,.13),minf(width-.3,4.8),Color(.92,.94,.89),19)

func _flush() -> void:
	for material: String in _batches:
		var poses: Array=_batches[material]
		var mesh := BoxMesh.new();mesh.size=Vector3.ONE
		var multimesh := MultiMesh.new();multimesh.transform_format=MultiMesh.TRANSFORM_3D;multimesh.mesh=mesh;multimesh.instance_count=poses.size()
		for index in range(poses.size()):multimesh.set_instance_transform(index,poses[index])
		var node := MultiMeshInstance3D.new();node.name="Storefront_"+material;node.multimesh=multimesh;node.material_override=_materials[material]
		node.set_meta("business_id",_business_id);node.set_meta("storefront_role","authored_facade_batch")
		node.visibility_range_end=110.;node.visibility_range_end_margin=12.;_store.add_child(node);_batch_count+=1
	_batches={}

func _process(_delta: float) -> void:
	if not loaded or not is_instance_valid(_player):return
	for store: Dictionary in stores:
		var node: Node3D=store.node
		node.visible=_player.global_position.distance_squared_to(node.global_position)<130.*130.
	for label: Label3D in labels:label.visible=_player.global_position.distance_squared_to(label.global_position)<65.*65.

func snapshot() -> Dictionary:
	var rows: Array=[]
	for store: Dictionary in stores:
		var node: Node3D=store.node
		rows.append({"id":store.record.id,"title":store.record.title,"style":store.record.style,"source_feature_id":store.record.source_feature_id,"source_edge_xz":store.record.source_edge_xz,"facade_transform":node.global_transform,"facade_width_m":store.record.facade_width_m,"visible":node.visible,"offers_new_entry":false,"existing_visit_source_match":store.record.existing_visit_source_match})
	return {"loaded":loaded,"error":load_error,"catalog_path":CATALOG_PATH,"store_count":stores.size(),"box_instance_count":placements.size()-_round_count,"round_mesh_count":_round_count,"batch_count":_batch_count,"label_count":labels.size(),"new_collision_objects":0,"new_entries":0,"stores":rows,"placements":placements.duplicate(true),"authored_not_surveyed":true}
