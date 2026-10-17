extends RefCounted
## Independent equivalence checks. Production callbacks define boundary truth.
const INDEX=preload("res://scripts/source_polygon_index.gd")
const EPS: float=0.0002
var failures: Array[Dictionary]=[]
var comparisons: int=0

func _failure(value: Dictionary) -> void:
	if failures.size()<30:failures.append(value)

func _polygon_samples(parts: Array) -> Array[Vector2]:
	var result: Array[Vector2]=[];var low: Vector2=Vector2(INF,INF);var high: Vector2=Vector2(-INF,-INF)
	for poly: Array in parts:
		for ring: PackedVector2Array in poly:
			for i: int in range(ring.size()):
				var point: Vector2=ring[i];low=low.min(point);high=high.max(point)
				for offset: Vector2 in [Vector2.ZERO,Vector2(EPS,0),Vector2(-EPS,0),Vector2(0,EPS),Vector2(0,-EPS)]:result.append(point+offset)
				if i>0:result.append((point+ring[i-1])*.5)
	if not parts.is_empty():
		var step: float=maxf(40.0,sqrt(maxf(1.,(high.x-low.x)*(high.y-low.y))/4096.0))
		for z: int in range(floori(low.y/step)-1,ceili(high.y/step)+2):
			for x: int in range(floori(low.x/step)-1,ceili(high.x/step)+2):result.append(Vector2(x*step,z*step))
	result.append_array([Vector2(1000000,1000000),Vector2(-1000000,-1000000),Vector2.ZERO])
	return result

func _polygons(label: String,parts: Array,callback: Callable) -> Dictionary:
	var before: PackedByteArray=var_to_bytes(parts);var index: RefCounted=INDEX.new();var ready: bool=index.setup(parts,callback)
	if not ready:_failure({"kind":label,"reason":"setup_failed"});return {}
	var samples: Array[Vector2]=_polygon_samples(parts);var mismatches: int=0
	for point: Vector2 in samples:
		var expected: bool=bool(callback.call(point,parts));var actual: bool=index.contains(point);comparisons+=1
		if expected!=actual:mismatches+=1;_failure({"kind":label,"point_xz":[point.x,point.y],"expected":expected,"actual":actual})
	for point: Vector2 in [Vector2(NAN,0),Vector2(INF,0),Vector2(0,-INF)]:
		comparisons+=1
		if index.contains(point):_failure({"kind":label,"reason":"nonfinite_accepted"})
	if before!=var_to_bytes(parts):_failure({"kind":label,"reason":"source_parts_mutated"})
	return {"samples":samples.size(),"mismatches":mismatches,"source_unchanged":before==var_to_bytes(parts),"index":index.snapshot()}

func _near_original(point: Vector2,points: Array[Vector2],radius: float) -> bool:
	for target: Vector2 in points:
		if (point-target).length()<radius:return true
	return false

func _doors(label: String,doors: Array) -> Dictionary:
	var points: Array[Vector2]=[]
	for door: Vector3 in doors:points.append(Vector2(door.x,door.z))
	var before: PackedByteArray=var_to_bytes(doors);var index: RefCounted=INDEX.new();var ready: bool=index.setup_points(points);var mismatches: int=0;var count: int=0
	if not ready:_failure({"kind":label,"reason":"point_setup_failed"});return {}
	for origin: Vector2 in points:
		for direction: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
			for offset: float in [-EPS,0.,EPS]:
				var point: Vector2=origin+direction*(1.28+offset);var expected: bool=_near_original(point,points,1.28);var actual: bool=index.within_distance(point,1.28);count+=1;comparisons+=1
				if expected!=actual:mismatches+=1;_failure({"kind":label,"point_xz":[point.x,point.y],"radius":1.28,"expected":expected,"actual":actual})
	for point: Vector2 in [Vector2(NAN,0),Vector2(INF,0),Vector2(1000000,1000000)]:
		if index.within_distance(point,1.28):_failure({"kind":label,"reason":"outside_or_nonfinite_point_accepted"})
	if before!=var_to_bytes(doors):_failure({"kind":label,"reason":"source_doors_mutated"})
	return {"door_count":points.size(),"boundary_comparisons":count,"mismatches":mismatches,"source_unchanged":before==var_to_bytes(doors),"index":index.snapshot(),"coordinates":"Original world XZ; door Y ignored, exact original difference.length()<radius"}

func _usage(module: Node3D,label: String) -> Dictionary:
	var private_index: RefCounted=module.get("private_polygon_index");var road_index: RefCounted=module.get("road_polygon_index");var doors: RefCounted=module.get("_door_guard_index")
	if not is_instance_valid(private_index) or not is_instance_valid(road_index) or not is_instance_valid(doors):_failure({"kind":label,"reason":"live_guard_index_missing"});return {}
	var before: Array=[private_index.snapshot().queries,road_index.snapshot().queries,doors.snapshot().queries]
	var groups: Array=module.get("groups")
	if groups.is_empty():_failure({"kind":label,"reason":"no_group_for_actual_allowed_guard"});return {}
	var point: Vector3=groups[0].points[0]
	# The real source-guard wrappers and real _allowed must call these instances.
	module._source_private_contains(Vector2.ZERO);module._source_road_contains(Vector2.ZERO);module._source_door_near(point,.28)
	var middle: Array=[private_index.snapshot().queries,road_index.snapshot().queries,doors.snapshot().queries]
	var allowed: bool=module._allowed(point,.28)
	var after: Array=[private_index.snapshot().queries,road_index.snapshot().queries,doors.snapshot().queries]
	if int(middle[0])<=int(before[0]) or int(middle[1])<=int(before[1]) or int(middle[2])<=int(before[2]) or int(after[0])<=int(middle[0]):_failure({"kind":label,"reason":"actual_guard_did_not_query_indexes","before":before,"middle":middle,"after":after})
	return {"before":before,"after_wrappers":middle,"after_actual_allowed":after,"allowed_at_source_route_start":allowed}

func inspect(scene: Node3D) -> Dictionary:
	failures.clear();comparisons=0
	var city: Node3D=scene.city;var callback: Callable=Callable(city,"_contains");var roads: Array=[]
	for parts: Array in city.road_cache:roads.append_array(parts)
	var source_before: PackedByteArray=var_to_bytes([city.private_cache,city.road_cache])
	var private_result: Dictionary=_polygons("actual_private",city.private_cache,callback)
	var road_result: Dictionary=_polygons("actual_flattened_roads",roads,callback)
	var outer: PackedVector2Array=PackedVector2Array([Vector2(-64,-64),Vector2(64,-64),Vector2(64,64),Vector2(-64,64),Vector2(-64,-64)])
	var hole: PackedVector2Array=PackedVector2Array([Vector2(-32,-32),Vector2(32,-32),Vector2(32,32),Vector2(-32,32),Vector2(-32,-32)])
	var island: PackedVector2Array=PackedVector2Array([Vector2(-8,-8),Vector2(8,-8),Vector2(8,8),Vector2(-8,8),Vector2(-8,-8)])
	var adversarial: Dictionary=_polygons("negative_cells_hole_second_polygon",[[outer,hole],[island]],callback)
	var empty: RefCounted=INDEX.new();var empty_ok: bool=empty.setup([],callback) and not empty.contains(Vector2.ZERO) and empty.setup_points([]) and not empty.within_distance(Vector2.ZERO,1.)
	var isolated: RefCounted=INDEX.new();var isolated_ok: bool=isolated.setup_points([Vector2.ZERO]) and not isolated.within_distance(Vector2(1.,0),1.) and isolated.within_distance(Vector2(1.-EPS,0),1.) and not isolated.within_distance(Vector2(1.+EPS,0),1.) and not isolated.within_distance(Vector2.ZERO,NAN)
	if not empty_ok or not isolated_ok:_failure({"kind":"adversarial_points","empty":empty_ok,"strict_radius_boundary":isolated_ok})
	var invalid: RefCounted=INDEX.new();var nonfinite_source_rejected: bool=not invalid.setup([[PackedVector2Array([Vector2.ZERO,Vector2(INF,0),Vector2(0,1),Vector2.ZERO])]],callback) and not invalid.setup_points([Vector2(NAN,0)])
	if not nonfinite_source_rejected:_failure({"kind":"invalid_source","reason":"nonfinite_source_accepted"})
	var street: Node3D=scene.street_pedestrians;var coverage: Node3D=scene.neighborhood_population.walkers
	var street_doors: Dictionary=_doors("street_actual_doors",street._doors)
	var coverage_doors: Dictionary=_doors("coverage_actual_doors",coverage._doors)
	var usage: Dictionary={"street":_usage(street,"street_live_usage"),"coverage":_usage(coverage,"coverage_live_usage")}
	if source_before!=var_to_bytes([city.private_cache,city.road_cache]):_failure({"kind":"actual_source","reason":"source_array_bytes_changed"})
	return {"passed":failures.is_empty(),"evidence":{"comparisons":comparisons,"private":private_result,"roads":road_result,"adversarial_holes_boundaries":adversarial,"street_doors":street_doors,"coverage_doors":coverage_doors,"live_usage":usage,"empty_and_strict_radius":empty_ok and isolated_ok,"nonfinite_source_rejected":nonfinite_source_rejected,"failures":failures,"scope":"Original exact membership/holes/strict radius equality plus actual guard use. Broad-phase padding does not widen final permissions. No movement or performance acceptance."}}
