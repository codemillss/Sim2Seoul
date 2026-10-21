extends Node3D
## Regional source-linked game stations, not real station plans or live service.
## The host's existing fresh-E dispatcher is the only interaction input owner.
const DATA_PATH := "res://assets/authored/subway_service.json"
var host: Node3D
var loaded := false
var load_error := ""
var active := false
var riding := false
var running := true
var exit_requested := false
var visit_station := 0
var docked_station := 0
var target_station := 1
var train_state := "doors_open"
var door_fraction := 1.0
var state_elapsed := 0.0
var speed_mps := 0.0
var station_m := 0.0
var route_length_m := 0.0
var direction := 1.0
var completed_legs := 0
var blocked_reason := ""
var events: Array[Dictionary] = []
var stations: Array[Dictionary] = []
var design: Dictionary = {}
var route: Array[Vector3] = []
var cumulative: Array[float] = []
var underground: Node3D
var train: CharacterBody3D
var train_floor: StaticBody3D
var bounds := AABB()
var _origin := Vector3.ZERO
var _world_spawn := Vector3.ZERO
var _materials: Dictionary = {}
var _train_doors: Array[Node3D] = []
var _ride_saved: Dictionary = {}
var _visit_saved: Dictionary = {}
var _release_pending := false
var _release_tick := 0
var _release_hold_controls := false
var _release_physics := true
var _last_interact_tick := -1
var _ready_tick := 0
var _status_panel: PanelContainer
var _status: Label
var _notice := ""
var _notice_until := 0

func setup(scene: Node3D) -> bool:
	if loaded or not is_instance_valid(scene) or not scene.runtime_ok:return false
	host=scene;name="CitySubwayService";process_mode=Node.PROCESS_MODE_ALWAYS;process_physics_priority=2
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not raw is Dictionary or int(raw.get("schema_version",0))!=1 or not raw.get("stations") is Array or raw.stations.size()!=2:return _fail("지하철 체험 자료가 다릅니다.")
	if String(raw.get("world_sha256",""))!=FileAccess.get_sha256("res://resources/world_geometry/world.json"):return _fail("지하철과 도시 원본이 다릅니다.")
	design=raw;_origin=_v3(raw.underground_origin);_world_spawn=host.player.spawn_transform.origin
	var total:=0.0
	for point: Array in raw.route.xz:
		var at: Vector3=_origin+Vector3(float(point[0]),0.,float(point[1]))
		if not route.is_empty():total+=at.distance_to(route.back())
		route.append(at);cumulative.append(total)
	if route.size()<2 or absf(total-float(raw.route.length_m))>.001:return _fail("지하철 원본 선형 길이가 다릅니다.")
	route_length_m=total;underground=Node3D.new();underground.name="AuthoredUnderground";add_child(underground)
	var low:=route[0];var high:=route[0]
	for at: Vector3 in route:low=low.min(at);high=high.max(at)
	bounds=AABB(Vector3(low.x-48.,_origin.y-.45,low.z-48.),Vector3(high.x-low.x+96.,8.0,high.z-low.z+96.))
	_build_tunnel()
	for index: int in range(2):
		var row: Dictionary=raw.stations[index].duplicate(true);row.index=index;row.node=Node3D.new();row.node.name=String(row.id);underground.add_child(row.node)
		row.frame=_frame(float(row.route_station_m));row.node.global_transform=row.frame;row.gate_open=false;row.screen_leaves=[];row.gate_leaves=[];row.bodies=[]
		row.spawn=row.frame*Vector3(0.,3.08,31.);row.exit=row.frame*Vector3(0.,3.08,33.);row.gate=row.frame*Vector3(0.,3.08,28.3);row.wait=row.frame*Vector3(0.,.08,3.1)
		var source: Array=row.entrance.source_xz;row.anchor=Vector3(float(source[0]),0.,float(source[1]));row.outward=Vector3(float(row.outward_xz[0]),0.,float(row.outward_xz[1])).normalized()
		var terrain: Node3D=host.get_node_or_null("TerrainSurface");var ground: float=terrain.ground_y_world(row.anchor) if is_instance_valid(terrain) else NAN
		if not is_finite(ground):return _fail("원본 지하철 출구의 지면이 없습니다.")
		row.anchor.y=ground;_build_station(row);_build_surface_entry(row);stations.append(row)
	_build_train();_build_interface();underground.visible=false;_ready_tick=Engine.get_physics_frames()+3;loaded=true
	_update_doors();print("CITY_SUBWAY_READY stations=2 route_m=",route_length_m," source_way=1458437476 original_surface_entrances=true game_station_plans=true")
	return true

func _fail(text: String) -> bool:load_error=text;return false
func _v3(value: Array) -> Vector3:return Vector3(float(value[0]),float(value[1]),float(value[2]))
func _event(kind: String,extra: Dictionary={}) -> void:
	events.append({"event":kind,"tick":Engine.get_physics_frames(),"station_m":station_m,"extra":extra.duplicate(true)})
	if events.size()>160:events.pop_front()

func _mat(color: Color) -> StandardMaterial3D:
	var key: String=color.to_html()
	if not _materials.has(key):
		var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.65
		if color.a<.99:material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.cull_mode=BaseMaterial3D.CULL_DISABLED
		_materials[key]=material
	return _materials[key]

func _box(parent: Node3D,title: String,size: Vector3,point: Vector3,color: Color,solid:=false) -> Node3D:
	var mesh:=BoxMesh.new();mesh.size=size;var node:=MeshInstance3D.new();node.name=title;node.mesh=mesh;node.position=point;node.material_override=_mat(color);parent.add_child(node)
	if solid:
		var body:=StaticBody3D.new();body.name=title+"Body";body.position=point;body.collision_layer=1;body.collision_mask=0
		var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;body.add_child(shape);parent.add_child(body)
	return node

func _label(parent: Node3D,title: String,text: String,point: Vector3,width:=6.,font:=34) -> Label3D:
	var label:=Label3D.new();label.name=title;label.text=text;label.position=point;label.font_size=font;label.pixel_size=.005;label.outline_size=4;label.modulate=Color(.98,.98,.92);label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;parent.add_child(label)
	var box: AABB=label.get_aabb()
	if box.size.x>width:label.pixel_size*=width/box.size.x
	return label

func _frame(distance: float) -> Transform3D:
	var at: float=clampf(distance,0.,route_length_m)
	for index: int in range(route.size()-1):
		if at<=cumulative[index+1]+.000001:
			var tangent: Vector3=(route[index+1]-route[index]).normalized();var fraction: float=(at-cumulative[index])/maxf(.001,cumulative[index+1]-cumulative[index])
			return Transform3D(Basis(tangent,Vector3.UP,Vector3(-tangent.z,0.,tangent.x)),route[index].lerp(route[index+1],fraction))
	return Transform3D(Basis.IDENTITY,route.back())

func _build_tunnel() -> void:
	for index: int in range(route.size()-1):
		var a: Vector3=route[index];var b: Vector3=route[index+1];var length: float=a.distance_to(b);var tangent: Vector3=(b-a).normalized()
		var segment:=Node3D.new();segment.name="SourceTrackSegment"+str(index);underground.add_child(segment);segment.global_transform=Transform3D(Basis(tangent,Vector3.UP,Vector3(-tangent.z,0.,tangent.x)),(a+b)*.5)
		_box(segment,"TrackBed",Vector3(length+.2,.25,8.8),Vector3(0.,-.78,0.),Color(.16,.18,.19),true)
		for side: float in [-1.,1.]:
			_box(segment,"RunningRail",Vector3(length+.2,.09,.09),Vector3(0.,-.40,side*.72),Color(.50,.53,.55))
			var opening: float=24. if side>0. and index in [0,route.size()-2] else 0.
			var offset: float=opening*.5 if index==0 else -opening*.5
			if length>opening:_box(segment,"TunnelWallPlus" if side>0. else "TunnelWallMinus",Vector3(length-opening+.1,4.1,.18),Vector3(offset if side>0. else 0.,1.35,side*4.8),Color(.20,.23,.25),true)
		_box(segment,"TunnelCeiling",Vector3(length+.3,.18,9.7),Vector3(0.,3.45,0.),Color(.17,.20,.22),true)
		for tie: int in range(int(length/1.5)):_box(segment,"Sleeper",Vector3(.19,.12,2.2),Vector3(-length*.5+tie*1.5,-.51,0.),Color(.28,.26,.23))
		for marker: int in range(int(length/12.)):_box(segment,"TunnelGuideLight",Vector3(.6,.10,.05),Vector3(-length*.5+marker*12.,1.4,-4.68),Color(.81,.85,.74))

func _build_station(row: Dictionary) -> void:
	var parent: Node3D=row.node;var color:=Color(float(row.color[0]),float(row.color[1]),float(row.color[2]));var tile:=Color(.82,.86,.85) if row.theme=="civic" else Color(.77,.83,.73)
	_box(parent,"PlatformFloor",Vector3(46.,.22,12.6),Vector3(0.,-.11,8.2),Color(.52,.58,.58),true)
	for side: float in [-1.,1.]:
		_box(parent,"EndWall",Vector3(.18,4.,12.6),Vector3(side*23.,2.,8.2),tile,true)
		_box(parent,"BackWall",Vector3(20.6,4.,.18),Vector3(side*12.7,2.,14.4),tile,true)
		_box(parent,"PlatformLineBand",Vector3(20.8,.30,.05),Vector3(side*12.7,2.75,14.28),color)
		_box(parent,"ScreenGlass",Vector3(21.6,3.15,.10),Vector3(side*12.3,1.575,1.75),Color(.23,.40,.42,.28),true)
		_box(parent,"ScreenTopRail",Vector3(23.,.14,.20),Vector3(side*11.5,3.10,1.75),Color(.43,.48,.48))
	_box(parent,"PlatformCeiling",Vector3(46.,.14,12.6),Vector3(0.,4.05,8.2),Color(.72,.76,.74),true)
	for index: int in range(18):
		var x: float=-21.5+index*2.5
		_box(parent,"TactilePaving",Vector3(2.45,.018,.38),Vector3(x,.012,2.42),Color(.94,.72,.08))
		for dot: int in range(5):_box(parent,"TactileDot",Vector3(.10,.018,.10),Vector3(x-.8+dot*.4,.03,2.42),Color(.99,.79,.13))
	for x: float in [-16.,16.]:
		_box(parent,"Column",Vector3(.65,3.9,.65),Vector3(x,1.95,9.),tile,true);_box(parent,"ColumnLineBand",Vector3(.67,.35,.67),Vector3(x,2.65,9.),color)
		_box(parent,"Bench",Vector3(3.,.45,.65),Vector3(x,.225,12.),color,true)
		_label(parent,"StationName",String(row.title)+"\n"+String(row.subtitle),Vector3(x,2.25,12.8),8.,42)
	for side: float in [-1.,1.]:
		var leaf:=Node3D.new();leaf.name="PlatformScreenDoor";parent.add_child(leaf);row.screen_leaves.append({"node":leaf,"side":side})
		_box(leaf,"SlidingScreenLeaf",Vector3(1.38,2.85,.10),Vector3.ZERO,Color(.22,.42,.47,.45),true)
		_label(leaf,"DoorArrow","←" if side<0. else "→",Vector3(0.,.5,.08),.6,34)
	row.departure_label=_label(parent,"DepartureBoard","",Vector3(0.,2.85,6.0),8.,36)
	_label(parent,"GameRouteMap","GAME S-01\n시청  ←→  을지로입구",Vector3(-8.,2.1,14.25),9.,32)
	_label(parent,"ExitWayfinding","출구 "+String(row.entrance_ref)+" ↑\n계단 · 개찰구",Vector3(7.2,2.5,12.3),6.,30)
	# Visible treads share one continuous sloping native support, as in the
	# existing game stairs. This is an authored stair, not a surveyed section.
	var points:=PackedVector3Array([Vector3(-2.,-.22,13.),Vector3(2.,-.22,13.),Vector3(-2.,0.,13.),Vector3(2.,0.,13.),Vector3(-2.,2.78,25.),Vector3(2.,2.78,25.),Vector3(-2.,3.,25.),Vector3(2.,3.,25.)])
	var ramp:=StaticBody3D.new();ramp.name="StairRampSupport";ramp.collision_layer=1;ramp.collision_mask=0;var shape:=CollisionShape3D.new();var convex:=ConvexPolygonShape3D.new();convex.points=points;shape.shape=convex;ramp.add_child(shape);parent.add_child(ramp)
	for step: int in range(20):_box(parent,"StairTread",Vector3(4.,.13,.61),Vector3(0.,step*.15-.06,13.+step*.6),tile)
	for side: float in [-1.,1.]:
		var rail:=_box(parent,"StairHandrail",Vector3(.06,.06,12.4),Vector3(side*2.1,2.6,19.),Color(.56,.60,.61));rail.rotation.x=-atan2(3.,12.)
		_box(parent,"StairSideWall",Vector3(.15,6.9,12.4),Vector3(side*2.35,3.2,19.),tile,true)
	_box(parent,"UpperConcourse",Vector3(18.,.22,11.2),Vector3(0.,2.89,30.5),tile,true)
	_box(parent,"ConcourseBackWall",Vector3(18.,3.6,.16),Vector3(0.,4.8,36.),tile,true)
	for side: float in [-1.,1.]:_box(parent,"ConcourseSideWall",Vector3(.16,3.6,11.2),Vector3(side*9.,4.8,30.5),tile,true)
	_box(parent,"ConcourseCeiling",Vector3(18.,.15,11.2),Vector3(0.,6.7,30.5),Color(.75,.78,.75),true)
	for side: float in [-1.,1.]:
		_box(parent,"TicketGateCase",Vector3(.55,1.05,1.5),Vector3(side*.82,3.525,27.2),Color(.48,.54,.55),true)
		_box(parent,"TicketGateBarrier",Vector3(7.5,1.15,.12),Vector3(side*5.1,3.575,27.2),Color(.44,.50,.51),true)
		_box(parent,"TransitCardReader",Vector3(.28,.12,.35),Vector3(side*.82,4.08,27.2),Color(.06,.17,.23))
		var leaf:=Node3D.new();leaf.name="TicketGateWing";parent.add_child(leaf);row.gate_leaves.append({"node":leaf,"side":side})
		_box(leaf,"GateWing",Vector3(.50,.80,.08),Vector3.ZERO,color,true)
	_label(parent,"TapCardSign","E · 교통카드 태그\n게임 개찰 · 요금 없음",Vector3(0.,5.15,27.2),5.,30)
	_label(parent,"SurfaceExit","E · 지상 출구 "+String(row.entrance_ref)+"\n"+String(row.title),Vector3(0.,5.3,35.5),6.,38)
	_label(parent,"StationPoster",("서울광장 · 덕수궁" if row.theme=="civic" else "도심 상가 · 문화 산책"),Vector3(-6.3,4.7,35.5),5.2,30)
	for x: float in [-10.,10.]:
		var light:=OmniLight3D.new();light.position=Vector3(x,3.2,8.);light.omni_range=23.;light.light_energy=1.25;light.shadow_enabled=false;parent.add_child(light)
	var upper_light:=OmniLight3D.new();upper_light.position=Vector3(0.,6.,30.);upper_light.omni_range=20.;upper_light.light_energy=1.2;upper_light.shadow_enabled=false;parent.add_child(upper_light)

func _build_surface_entry(row: Dictionary) -> void:
	var portal:=Node3D.new();portal.name="SourceEntrance_"+String(row.id);add_child(portal);portal.position=row.anchor
	var out: Vector3=row.outward;portal.basis=Basis(Vector3(out.z,0.,-out.x),Vector3.UP,out)
	var color:=Color(float(row.color[0]),float(row.color[1]),float(row.color[2]))
	_box(portal,"ExitCanopy",Vector3(2.2,.16,1.2),Vector3(0.,2.7,-.35),color)
	for side: float in [-1.,1.]:_box(portal,"ExitPillar",Vector3(.10,2.65,.10),Vector3(side*1.05,1.325,-.65),Color(.54,.58,.56))
	_box(portal,"MetroNameBoard",Vector3(2.8,.72,.12),Vector3(0.,3.02,.12),color)
	_label(portal,"SourceExitName",String(row.title)+"역 "+String(row.entrance_ref)+"\nE · 게임 지하역",Vector3(0.,3.05,.20),2.7,32)
	row.portal=portal

func _build_train() -> void:
	train=CharacterBody3D.new();train.name="GameSubwayTrain";train.collision_layer=4;train.collision_mask=1|2|4;train.floor_snap_length=0.;underground.add_child(train)
	var shape:=CollisionShape3D.new();shape.name="CollisionShape";var box:=BoxShape3D.new();box.size=Vector3(18.,3.,2.8);shape.shape=box;shape.position=Vector3(0.,1.5,0.);train.add_child(shape)
	_box(train,"CabinFloor",Vector3(17.8,.08,2.65),Vector3(0.,.04,0.),Color(.46,.50,.49),true);train_floor=train.get_node("CabinFloorBody")
	train.add_collision_exception_with(train_floor);train_floor.add_collision_exception_with(train)
	_box(train,"Roof",Vector3(18.,.13,2.9),Vector3(0.,3.,0.),Color(.65,.69,.67))
	for side: float in [-1.,1.]:
		_box(train,"CarEnd",Vector3(.13,2.85,2.8),Vector3(side*8.9,1.5,0.),Color(.75,.79,.78))
		_box(train,"CarNoseWindow",Vector3(.15,1.,2.1),Vector3(side*8.92,2.,0.),Color(.12,.23,.28,.30))
		_box(train,"LowerBody",Vector3(17.6,.83,.10),Vector3(0.,.49,side*1.4),Color(.73,.77,.76))
		_box(train,"LineStripe",Vector3(17.6,.18,.12),Vector3(0.,.86,side*1.41),Color(.07,.46,.29))
		_box(train,"UpperWindowBand",Vector3(17.6,1.75,.045),Vector3(0.,1.93,side*1.4),Color(.20,.36,.40,.22))
	for x: float in [-6.,-3.,3.,6.]:
		for side: float in [-1.,1.]:
			_box(train,"BenchSeat",Vector3(2.5,.38,.5),Vector3(x,.40,side*.98),Color(.67,.29,.42) if x==6. else Color(.19,.35,.58))
			_box(train,"BenchBack",Vector3(2.5,.62,.12),Vector3(x,.84,side*1.2),Color(.67,.29,.42) if x==6. else Color(.19,.35,.58))
	for side: float in [-1.,1.]:
		var leaf:=Node3D.new();leaf.name="TrainDoor";train.add_child(leaf);_train_doors.append(leaf);leaf.set_meta("side",side)
		_box(leaf,"DoorLeaf",Vector3(1.3,2.7,.08),Vector3.ZERO,Color(.68,.74,.73))
		_box(leaf,"DoorWindow",Vector3(.8,1.15,.085),Vector3(0.,.3,.01),Color(.14,.26,.31,.30))
	_box(train,"OverheadRail",Vector3(15.,.055,.055),Vector3(0.,2.5,0.),Color(.61,.65,.65))
	for x: int in range(-7,8):
		_box(train,"HandleStrap",Vector3(.025,.28,.025),Vector3(float(x),2.32,0.),Color(.79,.80,.75))
		var ring:=TorusMesh.new();ring.inner_radius=.065;ring.outer_radius=.095;ring.rings=12;ring.ring_segments=8;var handle:=MeshInstance3D.new();handle.name="HandStrapRing";handle.mesh=ring;handle.rotation.x=PI*.5;handle.position=Vector3(float(x),2.12,0.);handle.material_override=_mat(Color(.86,.86,.80));train.add_child(handle)
	_label(train,"InsideRouteMap","GAME S-01 · 시청 ↔ 을지로입구\n노약자 배려석 · 출입문 주의",Vector3(0.,2.7,-1.15),7.,26)
	var light:=OmniLight3D.new();light.position=Vector3(0.,2.6,0.);light.omni_range=13.;light.light_energy=1.4;light.shadow_enabled=false;train.add_child(light)
	train.global_transform=_frame(0.)

func _build_interface() -> void:
	_status_panel=PanelContainer.new();_status_panel.name="SubwayVisitStatus";_status_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var style:=StyleBoxFlat.new();style.bg_color=Color(.035,.075,.11,.94);style.content_margin_left=13;style.content_margin_right=13;style.content_margin_top=9;style.content_margin_bottom=9;_status_panel.add_theme_stylebox_override("panel",style)
	_status=Label.new();_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_status.add_theme_font_size_override("font_size",16);_status_panel.add_child(_status);host.get_node("Interface").add_child(_status_panel);_status_panel.visible=false

func _paused() -> bool:return not running or host.menu.visible or get_tree().paused

func _busy() -> bool:
	if _release_pending or host.player.facility_control:return true
	for key: String in ["city_bike_service","city_scooter_service","city_bus_service","drivable_car_service","city_helicopter_service"]:
		var service: Variant=host.get(key)
		if is_instance_valid(service) and service.get("riding")==true:return true
	var shop: Variant=host.get("shop_visit_service")
	if is_instance_valid(shop) and (shop.active or shop.ui_open or shop.swimwear_active):return true
	return host.interior_visit.active or host.interior_visit.in_elevator or host.interior_visit.elevator_open or (host.player.interior_active and not active)

func _supported(point: Vector3) -> bool:
	if absf(host.player.velocity.y)>.7:return false
	var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.14,point-Vector3.UP*.30,host.player.collision_mask,[host.player.get_rid()]))
	return not hit.is_empty() and hit.normal.y>=cos(host.player.floor_max_angle) and point.y-hit.position.y>=-.02 and point.y-hit.position.y<=.24

func _line_clear(from: Vector3,to: Vector3) -> bool:
	for height: float in [.75,1.3]:
		if not get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from+Vector3.UP*height,to+Vector3.UP*height,host.player.collision_mask,[host.player.get_rid()])).is_empty():return false
	return true

func _surface_safe(point: Vector3) -> Dictionary:return host.interior_visit._safe_external_point(point)

func _surface_destination(index: int) -> Dictionary:
	var row: Dictionary=stations[index];var out: Vector3=row.outward;var along:=Vector3(out.z,0.,-out.x)
	for forward: float in [2.4,1.2,3.4,0.]:
		for offset: float in [0.,.7,-.7,1.4,-1.4]:
			var safe: Dictionary=_surface_safe(row.anchor+out*forward+along*offset)
			if not safe.is_empty() and _line_clear(safe.point,row.anchor+out*.35):return {"point":safe.point,"toward":row.anchor+Vector3.UP*1.3,"id":row.id,"station_index":index,"title":row.title,"source_entrance_id":row.entrance.osm_node_id}
	return {}

func destination(kind: String="subway") -> Dictionary:
	if not loaded:return {}
	return _surface_destination(1 if kind in ["subway_euljiro","euljiro","euljiro_game"] else 0)

func _entry_candidate() -> int:
	if not loaded or active or _paused() or _busy() or not host.input_router.gameplay_enabled or not _supported(host.player.global_position):return -1
	var nearest:=3.7;var result:=-1
	for index: int in range(stations.size()):
		var row: Dictionary=stations[index];var offset: Vector3=host.player.global_position-row.anchor;var distance: float=Vector2(offset.x,offset.z).length()
		if distance>nearest or absf(offset.y)>1.1 or not _line_clear(host.player.global_position,row.anchor+row.outward*.35):continue
		nearest=distance;result=index
	return result

func can_interact() -> bool:
	if not loaded or _paused():return false
	if active:return true
	return _entry_candidate()>=0

func interaction_distance_m() -> float:
	if active:return 0.
	var nearest:=INF
	for row: Dictionary in stations:nearest=minf(nearest,host.player.global_position.distance_to(row.anchor))
	return nearest

func _latch() -> void:
	host.interior_visit.e_requires_release=true;host.interior_visit._e_was_pressed=true;host.interior_visit._e_press_pending=false

func handle_interact() -> bool:
	if not loaded or _paused():return false
	var tick: int=Engine.get_physics_frames()
	if tick==_last_interact_tick:return true
	_last_interact_tick=tick
	if riding:
		if train_state=="doors_open":_disembark()
		else:exit_requested=true;_tell("다음 역에 도착하면 내립니다.")
		return true
	if active:
		var row: Dictionary=stations[visit_station];var point: Vector3=host.player.global_position
		if not _supported(point):_tell("바닥에 내려선 뒤 이용하세요.");return true
		if point.distance_to(row.exit)<1.8:return exit_visit()
		if point.distance_to(row.gate)<2.1:
			row.gate_open=true;_update_doors();_tell("게임 교통카드 확인 · 개찰구가 열렸습니다.");_event("gate_opened",{"station":visit_station});return true
		if point.distance_to(row.wait)<2.1:
			if docked_station==visit_station and train_state=="doors_open":_board()
			else:_tell("열차를 기다리세요. 약 %d초"%int(ceil(_eta(visit_station))))
			return true
		return true
	var index: int=_entry_candidate()
	if index<0:return false
	_enter(index);return true

func _enter(index: int) -> bool:
	if active or _busy() or Engine.get_physics_frames()<_ready_tick:return false
	var outside: Dictionary=_surface_destination(index)
	if outside.is_empty():_tell("출구의 안전한 도보 공간을 확인하지 못했습니다.");return false
	var row: Dictionary=stations[index]
	if not host.player.begin_interior(row.spawn,bounds):_tell("지하역 바닥을 준비 중입니다.");return false
	_visit_saved={"yaw":host.rig.yaw,"pitch":host.rig.pitch,"distance":host.rig.requested_distance,"hud":host.hud_panel.visible,"names":host.building_names.is_physics_processing(),"starting_yaw":host.starting_yaw}
	active=true;visit_station=index;underground.visible=true;row.gate_open=false;host.starting_yaw=0.;host.building_names.set_physics_process(false);_orient(row.frame,3.5);_latch();_update_doors();_event("entered_station",{"station":index,"source_entrance":row.entrance.osm_node_id});return true

func _orient(frame: Transform3D,distance: float) -> void:
	host.rig.reset_orientation();host.rig.yaw=atan2(frame.basis.z.x,frame.basis.z.z);host.rig.pitch=deg_to_rad(-13.);host.rig.requested_distance=distance;host.rig.current_distance=distance;host.rig.snap_to_target_pose()

func _safe_indoor(point: Vector3,exclude_train:=false) -> bool:
	if not bounds.has_point(point):return false
	var excluded: Array[RID]=[host.player.get_rid()]
	if exclude_train:excluded.append(train.get_rid())
	var space: PhysicsDirectSpaceState3D=get_world_3d().direct_space_state
	var ground: Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.45,point-Vector3.UP*.35,host.player.collision_mask,excluded))
	if ground.is_empty() or ground.normal.y<.7 or absf(point.y-ground.position.y)>.24:return false
	var shape: CollisionShape3D=host.player.get_node("CollisionShape");var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape.shape;query.transform=Transform3D(Basis.IDENTITY,point)*shape.transform;query.collision_mask=host.player.collision_mask;query.exclude=excluded
	return space.intersect_shape(query,1).is_empty()

func _board() -> bool:
	if riding or _release_pending or docked_station!=visit_station or train_state!="doors_open" or door_fraction<.98:return false
	var row: Dictionary=stations[visit_station]
	if not row.gate_open or not _supported(host.player.global_position) or not _line_clear(host.player.global_position,row.wait):return false
	var seat: Vector3=train.to_global(Vector3(-2.,.16,0.))
	if not _safe_indoor(seat,true):_tell("열차 안의 안전한 자리를 확인 중입니다.");return false
	var player: CharacterBody3D=host.player
	_ride_saved={"physics":player.is_physics_processing(),"layer":player.collision_layer,"mask":player.collision_mask,"visual_transform":player.get_node("Visual").transform,"avatar_transform":host.exploration_avatar.transform,"rig_distance":host.rig.requested_distance,"rig_max":host.rig.distance_max_m,"rig_yaw":host.rig.yaw,"rig_pitch":host.rig.pitch,"exclude":host.rig._query.exclude.duplicate()}
	train.add_collision_exception_with(player);player.add_collision_exception_with(train);player.set_facility_control(true);player.set_physics_process(false)
	host.rig._query.exclude.append(train.get_rid());host.rig._query.exclude.append(train_floor.get_rid());host.rig.arm.add_excluded_object(train.get_rid());host.rig.arm.add_excluded_object(train_floor.get_rid())
	riding=true;exit_requested=false;_attach();_orient(train.global_transform,2.8);_latch();_event("boarded",{"station":visit_station});return true

func _attach() -> void:
	host.player.global_transform=Transform3D(train.global_basis,train.to_global(Vector3(-2.,.16,0.)));host.player.velocity=Vector3.ZERO;host.player.get_node("Visual").transform=Transform3D.IDENTITY
	host.exploration_avatar.transform=Transform3D.IDENTITY;host.exploration_avatar.set_activity("",0.)
	host.exploration_avatar._arm_to("Left",Vector3(-.20,1.73,-.12));host.exploration_avatar._arm_to("Right",Vector3(.20,1.73,-.12))

func _disembark() -> bool:
	if not riding or train_state!="doors_open" or docked_station<0:return false
	var row: Dictionary=stations[docked_station];var point: Vector3=row.wait
	if not _safe_indoor(point) or not host.player.relocate_interior_region(point,bounds):_tell("승강장이 막혀 있어 열차에서 기다립니다.");return false
	visit_station=docked_station;row.gate_open=true;_restore_ride(false);_orient(row.frame,3.4);_latch();_event("disembarked",{"station":visit_station});return true

func _restore_ride(external:=false) -> void:
	if not riding:return
	var player: CharacterBody3D=host.player;player.collision_layer=int(_ride_saved.layer);player.collision_mask=int(_ride_saved.mask)
	player.get_node("Visual").transform=_ride_saved.visual_transform;host.exploration_avatar.transform=_ride_saved.avatar_transform
	host.rig._query.exclude=_ride_saved.exclude;host.rig.arm.remove_excluded_object(train.get_rid());host.rig.arm.remove_excluded_object(train_floor.get_rid());host.rig.distance_max_m=float(_ride_saved.rig_max);host.rig.requested_distance=float(_ride_saved.rig_distance);host.rig.pitch=float(_ride_saved.rig_pitch)
	_release_physics=bool(_ride_saved.physics);_release_hold_controls=not external;_release_pending=true;_release_tick=Engine.get_physics_frames()+2
	if external:player.set_facility_control(false);player.set_physics_process(_release_physics)
	riding=false;exit_requested=false;_ride_saved.clear();host.rig.snap_to_target_pose()

func _finish_release() -> void:
	if not _release_pending or riding or Engine.get_physics_frames()<_release_tick:return
	var collider: CollisionShape3D=train.get_node("CollisionShape");var query:=PhysicsShapeQueryParameters3D.new();query.shape=collider.shape;query.transform=collider.global_transform;query.collision_mask=2;query.exclude=[train.get_rid()]
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query,4):
		if hit.collider==host.player:return
	train.remove_collision_exception_with(host.player);host.player.remove_collision_exception_with(train);_release_pending=false
	if _release_hold_controls:host.player.set_facility_control(false);host.player.set_physics_process(_release_physics);host.player.require_neutral_input()
	_release_hold_controls=false;_event("passenger_native_collision_restored")

func exit_visit() -> bool:
	if not active or riding or _paused():return false
	var row: Dictionary=stations[visit_station]
	if host.player.global_position.distance_to(row.exit)>1.8:return false
	var destination_row: Dictionary=_surface_destination(visit_station)
	if destination_row.is_empty():_tell("지상 출구가 막혀 있습니다. 역 안에서 기다리세요.");return false
	return leave_for_teleport(destination_row.point)

func leave_for_teleport(point: Vector3,roof_destination: Dictionary={}) -> bool:
	if not active or not point.is_finite():return false
	var target:=point
	if not roof_destination.is_empty():
		if not host._roof_destination_clear(roof_destination) or point.distance_to(roof_destination.get("pool_entry",Vector3.INF))>.001:return false
	else:
		var safe: Dictionary=_surface_safe(point)
		if safe.is_empty():return false
		target=safe.point
	if not host.player.end_interior(target):return false
	if riding:_restore_ride(true)
	active=false;underground.visible=false;host.starting_yaw=float(_visit_saved.get("starting_yaw",0.));host.hud_panel.visible=bool(_visit_saved.get("hud",true));host.building_names.set_physics_process(bool(_visit_saved.get("names",true)))
	host.rig.yaw=float(_visit_saved.get("yaw",0.));host.rig.pitch=float(_visit_saved.get("pitch",-.2));host.rig.requested_distance=float(_visit_saved.get("distance",4.));host.rig.snap_to_target_pose()
	host.player.require_neutral_input();_latch();_visit_saved.clear();_event("left_to_validated_exterior",{"point":target});return true

func return_to_world_spawn() -> bool:return leave_for_teleport(_world_spawn) if active else true

func cancel_ride_for_teleport() -> void:
	# Host calls only after applying a separately validated exterior destination.
	if not active:return
	if not bounds.has_point(host.player.global_position):leave_for_teleport(host.player.global_position)

func motion_policy() -> Dictionary:
	var authored: Dictionary={"maximum_speed_mps":float(design.motion.max_speed_mps),"acceleration_mps2":float(design.motion.acceleration_mps2),"braking_mps2":float(design.motion.braking_mps2)}
	return host.transport_motion_policy("subway",authored) if host.has_method("transport_motion_policy") else authored

func _doorway_occupied() -> bool:
	if docked_station<0:return false
	var query:=PhysicsShapeQueryParameters3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(3.,2.,.9);query.shape=shape;query.transform=stations[docked_station].frame*Transform3D(Basis.IDENTITY,Vector3(0.,1.05,1.7));query.collision_mask=2|4;query.exclude=[train.get_rid(),train_floor.get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _update_doors() -> void:
	for index: int in range(_train_doors.size()):
		var leaf: Node3D=_train_doors[index];var side: float=float(leaf.get_meta("side"));leaf.position=Vector3(side*(.66+door_fraction*1.35),1.45,1.43)
	for row: Dictionary in stations:
		var opening: float=door_fraction if int(row.index)==docked_station else 0.
		for leaf: Dictionary in row.screen_leaves:leaf.node.position=Vector3(float(leaf.side)*(.69+opening*1.45),1.48,1.75)
		for leaf: Dictionary in row.gate_leaves:leaf.node.position=Vector3(float(leaf.side)*(.25+(1. if row.gate_open else 0.)),3.75,27.2)

func _set_state(state: String) -> void:train_state=state;state_elapsed=0.;_event("train_"+state,{"docked":docked_station,"target":target_station})

func _physics_process(delta: float) -> void:
	if not loaded:return
	_finish_release()
	if _paused():
		if riding:_attach()
		return
	state_elapsed+=delta;blocked_reason=""
	if train_state=="doors_open":
		door_fraction=1.
		if riding and exit_requested:_disembark()
		if state_elapsed>=float(design.motion.dwell_seconds) and not _doorway_occupied():_set_state("closing")
	elif train_state=="closing":
		if _doorway_occupied():_set_state("opening")
		else:
			door_fraction=maxf(0.,1.-state_elapsed/float(design.motion.door_seconds))
			if door_fraction<=0.:
				target_station=1-docked_station;direction=1. if target_station==1 else -1.;docked_station=-1;_set_state("moving")
	elif train_state=="moving":
		var policy: Dictionary=motion_policy();var remaining: float=absf(float(stations[target_station].route_station_m)-station_m)
		var brake: float=maxf(.1,float(policy.get("braking_mps2",2.6)));var maximum: float=maxf(.5,float(policy.get("maximum_speed_mps",12.)));var acceleration: float=maxf(.1,float(policy.get("acceleration_mps2",2.)))
		var desired: float=minf(maximum,sqrt(2.*brake*remaining));speed_mps=move_toward(speed_mps,desired,(acceleration if desired>speed_mps else brake)*delta)
		var step: float=minf(remaining,speed_mps*delta);var next_station: float=station_m+direction*step;var pose: Transform3D=_frame(next_station)
		var motion: Vector3=pose.origin-train.global_position;train.global_basis=pose.basis
		var collision: KinematicCollision3D=train.move_and_collide(motion,false,.001)
		if collision==null:station_m=next_station
		else:speed_mps=0.;blocked_reason="native_train_obstacle";_event("train_obstacle",{"collider":String(collision.get_collider().name)})
		if remaining<=.003 or absf(float(stations[target_station].route_station_m)-station_m)<=.003:
			docked_station=target_station;speed_mps=0.;completed_legs+=1;_set_state("opening")
	elif train_state=="opening":
		door_fraction=minf(1.,state_elapsed/float(design.motion.door_seconds))
		if door_fraction>=1.:_set_state("doors_open")
	_update_doors()
	if riding:_attach()

func set_running(enabled: bool) -> void:running=enabled

func _eta(index: int) -> float:
	if docked_station==index:return 0.
	var maximum: float=maxf(1.,float(motion_policy().get("maximum_speed_mps",12.)))
	var distance: float=absf(float(stations[index].route_station_m)-station_m)
	if target_station!=index:distance=route_length_m+absf(float(stations[target_station].route_station_m)-station_m)
	return distance/(maximum*.75)+float(design.motion.door_seconds)*2.+(float(design.motion.dwell_seconds) if target_station!=index else 0.)

func prompt_text() -> String:
	if not loaded or host.menu.visible:return ""
	if riding:return "E · 하차" if train_state=="doors_open" else "E · 다음 역 하차 예약 · 다음 "+String(stations[target_station].title)
	if active:
		var connected_hint: String=host.underground_interaction_hint() if host.has_method("underground_interaction_hint") else ""
		if not connected_hint.is_empty():return connected_hint
		var row: Dictionary=stations[visit_station];var point: Vector3=host.player.global_position
		if Time.get_ticks_msec()<_notice_until:return _notice
		if point.distance_to(row.exit)<1.8:return "E · "+String(row.title)+"역 "+String(row.entrance_ref)+"번 출구로 나가기"
		if point.distance_to(row.gate)<2.1:return "E · 교통카드 태그 · 게임 개찰"
		if point.distance_to(row.wait)<2.1:return "E · 열린 열차 타기" if docked_station==visit_station and train_state=="doors_open" else "열차 약 %d초 · 노란 안전선 뒤 대기"%int(ceil(_eta(visit_station)))
		return "개찰구 E → 계단 → 승강장 · 열차/지상 출구에서 E"
	var index: int=_entry_candidate()
	return "E · "+String(stations[index].title)+"역 지하철 체험" if index>=0 else ""

func _tell(message: String) -> void:_notice=message;_notice_until=Time.get_ticks_msec()+3200

func _process(_delta: float) -> void:
	if not loaded:return
	for row: Dictionary in stations:
		row.departure_label.text="GAME S-01 · "+String(row.title)+"\n"+("문 열림 · E 승차" if docked_station==int(row.index) and train_state=="doors_open" else "열차 약 %d초"%int(ceil(_eta(int(row.index)))))
	_status_panel.visible=active and not host.menu.visible
	if not active:return
	host.hud_panel.visible=false;host.building_names.panel.visible=false;host.building_names.crosshair.visible=false
	for marker: Dictionary in host.building_names.markers:marker.node.visible=false
	var next_name: String=String(stations[target_station].title)
	_status.text="%s · %s\n%s\n개찰구 E · 계단으로 승강장 · 뒤쪽 게임 지하 연결통로"%[String(design.service_title),"다음 "+next_name if riding else String(stations[visit_station].title),prompt_text()]
	var view: Vector2=host.get_viewport().get_visible_rect().size;_status_panel.custom_minimum_size.x=minf(560.,maxf(1.,view.x-32.));_status_panel.size=Vector2(_status_panel.custom_minimum_size.x,_status_panel.get_combined_minimum_size().y);_status_panel.position=Vector2(16.,16.)

func snapshot() -> Dictionary:
	var rows: Array=[]
	for row: Dictionary in stations:rows.append({"id":row.id,"title":row.title,"source_entrance_id":row.entrance.osm_node_id,"source_anchor":row.anchor,"source_station":row.source_station,"gate_open":row.gate_open,"spawn":row.spawn,"exit":row.exit,"gate":row.gate,"wait":row.wait,"frame":row.frame})
	return {"loaded":loaded,"error":load_error,"active":active,"riding":riding,"state":train_state,"station_m":station_m,"route_length_m":route_length_m,"speed_mps":speed_mps,"door_fraction":door_fraction,"docked_station":docked_station,"target_station":target_station,"visit_station":visit_station,"completed_legs":completed_legs,"release_pending":_release_pending,"blocked_reason":blocked_reason,"train_position":train.global_position if is_instance_valid(train) else Vector3.ZERO,"motion_policy":motion_policy() if loaded else {},"stations":rows,"events":events.duplicate(true),"source_geometry_changed":false,"scope":"Retained City Hall5/Euljiro1-1 entrance identities; authored bounded underground game stations and continuously moving two-terminal train on a 338m regional source-derived Line2 segment. No real platform center, complete station, timetable, fare or actual full interstation distance claim."}

func connected_outdoor_context() -> Dictionary:return _visit_saved.duplicate(true)

func release_to_connected_building() -> Dictionary:
	# The caller already relocated to a validated building region. It keeps the
	# original player._outdoor_recovery; no exterior reset or teleport occurs.
	var context: Dictionary=connected_outdoor_context()
	active=false;underground.visible=false;_visit_saved.clear();_latch();_event("left_to_game_B1_connection")
	return context

func adopt_from_connected_building(context: Dictionary,index: int) -> void:
	_visit_saved=context.duplicate(true);active=true;visit_station=index;underground.visible=true
	stations[index].gate_open=false;host.starting_yaw=0.;host.building_names.set_physics_process(false)
	host.player.require_neutral_input();_orient(stations[index].frame,3.5);_latch();_update_doors();_event("arrived_from_game_B1_connection",{"station":index})
