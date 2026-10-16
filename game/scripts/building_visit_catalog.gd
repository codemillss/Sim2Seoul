extends RefCounted
## EXP04 source-sized game interiors. Exact source rings and their holes are
## preserved in the authored snapshot; the prepared floor rectangle fits inside
## that source envelope. Doors and indoor layouts are game assumptions.
const SOURCE_PATH := "res://assets/authored/interiors/source_catalog.json"
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
	for source: Dictionary in raw.records:
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
			"game_layout_basis": "원본 외곽 안에 맞춘 게임 실내 · 실제 평면도 미확인",
		}
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
