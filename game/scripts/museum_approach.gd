extends Node3D
## Game-authored elevation on the source SeMA footway. Source XZ is retained;
## the 3 m hill and lookout are deliberately not claims of measured terrain.
const DESIGN_PATH := "res://assets/authored/museum_approach.json"
const WORLD_PATH := "res://resources/world_geometry/world.json"
const SURFACE_SHADER := preload("res://shaders/street_surface.gdshader")
var loaded := false
var load_error := ""
var city: Node3D
var player: CharacterBody3D
var rig: Node3D
var bodies: Array[StaticBody3D] = []
var anchors: Array[Dictionary] = []
var _design: Dictionary = {}
var _line: Array[Vector3] = []
var _arc: Array[float] = []
var _stations: Array[float] = []
var _sections: Array[Dictionary] = []
var _materials := {}
var _surfaces := {}
var _collision_shapes := 0
var _maximum_mesh_grade := 0.0
var _terrace_frame := Transform3D.IDENTITY
var _terrain_surface: Node3D

func adopt_terrain(surface: Node3D) -> void:
	_terrain_surface=surface
	# The invented 3m profile and lookout are superseded, not added to source terrain.
	for child in get_children():
		remove_child(child);child.queue_free()
	bodies.clear();anchors.clear()
	set_meta("authored_terrain",false)
	set_meta("source_interpolated_terrain",true)

func setup(source_city: Node3D, controlled_player: CharacterBody3D, camera_rig: Node3D) -> bool:
	if loaded or not is_instance_valid(source_city) or not is_instance_valid(controlled_player):return false
	city=source_city;player=controlled_player;rig=camera_rig
	name="MuseumApproach";process_mode=Node.PROCESS_MODE_PAUSABLE
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(DESIGN_PATH))
	if not raw is Dictionary or raw.get("schema_version")!=1:return _fail("미술관 산책로 설계 자료를 읽지 못했습니다.")
	_design=raw
	if String(_design.get("world_sha256",""))!=FileAccess.get_sha256(WORLD_PATH):return _fail("미술관 산책로와 도시 원본이 다릅니다.")
	if not _validate():return false
	global_transform=city.global_transform
	_make_materials();_sample_sections();_build_hill();_build_terrace();_build_planting();_publish_meshes();_make_anchors()
	loaded=true
	set_meta("authored_terrain",true);set_meta("physical_terrain_verified",false)
	print("MUSEUM_APPROACH_READY source=",_design.source.feature_id," authored_rise_m=3 length_m=90 convex_shapes=",_collision_shapes," bodies=",bodies.size())
	return true

func _fail(message: String) -> bool:
	load_error=message
	return false

func _number(value: Variant) -> bool:return (value is float or value is int) and is_finite(float(value))

func _validate() -> bool:
	# A metre-preserving upright city frame is required. No source node is moved.
	var frame:=city.global_transform
	if not frame.is_finite() or not frame.basis.y.is_equal_approx(Vector3.UP) or not frame.basis.is_equal_approx(frame.basis.orthonormalized()):return _fail("미술관 산책로의 미터 좌표계가 다릅니다.")
	if not _design.get("source") is Dictionary or not _design.get("design") is Dictionary or not _design.get("scope") is Dictionary:return _fail("미술관 산책로의 출처/설계 구분이 없습니다.")
	if _design.scope.get("physical_terrain_verified")!=false or _design.source.get("feature_id")!="osm:way:183272668:highway_line":return _fail("미술관 산책로의 출처가 다릅니다.")
	var recipe: Dictionary=_design.design
	for key in ["used_length_m","walk_width_m","grounded_width_m","bottom_y_m","sample_spacing_m","visual_surface_offset_m"]:
		if not _number(recipe.get(key)):return _fail("미술관 산책로 치수가 다릅니다.")
	if recipe.used_length_m!=90.0 or recipe.walk_width_m!=3.2 or recipe.grounded_width_m!=7.2 or recipe.bottom_y_m>=-.1 or recipe.sample_spacing_m<=.25 or recipe.sample_spacing_m>2.:return _fail("미술관 산책로 허용 치수가 다릅니다.")
	if not _design.source.get("xz") is Array:return _fail("미술관 산책로 원본 선이 없습니다.")
	for point: Variant in _design.source.xz:
		if not point is Array or point.size()!=2 or not _number(point[0]) or not _number(point[1]):return _fail("미술관 산책로 원본 좌표가 다릅니다.")
		_line.append(Vector3(float(point[0]),0,float(point[1])))
	if _line.size()<2:return _fail("미술관 산책로 원본 선이 짧습니다.")
	_arc.append(0.)
	for index in range(1,_line.size()):
		var length:=_line[index].distance_to(_line[index-1])
		if length<.1:return _fail("미술관 산책로에 겹친 정점이 있습니다.")
		_arc.append(_arc.back()+length)
	if _arc.back()<recipe.used_length_m+6.:return _fail("미술관 기존 정문 앞의 평지를 확보하지 못했습니다.")
	if not recipe.get("profile") is Array or recipe.profile!=[[0.,0.],[35.,3.],[50.,3.],[90.,0.]]:return _fail("미술관 게임용 경사 프로필이 다릅니다.")
	var terrace: Variant=recipe.get("terrace")
	if not terrace is Dictionary:return _fail("미술관 전망 쉼터 설계가 없습니다.")
	for key in ["station_m","side_offset_m","width_m","length_m","height_m"]:
		if not _number(terrace.get(key)):return _fail("미술관 전망 쉼터 치수가 다릅니다.")
	if terrace.station_m!=42. or terrace.side_offset_m!=-4.6 or terrace.width_m!=6. or terrace.length_m!=6. or terrace.height_m!=3.:return _fail("미술관 전망 쉼터 범위가 다릅니다.")
	return true

func _make_materials() -> void:
	for recipe in [["paving",0],["grass",2],["earth",3]]:
		var material:=ShaderMaterial.new();material.shader=SURFACE_SHADER;material.set_shader_parameter("kind",recipe[1]);_materials[recipe[0]]=material
	for recipe in [["stone",Color(.43,.42,.38)],["coping",Color(.68,.67,.61)],["metal",Color(.19,.23,.21)],["leaf",Color(.24,.34,.16)],["leaf_light",Color(.35,.41,.20)],["wood",Color(.37,.26,.16)]]:
		var material:=StandardMaterial3D.new();material.albedo_color=recipe[1];material.roughness=.9;_materials[recipe[0]]=material
	for key in ["paving","grass","earth","stone"]:_surfaces[key]=[]

## Station remains distance along the unmodified source XZ polyline.
func path_point(station_m: float) -> Vector3:
	if _arc.is_empty():return Vector3.ZERO
	var s:=clampf(station_m,0.,float(_design.design.used_length_m))
	for index in range(1,_line.size()):
		if s>_arc[index] and index<_line.size()-1:continue
		var point: Vector3=_line[index-1].lerp(_line[index],(s-_arc[index-1])/(_arc[index]-_arc[index-1]))
		if is_instance_valid(_terrain_surface):
			var sample: Dictionary=_terrain_surface.sample_ground_world(to_global(point))
			if bool(sample.get("ok",false)):return to_local(sample.point)
		return point+Vector3.UP*height_at_station(s)
	return _line.back()

## Public convenience for navigation/tests; the source-local helper stays local.
func point_at_station(station_m: float) -> Vector3:return to_global(path_point(station_m))

func height_at_station(station_m: float) -> float:
	if is_instance_valid(_terrain_surface):
		var s:=clampf(station_m,0.,90.)
		for index in range(1,_line.size()):
			if s>_arc[index] and index<_line.size()-1:continue
			var point: Vector3=_line[index-1].lerp(_line[index],(s-_arc[index-1])/(_arc[index]-_arc[index-1]))
			return _terrain_surface.ground_y_world(to_global(point))-global_position.y
	var profile: Array=_design.design.profile
	var s:=clampf(station_m,0.,float(_design.design.used_length_m))
	for index in range(1,profile.size()):
		if s>float(profile[index][0]) and index<profile.size()-1:continue
		var a: Array=profile[index-1];var b: Array=profile[index]
		var t:=clampf((s-float(a[0]))/(float(b[0])-float(a[0])),0.,1.)
		return lerpf(float(a[1]),float(b[1]),t*t*(3.-2.*t))
	return 0.

func path_frame(station_m: float) -> Transform3D:
	var at:=path_point(station_m)
	var tangent:=path_point(minf(station_m+.05,90.))-path_point(maxf(station_m-.05,0.));tangent.y=0.;tangent=tangent.normalized()
	return Transform3D(Basis(Vector3(tangent.z,0,-tangent.x),Vector3.UP,tangent),at)

func _sample_sections() -> void:
	var spacing: float=_design.design.sample_spacing_m
	for index in range(int(ceil(90./spacing))+1):_stations.append(minf(float(index)*spacing,90.))
	for s in _arc:
		if s>0. and s<90.:_stations.append(s)
	for row: Array in _design.design.profile:_stations.append(float(row[0]))
	_stations.sort()
	var unique: Array[float]=[]
	for s in _stations:
		if unique.is_empty() or absf(s-unique.back())>.001:unique.append(s)
	_stations=unique
	for s in _stations:
		var frame:=path_frame(s)
		# Mitered cross sections meet exactly at the source footway's corners.
		var before:=path_frame(maxf(s-.02,0.)).basis.x
		var after:=path_frame(minf(s+.02,90.)).basis.x
		var side: Vector3=(before+after).normalized()
		var miter:=1./maxf(.8,side.dot(after))
		_sections.append({"station_m":s,"point":frame.origin,"side":side*miter})
	for index in range(1,_sections.size()):
		var a: Dictionary=_sections[index-1];var b: Dictionary=_sections[index]
		_maximum_mesh_grade=maxf(_maximum_mesh_grade,absf(b.point.y-a.point.y)/(b.station_m-a.station_m))

func _triangle(material: String,a: Vector3,b: Vector3,c: Vector3) -> void:
	# Godot's front face uses clockwise winding. Correct from outward normal.
	_surfaces[material].append(a);_surfaces[material].append(b);_surfaces[material].append(c)

func _top(material: String,a: Vector3,b: Vector3,c: Vector3) -> void:
	if (b-a).cross(c-a).y>0.:_triangle(material,a,c,b)
	else:_triangle(material,a,b,c)

func _quad(material: String,a: Vector3,b: Vector3,c: Vector3,d: Vector3) -> void:
	_triangle(material,a,b,c);_triangle(material,a,c,d)

func _body(title: String) -> StaticBody3D:
	var body:=StaticBody3D.new();body.name=title;body.collision_layer=1;body.collision_mask=0
	body.set_meta("geometry_id","museum_approach/"+title);body.set_meta("authored_game_terrain",true)
	add_child(body);bodies.append(body)
	return body

func _prism(body: StaticBody3D,a: Vector3,b: Vector3,c: Vector3) -> void:
	var bottom: float=_design.design.bottom_y_m
	var shape:=ConvexPolygonShape3D.new()
	shape.points=PackedVector3Array([a,b,c,Vector3(a.x,bottom,a.z),Vector3(b.x,bottom,b.z),Vector3(c.x,bottom,c.z)])
	var collision:=CollisionShape3D.new();collision.name="ClosedGround"+str(_collision_shapes);collision.shape=shape
	body.add_child(collision);_collision_shapes+=1

func _section_point(section: Dictionary,offset: float,outer := false) -> Vector3:
	var point: Vector3=section.point+section.side*offset
	if outer:point.y=0.
	return point

func _build_hill() -> void:
	var body:=_body("GroundedHill")
	var half_walk: float=_design.design.walk_width_m*.5
	var half_ground: float=_design.design.grounded_width_m*.5
	var visual: float=_design.design.visual_surface_offset_m
	var bottom: float=_design.design.bottom_y_m
	for index in range(1,_sections.size()):
		var first: Dictionary=_sections[index-1];var second: Dictionary=_sections[index]
		for strip in [[-half_ground,-half_walk,"grass"],[-half_walk,half_walk,"paving"],[half_walk,half_ground,"grass"]]:
			var left: float=strip[0];var right: float=strip[1];var material: String=strip[2]
			var a:=_section_point(first,left,is_equal_approx(absf(left),half_ground))
			var b:=_section_point(first,right,is_equal_approx(absf(right),half_ground))
			var c:=_section_point(second,right,is_equal_approx(absf(right),half_ground))
			var d:=_section_point(second,left,is_equal_approx(absf(left),half_ground))
			# Two exact triangular prisms per strip: visible and physical top agree,
			# including non-coplanar quads at bends; the entire volume is closed.
			_prism(body,a,b,c);_prism(body,a,c,d)
			_top(material,a+Vector3.UP*visual,b+Vector3.UP*visual,c+Vector3.UP*visual)
			_top(material,a+Vector3.UP*visual,c+Vector3.UP*visual,d+Vector3.UP*visual)
		var a:=_section_point(first,-half_ground,true);var b:=_section_point(second,-half_ground,true)
		_quad("earth",a,b,Vector3(b.x,bottom,b.z),Vector3(a.x,bottom,a.z))
		a=_section_point(second,half_ground,true);b=_section_point(first,half_ground,true)
		_quad("earth",a,b,Vector3(b.x,bottom,b.z),Vector3(a.x,bottom,a.z))
		# Flush narrow stone strips read as edging, without an invisible step.
		for sign_value in [-1.,1.]:
			var a0:=_section_point(first,sign_value*half_walk)+Vector3.UP*(visual+.003)
			var a1:=_section_point(first,sign_value*(half_walk-.14))+Vector3.UP*(visual+.003)
			var b0:=_section_point(second,sign_value*half_walk)+Vector3.UP*(visual+.003)
			var b1:=_section_point(second,sign_value*(half_walk-.14))+Vector3.UP*(visual+.003)
			_top("stone",a0,a1,b1);_top("stone",a0,b1,b0)
	# End faces close the rendered earth below the existing flat support.
	for section in [_sections.front(),_sections.back()]:
		var a:=_section_point(section,-half_ground,true);var b:=_section_point(section,half_ground,true)
		_quad("earth",a,b,Vector3(b.x,bottom,b.z),Vector3(a.x,bottom,a.z))

func _mesh(title: String,mesh: Mesh,point: Vector3,material: String,parent: Node3D = self) -> MeshInstance3D:
	var visual:=MeshInstance3D.new();visual.name=title;visual.mesh=mesh;visual.position=point;visual.material_override=_materials[material]
	parent.add_child(visual)
	return visual

func _box(title: String,size: Vector3,point: Vector3,material: String,parent: Node3D = self) -> MeshInstance3D:
	var mesh:=BoxMesh.new();mesh.size=size
	return _mesh(title,mesh,point,material,parent)

func _solid_box(body: StaticBody3D,title: String,size: Vector3,frame: Transform3D) -> void:
	var shape:=BoxShape3D.new();shape.size=size
	var collision:=CollisionShape3D.new();collision.name=title;collision.shape=shape;collision.transform=frame
	body.add_child(collision);_collision_shapes+=1

func _build_terrace() -> void:
	var recipe: Dictionary=_design.design.terrace
	_terrace_frame=path_frame(recipe.station_m);_terrace_frame.origin+=_terrace_frame.basis.x*float(recipe.side_offset_m)
	var terrace:=Node3D.new();terrace.name="WestLookout";terrace.transform=_terrace_frame;add_child(terrace)
	var body:=_body("SolidLookout")
	var height: float=recipe.height_m-float(_design.design.bottom_y_m)
	var a: Vector3=_terrace_frame*Vector3(-3,0,-3)
	var b: Vector3=_terrace_frame*Vector3(3,0,-3)
	var c: Vector3=_terrace_frame*Vector3(3,0,3)
	var d: Vector3=_terrace_frame*Vector3(-3,0,3)
	# The same convex top representation as the path prevents a box-vs-hull
	# contact tolerance seam from acting as a tiny unstepable vertical kerb.
	_prism(body,a,b,c);_prism(body,a,c,d)
	_box("RetainingStone",Vector3(6,height,6),Vector3(0,-height*.5,0),"stone",terrace)
	_box("PavedLookout",Vector3(6,.016,6),Vector3(0,.008,0),"paving",terrace)
	# Horizontal block courses make the 3 m foundation read as retaining masonry.
	for level in range(1,8):
		for x in [-3.006,3.006]:_box("StoneCourse",Vector3(.012,.024,6.01),Vector3(x,-float(level)*.4,0),"coping",terrace)
		for z in [-3.006,3.006]:_box("StoneCourse",Vector3(6.01,.024,.012),Vector3(0,-float(level)*.4,z),"coping",terrace)
	# The path-facing (+X) edge stays entirely open at the same Y3 plateau.
	for edge in ["west","north","south"]:
		var along_z: bool=edge=="west"
		for index in range(7):
			var point:=Vector3(-2.85,0.,float(index)*.95-2.85) if along_z else Vector3(float(index)*.95-2.85,0.,-2.85 if edge=="north" else 2.85)
			_box("LookoutPost",Vector3(.07,.9,.07),point+Vector3.UP*.45,"metal",terrace)
		var middle:=Vector3(-2.85,.83,0) if along_z else Vector3(0,.83,-2.85 if edge=="north" else 2.85)
		var size:=Vector3(.06,.07,5.76) if along_z else Vector3(5.76,.07,.06)
		_box("LookoutRail",size,middle,"metal",terrace)
		# A physical 0.9 m guard closes the exposed edge, matching the visible rail.
		var guard_size:=Vector3(.09,.9,5.8) if along_z else Vector3(5.8,.9,.09)
		_solid_box(body,"LookoutGuard",guard_size,_terrace_frame*Transform3D(Basis.IDENTITY,Vector3(middle.x,.45,middle.z)))
	# A wall-side bench leaves the central standing and path connection clear.
	_box("LookoutBenchSeat",Vector3(.55,.12,2.0),Vector3(-2.,.48,0),"wood",terrace)
	_box("LookoutBenchBack",Vector3(.10,.55,2.0),Vector3(-2.22,.78,0),"wood",terrace)
	for z in [-.8,.8]:_box("LookoutBenchLeg",Vector3(.35,.42,.08),Vector3(-2.,.21,z),"metal",terrace)
	_solid_box(body,"BenchSeatCollision",Vector3(.65,.96,2.),_terrace_frame*Transform3D(Basis.IDENTITY,Vector3(-2.05,.48,0)))

func _build_planting() -> void:
	# Non-solid small shrubs sit on the sloping shoulders, outside the paving.
	for station in [8.,16.,25.,32.,54.,63.,73.,82.]:
		var frame:=path_frame(station)
		for side in [-1.,1.]:
			var at: Vector3=frame.origin+frame.basis.x*(side*2.65);at.y=height_at_station(station)*.475+.24
			var sphere:=SphereMesh.new();sphere.radius=.5;sphere.height=1.;sphere.radial_segments=12;sphere.rings=6
			var shrub:=_mesh("ShoulderShrub",sphere,at,"leaf" if int(station)%2==0 else "leaf_light")
			shrub.scale=Vector3(.75,.65,.85)

func _publish_meshes() -> void:
	for key: String in _surfaces:
		var vertices:=PackedVector3Array(_surfaces[key])
		if vertices.is_empty():continue
		var normals:=PackedVector3Array()
		for index in range(0,vertices.size(),3):
			var normal: Vector3=(vertices[index+2]-vertices[index]).cross(vertices[index+1]-vertices[index]).normalized()
			normals.append(normal);normals.append(normal);normals.append(normal)
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		_mesh("Hill_"+key,mesh,Vector3.ZERO,key)
	_surfaces.clear()

func _make_anchors() -> void:
	for recipe in [["bottom",0.],["crest",35.],["plateau",42.],["farflat",90.]]:
		var frame:=path_frame(float(recipe[1]));var surface: Vector3=to_global(frame.origin)
		anchors.append({"id":recipe[0],"station_m":recipe[1],"surface_point":surface,"foot_point":surface+Vector3.UP*.08,"tangent":global_basis*frame.basis.z,"authored_height_m":frame.origin.y})
	var terrace_point:=to_global(_terrace_frame.origin)
	anchors.append({"id":"terrace","station_m":42.,"surface_point":terrace_point,"foot_point":terrace_point+Vector3.UP*.08,"tangent":global_basis*_terrace_frame.basis.z,"authored_height_m":3.})
	var entry: Array=_design.design.museum_flat_entrance_xz
	var point:=to_global(Vector3(float(entry[0]),.08,float(entry[1])))
	anchors.append({"id":"original_museum_entrance","foot_point":point,"authored_height_m":0.,"source_entrance_preserved":true})

func snapshot() -> Dictionary:
	var body_records: Array=[]
	for body in bodies:body_records.append({"name":body.name,"instance_id":body.get_instance_id(),"collision_layer":body.collision_layer,"shapes":body.get_child_count(),"frame":body.global_transform})
	return {"loaded":loaded,"error":load_error,"id":_design.get("id",""),"authored":true,"physical_terrain_verified":false,"source":_design.get("source",{}).duplicate(true),"scope":_design.get("scope",{}).duplicate(true),"profile":_design.get("design",{}).get("profile",[]).duplicate(true),"walk_length_m":90.,"source_length_m":_arc.back() if not _arc.is_empty() else 0.,"designed_height_m":3.,"walk_width_m":3.2,"grounded_width_m":7.2,"maximum_designed_grade":3.*1.5/35.,"maximum_collision_segment_grade":_maximum_mesh_grade,"maximum_designed_grade_degrees":rad_to_deg(atan(3.*1.5/35.)),"sample_count":_sections.size(),"collision_body_count":bodies.size(),"closed_convex_shape_count":_collision_shapes,"bodies":body_records,"anchors":anchors.duplicate(true),"terrace_frame":global_transform*_terrace_frame,"terrace_size_m":Vector2(6,6),"design_sha256":FileAccess.get_sha256(DESIGN_PATH),"source_buildings_modified":false,"original_museum_entrance_y_m":.08}
