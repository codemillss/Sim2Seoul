extends "res://scripts/palace_world.gd"
## W03 is additive: inherited authored scenes/source geometry remain unchanged.
var public_data: Dictionary = {}
var private_cache := []
var road_cache := []
var crossing_cache := []
var boundary_resource: Resource

func load_connection(world: Dictionary) -> bool:
	var path:="res://data/generated/public_manifest.json"
	if not FileAccess.file_exists(path):return _walk_fail("도심 보행 자료를 준비해주세요.")
	var m=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not m is Dictionary or m.get("task")!="W03" or m.get("schema_version")!=1:return _walk_fail("도심 자료 버전이 다릅니다.")
	if m.get("world_sha256")!=_hash("res://resources/world_geometry/world.json") or m.get("w02_sha256")!=_hash("res://data/generated/palace_walk.json") or m.get("boundary_resource_sha256")!=_hash("res://resources/play_boundary.tres"):return _walk_fail("도심 자료 원천/경계가 다릅니다.")
	for item in [["connection","res://data/generated/public_walk.json"],["decision","res://data/generated/public_decision.json"]]:
		if not m.get("files") is Dictionary or not m.files.get(item[0]) is Dictionary:return _walk_fail("도심 파일 목록이 없습니다.")
		var f: Dictionary=m.files[item[0]]
		if f.get("path")!=item[1] or not FileAccess.file_exists(item[1]) or f.get("sha256")!=_hash(item[1]):return _walk_fail("도심 파일 체크섬이 다릅니다.")
	var data=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/public_walk.json"))
	var manual=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/public_decision.json"))
	if not data is Dictionary or not manual is Dictionary or data.get("task")!="W03" or data.get("schema_version")!=1 or manual.get("task")!="W03":return _walk_fail("도심 자료 형식이 다릅니다.")
	if not manual.get("scope") is Dictionary or data.get("scope")!=manual.scope or manual.scope.get("physical_terrain_verified")!=false or manual.scope.get("real_world_access_verified")!=false or manual.scope.get("global_playable_boundary")!="W03-play-boundary-v1 finalized only for this game scene/source snapshot":return _walk_fail("도심 임시 지면/접근 범위가 다릅니다.")
	if manual.get("ground_y_m")!=0 or manual.get("movement_edge_margin_m")!=.4 or manual.get("road_center_exclusion_m")!=.5:return _walk_fail("지원하지 않는 경계 설정입니다.")
	if not data.get("boundary") is Dictionary or data.boundary.get("finalized_for_scene")!=true or data.boundary.get("contract_id")!="W03-play-boundary-v1" or not _valid_rings(data.boundary.get("support_rings")):return _walk_fail("도심 경계 계약이 다릅니다.")
	boundary_resource=load("res://resources/play_boundary.tres")
	if boundary_resource==null or boundary_resource.contract_id!=data.boundary.contract_id or boundary_resource.runtime_path!="res://data/generated/public_walk.json" or boundary_resource.movement_edge_margin_m!=.4 or boundary_resource.road_center_exclusion_m!=.5:return _walk_fail("경계 리소스 설정이 다릅니다.")
	if not data.get("support") is Dictionary:return _walk_fail("도심 지원면이 없습니다.")
	var s: Dictionary=data.support
	if s.get("id")!="W03_support" or s.get("role")!="Ground" or s.get("material")!="support" or s.get("bottom_y_m")!=-0.2 or s.get("top_y_m")!=0:return _walk_fail("도심 지원면 역할이 다릅니다.")
	if not s.get("vertices") is Array or not s.get("normals") is Array or s.vertices.size()<9 or s.vertices.size()%9!=0 or s.vertices.size()!=s.normals.size():return _walk_fail("도심 메시 배열이 다릅니다.")
	for v in s.vertices+s.normals:
		if not _number(v):return _walk_fail("도심 메시 숫자가 다릅니다.")
	var counts:={"source_bodies":685,"active_source_bodies":682,"retained_gate_wall_fragments":4,"active_bodies":687,"created_bodies":692,"support_triangles":s.vertices.size()/9}
	if data.get("counts")!=JSON.parse_string(JSON.stringify(counts)):return _walk_fail("도심 충돌 집계가 다릅니다.")
	if not _valid_rings(data.get("movement_rings")) or not _valid_rings(data.get("private_rings")):return _walk_fail("도심/사유지 경계 형식이 다릅니다.")
	if not data.get("routes") is Array or data.routes.size()!=5 or data.get("public_routes")!=["city_plaza","stonewall"]:return _walk_fail("도심 경로 목록이 다릅니다.")
	for i in range(5):
		var r=data.routes[i]
		if not r is Dictionary or r.get("id")!=["entrance","palace_loop","court_approach","city_plaza","stonewall"][i] or not r.get("xz") is Array or r.xz.size()<2 or not _number(r.get("length_m")) or r.length_m<=0:return _walk_fail("도심 경로 형식이 다릅니다.")
		for p in r.xz:
			if not _valid_xz(p):return _walk_fail("도심 경로 숫자가 다릅니다.")
	if not data.get("volume_obstacles") is Array or not data.get("checkpoints") is Array or data.checkpoints.size()!=8 or not data.get("crossings") is Array or data.crossings.size()!=3 or not data.get("road_exclusions") is Array:return _walk_fail("도심 체적/표식/접속부가 다릅니다.")
	for v in data.volume_obstacles:
		if not v is Dictionary or not _valid_rings(v.get("rings")) or not _number(v.get("bottom")) or not _number(v.get("top")) or v.top<=v.bottom:return _walk_fail("도심 체적이 다릅니다.")
	for c in data.checkpoints:
		if not c is Dictionary or not c.get("name") is String or not _valid_xz(c.get("xz")):return _walk_fail("도심 표식이 다릅니다.")
	for c in data.crossings:
		if not c is Dictionary or not c.get("id") is String or not c.get("geometry") is Dictionary or c.get("vehicle_controller")!=false or not _geometry_rings(c.geometry):return _walk_fail("도심 접속부 형식이 다릅니다.")
	for r in data.road_exclusions:
		if not r is Dictionary or not r.get("id") is String or not r.get("geometry") is Dictionary or not _geometry_rings(r.geometry):return _walk_fail("차도 경계 형식이 다릅니다.")
	var prior=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/palace_walk.json"))
	if not prior is Dictionary:return _walk_fail("기존 경내 자료가 다릅니다.")
	for key in ["spawn","route_xz","direction_xz","normal_xz","passage_length_m"]:
		if not data.has(key) or data[key]!=prior.get(key):return _walk_fail("기존 대한문 시작점/방향을 바꿨습니다.")
	for i in range(3):
		if data.routes[i]!=prior.routes[i]:return _walk_fail("기존 경내 경로를 바꿨습니다.")
	# All W03 semantic rejection happens before inherited source bodies are created.
	if not super.load_connection(world):return false
	fragments.W02_support.collision_layer=0
	fragments.W02_support.collision_mask=0
	fragments.W02_support.get_parent().visible=false
	_add_fragment(data.support,world)
	public_data=data;palace=data;connection=data
	movement_cache=_packed_rings(data.movement_rings)
	volume_cache.clear()
	for v in data.volume_obstacles:volume_cache.append({"rings":_packed_rings(v.rings),"bottom":v.bottom,"top":v.top})
	private_cache=_packed_rings(data.private_rings)
	for c in data.crossings:crossing_cache.append({"id":c.id,"rings":_packed_rings(_geometry_rings(c.geometry))})
	for r in data.road_exclusions:road_cache.append(_packed_rings(_geometry_rings(r.geometry)))
	return true

func _geometry_rings(g: Dictionary) -> Array:
	var parts: Array=[]
	if g.get("type")=="Polygon":parts=[g.get("coordinates",[])]
	elif g.get("type")=="MultiPolygon":parts=g.get("coordinates",[])
	if parts.is_empty():return []
	return parts if _valid_rings(parts) else []

func crossing_at(point: Vector2) -> String:
	for c in crossing_cache:
		if _contains(point,c.rings):return c.id
	return ""

func boundary_reason(point: Vector2) -> String:
	if _contains(point,private_cache):return "private"
	for parts in road_cache:
		if _contains(point,parts):return "road_outside_source_junction"
	return "unfinished_or_unsupported"
