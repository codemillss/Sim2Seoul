extends CharacterBody3D
## N02: physical, arc-station following of the unchanged N01 polyline.
## Configure before add_child. Position changes only at spawn and move_and_slide.

const SPEED_MPS: float = 1.2
const GRAVITY_MPS2: float = 9.8
const STOP_MARGIN_M: float = 0.1
const REVERSE_CLEARANCE_M: float = 0.6
const CLEAR_HOLD_S: float = 0.3
const BLOCKED_REVERSE_S: float = 2.0
const END_DWELL_S: float = 0.5
const TURN_RATE_RAD_S: float = PI
const POINT_EPS_M: float = 0.0001

@onready var visual: Node3D = $Visual
@onready var capsule: CollisionShape3D = $CollisionShape

var _player: CharacterBody3D
var _route_id: String = ""
var _points: PackedVector3Array = PackedVector3Array()
var _arc: PackedFloat64Array = PackedFloat64Array()
var _length_m: float = 0.0
var _station_m: float = 0.0
var _segment: int = 0
var _direction: int = 1
var _pending_direction: int = -1
var _configured: bool = false
var _running: bool = true
var _state: String = "unconfigured"
var _turn_kind: String = ""
var _blocked_reason: String = ""
var _blocked_s: float = 0.0
var _clear_s: float = 0.0
var _dwell_s: float = 0.0
var _elapsed_s: float = 0.0
var _physics_steps: int = 0
var _support_exclusions: Array[RID] = []
var _floor_name: String = ""
var _floor_path: String = ""
var _distance_m: float = 0.0
var _moves: int = 0
var _max_step_m: float = 0.0
var _turn_count: int = 0
var _reversals: int = 0
var _obstacle_reversals: int = 0
var _end_events: int = 0
var _completed_cycles: int = 0
var _pause_ticks: int = 0
var _cycle_origin_m: float = 0.0
var _cycle_direction: int = 1
var _cycle_end_events: int = 0
var _minimum_player_distance_m: float = INF
var _endpoint_history: Array[Dictionary] = []


func configure(route: Dictionary, world: Node3D, player: CharacterBody3D) -> void:
	_player = player
	_route_id = String(route.get("id", ""))
	_points.clear()
	_arc.clear()
	_arc.append(0.0)
	var xz: Array = route.get("xz", [])
	var ground_y: float = float(route.get("ground_y_m", 0.0))
	for raw_point: Variant in xz:
		var point: Array = raw_point as Array
		_points.append(world.to_global(Vector3(float(point[0]), ground_y, float(point[1]))))
		if _points.size() > 1:
			_arc.append(_arc[-1] + _points[-2].distance_to(_points[-1]))
	_configured = _points.size() >= 2 and _arc[-1] > 0.0
	if not _configured:
		_state = "unconfigured"
		return
	_length_m = _arc[-1]
	_station_m = _length_m * 0.5
	_cycle_origin_m = _station_m
	_segment = _segment_at(_station_m, 1)
	_state = "walking"


func _ready() -> void:
	if not _configured:
		set_physics_process(false)
		return
	global_position = _point_at(_station_m)
	visual.rotation.y = _heading(_segment_direction(_segment, 1))


func set_running(enabled: bool) -> void:
	_running = enabled
	if not enabled:
		velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	_physics_steps += 1
	if not _running:
		_pause_ticks += 1
		velocity = Vector3.ZERO
		return
	_elapsed_s += delta
	_find_support()
	_update_player_distance()
	var motion: Vector3 = _choose_motion(delta)
	var before: Vector3 = global_position
	velocity.x = motion.x / delta
	velocity.z = motion.z / delta
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY_MPS2 * delta
	move_and_slide()
	var achieved: Vector3 = global_position - before
	achieved.y = 0.0
	var step_m: float = achieved.length()
	_max_step_m = maxf(_max_step_m, step_m)
	if step_m > 0.000001:
		_moves += 1
		_distance_m += step_m
	if motion.length_squared() > 0.0 or step_m > 0.000001:
		_record_station()
		if step_m > 0.000001:
			_rotate_visual(_heading(achieved), delta)
		if _state != "off_route" and step_m < motion.length() * 0.5:
			_wait("physical_collision")
	_update_player_distance()


func _choose_motion(delta: float) -> Vector3:
	if _state == "off_route":
		return Vector3.ZERO
	_advance_vertex()
	if _state == "dwell" or _state == "endpoint_wait":
		_dwell_s += delta
		if _dwell_s < END_DWELL_S:
			return Vector3.ZERO
		var end_block: String = _corridor_block(REVERSE_CLEARANCE_M, -_direction, true)
		if not end_block.is_empty():
			_state = "endpoint_wait"
			_blocked_reason = end_block
			_clear_s = 0.0
			return Vector3.ZERO
		if _state == "endpoint_wait":
			_clear_s += delta
			if _clear_s < CLEAR_HOLD_S:
				return Vector3.ZERO
		_begin_turn("endpoint")
	if _state == "turning":
		var turn_block: String = _corridor_block(REVERSE_CLEARANCE_M, _pending_direction, true)
		if not turn_block.is_empty():
			if _turn_kind == "endpoint":
				_state = "endpoint_wait"
				_blocked_reason = turn_block
				_clear_s = 0.0
			else:
				_wait(turn_block)
			return Vector3.ZERO
		var target_yaw: float = _heading(_segment_direction(_segment_at(_station_m, _pending_direction), _pending_direction))
		_rotate_visual(target_yaw, delta)
		if absf(wrapf(target_yaw - visual.rotation.y, -PI, PI)) <= 0.0001:
			_direction = _pending_direction
			_segment = _segment_at(_station_m, _direction)
			_turn_count += 1
			_reversals += 1
			if _turn_kind == "blocked":
				_obstacle_reversals += 1
				_cycle_origin_m = _station_m
				_cycle_direction = _direction
				_cycle_end_events = 0
			_state = "walking"
			_blocked_reason = ""
			_blocked_s = 0.0
			_clear_s = 0.0
		return Vector3.ZERO
	var block: String = _corridor_block(SPEED_MPS * delta + STOP_MARGIN_M, _direction)
	if not block.is_empty():
		_wait(block)
		_blocked_s += delta
		if _blocked_s >= BLOCKED_REVERSE_S and _corridor_block(REVERSE_CLEARANCE_M, -_direction, true).is_empty():
			_begin_turn("blocked")
		return Vector3.ZERO
	if _state == "waiting":
		_clear_s += delta
		if _clear_s < CLEAR_HOLD_S:
			return Vector3.ZERO
		_state = "walking"
		_blocked_reason = ""
		_blocked_s = 0.0
		_clear_s = 0.0
	# Aim one physical step ahead on this segment. A distant endpoint target
	# lets tiny floor-contact offsets accumulate; this steers them back through
	# ordinary bounded motion without changing position or cutting a corner.
	var next_station: float = clampf(_station_m + _direction * SPEED_MPS * delta, _arc[_segment], _arc[_segment + 1])
	var target: Vector3 = _points[_segment] + _segment_direction(_segment, 1) * (next_station - _arc[_segment])
	var remaining: Vector3 = target - global_position
	remaining.y = 0.0
	return remaining.limit_length(SPEED_MPS * delta)


func _wait(reason: String) -> void:
	if _state != "waiting":
		_blocked_s = 0.0
	_state = "waiting"
	_blocked_reason = reason
	_clear_s = 0.0


func _begin_turn(kind: String) -> void:
	_state = "turning"
	_turn_kind = kind
	_pending_direction = -_direction
	_blocked_reason = ""
	_clear_s = 0.0


func _advance_vertex() -> void:
	if _state != "walking" and _state != "waiting":
		return
	var target_index: int = _segment + 1 if _direction > 0 else _segment
	var to_target: Vector3 = _points[target_index] - global_position
	to_target.y = 0.0
	if to_target.length() > POINT_EPS_M:
		return
	if (_direction > 0 and target_index == _points.size() - 1) or (_direction < 0 and target_index == 0):
		_state = "dwell"
		_dwell_s = 0.0
		_clear_s = 0.0
		_blocked_reason = ""
		_end_events += 1
		_cycle_end_events += 1
		_endpoint_history.append({"time_s": _elapsed_s, "endpoint": target_index, "station_m": _station_m, "position": _vector(global_position)})
	else:
		_segment += _direction


func _record_station() -> void:
	var old_station: float = _station_m
	var start: Vector3 = _points[_segment]
	var tangent: Vector3 = _segment_direction(_segment, 1)
	var segment_length: float = _arc[_segment + 1] - _arc[_segment]
	var achieved_projection: float = clampf((global_position - start).dot(tangent), 0.0, segment_length)
	_station_m = _arc[_segment] + achieved_projection
	var line_point: Vector3 = start + tangent * achieved_projection
	var offset: Vector3 = global_position - line_point
	offset.y = 0.0
	if offset.length() > 0.003:
		_state = "off_route"
		_blocked_reason = "physical_motion_left_route"
	if _cycle_end_events >= 2 and _direction == _cycle_direction:
		var crossed_origin: bool = old_station < _cycle_origin_m and _station_m >= _cycle_origin_m
		if _direction < 0:
			crossed_origin = old_station > _cycle_origin_m and _station_m <= _cycle_origin_m
		if crossed_origin:
			_completed_cycles += 1
			_cycle_end_events = 0


func _segment_at(station: float, direction: int) -> int:
	if direction > 0:
		for index: int in range(_points.size() - 1):
			if station < _arc[index + 1] - POINT_EPS_M:
				return index
		return _points.size() - 2
	for index: int in range(_points.size() - 2, -1, -1):
		if station > _arc[index] + POINT_EPS_M:
			return index
	return 0


func _point_at(station: float) -> Vector3:
	var index: int = _segment_at(station, 1)
	var fraction: float = (station - _arc[index]) / (_arc[index + 1] - _arc[index])
	return _points[index].lerp(_points[index + 1], clampf(fraction, 0.0, 1.0))


func _segment_direction(index: int, direction: int) -> Vector3:
	var tangent: Vector3 = _points[index + 1] - _points[index]
	tangent.y = 0.0
	return tangent.normalized() * float(direction)


func _heading(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


func _rotate_visual(target_yaw: float, delta: float) -> void:
	var angle: float = wrapf(target_yaw - visual.rotation.y, -PI, PI)
	visual.rotation.y = wrapf(visual.rotation.y + clampf(angle, -TURN_RATE_RAD_S * delta, TURN_RATE_RAD_S * delta), -PI, PI)


func _find_support() -> void:
	_support_exclusions = [get_rid()]
	_floor_name = ""
	_floor_path = ""
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.2, global_position - Vector3.UP * 0.2, 1, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	var contact: Vector3 = hit.get("position", Vector3.INF)
	if normal.dot(Vector3.UP) < cos(floor_max_angle) or absf(contact.y - global_position.y) > 0.12:
		return
	_support_exclusions.append(hit.get("rid", RID()))
	var body: Node = hit.get("collider") as Node
	if is_instance_valid(body):
		_floor_name = String(body.name)
		_floor_path = String(body.get_path())


func _corridor_block(distance_m: float, direction: int, require_full_distance: bool = false) -> String:
	# Sweep every intervening segment, including N01's small rounded vertices.
	var cursor: Vector3 = global_position
	var remaining: float = distance_m
	var index: int = _segment_at(_station_m, direction)
	for _part: int in range(_points.size() + 1):
		var endpoint: Vector3 = _points[index + 1] if direction > 0 else _points[index]
		endpoint.y = cursor.y
		var offset: Vector3 = endpoint - cursor
		var length_m: float = offset.length()
		var motion: Vector3 = offset.limit_length(remaining)
		var blocked: String = _sweep_block(cursor, motion)
		if not blocked.is_empty():
			return blocked
		if remaining <= length_m + POINT_EPS_M:
			return ""
		remaining -= length_m
		cursor = endpoint
		if (direction > 0 and index == _points.size() - 2) or (direction < 0 and index == 0):
			return "insufficient_reverse_route" if require_full_distance else ""
		index += direction
	return "unresolved_swept_corridor"


func _sweep_block(feet: Vector3, motion: Vector3) -> String:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule.shape
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * 0.85)
	query.collision_mask = collision_mask
	query.exclude = _support_exclusions
	query.margin = safe_margin
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var overlap: Array[Dictionary] = space.intersect_shape(query, 16)
	if not overlap.is_empty():
		return _collision_label(overlap)
	if motion.length_squared() <= 0.000000000001:
		return ""
	query.motion = motion
	var fractions: PackedFloat32Array = space.cast_motion(query)
	if fractions.size() != 2:
		return "unknown_sweep_result"
	if fractions[0] >= 1.0:
		return ""
	query.transform.origin += motion * minf(1.0, float(fractions[1]) + 0.001 / motion.length())
	query.motion = Vector3.ZERO
	var contacts: Array[Dictionary] = space.intersect_shape(query, 16)
	return _collision_label(contacts) if not contacts.is_empty() else "swept_capsule_blocked"


func _collision_label(contacts: Array[Dictionary]) -> String:
	var body: Node = contacts[0].get("collider") as Node
	return "body:" + String(body.name) if is_instance_valid(body) else "unknown_body"


func _update_player_distance() -> void:
	if not is_instance_valid(_player):
		return
	var separation: Vector3 = global_position - _player.global_position
	separation.y = 0.0
	_minimum_player_distance_m = minf(_minimum_player_distance_m, separation.length())


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func snapshot() -> Dictionary:
	return {
		"physics_steps": _physics_steps, "route_id": _route_id, "position": _vector(global_position), "velocity": _vector(velocity),
		"on_floor": is_on_floor(), "floor_collider": _floor_name, "floor_collider_path": _floor_path,
		"state": _state if _running else "paused", "running": _running,
		"station_m": _station_m, "route_length_m": _length_m, "segment": _segment, "direction": _direction,
		"visual_yaw_rad": visual.rotation.y, "turn_count": _turn_count, "reversals": _reversals,
		"obstacle_reversals": _obstacle_reversals, "end_events": _end_events,
		"endpoint_history": _endpoint_history.duplicate(true), "completed_cycles": _completed_cycles,
		"blocked_reason": _blocked_reason, "blocked_s": _blocked_s, "clear_s": _clear_s,
		"actual_distance_m": _distance_m, "moves": _moves, "max_step_m": _max_step_m,
		"pause_ticks": _pause_ticks,
		"minimum_player_distance_m": _minimum_player_distance_m if is_finite(_minimum_player_distance_m) else null,
		"speed_mps": SPEED_MPS, "gravity_mps2": GRAVITY_MPS2,
		"layer": collision_layer, "mask": collision_mask,
	}
