extends RefCounted
## Broad phase only. Exact source rings and strict point distances remain final.
const CELL_M: float=32.0
const BOUNDS_PAD_M: float=0.0001
const MAX_CELLS_PER_POLYGON: int=65536
var _parts: Array=[]
var _points: Array[Vector2]=[]
var _minimums: Array[Vector2]=[]
var _maximums: Array[Vector2]=[]
var _cells: Dictionary={}
var _global_parts: Array[int]=[]
var _exact: Callable
var _mode: String=""
var _ready: bool=false
var _queries: int=0
var _exact_calls: int=0
var _point_min: Vector2=Vector2.ZERO
var _point_max: Vector2=Vector2.ZERO

func _reset(mode: String) -> void:
	_parts.clear();_points.clear();_minimums.clear();_maximums.clear();_cells.clear();_global_parts.clear()
	_mode=mode;_ready=false;_queries=0;_exact_calls=0

func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(float(point.x)/CELL_M),floori(float(point.y)/CELL_M))

func setup(parts: Array,exact_contains: Callable) -> bool:
	_reset("polygons");_exact=exact_contains
	if not parts.is_empty() and not _exact.is_valid():return false
	_parts=parts.duplicate(false)
	for index: int in range(_parts.size()):
		var poly: Variant=_parts[index]
		if not poly is Array or poly.is_empty() or not poly[0] is PackedVector2Array:return false
		var outer: PackedVector2Array=poly[0]
		if outer.is_empty():_minimums.append(Vector2.ZERO);_maximums.append(Vector2.ZERO);continue
		if outer.size()<4 or outer[0]!=outer[outer.size()-1]:return false
		var low: Vector2=outer[0];var high: Vector2=outer[0]
		for point: Vector2 in outer:
			if not point.is_finite():return false
			low=low.min(point);high=high.max(point)
		_minimums.append(low);_maximums.append(high)
		if maxf(maxf(absf(low.x),absf(low.y)),maxf(absf(high.x),absf(high.y)))>100000000.0:_global_parts.append(index);continue
		var first: Vector2i=_cell(low-Vector2.ONE*BOUNDS_PAD_M);var last: Vector2i=_cell(high+Vector2.ONE*BOUNDS_PAD_M)
		var cell_count: int=(last.x-first.x+1)*(last.y-first.y+1)
		if cell_count>MAX_CELLS_PER_POLYGON:_global_parts.append(index);continue
		for z: int in range(first.y,last.y+1):
			for x: int in range(first.x,last.x+1):
				var key: Vector2i=Vector2i(x,z)
				if not _cells.has(key):_cells[key]=[]
				_cells[key].append(index)
	_ready=true;return true

func contains(point: Vector2) -> bool:
	_queries+=1
	if not _ready or _mode!="polygons" or not point.is_finite() or not _exact.is_valid():return false
	var candidates: Array=[]
	# Avoid Vector2i overflow for finite far-away queries; no ordinary source
	# polygon bbox can contain such a point, but global candidates remain exact.
	if maxf(absf(point.x),absf(point.y))<CELL_M*2000000000.0:candidates=_cells.get(_cell(point),[]).duplicate(false)
	candidates.append_array(_global_parts);candidates.sort()
	for index: int in candidates:
		var low: Vector2=_minimums[index];var high: Vector2=_maximums[index]
		if float(point.x)<float(low.x)-BOUNDS_PAD_M or float(point.y)<float(low.y)-BOUNDS_PAD_M or float(point.x)>float(high.x)+BOUNDS_PAD_M or float(point.y)>float(high.y)+BOUNDS_PAD_M:continue
		_exact_calls+=1
		if bool(_exact.call(point,[_parts[index]])):return true
	return false

func setup_points(points: Array) -> bool:
	_reset("points")
	for value: Variant in points:
		if not value is Vector2 or not value.is_finite():return false
		var point: Vector2=value
		if maxf(absf(point.x),absf(point.y))>=CELL_M*2000000000.0:return false
		var index: int=_points.size();_points.append(point)
		if index==0:_point_min=point;_point_max=point
		else:_point_min=_point_min.min(point);_point_max=_point_max.max(point)
		var key: Vector2i=_cell(point)
		if not _cells.has(key):_cells[key]=[]
		_cells[key].append(index)
	_ready=true;return true

func within_distance(point: Vector2,radius: float) -> bool:
	_queries+=1
	if not _ready or _mode!="points" or not point.is_finite() or is_nan(radius) or radius<=0.0 or _points.is_empty():return false
	var low_x: float=maxf(float(point.x)-radius-BOUNDS_PAD_M,float(_point_min.x));var low_z: float=maxf(float(point.y)-radius-BOUNDS_PAD_M,float(_point_min.y))
	var high_x: float=minf(float(point.x)+radius+BOUNDS_PAD_M,float(_point_max.x));var high_z: float=minf(float(point.y)+radius+BOUNDS_PAD_M,float(_point_max.y))
	if low_x>high_x or low_z>high_z:return false
	var first: Vector2i=Vector2i(floori(low_x/CELL_M),floori(low_z/CELL_M));var last: Vector2i=Vector2i(floori(high_x/CELL_M),floori(high_z/CELL_M));var candidates: Array=[]
	for z: int in range(first.y,last.y+1):
		for x: int in range(first.x,last.x+1):candidates.append_array(_cells.get(Vector2i(x,z),[]))
	candidates.sort()
	for index: int in candidates:
		_exact_calls+=1
		if (point-_points[index]).length()<radius:return true
	return false

func snapshot() -> Dictionary:
	return {"ready":_ready,"mode":_mode,"polygons":_parts.size(),"points":_points.size(),"cells":_cells.size(),"global_polygons":_global_parts.size(),"queries":_queries,"exact_calls":_exact_calls,"cell_m":CELL_M,"source_mutated":false,"final_predicate":"original_callable_point_single_polygon" if _mode=="polygons" else "original_strict_Vector2_difference_length_less_than_radius"}
