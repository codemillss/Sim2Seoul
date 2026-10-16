extends Node3D
## Photo-informed relief, contained by the retained source plan and height.
## Spacing and moulding dimensions are visual choices, not surveyed dimensions.
## These meshes have no bodies, openings, routes, or collision replacements.

var loaded := false
var load_error := ""
var landmark_count := 0
var detail_mesh_count := 0
var ornament_count := 0
var window_count := 0
var lattice_segment_count := 0
var triangle_count := 0
var door_world_position := Vector3.ZERO
var entrance_world_position := Vector3.ZERO
var entrance_outward_direction := Vector3.ZERO
var _batches: Dictionary = {}
var _materials: Dictionary = {}
var _front_faces: Array[Dictionary] = []

func setup(host: Node3D) -> bool:
	if loaded or not is_instance_valid(host):
		return _fail("시청 사진 외형의 연결 상태를 확인하지 못했습니다.")
	var civic := host.get("city_visuals") as Node3D
	if civic == null or not civic.get("loaded"):
		return _fail("시청 사진 외형에 필요한 원본 외형이 없습니다.")
	var bundle: Variant = civic.get("bundle")
	var components: Variant = civic.get("components")
	if not bundle is Dictionary or not components is Dictionary:
		return _fail("시청 사진 외형 자료를 읽지 못했습니다.")
	var library: Dictionary = {}
	var city_hall: Dictionary = {}
	for item: Dictionary in bundle.get("landmarks", []):
		if item.get("id") == "library": library = item
		elif item.get("id") == "city_hall": city_hall = item
	if library.is_empty() or city_hall.is_empty():
		return _fail("도서관과 신청사 외형이 필요합니다.")
	var library_stone := components.get("library_stone_low_stone_mass") as MeshInstance3D
	if library_stone != null:
		_materials["stone"] = library_stone.material_override
	if _materials.get("stone") == null:
		_materials["stone"] = _material("stone_fallback", Color(0.67, 0.67, 0.62), 0.86)
	_material("window", Color(0.055, 0.105, 0.12), 0.21, 0.36)
	_material("window_reveal", Color(0.23, 0.25, 0.24), 0.86)
	_material("window_metal", Color(0.32, 0.35, 0.34), 0.37, 0.68)
	_material("diagrid", Color(0.40, 0.48, 0.48), 0.33, 0.72)
	_material("eave_metal", Color(0.16, 0.22, 0.23), 0.45, 0.63)
	_add_library(library)
	_add_city_hall(city_hall)
	if window_count == 0 or lattice_segment_count == 0:
		return _fail("사진 외형을 원본 표면 안에 배치하지 못했습니다.")
	_commit()
	var grid := components.get("city_hall_frame_glass_grid") as MeshInstance3D
	if grid != null: grid.material_override = _materials["diagrid"]
	# Only prior decorative window strips/relief are retired. The closed stone
	# mass, original imported resource and all collision objects remain intact.
	var sparse := components.get("library_window_vertical_window_rhythm") as Node3D
	if sparse != null: sparse.visible = false
	var identity := host.get("seoul_identity") as Node3D
	if identity != null:
		var prior := identity.get_node_or_null("library_relief") as Node3D
		if prior != null: prior.visible = false
	landmark_count = 2
	loaded = true
	return true

func _material(key: String, color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	if _materials.has(key): return _materials[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if key == "window":
		material.clearcoat_enabled = true
		material.clearcoat = 0.65
		material.clearcoat_roughness = 0.18
	_materials[key] = material
	return material

func _add_library(item: Dictionary) -> void:
	var bottom := float(item.source_binding.current_bottom_y_m)
	var top := float(item.source_binding.current_top_y_m)
	var height := top - bottom
	var centre_x := float(item.source_binding.bbox_centre_xz_m[0])
	for entry: Dictionary in item.components:
		if entry.get("feature_role") == "central_facade":
			centre_x = _bounds(entry.vertices).get_center().x
			break
	var front_edges: Array[Dictionary] = []
	for polygon: Array in item.source_binding.geometry.coordinates:
		# Iterate exterior segments themselves; concave notches are retained.
		var ring: Array = polygon[0]
		for index in range(ring.size() - 1):
			var a := Vector2(float(ring[index][0]), float(ring[index][1]))
			var b := Vector2(float(ring[index + 1][0]), float(ring[index + 1][1]))
			var length := a.distance_to(b)
			if length < 3.8: continue
			var along := (b - a) / length
			var inward := Vector2(-along.y, along.x)
			if not _inside(item, (a + b) * 0.5 + inward * 0.35): inward *= -1.0
			var outward := -inward
			var basis := _basis(along, outward)
			var front := outward.y > 0.72
			if front: front_edges.append({"a": a, "b": b, "along": along, "inward": inward, "length": length})
			var count := maxi(1, int(floor((length - 0.8) / 2.85)))
			var bay := (length - 0.7) / float(count)
			for bay_index in range(count):
				var distance := 0.35 + bay * (float(bay_index) + 0.5)
				var edge_point := a + along * distance
				# The central entrance occupies the first row, with tall windows
				# above it. Other bays continue the tightly spaced vertical rhythm.
				for row in range(3):
					if front and row == 0 and absf(edge_point.x - centre_x) < 2.65: continue
					var low := bottom + height * (0.145 + row * 0.233)
					var high := low + height * (0.174 if row > 0 else 0.168)
					var width := minf(1.48, bay * 0.55)
					_add_library_window(item, edge_point, inward, basis, width, low, high)
			# Engaged pilasters sit in the stone between adjacent dark bays.
			for pier_index in range(count + 1):
				var edge_point := a + along * (0.35 + bay * float(pier_index))
				if front and absf(edge_point.x - centre_x) < 3.0: continue
				var p := edge_point + inward * 0.14
				_checked_box(item, "stone", Vector3(p.x, bottom + height * 0.46, p.y), Vector3(0.25, height * 0.73, 0.24), basis)
				_checked_box(item, "stone", Vector3(p.x, bottom + height * 0.825, p.y), Vector3(0.52, 0.20, 0.27), basis)
				_checked_box(item, "stone", Vector3(p.x, bottom + height * 0.105, p.y), Vector3(0.43, 0.25, 0.27), basis)
			# Cornice shadow, string course and parapet are actual shallow steps.
			for course: Vector3 in [Vector3(0.092, 0.25, 0.18), Vector3(0.32, 0.18, 0.13), Vector3(0.548, 0.16, 0.12), Vector3(0.838, 0.30, 0.22), Vector3(0.873, 0.18, 0.25)]:
				var p := (a + b) * 0.5 + inward * (course.z * 0.5 + 0.012)
				_checked_box(item, "stone", Vector3(p.x, bottom + height * course.x, p.y), Vector3(length - 0.48, course.y, course.z), basis)
	if not front_edges.is_empty():
		_add_library_centre(item, front_edges, centre_x, bottom, top)

func _add_library_window(item: Dictionary, edge: Vector2, inward: Vector2, basis: Basis, width: float, low: float, high: float) -> void:
	var centre_y := (low + high) * 0.5
	var height := high - low
	var reveal := edge + inward * 0.19
	var glazing := edge + inward * 0.095
	var face := edge + inward * 0.055
	# The dark reveal is wider than the glazing. The raised stone jambs and
	# sill stand in front of it, producing visible depth and cast shadows.
	if not _checked_box(item, "window_reveal", Vector3(reveal.x, centre_y, reveal.y), Vector3(width + 0.24, height + 0.24, 0.06), basis): return
	_checked_box(item, "window", Vector3(glazing.x, centre_y, glazing.y), Vector3(width, height, 0.085), basis)
	for sign_value: float in [-1.0, 1.0]:
		var jamb := Vector3(face.x, centre_y, face.y) + basis.x * sign_value * (width * 0.5 + 0.105)
		_checked_box(item, "stone", jamb, Vector3(0.19, height + 0.34, 0.09), basis)
	_checked_box(item, "stone", Vector3(face.x, low - 0.07, face.y), Vector3(width + 0.48, 0.18, 0.10), basis)
	_checked_box(item, "stone", Vector3(face.x, high + 0.08, face.y), Vector3(width + 0.43, 0.20, 0.10), basis)
	_checked_box(item, "window_metal", Vector3(face.x, centre_y, face.y), Vector3(0.055, height - 0.06, 0.07), basis)
	_checked_box(item, "window_metal", Vector3(face.x, low + height * 0.60, face.y), Vector3(width, 0.055, 0.07), basis)
	window_count += 1

func _add_library_centre(item: Dictionary, edges: Array[Dictionary], desired_x: float, bottom: float, top: float) -> void:
	var selected: Dictionary = {}
	var score := INF
	for edge: Dictionary in edges:
		var a: Vector2 = edge.a
		var b: Vector2 = edge.b
		var factor := clampf((desired_x - a.x) / (b.x - a.x), 0.0, 1.0)
		var p := a.lerp(b, factor)
		var distance := absf(p.x - desired_x)
		if distance < score:
			score = distance
			selected = edge.duplicate()
			selected["centre"] = p
	if selected.is_empty(): return
	var along: Vector2 = selected.along
	var inward: Vector2 = selected.inward
	# Orient the central assemblage along the real front edge at its axis.
	var basis := _basis(along, -inward)
	var edge: Vector2 = selected.centre
	var height := top - bottom
	var face := edge + inward * 0.085
	var p := Vector3(face.x, bottom + 3.10, face.y)
	door_world_position = p
	entrance_outward_direction = Vector3(-inward.x, 0.0, -inward.y)
	entrance_world_position = Vector3(edge.x, bottom + 0.05, edge.y) + entrance_outward_direction * 2.0
	_checked_box(item, "window_reveal", p - basis.z * 0.07, Vector3(4.55, 3.35, 0.15), basis)
	_checked_box(item, "window", p + basis.z * 0.015, Vector3(4.13, 3.02, 0.09), basis)
	for offset: float in [-2.42, -0.71, 0.71, 2.42]:
		var jamb := p + basis.x * offset + basis.z * 0.015
		_checked_box(item, "stone" if absf(offset) > 2.0 else "window_metal", jamb, Vector3(0.25 if absf(offset) > 2.0 else 0.065, 3.65 if absf(offset) > 2.0 else 3.03, 0.12), basis)
	_checked_box(item, "stone", Vector3(face.x, bottom + 4.96, face.y), Vector3(5.55, 0.32, 0.12), basis)
	_checked_box(item, "window_metal", Vector3(face.x, bottom + 3.96, face.y) + basis.z * 0.04, Vector3(4.16, 0.09, 0.06), basis)
	# Balcony relief and a stone crown make the retained taller centre read
	# as the old civic entrance pavilion rather than an unbroken slab.
	for entry: Vector3 in [Vector3(6.4, 6.35, 0.30), Vector3(6.8, 6.60, 0.18), Vector3(6.4, 7.60, 0.16)]:
		var centre := edge + inward * (entry.z * 0.5 + 0.012)
		_checked_box(item, "stone", Vector3(centre.x, bottom + entry.y, centre.y), Vector3(entry.x, 0.19, entry.z), basis)
	for index in range(11):
		var baluster := p + basis.x * (-2.9 + float(index) * 0.58)
		baluster.y = bottom + 7.10
		_checked_box(item, "stone", baluster, Vector3(0.15, 0.88, 0.12), basis)
	# Narrow trim follows each actual front segment, including the small
	# change in direction at the middle. It never bridges a source recess.
	for front: Dictionary in edges:
		var a: Vector2 = front.a
		var b: Vector2 = front.b
		var xmin := maxf(minf(a.x, b.x) + 0.18, desired_x - 8.60)
		var xmax := minf(maxf(a.x, b.x) - 0.18, desired_x + 8.60)
		if xmax - xmin < 0.3: continue
		var start := a.lerp(b, (xmin - a.x) / (b.x - a.x))
		var finish := a.lerp(b, (xmax - a.x) / (b.x - a.x))
		var front_in: Vector2 = front.inward
		var trim_basis := _basis((finish - start).normalized(), -front_in)
		for course: Vector3 in [Vector3(0.905, 0.22, 0.16), Vector3(0.970, 0.24, 0.22), Vector3(0.993, 0.20, 0.26)]:
			var centre := (start + finish) * 0.5 + front_in * (course.z * 0.5 + 0.012)
			_checked_box(item, "stone", Vector3(centre.x, bottom + height * course.x - 0.08, centre.y), Vector3(start.distance_to(finish), course.y, course.z), trim_basis)

func _add_city_hall(item: Dictionary) -> void:
	_front_faces.clear()
	var facade_bounds := AABB()
	var started := false
	for entry: Dictionary in item.components:
		if entry.get("feature_role") != "curved_glass_mass": continue
		var flat: Array = entry.vertices
		var normals: Array = entry.normals
		for index in range(0, flat.size(), 9):
			var normal := Vector3(normals[index], normals[index + 1], normals[index + 2])
			if normal.z < 0.15 or absf(normal.x) > 0.95: continue
			var a := Vector3(flat[index], flat[index + 1], flat[index + 2])
			var b := Vector3(flat[index + 3], flat[index + 4], flat[index + 5])
			var c := Vector3(flat[index + 6], flat[index + 7], flat[index + 8])
			if absf((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) < 0.0001: continue
			_front_faces.append({"a": a, "b": b, "c": c, "normal": normal.normalized()})
			if not started:
				facade_bounds = AABB(a, Vector3.ZERO)
				started = true
			facade_bounds = facade_bounds.expand(a).expand(b).expand(c)
	if not started: return
	var low := facade_bounds.position.y + 0.26
	var high := facade_bounds.end.y - 0.18
	# Crossed diagonals are sampled against the existing faceted curtain wall,
	# so their depth bends with the glass instead of floating on a flat plane.
	for slope: float in [-0.63, 0.63]:
		var start_x := facade_bounds.position.x - (high - low) * absf(slope)
		while start_x < facade_bounds.end.x + (high - low) * absf(slope):
			var y := low
			var previous: Dictionary = {}
			while y <= high + 0.01:
				var x := start_x + (y - low) * slope
				var sample := _front_point(Vector2(x, y))
				if not sample.is_empty() and not previous.is_empty():
					var p: Vector3 = previous.point + previous.normal * 0.065
					var q: Vector3 = sample.point + sample.normal * 0.065
					if p.distance_to(q) < 3.0 and _checked_beam(item, "diagrid", p, q, 0.13, 0.15, (previous.normal + sample.normal).normalized()):
						lattice_segment_count += 1
				previous = sample
				y = minf(y + 1.3, high + 1.3)
			start_x += 7.9
	# A continuous shaded roof lip underscores the broad overhanging edge.
	var x := facade_bounds.position.x + 0.65
	var last: Dictionary = {}
	while x < facade_bounds.end.x - 0.5:
		var sample := _front_point(Vector2(x, high - 0.28))
		if not sample.is_empty() and not last.is_empty():
			_checked_beam(item, "eave_metal", last.point + last.normal * 0.05, sample.point + sample.normal * 0.05, 0.35, 0.24, Vector3.FORWARD * -1.0)
		last = sample
		x += 1.7
func _front_point(point: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var front_z := -INF
	for face: Dictionary in _front_faces:
		var a: Vector3 = face.a
		var b: Vector3 = face.b
		var c: Vector3 = face.c
		var denominator := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		var wa := ((b.y - c.y) * (point.x - c.x) + (c.x - b.x) * (point.y - c.y)) / denominator
		var wb := ((c.y - a.y) * (point.x - c.x) + (a.x - c.x) * (point.y - c.y)) / denominator
		var wc := 1.0 - wa - wb
		if minf(wa, minf(wb, wc)) < -0.00001: continue
		var z := wa * a.z + wb * b.z + wc * c.z
		if z > front_z:
			front_z = z
			best = {"point": Vector3(point.x, point.y, z), "normal": face.normal}
	return best

func _checked_beam(item: Dictionary, key: String, a: Vector3, b: Vector3, width: float, depth: float, normal: Vector3) -> bool:
	var direction := b - a
	if direction.length() < 0.005: return false
	var axis_y := direction.normalized()
	var axis_x := axis_y.cross(normal).normalized()
	if axis_x.length_squared() < 0.1: return false
	var basis := Basis(axis_x, axis_y, axis_x.cross(axis_y).normalized())
	return _checked_box(item, key, (a + b) * 0.5, Vector3(width, direction.length() + 0.018, depth), basis)

func _basis(along: Vector2, outward: Vector2) -> Basis:
	return Basis(Vector3(along.x, 0.0, along.y), Vector3.UP, Vector3(outward.x, 0.0, outward.y))

func _checked_box(item: Dictionary, key: String, centre: Vector3, size: Vector3, basis: Basis) -> bool:
	var low := float(item.source_binding.current_bottom_y_m)
	var high := float(item.source_binding.current_top_y_m)
	for sx: float in [-0.5, 0.5]:
		for sy: float in [-0.5, 0.5]:
			for sz: float in [-0.5, 0.5]:
				var corner := centre + basis * Vector3(size.x * sx, size.y * sy, size.z * sz)
				if corner.y < low - 0.0001 or corner.y > high + 0.0001 or not _inside(item, Vector2(corner.x, corner.z)):
					return false
	if not _batches.has(key):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = tool
	var box := BoxMesh.new()
	box.size = size
	# A ring can have either winding. A positive determinant avoids inverted
	# shading/culling when the outward direction requires a reflected frame.
	var display_basis := basis
	if display_basis.determinant() < 0.0: display_basis.x *= -1.0
	var tool: SurfaceTool = _batches[key]
	tool.append_from(box, 0, Transform3D(display_basis, centre))
	ornament_count += 1
	triangle_count += 12
	return true

func _inside(item: Dictionary, point: Vector2) -> bool:
	for polygon: Array in item.source_binding.geometry.coordinates:
		var inside := false
		for index in range(polygon.size()):
			var ring := PackedVector2Array()
			for pair: Array in polygon[index]: ring.append(Vector2(float(pair[0]), float(pair[1])))
			if index == 0: inside = Geometry2D.is_point_in_polygon(point, ring)
			elif Geometry2D.is_point_in_polygon(point, ring): inside = false
		if inside: return true
	return false

func _bounds(flat: Array) -> AABB:
	var result := AABB(Vector3(flat[0], flat[1], flat[2]), Vector3.ZERO)
	for index in range(3, flat.size(), 3): result = result.expand(Vector3(flat[index], flat[index + 1], flat[index + 2]))
	return result

func _commit() -> void:
	for key: String in _batches:
		var tool: SurfaceTool = _batches[key]
		var visual := MeshInstance3D.new()
		visual.name = "photo_" + key
		visual.mesh = tool.commit()
		visual.material_override = _materials[key]
		visual.set_meta("photo_informed_civic_detail", true)
		visual.set_meta("collision_generated", false)
		add_child(visual)
		detail_mesh_count += 1
	_batches.clear()

func _fail(message: String) -> bool:
	load_error = message
	return false
