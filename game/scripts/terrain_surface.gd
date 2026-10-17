extends Node3D
## EXP21: the physical TIN and height queries share the exact same triangles.
## Absolute source elevation, inferred foundations and relative game Y stay separate.
const FIELD_PATH := "res://assets/authored/terrain_heightfield.json"
const MESH_PATH := "res://data/generated/terrain_surface.json"
var loaded := false
var data_ready := false
var load_error := ""
var field: Dictionary = {}
var mesh_data: Dictionary = {}
var domain := Rect2()
var faces := PackedVector3Array()
var normals := PackedVector3Array()
var cell_offsets := PackedInt32Array()
var width := 0
var depth := 0
var cell_size := 5.0
var origin := Vector2.ZERO
var foundation_by_source: Dictionary = {}
var support: StaticBody3D
var visual: MeshInstance3D
var setup_microseconds := 0
var runtime_mesh_sha256 := ""
var _ground_query_tick: int=-1
var _ground_query_cache: Dictionary={}

func _fail(message: String) -> bool:
	load_error=message;push_error(message);return false

func prepare() -> bool:
	var started:=Time.get_ticks_usec()
	if data_ready:return _fail("지형이 이미 준비됐습니다.")
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(FIELD_PATH))
	var physical: Variant=JSON.parse_string(FileAccess.get_file_as_string(MESH_PATH))
	if not raw is Dictionary or not physical is Dictionary:return _fail("지역 지형을 준비해주세요.")
	if raw.get("schema_version")!=1 or physical.get("schema_version")!=1 or physical.get("task")!="EXP21":return _fail("지형 자료 버전이 다릅니다.")
	if physical.get("inputs",{}).get("heightfield_sha256")!=FileAccess.get_sha256(FIELD_PATH):return _fail("지형 원천과 실제 면의 체크섬이 다릅니다.")
	field=raw;mesh_data=physical
	runtime_mesh_sha256=FileAccess.get_sha256(MESH_PATH)
	var g: Dictionary=physical.grid
	origin=Vector2(g.origin_xz_m[0],g.origin_xz_m[1]);width=int(g.width);depth=int(g.depth);cell_size=float(g.cell_size_m)
	if width<2 or depth<2 or cell_size<=0. or physical.faces_xyz.size()%9!=0:return _fail("지형 격자/삼각형이 잘못됐습니다.")
	domain=Rect2(origin,Vector2((width-1)*cell_size,(depth-1)*cell_size))
	for value: Variant in physical.faces_xyz:
		if not (value is float or value is int) or not is_finite(float(value)):return _fail("지형 좌표가 유한하지 않습니다.")
	for i in range(0,physical.faces_xyz.size(),3):faces.append(Vector3(physical.faces_xyz[i],physical.faces_xyz[i+1],physical.faces_xyz[i+2]))
	for i in range(0,faces.size(),3):normals.append((faces[i+2]-faces[i]).cross(faces[i+1]-faces[i]).normalized())
	cell_offsets=PackedInt32Array(physical.cell_face_offsets)
	if cell_offsets.size()!=(width-1)*(depth-1)+1 or cell_offsets[0]!=0 or cell_offsets[-1]*3!=faces.size():return _fail("지형 공간 색인이 다릅니다.")
	for i in range(1,cell_offsets.size()):
		if cell_offsets[i]<cell_offsets[i-1]:return _fail("지형 공간 색인 순서가 다릅니다.")
	for foundation: Dictionary in field.foundations:
		for id: String in foundation.source_ids:foundation_by_source[id]=foundation
	data_ready=true
	_build_surface()
	# The geometry is usable during the synchronous rebase, while actors remain
	# in their historical flat setup until loaded is explicitly committed.
	setup_microseconds=Time.get_ticks_usec()-started
	return true

func _build_surface() -> void:
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=faces
	var per_vertex:=PackedVector3Array()
	for normal: Vector3 in normals:per_vertex.append(normal);per_vertex.append(normal);per_vertex.append(normal)
	arrays[Mesh.ARRAY_NORMAL]=per_vertex
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material:=ShaderMaterial.new();material.shader=preload("res://shaders/street_surface.gdshader");material.set_shader_parameter("kind",2)
	visual=MeshInstance3D.new();visual.name="InterpolatedTerrain";visual.mesh=mesh;visual.material_override=material;add_child(visual)
	support=StaticBody3D.new();support.name="TerrainSupport";support.collision_layer=32;support.collision_mask=14;support.set_meta("geometry_id","EXP21_interpolated_terrain");add_child(support)
	var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces);shape.backface_collision=true
	var collision:=CollisionShape3D.new();collision.shape=shape;support.add_child(collision)

func _cell(point: Vector3) -> int:
	if not data_ready or not point.is_finite() or not domain.has_point(Vector2(point.x,point.z)):return -1
	var x:=clampi(floori((point.x-origin.x)/cell_size),0,width-2)
	var z:=clampi(floori((point.z-origin.y)/cell_size),0,depth-2)
	return z*(width-1)+x

func _height(face: int,p: Vector2) -> float:
	var a:=faces[face*3];var b:=faces[face*3+1];var c:=faces[face*3+2]
	var denominator: float=(b.z-c.z)*(a.x-c.x)+(c.x-b.x)*(a.z-c.z)
	if absf(denominator)<1e-10:return NAN
	var u: float=((b.z-c.z)*(p.x-c.x)+(c.x-b.x)*(p.y-c.z))/denominator
	var v: float=((c.z-a.z)*(p.x-c.x)+(a.x-c.x)*(p.y-c.z))/denominator
	if u<-.00002 or v<-.00002 or u+v>1.00002:return NAN
	return u*a.y+v*b.y+(1.-u-v)*c.y

func sample_ground_world(point: Vector3) -> Dictionary:
	var cell:=_cell(point)
	if cell<0:return {"ok":false,"reason":"outside_or_missing_terrain","height_m":NAN}
	for index in range(cell_offsets[cell],cell_offsets[cell+1]):
		var height:=_height(index,Vector2(point.x,point.z))
		if is_finite(height):return {"ok":true,"point":Vector3(point.x,height,point.z),"height_m":height,"normal":normals[index],"triangle":index,"source_kind":"source_interpolation_with_inferred_foundations"}
	return {"ok":false,"reason":"missing_surface_triangle","height_m":NAN}

func ground_y_world(point: Vector3) -> float:
	# The prepared surface is immutable. Reuse only exact XZ queries within
	# one physics tick; native floor/contact queries remain independent.
	if not point.is_finite():return NAN
	var key:=Vector2(point.x,point.z)
	if loaded:
		var tick:=Engine.get_physics_frames()
		if tick!=_ground_query_tick:_ground_query_tick=tick;_ground_query_cache.clear()
		if _ground_query_cache.has(key):return _ground_query_cache[key]
	var cell:=_cell(point)
	if cell<0:return NAN
	for index in range(cell_offsets[cell],cell_offsets[cell+1]):
		var height:=_height(index,Vector2(point.x,point.z))
		if is_finite(height):
			if loaded:
				if _ground_query_cache.size()>=4096:_ground_query_cache.clear()
				_ground_query_cache[key]=height
			return height
	return NAN

func building_base_y_world(id: String) -> float:
	if not data_ready or not foundation_by_source.has(id):return NAN
	return float(foundation_by_source[id].base_y_m)

func triangles_at_xz_rect(rect: Rect2) -> Array:
	var result: Array=[]
	if not data_ready or not rect.intersects(domain):return result
	var cut:=rect.intersection(domain)
	var min_x:=clampi(floori((cut.position.x-origin.x)/cell_size),0,width-2)
	var max_x:=clampi(floori((cut.end.x-origin.x)/cell_size),0,width-2)
	var min_z:=clampi(floori((cut.position.y-origin.y)/cell_size),0,depth-2)
	var max_z:=clampi(floori((cut.end.y-origin.y)/cell_size),0,depth-2)
	for z in range(min_z,max_z+1):
		for x in range(min_x,max_x+1):
			var cell:=z*(width-1)+x
			for index in range(cell_offsets[cell],cell_offsets[cell+1]):result.append({"a":faces[index*3],"b":faces[index*3+1],"c":faces[index*3+2]})
	return result

func snapshot() -> Dictionary:
	return {"loaded":loaded,"data_ready":data_ready,"error":load_error,"source_field_sha256":FileAccess.get_sha256(FIELD_PATH),"runtime_mesh_sha256":runtime_mesh_sha256,"triangles":faces.size()/3,"domain":domain,"foundation_groups":field.get("foundations",[]).size(),"bound_source_buildings":foundation_by_source.size(),"datum":field.get("datum",{}),"setup_microseconds":setup_microseconds,"source_files_unchanged":true,"runtime_geometry_elevation_changed":true,"scope":"Source-interpolated relative terrain plus explicitly inferred level building foundations. Not a measured DEM or verified absolute elevation; source XZ/height files are unchanged."}
