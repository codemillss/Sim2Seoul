extends Node3D
## Stylized background exteriors, not surveyed facades or factual shopfronts.
## Only material overrides change. Source vertices, bodies and landmarks stay intact.
const FACADE_SHADER: Shader = preload("res://shaders/city_facade.gdshader")
const WEB_FACADE_SHADER: Shader = preload("res://shaders/city_facade_web.gdshader")
const WALL_COLORS := [
	Color(0.73, 0.72, 0.67), Color(0.64, 0.67, 0.67),
	Color(0.77, 0.74, 0.67), Color(0.61, 0.60, 0.57),
	Color(0.67, 0.63, 0.58), Color(0.72, 0.73, 0.71),
	Color(0.58, 0.65, 0.67), Color(0.64, 0.58, 0.54),
]

var building_count := 0
var material_count := 0
var load_error := ""
var loaded := false
var _materials := {}
var _web_materials: Array[ShaderMaterial] = []
var _city: Node3D
var identity_profiles: Dictionary={}

func setup(city: Node3D) -> bool:
	if loaded:
		return _fail("일반 건물 외형은 이미 적용됐습니다.")
	if not is_instance_valid(city):
		return _fail("일반 건물 외형의 도시 노드를 찾지 못했습니다.")
	_city=city
	var sources: Variant = city.get("source_nodes")
	if not sources is Dictionary:
		return _fail("일반 건물 외형의 원본 목록이 없습니다.")
	var path := "res://resources/world_geometry/world.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("일반 건물 외형의 도시 자료를 읽지 못했습니다.")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.get("meshes") is Array:
		return _fail("일반 건물 외형의 도시 자료 형식이 다릅니다.")
	var targets: Array[Dictionary] = []
	for entry: Variant in parsed.meshes:
		if not entry is Dictionary:
			return _fail("일반 건물 외형의 원본 항목이 다릅니다.")
		# Civic/historic materials retain their existing identity. L02/L03 source
		# meshes have already been hidden before this optional V0 helper runs.
		if entry.get("role") != "Buildings" or entry.get("material") != "building":
			continue
		var id: String = str(entry.get("id", ""))
		var source := sources.get(id) as MeshInstance3D
		if source == null or not source.is_visible_in_tree() or source.mesh == null:
			continue
		if source.material_override != null:
			continue
		var bottom: Variant = entry.get("bottom_y_m")
		var top: Variant = entry.get("top_y_m")
		if not _number(bottom) or not _number(top) or float(top) <= float(bottom):
			return _fail("일반 건물 외형의 높이 자료가 다릅니다.")
		targets.append({"node": source, "id": id, "bottom": float(bottom), "top": float(top)})
	if targets.is_empty():
		return _fail("일반 건물 외형을 적용할 표시 원본이 없습니다.")
	# Validate everything before changing any display material. A shared shader
	# and shared cached materials avoid creating geometry for every window.
	for target: Dictionary in targets:
		var source: MeshInstance3D = target.node
		var seed: int = posmod(String(target.id).hash(), 1000003)
		var palette_index: int = posmod(seed, WALL_COLORS.size())
		var height: float=float(target.top)-float(target.bottom)
		var area: float=float((source.get_aabb().size.x*source.get_aabb().size.z))
		var style: int=3 if height>=65. else (2 if height>=28. else (1 if area>=300. else 0))
		var cache_key := palette_index * 4 + style
		if not _materials.has(cache_key):
			_materials[cache_key] = _make_material(palette_index, style)
		if OS.has_feature("web"):
			# GLES3 reserves sixteen UBO slots per instance, even for two values.
			# Own one ordinary-uniform material per building, retaining its seed.
			var own: ShaderMaterial = (_materials[cache_key] as ShaderMaterial).duplicate()
			_web_materials.append(own)
			source.material_override = own
			source.set_meta("web_facade_uniforms",true)
		else:
			source.material_override = _materials[cache_key]
		var base_y: float = source.to_global(Vector3(0.0, target.bottom, 0.0)).y
		var top_y: float = source.to_global(Vector3(0.0, target.top, 0.0)).y
		if OS.has_feature("web"):
			(source.material_override as ShaderMaterial).set_shader_parameter("height_limits_m", Vector2(base_y,top_y))
			(source.material_override as ShaderMaterial).set_shader_parameter("facade_seed", float(seed % 997))
		else:
			source.set_instance_shader_parameter("height_limits_m", Vector2(base_y, top_y))
			source.set_instance_shader_parameter("facade_seed", float(seed % 997))
		source.set_meta("v0_stylized_facade", true)
		source.set_meta("v0_facade_structural_style",style)
		building_count += 1
	material_count = _materials.size()+_web_materials.size()
	loaded = true
	return true

func _make_material(palette_index: int, style: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = WEB_FACADE_SHADER if OS.has_feature("web") else FACADE_SHADER
	material.set_shader_parameter("wall_tint", WALL_COLORS[palette_index])
	material.set_shader_parameter("glass_tint", Color(0.16,0.27,0.31) if style>=2 else Color(0.21,0.27,0.28))
	material.set_shader_parameter("floor_height_m", [3.0,3.25,3.7,4.05][style])
	material.set_shader_parameter("bay_width_m", [2.55,4.4,3.2,2.35][style])
	material.set_shader_parameter("curtain_wall", [0.0,.18,.62,.95][style])
	return material

func set_identity_profile(id: String,profile: String,wall_color: Color) -> bool:
	if not loaded or not is_instance_valid(_city):return false
	var source: MeshInstance3D=_city.source_nodes.get(id) as MeshInstance3D
	if not is_instance_valid(source) or source.mesh==null:return false
	var key: String="identity_"+profile
	if not _materials.has(key):
		var material:=StandardMaterial3D.new();material.albedo_color=wall_color;material.roughness=.84
		_materials[key]=material
	source.material_override=_materials[key]
	source.set_meta("v0_facade_identity_profile",profile);identity_profiles[id]=profile
	material_count=_materials.size()+_web_materials.size()
	return true

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value)

func _fail(message: String) -> bool:
	load_error = message
	return false
