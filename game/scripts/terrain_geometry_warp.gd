extends RefCounted
## EXP21: runtime-only height projection. Source meshes/data remain untouched.
## Horizontal faces are cut on the exact terrain-triangle edges. Each result's
## height is terrain barycentric Y + the source face's barycentric original Y,
## so a visual road and its independently built collision support share seams.
## MultiMesh raw layout follows RenderingServer.multimesh_set_buffer:
## https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-multimesh-set-buffer
const XZ_AREA_EPS: float=0.0000001
const COVERAGE_EPS: float=0.00001
const MAX_VERTICAL_XZ_EDGE_M: float=3.0
const CACHE_ROOT: String="res://data/generated/terrain_projection_cache"
const CACHE_SCHEMA: String="EXP21-exact-projection-v2"
var surface: Node
var city: Node3D
var _stats: Dictionary={}
var _helper_sha256: String=""
var _surface_sha256: String=""

func configure(terrain_surface: Node, source_city: Node3D) -> void:
	surface=terrain_surface;city=source_city
	_helper_sha256=FileAccess.get_sha256("res://scripts/terrain_geometry_warp.gd")
	var script: Script=surface.get_script()
	if script!=null and not script.resource_path.is_empty():_surface_sha256=FileAccess.get_sha256(script.resource_path)

func _begin(kind: String) -> void:
	_stats={"ok":true,"kind":kind,"source_faces":0,"output_faces":0,"clipped_source_faces":0,"uncovered_source_faces":0,"vertical_subdivisions":0,"dropped_leaf_faces":0,"source_xz_area_m2":0.0,"covered_xz_area_m2":0.0,"maximum_height_delta_m":0.0}

func _cache_key(kind: String,node: Node3D,geometry: Variant) -> String:
	var terrain_sha: String=String(surface.get("runtime_mesh_sha256"))
	if terrain_sha.length()!=64 or _helper_sha256.length()!=64 or _surface_sha256.length()!=64:return ""
	var context: HashingContext=HashingContext.new()
	if context.start(HashingContext.HASH_SHA256)!=OK:return ""
	var dependencies: Array=[CACHE_SCHEMA,Engine.get_version_info().string,kind,String(node.get_path()),node.global_transform,terrain_sha,_helper_sha256,_surface_sha256,geometry]
	if context.update(var_to_bytes(dependencies))!=OK:return ""
	return context.finish().hex_encode()

func _cache_read(key: String,kind: String,expected_surfaces: int=0) -> Resource:
	if key.is_empty():_stats["cache"]={"hit":false,"reason":"dependency_key_unavailable"};return null
	var path: String=CACHE_ROOT.path_join(key+".res")
	if not FileAccess.file_exists(path):_stats["cache"]={"hit":false,"key":key,"reason":"cold_or_invalidated"};return null
	# Ignore ResourceLoader's in-process cache: the exact keyed file must be
	# checked, including when a test replaces a disposable corrupted cache.
	var cached: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var valid: bool=cached!=null and cached.get_meta("projection_cache_schema","")==CACHE_SCHEMA and cached.get_meta("projection_cache_key","")==key and cached.get_meta("projection_cache_kind","")==kind
	if valid and kind=="mesh":
		valid=cached is ArrayMesh and (cached as ArrayMesh).get_surface_count()==expected_surfaces
		if valid:
			var bounds: AABB=(cached as ArrayMesh).get_aabb()
			valid=bounds.position.is_finite() and bounds.size.is_finite()
			for index: int in range(expected_surfaces):
				if (cached as ArrayMesh).surface_get_material(index)!=null:valid=false;break
	if valid and kind=="concave_shape":
		valid=cached is ConcavePolygonShape3D
		if valid:
			var faces: PackedVector3Array=(cached as ConcavePolygonShape3D).get_faces()
			valid=not faces.is_empty() and faces.size()%3==0 and faces.size()==int(cached.get_meta("projection_cache_point_count",-1))
			for point: Vector3 in faces:
				if not point.is_finite():valid=false;break
	if valid and kind=="convex_shape":
		valid=cached is ConvexPolygonShape3D
		if valid:
			var points: PackedVector3Array=(cached as ConvexPolygonShape3D).points
			valid=points.size()>=4 and points.size()==int(cached.get_meta("projection_cache_point_count",-1))
			for point: Vector3 in points:
				if not point.is_finite():valid=false;break
	if not valid:
		_stats["cache"]={"hit":false,"key":key,"reason":"invalid_resource_recomputed"}
		return null
	var stored: Variant=cached.get_meta("projection_cache_statistics",{})
	if not stored is Dictionary or not bool(stored.get("ok",false)):_stats["cache"]={"hit":false,"key":key,"reason":"invalid_statistics_recomputed"};return null
	_stats=(stored as Dictionary).duplicate(true)
	_stats["cache"]={"hit":true,"key":key,"geometry_processing_performed":false,"source_faces_processed_this_call":0,"geometry_statistics_basis":"Exact keyed cold projection statistics, not newly processed faces."}
	return cached

func _cache_write(resource: Resource,key: String,kind: String) -> void:
	if key.is_empty():return
	var prior: Dictionary=_stats.get("cache",{}).duplicate(true)
	resource.set_meta("projection_cache_schema",CACHE_SCHEMA);resource.set_meta("projection_cache_key",key);resource.set_meta("projection_cache_kind",kind)
	var stored: Dictionary=_stats.duplicate(true);stored.erase("cache")
	resource.set_meta("projection_cache_statistics",stored)
	if resource is ConcavePolygonShape3D:resource.set_meta("projection_cache_point_count",(resource as ConcavePolygonShape3D).get_faces().size())
	elif resource is ConvexPolygonShape3D:resource.set_meta("projection_cache_point_count",(resource as ConvexPolygonShape3D).points.size())
	var folder_error: Error=DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_ROOT))
	var error: Error=folder_error if folder_error!=OK else ResourceSaver.save(resource,CACHE_ROOT.path_join(key+".res"))
	prior["hit"]=false;prior["key"]=key;prior["geometry_processing_performed"]=true;prior["written"]=error==OK;prior["write_error"]=int(error)
	_stats["cache"]=prior

func _available() -> bool:
	return is_instance_valid(surface) and surface.has_method("ground_y_world") and surface.has_method("triangles_at_xz_rect")

func _xz(point: Vector3) -> Vector2:return Vector2(point.x,point.z)

func _area(a: Vector2,b: Vector2,c: Vector2) -> float:return absf((b-a).cross(c-a))*.5

func _weights(point: Vector2,a: Vector2,b: Vector2,c: Vector2) -> Vector3:
	var determinant: float=(b-a).cross(c-a)
	if absf(determinant)<XZ_AREA_EPS:return Vector3(1.,0.,0.)
	var second: float=(point-a).cross(c-a)/determinant
	var third: float=(b-a).cross(point-a)/determinant
	return Vector3(1.-second-third,second,third)

func _interpolate(first: Dictionary,second: Dictionary,amount: float) -> Dictionary:
	var result: Dictionary={"point":(first.point as Vector3).lerp(second.point,amount)}
	for key: String in ["uv","uv2","color"]:
		if first.has(key):result[key]=first[key].lerp(second[key],amount)
	return result

func _source_vertex(point: Vector2,vertices: Array) -> Dictionary:
	var a: Vector3=vertices[0].point;var b: Vector3=vertices[1].point;var c: Vector3=vertices[2].point
	var weight: Vector3=_weights(point,_xz(a),_xz(b),_xz(c))
	var result: Dictionary={"point":Vector3(point.x,a.y*weight.x+b.y*weight.y+c.y*weight.z,point.y)}
	for key: String in ["uv","uv2","color"]:
		if vertices[0].has(key):result[key]=vertices[0][key]*weight.x+vertices[1][key]*weight.y+vertices[2][key]*weight.z
	return result

func _terrain_y(point: Vector2,triangle: Dictionary) -> float:
	var a: Vector3=triangle.a;var b: Vector3=triangle.b;var c: Vector3=triangle.c
	var weight: Vector3=_weights(point,_xz(a),_xz(b),_xz(c))
	return a.y*weight.x+b.y*weight.y+c.y*weight.z

func _emit(vertices: Array,output: Array) -> void:
	if vertices.size()!=3:return
	var first: Vector3=vertices[0].point;var second: Vector3=vertices[1].point;var third: Vector3=vertices[2].point
	if (second-first).cross(third-first).length_squared()<0.000000000001:return
	output.append(vertices);_stats.output_faces=int(_stats.output_faces)+1

func _warp_vertical(vertices: Array,output: Array,depth: int=0) -> void:
	var lengths: Array[float]=[_xz(vertices[0].point).distance_to(_xz(vertices[1].point)),_xz(vertices[1].point).distance_to(_xz(vertices[2].point)),_xz(vertices[2].point).distance_to(_xz(vertices[0].point))]
	var edge: int=0
	for index: int in range(1,3):
		if lengths[index]>lengths[edge]:edge=index
	if lengths[edge]>MAX_VERTICAL_XZ_EDGE_M and depth<24:
		var next: int=(edge+1)%3;var opposite: int=(edge+2)%3
		var middle: Dictionary=_interpolate(vertices[edge],vertices[next],.5)
		_stats.vertical_subdivisions=int(_stats.vertical_subdivisions)+1
		_warp_vertical([vertices[edge],middle,vertices[opposite]],output,depth+1)
		_warp_vertical([middle,vertices[next],vertices[opposite]],output,depth+1)
		return
	var result: Array=[]
	for vertex: Dictionary in vertices:
		var item: Dictionary=vertex.duplicate();var before: Vector3=item.point
		var height: float=surface.ground_y_world(before)
		if not is_finite(height):_stats.dropped_leaf_faces=int(_stats.dropped_leaf_faces)+1;return
		item.point=before+Vector3.UP*height;result.append(item)
		_stats.maximum_height_delta_m=maxf(float(_stats.maximum_height_delta_m),absf(height))
	_emit(result,output)

func _warp_triangle(vertices: Array,output: Array) -> void:
	_stats.source_faces=int(_stats.source_faces)+1
	var a: Vector2=_xz(vertices[0].point);var b: Vector2=_xz(vertices[1].point);var c: Vector2=_xz(vertices[2].point)
	var source_area: float=_area(a,b,c)
	if source_area<XZ_AREA_EPS:
		var previous: int=int(_stats.output_faces)
		_warp_vertical(vertices,output)
		if int(_stats.output_faces)==previous:_stats.uncovered_source_faces=int(_stats.uncovered_source_faces)+1
		return
	_stats.source_xz_area_m2=float(_stats.source_xz_area_m2)+source_area
	var minimum: Vector2=a.min(b).min(c);var maximum: Vector2=a.max(b).max(c)
	var terrain_triangles: Array=surface.triangles_at_xz_rect(Rect2(minimum,maximum-minimum).grow(.00001))
	var source_polygon: PackedVector2Array=PackedVector2Array([a,b,c])
	var covered: float=0.0
	var source_normal: Vector3=((vertices[1].point as Vector3)-(vertices[0].point as Vector3)).cross((vertices[2].point as Vector3)-(vertices[0].point as Vector3))
	for terrain: Dictionary in terrain_triangles:
		var polygon: PackedVector2Array=PackedVector2Array([_xz(terrain.a),_xz(terrain.b),_xz(terrain.c)])
		var intersections: Array[PackedVector2Array]=Geometry2D.intersect_polygons(source_polygon,polygon)
		for intersection: PackedVector2Array in intersections:
			var indices: PackedInt32Array=Geometry2D.triangulate_polygon(intersection)
			for offset: int in range(0,indices.size(),3):
				var flat: Array[Vector2]=[intersection[indices[offset]],intersection[indices[offset+1]],intersection[indices[offset+2]]]
				var piece_area: float=_area(flat[0],flat[1],flat[2])
				if piece_area<XZ_AREA_EPS:continue
				var result: Array=[]
				for point: Vector2 in flat:
					var vertex: Dictionary=_source_vertex(point,vertices)
					var height: float=_terrain_y(point,terrain)
					vertex.point+=Vector3.UP*height;result.append(vertex)
					_stats.maximum_height_delta_m=maxf(float(_stats.maximum_height_delta_m),absf(height))
				# Geometry2D returns its own winding. Preserve the source 3D face's
				# horizontal-facing sign, including the bottom of closed supports.
				var normal: Vector3=((result[1].point as Vector3)-(result[0].point as Vector3)).cross((result[2].point as Vector3)-(result[0].point as Vector3))
				if normal.y*source_normal.y<0.0:var swap: Dictionary=result[1];result[1]=result[2];result[2]=swap
				_emit(result,output);covered+=piece_area
	_stats.covered_xz_area_m2=float(_stats.covered_xz_area_m2)+covered
	if covered<source_area-maxf(COVERAGE_EPS,source_area*.00001):
		# Omit only the portion outside the provided terrain domain. Keeping an
		# entire original face would overlay its already-warped inside portion.
		if covered>XZ_AREA_EPS:_stats.clipped_source_faces=int(_stats.clipped_source_faces)+1
		else:_stats.uncovered_source_faces=int(_stats.uncovered_source_faces)+1

func _vertex(arrays: Array,index: int,transform: Transform3D) -> Dictionary:
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var result: Dictionary={"point":transform*points[index]}
	for row: Array in [[Mesh.ARRAY_TEX_UV,"uv"],[Mesh.ARRAY_TEX_UV2,"uv2"],[Mesh.ARRAY_COLOR,"color"]]:
		var attribute: Variant=arrays[int(row[0])]
		if attribute!=null and attribute.size()==points.size():result[String(row[1])]=attribute[index]
	return result

func _append_arrays(triangles: Array,inverse: Transform3D) -> Array:
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	var points: PackedVector3Array=PackedVector3Array();var normals: PackedVector3Array=PackedVector3Array()
	var uvs: PackedVector2Array=PackedVector2Array();var uv2s: PackedVector2Array=PackedVector2Array();var colors: PackedColorArray=PackedColorArray()
	for triangle: Array in triangles:
		var a: Vector3=inverse*(triangle[0].point as Vector3);var b: Vector3=inverse*(triangle[1].point as Vector3);var c: Vector3=inverse*(triangle[2].point as Vector3)
		# Godot uses clockwise front-face winding: its visible normal is c-a x b-a.
		var normal: Vector3=(c-a).cross(b-a).normalized()
		for index: int in range(3):
			points.append([a,b,c][index]);normals.append(normal)
			if triangle[index].has("uv"):uvs.append(triangle[index].uv)
			if triangle[index].has("uv2"):uv2s.append(triangle[index].uv2)
			if triangle[index].has("color"):colors.append(triangle[index].color)
	arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals
	if uvs.size()==points.size() and not uvs.is_empty():arrays[Mesh.ARRAY_TEX_UV]=uvs
	if uv2s.size()==points.size() and not uv2s.is_empty():arrays[Mesh.ARRAY_TEX_UV2]=uv2s
	if colors.size()==points.size() and not colors.is_empty():arrays[Mesh.ARRAY_COLOR]=colors
	return arrays

func warp_mesh(node: MeshInstance3D,rigid_offset: float=NAN) -> Dictionary:
	_begin("mesh")
	if not is_instance_valid(node) or node.mesh==null or not _available():_stats.ok=false;_stats.reason="missing_mesh_or_surface";return _stats.duplicate(true)
	if is_finite(rigid_offset):
		node.global_position+=Vector3.UP*rigid_offset;_stats.rigid=true;_stats.maximum_height_delta_m=absf(rigid_offset);return _stats.duplicate(true)
	var original: Mesh=node.mesh
	var source_arrays: Array=[];var materials: Array[Material]=[];var overrides: Array[Material]=[]
	for index: int in range(original.get_surface_count()):
		if original is ArrayMesh and (original as ArrayMesh).surface_get_primitive_type(index)!=Mesh.PRIMITIVE_TRIANGLES:
			_stats.ok=false;_stats.reason="non_triangle_surface";return _stats.duplicate(true)
		source_arrays.append(original.surface_get_arrays(index));materials.append(original.surface_get_material(index));overrides.append(node.get_surface_override_material(index))
	var key: String=_cache_key("mesh",node,source_arrays)
	var cached: Resource=_cache_read(key,"mesh",source_arrays.size())
	var replacement: ArrayMesh=cached as ArrayMesh
	if replacement==null:
		replacement=ArrayMesh.new()
		for index: int in range(source_arrays.size()):
			var arrays: Array=source_arrays[index]
			var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var count: int=indices.size() if not indices.is_empty() else points.size()
			var triangles: Array=[]
			for offset: int in range(0,count-2,3):
				var vertices: Array=[]
				for corner: int in range(3):vertices.append(_vertex(arrays,indices[offset+corner] if not indices.is_empty() else offset+corner,node.global_transform))
				_warp_triangle(vertices,triangles)
			if triangles.is_empty():
				# Preserve surface slots when outside-domain faces are omitted.
				var empty: Array=[];empty.resize(Mesh.ARRAY_MAX);empty[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
				replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,empty)
			else:replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,_append_arrays(triangles,node.global_transform.affine_inverse()))
		# Save geometry before assigning any current material references. A
		# shader/material revision must appear immediately even on a cache hit.
		_cache_write(replacement,key,"mesh")
	node.mesh=replacement
	for index: int in range(materials.size()):
		replacement.surface_set_material(index,materials[index]);node.set_surface_override_material(index,overrides[index])
	node.set_meta("terrain_projected_runtime",true)
	return _stats.duplicate(true)

func _box_faces(size: Vector3) -> PackedVector3Array:
	var low: Vector3=-size*.5;var high: Vector3=size*.5
	var corners: Array[Vector3]=[Vector3(low.x,low.y,low.z),Vector3(high.x,low.y,low.z),Vector3(high.x,low.y,high.z),Vector3(low.x,low.y,high.z),Vector3(low.x,high.y,low.z),Vector3(high.x,high.y,low.z),Vector3(high.x,high.y,high.z),Vector3(low.x,high.y,high.z)]
	var faces: PackedVector3Array=PackedVector3Array()
	# Every face is clockwise when viewed from outside, as Godot expects.
	for index: int in [0,2,1,0,3,2,4,6,7,4,5,6,0,5,4,0,1,5,3,6,2,3,7,6,0,7,3,0,4,7,1,6,5,1,2,6]:faces.append(corners[index])
	return faces

func warp_shape(node: CollisionShape3D) -> Dictionary:
	_begin("shape")
	if not is_instance_valid(node) or node.shape==null or not _available():_stats.ok=false;_stats.reason="missing_shape_or_surface";return _stats.duplicate(true)
	var shape: Shape3D=node.shape
	var geometry: Dictionary={"source_class":shape.get_class(),"margin":shape.margin,"custom_solver_bias":shape.custom_solver_bias}
	if shape is ConcavePolygonShape3D:geometry["faces"]=(shape as ConcavePolygonShape3D).get_faces();geometry["backface_collision"]=(shape as ConcavePolygonShape3D).backface_collision
	elif shape is BoxShape3D:geometry["size"]=(shape as BoxShape3D).size
	elif shape is ConvexPolygonShape3D:geometry["points"]=(shape as ConvexPolygonShape3D).points
	var key: String=""
	if shape is ConcavePolygonShape3D or shape is ConvexPolygonShape3D or (shape is BoxShape3D and maxf(absf((node.global_basis.get_scale()*shape.size).x),absf((node.global_basis.get_scale()*shape.size).z))>1.25):
		var kind: String="convex_shape" if shape is ConvexPolygonShape3D else "concave_shape"
		key=_cache_key(kind,node,geometry)
		var cached: Resource=_cache_read(key,kind)
		if cached is Shape3D:node.shape=cached as Shape3D;node.set_meta("terrain_projected_runtime",true);return _stats.duplicate(true)
	var faces: PackedVector3Array=PackedVector3Array()
	if shape is ConcavePolygonShape3D:faces=(shape as ConcavePolygonShape3D).get_faces()
	elif shape is BoxShape3D:
		var box: BoxShape3D=shape as BoxShape3D
		var world_size: Vector3=node.global_basis.get_scale()*box.size
		if maxf(absf(world_size.x),absf(world_size.z))<=1.25:
			var height: float=surface.ground_y_world(node.global_position)
			if not is_finite(height):_stats.ok=false;_stats.reason="outside_terrain";return _stats.duplicate(true)
			node.global_position+=Vector3.UP*height;_stats.rigid=true;_stats.maximum_height_delta_m=absf(height);return _stats.duplicate(true)
		faces=_box_faces(box.size)
	elif shape is ConvexPolygonShape3D:
		# Convex debug meshes are wireframes, not filled faces. Keep this prop's
		# convex contract and project its own point cloud; root uses exact
		# concave supports for walkable ground and rigid whole-building offsets.
		var replacement_convex: ConvexPolygonShape3D=(shape as ConvexPolygonShape3D).duplicate() as ConvexPolygonShape3D
		var warped_points: PackedVector3Array=PackedVector3Array();var inverse_convex: Transform3D=node.global_transform.affine_inverse()
		for local_point: Vector3 in (shape as ConvexPolygonShape3D).points:
			var point: Vector3=node.global_transform*local_point
			var height: float=surface.ground_y_world(point)
			if not is_finite(height):_stats.ok=false;_stats.reason="convex_points_outside_terrain";return _stats.duplicate(true)
			warped_points.append(inverse_convex*(point+Vector3.UP*height))
			_stats.maximum_height_delta_m=maxf(float(_stats.maximum_height_delta_m),absf(height))
		replacement_convex.points=warped_points;node.shape=replacement_convex;node.set_meta("terrain_projected_runtime",true)
		_stats.projected_convex_points=warped_points.size();_stats.convex_hull_retained=true
		_cache_write(replacement_convex,key,"convex_shape")
		return _stats.duplicate(true)
	else:
		# Cylinders/capsules/spheres are small outdoor props. Root owns larger
		# rigid building assemblies; non-triangle prop shapes keep their type.
		var height: float=surface.ground_y_world(node.global_position)
		if not is_finite(height):_stats.ok=false;_stats.reason="outside_terrain";return _stats.duplicate(true)
		node.global_position+=Vector3.UP*height;_stats.rigid=true;_stats.maximum_height_delta_m=absf(height);return _stats.duplicate(true)
	if faces.is_empty():_stats.ok=false;_stats.reason="empty_shape_faces";return _stats.duplicate(true)
	var triangles: Array=[]
	for offset: int in range(0,faces.size()-2,3):
		var vertices: Array=[]
		for corner: int in range(3):vertices.append({"point":node.global_transform*faces[offset+corner]})
		_warp_triangle(vertices,triangles)
	var warped: PackedVector3Array=PackedVector3Array();var inverse: Transform3D=node.global_transform.affine_inverse()
	for triangle: Array in triangles:
		for vertex: Dictionary in triangle:warped.append(inverse*(vertex.point as Vector3))
	if warped.is_empty():_stats.ok=false;_stats.reason="shape_outside_terrain";return _stats.duplicate(true)
	var replacement: ConcavePolygonShape3D=ConcavePolygonShape3D.new();replacement.set_faces(warped)
	replacement.backface_collision=shape.backface_collision if shape is ConcavePolygonShape3D else true
	replacement.margin=shape.margin;replacement.custom_solver_bias=shape.custom_solver_bias
	_cache_write(replacement,key,"concave_shape")
	node.shape=replacement;node.set_meta("terrain_projected_runtime",true)
	return _stats.duplicate(true)

func warp_multimesh(node: MultiMeshInstance3D) -> Dictionary:
	_begin("multimesh")
	if not is_instance_valid(node) or node.multimesh==null or not _available():_stats.ok=false;_stats.reason="missing_multimesh_or_surface";return _stats.duplicate(true)
	var multi: MultiMesh=node.multimesh
	if multi.transform_format!=MultiMesh.TRANSFORM_3D:_stats.ok=false;_stats.reason="requires_3d_instances";return _stats.duplicate(true)
	var stride: int=12+(4 if multi.use_colors else 0)+(4 if multi.use_custom_data else 0)
	var buffer: PackedFloat32Array=multi.buffer
	if buffer.size()!=multi.instance_count*stride:
		# Dummy/headless RenderingServer can return no data or identity instance
		# transforms. Never overwrite a native batch using invented readback.
		_stats.ok=false;_stats.reason="native_instance_buffer_unavailable";_stats.instances_unchanged=multi.instance_count;return _stats.duplicate(true)
	var inverse: Transform3D=node.global_transform.affine_inverse();var changed: int=0;var outside: int=0
	for index: int in range(multi.instance_count):
		var offset: int=index*stride
		# Raw transform rows: xx,yx,zx,ox, xy,yy,zy,oy, xz,yz,zz,oz.
		var local: Vector3=Vector3(buffer[offset+3],buffer[offset+7],buffer[offset+11])
		var world: Vector3=node.global_transform*local
		var height: float=surface.ground_y_world(world)
		if not is_finite(height):outside+=1;continue
		var relocated: Vector3=inverse*(world+Vector3.UP*height)
		buffer[offset+3]=relocated.x;buffer[offset+7]=relocated.y;buffer[offset+11]=relocated.z
		changed+=1;_stats.maximum_height_delta_m=maxf(float(_stats.maximum_height_delta_m),absf(height))
	multi.buffer=buffer
	node.set_meta("terrain_projected_runtime",true)
	_stats.instances_changed=changed;_stats.instances_outside_terrain=outside
	return _stats.duplicate(true)
