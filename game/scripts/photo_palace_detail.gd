extends Node3D
## Photo-informed, independently modelled visual detail only.
## Reference: Seoul Metropolitan Government, 2020-10-29, photographs by Oh Se-hun:
## https://mediahub.seoul.go.kr/archives/1504168
## No photograph is imported. Detail dimensions are authored, not surveyed.
## Source meshes/resources, metre coordinates, bodies and the 3 x 3 m passage stay fixed.

const ROOF_TARGETS := ["daehanmun", "junghwajeon", "junghwamun", "jeonggwanheon"]
const CLEAR_PASSAGE_HALF_WIDTH := 1.5
const CLEAR_PASSAGE_HEIGHT := 3.0
const EPS := 0.00001

var loaded := false
var load_error := ""
var mesh_count := 0
var ornament_count := 0
var material_count := 0
var label_count := 0
var hidden_window_count := 0
var rejected_detail_count := 0
var landmark_count := 0
var _groups: Dictionary = {}
var _materials: Dictionary = {}
var _roof_triangles: Dictionary = {}
var _local_rings: Dictionary = {}
var _passage_centre_u := 0.0

func setup(host: Node3D) -> bool:
	if loaded or not is_instance_valid(host):
		return _fail("궁궐 사진 참조 외형의 호스트를 확인하지 못했습니다.")
	var palace := host.get("landmark_visuals") as Node3D
	if palace == null or not palace.get("loaded"):
		return _fail("궁궐 사진 참조에 필요한 기존 외형 자료가 없습니다.")
	var bundle: Dictionary = palace.get("bundle")
	var components: Dictionary = palace.get("components")
	if not bundle.get("landmarks") is Array or components.is_empty():
		return _fail("궁궐 사진 참조의 기존 부품을 확인하지 못했습니다.")
	var city: Node3D = host.get("city") as Node3D
	if city != null:
		var connection: Variant = city.get("connection")
		if connection is Dictionary and connection.get("route_xz") is Array:
			for item: Dictionary in bundle.landmarks:
				if item.id == "daehanmun":
					var point: Array = connection.route_xz[1]
					_passage_centre_u = _local_point(item, Vector3(point[0], 0.0, point[1])).x
	for item: Dictionary in bundle.landmarks:
		if not item.id in ROOF_TARGETS:
			continue
		_cache_item(item)
		_add_roof_details(item)
		if item.id == "daehanmun":
			_apply_daehanmun(item, components)
		landmark_count += 1
	_commit_groups()
	material_count = _materials.size()
	loaded = true
	return true

func _cache_item(item: Dictionary) -> void:
	var polygons: Array = []
	for polygon: Array in item.source_binding.geometry.coordinates:
		var rings: Array = []
		for ring: Array in polygon:
			var local := PackedVector2Array()
			for point: Array in ring:
				var p := _local_point(item, Vector3(point[0], 0.0, point[1]))
				local.append(Vector2(p.x, p.z))
			rings.append(local)
		polygons.append(rings)
	_local_rings[item.id] = polygons
	var triangles: Array = []
	for entry: Dictionary in item.components:
		if entry.id != str(item.id) + "_roof":
			continue
		var vertices: Array = entry.vertices
		for index in range(0, vertices.size(), 9):
			var tri: Array[Vector3] = []
			for corner in range(3):
				var i := index + corner * 3
				tri.append(_local_point(item, Vector3(vertices[i], vertices[i + 1], vertices[i + 2])))
			triangles.append(tri)
	_roof_triangles[item.id] = triangles

func _add_roof_details(item: Dictionary) -> void:
	var bounds: Array = item.orientation.local_bounds_m
	var width := float(bounds[2]) - float(bounds[0])
	var count := clampi(int(width / 0.30), 24, 100)
	var pitch := width / float(count)
	for side: float in [-1.0, 1.0]:
		for index in range(1, count):
			var u := float(bounds[0]) + float(index) * pitch
			var edge: float = _edge_v(item, u, side)
			if not is_finite(edge):
				continue
			var start_v := edge - side * 0.14
			var end_v := start_v - side * 0.52
			var tiles := _material("tile_" + str(index % 3), Color(0.27 + float(index % 3) * 0.023, 0.28 + float(index % 3) * 0.022, 0.27 + float(index % 3) * 0.021), 0.91)
			_add_roof_roll(item, u, start_v, end_v, 0.108, tiles, side)
			if item.id == "daehanmun":
				# Round pale timber ends under the dark tile edge, not new columns.
				var eave_y := _roof_y(item, u, start_v)
				if is_finite(eave_y):
					_add_rafter(item, u, start_v - side * 0.13, start_v - side * 0.64, eave_y - 0.22)
	# A rounded ridge with discrete overlaps. Its crown stays below the retained top.
	var centre_u := (float(bounds[0]) + float(bounds[2])) * 0.5
	var centre_v := (float(bounds[1]) + float(bounds[3])) * 0.5
	var half_ridge := width * 0.5 * float(item.recipe.get("roof_ridge_halfwidth_ratio", 0.58))
	var top: float = item.source_binding.current_top_y_m
	var ridge_count := maxi(4, int(half_ridge * 2.0 / 0.42))
	var ridge_pitch := half_ridge * 2.0 / float(ridge_count)
	for index in range(ridge_count):
		var a := centre_u - half_ridge + float(index) * ridge_pitch + 0.009
		var b := a + ridge_pitch - 0.018
		var vertices: Array[Vector3] = []
		for segment in range(8):
			var angle_a := PI * float(segment) / 8.0
			var angle_b := PI * float(segment + 1) / 8.0
			var p0 := Vector3(a, top - 0.245 + sin(angle_a) * 0.235, centre_v + cos(angle_a) * 0.28)
			var p1 := Vector3(b, p0.y, p0.z)
			var p2 := Vector3(b, top - 0.245 + sin(angle_b) * 0.235, centre_v + cos(angle_b) * 0.28)
			var p3 := Vector3(a, p2.y, p2.z)
			vertices.append_array([p0, p2, p1, p0, p3, p2])
		_add_faces("ridge_tiles", _material("ridge_tile", Color(0.39, 0.39, 0.36), 0.92), item, vertices)

func _add_roof_roll(item: Dictionary, u: float, start_v: float, end_v: float, radius: float, material: Material, side: float) -> void:
	var vertices: Array[Vector3] = []
	var end_vertices: Array[Vector3] = []
	var start_y := _roof_y(item, u, start_v)
	var end_y := _roof_y(item, u, end_v)
	if not is_finite(start_y) or not is_finite(end_y):
		return
	for segment in range(8):
		var a := PI * float(segment) / 8.0
		var b := PI * float(segment + 1) / 8.0
		var p0 := Vector3(u + cos(a) * radius, start_y - 0.025 + sin(a) * radius, start_v)
		var p1 := Vector3(p0.x, end_y - 0.025 + sin(a) * radius, end_v)
		var p2 := Vector3(u + cos(b) * radius, end_y - 0.025 + sin(b) * radius, end_v)
		var p3 := Vector3(p2.x, start_y - 0.025 + sin(b) * radius, start_v)
		if side < 0.0:
			vertices.append_array([p0, p1, p2, p0, p2, p3])
		else:
			vertices.append_array([p0, p2, p1, p0, p3, p2])
		# A dark inset semicircle makes the eave end read as a hollow clay tile.
		var centre := Vector3(u, start_y - 0.025, start_v - side * 0.004)
		var r := radius * 0.65
		var rim_a := Vector3(u + cos(a) * r, centre.y + sin(a) * r, centre.z)
		var rim_b := Vector3(u + cos(b) * r, centre.y + sin(b) * r, centre.z)
		end_vertices.append_array([centre, rim_a, rim_b] if side < 0.0 else [centre, rim_b, rim_a])
	_add_faces("eave_rolls", material, item, vertices)
	_add_faces("hollow_tile_ends", _material("tile_hollow", Color(0.095, 0.105, 0.095), 0.98), item, end_vertices)

func _add_rafter(item: Dictionary, u: float, start_v: float, end_v: float, y: float) -> void:
	var vertices: Array[Vector3] = []
	var radius := 0.056
	for segment in range(8):
		var a := TAU * float(segment) / 8.0
		var b := TAU * float(segment + 1) / 8.0
		var p0 := Vector3(u + cos(a) * radius, y + sin(a) * radius, start_v)
		var p1 := Vector3(p0.x, p0.y, end_v)
		var p2 := Vector3(u + cos(b) * radius, y + sin(b) * radius, end_v)
		var p3 := Vector3(p2.x, p2.y, start_v)
		var centre := Vector3(u, y, start_v)
		if start_v < end_v:
			vertices.append_array([p0, p1, p2, p0, p2, p3, centre, p0, p3])
		else:
			vertices.append_array([p0, p2, p1, p0, p3, p2, centre, p3, p0])
	_add_faces("pale_rafter_ends", _material("rafter_end", Color(0.73, 0.73, 0.62), 0.95), item, vertices)

func _apply_daehanmun(item: Dictionary, components: Dictionary) -> void:
	var dark_timber := _material("deep_timber", Color(0.105, 0.14, 0.105), 0.98)
	var door := _material("door_timber", Color(0.25, 0.12, 0.072), 0.94)
	for entry: Dictionary in item.components:
		var visual := components.get(entry.id) as MeshInstance3D
		if visual == null:
			continue
		if entry.feature_role == "window":
			visual.visible = false
			visual.set_meta("photo_detail_hidden_window", true)
			hidden_window_count += 1
		elif entry.feature_role == "backing":
			visual.material_override = dark_timber if entry.id.ends_with("passage_upper_backing") else door
	var bounds: Array = item.orientation.local_bounds_m
	var u_min := float(bounds[0])
	var u_max := float(bounds[2])
	var width := u_max - u_min
	var columns: Array[float] = []
	for index in range(4):
		columns.append(u_min + width * (float(index) + 0.3) / 3.6)
	var eave: float = float(item.source_binding.current_bottom_y_m) + float(item.source_binding.height_m) * float(item.recipe.eave_ratio)
	for side: float in [-1.0, 1.0]:
		for bay in [0, 2]:
			var left: float = columns[bay] + 0.30
			var right: float = columns[bay + 1] - 0.30
			var middle := (left + right) * 0.5
			var edge := _edge_v(item, middle, side)
			if not is_finite(edge):
				continue
			var v := edge - side * 0.34
			var door_height := minf(4.35, eave - 0.65)
			_add_box("side_panel_doors", door, item, Vector3(middle, door_height * 0.5 + 0.08, v), Vector3(right - left, door_height, 0.12))
			for seam_index in range(1, 12):
				var u := lerpf(left, right, float(seam_index) / 12.0)
				_add_box("door_board_seams", _material("door_seam", Color(0.13, 0.067, 0.043), 0.99), item, Vector3(u, door_height * 0.5 + 0.08, v + side * 0.068), Vector3(0.014, door_height - 0.05, 0.012))
			for rail_y in [0.64, 1.47, 2.34, 3.28]:
				if rail_y >= door_height:
					continue
				_add_box("door_cross_rails", _material("door_rail", Color(0.18, 0.082, 0.046), 0.94), item, Vector3(middle, rail_y, v + side * 0.10), Vector3(right - left - 0.06, 0.115, 0.07))
			_add_box("door_leaf_seam", _material("iron", Color(0.075, 0.07, 0.06), 0.87), item, Vector3(middle, door_height * 0.5 + 0.08, v + side * 0.077), Vector3(0.037, door_height - 0.04, 0.016))
			for offset in [-0.18, 0.18]:
				_add_box("door_iron_plates", _materials.iron, item, Vector3(middle + offset, 1.68, v + side * 0.115), Vector3(0.10, 0.24, 0.035))
		# Strong horizontal timber shadow over the existing clear opening.
		var centre_v := _edge_v(item, _passage_centre_u, side) - side * 0.32
		_add_box("gate_lintel_shadow", dark_timber, item, Vector3(_passage_centre_u, 3.16, centre_v), Vector3(3.36, 0.25, 0.16))
		for column_u: float in columns:
			var edge := _edge_v(item, column_u, side)
			if not is_finite(edge):
				continue
			for step in range(3):
				_add_box("bracket_layers", _material("bracket_green", Color(0.13, 0.25, 0.19), 0.95), item, Vector3(column_u, eave - 0.60 + float(step) * 0.13, edge - side * (0.39 - float(step) * 0.035)), Vector3(0.58 + float(step) * 0.23, 0.095, 0.36 + float(step) * 0.08))
	_add_nameboard(item, eave)

func _add_nameboard(item: Dictionary, eave: float) -> void:
	var u := _passage_centre_u
	var edge := _edge_v(item, u, -1.0)
	if not is_finite(edge):
		return
	var v := edge + 0.16
	var y := eave - 0.83
	_add_box("nameboard_frame", _material("nameboard_frame", Color(0.19, 0.13, 0.075), 0.91), item, Vector3(u, y, v), Vector3(3.45, 0.87, 0.13))
	_add_box("nameboard_face", _material("nameboard_ivory", Color(0.85, 0.79, 0.61), 0.96), item, Vector3(u, y, v - 0.074), Vector3(3.22, 0.69, 0.026))
	var label := Label3D.new()
	label.name = "DaehanmunHistoricNameboard"
	label.text = "大漢門"
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Songti SC", "Songti TC", "Hiragino Mincho ProN", "Noto Serif CJK SC", "serif"])
	label.font = font
	label.font_size = 72
	label.pixel_size = 0.0075
	label.outline_size = 0
	label.modulate = Color(0.10, 0.095, 0.07)
	label.no_depth_test = false
	label.fixed_size = false
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.shaded = true
	label.double_sided = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var orientation: Dictionary = item.orientation
	var u_axis: Array = orientation.u_axis_xz
	var v_axis: Array = orientation.v_axis_xz
	label.transform = Transform3D(Basis(Vector3(u_axis[0], 0.0, u_axis[1]), Vector3.UP, -Vector3(v_axis[0], 0.0, v_axis[1])), _world_point(item, Vector3(u, y, v - 0.095)))
	label.set_meta("authored_photo_detail", true)
	label.set_meta("not_surveyed", true)
	add_child(label)
	label_count += 1

func _add_box(key: String, material: Material, item: Dictionary, centre: Vector3, size: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	var source: PackedVector3Array = box.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = box.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var vertices: Array[Vector3] = []
	for index in indices:
		vertices.append(centre + source[index])
	_add_faces(key, material, item, vertices)

func _add_faces(key: String, material: Material, item: Dictionary, local_vertices: Array[Vector3]) -> void:
	if not _detail_fits(item, local_vertices):
		rejected_detail_count += 1
		return
	var group_key := key + "_" + str(material.get_instance_id())
	if not _groups.has(group_key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_groups[group_key] = {"surface": surface, "material": material, "key": key}
	var surface: SurfaceTool = _groups[group_key].surface
	var orientation: Dictionary = item.orientation
	var u_axis: Array = orientation.u_axis_xz
	var v_axis: Array = orientation.v_axis_xz
	var reflected := Vector3(u_axis[0], 0.0, u_axis[1]).cross(Vector3.UP).dot(Vector3(v_axis[0], 0.0, v_axis[1])) < 0.0
	for index in range(0, local_vertices.size(), 3):
		var a := _world_point(item, local_vertices[index])
		var b := _world_point(item, local_vertices[index + 2 if reflected else index + 1])
		var c := _world_point(item, local_vertices[index + 1 if reflected else index + 2])
		var normal := (c - a).cross(b - a).normalized()
		for point: Vector3 in [a, b, c]:
			surface.set_normal(normal)
			surface.add_vertex(point)
	ornament_count += 1

func _detail_fits(item: Dictionary, vertices: Array[Vector3]) -> bool:
	var bottom: float = item.source_binding.current_bottom_y_m
	var top: float = item.source_binding.current_top_y_m
	for point: Vector3 in vertices:
		if point.y < bottom - EPS or point.y > top + EPS or not _inside(item, Vector2(point.x, point.z)):
			return false
		if item.id == "daehanmun" and point.y < CLEAR_PASSAGE_HEIGHT + EPS and absf(point.x - _passage_centre_u) < CLEAR_PASSAGE_HALF_WIDTH + 0.015:
			return false
	# Mid-edge and interior samples also reject ornaments spanning concave boundaries.
	for index in range(0, vertices.size(), 3):
		var a := vertices[index]
		var b := vertices[index + 1]
		var c := vertices[index + 2]
		for point: Vector3 in [(a + b) * 0.5, (b + c) * 0.5, (c + a) * 0.5, (a + b + c) / 3.0]:
			if not _inside(item, Vector2(point.x, point.z)):
				return false
	return true

func _roof_y(item: Dictionary, u: float, v: float) -> float:
	var point := Vector2(u, v)
	for triangle: Array in _roof_triangles[item.id]:
		var a: Vector3 = triangle[0]
		var b: Vector3 = triangle[1]
		var c: Vector3 = triangle[2]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ac := Vector2(c.x - a.x, c.z - a.z)
		var ap := point - Vector2(a.x, a.z)
		var denominator := ab.cross(ac)
		if absf(denominator) < EPS:
			continue
		var wb := ap.cross(ac) / denominator
		var wc := ab.cross(ap) / denominator
		if wb >= -EPS and wc >= -EPS and wb + wc <= 1.0 + EPS:
			return a.y + wb * (b.y - a.y) + wc * (c.y - a.y)
	return NAN

func _edge_v(item: Dictionary, u: float, side: float) -> float:
	var hits: Array[float] = []
	for polygon: Array in _local_rings[item.id]:
		var ring: PackedVector2Array = polygon[0]
		for index in range(ring.size() - 1):
			var a := ring[index]
			var b := ring[index + 1]
			if absf(b.x - a.x) < EPS or u < minf(a.x, b.x) or u > maxf(a.x, b.x):
				continue
			hits.append(lerpf(a.y, b.y, (u - a.x) / (b.x - a.x)))
	if hits.is_empty():
		return NAN
	hits.sort()
	return hits[0] if side < 0.0 else hits[-1]

func _inside(item: Dictionary, point: Vector2) -> bool:
	for polygon: Array in _local_rings[item.id]:
		var inside := Geometry2D.is_point_in_polygon(point, polygon[0])
		for index in range(1, polygon.size()):
			if Geometry2D.is_point_in_polygon(point, polygon[index]):
				inside = false
		if inside:
			return true
	return false

func _world_point(item: Dictionary, point: Vector3) -> Vector3:
	var orientation: Dictionary = item.orientation
	var origin: Array = orientation.origin_xz_m
	var u: Array = orientation.u_axis_xz
	var v: Array = orientation.v_axis_xz
	return Vector3(origin[0] + point.x * u[0] + point.z * v[0], point.y, origin[1] + point.x * u[1] + point.z * v[1])

func _local_point(item: Dictionary, point: Vector3) -> Vector3:
	var orientation: Dictionary = item.orientation
	var origin: Array = orientation.origin_xz_m
	var u: Array = orientation.u_axis_xz
	var v: Array = orientation.v_axis_xz
	var delta := Vector2(point.x - origin[0], point.z - origin[1])
	return Vector3(delta.dot(Vector2(u[0], u[1])), point.y, delta.dot(Vector2(v[0], v[1])))

func _material(key: String, colour: Color, roughness: float) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	# Only the new thin tile shells need both faces; source walls stay unchanged.
	if key.begins_with("tile_") or key == "ridge_tile" or key == "rafter_end":
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = material
	return material

func _commit_groups() -> void:
	for key: String in _groups:
		var group: Dictionary = _groups[key]
		var visual := MeshInstance3D.new()
		visual.name = "PhotoDetail_" + group.key + "_" + str(mesh_count)
		var surface: SurfaceTool = group.surface
		visual.mesh = surface.commit()
		visual.material_override = group.material
		visual.set_meta("authored_photo_detail", true)
		visual.set_meta("within_source_envelope", true)
		visual.set_meta("not_surveyed", true)
		add_child(visual)
		mesh_count += 1
	_groups.clear()

func _fail(message: String) -> bool:
	load_error = message
	return false
