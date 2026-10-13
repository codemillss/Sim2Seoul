extends Resource
## The authored resource names the bundle. All coordinate values come from region.json.
@export_file("*.json") var manifest_path := "res://data/generated/manifest.json"

func read_runtime() -> Dictionary:
	if manifest_path != "res://data/generated/manifest.json":
		return _failure("런타임 manifest 경로가 허용된 프로젝트 경로와 다릅니다.")
	var manifest_result := _read_object(manifest_path)
	if not manifest_result.ok:
		return manifest_result
	var manifest: Dictionary = manifest_result.value
	if manifest.get("schema_version") != 2 or manifest.get("stage") != "E03_display_only":
		return _failure("지원하지 않는 런타임 manifest 버전 또는 단계입니다.")
	if not manifest.get("assets") is Array or manifest.assets.size() != 1:
		return _failure("도시 표시 자료 목록이 잘못됐습니다.")
	if manifest.get("region_file") != "res://data/generated/region.json":
		return _failure("좌표 설정 경로가 허용된 로컬 경로와 다릅니다.")
	var source = manifest.get("source_contract")
	if not source is Dictionary or source.get("file") != "config/region.json":
		return _failure("좌표 원천 기록이 없습니다.")
	var region_path: String = manifest.region_file
	if not FileAccess.file_exists(region_path):
		return _failure("로컬 좌표 설정이 없습니다. 실행 준비 도구를 실행해주세요.")
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(FileAccess.get_file_as_bytes(region_path))
	if hashing.finish().hex_encode() != source.get("sha256"):
		return _failure("좌표 설정의 체크섬이 다릅니다. 원천에서 다시 준비해주세요.")
	var region_result := _read_object(region_path)
	if not region_result.ok:
		return region_result
	var region: Dictionary = region_result.value
	var expected := {
		"region_id": "deoksugung_cityhall",
		"coordinate_contract_version": 1,
		"source_crs": "EPSG:4326", "metric_crs": "EPSG:32652",
		"world_axes": {"x":"east", "y":"up", "z":"south"},
		"meters_per_world_unit": 1.0,
		"origin_role": "fixed_technical_origin_not_spawn_point",
		"bbox_role": "data_investigation_only",
		"vertical_datum": "not_yet_resolved", "playable_boundary": null
	}
	for field in expected:
		if not region.has(field) or region[field] != expected[field]:
			return _failure("지원하지 않는 좌표 계약: %s" % field)
	var origin = region.get("origin_lon_lat")
	if not origin is Array or origin.size() != 2:
		return _failure("고정 원점의 형식이 잘못됐습니다.")
	for value in origin:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return _failure("고정 원점에 유효하지 않은 값이 있습니다.")
	var asset = manifest.assets[0]
	if not asset is Dictionary or asset.get("path") != "res://resources/world_geometry/world.json":
		return _failure("도시 표시 자료 경로가 허용된 로컬 경로와 다릅니다.")
	var asset_path: String = asset.path
	if not FileAccess.file_exists(asset_path):
		return _failure("도시 표시 자료가 없습니다. 실행 준비 도구를 실행해주세요.")
	var world_bytes := FileAccess.get_file_as_bytes(asset_path)
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(world_bytes)
	if hashing.finish().hex_encode() != asset.get("sha256") or world_bytes.size() != asset.get("bytes"):
		return _failure("도시 표시 자료의 크기 또는 체크섬이 다릅니다.")
	var world_result := _read_object(asset_path)
	if not world_result.ok:
		return world_result
	var world: Dictionary = world_result.value
	if world.get("schema_version") != 1 or world.get("task") != "E03" or world.get("coordinate_contract_sha256") != source.get("sha256"):
		return _failure("도시 표시 자료의 좌표 계약 또는 단계가 다릅니다.")
	if world.get("scope") != {"collision":false,"walkability_verified":false,"physical_terrain_verified":false,"playable_boundary":null,"spawn":null}:
		return _failure("표시용 도시 자료의 검증 범위가 다릅니다.")
	var coords = world.get("coordinate_system")
	if not coords is Dictionary or coords.get("world_axes") != region.world_axes or coords.get("origin_lon_lat") != region.origin_lon_lat or coords.get("unit") != "metre" or coords.get("projected_crs") != region.metric_crs:
		return _failure("도시 표시의 축·단위·원점이 좌표 계약과 다릅니다.")
	var display = world.get("display")
	if not display is Dictionary or not display.get("views") is Dictionary or not display.get("palette") is Dictionary:
		return _failure("도시 표시 설정이 잘못됐습니다.")
	for key in ["overview","top","palace"]:
		var view = display.views.get(key)
		if not view is Dictionary or not _finite_vector(view.get("position"),3) or not _finite_vector(view.get("target"),3) or typeof(view.get("size_m")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(view.size_m)) or view.size_m <= 0:
			return _failure("도시 표시 시점이 잘못됐습니다.")
	for rgb in display.palette.values():
		if not _finite_vector(rgb,3):
			return _failure("도시 표시 색상이 잘못됐습니다.")
	if not world.get("landmarks") is Array:
		return _failure("대표 지점 목록이 잘못됐습니다.")
	for anchor in world.landmarks:
		if not anchor is Dictionary or not anchor.get("name") is String or not _finite_vector(anchor.get("position"),3):
			return _failure("대표 지점의 위치가 잘못됐습니다.")
	if not world.get("meshes") is Array or world.meshes.is_empty() or not world.get("counts") is Dictionary or world.counts.get("meshes") != world.meshes.size():
		return _failure("도시 표시 도형 목록이 잘못됐습니다.")
	var ids := {}
	for mesh in world.meshes:
		if not mesh is Dictionary or not mesh.get("id") is String or ids.has(mesh.id):
			return _failure("도시 표시 도형 ID가 잘못됐거나 중복됐습니다.")
		ids[mesh.id] = true
		if mesh.get("role") not in ["Ground","Buildings","Routes","Barriers"] or not world.get("display") is Dictionary or not world.display.get("palette") is Dictionary or not world.display.palette.has(mesh.get("material")):
			return _failure("도시 표시 역할 또는 재질이 잘못됐습니다.")
		if not mesh.get("metadata") is Dictionary or not mesh.metadata.has("runtime_permission") or mesh.metadata.get("runtime_permission") != null or mesh.metadata.get("collision_generated") != false:
			return _failure("도시 표시는 아직 통행이나 충돌을 승인하지 않습니다.")
		var vertices = mesh.get("vertices")
		var normals = mesh.get("normals")
		if not vertices is Array or not normals is Array or vertices.is_empty() or vertices.size()%9 != 0 or vertices.size() != normals.size():
			return _failure("도시 도형의 삼각형 배열이 잘못됐습니다.")
		for values in [vertices,normals]:
			for value in values:
				if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)):
					return _failure("도시 도형에 유효하지 않은 숫자가 있습니다.")
	return {"ok":true, "manifest":manifest, "region":region, "world":world}

func _finite_vector(value, length: int) -> bool:
	if not value is Array or value.size() != length:
		return false
	for component in value:
		if typeof(component) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(component)):
			return false
	return true

func _read_object(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("로컬 실행 자료가 없습니다. 실행 준비 도구를 실행해주세요.")
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return _failure("로컬 실행 자료의 JSON 형식이 잘못됐습니다.")
	return {"ok":true, "value":parser.data}

func _failure(message: String) -> Dictionary:
	return {"ok":false, "error":message}
