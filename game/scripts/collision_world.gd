extends "res://scripts/base_world.gd"
## P04 static surface shells only; source display data and permissions are unchanged.
var bodies := {}
var plan: Dictionary = {}
var rules: Dictionary = {}
var collision_ok := false
var collision_error := ""

func _hash(path: String) -> String:
	return FileAccess.get_sha256(path)

func load_collision(world: Dictionary) -> bool:
	collision_ok = false
	collision_error = ""
	var rules_path := "res://resources/collision/rules.json"
	var plan_path := "res://resources/collision/generated.json"
	for path in [rules_path,plan_path]:
		if not FileAccess.file_exists(path):return _fail("충돌 자료가 없습니다. 준비 도구를 실행해주세요.")
	var raw_rules = JSON.parse_string(FileAccess.get_file_as_string(rules_path))
	var raw_plan = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	if not raw_rules is Dictionary or not raw_plan is Dictionary:return _fail("충돌 자료 형식이 잘못됐습니다.")
	rules = raw_rules
	plan = raw_plan
	var roles := {"static_world":{"layer_number":1,"layer":1,"mask":14},"player":{"layer_number":2,"layer":2,"mask":13},"pedestrian":{"layer_number":3,"layer":4,"mask":15},"vehicle":{"layer_number":4,"layer":8,"mask":15}}
	if rules.get("body_roles")!=JSON.parse_string(JSON.stringify(roles)) or rules.get("camera_query")!=JSON.parse_string(JSON.stringify({"layer":null,"mask":1,"exclude_player_rid":true})):return _fail("지원하지 않는 충돌 행렬입니다.")
	if rules.get("static_selection")!={"roles":["Buildings","Barriers"],"ground_ids":["temporary_support"],"shape":"ConcavePolygonShape3D","backface_collision":true}:return _fail("충돌 선택 정책이 다릅니다.")
	if plan.get("schema_version")!=1 or plan.get("task")!="P04" or rules.get("schema_version")!=1 or rules.get("task")!="P04":return _fail("충돌 단계/버전이 다릅니다.")
	var expected_scope := {"runtime_permission":null,"walkability_verified":false,"physical_terrain_verified":false,"playable_boundary":null,"spawn":null,"gate_openings":"W01_pending","support_plane":"G03 temporary engineering plane only"}
	if rules.get("scope")!=expected_scope or plan.get("scope")!=expected_scope:return _fail("충돌 자료가 통행/지형/문을 승인하지 않습니다.")
	if plan.get("world_file")!="res://resources/world_geometry/world.json" or plan.get("rules_file")!=rules_path or plan.get("world_sha256")!=_hash("res://resources/world_geometry/world.json") or plan.get("rules_sha256")!=_hash(rules_path) or plan.get("region_sha256")!=world.coordinate_contract_sha256:return _fail("충돌 자료와 도시/규칙 체크섬이 다릅니다.")
	if not plan.get("entries") is Array or not plan.get("excluded") is Array:return _fail("충돌 목록이 없습니다.")
	var by_id := {}
	var expected := {}
	for m in world.meshes:
		by_id[m.id] = m
		if m.role in ["Buildings","Barriers"] or m.id=="temporary_support":expected[m.id]=m
	var found := {}
	for entry in plan.entries:
		if not entry is Dictionary or not expected.has(entry.get("mesh_id")) or found.has(entry.get("mesh_id")):return _fail("충돌 ID가 중복됐거나 보기용 면이 포함됐습니다.")
		var m: Dictionary=expected[entry.mesh_id]
		if entry.get("role")!=m.role or entry.get("triangles")!=m.vertices.size()/9 or entry.get("holes")!=m.topology.holes or entry.get("layer")!=1 or entry.get("mask")!=14 or entry.get("shape")!="ConcavePolygonShape3D" or entry.get("backface_collision")!=true or not entry.has("runtime_permission") or entry.runtime_permission!=null:return _fail("충돌 형상/계층/권한 계약이 다릅니다.")
		found[entry.mesh_id]=true
	if found.size()!=expected.size():return _fail("도시 충돌체가 누락됐습니다.")
	var excluded := {}
	for entry in plan.excluded:
		if not entry is Dictionary or not by_id.has(entry.get("mesh_id")) or expected.has(entry.get("mesh_id")) or excluded.has(entry.get("mesh_id")):return _fail("충돌 제외 목록이 다릅니다.")
		excluded[entry.mesh_id]=true
	if excluded.size()+found.size()!=world.meshes.size():return _fail("충돌/보기용 목록이 완전하지 않습니다.")
	if plan.get("counts")!=JSON.parse_string(JSON.stringify({"colliders":685,"roles":{"Ground":1,"Buildings":635,"Barriers":49},"triangles":20302,"excluded":548})):return _fail("현재 지역 충돌 집계가 다릅니다.")
	populate(world)
	bodies.clear()
	for entry in plan.entries:
		var mesh_node: MeshInstance3D=source_nodes[entry.mesh_id]
		var arrays: Array=mesh_node.mesh.surface_get_arrays(0)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(arrays[Mesh.ARRAY_VERTEX])
		shape.backface_collision=true
		var body := StaticBody3D.new()
		body.name="StaticCollision"
		body.collision_layer=1
		body.collision_mask=14
		body.set_meta("geometry_id",entry.mesh_id)
		body.set_meta("collision_scope",{"runtime_permission":null})
		mesh_node.add_child(body)
		var collision := CollisionShape3D.new()
		collision.name="CollisionShape"
		collision.shape=shape
		body.add_child(collision)
		bodies[entry.mesh_id]=body
	collision_ok=true
	return true

func set_collision_enabled(enabled: bool) -> void:
	for body in bodies.values():
		body.collision_layer=1 if enabled else 0
		body.collision_mask=14 if enabled else 0

func _fail(message: String) -> bool:
	collision_error=message
	return false
