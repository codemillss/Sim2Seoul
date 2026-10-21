extends Node3D
## Bounded game-authored road-edge bands. Existing road/sidewalk support stays
## Y0; every side and end returns gently to it. These are not surveyed kerbs.
const DESIGN_PATH := "res://assets/authored/street_curbs.json"
var loaded := false
var load_error := ""
var city: Node3D
var player: CharacterBody3D
var rig: Node3D
var bodies: Array[StaticBody3D] = []
var segments: Array[Dictionary] = []
var skipped: Array[Dictionary] = []
var _design: Dictionary = {}
var _prepared: Array[Dictionary] = []
var _vertices := {"stone":[],"tile":[]}
var _shape_count := 0
var _built_length := 0.0
var _crossing_masks: Dictionary={}
var crossing_mask_audit: Array=[]

func setup(source_city: Node3D,controlled_player: CharacterBody3D,camera_rig: Node3D) -> bool:
	if loaded or not is_instance_valid(source_city) or not is_instance_valid(controlled_player):return false
	city=source_city;player=controlled_player;rig=camera_rig;name="StreetCurbs";process_mode=Node.PROCESS_MODE_PAUSABLE
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(DESIGN_PATH))
	if not raw is Dictionary or raw.get("schema_version")!=1:return _fail("게임용 연석 설계 자료를 읽지 못했습니다.")
	_design=raw
	if not _validate():return false
	var road: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/road_furniture.json"))
	if road is Dictionary:
		for mask: Dictionary in road.get("curb_crossing_masks",[]):
			var polygon:=PackedVector2Array()
			for xz: Array in mask.mask_xz:polygon.append(Vector2(xz[0],xz[1]))
			if not _crossing_masks.has(mask.curb_id):_crossing_masks[mask.curb_id]=[]
			_crossing_masks[mask.curb_id].append(polygon)
			crossing_mask_audit.append({"curb_id":mask.curb_id,"crossing_id":mask.crossing_id,"original_overlap_m2":mask.original_overlap_m2,"clearance_m":mask.clearance_m,"policy":"only_game_authored_curb_top_and_collision_split; source_bodies_unchanged"})
	global_transform=city.global_transform
	# Preflight against the scene before adding any of our own collision shapes.
	for record: Dictionary in _design.segments:
		var prepared:=_prepare(record)
		if not _clear(prepared):skipped.append({"id":record.id,"reason":"existing_above_ground_body_or_prop"});continue
		_prepared.append(prepared)
	for record in _prepared:_build_segment(record)
	_publish_meshes();loaded=true
	set_meta("authored_road_edge",true);set_meta("physical_terrain_verified",false)
	print("STREET_CURBS_READY segments=",segments.size()," skipped=",skipped.size()," length_m=",_built_length," height_m=.12 shapes=",_shape_count)
	return true

func _fail(message: String) -> bool:load_error=message;return false
func _number(value: Variant) -> bool:return (value is float or value is int) and is_finite(float(value))

func _validate() -> bool:
	var frame:=city.global_transform
	if not frame.is_finite() or not frame.basis.y.is_equal_approx(Vector3.UP) or not frame.basis.is_equal_approx(frame.basis.orthonormalized()):return _fail("연석의 미터 좌표계가 다릅니다.")
	if not _design.get("source_hashes") is Dictionary:return _fail("연석의 원본 목록이 없습니다.")
	for path: String in _design.source_hashes:
		if FileAccess.get_sha256(path)!=String(_design.source_hashes[path]):return _fail("연석과 도시·출입구·보행 원본이 다릅니다.")
	if not _design.get("design") is Dictionary or not _design.get("protection") is Dictionary:return _fail("연석의 치수/보호 계획이 없습니다.")
	var d: Dictionary=_design.design
	for key in ["height_m","width_m","flat_top_width_m","end_fade_length_m","sample_spacing_m","bottom_y_m"]:
		if not _number(d.get(key)):return _fail("연석의 치수가 다릅니다.")
	if d.height_m!=.12 or d.width_m!=1.4 or d.flat_top_width_m!=.3 or d.end_fade_length_m<1.2 or d.sample_spacing_m<=0. or d.sample_spacing_m>1. or d.bottom_y_m>=0.:return _fail("지원하지 않는 연석 경사입니다.")
	if _design.protection.get("door_buildings")!=125 or _design.protection.get("entrance_candidates")!=704:return _fail("연석의 출입구 보호 범위가 다릅니다.")
	for key in _design.protection.protected_static_intersection_area_m2:
		if float(_design.protection.protected_static_intersection_area_m2[key])>.00001:return _fail("연석이 보호 동선과 겹칩니다.")
	if not _design.get("segments") is Array:return _fail("연석 구간이 없습니다.")
	var ids:={}
	for record: Variant in _design.segments:
		if not record is Dictionary or not record.get("id") is String or ids.has(record.id) or not record.get("xz") is Array or record.xz.size()<2:return _fail("연석 구간 형식이 다릅니다.")
		ids[record.id]=true
		for point: Variant in record.xz:
			if not point is Array or point.size()!=2 or not _number(point[0]) or not _number(point[1]):return _fail("연석 좌표가 다릅니다.")
	return true

func _prepare(record: Dictionary) -> Dictionary:
	var line: Array[Vector3]=[];var arc: Array[float]=[0.]
	for point: Array in record.xz:line.append(Vector3(float(point[0]),0,float(point[1])))
	for index in range(1,line.size()):arc.append(arc.back()+line[index].distance_to(line[index-1]))
	var stations: Array[float]=[]
	for index in range(int(ceil(arc.back()/float(_design.design.sample_spacing_m)))+1):stations.append(minf(index*float(_design.design.sample_spacing_m),arc.back()))
	for value in arc:stations.append(value)
	stations.sort();var unique: Array[float]=[]
	for value in stations:
		if unique.is_empty() or value-unique.back()>.001:unique.append(value)
	var result:={"id":record.id,"line":line,"arc":arc,"length_m":arc.back(),"stations":unique,"roadside_sign":int(record.roadside_sign),"source_drive_features":record.source_drive_features,"sections":[]}
	for station in unique:
		var at:=_point(result,station)
		var tangent:=_point(result,minf(station+.025,arc.back()))-_point(result,maxf(station-.025,0.));tangent=tangent.normalized()
		result.sections.append({"station_m":station,"point":at,"side":Vector3(tangent.z,0,-tangent.x)})
	return result

func _point(record: Dictionary,station: float) -> Vector3:
	var s:=clampf(station,0.,record.length_m)
	for index in range(1,record.line.size()):
		if s>record.arc[index] and index<record.line.size()-1:continue
		return record.line[index-1].lerp(record.line[index],(s-record.arc[index-1])/maxf(.0001,record.arc[index]-record.arc[index-1]))
	return record.line.back()

func _height(record: Dictionary,station: float,lateral: float) -> float:
	var edge:=float(_design.design.width_m)*.5;var top:=float(_design.design.flat_top_width_m)*.5
	var cross_height:=clampf((edge-absf(lateral))/(edge-top),0.,1.)
	var t:=clampf(minf(station,record.length_m-station)/float(_design.design.end_fade_length_m),0.,1.)
	return float(_design.design.height_m)*cross_height*t*t*(3.-2.*t)

func _surface(record: Dictionary,section: Dictionary,lateral: float) -> Vector3:
	return section.point+section.side*lateral+Vector3.UP*_height(record,section.station_m,lateral)

func _clear(record: Dictionary) -> bool:
	var box:=BoxShape3D.new();box.size=Vector3(1.62,2.2,1.25)
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=box;query.collision_mask=1|4|8;query.margin=.002;query.exclude=[player.get_rid()]
	for section: Dictionary in record.sections:
		var side: Vector3=section.side;var tangent:=Vector3(-side.z,0,side.x)
		query.transform=global_transform*Transform3D(Basis(side,Vector3.UP,tangent),section.point+Vector3.UP*1.12)
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return false
	return true

func _prism(body: StaticBody3D,a: Vector3,b: Vector3,c: Vector3) -> void:
	var bottom: float=_design.design.bottom_y_m
	var shape:=ConvexPolygonShape3D.new();shape.points=PackedVector3Array([a,b,c,Vector3(a.x,bottom,a.z),Vector3(b.x,bottom,b.z),Vector3(c.x,bottom,c.z)])
	var node:=CollisionShape3D.new();node.name="BeveledGround"+str(_shape_count);node.shape=shape;body.add_child(node);_shape_count+=1

func _triangle(material: String,a: Vector3,b: Vector3,c: Vector3) -> void:
	if (b-a).cross(c-a).y>0.:_vertices[material].append_array([a,c,b])
	else:_vertices[material].append_array([a,b,c])

func _emit_curb_triangle(record: Dictionary,body: StaticBody3D,material: String,a: Vector3,b: Vector3,c: Vector3) -> void:
	var parts: Array=[PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])]
	for mask: PackedVector2Array in _crossing_masks.get(record.id,[]):
		var remaining: Array=[]
		for polygon: PackedVector2Array in parts:remaining.append_array(Geometry2D.clip_polygons(polygon,mask))
		parts=remaining
	var plane: Vector3=(b-a).cross(c-a)
	if absf(plane.y)<.000001:return
	for polygon: PackedVector2Array in parts:
		var indices: PackedInt32Array=Geometry2D.triangulate_polygon(polygon)
		for index: int in range(0,indices.size(),3):
			var points: Array[Vector3]=[]
			for corner: int in range(3):
				var xz: Vector2=polygon[indices[index+corner]]
				var height: float=a.y-(plane.x*(xz.x-a.x)+plane.z*(xz.y-a.z))/plane.y
				points.append(Vector3(xz.x,height,xz.y))
			_prism(body,points[0],points[1],points[2]);_triangle(material,points[0],points[1],points[2])

func _build_segment(record: Dictionary) -> void:
	var body:=StaticBody3D.new();body.name=record.id;body.collision_layer=1;body.collision_mask=0
	body.set_meta("geometry_id","street_curbs/"+record.id);body.set_meta("authored_game_curb",true);add_child(body);bodies.append(body)
	for index in range(1,record.sections.size()):
		var first: Dictionary=record.sections[index-1];var second: Dictionary=record.sections[index]
		for strip in [[-.7,-.15],[-.15,.15],[.15,.7]]:
			var a:=_surface(record,first,strip[0]);var b:=_surface(record,first,strip[1]);var c:=_surface(record,second,strip[1]);var d:=_surface(record,second,strip[0])
			var material: String="stone" if strip[0]==-.15 or signf(float(strip[0])+float(strip[1]))==float(record.roadside_sign) else "tile"
			_emit_curb_triangle(record,body,material,a,b,c);_emit_curb_triangle(record,body,material,a,c,d)
	var middle: float=record.length_m*.5
	var point:=_point(record,middle);var tangent:=(_point(record,middle+.05)-_point(record,middle-.05)).normalized()
	segments.append({"id":record.id,"length_m":record.length_m,"body_instance_id":body.get_instance_id(),"source_drive_features":record.source_drive_features,"source_xz":_json_xz(record.line),"top_point":to_global(point+Vector3.UP*.12),"foot_point":to_global(point+Vector3.UP*.20),"lateral_direction":global_basis*Vector3(tangent.z,0,-tangent.x),"cut_points":[to_global(record.line.front()),to_global(record.line.back())],"sample_count":record.sections.size(),"height_m":.12,"width_m":1.4})
	_built_length+=record.length_m

func _json_xz(line: Array[Vector3]) -> Array:
	var result: Array=[]
	for point in line:result.append([point.x,point.z])
	return result

func _publish_meshes() -> void:
	for key: String in _vertices:
		var points:=PackedVector3Array(_vertices[key]);if points.is_empty():continue
		var normals:=PackedVector3Array()
		for index in range(0,points.size(),3):
			var normal: Vector3=(points[index+2]-points[index]).cross(points[index+1]-points[index]).normalized()
			normals.append_array([normal,normal,normal])
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var visual:=MeshInstance3D.new();visual.name="Beveled_"+key;visual.mesh=mesh
		if key=="tile":
			var material:=ShaderMaterial.new();material.shader=preload("res://shaders/street_surface.gdshader");material.set_shader_parameter("kind",0);visual.material_override=material
		else:
			var material:=StandardMaterial3D.new();material.albedo_color=Color(.60,.59,.55);material.roughness=.92;visual.material_override=material
		add_child(visual)
	_vertices.clear()

## Independent tests/navigation can sample actual authored surface in world space.
func point_on_segment(id: String,station_m: float,lateral_m := 0.0) -> Vector3:
	for record in _prepared:
		if record.id!=id:continue
		var point:=_point(record,station_m);var tangent:=(_point(record,minf(station_m+.025,record.length_m))-_point(record,maxf(station_m-.025,0.))).normalized()
		return to_global(point+Vector3(tangent.z,0,-tangent.x)*lateral_m+Vector3.UP*_height(record,clampf(station_m,0.,record.length_m),lateral_m))
	return Vector3.INF

func snapshot() -> Dictionary:
	return {"loaded":loaded,"error":load_error,"authored":true,"physical_terrain_verified":false,"scope":_design.get("scope",{}).duplicate(true),"planned_segment_count":_design.get("planned_segment_count",0),"planned_length_m":_design.get("planned_length_m",0.),"built_length_m":_built_length,"segments":segments.duplicate(true),"skipped":skipped.duplicate(true),"owned_body_count":bodies.size(),"closed_convex_shape_count":_shape_count,"height_m":.12,"width_m":1.4,"flat_top_width_m":.3,"end_fade_length_m":1.2,"existing_ground_and_roads_y_m":0.,"protection":_design.get("protection",{}).duplicate(true),"named_flat_cuts":_design.get("named_flat_cuts",[]).duplicate(true),"source_hashes":_design.get("source_hashes",{}).duplicate(true),"design_sha256":FileAccess.get_sha256(DESIGN_PATH)}
