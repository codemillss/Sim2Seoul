extends Node3D
## Bounded, source-route-linked street details. Parking, people, birds and lamp
## placements are authored game additions, never surveyed access/event claims.
const DESIGN_PATH := "res://assets/authored/street_life.json"
var loaded := false
var load_error := ""
var city: Node3D
var player: CharacterBody3D
var rig: Node3D
var bodies: Array[StaticBody3D] = []
var anchors: Array[Dictionary] = []
var skipped: Array[Dictionary] = []
var birds: Array[Dictionary] = []
var performers: Array[Dictionary] = []
var lamps: Array[Dictionary] = []
var time_profile := "day"
var quality_id := "standard"
var elapsed := 0.0
var _light_elapsed := 0.0
var _design := {}
var _line: Array[Vector3] = []
var _arc: Array[float] = []
var _walk_routes: Array = []
var _drive_routes: Array = []
var _doors: Array[Vector3] = []
var _materials := {}
var _owned_bounds: Array[Dictionary] = []

func setup(source_city: Node3D, controlled_player: CharacterBody3D, camera_rig: Node3D) -> bool:
	if loaded or not is_instance_valid(source_city) or not is_instance_valid(controlled_player):return false
	city=source_city;player=controlled_player;rig=camera_rig;name="StreetLife";process_mode=Node.PROCESS_MODE_PAUSABLE
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(DESIGN_PATH))
	if not parsed is Dictionary or parsed.get("schema_version")!=1:return _fail("거리 생활 배치 자료를 읽지 못했습니다.")
	_design=parsed
	var data: Variant=city.get("public_data")
	if not data is Dictionary:return _fail("돌담길의 기존 보행 자료가 없습니다.")
	_walk_routes=data.get("routes",[])
	for route: Dictionary in _walk_routes:
		if String(route.id)!=String(_design.source_route.id):continue
		for index in range(int(_design.source_route.first_vertex),mini(route.xz.size(),int(_design.source_route.last_vertex)+1)):
			var point: Array=route.xz[index];_line.append(city.to_global(Vector3(float(point[0]),0,float(point[1]))))
	if _line.size()<2:return _fail("돌담길 기준 선분이 없습니다.")
	_arc.append(0.)
	for index in range(1,_line.size()):_arc.append(_arc.back()+_line[index].distance_to(_line[index-1]))
	var traffic: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/traffic.json"))
	if traffic is Dictionary:_drive_routes=traffic.get("routes",[])
	_collect_doors();_make_materials()
	_build_vehicles();_build_busker();_build_birds();_build_lamps()
	loaded=true;set_time_profile("day")
	print("STREET_LIFE_READY placed=",anchors.size()," birds=",birds.size()," people=",performers.size()," lamps=",lamps.size()," authored=true")
	return true

func _fail(message: String) -> bool:load_error=message;return false

func _collect_doors() -> void:
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/interiors/source_catalog.json"))
	if raw is Dictionary:
		for record: Dictionary in raw.get("records",[]):
			for entry: Dictionary in record.get("entry_candidates",[]):
				for key in ["entrance","door"]:
					var point: Array=entry.get(key,[])
					if point.size()==2:_doors.append(city.to_global(Vector3(float(point[0]),0,float(point[1]))))
	var host: Node=city.get_parent()
	var visit: Variant=host.get("interior_visit")
	if is_instance_valid(visit):
		for record: Dictionary in visit.catalog:_doors.append(record.entrance)
	var civic: Variant=host.get("photo_civic_detail")
	if is_instance_valid(civic):_doors.append(civic.entrance_world_position)

func _material(key: String,color: Color,roughness := .8) -> void:
	var value:=StandardMaterial3D.new();value.albedo_color=color;value.roughness=roughness
	_materials[key]=value

func _make_materials() -> void:
	for row in [["silver",Color(.64,.69,.71)],["cream",Color(.87,.86,.80)],["blue",Color(.20,.35,.42)],["steel",Color(.15,.20,.23)],["tire",Color(.045,.052,.058)],["glass",Color(.12,.22,.26)],["lamp",Color(.88,.83,.66)],["lamp_glow",Color(.88,.83,.66)],["skin",Color(.76,.55,.39)],["trousers",Color(.22,.27,.30)],["jacket",Color(.26,.39,.43)],["coat",Color(.49,.35,.25)],["hair",Color(.12,.10,.08)],["guitar",Color(.61,.34,.14)],["bird",Color(.37,.41,.44)],["bird_neck",Color(.26,.40,.38)],["beak",Color(.63,.45,.26)],["eye",Color(.025,.03,.035)]]:_material(row[0],row[1])

func _mesh(parent: Node3D,title: String,mesh: Mesh,point: Vector3,material: String) -> MeshInstance3D:
	var result:=MeshInstance3D.new();result.name=title;result.mesh=mesh;result.position=point;result.material_override=_materials[material]
	result.set_meta("street_life_part",title);parent.add_child(result);return result

func _box(parent: Node3D,title: String,size: Vector3,point: Vector3,material: String) -> MeshInstance3D:
	var mesh:=BoxMesh.new();mesh.size=size;return _mesh(parent,title,mesh,point,material)

func _round(parent: Node3D,title: String,size: Vector3,point: Vector3,material: String) -> MeshInstance3D:
	var mesh:=SphereMesh.new();mesh.radius=.5;mesh.height=1.;mesh.radial_segments=12;mesh.rings=6
	var result:=_mesh(parent,title,mesh,point,material);result.scale=size;return result

func _cylinder(parent: Node3D,title: String,radius: float,height: float,point: Vector3,material: String) -> MeshInstance3D:
	var mesh:=CylinderMesh.new();mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=height;mesh.radial_segments=12
	return _mesh(parent,title,mesh,point,material)

func _route_point(station: float) -> Dictionary:
	var s:=clampf(station,0.,_arc.back())
	for index in range(1,_line.size()):
		if s>_arc[index] and index<_line.size()-1:continue
		var tangent: Vector3=(_line[index]-_line[index-1]).normalized()
		var at: Vector3=_line[index-1]+tangent*(s-_arc[index-1])
		return {"point":at,"tangent":tangent,"roadside":Vector3(tangent.z,0,-tangent.x),"station_m":s,"segment":index-1}
	return {}

func _distance_to_routes(point: Vector3,routes: Array) -> float:
	var best:=INF;var flat:=Vector2(point.x,point.z)
	for route: Dictionary in routes:
		var points: Array=route.get("xz",[])
		for index in range(1,points.size()):
			var a: Vector3=city.to_global(Vector3(float(points[index-1][0]),0,float(points[index-1][1])))
			var b: Vector3=city.to_global(Vector3(float(points[index][0]),0,float(points[index][1])))
			best=minf(best,flat.distance_to(Geometry2D.get_closest_point_to_segment(flat,Vector2(a.x,a.z),Vector2(b.x,b.z))))
	return best

func _protected(point: Vector3,radius: float) -> Dictionary:
	var result:={"walk_distance_m":_distance_to_routes(point,_walk_routes),"traffic_distance_m":_distance_to_routes(point,_drive_routes),"entrance_distance_m":INF}
	for door in _doors:result.entrance_distance_m=minf(result.entrance_distance_m,Vector2(point.x-door.x,point.z-door.z).length())
	result["clear"]=result.walk_distance_m>=radius+float(_design.protection.walking_corridor_width_m)*.5+float(_design.protection.extra_margin_m) and result.traffic_distance_m>=radius+float(_design.protection.moving_vehicle_radius_margin_m) and result.entrance_distance_m>=radius+float(_design.protection.door_clearance_m)
	return result

func _ground(point: Vector3) -> Dictionary:
	var flat:=Vector2(point.x,point.z)
	if not player.free_roam_bounds.grow(-.5).has_point(flat):return {}
	if city.has_method("_contains") and city._contains(flat,city.private_cache):return {}
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*3.,point-Vector3.UP*5.,1|32)
	var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y<.85 or absf(hit.position.y-point.y)>.65:return {}
	return {"point":Vector3(point.x,hit.position.y+.035,point.z),"source":String(hit.collider.get_meta("geometry_id",hit.collider.name))}

func _volume_clear(frame: Transform3D,size: Vector3) -> bool:
	var shape:=BoxShape3D.new();shape.size=size
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.collision_mask=1|32;query.margin=.01
	query.transform=Transform3D(frame.basis,frame.origin+Vector3.UP*size.y*.5)
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _placement(id: String,kind: String,at: Vector3,tangent: Vector3,size: Vector3,solid := true) -> Node3D:
	var radius:=Vector2(size.x,size.z).length()*.5
	var protection:=_protected(at,radius)
	if not protection.clear:skipped.append({"id":id,"kind":kind,"reason":"protected_walk_traffic_or_entrance","point":at,"protection":protection});return null
	var ground:=_ground(at)
	if ground.is_empty():skipped.append({"id":id,"kind":kind,"reason":"unsupported_or_private","point":at});return null
	var yaw:=atan2(-tangent.x,-tangent.z)
	var frame:=Transform3D(Basis(Vector3.UP,yaw),ground.point)
	var extent: AABB=frame*AABB(Vector3(-size.x*.5,0,-size.z*.5),size)
	for other: Dictionary in _owned_bounds:
		if extent.grow(.08).intersects(other.bounds):skipped.append({"id":id,"kind":kind,"reason":"owned_prop_overlap","other_id":other.id});return null
	if not _volume_clear(frame,size):skipped.append({"id":id,"kind":kind,"reason":"occupied_volume","point":at});return null
	# Check the standing capsule and all four footprint supports independently.
	var capsule: CollisionShape3D=player.get_node("CollisionShape")
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule.shape;query.collision_mask=1|32;query.transform=Transform3D(Basis.IDENTITY,frame.origin)*capsule.transform
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():skipped.append({"id":id,"reason":"standing_capsule_occupied"});return null
	for x in [-.45,.45]:
		for z in [-.45,.45]:
			var support:=_ground(frame*Vector3(x*size.x,0,z*size.z))
			if support.is_empty() or absf(support.point.y-frame.origin.y)>.18:skipped.append({"id":id,"reason":"footprint_support"});return null
	var actor:=Node3D.new();actor.name=id;add_child(actor);actor.global_transform=frame
	actor.set_meta("street_life_kind",kind);actor.set_meta("authored_game_placement",true)
	if solid:
		var body:=StaticBody3D.new();body.name="OwnedPropCollision";body.collision_layer=1;body.collision_mask=0;body.position.y=size.y*.5
		body.set_meta("geometry_id","street_life/"+id)
		var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape;body.add_child(collision);actor.add_child(body);bodies.append(body)
	anchors.append({"id":id,"kind":kind,"source_route":_design.source_route.id,"frame":frame,"size_m":size,"support":ground.source,"protection":protection,"solid":solid,"authored":true})
	_owned_bounds.append({"id":id,"bounds":extent})
	return actor

func _build_vehicles() -> void:
	for kind in ["parked_cars","motorcycles"]:
		var recipe: Dictionary=_design[kind]
		for index in range(recipe.fractions.size()):
			var basis:=_route_point(float(recipe.fractions[index])*_arc.back())
			var at: Vector3=basis.point+basis.roadside*float(recipe.roadside_offset_m)
			var raw: Array=recipe.size_m;var size:=Vector3(raw[0],raw[1],raw[2])
			var actor:=_placement(("ParkedCar" if kind=="parked_cars" else "Motorcycle")+str(index),kind,at,basis.tangent,size)
			if actor==null:continue
			if kind=="parked_cars":_car(actor,["silver","cream","blue"][index%3])
			else:_motorcycle(actor,["blue","steel","cream"][index%3])

func _car(root_node: Node3D,paint: String) -> void:
	_box(root_node,"CarBody",Vector3(1.76,.54,4.08),Vector3(0,.60,0),paint)
	_box(root_node,"CarWindows",Vector3(1.48,.58,1.92),Vector3(0,1.12,-.05),"glass")
	_box(root_node,"CarRoof",Vector3(1.50,.10,1.94),Vector3(0,1.44,-.05),paint)
	for side in [-1.,1.]:
		_box(root_node,"Headlight",Vector3(.46,.15,.035),Vector3(side*.56,.66,-2.058),"lamp")
		_box(root_node,"Mirror",Vector3(.15,.10,.22),Vector3(side*.86,1.02,-.5),"steel")
		for axle in [-1.25,1.25]:
			var wheel:=_cylinder(root_node,"CarWheel",.31,.17,Vector3(side*.80,.32,axle),"tire");wheel.rotation.z=PI*.5

func _motorcycle(root_node: Node3D,paint: String) -> void:
	for z in [-.61,.61]:
		var wheel:=_cylinder(root_node,"MotorcycleWheel",.275,.14,Vector3(0,.28,z),"tire");wheel.rotation.z=PI*.5
		var hub:=_cylinder(root_node,"MotorcycleHub",.11,.15,Vector3(0,.28,z),"silver");hub.rotation.z=PI*.5
	_box(root_node,"MotorcycleEngine",Vector3(.34,.31,.60),Vector3(0,.48,.03),"steel")
	_round(root_node,"MotorcycleTank",Vector3(.43,.31,.55),Vector3(0,.76,-.17),paint)
	_box(root_node,"MotorcycleSeat",Vector3(.35,.09,.65),Vector3(0,.80,.28),"tire")
	for side in [-1.,1.]:_box(root_node,"MotorcycleFork",Vector3(.035,.60,.045),Vector3(side*.10,.53,-.61),"silver")
	_box(root_node,"MotorcycleHandlebar",Vector3(.61,.04,.055),Vector3(0,1.01,-.60),"steel")
	_round(root_node,"MotorcycleHeadlight",Vector3(.20,.18,.10),Vector3(0,.85,-.70),"lamp")
	_box(root_node,"MotorcycleExhaust",Vector3(.10,.09,.62),Vector3(.24,.35,.25),"silver")

func _person(root_node: Node3D,coat: String) -> Dictionary:
	_box(root_node,"PersonTorso",Vector3(.39,.48,.24),Vector3(0,1.13,0),coat)
	_round(root_node,"PersonHead",Vector3(.235,.28,.235),Vector3(0,1.52,0),"skin")
	_round(root_node,"PersonHair",Vector3(.245,.14,.245),Vector3(0,1.61,.01),"hair")
	var arms:=[];var forearms:=[]
	for side in [-1.,1.]:
		_box(root_node,"PersonLeg",Vector3(.13,.72,.14),Vector3(side*.105,.50,0),"trousers")
		_box(root_node,"PersonShoe",Vector3(.15,.10,.28),Vector3(side*.105,.09,-.06),"steel")
		var arm:=Node3D.new();arm.name="StrumArm" if side>0 else "NeckArm";arm.position=Vector3(side*.255,1.31,0);root_node.add_child(arm)
		_box(arm,"PersonSleeve",Vector3(.11,.26,.12),Vector3(0,-.13,0),coat)
		var forearm:=Node3D.new();forearm.name="PersonForearm";forearm.position=Vector3(0,-.26,0);arm.add_child(forearm)
		_box(forearm,"PersonLowerSleeve",Vector3(.10,.24,.11),Vector3(0,-.12,0),coat)
		_round(forearm,"PersonHand",Vector3(.09,.11,.09),Vector3(0,-.265,0),"skin");arms.append(arm);forearms.append(forearm)
	return {"actor":root_node,"arms":arms,"forearms":forearms}

func _hand_to(row: Dictionary,index: int,target: Vector3) -> void:
	var arm: Node3D=row.arms[index];var forearm: Node3D=row.forearms[index]
	var offset:=target-arm.position;var direction:=offset.normalized();var distance:=clampf(offset.length(),.06,.26+.265-.0002)
	var side: float=-1. if index==0 else 1.
	var pole:=Vector3(side*.8,-.3,.3);pole=(pole-direction*pole.dot(direction)).normalized()
	var along: float=(.26*.26-.265*.265+distance*distance)/(2.*distance)
	var elbow: Vector3=arm.position+direction*along+pole*sqrt(maxf(0.,.26*.26-along*along))
	var grip: Vector3=arm.position+direction*distance
	arm.basis=Basis(Quaternion(Vector3.DOWN,(elbow-arm.position).normalized()))
	forearm.basis=arm.basis.inverse()*Basis(Quaternion(Vector3.DOWN,(grip-elbow).normalized()))

func _build_busker() -> void:
	var recipe: Dictionary=_design.busker;var basis:=_route_point(float(recipe.fraction)*_arc.back())
	var at: Vector3=basis.point+basis.roadside*float(recipe.roadside_offset_m)
	var actor:=_placement("GuitarBusker","busker",at,basis.roadside,Vector3(1.8,1.7,1.0),false)
	if actor==null:return
	var person:=_person(actor,"jacket");person["kind"]="busker";performers.append(person)
	var guitar:=Node3D.new();guitar.name="Guitar";guitar.position=Vector3(.02,.99,-.24);guitar.rotation.z=deg_to_rad(25.);actor.add_child(guitar)
	_round(guitar,"GuitarLowerBody",Vector3(.39,.37,.13),Vector3(0,0,0),"guitar")
	_round(guitar,"GuitarUpperBody",Vector3(.29,.28,.13),Vector3(0,.20,0),"guitar")
	_round(guitar,"GuitarSoundHole",Vector3(.12,.12,.015),Vector3(0,.08,-.074),"tire")
	_box(guitar,"GuitarNeck",Vector3(.065,.53,.055),Vector3(0,.51,0),"hair")
	for index in range(6):_box(guitar,"GuitarString",Vector3(.002,.82,.002),Vector3(-.025+index*.01,.29,-.081),"silver")
	_box(actor,"BuskerSpeaker",Vector3(.40,.58,.30),Vector3(.67,.29,.04),"steel")
	for index in range(recipe.audience_offsets_m.size()):
		var raw: Array=recipe.audience_offsets_m[index]
		var point: Vector3=at+basis.tangent*float(raw[0])+basis.roadside*float(raw[1])
		var viewer:=_placement("Audience"+str(index),"audience",point,-basis.roadside,Vector3(.65,1.7,.55),false)
		if viewer==null:continue
		var row:=_person(viewer,"coat" if index%2==0 else "blue");row["kind"]="audience";performers.append(row)

func _bird(anchor: Vector3,tangent: Vector3,perched: bool,source: String) -> void:
	var bird:=Node3D.new();bird.name="Bird"+str(birds.size());add_child(bird);bird.global_position=anchor;bird.global_rotation.y=atan2(-tangent.x,-tangent.z)
	_round(bird,"BirdBody",Vector3(.18,.20,.31),Vector3(0,.15,0),"bird")
	var head:=Node3D.new();head.name="BirdHead";head.position=Vector3(0,.26,-.13);bird.add_child(head)
	_round(head,"BirdNeck",Vector3(.10,.14,.10),Vector3(0,-.035,.025),"bird_neck")
	_round(head,"BirdFace",Vector3(.11,.12,.13),Vector3.ZERO,"bird")
	_box(head,"BirdBeak",Vector3(.04,.035,.10),Vector3(0,-.01,-.09),"beak")
	for side in [-1.,1.]:_round(head,"BirdEye",Vector3(.015,.015,.015),Vector3(side*.052,.018,-.04),"eye")
	var wings:=[]
	for side in [-1.,1.]:
		var wing:=_box(bird,"BirdWing",Vector3(.055,.13,.25),Vector3(side*.09,.15,.03),"bird");wings.append(wing)
		_box(bird,"BirdFoot",Vector3(.025,.04,.07),Vector3(side*.045,.035,-.02),"beak")
	birds.append({"actor":bird,"anchor":anchor,"tangent":tangent,"perched":perched,"source":source,"head":head,"wings":wings,"state":"perch" if perched else "peck","phase":birds.size()*1.73})

func _build_birds() -> void:
	var recipe: Dictionary=_design.ground_birds
	for fraction in recipe.fractions:
		var basis:=_route_point(float(fraction)*_arc.back());var at: Vector3=basis.point+basis.roadside*float(recipe.roadside_offset_m)
		var root_node:=_placement("GroundBirdAnchor"+str(birds.size()),"ground_bird_anchor",at,basis.tangent,Vector3(.55,.45,.55),false)
		if root_node==null:continue
		var anchor: Vector3=root_node.global_position;root_node.queue_free();_bird(anchor,basis.tangent,false,"stonewall_route_offset")
	var wall: StaticBody3D=city.fragments.get(String(_design.source_wall))
	if wall==null:return
	var shape_node:=wall.get_node_or_null("CollisionShape") as CollisionShape3D
	if shape_node==null or not shape_node.shape is ConcavePolygonShape3D:return
	var vertices: PackedVector3Array=shape_node.shape.get_faces();var edges:={}
	for index in range(0,vertices.size(),3):
		var tri: Array[Vector3]=[vertices[index],vertices[index+1],vertices[index+2]]
		if not is_equal_approx(tri[0].y,2.) or not is_equal_approx(tri[1].y,2.) or not is_equal_approx(tri[2].y,2.):continue
		for side in range(3):
			var a: Vector3=tri[side];var b: Vector3=tri[(side+1)%3]
			var ka:="%.4f,%.4f"%[a.x,a.z];var kb:="%.4f,%.4f"%[b.x,b.z];var key:=ka+":"+kb if ka<kb else kb+":"+ka
			if not edges.has(key):edges[key]={"count":0,"a":a,"b":b,"centre":(tri[0]+tri[1]+tri[2])/3.}
			edges[key].count+=1
	var count:=0;var used:=[]
	for edge: Dictionary in edges.values():
		if edge.count!=1 or edge.a.distance_to(edge.b)<12.:continue
		var tangent: Vector3=(edge.b-edge.a).normalized();var inward:=Vector3(-tangent.z,0,tangent.x)
		if inward.dot(edge.centre-(edge.a+edge.b)*.5)<0:inward=-inward
		var anchor: Vector3=wall.to_global((edge.a+edge.b)*.5+inward*.12+Vector3.UP*.04)
		if _distance_to_routes(anchor,[{"xz":_line_to_xz()}])>float(_design.perched_birds.maximum_source_route_distance_m):continue
		var close:=false
		for previous: Vector3 in used:
			if previous.distance_to(anchor)<15.:close=true;break
		if close:continue
		_bird(anchor,(wall.global_basis*tangent).normalized(),true,"actual_W01_wall_top_edge");used.append(anchor);count+=1
		if count>=int(_design.perched_birds.count):break

func _line_to_xz() -> Array:
	var result:=[]
	for point in _line:
		var local:=city.to_local(point);result.append([local.x,local.z])
	return result

func _build_lamps() -> void:
	var recipe: Dictionary=_design.lamps;var station:=float(recipe.first_station_m)
	var stations: Array[float]=[]
	while station<_arc.back()-6. and stations.size()<int(recipe.maximum_count):
		stations.append(station);station+=float(recipe.spacing_m)
	# Move one existing fixture into the performance gap; do not add lights or
	# brighten the whole city. Its pole still passes every placement guard.
	if not stations.is_empty() and recipe.has("busker_station_offset_m"):
		var focus_station:=clampf(float(_design.busker.fraction)*_arc.back()+float(recipe.busker_station_offset_m),0.,_arc.back()-6.)
		var closest:=0
		for index in range(1,stations.size()):
			if absf(stations[index]-focus_station)<absf(stations[closest]-focus_station):closest=index
		stations[closest]=focus_station
	for lamp_station in stations:
		var basis:=_route_point(lamp_station);var at: Vector3=basis.point+basis.roadside*float(recipe.roadside_offset_m)
		var actor:=_placement("StreetLamp"+str(lamps.size()),"street_lamp",at,basis.tangent,Vector3(.22,4.4,.22))
		if actor==null:continue
		_cylinder(actor,"LampPole",.065,4.20,Vector3(0,2.10,0),"steel")
		_box(actor,"LampArm",Vector3(.08,.08,.85),Vector3(0,4.15,-.35),"steel")
		_box(actor,"LampHousing",Vector3(.40,.13,.61),Vector3(0,4.17,-.70),"steel")
		var bulb:=_box(actor,"WarmLampBulb",Vector3(.33,.045,.52),Vector3(0,4.08,-.70),"lamp_glow")
		var light:=OmniLight3D.new();light.name="WarmStreetLight";light.position=Vector3(0,3.94,-.70);light.light_color=Color(1.,.73,.43);light.omni_range=float(recipe.range_m);light.shadow_enabled=false;actor.add_child(light)
		lamps.append({"actor":actor,"bulb":bulb,"light":light,"station_m":basis.station_m})

func set_time_profile(profile: String) -> bool:
	if profile not in ["day","evening","night"]:return false
	time_profile=profile
	var glow: StandardMaterial3D=_materials.get("lamp_glow")
	if glow!=null:glow.emission_enabled=profile!="day";glow.emission=Color(1.,.62,.30);glow.emission_energy_multiplier=1.4 if profile=="night" else .65
	_update_lights();return true

func apply_quality(profile: String) -> void:quality_id=profile;_update_lights()

func _update_lights() -> void:
	var ordered:=lamps.duplicate();ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:return a.actor.global_position.distance_squared_to(player.global_position)<b.actor.global_position.distance_squared_to(player.global_position))
	var cap:=int(_design.get("lamps",{}).get("maximum_active_standard",8) if quality_id=="standard" else _design.get("lamps",{}).get("maximum_active_light",4))
	for index in range(ordered.size()):
		var row: Dictionary=ordered[index];var distance: float=Vector2(row.actor.global_position.x-player.global_position.x,row.actor.global_position.z-player.global_position.z).length()
		row.light.visible=time_profile!="day" and index<cap and distance<95.
		row.light.light_energy=2.1 if time_profile=="night" else 1.1

func _physics_process(delta: float) -> void:
	if not loaded:return
	elapsed+=maxf(0.,delta);_light_elapsed+=delta
	for row: Dictionary in birds:
		var phase:=fmod(elapsed+float(row.phase),8.);var actor: Node3D=row.actor;var anchor: Vector3=row.anchor;var tangent: Vector3=row.tangent
		var offset:=Vector3.ZERO;var flap:=0.;var peck:=0.
		if phase<3.0:row.state="perch" if row.perched else "peck";peck=-maxf(0.,sin(phase*7.))*.50
		elif phase<5.0:
			row.state="walk";offset=tangent*sin((phase-3.)*PI)*(.16 if row.perched else .30);peck=-.12
		else:
			row.state="flight";var progress: float=(phase-5.)/3.
			offset=tangent*sin(progress*TAU)*.8+Vector3.UP*sin(progress*PI)*1.2;flap=sin(progress*TAU*8.)*.90
		actor.global_position=anchor+offset;row.head.rotation.x=peck
		row.wings[0].rotation.z=-flap;row.wings[1].rotation.z=flap
	for index in range(performers.size()):
		var row: Dictionary=performers[index]
		if row.kind=="busker":
			_hand_to(row,0,Vector3(-.20,1.43,-.24));_hand_to(row,1,Vector3(.10,1.05+sin(elapsed*6.)*.035,-.32))
		else:
			var clap:=.12+sin(elapsed*3.5+index)*.06
			_hand_to(row,0,Vector3(-clap,1.16,-.33));_hand_to(row,1,Vector3(clap,1.16,-.33))
	if _light_elapsed>.35:_light_elapsed=0.;_update_lights()

func snapshot() -> Dictionary:
	var bird_rows:=[];var people_rows:=[];var light_rows:=[];var active_lights:=0;var counts:={}
	for row: Dictionary in anchors:counts[row.kind]=int(counts.get(row.kind,0))+1
	for row: Dictionary in birds:bird_rows.append({"position":row.actor.global_position,"anchor":row.anchor,"source":row.source,"state":row.state,"perched":row.perched,"head_rotation":row.head.rotation,"wing_rotations":[row.wings[0].rotation,row.wings[1].rotation]})
	for row: Dictionary in performers:people_rows.append({"kind":row.kind,"position":row.actor.global_position,"arm_rotations":[row.arms[0].rotation,row.arms[1].rotation],"forearm_rotations":[row.forearms[0].rotation,row.forearms[1].rotation]})
	for row: Dictionary in lamps:
		if row.light.visible:active_lights+=1
		light_rows.append({"position":row.actor.global_position,"station_m":row.station_m,"light_visible":row.light.visible,"energy":row.light.light_energy,"range_m":row.light.omni_range,"shadow_enabled":row.light.shadow_enabled,"emission_enabled":row.bulb.material_override.emission_enabled})
	return {"loaded":loaded,"error":load_error,"authored_game_placements":true,"source_route":_design.get("source_route",{}),"elapsed":elapsed,"time_profile":time_profile,"quality_id":quality_id,"counts":counts,"bird_count":birds.size(),"performer_count":performers.size(),"lamp_count":lamps.size(),"owned_static_bodies":bodies.size(),"anchors":anchors.duplicate(true),"skipped":skipped.duplicate(true),"birds":bird_rows,"performers":people_rows,"lamps":light_rows,"active_lights":active_lights,"maximum_bird_horizontal_excursion_m":.8,"maximum_bird_height_above_anchor_m":1.2,"audio":false}
