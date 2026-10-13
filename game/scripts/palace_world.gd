extends "res://scripts/daehanmun_connection.gd"
## Separate W02 scene. W01 authored sources/runtime bundles remain unchanged.
var palace: Dictionary = {}
var movement_cache := []
var volume_cache := []

func load_connection(world: Dictionary) -> bool:
	var manifest_path := "res://data/generated/palace_manifest.json"
	if not FileAccess.file_exists(manifest_path):return _walk_fail("경내 자료를 준비해주세요.")
	var m = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not m is Dictionary or m.get("task")!="W02" or m.get("schema_version")!=1:return _walk_fail("경내 자료 버전이 다릅니다.")
	if m.get("world_sha256")!=_hash("res://resources/world_geometry/world.json") or m.get("w01_sha256")!=_hash("res://data/generated/daehanmun.json") or m.get("region_sha256")!=world.coordinate_contract_sha256:return _walk_fail("경내 자료의 원천이 다릅니다.")
	for item in [["connection","res://data/generated/palace_walk.json"],["decision","res://data/generated/palace_decision.json"]]:
		if not m.get("files") is Dictionary or not m.files.get(item[0]) is Dictionary:return _walk_fail("경내 파일 목록이 없습니다.")
		var f: Dictionary=m.files[item[0]]
		if f.get("path")!=item[1] or not FileAccess.file_exists(item[1]) or f.get("sha256")!=_hash(item[1]):return _walk_fail("경내 파일 체크섬이 다릅니다.")
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/palace_walk.json"))
	var manual = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/palace_decision.json"))
	if not data is Dictionary or not manual is Dictionary or data.get("schema_version")!=1 or data.get("task")!="W02" or manual.get("task")!="W02":return _walk_fail("경내 자료 형식이 다릅니다.")
	if not manual.get("scope") is Dictionary or data.get("scope")!=manual.scope or manual.scope.get("physical_terrain_verified")!=false or manual.scope.get("real_world_access_verified")!=false or not manual.scope.has("global_playable_boundary") or manual.scope.global_playable_boundary!=null:return _walk_fail("경내 임시 지면/접근 범위가 다릅니다.")
	if manual.get("ground_y_m")!=0 or manual.get("path_width_m")!=2.4 or manual.get("movement_edge_margin_m")!=0.4:return _walk_fail("지원하지 않는 경내 설정입니다.")
	if not data.get("support") is Dictionary:return _walk_fail("경내 지원면이 없습니다.")
	var s: Dictionary=data.support
	if s.get("id")!="W02_support" or s.get("role")!="Ground" or s.get("material")!="support" or s.get("bottom_y_m")!=-0.2 or s.get("top_y_m")!=0:return _walk_fail("경내 지원면 역할이 다릅니다.")
	if not s.get("vertices") is Array or not s.get("normals") is Array or s.vertices.size()<9 or s.vertices.size()%9!=0 or s.vertices.size()!=s.normals.size():return _walk_fail("경내 메시 배열이 다릅니다.")
	for v in s.vertices+s.normals:
		if not _number(v):return _walk_fail("경내 메시 숫자가 다릅니다.")
	var counts := {"source_bodies":685,"active_source_bodies":682,"retained_gate_wall_fragments":4,"active_bodies":687,"created_bodies":691,"support_triangles":s.vertices.size()/9}
	if data.get("counts")!=JSON.parse_string(JSON.stringify(counts)):return _walk_fail("경내 충돌 집계가 다릅니다.")
	if not _valid_rings(data.get("movement_rings")):return _walk_fail("경내 보행 영역이 다릅니다.")
	if not data.get("routes") is Array or data.routes.size()!=3:return _walk_fail("경내 경로 목록이 없습니다.")
	for i in range(3):
		var r=data.routes[i]
		if not r is Dictionary or r.get("id")!=["entrance","palace_loop","court_approach"][i] or not r.get("xz") is Array or r.xz.size()<2 or not _number(r.get("length_m")) or r.length_m<=0:return _walk_fail("경내 경로 형식이 다릅니다.")
		for p in r.xz:
			if not _valid_xz(p):return _walk_fail("경내 경로 숫자가 다릅니다.")
	if not data.get("volume_obstacles") is Array or not data.get("checkpoints") is Array or data.checkpoints.size()!=5:return _walk_fail("경내 체적/표식 목록이 없습니다.")
	for v in data.volume_obstacles:
		if not v is Dictionary or not _valid_rings(v.get("rings")) or not _number(v.get("bottom")) or not _number(v.get("top")) or v.top<=v.bottom:return _walk_fail("경내 체적이 다릅니다.")
	for c in data.checkpoints:
		if not c is Dictionary or not c.get("name") is String or not _valid_xz(c.get("xz")):return _walk_fail("경내 표식이 다릅니다.")
	if not data.get("spawn") is Array or data.spawn.size()!=3:return _walk_fail("경내 시작점이 없습니다.")
	for v in data.spawn:
		if not _number(v):return _walk_fail("경내 시작점 숫자가 다릅니다.")
	var previous = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/daehanmun.json"))
	if not previous is Dictionary:return _walk_fail("기존 대한문 자료가 다릅니다.")
	for key in ["spawn","route_xz","direction_xz","normal_xz","passage_length_m"]:
		if not data.has(key) or data[key]!=previous.get(key):return _walk_fail("경내 자료가 기존 대한문 시작점/방향을 바꿨습니다.")
	# Reject a bad W02 bundle before creating any P04/W01 bodies.
	if not super.load_connection(world):return false
	palace=data
	fragments.W01_support.collision_layer=0
	fragments.W01_support.collision_mask=0
	fragments.W01_support.get_parent().visible=false
	_add_fragment(palace.support,world)
	connection=palace
	movement_cache=_packed_rings(palace.movement_rings)
	volume_cache.clear()
	for v in palace.volume_obstacles:volume_cache.append({"rings":_packed_rings(v.rings),"bottom":v.bottom,"top":v.top})
	return true

func _valid_xz(p: Variant) -> bool:
	return p is Array and p.size()==2 and _number(p[0]) and _number(p[1])

func _valid_rings(value: Variant) -> bool:
	if not value is Array or value.is_empty():return false
	for poly in value:
		if not poly is Array or poly.is_empty():return false
		for ring in poly:
			if not ring is Array or ring.size()<4:return false
			for p in ring:
				if not _valid_xz(p):return false
	return true

func _packed_rings(value: Array) -> Array:
	var result:=[]
	for poly in value:
		var part:=[]
		for ring in poly:
			var packed:=PackedVector2Array()
			for p in ring:packed.append(Vector2(p[0],p[1]))
			part.append(packed)
		result.append(part)
	return result

func _ring_contains(point: Vector2,ring: PackedVector2Array) -> bool:
	# Explicit horizontal crossing avoids the observed false negative in a long
	# buffered path polygon. Arithmetic uses scalar floats; source rings are unchanged.
	var inside:=false
	for i in range(ring.size()-1):
		var a:=ring[i]
		var b:=ring[i+1]
		if (a.y>point.y)!=(b.y>point.y):
			var crossing: float=float(b.x-a.x)*float(point.y-a.y)/float(b.y-a.y)+float(a.x)
			if float(point.x)<crossing:inside=not inside
	return inside

func _contains(point: Vector2,parts: Array) -> bool:
	for poly in parts:
		if not _ring_contains(point,poly[0]):continue
		var hole:=false
		for i in range(1,poly.size()):
			if _ring_contains(point,poly[i]):hole=true;break
		if not hole:return true
	return false

func movement_contains(point: Vector2) -> bool:
	return point.is_finite() and _contains(point,movement_cache)

func volume_penetration(point: Vector3,height: float,radius: float) -> float:
	var worst:=0.0
	var xz:=Vector2(point.x,point.z)
	for obstacle in volume_cache:
		var dy: float=maxf(maxf(obstacle.bottom-(point.y+height-radius),(point.y+radius)-obstacle.top),0.0)
		var dx:=0.0
		if not _contains(xz,obstacle.rings):
			dx=INF
			for poly in obstacle.rings:
				for ring in poly:
					for j in range(ring.size()-1):dx=minf(dx,xz.distance_to(Geometry2D.get_closest_point_to_segment(xz,ring[j],ring[j+1])))
		worst=maxf(worst,radius-sqrt(dx*dx+dy*dy))
	return worst
