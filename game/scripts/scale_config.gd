extends RefCounted
## E04 only; standard game world keeps its E03 contract and assets.
func read_scale(world_state: Dictionary) -> Dictionary:
	var manifest_path := "res://data/generated/scale_manifest.json"
	var data_path := "res://data/generated/scale_view.json"
	var manifest = _object(manifest_path)
	if not manifest is Dictionary or manifest.get("schema_version") != 1 or manifest.get("task") != "E04" or manifest.get("file") != data_path:
		return {"ok":false,"error":"고정 검증 자료를 준비해주세요."}
	if not FileAccess.file_exists(data_path):
		return {"ok":false,"error":"고정 검증 자료가 없습니다."}
	var bytes := FileAccess.get_file_as_bytes(data_path)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	if hashing.finish().hex_encode() != manifest.get("sha256") or bytes.size() != manifest.get("bytes"):
		return {"ok":false,"error":"고정 검증 자료의 체크섬 또는 크기가 다릅니다."}
	var data = _object(data_path)
	if not data is Dictionary or data.get("task") != "E04" or data.get("schema_version") != 1 or data.get("world_sha256") != world_state.manifest.assets[0].sha256 or manifest.get("world_sha256") != data.world_sha256 or data.get("coordinate_contract_sha256") != world_state.manifest.source_contract.sha256:
		return {"ok":false,"error":"고정 검증 자료가 현재 서울 배치/좌표 계약과 다릅니다."}
	if not data.get("anchors") is Array or data.anchors.size()!=7 or not data.get("controls") is Array or data.controls.size()!=5 or not data.get("distance_pairs") is Array or data.distance_pairs.size()!=4:
		return {"ok":false,"error":"고정 검증 지점·거리·기준물 목록이 잘못됐습니다."}
	for point in data.anchors:
		if not point is Dictionary or not point.get("id") is String or not point.get("feature_id") is String or not point.get("name") is String or point.get("source_point_kind") != "lexicographically_first_outer_ring_vertex_not_entrance_centroid_or_spawn" or not _vector(point.get("world_xyz_m")):
			return {"ok":false,"error":"대표점의 정의 또는 위치가 잘못됐습니다."}
	var anchor_ids := {}
	for point in data.anchors:
		if anchor_ids.has(point.id):return {"ok":false,"error":"대표점 ID가 중복됐습니다."}
		anchor_ids[point.id]=true
	var expected := {"grid_east_10m":[10,0,0],"grid_west_10m":[-10,0,0],"grid_north_10m":[0,0,-10],"grid_south_10m":[0,0,10],"local_up_10m":[0,10,0]}
	var control_ids := {}
	for control in data.controls:
		if not control is Dictionary or not control.get("id") is String or not _vector(control.get("expected_world_xyz_m")) or not expected.has(control.id) or not _same_vector(control.expected_world_xyz_m,expected[control.id]) or control_ids.has(control.id):
			return {"ok":false,"error":"10m 기준물의 위치가 잘못됐습니다."}
		control_ids[control.id]=true
	for pair in data.distance_pairs:
		if not pair is Dictionary or not anchor_ids.has(pair.get("from")) or not anchor_ids.has(pair.get("to")) or not pair.get("names") is Array or pair.names.size()!=2 or typeof(pair.get("projected_distance_m")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(pair.projected_distance_m)) or pair.projected_distance_m<=0:
			return {"ok":false,"error":"거리 기준의 형식이 잘못됐습니다."}
	var settings = data.get("settings")
	if not settings is Dictionary or not settings.get("views") is Dictionary or not settings.get("cube") is Dictionary or not _vector(settings.cube.get("position")) or settings.cube.get("edge_m")!=10:
		return {"ok":false,"error":"고정 시점 또는 큐브 기준이 잘못됐습니다."}
	for key in ["map","axes","oblique"]:
		var view = settings.views.get(key)
		if not view is Dictionary or not _vector(view.get("position")) or not _vector(view.get("target")) or view.position==view.target or view.get("projection")!="orthogonal" or not view.get("title") is String or typeof(view.get("size_m")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(view.size_m)) or view.size_m<=0:
			return {"ok":false,"error":"고정 시점의 형식이 잘못됐습니다."}
	return {"ok":true,"data":data}

func _object(path: String):
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _vector(value) -> bool:
	if not value is Array or value.size()!=3: return false
	for scalar in value:
		if typeof(scalar) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(scalar)):return false
	return true

func _same_vector(a: Array, b: Array) -> bool:
	for i in range(3):
		if float(a[i])!=float(b[i]):return false
	return true
