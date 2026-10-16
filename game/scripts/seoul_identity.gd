extends Node3D
## Additional authored appearance, never replacement source/collision data.
## The dimensions of ornament, stone courses and glazing are visual choices.
const STONE_SHADER: Shader = preload("res://shaders/stone_wall.gdshader")
const SURFACE_SHADER: Shader = preload("res://shaders/seoul_surface.gdshader")
const GRANITE_ALBEDO: Texture2D = preload("res://assets/textures/seoul/palace_granite_albedo.png")
const DUPLICATE_WALL_IDS := ["osm:way:381941848:barrier", "osm:way:381941854:barrier"]
const PALACE_WALL_ID := "osm:way:26658458:barrier"
const EPS := 0.00005

var loaded := false
var load_error := ""
var wall_count := 0
var landmark_count := 0
var detail_mesh_count := 0
var ornament_count := 0
var material_count := 0
var overlap_report: Dictionary = {}
var _materials: Dictionary = {}
var _details: Dictionary = {}
var _roof_shader: Shader

func setup(city: Node3D, host: Node3D) -> bool:
	if loaded or not is_instance_valid(city) or not is_instance_valid(host):
		return _fail("서울 외형의 도시 노드를 확인하지 못했습니다.")
	var palace := host.get("landmark_visuals") as Node3D
	var civic := host.get("city_visuals") as Node3D
	if palace == null or civic == null or not palace.get("loaded") or not civic.get("loaded"):
		return _fail("서울 외형에 필요한 궁궐과 시청 자료가 없습니다.")
	var sources: Variant = city.get("source_nodes")
	var fragments: Variant = city.get("fragments")
	if not sources is Dictionary or not fragments is Dictionary or not fragments.has("W01_palace_wall"):
		return _fail("덕수궁 돌담 원본을 확인하지 못했습니다.")
	var wall := fragments["W01_palace_wall"].get_parent() as MeshInstance3D
	if wall == null or wall.mesh == null:
		return _fail("덕수궁 돌담 표시 자료가 없습니다.")
	# W01 and the two separately tagged historic wall ways share actual source
	# segments. Remove only covered visual surfaces; every body/shape remains.
	for id: String in DUPLICATE_WALL_IDS:
		var duplicate := sources.get(id) as MeshInstance3D
		if duplicate != null and duplicate.mesh != null:
			_remove_coincident_faces(duplicate, wall, id)
	var stone := _stone_material(false)
	wall.material_override = stone
	wall.set_meta("seoul_stone_wall", true)
	wall_count += 1
	for id: String in DUPLICATE_WALL_IDS:
		var visual := sources.get(id) as MeshInstance3D
		if visual != null:
			visual.material_override = stone
			visual.set_meta("seoul_stone_wall", true)
			wall_count += 1
	# Replace the displayed flat top with a shallow tiled coping contained in
	# the existing two-metre envelope. The original collision is still 2 m.
	_add_wall_coping(wall)
	var palace_bundle: Dictionary = palace.get("bundle")
	var palace_components: Dictionary = palace.get("components")
	for item: Dictionary in palace_bundle.landmarks:
		_apply_palace(item, palace_components)
		landmark_count += 1
	var civic_bundle: Dictionary = civic.get("bundle")
	var civic_components: Dictionary = civic.get("components")
	for item: Dictionary in civic_bundle.landmarks:
		if item.id in ["city_hall", "library", "sfc"]:
			_apply_civic(item, civic_components)
			landmark_count += 1
	_commit_details()
	material_count = _materials.size()
	loaded = true
	return true

func _stone_material(coping: bool) -> ShaderMaterial:
	var key := "stone_coping" if coping else "stone_wall"
	if _materials.has(key): return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = STONE_SHADER
	material.set_shader_parameter("coping_only", coping)
	material.set_shader_parameter("granite_albedo", GRANITE_ALBEDO)
	_materials[key] = material
	return material

func _surface(key: String, kind: int, tint: Color, orientation: Dictionary = {}) -> ShaderMaterial:
	if _materials.has(key): return _materials[key]
	var material := ShaderMaterial.new()
	if kind == 0:
		# L02 uses thin roof sheets. Only roofing needs visible undersides;
		# closed stone/glass/wood surfaces retain ordinary back-face culling.
		if _roof_shader == null:
			_roof_shader = Shader.new()
			_roof_shader.code = SURFACE_SHADER.code.replace("cull_back", "cull_disabled")
		material.shader = _roof_shader
	else:
		material.shader = SURFACE_SHADER
	material.set_shader_parameter("surface_kind", kind)
	material.set_shader_parameter("tint", tint)
	if not orientation.is_empty():
		material.set_shader_parameter("origin_xz", Vector2(orientation.origin_xz_m[0], orientation.origin_xz_m[1]))
		material.set_shader_parameter("u_axis", Vector2(orientation.u_axis_xz[0], orientation.u_axis_xz[1]))
		material.set_shader_parameter("v_axis", Vector2(orientation.v_axis_xz[0], orientation.v_axis_xz[1]))
	_materials[key] = material
	return material

func _apply_palace(item: Dictionary, components: Dictionary) -> void:
	var orientation: Dictionary = item.orientation
	var roof := _surface("roof_" + str(item.id), 0, Color(0.22, 0.25, 0.26), orientation)
	var paint := _surface("dancheong", 1, Color(0.16, 0.39, 0.31))
	var lattice := _surface("wood_lattice", 2, Color(0.36, 0.24, 0.15))
	var white_stone := _surface("palace_ashlar", 3, Color(0.83, 0.82, 0.75))
	var timber := _surface("painted_timber", 6, Color(0.42, 0.105, 0.073))
	var plaster := _surface("palace_plaster", 7, Color(0.74, 0.72, 0.65))
	var brick := _surface("dondeokjeon_brick", 4, Color(0.49, 0.22, 0.17))
	for entry: Dictionary in item.components:
		var visual := components.get(entry.id) as MeshInstance3D
		if visual == null: continue
		if entry.material in ["tile", "tile_edge"]:
			visual.material_override = roof
		elif entry.material == "red_column":
			visual.material_override = timber
		elif entry.material == "cream_wall":
			visual.material_override = plaster
		elif entry.material == "green_beam":
			visual.material_override = paint
		elif entry.material == "wood_panel" and entry.feature_role == "window":
			visual.material_override = lattice
		elif entry.material in ["stone", "light_stone", "stone_shadow"]:
			visual.material_override = white_stone
		elif entry.material == "brick":
			visual.material_override = brick
		# Existing columns provide the actual positions. Painted bracket heads
		# and timber crosspieces make the open-sided palace construction legible.
		if entry.feature_role == "column" and entry.material == "red_column":
			var bounds := _bounds(entry.vertices)
			var centre := bounds.get_center()
			var y := bounds.end.y - 0.30
			_add_checked_box("painted_brackets", paint, item, Vector3(centre.x, y, centre.z), Vector3(0.78, 0.16, 0.66))
			_add_checked_box("painted_brackets", paint, item, Vector3(centre.x, y + 0.16, centre.z), Vector3(1.10, 0.12, 0.42))
	if item.id in ["daehanmun", "junghwajeon", "junghwamun", "jeonggwanheon"]:
		_add_eave_rafters(item, roof)

func _add_eave_rafters(item: Dictionary, material: Material) -> void:
	var orientation: Dictionary = item.orientation
	var bounds: Array = orientation.local_bounds_m
	var width := float(bounds[2]) - float(bounds[0])
	var top: float = item.source_binding.current_top_y_m
	var bottom: float = item.source_binding.current_bottom_y_m
	var ratio: float = item.recipe.get("eave_ratio", 0.55)
	var eave := bottom + (top - bottom) * ratio
	var steps := mini(54, maxi(12, int(width / 0.42)))
	for side: float in [-1.0, 1.0]:
		var v: float = bounds[1] + 0.63 if side < 0.0 else bounds[3] - 0.63
		for index in range(1, steps):
			var u: float = lerpf(bounds[0], bounds[2], float(index) / float(steps))
			var centre := _world_point(orientation, Vector3(u, eave - 0.10, v))
			_add_checked_box("eave_rafters_" + str(item.id), material, item, centre, Vector3(0.105, 0.15, 0.82))

func _apply_civic(item: Dictionary, components: Dictionary) -> void:
	var glass := _surface("city_hall_glass", 5, Color(0.30, 0.45, 0.51))
	var stone := _surface("civic_ashlar", 3, Color(0.76, 0.74, 0.67))
	var dark_roof := _surface("civic_roof", 0, Color(0.28, 0.32, 0.33))
	var window := _surface("library_windows", 2, Color(0.50, 0.52, 0.48))
	for entry: Dictionary in item.components:
		var visual := components.get(entry.id) as MeshInstance3D
		if visual == null: continue
		if entry.material == "glass": visual.material_override = glass
		elif entry.material == "stone": visual.material_override = stone
		elif entry.material == "roof": visual.material_override = dark_roof
		elif entry.material == "window": visual.material_override = window
	if item.id == "library":
		# Engage repeated pale pilasters and capitals into the source front edge;
		# these do not suggest a new walk-through portico or fictitious entrance.
		_add_library_relief(item, stone)

func _add_library_relief(item: Dictionary, material: Material) -> void:
	var rings: Array = item.source_binding.geometry.coordinates
	var ring: Array = rings[0][0]
	var best_a := Vector2.ZERO
	var best_b := Vector2.ZERO
	var longest := 0.0
	for index in range(ring.size() - 1):
		var a := Vector2(ring[index][0], ring[index][1])
		var b := Vector2(ring[index + 1][0], ring[index + 1][1])
		var delta := b - a
		if absf(delta.y) < 0.08 * absf(delta.x) and maxf(a.y, b.y) > -120.0 and delta.length() > longest:
			best_a = a
			best_b = b
			longest = delta.length()
	if longest < 12.0: return
	var along := (best_b - best_a).normalized()
	var inward := Vector2(along.y, -along.x)
	var midpoint := (best_a + best_b) * 0.5
	if not _inside(item, midpoint + inward * 0.5): inward *= -1.0
	var basis := Basis(Vector3(along.x, 0.0, along.y), Vector3.UP, Vector3(-along.y, 0.0, along.x))
	for index in range(1, 9):
		var p := best_a.lerp(best_b, float(index) / 9.0) + inward * 0.30
		var centre := Vector3(p.x, 8.1, p.y)
		_add_box("library_relief", material, centre, Vector3(0.56, 12.0, 0.34), basis)
		_add_box("library_relief", material, Vector3(p.x, 14.2, p.y), Vector3(1.04, 0.35, 0.45), basis)
		_add_box("library_relief", material, Vector3(p.x, 2.1, p.y), Vector3(0.84, 0.32, 0.43), basis)

func _add_checked_box(key: String, material: Material, item: Dictionary, centre: Vector3, size: Vector3) -> void:
	var orientation: Dictionary = item.orientation
	var u: Array = orientation.u_axis_xz
	var v: Array = orientation.v_axis_xz
	var basis := Basis(Vector3(u[0], 0.0, u[1]), Vector3.UP, Vector3(v[0], 0.0, v[1]))
	if basis.determinant() < 0.0: basis.x *= -1.0
	for x: float in [-0.5, 0.5]:
		for z: float in [-0.5, 0.5]:
			var point: Vector3 = centre + basis * Vector3(x * size.x, 0.0, z * size.z)
			if not _inside(item, Vector2(point.x, point.z)): return
	var bottom: float = item.source_binding.current_bottom_y_m
	var top: float = item.source_binding.current_top_y_m
	if centre.y - size.y * 0.5 < bottom or centre.y + size.y * 0.5 > top: return
	_add_box(key, material, centre, size, basis)

func _add_box(key: String, material: Material, centre: Vector3, size: Vector3, basis: Basis) -> void:
	if not _details.has(key):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_details[key] = {"tool": tool, "material": material}
	var box := BoxMesh.new()
	box.size = size
	var tool: SurfaceTool = _details[key].tool
	tool.append_from(box, 0, Transform3D(basis, centre))
	ornament_count += 1

func _commit_details() -> void:
	for key: String in _details:
		var tool: SurfaceTool = _details[key].tool
		var visual := MeshInstance3D.new()
		visual.name = key
		visual.mesh = tool.commit()
		visual.material_override = _details[key].material
		visual.set_meta("authored_seoul_ornament", true)
		add_child(visual)
		detail_mesh_count += 1
	_details.clear()

func _inside(item: Dictionary, point: Vector2) -> bool:
	for polygon: Array in item.source_binding.geometry.coordinates:
		var inside := false
		for index in range(polygon.size()):
			var packed := PackedVector2Array()
			for p: Array in polygon[index]: packed.append(Vector2(p[0], p[1]))
			if index == 0: inside = Geometry2D.is_point_in_polygon(point, packed)
			elif Geometry2D.is_point_in_polygon(point, packed): inside = false
		if inside: return true
	return false

func _world_point(orientation: Dictionary, p: Vector3) -> Vector3:
	var origin: Array = orientation.origin_xz_m
	var u: Array = orientation.u_axis_xz
	var v: Array = orientation.v_axis_xz
	return Vector3(origin[0] + p.x * u[0] + p.z * v[0], p.y, origin[1] + p.x * u[1] + p.z * v[1])

func _bounds(flat: Array) -> AABB:
	var bounds := AABB(Vector3(flat[0], flat[1], flat[2]), Vector3.ZERO)
	for index in range(3, flat.size(), 3): bounds = bounds.expand(Vector3(flat[index], flat[index + 1], flat[index + 2]))
	return bounds

func _remove_coincident_faces(source: MeshInstance3D, reference: MeshInstance3D, id: String) -> void:
	var input: Array = source.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = input[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = input[Mesh.ARRAY_NORMAL]
	var reference_array: Array = reference.mesh.surface_get_arrays(0)
	var reference_vertices: PackedVector3Array = reference_array[Mesh.ARRAY_VERTEX]
	var relative := source.global_transform.affine_inverse() * reference.global_transform
	var reference_triangles: Array[Dictionary] = []
	for index in range(0, reference_vertices.size(), 3):
		var a: Vector3 = relative * reference_vertices[index]
		var b: Vector3 = relative * reference_vertices[index + 1]
		var c: Vector3 = relative * reference_vertices[index + 2]
		var normal := (c - a).cross(b - a).normalized()
		if normal.length_squared() > 0.5: reference_triangles.append({"a": a, "b": b, "c": c, "normal": normal, "plane": normal.dot(a)})
	var output_vertices := PackedVector3Array()
	var output_normals := PackedVector3Array()
	var removed := 0
	var trimmed := 0
	for index in range(0, vertices.size(), 3):
		var a := vertices[index]
		var b := vertices[index + 1]
		var c := vertices[index + 2]
		var normal := (c - a).cross(b - a).normalized()
		var plane := normal.dot(a)
		var drop := _dominant_axis(normal)
		var pieces: Array[PackedVector2Array] = [PackedVector2Array([_project(a, drop), _project(b, drop), _project(c, drop)])]
		var original_area := _area(pieces[0])
		for candidate: Dictionary in reference_triangles:
			if normal.dot(candidate.normal) < 0.999999 or absf(plane - candidate.plane) > EPS: continue
			var clip := PackedVector2Array([_project(candidate.a, drop), _project(candidate.b, drop), _project(candidate.c, drop)])
			var remainder: Array[PackedVector2Array] = []
			for piece: PackedVector2Array in pieces: remainder.append_array(_subtract_triangle(piece, clip))
			pieces = remainder
			if pieces.is_empty(): break
		var retained_area := 0.0
		for piece: PackedVector2Array in pieces: retained_area += _area(piece)
		if retained_area < EPS * EPS: removed += 1
		elif retained_area < original_area - EPS * EPS: trimmed += 1
		for piece: PackedVector2Array in pieces:
			for j in range(1, piece.size() - 1):
				var face: Array[Vector3] = [_unproject(piece[0], drop, normal, plane), _unproject(piece[j], drop, normal, plane), _unproject(piece[j + 1], drop, normal, plane)]
				if (face[2] - face[0]).cross(face[1] - face[0]).dot(normal) < 0.0: face.reverse()
				for point: Vector3 in face:
					output_vertices.append(point)
					output_normals.append(normals[index])
	var mesh := _mesh(output_vertices, output_normals)
	if mesh != null: source.mesh = mesh
	else: source.visible = false
	overlap_report[id] = {"source_triangles": vertices.size() / 3, "removed_triangles": removed, "trimmed_triangles": trimmed, "retained_triangles": output_vertices.size() / 3, "plane_tolerance_m": EPS, "bodies_changed": 0}

func _subtract_triangle(subject: PackedVector2Array, clip: PackedVector2Array) -> Array[PackedVector2Array]:
	var output: Array[PackedVector2Array] = []
	var remaining := subject
	var sign_value := 1.0 if _signed_area(clip) > 0.0 else -1.0
	for index in range(3):
		var a := clip[index]
		var b := clip[(index + 1) % 3]
		var outside := _half_plane(remaining, a, b, -sign_value)
		if outside.size() >= 3 and _area(outside) > EPS * EPS: output.append(outside)
		remaining = _half_plane(remaining, a, b, sign_value)
		if remaining.size() < 3: break
	return output

func _half_plane(poly: PackedVector2Array, a: Vector2, b: Vector2, side: float) -> PackedVector2Array:
	var output := PackedVector2Array()
	for index in range(poly.size()):
		var p := poly[index]
		var q := poly[(index + 1) % poly.size()]
		var dp := (b - a).cross(p - a) * side
		var dq := (b - a).cross(q - a) * side
		if dp >= -0.00000001: output.append(p)
		if (dp >= 0.0) != (dq >= 0.0): output.append(p.lerp(q, clampf(dp / (dp - dq), 0.0, 1.0)))
	return output

func _signed_area(poly: PackedVector2Array) -> float:
	var sum := 0.0
	for index in range(poly.size()): sum += poly[index].cross(poly[(index + 1) % poly.size()])
	return sum * 0.5

func _area(poly: PackedVector2Array) -> float:
	return absf(_signed_area(poly))

func _dominant_axis(n: Vector3) -> int:
	if absf(n.x) > absf(n.y) and absf(n.x) > absf(n.z): return 0
	return 1 if absf(n.y) > absf(n.z) else 2

func _project(p: Vector3, drop: int) -> Vector2:
	if drop == 0: return Vector2(p.y, p.z)
	return Vector2(p.x, p.z) if drop == 1 else Vector2(p.x, p.y)

func _unproject(p: Vector2, drop: int, normal: Vector3, plane: float) -> Vector3:
	if drop == 0: return Vector3((plane - normal.y * p.x - normal.z * p.y) / normal.x, p.x, p.y)
	if drop == 1: return Vector3(p.x, (plane - normal.x * p.x - normal.z * p.y) / normal.y, p.y)
	return Vector3(p.x, p.y, (plane - normal.x * p.x - normal.y * p.y) / normal.z)

func _add_wall_coping(wall: MeshInstance3D) -> void:
	var arrays: Array = wall.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var top_triangles: Array[Array] = []
	var edge_counts: Dictionary = {}
	var edge_points: Dictionary = {}
	for index in range(0, vertices.size(), 3):
		if normals[index].y < 0.99: continue
		var tri: Array[Vector3] = [vertices[index], vertices[index + 1], vertices[index + 2]]
		top_triangles.append(tri)
		for j in range(3):
			var a := tri[j]
			var b := tri[(j + 1) % 3]
			var ka := "%0.5f,%0.5f" % [a.x, a.z]
			var kb := "%0.5f,%0.5f" % [b.x, b.z]
			var key := ka + ":" + kb if ka < kb else kb + ":" + ka
			edge_counts[key] = int(edge_counts.get(key, 0)) + 1
			edge_points[key] = [Vector2(a.x, a.z), Vector2(b.x, b.z)]
	var boundaries: Array[Array] = []
	for key: String in edge_counts:
		if edge_counts[key] == 1: boundaries.append(edge_points[key])
	if top_triangles.is_empty() or boundaries.is_empty(): return
	var wall_vertices := PackedVector3Array()
	var wall_normals := PackedVector3Array()
	for index in range(0, vertices.size(), 3):
		if normals[index].y > 0.99: continue
		var poly: Array[Vector3] = [vertices[index], vertices[index + 1], vertices[index + 2]]
		var clipped: Array[Vector3] = []
		for j in range(poly.size()):
			var a := poly[j]
			var b := poly[(j + 1) % poly.size()]
			if a.y <= 1.80: clipped.append(a)
			if (a.y <= 1.80) != (b.y <= 1.80): clipped.append(a.lerp(b, (1.80 - a.y) / (b.y - a.y)))
		for j in range(1, clipped.size() - 1):
			for p: Vector3 in [clipped[0], clipped[j], clipped[j + 1]]:
				wall_vertices.append(p)
				wall_normals.append(normals[index])
	wall.mesh = _mesh(wall_vertices, wall_normals)
	var cap_vertices := PackedVector3Array()
	var cap_normals := PackedVector3Array()
	for tri: Array in top_triangles:
		var middle: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
		for j in range(3):
			var a: Vector3 = tri[j]
			var b: Vector3 = tri[(j + 1) % 3]
			var midpoint := (a + b) * 0.5
			for small: Array in [[a, midpoint, middle], [midpoint, b, middle]]:
				var face: Array[Vector3] = []
				for p: Vector3 in small:
					var point := Vector2(p.x, p.z)
					var distance_to_edge := INF
					for edge: Array in boundaries: distance_to_edge = minf(distance_to_edge, point.distance_to(Geometry2D.get_closest_point_to_segment(point, edge[0], edge[1])))
					face.append(Vector3(p.x, 1.80 + clampf(distance_to_edge / 0.15, 0.0, 1.0) * 0.20, p.z))
				var normal := (face[2] - face[0]).cross(face[1] - face[0]).normalized()
				for p: Vector3 in face:
					cap_vertices.append(p)
					cap_normals.append(normal)
	var cap := MeshInstance3D.new()
	cap.name = "DeoksugungTileCoping"
	cap.mesh = _mesh(cap_vertices, cap_normals)
	cap.material_override = _stone_material(true)
	add_child(cap)
	cap.global_transform = wall.global_transform
	cap.set_meta("within_original_wall_envelope", true)
	detail_mesh_count += 1

func _mesh(vertices: PackedVector3Array, normals: PackedVector3Array) -> ArrayMesh:
	if vertices.is_empty(): return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _fail(message: String) -> bool:
	load_error = message
	return false
