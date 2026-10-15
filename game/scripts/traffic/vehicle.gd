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
var _motion_cap_m: float = INF


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
	_find_support()
	# The manager refreshes lazily once per physics frame, after priority-0 humans.
	_permission = _manager.call("permission", self) as Dictionary
	var step_budget: float = _choose_step_budget(delta)
	var step_m: float = _move_on_polyline(step_budget, delta)
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


func _move_on_polyline(step_budget: float, delta: float) -> float:
	# Consume this tick's distance along every encountered original segment.
	# Each physical part uses part/delta, so no diagonal chord or waypoint teleport
	# is introduced, and a short last fragment does not reset the driving speed.
	var remaining_budget: float = step_budget
	var achieved_distance: float = 0.0
	_motion_parts = 0
	var first_part: bool = true
	var vertical_speed: float = 0.0 if is_on_floor() else velocity.y - GRAVITY_MPS2 * delta
	for _part: int in range(_points.size() + 1):
		if not first_part and (remaining_budget <= 0.000001 or not _advance_vertex()):
			break
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
		move_and_slide()
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
	global_rotation.y = next_yaw
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
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.2, global_position - Vector3.UP * 0.2, 17, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	var contact: Vector3 = hit.get("position", Vector3.INF)
	if normal.dot(Vector3.UP) < cos(floor_max_angle) or absf(contact.y - global_position.y) > 0.12:
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


func _sweep_obstacle(feet: Vector3, motion: Vector3, yaw: float) -> Dictionary:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = body_shape.shape
	query.transform = Transform3D(Basis(Vector3.UP, yaw), feet + Vector3.UP * 0.75)
	query.collision_mask = collision_mask
	query.exclude = _support_exclusions
	query.margin = safe_margin
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var contacts: Array[Dictionary] = space.intersect_shape(query, 16)
	if not contacts.is_empty():
		return {"distance_m": 0.0, "reason": _collision_label(contacts)}
	if motion.length_squared() <= 0.000000000001:
		return {}
	query.motion = motion
	var fractions: PackedFloat32Array = space.cast_motion(query)
	if fractions.size() != 2:
		return {"distance_m": 0.0, "reason": "unknown_full_box_sweep"}
	if fractions[0] >= 1.0:
		return {}
	query.transform.origin += motion * minf(1.0, float(fractions[1]) + 0.001 / motion.length())
	query.motion = Vector3.ZERO
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
	global_position = _points[0]
	global_rotation.y = _heading(_segment_direction(0))
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
		"max_speed_limit_mps": MAX_SPEED_MPS, "crossing_speed_limit_mps": CROSSING_SPEED_MPS, "accel_mps2": ACCEL_MPS2, "decel_mps2": BRAKE_MPS2,
		"reaction_s": REACTION_S, "clearance_m": CLEARANCE_M, "gravity_mps2": GRAVITY_MPS2,
		"layer": collision_layer, "mask": collision_mask, "physics_priority": process_physics_priority,
	}
