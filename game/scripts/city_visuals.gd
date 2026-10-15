extends Node3D
## L03 changes visible surfaces only; inherited bodies stay on their original nodes.
const TARGETS := ["city_hall", "library", "plaza", "sfc"]
var bundle: Dictionary = {}
var components := {}
var originals := {}
var load_error := ""
var loaded := false

func apply_to(city: Node3D) -> bool:
	var manifest_path := "res://data/generated/city_landmarks_manifest.json"
	var data_path := "res://data/generated/city_landmarks.json"
	if not FileAccess.file_exists(manifest_path) or not FileAccess.file_exists(data_path):
		return _fail("도시 외형 자료를 준비해주세요.")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if not manifest is Dictionary or not parsed is Dictionary:
		return _fail("도시 외형 자료 형식이 다릅니다.")
	if manifest.get("schema_version") != 1 or manifest.get("task") != "L03" or parsed.get("schema_version") != 1 or parsed.get("task") != "L03":
		return _fail("도시 외형 버전이 다릅니다.")
	if not manifest.get("file") is Dictionary or manifest.file.get("path") != data_path or manifest.file.get("sha256") != FileAccess.get_sha256(data_path):
		return _fail("도시 외형 체크섬이 다릅니다.")
	var world_hash := FileAccess.get_sha256("res://resources/world_geometry/world.json")
	if manifest.get("world_sha256") != world_hash or parsed.get("world_sha256") != world_hash or parsed.get("landmark_spec_sha256") != manifest.get("landmark_spec_sha256"):
		return _fail("도시 외형과 원천 배치가 다릅니다.")
	if not parsed.get("palette") is Dictionary or not parsed.get("landmarks") is Array or parsed.landmarks.size() != 4:
		return _fail("도시 외형 대상이 다릅니다.")
	var ids := []
	var component_ids := []
	for item in parsed.landmarks:
		if not item is Dictionary or not TARGETS.has(item.get("id")) or ids.has(item.id) or not item.get("components") is Array or item.components.is_empty():
			return _fail("도시 외형이 누락되거나 중복됐습니다.")
		ids.append(item.id)
		for entry in item.components:
			if not entry is Dictionary or not entry.get("id") is String or component_ids.has(entry.id) or not parsed.palette.has(entry.get("material")):
				return _fail("도시 외형 부품이 다릅니다.")
			component_ids.append(entry.id)
			if not entry.get("vertices") is Array or not entry.get("normals") is Array or entry.vertices.size() < 9 or entry.vertices.size() % 9 != 0 or entry.vertices.size() != entry.normals.size():
				return _fail("도시 외형 삼각형이 다릅니다.")
			for v in entry.vertices + entry.normals:
				if not _number(v): return _fail("도시 외형 좌표가 다릅니다.")
	for rgb in parsed.palette.values():
		if not rgb is Array or rgb.size() != 3: return _fail("도시 재질이 다릅니다.")
		for value in rgb:
			if not _number(value) or value < 0 or value > 1: return _fail("도시 색이 다릅니다.")
	if not parsed.get("hidden_mesh_ids") is Array or not parsed.get("hidden_fragment_ids") is Array or not parsed.hidden_fragment_ids.is_empty():
		return _fail("도시 외형 교체 목록이 다릅니다.")
	for id in parsed.hidden_mesh_ids:
		if not city.source_nodes.has(id): return _fail("도시 원본 외형이 없습니다.")
	for id in parsed.hidden_fragment_ids:
		if not city.fragments.has(id): return _fail("도시 원본 부품이 없습니다.")
	# Complete validation precedes any visual mutation. No CollisionObject is created.
	bundle = parsed
	var materials := {}
	for key in bundle.palette:
		var rgb: Array = bundle.palette[key]
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(rgb[0], rgb[1], rgb[2])
		material.roughness = 0.9
		materials[key] = material
	for item in bundle.landmarks:
		var landmark := Node3D.new()
		landmark.name = item.id
		landmark.set_meta("feature_id", item.feature_id)
		add_child(landmark)
		for entry in item.components:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			for i in range(0, entry.vertices.size(), 3):
				vertices.append(Vector3(entry.vertices[i], entry.vertices[i+1], entry.vertices[i+2]))
				normals.append(Vector3(entry.normals[i], entry.normals[i+1], entry.normals[i+2]))
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, materials[entry.material])
			var visual := MeshInstance3D.new()
			visual.name = entry.id.replace(":", "_")
			visual.mesh = mesh
			visual.set_meta("component_id", entry.id)
			visual.set_meta("feature_role", entry.feature_role)
			landmark.add_child(visual)
			components[entry.id] = visual
	for id in bundle.hidden_mesh_ids: originals[city.source_nodes[id]] = city.source_nodes[id].visible
	for id in bundle.hidden_fragment_ids:
		var original: Node3D = city.fragments[id].get_parent()
		originals[original] = original.visible
	show_authored(true)
	loaded = true
	return true

func show_authored(enabled: bool) -> void:
	visible = enabled
	for node in originals: node.visible = false if enabled else originals[node]

func _number(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(v)

func _fail(message: String) -> bool:
	load_error = message
	return false
