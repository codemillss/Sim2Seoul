extends RefCounted
## Source-sized game interiors. Furniture and room programmes are authored,
## not a survey of the named tenants or a claim about real public access.
const LIBRARY_ID := "osm:relation:10757525:building"
const CITYHALL_ID := "osm:way:198561926:building"
var room: Node3D
var profile_id := "office"
var level_profiles: Array[Dictionary] = []
var detail_counts: Dictionary = {}
var features: Array[String] = []
var placements: Array[Dictionary] = []
var protected_zones: Array[AABB] = []
var labels: Array[Label3D] = []
var _round_batches: Dictionary = {}
var _round_meshes: Dictionary = {}
var _level := 0
var _seed := 0
var _rejected := 0
var facility_kit: RefCounted

func setup(owner_room: Node3D) -> void:
	room = owner_room
	_seed = absi(String(room.spec.get("id","")).hash())
	profile_id = _classify()
	var colors := {
		"oak":Color(.54,.37,.22),"oak_light":Color(.73,.57,.37),"walnut":Color(.27,.17,.12),
		"stone":Color(.71,.72,.69),"paper":Color(.94,.92,.84),"ink":Color(.08,.13,.17),
		"screen":Color(.12,.30,.39),"seoul_teal":Color(.06,.38,.40),"brass":Color(.65,.48,.23),
		"linen":Color(.69,.65,.57),"navy":Color(.16,.22,.31),"sage":Color(.33,.43,.33),
		"leaf":Color(.17,.32,.19),"leaf_light":Color(.29,.44,.22),"flower":Color(.65,.21,.25),
		"cushion_blue":Color(.13,.43,.66),"cushion_green":Color(.40,.60,.24),
		"cushion_yellow":Color(.90,.72,.18),"cushion_orange":Color(.87,.39,.15),"terracotta":Color(.55,.28,.18)}
	for key: String in colors:
		var material := StandardMaterial3D.new()
		material.albedo_color = colors[key]
		material.roughness = .78 if key!="brass" else .35
		material.metallic = .65 if key=="brass" else 0.0
		room._materials[key] = material
		if key in ["oak","oak_light","walnut","linen","navy","sage"]:
			var surface := ShaderMaterial.new()
			surface.shader = preload("res://scripts/interior_surface.gdshader")
			surface.set_shader_parameter("base_color",colors[key])
			surface.set_shader_parameter("surface_kind",1 if key in ["oak","oak_light","walnut"] else 3)
			room._materials[key] = surface
	var floor_color: Color = {"library":Color(.72,.68,.57),"civic":Color(.34,.38,.39),"office":Color(.66,.68,.67),"hotel":Color(.47,.42,.35),"gallery":Color(.72,.71,.67),"chapel":Color(.55,.49,.38),"residential":Color(.64,.61,.55),"bank":Color(.66,.69,.67)}.get(profile_id,Color(.66,.68,.67))
	room._materials["floor"].set_shader_parameter("base_color",floor_color)
	var glazing := StandardMaterial3D.new()
	glazing.albedo_color = Color(.46,.66,.71,.24)
	glazing.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glazing.roughness = .14
	glazing.cull_mode = BaseMaterial3D.CULL_DISABLED
	room._materials["clear_glass"] = glazing
	# Each floor uses these same XZ reservations. They include the complete stair
	# approach and front cross-corridor, not just point samples at the spawn.
	protected_zones = [
		AABB(Vector3(-1.55,-.2,-room.depth*.5),Vector3(3.40,room.floor_height+.4,room.depth)),
		AABB(Vector3(-room.width*.5,-.2,room.depth*.5-2.95),Vector3(room.width,room.floor_height+.4,2.95)),
		AABB(Vector3(room.stair_left-.20,-.2,room.stair_back-.15),Vector3(room.stair_width*2.0+.95,room.floor_height+.4,room.stair_front-room.stair_back+2.65))]
	# Shared curved meshes keep pots, lamps and upholstery from being all boxes.
	var cylinder := CylinderMesh.new();cylinder.top_radius=.5;cylinder.bottom_radius=.5;cylinder.height=1.0;cylinder.radial_segments=12
	_round_meshes["cylinder"] = cylinder
	var pot := CylinderMesh.new();pot.top_radius=.5;pot.bottom_radius=.36;pot.height=1.0;pot.radial_segments=12
	_round_meshes["pot"] = pot
	var foliage := SphereMesh.new();foliage.radius=.5;foliage.height=1.0;foliage.radial_segments=10;foliage.rings=6
	_round_meshes["foliage"] = foliage
	var shade := CylinderMesh.new();shade.top_radius=.30;shade.bottom_radius=.5;shade.height=1.0;shade.radial_segments=12
	_round_meshes["shade"] = shade
	facility_kit=preload("res://scripts/interior_facility_kit.gd").new()
	facility_kit.setup(self)

func _classify() -> String:
	var id := String(room.spec.get("id",""))
	var title := String(room.spec.get("title","")).to_lower()
	if id==LIBRARY_ID or room.spec.get("kind")=="library":return "library"
	if id==CITYHALL_ID or "시청" in title:return "civic"
	if "호텔" in title or "hotel" in title or "프레이저" in title or "westin" in title:return "hotel"
	if "미술관" in title or "박물관" in title or "아트센터" in title or "전시" in title:return "gallery"
	if "교회" in title or "성공회" in title or "성당" in title:return "chapel"
	if "아파트" in title or "residence" in title:return "residential"
	if "은행" in title:return "bank"
	return "office"

func _programme(level: int) -> Dictionary:
	if facility_kit:
		var facility_programme: Dictionary=facility_kit.programme(profile_id,level,_seed)
		if not facility_programme.is_empty():return facility_programme
	var index := level%3
	match profile_id:
		"library":
			var titles := ["일반자료 · 안내", "자료열람 · 생각마루", "서울자료 · 디지털열람", "기록과 전시 · 휴게"]
			return {"profile_id":["library_welcome","library_reading","library_digital","library_archive"][mini(level,3)],"title":titles[mini(level,3)]}
		"civic":
			return {"profile_id":"civic_welcome" if level==0 else ["civic_service","civic_meeting","civic_public_lounge"][index],"title":"시민안내 · 공공 로비" if level==0 else ["민원상담 · 대기","회의 · 협업","공공 라운지 · 전시"][index]}
		"hotel":
			return {"profile_id":"hotel_lobby" if level==0 else "hotel_lounge" if level==1 else "hotel_guest","title":"프런트 · 로비 라운지" if level==0 else "라운지 · 아침식사" if level==1 else "객실 · 공용 복도"}
		"gallery":return {"profile_id":"gallery_foyer" if level==0 else "gallery_exhibition","title":"전시안내 · 아트 라운지" if level==0 else "기획전시 · 감상"}
		"chapel":return {"profile_id":"chapel_hall" if level==0 else "chapel_community","title":"예배 · 안내" if level==0 else "모임 · 교육"}
		"residential":return {"profile_id":"residential_lobby" if level==0 else "residential_corridor","title":"공동현관 · 우편" if level==0 else "주거층 · 공용 복도"}
		"bank":return {"profile_id":"bank_service" if level==0 else "bank_consulting","title":"금융창구 · 대기" if level==0 else "상담 · 업무"}
	var office_index := (level+_seed)%3
	return {"profile_id":"office_lobby" if level==0 else ["office_work","office_meeting","office_lounge"][office_index],"title":"리셉션 · 입주사 안내" if level==0 else ["업무 · 집중","회의 · 협업","휴게 · 공용 라운지"][office_index]}

func build_level(level: int) -> void:
	_level = level
	var programme := _programme(level)
	programme["level"] = level
	programme["layout_basis"] = "game_reconstruction"
	programme["features"] = []
	level_profiles.append(programme)
	_architecture(level)
	if facility_kit.build(String(programme.profile_id)):return
	match profile_id:
		"library":_library(level)
		"civic":_civic(level)
		"hotel":_hotel(level)
		"gallery":_gallery(level)
		"chapel":_chapel(level)
		"residential":_residential(level)
		"bank":_bank(level)
		_:_office(level)
	facility_kit.decorate(profile_id,level)

func _feature(name: String) -> void:
	if not features.has(name):features.append(name)
	var list: Array = level_profiles[_level].features
	if not list.has(name):list.append(name)

func _count(name: String) -> void:detail_counts[name] = int(detail_counts.get(name,0))+1

func _safe(point: Vector3, size: Vector3) -> bool:
	var footprint := AABB(Vector3(point.x-size.x*.5,-.1,point.z-size.z*.5),Vector3(size.x,room.floor_height+.2,size.z))
	if footprint.position.x<-room.width*.5+.25 or footprint.end.x>room.width*.5-.25:return false
	if footprint.position.z<-room.depth*.5+.25 or footprint.end.z>room.depth*.5-.25:return false
	for zone in protected_zones:
		if footprint.grow(.18).intersects(zone):return false
	return true

func _box(title: String, size: Vector3, point: Vector3, material: String, solid := false, basis := Basis.IDENTITY) -> bool:
	# Rotation-aware footprint: only decor may ignore the clear circulation zone.
	var extent := Vector3(absf(basis.x.x)*size.x+absf(basis.y.x)*size.y+absf(basis.z.x)*size.z,size.y,absf(basis.x.z)*size.x+absf(basis.y.z)*size.y+absf(basis.z.z)*size.z)
	if solid and not _safe(point,extent):
		_rejected += 1
		return false
	var at: Vector3 = point+Vector3.UP*(_level*room.floor_height)
	var body: StaticBody3D = room._box("Detail_"+title,size,at,material,solid,basis)
	if body:
		body.set_meta("detail_level",_level)
		body.set_meta("detail_profile",profile_id)
	placements.append({"title":"Detail_"+title,"position":at,"size":size,"footprint_size":extent,"basis":basis,"level":_level,"solid":solid,"mesh_kind":"box"})
	_count(title)
	return true

func _round(title: String, kind: String, size: Vector3, point: Vector3, material: String, basis := Basis.IDENTITY) -> void:
	var key := kind+"/"+material
	if not _round_batches.has(key):_round_batches[key] = []
	_round_batches[key].append(Transform3D(basis*Basis.from_scale(size),point+Vector3.UP*(_level*room.floor_height)))
	placements.append({"title":"Detail_"+title,"position":point+Vector3.UP*(_level*room.floor_height),"size":size,"basis":basis,"level":_level,"solid":false,"mesh_kind":kind})
	_count(title)

func _label(title: String, text: String, point: Vector3, font_size := 25, front := true, turn := 0.0) -> Label3D:
	var label: Label3D = room._sign("Detail_"+title,text,point+Vector3.UP*(_level*room.floor_height),font_size,front)
	label.pixel_size = .008
	label.outline_size = 2
	label.modulate = Color(.12,.19,.20)
	label.rotation.y += turn
	label.set_meta("detail_level",_level)
	labels.append(label)
	_count(title)
	return label

func _right_x(inset := 1.6) -> float:return maxf(2.8,room.width*.5-inset)
func _left_x(inset := 1.6) -> float:return minf(-2.9,-room.width*.5+inset)
func _core_right(inset := 2.0) -> float:return minf(5.6,_right_x(inset))
func _core_left(inset := 2.0) -> float:return maxf(-5.6,_left_x(inset))
func _front(offset := 6.0) -> float:return room.depth*.5-offset
func _station_z(index: int, spacing := 4.6) -> float:return _front(6.7+index*spacing)

func _architecture(level: int) -> void:
	var y: float = room.floor_height
	var title := String(level_profiles[level].title)
	# Low skirtings, measured panel joints and ceiling ribs break the blank shell.
	_box("Skirting",Vector3(.05,.14,room.depth-.8),Vector3(room.width*.5-.04,.07,0),"walnut")
	_box("Skirting",Vector3(.05,.14,room.depth-.8),Vector3(-room.width*.5+.04,.07,0),"walnut")
	var panel_count := mini(18,maxi(3,int(room.depth/2.4)))
	for i in range(panel_count):
		var z := lerpf(-room.depth*.5+.7,room.depth*.5-.7,float(i)/float(panel_count-1))
		_box("WallPanelJoint",Vector3(.012,2.9,.015),Vector3(room.width*.5-.025,1.5,z),"stone")
	for index in range(mini(9,maxi(2,int(room.depth/7.0)))):
		var z := lerpf(-room.depth*.5+2.0,room.depth*.5-2.0,float(index)/float(maxi(1,mini(9,maxi(2,int(room.depth/7.0)))-1)))
		_box("CeilingRib",Vector3(room.width-.4,.12,.16),Vector3(0,y-.12,z),"paper")
		for side in [-1.0,1.0]:
			_box("LinearCeilingLight",Vector3(.18,.04,2.0),Vector3(side*minf(room.width*.28,5.0),y-.19,z),"light")
	# The eye-level entry board says it is a game programme rather than a survey.
	var board_x := _right_x(1.65) if profile_id=="library" else _core_right(1.65)
	var board_z := _front(4.0)
	if _box("ProgrammeBoard",Vector3(2.15,2.30,.14),Vector3(board_x,1.32,board_z),"oak",true):
		_box("ProgrammeBoardFace",Vector3(1.98,2.12,.03),Vector3(board_x,1.32,board_z+.09),"paper")
		var programme_label := _label("FloorProgramme","%dF  시설 안내\n\n%s\n\n계단 · 승강기  ←\n출입구  ↓"%[level+1,title],Vector3(board_x,1.45,board_z+.12),24)
		_wrap(programme_label,1.82)
	# A side wall plaque is readable close to the arrival without spanning the path.
	_label("LevelArrow","%d층  %s   →"%[level+1,title],Vector3(room.width*.5-.15,2.25,_front(7.0)),25,true,-PI*.5)
	if level==0:_plant(Vector3(_right_x(.9),0,_front(3.8)),.75)
	if profile_id in ["office","hotel","gallery","residential","bank"]:_arrival_core()

func _wrap(label: Label3D, metres: float) -> void:
	label.width = metres/label.pixel_size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _arrival_core() -> void:
	# The source plate stays intact. These human-scale fit-out zones concentrate
	# the lobby beside the arrival, instead of pushing every object to a far wall.
	var width := minf(6.8,(room.width*.5-.45)-2.05)
	var length := minf(14.0,room.depth-7.0)
	if width>2.3:
		_box("LobbyFloorInset",Vector3(width,.008,length),Vector3(2.05+width*.5,.006,_front(3.3+length*.5)),"walnut" if profile_id=="hotel" else "stone")
	if room.width>=22.0:
		_box("LoungeFloorInset",Vector3(6.8,.009,8.8),Vector3(-5.6,.007,_front(8.2)),"linen")
		for side in [-1.0,1.0]:
			var column := Vector3(side*8.2,room.floor_height*.5,_front(7.6))
			_box("LobbyColumn",Vector3(.30,room.floor_height-.12,.30),column,"paper",true)
	# A low suspended fascia makes the change of room programme visible at
	# eye level; its lower edge remains above the standing capsule.
	var fascia_y := minf(room.floor_height-.45,2.75)
	_box("LobbyWayfindingFascia",Vector3(4.8,.26,.10),Vector3(0,fascia_y,_front(5.3)),"walnut" if profile_id=="hotel" else "ink")
	var sign := _label("LobbyDirection",("프런트  →    ←  라운지" if profile_id=="hotel" else "리셉션  →    ←  공용공간") if _level==0 else String(level_profiles[_level].title),Vector3(0,fascia_y,_front(5.23)),24)
	sign.modulate=Color(.94,.94,.87);sign.outline_size=0
	_wrap(sign,4.5)
	_feature("human_scale_arrival_core")

func _feature_wall(point: Vector3, width := 3.8, material := "oak") -> void:
	var height := minf(2.65,room.floor_height-.25)
	if not _box("LobbyFeatureWall",Vector3(width,height,.16),point+Vector3.UP*(height*.5),material,true):return
	for index in range(int(width/.20)):
		_box("FeatureWallLouver",Vector3(.035,height-.12,.06),point+Vector3(-width*.5+.11+index*.20,height*.5,.12),"brass" if profile_id=="hotel" else "oak_light")
	_feature("reception_feature_wall")

func _glass_room(point: Vector3, title: String, width := 4.5, length := 5.2) -> void:
	var half := width*.5
	var height := minf(2.5,room.floor_height-.30)
	var z_back := point.z-length*.5
	var z_front := point.z+length*.5
	# Front has a real 1.1m opening. Inner side walls remain outside the complete
	# central reserve, so the corridor never depends on stepping through glass.
	if not _safe(point,Vector3(width,1,length)):return
	for side in [-1.0,1.0]:
		_box("GlassRoomSide",Vector3(.075,height,length),Vector3(point.x+side*half,height*.5,point.z),"clear_glass",true)
		for z in [z_back,z_front]:_box("GlassRoomUpright",Vector3(.055,height,.055),Vector3(point.x+side*half,height*.5,z),"ink")
	_box("GlassRoomRear",Vector3(width,height,.075),Vector3(point.x,height*.5,z_back),"clear_glass",true)
	var leaf := (width-1.10)*.5
	for side in [-1.0,1.0]:
		_box("GlassRoomFront",Vector3(leaf,height,.075),Vector3(point.x+side*(.55+leaf*.5),height*.5,z_front),"clear_glass",true)
		_box("GlassDoorJamb",Vector3(.055,height,.09),Vector3(point.x+side*.55,height*.5,z_front),"ink")
	_box("GlassRoomLintel",Vector3(width,.08,.10),Vector3(point.x,height,z_front),"ink")
	var label := _label("GlassRoomTitle",title,Vector3(point.x,height-.25,z_front+.07),24)
	_wrap(label,width-.30)
	_feature("glass_partitioned_rooms")

func _desk(point: Vector3, label: String, material := "oak", width := 2.3) -> bool:
	if not _box(label,Vector3(width,.72,1.0),point+Vector3(0,.36,0),material,true):return false
	_box(label+"Top",Vector3(width+.08,.08,1.08),point+Vector3(0,.78,0),"oak_light" if material=="oak" else "stone")
	for x in [-width*.5+.2,width*.5-.2]:_box("DeskFoot",Vector3(.08,.10,.82),point+Vector3(x,.05,0),"dark")
	return true

func _chair(point: Vector3, material := "sage", back := true, back_side := 1.0) -> void:
	if not _box("ChairSeat",Vector3(.54,.12,.54),point+Vector3(0,.46,0),material,true):return
	for x in [-.20,.20]:
		for z in [-.20,.20]:_box("ChairLeg",Vector3(.045,.42,.045),point+Vector3(x,.21,z),"walnut")
	if back:_box("ChairBack",Vector3(.54,.48,.075),point+Vector3(0,.76,back_side*.245),material)

func _plant(point: Vector3, scale_factor := 1.0) -> void:
	if not _safe(point,Vector3(.70*scale_factor,1,.70*scale_factor)):return
	_round("PlantPot","pot",Vector3(.48,.46,.48)*scale_factor,point+Vector3(0,.23,0)*scale_factor,"stone")
	_box("PlantStem",Vector3(.045,.82,.045)*scale_factor,point+Vector3(0,.72,0)*scale_factor,"walnut")
	for index in range(3):
		var p := Vector3(sin(index*2.1)*.18,1.00+index*.17,cos(index*2.1)*.14)*scale_factor
		_round("PlantFoliage","foliage",Vector3(.54,.46,.45)*scale_factor,point+p,"leaf" if index%2==0 else "leaf_light")
	_feature("potted_plants")

func _reception(point: Vector3, prefix: String, wording: String, material := "oak") -> void:
	if not _desk(point,prefix+"Reception",material,2.7):return
	_box("ReceptionLoweredCounter",Vector3(.66,.05,.34),point+Vector3(.94,.65,.63),material)
	_label(prefix+"CounterSign",wording,point+Vector3(0,.46,.512),27)
	_box("ReceptionMonitor",Vector3(.62,.38,.055),point+Vector3(.30,1.03,-.23),"ink")
	_box("ReceptionMonitorStand",Vector3(.08,.18,.10),point+Vector3(.30,.87,-.23),"steel")
	_paper(point+Vector3(-.72,.84,.05))
	_feature("reception")

func _paper(point: Vector3) -> void:
	_box("PaperNotice",Vector3(.26,.012,.34),point,"paper")
	for row in range(4):_box("PrintedLine",Vector3(.18,.003,.007),point+Vector3(0,.008,-.09+row*.045),"stone")

func _book(point: Vector3, color_index: int) -> void:
	var color: String = ["book_red","book_green","book_blue","book_cream"][posmod(color_index,4)]
	_box("ClosedBook",Vector3(.30,.055,.38),point,color)
	_box("BookPages",Vector3(.27,.035,.35),point+Vector3(.005,.006,.006),"paper")

func _shelf(point: Vector3, serial: int, full_height := false) -> void:
	var height := 2.75 if full_height else 2.05
	var bays := 5 if full_height else 4
	if not _box("LibraryShelf",Vector3(.48,height,2.35),point+Vector3(0,height*.5,0),"oak",true):return
	# Recessed dark pockets leave visible rails, upright dividers and varied books.
	_box("ShelfInner",Vector3(.035,height-.18,2.15),point+Vector3(-.26,height*.5,0),"walnut")
	for row in range(bays):
		var row_y := .10+row*(height-.13)/float(bays)
		_box("ShelfRail",Vector3(.52,.055,2.35),point+Vector3(-.02,row_y,0),"oak_light")
		for book in range(15):
			var h := .24+float(posmod(book*7+row*5+serial,6))*.027
			var z := -.99+book*.14
			var color: String = ["book_red","book_green","book_blue","book_cream"][posmod(book+row+serial,4)]
			_box("BookSpine",Vector3(.07,h,.075+float(book%3)*.015),point+Vector3(-.29,row_y+h*.5+.035,z),color)
			_box("BookSpineBand",Vector3(.006,.025,.052),point+Vector3(-.33,row_y+.09,z),"paper")
	_label("ShelfNumber","%02d  %s"%[serial+1,["문학","사회과학","서울자료","인문예술"][posmod(serial+_level,4)]],point+Vector3(-.33,height-.12,0),18,true,-PI*.5)
	_feature("wooden_bookshelves")
	_feature("varied_book_spines")

func _reading_desk(point: Vector3, digital := false) -> void:
	# A usable desk needs knee space, not a floor-to-top cabinet collider.
	if not _box("ReadingDeskTop",Vector3(2.08,.08,1.08),point+Vector3(0,.78,0),"oak_light",true):return
	for x: float in [-.87,.87]:
		for z: float in [-.38,.38]:_box("ReadingDeskLeg",Vector3(.075,.74,.075),point+Vector3(x,.37,z),"oak",true)
	var seat:=point+Vector3(0,0,1.05)
	# Like the existing stationary-cycle saddle, this seated display keeps the
	# original upright capsule on the real floor. The chair itself is visual.
	_box("ReadingChairSeat",Vector3(.54,.12,.54),seat+Vector3.UP*.46,"sage")
	_box("ReadingChairBack",Vector3(.54,.48,.075),seat+Vector3(0,.76,.245),"sage")
	for x: float in [-.20,.20]:
		for z: float in [-.20,.20]:_box("ReadingChairLeg",Vector3(.045,.42,.045),seat+Vector3(x,.21,z),"walnut")
	facility_kit.register_study_desk(point,seat,digital)
	_box("DeskDivider",Vector3(2.04,.38,.04),point+Vector3(0,1.01,-.50),"oak_light")
	for side in [-1.0,1.0]:
		var lamp := point+Vector3(side*.65,0,-.25)
		_round("ReadingLampBase","cylinder",Vector3(.20,.025,.20),lamp+Vector3.UP*.84,"brass")
		_box("ReadingLampStem",Vector3(.025,.45,.025),lamp+Vector3.UP*1.06,"brass")
		_box("ReadingLampShade",Vector3(.43,.07,.15),lamp+Vector3.UP*1.30,"sage")
		_box("ReadingLampGlow",Vector3(.36,.015,.10),lamp+Vector3.UP*1.255,"light")
	if digital:
		_box("LaptopKeyboard",Vector3(.48,.025,.30),point+Vector3(-.50,.84,.10),"steel")
		_box("LaptopScreen",Vector3(.48,.31,.035),point+Vector3(-.50,1.00,-.055),"ink")
		_box("LaptopDisplay",Vector3(.42,.25,.008),point+Vector3(-.50,1.00,-.030),"screen")
	else:
		_box("StudyOpenBookCover",Vector3(.52,.025,.35),point+Vector3(0,.835,.10),"book_blue")
		for side: float in [-1.,1.]:_box("StudyOpenBookPage",Vector3(.245,.012,.33),point+Vector3(side*.128,.856,.10),"paper",false,Basis(Vector3.FORWARD,side*.045))
		for row: int in range(5):_box("StudyPrintedText",Vector3(.19,.003,.006),point+Vector3(-.13,.865,-.02+row*.05),"stone")
	_paper(point+Vector3(.18,.84,.34))
	_feature("individual_reading_lamps")

func _library(level: int) -> void:
	var x := _right_x(.65)
	var shelves := mini(12,maxi(2,int((room.depth-14.0)/3.0)))
	for index in range(shelves):_shelf(Vector3(x,0,_front(11.0+index*3.05)),index,level==1)
	if level==0:
		_reception(Vector3(_left_x(1.8),0,_front(6.6)),"Library","종합안내 · 대출 / 반납")
		var machine := Vector3(_right_x(2.0),0,_front(7.0))
		if _box("ReturnMachine",Vector3(.95,1.25,.62),machine+Vector3.UP*.625,"paper",true):
			_box("ReturnSlot",Vector3(.64,.12,.03),machine+Vector3(0,.76,.325),"ink")
			_box("ReturnDisplay",Vector3(.40,.24,.03),machine+Vector3(0,1.04,.325),"screen")
			_label("ReturnMachineLabel","도서 반납",machine+Vector3(0,1.42,.33),23)
			_feature("book_return_machine")
		_label("LibraryGuide","서울도서관\n왼쪽 열람석 · E 앉아서 공부\n다시 E · 일어나기",Vector3(_left_x(1.8),2.05,_front(6.95)),26)
	elif level==1:
		_reading_terrace(Vector3(_left_x(1.8),0,_front(8.0)))
	elif level==3:
		_display_case(Vector3(_left_x(1.9),0,_front(7.2)),"서울의 기록",0)
	for index in range(mini(6,maxi(2,int((room.depth-15)/6.0)))):
		var z := _front(13.0+index*6.0)
		if z>room.stair_front+3.0:_reading_desk(Vector3(_left_x(1.9),0,z),level==2)
	_feature("library_floor_programmes")
	# The circular clock is deliberately readable beside the entrance directory.
	_round("WallClock","cylinder",Vector3(.48,.035,.48),Vector3(_right_x(1.6),2.85,_front(4.02)),"paper",Basis(Vector3.RIGHT,PI*.5))
	_label("ClockFace","12\n9     3\n6",Vector3(_right_x(1.6),2.86,_front(3.97)),15)

func _reading_terrace(point: Vector3) -> void:
	for step in range(3):
		var center := point+Vector3(0,.10+step*.16,-step*.60)
		if not _box("ReadingTerrace",Vector3(2.4,.20+step*.32,.65),Vector3(center.x,(.20+step*.32)*.5,center.z),"oak",true):continue
		for side in [-1.0,1.0]:
			var color: String = ["cushion_blue","cushion_green","cushion_yellow","cushion_orange"][posmod(step+(1 if side>0 else 0),4)]
			_round("ColorCushion","cylinder",Vector3(.48,.085,.48),Vector3(center.x+side*.62,.24+step*.32,center.z),color)
	_label("ThinkingMaru","생각마루\n책과 함께 쉬어 가세요",point+Vector3(0,1.65,-1.58),26)
	_feature("stepped_reading_terrace")
	_feature("coloured_round_cushions")

func _queue_seat(point: Vector3) -> void:
	if not _box("QueueSeat",Vector3(1.75,.12,.55),point+Vector3.UP*.46,"navy",true):return
	_box("QueueSeatBack",Vector3(1.75,.50,.10),point+Vector3(0,.78,-.23),"navy")
	for side in [-1.0,1.0]:
		_box("QueueSeatArm",Vector3(.06,.22,.50),point+Vector3(side*.80,.67,0),"steel")
		_box("QueueSeatLeg",Vector3(.07,.42,.36),point+Vector3(side*.62,.22,0),"steel")

func _garden(point: Vector3, size := Vector2(4.0,2.7)) -> void:
	if not _box("VerticalGarden",Vector3(size.x,size.y,.26),point+Vector3.UP*(size.y*.5),"leaf",true):return
	var columns := int(size.x/.35)
	for row in range(7):
		for column in range(columns):
			var phase := float(row*19+column*7+_seed%37)
			var p := point+Vector3(-size.x*.5+.17+column*.35+sin(phase)*.06,.20+row*.34+cos(phase*1.7)*.065,.16+sin(phase*.7)*.035)
			var orientation := Basis(Vector3.FORWARD,sin(phase*1.3)*.65)
			_round("GardenFoliage","foliage",Vector3(.43+sin(phase)*.07,.22+cos(phase)*.035,.17),p,"leaf_light" if (row+column)%3==0 else "leaf",orientation)
			_round("GardenLeafCluster","foliage",Vector3(.20,.32,.12),p+Vector3(.10,.08,.03),"leaf",Basis(Vector3.FORWARD,cos(phase)*.85))
			if (row*11+column+_seed)%17==0:_round("GardenFlower","foliage",Vector3(.12,.12,.08),p+Vector3(0,0,.13),"flower")
	_feature("vertical_garden")
	# White diagonal frames echo the new City Hall lobby at one-storey scale.
	for side in [-1.0,1.0]:
		var basis := Basis(Vector3.FORWARD,side*.24)
		_box("CivicDiagonalFrame",Vector3(.13,size.y+.30,.15),point+Vector3(side*(size.x*.5+.15),size.y*.5,.24),"paper",false,basis)

func _civic(level: int) -> void:
	var x := minf(_right_x(2.4),6.0)
	var left := maxf(_left_x(2.2),-6.0)
	var z := _front(6.5)
	if level==0:
		_reception(Vector3(x,0,z),"Civic","시민안내 · 종합민원","stone")
		_garden(Vector3(x,0,z-1.4),Vector2(4.2,2.8))
		_label("SeoulGarden","서울림 · 시민의 쉼터",Vector3(x,3.0,z-1.2),26)
		var ticket := Vector3(left,0,z)
		if _box("QueueTicket",Vector3(.60,1.23,.50),ticket+Vector3.UP*.615,"paper",true):
			_box("QueueTicketScreen",Vector3(.40,.28,.03),ticket+Vector3(0,.98,.27),"screen")
			_box("TicketSlot",Vector3(.20,.045,.025),ticket+Vector3(0,.68,.27),"ink")
			_label("QueueTicketLabel","번호표 발급",ticket+Vector3(0,1.52,.26),24)
		_feature("queue_ticket_machine")
		for index in range(2):
			var counter := Vector3(x,0,z-5.0-index*3.6)
			if _desk(counter,"CivicServiceCounter","oak",2.5):
				_label("ServiceCounterNumber","%02d  %s"%[index+1,["시민 상담","생활 안내"][index]],counter+Vector3(0,1.46,0),25)
				_box("ServiceDeskDivider",Vector3(.05,.42,.72),counter+Vector3(.92,1.04,0),"glass")
		_feature("numbered_service_counters")
	elif String(level_profiles[level].profile_id)=="civic_public_lounge":
		_garden(Vector3(x,0,z-1.2),Vector2(3.7,2.6))
		_display_case(Vector3(left,0,z),"서울의 오늘",level)
	elif String(level_profiles[level].profile_id)=="civic_meeting":
		_meeting(Vector3(x,0,z-1),"시민회의실")
	else:
		for index in range(3):
			var at := Vector3(x,0,z-index*3.5)
			if _desk(at,"CivicServiceCounter","oak",2.5):
				_label("ServiceCounterNumber","%02d  %s"%[index+1,["민원 상담","서류 접수","생활 안내"][index]],at+Vector3(0,1.5,0),25)
		_feature("numbered_service_counters")
	for index in range(3):_queue_seat(Vector3(left,0,z-3.2-index*2.0))
	_label("CivicQueueDisplay","종합민원 안내\n접수 · 상담 · 생활정보\n먼저 안내창구를 찾아주세요",Vector3(left,2.4,z-8.0),25)
	_feature("citizen_waiting_area")
	if room.width>22.0:
		for side in [-1.0,1.0]:_plant(Vector3(side*8.0,0,z-1.0),1.1)

func _access_gate(point: Vector3) -> void:
	if not _box("AccessGate",Vector3(.28,.95,1.15),point+Vector3.UP*.475,"steel",true):return
	_box("AccessReader",Vector3(.18,.04,.23),point+Vector3(0,.98,.30),"ink")
	_box("AccessReaderLight",Vector3(.08,.015,.05),point+Vector3(0,1.005,.34),"seoul_teal")
	_box("AccessGateWing",Vector3(.35,.36,.035),point+Vector3(-.25,.65,.25),"glass")

func _office(level: int) -> void:
	var x := _core_right(2.0)
	var z := _front(7.0)
	var programme := String(level_profiles[level].profile_id)
	if level==0:
		_reception(Vector3(x,0,z),"Office","방문 안내 · RECEPTION","walnut")
		_feature_wall(Vector3(x,0,z-1.3),3.8,"walnut")
		for offset in [-.75,.75]:_access_gate(Vector3(x+offset,0,z-3.3))
		var directory := Vector3(_core_left(1.2),0,_front(5.1))
		if _box("TenantDirectory",Vector3(1.45,2.20,.16),directory+Vector3.UP*1.25,"ink",true):
			var directory_label := _label("TenantDirectoryText","입주사 안내\n\n업무 · 공용공간\n회의 · 라운지\n로비 · 안내\n\n방문증을 착용해 주세요",directory+Vector3(0,1.4,.11),24)
			directory_label.modulate=Color(.93,.94,.87);directory_label.outline_size=0
			_wrap(directory_label,1.27)
		_sofa(Vector3(x,0,z-6.0),"navy")
		if room.width>=18.0:
			_sofa(Vector3(_core_left(),0,z-3.6),"sage")
			_feature_wall(Vector3(_core_left(),0,z-4.3),3.3,"oak")
		_feature("access_gates")
		_feature("tenant_directory")
	elif programme=="office_meeting":
		_meeting(Vector3(x,0,z),"회의실 %02d"%((_seed+level)%9+1))
		_glass_room(Vector3(x,0,z),"회의 · 협업",minf(4.5,room.width*.5-2.5),5.3)
		_sofa(Vector3(x,0,z-6.5),"sage")
	elif programme=="office_lounge":
		_sofa(Vector3(x,0,z),"sage")
		_pantry(Vector3(x,0,z-4.5))
		if room.depth>24:_sofa(Vector3(_core_left(1.8),0,z-3.0),"linen")
	else:
		for index in range(mini(5,maxi(2,int((room.depth-11.0)/4.5)))):
			var at := Vector3(x,0,z-index*4.5)
			if _desk(at,"OfficeDesk","oak",2.2):
				_chair(at+Vector3(0,0,1.0),"navy")
				_box("OfficeMonitor",Vector3(.70,.42,.06),at+Vector3(0,1.13,-.20),"ink")
				_box("OfficeMonitorScreen",Vector3(.62,.34,.018),at+Vector3(0,1.13,-.16),"screen")
				_box("OfficeKeyboard",Vector3(.44,.026,.14),at+Vector3(0,.84,.20),"dark")
				_paper(at+Vector3(.73,.84,.05))
				# Open-ended desk bays with a 1.45m divider create work zones,
				# rather than isolated desks in the full source footprint.
				_box("WorkBayDivider",Vector3(2.8,1.45,.10),at+Vector3(0,.725,-1.30),"oak_light",true)
				_box("WorkBaySideGlass",Vector3(.075,1.9,2.8),at+Vector3(1.45,.95,0),"clear_glass",true)
				_box("WorkBayFrame",Vector3(.07,1.9,.07),at+Vector3(1.45,.95,1.36),"ink")
		if room.width>=23.0:
			var left_meeting := Vector3(_core_left(),0,z-1.0)
			_meeting(left_meeting,"공용 회의실")
			_glass_room(left_meeting,"공용 회의실",4.6,5.3)
		_feature("workstations")
		_feature("partitioned_work_bays")
	_plant(Vector3(x,0,_front(3.9)),.8)
	_feature("office_floor_programmes")

func _meeting(point: Vector3, title: String) -> void:
	if not _desk(point,"MeetingTable","walnut",2.5):return
	for side in [-1.0,1.0]:
		for offset in [-.65,.65]:_chair(point+Vector3(offset,0,side*1.12),"navy",true,side)
	_box("MeetingWhiteboard",Vector3(2.2,1.1,.07),point+Vector3(0,1.72,-2.0),"paper")
	_box("WhiteboardTray",Vector3(2.2,.05,.14),point+Vector3(0,1.15,-1.95),"steel")
	_label("MeetingRoomSign",title+"\n회의 중에는 조용히 해 주세요",point+Vector3(0,2.6,-2.0),24)
	for index in range(3):_paper(point+Vector3(-.65+index*.65,.84,.03))
	_feature("meeting_room")

func _sofa(point: Vector3, material := "linen") -> void:
	if not _box("LoungeSofa",Vector3(2.15,.43,.90),point+Vector3.UP*.37,material,true):return
	_box("SofaBack",Vector3(2.15,.66,.22),point+Vector3(0,.78,-.36),material)
	for side in [-1.0,1.0]:
		_box("SofaArm",Vector3(.20,.30,.92),point+Vector3(side*1.0,.70,0),material)
		_box("SofaFoot",Vector3(.09,.17,.08),point+Vector3(side*.8,.09,.28),"walnut")
		_box("SofaCushion",Vector3(.46,.32,.15),point+Vector3(side*.55,.76,-.22),"sage" if material=="linen" else "linen")
	var table := point+Vector3(0,0,1.25)
	if _box("LoungeCoffeeTable",Vector3(1.15,.40,.65),table+Vector3.UP*.20,"walnut",true):
		_box("CoffeeTableTop",Vector3(1.22,.05,.70),table+Vector3.UP*.43,"stone")
		_book(table+Vector3(-.25,.49,.02),1)
		_round("CoffeeCup","cylinder",Vector3(.085,.095,.085),table+Vector3(.34,.51,.04),"paper")
	_feature("upholstered_lounge")

func _pantry(point: Vector3) -> void:
	if not _desk(point,"PantryCounter","walnut",2.1):return
	_box("CoffeeMachine",Vector3(.46,.53,.38),point+Vector3(-.5,1.10,0),"ink")
	_box("CoffeeMachinePanel",Vector3(.27,.18,.025),point+Vector3(-.5,1.20,.205),"screen")
	for index in range(3):_round("PantryCup","cylinder",Vector3(.08,.10,.08),point+Vector3(.10+index*.16,.88,.13),"paper")
	_label("PantrySign","공용 휴게공간\n사용한 컵은 반납해 주세요",point+Vector3(0,1.9,-.48),24)
	_feature("coffee_pantry")

func _hotel(level: int) -> void:
	var x := _core_right(2.0)
	var z := _front(6.8)
	if level==0:
		_reception(Vector3(x,0,z),"Hotel","프런트 · CHECK IN","walnut")
		_feature_wall(Vector3(x,0,z-1.15),3.8,"walnut")
		_label("HotelWelcome","환영합니다\nWELCOME",Vector3(x,2.05,z-.90),31)
		_sofa(Vector3(x,0,z-5.0),"linen")
		_floor_lamp(Vector3(x+1.35,0,z-5.0))
		if room.width>15:
			_sofa(Vector3(_core_left(1.8),0,z-3),"navy")
			_feature_wall(Vector3(_core_left(),0,z-3.7),3.3,"oak")
			_floor_lamp(Vector3(_core_left()-.95,0,z-3.5))
		_feature("hotel_check_in")
	elif level==1:
		_pantry(Vector3(x,0,z))
		for index in range(mini(4,maxi(1,int((room.depth-13.0)/4.8)))):
			_sofa(Vector3(x,0,z-4.2-index*4.8),"linen")
		_feature("breakfast_lounge")
	else:
		for index in range(mini(5,maxi(1,int((room.depth-11.0)/5.2)))):
			_guest_suite(Vector3(x,0,z-index*5.2),level*100+index+1)
			if room.width>=22.0:_guest_suite(Vector3(_core_left(),0,z-index*5.2),level*100+index+21)
		_feature("guest_room_bays")
	_plant(Vector3(_core_right(.9),0,_front(3.8)),1.0)

func _floor_lamp(point: Vector3) -> void:
	if not _safe(point,Vector3(.65,1,.65)):return
	_round("FloorLampBase","cylinder",Vector3(.38,.05,.38),point+Vector3.UP*.04,"brass")
	_box("FloorLampStem",Vector3(.035,1.5,.035),point+Vector3.UP*.80,"brass")
	_round("FloorLampShade","shade",Vector3(.64,.40,.64),point+Vector3.UP*1.60,"linen")
	_round("FloorLampGlow","cylinder",Vector3(.56,.015,.56),point+Vector3.UP*1.405,"light")

func _guest_suite(point: Vector3, number: int) -> void:
	var side := 1.0 if point.x>0 else -1.0
	var inner := maxf(2.55,absf(point.x)-2.25)
	var outer := minf(room.width*.5-.45,absf(point.x)+2.25)
	var bay_width := outer-inner
	var center_x := side*(inner+bay_width*.5)
	var height: float=room.floor_height-.15
	# Only register a room when its complete enclosure fits the protected plan.
	# Full-height transoms prevent jumping through the top of a locked doorway.
	if not _safe(Vector3(center_x,0,point.z+.025),Vector3(bay_width,height,4.5)):return
	if not _box("Bed",Vector3(1.55,.48,2.2),point+Vector3(0,.28,-.30),"linen",true):return
	_box("BedDuvet",Vector3(1.55,.12,1.64),point+Vector3(0,.57,-.03),"paper")
	_box("BedRunner",Vector3(1.56,.025,.36),point+Vector3(0,.65,.47),"navy")
	_box("BedHeadboard",Vector3(1.65,1.10,.12),point+Vector3(0,.65,-1.40),"walnut")
	for pillow_side in [-1.0,1.0]:_box("BedPillow",Vector3(.58,.13,.38),point+Vector3(pillow_side*.40,.62,-.96),"paper")
	_box("GuestRoomRearWall",Vector3(bay_width,height,.12),Vector3(center_x,height*.5,point.z-2.2),"wall",true)
	_box("GuestRoomOuterWall",Vector3(.12,height,4.5),Vector3(side*outer,height*.5,point.z),"wall",true)
	_box("GuestRoomFrontWall",Vector3(bay_width,height,.12),Vector3(center_x,height*.5,point.z+2.25),"oak_light",true)
	_box("GuestRoomEntryWall",Vector3(.12,height,2.75),Vector3(side*inner,height*.5,point.z-.825),"wall",true)
	_box("GuestRoomDoorPocket",Vector3(.12,height,.55),Vector3(side*inner,height*.5,point.z+1.98),"walnut",true)
	var leaf_height := 2.20
	_box("GuestDoorTransom",Vector3(.12,height-leaf_height,1.15),Vector3(side*inner,(height+leaf_height)*.5,point.z+1.175),"wall",true)
	room.make_guest_door(_level,number,side*inner,point.z+1.175,leaf_height,side)
	_box("GuestDoorHeader",Vector3(.16,.12,1.15),Vector3(side*inner,leaf_height+.06,point.z+1.175),"walnut")
	for z in [.60,1.75]:_box("GuestDoorJamb",Vector3(.16,leaf_height+.12,.07),Vector3(side*inner,(leaf_height+.12)*.5,point.z+z),"walnut")
	_label("GuestRoomNumber","%03d\n객실"%number,Vector3(side*(inner-.09),1.65,point.z+1.98),22,true,-side*PI*.5)
	_box("GuestRoomFloorInset",Vector3(bay_width-.10,.009,4.3),Vector3(center_x,.007,point.z),"linen")
	_feature("beds_and_room_numbers")
	_feature("master_key_guest_room_doors")

func _display_case(point: Vector3, title: String, variation: int) -> void:
	if not _box("GalleryDisplay",Vector3(1.75,.92,.72),point+Vector3.UP*.46,"paper",true):return
	_box("DisplayCaseTop",Vector3(1.85,.045,.80),point+Vector3.UP*.94,"steel")
	for index in range(3):_book(point+Vector3(-.52+index*.50,1.0,0),index+variation)
	_label("DisplayCaption",title+"\n자료 전시",point+Vector3(0,.65,.38),22)
	_feature("exhibition_cases")

func _gallery(level: int) -> void:
	var x := _right_x(2.0)
	var z := _front(6.8)
	if level==0:_reception(Vector3(x,0,z),"Gallery","전시안내 · 관람 안내","paper")
	for index in range(mini(5,maxi(2,int((room.depth-12.0)/5.0)))):
		var at := Vector3(x,0,z-4.0-index*5.0)
		if not _box("ArtworkPanel",Vector3(2.0,2.35,.14),at+Vector3.UP*1.175,"paper",true):continue
		_box("ArtworkFrame",Vector3(1.5,1.50,.065),at+Vector3(0,1.43,.11),"walnut")
		_box("ArtworkCanvas",Vector3(1.35,1.35,.025),at+Vector3(0,1.43,.16),"linen")
		for mark in range(4):
			_box("Artwork",Vector3(.26+mark*.10,.38,.018),at+Vector3(-.48+mark*.29,1.23+sin(mark+index)*.30,.19),["seoul_teal","terracotta","sage","brass"][posmod(mark+level+index,4)])
		_label("ArtworkCaption","서울의 장면 %02d\n색과 도시 · 추상 구성"%(index+1),at+Vector3(0,.43,.12),19)
	if room.width>15.0:_display_case(Vector3(_left_x(1.8),0,z-1.0),"기록과 도시",level)
	_feature("freestanding_art_panels")
	_feature("original_abstract_artworks")

func _chapel(level: int) -> void:
	var x := _right_x(2.0)
	var z := _front(6.8)
	if level>0:
		_meeting(Vector3(x,0,z),"모임 · 교육실")
		_pantry(Vector3(x,0,z-6.0))
		_feature("community_room")
		return
	for index in range(mini(7,maxi(2,int((room.depth-13.0)/2.5)))):
		var point := Vector3(x,0,z-index*2.4)
		if not _box("ChapelPew",Vector3(2.3,.15,.58),point+Vector3.UP*.46,"walnut",true):continue
		_box("PewBack",Vector3(2.3,.52,.09),point+Vector3(0,.78,.24),"walnut")
		for side in [-1.0,1.0]:_box("PewSupport",Vector3(.12,.43,.52),point+Vector3(side*.91,.23,0),"walnut")
	var altar := Vector3(x,0,maxf(-room.depth*.5+3.0,z-17.0))
	_desk(altar,"ChapelLectern","oak",1.2)
	_label("ChapelNotice","예배당\n조용히 머물러 주세요",altar+Vector3(0,2.2,-.50),27)
	_feature("wooden_pews_and_lectern")

func _residential(level: int) -> void:
	var x := _right_x(1.7)
	var z := _front(6.2)
	if level==0:
		if _box("ResidentialMailWall",Vector3(2.3,1.8,.32),Vector3(x,1.2,z),"steel",true):
			for row in range(4):
				for column in range(5):
					var at := Vector3(x-.90+column*.45,.62+row*.38,z+.18)
					_box("Mailbox",Vector3(.40,.33,.04),at,"paper")
					_box("MailboxSlot",Vector3(.23,.018,.015),at+Vector3(0,.075,.03),"ink")
			_label("MailWallLabel","세대 우편함 · 공동현관",Vector3(x,2.36,z+.20),26)
		for index in range(3):_box("ParcelBox",Vector3(.45,.35,.40),Vector3(x-.6+index*.55,.175,z+1.2),"oak_light",true)
		_feature("mailboxes_and_parcels")
	else:
		for index in range(mini(6,maxi(2,int((room.depth-11.0)/4.0)))):
			var at := Vector3(x,1.15,z-index*4.0)
			if not _box("ResidentialDoorBay",Vector3(2.0,2.3,.13),at,"wall",true):continue
			_box("ApartmentDoor",Vector3(.90,2.04,.06),at+Vector3(0,-.1,.10),"walnut")
			_box("DoorHandle",Vector3(.05,.14,.045),at+Vector3(.31,-.1,.15),"steel")
			_label("ApartmentNumber","%03d"%(level*100+index+1),at+Vector3(.68,.28,.11),20)
		_feature("numbered_apartment_doors")

func _bank(level: int) -> void:
	var x := _right_x(2.0)
	var left := _left_x(1.6)
	var z := _front(6.6)
	if level>0:
		_meeting(Vector3(x,0,z),"상담실 · 고객 상담")
		_feature("financial_consultation")
		return
	for index in range(3):
		var point := Vector3(x,0,z-index*3.5)
		if not _desk(point,"BankServiceCounter","paper",2.2):continue
		_box("BankPrivacyDivider",Vector3(.06,.52,.80),point+Vector3(.95,1.10,0),"glass")
		_label("BankCounterNumber","%02d  고객 상담"%(index+1),point+Vector3(0,1.65,0),25)
	for index in range(3):_queue_seat(Vector3(left,0,z-index*2.0))
	_label("BankQueueNotice","창구 안내 · 번호표 순서대로\n신분증을 준비해 주세요",Vector3(left,2.25,z-4.0),25)
	_feature("bank_counter_and_waiting")

func finish() -> void:
	for key: String in _round_batches:
		var split := key.split("/")
		var transforms: Array = _round_batches[key]
		var mm := MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=_round_meshes[split[0]];mm.instance_count=transforms.size()
		for i in range(transforms.size()):mm.set_instance_transform(i,transforms[i])
		var instance := MultiMeshInstance3D.new();instance.name="DetailCurves_"+key.replace("/","_");instance.multimesh=mm;instance.material_override=room._materials[split[1]]
		room.add_child(instance)
	_round_batches.clear()
	set_active_floor(0)

func set_active_floor(level: int) -> void:
	for label in labels:label.visible=absi(int(label.get_meta("detail_level",-10))-level)<=1

func snapshot() -> Dictionary:
	return {"profile_id":profile_id,"profile_basis":"source kind and title; authored interpretation","layout_basis":"game_reconstruction","level_profiles":level_profiles.duplicate(true),"detail_counts":detail_counts.duplicate(),"features":features.duplicate(),"protected_zones":protected_zones.duplicate(),"placements":placements.duplicate(true),"facilities":facility_kit.snapshot() if facility_kit else [],"rejected_unsafe_placements":_rejected,"visible_detail_labels":labels.filter(func(label: Label3D) -> bool:return label.visible).size(),"total_detail_labels":labels.size()}
