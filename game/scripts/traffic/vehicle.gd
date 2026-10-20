extends CharacterBody3D
## N03: the unchanged N01 source-forward polyline, followed by physical motion.
## Configure before add_child. Only spawn and a current-tick manager guard recycle
## may assign position; ordinary driving always uses move_and_slide.

const MAX_SPEED_MPS: float = 5.0
const CROSSING_SPEED_MPS: float = 2.0
const ACCEL_MPS2: float = 1.5
const BRAKE_MPS2: float = 3.0
const REACTION_S: float = 0.5
const CLEARANCE_M: float = 1.0
const GRAVITY_MPS2: float = 9.8
const POINT_EPS_M: float = 0.0001
const SPEED_EPS_MPS: float = 0.001
const ROUTE_TOLERANCE_M: float = 0.003

@onready var body_shape: CollisionShape3D = $CollisionShape

var _manager: Node
var _static_world: Node3D
var _route_id: String = ""
var _points: PackedVector3Array = PackedVector3Array()
var _arc: PackedFloat64Array = PackedFloat64Array()
var _conflicts: Array[Dictionary] = []
var _length_m: float = 0.0
var _end_stop_s_m: float = 0.0
var _station_m: float = 0.0
var _segment: int = 0
var _speed_mps: float = 0.0
var _command_speed_mps: float = 0.0
var _motion_parts: int = 0
var _configured: bool = false
var _running: bool = true
var _state: String = "unconfigured"
var _blocked_reason: String = ""
var _permission: Dictionary = {}
var _support_exclusions: Array[RID] = []
var _last_support_rid: RID = RID()
var _floor_name: String = ""
var _floor_path: String = ""
var _floor_reason: String = "not_observed"
var _physics_steps: int = 0
var _elapsed_s: float = 0.0
var _pause_ticks: int = 0
var _distance_m: float = 0.0
var _cycle_distance_m: float = 0.0
var _max_step_m: float = 0.0
var _max_speed_mps: float = 0.0
var _max_route_offset_m: float = 0.0
var _cycle_count: int = 0
var _end_events: int = 0
var _last_recycle_tick: int = -1
var _endpoint_history: Array[Dictionary] = []
var _recycle_history: Array[Dictionary] = []
var _obstacle: Dictionary = {}
var _painted_signal_observation: Dictionary = {}
var _painted_signal_commit: Dictionary = {}
var _painted_signal_events: Array[Dictionary] = []
var _motion_cap_m: float = INF
var _terrain_enabled: bool = false
var _terrain_normal: Vector3 = Vector3.UP
var _terrain_grade: float = 0.0
var _terrain_node: Node
var _terrain_pose_cache: Dictionary={}
var _terrain_query_tick: int=-1
var _terrain_query_counts: Dictionary={}
var _terrain_orientation_blocked: bool=false
var _terrain_clearance_moves: int=0
var _terrain_clearance_distance_this_tick_m: float=0.0
var _last_motion_contacts: Array[Dictionary]=[]
const TERRAIN_CLEARANCE_M: float=.003
## Test-only one-tick pulses audit the early bound against every original
## posed sweep. Production takes the proven-empty shortcut without this work.
var terrain_verify_early_bounds: bool=false
var _early_bounds_checks: int=0
var _early_bounds_verified: int=0
var _early_empty_verified: int=0
var _early_bounds_violations: int=0
var _early_bounds_empty_returns: int=0
var _last_early_bounds_violation: Dictionary={}
var _early_terrain_bounds: AABB=AABB()
var _early_terrain_bounds_valid: bool=false


func _terrain_service() -> Node:
	if not is_instance_valid(_static_world):return null
	var candidate: Variant=_static_world.get_parent().get("terrain_surface")
	return candidate as Node if is_instance_valid(candidate) and bool(candidate.get("loaded")) else null


func _reset_terrain_queries() -> void:
	var tick: int=Engine.get_physics_frames()
	if _terrain_query_tick==tick:return
	_terrain_query_tick=tick;_terrain_pose_cache.clear()
	_terrain_query_counts={"ground":0,"pose_cache_hits":0,"ground_envelopes":0,"envelope_triangles":0,"early_broadphase":0,"early_empty":0,"broadphase":0,"narrow_intersections":0,"narrow_sweeps":0}


func _terrain_height(at: Vector3) -> float:
	_reset_terrain_queries();_terrain_query_counts.ground=int(_terrain_query_counts.ground)+1
	var terrain: Node=_terrain_node if is_instance_valid(_terrain_node) else _terrain_service()
	return NAN if terrain==null else terrain.ground_y_world(at)


func _sample_terrain(at: Vector3) -> Dictionary:
	var terrain: Node=_terrain_node if is_instance_valid(_terrain_node) else _terrain_service()
	return {} if terrain==null else terrain.sample_ground_world(at)


func _terrain_triangle_height(triangle: Dictionary,point: Vector2) -> float:
	var a: Vector3=triangle.a;var b: Vector3=triangle.b;var c: Vector3=triangle.c
	var determinant: float=(b.z-c.z)*(a.x-c.x)+(c.x-b.x)*(a.z-c.z)
	if absf(determinant)<.0000000001:return NAN
	var first: float=((b.z-c.z)*(point.x-c.x)+(c.x-b.x)*(point.y-c.z))/determinant
	var second: float=((c.z-a.z)*(point.x-c.x)+(a.x-c.x)*(point.y-c.z))/determinant
	return first*a.y+second*b.y+(1.0-first-second)*c.y


func _terrain_clearance_height(at: Vector3,basis: Basis) -> float:
	var height: float=_terrain_height(at)
	if not is_finite(height) or basis.y.y<=.0001:return NAN
	_terrain_query_counts.ground_envelopes=int(_terrain_query_counts.ground_envelopes)+1
	var terrain: Node=_terrain_node if is_instance_valid(_terrain_node) else _terrain_service()
	if terrain==null:return NAN
	var polygon: PackedVector2Array=PackedVector2Array();var low: Vector2=Vector2.INF;var high: Vector2=-Vector2.INF
	for offset: Vector3 in [Vector3(-.9,0.,-2.1),Vector3(.9,0.,-2.1),Vector3(.9,0.,2.1),Vector3(-.9,0.,2.1)]:
		var corner: Vector3=at+basis*offset;var flat: Vector2=Vector2(corner.x,corner.z)
		polygon.append(flat);low=low.min(flat);high=high.max(flat)
	# The difference between a terrain triangle plane and the rigid bottom
	# plane is affine. Its exact maximum over their intersection lies at an
	# intersection vertex, including interior ridge/edge vertices missed by
	# centre/corner-only probes. No extra ground permission or curb exclusion.
	for triangle: Dictionary in terrain.triangles_at_xz_rect(Rect2(low,high-low).grow(.00001)):
		_terrain_query_counts.envelope_triangles=int(_terrain_query_counts.envelope_triangles)+1
		var ground_polygon: PackedVector2Array=PackedVector2Array([Vector2(triangle.a.x,triangle.a.z),Vector2(triangle.b.x,triangle.b.z),Vector2(triangle.c.x,triangle.c.z)])
		for intersection: PackedVector2Array in Geometry2D.intersect_polygons(polygon,ground_polygon):
			for point: Vector2 in intersection:
				var ground: float=_terrain_triangle_height(triangle,point)
				if not is_finite(ground):continue
				var normal: Vector3=basis.y
				var bottom_offset: float=-(normal.x*(point.x-at.x)+normal.z*(point.y-at.z))/normal.y
				height=maxf(height,ground-bottom_offset)
	return height+TERRAIN_CLEARANCE_M

func _terrain_pose(at: Vector3, yaw: float) -> Transform3D:
	_reset_terrain_queries()
	var key: Vector3=Vector3(at.x,at.z,yaw)
	if _terrain_pose_cache.has(key):_terrain_query_counts.pose_cache_hits=int(_terrain_query_counts.pose_cache_hits)+1;return _terrain_pose_cache[key]
	var centre_height: float=_terrain_height(at)
	if not is_finite(centre_height):return Transform3D(Basis(Vector3.UP,yaw),at)
	var flat: Basis=Basis(Vector3.UP,yaw)
	var heights: Array[float]=[]
	for x: float in [-.9,.9]:
		for z: float in [-2.1,2.1]:
			var height: float=_terrain_height(at+flat*Vector3(x,0.,z))
			heights.append(height if is_finite(height) else centre_height)
	# Fit a footprint plane instead of inheriting a single TIN triangle's
	# discontinuous normal. Indices: left-front,left-back,right-front,right-back.
	var side_gradient: float=((heights[2]+heights[3])-(heights[0]+heights[1]))/(2.0*1.8)
	var back_gradient: float=((heights[1]+heights[3])-(heights[0]+heights[2]))/(2.0*4.2)
	var normal: Vector3=(Vector3.UP-flat.x*side_gradient-flat.z*back_gradient).normalized()
	var forward: Vector3=-flat.z;forward=(forward-normal*forward.dot(normal)).normalized()
	var right: Vector3=forward.cross(normal).normalized()
	var basis: Basis=Basis(right,normal,-forward).orthonormalized()
	var feet: Vector3=Vector3(at.x,centre_height,at.z)
	# Resample the actual tilted corners too. Their horizontal projection differs
	# slightly from the four yaw-only samples used to estimate the stable plane.
	feet.y=_terrain_clearance_height(feet,basis)
	var result: Transform3D=Transform3D(basis,feet)
	_terrain_pose_cache[key]=result
	return result


func _collect_motion_contacts() -> void:
	var count: int=get_slide_collision_count()
	if count==0:return
	_last_motion_contacts.clear()
	for index: int in range(mini(count,4)):
		var collision: KinematicCollision3D=get_slide_collision(index)
		var collider: Object=collision.get_collider()
		var node: Node=collider as Node
		_last_motion_contacts.append({"normal":_vector(collision.get_normal()),"point":_vector(collision.get_position()),"collider":String(node.get_path()) if is_instance_valid(node) else str(collider),"geometry_id":node.get_meta("geometry_id","") if is_instance_valid(node) else ""})


func _apply_terrain_orientation(delta: float=1.0/60.0) -> bool:
	if not _terrain_enabled:return true
	var pose: Transform3D=_terrain_pose(global_position,_heading(_segment_direction(_segment)))
	var rise: float=pose.origin.y-global_position.y
	_terrain_orientation_blocked=false
	if rise>.0001:
		# Rotation can put a new lower corner inside the old road plane. Obtain
		# the required vertical clearance through physics before rotating the box.
		var previous_velocity: Vector3=velocity
		var before_clearance: Vector3=global_position
		velocity=Vector3(0.0,rise/maxf(.000001,delta),0.0);move_and_slide();_collect_motion_contacts();_terrain_clearance_moves+=1
		var horizontal_clearance: float=Vector2(global_position.x-before_clearance.x,global_position.z-before_clearance.z).length()
		_terrain_clearance_distance_this_tick_m+=horizontal_clearance
		if horizontal_clearance>.0000001:_record_station()
		velocity=previous_velocity
		if global_position.y<pose.origin.y-.001:
			_terrain_orientation_blocked=true;return false
	global_basis=pose.basis
	# Re-establish actual contact with the newly oriented shape through the
	# CharacterBody floor query, rather than leaving a permanent clearance gap.
	var before_snap: Vector3=global_position
	apply_floor_snap()
	var snap_horizontal: float=Vector2(global_position.x-before_snap.x,global_position.z-before_snap.z).length()
	_terrain_clearance_distance_this_tick_m+=snap_horizontal
	if snap_horizontal>.0000001:_record_station()
	_terrain_normal=pose.basis.y
	_terrain_grade=sqrt(maxf(0.0,1.0-_terrain_normal.y*_terrain_normal.y))/maxf(.0001,_terrain_normal.y)
	return true

func refresh_terrain() -> void:
	# Called once after the outdoor support shapes have been warped. Elevation
	# never changes original XZ station/length contracts or ordinary motion.
	_terrain_node=_terrain_service();_terrain_enabled=_terrain_node!=null
	if not _configured or not _terrain_enabled:return
	var visual: MeshInstance3D=_terrain_node.get("visual") as MeshInstance3D
	if is_instance_valid(visual) and visual.mesh!=null:
		_early_terrain_bounds=visual.global_transform*visual.mesh.get_aabb()
		_early_terrain_bounds_valid=_early_terrain_bounds.position.is_finite() and _early_terrain_bounds.size.is_finite() and _early_terrain_bounds.size.x>0.0 and _early_terrain_bounds.size.z>0.0
	for index: int in range(_points.size()):
		var sample: Dictionary=_sample_terrain(_points[index])
		if bool(sample.get("ok",false)):_points[index].y=sample.point.y
	var start: Vector3=_points[_segment]+_segment_direction(_segment)*(_station_m-_arc[_segment])
	global_transform=_terrain_pose(start,_heading(_segment_direction(_segment)))
	velocity=Vector3.ZERO;floor_snap_length=.45
	_apply_terrain_orientation()
	_find_support()


func configure(route: Dictionary, manager: Node, static_world: Node3D) -> void:
	_configured = false
	_manager = manager
	_static_world = static_world
	_route_id = String(route.get("id", ""))
	_points.clear()
	_arc.clear()
	_conflicts.clear()
	_arc.append(0.0)
	var ground_y: float = float(route.get("ground_y_m", 0.0))
	for raw_point: Variant in route.get("xz", []):
		var point: Array = raw_point as Array
		if point.size() != 2:
			return
		_points.append(static_world.to_global(Vector3(float(point[0]), ground_y, float(point[1]))))
		if _points.size() > 1:
			var offset: Vector3 = _points[-1] - _points[-2]
			offset.y = 0.0
			if offset.length() <= POINT_EPS_M:
				return
			_arc.append(_arc[-1] + offset.length())
	if _points.size() < 2:
		return
	_length_m = _arc[-1]
	if absf(_length_m - float(route.get("length_m", -1.0))) > 0.001:
		return
	var binding: Dictionary = route.get("source_binding", {})
	if String(binding.get("source_direction", "")) != "source_forward":
		return
	for item: Variant in route.get("conflicts", []):
		_conflicts.append((item as Dictionary).duplicate(true))
	_end_stop_s_m = clampf(float(route.get("end_stop_s_m", _length_m)), 0.0, _length_m)
	_configured = is_instance_valid(_manager) and _manager.has_method("permission")
	if _configured:
		_state = "accelerating"


func _ready() -> void:
	if not _configured:
		set_physics_process(false)
		return
	process_physics_priority = 1
	global_position = _points[0]
	global_rotation.y = _heading(_segment_direction(0))
	_find_support()


func set_running(enabled: bool) -> void:
	_running = enabled
	if not enabled:
		velocity = Vector3.ZERO
		_speed_mps = 0.0
		_command_speed_mps = 0.0


func _physics_process(delta: float) -> void:
	_physics_steps += 1
	if not _running:
		_pause_ticks += 1
		velocity = Vector3.ZERO
		return
	_elapsed_s += delta
	_terrain_clearance_distance_this_tick_m=0.0
	_apply_terrain_orientation(delta)
	_find_support()
	# The manager refreshes lazily once per physics frame, after priority-0 humans.
	_permission = _manager.call("permission", self) as Dictionary
	var step_budget: float = _choose_step_budget(delta)
	# A clearance move can slide a fraction along the road. Its actual XZ
	# travel consumes this same tick's budget; never silently add it on top.
	step_budget=maxf(0.0,step_budget-_terrain_clearance_distance_this_tick_m)
	var step_m: float = _move_on_polyline(step_budget, delta)
	step_m+=_terrain_clearance_distance_this_tick_m
	_speed_mps = step_m / delta
	# A vertex may split a physical tick into several part/delta calls. Restore
	# the achieved arc speed on the final tangent, rather than exposing only the
	# shortened last part's velocity as this tick's driving velocity.
	var tangent: Vector3 = _segment_direction(_segment)
	velocity.x = tangent.x * _speed_mps
	velocity.z = tangent.z * _speed_mps
	_distance_m += step_m
	_cycle_distance_m += step_m
	_max_step_m = maxf(_max_step_m, step_m)
	_max_speed_mps = maxf(_max_speed_mps, _speed_mps)
	if _at_endpoint() and _speed_mps <= SPEED_EPS_MPS:
		if _state != "endpoint_wait":
			_end_events += 1
			_endpoint_history.append({"time_s": _elapsed_s, "tick": Engine.get_physics_frames(), "position": _vector(global_position), "station_m": _station_m, "cycle_distance_m": _cycle_distance_m})
		_state = "endpoint_wait"
		_speed_mps = 0.0
		velocity.x = 0.0
		velocity.z = 0.0


func _choose_step_budget(delta: float) -> float:
	_command_speed_mps = 0.0
	if _state == "off_route":
		return 0.0
	if _terrain_enabled and _terrain_orientation_blocked:
		_state="waiting_terrain_clearance";_blocked_reason="physical_orientation_clearance_blocked";return 0.0
	_blocked_reason = ""
	_motion_cap_m = INF
	_obstacle = {}
	if _state == "endpoint_wait":
		return 0.0
	if not _advance_vertex():
		return 0.0
	var target_speed: float = MAX_SPEED_MPS
	var end_remaining: float = maxf(0.0, _length_m - _station_m)
	# Start preparing at N01's end_stop_s_m, using a gentler brake curve that
	# reaches the actual endpoint rather than stopping one safety margin short.
	if _station_m >= _end_stop_s_m:
		var zone_length: float = maxf(POINT_EPS_M, _length_m - _end_stop_s_m)
		var end_brake: float = minf(BRAKE_MPS2, MAX_SPEED_MPS * MAX_SPEED_MPS / (2.0 * zone_length))
		target_speed = minf(target_speed, _braking_speed(end_remaining, delta, end_brake))
		_state = "braking_endpoint"
	var fresh: bool = bool(_permission.get("fresh", false))
	var conflict: Dictionary = _current_conflict()
	if not fresh:
		target_speed = 0.0
		_state = "waiting_information"
		_blocked_reason = String(_permission.get("reason", "missing_current_observation"))
	if _floor_reason != "up_floor_ray" and not is_on_floor():
		target_speed = 0.0
		_state = "waiting_support"
		_blocked_reason = _floor_reason
	if not conflict.is_empty():
		var enter_s: float = float(conflict["enter_s_m"])
		var entry_remaining: float = maxf(0.0, enter_s - _station_m)
		var crossing_limit: float = CROSSING_SPEED_MPS
		if _station_m < enter_s:
			# v*dt + (v^2-v_cross^2)/(2*a) <= distance to entry.
			# Reserve the next step as well as the continuous braking distance.
			var brake_step: float = BRAKE_MPS2 * delta
			crossing_limit = sqrt(brake_step * brake_step + CROSSING_SPEED_MPS * CROSSING_SPEED_MPS + 2.0 * BRAKE_MPS2 * entry_remaining) - brake_step
		if crossing_limit < target_speed:
			target_speed = crossing_limit
			_state = "braking_for_crossing" if _station_m < enter_s else "crossing_slow"
		var stop_s: float = float(conflict["stop_s_m"])
		var allow: bool = fresh and bool(_permission.get("allow_crossing", false))
		var human: bool = bool(_permission.get("human_present", true))
		if not allow and _station_m <= stop_s + POINT_EPS_M:
			var stop_remaining: float = maxf(0.0, stop_s - _station_m)
			_motion_cap_m = minf(_motion_cap_m, stop_remaining)
			target_speed = minf(target_speed, _braking_speed(stop_remaining, delta))
			_state = "braking_crossing" if _speed_mps > SPEED_EPS_MPS else "waiting_crossing"
			_blocked_reason = String(_permission.get("reason", "crossing_not_reserved"))
		elif not allow or human:
			target_speed = 0.0
			_state = "braking_human" if human else "braking_crossing"
			_blocked_reason = String(_permission.get("reason", "crossing_occupied"))
	var lookahead: float = _speed_mps * REACTION_S + _speed_mps * _speed_mps / (2.0 * BRAKE_MPS2) + CLEARANCE_M
	_obstacle = _corridor_obstacle(lookahead)
	if not _obstacle.is_empty():
		# React immediately throughout the full planned reaction/braking corridor.
		# A new close obstruction additionally caps this step before physical contact.
		target_speed = 0.0
		_motion_cap_m = minf(_motion_cap_m, maxf(0.0, float(_obstacle.get("distance_m", 0.0)) - 0.05))
		_state = "braking_obstacle" if _speed_mps > SPEED_EPS_MPS else "waiting_obstacle"
		_blocked_reason = String(_obstacle.get("reason", "unknown_obstacle"))
	target_speed=_painted_signal_speed(target_speed,delta)
	var change: float = ACCEL_MPS2 * delta if target_speed > _speed_mps else BRAKE_MPS2 * delta
	var next_speed: float = move_toward(_speed_mps, target_speed, change)
	_command_speed_mps = next_speed
	if target_speed >= MAX_SPEED_MPS - SPEED_EPS_MPS and _blocked_reason.is_empty():
		_state = "driving" if next_speed >= MAX_SPEED_MPS - SPEED_EPS_MPS else "accelerating"
	var step_budget: float = minf(next_speed * delta, _motion_cap_m)
	# Finish the final submillimetre through a bounded physical move, avoiding an
	# asymptotic stop just short of a point while never skipping an N01 vertex.
	if end_remaining <= POINT_EPS_M and _blocked_reason.is_empty():
		step_budget = minf(POINT_EPS_M, _motion_cap_m)
	return maxf(0.0, step_budget)


func _painted_signal_speed(target_speed: float,delta: float) -> float:
	# Optional exploration signals supplement the old route conflicts without
	# editing their source polyline or granting a FIFO/human-priority bypass.
	# BusBody has its own longer-body service controller and does not expose
	# this manager hook, so its front/rear clearance policy remains independent.
	if not is_instance_valid(_manager) or not _manager.has_method("painted_signal_limit"):return target_speed
	if not _painted_signal_commit.is_empty() and _station_m>=float(_painted_signal_commit.clear_station_m):
		_painted_signal_event("rear_cleared",_painted_signal_commit)
		_painted_signal_commit.clear()
	var observed: Dictionary=_manager.painted_signal_limit(self,_segment_direction(_segment),30.0)
	_painted_signal_observation=observed.duplicate(true)
	var id: String=String(observed.get("crossing_id",""))
	if id.is_empty():return target_speed
	if not _painted_signal_commit.is_empty() and String(_painted_signal_commit.crossing_id)==id:return target_speed
	var half_length: float=(body_shape.shape as BoxShape3D).size.z*.5
	var distance: float=float(observed.get("distance_m",INF))
	var remaining: float=distance-half_length-.35
	var phase: String=String(observed.get("state","uncontrolled"))
	# Historical managers may report a distant FIFO hold while still permitting
	# travel up to that old stop point. Use the actual motion budget rather than
	# treating that descriptive reason as a present obstruction at this crossing.
	var clear_to_move: bool=bool(_permission.get("fresh",false)) and target_speed>SPEED_EPS_MPS and _obstacle.is_empty() and _motion_cap_m>POINT_EPS_M
	var brake_room: float=_speed_mps*_speed_mps/(2.0*BRAKE_MPS2)+_speed_mps*delta
	var crossing_this_step: bool=remaining<=maxf(.05,_speed_mps*delta) and _speed_mps>.10
	var unavoidable_amber: bool=phase=="amber" and _speed_mps>.5 and remaining<brake_room
	if clear_to_move and ((phase=="green" and crossing_this_step) or unavoidable_amber):
		var clearance: float=maxf(0.0,float(observed.get("clearance_from_stop_m",8.0)))
		_painted_signal_commit={"crossing_id":id,"entry_phase":phase,"entry_station_m":_station_m,"clear_station_m":_station_m+distance+clearance+half_length+.50,"reason":"green_front_entry" if phase=="green" else "amber_insufficient_physical_brake_room"}
		_painted_signal_event("committed",_painted_signal_commit)
		return target_speed
	if not bool(observed.get("required",false)):return target_speed
	_motion_cap_m=minf(_motion_cap_m,maxf(0.0,remaining))
	var limit: float=_braking_speed(maxf(0.0,remaining),delta)
	if limit<target_speed:
		target_speed=limit
		_state="braking_painted_signal" if _speed_mps>SPEED_EPS_MPS else "waiting_painted_signal"
		_blocked_reason="painted_signal_"+phase
	return target_speed


func _painted_signal_event(kind: String,evidence: Dictionary) -> void:
	if _painted_signal_events.size()>=48:_painted_signal_events.pop_front()
	_painted_signal_events.append({"event":kind,"tick":Engine.get_physics_frames(),"station_m":_station_m,"evidence":evidence.duplicate(true)})


func _move_on_polyline(step_budget: float, delta: float) -> float:
	# Consume this tick's distance along every encountered original segment.
	# Each physical part uses part/delta, so no diagonal chord or waypoint teleport
	# is introduced, and a short last fragment does not reset the driving speed.
	var remaining_budget: float = step_budget
	var achieved_distance: float = 0.0
	_motion_parts = 0
	var first_part: bool = true
	var vertical_speed: float = 0.0 if is_on_floor() else velocity.y - GRAVITY_MPS2 * delta
	var accounted_clearance: float=_terrain_clearance_distance_this_tick_m
	for _part: int in range(_points.size() + 1):
		if not first_part and (remaining_budget <= 0.000001 or not _advance_vertex()):
			break
		var extra_clearance: float=maxf(0.0,_terrain_clearance_distance_this_tick_m-accounted_clearance)
		remaining_budget=maxf(0.0,remaining_budget-extra_clearance);accounted_clearance=_terrain_clearance_distance_this_tick_m
		var vertex_remaining: float = maxf(0.0, _arc[_segment + 1] - _station_m)
		var part_budget: float = minf(remaining_budget, vertex_remaining)
		var next_station: float = _station_m + part_budget
		var target: Vector3 = _points[_segment] + _segment_direction(_segment) * (next_station - _arc[_segment])
		var motion: Vector3 = target - global_position
		motion.y = 0.0
		motion = motion.limit_length(part_budget)
		var before: Vector3 = global_position
		velocity.x = motion.x / delta
		velocity.z = motion.z / delta
		# Apply this tick's vertical displacement once, even when crossing vertices.
		velocity.y = vertical_speed if first_part else 0.0
		if _terrain_enabled and (is_on_floor() or _floor_reason=="up_floor_ray"):
			var ground_pose: Transform3D=_terrain_pose(global_position+motion,_heading(_segment_direction(_segment)))
			# Request the surface rise through the same physical move, never snap
			# the body to the height sample during normal driving.
			var retained_basis_height: float=_terrain_clearance_height(global_position+motion,global_basis)
			var desired_height: float=maxf(ground_pose.origin.y,retained_basis_height) if is_finite(retained_basis_height) else ground_pose.origin.y
			velocity.y=(desired_height-TERRAIN_CLEARANCE_M-global_position.y)/delta
		move_and_slide()
		if _terrain_enabled:_collect_motion_contacts()
		_motion_parts += 1
		if first_part:
			vertical_speed = velocity.y
		first_part = false
		var achieved: Vector3 = global_position - before
		achieved.y = 0.0
		var distance: float = achieved.length()
		achieved_distance += distance
		remaining_budget = maxf(0.0, remaining_budget - distance)
		_record_station()
		if _state == "off_route":
			break
		if motion.length() > POINT_EPS_M and distance < motion.length() * 0.5:
			_state = "blocked"
			_blocked_reason = "physical_collision"
			break
		var to_vertex: Vector3 = _points[_segment + 1] - global_position
		to_vertex.y = 0.0
		if to_vertex.length() > POINT_EPS_M or _segment == _points.size() - 2:
			break
	velocity.y = 0.0 if is_on_floor() else vertical_speed
	return achieved_distance


func _braking_speed(remaining_m: float, delta: float, deceleration: float = BRAKE_MPS2) -> float:
	# v*dt + v^2/(2*a) <= distance, so the next physical step leaves braking room.
	var time_term: float = deceleration * delta
	return maxf(0.0, sqrt(time_term * time_term + 2.0 * deceleration * maxf(0.0, remaining_m)) - time_term)


func _current_conflict() -> Dictionary:
	for conflict: Dictionary in _conflicts:
		if _station_m <= float(conflict["exit_s_m"]) + POINT_EPS_M:
			return conflict
	return {}


func _advance_vertex() -> bool:
	var remaining: Vector3 = _points[_segment + 1] - global_position
	remaining.y = 0.0
	if remaining.length() > POINT_EPS_M or _segment == _points.size() - 2:
		return true
	var next_segment: int = _segment + 1
	var next_yaw: float = _heading(_segment_direction(next_segment))
	var rotated_overlap: Dictionary = _sweep_obstacle(global_position, Vector3.ZERO, next_yaw)
	if not rotated_overlap.is_empty():
		_state = "waiting_turn"
		_blocked_reason = "next_segment_orientation_occupied:" + String(rotated_overlap.get("reason", "unknown"))
		return false
	_segment = next_segment
	if _terrain_enabled:_apply_terrain_orientation()
	else:global_rotation.y = next_yaw
	return true


func _record_station() -> void:
	var start: Vector3 = _points[_segment]
	var tangent: Vector3 = _segment_direction(_segment)
	var length_m: float = _arc[_segment + 1] - _arc[_segment]
	var projection: float = clampf((global_position - start).dot(tangent), 0.0, length_m)
	_station_m = _arc[_segment] + projection
	var offset: Vector3 = global_position - (start + tangent * projection)
	offset.y = 0.0
	_max_route_offset_m = maxf(_max_route_offset_m, offset.length())
	if offset.length() > ROUTE_TOLERANCE_M:
		_state = "off_route"
		_blocked_reason = "physical_motion_left_route"


func _segment_direction(index: int) -> Vector3:
	var direction: Vector3 = _points[index + 1] - _points[index]
	direction.y = 0.0
	return direction.normalized()


func _heading(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


func _find_support() -> void:
	_support_exclusions = [get_rid()]
	# These RIDs are supplied by the manager after identifying only W03 support
	# and the two limited N03 road support bodies; never exclude arbitrary world.
	for value: Variant in _static_world.get_meta("vehicle_support_rids", []):
		if value is RID:
			var support_rid: RID = value
			if support_rid.is_valid() and not _support_exclusions.has(support_rid):
				_support_exclusions.append(support_rid)
	if _last_support_rid.is_valid() and not _support_exclusions.has(_last_support_rid):
		_support_exclusions.append(_last_support_rid)
	_floor_name = ""
	_floor_path = ""
	_floor_reason = "no_up_floor_at_feet"
	var ray_length: float=.45 if _terrain_enabled else .2
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * ray_length, global_position - Vector3.UP * ray_length, 17, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	var contact: Vector3 = hit.get("position", Vector3.INF)
	if normal.dot(Vector3.UP) < cos(floor_max_angle) or absf(contact.y - global_position.y) > (.32 if _terrain_enabled else .12):
		_floor_reason = "ray_hit_is_not_support"
		return
	_last_support_rid = hit.get("rid", RID())
	if not _support_exclusions.has(_last_support_rid):
		_support_exclusions.append(_last_support_rid)
	_floor_reason = "up_floor_ray"
	var body: Node = hit.get("collider") as Node
	if is_instance_valid(body):
		_floor_name = String(body.name)
		_floor_path = String(body.get_path())


func _corridor_obstacle(distance_m: float) -> Dictionary:
	if _terrain_enabled:return _terrain_corridor_obstacle(distance_m)
	var cursor: Vector3 = global_position
	var remaining: float = distance_m
	var travelled: float = 0.0
	for index: int in range(_segment, _points.size() - 1):
		var endpoint: Vector3 = _points[index + 1]
		endpoint.y = cursor.y
		var offset: Vector3 = endpoint - cursor
		var motion: Vector3 = offset.limit_length(remaining)
		var obstacle: Dictionary = _sweep_obstacle(cursor, motion, _heading(_segment_direction(index)))
		if not obstacle.is_empty():
			obstacle["distance_m"] = travelled + float(obstacle["distance_m"])
			return obstacle
		if remaining <= offset.length() + POINT_EPS_M:
			return {}
		remaining -= offset.length()
		travelled += offset.length()
		cursor = endpoint
	return {}


func _early_corridor_broadphase(distance_m: float) -> Dictionary:
	_reset_terrain_queries()
	if not _early_terrain_bounds_valid:return {"available":false,"reason":"missing_finite_terrain_visual_bounds"}
	var box: BoxShape3D=body_shape.shape as BoxShape3D
	if box==null:return {"available":false,"reason":"requires_box_shape"}
	# Full local corner radius includes the collider's 0.75m centre offset.
	# Every future terrain pose is an orthonormal rigid rotation, so none of
	# those corners can exceed this radius from the vehicle's feet in any axis.
	var radius: float=0.0
	for x: float in [-box.size.x*.5,box.size.x*.5]:
		for y: float in [-box.size.y*.5,box.size.y*.5]:
			for z: float in [-box.size.z*.5,box.size.z*.5]:radius=maxf(radius,(body_shape.transform*Vector3(x,y,z)).length())
	var cursor: Vector3=global_position;var low: Vector2=Vector2(cursor.x,cursor.z);var high: Vector2=low
	var remaining: float=maxf(0.0,distance_m)
	for index: int in range(_segment,_points.size()-1):
		var offset: Vector3=_points[index+1]-cursor;offset.y=0.0
		var span: float=minf(remaining,offset.length())
		cursor+=_segment_direction(index)*span
		low=low.min(Vector2(cursor.x,cursor.z));high=high.max(Vector2(cursor.x,cursor.z))
		remaining-=span
		if remaining<=POINT_EPS_M:break
	# The exact supporting feetY is terrainY minus a bottom-plane offset
	# bounded by radius. The full box then adds at most another radius. Linear
	# casts stay between endpoint bounds. Include the current feet separately
	# for a physically displaced/airborne start. The 1cm broad-only padding also
	# covers float32 accumulation across the unchanged half-metre substeps; it
	# does not alter any narrow collision margin or actual contact threshold.
	var margin: float=safe_margin+TERRAIN_CLEARANCE_M+.01
	low-=Vector2.ONE*(radius+margin);high+=Vector2.ONE*(radius+margin)
	var minimum_y: float=minf(_early_terrain_bounds.position.y-2.0*radius,global_position.y-radius)-margin
	var maximum_y: float=maxf(_early_terrain_bounds.end.y+2.0*radius,global_position.y+radius)+margin
	var bounds: AABB=AABB(Vector3(low.x,minimum_y,low.y),Vector3(high.x-low.x,maximum_y-minimum_y,high.y-low.y))
	var broad_shape: BoxShape3D=BoxShape3D.new();broad_shape.size=bounds.size
	var query: PhysicsShapeQueryParameters3D=PhysicsShapeQueryParameters3D.new();query.shape=broad_shape;query.transform=Transform3D(Basis.IDENTITY,bounds.get_center());query.collision_mask=collision_mask;query.exclude=_support_exclusions;query.margin=0.0
	_terrain_query_counts.early_broadphase=int(_terrain_query_counts.early_broadphase)+1
	return {"available":true,"empty":get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),"bounds":bounds,"radius_m":radius}


func _terrain_corridor_obstacle(distance_m: float) -> Dictionary:
	var early: Dictionary=_early_corridor_broadphase(distance_m)
	var early_empty: bool=bool(early.get("available",false)) and bool(early.get("empty",false))
	if early_empty and not terrain_verify_early_bounds:
		_early_bounds_empty_returns+=1;_terrain_query_counts.early_empty=int(_terrain_query_counts.early_empty)+1;return {}
	var cursor: Vector3=global_position
	var remaining: float=distance_m
	var travelled: float=0.0
	var pieces: Array[Dictionary]=[]
	var bounds: AABB=AABB();var bounds_valid: bool=false
	var local_bounds: AABB=AABB(-body_shape.shape.size*.5,body_shape.shape.size)
	for index: int in range(_segment,_points.size()-1):
		var endpoint: Vector3=_points[index+1]
		var offset: Vector3=endpoint-cursor;offset.y=0.0
		var span: float=minf(remaining,offset.length())
		var direction: Vector3=_segment_direction(index)
		var yaw: float=_heading(direction)
		var count: int=maxi(1,int(ceil(span/.5)))
		for part: int in range(count):
			var amount: float=minf(.5,maxf(0.0,span-float(part)*.5))
			var start_pose: Transform3D=_terrain_pose(cursor,yaw)
			var end_pose: Transform3D=_terrain_pose(cursor+direction*amount,yaw)
			var motion: Vector3=end_pose.origin-cursor
			pieces.append({"feet":cursor,"motion":motion,"yaw":yaw,"distance_m":travelled})
			# Enclose BOTH endpoints of each original fixed-orientation full-box
			# sweep, including its native safe_margin. Empty union means every
			# narrower query is empty; any hit retains the complete old probes.
			var query_pose: Transform3D=Transform3D(start_pose.basis,cursor+start_pose.basis*body_shape.position)
			var first: AABB=query_pose*local_bounds;query_pose.origin+=motion
			var last: AABB=query_pose*local_bounds
			bounds=first.merge(last) if not bounds_valid else bounds.merge(first).merge(last);bounds_valid=true
			cursor=end_pose.origin;travelled+=amount
		remaining-=span
		if remaining<=POINT_EPS_M:break
	if pieces.is_empty():return {}
	bounds=bounds.grow(safe_margin+.0002)
	if terrain_verify_early_bounds and bool(early.get("available",false)):
		_early_bounds_checks+=1
		var coarse: AABB=early.bounds
		if coarse.encloses(bounds):
			_early_bounds_verified+=1
			if early_empty:
				_early_empty_verified+=1;_early_bounds_empty_returns+=1;_terrain_query_counts.early_empty=int(_terrain_query_counts.early_empty)+1;return {}
		else:
			_early_bounds_violations+=1
			_last_early_bounds_violation={"tick":Engine.get_physics_frames(),"early_empty":early_empty,"radius_m":early.radius_m,"coarse":{"position":_vector(coarse.position),"size":_vector(coarse.size)},"all_original_sweeps":{"position":_vector(bounds.position),"size":_vector(bounds.size)}}
			# A diagnostic violation always falls back to the old complete query;
			# the test can fail without turning a suspect bound into permission.
	var broad_shape: BoxShape3D=BoxShape3D.new();broad_shape.size=bounds.size
	var query: PhysicsShapeQueryParameters3D=PhysicsShapeQueryParameters3D.new();query.shape=broad_shape;query.transform=Transform3D(Basis.IDENTITY,bounds.get_center());query.collision_mask=collision_mask;query.exclude=_support_exclusions;query.margin=0.0
	_terrain_query_counts.broadphase=int(_terrain_query_counts.broadphase)+1
	if get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return {}
	for piece: Dictionary in pieces:
		var obstacle: Dictionary=_sweep_obstacle(piece.feet,piece.motion,float(piece.yaw))
		if not obstacle.is_empty():obstacle["distance_m"]=float(piece.distance_m)+float(obstacle["distance_m"]);return obstacle
	return {}

func _sweep_obstacle(feet: Vector3, motion: Vector3, yaw: float) -> Dictionary:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = body_shape.shape
	var pose: Transform3D=_terrain_pose(feet,yaw) if _terrain_enabled else Transform3D(Basis(Vector3.UP,yaw),feet)
	query.transform = Transform3D(pose.basis, feet + pose.basis*body_shape.position)
	query.collision_mask = collision_mask
	query.exclude = _support_exclusions
	query.margin = safe_margin
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if _terrain_enabled:_terrain_query_counts.narrow_intersections=int(_terrain_query_counts.narrow_intersections)+1
	var contacts: Array[Dictionary] = space.intersect_shape(query, 16)
	if not contacts.is_empty():
		return {"distance_m": 0.0, "reason": _collision_label(contacts)}
	if motion.length_squared() <= 0.000000000001:
		return {}
	query.motion = motion
	if _terrain_enabled:_terrain_query_counts.narrow_sweeps=int(_terrain_query_counts.narrow_sweeps)+1
	var fractions: PackedFloat32Array = space.cast_motion(query)
	if fractions.size() != 2:
		return {"distance_m": 0.0, "reason": "unknown_full_box_sweep"}
	if fractions[0] >= 1.0:
		return {}
	query.transform.origin += motion * minf(1.0, float(fractions[1]) + 0.001 / motion.length())
	query.motion = Vector3.ZERO
	if _terrain_enabled:_terrain_query_counts.narrow_intersections=int(_terrain_query_counts.narrow_intersections)+1
	contacts = space.intersect_shape(query, 16)
	return {"distance_m": motion.length() * float(fractions[0]), "reason": _collision_label(contacts) if not contacts.is_empty() else "swept_full_box_blocked"}


func _collision_label(contacts: Array[Dictionary]) -> String:
	var body: Node = contacts[0].get("collider") as Node
	return "body:" + String(body.name) if is_instance_valid(body) else "unknown_body"


func _at_endpoint() -> bool:
	var offset: Vector3 = global_position - _points[-1]
	offset.y = 0.0
	return _station_m >= _length_m - POINT_EPS_M and offset.length() <= POINT_EPS_M


func get_route_id() -> String:
	return _route_id


func get_station_m() -> float:
	return _station_m


func is_at_end() -> bool:
	return _configured and _at_endpoint()


func can_recycle() -> bool:
	return _configured and _running and _state == "endpoint_wait" and _at_endpoint() and _speed_mps <= SPEED_EPS_MPS and is_on_floor() and absf(velocity.y) <= SPEED_EPS_MPS


func try_recycle(guard: Dictionary) -> bool:
	# Manager is the sole caller. It evaluates actual camera/frustum, 30 m human
	# separation and entry occupancy after this tick's camera step, then grants.
	var tick: int = Engine.get_physics_frames()
	if not can_recycle() or not bool(guard.get("allowed", false)) or int(guard.get("tick", -1)) != tick:
		return false
	_recycle_history.append({"tick": tick, "time_s": _elapsed_s, "from": _vector(global_position), "to": _vector(_points[0]), "guard": _json_safe(guard)})
	global_transform=_terrain_pose(_points[0],_heading(_segment_direction(0))) if _terrain_enabled else Transform3D(Basis(Vector3.UP,_heading(_segment_direction(0))),_points[0])
	_station_m = 0.0
	_segment = 0
	_speed_mps = 0.0
	_command_speed_mps = 0.0
	velocity = Vector3.ZERO
	_cycle_distance_m = 0.0
	_cycle_count += 1
	_last_recycle_tick = tick
	_state = "accelerating"
	_blocked_reason = ""
	_permission = {}
	_obstacle = {}
	_painted_signal_observation.clear()
	_painted_signal_commit.clear()
	_find_support()
	return true


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			return value if is_finite(float(value)) else null
		TYPE_VECTOR3:
			return _vector(value)
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			for key: Variant in value:
				result[str(key)] = _json_safe(value[key])
			return result
		TYPE_ARRAY:
			var result: Array = []
			for item: Variant in value:
				result.append(_json_safe(item))
			return result
	return str(value)


func snapshot() -> Dictionary:
	return {
		"route_id": _route_id, "position": _vector(global_position), "velocity": _vector(velocity),
		"station_m": _station_m, "route_length_m": _length_m, "segment": _segment, "direction": 1,
		"speed_mps": _speed_mps, "command_speed_mps": _command_speed_mps, "motion_parts": _motion_parts, "max_speed_mps": _max_speed_mps, "body_yaw_rad": global_rotation.y,
		"visual_yaw_rad": global_rotation.y, "state": _state if _running else "paused", "running": _running,
		"on_floor": is_on_floor(), "floor_collider": _floor_name, "floor_collider_path": _floor_path, "floor_reason": _floor_reason,
		"at_end": is_at_end(), "can_recycle": can_recycle(), "cycle_count": _cycle_count, "completed_cycles": _cycle_count,
		"end_events": _end_events, "endpoint_history": _endpoint_history.duplicate(true), "recycle_history": _recycle_history.duplicate(true),
		"last_recycle_tick": _last_recycle_tick, "physics_steps": _physics_steps, "elapsed_s": _elapsed_s, "pause_ticks": _pause_ticks,
		"actual_distance_m": _distance_m, "cycle_distance_m": _cycle_distance_m, "max_step_m": _max_step_m, "max_route_offset_m": _max_route_offset_m,
		"blocked_reason": _blocked_reason, "obstacle": _json_safe(_obstacle), "permission": _json_safe(_permission),
		"painted_signal":_json_safe(_painted_signal_observation),"painted_signal_commit":_json_safe(_painted_signal_commit),"painted_signal_events":_json_safe(_painted_signal_events),
		"max_speed_limit_mps": MAX_SPEED_MPS, "crossing_speed_limit_mps": CROSSING_SPEED_MPS, "accel_mps2": ACCEL_MPS2, "decel_mps2": BRAKE_MPS2,
		"reaction_s": REACTION_S, "clearance_m": CLEARANCE_M, "gravity_mps2": GRAVITY_MPS2,
		"layer": collision_layer, "mask": collision_mask, "physics_priority": process_physics_priority,
		"terrain_enabled":_terrain_enabled,"terrain_normal":_vector(_terrain_normal),"terrain_grade":_terrain_grade,
		"terrain_query_tick":_terrain_query_tick,"terrain_queries":_terrain_query_counts.duplicate(true),"terrain_clearance_moves":_terrain_clearance_moves,"terrain_orientation_blocked":_terrain_orientation_blocked,"terrain_clearance_XZ_this_tick_m":_terrain_clearance_distance_this_tick_m,"last_motion_contacts":_last_motion_contacts.duplicate(true),
		"early_bounds":{"diagnostic_enabled":terrain_verify_early_bounds,"available":_early_terrain_bounds_valid,"checks":_early_bounds_checks,"verified":_early_bounds_verified,"verified_empty":_early_empty_verified,"violations":_early_bounds_violations,"empty_returns":_early_bounds_empty_returns,"last_violation":_last_early_bounds_violation.duplicate(true)},
	}
