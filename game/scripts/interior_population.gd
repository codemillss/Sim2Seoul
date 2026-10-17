extends Node3D
## Small authored role scenes on the occupied floor. No new collision bodies,
## source changes, doorway occupancy or identical four-person circulation loop.
var room: Node3D
var level := -1
var programme := ""
var people: Array[Node3D]=[]
var records: Array[Dictionary]=[]
var elapsed := 0.0
var rejected_candidates := 0
var _solids: Array[AABB]=[]
var _occupied: Array[AABB]=[]
var _materials: Dictionary={}

func setup(owner_room: Node3D) -> void:
	room=owner_room;name="InteriorPopulation";process_mode=Node.PROCESS_MODE_PAUSABLE
	activate_floor(room.active_floor)

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new();material.albedo_color=color;material.roughness=.86;_materials[key]=material
	return _materials[key]

func _box(parent: Node3D,title: String,size: Vector3,point: Vector3,color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new();node.name=title;var mesh := BoxMesh.new();mesh.size=size;node.mesh=mesh;node.material_override=_material(color);node.position=point;node.set_meta("population_part",title);parent.add_child(node);return node

func _body_bounds(body: StaticBody3D) -> AABB:
	for child in body.get_children():
		if not child is CollisionShape3D:continue
		var bounds := AABB()
		if child.shape is BoxShape3D:bounds=AABB(-child.shape.size*.5,child.shape.size)
		elif child.shape is ConvexPolygonShape3D:
			var points: PackedVector3Array=child.shape.points
			if points.is_empty():continue
			bounds=AABB(points[0],Vector3.ZERO)
			for point in points:bounds=bounds.expand(point)
		else:continue
		return body.transform*child.transform*bounds
	return AABB()

func _cache_floor() -> void:
	_solids.clear();_occupied.clear()
	var low: float=level*room.floor_height+.035;var high: float=low+1.72
	for body: StaticBody3D in room.bodies:
		var bounds := _body_bounds(body)
		if bounds.has_volume() and bounds.end.y>low and bounds.position.y<high:_solids.append(bounds)

func _protected(point: Vector3,half_width := .26,half_depth := .34) -> bool:
	var box := AABB(Vector3(point.x-half_width,-.1,point.z-half_depth),Vector3(half_width*2.0,room.floor_height+.2,half_depth*2.0))
	if box.position.x<-room.width*.5+.4 or box.end.x>room.width*.5-.4 or box.position.z<-room.depth*.5+.4 or box.end.z>room.depth*.5-.4:return true
	for reserved: AABB in room.detail_kit.protected_zones:
		if reserved.intersects(box):return true
	if is_instance_valid(room.escalator) and level in [0,1] and room.escalator.reservation.intersects(box):return true
	var y: float=level*room.floor_height+.08
	for point_reserved in [room.to_local(room.floor_spawn(level)),room.to_local(room.elevator_point(level))]:
		if Vector2(point.x-point_reserved.x,point.z-point_reserved.z).length()<1.35:return true
	for door: Dictionary in room.guest_doors:
		if int(door.level)!=level:continue
		for key in ["outside_point","inside_point","door_point"]:
			var entry: Vector3=door[key]
			if Vector2(point.x-entry.x,point.z-entry.z).length()<1.02:return true
	for target: Dictionary in room.detail_kit.facility_kit.interactions:
		if int(target.level)!=level:continue
		for key in ["use_point","approach_point"]:
			var use: Vector3=target[key]
			if Vector2(point.x-use.x,point.z-use.z).length()<1.05:return true
	return false

func _clear(point: Vector3,prop := "") -> bool:
	var half_depth := .65 if prop in ["cart","suitcase"] else .32
	if _protected(point,.25,half_depth):return false
	var box := AABB(Vector3(point.x-.25,level*room.floor_height+.035,point.z-half_depth),Vector3(.50,1.67,half_depth*2.0))
	for solid: AABB in _solids:
		if solid.intersects(box):return false
	for old: AABB in _occupied:
		if old.grow(.16).intersects(box):return false
	return true

func _find_spot(preferred: Vector3,prop := "") -> Vector3:
	var candidates: Array[Vector3]=[preferred]
	for x in [-2.2,2.25,-3.15,3.15,-4.0,4.0,-5.4,5.4]:
		for from_front in [6.0,8.0,10.0,12.0,14.0,17.0,20.0,24.0,28.0]:candidates.append(Vector3(float(x),0,room.depth*.5-float(from_front)))
	candidates.sort_custom(func(a: Vector3,b: Vector3)->bool:return a.distance_squared_to(preferred)<b.distance_squared_to(preferred))
	for candidate: Vector3 in candidates:
		if _clear(candidate,prop):return candidate
		rejected_candidates+=1
	return Vector3.INF

func _placement(title: String) -> Dictionary:
	for row: Dictionary in room.detail_kit.placements:
		if int(row.level)==level and String(row.title)=="Detail_"+title:return row
	return {}

func _preferred_from(title: String,offset: Vector3,fallback: Vector3) -> Vector3:
	var row := _placement(title)
	if row.is_empty():return fallback
	var point: Vector3=row.position;point.y=0.0;return point+offset

func activate_floor(next: int) -> void:
	if next==level:return
	for person: Node3D in people:
		remove_child(person);person.queue_free()
	people.clear();records.clear();room.people.clear();level=next
	programme=String(room.detail_kit.level_profiles[level].profile_id);_cache_floor()
	var front: float=room.depth*.5
	var profile: String=room.detail_kit.profile_id
	if "fitness" in programme:
		_add_standing("gym_stretch","스트레칭","stretch","towel",Color(.84,.36,.18),Vector3(2.3,0,front-9.8),false)
		if not _add_seated("gym_rest","휴식 · 물 마시기","water",Color(.24,.57,.59),"FacilityWeightBench"):_add_standing("gym_rest","휴식","rest","water",Color(.24,.57,.59),Vector3(-2.2,0,front-9.0),false)
	elif profile=="hotel" and level==0:
		_add_standing("hotel_reception","프런트 직원","service","badge",Color(.15,.22,.34),_preferred_from("HotelReception",Vector3(.65,0,-.76),Vector3(3.2,0,front-8.0)),false,PI)
		_add_standing("hotel_traveller","체크인 손님","walk","suitcase",Color(.63,.39,.23),Vector3(-2.2,0,front-8.2),true)
		_add_standing("hotel_concierge","안내 직원","service","clipboard",Color(.20,.29,.38),Vector3(2.25,0,front-11.8),false)
	elif profile=="hotel" and programme=="hotel_guest":
		_add_standing("hotel_housekeeper","객실 정리 직원","service","cart",Color(.19,.57,.62),Vector3(2.2,0,front-8.0),false)
		_add_standing("hotel_guest","투숙객","walk","suitcase",Color(.64,.54,.37),Vector3(-2.2,0,front-8.0),true)
	elif profile=="library":
		_add_seated("library_reader","독서","book",Color(.34,.43,.32),"ChairSeat")
		_add_standing("library_browser","자료 찾기","walk","book",Color(.43,.35,.52),_preferred_from("ShelfBack",Vector3(-1.0,0,0),Vector3(2.4,0,front-11.0)),true)
		_add_standing("library_staff","자료 안내","service","clipboard",Color(.24,.42,.47),_preferred_from("LibraryReception",Vector3(.65,0,-.76),Vector3(-2.2,0,front-7.8)),false,PI)
	elif profile=="office":
		_add_seated("office_worker","업무 중","laptop",Color(.22,.34,.46),"ChairSeat")
		_add_standing("office_colleague","동료와 이동","walk","briefcase",Color(.38,.38,.42),Vector3(-2.2,0,front-10),true)
		_add_standing("office_staff","업무 확인","read","clipboard",Color(.46,.39,.33),Vector3(2.25,0,front-8),false)
	elif profile=="chapel" and level==0:
		_add_seated("chapel_worshipper","조용한 묵상","book",Color(.26,.28,.36),"ChapelPew")
		_add_standing("chapel_guide","예배 안내","service","book",Color(.42,.36,.29),Vector3(-2.2,0,front-8),false)
	else:
		_add_standing(profile+"_visitor","방문객","walk","bag",Color(.41,.44,.36),Vector3(-2.2,0,front-9),true)
		_add_standing(profile+"_staff","공간 안내","service","clipboard",Color(.28,.42,.46),Vector3(2.25,0,front-8),false)
	# A compact floor can reject a seat or prop footprint. Use a distinct free
	# standing role rather than forcing any model into an occupied room.
	if people.size()<2:_add_standing(profile+"_quiet_visitor","잠시 머무는 방문객","read","book",Color(.49,.40,.29),Vector3(-2.2,0,front-14),false)
	step(0.0)

func _add_standing(role: String,title: String,action: String,prop: String,coat: Color,preferred: Vector3,moving: bool,yaw := 0.0) -> bool:
	var point := _find_spot(preferred,prop)
	if not point.is_finite():return false
	var end := point
	if moving:
		for offset in [1.05,-1.05,.65,-.65]:
			var candidate := point+Vector3(0,0,float(offset));var clear := true
			for index in range(9):
				if not _clear(point.lerp(candidate,float(index)/8.0),prop):clear=false;break
			if clear:end=candidate;break
	var actor := _model(role,title,action,prop,coat,false)
	actor.position=point+Vector3.UP*(level*room.floor_height+.02);actor.rotation.y=yaw
	var envelope := AABB(Vector3(point.x-.25,level*room.floor_height+.035,minf(point.z,end.z)-.65),Vector3(.50,1.67,absf(end.z-point.z)+1.30));_occupied.append(envelope)
	records.append({"node":actor,"role":role,"title":title,"action":action,"prop":prop,"start":point,"end":end,"phase":0.0,"seated":false,"yaw":yaw,"envelope":envelope,"level":level,"programme":programme})
	return true

func _add_seated(role: String,title: String,prop: String,coat: Color,seat_title: String) -> bool:
	var seat := _placement(seat_title)
	if seat.is_empty():return false
	var point: Vector3=seat.position;point.y=0
	if _protected(point,.25,.42):return false
	for old: AABB in _occupied:
		if old.grow(.15).has_point(point+Vector3.UP*(level*room.floor_height+.6)):return false
	var actor := _model(role,title,"read",prop,coat,true);actor.position=point+Vector3.UP*(level*room.floor_height+.02)
	var envelope := AABB(Vector3(point.x-.26,level*room.floor_height+.03,point.z-.48),Vector3(.52,1.35,.75));_occupied.append(envelope)
	records.append({"node":actor,"role":role,"title":title,"action":"read","prop":prop,"start":point,"end":point,"phase":0.0,"seated":true,"yaw":0.0,"envelope":envelope,"level":level,"programme":programme,"seat_geometry":seat.title})
	return true

func _model(role: String,title: String,action: String,prop: String,coat: Color,seated: bool) -> Node3D:
	var actor := Node3D.new();actor.name="Role_"+role;actor.set_meta("interior_role",role);actor.set_meta("floor_programme",programme);actor.set_meta("level",level);add_child(actor);people.append(actor);room.people.append(actor)
	var hip := .55 if seated else .82
	var skin := Color(.73,.51,.35) if people.size()%2 else Color(.88,.68,.49)
	_box(actor,"RoleTorso",Vector3(.38,.50,.24),Vector3(0,hip+.29,0),coat)
	_box(actor,"RoleHead",Vector3(.24,.27,.23),Vector3(0,hip+.69,0),skin)
	_box(actor,"RoleHair",Vector3(.25,.085,.24),Vector3(0,hip+.81,0),Color(.11,.095,.08))
	for side in [-1.0,1.0]:
		if seated:
			_box(actor,"SeatedThigh",Vector3(.14,.14,.37),Vector3(side*.105,.53,-.16),Color(.20,.24,.28))
			_box(actor,"SeatedShin",Vector3(.13,.38,.14),Vector3(side*.105,.29,-.34),Color(.20,.24,.28))
			_box(actor,"RoleShoe",Vector3(.16,.10,.27),Vector3(side*.105,.07,-.41),Color(.12,.14,.15))
		else:
			var leg := Node3D.new();leg.name="LegLeft" if side<0 else "LegRight";leg.position=Vector3(side*.105,.76,0);actor.add_child(leg)
			if action=="stretch":
				_box(leg,"SportShorts",Vector3(.15,.31,.18),Vector3(0,-.155,0),Color(.22,.25,.28))
				_box(leg,"BareSportCalf",Vector3(.115,.34,.13),Vector3(0,-.49,0),skin)
			else:_box(leg,"RoleTrouser",Vector3(.14,.66,.17),Vector3(0,-.33,0),Color(.22,.25,.28))
			_box(leg,"RoleShoe",Vector3(.16,.10,.27),Vector3(0,-.70,-.04),Color(.86,.86,.81) if "gym" in role else Color(.12,.14,.15))
		var arm := Node3D.new();arm.name="ArmLeft" if side<0 else "ArmRight";arm.position=Vector3(side*.245,hip+.48,0);actor.add_child(arm)
		_box(arm,"RoleSleeve",Vector3(.12,.47,.14),Vector3(0,-.235,0),coat);_box(arm,"RoleHand",Vector3(.105,.10,.10),Vector3(0,-.50,0),skin)
	if prop in ["book","clipboard","laptop"]:
		var held := Node3D.new();held.name="RoleProp";actor.add_child(held);held.position=Vector3(0,hip+.20,-.34)
		_box(held,"OpenBook" if prop=="book" else "Clipboard" if prop=="clipboard" else "LaptopKeyboard",Vector3(.35,.025,.26),Vector3.ZERO,Color(.87,.83,.64) if prop=="book" else Color(.24,.29,.32))
		if prop=="book":_box(held,"BookPages",Vector3(.31,.018,.23),Vector3(0,.02,0),Color(.95,.94,.86))
		if prop=="laptop":_box(held,"LaptopScreen",Vector3(.35,.23,.025),Vector3(0,.12,-.12),Color(.15,.35,.42))
	elif prop=="cart":
		_box(actor,"CleaningApron",Vector3(.32,.45,.025),Vector3(0,1.05,-.135),Color(.85,.88,.83))
		_box(actor,"CleaningCart",Vector3(.41,.61,.44),Vector3(0,.37,.43),Color(.32,.53,.57))
		for i in range(3):_box(actor,"FoldedCleaningTowel",Vector3(.34,.055,.32),Vector3(0,.72+i*.06,.43),Color(.89,.89,.80))
		for side in [-1.0,1.0]:_box(actor,"CartWheel",Vector3(.07,.12,.09),Vector3(side*.16,.07,.43),Color(.12,.16,.17))
	elif prop in ["suitcase","briefcase","bag"]:
		_box(actor,"Suitcase" if prop=="suitcase" else "Briefcase",Vector3(.35,.44,.23),Vector3(0,.27,.43),Color(.77,.55,.19) if prop=="suitcase" else Color(.31,.23,.19))
		if prop=="suitcase":_box(actor,"LuggagePullHandle",Vector3(.025,.45,.025),Vector3(0,.70,.43),Color(.58,.64,.65))
		else:_box(actor,"BriefcaseHandle",Vector3(.15,.07,.025),Vector3(0,.54,.43),Color(.52,.45,.35))
	elif prop=="towel":_box(actor,"SportsTowel",Vector3(.32,.07,.035),Vector3(0,1.27,-.15),Color(.91,.91,.85))
	elif prop=="water":_box(actor,"WaterBottle",Vector3(.085,.24,.085),Vector3(.22,hip+.16,-.22),Color(.32,.72,.81))
	if prop=="badge":_box(actor,"ReceptionBadge",Vector3(.11,.09,.025),Vector3(.10,1.18,-.14),Color(.82,.68,.37))
	var label := Label3D.new();label.name="RoleHint";label.text=title;label.font_size=19;label.pixel_size=.0026;label.position=Vector3(0,hip+1.02,0);label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.modulate=Color(.91,.91,.79);label.outline_size=3;label.visibility_range_end=11;actor.add_child(label)
	return actor

func step(delta: float) -> void:
	elapsed+=maxf(0.0,delta)
	for row: Dictionary in records:
		var actor: Node3D=row.node;var action := String(row.action)
		if action=="walk" and (row.start as Vector3).distance_to(row.end)>.05:
			row.phase=float(row.phase)+maxf(0.0,delta)*.45
			var length: float=(row.start as Vector3).distance_to(row.end);var cycle := fposmod(float(row.phase),length*2.0)
			var t := cycle/length if cycle<=length else 2.0-cycle/length
			actor.position=(row.start as Vector3).lerp(row.end,t)+Vector3.UP*(level*room.floor_height+.02)
			var forward: Vector3=(row.end as Vector3)-row.start
			if cycle>length:forward=-forward
			actor.rotation.y=atan2(-forward.x,-forward.z)
		for side_name in ["Left","Right"]:
			var side := -1.0 if side_name=="Left" else 1.0
			var arm: Node3D=actor.get_node_or_null("Arm"+side_name)
			var leg: Node3D=actor.get_node_or_null("Leg"+side_name)
			var swing := sin(elapsed*4.5+side*PI*.5)*.28
			if is_instance_valid(leg):leg.rotation.x=swing if action=="walk" else 0.0
			if is_instance_valid(arm):
				if action=="stretch":arm.rotation=Vector3(-.32,0,side*(1.15+sin(elapsed*1.8)*.20))
				elif row.prop in ["book","clipboard","laptop"]:arm.rotation=Vector3(-.85+sin(elapsed*.9)*.035,0,side*.06)
				else:arm.rotation=Vector3(-swing*.7 if action=="walk" else -.10,0,side*.025)

func snapshot() -> Dictionary:
	var rows: Array=[]
	for row: Dictionary in records:
		var actor: Node3D=row.node
		rows.append({"role":row.role,"title":row.title,"action":row.action,"prop":row.prop,"seated":row.seated,"level":row.level,"programme":row.programme,"position":actor.position,"start":row.start,"end":row.end,"envelope":row.envelope,"seat_geometry":row.get("seat_geometry",""),"visible":actor.is_visible_in_tree(),"part_count":actor.get_child_count()})
	return {"floor":level,"programme":programme,"count":people.size(),"roles":rows,"rejected_candidates":rejected_candidates,"new_collision_bodies":0,"authored_not_surveyed":true}
