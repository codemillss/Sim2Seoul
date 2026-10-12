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
	if manifest.get("schema_version") != 1 or manifest.get("stage") != "E02_structure_only":
		return _failure("지원하지 않는 런타임 manifest 버전 또는 단계입니다.")
	if not manifest.get("assets") is Array or not manifest.assets.is_empty():
		return _failure("E02에는 아직 서울 자산을 연결하지 않습니다.")
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
	return {"ok":true, "manifest":manifest, "region":region}

func _read_object(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("로컬 실행 자료가 없습니다. 실행 준비 도구를 실행해주세요.")
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return _failure("로컬 실행 자료의 JSON 형식이 잘못됐습니다.")
	return {"ok":true, "value":parser.data}

func _failure(message: String) -> Dictionary:
	return {"ok":false, "error":message}
