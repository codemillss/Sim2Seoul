extends RefCounted
## Authored playable facility spaces. Equipment, menus and floor programmes
## are original game interpretations, not facilities verified at each address.
var _kit_ref: WeakRef
var kit: RefCounted:
	get:return _kit_ref.get_ref() as RefCounted if _kit_ref!=null else null
var room: Node3D
var facilities: Array[Dictionary] = []
## Room-local, source-sized equipment targets. Each registration belongs to
## geometry that was actually accepted by the protected circulation layout.
var interactions: Array[Dictionary] = []
var _active_facility_id := ""
var _active_facility_type := ""

func setup(detail_kit: RefCounted) -> void:
	_kit_ref=weakref(detail_kit);room=detail_kit.room
	var colors := {"facility_tile":Color(.73,.82,.77),"gym_rubber":Color(.14,.18,.20),"food_rice":Color(.96,.93,.79),"food_kimchi":Color(.66,.22,.10),"food_green":Color(.28,.47,.17),"food_soup":Color(.49,.32,.12),"towel":Color(.88,.87,.81),"bath_water":Color(.22,.60,.65,.57)}
	for key: String in colors:
		var material := StandardMaterial3D.new();material.albedo_color=colors[key];material.roughness=.78
		if key=="bath_water":material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.roughness=.12
		room._materials[key]=material
	var tile := ShaderMaterial.new();tile.shader=preload("res://scripts/interior_surface.gdshader");tile.set_shader_parameter("base_color",colors.facility_tile);tile.set_shader_parameter("surface_kind",0);room._materials["facility_tile"]=tile

func programme(profile: String,level: int,seed: int) -> Dictionary:
	match profile:
		"hotel":
			if level==1:return {"profile_id":"hotel_buffet","title":"뷔페 · 한식 다이닝"}
			if level>=3 and level%6==3:return {"profile_id":"hotel_fitness","title":"피트니스 · 트레이닝"}
			if level>=4 and level%6==4:return {"profile_id":"hotel_spa","title":"스파 · 샤워 · 목욕"}
			if level>=5 and level%6==5:return {"profile_id":"hotel_banquet","title":"연회 · 비즈니스 라운지"}
		"office":
			if level>0:
				match (level+seed)%6:
					3:return {"profile_id":"office_cafeteria","title":"구내식당 · 공용 주방"}
					4:return {"profile_id":"office_fitness","title":"피트니스 · 휴게"}
					5:return {"profile_id":"office_training","title":"교육 · 세미나"}
		"civic":
			if level>0 and level%6==4:return {"profile_id":"civic_classroom","title":"시민강의 · 배움터"}
			if level>0 and level%6==5:return {"profile_id":"civic_cafeteria","title":"시민 식당 · 휴게"}
		"residential":
			if level==1:return {"profile_id":"residential_laundry","title":"공용 세탁 · 생활지원"}
			if level==2:return {"profile_id":"residential_kitchen","title":"공유 주방 · 주민식탁"}
			if level==3:return {"profile_id":"residential_fitness","title":"주민 운동 · 휴게"}
		"gallery":
			if level==1:return {"profile_id":"gallery_workshop","title":"창작 작업실 · 교육"}
			if level==2:return {"profile_id":"gallery_lounge","title":"아트 라운지 · 자료"}
		"bank":
			if level==2:return {"profile_id":"bank_staff_lounge","title":"직원 휴게 · 공용 식탁"}
		"chapel":
			if level==1:return {"profile_id":"chapel_education","title":"모임 · 교육 · 공동식탁"}
	return {}

func build(programme_id: String) -> bool:
	match programme_id:
		"hotel_buffet","office_cafeteria","civic_cafeteria":_dining(programme_id);return true
		"hotel_fitness","office_fitness","residential_fitness":_fitness();return true
		"hotel_spa":_spa();return true
		"hotel_banquet":_banquet();return true
		"civic_classroom","office_training","chapel_education":_classroom(programme_id);return true
		"residential_laundry":_laundry();return true
		"residential_kitchen":_community_kitchen();return true
		"gallery_workshop":_workshop();return true
		"gallery_lounge","bank_staff_lounge":_lounge(programme_id);return true
	return false

func decorate(profile: String,level: int) -> void:
	if profile!="library" or level not in [1,2,3]:return
	var kind: String=["children_reading","media_reading","library_study"][level-1]
	var title: String=["어린이 자료 · 이야기 마당","미디어 자료 · 디지털 열람","그룹 스터디 · 자료 토론"][level-1]
	var zone := _zone(kind,title,1.0,4.2)
	if level==1 and not zone.is_empty():
		var p: Vector3=zone.center
		_b("FacilityChildTable",Vector3(1.2,.08,.95),Vector3(p.x,.50,zone.front-2.6),"oak_light",true)
		for side in [-1.0,1.0]:
			_r("FacilityChildStool","cylinder",Vector3(.43,.29,.43),Vector3(p.x+side*.85,.15,zone.front-2.5),"cushion_green" if side<0 else "cushion_orange")
			_b("FacilityChildStoolSupport",Vector3(.28,.29,.28),Vector3(p.x+side*.85,.145,zone.front-2.5),"oak_light",true)
		for i in range(3):kit._book(Vector3(p.x-.35+i*.32,.58,zone.front-2.6),i)
		kit._feature("children_story_corner")
	elif level==2 and not zone.is_empty():
		var p: Vector3=zone.center
		_computer(Vector3(p.x,0,zone.front-2.6),"FacilityMediaDesk")
		_b("FacilityHeadphoneBand",Vector3(.26,.025,.08),Vector3(p.x+.61,1.03,zone.front-2.5),"ink")
		for side in [-1.0,1.0]:_r("FacilityHeadphoneCup","cylinder",Vector3(.08,.065,.08),Vector3(p.x+.61+side*.13,.97,zone.front-2.5),"ink")
		kit._feature("media_reading_station")
	elif level==3 and not zone.is_empty():
		var p: Vector3=zone.center
		var table_x: float=zone.outer-.95
		var table_z: float=zone.front-2.55
		if kit._desk(Vector3(table_x,0,table_z),"FacilityStudyTable","oak",1.4):
			for side in [-1.0,1.0]:kit._chair(Vector3(table_x,0,table_z+side*.94),"sage",true,side)
		_b("FacilityStudyWhiteboard",Vector3(minf(2.4,float(zone.width)-.3),1.1,.05),Vector3(p.x,1.7,zone.back+.08),"paper")
		_label("FacilityStudyNotice","자료 토론 · 그룹 스터디",Vector3(p.x,1.7,zone.back+.12),minf(2.3,float(zone.width)-.4),23)
		kit._feature("library_group_study")

func register_study_desk(table: Vector3,seat: Vector3,digital: bool) -> void:
	_active_facility_id="library_desk_%d_%d"%[kit._level,interactions.size()];_active_facility_type="library_study"
	var y: float=kit._level*room.floor_height
	var approach:=seat+Vector3(0,.08,.65);var use:=seat+Vector3.UP*.08
	facilities.append({"id":_active_facility_id,"type":"library_study","programme":String(kit.level_profiles[kit._level].profile_id),"level":kit._level,"title":"디지털 열람석" if digital else "조용한 열람석","entry_point":approach+Vector3.UP*y,"walk_points":[approach+Vector3.UP*y,use+Vector3.UP*y],"coordinate_space":"room_local","bounds":AABB(table+Vector3(-1.04,y,-.54),Vector3(2.08,1.8,2.45))})
	_interaction("study","열람석에 앉아 공부하기","study",use,approach,table+Vector3(0,.87,.10),{"facing_yaw":0.,"equipment_title":"Detail_ReadingDeskTop","duration_seconds":20.,"digital":digital,"seat_height_m":.52,"desk_height_m":.82,"seat_center":seat+Vector3.UP*y,"table_center":table+Vector3.UP*y})
	_label("StudySeatPrompt","E · 앉아서 공부 / 다시 E · 일어나기",seat+Vector3(0,1.25,.05),1.65,18)
	kit._feature("usable_seated_library_study")

func _b(title: String,size: Vector3,p: Vector3,material: String,solid := false,basis := Basis.IDENTITY) -> bool:
	var added: bool=kit._box(title,size,p,material,solid,basis)
	if added:
		kit.placements.back()["facility_id"]=_active_facility_id
		if solid:
			room.bodies.back().set_meta("facility_id",_active_facility_id)
			room.bodies.back().set_meta("facility_type",_active_facility_type)
	return added

func _r(title: String,kind: String,size: Vector3,p: Vector3,material: String,basis := Basis.IDENTITY) -> void:
	kit._round(title,kind,size,p,material,basis)
	kit.placements.back()["facility_id"]=_active_facility_id

func _label(title: String,text: String,p: Vector3,width := 2.4,font_size := 25) -> Label3D:
	var label: Label3D=kit._label(title,text,p,font_size)
	kit._wrap(label,width)
	label.set_meta("facility_id",_active_facility_id);label.set_meta("facility_type",_active_facility_type);label.set_meta("facility_level",kit._level)
	return label

func _interaction(kind: String,title: String,equipment_id: String,use_point: Vector3,approach_point: Vector3,anchor_point: Vector3,data: Dictionary = {}) -> void:
	# Input coordinates are relative to this floor; exported coordinates include
	# its full Y offset, exactly like facility entry and shower points.
	if not kit._safe(use_point,Vector3(.62,1.70,.62)) or not kit._safe(approach_point,Vector3(.62,1.70,.62)):return
	var floor_offset: Vector3=Vector3.UP*(kit._level*room.floor_height)
	var row := {"id":"%s/%s/%s"%[String(room.spec.get("id","building")),_active_facility_id,equipment_id],"kind":kind,"title":title,"level":kit._level,"facility_id":_active_facility_id,"use_point":use_point+floor_offset,"approach_point":approach_point+floor_offset,"anchor_point":anchor_point+floor_offset,"coordinate_space":"room_local","data":data.duplicate(true)}
	interactions.append(row)

func _zone(kind: String,title: String,side := 1.0,length := 7.8) -> Dictionary:
	var x: float=kit._core_right(2.0) if side>0 else kit._core_left(2.0)
	var width := minf(4.8,(room.width*.5-.55-absf(x))*2.0)
	var front: float=room.depth*.5-5.4
	var usable_length := minf(length,room.depth-7.0)
	if side<0 and absf(x)>room.width*.5-5.0:usable_length=minf(usable_length,front-room.stair_front-2.8)
	if width<2.3 or usable_length<3.8:return {}
	var point := Vector3(x,0,front-usable_length*.5)
	if not kit._safe(point,Vector3(width,1,usable_length)):return {}
	var inner := x-side*width*.5
	var outer := x+side*width*.5
	var back := front-usable_length
	var h := minf(2.4,room.floor_height-.28)
	_active_facility_id="%s_%d_%d"%[kind,kit._level,facilities.size()]
	_active_facility_type=kind
	_b("FacilityZoneRearWall",Vector3(width,h,.09),Vector3(x,h*.5,back),"facility_tile" if kind=="spa" else "wall",true)
	_b("FacilityZoneOuterWall",Vector3(.09,h,usable_length),Vector3(outer,h*.5,point.z),"oak_light" if kind in ["buffet","kitchen"] else "wall",true)
	# The corridor-side opening is 1.65m long, wide enough to enter on foot.
	if usable_length>4.8:_b("FacilityZoneInnerScreen",Vector3(.065,h,usable_length-1.65),Vector3(inner,h*.5,back+(usable_length-1.65)*.5),"clear_glass",true)
	_b("FacilityFloorFinish",Vector3(width-.05,.008,usable_length-.04),Vector3(x,.016,point.z),"facility_tile" if kind in ["spa","laundry","kitchen","buffet"] else "oak_light")
	_b("FacilitySignBoard",Vector3(minf(width,2.75),.50,.06),Vector3(x,2.28,front),"ink")
	var sign := _label("FacilitySign",title,Vector3(x,2.28,front+.045),minf(width-.15,2.60),23)
	sign.modulate=Color(.96,.96,.89);sign.outline_size=0
	var y: float=kit._level*room.floor_height+.08
	var entry := Vector3(inner+side*.52,y,front-.78)
	var walk: Array[Vector3]=[Vector3(0,y,front-.78),entry,Vector3(x,y,front-.85)]
	var row := {"id":_active_facility_id,"type":kind,"programme":String(kit.level_profiles[kit._level].profile_id),"level":kit._level,"title":title,"entry_point":entry,"walk_points":walk,"coordinate_space":"room_local","bounds":AABB(Vector3(minf(inner,outer),kit._level*room.floor_height,back),Vector3(width,h,usable_length)),"geometry_prefix":"Detail_Facility","sign_prefix":"Detail_FacilitySign"}
	facilities.append(row)
	kit._feature("walk_in_"+kind)
	return {"center":point,"width":width,"length":usable_length,"front":front,"back":back,"inner":inner,"outer":outer,"side":side,"row":row}

func _dining(programme_id: String) -> void:
	var zone := _zone("buffet","한식 뷔페 · 밥 / 국 / 반찬",1.0,7.8)
	if zone.is_empty():return
	var counter_x: float=zone.outer-.64
	var z: float=zone.front-4.2
	if _b("FacilityBuffetCounter",Vector3(1.0,.88,4.9),Vector3(counter_x,.44,z),"oak",true):
		_b("FacilityBuffetSteelTop",Vector3(1.08,.07,5.0),Vector3(counter_x,.915,z),"steel")
		for i in range(4):
			var at := Vector3(counter_x,.985,z+1.75-i*1.16)
			var tray_built := _b("FacilityFoodTray",Vector3(.76,.065,.80),at,"steel")
			_b("FacilityTrayInset",Vector3(.65,.025,.68),at+Vector3.UP*.042,"paper")
			if i==0:
				for dx in [-.20,.20]:_r("FacilityRiceMound","foliage",Vector3(.30,.13,.42),at+Vector3(dx,.12,0),"food_rice")
			elif i==1:
				_r("FacilitySoupPot","cylinder",Vector3(.56,.22,.56),at+Vector3.UP*.10,"ink")
				_r("FacilitySoupSurface","cylinder",Vector3(.50,.013,.50),at+Vector3.UP*.215,"food_soup")
			else:
				for n in range(6):_b("FacilityKoreanSideDish",Vector3(.16,.055,.20),at+Vector3(-.20+float(n%3)*.20,.10,-.16+float(n/3)*.30),"food_kimchi" if i==2 else "food_green")
			_label("FacilityBuffetMenu",["따뜻한 밥","국 · 수프","김치 · 반찬","채소 · 샐러드"][i],at+Vector3(-.05,.22,.49),.90,18)
			if tray_built:
				var food_title: String=["따뜻한 밥","국 · 수프","김치 · 반찬","채소 · 샐러드"][i]
				var use_point := Vector3(counter_x-1.03,.08,at.z)
				_interaction("eat",food_title,"food_%d"%i,use_point,use_point+Vector3(0,0,.55),at+Vector3.UP*.12,{"facing_yaw":-PI*.5,"duration_seconds":3.6,"food_material":["food_rice","food_soup","food_kimchi","food_green"][i],"equipment_title":"Detail_FacilityFoodTray","food_index":i})
		_b("FacilityTrayRail",Vector3(.25,.045,4.9),Vector3(counter_x-.65,.76,z),"steel")
		kit._feature("korean_buffet_food_trays")
	var kitchen := _zone("kitchen","다이닝 · 오픈 키친",-1.0,7.2)
	if not kitchen.is_empty():
		var p: Vector3=kitchen.center
		_dining_table(Vector3(p.x,0,kitchen.front-3.0))
		_kitchen_counter(Vector3(p.x,0,kitchen.front-minf(kitchen.length-1.0,6.1)))
	elif zone.width>3.6:_dining_table(Vector3(zone.inner+1.25,0,zone.front-6.25),1.2)
	kit._feature("communal_dining")

func _dining_table(point: Vector3,width := 1.7) -> void:
	if not kit._desk(point,"FacilityDiningTable","oak",width):return
	for side in [-1.0,1.0]:kit._chair(point+Vector3(0,0,side*1.02),"linen",true,side)
	for side in [-1.0,1.0]:
		_r("FacilityDiningPlate","cylinder",Vector3(.26,.018,.26),point+Vector3(side*.42,.835,0),"paper")
		_b("FacilityChopsticks",Vector3(.018,.012,.26),point+Vector3(side*.42+.19,.85,0),"walnut")
		_r("FacilityDiningCup","cylinder",Vector3(.075,.09,.075),point+Vector3(side*.42,.88,-.30),"paper")

func _kitchen_counter(point: Vector3) -> void:
	if not kit._desk(point,"FacilityKitchenCounter","paper",2.2):return
	_b("FacilityKitchenSplashback",Vector3(2.25,.76,.05),point+Vector3(0,1.18,-.51),"facility_tile")
	for side in [-1.0,1.0]:_r("FacilityHobRing","cylinder",Vector3(.29,.014,.29),point+Vector3(side*.38,.845,-.05),"ink")
	_b("FacilityRangeHood",Vector3(1.45,.19,.65),point+Vector3(0,2.13,-.12),"steel")
	_b("FacilitySink",Vector3(.44,.025,.43),point+Vector3(.79,.845,.02),"steel")
	_b("FacilityTap",Vector3(.035,.25,.035),point+Vector3(.79,.98,-.25),"steel")
	kit._feature("open_kitchen_hob_sink_hood")

func _fitness() -> void:
	var zone := _zone("fitness","피트니스 · 유산소 / 근력",1.0,7.8)
	if zone.is_empty():return
	for i in range(2):_treadmill(Vector3(zone.outer-.85,0,zone.front-2.8-i*2.6),i)
	# Keep a continuous aisle between the new stations and the original belts.
	# Very narrow accepted rooms retain their original treadmill programme.
	if float(zone.width)>=4.1:
		_stationary_cycle(Vector3(zone.inner+.93,0,zone.front-2.9))
		_rower(Vector3(zone.inner+.93,0,zone.front-5.70))
	var left := _zone("strength","스트레칭 · 웨이트",-1.0,6.8)
	if not left.is_empty():
		var x: float=left.center.x
		var bench_run := minf(1.75,float(left.length)-2.6)
		var z: float=left.front-1.95-bench_run*.5
		var bench_x := x+.30
		_b("FacilityWeightBench",Vector3(.62,.12,bench_run),Vector3(bench_x,.53,z),"gym_rubber",true)
		for dz in [-bench_run*.36,bench_run*.36]:_b("FacilityBenchSupport",Vector3(.48,.46,.08),Vector3(bench_x,.23,z+dz),"steel")
		# A longitudinal rack fits even the shortest west-side room without
		# pushing its rear end into the protected staircase approach.
		var rack_x: float=left.outer+.38
		var rack_z: float=left.front-minf(3.0,float(left.length)*.55)
		if _b("FacilityDumbbellRack",Vector3(.45,.78,1.8),Vector3(rack_x,.39,rack_z),"steel",true):
			for i in range(4):_dumbbell(Vector3(rack_x,.85,rack_z-.60+i*.40))
			var use_point := Vector3(x,.08,left.front-1.10)
			_interaction("weights","덤벨 운동","dumbbells",use_point,use_point+Vector3(0,0,.50),Vector3(rack_x,.85,rack_z+.60),{"facing_yaw":0.0,"duration_seconds":8.0,"equipment_title":"Detail_FacilityDumbbellRack","weight_kg":5.0})
		_b("FacilityExerciseMat",Vector3(1.25,.018,1.8),Vector3(x,.025,left.front-1.6),"sage")
	kit._feature("fitness_equipment")

func _treadmill(point: Vector3,index: int) -> void:
	if not _b("FacilityTreadmill",Vector3(1.0,.10,1.95),point+Vector3.UP*.05,"steel",true):return
	_b("FacilityRunningBelt",Vector3(.75,.025,1.65),point+Vector3(0,.115,0),"gym_rubber")
	for side in [-1.0,1.0]:_b("FacilityTreadmillHandle",Vector3(.045,1.08,.045),point+Vector3(side*.46,.64,-.58),"steel")
	_b("FacilityTreadmillConsole",Vector3(.82,.37,.12),point+Vector3(0,1.21,-.61),"ink")
	_b("FacilityFitnessDisplay",Vector3(.55,.19,.025),point+Vector3(0,1.22,-.53),"screen")
	var floor_offset: Vector3=Vector3.UP*(kit._level*room.floor_height)
	_interaction("treadmill","러닝머신 %d"%(index+1),"treadmill_%d"%index,point+Vector3(0,.18,.12),point+Vector3(0,.08,1.30),point+Vector3(0,.13,0),{"facing_yaw":0.0,"duration_seconds":8.0,"equipment_title":"Detail_FacilityTreadmill","belt_center":point+Vector3(0,.13,0)+floor_offset,"belt_size":Vector3(.75,.025,1.65),"speed_kmh":6.0})

func _stationary_cycle(point: Vector3) -> void:
	# The low physical mat supports the retained standing capsule. Saddle,
	# crank and frame are visible equipment; the seated pose is display-only.
	if not _b("FacilityStationaryCycle",Vector3(.83,.035,1.55),point+Vector3(0,-.0175,-.18),"gym_rubber",true):return
	for z in [-.75,.38]:_b("FacilityCycleFoot",Vector3(.74,.06,.10),point+Vector3(0,.07,z),"steel")
	_b("FacilityCycleFrame",Vector3(.09,.48,.09),point+Vector3(0,.32,-.14),"steel",false,Basis(Vector3.RIGHT,-.50))
	_r("FacilityCycleFlywheel","cylinder",Vector3(.45,.12,.45),point+Vector3(0,.29,-.63),"ink",Basis(Vector3.FORWARD,PI*.5))
	_b("FacilityCycleSaddlePost",Vector3(.07,.47,.07),point+Vector3(0,.37,.06),"steel")
	_b("FacilityCycleSaddle",Vector3(.29,.09,.29),point+Vector3(0,.65,.06),"gym_rubber")
	_b("FacilityCycleHandlePost",Vector3(.065,.80,.065),point+Vector3(0,.49,-.62),"steel")
	_b("FacilityCycleHandle",Vector3(.59,.055,.07),point+Vector3(0,.96,-.53),"ink")
	_b("FacilityCycleConsole",Vector3(.30,.20,.045),point+Vector3(0,1.08,-.65),"screen")
	_label("FacilityCycleLabel","사이클 · E 탑승",point+Vector3(0,1.41,-.65),.94,17)
	var use_point := point+Vector3(0,.08,.02)
	_interaction("cycle","실내 사이클","stationary_cycle",use_point,use_point+Vector3(0,0,.72),point+Vector3(0,.30,-.25),{"facing_yaw":0.0,"duration_seconds":8.0,"equipment_title":"Detail_FacilityStationaryCycle","cadence_rpm":60.0,"speed_kmh":18.0,"machine_origin":point+Vector3.UP*(kit._level*room.floor_height)})

func _rower(point: Vector3) -> void:
	if not _b("FacilityRowingMachine",Vector3(.81,.035,2.12),point+Vector3(0,-.0175,-.32),"gym_rubber",true):return
	_b("FacilityRowerRail",Vector3(.16,.15,1.72),point+Vector3(0,.22,-.03),"steel")
	for z in [-1.20,.56]:_b("FacilityRowerFoot",Vector3(.75,.075,.12),point+Vector3(0,.075,z),"steel")
	_r("FacilityRowerFan","cylinder",Vector3(.58,.26,.58),point+Vector3(0,.39,-1.08),"ink",Basis(Vector3.FORWARD,PI*.5))
	for side in [-1.0,1.0]:
		_b("FacilityRowerFootPlate",Vector3(.21,.05,.35),point+Vector3(side*.22,.26,-.47),"ink",false,Basis(Vector3.RIGHT,-.35))
		_b("FacilityRowerFootStrap",Vector3(.24,.04,.07),point+Vector3(side*.22,.31,-.47),"steel")
	_b("FacilityRowerConsolePost",Vector3(.04,.47,.05),point+Vector3(0,.72,-1.11),"steel")
	_b("FacilityRowerConsole",Vector3(.28,.20,.045),point+Vector3(0,.95,-1.08),"screen")
	_label("FacilityRowerLabel","로잉 · E 탑승",point+Vector3(0,1.28,-1.11),.92,17)
	var use_point := point+Vector3(0,.08,.05)
	_interaction("rowing","로잉머신","rowing_machine",use_point,use_point+Vector3(0,0,.75),point+Vector3(0,.48,-.35),{"facing_yaw":0.0,"duration_seconds":8.0,"equipment_title":"Detail_FacilityRowingMachine","stroke_seconds":2.4,"metres_per_stroke":8.0,"machine_origin":point+Vector3.UP*(kit._level*room.floor_height)})

func _dumbbell(point: Vector3) -> void:
	_b("FacilityDumbbellBar",Vector3(.26,.035,.035),point,"steel")
	for side in [-1.0,1.0]:_r("FacilityDumbbellWeight","cylinder",Vector3(.15,.08,.15),point+Vector3(side*.13,0,0),"gym_rubber",Basis(Vector3.FORWARD,PI*.5))

func _spa() -> void:
	var zone := _zone("spa","스파 · 샤워 · 얕은 탕",1.0,7.8)
	if zone.is_empty():return
	var x: float=zone.outer-.72
	var z: float=zone.front-2.5
	_shower(Vector3(x,0,z))
	var bath_x: float=zone.center.x
	var bath_z: float=zone.front-5.7
	var bath_width := minf(3.5,float(zone.width)-.60)
	var bath_depth := 2.2
	_b("FacilityBathTile",Vector3(bath_width,.009,bath_depth),Vector3(bath_x,.007,bath_z),"facility_tile")
	_b("FacilityBathWater",Vector3(bath_width-.20,.024,bath_depth-.18),Vector3(bath_x,.16,bath_z),"bath_water")
	for side in [-1.0,1.0]:
		_b("FacilityBathSide",Vector3(.13,.27,bath_depth+.16),Vector3(bath_x+side*bath_width*.5,.135,bath_z),"facility_tile",true)
	_b("FacilityBathBack",Vector3(bath_width,.27,.13),Vector3(bath_x,.135,bath_z-bath_depth*.5),"facility_tile",true)
	var segment := maxf(.10,(bath_width-1.10)*.5)
	for side in [-1.0,1.0]:_b("FacilityBathFront",Vector3(segment,.27,.13),Vector3(bath_x+side*(.55+segment*.5),.135,bath_z+bath_depth*.5),"facility_tile",true)
	_label("FacilityBathSign","얕은 탕 · 열린 입구",Vector3(bath_x,.70,bath_z-bath_depth*.5+.08),bath_width-.2,23)
	var y: float=kit._level*room.floor_height+.08
	var route: Array=zone.row.walk_points
	route.append(Vector3(zone.inner+.52,y,zone.front-3.75));route.append(Vector3(bath_x,y,bath_z+1.5));route.append(Vector3(bath_x,y,bath_z))
	zone.row["bath_point"]=Vector3(bath_x,y,bath_z)
	var locker := _zone("spa_lockers","탈의 · 타월 · 휴게",-1.0,6.8)
	if not locker.is_empty():
		_lockers(Vector3(locker.center.x,0,locker.front-3.4))
		kit._sofa(Vector3(locker.center.x,0,locker.front-5.3),"linen")
	kit._feature("walk_in_shower_and_shallow_bath")

func _shower(point: Vector3) -> void:
	var enclosure_built := true
	for side in [-1.0,1.0]:
		var side_built := _b("FacilityShowerPartition",Vector3(.055,2.10,1.4),point+Vector3(side*.62,1.05,0),"clear_glass",true)
		enclosure_built=enclosure_built and side_built
	var back_built := _b("FacilityShowerBack",Vector3(1.25,2.10,.055),point+Vector3(0,1.05,-.69),"facility_tile",true)
	_b("FacilityShowerRail",Vector3(.035,1.20,.035),point+Vector3(0,1.39,-.62),"steel")
	_r("FacilityShowerHead","cylinder",Vector3(.23,.045,.23),point+Vector3(0,2.06,-.35),"steel")
	_b("FacilityShowerArm",Vector3(.035,.035,.30),point+Vector3(0,2.09,-.49),"steel")
	_b("FacilityShowerDrain",Vector3(.25,.012,.25),point+Vector3(0,.025,.10),"steel")
	for line in range(4):_b("FacilityDrainSlot",Vector3(.18,.004,.016),point+Vector3(0,.034,.025+line*.05),"ink")
	_r("FacilityBathStool","cylinder",Vector3(.38,.25,.38),point+Vector3(.32,.13,-.31),"oak_light")
	_b("FacilityBathStoolSupport",Vector3(.25,.25,.25),point+Vector3(.32,.125,-.31),"oak_light",true)
	var y: float=kit._level*room.floor_height+.08
	facilities.back()["shower_point"]=Vector3(point.x,y,point.z+.20)
	if enclosure_built and back_built:
		_interaction("shower","샤워","shower",point+Vector3(0,.08,.20),point+Vector3(0,.08,1.35),point+Vector3(0,2.06,-.35),{"facing_yaw":0.0,"duration_seconds":7.0,"equipment_title":"Detail_FacilityShowerHead","water_radius":.28})

func _lockers(point: Vector3) -> void:
	if not _b("FacilityLockerBank",Vector3(2.25,1.85,.48),point+Vector3.UP*.925,"oak",true):return
	for i in range(5):
		_b("FacilityLockerDoor",Vector3(.41,1.70,.025),point+Vector3(-.88+i*.44,.94,.26),"oak_light")
		_b("FacilityLockerHandle",Vector3(.025,.12,.03),point+Vector3(-.76+i*.44,1.0,.29),"steel")
	for i in range(3):_b("FacilityFoldedTowel",Vector3(.35,.065,.26),point+Vector3(-.56+i*.55,1.92,0),"towel")

func _banquet() -> void:
	var zone := _zone("banquet","연회 · 행사 · 비즈니스",1.0,7.8)
	if zone.is_empty():return
	for i in range(2):_dining_table(Vector3(zone.center.x,0,zone.front-2.8-i*3.0),2.0)
	var left := _zone("business_lounge","비즈니스 라운지",-1.0,6.4)
	if not left.is_empty():_computer(Vector3(left.center.x,0,left.front-3.2),"FacilityBusinessDesk")
	kit._feature("banquet_dining_and_business")

func _classroom(programme_id: String) -> void:
	var zone := _zone("classroom","시민 강의실" if programme_id=="civic_classroom" else "교육 · 세미나",1.0,7.8)
	if zone.is_empty():return
	var x: float=zone.center.x
	var z: float=zone.front
	var desk_width := minf(2.2,float(zone.width)-1.15)
	var desk_x: float=zone.outer-desk_width*.5-.18
	for row in range(3):
		if kit._desk(Vector3(desk_x,0,z-2.4-row*1.65),"FacilityLectureDesk","oak",desk_width):
			kit._chair(Vector3(desk_x,0,z-1.47-row*1.65),"navy")
	_b("FacilityLectureScreen",Vector3(minf(2.7,float(zone.width)-.3),1.35,.055),Vector3(x,1.76,zone.back+.08),"paper")
	_b("FacilityProjector",Vector3(.30,.15,.27),Vector3(x,room.floor_height-.24,z-3.0),"paper")
	_label("FacilityLectureScreenText","오늘의 배움\n함께 생각하고 나누는 공간",Vector3(x,1.76,zone.back+.12),minf(2.4,float(zone.width)-.4),23)
	if programme_id=="chapel_education":
		var left := _zone("community_table","모임 · 공동식탁",-1.0,6.4)
		if not left.is_empty():_dining_table(Vector3(left.center.x,0,left.front-3.0))
	kit._feature("lecture_desks_projector_screen")

func _laundry() -> void:
	var zone := _zone("laundry","공용 세탁실 · 세탁 / 건조",1.0,6.5)
	if zone.is_empty():return
	var x: float=zone.center.x
	var z: float=zone.front-3.0
	for i in range(2):
		var p := Vector3(zone.outer-.58,0,z-i*1.45)
		if not _b("FacilityWasher",Vector3(.88,1.0,.82),p+Vector3.UP*.50,"paper",true):continue
		_r("FacilityWasherDoor","cylinder",Vector3(.56,.08,.56),p+Vector3(0,.49,.46),"steel",Basis(Vector3.RIGHT,PI*.5))
		_r("FacilityWasherGlass","cylinder",Vector3(.40,.012,.40),p+Vector3(0,.49,.51),"screen",Basis(Vector3.RIGHT,PI*.5))
		_b("FacilityLaundryDisplay",Vector3(.34,.13,.025),p+Vector3(.10,.87,.43),"ink")
	kit._desk(Vector3(zone.outer-.95,0,z-2.4),"FacilityLaundryFoldTable","oak",1.4)
	for i in range(3):_b("FacilityLaundryTowel",Vector3(.30,.08,.30),Vector3(zone.outer-1.30+i*.36,.86,z-2.4),"towel")
	kit._feature("washing_machines_and_folding")

func _community_kitchen() -> void:
	var zone := _zone("kitchen","공유 주방 · 함께 요리해요",1.0,7.2)
	if zone.is_empty():return
	_kitchen_counter(Vector3(zone.center.x,0,zone.front-4.4))
	var left := _zone("residents_table","주민 식탁 · 소통",-1.0,6.4)
	if not left.is_empty():_dining_table(Vector3(left.center.x,0,left.front-3.0),2.0)
	kit._feature("residential_shared_kitchen")

func _workshop() -> void:
	var zone := _zone("workshop","창작 작업실 · 도시를 그리다",1.0,7.4)
	if zone.is_empty():return
	for i in range(2):
		var p := Vector3(zone.center.x,0,zone.front-2.7-i*2.6)
		if not kit._desk(p,"FacilityStudioTable","oak",minf(2.1,float(zone.width)-.6)):continue
		_b("FacilityArtPaper",Vector3(.65,.012,.48),p+Vector3(0,.84,0),"paper")
		for n in range(3):_r("FacilityPaintPot","cylinder",Vector3(.095,.10,.095),p+Vector3(-.43+n*.20,.89,-.28),["terracotta","seoul_teal","brass"][n])
		_b("FacilityEaselBoard",Vector3(.82,1.10,.055),p+Vector3(0,1.49,-.48),"oak_light")
		_b("FacilityEaselCanvas",Vector3(.67,.79,.025),p+Vector3(0,1.56,-.43),"paper")
		for mark in range(3):_b("FacilityPaintStroke",Vector3(.11,.30,.015),p+Vector3(-.18+mark*.19,1.50+mark*.08,-.408),["terracotta","sage","seoul_teal"][mark])
	kit._feature("art_studio_easels_paint_worktables")

func _lounge(programme_id: String) -> void:
	var zone := _zone("staff_lounge" if programme_id=="bank_staff_lounge" else "art_lounge","직원 휴게 · 공용 식탁" if programme_id=="bank_staff_lounge" else "아트 라운지 · 자료열람",1.0,7.2)
	if zone.is_empty():return
	kit._sofa(Vector3(zone.center.x,0,zone.front-3.2),"linen")
	kit._pantry(Vector3(zone.center.x,0,zone.front-5.6))
	if programme_id=="bank_staff_lounge":_lockers(Vector3(kit._core_left(),0,zone.front-3.8))
	else:kit._display_case(Vector3(kit._core_left(),0,zone.front-3.0),"전시 도록 · 도시의 기록",kit._level)
	kit._feature("purpose_specific_lounge")

func _computer(point: Vector3,title: String) -> void:
	if not kit._desk(point,title,"oak",1.9):return
	kit._chair(point+Vector3(0,0,1.05),"navy")
	_b("FacilityComputerMonitor",Vector3(.72,.44,.07),point+Vector3(0,1.12,-.20),"ink")
	_b("FacilityComputerDisplay",Vector3(.63,.34,.018),point+Vector3(0,1.12,-.15),"screen")
	_b("FacilityComputerKeyboard",Vector3(.45,.025,.15),point+Vector3(0,.84,.20),"dark")

func snapshot() -> Array[Dictionary]:return facilities.duplicate(true)
