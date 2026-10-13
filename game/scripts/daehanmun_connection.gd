extends "res://scripts/collision_world.gd"
## W01 local overrides; E03/P04 source bundles remain unchanged.
var connection: Dictionary = {}
var decision: Dictionary = {}
var fragments := {}
var walk_error := ""

func load_connection(world: Dictionary) -> bool:
	var manifest_path := "res://data/generated/daehanmun_manifest.json"
	if not FileAccess.file_exists(manifest_path):return _walk_fail("대한문 연결 자료를 준비해주세요.")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary or manifest.get("schema_version")!=1 or manifest.get("task")!="W01":return _walk_fail("대한문 자료 버전이 다릅니다.")
	if manifest.get("world_sha256")!=_hash("res://resources/world_geometry/world.json") or manifest.get("collision_sha256")!=_hash("res://resources/collision/generated.json") or manifest.get("region_sha256")!=world.coordinate_contract_sha256:return _walk_fail("대한문 자료와 원천 도시가 다릅니다.")
	for item in [["connection","res://data/generated/daehanmun.json"],["decision","res://data/generated/daehanmun_decision.json"]]:
		if not manifest.get("files") is Dictionary or not manifest.files.has(item[0]):return _walk_fail("대한문 파일 목록이 없습니다.")
		if not manifest.files[item[0]] is Dictionary:return _walk_fail("대한문 파일 항목이 잘못됐습니다.")
		var file: Dictionary=manifest.files[item[0]]
		if file.get("path")!=item[1] or not FileAccess.file_exists(item[1]) or file.get("sha256")!=_hash(item[1]):return _walk_fail("대한문 파일 체크섬이 다릅니다.")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/daehanmun.json"))
	var manual = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/daehanmun_decision.json"))
	if not parsed is Dictionary or not manual is Dictionary:return _walk_fail("대한문 자료 형식이 다릅니다.")
	connection=parsed
	decision=manual
	if connection.get("task")!="W01" or connection.get("schema_version")!=1 or decision.get("task")!="W01" or decision.get("opening_width_m")!=3.0 or decision.get("opening_height_m")!=3.0:return _walk_fail("지원하지 않는 대한문 설정입니다.")
	if not decision.get("scope") is Dictionary:return _walk_fail("대한문 범위 설정이 없습니다.")
	if connection.get("opening")!={"width":3.0,"height":3.0} or connection.get("scope")!=decision.get("scope") or decision.scope.get("physical_terrain_verified")!=false or decision.scope.get("measured_gate_dimensions")!=false or not decision.scope.has("global_playable_boundary") or decision.scope.global_playable_boundary!=null:return _walk_fail("임시 지면/치수 범위가 다릅니다.")
	var disabled := ["osm:way:377289797:building","osm:way:26658458:barrier","temporary_support"]
	if connection.get("disabled_source_ids")!=disabled or not connection.get("fragments") is Array or connection.fragments.size()!=5 or not connection.get("volume_obstacles") is Array:return _walk_fail("대한문 충돌 교체 목록이 다릅니다.")
	var expected_ids := ["W01_gate_side_0","W01_gate_side_1","W01_gate_lintel","W01_palace_wall","W01_support"]
	var triangles := 0
	for i in range(5):
		var m = connection.fragments[i]
		if not m is Dictionary or m.get("id")!=expected_ids[i] or not m.get("vertices") is Array or not m.get("normals") is Array or m.vertices.size()<9 or m.vertices.size()%9!=0 or m.vertices.size()!=m.normals.size():return _walk_fail("대한문 메시 배열이 다릅니다.")
		for v in m.vertices+m.normals:
			if not _number(v):return _walk_fail("대한문 메시 숫자가 잘못됐습니다.")
		triangles+=m.vertices.size()/9
	if triangles!=500 or connection.get("counts")!=JSON.parse_string(JSON.stringify({"preserved_active_bodies":682,"replacement_bodies":5,"active_bodies":687,"fragment_triangles":500})):return _walk_fail("대한문 충돌 집계가 다릅니다.")
	if not connection.get("movement_ring") is Array or connection.movement_ring.size()<4 or not connection.get("spawn") is Array or connection.spawn.size()!=3:return _walk_fail("대한문 시작점/범위가 없습니다.")
	for p in connection.movement_ring:
		if not p is Array or p.size()!=2 or not _number(p[0]) or not _number(p[1]):return _walk_fail("대한문 범위 숫자가 다릅니다.")
	for v in connection.spawn:
		if not _number(v):return _walk_fail("대한문 시작점 숫자가 다릅니다.")
	if not connection.get("route_xz") is Array or connection.route_xz.size()!=4 or not _number(connection.get("passage_length_m")) or connection.passage_length_m<=0:return _walk_fail("대한문 원천 경로가 없습니다.")
	for p in connection.route_xz:
		if not p is Array or p.size()!=2 or not _number(p[0]) or not _number(p[1]):return _walk_fail("대한문 원천 경로 숫자가 다릅니다.")
	for key in ["direction_xz","normal_xz"]:
		if not connection.get(key) is Array or connection[key].size()!=2 or not _number(connection[key][0]) or not _number(connection[key][1]):return _walk_fail("대한문 방향이 잘못됐습니다.")
	for v in connection.volume_obstacles:
		if not v is Dictionary or not v.get("rings") is Array or not (v.get("bottom") is float or v.get("bottom") is int) or not (v.get("top") is float or v.get("top") is int) or not _number(v.bottom) or not _number(v.top) or v.top<=v.bottom:return _walk_fail("대한문 체적 검사가 없습니다.")
		for poly in v.rings:
			if not poly is Array or poly.is_empty():return _walk_fail("대한문 체적 링이 없습니다.")
			for ring in poly:
				if not ring is Array or ring.size()<4:return _walk_fail("대한문 체적 링이 잘못됐습니다.")
				for p in ring:
					if not p is Array or p.size()!=2 or not _number(p[0]) or not _number(p[1]):return _walk_fail("대한문 체적 좌표가 잘못됐습니다.")
	if not load_collision(world):return _walk_fail(collision_error)
	for id in disabled:
		bodies[id].collision_layer=0
		bodies[id].collision_mask=0
		source_nodes[id].visible=false
	for entry in connection.fragments:_add_fragment(entry,world)
	return true

func _add_fragment(entry: Dictionary,world: Dictionary) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in range(0,entry.vertices.size(),3):
		verts.append(Vector3(entry.vertices[i],entry.vertices[i+1],entry.vertices[i+2]))
		normals.append(Vector3(entry.normals[i],entry.normals[i+1],entry.normals[i+2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=verts
	arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var visual := MeshInstance3D.new()
	visual.name=entry.id
	visual.mesh=mesh
	var material := StandardMaterial3D.new()
	var color: Array=world.display.palette[entry.material]
	material.albedo_color=Color(color[0],color[1],color[2])
	material.roughness=0.92
	visual.material_override=material
	add_child(visual)
	var body := StaticBody3D.new()
	body.name="StaticCollision"
	body.collision_layer=1
	body.collision_mask=14
	body.set_meta("geometry_id",entry.id)
	body.set_meta("source_id",entry.source_id)
	visual.add_child(body)
	var collision := CollisionShape3D.new()
	collision.name="CollisionShape"
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(verts)
	shape.backface_collision=true
	collision.shape=shape
	body.add_child(collision)
	fragments[entry.id]=body

func movement_polygon() -> PackedVector2Array:
	var p := PackedVector2Array()
	for v in connection.movement_ring:p.append(Vector2(v[0],v[1]))
	return p

func _horizontal_distance(point: Vector2,polygons: Array) -> float:
	var nearest := INF
	for poly in polygons:
		var inside := false
		for i in range(poly.size()):
			var ring := PackedVector2Array()
			for p in poly[i]:ring.append(Vector2(p[0],p[1]))
			if i==0:inside=Geometry2D.is_point_in_polygon(point,ring)
			elif Geometry2D.is_point_in_polygon(point,ring):inside=false
			for j in range(ring.size()-1):nearest=minf(nearest,point.distance_to(Geometry2D.get_closest_point_to_segment(point,ring[j],ring[j+1])))
		if inside:return 0.0
	return nearest

func volume_penetration(point: Vector3,height: float,radius: float) -> float:
	var worst := 0.0
	for obstacle in connection.volume_obstacles:
		var dy: float=maxf(maxf(obstacle.bottom-(point.y+height-radius),(point.y+radius)-obstacle.top),0.0)
		var dx:=_horizontal_distance(Vector2(point.x,point.z),obstacle.rings)
		worst=maxf(worst,radius-sqrt(dx*dx+dy*dy))
	return worst

func volume_clear(point: Vector3,height: float,radius: float) -> bool:
	return volume_penetration(point,height,radius+0.005)<=0.0

func _walk_fail(message: String) -> bool:
	walk_error=message
	return false

func _number(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(v)
