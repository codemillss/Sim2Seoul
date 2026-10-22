extends Node3D
## Source-linked game shops. Exterior collision and building visit rooms are untouched.
const DESIGN_PATH := "res://assets/authored/shop_service.json"
const STOREFRONT_PATH := "res://assets/authored/street_businesses.json"
const ENTRY_RANGE_M := 3.0
const PRODUCT_RANGE_M := 1.65
var host: Node3D
var loaded := false
var load_error := ""
var active := false
var ui_open := false
var inventory_open := false
var equipped_item_id := ""
var swimwear_active := false
var balance := 50000
var inventory: Dictionary = {}
var transactions: Array[Dictionary] = []
var shops: Array[Dictionary] = []
var events: Array[Dictionary] = []
var current_shop_id := ""
var entry_count := 0
var exit_count := 0
var rejected_entries := 0
var rejected_exits := 0
var rejected_purchases := 0
var _current: Dictionary = {}
var _selected_item_id := ""
var _selection_token := 0
var _spent_tokens: Dictionary = {}
var _last_interact_tick := -100
var _outside := Vector3.ZERO
var _world_spawn := Vector3.ZERO
var _saved: Dictionary = {}
var _ui_saved: Dictionary = {}
var _notice := ""
var _notice_until := 0
var _confirm_held := false
var _ready_tick := 0
var _status_panel: PanelContainer
var _status_text: Label
var _picker: PanelContainer
var _picker_scroll: ScrollContainer
var _picker_title: Label
var _wallet_text: Label
var _inventory_text: Label
var _selection_text: Label
var _receipt_text: Label
var _product_grid: GridContainer
var _buy_button: Button
var _materials: Dictionary = {}
var _original_clothing: Dictionary = {}
var _outfit_details: Node3D
var _wardrobe: PanelContainer
var _wardrobe_scroll: ScrollContainer
var _wardrobe_text: Label
var _wardrobe_buttons: VBoxContainer
var _wardrobe_close: Button
var _swim_saved: Dictionary = {}
var _swim_details: Node3D
var _swim_feet: Array[MeshInstance3D] = []

func setup(scene: Node3D) -> bool:
	if loaded or not is_instance_valid(scene) or not scene.runtime_ok:return false
	host=scene;name="ShopVisitService";process_mode=Node.PROCESS_MODE_ALWAYS;process_physics_priority=2
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(DESIGN_PATH))
	var frontage: Variant=JSON.parse_string(FileAccess.get_file_as_string(STOREFRONT_PATH))
	if not raw is Dictionary or int(raw.get("schema_version",0))!=1 or not raw.get("shops") is Array:return _fail("상점 방문 자료가 다릅니다.")
	if not frontage is Dictionary or raw.get("source_storefronts_sha256","")!=FileAccess.get_sha256(STOREFRONT_PATH):return _fail("상점 외관과 방문 자료가 다릅니다.")
	if not is_instance_valid(host.get("street_businesses")) or not host.street_businesses.loaded:return _fail("거리 상점 외관이 준비되지 않았습니다.")
	balance=int(raw.get("initial_game_credits",50000));_world_spawn=host.player.spawn_transform.origin
	for spec: Dictionary in raw.shops:
		var source: Dictionary={};var facade: Node3D
		if spec.has("virtual_frontage"):
			source=spec.virtual_frontage.duplicate(true);facade=_build_virtual_frontage(source)
		else:
			for existing: Dictionary in host.street_businesses.stores:
				if String(existing.record.id)==String(spec.get("storefront_id","")):source=existing.record;facade=existing.node;break
		if source.is_empty() or not is_instance_valid(facade):return _fail("연결할 실제 표시 상점이 없습니다.")
		if not spec.has_all(["id","title","kind","room_origin","room_size","products"]):return _fail("상점 실내 자료가 부족합니다.")
		var ids: Dictionary={}
		for product: Dictionary in spec.products:
			if not product.has_all(["id","title","price","model","color"]) or int(product.price)<=0 or ids.has(String(product.id)):return _fail("게임 상품 자료가 다릅니다.")
			ids[String(product.id)]=true
		var row: Dictionary=spec.duplicate(true);row.source=source.duplicate(true);row.facade=facade
		row.room=Node3D.new();row.room.name=String(spec.id);add_child(row.room)
		row.origin=_vector(spec.room_origin);row.size=_vector(spec.room_size);row.room.position=row.origin
		# Native floor contact may place the feet a fraction below the visual top.
		# Match existing detached interiors' below-floor recovery allowance.
		row.bounds=AABB(row.origin+Vector3(-row.size.x*.5+.22,-.25,-row.size.z*.5+.22),Vector3(row.size.x-.44,row.size.y+.13,row.size.z-.44))
		# Leave room behind the arrival capsule for the ordinary third-person camera.
		row.spawn=row.origin+Vector3(0.,.08,row.size.z*.5-3.5)
		row.exit=row.origin+Vector3(0.,.08,row.size.z*.5-1.)
		row.interactions=[];row.bodies=[]
		_build_room(row);row.room.visible=false
		var marker:=Label3D.new();marker.name="ShopPortal_"+String(spec.id);marker.text="%s\nE · 상점 출입"%String(spec.title)
		marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED;marker.font_size=30;marker.pixel_size=.0045;marker.outline_size=6;marker.modulate=Color(.92,1.,.73)
		add_child(marker);row.marker=marker;shops.append(row)
	_build_interface();_remember_clothing();_ready_tick=Engine.get_physics_frames()+3;loaded=shops.size()==3
	print("SHOP_VISIT_READY shops=",shops.size()," game_credits=",balance," exterior_unchanged=true session_only=true")
	return loaded

func _fail(message: String) -> bool:
	load_error=message;return false

func _vector(value: Array) -> Vector3:return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _build_virtual_frontage(source: Dictionary) -> Node3D:
	if not host.city.source_nodes.has(String(source.source_feature_id)):return null
	var terrain: Node3D=host.get_node_or_null("TerrainSurface")
	if not is_instance_valid(terrain):return null
	var base: float=terrain.building_base_y_world(String(source.source_feature_id))
	if not is_finite(base):return null
	var out:=Vector3(float(source.outward_xz[0]),0.,float(source.outward_xz[1])).normalized()
	var facade:=Node3D.new();facade.name="AuthoredCitywearFrontage";add_child(facade)
	facade.global_transform=Transform3D(Basis(Vector3.UP.cross(out),Vector3.UP,out),Vector3(float(source.facade_center_xz[0]),base,float(source.facade_center_xz[1]))+out*.045)
	var row: Dictionary={"room":facade,"bodies":[]};var width: float=float(source.facade_width_m)
	_box(row,"CitywearFascia",Vector3(width,.55,.16),Vector3(0.,2.65,.12),Color(.14,.23,.28))
	_label(row,"CitywearName","CITYWEAR · 시티웨어",Vector3(0.,2.70,.23),width-.3,36)
	_label(row,"GameClothingUnit","게임 의류점 · E 출입",Vector3(0.,2.32,.24),4.4,25)
	_box(row,"CitywearDoor",Vector3(1.5,2.15,.045),Vector3(0.,1.1,.13),Color(.27,.42,.46))
	_box(row,"DoorHandle",Vector3(.04,.5,.07),Vector3(.5,1.2,.18),Color(.83,.80,.69))
	for side: float in [-1.,1.]:
		_box(row,"DisplayWindow",Vector3(1.9,1.8,.045),Vector3(side*1.95,1.2,.13),Color(.16,.23,.28))
		_box(row,"WindowGarment",Vector3(.56,.68,.10),Vector3(side*1.95,1.25,.20),Color(.88,.81,.64) if side<0. else Color(.10,.30,.67))
		_box(row,"DisplayRail",Vector3(1.75,.045,.08),Vector3(side*1.95,1.85,.21),Color(.69,.65,.54))
	return facade

func _material(color: Color) -> StandardMaterial3D:
	var key: String=color.to_html()
	if not _materials.has(key):
		var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.72;_materials[key]=material
	return _materials[key]

func _box(row: Dictionary,title: String,size: Vector3,point: Vector3,color: Color,solid:=false) -> MeshInstance3D:
	var mesh:=BoxMesh.new();mesh.size=size
	var node:=MeshInstance3D.new();node.name=title;node.mesh=mesh;node.position=point;node.material_override=_material(color);row.room.add_child(node)
	if solid:
		var body:=StaticBody3D.new();body.name=title+"Body";body.collision_layer=1;body.collision_mask=0
		var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;body.add_child(shape);body.position=point;row.room.add_child(body);row.bodies.append(body)
	return node

func _round(row: Dictionary,title: String,size: Vector3,point: Vector3,color: Color) -> void:
	var mesh:=CylinderMesh.new();mesh.top_radius=.5;mesh.bottom_radius=.5;mesh.height=1.;mesh.radial_segments=16
	var node:=MeshInstance3D.new();node.name=title;node.mesh=mesh;node.position=point;node.scale=size;node.material_override=_material(color);row.room.add_child(node)

func _label(row: Dictionary,title: String,text: String,point: Vector3,width:=2.,font:=28) -> Label3D:
	var label:=Label3D.new();label.name=title;label.text=text;label.position=point;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size=font;label.pixel_size=.004;label.outline_size=4;label.modulate=Color(.98,.96,.85);row.room.add_child(label)
	var aabb: AABB=label.get_aabb()
	if aabb.size.x>width:label.pixel_size*=width/aabb.size.x
	return label

func _build_room(row: Dictionary) -> void:
	var size: Vector3=row.size;var restaurant: bool=String(row.kind)=="restaurant"
	var wall:=Color(.83,.77,.65) if restaurant else Color(.85,.91,.89)
	var wood:=Color(.36,.19,.10) if restaurant else Color(.17,.28,.31)
	_box(row,"Floor",Vector3(size.x,.20,size.z),Vector3(0.,-.10,0.),Color(.45,.32,.20) if restaurant else Color(.65,.70,.68),true)
	_box(row,"BackWall",Vector3(size.x,size.y,.18),Vector3(0.,size.y*.5,-size.z*.5),wall,true)
	_box(row,"FrontWall",Vector3(size.x,size.y,.18),Vector3(0.,size.y*.5,size.z*.5),wall,true)
	for side: float in [-1.,1.]:_box(row,"SideWall",Vector3(.18,size.y,size.z),Vector3(side*size.x*.5,size.y*.5,0.),wall,true)
	_box(row,"Ceiling",Vector3(size.x,.15,size.z),Vector3(0.,size.y,0.),Color(.73,.77,.73),true)
	_box(row,"ExitDoor",Vector3(1.8,2.5,.06),Vector3(0.,1.25,size.z*.5-.11),wood)
	_box(row,"ExitDoorGlass",Vector3(1.5,1.7,.035),Vector3(0.,1.5,size.z*.5-.15),Color(.21,.36,.40))
	_label(row,"ExitSign","E · 밖으로\n입구",Vector3(0.,2.7,size.z*.5-.28),2.0,34)
	_label(row,"ShopTitle",String(row.title),Vector3(0.,3.08,-size.z*.5+.28),5.,42)
	if String(row.kind)!="clothing":_label(row,"GameMenuNotice","게임 메뉴 · 게임 가격\n구매품은 가방에 보관됩니다",Vector3(0.,2.6,-size.z*.5+.35),4.,24)
	for x: float in [-3.,3.]:
		var light:=OmniLight3D.new();light.position=Vector3(x,3.1,0.);light.omni_range=10.;light.light_energy=1.1;light.light_color=Color(1.,.82,.62) if restaurant else Color(.84,.95,1.);light.shadow_enabled=false;row.room.add_child(light)
	if restaurant:
		for side: float in [-1.,1.]:
			for z: float in [-1.7,1.3]:
				var x: float=side*3.6
				_box(row,"DiningTable",Vector3(1.65,.12,1.15),Vector3(x,.77,z),wood,true)
				_box(row,"TableLeg",Vector3(.16,.70,.16),Vector3(x,.35,z),wood)
				for dx: float in [-1.2,1.2]:
					_box(row,"DiningChairSeat",Vector3(.55,.10,.52),Vector3(x+dx,.47,z),wood,true)
					_box(row,"DiningChairBack",Vector3(.10,.65,.52),Vector3(x+dx+signf(dx)*.23,.77,z),wood,true)
				_round(row,"SoybeanBowl",Vector3(.36,.12,.36),Vector3(x,.89,z),Color(.92,.88,.68))
				_box(row,"Chopsticks",Vector3(.025,.02,.32),Vector3(x+.38,.85,z),Color(.71,.65,.53))
		for index: int in range(row.products.size()):
			var x: float=-2.+float(index)*2.
			_build_product(row,row.products[index],Vector3(x,1.05,-3.7),Vector3(x,.08,-2.45))
		_box(row,"MenuCounter",Vector3(6.2,.95,.70),Vector3(0.,.475,-3.7),wood,true)
		for stripe: int in range(12):_box(row,"WoodSlat",Vector3(.035,2.2,.035),Vector3(-5.8+stripe*.25,1.4,-size.z*.5+.12),wood)
	elif String(row.kind)=="clothing":
		for index: int in range(row.products.size()):
			var product: Dictionary=row.products[index];var x: float=(float(index)-1.)*3.6;var color:=Color(float(product.color[0]),float(product.color[1]),float(product.color[2]))
			_box(row,"MannequinPlinth",Vector3(1.35,.15,1.15),Vector3(x,.075,-2.9),wood,true)
			_box(row,"DisplayTorso",Vector3(.43,.47,.25),Vector3(x,1.15,-2.9),color)
			_round(row,"MannequinHead",Vector3(.23,.28,.23),Vector3(x,1.67,-2.9),Color(.77,.73,.64))
			for side: float in [-1.,1.]:
				_box(row,"DisplaySleeve",Vector3(.13,.46,.20),Vector3(x+side*.31,1.15,-2.9),color)
				_box(row,"MannequinLeg",Vector3(.14,.67,.17),Vector3(x+side*.11,.58,-2.9),Color(.32,.34,.33))
			if String(product.outfit.style)=="hoodie":_box(row,"DisplayHood",Vector3(.33,.18,.14),Vector3(x,1.43,-2.78),color)
			_label(row,"GarmentLabel",String(product.title)+"\n"+_money(int(product.price))+" 게임원",Vector3(x,2.35,-2.9),2.7,30)
			row.interactions.append({"id":String(product.id),"anchor":row.origin+Vector3(x,1.18,-2.9),"point":row.origin+Vector3(x,.08,-1.5)})
		for side: float in [-1.,1.]:
			_box(row,"ClothesRail",Vector3(.065,.065,3.),Vector3(side*5.7,1.85,.5),Color(.53,.51,.47))
			for index: int in range(5):_box(row,"HangingGarment",Vector3(.13,.65,.40),Vector3(side*5.7,1.36,-.7+index*.55),Color(.35+index*.08,.32,.27+index*.08))
		_box(row,"FittingCurtain",Vector3(1.6,2.5,.07),Vector3(4.8,1.25,3.3),Color(.36,.22,.25),true)
		_box(row,"MirrorFrame",Vector3(.10,2.1,1.1),Vector3(-6.5,1.2,2.5),wood)
		_box(row,"MirrorStylePanel",Vector3(.12,1.9,.9),Vector3(-6.48,1.2,2.5),Color(.54,.68,.70))
		_label(row,"FittingSign","피팅 공간 · I 소지품에서 재착용",Vector3(3.8,2.9,2.9),4.,27)
	else:
		for side: float in [-1.,1.]:
			var x: float=side*(size.x*.5-.8)
			_box(row,"ShelfBack",Vector3(.65,2.1,6.4),Vector3(x,1.05,-.4),Color(.20,.28,.30),true)
			for level: int in range(4):_box(row,"Shelf",Vector3(.85,.055,6.4),Vector3(x,.45+level*.44,-.4),Color(.88,.90,.85))
		for index: int in range(row.products.size()):
			var side: float=-1. if index<3 else 1.;var z: float=-2.6+float(index%3)*2.1
			var x: float=side*(size.x*.5-.8)
			_build_product(row,row.products[index],Vector3(x-side*.12,1.0,z),Vector3(x-side*1.25,.08,z))
		_box(row,"Checkout",Vector3(2.7,.95,.8),Vector3(0.,.475,-size.z*.5+.8),wood,true)
		_box(row,"Register",Vector3(.55,.35,.4),Vector3(.6,1.12,-size.z*.5+.8),Color(.09,.12,.15))
		for strip: int in range(12):_box(row,"FloorGrout",Vector3(size.x,.003,.012),Vector3(0.,.004,-size.z*.5+strip*.8),Color(.48,.53,.52))

func _build_product(row: Dictionary,product: Dictionary,anchor: Vector3,approach: Vector3) -> void:
	var color:=Color(float(product.color[0]),float(product.color[1]),float(product.color[2]))
	for index: int in range(4):
		var point: Vector3=anchor+Vector3((float(index%2)-.5)*.24,0.,(float(index/2)-.5)*.24)
		match String(product.model):
			"bottle","cup","bowl","plate":
				_round(row,String(product.id),Vector3(.15,.30,.15) if product.model=="bottle" else Vector3(.28,.12,.28),point,color)
				if product.model=="bottle":_round(row,"BottleCap",Vector3(.07,.04,.07),point+Vector3.UP*.17,Color(.94,.96,.99))
			"rice_triangle":
				var mesh:=PrismMesh.new();mesh.size=Vector3(.19,.22,.14);var node:=MeshInstance3D.new();node.mesh=mesh;node.position=point;node.material_override=_material(color);row.room.add_child(node)
			_:
				_box(row,String(product.id),Vector3(.25,.10,.18) if product.model=="lunch_box" else Vector3(.17,.25,.12),point,color)
	_label(row,"ProductLabel_"+String(product.id),"%s\n%s 게임원"%[String(product.title),_money(int(product.price))],anchor+Vector3.UP*.64,1.75,26)
	row.interactions.append({"id":String(product.id),"anchor":row.origin+anchor,"point":row.origin+approach})

func _new_panel(title: String) -> PanelContainer:
	var panel:=PanelContainer.new();panel.name=title;panel.mouse_filter=Control.MOUSE_FILTER_STOP
	var style:=StyleBoxFlat.new();style.bg_color=Color(.035,.07,.09,.96);style.content_margin_left=14;style.content_margin_right=14;style.content_margin_top=12;style.content_margin_bottom=12
	style.corner_radius_top_left=8;style.corner_radius_top_right=8;style.corner_radius_bottom_left=8;style.corner_radius_bottom_right=8;panel.add_theme_stylebox_override("panel",style)
	host.get_node("Interface").add_child(panel);panel.visible=false;panel.z_index=20;return panel

func _text(parent: Node,size:=16) -> Label:
	var label:=Label.new();label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",size);label.add_theme_color_override("font_color",Color(.96,.97,.89));parent.add_child(label);return label

func _build_interface() -> void:
	_status_panel=_new_panel("ShopWalletStatus");_status_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;_status_text=_text(_status_panel,15)
	_picker=_new_panel("ShopProductPicker")
	_picker_scroll=ScrollContainer.new();_picker_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;_picker_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;_picker_scroll.follow_focus=true;_picker.add_child(_picker_scroll)
	var box:=VBoxContainer.new();box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_theme_constant_override("separation",9);_picker_scroll.add_child(box)
	_picker_title=_text(box,20);_wallet_text=_text(box,16)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(0,145);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;box.add_child(scroll)
	_product_grid=GridContainer.new();_product_grid.columns=2;_product_grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(_product_grid)
	_selection_text=_text(box,16)
	_buy_button=Button.new();_buy_button.text="1개 구매";_buy_button.custom_minimum_size.y=42;_buy_button.pressed.connect(purchase_selected);box.add_child(_buy_button)
	_receipt_text=_text(box,15);_inventory_text=_text(box,14)
	var close:=Button.new();close.text="닫고 둘러보기 · E";close.custom_minimum_size.y=36;close.pressed.connect(close_picker);box.add_child(close)
	_wardrobe=_new_panel("OwnedClothingInventory");_wardrobe_scroll=ScrollContainer.new();_wardrobe_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;_wardrobe_scroll.follow_focus=true;_wardrobe.add_child(_wardrobe_scroll)
	var wardrobe_box:=VBoxContainer.new();wardrobe_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;wardrobe_box.add_theme_constant_override("separation",10);_wardrobe_scroll.add_child(wardrobe_box)
	_wardrobe_text=_text(wardrobe_box,17);_wardrobe_buttons=VBoxContainer.new();wardrobe_box.add_child(_wardrobe_buttons)
	var default_button:=Button.new();default_button.text="기본 옷으로 돌아가기";default_button.pressed.connect(restore_default_outfit);wardrobe_box.add_child(default_button)
	_wardrobe_close=Button.new();_wardrobe_close.text="닫기 · I / E";_wardrobe_close.pressed.connect(close_picker);wardrobe_box.add_child(_wardrobe_close)

func _paused() -> bool:return not is_instance_valid(host) or host.menu.visible or get_tree().paused

func _busy_elsewhere() -> bool:
	if host.player.facility_control and not ui_open:return true
	for key: String in ["city_bike_service","city_scooter_service","city_bus_service","drivable_car_service","city_helicopter_service","traffic_car_takeover"]:
		var service: Variant=host.get(key)
		if is_instance_valid(service) and service.get("riding")==true:return true
	return is_instance_valid(host.get("interior_visit")) and (host.interior_visit.active or host.interior_visit.in_elevator or host.interior_visit.elevator_open)

func _door(row: Dictionary) -> Vector3:
	# Match street_businesses._door: convenience door is left of facade center.
	return row.facade.to_global(Vector3(float(row.source.facade_width_m)*float(row.door_local_x_factor),0.,.045))

func _outward(row: Dictionary) -> Vector3:return row.facade.global_basis.z.normalized()

func _line_clear(from: Vector3,to: Vector3) -> bool:
	for height: float in [.70,1.30]:
		var ray:=PhysicsRayQueryParameters3D.create(from+Vector3.UP*height,to+Vector3.UP*height,host.player.collision_mask,[host.player.get_rid()])
		if not host.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():return false
	return true

func _supported(point: Vector3) -> bool:
	if absf(host.player.velocity.y)>.7:return false
	var ray:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.13,point-Vector3.UP*.28,host.player.collision_mask,[host.player.get_rid()])
	var hit: Dictionary=host.get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit.normal.y>=cos(host.player.floor_max_angle) and point.y-hit.position.y>=-.015 and point.y-hit.position.y<=.23

func _nearest_shop() -> Dictionary:
	if not loaded or active or _paused() or _busy_elsewhere() or host.player.interior_active or not host.input_router.gameplay_enabled:return {}
	if not _supported(host.player.global_position):return {}
	var closest: Dictionary={};var best:=ENTRY_RANGE_M
	for row: Dictionary in shops:
		var door: Vector3=_door(row);var out: Vector3=_outward(row);var offset: Vector3=host.player.global_position-door
		var along:=Vector3(out.z,0.,-out.x);var front: float=offset.dot(out)
		if front<.22 or front>ENTRY_RANGE_M or absf(offset.dot(along))>1.35 or absf(offset.y)>1.15:continue
		var distance: float=Vector2(offset.x,offset.z).length()
		if distance>best or not _line_clear(host.player.global_position,door+out*.36):continue
		closest=row;best=distance
	return closest

func _nearest_product() -> Dictionary:
	if not active or ui_open or _paused() or not _supported(host.player.global_position):return {}
	var nearest:=PRODUCT_RANGE_M;var result: Dictionary={}
	for target: Dictionary in _current.interactions:
		var distance: float=host.player.global_position.distance_to(target.point)
		if distance>nearest or not _line_clear(host.player.global_position,target.point):continue
		var ray:=PhysicsRayQueryParameters3D.create(host.player.global_position+Vector3.UP*1.3,target.anchor+Vector3.UP*.15,host.player.collision_mask,[host.player.get_rid()])
		var hit: Dictionary=host.get_world_3d().direct_space_state.intersect_ray(ray)
		# The shelf/counter owns the product: a front-face hit at the final .5m is valid.
		if not hit.is_empty() and hit.position.distance_to(target.anchor+Vector3.UP*.15)>.55:continue
		nearest=distance;result=target
	return result

func _at_exit() -> bool:return active and host.player.global_position.distance_to(_current.exit)<1.35 and _supported(host.player.global_position) and _line_clear(host.player.global_position,_current.exit)

func can_interact() -> bool:
	if not loaded or _paused():return false
	if active:return ui_open or _at_exit() or not _nearest_product().is_empty()
	return not _nearest_shop().is_empty()

func interaction_distance_m() -> float:
	if active:return 0.
	var nearest:=INF
	for row: Dictionary in shops:nearest=minf(nearest,host.player.global_position.distance_to(_door(row)))
	return nearest

func interact() -> bool:
	if not loaded or _paused():return false
	# Host E routing supplies a press edge. A second route in the same tick cannot act twice.
	var tick: int=Engine.get_physics_frames()
	if tick==_last_interact_tick:return true
	_last_interact_tick=tick
	if active:
		if ui_open:close_picker();return true
		if _at_exit():exit_visit();return true
		var target: Dictionary=_nearest_product()
		if not target.is_empty():open_picker(String(target.id));return true
		return false
	var row: Dictionary=_nearest_shop()
	if row.is_empty():return false
	_enter(row);return true

func handle_interact() -> bool:return interact()

func _safe_outside(requested: Vector3) -> Dictionary:
	return host.interior_visit._safe_external_point(requested) if is_instance_valid(host.get("interior_visit")) else {}

func _enter(row: Dictionary) -> bool:
	if Engine.get_physics_frames()<_ready_tick or active or _busy_elsewhere():return false
	var safe: Dictionary={};var out: Vector3=_outward(row)
	for candidate: Vector3 in [host.player.global_position,host.player.global_position+out*.2,_door(row)+out*1.2,_door(row)+out*1.8]:
		safe=_safe_outside(candidate)
		if not safe.is_empty():break
	if safe.is_empty():rejected_entries+=1;_tell("상점 밖의 안전한 복귀 공간을 확인하지 못했습니다.");return false
	if not host.player.begin_interior(row.spawn,row.bounds):rejected_entries+=1;_tell("상점 바닥을 확인 중입니다. 잠시 후 다시 시도하세요.");return false
	_outside=safe.point;_current=row;current_shop_id=String(row.id)
	_saved={"yaw":host.rig.yaw,"pitch":host.rig.pitch,"distance":host.rig.requested_distance,"starting_yaw":host.starting_yaw,"hud_visible":host.hud_panel.visible,"names_processing":host.building_names.is_physics_processing()}
	active=true;entry_count+=1;row.room.visible=true;host.starting_yaw=0.;host.building_names.set_physics_process(false);host.hud_panel.visible=false
	_hide_names();_orient(0.,deg_to_rad(-13.),3.1);_latch_e();_tell("%s · 게임 상품과 게임 가격입니다."%String(row.title));_event("entered",{"shop":current_shop_id,"return_point":_outside});return true

func _orient(yaw: float,pitch: float,distance: float) -> void:
	host.rig.reset_orientation();host.rig.yaw=yaw;host.rig.pitch=pitch;host.rig.requested_distance=distance;host.rig.current_distance=distance;host.rig.snap_to_target_pose()

func _latch_e() -> void:
	if is_instance_valid(host.get("interior_visit")):
		host.interior_visit.e_requires_release=true;host.interior_visit._e_was_pressed=true;host.interior_visit._e_press_pending=false

func _product(id: String) -> Dictionary:
	for product: Dictionary in _current.get("products",[]):
		if String(product.id)==id:return product
	return {}

func _owned_product(id: String) -> Dictionary:
	for row: Dictionary in shops:
		for product: Dictionary in row.products:
			if String(product.id)==id:return product
	return {}

func _remember_clothing() -> void:
	if not is_instance_valid(host.get("exploration_avatar")):return
	for mesh: MeshInstance3D in host.exploration_avatar._meshes:
		var part: String=String(mesh.get_meta("avatar_part",""))
		if part in ["Torso","Shirt","JacketFront","JacketHem","LeftSleeve","RightSleeve","LeftLowerSleeve","RightLowerSleeve"]:
			_original_clothing[mesh.get_instance_id()]={"node":mesh,"material":mesh.material_override,"part":part}

func restore_default_outfit(force:=false) -> bool:
	if swimwear_active and not force:return false
	for saved: Dictionary in _original_clothing.values():
		if is_instance_valid(saved.node):saved.node.material_override=saved.material
	if is_instance_valid(_outfit_details):
		_outfit_details.get_parent().remove_child(_outfit_details);_outfit_details.queue_free();_outfit_details=null
	equipped_item_id=""
	if inventory_open:_refresh_wardrobe()
	return not _original_clothing.is_empty()

func _outfit_box(title: String,size: Vector3,point: Vector3,color: Color) -> void:
	var mesh:=BoxMesh.new();mesh.size=size;var node:=MeshInstance3D.new();node.name=title;node.mesh=mesh;node.position=point;node.material_override=_material(color);_outfit_details.add_child(node)

func equip_owned(item_id: String) -> bool:
	if swimwear_active:return false
	var product: Dictionary=_owned_product(item_id)
	if int(inventory.get(item_id,0))<1 or not product.has("outfit") or _original_clothing.is_empty():return false
	restore_default_outfit()
	var outfit: Dictionary=product.outfit
	for saved: Dictionary in _original_clothing.values():
		if not is_instance_valid(saved.node) or not saved.material is StandardMaterial3D:continue
		var key: String="shirt" if saved.part=="Shirt" else ("trim" if saved.part in ["JacketFront","JacketHem","LeftLowerSleeve","RightLowerSleeve"] else "body")
		var colors: Array=outfit[key];var material: StandardMaterial3D=saved.material.duplicate(true)
		material.albedo_color=Color(float(colors[0]),float(colors[1]),float(colors[2]));saved.node.material_override=material
	_outfit_details=Node3D.new();_outfit_details.name="GameShopWornClothing";host.exploration_avatar._upper_body.add_child(_outfit_details)
	var trim:=Color(float(outfit.trim[0]),float(outfit.trim[1]),float(outfit.trim[2]))
	match String(outfit.style):
		"hoodie":
			_outfit_box("FoldedHood",Vector3(.33,.17,.15),Vector3(0.,.43,.10),trim)
			_outfit_box("FrontPocket",Vector3(.29,.13,.035),Vector3(0.,.12,-.16),trim)
			for side: float in [-1.,1.]:_outfit_box("HoodDrawstring",Vector3(.012,.16,.018),Vector3(side*.045,.31,-.17),Color(.94,.93,.86))
		"cardigan":
			for index: int in range(4):_outfit_box("CardiganButton",Vector3(.025,.025,.02),Vector3(0.,.08+index*.08,-.17),trim)
		"jacket":
			_outfit_box("JacketZipper",Vector3(.015,.37,.022),Vector3(0.,.23,-.17),Color(.69,.72,.73))
			for side: float in [-1.,1.]:_outfit_box("JacketCollar",Vector3(.12,.085,.035),Vector3(side*.10,.405,-.145),trim)
	equipped_item_id=item_id;_event("outfit_equipped",{"item":item_id})
	if inventory_open:_refresh_wardrobe()
	return true

func outfit_snapshot() -> Dictionary:
	var parts: Array=[]
	for saved: Dictionary in _original_clothing.values():
		if not is_instance_valid(saved.node):continue
		var material: Material=saved.node.material_override
		parts.append({"part":saved.part,"original_material":material==saved.material,"color":material.albedo_color if material is StandardMaterial3D else Color.TRANSPARENT})
	return {"equipped_item":equipped_item_id,"swimwear_active":swimwear_active,"parts":parts,"cosmetic_detail_count":_outfit_details.get_child_count() if is_instance_valid(_outfit_details) else 0,"original_avatar_script_unchanged":true,"capsule_modified":false}

func begin_swimwear() -> bool:
	if swimwear_active:return true
	if not loaded or ui_open or not is_instance_valid(host.get("exploration_avatar")) or _original_clothing.is_empty():return false
	_swim_saved={"equipped_item":equipped_item_id,"meshes":[],"details_visible":_outfit_details.visible if is_instance_valid(_outfit_details) else false}
	var skin: Color=host.exploration_avatar._materials.skin.albedo_color
	var shorts:=Color(.035,.35,.45)
	for mesh: MeshInstance3D in host.exploration_avatar._meshes:
		_swim_saved.meshes.append({"node":mesh,"material":mesh.material_override,"visible":mesh.visible})
		var part: String=String(mesh.get_meta("avatar_part",""))
		if part in ["Shirt","JacketFront","JacketHem","LeftShoe","RightShoe","LeftShoeSole","RightShoeSole","LeftShoeLaces","RightShoeLaces"]:
			mesh.visible=false;continue
		var skin_part: bool=part in ["Torso","LeftSleeve","RightSleeve","LeftLowerSleeve","RightLowerSleeve","LeftLowerLeg","RightLowerLeg","LeftShoe","RightShoe"]
		var shorts_part: bool=part in ["Pelvis","LeftUpperLeg","RightUpperLeg"]
		if (skin_part or shorts_part) and mesh.material_override is StandardMaterial3D:
			var material: StandardMaterial3D=host.exploration_avatar._materials.skin.duplicate(true) if skin_part else mesh.material_override.duplicate(true);material.albedo_color=skin if skin_part else shorts;mesh.material_override=material
	if is_instance_valid(_outfit_details):_outfit_details.visible=false
	# Follow the actual pelvis so the waistband remains fitted during stance,
	# swimming and the existing render-only joint interpolation.
	_swim_details=Node3D.new();_swim_details.name="GameSwimShorts";host.exploration_avatar._pelvis.add_child(_swim_details)
	var waist:=MeshInstance3D.new();waist.name="SwimShortsWaistband"
	waist.mesh=preload("res://scripts/player/human_surface_meshes.gd").loft("swim_waist",[[.012,.172,.126,.125,0.],[.025,.174,.127,.126,0.],[.048,.169,.121,.122,0.]],28)
	waist.material_override=_material(Color(.02,.17,.23));_swim_details.add_child(waist)
	for side: String in ["Left","Right"]:
		var bare:=MeshInstance3D.new();bare.name=side+"SwimBareFoot"
		bare.mesh=preload("res://scripts/player/human_surface_meshes.gd").loft("bare_foot",[[-.110,.042,.139,.057,-.030],[-.092,.061,.154,.063,-.030],[-.060,.062,.144,.059,-.025],[-.020,.042,.057,.048,.015],[.009,.036,.044,.042,.022]],24)
		bare.material_override=host.exploration_avatar._materials.skin
		host.exploration_avatar._joints[side+"Foot"].add_child(bare);_swim_feet.append(bare)
	host.exploration_avatar.set_swimwear_visuals(true)
	swimwear_active=true;_event("swimwear_started",{"saved_outfit":equipped_item_id});return true

func end_swimwear() -> bool:
	if not swimwear_active:return true
	host.exploration_avatar.set_swimwear_visuals(false)
	for saved: Dictionary in _swim_saved.get("meshes",[]):
		if is_instance_valid(saved.node):saved.node.material_override=saved.material;saved.node.visible=bool(saved.visible)
	if is_instance_valid(_outfit_details):_outfit_details.visible=bool(_swim_saved.get("details_visible",true))
	if is_instance_valid(_swim_details):_swim_details.get_parent().remove_child(_swim_details);_swim_details.queue_free();_swim_details=null
	for bare: MeshInstance3D in _swim_feet:
		if is_instance_valid(bare):bare.get_parent().remove_child(bare);bare.queue_free()
	_swim_feet.clear()
	equipped_item_id=String(_swim_saved.get("equipped_item",""));swimwear_active=false;_swim_saved.clear();_event("swimwear_ended",{"restored_outfit":equipped_item_id});return true

func focus_current_ui() -> void:
	if not ui_open or _paused():return
	if inventory_open:
		if _wardrobe_buttons.get_child_count()>0:(_wardrobe_buttons.get_child(0) as Button).grab_focus.call_deferred()
		else:_wardrobe_close.grab_focus.call_deferred()
	elif not _buy_button.disabled:_buy_button.grab_focus.call_deferred()
	elif _product_grid.get_child_count()>0:(_product_grid.get_child(0) as Button).grab_focus.call_deferred()

func open_inventory() -> bool:
	if not loaded or swimwear_active or ui_open or _paused() or _busy_elsewhere() or not host.input_router.gameplay_enabled:return false
	if host.player.interior_active and not active:return false
	_ui_saved={"gameplay":host.input_router.gameplay_enabled,"capture":Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"facility":host.player.facility_control,"point":host.player.global_position}
	ui_open=true;inventory_open=true;host.player.set_facility_control(true);host.input_router.gameplay_enabled=false;host.rig.set_capture(false)
	_refresh_wardrobe();_wardrobe.visible=true;_latch_e();focus_current_ui();return true

func _refresh_wardrobe() -> void:
	if not inventory_open:return
	_wardrobe_text.text="소지품 · 잔액 %s 게임원\n%s\n착용 · %s\n이번 실행에서만 유지됩니다."%[_money(balance),_inventory_summary(),String(_owned_product(equipped_item_id).get("title","기본 옷"))]
	for child: Node in _wardrobe_buttons.get_children():_wardrobe_buttons.remove_child(child);child.queue_free()
	for key: String in inventory:
		var product: Dictionary=_owned_product(key)
		if not product.has("outfit"):continue
		var button:=Button.new();button.text=String(product.title)+(" · 착용 중" if key==equipped_item_id else " · 입기");button.custom_minimum_size.y=42;button.pressed.connect(equip_owned.bind(key));_wardrobe_buttons.add_child(button)

func open_picker(item_id: String) -> bool:
	if not active or _paused() or ui_open or _product(item_id).is_empty():return false
	var target: Dictionary=_nearest_product()
	if target.is_empty() or String(target.id)!=item_id:return false
	_ui_saved={"gameplay":host.input_router.gameplay_enabled,"capture":Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"facility":host.player.facility_control}
	ui_open=true;host.player.set_facility_control(true);host.input_router.gameplay_enabled=false;host.rig.set_capture(false);_confirm_held=false
	for child: Node in _product_grid.get_children():_product_grid.remove_child(child);child.queue_free()
	for product: Dictionary in _current.products:
		var button:=Button.new();button.text="%s · %s 게임원"%[String(product.title),_money(int(product.price))];button.custom_minimum_size.y=39;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.pressed.connect(select_item.bind(String(product.id)));_product_grid.add_child(button)
	select_item(item_id);_picker.visible=true;_buy_button.grab_focus.call_deferred();_event("picker_opened",{"shop":current_shop_id,"item":item_id});return true

func select_item(item_id: String) -> bool:
	if not active or not ui_open or _paused() or _product(item_id).is_empty():return false
	_selected_item_id=item_id;_selection_token+=1;_receipt_text.text="구매할 상품을 고르고 ‘1개 구매’를 눌러주세요.";_refresh_picker();return true

func purchase_selected() -> bool:
	if not loaded or not active or not ui_open or _paused():return false
	var item: Dictionary=_product(_selected_item_id)
	if item.is_empty() or _spent_tokens.has(_selection_token):rejected_purchases+=1;return false
	if swimwear_active and item.has("outfit"):
		rejected_purchases+=1;_receipt_text.text="탈의실에서 사복으로 갈아입은 뒤 의상을 구매하세요.";return false
	if item.has("outfit") and int(inventory.get(String(item.id),0))>0:
		_spent_tokens[_selection_token]=true;equip_owned(String(item.id));_receipt_text.text="이미 보유한 의상을 입었습니다. 추가 차감은 없습니다.";_refresh_picker();return true
	var price: int=int(item.price)
	if balance<price:
		rejected_purchases+=1;_receipt_text.text="잔액이 부족합니다. 다른 상품을 선택하세요.";_event("purchase_rejected_insufficient_credits",{"item":item.id});return false
	# Spend the token before any UI/event update. Repeated click/Enter cannot debit twice.
	_spent_tokens[_selection_token]=true;balance-=price;inventory[String(item.id)]=int(inventory.get(String(item.id),0))+1
	var receipt: Dictionary={"transaction":transactions.size()+1,"selection_token":_selection_token,"shop":current_shop_id,"item":String(item.id),"title":String(item.title),"price":price,"balance_after":balance,"quantity_after":inventory[String(item.id)]}
	transactions.append(receipt);_receipt_text.text="구매 완료 · %s 1개\n가방에 보관했습니다. 다시 구매하려면 상품을 새로 선택하세요."%String(item.title)
	if item.has("outfit"):
		equip_owned(String(item.id));_receipt_text.text="구매·착용 완료 · %s\nI 소지품에서 다시 입을 수 있습니다."%String(item.title)
	_refresh_picker();_event("purchased",receipt);return true

func close_picker() -> void:
	if not ui_open:return
	ui_open=false;inventory_open=false;_picker.visible=false;_wardrobe.visible=false;_selected_item_id="";_confirm_held=false
	host.player.set_facility_control(bool(_ui_saved.get("facility",false)));host.input_router.gameplay_enabled=bool(_ui_saved.get("gameplay",true)) and not host.menu.visible
	host.rig.set_capture(bool(_ui_saved.get("capture",true)) and not host.menu.visible);host.player.require_neutral_input();_latch_e();_ui_saved.clear()

func exit_visit() -> bool:
	if not active or _paused() or not _at_exit():return false
	return _exit_candidates([_outside,_door(_current)+_outward(_current)*1.2,_door(_current)+_outward(_current)*1.8])

func _exit_candidates(points: Array) -> bool:
	for candidate: Vector3 in points:
		var safe: Dictionary=_safe_outside(candidate)
		if safe.is_empty() or not host.player.end_interior(safe.point):continue
		_finish_visit(true);exit_count+=1;_event("exited",{"point":safe.point});return true
	rejected_exits+=1;_tell("상점 밖이 막혀 있습니다. 안전한 공간이 생기면 다시 나가세요.");return false

func return_to_world_spawn() -> bool:
	if not active:return true
	return _exit_candidates([_world_spawn])

func leave_for_teleport(point: Vector3) -> bool:
	if not active:return false
	var safe: Dictionary=_safe_outside(point)
	if safe.is_empty() or not host.player.end_interior(safe.point):return false
	_finish_visit(false);exit_count+=1;_event("validated_external_teleport",{"point":safe.point});return true

func leave_for_rooftop(destination: Dictionary) -> bool:
	if not active or not host.has_method("_roof_destination_clear") or not host._roof_destination_clear(destination):return false
	if not destination.get("pool_entry") is Vector3 or not host.player.end_interior(destination.pool_entry):return false
	_finish_visit(false);exit_count+=1;_event("validated_rooftop_teleport",{"point":destination.pool_entry});return true

func after_external_teleport() -> bool:
	if not active:
		if ui_open:close_picker()
		return true
	# Only a successfully applied, supported exterior destination may end the visit.
	if _current.bounds.has_point(host.player.global_position):return false
	var safe: Dictionary=_safe_outside(host.player.global_position)
	if safe.is_empty():return false
	if host.player.interior_active and not host.player.end_interior(safe.point):return false
	_finish_visit(false);exit_count+=1;_event("external_teleport_cleaned",{"point":safe.point});return true

func _finish_visit(restore_view: bool) -> void:
	if ui_open:close_picker()
	_current.room.visible=false;active=false;current_shop_id="";_current={}
	host.starting_yaw=float(_saved.get("starting_yaw",0.));host.hud_panel.visible=bool(_saved.get("hud_visible",true));host.building_names.set_physics_process(bool(_saved.get("names_processing",true)))
	if restore_view:_orient(float(_saved.get("yaw",0.)),float(_saved.get("pitch",-.2)),float(_saved.get("distance",4.)))
	host.player.clear_water_region();host.player.require_neutral_input();_latch_e();_saved.clear();_status_panel.visible=false

func destination(kind: String="shop") -> Dictionary:
	if not loaded:return {}
	for row: Dictionary in shops:
		var wanted: String="restaurant" if kind in ["restaurant","jinjuhoegwan","jinju_game_restaurant"] else ("clothing" if kind in ["clothing","citywear","citywear_game_clothing"] else "convenience")
		if String(row.kind)!=wanted:continue
		var door: Vector3=_door(row);var out: Vector3=_outward(row);var along:=Vector3(out.z,0.,-out.x)
		for offset: float in [0.,.4,-.4,.8,-.8]:
			var safe: Dictionary=_safe_outside(door+out*1.4+along*offset)
			if not safe.is_empty() and _line_clear(safe.point,door+out*.36):return {"point":safe.point,"toward":door+Vector3.UP*1.1,"id":String(row.id),"title":String(row.title)}
	return {}

func prompt_text() -> String:
	if not loaded or _paused():return ""
	if active:
		if ui_open:return "소지품 · 보유 의상 입기 · I / E 닫기" if inventory_open else "상품 선택 · 구매 · E 닫기"
		if _at_exit():return "E · 상점 밖으로 나가기"
		var target: Dictionary=_nearest_product()
		if not target.is_empty():return "E · %s 고르기 · 잔액 %s 게임원"%[String(_product(String(target.id)).title),_money(balance)]
		return "진열 상품 가까이에서 E · 출입문 E 나가기 · I 소지품"
	var row: Dictionary=_nearest_shop()
	return "E · %s 들어가기"%String(row.title) if not row.is_empty() else ""

func _money(value: int) -> String:
	var digits: String=str(value);var result:=""
	for index: int in range(digits.length()):
		if index>0 and (digits.length()-index)%3==0:result+=","
		result+=digits[index]
	return result

func _inventory_summary() -> String:
	var parts:=PackedStringArray()
	for key: String in inventory:
		var title: String=key
		for row: Dictionary in shops:
			for product: Dictionary in row.products:
				if String(product.id)==key:title=String(product.title)
		parts.append("%s ×%d"%[title,int(inventory[key])])
	return "가방 · "+("비어 있음" if parts.is_empty() else " / ".join(parts))

func _refresh_picker() -> void:
	if not ui_open:return
	var item: Dictionary=_product(_selected_item_id)
	_picker_title.text=String(_current.title)+" · 게임 상점"
	_wallet_text.text="잔액 %s 게임원 · 실제 결제 없음"%_money(balance)
	_inventory_text.text=_inventory_summary()+"\n잔액·가방은 이번 실행에서만 유지됩니다."
	_selection_text.text="선택 · %s / %s 게임원"%[String(item.get("title","상품")),_money(int(item.get("price",0)))]
	_buy_button.disabled=item.is_empty() or _spent_tokens.has(_selection_token) or balance<int(item.get("price",0))
	if swimwear_active and item.has("outfit"):_buy_button.text="수영복 착용 중 · 의상 구매 불가";_buy_button.disabled=true
	elif _spent_tokens.has(_selection_token):_buy_button.text="구매 완료 · 상품을 새로 선택하세요"
	elif item.has("outfit") and int(inventory.get(String(item.id),0))>0:_buy_button.text="보유한 의상 입기 · 추가 차감 없음";_buy_button.disabled=false
	elif balance<int(item.get("price",0)):_buy_button.text="잔액 부족 · 다른 상품을 선택하세요"
	else:_buy_button.text=("구매하고 입기 · " if item.has("outfit") else "1개 구매 · ")+"%s 게임원"%_money(int(item.get("price",0)))

func _input(event: InputEvent) -> void:
	if not loaded or _paused() or not event is InputEventKey or event.echo:return
	if event.pressed and event.physical_keycode==KEY_I:
		if ui_open:
			var was_inventory: bool=inventory_open;close_picker()
			if not was_inventory:open_inventory()
		else:open_inventory()
		get_viewport().set_input_as_handled();return
	if not ui_open:return
	if event.physical_keycode in [KEY_ENTER,KEY_KP_ENTER]:
		if not event.pressed:_confirm_held=false
		elif not inventory_open and _buy_button.has_focus() and not _confirm_held:_confirm_held=true;purchase_selected();get_viewport().set_input_as_handled()
	elif event.pressed and event.physical_keycode==KEY_E:
		close_picker();get_viewport().set_input_as_handled()

func _tell(text: String) -> void:_notice=text;_notice_until=Time.get_ticks_msec()+3500
func _event(kind: String,details: Dictionary={}) -> void:events.append({"event":kind,"tick":Engine.get_physics_frames(),"details":details.duplicate(true)})

func _hide_names() -> void:
	host.building_names.panel.visible=false;host.building_names.crosshair.visible=false
	for marker: Dictionary in host.building_names.markers:marker.node.visible=false

func _process(_delta: float) -> void:
	if not loaded:return
	var paused: bool=_paused();var view: Vector2=host.get_viewport().get_visible_rect().size
	if inventory_open and not active and host.player.global_position.distance_to(_ui_saved.get("point",host.player.global_position))>.4:close_picker()
	for row: Dictionary in shops:
		row.marker.global_position=_door(row)+_outward(row)*.45+Vector3.UP*2.7
		row.marker.visible=not active and not paused and host.player.global_position.distance_to(_door(row))<26.
	if active:
		_hide_names();host.hud_panel.visible=false
		_status_text.text="%s · 잔액 %s 게임원\n%s\n%s"%[String(_current.title),_money(balance),_inventory_summary(),_notice if Time.get_ticks_msec()<_notice_until else "진열 상품에서 E · 출입문에서 E 나가기"]
	if ui_open and not paused:host.input_router.gameplay_enabled=false
	_status_panel.visible=active and not ui_open and not paused
	_status_panel.custom_minimum_size.x=minf(510.,maxf(1.,view.x-32.));_status_panel.size=Vector2(_status_panel.custom_minimum_size.x,_status_panel.get_combined_minimum_size().y);_status_panel.position=Vector2(16.,16.)
	_picker.visible=ui_open and not inventory_open and not paused
	_wardrobe.visible=ui_open and inventory_open and not paused
	if ui_open and not inventory_open:
		var width: float=minf(620.,maxf(1.,view.x-32.));var height: float=minf(560.,maxf(120.,view.y-56.))
		_picker_scroll.custom_minimum_size=Vector2(0.,height);_picker.custom_minimum_size.x=width;_picker.size=Vector2(width,height+24.);_picker.position=(view-_picker.size)*.5
	elif inventory_open:
		var height: float=minf(440.,maxf(120.,view.y-56.));_wardrobe_scroll.custom_minimum_size=Vector2(0.,height)
		_wardrobe.custom_minimum_size.x=minf(560.,maxf(1.,view.x-32.));_wardrobe.size=Vector2(_wardrobe.custom_minimum_size.x,height+24.);_wardrobe.position=(view-_wardrobe.size)*.5

func snapshot() -> Dictionary:
	var rows: Array=[]
	for row: Dictionary in shops:rows.append({"id":row.id,"source_feature_id":row.source.source_feature_id,"storefront_id":row.storefront_id,"door":_door(row),"origin":row.origin,"bounds":row.bounds,"spawn":row.spawn,"exit":row.exit,"product_count":row.products.size(),"body_count":row.bodies.size(),"interactions":row.interactions.duplicate(true)})
	return {"loaded":loaded,"error":load_error,"active":active,"ui_open":ui_open,"inventory_open":inventory_open,"outfit":outfit_snapshot(),"shop":current_shop_id,"balance":balance,"inventory":inventory.duplicate(true),"transactions":transactions.duplicate(true),"selection_token":_selection_token,"selected_item":_selected_item_id,"entry_count":entry_count,"exit_count":exit_count,"rejected_entries":rejected_entries,"rejected_exits":rejected_exits,"rejected_purchases":rejected_purchases,"shops":rows,"events":events.duplicate(true),"scope":"Three source-facade-linked authored game shops, including a fictional clothing unit. Session-only game credits/products/prices/outfits, no actual payment/current tenancy/interior reconstruction. Original exterior/catalog/avatar script and capsule unchanged."}

func _exit_tree() -> void:
	# Copied outfit materials never replace the saved original resources permanently.
	inventory_open=false
	if is_instance_valid(host) and is_instance_valid(host.get("exploration_avatar")):end_swimwear();restore_default_outfit(true)
