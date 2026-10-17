extends RefCounted
## EXP04 source-sized game interiors. Exact source rings and their holes are
## preserved in the authored snapshot; the prepared floor rectangle fits inside
## that source envelope. Doors and indoor layouts are game assumptions.
const SOURCE_PATH := "res://assets/authored/interiors/source_catalog.json"
const SUPPLEMENTAL_PATH := "res://assets/authored/interiors/supplemental_catalog.json"
const EXTENT_PATH := "res://assets/authored/exploration_extent.json"
const WORLD_PATH := "res://resources/world_geometry/world.json"
const LIBRARY_ID := "osm:relation:10757525:building"

var load_error := ""
var counts: Dictionary = {}
var provenance: Dictionary = {}

func build(host: Node3D) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	load_error = ""
	if not FileAccess.file_exists(SOURCE_PATH):
		load_error = "건물 실내의 원본 외곽 자료가 없습니다."
		return records
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	if not raw is Dictionary or raw.get("schema_version") != 1 or not raw.get("records") is Array:
		load_error = "건물 실내 자료 형식이 다릅니다."
		return records
	if raw.get("world_sha256") != FileAccess.get_sha256(WORLD_PATH):
		load_error = "건물 실내와 현재 도시의 원본이 다릅니다."
		return records
	counts = raw.get("counts", {}).duplicate(true)
	provenance = raw.get("provenance", {}).duplicate(true)
	var sources: Array=raw.records.duplicate(true)
	if FileAccess.file_exists(SUPPLEMENTAL_PATH):
		var extra: Variant=JSON.parse_string(FileAccess.get_file_as_string(SUPPLEMENTAL_PATH))
		if not extra is Dictionary or extra.get("schema_version")!=1 or extra.get("task")!="supplemental_lotte_visit" or not extra.get("records") is Array:
			load_error="추가 건물 실내 자료 형식이 다릅니다.";return records
		if extra.records.size()!=1:
			load_error="추가 실내 자료는 검증된 롯데호텔 한 동이어야 합니다.";return records
		if extra.get("world_sha256")!=FileAccess.get_sha256(WORLD_PATH) or extra.get("base_catalog_sha256")!=FileAccess.get_sha256(SOURCE_PATH) or extra.get("exploration_extent_sha256")!=FileAccess.get_sha256(EXTENT_PATH):
			load_error="추가 실내 자료와 도시·기존 카탈로그·탐험 경계가 다릅니다.";return records
		var world: Variant=JSON.parse_string(FileAccess.get_file_as_string(WORLD_PATH))
		if not world is Dictionary or extra.get("coordinate_contract_sha256")!=world.get("coordinate_contract_sha256"):
			load_error="추가 실내 자료의 좌표 계약이 다릅니다.";return records
		var found: Dictionary={}
		for source: Dictionary in sources:found[String(source.get("id",""))]=true
		for source: Dictionary in extra.records:
			var extra_id: String=String(source.get("id",""))
			if extra_id!="osm:way:117914845:building" or found.has(extra_id) or extra.records.size()!=1:
				load_error="추가 실내 자료에 중복되거나 승인되지 않은 건물이 있습니다.";return records
			found[extra_id]=true;sources.append(source)
		counts["base_records"]=raw.records.size();counts["supplemental_records"]=extra.records.size();counts["records"]=sources.size()
		provenance["supplemental_catalog"]={"path":SUPPLEMENTAL_PATH,"sha256":FileAccess.get_sha256(SUPPLEMENTAL_PATH),"generator_sha256":extra.get("generator_sha256","")}
	for source: Dictionary in sources:
		var id := String(source.get("id", ""))
		if not host.city.source_nodes.has(id): continue
		var floor: Dictionary = source.get("floor", {})
		if float(floor.get("width", 0.0)) < 12.0 or float(floor.get("depth", 0.0)) < 16.0: continue
		if float(floor.get("rectangle_outside_source_m2", 1.0)) > 0.000001: continue
		var source_parts: Array = source.get("source_rings", [])
		var part_index := int(source.get("source_part_index", 0))
		if part_index < 0 or part_index >= source_parts.size(): continue
		var part: Array = source_parts[part_index]
		if part.is_empty(): continue
		var ring := PackedVector2Array()
		for point: Array in part[0]: ring.append(Vector2(float(point[0]), float(point[1])))
		var candidates: Array[Dictionary] = []
		for candidate: Dictionary in source.get("entry_candidates", []):
			candidates.append({
				"door": _xz(candidate.door, 1.5),
				"entrance": _xz(candidate.entrance, 0.08),
				"along": _xz(candidate.along),
				"outward": _xz(candidate.outward),
				"door_width": float(candidate.door_width),
				"source_edge_length": float(candidate.source_edge_length),
				"street_distance": float(candidate.street_distance),
			})
		if id == LIBRARY_ID:
			var civic: Variant = host.get("photo_civic_detail")
			if is_instance_valid(civic) and civic.get("loaded"):
				var outward: Vector3 = civic.entrance_outward_direction
				var entrance: Vector3 = civic.entrance_world_position
				entrance.y = 0.08
				candidates = [{"door": civic.door_world_position,
					"entrance": entrance,
					"along": Vector3(outward.z, 0.0, -outward.x),
					"outward": outward, "door_width": 4.55,
					"source_edge_length": 28.54, "street_distance": 0.0}]
		if candidates.is_empty(): continue
		var selected: Dictionary = candidates[0]
		var record := {
			"id": id, "title": String(source.title), "kind": String(source.kind),
			"width": float(floor.width), "depth": float(floor.depth),
			"floor_height": float(source.floor_height), "floor_count": int(source.floor_count),
			"source_height": float(source.source_height), "source_levels": source.source_levels,
			"height_basis": String(source.height_basis), "floors_basis": String(source.floors_basis),
			"rectangle_center": Vector2(float(floor.rectangle_center[0]), float(floor.rectangle_center[1])),
			"rectangle_along": _xz(floor.along), "rectangle_outward": _xz(floor.outward),
			"along": selected.along, "outward": selected.outward,
			"door": selected.door, "entrance": selected.entrance,
			"door_width": selected.door_width, "entry_candidates": candidates,
			"source_ring": ring, "source_rings": source_parts,
			"source_part_index": part_index,
			"source_footprint_area_m2": float(source.source_footprint_area_m2),
			"rectangle_area_m2": float(floor.rectangle_area_m2),
			"rectangle_outside_source_m2": float(floor.rectangle_outside_source_m2),
			"source_reference_ids": source.source_reference_ids,
			"catalog_origin": String(source.get("catalog_origin","EXP04_base")),
			"game_layout_basis": "원본 외곽 안에 맞춘 게임 실내 · 실제 평면도 미확인",
		}
		_apply_runtime_terrain(host, record)
		records.append(record)
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.id == LIBRARY_ID: return true
		if b.id == LIBRARY_ID: return false
		if a.kind == "civic" and b.kind != "civic": return true
		if b.kind == "civic" and a.kind != "civic": return false
		return String(a.id) < String(b.id))
	return records

func _xz(value: Array, y := 0.0) -> Vector3:
	return Vector3(float(value[0]), y, float(value[1]))

func _apply_runtime_terrain(host: Node3D, record: Dictionary) -> void:
	# Authored JSON and source_height remain unchanged. Only the runtime copy
	# receives a local foundation elevation; source height still means thickness.
	var base_y := 0.0
	var terrain := host.get_node_or_null("TerrainSurface")
	var applied := false
	if is_instance_valid(terrain):
		if terrain.has_method("building_base_y_world"):
			base_y = float(terrain.building_base_y_world(String(record.id)))
		elif terrain.has_method("ground_y_world"):
			base_y = float(terrain.ground_y_world(Vector3(record.rectangle_center.x,0.0,record.rectangle_center.y)))
		applied = is_finite(base_y)
	if not applied:base_y = 0.0
	record["base_offset_m"] = base_y
	record["source_roof_world_y"] = base_y+float(record.source_height)
	record["terrain_elevation_applied"] = applied
	record["flat_source_entrance"] = record.entrance
	record["flat_source_door"] = record.door
	# An outdoor foot anchor is two metres beyond the facade. It follows
	# that exact pavement triangle; a level building foundation is separate.
	var entry_ground_y: float = terrain.ground_y_world(record.flat_source_entrance) if applied else 0.0
	if not is_finite(entry_ground_y):
		record.terrain_elevation_applied=false
		entry_ground_y=base_y
	record["entry_surface_adjustment_m"] = entry_ground_y-base_y
	record["entrance_ground_y_m"] = entry_ground_y
	record.entrance += Vector3.UP*entry_ground_y
	record.door += Vector3.UP*base_y
	for candidate: Dictionary in record.entry_candidates:
		candidate["flat_source_entrance"] = candidate.entrance
		candidate["flat_source_door"] = candidate.door
		var candidate_ground_y: float = terrain.ground_y_world(candidate.flat_source_entrance) if applied else 0.0
		if not is_finite(candidate_ground_y):
			record.terrain_elevation_applied=false
			candidate_ground_y=base_y
		candidate["entry_surface_adjustment_m"] = candidate_ground_y-base_y
		candidate["entrance_ground_y_m"] = candidate_ground_y
		candidate.entrance += Vector3.UP*candidate_ground_y
		candidate.door += Vector3.UP*base_y
